//! Carnival (setting `Theme` = 5), as in the macOS version (`OverlayKarneval.swift`) and the Windows one
//! (`src/LayerKarneval.cs`): Rio's parade, each Christmas element in its carnival form. Confetti, streamers and
//! feathers fall and pile up in the leaves' place (New Year's confetti with some of its pictures changed,
//! `make_carnival_sprites`); here are the carnival float built step by step in the snowman's place, the truck with
//! a band on it that drives along the ground in Santa's, the people of a samba parade in the nisser's (walking in
//! time with the drums: `SceneState::beat_count`), the fringe garland with masks behind the lights, the toucans on
//! the window edges, and the street sweepers of Ash Wednesday in the plow's. The Rhineland's form of each is in
//! `karneval_rhein.rs`, and every entry here hands over to it.
//! Nothing here shows or suggests drinking. The figures are original, clothed and friendly. The drawing is kept
//! line for line the same as in the other two versions.

use cairo::{Context, FillRule, LineCap};

use super::draw::*;
use super::muertos::{bezier, c, fill_with, flat, round, shade};
use super::nytaar::{make_confetti_sprites, CONFETTI};
use super::{Layer, SceneState, LEAF_PX};
use crate::figures::DONKEY_STRIDE;
use crate::folk::CARNIVAL_RHEIN;
use crate::x11::Res;

pub(super) const K_INK: Argb = rgb(38, 34, 52);
pub(super) const K_GOLD: Argb = rgb(240, 196, 64);
pub(super) const K_SKINS: [Argb; 5] =
    [rgb(255, 214, 186), rgb(206, 150, 106), rgb(140, 92, 62), rgb(236, 190, 150), rgb(110, 72, 50)];
/// Carnival's bright colours.
const COLOURS: [Argb; 7] = [
    rgb(255, 64, 129),
    rgb(0, 176, 140),
    rgb(255, 196, 0),
    rgb(60, 120, 230),
    rgb(160, 80, 220),
    rgb(255, 120, 30),
    rgb(40, 190, 80),
];
const PI: f64 = std::f64::consts::PI;

/// One piece of a closed outline: where it starts, a straight line on to a point, or a curve with two control
/// points on to a point (as `Shape().Start().To().Curve()` on Windows).
#[derive(Clone, Copy)]
pub(super) enum Seg {
    M(f64, f64),
    L(f64, f64),
    C(f64, f64, f64, f64, f64, f64),
}
use Seg::{C, L, M};

/// Makes the closed outline the current path.
pub(super) fn shape(cr: &Context, segs: &[Seg]) {
    cr.new_path();
    for seg in segs {
        match *seg {
            M(x, y) => cr.move_to(x, y),
            L(x, y) => cr.line_to(x, y),
            C(x1, y1, x2, y2, x, y) => cr.curve_to(x1, y1, x2, y2, x, y),
        }
    }
    cr.close_path();
}

pub(super) fn fill_shape(cr: &Context, col: Argb, segs: &[Seg]) {
    shape(cr, segs);
    fill_with(cr, col);
}

// ---------------------------------------------------------------------- confetti with feathers or sweets
/// What falls and piles up at carnival: New Year's ten confetti pictures (laid out as the leaves', so the leaves'
/// code lets them fall and pile up), with two of them changed into a feather (Rio) or a wrapped sweet, a Kamelle
/// (the Rhineland): one of the pieces of paper and one of the streamers, so one pick in five gets one, in two
/// colours. (Windows has a sixth picture for every colour instead; here the number of pictures is the leaves'.)
pub(super) fn make_carnival_sprites(sweets: bool) -> Res<Vec<Vec<u32>>> {
    let mut all = make_confetti_sprites()?;
    let m = LEAF_PX as f64 / 2.0;
    for (slot, colour) in [(4usize, CONFETTI[2]), (9, CONFETTI[3])] {
        let img = Image::new(LEAF_PX as i32, LEAF_PX as i32)?;
        let cr = &img.cr;
        let (light, quill) = (shade(colour, 1.2), shade(colour, 0.7));
        if sweets {
            // a sweet in a paper twisted at both ends
            fill_polygon(cr, light, &[(6.0, m - 12.0), (20.0, m - 4.0), (20.0, m + 4.0), (6.0, m + 12.0)]);
            fill_polygon(cr, light, &[(58.0, m - 12.0), (44.0, m - 4.0), (44.0, m + 4.0), (58.0, m + 12.0)]);
            fill_ellipse(cr, colour, 16.0, m - 11.0, 32.0, 22.0);
            fill_ellipse(cr, c(255, 255, 255, 110), 22.0, m - 8.0, 12.0, 6.0);
            flat(cr, quill, 2.0, 26.0, m - 10.0, 26.0, m + 10.0);
            flat(cr, quill, 2.0, 38.0, m - 10.0, 38.0, m + 10.0);
        } else {
            // a feather: a curved quill with a soft vane to both sides, the tip at the right
            fill_shape(
                cr,
                colour,
                &[
                    M(12.0, m + 2.0),
                    C(24.0, m - 18.0, 48.0, m - 18.0, 60.0, m - 4.0),
                    C(50.0, m + 14.0, 26.0, m + 16.0, 12.0, m + 2.0),
                ],
            );
            bezier(cr, quill, 2.0, [4.0, m + 4.0, 20.0, m + 2.0, 44.0, m - 2.0, 60.0, m - 4.0]);
            let barb = shade(colour, 0.82);
            for k in 0..5 {
                let k = k as f64;
                flat(cr, barb, 1.2, 18.0 + k * 8.0, m + 1.0 - k * 0.8, 23.0 + k * 8.0, m - 9.0 + k * 0.6);
            }
        }
        img.surface.flush();
        if let Some(picture) = all.get_mut(slot) {
            picture.clone_from(&img.pixels);
        }
    }
    Ok(all)
}

// ---------------------------------------------------------------------- small people, shared by float, truck and sweepers
/// A small person standing at (x, 0), `h` tall: legs, a body in cloth, a head. `sway` leans it; `arm` is the near
/// arm's angle from straight down (radians, positive forward); `step` swings the legs. For the band and the
/// sweepers.
pub(super) struct SmallPerson {
    pub x: f64,
    pub h: f64,
    pub cloth: Argb,
    pub skin: Argb,
    pub legs: Argb,
    pub sway: f64,
    pub arm: f64,
    pub step: f64,
}

pub(super) fn small_person(cr: &Context, p: SmallPerson) {
    let k = p.h / 40.0;
    let saved = cr.matrix();
    cr.translate(p.x, 0.0);
    cr.scale(k, k);
    round(cr, p.legs, 3.4, -2.0, -14.0, -2.0 + p.step.sin() * 5.0, 0.0);
    round(cr, p.legs, 3.4, 2.0, -14.0, 2.0 - p.step.sin() * 5.0, 0.0);
    cr.translate(0.0, -14.0);
    cr.rotate(p.sway);
    fill_shape(
        cr,
        p.cloth,
        &[
            M(-5.5, -18.0),
            L(5.5, -18.0),
            C(6.5, -11.0, 6.5, -5.0, 6.0, 1.0),
            L(-6.0, 1.0),
            C(-6.5, -5.0, -6.5, -11.0, -5.5, -18.0),
        ],
    );
    fill_ellipse(cr, p.skin, -5.5, -30.0, 12.0, 12.0);
    fill_ellipse(cr, K_INK, 2.0, -25.6, 1.8, 2.2);
    let (hx, hy) = (p.arm.sin() * 9.0, -15.0 + p.arm.cos() * 9.0);
    round(cr, shade(p.cloth, 0.85), 3.0, 0.0, -15.0, hx, hy);
    fill_ellipse(cr, p.skin, hx - 2.0, hy - 2.0, 4.0, 4.0);
    cr.set_matrix(saved);
}

// ---------------------------------------------------------------------- the float
/// Carnival's form of the snowman: a float (carro alegórico) being built, a step for every hour the app runs, in
/// the same place and frame as the snowman. Origin at the ground, y up is negative.
pub(super) fn parade_float(cr: &Context, stage: i32, rhein: bool) {
    if rhein {
        super::karneval_rhein::prunkwagen(cr, stage);
        return;
    }
    let cols = COLOURS;
    let n = cols.len();
    let (wood, dark) = (rgb(120, 84, 52), rgb(46, 44, 60));
    fill_ellipse(cr, c(20, 16, 30, 55), -58.0, -3.0, 116.0, 6.0);
    // 1: the chassis on its wheels
    fill_rect(cr, wood, -54.0, -14.0, 108.0, 5.0);
    for wx in [-38.0, 0.0, 38.0] {
        fill_ellipse(cr, dark, wx - 7.0, -14.0, 14.0, 14.0);
        fill_ellipse(cr, rgb(150, 154, 166), wx - 2.5, -9.5, 5.0, 5.0);
    }
    // 2: the lower deck
    if stage >= 2 {
        fill_rect(cr, cols[3], -56.0, -30.0, 112.0, 17.0);
        fill_rect(cr, shade(cols[3], 0.8), -56.0, -17.0, 112.0, 4.0);
    }
    // 3: a skirt with a fringe that hides the wheels
    if stage >= 3 {
        fill_rect(cr, cols[0], -57.0, -14.0, 114.0, 10.0);
        for k in 0..19 {
            let x = -57.0 + k as f64 * 6.0;
            fill_polygon(cr, if k % 2 == 0 { cols[2] } else { cols[0] }, &[(x, -4.0), (x + 6.0, -4.0), (x + 3.0, 1.5)]);
        }
    }
    // 4: the upper deck, and steps up to it
    if stage >= 4 {
        fill_rect(cr, cols[1], -36.0, -48.0, 72.0, 18.0);
        fill_rect(cr, shade(cols[1], 0.8), -36.0, -33.0, 72.0, 3.0);
        for k in 0..3 {
            let k = k as f64;
            fill_rect(cr, rgb(250, 240, 220), -52.0 + k * 5.0, -34.0 - k * 4.6, 6.0, 4.6 * (k + 1.0));
        }
    }
    // 5: gold trim along both decks
    if stage >= 5 {
        fill_rect(cr, K_GOLD, -56.0, -31.5, 112.0, 2.4);
        fill_rect(cr, K_GOLD, -36.0, -49.5, 72.0, 2.4);
        for k in 0..9 {
            fill_ellipse(cr, K_GOLD, -52.0 + k as f64 * 13.0, -25.0, 4.0, 4.0);
        }
    }
    // 6: two columns
    if stage >= 6 {
        for cx in [-30.0, 30.0] {
            fill_rect(cr, rgb(250, 244, 230), cx - 3.5, -86.0, 7.0, 37.0);
            fill_rect(cr, rgb(222, 212, 192), cx + 1.0, -86.0, 2.5, 37.0);
            fill_rect(cr, K_GOLD, cx - 5.5, -89.0, 11.0, 3.4);
            fill_rect(cr, K_GOLD, cx - 5.5, -52.0, 11.0, 3.0);
        }
    }
    // 7: a great sun between them, 8: its rays, 9: its face
    if stage >= 8 {
        for k in 0..16 {
            let a = k as f64 * PI / 8.0;
            let (r0, r1) = (19.0, if k % 2 == 0 { 32.0 } else { 26.0 });
            fill_polygon(
                cr,
                if k % 2 == 0 { rgb(255, 170, 30) } else { K_GOLD },
                &[
                    ((a - 0.14).cos() * r0, -84.0 + (a - 0.14).sin() * r0),
                    (a.cos() * r1, -84.0 + a.sin() * r1),
                    ((a + 0.14).cos() * r0, -84.0 + (a + 0.14).sin() * r0),
                ],
            );
        }
    }
    if stage >= 7 {
        fill_ellipse(cr, rgb(255, 170, 30), -21.0, -105.0, 42.0, 42.0);
        fill_ellipse(cr, rgb(255, 214, 80), -18.0, -102.0, 36.0, 36.0);
    }
    if stage >= 9 {
        fill_ellipse(cr, K_INK, -8.5, -89.0, 4.0, 5.0);
        fill_ellipse(cr, K_INK, 4.5, -89.0, 4.0, 5.0);
        bezier(cr, K_INK, 1.6, [-9.0, -79.0, -4.0, -72.0, 4.0, -72.0, 9.0, -79.0]);
        fill_ellipse(cr, c(255, 140, 90, 150), -14.0, -82.0, 6.0, 4.0);
        fill_ellipse(cr, c(255, 140, 90, 150), 8.0, -82.0, 6.0, 4.0);
    }
    // 10: fans of feathers at both ends
    if stage >= 10 {
        for side in [-1.0, 1.0] {
            for k in 0..5usize {
                let a = -PI / 2.0 + side * (0.25 + k as f64 * 0.26);
                let col = cols[(k + if side < 0.0 { 0 } else { 3 }) % n];
                let (tx, ty) = (side * 46.0 + a.cos() * 30.0, -32.0 + a.sin() * 30.0);
                bezier(
                    cr,
                    shade(col, 0.8),
                    1.2,
                    [side * 46.0, -32.0, side * 46.0 + a.cos() * 12.0, -32.0 + a.sin() * 14.0, tx - side * 2.0, ty + 4.0, tx, ty],
                );
                let saved = cr.matrix();
                cr.translate(side * 46.0 + a.cos() * 20.0, -32.0 + a.sin() * 20.0);
                cr.rotate(a);
                fill_ellipse(cr, col, -11.0, -3.4, 22.0, 6.8);
                cr.set_matrix(saved);
            }
        }
    }
    // 11: coloured bulbs along the decks
    if stage >= 11 {
        for k in 0..12usize {
            fill_ellipse(cr, cols[k % n], -55.0 + k as f64 * 9.6, -35.5, 4.4, 4.4);
        }
        for k in 0..8usize {
            fill_ellipse(cr, cols[(k + 2) % n], -35.0 + k as f64 * 9.4, -53.5, 4.2, 4.2);
        }
    }
    // 12: streamers from the columns, and a pennant on each
    if stage >= 12 {
        for side in [-1.0, 1.0] {
            bezier(cr, cols[0], 1.6, [side * 30.0, -88.0, side * 44.0, -84.0, side * 40.0, -66.0, side * 52.0, -60.0]);
            bezier(cr, cols[2], 1.6, [side * 30.0, -88.0, side * 38.0, -76.0, side * 48.0, -78.0, side * 56.0, -70.0]);
            flat(cr, wood, 1.2, side * 30.0, -89.0, side * 30.0, -108.0);
            fill_polygon(
                cr,
                cols[if side < 0.0 { 4 } else { 5 }],
                &[(side * 30.0, -108.0), (side * 30.0 + side * 13.0, -104.0), (side * 30.0, -100.0)],
            );
        }
    }
}

// ---------------------------------------------------------------------- the samba parade
/// How a walker stands at carnival: the pose of the elf it stands in for, and the beat everyone steps to.
pub(super) struct RevellerPose {
    /// Who it is: the walker's own number (which of the eight is `look % 8`; its colours follow it too).
    pub look: usize,
    /// The elf's tunic number (varies the colours).
    pub tunic: usize,
    /// The colour of what it carries (the elf's gift's).
    pub gift: Argb,
    pub walking: bool,
    pub standing: bool,
    pub waving: bool,
    pub carries_gift: bool,
    /// The controller's beat (`SceneState::beat_count`).
    pub beat_count: f64,
}

/// One arm from the shoulder (sx, sy) at angle `a` from straight down, with a hand; returns where the hand is.
pub(super) fn k_arm(cr: &Context, sx: f64, sy: f64, a: f64, sleeve: Argb, skin: Argb) -> (f64, f64) {
    let (hx, hy) = (sx + a.sin() * 10.0, sy + a.cos() * 10.0);
    round(cr, sleeve, 3.2, sx, sy, hx, hy);
    fill_ellipse(cr, skin, hx - 2.2, hy - 2.2, 4.4, 4.4);
    (hx, hy)
}

/// The wide skirt of the flag bearer and the baiana; `spin` (0-1) swings it out.
fn k_skirt(cr: &Context, col: Argb, trim: Argb, spin: f64) {
    let wide = 15.0 + spin * 4.0;
    fill_shape(
        cr,
        col,
        &[
            M(-5.0, -24.0),
            L(5.0, -24.0),
            C(9.0, -18.0, wide, -8.0, wide + 1.0, -1.0),
            L(-wide - 1.0, -1.0),
            C(-wide, -8.0, -9.0, -18.0, -5.0, -24.0),
        ],
    );
    fill_rect(cr, trim, -wide - 1.0, -3.4, 2.0 * wide + 2.0, 2.6);
    let faint = (150, trim.1, trim.2, trim.3);
    for k in 0..4 {
        let k = k as f64;
        flat(cr, faint, 0.8, -3.0 + k * 2.0, -22.0, (-wide + 4.0) + k * (2.0 * wide - 8.0) / 3.0, -4.0);
    }
}

/// The jacket most of the walkers wear.
const JACKET: [Seg; 5] =
    [M(-5.5, -33.0), L(5.5, -33.0), C(6.5, -26.0, 6.5, -19.0, 6.0, -13.0), L(-6.0, -13.0), C(-6.5, -19.0, -6.5, -26.0, -5.5, -33.0)];

/// The face every walker has (in the head's own frame).
pub(super) fn k_face(cr: &Context) {
    fill_ellipse(cr, c(250, 150, 140, 130), 1.6, 0.4, 3.6, 2.6);
    fill_ellipse(cr, K_INK, 1.6, -2.2, 1.9, 2.5);
    fill_ellipse(cr, K_INK, 4.5, -2.2, 1.5, 2.3);
    bezier(cr, K_INK, 0.8, [1.2, 2.2, 2.8, 4.6, 4.8, 4.6, 5.8, 2.2]);
}

/// Carnival's walkers: the people of a samba parade. They are nisser in everything but looks (they walk, stop,
/// wave, cross to the next screen and meet), and who each one is follows the walker itself (`RevellerPose::look`),
/// not what it carries: the flag bearer and her escort, a baiana in a wide skirt, a dancer in a feather headdress,
/// two drummers, Pierrot and Harlequin. They step, stand and wave in time with the drums: the phases come from
/// the controller's beat, so every one on every screen moves together.
/// Drawn like a nisse: feet at (0, 0), y up is negative, facing right.
pub(super) fn reveller(cr: &Context, pose: &RevellerPose, rhein: bool) {
    // each on the beat or just off it; a walking step takes two beats, standing and waving one bar
    let beats = pose.beat_count + (pose.look % 2) as f64;
    let (walking, waving) = (pose.walking, pose.waving);
    let p = if walking { (beats / 4.0 - (beats / 4.0).floor()) * 4.0 * PI } else { 0.0 };
    let bar = (beats / 2.0 - (beats / 2.0).floor()) * 2.0 * PI;
    let stand_phase = if pose.standing { bar } else { 0.0 };
    let wave_phase = if waving { bar } else { 0.0 };
    if rhein {
        super::karneval_rhein::jeck(cr, pose, p, stand_phase, wave_phase);
        return;
    }
    let (look, tunic) = (pose.look, pose.tunic);
    let who = look % 8;
    let beat = if walking {
        p
    } else if waving {
        wave_phase
    } else {
        stand_phase
    };
    let leg_a = if walking { p.sin() * 0.5 } else { beat.sin() * 0.12 };
    // everyone bounces on the beat, also standing still
    let bob = -beat.sin().abs() * if waving { 3.0 } else { 1.5 };
    let skin = K_SKINS[(look * 3 + tunic) % K_SKINS.len()];
    let cols = COLOURS;
    let ink = K_INK;
    let (own, second) = (cols[(look + tunic * 2) % cols.len()], cols[(look + tunic * 2 + 3) % cols.len()]);
    let (white, cream, lace, straw) = (rgb(248, 246, 240), rgb(250, 246, 236), rgb(252, 250, 246), rgb(238, 214, 150));
    let stick = rgb(150, 110, 60);
    fill_ellipse(cr, c(30, 20, 40, 50), -11.0, -2.0, 22.0, 4.0);

    // what each one wears below the waist: a wide skirt to the ground, or legs
    let wide_skirt = who == 0 || who == 2;
    let spin = if waving { wave_phase.sin().abs() } else { 0.0 };
    if !wide_skirt {
        let leg_col = match who {
            1 | 6 => white,
            7 => second,
            3 => skin,
            _ => shade(own, 0.6),
        };
        for (hx, a) in [(-2.0, leg_a), (2.0, -leg_a)] {
            let (fx, fy) = (hx + a.sin() * 13.0, -14.0 + bob + a.cos() * 13.0);
            round(cr, leg_col, if who == 3 { 3.0 } else { 4.0 }, hx, -14.0 + bob, fx, fy);
            fill_ellipse(cr, if who == 3 { K_GOLD } else { ink }, fx - 3.0, fy - 2.0, 8.0, 4.2);
        }
    }
    let body = cr.matrix();
    cr.translate(0.0, bob);

    let swing = if walking { p.sin() * 0.8 } else { beat.sin() * 0.3 };
    match who {
        0 => {
            // the flag bearer (porta-bandeira): a wide gown, and the flag held high
            k_arm(cr, -1.0, -31.0, -0.5 - swing * 0.2, cream, skin);
            k_skirt(cr, cream, K_GOLD, spin);
            fill_rect(cr, cream, -5.0, -33.0, 10.0, 10.0);
            fill_rect(cr, K_GOLD, -5.0, -26.0, 10.0, 2.0);
            let (hx, hy) = k_arm(cr, 1.0, -31.0, 2.5, cream, skin);
            flat(cr, stick, 1.4, hx, hy + 6.0, hx + 2.0, hy - 30.0);
            let wave = (beat * 2.0).sin() * 2.0;
            fill_shape(
                cr,
                own,
                &[
                    M(hx + 2.0, hy - 30.0),
                    C(hx + 8.0, hy - 33.0 + wave, hx + 14.0, hy - 27.0 - wave, hx + 20.0, hy - 30.0 + wave),
                    L(hx + 20.0, hy - 17.0 + wave),
                    C(hx + 14.0, hy - 14.0 - wave, hx + 8.0, hy - 20.0 + wave, hx + 1.4, hy - 17.0),
                ],
            );
            fill_ellipse(cr, K_GOLD, hx + 8.0, hy - 27.0, 6.0, 6.0);
        }
        1 => {
            // her escort (mestre-sala): a white suit and a straw hat, lifted in a bow when he "waves"
            k_arm(cr, -1.0, -31.0, -1.2 + swing * 0.3, white, skin);
            fill_shape(cr, white, &JACKET);
            fill_rect(cr, own, -6.0, -19.0, 12.0, 2.4);
            fill_polygon(cr, own, &[(2.0, -33.0), (5.5, -33.0), (4.6, -26.0)]);
            let (hx, hy) = k_arm(cr, 1.0, -31.0, if waving { 2.4 } else { 1.2 - swing * 0.3 }, white, skin);
            if waving {
                fill_ellipse(cr, straw, hx - 7.0, hy - 4.0, 14.0, 4.0);
                fill_rect(cr, straw, hx - 4.0, hy - 8.0, 8.0, 5.0);
                fill_rect(cr, own, hx - 4.0, hy - 5.0, 8.0, 1.6);
            }
        }
        2 => {
            // a baiana: white lace, a wide skirt that swings out when she spins, a head wrap and beads
            k_arm(cr, -1.0, -31.0, -1.3 - spin * 0.6, lace, skin);
            k_skirt(cr, lace, rgb(214, 226, 240), spin);
            fill_rect(cr, lace, -5.5, -33.0, 11.0, 10.0);
            bezier(cr, own, 1.4, [-4.0, -32.0, -2.0, -27.0, 2.0, -27.0, 4.0, -32.0]);
            bezier(cr, second, 1.4, [-4.6, -31.0, -2.0, -24.5, 2.0, -24.5, 4.6, -31.0]);
            k_arm(cr, 1.0, -31.0, 1.3 + spin * 0.6, lace, skin);
        }
        3 => {
            // a dancer (passista): a sequin dress and a headdress of feathers, arms up
            k_arm(cr, -1.0, -31.0, -2.4 + beat.sin() * 0.4, own, skin);
            fill_shape(
                cr,
                own,
                &[
                    M(-5.0, -33.0),
                    L(5.0, -33.0),
                    C(6.0, -26.0, 8.5, -19.0, 9.5, -14.0),
                    L(-9.5, -14.0),
                    C(-8.5, -19.0, -6.0, -26.0, -5.0, -33.0),
                ],
            );
            for k in 0..6 {
                let x = k as f64 * 3.2;
                let col = if k % 2 == 0 { second } else { K_GOLD };
                fill_polygon(cr, col, &[(-9.5 + x, -14.0), (-6.3 + x, -14.0), (-7.9 + x, -9.5)]);
            }
            for (sx, sy) in [(-3.0, -28.0), (2.0, -25.0), (-1.0, -20.0), (4.0, -19.0), (-5.0, -17.0)] {
                fill_ellipse(cr, c(255, 250, 220, 230), sx, sy, 1.5, 1.5);
            }
            k_arm(cr, 1.0, -31.0, 2.4 + beat.sin() * 0.4, own, skin);
        }
        4 => {
            // the big drum (surdo): carried on a strap, struck on every beat
            k_arm(cr, -1.0, -31.0, 0.9, own, skin);
            fill_rect(cr, own, -5.5, -33.0, 11.0, 18.0);
            fill_rect(cr, second, -5.5, -27.0, 11.0, 2.2);
            fill_rect(cr, second, -5.5, -22.0, 11.0, 2.2);
            fill_rect(cr, shade(own, 0.6), -5.0, -16.0, 10.0, 3.0);
            flat(cr, ink, 1.2, -4.0, -33.0, 6.0, -22.0);
            fill_rect(cr, rgb(214, 220, 230), 3.0, -27.0, 13.0, 15.0);
            fill_rect(cr, rgb(150, 156, 170), 3.0, -27.0, 13.0, 2.0);
            fill_rect(cr, rgb(150, 156, 170), 3.0, -14.0, 13.0, 2.0);
            fill_ellipse(cr, cream, 3.0, -29.0, 13.0, 4.0);
            let (hx, hy) = k_arm(cr, 1.0, -31.0, 1.5 + beat.sin().abs() * 0.9, own, skin);
            flat(cr, stick, 1.4, hx, hy, hx + 5.0, hy + 3.5);
            fill_ellipse(cr, cream, hx + 3.6, hy + 2.0, 4.0, 4.0);
        }
        5 => {
            // the small drum (tamborim): held up in one hand, a stick in the other
            let (bx, by) = k_arm(cr, -1.0, -31.0, 2.2, own, skin);
            fill_rect(cr, own, -5.5, -33.0, 11.0, 18.0);
            fill_rect(cr, second, -5.5, -24.0, 11.0, 3.0);
            fill_rect(cr, shade(own, 0.6), -5.0, -16.0, 10.0, 3.0);
            fill_ellipse(cr, K_GOLD, bx - 5.0, by - 6.0, 10.0, 6.0);
            fill_ellipse(cr, cream, bx - 4.0, by - 5.6, 8.0, 4.2);
            let (hx, hy) = k_arm(cr, 1.0, -31.0, 2.3 + (beat * 2.0).sin().abs() * 0.5, own, skin);
            flat(cr, stick, 1.2, hx, hy, hx - 7.0, hy - 3.0);
        }
        6 => {
            // Pierrot: baggy white with black pompoms, a ruff and a black cap
            k_arm(cr, -1.0, -31.0, -swing, white, skin);
            fill_shape(
                cr,
                white,
                &[
                    M(-6.0, -33.0),
                    L(6.0, -33.0),
                    C(9.0, -25.0, 9.0, -18.0, 7.5, -12.0),
                    L(-7.5, -12.0),
                    C(-9.0, -18.0, -9.0, -25.0, -6.0, -33.0),
                ],
            );
            for dy in [-27.0, -21.0, -15.5] {
                fill_ellipse(cr, ink, 0.6, dy, 3.2, 3.2);
            }
            for k in 0..5 {
                fill_ellipse(cr, rgb(232, 236, 244), -7.0 + k as f64 * 3.0, -35.4, 4.4, 4.0);
            }
            k_arm(cr, 1.0, -31.0, if waving { 2.6 + wave_phase.sin() * 0.4 } else { swing }, white, skin);
        }
        _ => {
            // Harlequin: a suit of diamonds in two colours, and a two-cornered hat
            k_arm(cr, -1.0, -31.0, -swing, own, skin);
            cr.save().ok();
            shape(cr, &JACKET);
            cr.clip();
            fill_rect(cr, own, -8.0, -34.0, 16.0, 22.0);
            for row in 0..5 {
                for col in 0..4 {
                    let cx = -6.0 + col as f64 * 4.0 + if row % 2 == 0 { 0.0 } else { 2.0 };
                    let cy = -32.0 + row as f64 * 4.4;
                    fill_polygon(cr, second, &[(cx, cy - 2.2), (cx + 2.0, cy), (cx, cy + 2.2), (cx - 2.0, cy)]);
                }
            }
            cr.restore().ok();
            fill_polygon(cr, rgb(250, 250, 250), &[(-4.0, -34.0), (4.0, -34.0), (0.0, -30.5)]);
            k_arm(cr, 1.0, -31.0, if waving { 2.6 + wave_phase.sin() * 0.4 } else { swing }, second, skin);
        }
    }

    // a shaker (chocalho) in the hand of those who carry something: it is what changes hands at a meeting
    if pose.carries_gift && !waving && who != 0 && who != 4 && who != 5 {
        flat(cr, stick, 1.4, 11.0, -22.0, 14.0, -16.0);
        fill_ellipse(cr, pose.gift, 6.5, -28.0, 8.0, 7.0);
        fill_ellipse(cr, c(255, 255, 255, 120), 8.0, -27.0, 2.4, 2.4);
    }

    // the head, nodding with the beat
    cr.translate(1.0, -40.0);
    cr.rotate(beat.sin() * 0.07);
    fill_ellipse(cr, skin, -6.5, -6.5, 13.0, 13.0);
    if who == 6 {
        // Pierrot's white face
        fill_ellipse(cr, rgb(250, 250, 250), -6.5, -6.5, 13.0, 13.0);
    }
    k_face(cr);
    // what each one wears on the head
    match who {
        0 => fill_polygon(
            cr,
            K_GOLD,
            &[(-5.0, -6.0), (-3.0, -11.0), (-1.0, -7.5), (1.0, -12.0), (3.0, -7.5), (5.5, -11.0), (6.0, -6.0)],
        ),
        1 => {
            // (lifted off, it is in his hand)
            if !waving {
                fill_ellipse(cr, straw, -8.5, -8.0, 17.0, 4.4);
                fill_rect(cr, straw, -5.0, -12.4, 10.0, 5.6);
                fill_rect(cr, own, -5.0, -8.8, 10.0, 1.8);
            }
        }
        2 => {
            fill_ellipse(cr, lace, -7.0, -11.5, 14.0, 8.0);
            fill_ellipse(cr, rgb(226, 232, 242), -3.0, -13.5, 7.0, 5.0);
        }
        3 => {
            for k in 0..7 {
                let a = -PI / 2.0 + (k as f64 - 3.0) * 0.3;
                let head = cr.matrix();
                cr.translate(a.cos() * 11.0, -6.0 + a.sin() * 11.0);
                cr.rotate(a);
                fill_ellipse(cr, if k % 2 == 0 { own } else { second }, -8.0, -2.4, 16.0, 4.8);
                cr.set_matrix(head);
            }
            fill_rect(cr, K_GOLD, -6.0, -7.6, 12.0, 2.6);
        }
        4 => {
            fill_ellipse(cr, second, -7.0, -8.6, 14.0, 5.4);
            fill_rect(cr, second, 2.0, -6.4, 7.0, 2.0);
        }
        5 => {
            fill_ellipse(cr, straw, -8.0, -8.0, 16.0, 4.2);
            fill_rect(cr, straw, -4.6, -11.6, 9.2, 4.6);
        }
        6 => fill_ellipse(cr, ink, -6.6, -8.6, 13.2, 6.0),
        _ => {
            fill_polygon(cr, ink, &[(-9.0, -5.0), (-6.0, -10.0), (0.0, -8.0), (6.0, -10.0), (9.0, -5.0)]);
            fill_ellipse(cr, own, -1.6, -11.4, 3.2, 3.2);
        }
    }
    cr.set_matrix(body);
}

// ---------------------------------------------------------------------- the band truck
/// Carnival's "flyer" in Santa's place does not fly: a truck with a band on it drives along the ground, the drums
/// playing while it passes. Drawn in Santa's frame moved down to the ground (`draw_santa_and_sparks`): facing +x,
/// origin at the ground under its middle; `t` is the trip's clock, `beat_count` the controller's beat.
pub(super) fn band_truck(cr: &Context, t: f64, beat_count: f64, rhein: bool) {
    if rhein {
        super::karneval_rhein::festwagen(cr, t, beat_count);
        return;
    }
    let cols = COLOURS;
    let n = cols.len();
    let beat = beat_count * PI;
    let (dark, body, body_dark) = (rgb(46, 44, 60), rgb(250, 196, 40), rgb(214, 150, 20));
    let roll = t * 5.0;
    // wheels
    for wx in [-78.0, -52.0, 58.0] {
        fill_ellipse(cr, dark, wx - 11.0, -22.0, 22.0, 22.0);
        fill_ellipse(cr, rgb(160, 164, 176), wx - 4.5, -15.5, 9.0, 9.0);
        for k in 0..3 {
            let a = roll + k as f64 * 2.094;
            flat(cr, dark, 1.4, wx, -11.0, wx + a.cos() * 4.5, -11.0 + a.sin() * 4.5);
        }
    }
    // the cab at the front
    fill_shape(
        cr,
        body,
        &[M(40.0, -16.0), L(40.0, -58.0), L(66.0, -58.0), C(76.0, -58.0, 84.0, -44.0, 86.0, -34.0), L(92.0, -30.0), L(92.0, -16.0)],
    );
    fill_shape(
        cr,
        rgb(178, 214, 236),
        &[M(52.0, -36.0), L(52.0, -53.0), L(66.0, -53.0), C(72.0, -53.0, 78.0, -44.0, 80.0, -36.0)],
    );
    fill_ellipse(cr, rgb(206, 150, 106), 60.0, -49.0, 8.0, 9.0);
    fill_rect(cr, body_dark, 40.0, -22.0, 52.0, 6.0);
    fill_ellipse(cr, rgb(255, 244, 190), 88.0, -28.0, 4.4, 5.4);
    // the bed: a stage with a fringed skirt and a row of bulbs that light in turn with the beat
    fill_rect(cr, cols[0], -104.0, -34.0, 144.0, 18.0);
    fill_rect(cr, cols[4], -104.0, -38.0, 144.0, 5.0);
    for k in 0..24 {
        let x = -104.0 + k as f64 * 6.0;
        fill_polygon(cr, if k % 2 == 0 { cols[2] } else { cols[1] }, &[(x, -16.0), (x + 6.0, -16.0), (x + 3.0, -11.0)]);
    }
    let lit = (beat_count * 2.0) as i64;
    for k in 0..12usize {
        let on = (k as i64 + lit).rem_euclid(3) == 0;
        let col = if on { rgb(255, 250, 200) } else { shade(cols[k % n], 0.75) };
        fill_ellipse(cr, col, -101.0 + k as f64 * 12.0, -30.0, 5.0, 5.0);
    }
    // stacks of loudspeakers at both ends, their cones pumping
    for sx in [-104.0, 18.0] {
        fill_rect(cr, dark, sx, -86.0, 22.0, 48.0);
        for k in 0..2 {
            let (r, y) = (7.0 + beat.sin().abs() * 1.2, k as f64 * 22.0);
            fill_ellipse(cr, rgb(96, 96, 112), sx + 11.0 - r, -74.0 + y - r, 2.0 * r, 2.0 * r);
            fill_ellipse(cr, dark, sx + 8.0, -77.0 + y, 6.0, 6.0);
        }
    }
    // the band: a singer, a guitarist and two drummers, bouncing on the beat
    for (kind, x) in [-70.0, -48.0, -24.0, 0.0].into_iter().enumerate() {
        let b = (beat + kind as f64 * 0.5 * PI).sin();
        let saved = cr.matrix();
        cr.translate(0.0, -38.0 - b.abs() * 2.0);
        small_person(
            cr,
            SmallPerson {
                x,
                h: 34.0,
                cloth: cols[(kind + 1) % n],
                skin: K_SKINS[(kind * 2 + 1) % K_SKINS.len()],
                legs: dark,
                sway: b * 0.08,
                arm: if kind == 0 { 2.3 } else { 1.2 + b.abs() * 0.7 },
                step: 0.0,
            },
        );
        match kind {
            // a microphone
            0 => fill_ellipse(cr, dark, x + 5.0, -30.0, 3.4, 3.4),
            // a small guitar
            1 => {
                fill_ellipse(cr, rgb(170, 110, 50), x - 2.0, -20.0, 10.0, 8.0);
                flat(cr, rgb(120, 80, 40), 1.6, x + 6.0, -17.0, x + 16.0, -24.0);
            }
            2 => {
                fill_rect(cr, rgb(214, 220, 230), x + 4.0, -22.0, 10.0, 11.0);
                fill_ellipse(cr, rgb(250, 246, 236), x + 4.0, -24.0, 10.0, 4.0);
            }
            _ => fill_ellipse(cr, K_GOLD, x + 5.0, -27.0, 9.0, 5.0),
        }
        cr.set_matrix(saved);
    }
    // a canopy over them, with a fringe
    flat(cr, dark, 1.6, -93.0, -86.0, -93.0, -104.0);
    flat(cr, dark, 1.6, 29.0, -86.0, 29.0, -104.0);
    fill_rect(cr, cols[1], -94.0, -110.0, 124.0, 7.0);
    for k in 0..20 {
        let x = k as f64 * 6.2;
        let col = if k % 2 == 0 { cols[2] } else { cols[0] };
        fill_polygon(cr, col, &[(-94.0 + x, -103.0), (-87.8 + x, -103.0), (-90.9 + x, -98.0)]);
    }
}

// ---------------------------------------------------------------------- the street sweepers
/// Carnival's form of the snow plow: the street sweepers of Ash Wednesday. Two sweepers in orange walk in front
/// with their brooms, one of them dancing as he sweeps, and a cart follows for what they sweep up. Facing +x,
/// origin at the ground, the brooms where the plow's blade would be. No horn and no smoke. `ph` is the height of
/// what is gathered in front, `wheel` the plow's wheel's turn (they walk at the donkey cart's pace).
pub(super) fn street_sweepers(cr: &Context, ph: f64, wheel: f64) {
    let step = wheel * DONKEY_STRIDE as f64;
    let (orange, dark, wood, trousers) = (rgb(245, 130, 30), rgb(46, 44, 60), rgb(150, 110, 60), rgb(60, 70, 110));
    let cols = COLOURS;
    let n = cols.len();
    // the cart: a bin on two wheels, confetti heaped in it, pushed by a third sweeper
    for k in 0..10usize {
        fill_rect(cr, cols[k % n], -66.0 + (k * 7 % 40) as f64, -50.0 - (k % 3) as f64 * 3.0, 5.0, 3.4);
    }
    fill_polygon(cr, rgb(60, 150, 90), &[(-74.0, -46.0), (-22.0, -46.0), (-27.0, -14.0), (-69.0, -14.0)]);
    fill_rect(cr, rgb(40, 110, 66), -76.0, -48.0, 56.0, 4.0);
    for wx in [-62.0, -34.0] {
        fill_ellipse(cr, dark, wx - 8.0, -16.0, 16.0, 16.0);
        fill_ellipse(cr, rgb(160, 164, 176), wx - 3.0, -11.0, 6.0, 6.0);
    }
    round(cr, dark, 2.0, -76.0, -44.0, -92.0, -34.0);
    small_person(
        cr,
        SmallPerson { x: -100.0, h: 46.0, cloth: orange, skin: K_SKINS[2], legs: trousers, sway: 0.08, arm: 1.3, step },
    );
    // the two with brooms: the second one dances (he turns his broom and bounces)
    for i in 0..2usize {
        let x = if i == 0 { 20.0 } else { 62.0 };
        let dance = i == 1;
        let pace = if dance { 2.0 } else { 1.0 };
        let sw = (step * pace + i as f64 * 1.4).sin();
        let saved = cr.matrix();
        cr.translate(0.0, if dance { -sw.abs() * 3.0 } else { 0.0 });
        small_person(
            cr,
            SmallPerson {
                x,
                h: 48.0,
                cloth: orange,
                skin: K_SKINS[i * 3],
                legs: trousers,
                sway: if dance { sw * 0.14 } else { 0.05 },
                arm: 0.9 + sw * 0.35,
                step: step + i as f64,
            },
        );
        // a cap, and the broom from the hands down to the ground in front
        fill_rect(cr, orange, x - 5.0, -57.5, 12.0, 3.6);
        cr.set_matrix(saved);
        let bx = x + 26.0 + sw * 7.0;
        round(cr, wood, 2.0, x + 6.0, -30.0, bx, -5.0);
        for k in 0..6 {
            let col = if k % 2 == 0 { rgb(214, 170, 72) } else { rgb(176, 132, 52) };
            round(cr, col, 1.6, bx, -6.0, bx - 6.0 + k as f64 * 3.4, 1.0);
        }
    }
    // confetti gathered in front of the brooms
    for (i, lx) in [96.0, 103.0, 110.0].into_iter().enumerate() {
        if (i as f64) * 6.0 < ph {
            fill_rect(cr, cols[(i * 2 + 1) % n], lx, -5.0 - (i % 2) as f64 * 2.4, 5.0, 3.4);
        }
    }
}

// ---------------------------------------------------------------------- the fringe garland with masks
/// One carnival mask hanging by its ribbon from (x, y): a half-mask with two eye holes and three small plumes.
fn garland_mask(cr: &Context, x: f64, y: f64, colour: Argb, plume: Argb, s: f64) {
    flat(cr, rgb(60, 50, 60), 0.9 * s, x, y, x, y + 5.0 * s);
    for k in 0..3 {
        let d = k as f64 - 1.0;
        let saved = cr.matrix();
        cr.translate(x + d * 3.4 * s, y + 7.0 * s);
        cr.rotate(-PI / 2.0 + d * 0.45);
        fill_ellipse(cr, plume, 0.0, -1.4 * s, 8.0 * s, 2.8 * s);
        cr.set_matrix(saved);
    }
    let outline = [
        M(x - 9.0 * s, y + 8.0 * s),
        C(x - 5.0 * s, y + 5.5 * s, x + 5.0 * s, y + 5.5 * s, x + 9.0 * s, y + 8.0 * s),
        C(x + 9.5 * s, y + 13.0 * s, x + 4.0 * s, y + 15.0 * s, x + 1.2 * s, y + 11.6 * s),
        L(x - 1.2 * s, y + 11.6 * s),
        C(x - 4.0 * s, y + 15.0 * s, x - 9.5 * s, y + 13.0 * s, x - 9.0 * s, y + 8.0 * s),
    ];
    // (the eye holes are left out of the shape itself: what hangs behind the mask shows through them)
    shape(cr, &outline);
    ellipse_path(cr, x - 6.4 * s, y + 8.4 * s, 4.2 * s, 2.8 * s);
    ellipse_path(cr, x + 2.2 * s, y + 8.4 * s, 4.2 * s, 2.8 * s);
    cr.set_fill_rule(FillRule::EvenOdd);
    fill_with(cr, colour);
    cr.set_fill_rule(FillRule::Winding);
    shape(cr, &outline);
    stroke(cr, K_GOLD, 0.9 * s, LineCap::Butt);
}

/// The garland along the string (which is `w` wide on a screen of scale `s`): a fringe of foil strips in bright
/// colours all the way, and a mask hanging between every two bulbs (the Rhineland: pennants and jester caps).
/// Nothing in it moves, so it is drawn once into the string's own picture (`lights.rs`); the bulbs over it are the
/// Christmas lights' own and twinkle as they do.
pub(super) fn carnival_garland(cr: &Context, w: f64, s: f64, rhein: bool) {
    if rhein {
        super::karneval_rhein::rhenish_garland(cr, w, s);
        return;
    }
    let (span, sag, top) = (230.0 * s, 22.0 * s, 1.0);
    let cols = COLOURS;
    let len = cols.len();
    let at = |x0: f64, u: f64| (x0 + u * span, top + sag * (1.0 - (2.0 * u - 1.0) * (2.0 * u - 1.0)));
    let mut n = 0usize;
    let mut x0 = -span * 0.3;
    while x0 < w {
        const STRIPS: usize = 46;
        for k in 0..STRIPS {
            let (x, y) = at(x0, (k as f64 + 0.5) / STRIPS as f64);
            let long = (7.0 + ((k * 7 + n * 3) % 5) as f64 * 1.4) * s;
            fill_rect(cr, cols[(k + n) % len], x - 1.6 * s, y, 3.2 * s, long);
        }
        for b in 0..4usize {
            let (x, y) = at(x0, b as f64 / 4.0);
            garland_mask(cr, x, y + 6.0 * s, cols[(b + n * 2) % len], cols[(b + n * 2 + 3) % len], s);
        }
        n += 1;
        x0 += span;
    }
}

// ---------------------------------------------------------------------- toucans on the window edges
/// One toucan perched on y = 0, about 30 high, looking right: black with a white throat, a big orange beak with a
/// dark tip (open when it calls), a blue ring round the eye and a tail down behind.
fn toucan(cr: &Context, calls: bool, look: f64) {
    let black = rgb(26, 26, 32);
    fill_polygon(cr, black, &[(-7.0, -8.0), (-13.0, 6.0), (-8.0, 6.0), (-3.0, -6.0)]);
    fill_ellipse(cr, black, -8.0, -22.0, 15.0, 22.0);
    fill_ellipse(cr, rgb(250, 246, 236), -1.0, -19.5, 8.5, 11.0);
    fill_ellipse(cr, rgb(232, 60, 50), -3.0, -4.0, 6.0, 4.0);
    flat(cr, rgb(110, 130, 150), 1.4, -1.0, -1.0, -1.0, 1.4);
    flat(cr, rgb(110, 130, 150), 1.4, 3.0, -1.0, 3.0, 1.4);
    let saved = cr.matrix();
    cr.translate(2.0, -22.0);
    cr.rotate(look);
    fill_ellipse(cr, black, -6.5, -6.5, 13.0, 12.5);
    // the beak: the upper half, and the lower one dropped when it calls
    fill_shape(cr, rgb(255, 150, 30), &[M(4.0, -4.0), C(11.0, -7.5, 20.0, -5.0, 22.0, 0.6), L(4.0, 0.6)]);
    fill_polygon(cr, rgb(255, 214, 80), &[(4.0, -3.4), (13.0, -5.4), (14.0, -2.6), (4.0, -1.6)]);
    fill_polygon(cr, rgb(40, 30, 30), &[(18.6, -2.6), (22.0, 0.6), (18.0, 0.6)]);
    let head = cr.matrix();
    cr.translate(4.0, 0.6);
    cr.rotate(if calls { 0.3 } else { 0.0 });
    fill_shape(cr, rgb(240, 120, 20), &[M(0.0, 0.0), L(17.0, 0.0), C(13.0, 3.6, 5.0, 4.0, 0.0, 2.8)]);
    cr.set_matrix(head);
    fill_ellipse(cr, rgb(70, 170, 230), 0.4, -4.6, 4.6, 4.6);
    fill_ellipse(cr, black, 1.9, -3.1, 1.7, 1.7);
    cr.set_matrix(saved);
}

impl Layer {
    /// Toucans sit on the window edges, one about every 380 points, at places fixed on the window; each looks
    /// about and now and then calls. Only where the edge is not hidden by a window in front. (Sizes in the window
    /// snow's unit, `ledge_u`.) The Rhineland has jester caps and doughnuts there instead
    /// (`karneval_rhein::ledge_cap` and `doughnut`): the caps' bells ring for a moment about every seven seconds,
    /// in time with the beat.
    pub(super) fn draw_ledge_carnival(&mut self, st: &SceneState) {
        if !(st.karneval() && st.window_snow) {
            return;
        }
        let rhein = st.carnival == CARNIVAL_RHEIN;
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
            let count = ((s.w / (380.0 * u)) as i32).max(1);
            for k in 0..count {
                let gx = s.x + s.w * (k as f32 + 0.5 + ((id + k * 31) % 40 - 20) as f32 / 100.0) / count as f32;
                if gx < ox - 30.0 * u || gx > ox + w + 30.0 * u || !l.is_visible(gx) {
                    continue;
                }
                let t = st.time + k as f64 * 3.7 + (id % 23) as f64;
                let (x, y) = (gx - ox, edge - l.height_at(gx) * 0.8);
                if rhein {
                    let rings = t.rem_euclid(7.3) < 0.6;
                    let ring = if !rings {
                        0.0
                    } else if ((st.beat_count * 2.0) as i64).rem_euclid(2) == 0 {
                        1.6
                    } else {
                        -1.6
                    };
                    self.mark(x - 23.0 * u, y - 28.0 * u, 46.0 * u, 32.0 * u);
                    let cr = &self.canvas.cr;
                    let saved = cr.matrix();
                    cr.translate(x as f64, y as f64);
                    cr.scale(u as f64, u as f64);
                    super::karneval_rhein::jester_cap(cr, 26.0, ring);
                    cr.set_matrix(saved);
                    // a doughnut beside every other one
                    if (id + k) % 2 != 0 || !l.is_visible(gx + 40.0 * u) {
                        continue;
                    }
                    self.mark(x + 24.0 * u, y - 19.0 * u, 32.0 * u, 22.0 * u);
                    let cr = &self.canvas.cr;
                    let saved = cr.matrix();
                    cr.translate((x + 25.0 * u) as f64, (y - 18.0 * u) as f64);
                    cr.scale(u as f64, u as f64);
                    super::karneval_rhein::doughnut(cr);
                    cr.set_matrix(saved);
                    continue;
                }
                // (it looks up for a moment every few seconds, and calls about every nine)
                let pose = if t.rem_euclid(9.1) < 0.5 {
                    2
                } else if t.rem_euclid(3.3) < 0.7 {
                    1
                } else {
                    0
                };
                let flipped = (id + k) % 2 == 1;
                self.mark(x - 27.0 * u, y - 36.0 * u, 54.0 * u, 44.0 * u);
                let cr = &self.canvas.cr;
                let saved = cr.matrix();
                cr.translate(x as f64, y as f64);
                cr.scale(if flipped { -(u as f64) } else { u as f64 }, u as f64);
                let look = match pose {
                    1 => -0.3,
                    2 => -0.12,
                    _ => 0.0,
                };
                toucan(cr, pose == 2, look);
                cr.set_matrix(saved);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn carnival_pictures_are_laid_out_as_the_leaves() {
        let confetti = make_confetti_sprites().unwrap();
        for sweets in [false, true] {
            let sprites = make_carnival_sprites(sweets).unwrap();
            assert_eq!(sprites.len(), 10, "ten pictures, as the leaves'");
            for (i, s) in sprites.iter().enumerate() {
                assert_eq!(s.len(), LEAF_PX * LEAF_PX);
                assert!(s.iter().any(|p| p >> 24 != 0), "picture {i} is empty");
                // two of them are carnival's own: a feather or a sweet
                assert_eq!(*s != confetti[i], i == 4 || i == 9, "picture {i} (sweets: {sweets})");
            }
        }
    }

    #[test]
    fn every_carnival_figure_draws_at_every_step_and_pose() {
        for rhein in [false, true] {
            let img = Image::new(600, 300).unwrap();
            let cr = &img.cr;
            cr.translate(300.0, 250.0);
            for stage in 1..=12 {
                parade_float(cr, stage, rhein);
            }
            for look in 0..16 {
                for (walking, standing, waving, carries_gift) in
                    [(true, false, false, false), (false, false, true, false), (false, true, false, true)]
                {
                    let pose = RevellerPose {
                        look,
                        tunic: look % 4,
                        gift: rgb(200, 40, 60),
                        walking,
                        standing,
                        waving,
                        carries_gift,
                        beat_count: 7.3,
                    };
                    reveller(cr, &pose, rhein);
                }
            }
            band_truck(cr, 3.0, 7.3, rhein);
            street_sweepers(cr, 12.0, 2.5);
            toucan(cr, true, -0.12);
            img.surface.flush();
            assert!(img.pixels.iter().any(|p| p >> 24 != 0));
        }
    }

    #[test]
    fn the_masks_have_eye_holes_one_can_see_through() {
        // one mask alone, on nothing: the middle of an eye hole stays empty, the cheek beside it is filled
        let s = 4.0;
        let img = Image::new(200, 200).unwrap();
        garland_mask(&img.cr, 100.0, 60.0, rgb(255, 64, 129), rgb(0, 176, 140), s);
        img.surface.flush();
        let at = |x: f64, y: f64| img.pixels[(y as usize) * 200 + x as usize] >> 24;
        assert_eq!(at(100.0 - 4.3 * s, 60.0 + 9.8 * s), 0, "the left eye hole is filled");
        assert_eq!(at(100.0 + 4.3 * s, 60.0 + 9.8 * s), 0, "the right eye hole is filled");
        assert!(at(100.0 - 7.8 * s, 60.0 + 10.5 * s) > 200, "the mask itself is missing");
    }

    #[test]
    fn both_garlands_stay_inside_the_lights_strip() {
        // the strip is 70 units high (`lights.rs`); what hangs lowest is a mask (or a jester's cap)
        let s = 2.0;
        for rhein in [false, true] {
            let img = Image::new(1000, 200).unwrap();
            carnival_garland(&img.cr, 1000.0, s, rhein);
            img.surface.flush();
            assert!(img.pixels[..1000 * 100].iter().any(|p| p >> 24 != 0), "nothing drawn (rhein: {rhein})");
            let below = (70.0 * s) as usize * 1000;
            assert!(img.pixels[below..].iter().all(|p| p >> 24 == 0), "the garland hangs below the strip (rhein: {rhein})");
        }
    }
}
