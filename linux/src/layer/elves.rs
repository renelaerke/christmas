//! Elves (Danish "nisser": red hat, grey clothes) walking on the snow pile. They stop, wave, carry gifts, meet to
//! hand over or swap a gift, and walk over to the neighbouring screen. Every 1½–3 minutes one arrives or leaves,
//! so their number swings a little around the chosen count. Ported from the "nisser" part of `src/Layer.cs`.

use cairo::LineCap;

use super::draw::*;
use super::{heap_at, Layer, SceneState};

const TUNICS: [Argb; 4] = [rgb(115, 120, 130), rgb(40, 105, 65), rgb(150, 35, 45), rgb(70, 85, 145)];
const GIFTS: [Argb; 4] = [rgb(40, 140, 70), rgb(60, 100, 200), rgb(200, 40, 60), rgb(150, 80, 180)];
const MEET_TIME: f32 = 2.4;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ElfState {
    Walk,
    Stand,
    Wave,
}

/// One elf. It moves between screens as a whole (same clothes, direction and gift).
pub struct Elf {
    id: u64,
    pub(super) x: f32,
    dir: f32,
    speed: f32,
    walk_phase: f32,
    t: f32,
    pub(super) state: ElfState,
    pub(super) state_timer: f32,
    size: f32,
    carries_gift: bool,
    /// Walking in from an edge, walking out for good, or walking over to the neighbouring screen.
    entering: bool,
    leaving: bool,
    crossing: bool,
    /// Meeting another elf to hand over or swap a gift; the one with `meet_with` makes the exchange.
    meet_timer: f32,
    meet_cooldown: f32,
    meet_with: Option<u64>,
    tunic: Argb,
    mitten: Argb,
    gift: Argb,
}

impl Elf {
    fn free_to_meet(&self) -> bool {
        self.state == ElfState::Walk
            && self.meet_timer <= 0.0
            && self.meet_cooldown <= 0.0
            && !self.entering
            && !self.leaving
            && !self.crossing
    }

    /// Which way it walks: -1 left, 1 right (used to hand it to the neighbouring screen).
    pub fn dir(&self) -> f32 {
        self.dir
    }
}

impl Layer {
    /// All elves wave for a while (the elf party behind some calendar doors).
    pub fn elf_wave(&mut self, seconds: f32) {
        for e in &mut self.elves {
            e.state = ElfState::Wave;
            e.state_timer = seconds;
        }
    }

    /// Elves that walked off this screen towards a neighbour since the last call.
    pub fn take_outgoing_elves(&mut self) -> Vec<Elf> {
        std::mem::take(&mut self.outgoing)
    }

    /// An elf arriving from the neighbouring screen walks in at the matching edge.
    pub fn receive_elf(&mut self, mut e: Elf, from_scale: f32) {
        let s = self.s;
        e.crossing = false;
        e.leaving = false;
        e.entering = true;
        e.state = ElfState::Walk;
        e.speed = e.speed / from_scale * s;
        e.x = if e.dir > 0.0 { -40.0 * s } else { self.w as f32 + 40.0 * s };
        e.state_timer = 4.0 + self.rng.f() * 6.0;
        e.meet_with = None;
        self.elves.push(e);
        crate::log::debug(&format!(
            "elf crossed to screen x={} dir={} ({} here now)",
            self.rect.x,
            self.elves.last().map_or(0.0, |e| e.dir),
            self.elves.len()
        ));
    }

    fn add_elf(&mut self, walking_in: bool) {
        let (s, w) = (self.s, self.w as f32);
        let r = &mut self.rng;
        let dir = if r.f() < 0.5 { -1.0 } else { 1.0 };
        let x = if walking_in {
            if dir > 0.0 {
                -40.0 * s
            } else {
                w + 40.0 * s
            }
        } else {
            60.0 * s + r.f() * (w - 120.0 * s)
        };
        let speed = (22.0 + r.f() * 18.0) * s;
        let size = 0.85 + r.f() * 0.3;
        let tunic = TUNICS[r.range(0, TUNICS.len() as i32) as usize];
        let mitten = if tunic.1 > 140 { rgb(40, 105, 65) } else { HAT_RED };
        let carries_gift = r.f() < 0.4;
        let gift = GIFTS[r.range(0, GIFTS.len() as i32) as usize];
        let state_timer = 4.0 + r.f() * 6.0;
        let t = r.f() * 10.0;
        self.next_elf_id += 1;
        self.elves.push(Elf {
            id: self.next_elf_id,
            x,
            dir,
            speed,
            walk_phase: 0.0,
            t,
            state: ElfState::Walk,
            state_timer,
            size,
            carries_gift,
            entering: walking_in,
            leaving: false,
            crossing: false,
            meet_timer: 0.0,
            meet_cooldown: 0.0,
            meet_with: None,
            tunic,
            mitten,
            gift,
        });
    }

    pub(super) fn update_elves(&mut self, dt: f32, st: &SceneState) {
        let (s, w) = (self.s, self.w as f32);
        // Every 1½–3 minutes an elf arrives or leaves. The offset is pulled back toward 0, so the number swings
        // a little up and down but stays around the chosen count over time.
        self.elf_change_timer -= dt;
        if self.elf_change_timer <= 0.0 {
            // JULE_ELF_SECONDS=N (or JULE_NISSE_SECONDS) changes the interval, for testing
            self.elf_change_timer = elf_seconds().unwrap_or_else(|| 90.0 + self.rng.f() * 90.0);
            let o = self.elf_offset;
            self.elf_offset = if o == 0 {
                if self.rng.f() < 0.5 {
                    -1
                } else {
                    1
                }
            } else if self.rng.f() < 0.7 {
                o - o.signum()
            } else {
                (o + o.signum()).clamp(-2, 2)
            };
        }
        let target = if st.elves { (st.elf_count + self.elf_offset).max(1) as usize } else { 0 };
        let staying = self.elves.iter().filter(|e| !e.leaving).count();
        if staying < target {
            // At start-up everyone is already there; later arrivals walk in from a screen edge.
            let arriving = !self.elves.is_empty() || st.time > 2.0;
            for _ in 0..if arriving { 1 } else { target - staying } {
                self.add_elf(arriving);
            }
        } else if staying > target {
            if !st.elves {
                self.elves.clear();
            } else if let Some(e) = self.elves.iter_mut().rev().find(|e| !e.leaving && !e.entering && !e.crossing) {
                // Walks off at an edge with no screen beyond it if there is one (so the count really goes down),
                // otherwise at the nearest edge, where it crosses to the neighbouring screen.
                e.leaving = true;
                e.state = ElfState::Walk;
                let (left_free, right_free) = (!self.neighbor_left, !self.neighbor_right);
                e.dir = if left_free != right_free {
                    if left_free {
                        -1.0
                    } else {
                        1.0
                    }
                } else if e.x < w / 2.0 {
                    -1.0
                } else {
                    1.0
                };
            }
        }

        self.meet_elves();
        let mut exchanges = Vec::new();
        for i in 0..self.elves.len() {
            let e = &mut self.elves[i];
            e.meet_cooldown = (e.meet_cooldown - dt).max(0.0);
            if e.meet_timer > 0.0 {
                let before = e.meet_timer;
                e.meet_timer -= dt;
                // halfway through the meeting the gift changes hands
                if before > MEET_TIME / 2.0 && e.meet_timer <= MEET_TIME / 2.0 {
                    if let Some(other) = e.meet_with {
                        exchanges.push((e.id, other));
                    }
                }
                if e.meet_timer <= 0.0 {
                    // say goodbye and walk on, each in its own direction (past each other)
                    e.meet_with = None;
                    e.state = ElfState::Walk;
                    e.state_timer = 4.0 + self.rng.f() * 6.0;
                    e.meet_cooldown = 20.0;
                }
                e.t += dt;
                continue;
            }
            // Wrap at 200π (a whole number of periods for both the wave and the hat sway) so the float never grows
            // large enough to lose precision during long uptimes.
            e.t += dt;
            if e.t > 200.0 * std::f32::consts::PI {
                e.t -= 200.0 * std::f32::consts::PI;
            }
            e.state_timer -= dt;
            if e.state == ElfState::Walk {
                e.x += e.dir * e.speed * dt;
                e.walk_phase += dt * e.speed / (4.5 * s);
                if e.entering && e.x > 30.0 * s && e.x < w - 30.0 * s {
                    e.entering = false;
                }
                if !e.entering && !e.leaving && !e.crossing {
                    // At an edge with a neighbouring screen, about half the elves walk on over to it.
                    if e.x < 30.0 * s {
                        if self.neighbor_left && self.rng.f() < 0.5 {
                            e.crossing = true;
                        } else {
                            e.x = 30.0 * s;
                            e.dir = 1.0;
                        }
                    }
                    if e.x > w - 30.0 * s {
                        if self.neighbor_right && self.rng.f() < 0.5 {
                            e.crossing = true;
                        } else {
                            e.x = w - 30.0 * s;
                            e.dir = -1.0;
                        }
                    }
                }
                // no stopping or turning while arriving, leaving or crossing to another screen
                if e.entering || e.leaving || e.crossing {
                    continue;
                }
                if e.state_timer <= 0.0 {
                    let r = self.rng.f();
                    if r < 0.3 {
                        e.state = ElfState::Stand;
                        e.state_timer = 2.0 + self.rng.f() * 3.0;
                    } else if r < 0.5 {
                        e.state = ElfState::Wave;
                        e.state_timer = 2.5;
                    } else {
                        if r < 0.7 {
                            e.dir = -e.dir;
                        }
                        e.state_timer = 4.0 + self.rng.f() * 8.0;
                    }
                }
            } else if e.leaving {
                e.state = ElfState::Walk; // stop waving and keep walking out
            } else if e.state_timer <= 0.0 {
                e.state = ElfState::Walk;
                e.state_timer = 4.0 + self.rng.f() * 8.0;
                if self.rng.f() < 0.4 {
                    e.dir = -e.dir;
                }
            }
        }
        for (a, b) in exchanges {
            self.exchange_gifts(a, b);
        }

        // Elves that walked off the screen continue on the neighbouring screen in that direction, if there is one
        // (the controller hands them over); otherwise they are gone.
        let mut i = self.elves.len();
        while i > 0 {
            i -= 1;
            let e = &self.elves[i];
            if !(e.leaving || e.crossing) || (e.x >= -45.0 * s && e.x <= w + 45.0 * s) {
                continue;
            }
            let e = self.elves.remove(i);
            let has_next = if e.dir > 0.0 { self.neighbor_right } else { self.neighbor_left };
            if has_next && st.elves {
                self.outgoing.push(e);
            }
        }
    }

    /// Two elves walking toward each other stop when they meet, if at least one of them carries a gift.
    fn meet_elves(&mut self) {
        let s = self.s;
        for a in 0..self.elves.len() {
            if !self.elves[a].free_to_meet() {
                continue;
            }
            for b in 0..self.elves.len() {
                let (ea, eb) = (&self.elves[a], &self.elves[b]);
                if a == b || !eb.free_to_meet() || ea.dir == eb.dir || !(ea.carries_gift || eb.carries_gift) {
                    continue;
                }
                let d = eb.x - ea.x;
                // b is in front of a, close enough to reach out
                if d * ea.dir <= 0.0 || d.abs() >= 24.0 * s * (ea.size + eb.size) / 2.0 {
                    continue;
                }
                let id_b = eb.id;
                for (i, with) in [(a, Some(id_b)), (b, None)] {
                    let e = &mut self.elves[i];
                    e.meet_timer = MEET_TIME;
                    e.state = ElfState::Stand;
                    e.meet_with = with;
                }
                return; // one meeting at a time is plenty
            }
        }
    }

    /// One gift: it goes to the other elf. Two gifts: they swap.
    fn exchange_gifts(&mut self, a: u64, b: u64) {
        let (Some(ia), Some(ib)) =
            (self.elves.iter().position(|e| e.id == a), self.elves.iter().position(|e| e.id == b))
        else {
            return;
        };
        let (ga, gb) =
            ((self.elves[ia].carries_gift, self.elves[ia].gift), (self.elves[ib].carries_gift, self.elves[ib].gift));
        let swapped = ga.0 && gb.0;
        if swapped {
            self.elves[ia].gift = gb.1;
            self.elves[ib].gift = ga.1;
        } else {
            let (giver, taker) = if ga.0 { (ia, ib) } else { (ib, ia) };
            let gift = self.elves[giver].gift;
            self.elves[taker].carries_gift = true;
            self.elves[taker].gift = gift;
            self.elves[giver].carries_gift = false;
        }
        crate::log::debug(&format!("elves met: gift {}", if swapped { "swapped" } else { "handed over" }));
    }

    pub(super) fn draw_elves(&mut self, autumn: bool) {
        for i in 0..self.elves.len() {
            self.draw_elf(i, autumn);
        }
    }

    fn draw_elf(&mut self, i: usize, autumn: bool) {
        let e = &self.elves[i];
        let sc = self.s * e.size;
        let gy = self.ground_y - heap_at(&self.heap, e.x) + 2.0 * self.s;
        let (ex, dir) = (e.x, e.dir);
        self.mark(ex - 32.0 * sc, gy - 72.0 * sc, 64.0 * sc, 80.0 * sc);
        let e = &self.elves[i];

        let cr = &self.canvas.cr;
        let saved = cr.matrix();
        cr.translate(ex as f64, gy as f64);
        cr.scale((dir * sc) as f64, sc as f64);
        if autumn {
            animal(cr, e);
            cr.set_matrix(saved);
            return;
        }

        let walking = e.state == ElfState::Walk;
        let p = e.walk_phase as f64;
        let leg_a = if walking { p.sin() * 0.55 } else { 0.0 };
        let bob = if walking { -p.sin().abs() * 1.5 } else { 0.0 };

        fill_ellipse(cr, SHADOW, -11.0, -2.0, 22.0, 4.0);

        let pants = rgb(80, 80, 92);
        let boot = rgb(62, 40, 28);
        let leg = |hx: f64, hy: f64, a: f64| {
            let (fx, fy) = (hx + a.sin() * 12.0, hy + a.cos() * 12.0);
            line(cr, pants, 5.0, LineCap::Round, hx, hy, fx, fy);
            fill_ellipse(cr, boot, fx - 3.0, fy - 2.0, 9.0, 5.0);
        };
        leg(-2.0, -15.0 + bob, leg_a);
        leg(2.0, -15.0 + bob, -leg_a);

        cr.translate(0.0, bob);
        let (back_arm, front_arm) = if e.state == ElfState::Wave {
            (-leg_a * 0.8, 2.5 + (e.t as f64 * 11.0).sin() * 0.45)
        } else if e.carries_gift {
            (1.3, 1.3)
        } else {
            (-leg_a * 0.9, leg_a * 0.9)
        };
        let arm = |sx: f64, sy: f64, a: f64| {
            let (hx, hy) = (sx + a.sin() * 10.0, sy + a.cos() * 10.0);
            line(cr, e.tunic, 4.2, LineCap::Round, sx, sy, hx, hy);
            fill_ellipse(cr, e.mitten, hx - 2.5, hy - 2.5, 5.0, 5.0);
        };

        arm(-1.0, -29.0, back_arm);
        fill_ellipse(cr, e.tunic, -10.0, -34.0, 20.0, 22.0);
        fill_rect(cr, rgb(35, 30, 30), -9.5, -20.0, 19.0, 3.0);
        fill_rect(cr, GOLD, 2.0, -20.5, 3.5, 4.0);

        if e.carries_gift && e.state != ElfState::Wave {
            fill_rect(cr, e.gift, 6.0, -31.0, 11.0, 10.0);
            line(cr, GOLD, 1.6, LineCap::Butt, 11.5, -31.0, 11.5, -21.0);
            line(cr, GOLD, 1.6, LineCap::Butt, 6.0, -26.0, 17.0, -26.0);
            draw_ellipse(cr, GOLD, 1.6, 9.0, -34.0, 3.0, 3.0);
            draw_ellipse(cr, GOLD, 1.6, 12.0, -34.0, 3.0, 3.0);
        }

        fill_ellipse(cr, SKIN, -6.0, -44.0, 13.0, 12.0);
        cr.new_path();
        cr.move_to(-6.0, -39.0);
        cr.curve_to(-7.0, -30.0, -2.0, -22.0, 3.0, -20.0);
        cr.curve_to(7.0, -24.0, 9.0, -32.0, 7.5, -39.0);
        cr.close_path();
        set(cr, rgb(250, 250, 250));
        let _ = cr.fill();
        arm(1.0, -29.0, front_arm);
        fill_ellipse(cr, rgb(240, 160, 150), 4.0, -40.0, 5.0, 5.0);

        let sway = (if walking { p * 0.5 } else { e.t as f64 * 1.5 }).sin() * 2.5;
        let (tip_x, tip_y) = (-14.0 + sway, -57.0);
        cr.new_path();
        cr.move_to(-7.5, -39.0);
        cr.line_to(8.0, -39.0);
        cr.curve_to(9.0, -54.0, 0.0, -62.0, tip_x, tip_y);
        cr.curve_to(-6.0, -57.0, -7.0, -49.0, -7.5, -39.0);
        cr.close_path();
        set(cr, HAT_RED);
        let _ = cr.fill();
        line(cr, rgb(150, 15, 25), 2.0, LineCap::Butt, -7.5, -39.5, 8.0, -39.5);
        fill_ellipse(cr, WHITE, tip_x - 3.0, tip_y - 3.0, 6.0, 6.0);
        cr.set_matrix(saved);
    }
}

/// The autumn theme's walkers (`DrawAnimal` on Windows). They are elves in everything but looks: they walk, stop,
/// wave, cross to the next screen and meet to hand over what they carry. A hedgehog carries an apple on its spines,
/// a squirrel an acorn in its paws. Which animal a walker is follows its clothes, so it stays the same animal.
/// Drawn in the elf's frame: feet at (0, 0), y up is negative, facing right.
fn animal(cr: &cairo::Context, e: &Elf) {
    let pi = std::f64::consts::PI;
    let walking = e.state == ElfState::Walk;
    let waving = e.state == ElfState::Wave;
    let p = if walking { e.walk_phase as f64 } else { 0.0 };
    let stand_phase = if e.state == ElfState::Stand { e.t as f64 * 1.5 } else { 0.0 };
    let wave_phase = if waving { e.t as f64 * 11.0 } else { 0.0 };
    let dark = rgb(52, 36, 26);
    let round = |col: Argb, width: f64, x1: f64, y1: f64, x2: f64, y2: f64| {
        line(cr, col, width, LineCap::Round, x1, y1, x2, y2);
    };
    // a filled shape of curves: the start point, then two control points and the end per curve
    let fill_curves = |col: Argb, start: (f64, f64), xy: &[f64]| {
        cr.new_path();
        cr.move_to(start.0, start.1);
        for c in xy.chunks_exact(6) {
            cr.curve_to(c[0], c[1], c[2], c[3], c[4], c[5]);
        }
        cr.close_path();
        set(cr, col);
        let _ = cr.fill();
    };
    fill_ellipse(cr, (50, 60, 40, 20), -13.0, -2.0, 26.0, 4.0);
    let carrying = e.carries_gift && !waving;

    if TUNICS.iter().position(|t| *t == e.tunic).unwrap_or(0) % 2 == 0 {
        // ---- hedgehog
        let (spine, spine_dark, fur) = (rgb(104, 74, 50), rgb(70, 48, 32), rgb(216, 182, 142));
        let bob = if walking { -p.sin().abs() } else { 0.0 };
        // sniffing the air when it "waves"
        let sniff = if waving { -4.0 - wave_phase.sin() * 2.0 } else { stand_phase.sin() * 0.6 };
        for (fx, phase) in [(-10.0, 0.0), (-4.0, pi), (5.0, pi), (11.0, 0.0)] {
            let to = fx + if walking { (p + phase).sin() * 3.0 } else { 0.0 };
            round(spine_dark, 3.6, fx, -5.0 + bob, to, 0.0);
        }
        cr.translate(0.0, bob);
        // the face: a tan cone ending in the nose
        fill_curves(
            fur,
            (4.0, -22.0),
            &[14.0, -22.0, 20.0, -14.0, 25.0, -7.0 + sniff, 22.0, -3.0, 14.0, -2.0, 4.0, -2.0],
        );
        // the spiny back
        fill_curves(
            spine,
            (-19.0, -2.0),
            &[-22.0, -22.0, -6.0, -29.0, 6.0, -24.0, 12.0, -20.0, 12.0, -8.0, 8.0, -2.0],
        );
        for i in 0..10 {
            let a = pi * (1.02 - 0.84 * i as f64 / 9.0);
            let (bx, by) = (-5.0 + a.cos() * 15.0, -11.0 - a.sin() * 15.0);
            round(spine_dark, 1.8, bx, by, bx + a.cos() * 6.0, by - a.sin() * 6.0);
        }
        for i in 0..6 {
            let a = pi * (0.9 - 0.7 * i as f64 / 5.0);
            let (bx, by) = (-5.0 + a.cos() * 8.0, -9.0 - a.sin() * 8.0);
            round(spine_dark, 1.4, bx, by, bx + a.cos() * 5.0, by - a.sin() * 5.0);
        }
        fill_ellipse(cr, spine, 6.0, -22.0, 6.0, 6.0); // ear
        fill_ellipse(cr, dark, 14.0, -15.0 + sniff * 0.4, 3.2, 3.2); // eye
        fill_ellipse(cr, dark, 22.5, -9.5 + sniff, 4.5, 4.5); // nose
        if carrying {
            // an apple stuck on the spines
            let apples = [rgb(206, 48, 44), rgb(196, 176, 52), rgb(222, 120, 40)];
            let which = GIFTS.iter().position(|g| *g == e.gift).unwrap_or(0) % 3;
            fill_ellipse(cr, apples[which], -11.0, -41.0, 13.0, 12.0);
            round(spine_dark, 1.6, -4.5, -41.0, -3.5, -45.0);
            fill_ellipse(cr, rgb(88, 150, 60), -3.5, -47.0, 6.0, 3.5);
            fill_ellipse(cr, (120, 255, 255, 255), -8.5, -39.0, 3.0, 3.0);
        }
    } else {
        // ---- squirrel
        let (rust, rust_dark, cream) = (rgb(192, 94, 46), rgb(150, 66, 30), rgb(242, 222, 190));
        let bob = if walking { -p.sin().abs() * 3.0 } else { 0.0 };
        let flick = if walking {
            (p * 0.5).sin() * 2.0
        } else {
            stand_phase.sin() * 1.5 + if waving { wave_phase.sin() * 3.0 } else { 0.0 }
        };
        cr.translate(0.0, bob);
        // the bushy tail, curling up behind the back
        fill_curves(
            rust,
            (-7.0, -5.0),
            &[
                -31.0,
                -6.0,
                -33.0 + flick,
                -38.0,
                -16.0 + flick,
                -47.0,
                -7.0 + flick,
                -51.0,
                -1.0 + flick,
                -41.0,
                -8.0,
                -35.0,
                -17.0,
                -28.0,
                -13.0,
                -15.0,
                -5.0,
                -9.0,
            ],
        );
        round(rust_dark, 1.4, -18.0 + flick * 0.6, -40.0, -22.0, -20.0);
        // hind leg and foot
        let step = if walking { p.sin() * 3.0 } else { 0.0 };
        fill_ellipse(cr, rust_dark, -7.0, -11.0, 15.0, 10.0);
        round(rust_dark, 4.0, 1.0, -3.0, 8.0 + step, -1.0);
        // body and belly
        fill_ellipse(cr, rust, -9.0, -30.0, 17.0, 27.0);
        fill_ellipse(cr, cream, -1.0, -25.0, 8.0, 19.0);
        // head, ear, eye, nose
        fill_ellipse(cr, rust, 0.0, -43.0, 16.0, 14.0);
        fill_polygon(cr, rust_dark, &[(3.0, -41.0), (5.0, -51.0), (10.0, -42.0)]);
        fill_ellipse(cr, cream, 9.0, -36.0, 7.0, 6.0);
        fill_ellipse(cr, dark, 9.5, -39.0, 3.0, 3.0);
        fill_ellipse(cr, dark, 15.0, -35.0, 2.6, 2.6);
        // the front paw: holding the acorn, waving, or swinging
        let (hand_x, hand_y) = if waving {
            (11.0, -37.0 + wave_phase.sin() * 3.0)
        } else if e.carries_gift {
            (11.0, -24.0)
        } else {
            (9.0 + if walking { p.sin() * 2.0 } else { 0.0 }, -20.0)
        };
        if carrying {
            let cup = rgb(104, 70, 34);
            fill_ellipse(cr, rgb(176, 128, 66), 9.0, -27.0, 8.0, 10.0);
            fill_ellipse(cr, cup, 8.5, -29.0, 9.0, 5.0);
            round(cup, 1.4, 13.0, -29.0, 13.0, -31.5);
        }
        round(rust_dark, 3.4, 3.0, -25.0, hand_x, hand_y);
    }
}

/// `JULE_ELF_SECONDS=N` (the Windows name `JULE_NISSE_SECONDS` works too): an elf arrives or leaves every N
/// seconds, for testing.
fn elf_seconds() -> Option<f32> {
    ["JULE_ELF_SECONDS", "JULE_NISSE_SECONDS"]
        .iter()
        .find_map(|k| std::env::var(k).ok()?.trim().parse::<f32>().ok())
        .filter(|v| *v > 0.0)
}
