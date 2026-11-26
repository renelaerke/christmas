//! The Rhineland's street carnival (setting `Carnival` = 2), as in the macOS version
//! (`OverlayKarnevalRhein.swift`) and the Windows one (`src/LayerKarnevalRhein.cs`): the German form of the
//! Karneval theme, as it is held in Cologne, Düsseldorf and Mainz. The same slots as Rio's (`karneval.rs`, which
//! calls in here), in other clothes: confetti and wrapped sweets (Kamelle) fall, a parade wagon with a great
//! jester's head is built in the snowman's place, a tractor pulls a wagon with a prince and a brass band along the
//! ground and sweets are thrown from it, and the walkers are the people of a Rose Monday parade, marching in time:
//! a dancing guard girl and a guardsman in the red and white of the old town guards, a patchwork clown, the
//! prince, a tuba player, a drummer, a jester and a child dressed as a bee. A string of pennants and jester caps
//! hangs along the top, and jester caps and doughnuts lie on the window edges.
//! Nothing here shows or suggests drinking, the guardsman carries flowers where the real ones carry a wooden rifle
//! with a flower in it, the wagon shows no caricature of anyone, and no greeting is written on anything.

use cairo::Context;

use super::draw::*;
use super::karneval::Seg::{C, L, M};
use super::karneval::{fill_shape, k_arm, k_face, shape, small_person, RevellerPose, SmallPerson, K_GOLD, K_INK, K_SKINS};
use super::muertos::{bezier, c, flat, round, shade};

const R_RED: Argb = rgb(214, 32, 48);
const R_WHITE: Argb = rgb(250, 248, 242);
const R_BLUE: Argb = rgb(40, 90, 190);
const R_YELLOW: Argb = rgb(255, 204, 40);
const R_GREEN: Argb = rgb(40, 150, 80);
const PI: f64 = std::f64::consts::PI;

/// A jester's cap (Narrenkappe) with its points to both sides and a bell on each; its brow at (0, 0), `w` wide.
/// `ring` swings the bells.
pub(super) fn jester_cap(cr: &Context, w: f64, ring: f64) {
    let k = w / 20.0;
    let parts = [(-13.0, -9.0, R_RED), (0.0, -15.0, R_YELLOW), (13.0, -9.0, R_BLUE)];
    for (i, (tx, ty, colour)) in parts.into_iter().enumerate() {
        // (the left point starts at the brow's left end, the middle one a little in, the right one in the middle)
        let (from, to) = match i {
            0 => (-9.0 * k, k),
            1 => (-5.0 * k, 5.0 * k),
            _ => (0.0, 10.0 * k),
        };
        fill_shape(
            cr,
            colour,
            &[
                M(from, 0.0),
                C((tx - 4.0) * k, -4.0 * k, (tx - 2.0) * k, (ty + 2.0) * k, (tx + ring) * k, ty * k),
                C((tx + 3.0) * k, (ty + 4.0) * k, (tx + 5.0) * k, -3.0 * k, to, 0.0),
            ],
        );
        fill_ellipse(cr, K_GOLD, (tx + ring) * k - 1.8 * k, ty * k - 1.8 * k, 3.6 * k, 3.6 * k);
    }
    fill_rect(cr, R_WHITE, -10.0 * k, -1.6 * k, 20.0 * k, 3.2 * k);
}

// ---------------------------------------------------------------------- the parade float
/// The float in the snowman's place, the Rhineland's form (Prunkwagen): the same twelve steps as Rio's
/// (`karneval::parade_float`), in red and white with gold, and in the sun's place a great jester's head.
pub(super) fn prunkwagen(cr: &Context, stage: i32) {
    let (wood, dark) = (rgb(120, 84, 52), rgb(46, 44, 60));
    let (red, white, gold) = (R_RED, R_WHITE, K_GOLD);
    fill_ellipse(cr, c(20, 16, 30, 55), -58.0, -3.0, 116.0, 6.0);
    fill_rect(cr, wood, -54.0, -14.0, 108.0, 5.0);
    for wx in [-38.0, 0.0, 38.0] {
        fill_ellipse(cr, dark, wx - 7.0, -14.0, 14.0, 14.0);
        fill_ellipse(cr, rgb(150, 154, 166), wx - 2.5, -9.5, 5.0, 5.0);
    }
    // 2: the lower deck, in red and white lozenges
    if stage >= 2 {
        fill_rect(cr, white, -56.0, -30.0, 112.0, 17.0);
        for k in 0..14 {
            let x = -56.0 + k as f64 * 8.0;
            fill_polygon(cr, red, &[(x + 4.0, -30.0), (x + 8.0, -21.5), (x + 4.0, -13.0), (x, -21.5)]);
        }
    }
    // 3: a skirt with a fringe
    if stage >= 3 {
        fill_rect(cr, red, -57.0, -14.0, 114.0, 10.0);
        for k in 0..19 {
            let x = -57.0 + k as f64 * 6.0;
            fill_polygon(cr, if k % 2 == 0 { white } else { red }, &[(x, -4.0), (x + 6.0, -4.0), (x + 3.0, 1.5)]);
        }
    }
    // 4: the upper deck and steps
    if stage >= 4 {
        fill_rect(cr, red, -36.0, -48.0, 72.0, 18.0);
        fill_rect(cr, shade(red, 0.8), -36.0, -33.0, 72.0, 3.0);
        for k in 0..3 {
            let k = k as f64;
            fill_rect(cr, white, -52.0 + k * 5.0, -34.0 - k * 4.6, 6.0, 4.6 * (k + 1.0));
        }
    }
    // 5: gold trim
    if stage >= 5 {
        fill_rect(cr, gold, -56.0, -31.5, 112.0, 2.4);
        fill_rect(cr, gold, -36.0, -49.5, 72.0, 2.4);
        for k in 0..6 {
            fill_polygon(cr, gold, &star_points(-30.0 + k as f64 * 12.0, -40.0, 3.4, 1.5, 0.0));
        }
    }
    // 6: two columns
    if stage >= 6 {
        for cx in [-30.0, 30.0] {
            fill_rect(cr, white, cx - 3.5, -86.0, 7.0, 37.0);
            for k in 0..5 {
                let y = k as f64 * 7.0;
                fill_polygon(cr, red, &[(cx - 3.5, -84.0 + y), (cx + 3.5, -87.0 + y), (cx + 3.5, -84.0 + y), (cx - 3.5, -81.0 + y)]);
            }
            fill_rect(cr, gold, cx - 5.5, -89.0, 11.0, 3.4);
            fill_rect(cr, gold, cx - 5.5, -52.0, 11.0, 3.0);
        }
    }
    // 7: a great jester's head between them, 8: its cap with bells, 9: its face
    if stage >= 7 {
        fill_ellipse(cr, rgb(236, 190, 150), -19.0, -100.0, 38.0, 40.0);
        fill_polygon(
            cr,
            white,
            &[(-16.0, -64.0), (-8.0, -58.0), (0.0, -64.0), (8.0, -58.0), (16.0, -64.0), (12.0, -70.0), (-12.0, -70.0)],
        );
    }
    if stage >= 8 {
        let saved = cr.matrix();
        cr.translate(0.0, -94.0);
        jester_cap(cr, 40.0, 0.0);
        cr.set_matrix(saved);
    }
    if stage >= 9 {
        fill_ellipse(cr, K_INK, -9.0, -88.0, 4.4, 5.4);
        fill_ellipse(cr, K_INK, 4.6, -88.0, 4.4, 5.4);
        fill_ellipse(cr, red, -3.4, -82.0, 6.8, 6.8);
        bezier(cr, K_INK, 1.8, [-10.0, -74.0, -5.0, -66.0, 5.0, -66.0, 10.0, -74.0]);
        fill_ellipse(cr, c(250, 150, 140, 150), -15.0, -80.0, 6.0, 4.4);
        fill_ellipse(cr, c(250, 150, 140, 150), 9.0, -80.0, 6.0, 4.4);
    }
    // 10: big rosettes at both ends
    if stage >= 10 {
        for side in [-1.0, 1.0] {
            for k in 0..8 {
                let a = k as f64 * PI / 4.0;
                let col = if k % 2 == 0 { red } else { white };
                fill_ellipse(cr, col, side * 47.0 + a.cos() * 8.0 - 5.0, -40.0 + a.sin() * 8.0 - 5.0, 10.0, 10.0);
            }
            fill_ellipse(cr, gold, side * 47.0 - 4.5, -44.5, 9.0, 9.0);
        }
    }
    // 11: coloured bulbs along the decks
    if stage >= 11 {
        let bulbs = [R_YELLOW, R_BLUE, R_GREEN, red];
        for k in 0..12usize {
            fill_ellipse(cr, bulbs[k % 4], -55.0 + k as f64 * 9.6, -35.5, 4.4, 4.4);
        }
        for k in 0..8usize {
            fill_ellipse(cr, bulbs[(k + 2) % 4], -35.0 + k as f64 * 9.4, -53.5, 4.2, 4.2);
        }
    }
    // 12: streamers and pennants
    if stage >= 12 {
        for side in [-1.0, 1.0] {
            bezier(cr, R_YELLOW, 1.6, [side * 30.0, -88.0, side * 44.0, -84.0, side * 40.0, -66.0, side * 52.0, -60.0]);
            bezier(cr, R_BLUE, 1.6, [side * 30.0, -88.0, side * 38.0, -76.0, side * 48.0, -78.0, side * 56.0, -70.0]);
            flat(cr, wood, 1.2, side * 30.0, -89.0, side * 30.0, -108.0);
            fill_polygon(cr, red, &[(side * 30.0, -108.0), (side * 30.0 + side * 13.0, -104.0), (side * 30.0, -100.0)]);
            fill_polygon(cr, white, &[(side * 30.0, -104.0), (side * 30.0 + side * 13.0, -104.0), (side * 30.0, -100.0)]);
        }
    }
}

// ---------------------------------------------------------------------- the carnival parade
/// A coat's outline, `flare` wide at its hem.
fn coat_outline(flare: f64) -> [super::karneval::Seg; 5] {
    [M(-5.5, -33.0), L(5.5, -33.0), C(6.5, -26.0, 6.5, -19.0, flare, -13.0), L(-flare, -13.0), C(-6.5, -19.0, -6.5, -26.0, -5.5, -33.0)]
}

fn k_coat(cr: &Context, col: Argb, flare: f64) {
    fill_shape(cr, col, &coat_outline(flare));
}

/// The three-cornered hat of the town guards, with a plume.
fn k_tricorn(cr: &Context, plume: Argb) {
    fill_polygon(cr, K_INK, &[(-9.0, -5.4), (0.0, -11.0), (9.4, -5.4), (6.0, -3.6), (-6.0, -3.6)]);
    flat(cr, K_GOLD, 1.0, -8.0, -5.6, 0.0, -10.4);
    flat(cr, K_GOLD, 1.0, 0.0, -10.4, 8.6, -5.6);
    fill_ellipse(cr, plume, -5.0, -15.0, 5.0, 8.0);
}

/// The band's cap: blue with a peak and a gold badge.
fn k_band_cap(cr: &Context) {
    fill_rect(cr, R_BLUE, -6.0, -11.0, 12.0, 5.4);
    fill_rect(cr, K_INK, -1.0, -6.2, 9.0, 1.6);
    fill_ellipse(cr, K_GOLD, -1.6, -10.0, 3.2, 3.2);
}

/// The Rhineland's walkers: the people of a Rose Monday parade (Jecken), marching in time with the band. Who each
/// one is follows the walker itself (`RevellerPose::look`). "Waving" is each one's own turn: the guard girl kicks
/// high, the prince throws, the musicians lift their instruments, the clown and the jester jump.
/// (Called from `karneval::reveller`, which works out the phases from the beat: `p` the walking step's, and those
/// of standing and waving.)
pub(super) fn jeck(cr: &Context, pose: &RevellerPose, p: f64, stand_phase: f64, wave_phase: f64) {
    let (walking, waving) = (pose.walking, pose.waving);
    let (look, tunic) = (pose.look, pose.tunic);
    let who = look % 8;
    let beat = if walking {
        p
    } else if waving {
        wave_phase
    } else {
        stand_phase
    };
    let leg_a = if walking { p.sin() * 0.5 } else { beat.sin() * 0.1 };
    let bob = -beat.sin().abs() * if waving { 3.0 } else { 1.2 };
    let skin = K_SKINS[(look * 3 + tunic) % K_SKINS.len()];
    let (ink, red, white, gold) = (K_INK, R_RED, R_WHITE, K_GOLD);
    let stick = rgb(150, 110, 60);
    fill_ellipse(cr, c(30, 20, 40, 50), -11.0, -2.0, 22.0, 4.0);

    // legs: white tights and boots for the guards and the prince, patchwork for the clown, stripes for the bee
    let patch = [R_YELLOW, R_BLUE, R_GREEN, red];
    let kick = if who == 0 && waving { wave_phase.sin().abs() * 1.5 } else { 0.0 };
    for i in 0..2usize {
        let (hx, a) = if i == 0 { (-2.0, leg_a) } else { (2.0, -leg_a - kick) };
        let (fx, fy) = (hx + a.sin() * 13.0, -14.0 + bob + a.cos() * 13.0);
        let col = match who {
            0 | 1 | 3 => white,
            2 => patch[(i * 2 + tunic) % 4],
            7 => ink,
            6 => {
                if i == 0 {
                    red
                } else {
                    R_YELLOW
                }
            }
            _ => rgb(40, 50, 90),
        };
        round(cr, col, if who == 0 { 3.2 } else { 4.0 }, hx, -14.0 + bob, fx, fy);
        fill_ellipse(cr, if who == 2 { red } else { ink }, fx - 3.0, fy - 2.0, if who == 2 { 10.0 } else { 8.0 }, 4.2);
    }
    let body = cr.matrix();
    cr.translate(0.0, bob);

    let swing = if walking { p.sin() * 0.8 } else { beat.sin() * 0.3 };
    match who {
        0 => {
            // the dancing guard girl (Tanzmariechen): a red and white uniform with a short skirt, and a high kick
            k_arm(cr, -1.0, -31.0, if waving { -2.6 } else { -swing }, red, skin);
            k_coat(cr, red, 5.0);
            for k in 0..3 {
                fill_rect(cr, gold, -3.4, -31.0 + k as f64 * 4.4, 6.8, 1.2);
            }
            fill_polygon(cr, white, &[(-5.0, -17.0), (5.0, -17.0), (10.0, -10.0), (-10.0, -10.0)]);
            fill_rect(cr, red, -10.0, -11.4, 20.0, 1.6);
            k_arm(cr, 1.0, -31.0, if waving { 2.6 } else { swing }, red, skin);
        }
        1 => {
            // a guardsman (in the red and white of the old town guards), with a bunch of flowers to give away
            k_arm(cr, -1.0, -31.0, -swing, red, skin);
            k_coat(cr, red, 6.0);
            fill_polygon(cr, white, &[(-5.5, -33.0), (5.5, -33.0), (0.0, -22.0)]);
            fill_rect(cr, white, -6.4, -16.5, 12.8, 2.4);
            for k in 0..3 {
                fill_ellipse(cr, gold, 2.4, -28.0 + k as f64 * 4.0, 1.8, 1.8);
            }
            let (hx, hy) = k_arm(cr, 1.0, -31.0, if waving { 2.5 + wave_phase.sin() * 0.3 } else { 1.5 }, red, skin);
            flat(cr, R_GREEN, 1.4, hx, hy, hx + 1.0, hy - 7.0);
            fill_ellipse(cr, R_YELLOW, hx - 2.5 - 2.2, hy - 9.0 - 2.2, 4.4, 4.4);
            fill_ellipse(cr, rgb(255, 120, 170), hx + 2.5 - 2.2, hy - 9.5 - 2.2, 4.4, 4.4);
            fill_ellipse(cr, white, hx - 2.2, hy - 12.0 - 2.2, 4.4, 4.4);
        }
        2 => {
            // a patchwork clown (Lappenclown): a suit of coloured rags, a ruff and a small hat
            k_arm(cr, -1.0, -31.0, if waving { -2.5 } else { -swing }, patch[tunic % 4], skin);
            cr.save().ok();
            shape(
                cr,
                &[
                    M(-6.0, -33.0),
                    L(6.0, -33.0),
                    C(8.5, -25.0, 8.5, -18.0, 7.0, -12.0),
                    L(-7.0, -12.0),
                    C(-8.5, -18.0, -8.5, -25.0, -6.0, -33.0),
                ],
            );
            cr.clip();
            for row in 0..6usize {
                for col in 0..5usize {
                    let rag = patch[(row * 3 + col + tunic) % 4];
                    fill_rect(cr, rag, -9.0 + col as f64 * 3.8, -34.0 + row as f64 * 3.8, 3.8, 3.8);
                }
            }
            cr.restore().ok();
            for k in 0..5 {
                fill_ellipse(cr, white, -7.0 + k as f64 * 3.0, -35.4, 4.4, 4.0);
            }
            k_arm(cr, 1.0, -31.0, if waving { 2.5 } else { swing }, patch[(tunic + 2) % 4], skin);
        }
        3 => {
            // the prince: a gold tunic and a cape, pheasant feathers in his cap; he throws when he "waves"
            fill_shape(
                cr,
                red,
                &[M(-5.0, -33.0), C(-11.0, -26.0, -12.0, -18.0, -10.0, -11.0), L(-3.0, -12.0), L(-2.0, -32.0)],
            );
            k_arm(cr, -1.0, -31.0, -swing * 0.6, gold, skin);
            k_coat(cr, gold, 6.0);
            fill_rect(cr, white, -6.4, -17.0, 12.8, 2.4);
            fill_polygon(cr, white, &[(-4.0, -33.0), (4.0, -33.0), (0.0, -29.0)]);
            let (hx, hy) = k_arm(cr, 1.0, -31.0, if waving { 2.2 + wave_phase.sin() * 0.9 } else { 1.3 }, gold, skin);
            if waving {
                for (k, sweet) in patch.into_iter().take(3).enumerate() {
                    fill_ellipse(cr, sweet, hx + 3.0 + k as f64 * 3.4, hy - 5.0 - k as f64 * 2.6, 2.6, 2.2);
                }
            }
        }
        4 => {
            // the tuba player: a blue band uniform, the horn round the body and its bell over the shoulder
            k_arm(cr, -1.0, -31.0, 1.4, R_BLUE, skin);
            k_coat(cr, R_BLUE, 6.0);
            for k in 0..3 {
                fill_rect(cr, gold, -3.4, -31.0 + k as f64 * 4.4, 6.8, 1.1);
            }
            draw_ellipse(cr, rgb(214, 170, 60), 3.0, -2.0, -30.0, 14.0, 16.0);
            let lift = if waving { wave_phase.sin().abs() * 3.0 } else { beat.sin().abs() };
            fill_ellipse(cr, rgb(214, 170, 60), -13.0, -47.0 - lift, 14.0, 12.0);
            fill_ellipse(cr, rgb(150, 110, 30), -10.5, -45.0 - lift, 9.0, 7.6);
            k_arm(cr, 1.0, -31.0, 1.6, R_BLUE, skin);
        }
        5 => {
            // the drummer: the same uniform, a side drum on a sling and two sticks
            k_arm(cr, -1.0, -31.0, 1.3 + (beat + 1.5).sin().abs() * 0.6, R_BLUE, skin);
            k_coat(cr, R_BLUE, 6.0);
            flat(cr, white, 1.2, -4.0, -33.0, 6.0, -22.0);
            fill_rect(cr, white, 3.0, -24.0, 12.0, 10.0);
            fill_rect(cr, red, 3.0, -24.0, 12.0, 2.0);
            fill_rect(cr, red, 3.0, -16.0, 12.0, 2.0);
            for k in 0..3 {
                let x = k as f64 * 4.0;
                flat(cr, red, 0.8, 5.0 + x, -22.0, 7.0 + x, -16.0);
            }
            let (hx, hy) = k_arm(cr, 1.0, -31.0, 1.4 + beat.sin().abs() * 0.7, R_BLUE, skin);
            flat(cr, stick, 1.2, hx, hy, hx + 5.0, hy + 3.0);
        }
        6 => {
            // the jester: half red and half yellow, with the cap and its bells, and a jump
            k_arm(cr, -1.0, -31.0, if waving { -2.5 } else { -swing }, red, skin);
            cr.save().ok();
            shape(cr, &coat_outline(6.0));
            cr.clip();
            fill_rect(cr, red, -8.0, -34.0, 8.0, 22.0);
            fill_rect(cr, R_YELLOW, 0.0, -34.0, 8.0, 22.0);
            cr.restore().ok();
            for k in 0..4 {
                let x = k as f64 * 3.0;
                let col = if k % 2 == 0 { R_YELLOW } else { red };
                fill_polygon(cr, col, &[(-6.0 + x, -13.0), (-3.0 + x, -13.0), (-4.5 + x, -9.6)]);
            }
            k_arm(cr, 1.0, -31.0, if waving { 2.5 } else { swing }, R_YELLOW, skin);
        }
        _ => {
            // a child dressed as a bee: yellow and black stripes, small wings and feelers
            fill_ellipse(cr, c(255, 255, 255, 170), -13.0, -34.0, 10.0, 13.0);
            fill_ellipse(cr, c(255, 255, 255, 130), -11.0, -27.0, 8.0, 10.0);
            k_arm(cr, -1.0, -31.0, if waving { -2.5 } else { -swing }, ink, skin);
            fill_ellipse(cr, R_YELLOW, -7.5, -34.0, 15.0, 22.0);
            cr.save().ok();
            cr.new_path();
            ellipse_path(cr, -7.5, -34.0, 15.0, 22.0);
            cr.clip();
            for k in 0..3 {
                fill_rect(cr, ink, -8.0, -29.0 + k as f64 * 6.4, 16.0, 3.0);
            }
            cr.restore().ok();
            k_arm(cr, 1.0, -31.0, if waving { 2.5 } else { swing }, ink, skin);
        }
    }

    // a bag of sweets in the hand of those who carry something: it is what changes hands at a meeting
    if pose.carries_gift && !waving && who != 1 && who != 4 && who != 5 {
        let col = pose.gift;
        fill_polygon(cr, col, &[(8.0, -22.0), (15.0, -22.0), (16.5, -14.0), (6.5, -14.0)]);
        fill_polygon(cr, shade(col, 1.25), &[(9.4, -22.0), (11.5, -25.5), (13.6, -22.0)]);
        fill_ellipse(cr, c(255, 255, 255, 140), 9.0, -20.0, 2.6, 2.6);
    }

    // the head, nodding with the beat
    cr.translate(1.0, -40.0);
    cr.rotate(beat.sin() * 0.06);
    fill_ellipse(cr, skin, -6.5, -6.5, 13.0, 13.0);
    k_face(cr);
    // what each one wears on the head
    match who {
        0 => {
            k_tricorn(cr, white);
            fill_ellipse(cr, rgb(214, 170, 90), -8.6, -3.0, 5.0, 9.0);
            fill_ellipse(cr, rgb(214, 170, 90), 4.6, -3.0, 5.0, 9.0);
        }
        1 => k_tricorn(cr, red),
        2 => {
            fill_ellipse(cr, rgb(232, 120, 40), -9.0, -5.0, 5.0, 7.0);
            fill_ellipse(cr, rgb(232, 120, 40), 5.0, -5.0, 5.0, 7.0);
            fill_rect(cr, R_GREEN, -3.4, -11.4, 6.8, 5.0);
            fill_rect(cr, R_GREEN, -5.6, -7.4, 11.2, 1.6);
            fill_ellipse(cr, R_RED, 4.2, -0.6, 3.8, 3.8);
        }
        3 => {
            fill_ellipse(cr, red, -7.0, -9.4, 14.0, 5.6);
            for k in 0..3 {
                let k = k as f64;
                bezier(
                    cr,
                    rgb(170, 120, 60),
                    1.4,
                    [-3.0 + k * 2.0, -8.0, -6.0 + k * 2.0, -16.0, -10.0 + k * 3.0, -19.0, -13.0 + k * 4.0, -18.0],
                );
            }
        }
        4 | 5 => k_band_cap(cr),
        6 => {
            cr.translate(0.0, -5.0);
            jester_cap(cr, 15.0, (beat * 2.0).sin() * 1.2);
        }
        _ => {
            fill_ellipse(cr, ink, -7.0, -8.6, 14.0, 6.0);
            for side in [-1.0, 1.0] {
                flat(cr, ink, 0.9, side * 3.0, -8.0, side * 5.0, -14.0);
                fill_ellipse(cr, R_YELLOW, side * 5.0 - 1.5, -16.0, 3.0, 3.0);
            }
        }
    }
    cr.set_matrix(body);
}

// ---------------------------------------------------------------------- the parade wagon
/// The Rhineland's wagon in Santa's place: a tractor pulling a decorated wagon, the prince on it throwing sweets
/// and a small brass band playing. The sweets themselves are thrown by the figures as sparks
/// (`figures.rs`, `update_santa`). Facing +x, origin at the ground under its middle; `t` is the trip's clock,
/// `beat_count` the controller's beat.
pub(super) fn festwagen(cr: &Context, t: f64, beat_count: f64) {
    let beat = beat_count * PI;
    let (dark, red, white, gold, brass) = (rgb(46, 44, 60), R_RED, R_WHITE, K_GOLD, rgb(214, 170, 60));
    let roll = t * 5.0;
    // the tractor: green, a big wheel behind and a small one in front, an exhaust pipe that shakes
    fill_rect(cr, dark, 86.0, -56.0 + (t * 20.0).sin() * 0.6, 3.0, 16.0);
    fill_shape(
        cr,
        R_GREEN,
        &[M(54.0, -18.0), L(54.0, -40.0), L(98.0, -40.0), C(104.0, -40.0, 106.0, -32.0, 106.0, -24.0), L(106.0, -18.0)],
    );
    fill_rect(cr, shade(R_GREEN, 0.8), 54.0, -22.0, 52.0, 4.0);
    fill_rect(cr, rgb(178, 214, 236), 56.0, -62.0, 20.0, 22.0);
    fill_rect(cr, R_GREEN, 54.0, -66.0, 24.0, 4.0);
    fill_rect(cr, R_GREEN, 54.0, -62.0, 2.0, 24.0);
    fill_rect(cr, R_GREEN, 76.0, -62.0, 2.0, 24.0);
    fill_ellipse(cr, rgb(236, 190, 150), 61.0, -57.0, 8.0, 9.0);
    fill_rect(cr, rgb(60, 80, 120), 60.0, -58.0, 10.0, 3.0);
    for (wx, r) in [(64.0, 17.0), (98.0, 10.0)] {
        fill_ellipse(cr, dark, wx - r, -2.0 * r, 2.0 * r, 2.0 * r);
        fill_ellipse(cr, R_YELLOW, wx - r * 0.5, -r * 1.5, r, r);
        for k in 0..4 {
            let a = roll * (17.0 / r) + k as f64 * PI / 2.0;
            flat(cr, dark, 1.4, wx, -r, wx + a.cos() * r * 0.5, -r + a.sin() * r * 0.5);
        }
    }
    round(cr, dark, 2.4, 40.0, -16.0, 54.0, -18.0);
    // the wagon: a deck with a railing in red and white lozenges, a fringe, and wheels
    for wx in [-84.0, -6.0] {
        fill_ellipse(cr, dark, wx - 10.0, -20.0, 20.0, 20.0);
        fill_ellipse(cr, rgb(160, 164, 176), wx - 4.0, -14.0, 8.0, 8.0);
    }
    fill_rect(cr, white, -106.0, -38.0, 146.0, 22.0);
    for k in 0..18 {
        let x = -106.0 + k as f64 * 8.1;
        fill_polygon(cr, red, &[(x + 4.0, -38.0), (x + 8.1, -27.0), (x + 4.0, -16.0), (x, -27.0)]);
    }
    fill_rect(cr, gold, -106.0, -40.0, 146.0, 3.0);
    for k in 0..24 {
        let x = k as f64 * 6.1;
        let col = if k % 2 == 0 { red } else { white };
        fill_polygon(cr, col, &[(-106.0 + x, -16.0), (-99.9 + x, -16.0), (-103.0 + x, -11.0)]);
    }
    // at the back a great jester's cap on a post, its bells swinging with the beat
    fill_rect(cr, rgb(150, 110, 60), -96.0, -78.0, 4.0, 40.0);
    let saved = cr.matrix();
    cr.translate(-94.0, -78.0);
    jester_cap(cr, 34.0, beat.sin() * 1.4);
    cr.set_matrix(saved);
    // on the deck: three of the band, and the prince at the front with his arm up
    for (i, x) in [-66.0, -44.0, -22.0].into_iter().enumerate() {
        let b = (beat + i as f64 * 0.5 * PI).sin();
        let saved = cr.matrix();
        cr.translate(0.0, -40.0 - b.abs() * 1.6);
        small_person(
            cr,
            SmallPerson {
                x,
                h: 34.0,
                cloth: R_BLUE,
                skin: K_SKINS[(i * 2) % K_SKINS.len()],
                legs: dark,
                sway: b * 0.06,
                arm: 1.5 + b.abs() * 0.4,
                step: 0.0,
            },
        );
        match i {
            // a tuba
            0 => {
                draw_ellipse(cr, brass, 2.4, x - 3.0, -24.0, 12.0, 13.0);
                fill_ellipse(cr, brass, x - 9.0, -40.0, 12.0, 10.0);
            }
            // a trumpet
            1 => {
                flat(cr, brass, 2.2, x + 3.0, -24.0, x + 15.0, -26.0);
                fill_polygon(cr, brass, &[(x + 14.0, -29.5), (x + 19.0, -31.0), (x + 19.0, -21.0), (x + 14.0, -22.5)]);
            }
            // a drum
            _ => {
                fill_rect(cr, white, x + 4.0, -20.0, 10.0, 9.0);
                fill_rect(cr, red, x + 4.0, -20.0, 10.0, 1.8);
            }
        }
        fill_rect(cr, R_BLUE, x - 5.0, -37.5, 11.0, 4.0);
        cr.set_matrix(saved);
    }
    let wave = (beat * 0.5).sin();
    let saved = cr.matrix();
    cr.translate(0.0, -40.0);
    small_person(
        cr,
        SmallPerson {
            x: 12.0,
            h: 38.0,
            cloth: gold,
            skin: K_SKINS[0],
            legs: white,
            sway: wave * 0.08,
            arm: 2.4 + wave * 0.5,
            step: 0.0,
        },
    );
    fill_ellipse(cr, red, 6.0, -41.0, 13.0, 5.0);
    bezier(cr, rgb(170, 120, 60), 1.2, [10.0, -40.0, 7.0, -48.0, 3.0, -51.0, 0.0, -50.0]);
    cr.set_matrix(saved);
    // bunting from the cap's post to the front
    let flags = [red, white, R_YELLOW];
    for k in 0..9usize {
        let u = (k as f64 + 0.5) / 9.0;
        let (x, y) = (-92.0 + u * 126.0, -76.0 + 22.0 * u + 12.0 * u * (1.0 - u) * 4.0 * 0.3);
        fill_polygon(cr, flags[k % 3], &[(x - 4.0, y), (x + 4.0, y + 1.0), (x, y + 9.0)]);
    }
    bezier(cr, dark, 0.8, [-92.0, -76.0, -50.0, -62.0, -8.0, -56.0, 34.0, -54.0]);
}

// ---------------------------------------------------------------------- pennants and jester caps
/// The Rhineland's garland along the string (`w` wide on a screen of scale `s`): pennants in red, white and
/// yellow, and a small jester's cap hanging between every two bulbs. (Drawn into the string's own picture by
/// `karneval::carnival_garland`; the bulbs are the Christmas lights' own.)
pub(super) fn rhenish_garland(cr: &Context, w: f64, s: f64) {
    let (span, sag, top) = (230.0 * s, 22.0 * s, 1.0);
    let cols = [R_RED, R_WHITE, R_YELLOW];
    let at = |x0: f64, u: f64| (x0 + u * span, top + sag * (1.0 - (2.0 * u - 1.0) * (2.0 * u - 1.0)));
    let mut n = 0usize;
    let mut x0 = -span * 0.3;
    while x0 < w {
        for k in (0..16usize).filter(|k| k % 4 != 0) {
            let u = (k as f64 + 0.5) / 16.0;
            let (a, b) = (at(x0, u - 0.022), at(x0, u + 0.022));
            let col = cols[(k + n) % 3];
            let mid = ((a.0 + b.0) / 2.0, (a.1 + b.1) / 2.0);
            fill_polygon(cr, col, &[a, b, (mid.0, mid.1 + 13.0 * s)]);
            fill_polygon(cr, shade(col, 0.82), &[mid, b, (mid.0, mid.1 + 13.0 * s)]);
        }
        for b in 0..4usize {
            let (px, py) = at(x0, b as f64 / 4.0);
            flat(cr, rgb(60, 50, 60), 0.9 * s, px, py, px, py + 7.0 * s);
            let saved = cr.matrix();
            cr.translate(px, py + 17.0 * s);
            cr.rotate(((n * 4 + b) as f64 * 1.9).sin() * 0.14);
            jester_cap(cr, 13.0 * s, 0.0);
            cr.set_matrix(saved);
        }
        n += 1;
        x0 += span;
    }
}

// ---------------------------------------------------------------------- jester caps and doughnuts on the window edges
/// A doughnut (the carnival's own cake, with sugar on top) on a paper napkin, beside every other jester's cap on a
/// window edge (`Layer::draw_ledge_carnival`, which also draws the cap). In a box of 30 by 20 from (0, 0).
pub(super) fn doughnut(cr: &Context) {
    fill_polygon(cr, rgb(250, 248, 242), &[(1.0, 19.0), (15.0, 14.0), (29.0, 19.0), (22.0, 20.0), (8.0, 20.0)]);
    fill_ellipse(cr, rgb(206, 140, 70), 5.0, 6.0, 20.0, 13.0);
    fill_ellipse(cr, rgb(232, 180, 110), 6.0, 6.0, 18.0, 8.0);
    fill_ellipse(cr, c(255, 255, 255, 220), 8.0, 5.6, 14.0, 4.6);
    fill_ellipse(cr, rgb(214, 32, 48), 21.6, 11.0, 3.4, 2.6);
}
