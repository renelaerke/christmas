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
        }
    }

    /// True while something fast is on its way (the frame rate is boosted).
    pub fn busy(&self) -> bool {
        self.santa.is_some() || !self.sparks.is_empty() || self.plow.active
    }

    /// The screens were rebuilt: whatever was on its way is gone with them.
    pub fn screens_changed(&mut self) {
        self.santa = None;
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
        let target = &screens[self.rng.range(0, screens.len() as i32) as usize];
        let b = target.rect;
        let scale = target.s;
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
        let speed = 230.0 * pace * scale * wide;
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
        s.x += s.dir * s.speed * dt;
        s.phase += dt;
        self.spark_acc += dt * 45.0;
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
        if (s.dir > 0.0 && s.x > s.max_x + 450.0 * s.scale) || (s.dir < 0.0 && s.x < s.min_x - 450.0 * s.scale) {
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

    fn start_plow(&mut self, screens: &[ScreenInfo], start: usize) {
        if self.plow.active {
            return;
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
        let p = &mut self.plow;
        // speed and size follow the screen the truck is on
        let here = p
            .members
            .iter()
            .find(|&&i| p.gx >= screens[i].rect.x as f32 && p.gx < screens[i].rect.right() as f32)
            .or(p.members.first());
        let s = here.map_or(1.0, |&i| screens[i].s);
        p.gx += p.dir * PLOW_SPEED * s * dt;
        p.wheel += PLOW_SPEED * s * dt / (10.0 * s * PLOW_SCALE);
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

    /// Sparks rising around the snowman when it grew today (at `pos`, global coordinates, on a screen of scale s).
    pub fn snowman_celebrate(&mut self, (x, y): (f32, f32), s: f32) {
        for _ in 0..70 {
            let r = &mut self.rng;
            let life = 1.5 + r.f() * 1.5;
            self.sparks.push(Spark {
                x: x + (r.f() - 0.5) * 90.0 * s,
                y: y - r.f() * 120.0 * s,
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

    pub fn update(&mut self, dt: f32, now: f64, screens: &[ScreenInfo], santa: bool, plow: bool) {
        if self.plow_at.is_some_and(|at| now >= at) {
            self.plow_at = None;
            self.send_plow(screens);
        }
        self.update_santa(dt, screens, santa);
        self.update_sparks(dt);
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
