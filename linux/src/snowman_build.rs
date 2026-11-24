//! The snowman in the Christmas theme (as `src/SnowmanBuild.cs` and `SnowmanBuild.swift`, line for line): three
//! children build it at the bottom of the primary screen in about 15 minutes. They roll the three balls one by
//! one, lift them on top of each other and dress it (eyes, nose, buttons, arms, smile, scarf, hat). When it is
//! finished they cheer and have a snowball fight, and a few minutes later the snow plow comes by and runs it down.
//! The children then walk to another place and start again.
//!
//! This is only the story; `layer/build.rs` draws it on the primary screen, and the controller owns it (so it
//! survives the screens being rebuilt), tells it where the plow is and sends the plow when it asks. Positions are
//! in logical units (pixels / the screen's figure scale) from the primary screen's left edge, and heights are
//! above the ground.
//! `JULE_SNOWMAN_SPEED=N` runs it N times faster, and `JULE_SNOWMAN_START=T[,X]` starts T seconds into the build
//! (at X units from the left edge) instead of somewhere at random (both for testing).

use crate::figures::PLOW_SCALE;
use crate::rng::Rng;

pub const BUILD_TIME: f32 = 900.0;
// When each part is rolled and lifted (seconds into the build).
const BOTTOM_END: f32 = 330.0;
const MIDDLE_START: f32 = 150.0;
const MIDDLE_END: f32 = 540.0;
const MIDDLE_LIFT: f32 = 565.0;
const HEAD_START: f32 = 565.0;
const HEAD_END: f32 = 735.0;
const HEAD_LIFT: f32 = 760.0;
const DRESS_START: f32 = 760.0;
/// eyes, nose, buttons, arms, smile, scarf, hat
pub const ITEMS: i32 = 7;
const ITEM_TIME: f32 = (BUILD_TIME - DRESS_START) / ITEMS as f32;
pub const BOTTOM_R: f32 = 14.0;
pub const MIDDLE_R: f32 = 10.0;
pub const HEAD_R: f32 = 7.5;
// the centres of the stacked balls, above the ground
pub const MIDDLE_Y: f32 = 2.0 * BOTTOM_R - 3.0 + MIDDLE_R;
pub const HEAD_Y: f32 = MIDDLE_Y + MIDDLE_R - 2.5 + HEAD_R;
/// The children's playground while they build and play (half its width, in units round the site): the walkers
/// turn before they reach it. The place is chosen far enough from the screen's edges that the playground never
/// covers one (a walker coming in at an edge would otherwise have nowhere to go).
pub const PLAY_HALF_WIDTH: f32 = 85.0;
const GRAVITY: f32 = 110.0;

#[derive(Clone, Copy, Default)]
pub struct Ball {
    pub x: f32,
    pub y: f32,
    pub r: f32,
    pub roll: f32,
    vx: f32,
    pub present: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Pose {
    Walk,
    Stand,
    Wave,
    Push,
    Lift,
    Pat,
    Jump,
    Throw,
    Sad,
}

pub struct Kid {
    /// Which of the three children (clothes and size).
    pub look: usize,
    pub size: f32,
    /// Units per second.
    speed: f32,
    pub x: f32,
    pub dir: f32,
    pub lift: f32,
    pub walk_phase: f32,
    pub t: f32,
    target_x: f32,
    face_dir: f32,
    pub throw_t: f32,
    /// The pose drawn now, and the one to take at the target.
    pub pose: Pose,
    want: Pose,
    /// The plow is passing.
    waving: bool,
}

impl Kid {
    fn new(look: usize, size: f32, speed: f32) -> Kid {
        Kid {
            look,
            size,
            speed,
            x: 0.0,
            dir: 1.0,
            lift: 0.0,
            walk_phase: 0.0,
            t: 0.0,
            target_x: 0.0,
            face_dir: 0.0,
            throw_t: -1.0,
            pose: Pose::Walk,
            want: Pose::Walk,
            waving: false,
        }
    }
}

pub struct Snowball {
    pub x: f32,
    pub y: f32,
    vx: f32,
    vy: f32,
    target_x: f32,
    /// Negative while it flies; then the half second its puff lasts.
    pub life: f32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    Walking,
    Building,
    Finished,
    RunDown,
}

pub struct SnowmanBuild {
    /// Bottom, middle, head.
    pub balls: [Ball; 3],
    pub kids: [Kid; 3],
    pub snowballs: Vec<Snowball>,
    pub site_x: f32,
    /// How many of the items are on.
    pub dressed: i32,
    pub state: State,
    /// Seconds into the build.
    pub t: f32,
    /// The controller sends the plow (and clears this).
    pub wants_plow: bool,
    /// True for the one update in which the snowman was finished.
    pub just_finished: bool,
    /// The balls the plow ran down in this update (x, height of the centre, radius): the screen throws them up as
    /// chunks of snow.
    pub run_down: Vec<(f32, f32, f32)>,
    rng: Rng,
    speed: f32,
    started: bool,
    clock: f32,
    plow_at: f32,
    state_timer: f32,
    throw_timer: f32,
    wander_timer: f32,
    next_thrower: usize,
    /// Where the plow's blade was in the last update (None: no plow on the screen).
    last_blade: Option<f32>,
}

fn sign(v: f32) -> f32 {
    if v > 0.0 {
        1.0
    } else if v < 0.0 {
        -1.0
    } else {
        0.0
    }
}

fn smooth(a: f32, b: f32, x: f32) -> f32 {
    let f = ((x - a) / (b - a)).clamp(0.0, 1.0);
    f * f * (3.0 - 2.0 * f)
}

/// A ball rolled back and forth around its home while it grows, coming to rest at home.
#[allow(clippy::too_many_arguments)]
fn roll(b: &mut Ball, t: f32, t0: f32, t1: f32, home: f32, amp: f32, period: f32, r: f32) {
    let u = t.min(t1) - t0;
    let f = (u / (t1 - t0)).clamp(0.0, 1.0);
    b.r = 2.5 + (r - 2.5) * f.powf(0.6);
    let settle = 1.0 - smooth(t1 - 0.15 * (t1 - t0), t1, t0 + u);
    b.x = home + amp * (std::f32::consts::TAU * u / period).sin() * settle;
    b.y = b.r;
    b.roll = (b.x - home) / b.r.max(1.0);
}

/// Lifted in an arc from where it was rolled onto the ball below.
fn lift_onto(b: &mut Ball, t: f32, t0: f32, t1: f32, from: f32, to: f32, y: f32) {
    if t < t0 {
        return;
    }
    let f = smooth(t0, t1, t);
    b.x = from + (to - from) * f;
    b.y = b.r + (y - b.r) * f + (std::f32::consts::PI * f).sin() * 6.0;
}

fn go(k: &mut Kid, x: f32, want: Pose, face: f32) {
    k.target_x = x;
    k.want = want;
    k.face_dir = face;
}

fn push_ball(k: &mut Kid, b: &Ball) {
    // from behind, in the direction it rolls
    let dir = if b.vx.abs() > 0.05 {
        sign(b.vx)
    } else if k.face_dir != 0.0 {
        k.face_dir
    } else {
        1.0
    };
    go(k, b.x - dir * (b.r + 6.0), Pose::Push, dir);
}

/// Each item is put on by one of the two big children in turn, reaching up for the last seconds of its turn.
fn dress(k: &mut Kid, t: f32, parity: i32, x: f32, face: f32) {
    let u = t - DRESS_START;
    let slot = (u / ITEM_TIME) as i32;
    let mine = slot < ITEMS && slot % 2 == parity && u - slot as f32 * ITEM_TIME > ITEM_TIME - 7.0;
    go(k, x, if mine { Pose::Lift } else { Pose::Stand }, face);
}

impl SnowmanBuild {
    pub fn new(seed: u64) -> SnowmanBuild {
        let speed = std::env::var("JULE_SNOWMAN_SPEED")
            .ok()
            .and_then(|v| v.trim().parse::<f32>().ok())
            .filter(|v| *v > 0.0)
            .unwrap_or(1.0);
        SnowmanBuild {
            balls: [Ball::default(); 3],
            kids: [Kid::new(0, 1.0, 30.0), Kid::new(1, 0.95, 30.0), Kid::new(2, 0.8, 24.0)],
            snowballs: Vec::new(),
            site_x: 0.0,
            dressed: 0,
            state: State::Walking,
            t: 0.0,
            wants_plow: false,
            just_finished: false,
            run_down: Vec::new(),
            rng: Rng::new(seed),
            speed,
            started: false,
            clock: 0.0,
            plow_at: -1.0,
            state_timer: 0.0,
            throw_timer: 0.0,
            wander_timer: 0.0,
            next_thrower: 0,
            last_blade: None,
        }
    }

    #[cfg(test)]
    fn has_snow(&self) -> bool {
        self.balls.iter().any(|b| b.present)
    }

    /// The children are building or playing: the walkers keep out of their playground.
    pub fn playing(&self) -> bool {
        matches!(self.state, State::Building | State::Finished)
    }

    /// One frame. `width_u` is the screen's width in units, and `plow` the truck while it is on this screen's row:
    /// its x in units from the screen's left edge and its direction. Returns the snow the plow took with it when
    /// it ran the snowman down (in units; it goes into the pile before the blade).
    pub fn update(&mut self, dt: f32, width_u: f32, plow: Option<(f32, f32)>) -> f32 {
        self.run_down.clear();
        let mut pushed = 0.0;
        for k in &mut self.kids {
            k.waving = plow.is_some_and(|(px, _)| (k.x - px).abs() < 170.0);
        }
        let blade = plow.map(|(px, dir)| px + dir * 72.0 * PLOW_SCALE);
        // Only where the blade arrives this frame: a snowman begun behind the plow, after it has passed, stays.
        if let (Some((_, dir)), Some(blade), Some(last)) = (plow, blade, self.last_blade) {
            let reached = self.balls.iter().any(|b| {
                let near = b.x - dir * b.r; // the ball's side facing the plow
                b.present && (blade - near) * dir >= 0.0 && (last - near) * dir < 0.0
            });
            if reached {
                for b in self.balls.iter().filter(|b| b.present) {
                    self.run_down.push((b.x, b.y, b.r));
                    pushed += b.r * b.r * 2.0;
                }
                crate::log::debug(&format!(
                    "snowman: run down by the plow at x={} ({} s into the build)",
                    self.site_x as i32, self.t as i32
                ));
                self.run_over();
            }
        }
        self.last_blade = blade;

        let dt = dt * self.speed;
        self.clock += dt;
        self.just_finished = false;
        let lo = PLAY_HALF_WIDTH + 40.0;
        let hi = lo.max(width_u - PLAY_HALF_WIDTH - 40.0);
        if !self.started {
            // The app may start in the middle of a build: somewhere, some way along.
            self.started = true;
            self.site_x = lo + self.rng.f() * (hi - lo);
            self.state = State::Building;
            self.t = self.rng.f() * BUILD_TIME * 0.95;
            if let Ok(v) = std::env::var("JULE_SNOWMAN_START") {
                let mut parts = v.split(',').map(|p| p.trim().parse::<f32>().ok());
                if let Some(Some(t)) = parts.next() {
                    self.t = t.clamp(0.0, BUILD_TIME - 1.0);
                }
                if let Some(Some(x)) = parts.next() {
                    self.site_x = x;
                }
            }
            let site = self.site_x;
            for k in &mut self.kids {
                k.x = site + (self.rng.f() - 0.5) * 80.0;
                k.target_x = k.x;
            }
            crate::log::debug(&format!("snowman: building at x={}, {} s along", self.site_x as i32, self.t as i32));
        }
        self.site_x = self.site_x.min(hi).max(lo);

        match self.state {
            State::Walking => {
                if self.kids.iter().all(|k| (k.x - k.target_x).abs() <= 1.5) {
                    self.state = State::Building;
                    self.t = 0.0;
                    crate::log::debug(&format!("snowman: starting a new one at x={}", self.site_x as i32));
                }
            }
            State::Building => {
                self.t += dt;
                if self.t >= BUILD_TIME {
                    self.t = BUILD_TIME;
                    self.state = State::Finished;
                    self.state_timer = 0.0;
                    self.throw_timer = 3.0;
                    self.just_finished = true;
                    self.plow_at = self.clock + 120.0 + self.rng.f() * 120.0;
                    crate::log::debug(&format!(
                        "snowman: finished, the plow comes in {} s",
                        (self.plow_at - self.clock) as i32
                    ));
                }
            }
            State::Finished => {
                self.state_timer += dt;
                // If the plow cannot come now (already out, or switched off), ask again a minute later.
                if self.plow_at >= 0.0 && self.clock >= self.plow_at {
                    self.wants_plow = true;
                    self.plow_at = self.clock + 60.0;
                }
            }
            State::RunDown => {
                self.state_timer -= dt;
                if self.state_timer <= 0.0 && !self.kids.iter().any(|k| k.waving) {
                    self.move_on(lo, hi);
                }
            }
        }

        self.place_balls(dt);
        self.set_targets(dt);
        self.move_kids(dt, width_u);
        self.update_snowballs(dt);
        pushed
    }

    /// The plow has reached the snowman: it is gone, and the children start again elsewhere after a while.
    fn run_over(&mut self) {
        self.state = State::RunDown;
        self.state_timer = 5.0;
        self.plow_at = -1.0;
        self.wants_plow = false;
        self.snowballs.clear();
        for b in &mut self.balls {
            b.present = false;
        }
        self.dressed = 0;
        let site = self.site_x;
        for k in &mut self.kids {
            k.throw_t = -1.0;
            let (x, face) = (k.x, sign(site - k.x));
            go(k, x, Pose::Sad, face);
        }
    }

    fn move_on(&mut self, lo: f32, hi: f32) {
        let old = self.site_x;
        let away = ((hi - lo) * 0.3).min(250.0);
        for _ in 0..12 {
            self.site_x = lo + self.rng.f() * (hi - lo);
            if (self.site_x - old).abs() >= away {
                break;
            }
        }
        self.state = State::Walking;
        let site = self.site_x;
        go(&mut self.kids[0], site - 20.0, Pose::Stand, 1.0);
        go(&mut self.kids[1], site + 40.0, Pose::Pat, -1.0);
        go(&mut self.kids[2], site + 15.0, Pose::Stand, -1.0);
        crate::log::debug(&format!("snowman: the children walk from x={} to x={}", old as i32, site as i32));
    }

    // ------------------------------------------------------------------ the balls
    fn place_balls(&mut self, dt: f32) {
        let built = self.playing();
        let t = if self.state == State::Finished { BUILD_TIME } else { self.t };
        let site = self.site_x;
        let before = [self.balls[0].x, self.balls[1].x, self.balls[2].x];

        let bottom = &mut self.balls[0];
        bottom.present = built;
        if bottom.present {
            roll(bottom, t, 0.0, BOTTOM_END, site, 30.0, 50.0, BOTTOM_R);
        }

        let middle = &mut self.balls[1];
        middle.present = built && t >= MIDDLE_START;
        if middle.present {
            roll(middle, t, MIDDLE_START, MIDDLE_END, site + 42.0, 22.0, 44.0, MIDDLE_R);
            lift_onto(middle, t, MIDDLE_END + 10.0, MIDDLE_LIFT, site + 42.0, site, MIDDLE_Y);
        }

        let head = &mut self.balls[2];
        head.present = built && t >= HEAD_START;
        if head.present {
            roll(head, t, HEAD_START, HEAD_END, site - 34.0, 14.0, 36.0, HEAD_R);
            lift_onto(head, t, HEAD_END + 8.0, HEAD_LIFT, site - 34.0, site, HEAD_Y);
        }

        for (b, x0) in self.balls.iter_mut().zip(before) {
            b.vx = if dt > 0.0 { (b.x - x0) / dt } else { 0.0 };
        }
        // (nothing is worn once the plow has run it down: the build's clock stands still until they begin again)
        self.dressed = if !built || t < DRESS_START { 0 } else { (((t - DRESS_START) / ITEM_TIME) as i32).min(ITEMS) };
    }

    // ------------------------------------------------------------------ the children
    fn set_targets(&mut self, dt: f32) {
        let (t, site) = (self.t, self.site_x);
        if self.state == State::Building {
            // the oldest rolls the bottom ball, helps lift the middle one, rolls the head and dresses it
            if t < BOTTOM_END {
                push_ball(&mut self.kids[0], &self.balls[0]);
            } else if t < MIDDLE_END + 10.0 {
                go(&mut self.kids[0], site - BOTTOM_R - 7.0, Pose::Pat, 1.0);
            } else if t < MIDDLE_LIFT {
                go(&mut self.kids[0], site - BOTTOM_R - 5.0, Pose::Lift, 1.0);
            } else if t < HEAD_END {
                push_ball(&mut self.kids[0], &self.balls[2]);
            } else if t < HEAD_LIFT {
                go(&mut self.kids[0], site - BOTTOM_R - 6.0, Pose::Lift, 1.0);
            } else {
                dress(&mut self.kids[0], t, 0, site - BOTTOM_R - 6.0, 1.0);
            }

            // the second makes snow ready, then rolls the middle ball and lifts it up
            if t < MIDDLE_START {
                go(&mut self.kids[1], site + 40.0, Pose::Pat, -1.0);
            } else if t < MIDDLE_END {
                push_ball(&mut self.kids[1], &self.balls[1]);
            } else if t < MIDDLE_END + 10.0 {
                go(&mut self.kids[1], site + 42.0 + MIDDLE_R + 5.0, Pose::Stand, -1.0);
            } else if t < MIDDLE_LIFT {
                go(&mut self.kids[1], site + BOTTOM_R + 5.0, Pose::Lift, -1.0);
            } else if t < HEAD_LIFT {
                go(&mut self.kids[1], site + BOTTOM_R + 7.0, Pose::Pat, -1.0);
            } else {
                dress(&mut self.kids[1], t, 1, site + BOTTOM_R + 6.0, -1.0);
            }
        } else if self.state == State::Finished {
            if self.state_timer < 5.0 {
                // hooray, beside it (not in front, where they would hide it)
                go(&mut self.kids[0], site - 30.0, Pose::Jump, 1.0);
                go(&mut self.kids[1], site + 30.0, Pose::Jump, -1.0);
                go(&mut self.kids[2], site + 48.0, Pose::Jump, -1.0);
            } else {
                // a snowball fight in front of the snowman
                if self.kids[0].throw_t < 0.0 {
                    go(&mut self.kids[0], site - 60.0, Pose::Stand, 1.0);
                }
                if self.kids[1].throw_t < 0.0 {
                    go(&mut self.kids[1], site + 60.0, Pose::Stand, -1.0);
                }
                self.throw_timer -= dt;
                let ready = self.kids[..2].iter().all(|k| (k.x - k.target_x).abs() < 1.0);
                if self.throw_timer <= 0.0 && ready {
                    self.kids[self.next_thrower].throw_t = 0.0;
                    self.next_thrower ^= 1;
                    self.throw_timer = 2.5 + self.rng.f() * 4.0;
                }
            }
        }

        // the little one wanders about, pats snow and jumps
        if self.state == State::Building || (self.state == State::Finished && self.state_timer >= 5.0) {
            self.wander_timer -= dt;
            if self.wander_timer <= 0.0 {
                self.wander_timer = 6.0 + self.rng.f() * 6.0;
                let r = self.rng.f();
                let x = site + (self.rng.f() - 0.5) * 110.0;
                let want = if r < 0.45 {
                    Pose::Pat
                } else if r < 0.7 {
                    Pose::Jump
                } else {
                    Pose::Stand
                };
                go(&mut self.kids[2], x, want, sign(site - x));
            }
        }
    }

    fn move_kids(&mut self, dt: f32, width_u: f32) {
        let wrap = 200.0 * std::f32::consts::PI;
        let mut thrower = None;
        for (i, k) in self.kids.iter_mut().enumerate() {
            k.t += dt;
            if k.t > wrap {
                k.t -= wrap;
            }
            k.target_x = k.target_x.min(width_u - 10.0).max(10.0);
            let d = k.target_x - k.x;
            if k.waving {
                k.pose = Pose::Wave;
                k.lift = 0.0;
                continue;
            }
            if d.abs() > 1.0 {
                let step = sign(d) * d.abs().min(k.speed * dt);
                k.x += step;
                k.dir = sign(d);
                k.pose = Pose::Walk;
                k.walk_phase += step.abs() / (4.5 * k.size);
            } else {
                // at the target (a pushed ball moves on slowly: the legs keep walking)
                k.walk_phase += d.abs() / (4.5 * k.size);
                k.x = k.target_x;
                k.pose = k.want;
                if k.face_dir != 0.0 {
                    k.dir = k.face_dir;
                }
            }
            if k.throw_t >= 0.0 {
                let before = k.throw_t;
                k.throw_t += dt;
                k.pose = Pose::Throw;
                if before < 0.3 && k.throw_t >= 0.3 {
                    thrower = Some(i);
                }
                if k.throw_t > 0.7 {
                    k.throw_t = -1.0;
                }
            }
            k.lift = if k.pose == Pose::Jump { (k.t * 6.0).sin().abs() * 7.0 } else { 0.0 };
        }
        if let Some(i) = thrower {
            self.throw_at(i, if i == 0 { 1 } else { 0 });
        }
    }

    // ------------------------------------------------------------------ snowballs
    fn throw_at(&mut self, from: usize, to: usize) {
        let (fx, fdir, fsize) = (self.kids[from].x, self.kids[from].dir, self.kids[from].size);
        let (tx, tsize) = (self.kids[to].x, self.kids[to].size);
        let x = fx + fdir * 7.0 * fsize;
        let y = 32.0 * fsize;
        let flight = 0.9 + self.rng.f() * 0.3;
        let target_x = tx + (self.rng.f() - 0.5) * 16.0;
        let ty = 26.0 * tsize;
        self.snowballs.push(Snowball {
            x,
            y,
            vx: (target_x - x) / flight,
            vy: (ty - y + 0.5 * GRAVITY * flight * flight) / flight,
            target_x,
            life: -1.0,
        });
    }

    fn update_snowballs(&mut self, dt: f32) {
        self.snowballs.retain_mut(|s| {
            if s.life >= 0.0 {
                s.life -= dt;
                return s.life >= 0.0;
            }
            s.x += s.vx * dt;
            s.y += s.vy * dt;
            s.vy -= GRAVITY * dt;
            let past = if s.vx > 0.0 { s.x >= s.target_x } else { s.x <= s.target_x };
            if past || s.y <= 0.0 {
                s.y = s.y.max(0.0);
                s.life = 0.5;
            }
            true
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Runs `seconds` of the story in steps of 0.05 s on a screen 1600 units wide, with no plow.
    fn run(b: &mut SnowmanBuild, seconds: f32) {
        for _ in 0..(seconds / 0.05) as usize {
            b.update(0.05, 1600.0, None);
        }
    }

    /// A build begun at `t` seconds (whatever the test machine's environment says).
    fn begun_at(t: f32) -> SnowmanBuild {
        let mut b = SnowmanBuild::new(7);
        b.speed = 1.0;
        b.update(0.05, 1600.0, None);
        b.t = t;
        b
    }

    #[test]
    fn the_balls_come_one_by_one_and_end_stacked() {
        let mut b = begun_at(10.0);
        run(&mut b, 1.0);
        assert!(b.balls[0].present && !b.balls[1].present && !b.balls[2].present);
        assert_eq!(b.dressed, 0);
        b.t = 400.0;
        run(&mut b, 1.0);
        assert!(b.balls[1].present && !b.balls[2].present);
        b.t = 780.0;
        run(&mut b, 1.0);
        // all three on top of each other at the site, and the first items are on
        for (ball, y) in b.balls.iter().zip([BOTTOM_R, MIDDLE_Y, HEAD_Y]) {
            assert!(ball.present);
            assert!((ball.x - b.site_x).abs() < 0.01 && (ball.y - y).abs() < 0.01, "ball at {},{}", ball.x, ball.y);
        }
        assert!(b.dressed >= 1 && b.dressed < ITEMS);
    }

    #[test]
    fn finished_they_cheer_fight_and_ask_for_the_plow() {
        let mut b = begun_at(BUILD_TIME - 1.0);
        let mut finished = 0;
        for _ in 0..100 {
            b.update(0.05, 1600.0, None);
            finished += usize::from(b.just_finished);
        }
        assert_eq!(finished, 1);
        assert_eq!(b.state, State::Finished);
        assert_eq!(b.dressed, ITEMS);
        assert!(b.kids.iter().all(|k| k.pose == Pose::Jump || k.pose == Pose::Walk));
        // a snowball is thrown within the first half minute of the fight
        let mut thrown = false;
        for _ in 0..600 {
            b.update(0.05, 1600.0, None);
            thrown |= !b.snowballs.is_empty();
        }
        assert!(thrown, "no snowball was thrown");
        // the plow is asked for 2-4 minutes after the snowman was finished, and again while it does not come
        assert!(!b.wants_plow);
        run(&mut b, 240.0);
        assert!(b.wants_plow);
        b.wants_plow = false;
        run(&mut b, 61.0);
        assert!(b.wants_plow);
    }

    #[test]
    fn the_plow_runs_it_down_and_they_start_again_elsewhere() {
        let mut b = begun_at(BUILD_TIME - 1.0);
        run(&mut b, 20.0);
        let site = b.site_x;
        // the plow drives in from the left at 170 units a second
        let mut px = -200.0;
        let mut pushed = 0.0;
        let mut chunks = 0;
        while px < 1900.0 {
            px += 170.0 * 0.05;
            pushed += b.update(0.05, 1600.0, Some((px, 1.0)));
            chunks += b.run_down.len();
            // it stands until the blade is there
            if px + 72.0 * PLOW_SCALE < site - BOTTOM_R - 1.0 {
                assert!(b.has_snow(), "gone before the blade reached it (plow at {px}, snowman at {site})");
            }
        }
        assert_eq!(chunks, 3, "all three balls fly apart, once");
        assert!(pushed > 0.0);
        assert!(!b.has_snow());
        assert_eq!(b.dressed, 0, "nothing is left hanging in the air");
        // the children walk to another place and build a new one from the start
        run(&mut b, 120.0);
        assert_eq!(b.state, State::Building);
        assert!((b.site_x - site).abs() >= 250.0, "the new place is at {} (was {site})", b.site_x);
        assert!(b.t < 120.0 && b.balls[0].present && b.dressed == 0);
    }

    #[test]
    fn a_snowman_begun_behind_the_plow_stays() {
        let mut b = begun_at(100.0);
        run(&mut b, 1.0);
        // the plow is already past the place when the first update with it comes
        let mut px = b.site_x + 300.0;
        for _ in 0..200 {
            px += 170.0 * 0.05;
            b.update(0.05, 1600.0, Some((px, 1.0)));
        }
        assert!(b.has_snow());
        assert_eq!(b.state, State::Building);
    }
}
