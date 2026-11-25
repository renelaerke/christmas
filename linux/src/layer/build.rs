//! The snowman the children build in the Christmas theme (`snowman_build.rs` has the story), on the primary
//! screen: the balls, what the snowman wears, the three children and their snowballs, and the chunks of snow when
//! the plow runs it down. Ported from `src/LayerSnowman.cs`.
//!
//! Windows draws these before the snow pile, which then covers their feet. Here the pile is a cached image drawn
//! first (`ground.rs`), so they are drawn after it and cut off along the pile's top instead, which looks the
//! same. (The shadows Windows draws under the bottom ball and the children lie below that line and are never
//! seen, so they are left out.) Everything is drawn again each frame and registered with `mark()`, as the elves
//! are.

use std::f64::consts::PI;

use cairo::{Context, LineCap};

use super::draw::*;
use super::plow::PlowBit;
use super::{heap_at, snowman, Layer, SceneState, HEAP_STEP};
use crate::snowman_build::{Ball, Kid, Pose, HEAD_R, HEAD_Y, MIDDLE_Y, PLAY_HALF_WIDTH};

/// A child's clothes: jacket, trousers, knitted hat, its pompom, mittens, and a scarf (or none).
struct Clothes {
    jacket: Argb,
    trousers: Argb,
    hat: Argb,
    pompom: Argb,
    mittens: Argb,
    scarf: Option<Argb>,
}

static KID_CLOTHES: [Clothes; 3] = [
    Clothes {
        jacket: rgb(205, 50, 45),
        trousers: rgb(45, 65, 120),
        hat: rgb(240, 240, 245),
        pompom: rgb(205, 40, 45),
        mittens: rgb(45, 65, 120),
        scarf: Some(rgb(245, 190, 45)),
    },
    Clothes {
        jacket: rgb(45, 125, 195),
        trousers: rgb(55, 55, 65),
        hat: rgb(245, 185, 40),
        pompom: WHITE,
        mittens: rgb(245, 185, 40),
        scarf: None,
    },
    Clothes {
        jacket: rgb(90, 170, 100),
        trousers: rgb(75, 150, 90),
        hat: rgb(225, 90, 150),
        pompom: WHITE,
        mittens: rgb(225, 90, 150),
        scarf: None,
    },
];

impl Layer {
    /// Where the children build and play, in this screen's pixels (only on the primary screen, while they do).
    pub(super) fn play_zone(&self, st: &SceneState) -> Option<(f32, f32)> {
        let b = st.build.filter(|b| self.primary && b.playing())?;
        Some(((b.site_x - PLAY_HALF_WIDTH) * self.s, (b.site_x + PLAY_HALF_WIDTH) * self.s))
    }

    fn build_ground(&self, x: f32) -> f32 {
        self.ground_y - heap_at(&self.heap, x.clamp(0.0, self.w as f32 - 1.0)) + 2.0 * self.s
    }

    /// The plow's blade has reached the snowman (this frame): it flies apart in chunks of snow.
    pub(super) fn update_build(&mut self, st: &SceneState) {
        let Some(b) = st.build.filter(|b| self.primary && !b.run_down.is_empty()) else { return };
        let s = self.s;
        let dir = st.plow.map_or(1.0, |p| p.dir);
        for &(x, y, r) in &b.run_down {
            let bx = x * s;
            let by = self.build_ground(bx) - y * s;
            for _ in 0..4 + (r * 1.6) as i32 {
                let rg = &mut self.rng;
                self.plow_bits.push(PlowBit::chunk(
                    bx + (rg.f() - 0.5) * r * s,
                    by + (rg.f() - 0.5) * r * s,
                    dir * (60.0 + rg.f() * 150.0) * s,
                    -(70.0 + rg.f() * 170.0) * s,
                    (1.5 + rg.f() * 3.0) * s,
                ));
            }
        }
    }

    pub(super) fn draw_build(&mut self, st: &SceneState) {
        let Some(b) = st.build.filter(|_| self.primary) else { return };
        let s = self.s;
        let sx = b.site_x * s;
        let gy = self.build_ground(sx);
        self.snowman_pos = Some((self.rect.x as f32 + sx, self.rect.y as f32 + gy));

        // what is drawn this frame, as boxes: registered with mark(), and their span is what the clip covers
        let mut boxes: Vec<(f32, f32, f32, f32)> = Vec::new();
        for ball in b.balls.iter().filter(|ball| ball.present) {
            let bx = ball.x * s;
            let by = self.build_ground(bx) - ball.y * s;
            let r = ball.r;
            boxes.push((bx - (r + 2.0) * s, by - (r + 2.0) * s, (2.0 * r + 4.0) * s, (2.0 * r + 6.0) * s));
        }
        if b.dressed > 0 {
            boxes.push((sx - 30.0 * s, gy - 74.0 * s, 60.0 * s, 78.0 * s));
        }
        for k in &b.kids {
            let ks = s * k.size;
            let x = k.x * s;
            let ground = self.build_ground(x);
            let top = ground - k.lift * s - 60.0 * ks;
            boxes.push((x - 24.0 * ks, top, 48.0 * ks, ground + 6.0 * ks - top));
        }
        for sb in &b.snowballs {
            let x = sb.x * s;
            let y = self.build_ground(x) - sb.y * s;
            let reach = 14.0 * s;
            boxes.push((x - reach, y - reach, 2.0 * reach, 2.0 * reach));
        }
        if boxes.is_empty() {
            return;
        }
        let (mut x0, mut x1) = (f32::MAX, f32::MIN);
        for &(x, y, w, h) in &boxes {
            self.mark(x, y, w, h);
            x0 = x0.min(x);
            x1 = x1.max(x + w);
        }
        let (x0, x1) = (x0.max(0.0) - 4.0, x1.min(self.w as f32) + 4.0);

        let cr = &self.canvas.cr;
        cr.save().ok();
        // Everything stands in the snow: cut off along the pile's top (just above it, so its outline stays), and
        // at the ground line when there is no pile.
        let keep = 0.75 * s;
        let i0 = (x0.max(0.0) / HEAP_STEP as f32) as usize;
        let i1 = ((x1.max(0.0) / HEAP_STEP as f32) as usize + 1).min(self.heap.len() - 1);
        cr.new_path();
        cr.move_to(x0 as f64, -10.0);
        cr.line_to(x1 as f64, -10.0);
        cr.line_to(x1 as f64, (self.ground_y - self.heap[i1] - keep) as f64);
        for i in (i0.min(i1)..=i1).rev() {
            cr.line_to((i * HEAP_STEP) as f64, (self.ground_y - self.heap[i] - keep) as f64);
        }
        cr.line_to(x0 as f64, (self.ground_y - self.heap[i0.min(i1)] - keep) as f64);
        cr.close_path();
        cr.clip();

        for ball in b.balls.iter().filter(|ball| ball.present) {
            let bx = ball.x * s;
            build_ball(cr, ball, bx as f64, (self.build_ground(bx) - ball.y * s) as f64, s as f64);
        }
        if b.dressed > 0 {
            snowman_dress(cr, b.dressed, sx as f64, gy as f64, s as f64);
        }
        for k in &b.kids {
            let x = k.x * s;
            kid(cr, k, x as f64, (self.build_ground(x) - k.lift * s) as f64, (s * k.size) as f64);
        }
        for sb in &b.snowballs {
            let x = sb.x * s;
            let (x, y, s) = (x as f64, (self.build_ground(x) - sb.y * s) as f64, s as f64);
            if sb.life < 0.0 {
                let r = 1.9 * s;
                fill_ellipse(cr, (250, 250, 252, 255), x - r, y - r, 2.0 * r, 2.0 * r);
                draw_ellipse(cr, (110, 150, 175, 205), 0.8, x - r, y - r, 2.0 * r, 2.0 * r);
            } else {
                // it bursts into a little puff
                let (spread, d) = ((0.5 - sb.life as f64) * 18.0 * s, 1.1 * s);
                for i in 0..6 {
                    let a = i as f64 * PI / 3.0 + 0.4;
                    fill_ellipse(
                        cr,
                        (250, 250, 252, 255),
                        x + a.cos() * spread - d,
                        y - a.sin().abs() * spread - d,
                        2.0 * d,
                        2.0 * d,
                    );
                }
            }
        }
        cr.restore().ok();
    }
}

/// One of the snowman's balls where it is now, with two lumps in the snow that turn with it, so it can be seen
/// rolling.
fn build_ball(cr: &Context, ball: &Ball, bx: f64, by: f64, s: f64) {
    let saved = cr.matrix();
    cr.translate(bx, by);
    cr.scale(s, s);
    let r = ball.r as f64;
    snowman::ball(cr, 0.0, 0.0, r);
    for i in 0..2 {
        let a = ball.roll as f64 + i as f64 * 2.6;
        let lr = r * if i == 0 { 0.55 } else { 0.35 };
        let d = (r * 0.12).max(0.8);
        fill_ellipse(cr, (70, 150, 170, 200), a.cos() * lr - d, a.sin() * lr - d, 2.0 * d, 2.0 * d);
    }
    cr.set_matrix(saved);
}

/// The upper half of a disc: a knitted hat's dome (GDI+ `FillPie` from 180° over 180°).
fn dome(cr: &Context, c: Argb, cx: f64, cy: f64, r: f64) {
    cr.new_path();
    cr.arc(cx, cy, r, PI, 2.0 * PI);
    cr.close_path();
    set(cr, c);
    let _ = cr.fill();
}

/// What the children put on the finished stack, in order. The snowman looks to the right.
fn snowman_dress(cr: &Context, n: i32, sx: f64, gy: f64, s: f64) {
    let saved = cr.matrix();
    cr.translate(sx, gy);
    cr.scale(s, s);
    let (my, hy) = (-(MIDDLE_Y as f64), -(HEAD_Y as f64));
    let coal = rgb(35, 35, 40);
    if n >= 4 {
        let wood = rgb(110, 70, 35);
        line(cr, wood, 1.6, LineCap::Round, -8.0, my - 3.0, -21.0, my - 12.0);
        line(cr, wood, 1.6, LineCap::Round, -17.0, my - 9.5, -18.0, my - 15.0);
        line(cr, wood, 1.6, LineCap::Round, 8.0, my - 3.0, 21.0, my - 10.0);
        line(cr, wood, 1.6, LineCap::Round, 17.0, my - 7.5, 20.0, my - 13.0);
    }
    if n >= 1 {
        fill_ellipse(cr, coal, 0.3, hy - 3.2, 2.2, 2.2);
        fill_ellipse(cr, coal, 4.3, hy - 3.2, 2.2, 2.2);
    }
    if n >= 2 {
        fill_polygon(cr, rgb(240, 130, 30), &[(3.0, hy - 0.8), (12.0, hy + 0.2), (3.0, hy + 1.2)]);
    }
    if n >= 3 {
        for i in 0..3 {
            fill_ellipse(cr, coal, 0.2, my - 5.8 + i as f64 * 4.6, 2.4, 2.4);
        }
    }
    if n >= 5 {
        for i in 0..4 {
            let x = 0.5 + i as f64 * 1.7;
            let y = hy + 3.6 + 0.5 * (1.0 - (i as f64 - 1.5).abs() / 1.5);
            fill_ellipse(cr, coal, x - 0.6, y - 0.6, 1.2, 1.2);
        }
    }
    if n >= 6 {
        let ny = hy + HEAD_R as f64 - 1.5;
        let scarf = rgb(200, 30, 40);
        fill_rect(cr, scarf, -7.5, ny, 15.0, 3.4);
        fill_polygon(cr, scarf, &[(-5.0, ny + 2.0), (-1.5, ny + 2.0), (-2.5, ny + 11.0), (-6.5, ny + 10.5)]);
        line(cr, WHITE, 1.0, LineCap::Butt, -5.5, ny + 6.0, -2.0, ny + 6.0);
        line(cr, WHITE, 1.0, LineCap::Butt, -6.0, ny + 8.5, -2.3, ny + 8.5);
    }
    if n >= 7 {
        // a green knitted hat with a pompom
        let top = hy - HEAD_R as f64;
        dome(cr, rgb(40, 140, 70), 0.0, top + 0.8, 6.8);
        fill_rect(cr, rgb(25, 105, 50), -7.3, top - 0.2, 14.6, 2.8);
        fill_ellipse(cr, WHITE, -2.4, top - 8.4, 4.8, 4.8);
    }
    cr.set_matrix(saved);
}

/// One child with its feet at (x, gy), `ks` pixels to the unit. Drawn facing right; y up is negative.
fn kid(cr: &Context, k: &Kid, x: f64, gy: f64, ks: f64) {
    let c = &KID_CLOTHES[k.look % KID_CLOTHES.len()];
    let saved = cr.matrix();
    cr.translate(x, gy);
    cr.scale(if k.dir < 0.0 { -ks } else { ks }, ks);

    let pose = k.pose;
    let (phase, t, throw_t) = (k.walk_phase as f64, k.t as f64, k.throw_t as f64);
    let walking = pose == Pose::Walk || pose == Pose::Push;
    let leg_a = if walking { phase.sin() * 0.5 } else { 0.0 };
    let bob = if pose == Pose::Walk { -phase.sin().abs() * 1.2 } else { 0.0 };
    let squat = pose == Pose::Pat;
    if pose == Pose::Push {
        cr.rotate(12f64.to_radians()); // leaning into the ball
    }

    let boot = rgb(50, 40, 35);
    let leg = |hx: f64, hy: f64, a: f64| {
        let (fx, fy) = (hx + a.sin() * 11.0, hy + a.cos() * 11.0);
        line(cr, c.trousers, 5.0, LineCap::Round, hx, hy, fx, fy);
        fill_ellipse(cr, boot, fx - 3.0, fy - 2.0, 8.0, 4.5);
    };
    if squat {
        // knees forward, bottom down
        line(cr, c.trousers, 5.0, LineCap::Round, -2.0, -8.0, 4.0, -9.0);
        line(cr, c.trousers, 5.0, LineCap::Round, 4.0, -9.0, 3.0, -1.5);
        fill_ellipse(cr, boot, 1.0, -3.0, 8.0, 4.5);
        line(cr, c.trousers, 5.0, LineCap::Round, 1.0, -8.0, -1.0, -1.5);
        fill_ellipse(cr, boot, -3.0, -3.0, 8.0, 4.5);
    } else {
        leg(-1.8, -14.0 + bob, leg_a);
        leg(1.8, -14.0 + bob, -leg_a);
    }

    cr.translate(0.0, if squat { 7.0 } else { bob });
    let (back, front) = match pose {
        Pose::Wave => (0.15, 2.5 + (t * 11.0).sin() * 0.45),
        Pose::Push => (1.45, 1.6),
        Pose::Lift => (2.55, 2.7),
        Pose::Pat => (1.1, 1.3 + (t * 9.0).sin() * 0.3),
        Pose::Jump => (2.7 + (t * 6.0).sin() * 0.2, 2.85 - (t * 6.0).sin() * 0.2),
        // wound up behind the head, then the swing
        Pose::Throw => (0.6, if throw_t < 0.3 { -2.4 } else { -2.4 + ((throw_t - 0.3) / 0.15).min(1.0) * 4.1 }),
        Pose::Sad => (0.05, 0.05),
        Pose::Walk => (-leg_a * 0.9, leg_a * 0.9),
        Pose::Stand => (0.2, 0.1),
    };
    let arm = |sx: f64, sy: f64, a: f64| {
        let (hx, hy) = (sx + a.sin() * 9.0, sy + a.cos() * 9.0);
        line(cr, c.jacket, 4.2, LineCap::Round, sx, sy, hx, hy);
        fill_ellipse(cr, c.mittens, hx - 2.4, hy - 2.4, 4.8, 4.8);
    };

    arm(-1.0, -25.0, back);
    fill_ellipse(cr, c.jacket, -8.5, -31.0, 17.0, 18.0);
    line(cr, (90, 0, 0, 0), 0.8, LineCap::Butt, 4.5, -29.0, 5.0, -15.0);

    fill_ellipse(cr, SKIN, -5.5, -42.0, 11.0, 11.0);
    fill_ellipse(cr, (150, 240, 140, 140), 1.2, -35.5, 3.0, 2.4);
    let eye = rgb(45, 40, 40);
    if pose == Pose::Sad {
        fill_rect(cr, eye, 2.2, -37.0, 2.0, 0.8);
    } else {
        fill_ellipse(cr, eye, 2.4, -37.6, 1.6, 1.6);
    }
    if let Some(scarf) = c.scarf {
        fill_rect(cr, scarf, -5.0, -32.0, 10.0, 3.0);
        fill_polygon(cr, scarf, &[(-5.0, -31.0), (-2.5, -31.0), (-5.5, -23.0), (-8.0, -24.0)]);
    }

    dome(cr, c.hat, 0.0, -41.5, 6.0);
    fill_rect(cr, c.hat, -6.3, -42.0, 12.6, 3.0);
    line(cr, (50, 0, 0, 0), 0.7, LineCap::Butt, -6.3, -40.5, 6.3, -40.5);
    fill_ellipse(cr, c.pompom, -2.2, -50.0, 4.4, 4.4);
    arm(1.0, -25.0, front);
    cr.set_matrix(saved);
}
