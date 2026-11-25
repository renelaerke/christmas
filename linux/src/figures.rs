//! What moves across screens in global coordinates: Santa with his sleigh, the sparks and stars he leaves, and
//! the snow plow. Each screen draws the part that is on it (`layer/santa.rs`, `layer/plow.rs`). Corresponds to the
//! Santa, sparks and `PlowRun` parts of `src/Controller.cs`.

use crate::rng::Rng;
use crate::x11::Rect;

pub struct Spark {
    pub x: f32,
    pub y: f32,
    pub vx: f32,
    pub vy: f32,
    pub life: f32,
    pub max: f32,
    pub size: f32,
    pub gold: bool,
    /// A falling star (star shower, phase 4) instead of a round spark.
    pub star: bool,
}

/// A spark of New Year's rockets: of a burst (in the burst's colour, an index into the confetti's colours), of a
/// rocket's tail (no colour: gold), or one dot of a number written in sparks (`holds`: it stays fully lit and only
/// fades at the very end). It is slowed by the air (`drag`, per second) and sinks with its own weight.
/// (The sweets thrown from the Rhineland carnival's wagon are these too: coloured, heavy, and not slowed.)
pub struct Ember {
    pub x: f32,
    pub y: f32,
    vx: f32,
    vy: f32,
    pub life: f32,
    pub max: f32,
    pub size: f32,
    pub colour: Option<usize>,
    pub holds: bool,
    drag: f32,
    gravity: f32,
}

/// One of New Year's rockets on its way up, in global coordinates: it bursts when it reaches `burst_y`.
pub struct Rocket {
    pub x: f32,
    pub y: f32,
    vy: f32,
    burst_y: f32,
    pub scale: f32,
    sway: f32,
    trail: f32,
    colour: usize,
}

/// How many colours a burst can have (the confetti's, `layer/nytaar.rs`).
const BURST_COLOURS: i32 = 7;

/// The digits, written as dots on a grid of five by seven.
const DIGIT_DOTS: [[&str; 7]; 10] = [
    ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
];

pub struct Santa {
    pub x: f32,
    y0: f32,
    /// 1 to the right, -1 to the left.
    pub dir: f32,
    speed: f32,
    /// Seconds into the trip; drives the bobbing, the galloping and Rudolph's nose.
    pub phase: f32,
    /// The scale of the screen he was launched on.
    pub scale: f32,
    min_x: f32,
    max_x: f32,
}

impl Santa {
    pub fn y(&self) -> f32 {
        self.y0 + (self.phase * 0.9).sin() * 40.0 * self.scale
    }
}

/// One plow run, driving continuously across side-by-side screens. Each screen scrapes its own snow while the
/// truck is on it and draws the truck where it is.
pub struct PlowRun {
    pub active: bool,
    pub gx: f32,
    pub dir: f32,
    next_dir: f32,
    pub wheel: f32,
    /// Snow scraped up on this run; the pile in front of the blade grows with it.
    pub pushed: f32,
    cooldown: f32,
    min_x: f32,
    max_x: f32,
    /// Indexes of the screens in this run's row.
    pub members: Vec<usize>,
}

pub const PLOW_SPEED: f32 = 170.0;
pub const PLOW_SCALE: f32 = 1.15;
/// The Day of the Dead's donkey cart walks at a donkey's pace (a share of the plow's speed).
pub const CART_PACE: f32 = 0.45;
/// How fast the donkey's legs swing against the cart's wheel (radians of leg swing per radian of wheel turn).
pub const DONKEY_STRIDE: f32 = 1.6;

/// Seconds per step cycle of the donkey's legs (each leg lands once), worked out from how the drawing moves them:
/// the legs swing with sin(wheel x DONKEY_STRIDE), and the wheel turns PLOW_SPEED x CART_PACE / (10 x PLOW_SCALE)
/// radians a second. The hooves' sound is timed from it (`sound::donkey_cart`).
pub fn donkey_step_cycle() -> f64 {
    (std::f32::consts::TAU / DONKEY_STRIDE / (PLOW_SPEED * CART_PACE / (10.0 * PLOW_SCALE))) as f64
}

/// A screen as the figures see it.
pub struct ScreenInfo {
    pub rect: Rect,
    /// The screen's figure scale (`Layer::s`).
    pub s: f32,
    pub primary: bool,
    /// Average height of its snow pile.
    pub heap_average: f32,
}

pub struct Figures {
    pub santa: Option<Santa>,
    santa_next: f32,
    spark_acc: f32,
    pub sparks: Vec<Spark>,
    pub plow: PlowRun,
    plow_at: Option<f64>,
    rng: Rng,
    /// This trip's speed against the normal (0.9..1.1); his tune plays at the same rate.
    pub santa_pace: f32,
    /// A new trip started since the last call to `take_new_trip` (the sound picks a tune for it).
    new_trip: bool,
    /// The autumn theme (set by the controller): geese fly in Santa's place, at varying distance and with no
    /// trail of sparks.
    pub autumn: bool,
    /// De dødes dag (set by the controller): monarch butterflies fly in Santa's place, also at varying distance
    /// and with no sparks, and the plow is a donkey cart at a donkey's pace.
    pub muertos: bool,
    /// Halloween (set by the controller): a witch on her broom flies in Santa's place, and the plow is one of two
    /// each run (`ghosts_blow`).
    pub halloween: bool,
    /// Halloween's plow this run: three ghosts that blow the leaves away (true), or a witch who sweeps them up
    /// (false). Random, but drawn two at a time (one of each, in random order: `plow_forms`), so over time each
    /// comes exactly half the times. `JULE_HALLOWEEN_PLOV=heks` or `=spoegelser` fixes it for tests.
    pub ghosts_blow: bool,
    plow_forms: Vec<bool>,
    /// How near this trip passes (0.5 far .. 1.2 near; 1 at Christmas): far geese call more quietly.
    pub flyer_depth: f32,
    /// New Year (set by the controller): the flyer in Santa's place is a volley of rockets. Each rises from the
    /// bottom of a screen with a tail of sparks and bursts in a band across the top into one soft bloom of
    /// coloured sparks, which fades over a second or two (never a flash, and nothing below the top band). The
    /// volley keeps Santa's schedule and his switch, and counts as "Santa is flying" for the frame rate and the
    /// tune: while it lasts `santa` is set (standing still in the middle), but no figure is drawn for it.
    pub nytaar: bool,
    pub rockets: Vec<Rocket>,
    pub embers: Vec<Ember>,
    /// How long this volley lasts, the time to its next rocket, and the average time between two rockets on one
    /// screen.
    volley_length: f32,
    volley_next: f32,
    volley_gap: f32,
    /// Carnival (set by the controller): nothing flies. In Santa's place a truck with a band on it drives along
    /// the ground at a walking pace (each screen sets it down on its own pile, `layer/santa.rs`), and the plow is
    /// a group of street sweepers at the donkey cart's pace. The two share the ground and are never out together:
    /// the truck does not start while the sweepers are out, and the sweepers wait until the truck has gone by.
    pub karneval: bool,
    /// The Rhineland's carnival (set by the controller, with `karneval`): sweets are thrown from the wagon.
    pub rhein: bool,
    kamelle_acc: f32,
}

/// The screen directly to the left (dir < 0) or right (dir > 0) of screen `i`: edge to edge and overlapping
/// vertically.
pub fn neighbor(rects: &[Rect], i: usize, dir: f32) -> Option<usize> {
    let b = rects[i];
    rects.iter().enumerate().position(|(j, o)| {
        let touches = if dir > 0.0 { (o.x - b.right()).abs() < 2 } else { (o.right() - b.x).abs() < 2 };
        j != i && touches && o.y < b.bottom() && o.bottom() > b.y
    })
}

impl Figures {
    pub fn new(seed: u64) -> Figures {
        Figures {
            santa: None,
            santa_next: 5.0,
            spark_acc: 0.0,
            sparks: Vec::new(),
            plow: PlowRun {
                active: false,
                gx: 0.0,
                dir: 1.0,
                next_dir: 1.0,
                wheel: 0.0,
                pushed: 0.0,
                cooldown: 20.0,
                min_x: 0.0,
                max_x: 0.0,
                members: Vec::new(),
            },
            plow_at: None,
            rng: Rng::new(seed),
            santa_pace: 1.0,
            new_trip: false,
            autumn: false,
            muertos: false,
            halloween: false,
            ghosts_blow: false,
            plow_forms: Vec::new(),
            flyer_depth: 1.0,
            nytaar: false,
            rockets: Vec::new(),
            embers: Vec::new(),
            volley_length: 0.0,
            volley_next: 0.0,
            volley_gap: 0.85,
            karneval: false,
            rhein: false,
            kamelle_acc: 0.0,
        }
    }

    /// True while something fast is on its way (the frame rate is boosted).
    pub fn busy(&self) -> bool {
        self.santa.is_some() || !self.sparks.is_empty() || !self.rockets.is_empty() || !self.embers.is_empty() || self.plow.active
    }

    /// The screens were rebuilt: whatever was on its way is gone with them.
    pub fn screens_changed(&mut self) {
        self.santa = None;
        self.rockets.clear();
        self.plow.active = false;
        self.plow.members.clear();
    }

    /// Ends Santa's trip and the plow run at once, as if they had arrived (`FinishRuns()` on Windows). Phase 4
    /// also stops their sound here.
    pub fn finish_runs(&mut self) {
        if self.santa.is_some() || self.plow.active {
            crate::log::debug(&format!("finish runs: santa={} plow={}", self.santa.is_some(), self.plow.active));
        }
        if self.santa.take().is_some() {
            self.santa_next = 60.0 + self.rng.f() * 120.0;
        }
        self.sparks.clear();
        self.rockets.clear();
        self.embers.clear();
        if self.plow.active {
            self.plow.active = false;
            self.plow.cooldown = 30.0;
        }
    }

    // ------------------------------------------------------------------ Santa
    pub fn launch_santa(&mut self, screens: &[ScreenInfo]) {
        if self.santa.is_some() || screens.is_empty() {
            return;
        }
        // (carnival's truck and its street sweepers share the ground: never both at once)
        if self.karneval && self.plow.active {
            return;
        }
        // (New Year's flyer is a volley of rockets)
        if self.nytaar {
            let seconds = 12.0 + self.rng.f() * 6.0;
            self.launch_volley(screens, seconds, 0.85);
            return;
        }
        let target = &screens[self.rng.range(0, screens.len() as i32) as usize];
        let b = target.rect;
        // the geese pass at very different distances (as `flyerDepth` on Windows)
        self.flyer_depth = if self.autumn || self.muertos || self.halloween { 0.5 + self.rng.f() * 0.7 } else { 1.0 };
        let scale = target.s * self.flyer_depth;
        let y0 = b.y as f32 + b.h as f32 * (0.12 + self.rng.f() * 0.25);
        // fly over every screen at the same height
        let (mut min_x, mut max_x) = (b.x as f32, b.right() as f32);
        for o in screens {
            if y0 >= o.rect.y as f32 && y0 < o.rect.bottom() as f32 {
                min_x = min_x.min(o.rect.x as f32);
                max_x = max_x.max(o.rect.right() as f32);
            }
        }
        let dir = if self.rng.f() < 0.5 { 1.0 } else { -1.0 };
        let x = if dir > 0.0 { min_x - 420.0 * scale } else { max_x + 420.0 * scale };
        // ±10% speed per trip (phase 4 plays the tune at the same pace)
        let pace = 0.9 + self.rng.f() * 0.2;
        let wide = if max_x - min_x > b.w as f32 * 1.5 { 1.6 } else { 1.0 };
        let (mut x, mut speed, mut pace) = (x, 230.0 * pace * scale * wide, pace);
        if self.karneval {
            // the band truck: on the ground, at the ordinary size and at a walking pace; the music keeps its own
            // tempo, which is the beat the walkers step to
            x = if dir > 0.0 { min_x - 260.0 * scale } else { max_x + 260.0 * scale };
            speed = 70.0 * target.s;
            pace = 1.0;
        }
        self.santa_pace = pace;
        crate::log::debug(&format!("santa: dir {dir} from {min_x} to {max_x} at y {y0:.0}"));
        self.santa = Some(Santa { x, y0, dir, speed, phase: 0.0, scale, min_x, max_x });
        self.new_trip = true;
    }

    fn update_santa(&mut self, dt: f32, screens: &[ScreenInfo], enabled: bool) {
        let Some(s) = self.santa.as_mut() else {
            if enabled {
                self.santa_next -= dt;
                if self.santa_next <= 0.0 {
                    self.launch_santa(screens);
                    self.santa_next = 60.0 + self.rng.f() * 120.0;
                }
            }
            return;
        };
        if self.nytaar {
            // the volley: rockets go up one after the other, anywhere on any screen
            s.phase += dt;
            if s.phase < self.volley_length {
                self.volley_next -= dt;
                while self.volley_next <= 0.0 && !screens.is_empty() {
                    let r = &mut self.rng;
                    self.volley_next += self.volley_gap * (0.45 + r.f() * 1.1) / screens.len() as f32;
                    let o = &screens[r.range(0, screens.len() as i32) as usize];
                    let b = o.rect;
                    let y = b.bottom() as f32 - 4.0 * o.s;
                    let burst_y = b.y as f32 + b.h as f32 * (0.10 + r.f() * 0.22);
                    self.rockets.push(Rocket {
                        x: b.x as f32 + b.w as f32 * (0.07 + r.f() * 0.86),
                        y,
                        vy: -(y - burst_y) / (0.9 + r.f() * 0.45),
                        burst_y,
                        scale: o.s,
                        sway: r.f() * std::f32::consts::TAU,
                        trail: 0.0,
                        colour: r.range(0, BURST_COLOURS) as usize,
                    });
                }
            } else if self.rockets.is_empty() && s.phase > self.volley_length + 2.5 {
                self.santa = None;
                self.santa_next = 60.0 + self.rng.f() * 120.0;
            }
            return;
        }
        s.x += s.dir * s.speed * dt;
        s.phase += dt;
        // (Santa leaves a trail of sparks; the geese, the butterflies, the witch and carnival's truck do not)
        if !self.autumn && !self.muertos && !self.halloween && !self.karneval {
            self.spark_acc += dt * 45.0;
        }
        // The Rhineland's wagon: sweets (Kamelle) are thrown from it in handfuls, up and out to both sides
        if self.rhein {
            self.kamelle_acc += dt * 7.0;
            let bottom = screens
                .iter()
                .find(|o| s.x >= o.rect.x as f32 && s.x < o.rect.right() as f32)
                .map(|o| o.rect.bottom() as f32);
            while self.kamelle_acc >= 1.0 {
                self.kamelle_acc -= 1.0;
                let Some(bottom) = bottom else { continue };
                let (r, k) = (&mut self.rng, s.scale);
                let life = 1.5 + r.f() * 0.5;
                self.embers.push(Ember {
                    x: s.x + (r.f() - 0.5) * 120.0 * k,
                    y: bottom - (70.0 + r.f() * 20.0) * k,
                    vx: (r.f() - 0.5) * 220.0 * k,
                    vy: -(150.0 + r.f() * 130.0) * k,
                    life,
                    max: life,
                    size: (2.6 + r.f() * 1.2) * k,
                    colour: Some(r.range(0, BURST_COLOURS) as usize),
                    holds: false,
                    drag: 0.0,
                    gravity: 300.0 * k,
                });
            }
        }
        let r = &mut self.rng;
        while self.spark_acc >= 1.0 {
            self.spark_acc -= 1.0;
            let life = 0.8 + r.f() * 1.4;
            self.sparks.push(Spark {
                x: s.x - s.dir * 90.0 * s.scale + (r.f() - 0.5) * 10.0 * s.scale,
                y: s.y() + (r.f() - 0.3) * 20.0 * s.scale,
                vx: -s.dir * (10.0 + r.f() * 30.0) * s.scale,
                vy: (r.f() - 0.5) * 20.0 * s.scale,
                life,
                max: life,
                size: (1.5 + r.f() * 3.0) * s.scale,
                gold: r.f() < 0.6,
                star: false,
            });
        }
        // (the truck starts and ends nearer the screens than the flyers do: it is slow)
        let reach = s.scale * if self.karneval { 260.0 } else { 450.0 };
        if (s.dir > 0.0 && s.x > s.max_x + reach) || (s.dir < 0.0 && s.x < s.min_x - reach) {
            self.santa = None;
            self.santa_next = 60.0 + self.rng.f() * 120.0;
        }
    }

    fn update_sparks(&mut self, dt: f32) {
        let gravity = 12.0 * self.santa.as_ref().map_or(1.0, |s| s.scale);
        self.sparks.retain_mut(|sp| {
            sp.life -= dt;
            if sp.life <= 0.0 {
                return false;
            }
            sp.x += sp.vx * dt;
            sp.y += sp.vy * dt;
            sp.vy += gravity * dt;
            true
        });
    }

    // ------------------------------------------------------------------ New Year's rockets
    /// Starts a volley over every screen, lasting `seconds`; `gap` is the average time between two rockets on one
    /// screen. One that is already going is replaced (midnight's big volley takes over from an ordinary one).
    pub fn launch_volley(&mut self, screens: &[ScreenInfo], seconds: f32, gap: f32) {
        let Some(first) = screens.first() else { return };
        let min_x = screens.iter().map(|s| s.rect.x as f32).fold(f32::MAX, f32::min);
        let max_x = screens.iter().map(|s| s.rect.right() as f32).fold(f32::MIN, f32::max);
        self.volley_length = seconds;
        self.volley_gap = gap;
        self.volley_next = 0.3;
        self.flyer_depth = 1.0;
        self.santa_pace = 0.95 + self.rng.f() * 0.1;
        self.santa = Some(Santa {
            x: (min_x + max_x) / 2.0,
            y0: first.rect.y as f32 + first.rect.h as f32 * 0.2,
            dir: 1.0,
            speed: 0.0,
            phase: 0.0,
            scale: first.s,
            min_x,
            max_x,
        });
        self.new_trip = true;
        crate::log::debug(&format!("volley: {seconds:.0} s over {} screen(s)", screens.len()));
    }

    /// The rockets rise, each leaving a short tail of gold sparks, and burst where they were aimed: a round bloom
    /// of sparks in the rocket's colour. Most are thrown out at nearly the same speed and make the shell; the rest
    /// fill it, and a few are silver. The sparks are slowed by the air and sink a little as they fade.
    fn update_rockets(&mut self, dt: f32) {
        let mut i = 0;
        while i < self.rockets.len() {
            let r = &mut self.rockets[i];
            r.y += r.vy * dt;
            r.x += (r.sway + r.y * 0.012).sin() * 14.0 * r.scale * dt;
            r.trail += dt * 48.0;
            let (x, y, scale, colour, arrived) = (r.x, r.y, r.scale, r.colour, r.y <= r.burst_y);
            while self.rockets[i].trail >= 1.0 {
                self.rockets[i].trail -= 1.0;
                let g = &mut self.rng;
                let life = 0.3 + g.f() * 0.35;
                self.embers.push(Ember {
                    x: x + (g.f() - 0.5) * 3.0 * scale,
                    y: y + g.f() * 8.0 * scale,
                    vx: (g.f() - 0.5) * 16.0 * scale,
                    vy: (20.0 + g.f() * 30.0) * scale,
                    life,
                    max: life,
                    size: (1.6 + g.f() * 1.6) * scale,
                    colour: None,
                    holds: false,
                    drag: 0.0,
                    gravity: 60.0 * scale,
                });
            }
            if !arrived {
                i += 1;
                continue;
            }
            self.rockets.remove(i);
            let n = 64;
            for k in 0..n {
                let g = &mut self.rng;
                let a = std::f32::consts::TAU * (k as f32 + g.f()) / n as f32;
                let shell = k % 3 != 0;
                let reach = if shell { 0.86 + g.f() * 0.2 } else { 0.25 + g.f() * 0.55 };
                let v = 195.0 * reach * scale;
                let life = (if shell { 1.35 } else { 1.0 }) + g.f() * 0.85;
                let size = (if shell { 3.4 + g.f() * 2.4 } else { 2.4 + g.f() * 1.6 }) * scale;
                self.embers.push(Ember {
                    x,
                    y,
                    vx: a.cos() * v,
                    vy: a.sin() * v,
                    life,
                    max: life,
                    size,
                    colour: Some(if k % 8 == 4 { 1 } else { colour }),
                    holds: false,
                    drag: 1.9,
                    gravity: 30.0 * scale,
                });
            }
        }
        self.embers.retain_mut(|e| {
            e.life -= dt;
            if e.life <= 0.0 {
                return false;
            }
            e.x += e.vx * dt;
            e.y += e.vy * dt;
            if e.drag > 0.0 {
                let k = (-e.drag * dt).exp();
                e.vx *= k;
                e.vy *= k;
            }
            e.vy += e.gravity * dt;
            true
        });
    }

    /// Writes a number in sparks, centred on (x, y) in global coordinates and `height` tall, on a screen of scale
    /// `scale`. The sparks stay lit for `life` seconds, hardly moving (a number that drifts apart cannot be read),
    /// and go out at the end.
    pub fn write_in_sparks(&mut self, number: i32, (x, y): (f32, f32), height: f32, life: f32, scale: f32) {
        let digits: Vec<usize> = number.to_string().bytes().filter(u8::is_ascii_digit).map(|b| (b - b'0') as usize).collect();
        let pitch = height / 7.0;
        let (wide, gap) = (5.0 * pitch, pitch * 1.7);
        let total = digits.len() as f32 * wide + digits.len().saturating_sub(1) as f32 * gap;
        for (i, d) in digits.iter().enumerate() {
            let x0 = x - total / 2.0 + i as f32 * (wide + gap) + pitch / 2.0;
            for (row, line) in DIGIT_DOTS[*d].iter().enumerate() {
                for (col, ch) in line.bytes().enumerate() {
                    if ch != b'1' {
                        continue;
                    }
                    let g = &mut self.rng;
                    let lasts = life * (0.85 + g.f() * 0.15);
                    self.embers.push(Ember {
                        x: x0 + col as f32 * pitch,
                        y: y - height / 2.0 + (row as f32 + 0.5) * pitch,
                        vx: (g.f() - 0.5) * 1.6 * scale,
                        vy: (g.f() - 0.5) * 1.6 * scale,
                        life: lasts,
                        max: lasts,
                        size: pitch * 0.42,
                        colour: Some(0),
                        holds: true,
                        drag: 0.0,
                        gravity: 1.5 * scale,
                    });
                }
            }
        }
    }

    // ------------------------------------------------------------------ snow plow
    /// Sends the plow out now (`--plow`), starting from the primary screen's row of screens.
    pub fn send_plow(&mut self, screens: &[ScreenInfo]) {
        if let Some(i) = screens.iter().position(|s| s.primary).or(if screens.is_empty() { None } else { Some(0) }) {
            self.start_plow(screens, i);
        }
    }

    /// Schedules a plow run `seconds` from `now` (`--plow=N`).
    pub fn send_plow_after(&mut self, now: f64, seconds: f32) {
        self.plow_at = Some(now + seconds.max(0.0) as f64);
    }

    fn pick_halloween_plow(&mut self) {
        if self.plow_forms.is_empty() {
            let first = self.rng.f() < 0.5;
            self.plow_forms = vec![first, !first];
        }
        self.ghosts_blow = self.plow_forms.pop().unwrap_or(false);
        match std::env::var("JULE_HALLOWEEN_PLOV").as_deref() {
            Ok("heks") => self.ghosts_blow = false,
            Ok("spoegelser") => self.ghosts_blow = true,
            _ => {}
        }
        crate::log::debug(if self.ghosts_blow { "halloween plow: ghosts blow" } else { "halloween plow: witch sweeps" });
    }

    fn start_plow(&mut self, screens: &[ScreenInfo], start: usize) {
        if self.plow.active {
            return;
        }
        // (carnival's sweepers wait until the band truck has gone by)
        if self.karneval && self.santa.is_some() {
            self.plow.cooldown = 15.0;
            return;
        }
        if self.halloween {
            self.pick_halloween_plow();
        }
        // all screens joined edge to edge with the starting screen, left and right
        let rects: Vec<Rect> = screens.iter().map(|s| s.rect).collect();
        let mut row = vec![start];
        let mut grew = true;
        while grew {
            grew = false;
            for i in 0..rects.len() {
                if !row.contains(&i)
                    && row.iter().any(|&m| neighbor(&rects, m, -1.0) == Some(i) || neighbor(&rects, m, 1.0) == Some(i))
                {
                    row.push(i);
                    grew = true;
                }
            }
        }
        let p = &mut self.plow;
        p.min_x = row.iter().map(|&i| rects[i].x as f32).fold(f32::MAX, f32::min);
        p.max_x = row.iter().map(|&i| rects[i].right() as f32).fold(f32::MIN, f32::max);
        p.dir = p.next_dir;
        p.next_dir = -p.next_dir;
        let sc = screens[start].s * PLOW_SCALE;
        p.gx = if p.dir > 0.0 { p.min_x - 110.0 * sc } else { p.max_x + 110.0 * sc };
        p.pushed = 0.0;
        p.active = true;
        crate::log::debug(&format!("plow start dir={} from {} to {} screens={}", p.dir, p.min_x, p.max_x, row.len()));
        p.members = row;
    }

    fn update_plow(&mut self, dt: f32, screens: &[ScreenInfo], enabled: bool) {
        if !self.plow.active {
            self.plow.cooldown -= dt;
            if enabled && self.plow.cooldown <= 0.0 {
                // the plow comes when a screen's pile is three quarters of its normal height
                if let Some(i) = screens.iter().position(|s| s.heap_average > 18.0 * s.s * 0.75) {
                    self.start_plow(screens, i);
                }
            }
            return;
        }
        // (so does Halloween's witch; the ghosts float a little faster, and New Year's street sweeper trundles)
        // (carnival's sweepers walk too)
        let pace = if self.muertos || self.karneval || (self.halloween && !self.ghosts_blow) {
            CART_PACE
        } else if self.halloween || self.nytaar {
            0.6
        } else {
            1.0
        };
        let p = &mut self.plow;
        // speed and size follow the screen the truck is on
        let here = p
            .members
            .iter()
            .find(|&&i| p.gx >= screens[i].rect.x as f32 && p.gx < screens[i].rect.right() as f32)
            .or(p.members.first());
        let s = here.map_or(1.0, |&i| screens[i].s);
        p.gx += p.dir * PLOW_SPEED * pace * s * dt;
        p.wheel += PLOW_SPEED * pace * s * dt / (10.0 * s * PLOW_SCALE);
        let margin = 260.0 * s * PLOW_SCALE;
        if (p.dir > 0.0 && p.gx > p.max_x + margin) || (p.dir < 0.0 && p.gx < p.min_x - margin) {
            p.active = false;
            p.cooldown = 30.0;
            crate::log::debug(&format!("plow done, pushed {:.0}", p.pushed));
        }
    }

    // ------------------------------------------------------------------ every frame
    /// True once after each new trip.
    pub fn take_new_trip(&mut self) -> bool {
        std::mem::take(&mut self.new_trip)
    }

    /// The stretch of screens Santa flies over this trip (for panning his sound).
    pub fn santa_span(&self) -> Option<(f32, f32)> {
        self.santa.as_ref().map(|s| (s.min_x, s.max_x))
    }

    /// The row of screens the plow drives this run (for panning its sound).
    pub fn plow_span(&self) -> (f32, f32) {
        (self.plow.min_x, self.plow.max_x)
    }

    // ------------------------------------------------------------------ effects (from the calendar)
    /// Gold and white stars falling over every screen.
    pub fn star_shower(&mut self, screens: &[ScreenInfo]) {
        for sc in screens {
            let (b, s) = (sc.rect, sc.s);
            for _ in 0..90 {
                let r = &mut self.rng;
                let life = 5.0 + r.f() * 3.0;
                self.sparks.push(Spark {
                    x: b.x as f32 + r.f() * b.w as f32,
                    y: b.y as f32 - r.f() * b.h as f32 * 0.8,
                    vx: (r.f() - 0.5) * 20.0 * s,
                    vy: (140.0 + r.f() * 140.0) * s,
                    life,
                    max: life,
                    size: (3.0 + r.f() * 4.0) * s,
                    gold: r.f() < 0.8,
                    star: true,
                });
            }
        }
    }

    /// Sparks rising around the snowman when the children have finished it (`small`), or around autumn's
    /// haystack when it grew today (at `pos`, global coordinates, on a screen of scale s).
    pub fn snowman_celebrate(&mut self, (x, y): (f32, f32), s: f32, small: bool) {
        let (wide, high, count) = if small { (60.0, 70.0, 45) } else { (90.0, 120.0, 70) };
        for _ in 0..count {
            let r = &mut self.rng;
            let life = 1.5 + r.f() * 1.5;
            self.sparks.push(Spark {
                x: x + (r.f() - 0.5) * wide * s,
                y: y - r.f() * high * s,
                vx: (r.f() - 0.5) * 60.0 * s,
                vy: -(20.0 + r.f() * 60.0) * s,
                life,
                max: life,
                size: (2.0 + r.f() * 3.0) * s,
                gold: r.f() < 0.6,
                star: false,
            });
        }
    }

    /// A puff of sparkles where an elf vanishes or reappears by magic (its feet at (x, y), global coordinates;
    /// `sc` pixels per unit of the elf, on a screen of scale s).
    pub fn magic_puff(&mut self, (x, y): (f32, f32), sc: f32, s: f32) {
        for i in 0..26 {
            let r = &mut self.rng;
            let life = 0.8 + r.f() * 0.8;
            self.sparks.push(Spark {
                x: x + (r.f() - 0.5) * 36.0 * sc,
                y: y - r.f() * 60.0 * sc,
                vx: (r.f() - 0.5) * 50.0 * s,
                vy: -(15.0 + r.f() * 45.0) * s,
                life,
                max: life,
                size: (1.5 + r.f() * 2.5) * s,
                gold: r.f() < 0.5,
                star: i % 4 == 0,
            });
        }
    }

    pub fn update(&mut self, dt: f32, now: f64, screens: &[ScreenInfo], santa: bool, plow: bool) {
        if self.plow_at.is_some_and(|at| now >= at) {
            self.plow_at = None;
            self.send_plow(screens);
        }
        self.update_santa(dt, screens, santa);
        self.update_sparks(dt);
        self.update_rockets(dt);
        self.update_plow(dt, screens, plow);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn screens() -> Vec<ScreenInfo> {
        // two monitors side by side, as on the Mint test machine, plus one far away below
        [Rect::new(0, 0, 6144, 3456), Rect::new(6144, 0, 5120, 2880), Rect::new(0, 5000, 1920, 1080)]
            .into_iter()
            .enumerate()
            .map(|(i, rect)| ScreenInfo { rect, s: rect.h as f32 / 1080.0, primary: i == 0, heap_average: 0.0 })
            .collect()
    }

    #[test]
    fn neighbours_touch_edge_to_edge() {
        let r: Vec<Rect> = screens().iter().map(|s| s.rect).collect();
        assert_eq!(neighbor(&r, 0, 1.0), Some(1));
        assert_eq!(neighbor(&r, 1, -1.0), Some(0));
        assert_eq!(neighbor(&r, 0, -1.0), None);
        assert_eq!(neighbor(&r, 2, 1.0), None);
    }

    #[test]
    fn plow_drives_across_the_row_and_finishes() {
        let sc = screens();
        let mut f = Figures::new(1);
        f.send_plow(&sc);
        assert!(f.plow.active);
        let mut m = f.plow.members.clone();
        m.sort();
        assert_eq!(m, vec![0, 1], "the screen below is not in the row");
        let mut t = 0.0;
        while f.plow.active && t < 600.0 {
            f.update(0.05, t, &sc, false, true);
            t += 0.05;
        }
        assert!(!f.plow.active, "the plow never arrived");
        // across 11264 px at 170 px/s per 1080 px of screen height: well under a minute on these screens
        assert!(t < 60.0, "took {t} s");
    }

    #[test]
    fn a_volley_sends_rockets_up_that_burst_in_the_top_band_and_then_it_is_over() {
        let sc = screens();
        let mut f = Figures::new(4);
        f.nytaar = true;
        f.launch_santa(&sc);
        assert!(f.santa.is_some(), "the volley counts as a trip");
        let (mut t, mut most, mut rockets) = (0.0, 0usize, 0usize);
        while f.santa.is_some() && t < 60.0 {
            f.update(0.05, t, &sc, false, false);
            rockets = rockets.max(f.rockets.len());
            most = most.max(f.embers.len());
            for e in f.embers.iter().filter(|e| e.colour.is_some()) {
                // (a burst's sparks start in the top third of their screen and reach about a fifth of its height)
                let on = sc.iter().find(|s| e.x >= s.rect.x as f32 - 700.0 && e.x < s.rect.right() as f32 + 700.0 && e.y >= s.rect.y as f32 - 800.0 && e.y < s.rect.bottom() as f32);
                let s = on.expect("a spark is on no screen");
                assert!(e.y < s.rect.y as f32 + s.rect.h as f32 * 0.62, "a spark at {} is far below the top band", e.y);
            }
            t += 0.05;
        }
        assert!(rockets > 0 && most > 60, "{rockets} rockets at once, {most} sparks");
        assert!(t > 12.0 && t < 30.0, "the volley took {t} s");
        assert!(f.rockets.is_empty());
        // the last sparks go out by themselves
        for _ in 0..80 {
            f.update(0.05, t, &sc, false, false);
        }
        assert!(f.embers.is_empty() && !f.busy());
    }

    #[test]
    fn a_number_is_written_in_sparks_and_goes_out() {
        let mut f = Figures::new(5);
        f.write_in_sparks(2027, (1000.0, 500.0), 140.0, 2.0, 1.0);
        // 2, 0, 2 and 7 have 14, 19, 14 and 11 dots
        assert_eq!(f.embers.len(), 14 + 19 + 14 + 11);
        let (left, right) = f.embers.iter().fold((f32::MAX, f32::MIN), |(l, r), e| (l.min(e.x), r.max(e.x)));
        assert!(left > 700.0 && right < 1300.0 && (left + right) / 2.0 > 980.0 && (left + right) / 2.0 < 1020.0, "{left}..{right}");
        for _ in 0..50 {
            f.update(0.05, 0.0, &[], false, false);
        }
        assert!(f.embers.is_empty());
    }

    #[test]
    fn plow_comes_when_the_pile_is_high() {
        let mut sc = screens();
        let mut f = Figures::new(2);
        f.update(25.0, 0.0, &sc, false, true);
        assert!(!f.plow.active);
        sc[1].heap_average = 18.0 * sc[1].s;
        f.update(0.05, 25.0, &sc, false, true);
        assert!(f.plow.active);
    }

    #[test]
    fn santa_crosses_both_screens_and_finish_runs_ends_everything() {
        let sc = screens();
        let mut f = Figures::new(3);
        for _ in 0..20 {
            f.launch_santa(&sc);
            let s = f.santa.as_ref().unwrap();
            if s.y0 < 2880.0 {
                break;
            }
            f.santa = None;
        }
        let s = f.santa.as_ref().unwrap();
        assert!(s.max_x - s.min_x > 11000.0 || s.y0 >= 5000.0);
        f.update(1.0, 0.0, &sc, true, false);
        assert!(!f.sparks.is_empty());
        f.send_plow(&sc);
        f.finish_runs();
        assert!(f.santa.is_none() && f.sparks.is_empty() && !f.plow.active);
    }
}
