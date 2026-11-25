//! New Year (setting `Theme` = 4), as in the macOS version (`OverlayNytaar.swift`) and the Windows one
//! (`src/LayerNytaar.cs`): each Christmas element has its New Year form. Here are the pictures of the confetti and
//! paper streamers that fall for snow, the large clock that shows the time and is decorated step by step in the
//! snowman's place, the party guests in paper hats that walk in the nisser's, the pennants and paper lanterns
//! that hang in the lights', the sparklers and party poppers on the window edges, the small street sweeper in the
//! plow's, and the rockets and their sparks (`figures.rs`: `Rocket`, `Ember`). Nothing here shows or suggests
//! drinking: no glasses, bottles or corks. The drawing is kept line for line the same as in the other two
//! versions. All figures are original.

use cairo::{Context, LineCap};

use super::draw::*;
use super::muertos::{bezier, c, fill_with, flat, glow, round, shade};
use super::{Layer, SceneState, LEAF_PX};
use crate::x11::Res;

/// New Year's confetti and streamers: gold and silver, and a few strong colours.
pub(crate) const CONFETTI: [Argb; 7] = [
    rgb(240, 196, 64),
    rgb(214, 220, 230),
    rgb(233, 50, 90),
    rgb(40, 160, 220),
    rgb(120, 200, 80),
    rgb(160, 90, 220),
    rgb(255, 140, 40),
];
const INK: Argb = rgb(38, 34, 52);
const PARTY_GOLD: Argb = rgb(235, 195, 70);
const SKINS: [Argb; 4] = [rgb(255, 214, 186), rgb(232, 180, 140), rgb(170, 118, 84), rgb(250, 224, 200)];
const HAIRS: [Argb; 4] = [rgb(92, 60, 36), rgb(40, 34, 36), rgb(214, 170, 90), rgb(150, 70, 40)];
const CLOTHES: [Argb; 4] = [rgb(36, 60, 120), rgb(196, 42, 82), rgb(30, 120, 110), rgb(120, 60, 160)];
const LANTERNS: [Argb; 4] = [rgb(233, 60, 80), rgb(255, 150, 40), rgb(60, 170, 210), rgb(170, 100, 220)];
/// The crackers' colours (the nisser's gifts').
const CRACKERS: [Argb; 4] = [rgb(40, 140, 70), rgb(60, 100, 200), rgb(200, 40, 60), rgb(150, 80, 180)];
/// The eight guests: a dress (true) or a jacket, and which clothes, skin, hair and hat; a balloon's colour for the
/// three who have one when their hands are empty. A guest keeps its look: what changes hands at a meeting is only
/// the cracker.
const GUESTS: [(bool, usize, usize, usize, usize, Option<usize>); 8] = [
    (false, 0, 0, 0, 2, None),
    (true, 1, 2, 1, 4, Some(3)),
    (false, 2, 1, 3, 0, None),
    (true, 3, 3, 2, 6, None),
    (true, 1, 0, 1, 3, None),
    (false, 0, 2, 1, 5, Some(4)),
    (true, 3, 1, 0, 2, Some(6)),
    (false, 2, 3, 2, 4, None),
];
const PI: f64 = std::f64::consts::PI;

/// `col` with its alpha multiplied by `k` (0..1).
fn faded(col: Argb, k: f64) -> Argb {
    ((col.0 as f64 * k.clamp(0.0, 1.0)) as u8, col.1, col.2, col.3)
}

// ---------------------------------------------------------------------- confetti
/// The ten confetti pictures, premultiplied ARGB, `LEAF_PX` square, laid out as the leaves' (`make_leaf_sprites`),
/// so the same code lets them fall and pile up: five times a small piece of paper (a slip seen at a slant with one
/// half in shade as if folded, another slip, a round piece, a narrow slip, a slip again), each followed by a curl
/// of paper streamer in another colour, which one pick in five gets.
pub(super) fn make_confetti_sprites() -> Res<Vec<Vec<u32>>> {
    let mut all = Vec::with_capacity(10);
    for i in 0..5usize {
        let colour = CONFETTI[i];
        let dark = shade(colour, 0.78);
        let img = Image::new(LEAF_PX as i32, LEAF_PX as i32)?;
        let cr = &img.cr;
        match i {
            1 => {
                fill_polygon(cr, colour, &[(20.0, 14.0), (44.0, 20.0), (40.0, 50.0), (16.0, 44.0)]);
                fill_polygon(cr, dark, &[(18.0, 29.0), (42.0, 35.0), (40.0, 50.0), (16.0, 44.0)]);
            }
            2 => {
                fill_ellipse(cr, colour, 16.0, 18.0, 32.0, 28.0);
                fill_ellipse(cr, dark, 30.0, 22.0, 18.0, 24.0);
            }
            3 => {
                fill_polygon(cr, colour, &[(8.0, 26.0), (54.0, 20.0), (56.0, 30.0), (10.0, 36.0)]);
                fill_polygon(cr, dark, &[(32.0, 23.0), (54.0, 20.0), (56.0, 30.0), (34.0, 33.0)]);
            }
            _ => {
                fill_polygon(cr, colour, &[(14.0, 22.0), (48.0, 16.0), (52.0, 40.0), (18.0, 46.0)]);
                fill_polygon(cr, dark, &[(31.0, 19.0), (48.0, 16.0), (52.0, 40.0), (35.0, 43.0)]);
            }
        }
        img.surface.flush();
        all.push(img.pixels.clone());

        // a streamer: a ribbon in an S with a curl at one end
        let colour = CONFETTI[(i + 5) % CONFETTI.len()];
        let dark = shade(colour, 0.78);
        let img = Image::new(LEAF_PX as i32, LEAF_PX as i32)?;
        let cr = &img.cr;
        bezier(cr, dark, 7.0, [6.0, 40.0, 18.0, 12.0, 30.0, 52.0, 44.0, 26.0]);
        bezier(cr, colour, 7.0, [44.0, 26.0, 50.0, 14.0, 62.0, 20.0, 56.0, 30.0]);
        bezier(cr, colour, 5.0, [56.0, 30.0, 52.0, 36.0, 46.0, 32.0, 49.0, 27.0]);
        img.surface.flush();
        all.push(img.pixels.clone());
    }
    Ok(all)
}

// ---------------------------------------------------------------------- the clock
/// One paper lantern: a round ribbed ball, `r` wide to each side of (cx, cy). Lit, it glows; `alpha` (0..1) fades
/// the whole of it (the garland's lit lanterns twinkle over their unlit forms).
fn paper_lantern(cr: &Context, cx: f64, cy: f64, r: f64, colour: Argb, lit: bool, alpha: f64) {
    let ry = r * 1.08;
    if lit {
        glow(cr, faded(c(255, 226, 150, 120), alpha), cx, cy, r * 2.0);
    }
    fill_ellipse(cr, faded(shade(colour, if lit { 0.95 } else { 0.7 }), alpha), cx - r, cy - ry, 2.0 * r, 2.0 * ry);
    let middle = if lit { shade(colour, 1.25) } else { shade(colour, 0.88) };
    fill_ellipse(cr, faded(middle, alpha), cx - r * 0.62, cy - ry, r * 1.24, 2.0 * ry);
    draw_ellipse(cr, faded(shade(colour, 0.55), alpha), (r * 0.07).max(0.5), cx - r * 0.26, cy - ry, r * 0.52, 2.0 * ry);
    if lit {
        fill_ellipse(cr, faded(c(255, 244, 200, 170), alpha), cx - r * 0.3, cy - ry * 0.4, r * 0.6, ry * 0.9);
    }
    // the rings at top and bottom
    fill_rect(cr, faded(INK, alpha), cx - r * 0.36, cy - ry - r * 0.12, r * 0.72, r * 0.2);
    fill_rect(cr, faded(INK, alpha), cx - r * 0.3, cy + ry - r * 0.08, r * 0.6, r * 0.18);
}

/// A row of pennants hanging from a line that sags from `from` to `to`.
fn pennant_line(cr: &Context, from: (f64, f64), to: (f64, f64), sag: f64, count: usize, size: f64, first: usize) {
    let at = |u: f64| (from.0 + (to.0 - from.0) * u, from.1 + (to.1 - from.1) * u + sag * 4.0 * u * (1.0 - u));
    cr.new_path();
    for k in 0..=16 {
        let p = at(k as f64 / 16.0);
        cr.line_to(p.0, p.1);
    }
    stroke(cr, c(60, 50, 60, 220), (size * 0.09).max(0.6), LineCap::Round);
    for k in 0..count {
        let u = (k as f64 + 0.5) / count as f64;
        let (a, b) = (at(u - 0.4 / count as f64), at(u + 0.4 / count as f64));
        let col = CONFETTI[(first + k * 2) % CONFETTI.len()];
        let mid = ((a.0 + b.0) / 2.0, (a.1 + b.1) / 2.0);
        fill_polygon(cr, col, &[a, b, (mid.0, mid.1 + size)]);
        fill_polygon(cr, shade(col, 0.8), &[mid, b, (mid.0, mid.1 + size)]);
    }
}

/// One of the clock's hands: `turn` 0..1 round the face from twelve.
fn clock_hand(cr: &Context, cy: f64, turn: f64, len: f64, width: f64, col: Argb, tail: f64) {
    let a = turn * 2.0 * PI;
    round(cr, col, width, -a.sin() * tail, cy + a.cos() * tail, a.sin() * len, cy - a.cos() * len);
}

/// New Year's form of the snowman: a large clock on a stand whose hands show the time (`hour` and `minute` as
/// turns of their hands, 0..1; `second` the second hand's, which is only there in the last minute before
/// midnight), decorated a step for every hour the app runs, in the same place and box as the snowman. The clock
/// itself stands from the first step: it is the countdown. Origin at the ground, y up is negative.
pub(super) fn party_clock(cr: &Context, stage: i32, hour: f64, minute: f64, second: Option<f64>) {
    let (iron, iron_light, face) = (rgb(52, 62, 86), rgb(92, 104, 132), rgb(250, 246, 232));
    let (cy, r) = (-84.0, 30.0);
    fill_ellipse(cr, c(20, 16, 30, 55), -44.0, -3.0, 88.0, 6.0);

    // the poles the pennants and lanterns hang on (steps 5-8)
    for (side, from) in [(-1.0, 5), (1.0, 6)] {
        if stage < from {
            continue;
        }
        round(cr, rgb(120, 88, 56), 2.2, side * 54.0, 0.0, side * 54.0, -70.0);
        pennant_line(cr, (side * 54.0, -70.0), (side * 24.0, -100.0), 9.0, 4, 8.0, if side < 0.0 { 0 } else { 3 });
    }
    // balloons tied to the foot (steps 9 and 10)
    for (side, from) in [(-1.0, 9), (1.0, 10)] {
        if stage < from {
            continue;
        }
        for (k, (bx, by)) in [(30.0, -40.0), (42.0, -54.0)].into_iter().enumerate() {
            let col = CONFETTI[(k * 3 + if side < 0.0 { 2 } else { 4 }) % CONFETTI.len()];
            bezier(
                cr,
                c(230, 230, 240, 170),
                0.7,
                [side * 10.0, -5.0, side * 14.0, -22.0, side * (bx - 8.0), by + 26.0, side * bx, by + 10.0],
            );
            fill_ellipse(cr, col, side * bx - 8.0, by - 10.0, 16.0, 20.0);
            fill_polygon(cr, col, &[(side * bx - 2.0, by + 9.5), (side * bx + 2.0, by + 9.5), (side * bx, by + 12.5)]);
            fill_ellipse(cr, c(255, 255, 255, 110), side * bx - 5.0, by - 7.0, 4.5, 7.0);
        }
    }

    // the stand: a foot, a post and a collar under the clock
    cr.new_path();
    cr.move_to(-22.0, 0.0);
    cr.curve_to(-20.0, -7.0, -8.0, -8.0, -5.0, -12.0);
    cr.line_to(5.0, -12.0);
    cr.curve_to(8.0, -8.0, 20.0, -7.0, 22.0, 0.0);
    cr.close_path();
    fill_with(cr, iron);
    fill_rect(cr, iron, -3.6, -56.0, 7.2, 46.0);
    fill_rect(cr, iron_light, -3.6, -56.0, 2.2, 46.0);
    fill_rect(cr, iron, -6.5, -57.0, 13.0, 4.0);
    // paper streamers wound round the post (step 4)
    if stage >= 4 {
        for k in 0..6usize {
            let y = -14.0 - k as f64 * 7.0;
            fill_polygon(cr, CONFETTI[(k * 2) % CONFETTI.len()], &[(-3.8, y), (3.8, y - 4.0), (3.8, y - 7.0), (-3.8, y - 3.0)]);
        }
        bezier(cr, CONFETTI[2], 1.6, [3.8, -16.0, 12.0, -12.0, 8.0, -4.0, 15.0, -1.0]);
        bezier(cr, CONFETTI[0], 1.6, [-3.8, -22.0, -12.0, -18.0, -9.0, -8.0, -16.0, -2.0]);
    }

    // the clock: a dark case, a pale face with twelve marks, two hands
    fill_ellipse(cr, c(20, 16, 30, 40), -r - 3.0, cy - r - 1.0, 2.0 * r + 6.0, 2.0 * r + 6.0);
    fill_ellipse(cr, iron, -r - 2.0, cy - r - 2.0, 2.0 * r + 4.0, 2.0 * r + 4.0);
    if stage >= 2 {
        draw_ellipse(cr, PARTY_GOLD, 2.4, -r - 0.6, cy - r - 0.6, 2.0 * r + 1.2, 2.0 * r + 1.2);
    }
    fill_ellipse(cr, face, -r + 3.0, cy - r + 3.0, 2.0 * r - 6.0, 2.0 * r - 6.0);
    draw_ellipse(cr, rgb(214, 204, 180), 1.0, -r + 4.5, cy - r + 4.5, 2.0 * r - 9.0, 2.0 * r - 9.0);
    for k in 0..12 {
        let a = k as f64 * PI / 6.0;
        let big = k % 3 == 0;
        let (r0, r1) = (r - if big { 11.0 } else { 8.5 }, r - 5.5);
        round(cr, INK, if big { 2.2 } else { 1.1 }, a.sin() * r0, cy - a.cos() * r0, a.sin() * r1, cy - a.cos() * r1);
    }
    clock_hand(cr, cy, hour, 13.5, 3.0, INK, 3.0);
    clock_hand(cr, cy, minute, 20.5, 2.0, INK, 3.0);
    if let Some(turn) = second {
        clock_hand(cr, cy, turn, 21.5, 0.9, rgb(214, 40, 60), 5.0);
    }
    fill_ellipse(cr, PARTY_GOLD, -2.2, cy - 2.2, 4.4, 4.4);
    // small gold bulbs round the case (step 2)
    if stage >= 2 {
        for k in 0..12 {
            let a = (k as f64 + 0.5) * PI / 6.0;
            fill_ellipse(cr, rgb(255, 232, 150), a.sin() * (r + 1.0) - 1.6, cy - a.cos() * (r + 1.0) - 1.6, 3.2, 3.2);
        }
    }
    // a bow under the clock (step 3)
    if stage >= 3 {
        let red = rgb(214, 40, 70);
        fill_polygon(cr, red, &[(0.0, -52.0), (-12.0, -58.0), (-12.0, -46.0)]);
        fill_polygon(cr, red, &[(0.0, -52.0), (12.0, -58.0), (12.0, -46.0)]);
        fill_polygon(cr, shade(red, 0.8), &[(-2.0, -51.0), (-9.0, -38.0), (-4.0, -39.0), (0.0, -49.0)]);
        fill_polygon(cr, shade(red, 0.8), &[(2.0, -51.0), (9.0, -38.0), (4.0, -39.0), (0.0, -49.0)]);
        fill_ellipse(cr, shade(red, 1.15), -3.0, -55.0, 6.0, 6.0);
    }
    // a paper lantern on each pole (steps 7 and 8)
    if stage >= 7 {
        paper_lantern(cr, -54.0, -79.0, 8.0, rgb(233, 60, 80), true, 1.0);
    }
    if stage >= 8 {
        paper_lantern(cr, 54.0, -79.0, 8.0, rgb(255, 150, 40), true, 1.0);
    }
    // a gold star on top (step 11)
    if stage >= 11 {
        fill_polygon(cr, shade(PARTY_GOLD, 0.8), &star_points(0.0, -121.0, 9.5, 4.2, 0.0));
        fill_polygon(cr, rgb(255, 226, 120), &star_points(0.0, -121.0, 7.5, 3.4, 0.0));
    }
    // two sparklers behind the star, burning (step 12)
    if stage >= 12 {
        for side in [-1.0, 1.0] {
            round(cr, rgb(90, 90, 100), 1.0, side * 5.0, -112.0, side * 17.0, -127.0);
            let (x, y) = (side * 17.0, -127.0);
            for k in 0..8 {
                let a = k as f64 * PI / 4.0 + side * 0.3;
                let len = if k % 2 == 0 { 6.0 } else { 3.6 };
                let col = if k % 2 == 0 { rgb(255, 240, 190) } else { rgb(255, 206, 110) };
                round(cr, col, 0.8, x, y, x + a.cos() * len, y + a.sin() * len);
            }
            fill_ellipse(cr, rgb(255, 252, 230), x - 1.6, y - 1.6, 3.2, 3.2);
        }
    }
}

// ---------------------------------------------------------------------- party guests
/// How a guest stands: the pose of the elf it stands in for.
pub(super) struct GuestPose {
    /// Which of the eight guests it is (`GUESTS`).
    pub look: usize,
    /// Its cracker's colour (the elf's gift number).
    pub gift: usize,
    pub walking: bool,
    pub waving: bool,
    pub carries_gift: bool,
    /// The step's phase while walking, and the phases of standing and waving (0 when not).
    pub walk: f64,
    pub stand: f64,
    pub wave: f64,
}

fn guest_arm(cr: &Context, sx: f64, sy: f64, a: f64, sleeve: Argb, skin: Argb) {
    let (hx, hy) = (sx + a.sin() * 10.0, sy + a.cos() * 10.0);
    round(cr, sleeve, 3.2, sx, sy, hx, hy);
    fill_ellipse(cr, skin, hx - 2.2, hy - 2.2, 4.4, 4.4);
}

/// New Year's walkers. They are nisser in everything but looks: they walk, stop, wave, cross to the next screen
/// and meet to hand something over (a party cracker). Each wears a paper hat; half are in a dress and half in
/// jacket and trousers, and now and then one has a balloon on a string. "Waving" is a jump with a blow on a party
/// horn. Drawn like a nisse: feet at (0, 0), y up is negative, facing right.
pub(super) fn guest(cr: &Context, pose: GuestPose) {
    let (p, stand_phase, wave_phase) = (pose.walk, pose.stand, pose.wave);
    let (walking, waving) = (pose.walking, pose.waving);
    let leg_a = if walking { p.sin() * 0.55 } else { 0.0 };
    // the jump: off the ground and down again, once for every blow of the horn
    let jump = if waving { wave_phase.sin().abs() * 6.0 } else { 0.0 };
    let bob = if walking { -p.sin().abs() * 1.5 } else { -jump };
    let (dress, cloth_i, skin_i, hair_i, hat_i, balloon) = GUESTS[pose.look % GUESTS.len()];
    let (cloth, skin, hair, hat_col) = (CLOTHES[cloth_i], SKINS[skin_i], HAIRS[hair_i], CONFETTI[hat_i]);
    fill_ellipse(cr, c(30, 20, 40, 50), -10.0, -2.0, 20.0, 4.0);

    // a balloon on a string, for some of those with empty hands
    if let Some(colour) = balloon.filter(|_| !pose.carries_gift) {
        let sw = (if walking { p * 0.5 } else { stand_phase }).sin() * 2.0;
        let col = CONFETTI[colour % CONFETTI.len()];
        bezier(cr, c(235, 235, 245, 180), 0.7, [-8.0, -24.0 + bob, -10.0, -36.0 + bob, -15.0 - sw * 0.5, -40.0, -14.0 - sw, -50.0]);
        fill_ellipse(cr, col, -21.0 - sw, -66.0, 14.0, 17.0);
        fill_polygon(cr, col, &[(-15.6 - sw, -49.6), (-12.4 - sw, -49.6), (-14.0 - sw, -47.4)]);
        fill_ellipse(cr, c(255, 255, 255, 120), -18.6 - sw, -63.5, 4.0, 6.0);
    }

    // legs: tights under a dress, trousers otherwise
    let leg_col = if dress { rgb(60, 54, 80) } else { shade(cloth, 0.62) };
    for side in [-1.0, 1.0] {
        let (hx, a) = (2.0 * side, -leg_a * side);
        let spread = if waving { 0.35 * side * (jump / 6.0) } else { 0.0 };
        let (fx, fy) = (hx + (a + spread).sin() * 13.0, -14.0 + bob + (a + spread).cos() * 13.0);
        round(cr, leg_col, if dress { 3.0 } else { 4.0 }, hx, -14.0 + bob, fx, fy);
        fill_ellipse(cr, INK, fx - 3.0, fy - 2.0, 8.0, 4.2);
    }

    let body = cr.matrix();
    cr.translate(0.0, bob);
    let (back_arm, front_arm) = if waving {
        (-2.5 - wave_phase.sin() * 0.3, 1.9)
    } else if pose.carries_gift {
        (1.3, 1.3)
    } else {
        (-leg_a * 0.9, leg_a * 0.9)
    };
    guest_arm(cr, -1.0, -31.0, back_arm, shade(cloth, 0.86), skin);

    if dress {
        cr.new_path();
        cr.move_to(-5.0, -33.0);
        cr.line_to(5.0, -33.0);
        cr.curve_to(6.5, -26.0, 10.0, -18.0, 11.5, -11.0);
        cr.line_to(-11.5, -11.0);
        cr.curve_to(-10.0, -18.0, -6.5, -26.0, -5.0, -33.0);
        cr.close_path();
        fill_with(cr, cloth);
        flat(cr, shade(cloth, 1.35), 1.4, -6.2, -24.0, 6.2, -24.0);
        // a few sequins
        for (dx, dy) in [(-4.0, -15.0), (2.0, -18.0), (6.0, -14.0), (-1.0, -13.0)] {
            fill_ellipse(cr, c(255, 240, 190, 220), dx, dy, 1.4, 1.4);
        }
    } else {
        fill_rect(cr, shade(cloth, 0.62), -5.0, -16.0, 10.0, 4.0);
        cr.new_path();
        cr.move_to(-5.5, -33.0);
        cr.line_to(5.5, -33.0);
        cr.curve_to(6.5, -26.0, 6.5, -19.0, 6.0, -13.0);
        cr.line_to(-6.0, -13.0);
        cr.curve_to(-6.5, -19.0, -6.5, -26.0, -5.5, -33.0);
        cr.close_path();
        fill_with(cr, cloth);
        // a shirt front and a bow tie
        fill_polygon(cr, rgb(248, 248, 252), &[(1.5, -33.0), (5.5, -33.0), (4.5, -22.0)]);
        fill_polygon(cr, hat_col, &[(3.6, -31.0), (1.2, -32.6), (1.2, -29.4)]);
        fill_polygon(cr, hat_col, &[(3.6, -31.0), (6.0, -32.6), (6.0, -29.4)]);
    }

    // the party cracker: a wrapped tube with a twist at each end
    if pose.carries_gift && !waving {
        let col = CRACKERS[pose.gift % CRACKERS.len()];
        let saved = cr.matrix();
        cr.translate(12.5, -20.0);
        cr.rotate(-0.35);
        fill_polygon(cr, col, &[(-9.0, -3.4), (-5.0, -1.4), (-5.0, 1.4), (-9.0, 3.4)]);
        fill_polygon(cr, col, &[(9.0, -3.4), (5.0, -1.4), (5.0, 1.4), (9.0, 3.4)]);
        fill_rect(cr, col, -5.0, -2.8, 10.0, 5.6);
        fill_rect(cr, PARTY_GOLD, -1.4, -2.8, 2.8, 5.6);
        fill_rect(cr, c(255, 255, 255, 150), -4.6, -2.8, 1.2, 5.6);
        fill_rect(cr, c(255, 255, 255, 150), 3.4, -2.8, 1.2, 5.6);
        cr.set_matrix(saved);
    }

    // the head, looking a little the way it walks
    let sway = (if walking { p * 0.5 } else { stand_phase }).sin() * 0.05;
    let saved = cr.matrix();
    cr.translate(1.0, -40.0);
    cr.rotate(sway - if waving { 0.12 } else { 0.0 });
    if dress {
        // long hair down the back
        cr.new_path();
        cr.move_to(-6.8, -3.0);
        cr.curve_to(-9.5, 2.0, -9.0, 9.0, -6.0, 11.0);
        cr.line_to(-2.5, 6.0);
        cr.curve_to(-4.0, 3.0, -4.0, 0.0, -3.0, -3.0);
        cr.close_path();
        fill_with(cr, hair);
    }
    fill_ellipse(cr, skin, -6.5, -6.5, 13.0, 13.0);
    fill_ellipse(cr, hair, -7.0, -7.4, 12.4, 7.4);
    fill_ellipse(cr, skin, -3.4, -4.6, 9.6, 6.4);
    fill_ellipse(cr, c(250, 160, 150, 140), 1.6, 0.4, 3.6, 2.6);
    fill_ellipse(cr, INK, 1.6, -2.2, 1.9, 2.5);
    fill_ellipse(cr, INK, 4.5, -2.2, 1.5, 2.3);
    if waving {
        fill_ellipse(cr, INK, 4.6, 2.2, 2.2, 2.2);
    } else {
        bezier(cr, INK, 0.8, [1.6, 2.6, 3.0, 4.2, 4.6, 4.2, 5.6, 2.6]);
    }
    // the paper hat: a striped cone with a pompom, a little askew
    let head = cr.matrix();
    cr.translate(-0.6, -6.0);
    cr.rotate(-0.16);
    fill_polygon(cr, hat_col, &[(-5.4, 0.6), (5.4, 0.6), (0.4, -14.5)]);
    fill_polygon(cr, shade(hat_col, 1.3), &[(-3.5, -4.6), (3.6, -4.6), (2.7, -7.2), (-2.6, -7.2)]);
    fill_polygon(cr, PARTY_GOLD, &[(-5.4, 0.6), (5.4, 0.6), (4.7, -1.6), (-4.7, -1.6)]);
    fill_ellipse(cr, WHITE, -1.8, -17.6, 4.6, 4.6);
    cr.set_matrix(head);
    // the party horn: blown out straight with its tip still curled
    if waving {
        // (no longer than the walker's own box is wide: that is all that is cleared behind it)
        let reach = 8.0 + wave_phase.sin().abs() * 8.0;
        let parts = (reach / 3.0) as i32;
        round(cr, rgb(250, 250, 250), 1.8, 5.6, 3.2, 8.5, 3.6);
        for k in 0..parts {
            let (k0, k1) = (k as f64, (k + 1) as f64);
            let col = if k % 2 == 0 { rgb(233, 50, 90) } else { PARTY_GOLD };
            flat(cr, col, 3.0, 8.5 + k0 * 3.0, 3.6 - k0 * 0.25, 8.5 + k1 * 3.0, 3.6 - k1 * 0.25);
        }
        let (ex, ey) = (8.5 + parts as f64 * 3.0, 3.6 - parts as f64 * 0.25);
        draw_ellipse(cr, rgb(233, 50, 90), 1.8, ex - 0.4, ey - 5.0, 5.0, 5.0);
    }
    cr.set_matrix(saved);

    guest_arm(cr, 1.0, -31.0, front_arm, shade(cloth, 0.86), skin);
    cr.set_matrix(body);
}

// ---------------------------------------------------------------------- pennants and paper lanterns
/// What hangs at a bulb's place (`idx` counts them): every other one a small gold bulb, the others a paper lantern.
/// With `lit` None it is the unlit form, drawn once with the string; with a brightness (0..1) the lit form that
/// twinkles over it. Everything stays inside the bulb's own box (`lights.rs`), which is all that is restored when
/// it twinkles.
pub(super) fn party_bulb(cr: &Context, idx: usize, bx: f64, by: f64, s: f64, lit: Option<f64>) {
    if idx % 2 == 0 {
        match lit {
            None => {
                fill_rect(cr, rgb(70, 60, 50), bx - 2.5 * s, by, 5.0 * s, 4.0 * s);
                fill_ellipse(cr, rgb(150, 118, 50), bx - 3.5 * s, by + 3.0 * s, 7.0 * s, 11.0 * s);
            }
            Some(br) => {
                // a soft glow that fades out to nothing (a flat disc looks like a grey plate on a dark desktop)
                glow(cr, faded(c(255, 220, 120, 150), br), bx, by + 11.0 * s, 11.0 * s);
                fill_ellipse(cr, faded(rgb(255, 226, 130), br), bx - 3.5 * s, by + 3.0 * s, 7.0 * s, 11.0 * s);
                fill_ellipse(cr, faded(c(255, 255, 255, 170), br), bx - 1.8 * s, by + 5.0 * s, 2.4 * s, 3.6 * s);
            }
        }
        return;
    }
    let col = LANTERNS[(idx / 2) % LANTERNS.len()];
    match lit {
        None => {
            flat(cr, rgb(60, 50, 60), s, bx, by, bx, by + 6.0 * s);
            paper_lantern(cr, bx, by + 13.5 * s, 6.5 * s, col, false, 1.0);
        }
        Some(br) => paper_lantern(cr, bx, by + 13.5 * s, 6.5 * s, col, true, br),
    }
}

/// The pennants along the string, in the confetti's colours, between the bulbs' places (the string is `w` wide on
/// a screen of scale `s`).
pub(super) fn pennants(cr: &Context, w: f64, s: f64) {
    let (span, sag, top) = (230.0 * s, 22.0 * s, 1.0);
    let at = |x0: f64, u: f64| (x0 + u * span, top + sag * (1.0 - (2.0 * u - 1.0) * (2.0 * u - 1.0)));
    let mut n = 0usize;
    let mut x0 = -span * 0.3;
    while x0 < w {
        for k in (0..12usize).filter(|k| k % 3 != 1) {
            let u = (k as f64 + 0.5) / 12.0;
            let (a, b) = (at(x0, u - 0.026), at(x0, u + 0.026));
            let col = CONFETTI[(n * 3 + k) % CONFETTI.len()];
            let mid = ((a.0 + b.0) / 2.0, (a.1 + b.1) / 2.0);
            let tip = (mid.0 + ((n + k) as f64 * 2.3).sin() * 1.5 * s, mid.1 + 15.0 * s);
            fill_polygon(cr, col, &[a, b, tip]);
            fill_polygon(cr, shade(col, 0.8), &[mid, b, tip]);
        }
        n += 1;
        x0 += span;
    }
}

// ---------------------------------------------------------------------- street sweeper
/// New Year's form of the snow plow: a small street sweeper the morning after, with a round brush turning in
/// front of it and a blinking amber lamp on the roof. Facing +x, origin at the ground, the brush where the plow's
/// blade would be. It has no horn and leaves no smoke. `ph` is the pile in front of it, `step` the wheel's turn.
pub(super) fn sweeper(cr: &Context, ph: f64, step: f64) {
    let (body, body_dark, dark, glass) = (rgb(40, 150, 160), rgb(26, 104, 116), rgb(46, 48, 58), rgb(178, 214, 236));
    // the hopper behind, with a window the confetti shows in
    cr.new_path();
    cr.move_to(-64.0, -16.0);
    cr.line_to(-64.0, -52.0);
    cr.curve_to(-64.0, -60.0, -58.0, -62.0, -52.0, -62.0);
    cr.line_to(14.0, -62.0);
    cr.line_to(14.0, -16.0);
    cr.close_path();
    fill_with(cr, body);
    fill_rect(cr, body_dark, -64.0, -22.0, 78.0, 6.0);
    fill_rect(cr, rgb(232, 240, 244), -52.0, -52.0, 34.0, 18.0);
    for k in 0..14usize {
        let lift = (ph * 0.3).min(11.0) * (k % 3) as f64 / 2.0;
        fill_rect(cr, CONFETTI[(k * 3) % CONFETTI.len()], -51.0 + (k * 7 % 31) as f64, -39.0 + (k * 5 % 4) as f64 - lift, 3.6, 2.6);
    }
    cr.new_path();
    cr.rectangle(-52.0, -52.0, 34.0, 18.0);
    stroke(cr, body_dark, 1.4, LineCap::Butt);
    // yellow and black warning stripes at the back
    for k in 0..4 {
        let y = -28.0 - k as f64 * 7.0;
        let col = if k % 2 == 0 { rgb(250, 204, 50) } else { dark };
        fill_polygon(cr, col, &[(-64.0, y), (-58.0, y), (-58.0, y - 7.0), (-64.0, y - 7.0)]);
    }
    // the cab in front: big windows all round
    cr.new_path();
    cr.move_to(14.0, -16.0);
    cr.line_to(14.0, -66.0);
    cr.line_to(40.0, -66.0);
    cr.curve_to(48.0, -66.0, 54.0, -52.0, 56.0, -36.0);
    cr.line_to(56.0, -16.0);
    cr.close_path();
    fill_with(cr, shade(body, 1.12));
    cr.new_path();
    cr.move_to(20.0, -38.0);
    cr.line_to(20.0, -61.0);
    cr.line_to(39.0, -61.0);
    cr.curve_to(45.0, -61.0, 49.0, -50.0, 51.0, -38.0);
    cr.close_path();
    fill_with(cr, glass);
    flat(cr, c(255, 255, 255, 150), 2.0, 26.0, -57.0, 34.0, -42.0);
    flat(cr, body_dark, 1.4, 33.0, -61.0, 33.0, -38.0);
    fill_rect(cr, body_dark, 14.0, -22.0, 42.0, 6.0);
    // the driver: a head in a cap
    fill_ellipse(cr, rgb(232, 180, 140), 36.0, -55.0, 9.0, 10.0);
    fill_rect(cr, rgb(250, 150, 40), 35.5, -56.5, 10.0, 3.6);
    fill_rect(cr, rgb(250, 150, 40), 44.0, -54.4, 4.0, 1.6);
    // the amber lamp, blinking
    let blink = (step * 1.3).sin() > 0.0;
    if blink {
        fill_ellipse(cr, c(255, 190, 60, 90), 18.0, -80.0, 20.0, 20.0);
    }
    fill_rect(cr, dark, 24.0, -68.0, 8.0, 2.4);
    fill_ellipse(cr, if blink { rgb(255, 196, 70) } else { rgb(190, 120, 30) }, 24.5, -74.0, 7.0, 8.0);
    // a headlamp and the bumper
    fill_ellipse(cr, rgb(255, 244, 190), 53.0, -30.0, 4.4, 5.4);
    fill_rect(cr, dark, 50.0, -17.0, 10.0, 4.0);
    // wheels
    for wx in [-42.0, 34.0] {
        fill_ellipse(cr, dark, wx - 11.0, -20.0, 22.0, 22.0);
        fill_ellipse(cr, rgb(150, 154, 166), wx - 5.0, -14.0, 10.0, 10.0);
        for k in 0..3 {
            let a = step + k as f64 * 2.094;
            flat(cr, dark, 1.4, wx, -9.0, wx + a.cos() * 5.0, -9.0 + a.sin() * 5.0);
        }
    }
    // the suction mouth between the wheels
    fill_polygon(cr, dark, &[(-18.0, -16.0), (10.0, -16.0), (14.0, -3.0), (-22.0, -3.0)]);
    // the arm and the round brush in front, turning: seen from the side it is a flat disc of bristles
    round(cr, dark, 3.0, 52.0, -16.0, 74.0, -9.0);
    fill_ellipse(cr, dark, 71.0, -12.0, 7.0, 5.0);
    fill_ellipse(cr, rgb(96, 84, 70), 58.0, -8.0, 36.0, 9.0);
    for k in 0..14 {
        let a = step * 2.4 + k as f64 * (2.0 * PI / 14.0);
        let (co, si) = (a.cos(), a.sin());
        let col = if si > 0.0 { rgb(226, 190, 120) } else { rgb(170, 138, 84) };
        round(cr, col, 1.5, 76.0 + co * 10.0, -5.0 + si * 2.6 * 0.4, 76.0 + co * 19.0, 0.5 + si * 2.6);
    }
    // confetti gathered in front of the brush
    for (i, lx) in [96.0, 103.0, 110.0].into_iter().enumerate() {
        if (i as f64) * 6.0 < ph {
            fill_rect(cr, CONFETTI[(i * 2 + 1) % CONFETTI.len()], lx, -5.0 - (i % 2) as f64 * 2.4, 5.0, 3.4);
        }
    }
}

/// A party popper lying on its side with its streamers out, pointing to the left; its foot at (0, 0).
fn popper(cr: &Context) {
    // the streamers thrown out of it
    bezier(cr, CONFETTI[2], 1.4, [4.0, -8.0, 10.0, -18.0, 14.0, -4.0, 21.0, -10.0]);
    bezier(cr, CONFETTI[3], 1.4, [4.0, -6.0, 12.0, -8.0, 12.0, -1.0, 20.0, -2.0]);
    bezier(cr, CONFETTI[0], 1.4, [4.0, -9.0, 6.0, -16.0, 12.0, -17.0, 15.0, -12.0]);
    for (k, (x, y)) in [(9.0, -13.0), (15.0, -6.0), (18.0, -15.0), (11.0, -3.0), (20.0, -7.0)].into_iter().enumerate() {
        fill_rect(cr, CONFETTI[(k * 2 + 1) % CONFETTI.len()], x, y, 2.4, 1.8);
    }
    // the popper: a cone with a gold collar and a string at its tip
    fill_polygon(cr, rgb(60, 150, 210), &[(-17.0, -3.4), (4.0, -11.5), (4.0, -0.4)]);
    fill_polygon(cr, rgb(40, 110, 170), &[(-17.0, -3.4), (4.0, -5.0), (4.0, -0.4)]);
    fill_polygon(cr, rgb(240, 196, 64), &[(1.0, -10.4), (4.0, -11.5), (4.0, -0.4), (1.0, -1.0)]);
    bezier(cr, rgb(240, 240, 245), 0.8, [-17.0, -3.4, -20.0, -2.0, -19.0, 0.0, -22.0, -0.6]);
}

impl Layer {
    /// On the window edges: sparklers standing here and there, each burning down from its tip in about half a
    /// minute and replaced by a new one a little later; and on every edge that is wide enough a party popper
    /// lying with its streamers out. Both only where the edge is not hidden by a window in front. (Sizes in the
    /// window snow's unit, `ledge_u`.)
    pub(super) fn draw_ledge_party(&mut self, st: &SceneState) {
        if !(st.nytaar && st.window_snow) {
            return;
        }
        let u = st.ledge_u;
        let (ox, oy, w) = (self.rect.x as f32, self.rect.y as f32, self.w as f32);
        for l in st.ledges {
            let dragged = l.moving && l.rect.w == l.settled.w && l.rect.h == l.settled.h;
            let s = l.settled;
            if dragged || s.w <= 200.0 * u || s.right() <= ox || s.x >= ox + w || s.y <= oy || s.y > oy + self.h as f32 {
                continue;
            }
            let edge = s.y - oy;
            let id = (l.id % 9973) as i32;
            // the popper: somewhere along the middle three fifths
            let px = s.x + s.w * (0.2 + (id * 53 % 60) as f32 / 100.0);
            if s.w > 320.0 * u && px >= ox - 30.0 * u && px <= ox + w + 30.0 * u && l.is_visible(px) {
                let (x, y) = (px - ox, edge - l.height_at(px) * 0.9 + 2.0 * u);
                self.mark(x - 24.0 * u, y - 20.0 * u, 48.0 * u, 22.0 * u);
                let cr = &self.canvas.cr;
                let saved = cr.matrix();
                cr.translate(x as f64, y as f64);
                cr.scale(if id % 2 == 0 { u as f64 } else { -(u as f64) }, u as f64);
                popper(cr);
                cr.set_matrix(saved);
            }
            // the sparklers: one about every 300 points
            let count = ((s.w / (300.0 * u)) as i32).max(1);
            for k in 0..count {
                let gx = s.x + s.w * (k as f32 + 0.5 + ((id + k * 29) % 30 - 15) as f32 / 100.0) / count as f32;
                if gx < ox - 20.0 * u || gx > ox + w + 20.0 * u || !l.is_visible(gx) || (gx - px).abs() <= 34.0 * u {
                    continue;
                }
                // 34 s of burning, then 8 s before the next one is lit
                let t = (st.time + k as f64 * 13.7 + (id % 41) as f64).rem_euclid(42.0);
                if t > 34.0 {
                    continue;
                }
                // (it stands in the confetti, most of its bare wire above it)
                let (foot, x) = (edge - l.height_at(gx) * 0.75, gx - ox);
                let (tall, bare): (f64, f64) = (34.0, 12.0);
                let left = (tall - bare) * (1.0 - t / 34.0); // the coat that has not burnt yet
                // (down to where its sparks fall when it has burnt low)
                self.mark(x - 16.0 * u, foot - (tall as f32 + 16.0) * u, 32.0 * u, (tall as f32 + 30.0) * u);
                let cr = &self.canvas.cr;
                let saved = cr.matrix();
                cr.translate(x as f64, foot as f64);
                cr.scale(u as f64, u as f64);
                flat(cr, rgb(70, 66, 74), 1.2, 0.0, 0.0, 0.0, -tall);
                flat(cr, rgb(150, 150, 160), 2.4, 0.0, -bare, 0.0, -bare - left);
                // the burning point: a glint that flickers, and a few sparks thrown off it
                let by = -bare - left;
                let f = st.time * 23.0 + k as f64 * 1.7;
                let flicker = 0.75 + 0.25 * f.sin() * (f * 0.37 + 1.0).sin();
                glow(cr, c(255, 200, 90, 120), 0.0, by, 13.0 * flicker);
                for j in 0..4 {
                    let a = f * 0.3 + j as f64 * PI / 4.0;
                    let len = 7.5 * flicker * if j % 2 == 0 { 1.0 } else { 0.6 };
                    round(cr, rgb(255, 250, 225), 0.9, -a.cos() * len, by - a.sin() * len, a.cos() * len, by + a.sin() * len);
                }
                fill_ellipse(cr, WHITE, -1.8, by - 1.8, 3.6, 3.6);
                for j in 0..4 {
                    // each spark flies out and falls for a third of a second, then the next one starts
                    let q = st.time * 3.0 + j as f64 * 0.25 + k as f64;
                    let (part, whole) = (q - q.floor(), q.floor());
                    let seed = whole * 7.0 + j as f64 * 13.0 + k as f64;
                    let (a, reach) = (seed * 2.4, 9.0 + (seed * 3.7).rem_euclid(6.0));
                    let alpha = (255.0 * (1.0 - part)) as u8;
                    fill_ellipse(
                        cr,
                        c(255, 220, 120, alpha),
                        a.cos() * reach * part - 1.0,
                        by + a.sin() * reach * part + 8.0 * part * part - 1.0,
                        2.0,
                        2.0,
                    );
                }
                cr.set_matrix(saved);
            }
        }
    }

    /// The rockets on their way up and the sparks of their bursts and tails, and the numbers written in sparks,
    /// where they are on this screen. They move in global coordinates (`figures.rs`).
    pub(super) fn draw_embers(&mut self, st: &SceneState) {
        let (ox, oy) = (self.rect.x as f32, self.rect.y as f32);
        let (w, h) = (self.w as f32, self.h as f32);
        for e in st.embers {
            let (x, y) = (e.x - ox, e.y - oy);
            if x < -20.0 || y < -20.0 || x > w + 20.0 || y > h + 20.0 {
                continue;
            }
            let life = if e.holds { (e.life / 0.3).min(1.0) } else { e.life / e.max };
            let a = (255.0 * life.clamp(0.0, 1.0)) as u8;
            let r = e.size * 1.1;
            self.mark(x - r, y - r, 2.0 * r, 2.0 * r);
            let cr = &self.canvas.cr;
            let (x, y, r) = (x as f64, y as f64, r as f64);
            match e.colour {
                // a rocket's spark in its burst's colour: a soft dot with a light middle
                Some(i) => {
                    let col = CONFETTI[i % CONFETTI.len()];
                    let light = |v: u8| ((v as u16 + 255) / 2) as u8;
                    fill_ellipse(cr, ((a as u16 * 110 / 255) as u8, col.1, col.2, col.3), x - r, y - r, 2.0 * r, 2.0 * r);
                    fill_ellipse(cr, (a, col.1, col.2, col.3), x - r * 0.6, y - r * 0.6, r * 1.2, r * 1.2);
                    fill_ellipse(cr, (a, light(col.1), light(col.2), light(col.3)), x - r * 0.3, y - r * 0.3, r * 0.6, r * 0.6);
                }
                // a spark of a rocket's tail
                None => fill_ellipse(cr, (a, 255, 220, 120), x - r * 0.45, y - r * 0.45, r * 0.9, r * 0.9),
            }
        }
        for rocket in st.rockets {
            let (x, y, k) = (rocket.x - ox, rocket.y - oy, 7.0 * rocket.scale);
            if x < -20.0 || y < -20.0 || x > w + 20.0 || y > h + 20.0 {
                continue;
            }
            self.mark(x - k, y - k, 2.0 * k, 2.0 * k);
            let cr = &self.canvas.cr;
            let (x, y, k) = (x as f64, y as f64, k as f64);
            fill_ellipse(cr, WHITE, x - k * 0.3, y - k * 0.3, k * 0.6, k * 0.6);
            flat(cr, WHITE, 1.0, x - k, y, x + k, y);
            flat(cr, WHITE, 1.0, x, y - k, x, y + k);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn confetti_pictures_are_laid_out_as_the_leaves() {
        let sprites = make_confetti_sprites().unwrap();
        assert_eq!(sprites.len(), 10, "ten pictures, as the leaves'");
        for (i, s) in sprites.iter().enumerate() {
            assert_eq!(s.len(), LEAF_PX * LEAF_PX);
            assert!(s.iter().any(|p| p >> 24 != 0), "picture {i} is empty");
        }
    }

    #[test]
    fn the_clock_and_a_guest_draw_at_every_step() {
        let img = Image::new(200, 200).unwrap();
        for stage in 1..=12 {
            img.cr.identity_matrix();
            img.cr.translate(100.0, 180.0);
            party_clock(&img.cr, stage, 0.97, 0.9, Some(0.5));
        }
        for look in 0..GUESTS.len() {
            for (walking, waving, carries_gift) in [(true, false, false), (false, true, false), (false, false, true)] {
                img.cr.identity_matrix();
                img.cr.translate(100.0, 180.0);
                let pose =
                    GuestPose { look, gift: look, walking, waving, carries_gift, walk: 1.0, stand: 1.0, wave: 1.0 };
                guest(&img.cr, pose);
            }
        }
        sweeper(&img.cr, 12.0, 3.0);
        img.surface.flush();
        assert!(img.pixels.iter().any(|p| p >> 24 != 0));
    }

    #[test]
    fn a_lit_bulb_stays_inside_its_box() {
        // the box the light string restores when a bulb twinkles (`lights.rs`): 28 x 29 units from 14 to the left
        // of the bulb and 1 above it
        let s = 2.0;
        for idx in 0..4 {
            let img = Image::new(200, 200).unwrap();
            party_bulb(&img.cr, idx, 100.0, 60.0, s, Some(1.0));
            img.surface.flush();
            for y in 0..200i32 {
                for x in 0..200i32 {
                    if img.pixels[(y * 200 + x) as usize] >> 24 == 0 {
                        continue;
                    }
                    let inside = (x as f64) >= 100.0 - 14.0 * s - 2.0
                        && (x as f64) <= 100.0 + 14.0 * s + 2.0
                        && (y as f64) >= 60.0 - 2.0
                        && (y as f64) <= 60.0 + 28.0 * s + 2.0;
                    assert!(inside, "bulb {idx} draws at ({x}, {y}), outside its box");
                }
            }
        }
    }
}
