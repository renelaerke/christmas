//! Halloween (setting `Theme` = 3), as in the macOS version (`OverlayHalloween.swift`) and the Windows one
//! (`src/LayerHalloween.cs`): each Christmas element has its Halloween form. Autumn's leaves fall and pile up as
//! they are. Here are the jack-o'-lanterns that stand in the snowman's place, the witch on her broom that flies in
//! Santa's, the ghosts and children dressed up for trick or treat that walk in the nisser's, the string of pumpkin
//! lanterns and bats that hangs in the lights', the cats and spiders on the window edges, and the two forms of the
//! plow: a witch who sweeps the leaves up, or ghosts who blow them away. The drawing is kept line for line the same
//! as in the other two versions. All figures are original.

use cairo::{Context, LineCap};

use super::draw::*;
use super::muertos::{bezier, c, fill_with, flat, glow, quad_to, round, shade};
use super::{Layer, SceneState, LEAF_COLOURS};
use crate::figures::DONKEY_STRIDE;

const PUMPKIN: [Argb; 3] = [rgb(255, 122, 26), rgb(224, 106, 18), rgb(217, 84, 30)];
const NIGHT: Argb = rgb(23, 21, 29);
const CANDLE_LIGHT: Argb = rgb(255, 224, 138);
const PI: f64 = std::f64::consts::PI;

// ---------------------------------------------------------------------- small things the figures share
/// One pumpkin standing on the ground at x = `cx`, `r` wide to each side: ribbed, with a stalk, and when carved a
/// face (eyes from `face` 1, the mouth too from 2) that is dark until a candle is lit inside it.
fn pumpkin(cr: &Context, cx: f64, r: f64, colour: Argb, stalk: bool, face: i32, lit: bool) {
    let ry = r * 0.82;
    let cy = -ry;
    if lit {
        glow(cr, c(255, 179, 71, 90), cx, cy, r * 1.9);
    }
    fill_ellipse(cr, shade(colour, 0.72), cx - r, cy - ry, 2.0 * r, 2.0 * ry);
    // the ribs: lighter lobes from the middle out
    fill_ellipse(cr, shade(colour, 0.88), cx - r * 0.86, cy - ry * 0.97, r * 1.72, ry * 1.94);
    fill_ellipse(cr, colour, cx - r * 0.58, cy - ry, r * 1.16, 2.0 * ry);
    draw_ellipse(cr, shade(colour, 0.6), (r * 0.035).max(0.8), cx - r * 0.28, cy - ry, r * 0.56, 2.0 * ry);
    if stalk {
        cr.new_path();
        cr.move_to(cx - r * 0.1, cy - ry * 0.92);
        cr.curve_to(cx - r * 0.1, cy - ry * 1.2, cx + r * 0.05, cy - ry * 1.3, cx + r * 0.26, cy - ry * 1.34);
        cr.line_to(cx + r * 0.3, cy - ry * 1.2);
        cr.curve_to(cx + r * 0.16, cy - ry * 1.18, cx + r * 0.12, cy - ry * 1.05, cx + r * 0.12, cy - ry * 0.92);
        cr.close_path();
        fill_with(cr, rgb(72, 120, 48));
    }
    if face <= 0 {
        return;
    }
    let inside = if lit { CANDLE_LIGHT } else { rgb(58, 28, 8) };
    fill_polygon(cr, inside, &[(cx - r * 0.5, cy - ry * 0.08), (cx - r * 0.3, cy - ry * 0.48), (cx - r * 0.1, cy - ry * 0.08)]);
    fill_polygon(cr, inside, &[(cx + r * 0.1, cy - ry * 0.08), (cx + r * 0.3, cy - ry * 0.48), (cx + r * 0.5, cy - ry * 0.08)]);
    fill_polygon(cr, inside, &[(cx - r * 0.07, cy + ry * 0.2), (cx, cy + ry * 0.02), (cx + r * 0.07, cy + ry * 0.2)]);
    if face > 1 {
        // a wide grin with teeth left standing
        let (left, right) = ((cx - r * 0.58, cy + ry * 0.26), (cx + r * 0.58, cy + ry * 0.26));
        cr.new_path();
        cr.move_to(left.0, left.1);
        quad_to(cr, left, (cx, cy + ry * 0.5), right);
        quad_to(cr, right, (cx, cy + ry * 1.0), left);
        cr.close_path();
        fill_with(cr, inside);
        fill_rect(cr, colour, cx - 0.26 * r, cy + ry * 0.3, r * 0.14, ry * 0.16);
        fill_rect(cr, colour, cx + 0.2 * r, cy + ry * 0.3, r * 0.14, ry * 0.16);
        fill_rect(cr, colour, cx - r * 0.04, cy + ry * 0.56, r * 0.14, ry * 0.16);
    }
}

/// A small bat seen from the front, wings out: `flap` -1..1 lifts and lowers the wing tips.
fn bat(cr: &Context, x: f64, y: f64, size: f64, flap: f64) {
    let saved = cr.matrix();
    cr.translate(x, y);
    cr.scale(size, size);
    let lift = flap * 7.0;
    for side in [-1.0, 1.0] {
        cr.new_path();
        cr.move_to(side * 2.0, -1.0);
        cr.curve_to(side * 8.0, -8.0 - lift, side * 15.0, -7.0 - lift, side * 20.0, -1.0 - lift);
        // the scalloped trailing edge
        let (p0, p1, p2, p3) = (
            (side * 20.0, -1.0 - lift),
            (side * 14.0, 2.0 - lift * 0.6),
            (side * 8.0, 4.0 - lift * 0.3),
            (side * 2.0, 4.0),
        );
        quad_to(cr, p0, (side * 17.0, -2.0 - lift * 0.7), p1);
        quad_to(cr, p1, (side * 11.0, -lift * 0.4), p2);
        quad_to(cr, p2, (side * 5.0, 1.0), p3);
        cr.close_path();
        fill_with(cr, NIGHT);
    }
    fill_ellipse(cr, NIGHT, -3.0, -4.0, 6.0, 9.0);
    fill_polygon(cr, NIGHT, &[(-2.6, -3.0), (-2.2, -7.5), (-0.4, -4.0)]);
    fill_polygon(cr, NIGHT, &[(2.6, -3.0), (2.2, -7.5), (0.4, -4.0)]);
    fill_ellipse(cr, rgb(255, 210, 90), -1.9, -2.6, 1.3, 1.3);
    fill_ellipse(cr, rgb(255, 210, 90), 0.6, -2.6, 1.3, 1.3);
    cr.set_matrix(saved);
}

/// A black cat sitting, looking at us, its tail curled to the right (`tail` -1..1 swings its tip). Sits on y = 0,
/// about 26 high, centred on x = 0.
fn cat(cr: &Context, tail: f64, eyes_open: bool) {
    let black = NIGHT;
    bezier(cr, black, 3.0, [8.0, -3.0, 20.0, -2.0, 20.0 + tail * 3.0, -14.0, 14.0 + tail * 5.0, -19.0]);
    // haunches, chest and head
    fill_ellipse(cr, black, -9.0, -13.0, 20.0, 13.0);
    cr.new_path();
    cr.move_to(-8.0, -1.0);
    cr.curve_to(-10.0, -12.0, -7.0, -19.0, -3.0, -21.0);
    cr.line_to(4.0, -21.0);
    cr.curve_to(8.0, -15.0, 9.0, -8.0, 8.0, -1.0);
    cr.close_path();
    fill_with(cr, black);
    fill_ellipse(cr, black, -8.0, -29.0, 15.0, 13.0);
    fill_polygon(cr, black, &[(-7.5, -24.0), (-7.0, -33.0), (-2.0, -28.0)]);
    fill_polygon(cr, black, &[(6.5, -24.0), (6.0, -33.0), (1.0, -28.0)]);
    fill_ellipse(cr, black, -8.0, -3.0, 6.0, 3.4);
    fill_ellipse(cr, black, 1.0, -3.0, 6.0, 3.4);
    let yellow = rgb(255, 214, 64);
    if eyes_open {
        for dx in [-4.2, 1.2] {
            fill_ellipse(cr, yellow, dx, -24.5, 3.2, 2.6);
            fill_rect(cr, black, dx + 1.3, -24.5, 0.7, 2.6);
        }
    } else {
        flat(cr, yellow, 0.7, -4.0, -23.2, -1.2, -23.2);
        flat(cr, yellow, 0.7, 1.4, -23.2, 4.2, -23.2);
    }
}

// ---------------------------------------------------------------------- the jack-o'-lanterns
/// Halloween's form of the snowman: three pumpkins put out and carved into jack-o'-lanterns, a step for every hour
/// the app runs (see the controller), in the same place and box as the snowman. Origin at the ground, y up is
/// negative.
pub(super) fn pumpkins(cr: &Context, stage: i32) {
    fill_ellipse(cr, c(20, 12, 8, 60), -60.0, -3.0, 120.0, 6.0);
    let stalks = stage >= 4;
    // the curling vine behind them (stage 4)
    if stalks {
        bezier(cr, rgb(72, 120, 48), 1.6, [-30.0, -30.0, -24.0, -52.0, -8.0, -40.0, -14.0, -56.0]);
        bezier(cr, rgb(72, 120, 48), 1.6, [30.0, -26.0, 40.0, -44.0, 22.0, -44.0, 30.0, -54.0]);
        fill_ellipse(cr, rgb(86, 138, 56), -22.0, -50.0, 9.0, 6.0);
    }
    if stage >= 1 {
        pumpkin(cr, -38.0, 20.0, PUMPKIN[1], stalks, if stage >= 8 { 2 } else { 0 }, stage >= 10);
    }
    if stage >= 2 {
        pumpkin(cr, 38.0, 18.0, PUMPKIN[2], stalks, if stage >= 9 { 2 } else { 0 }, stage >= 10);
    }
    if stage >= 3 {
        let face = if stage >= 6 {
            2
        } else if stage >= 5 {
            1
        } else {
            0
        };
        pumpkin(cr, 0.0, 32.0, PUMPKIN[0], stalks, face, stage >= 7);
    }
    // a witch's hat on the right pumpkin (stage 11)
    if stage >= 11 {
        let saved = cr.matrix();
        cr.translate(40.0, -29.0);
        cr.rotate(0.22);
        fill_ellipse(cr, NIGHT, -15.0, -3.0, 30.0, 7.0);
        fill_polygon(cr, NIGHT, &[(-8.0, -1.0), (2.0, -30.0), (8.0, -1.0)]);
        fill_rect(cr, rgb(123, 44, 191), -7.4, -5.5, 14.8, 3.0);
        fill_rect(cr, rgb(255, 210, 63), -2.0, -6.0, 4.0, 4.0);
        cr.set_matrix(saved);
    }
    // a black cat on the left pumpkin (stage 12)
    if stage >= 12 {
        let saved = cr.matrix();
        cr.translate(-40.0, -31.0);
        cr.scale(0.9, 0.9);
        cat(cr, 0.3, true);
        cr.set_matrix(saved);
    }
}

// ---------------------------------------------------------------------- ghosts and children dressed up
/// How a walker stands: what `elves.rs` works out from the elf it draws.
#[derive(Clone, Copy)]
pub(super) struct SpookPose {
    /// Which of them it is (the elf's tunic number): even a ghost, odd a child dressed up.
    pub tunic: usize,
    pub walking: bool,
    pub waving: bool,
    pub carries_gift: bool,
    /// The step's phase while walking, and the phases of standing and waving (0 when not).
    pub walk: f64,
    pub stand: f64,
    pub wave: f64,
}

/// Halloween's walkers. They are nisser in everything but looks: they walk, stop, wave, cross to the next screen
/// and meet to hand something over (a bucket of sweets). Every other one is a ghost under a sheet, floating a
/// little above the ground; the others are children dressed up for trick or treat, a small witch or a small
/// pumpkin. Drawn like a nisse: feet at (0, 0), y up is negative, facing right.
pub(super) fn spook(cr: &Context, pose: SpookPose) {
    if pose.tunic % 2 == 0 {
        ghost(cr, pose);
    } else {
        treater(cr, pose);
    }
}

/// The bucket of sweets a walker carries: a small pumpkin pail with a handle.
fn sweet_bucket(cr: &Context, x: f64, y: f64) {
    bezier(cr, rgb(60, 40, 30), 1.0, [x - 4.0, y - 6.0, x - 3.0, y - 11.0, x + 3.0, y - 11.0, x + 4.0, y - 6.0]);
    fill_ellipse(cr, PUMPKIN[0], x - 5.5, y - 7.0, 11.0, 9.0);
    fill_polygon(cr, rgb(58, 28, 8), &[(x - 3.0, y - 3.4), (x - 1.8, y - 5.2), (x - 0.6, y - 3.4)]);
    fill_polygon(cr, rgb(58, 28, 8), &[(x + 0.6, y - 3.4), (x + 1.8, y - 5.2), (x + 3.0, y - 3.4)]);
    fill_ellipse(cr, rgb(233, 30, 99), x - 3.4, y - 9.2, 3.0, 3.0);
    fill_ellipse(cr, rgb(255, 210, 63), x + 0.2, y - 9.6, 3.0, 3.0);
}

fn ghost(cr: &Context, pose: SpookPose) {
    let (walking, waving) = (pose.walking, pose.waving);
    let p = if walking { pose.walk } else { 0.0 };
    // it floats: up and down as it goes, a little higher when it says boo
    let bob = if walking {
        p.sin() * 2.0
    } else if waving {
        -3.0 - pose.wave.sin().abs() * 2.0
    } else {
        pose.stand.sin() * 1.2
    };
    let hem = if walking { p } else { pose.stand };
    let sheet = if pose.tunic == 2 { rgb(236, 228, 250) } else { rgb(248, 250, 252) };
    let (fold, edge) = (c(196, 204, 226, 150), c(110, 120, 150, 190));
    fill_ellipse(cr, c(30, 20, 40, 45), -10.0, -2.0, 20.0, 4.0);
    let saved = cr.matrix();
    cr.translate(0.0, bob - 4.0);

    let arm = if waving { 0.9 + pose.wave.sin() * 0.25 } else { 0.25 };
    // the arms under the sheet: stubs out to the sides, up when it says boo
    for side in [-1.0, 1.0] {
        cr.new_path();
        cr.move_to(side * 8.0, -30.0);
        cr.curve_to(side * 14.0, -30.0 - arm * 4.0, side * 19.0, -28.0 - arm * 14.0, side * 18.0, -24.0 - arm * 16.0);
        cr.curve_to(side * 15.0, -20.0 - arm * 10.0, side * 12.0, -20.0, side * 8.0, -20.0);
        cr.close_path();
        set(cr, sheet);
        let _ = cr.fill_preserve();
        stroke(cr, edge, 1.0, LineCap::Butt);
    }
    cr.new_path();
    cr.move_to(-11.0, -4.0);
    cr.curve_to(-11.0, -20.0, -12.0, -46.0, 0.0, -46.0);
    cr.curve_to(12.0, -46.0, 11.0, -20.0, 11.0, -4.0);
    // the wavy hem, right to left
    let waves = 4;
    let mut at = (11.0, -4.0);
    for k in 0..waves {
        let x1 = 11.0 - 22.0 * (k + 1) as f64 / waves as f64;
        let xm = 11.0 - 22.0 * (k as f64 + 0.5) / waves as f64;
        let to = (x1, -4.0);
        quad_to(cr, at, (xm, 1.0 + (hem + k as f64 * 1.6).sin() * 2.0), to);
        at = to;
    }
    cr.close_path();
    set(cr, sheet);
    let _ = cr.fill_preserve();
    stroke(cr, edge, 1.0, LineCap::Butt);
    // a fold of shade down one side
    cr.new_path();
    cr.move_to(-10.2, -6.0);
    cr.curve_to(-10.4, -20.0, -11.0, -40.0, -3.0, -45.0);
    cr.curve_to(-8.0, -36.0, -7.0, -18.0, -7.0, -6.0);
    cr.close_path();
    fill_with(cr, fold);
    // the face: two dark eyes and a round mouth (wide open at boo)
    let ink = rgb(34, 30, 48);
    fill_ellipse(cr, ink, -3.2, -36.0, 4.0, 5.4);
    fill_ellipse(cr, ink, 3.4, -36.0, 4.0, 5.4);
    fill_ellipse(cr, ink, 0.6, -28.5, 3.4, if waving { 5.5 } else { 2.6 });

    if pose.carries_gift && !waving {
        sweet_bucket(cr, 15.0, -14.0);
    }
    cr.set_matrix(saved);
}

fn treater_arm(cr: &Context, sx: f64, sy: f64, a: f64, sleeve: Argb, skin: Argb) {
    let (hx, hy) = (sx + a.sin() * 10.0, sy + a.cos() * 10.0);
    round(cr, sleeve, 3.2, sx, sy, hx, hy);
    fill_ellipse(cr, skin, hx - 2.2, hy - 2.2, 4.4, 4.4);
}

fn treater(cr: &Context, pose: SpookPose) {
    let (walking, waving) = (pose.walking, pose.waving);
    let p = if walking { pose.walk } else { 0.0 };
    let leg_a = if walking { p.sin() * 0.55 } else { 0.0 };
    let bob = if walking {
        -p.sin().abs() * 1.5
    } else if waving {
        -pose.wave.sin().abs() * 2.0
    } else {
        0.0
    };
    let witch = pose.tunic % 4 == 1;
    let (ink, skin) = (rgb(34, 26, 40), rgb(255, 214, 186));
    fill_ellipse(cr, c(30, 20, 40, 50), -10.0, -2.0, 20.0, 4.0);

    // legs: striped stockings for the witch, green tights for the pumpkin
    let stocking = if witch { rgb(123, 44, 191) } else { rgb(72, 120, 48) };
    for (hx, a) in [(-2.0, leg_a), (2.0, -leg_a)] {
        let hip = -13.0 + bob;
        let (fx, fy) = (hx + a.sin() * 12.0, hip + a.cos() * 12.0);
        round(cr, stocking, 3.4, hx, hip, fx, fy);
        if witch {
            flat(cr, rgb(255, 152, 0), 3.4, hx + a.sin() * 4.0, hip + a.cos() * 4.0, hx + a.sin() * 7.0, hip + a.cos() * 7.0);
        }
        fill_ellipse(cr, ink, fx - 3.0, fy - 2.0, 8.0, 4.4);
    }

    let saved = cr.matrix();
    cr.translate(0.0, bob);
    let (back_arm, front_arm) = if waving {
        (-0.4 + pose.wave.sin() * 0.3, 2.6 + pose.wave.sin() * 0.5)
    } else if pose.carries_gift {
        (1.3, 1.3)
    } else {
        (-leg_a * 0.9, leg_a * 0.9)
    };
    let sleeve = if witch { rgb(40, 30, 54) } else { rgb(72, 120, 48) };
    treater_arm(cr, -1.0, -30.0, back_arm, sleeve, skin);

    if witch {
        // a dark dress flaring to the hem, with a purple sash
        cr.new_path();
        cr.move_to(-5.0, -32.0);
        cr.line_to(5.0, -32.0);
        cr.curve_to(7.0, -24.0, 10.0, -16.0, 11.0, -10.0);
        cr.line_to(-11.0, -10.0);
        cr.curve_to(-10.0, -16.0, -7.0, -24.0, -5.0, -32.0);
        cr.close_path();
        fill_with(cr, rgb(40, 30, 54));
        for k in 0..5 {
            let x = -11.0 + k as f64 * 4.4;
            fill_polygon(cr, rgb(40, 30, 54), &[(x, -10.0), (x + 2.2, -6.5), (x + 4.4, -10.0)]);
        }
        flat(cr, rgb(123, 44, 191), 1.6, -6.4, -22.0, 6.4, -22.0);
    } else {
        // a round pumpkin costume with ribs and a carved face
        fill_ellipse(cr, shade(PUMPKIN[0], 0.8), -11.0, -33.0, 22.0, 22.0);
        fill_ellipse(cr, PUMPKIN[0], -7.0, -33.0, 14.0, 22.0);
        draw_ellipse(cr, shade(PUMPKIN[0], 0.6), 0.8, -3.2, -33.0, 6.4, 22.0);
        fill_polygon(cr, ink, &[(-5.5, -22.0), (-3.5, -26.0), (-1.5, -22.0)]);
        fill_polygon(cr, ink, &[(1.5, -22.0), (3.5, -26.0), (5.5, -22.0)]);
        bezier(cr, ink, 1.4, [-5.0, -18.0, -2.0, -15.0, 2.0, -15.0, 5.0, -18.0]);
    }

    if pose.carries_gift && !waving {
        sweet_bucket(cr, 13.0, -17.0);
    }

    // the head, looking a little the way it walks
    let sway = (if walking { p * 0.5 } else { pose.stand }).sin() * 0.05;
    let body = cr.matrix();
    cr.translate(1.0, -39.0);
    cr.rotate(sway);
    fill_ellipse(cr, skin, -6.5, -6.5, 13.0, 13.0);
    fill_ellipse(cr, c(250, 170, 160, 150), 1.5, 0.2, 3.6, 2.6);
    fill_ellipse(cr, ink, 1.4, -2.4, 2.0, 2.6);
    fill_ellipse(cr, ink, 4.4, -2.4, 1.6, 2.4);
    bezier(cr, ink, 0.8, [1.6, 2.6, 3.0, 4.0, 4.4, 4.0, 5.4, 2.6]);
    if witch {
        // hair, and a pointed hat with a bent tip and a buckle
        fill_ellipse(cr, rgb(214, 110, 40), -8.0, -4.0, 6.0, 11.0);
        fill_ellipse(cr, ink, -11.0, -8.2, 22.0, 5.0);
        cr.new_path();
        cr.move_to(-6.0, -6.5);
        cr.curve_to(-4.0, -16.0, -1.0, -22.0, 5.0, -23.0);
        cr.curve_to(2.0, -19.0, 5.0, -12.0, 6.0, -6.5);
        cr.close_path();
        fill_with(cr, ink);
        fill_rect(cr, rgb(123, 44, 191), -5.6, -9.0, 11.4, 2.2);
        fill_rect(cr, rgb(255, 210, 63), -1.4, -9.4, 3.0, 3.0);
    } else {
        // the pumpkin's cap: a green stalk and two leaves
        fill_ellipse(cr, rgb(72, 120, 48), -6.8, -8.4, 13.6, 5.4);
        fill_rect(cr, rgb(60, 100, 40), -1.0, -12.6, 2.6, 5.0);
        fill_ellipse(cr, rgb(86, 138, 56), 1.0, -11.4, 6.0, 3.0);
    }
    cr.set_matrix(body);

    treater_arm(cr, 1.0, -30.0, front_arm, sleeve, skin);
    if waving {
        // waving a lollipop
        let (sa, ca) = (front_arm.sin(), front_arm.cos());
        let (hx, hy) = (1.0 + sa * 10.0, -30.0 + ca * 10.0);
        flat(cr, rgb(250, 250, 250), 1.0, hx, hy, hx + sa * 6.0, hy + ca * 6.0);
        fill_ellipse(cr, rgb(233, 30, 99), hx + sa * 8.0 - 3.0, hy + ca * 8.0 - 3.0, 6.0, 6.0);
        draw_ellipse(cr, c(255, 255, 255, 200), 0.8, hx + sa * 8.0 - 1.5, hy + ca * 8.0 - 1.5, 3.0, 3.0);
    }
    cr.set_matrix(saved);
}

// ---------------------------------------------------------------------- the witch on her broom
/// Halloween's flyer in Santa's place: a witch on her broom, flying toward +x, her cape and the broom's twigs
/// streaming behind, a cat riding at the back, and a handful of bats after her. Drawn in Santa's frame (translated
/// to his place and scaled by his size and direction); `t` is the trip's clock.
pub(super) fn witch(cr: &Context, t: f64) {
    // the bats: each beats its wings in its own time and wanders around its place behind her
    const PLACES: [(f64, f64, f64); 6] =
        [(-150.0, -46.0, 1.0), (-205.0, -8.0, 0.8), (-120.0, 30.0, 0.9), (-250.0, -58.0, 0.7), (-285.0, 16.0, 0.85), (-190.0, 52.0, 0.7)];
    for (i, (px, py, size)) in PLACES.into_iter().enumerate() {
        let fi = i as f64;
        bat(
            cr,
            px + (t * 1.1 + fi * 2.3).sin() * 10.0,
            py + (t * 1.7 + fi * 1.3).sin() * 9.0,
            size * 1.25,
            (t * (11.0 + fi) + fi * 2.0).sin(),
        );
    }
    let saved = cr.matrix();
    cr.translate(0.0, (t * 1.8).sin() * 5.0);
    cr.rotate(-0.06 + (t * 1.8 + 1.0).sin() * 0.03);
    let (ink, wood, skin) = (NIGHT, rgb(120, 80, 40), rgb(132, 178, 96));
    let flutter = (t * 9.0).sin();
    // the broom: the stick, and the twigs bound at the back, shaking in the wind
    for k in 0..7 {
        let a = (k as f64 - 3.0) * 0.09;
        let col = if k % 2 == 0 { rgb(214, 170, 72) } else { rgb(176, 132, 52) };
        round(cr, col, 2.2, -62.0, 2.0, -108.0, 2.0 + a * 46.0 + flutter * (k % 3 - 1) as f64 * 2.2);
    }
    fill_rect(cr, rgb(96, 60, 30), -66.0, -1.6, 6.0, 7.2);
    round(cr, wood, 3.6, -64.0, 2.0, 104.0, -5.0);
    // the cat riding at the back
    let rider = cr.matrix();
    cr.translate(-40.0, 0.0);
    cr.scale(0.8, 0.8);
    cat(cr, flutter * 0.6, true);
    cr.set_matrix(rider);
    // the cape streaming behind her
    let (c1, c2, c3) = ((-40.0, -30.0 + flutter * 5.0), (-30.0, -20.0 + flutter * 3.0), (-18.0, -12.0 + flutter * 2.0));
    cr.new_path();
    cr.move_to(18.0, -42.0);
    cr.curve_to(0.0, -44.0, -22.0, -40.0 + flutter * 3.0, c1.0, c1.1);
    quad_to(cr, c1, (-30.0, -26.0 + flutter * 4.0), c2);
    quad_to(cr, c2, (-20.0, -18.0 + flutter * 3.0), c3);
    cr.curve_to(0.0, -12.0, 12.0, -18.0, 22.0, -30.0);
    cr.close_path();
    fill_with(cr, rgb(74, 38, 110));
    // her leg forward along the stick: a striped stocking and a pointed shoe
    round(cr, rgb(123, 44, 191), 5.0, 26.0, -8.0, 52.0, -9.0);
    for k in 0..3 {
        let kf = k as f64;
        flat(cr, rgb(255, 152, 0), 5.0, 31.0 + kf * 7.0, -8.2 - kf * 0.3, 34.0 + kf * 7.0, -8.3 - kf * 0.3);
    }
    fill_polygon(cr, ink, &[(50.0, -13.0), (64.0, -11.0), (62.0, -6.0), (50.0, -5.0)]);
    // the dress, leaning forward over the stick
    cr.new_path();
    cr.move_to(14.0, -44.0);
    cr.curve_to(26.0, -46.0, 36.0, -36.0, 38.0, -22.0);
    cr.curve_to(36.0, -8.0, 22.0, -2.0, 10.0, -4.0);
    cr.curve_to(8.0, -18.0, 10.0, -34.0, 14.0, -44.0);
    cr.close_path();
    fill_with(cr, ink);
    // arms to the stick
    round(cr, ink, 4.0, 28.0, -36.0, 44.0, -14.0);
    fill_ellipse(cr, skin, 42.0, -15.0, 6.0, 6.0);
    // head, with a long nose and chin, and hair flying back
    let hair = rgb(214, 110, 40);
    bezier(cr, hair, 3.0, [22.0, -52.0, 8.0, -52.0, 0.0, -44.0 + flutter * 2.0, -8.0, -46.0 + flutter * 3.0]);
    bezier(cr, hair, 3.0, [22.0, -48.0, 10.0, -46.0, 4.0, -40.0 + flutter * 2.0, -4.0, -38.0 + flutter * 3.0]);
    fill_ellipse(cr, skin, 20.0, -60.0, 17.0, 17.0);
    fill_polygon(cr, skin, &[(35.0, -53.0), (44.0, -50.0), (35.0, -48.0)]);
    fill_polygon(cr, skin, &[(31.0, -46.0), (38.0, -42.0), (28.0, -43.0)]);
    fill_ellipse(cr, ink, 30.0, -55.0, 2.4, 2.8);
    bezier(cr, ink, 0.9, [31.0, -46.5, 33.0, -45.5, 35.0, -45.5, 36.0, -47.0]);
    // the pointed hat, its tip bent back
    let head = cr.matrix();
    cr.translate(27.0, -59.0);
    cr.rotate(-0.2);
    fill_ellipse(cr, ink, -17.0, -3.5, 34.0, 8.0);
    cr.new_path();
    cr.move_to(-9.0, -1.0);
    cr.curve_to(-7.0, -18.0, -6.0, -30.0, -16.0 + flutter * 1.5, -40.0);
    cr.curve_to(-2.0, -34.0, 6.0, -18.0, 9.0, -1.0);
    cr.close_path();
    fill_with(cr, ink);
    fill_rect(cr, rgb(123, 44, 191), -8.6, -6.4, 17.4, 3.4);
    fill_rect(cr, rgb(255, 210, 63), -2.4, -7.0, 4.8, 4.8);
    cr.set_matrix(head);
    cr.set_matrix(saved);
}

// ---------------------------------------------------------------------- the witch sweeps, or the ghosts blow
fn cat_leg(cr: &Context, hx: f64, a: f64) {
    let s = a.sin();
    round(cr, NIGHT, 3.2, hx, -16.0, hx + s * 6.0, -7.0);
    round(cr, NIGHT, 2.8, hx + s * 6.0, -7.0, hx + s * 8.0, 0.0);
}

/// Halloween has two forms of the snow plow, one or the other each run (`SceneState::ghosts_blow`). This is the
/// first: a small witch walks in front sweeping the leaves up with her broom; they fly back into a cauldron on a
/// cart that her black cat pulls. Facing +x, origin at the ground, the broom where the plow's blade would be.
/// `ph` is the height of what is gathered in front, `step` the wheel's turn.
pub(super) fn witch_sweeper(cr: &Context, ph: f64, step: f64) {
    let stride = DONKEY_STRIDE as f64;
    let (ink, wood, wood_dark) = (NIGHT, rgb(120, 80, 40), rgb(84, 54, 28));
    // the cart: a flat bed on two small wheels, and on it the cauldron heaped with leaves
    for (i, lx) in [-90.0, -80.0, -70.0, -60.0, -50.0].into_iter().enumerate() {
        let odd = (i % 2) as f64;
        fill_ellipse(cr, LEAF_COLOURS[(i * 2) % LEAF_COLOURS.len()], lx - 8.0, -66.0 + odd * 4.0, 17.0, 12.0);
        fill_ellipse(cr, LEAF_COLOURS[(i * 2 + 1) % LEAF_COLOURS.len()], lx - 2.0, -60.0 - odd * 3.0, 15.0, 11.0);
    }
    fill_ellipse(cr, ink, -98.0, -62.0, 56.0, 46.0);
    fill_ellipse(cr, rgb(52, 48, 62), -92.0, -58.0, 18.0, 30.0);
    fill_ellipse(cr, rgb(64, 60, 76), -100.0, -62.0, 60.0, 10.0);
    fill_ellipse(cr, ink, -96.0, -60.5, 52.0, 6.0);
    fill_rect(cr, wood_dark, -104.0, -18.0, 70.0, 5.0);
    for wx in [-92.0, -48.0] {
        fill_ellipse(cr, wood_dark, wx - 9.0, -18.0, 18.0, 18.0);
        draw_ellipse(cr, wood, 1.8, wx - 6.5, -15.5, 13.0, 13.0);
        for k in 0..4 {
            let a = step * 1.6 + k as f64 * PI / 2.0;
            flat(cr, wood, 1.4, wx, -9.0, wx + a.cos() * 6.5, -9.0 + a.sin() * 6.5);
        }
    }
    // the shaft and the cat that pulls: black, tail up, its legs going
    round(cr, wood_dark, 2.4, -36.0, -16.0, 6.0, -20.0);
    cat_leg(cr, -2.0, (step * stride + 1.2).sin() * 0.5);
    cat_leg(cr, 22.0, (step * stride + 1.2 + PI).sin() * 0.5);
    bezier(cr, ink, 3.0, [-6.0, -22.0, -16.0, -26.0, -18.0, -40.0, -10.0, -46.0 + (step * stride).sin() * 2.0]);
    fill_ellipse(cr, ink, -8.0, -28.0, 40.0, 15.0);
    cat_leg(cr, 2.0, (step * stride + PI).sin() * 0.5);
    cat_leg(cr, 26.0, (step * stride).sin() * 0.5);
    let nod = (step * stride).sin();
    fill_ellipse(cr, ink, 24.0, -38.0 + nod, 16.0, 14.0);
    fill_polygon(cr, ink, &[(26.0, -34.0 + nod), (26.5, -44.0 + nod), (31.0, -37.0 + nod)]);
    fill_polygon(cr, ink, &[(38.0, -34.0 + nod), (38.0, -44.0 + nod), (33.5, -37.0 + nod)]);
    fill_ellipse(cr, rgb(255, 214, 64), 33.0, -33.0 + nod, 3.0, 2.6);
    flat(cr, rgb(200, 60, 60), 1.6, 22.0, -28.0, 26.0, -22.0); // the harness
    // the small witch with the broom, walking in front (her legs keep the cat's time)
    let saved = cr.matrix();
    cr.translate(78.0, 0.0);
    cr.scale(1.3, 1.3);
    let walker = SpookPose {
        tunic: 1,
        walking: true,
        waving: false,
        carries_gift: false,
        walk: (step * stride).rem_euclid(4.0 * PI),
        stand: 0.0,
        wave: 0.0,
    };
    spook(cr, walker);
    cr.set_matrix(saved);
    // the broom: the handle from her hands down to the ground in front, the twigs swinging
    let swing = (step * stride * 2.0).sin() * 5.0;
    round(cr, wood, 2.2, 80.0, -42.0, 98.0 + swing, -4.0);
    for k in 0..6 {
        let col = if k % 2 == 0 { rgb(214, 170, 72) } else { rgb(176, 132, 52) };
        round(cr, col, 1.6, 97.0 + swing, -6.0, 92.0 + swing + k as f64 * 3.4, 1.0);
    }
    fill_rect(cr, wood_dark, 94.0 + swing, -8.0, 7.0, 3.0);
    // leaves gathered in front of the broom
    for (i, lx) in [102.0, 109.0, 116.0].into_iter().enumerate() {
        if (i as f64) * 6.0 < ph {
            fill_ellipse(cr, LEAF_COLOURS[i % LEAF_COLOURS.len()], lx + swing - 5.0, -6.0 - (i % 2) as f64 * 2.0, 10.0, 6.0);
        }
    }
}

/// The second: three ghosts float along in a row, leaning forward, and blow; the leaves whirl up in front of them
/// and are carried off. Facing +x, origin at the ground. `t` is the plow's wheel, which here only keeps time.
pub(super) fn ghost_blowers(cr: &Context, ph: f64, t: f64) {
    const PLACES: [(f64, f64, f64, usize); 3] = [(-64.0, -8.0, 1.15, 0), (-8.0, -20.0, 1.3, 2), (46.0, -4.0, 1.2, 0)];
    for (i, (px, py, size, tunic)) in PLACES.into_iter().enumerate() {
        let fi = i as f64;
        let saved = cr.matrix();
        cr.translate(px, py + (t * 0.9 + fi * 2.1).sin() * 3.0);
        cr.rotate(0.30 + (t * 0.7 + fi).sin() * 0.04);
        cr.scale(size, size);
        let floater = SpookPose {
            tunic,
            walking: true,
            waving: false,
            carries_gift: false,
            walk: (t * 0.5 + fi * 0.37).rem_euclid(4.0 * PI),
            stand: 0.0,
            wave: 0.0,
        };
        spook(cr, floater);
        // cheeks puffed and a round mouth, blowing
        fill_ellipse(cr, rgb(34, 30, 48), 2.6, -33.0, 5.0, 5.6);
        fill_ellipse(cr, c(244, 200, 210, 150), -5.4, -30.0, 4.0, 3.0);
        cr.set_matrix(saved);
        // its breath: thin pale streaks out in front, wavering
        let (bx, by) = (px + 22.0 * size, py - 30.0 * size);
        for k in 0..3 {
            let kf = k as f64;
            let w = (t * 3.0 + fi * 1.7 + kf * 2.0).sin() * 3.0;
            bezier(
                cr,
                c(255, 255, 255, 110 - k * 25),
                1.6 - kf * 0.3,
                [bx + 4.0, by + kf * 5.0 - 3.0, bx + 18.0, by + kf * 6.0 - 6.0 + w, bx + 30.0, by + kf * 7.0 + 4.0 - w, bx + 44.0 + kf * 6.0, by + kf * 8.0 + w * 0.5],
            );
        }
    }
    // leaves lifted off the pile just ahead of them
    for (i, lx) in [88.0, 100.0, 112.0].into_iter().enumerate() {
        let fi = i as f64;
        if fi * 6.0 < ph {
            fill_ellipse(cr, LEAF_COLOURS[(i + 1) % LEAF_COLOURS.len()], lx - 5.0, -8.0 - fi * 5.0 + (t * 4.0 + fi).sin() * 3.0, 10.0, 6.0);
        }
    }
}

// ---------------------------------------------------------------------- the string of pumpkins and bats
/// A small pumpkin lantern hanging at a bulb's place, its top at (bx, by), on a screen of scale `s`: with `lit`
/// None the dark lantern with its hook (drawn once, with the string), with Some(brightness 0..1) its lit form over
/// that, as it twinkles. The lit form keeps inside the bulb's own box (`lights.rs`), which is all that is restored.
pub(super) fn garland_pumpkin(cr: &Context, bx: f64, by: f64, s: f64, lit: Option<f64>) {
    let alpha = |a: f64| (a * lit.unwrap_or(1.0)).clamp(0.0, 255.0) as u8;
    let (col, face) = match lit {
        Some(_) => ((alpha(255.0), 255, 140, 30), (alpha(255.0), CANDLE_LIGHT.1, CANDLE_LIGHT.2, CANDLE_LIGHT.3)),
        None => (rgb(140, 70, 16), rgb(48, 24, 8)),
    };
    if lit.is_some() {
        glow(cr, (alpha(110.0), 255, 170, 60), bx, by + 12.5 * s, 12.0 * s);
    } else {
        flat(cr, rgb(60, 44, 30), 1.2 * s, bx, by, bx, by + 4.0 * s);
        fill_rect(cr, rgb(72, 120, 48), bx - 1.2 * s, by + 3.0 * s, 2.4 * s, 2.4 * s);
    }
    let rim = shade((255, col.1, col.2, col.3), 0.8);
    fill_ellipse(cr, (col.0, rim.1, rim.2, rim.3), bx - 6.5 * s, by + 4.6 * s, 13.0 * s, 10.8 * s);
    fill_ellipse(cr, col, bx - 4.0 * s, by + 4.6 * s, 8.0 * s, 10.8 * s);
    fill_polygon(cr, face, &[(bx - 3.6 * s, by + 9.6 * s), (bx - 2.2 * s, by + 7.0 * s), (bx - 0.8 * s, by + 9.6 * s)]);
    fill_polygon(cr, face, &[(bx + 0.8 * s, by + 9.6 * s), (bx + 2.2 * s, by + 7.0 * s), (bx + 3.6 * s, by + 9.6 * s)]);
    fill_polygon(cr, face, &[(bx - 3.4 * s, by + 11.2 * s), (bx + 3.4 * s, by + 11.2 * s), (bx, by + 13.6 * s)]);
}

/// What hangs on the string besides the lanterns: bats hanging by their feet, asleep with their wings folded round
/// them. Drawn once into the strip's image, over the string. `w` is the strip's width in pixels.
pub(super) fn sleeping_bats(cr: &Context, w: f64, s: f64) {
    let (span, sag, top) = (230.0 * s, 22.0 * s, 1.0);
    let mut n = 0usize;
    let mut x0 = -span * 0.3;
    while x0 < w {
        for k in (0..12usize).filter(|k| k % 3 != 1 && (n + k) % 2 == 0) {
            let u = (k as f64 + 0.5) / 12.0;
            let (x, y) = (x0 + u * span, top + sag * (1.0 - (2.0 * u - 1.0) * (2.0 * u - 1.0)));
            let size = (0.8 + ((n * 7 + k) % 4) as f64 * 0.12) * s;
            let saved = cr.matrix();
            cr.translate(x, y);
            cr.rotate(((n + k) as f64 * 2.3).sin() * 0.12);
            cr.scale(size, size);
            // the folded wings as a pointed cloak, the head and ears below, two small feet on the string
            flat(cr, NIGHT, 1.0, -1.4, 0.0, -1.4, 2.4);
            flat(cr, NIGHT, 1.0, 1.4, 0.0, 1.4, 2.4);
            cr.new_path();
            cr.move_to(0.0, 1.6);
            cr.curve_to(-6.5, 4.0, -5.5, 12.0, -1.0, 15.5);
            cr.line_to(1.0, 15.5);
            cr.curve_to(5.5, 12.0, 6.5, 4.0, 0.0, 1.6);
            cr.close_path();
            fill_with(cr, NIGHT);
            fill_ellipse(cr, NIGHT, -2.8, 13.6, 5.6, 5.4);
            fill_polygon(cr, NIGHT, &[(-2.6, 17.4), (-2.9, 21.4), (-0.6, 18.6)]);
            fill_polygon(cr, NIGHT, &[(2.6, 17.4), (2.9, 21.4), (0.6, 18.6)]);
            cr.set_matrix(saved);
        }
        n += 1;
        x0 += span;
    }
}

// ---------------------------------------------------------------------- cats and spiders on the window edges
fn spider(cr: &Context) {
    for side in [-1.0, 1.0] {
        for j in 0..4 {
            let jf = j as f64;
            let a = jf * 0.42 - 0.6;
            bezier(cr, NIGHT, 0.9, [side * 2.0, -1.0 + jf * 0.8, side * 6.0, -4.0 + jf * 1.6 + a, side * 8.0, -2.0 + jf * 2.0, side * 9.0, 1.0 + jf * 1.8]);
        }
    }
    fill_ellipse(cr, NIGHT, -3.4, -2.4, 6.8, 7.4);
    fill_ellipse(cr, NIGHT, -2.2, -5.0, 4.4, 4.0);
    fill_ellipse(cr, rgb(220, 40, 40), -1.4, -4.0, 1.0, 1.0);
    fill_ellipse(cr, rgb(220, 40, 40), 0.4, -4.0, 1.0, 1.0);
}

impl Layer {
    /// A black cat sits on every window's top edge that is wide enough, at a place fixed on the window, swinging its
    /// tail and blinking now and then; and here and there a spider hangs under the edge on its thread, letting
    /// itself down and climbing up again. Both only where the edge is not hidden by a window in front. They move,
    /// so they are drawn every frame over the cached leaves (which clearing restores under them). Sizes are in the
    /// window snow's unit, `ledge_u`.
    pub(super) fn draw_ledge_spooks(&mut self, st: &SceneState) {
        if !(st.halloween && st.window_snow) {
            return;
        }
        let u = st.ledge_u;
        let (ox, oy, w) = (self.rect.x as f32, self.rect.y as f32, self.w as f32);
        for l in st.ledges {
            // (a cat needs no leaves to sit on, so a bare edge has one too; but not a window being dragged)
            let dragged = l.moving && l.rect.w == l.settled.w && l.rect.h == l.settled.h;
            let s = l.settled;
            if dragged || s.w <= 260.0 * u || s.right() <= ox || s.x >= ox + w || s.y <= oy || s.y > oy + self.h as f32 {
                continue;
            }
            let edge = s.y - oy;
            let id = (l.id % 9973) as i32;
            // the cat: somewhere along the middle three fifths
            let cat_x = s.x + s.w * (0.2 + (id * 37 % 60) as f32 / 100.0);
            if cat_x >= ox - 30.0 * u && cat_x <= ox + w + 30.0 * u && l.is_visible(cat_x) {
                let (foot, x) = (edge - l.height_at(cat_x) * 0.55, cat_x - ox);
                let t = st.time + (id % 17) as f64;
                // (it blinks for a moment every five seconds or so, and its tail goes over about once a second)
                let blink = t.rem_euclid(5.3) < 0.18;
                let tail = if blink {
                    0.2
                } else if (t * 1.1) as i64 % 2 == 0 {
                    -0.6
                } else {
                    0.8
                };
                self.mark(x - 22.0 * u, foot - 36.0 * u, 50.0 * u, 38.0 * u);
                let cr = &self.canvas.cr;
                let saved = cr.matrix();
                cr.translate(x as f64, foot as f64);
                cr.scale(u as f64, u as f64);
                cat(cr, tail, !blink);
                cr.set_matrix(saved);
            }
            // the spiders: one about every 420 points, hanging under the edge
            let count = (s.w / (420.0 * u)) as i32;
            for k in 0..count {
                let gx = s.x + s.w * (k as f32 + 0.5 + ((id + k * 29) % 30 - 15) as f32 / 100.0) / count as f32;
                if gx < ox - 20.0 * u || gx > ox + w + 20.0 * u || !l.is_visible(gx) {
                    continue;
                }
                let t = st.time * 0.5 + k as f64 * 2.1 + (id % 13) as f64;
                let drop = 26.0 + (k % 3) as f64 * 14.0 + t.sin() * 16.0;
                let x = gx - ox;
                self.mark(x - 12.0 * u, edge - 2.0, 24.0 * u, (drop as f32 + 16.0) * u);
                let cr = &self.canvas.cr;
                let saved = cr.matrix();
                cr.translate(x as f64, edge as f64);
                cr.scale(u as f64, u as f64);
                flat(cr, c(235, 235, 245, 170), 0.8, 0.0, 0.0, 0.0, drop);
                cr.translate(0.0, drop + 4.0);
                spider(cr);
                cr.set_matrix(saved);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_halloween_figure_draws_at_every_stage_and_pose() {
        let img = Image::new(600, 300).unwrap();
        let cr = &img.cr;
        cr.translate(300.0, 250.0);
        for stage in 1..=12 {
            pumpkins(cr, stage);
        }
        witch(cr, 1.3);
        witch_sweeper(cr, 12.0, 2.5);
        ghost_blowers(cr, 12.0, 2.5);
        for tunic in 0..4 {
            for (walking, waving, carries_gift) in [(true, false, false), (false, false, true), (false, true, false)] {
                spook(cr, SpookPose { tunic, walking, waving, carries_gift, walk: 1.0, stand: 0.7, wave: 2.0 });
            }
        }
        garland_pumpkin(cr, 0.0, -200.0, 1.0, None);
        garland_pumpkin(cr, 0.0, -200.0, 1.0, Some(0.7));
        sleeping_bats(cr, 300.0, 1.0);
        cat(cr, 0.5, false);
        spider(cr);
        img.surface.flush();
        assert!(img.pixels.iter().any(|p| *p != 0));
    }

    #[test]
    fn a_lit_garland_pumpkin_keeps_inside_its_bulbs_box() {
        // the lights' image restores only each bulb's own box (28 x 29 points from 14 to the left of and 1 above
        // the bulb's place): the lit lantern and its glow must not reach outside it
        let (w, h, s) = (80usize, 60usize, 1.0);
        let img = Image::new(w as i32, h as i32).unwrap();
        garland_pumpkin(&img.cr, 40.0, 10.0, s, Some(1.0));
        img.surface.flush();
        for y in 0..h {
            for x in 0..w {
                let inside = (26..54).contains(&x) && (9..38).contains(&y);
                assert!(inside || img.pixels[y * w + x] == 0, "light outside the box at {x},{y}");
            }
        }
    }
}
