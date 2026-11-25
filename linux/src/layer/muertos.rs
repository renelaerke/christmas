//! De dødes dag (Día de los Muertos, setting `Theme` = 2), as in the macOS version (`Overlay.swift`) and the
//! Windows one (`src/LayerMuertos.cs`): each Christmas element has its form for the dead. Here are the pictures of
//! the marigold petals that fall for snow, the ofrenda (altar) that stands in the snowman's place, the monarch
//! butterflies that fly in Santa's, the calacas (skeletons) that walk in the nisser's, the papel picado that hangs
//! in the lights', the candles on the window edges and the donkey cart that clears the petals in the plow's. The
//! drawing is kept line for line the same as in the other two versions.

use cairo::{Context, LineCap};

use super::draw::*;
use super::{Layer, SceneState, LEAF_PX};
use crate::figures::DONKEY_STRIDE;
use crate::x11::Res;

/// The marigolds' (cempasúchil) colours: deep orange to golden yellow.
pub(super) const MARIGOLD: [Argb; 5] =
    [rgb(255, 140, 0), rgb(255, 176, 0), rgb(246, 112, 10), rgb(255, 206, 50), rgb(232, 96, 12)];
/// The bright colours of the papel picado and the altar's cloths.
pub(super) const PICADO: [Argb; 6] =
    [rgb(233, 30, 99), rgb(255, 152, 0), rgb(0, 166, 166), rgb(123, 44, 191), rgb(255, 210, 63), rgb(46, 158, 79)];

const INK: Argb = rgb(34, 26, 40);
const BONE: Argb = rgb(246, 242, 230);
const PI: f64 = std::f64::consts::PI;

/// (red, green, blue, alpha), as the colours are written in the other two versions.
pub(super) const fn c(r: u8, g: u8, b: u8, a: u8) -> Argb {
    (a, r, g, b)
}

pub(super) fn shade(col: Argb, f: f64) -> Argb {
    let k = |v: u8| (v as f64 * f).min(255.0) as u8;
    (col.0, k(col.1), k(col.2), k(col.3))
}

pub(super) fn round(cr: &Context, col: Argb, width: f64, x1: f64, y1: f64, x2: f64, y2: f64) {
    line(cr, col, width, LineCap::Round, x1, y1, x2, y2);
}

pub(super) fn flat(cr: &Context, col: Argb, width: f64, x1: f64, y1: f64, x2: f64, y2: f64) {
    line(cr, col, width, LineCap::Butt, x1, y1, x2, y2);
}

/// A curve with one control point (a quadratic one, as Cairo's cubic) from `from` to `to`.
pub(super) fn quad_to(cr: &Context, from: (f64, f64), ctrl: (f64, f64), to: (f64, f64)) {
    cr.curve_to(
        from.0 + (ctrl.0 - from.0) * 2.0 / 3.0,
        from.1 + (ctrl.1 - from.1) * 2.0 / 3.0,
        to.0 + (ctrl.0 - to.0) * 2.0 / 3.0,
        to.1 + (ctrl.1 - to.1) * 2.0 / 3.0,
        to.0,
        to.1,
    );
}

pub(super) fn fill_with(cr: &Context, col: Argb) {
    set(cr, col);
    let _ = cr.fill();
}

/// A stroked curve: the start, two control points and the end.
pub(super) fn bezier(cr: &Context, col: Argb, width: f64, p: [f64; 8]) {
    cr.new_path();
    cr.move_to(p[0], p[1]);
    cr.curve_to(p[2], p[3], p[4], p[5], p[6], p[7]);
    stroke(cr, col, width, LineCap::Round);
}

/// A soft round light: `inner` in the middle, fading to nothing at the rim.
pub(super) fn glow(cr: &Context, inner: Argb, cx: f64, cy: f64, r: f64) {
    let grad = cairo::RadialGradient::new(cx, cy, 0.0, cx, cy, r);
    let (red, green, blue) = (inner.1 as f64 / 255.0, inner.2 as f64 / 255.0, inner.3 as f64 / 255.0);
    grad.add_color_stop_rgba(0.0, red, green, blue, inner.0 as f64 / 255.0);
    grad.add_color_stop_rgba(1.0, red, green, blue, 0.0);
    cr.new_path();
    ellipse_path(cr, cx - r, cy - r, 2.0 * r, 2.0 * r);
    let _ = cr.set_source(&grad);
    let _ = cr.fill();
}

// ---------------------------------------------------------------------- petals
/// The ten petal pictures, premultiplied ARGB, `LEAF_PX` square, laid out as the leaves' (`make_leaf_sprites`):
/// per colour a petal (a short fan with a frilled outer edge, the narrow base at the left) and then a whole small
/// flower head (frilled rings), which one pick in five gets.
pub(super) fn make_petal_sprites() -> Res<Vec<Vec<u32>>> {
    let m = LEAF_PX as f64 / 2.0;
    let crease = c(150, 60, 0, 70);
    let mut all = Vec::with_capacity(MARIGOLD.len() * 2);
    for colour in MARIGOLD {
        for shape in 0..2 {
            let img = Image::new(LEAF_PX as i32, LEAF_PX as i32)?;
            let cr = &img.cr;
            if shape == 0 {
                cr.new_path();
                cr.move_to(8.0, m);
                quad_to(cr, (8.0, m), (18.0, m - 22.0), (44.0, m - 22.0));
                // the frilled edge: small scallops from top to bottom
                let n = 6;
                let mut at = (44.0, m - 22.0);
                for k in 0..n {
                    let a1 = -PI / 2.0 + PI * (k + 1) as f64 / n as f64;
                    let am = -PI / 2.0 + PI * (k as f64 + 0.5) / n as f64;
                    let to = (38.0 + a1.cos() * 18.0, m + a1.sin() * 22.0);
                    quad_to(cr, at, (38.0 + am.cos() * 26.0, m + am.sin() * 29.0), to);
                    at = to;
                }
                quad_to(cr, at, (18.0, m + 22.0), (8.0, m));
                cr.close_path();
                fill_with(cr, colour);
                round(cr, crease, 2.0, 10.0, m, 48.0, m - 8.0);
                round(cr, crease, 2.0, 10.0, m, 50.0, m + 6.0);
            } else {
                for r in [30.0, 22.0, 13.0] {
                    let lobes = 12;
                    let ring = |cr: &Context| {
                        cr.new_path();
                        let mut at = (m + r * 0.86, m);
                        cr.move_to(at.0, at.1);
                        for k in 1..=lobes {
                            let a1 = 2.0 * PI * k as f64 / lobes as f64;
                            let am = a1 - PI / lobes as f64;
                            let to = (m + a1.cos() * r * 0.86, m + a1.sin() * r * 0.86);
                            quad_to(cr, at, (m + am.cos() * r * 1.12, m + am.sin() * r * 1.12), to);
                            at = to;
                        }
                        cr.close_path();
                    };
                    ring(cr);
                    fill_with(cr, if r == 22.0 { shade(colour, 0.85) } else { colour });
                    ring(cr);
                    stroke(cr, crease, 1.5, LineCap::Butt);
                }
            }
            img.surface.flush();
            all.push(img.pixels.clone());
        }
    }
    Ok(all)
}

// ---------------------------------------------------------------------- small things the figures share
/// A small marigold head (cempasúchil) centred at (x, y): frilled rings in orange.
fn marigold(cr: &Context, x: f64, y: f64, r: f64, colour: Argb) {
    fill_ellipse(cr, shade(colour, 0.78), x - r, y - r * 0.9, r * 2.0, r * 1.8);
    for k in 0..7 {
        let a = k as f64 * 0.8976;
        fill_ellipse(cr, colour, x + a.cos() * r * 0.45 - r * 0.5, y + a.sin() * r * 0.4 - r * 0.45, r, r * 0.9);
    }
    fill_ellipse(cr, shade(colour, 0.85), x - r * 0.4, y - r * 0.38, r * 0.8, r * 0.76);
}

/// A candle standing at (x, y) (its foot), with a flame and a soft glow.
fn candle(cr: &Context, x: f64, y: f64, h: f64) {
    // a warm glow around the flame (a flat light disc read as a grey spot on a dark desktop)
    glow(cr, c(255, 190, 70, 120), x, y - h - 5.0, 9.0);
    fill_rect(cr, rgb(250, 242, 222), x - 2.6, y - h, 5.2, h);
    fill_rect(cr, rgb(220, 205, 175), x + 0.8, y - h, 1.8, h);
    flat(cr, rgb(60, 40, 30), 0.8, x, y - h, x, y - h - 1.8);
    cr.new_path();
    cr.move_to(x, y - h - 9.0);
    cr.curve_to(x + 3.2, y - h - 4.5, x + 2.4, y - h - 1.0, x, y - h - 1.0);
    cr.curve_to(x - 2.4, y - h - 1.0, x - 3.2, y - h - 4.5, x, y - h - 9.0);
    cr.close_path();
    fill_with(cr, rgb(255, 180, 40));
    fill_ellipse(cr, rgb(255, 245, 200), x - 0.9, y - h - 4.6, 1.8, 3.0);
}

/// A sugar skull (calavera de azúcar) centred at (x, y), `w` wide, with icing around the eyes.
fn sugar_skull(cr: &Context, x: f64, y: f64, w: f64, icing: Argb) {
    let k = w / 20.0;
    let ink = rgb(36, 28, 40);
    fill_ellipse(cr, rgb(250, 246, 236), x - 10.0 * k, y - 10.0 * k, 20.0 * k, 17.0 * k);
    fill_rect(cr, rgb(250, 246, 236), x - 6.0 * k, y + 3.0 * k, 12.0 * k, 6.0 * k);
    draw_ellipse(cr, c(150, 140, 130, 140), 0.8, x - 10.0 * k, y - 10.0 * k, 20.0 * k, 17.0 * k);
    for dx in [-4.5, 4.5] {
        fill_ellipse(cr, icing, x + dx * k - 3.6 * k, y - 3.6 * k, 7.2 * k, 7.2 * k);
        fill_ellipse(cr, ink, x + dx * k - 2.4 * k, y - 2.4 * k, 4.8 * k, 4.8 * k);
    }
    fill_polygon(cr, ink, &[(x, y + 1.5 * k), (x - 1.4 * k, y + 4.0 * k), (x + 1.4 * k, y + 4.0 * k)]);
    flat(cr, ink, 0.8, x - 4.5 * k, y + 6.5 * k, x + 4.5 * k, y + 6.5 * k);
    for dx in [-3.0, -1.0, 1.0, 3.0] {
        flat(cr, ink, 0.7, x + dx * k, y + 5.3 * k, x + dx * k, y + 7.8 * k);
    }
    // icing on the forehead: a small flower
    for j in 0..5 {
        let a = j as f64 * 1.2566;
        fill_ellipse(cr, icing, x + a.cos() * 2.0 * k - 1.2 * k, y - 6.5 * k + a.sin() * 2.0 * k - 1.2 * k, 2.4 * k, 2.4 * k);
    }
    fill_ellipse(cr, rgb(255, 210, 63), x - k, y - 7.5 * k, 2.0 * k, 2.0 * k);
}

// ---------------------------------------------------------------------- monarch butterflies
/// One monarch butterfly flying toward +x, seen from above: the body along x, the wings to both sides. The wings
/// beat by folding toward the body (their spread is |cos| of the flap).
fn monarch(cr: &Context, x: f64, y: f64, size: f64, flap: f64) {
    let saved = cr.matrix();
    cr.translate(x, y);
    cr.scale(size, size);
    let spread = 0.18 + 0.82 * flap.cos().abs();
    let (black, dot) = (rgb(28, 22, 26), c(255, 255, 255, 230));
    let orange = |cr: &Context, x0: f64, y0: f64, x1: f64, y1: f64| {
        let grad = cairo::LinearGradient::new(x0, y0, x1, y1);
        grad.add_color_stop_rgb(0.0, 1.0, 136.0 / 255.0, 0.0);
        grad.add_color_stop_rgb(1.0, 214.0 / 255.0, 92.0 / 255.0, 0.0);
        let _ = cr.set_source(&grad);
        let _ = cr.fill();
    };
    for side in [-1.0, 1.0] {
        let wing = cr.matrix();
        cr.scale(1.0, side * spread);
        // forewing (toward the head) and hindwing, black-edged with orange cells
        cr.new_path();
        cr.move_to(4.0, 0.0);
        cr.curve_to(10.0, -10.0, 22.0, -24.0, 14.0, -30.0);
        cr.curve_to(4.0, -30.0, -6.0, -20.0, -2.0, 0.0);
        cr.close_path();
        fill_with(cr, black);
        cr.new_path();
        cr.move_to(-1.0, 0.0);
        cr.curve_to(-2.0, -12.0, -10.0, -24.0, -18.0, -18.0);
        cr.curve_to(-22.0, -10.0, -12.0, -2.0, -1.0, 0.0);
        cr.close_path();
        fill_with(cr, black);
        cr.new_path();
        cr.move_to(4.0, -2.0);
        cr.curve_to(9.0, -10.0, 18.0, -21.0, 12.0, -26.0);
        cr.curve_to(5.0, -26.0, -3.0, -18.0, 0.0, -2.0);
        cr.close_path();
        orange(cr, 4.0, -2.0, 12.0, -26.0);
        cr.new_path();
        cr.move_to(-2.0, -2.0);
        cr.curve_to(-3.0, -11.0, -9.0, -20.0, -16.0, -16.0);
        cr.curve_to(-19.0, -10.0, -11.0, -3.0, -2.0, -2.0);
        cr.close_path();
        orange(cr, -2.0, -2.0, -16.0, -16.0);
        // the black veins and the white dots in the border
        flat(cr, black, 1.1, 2.0, -3.0, 12.0, -22.0);
        flat(cr, black, 1.1, 1.0, -3.0, 4.0, -24.0);
        flat(cr, black, 1.1, -2.0, -3.0, -12.0, -15.0);
        flat(cr, black, 1.1, -2.0, -3.0, -6.0, -18.0);
        for (dx, dy) in [(15.0, -28.0), (10.0, -29.5), (5.0, -27.5), (-16.0, -18.5), (-19.0, -13.0), (-12.0, -20.0)] {
            fill_ellipse(cr, dot, dx - 0.9, dy - 0.9, 1.8, 1.8);
        }
        cr.set_matrix(wing);
    }
    // body, head and antennae
    fill_ellipse(cr, black, -9.0, -1.6, 16.0, 3.2);
    fill_ellipse(cr, black, 5.5, -2.0, 4.0, 4.0);
    flat(cr, black, 0.8, 9.0, -1.0, 14.0, -4.0);
    flat(cr, black, 0.8, 9.0, 1.0, 14.0, 4.0);
    cr.set_matrix(saved);
}

/// The dead's flyer in Santa's place: a loose swarm of monarch butterflies (they are said to carry the souls home).
/// Each one flutters at its own pace and wanders up and down around its place in the swarm. Drawn in Santa's
/// frame: translated to his place and scaled by his size and direction.
pub(super) fn monarchs(cr: &Context, t: f64) {
    const PLACES: [(f64, f64, f64); 10] = [
        (230.0, -40.0, 1.1),
        (180.0, -72.0, 0.8),
        (150.0, -20.0, 1.0),
        (100.0, -78.0, 0.9),
        (70.0, -45.0, 1.2),
        (20.0, -10.0, 0.8),
        (-10.0, -72.0, 1.0),
        (-60.0, -40.0, 0.9),
        (-110.0, -70.0, 0.75),
        (-150.0, -15.0, 0.85),
    ];
    for (i, (px, py, size)) in PLACES.into_iter().enumerate() {
        let fi = i as f64;
        monarch(
            cr,
            px + (t * 0.9 + fi * 2.1).sin() * 12.0,
            py + (t * 1.3 + fi * 1.7).sin() * 14.0,
            size,
            t * (10.0 + (i % 3) as f64 * 1.5) + fi * 1.3,
        );
    }
}

// ---------------------------------------------------------------------- the ofrenda
/// The dead's form of the snowman: an ofrenda, the home altar, put together piece by piece (a step for every hour
/// the app runs, see the controller) in the same place and box as the snowman. Three tiers under coloured cloths,
/// then candles, marigolds, a sugar skull, bread, a framed photo, an arch of marigolds and a monarch resting on
/// it. Origin at the ground, y up is negative.
pub(super) fn ofrenda(cr: &Context, stage: i32) {
    fill_ellipse(cr, c(40, 20, 30, 60), -60.0, -3.0, 120.0, 6.0);
    let cloth = PICADO;
    // the arch of marigolds behind the altar (stage 10): two bent canes thick with flowers
    if stage >= 10 {
        bezier(cr, rgb(70, 110, 40), 2.4, [-50.0, -2.0, -54.0, -150.0, 54.0, -150.0, 50.0, -2.0]);
        for k in 0..=16 {
            let u = k as f64 / 16.0;
            let v = 1.0 - u;
            let px = v * v * v * -50.0 + 3.0 * v * v * u * -54.0 + 3.0 * v * u * u * 54.0 + u * u * u * 50.0;
            let py = v * v * v * -2.0 + 3.0 * v * v * u * -150.0 + 3.0 * v * u * u * -150.0 + u * u * u * -2.0;
            marigold(cr, px, py, 4.2, MARIGOLD[k % MARIGOLD.len()]);
        }
    }
    if stage >= 1 {
        tier(cr, 0.0, 112.0, 26.0, cloth[3]);
    }
    if stage >= 2 {
        tier(cr, -26.0, 84.0, 26.0, cloth[0]);
    }
    if stage >= 3 {
        tier(cr, -52.0, 56.0, 24.0, cloth[2]);
    }
    // papel picado along the front of the bottom tier (stage 11)
    if stage >= 11 {
        for i in 0..5 {
            let x = -44.0 + i as f64 * 22.0;
            fill_rect(cr, cloth[(i + 1) % cloth.len()], x - 8.0, -14.0, 16.0, 10.0);
            fill_ellipse(cr, rgb(96, 58, 34), x - 2.0, -11.0, 4.0, 4.0);
        }
    }
    // the photo of the one remembered, at the back of the top tier (stage 9)
    if stage >= 9 {
        fill_rect(cr, rgb(196, 150, 60), 8.0, -98.0, 18.0, 22.0);
        fill_rect(cr, rgb(232, 224, 205), 10.5, -95.5, 13.0, 17.0);
        fill_ellipse(cr, rgb(120, 100, 88), 12.5, -87.5, 9.0, 9.0);
        fill_ellipse(cr, rgb(150, 128, 110), 14.5, -93.0, 5.0, 6.0);
    }
    // the sugar skull on top (stage 6)
    if stage >= 6 {
        sugar_skull(cr, -8.0, -86.0, 22.0, cloth[0]);
    }
    // marigolds along each tier's edge (stage 5)
    if stage >= 5 {
        for (y, w) in [(-27.0, 100.0), (-53.0, 72.0)] {
            let (mut x, mut k) = (-w / 2.0, 0usize);
            while x <= w / 2.0 {
                marigold(cr, x, y, 4.6, MARIGOLD[k % MARIGOLD.len()]);
                x += 12.0;
                k += 1;
            }
        }
    }
    // bread of the dead (pan de muerto) on the middle tier (stage 8)
    if stage >= 8 {
        fill_ellipse(cr, rgb(206, 146, 80), -38.0, -38.0, 22.0, 12.0);
        round(cr, rgb(244, 226, 190), 2.6, -34.0, -35.0, -20.0, -31.0);
        round(cr, rgb(244, 226, 190), 2.6, -34.0, -31.0, -20.0, -35.0);
        fill_ellipse(cr, rgb(244, 226, 190), -29.5, -39.5, 5.0, 5.0);
    }
    // candles: on the bottom tier (stage 4), the middle tier (stage 7)
    if stage >= 4 {
        candle(cr, -50.0, -26.0, 14.0);
        candle(cr, 50.0, -26.0, 14.0);
    }
    if stage >= 7 {
        candle(cr, -36.0, -52.0, 11.0);
        candle(cr, 36.0, -52.0, 11.0);
    }
    // a glass of water and small sugar skulls for the children (stage 12), and a monarch resting on the arch
    if stage >= 12 {
        fill_rect(cr, c(190, 225, 245, 150), 14.0, -40.0, 8.0, 12.0);
        fill_rect(cr, c(150, 200, 235, 170), 14.0, -34.0, 8.0, 6.0);
        draw_ellipse(cr, c(255, 255, 255, 120), 0.8, 14.0, -41.0, 8.0, 2.0);
        sugar_skull(cr, 2.0, -32.0, 9.0, cloth[2]);
        monarch(cr, 24.0, -100.0, 0.55, 0.5);
    }
}

/// One tier of the altar: a box under a cloth with a scalloped hem.
fn tier(cr: &Context, y: f64, w: f64, h: f64, col: Argb) {
    fill_rect(cr, rgb(96, 58, 34), -w / 2.0, y - h, w, h);
    let hem = y - h + h * 0.62;
    cr.new_path();
    cr.move_to(-w / 2.0 - 2.0, y - h);
    cr.line_to(w / 2.0 + 2.0, y - h);
    cr.line_to(w / 2.0 + 2.0, hem);
    let n = (w / 9.0) as i32;
    let mut at = (w / 2.0 + 2.0, hem);
    for i in 0..n {
        let x1 = w / 2.0 + 2.0 - (w + 4.0) * (i + 1) as f64 / n as f64;
        let xm = w / 2.0 + 2.0 - (w + 4.0) * (i as f64 + 0.5) / n as f64;
        quad_to(cr, at, (xm, hem + 7.0), (x1, hem));
        at = (x1, hem);
    }
    cr.close_path();
    fill_with(cr, col);
    flat(cr, shade(col, 0.7), 1.0, -w / 2.0 - 2.0, y - h + 0.5, w / 2.0 + 2.0, y - h + 0.5);
}

// ---------------------------------------------------------------------- calacas
/// How a calaca stands: what `elves.rs` works out from the elf it draws.
#[derive(Clone, Copy)]
pub(super) struct CalacaPose {
    /// Which clothes (the elf's tunic number) and which bunch of marigolds (its gift's number).
    pub tunic: usize,
    pub gift: usize,
    pub walking: bool,
    pub waving: bool,
    pub carries_gift: bool,
    /// The step's phase while walking, and the phases of standing and waving (0 when not).
    pub walk: f64,
    pub stand: f64,
    pub wave: f64,
}

fn bone_line(cr: &Context, x1: f64, y1: f64, x2: f64, y2: f64, w: f64) {
    round(cr, INK, w + 1.8, x1, y1, x2, y2);
    round(cr, BONE, w, x1, y1, x2, y2);
}

fn calaca_arm(cr: &Context, sx: f64, sy: f64, a: f64) {
    let (hx, hy) = (sx + a.sin() * 11.0, sy + a.cos() * 11.0);
    bone_line(cr, sx, sy, hx, hy, 2.0);
    fill_ellipse(cr, BONE, hx - 2.0, hy - 2.0, 4.0, 4.0);
    draw_ellipse(cr, INK, 0.8, hx - 2.0, hy - 2.0, 4.0, 4.0);
}

/// The Day of the Dead's walkers: small cheerful skeletons. They are nisser in everything but looks: they walk,
/// stop, wave (dance, with a maraca), cross to the next screen and meet to hand over a bunch of marigolds. Every
/// other one is a calaca in a sombrero with a striped serape, the others a catrina in a long dress and a wide hat
/// with flowers. The bones are white with a dark outline, so they show on light windows as well as dark ones.
/// Drawn like a nisse: feet at (0, 0), y up is negative, facing right.
pub(super) fn calaca(cr: &Context, pose: CalacaPose) {
    let p = if pose.walking { pose.walk } else { 0.0 };
    let leg_a = if pose.walking { p.sin() * 0.55 } else { 0.0 };
    let bob = if pose.walking {
        -p.sin().abs() * 1.5
    } else if pose.waving {
        -pose.wave.sin().abs() * 2.0
    } else {
        0.0
    };
    let ti = pose.tunic;
    let catrina = ti % 2 == 1;
    let colours = PICADO;
    let main = colours[(ti / 2 + if catrina { 3 } else { 0 }) % colours.len()];

    fill_ellipse(cr, c(40, 20, 30, 50), -11.0, -2.0, 22.0, 4.0);

    // legs and shoes (under a catrina's dress only the shoes step out)
    for (hx, a) in [(-2.0, leg_a), (2.0, -leg_a)] {
        let hy = -15.0 + bob;
        let (fx, fy) = (hx + a.sin() * 13.0, hy + a.cos() * 13.0);
        if !catrina {
            bone_line(cr, hx, hy, fx, fy, 2.4);
        }
        fill_ellipse(cr, INK, fx - 3.0, fy - 2.0, 8.5, 4.5);
    }

    let saved = cr.matrix();
    cr.translate(0.0, bob);
    let (back_arm, front_arm) = if pose.waving {
        (-0.4 + pose.wave.sin() * 0.3, 2.6 + pose.wave.sin() * 0.5)
    } else if pose.carries_gift {
        (1.3, 1.3)
    } else {
        (-leg_a * 0.9, leg_a * 0.9)
    };
    let sway = (if pose.walking { p * 0.5 } else { pose.stand }).sin() * 0.06;

    calaca_arm(cr, -1.0, -33.0, back_arm);

    if catrina {
        // the long dress, flaring from the waist, with a ruffle at the hem
        cr.new_path();
        cr.move_to(-5.0, -34.0);
        cr.line_to(5.0, -34.0);
        cr.curve_to(7.0, -24.0, 12.0, -12.0, 13.0, -3.0);
        cr.line_to(-13.0, -3.0);
        cr.curve_to(-12.0, -12.0, -7.0, -24.0, -5.0, -34.0);
        cr.close_path();
        fill_with(cr, main);
        flat(cr, shade(main, 0.65), 1.0, -5.0, -34.0, 5.0, -34.0);
        for k in 0..6 {
            fill_ellipse(cr, shade(main, 0.75), -13.0 + k as f64 * 4.3, -5.0, 4.6, 3.6);
        }
        flat(cr, colours[(ti + 4) % colours.len()], 1.6, -6.5, -24.0, 6.5, -24.0); // the sash
    } else {
        // spine, pelvis and ribcage
        bone_line(cr, 0.0, -17.0, 0.0, -34.0, 1.8);
        fill_ellipse(cr, INK, -6.0, -21.0, 12.0, 6.5);
        fill_ellipse(cr, BONE, -5.0, -20.2, 10.0, 5.0);
        draw_ellipse(cr, INK, 3.0, -6.5, -36.0, 13.0, 13.0);
        draw_ellipse(cr, BONE, 1.6, -6.5, -36.0, 13.0, 13.0);
        bone_line(cr, -5.0, -32.0, 5.0, -32.0, 1.1);
        bone_line(cr, -5.0, -28.5, 5.0, -28.5, 1.1);
        // the striped serape over one shoulder
        let stripe = [main, colours[(ti + 2) % colours.len()], rgb(250, 240, 210)];
        for (k, col) in stripe.into_iter().enumerate() {
            let o = k as f64 * 2.2;
            flat(cr, col, 2.4, -6.0 + o * 0.4, -36.0 + o, 6.0 + o * 0.4, -24.0 + o);
        }
    }

    if pose.carries_gift && !pose.waving {
        // a bunch of marigolds
        flat(cr, rgb(70, 110, 40), 1.2, 10.0, -22.0, 12.0, -31.0);
        flat(cr, rgb(70, 110, 40), 1.2, 10.0, -22.0, 16.0, -30.0);
        marigold(cr, 11.5, -32.0, 3.2, MARIGOLD[pose.gift % MARIGOLD.len()]);
        marigold(cr, 16.5, -31.0, 3.0, MARIGOLD[(pose.gift + 1) % MARIGOLD.len()]);
        marigold(cr, 14.0, -35.5, 2.8, MARIGOLD[(pose.gift + 3) % MARIGOLD.len()]);
    }

    // the skull, with the eye sockets ringed in colour like a sugar skull
    let body = cr.matrix();
    cr.translate(1.0, -44.0);
    cr.rotate(sway);
    fill_ellipse(cr, INK, -7.6, -7.6, 15.2, 14.2);
    fill_ellipse(cr, BONE, -6.7, -6.7, 13.4, 12.4);
    fill_rect(cr, BONE, -3.6, 3.0, 7.2, 3.6);
    draw_ellipse(cr, INK, 0.8, -3.6, 3.0, 7.2, 3.6);
    let ring = colours[(ti + 1) % colours.len()];
    for dx in [-0.5, 4.4] {
        fill_ellipse(cr, ring, dx - 2.9, -2.9, 5.8, 5.8);
        fill_ellipse(cr, INK, dx - 1.9, -1.9, 3.8, 3.8);
    }
    fill_polygon(cr, INK, &[(5.5, 1.2), (4.4, 3.0), (6.4, 3.0)]);
    for dx in [-1.5, 1.0, 3.5] {
        flat(cr, INK, 0.6, dx, 3.4, dx, 6.2);
    }

    if catrina {
        // a wide hat tilted back, with flowers and a feather
        cr.rotate(-0.12);
        fill_ellipse(cr, INK, -15.0, -9.0, 30.0, 6.0);
        fill_ellipse(cr, shade(main, 0.55), -14.0, -8.4, 28.0, 4.8);
        cr.new_path();
        cr.move_to(-6.0, -7.0);
        cr.curve_to(-6.0, -14.0, 6.0, -14.0, 6.0, -7.0);
        cr.close_path();
        fill_with(cr, shade(main, 0.55));
        bezier(cr, rgb(250, 250, 250), 1.6, [-4.0, -11.0, -10.0, -20.0, -16.0, -20.0, -18.0, -14.0]);
        marigold(cr, -2.0, -10.0, 2.6, MARIGOLD[0]);
        marigold(cr, 3.0, -9.5, 2.4, colours[0]);
        marigold(cr, 7.5, -8.5, 2.2, MARIGOLD[3]);
    } else {
        // a sombrero: wide brim, tall crown and a coloured band
        fill_ellipse(cr, INK, -16.0, -9.0, 32.0, 6.5);
        fill_ellipse(cr, rgb(214, 170, 72), -15.0, -8.4, 30.0, 5.2);
        cr.new_path();
        cr.move_to(-6.5, -6.5);
        cr.curve_to(-6.0, -19.0, 6.0, -19.0, 6.5, -6.5);
        cr.close_path();
        set(cr, rgb(214, 170, 72));
        let _ = cr.fill_preserve();
        stroke(cr, rgb(120, 84, 30), 0.8, LineCap::Butt);
        fill_rect(cr, main, -6.4, -9.4, 12.8, 2.4);
    }
    cr.set_matrix(body);

    calaca_arm(cr, 1.0, -33.0, front_arm);
    if pose.waving {
        // dancing with a maraca in the raised hand
        let (hx, hy) = (1.0 + front_arm.sin() * 11.0, -33.0 + front_arm.cos() * 11.0);
        flat(cr, rgb(120, 80, 40), 1.4, hx, hy, hx + front_arm.sin() * 4.0, hy + front_arm.cos() * 4.0);
        let maraca = colours[(ti + 5) % colours.len()];
        fill_ellipse(cr, maraca, hx + front_arm.sin() * 6.0 - 3.0, hy + front_arm.cos() * 6.0 - 3.0, 6.0, 6.0);
    }
    cr.set_matrix(saved);
}

// ---------------------------------------------------------------------- the donkey cart
fn donkey_leg(cr: &Context, hx: f64, a: f64, col: Argb) {
    let (kx, ky) = (hx + a.sin() * 9.0, -14.0);
    round(cr, col, 4.0, hx, -28.0, kx, ky);
    round(cr, col, 3.4, kx, ky, kx + a.sin() * 3.0, 0.0);
    fill_rect(cr, INK, kx + a.sin() * 3.0 - 2.0, -2.5, 5.0, 3.0);
}

/// The Day of the Dead's form of the snow plow: a donkey pulls a wooden cart, and a calaca walks in front sweeping
/// the marigold petals up with a broom; they fly back over the donkey into the cart, to be taken out to the
/// graves. Facing +x, origin at the ground, the broom where the plow's blade would be. `ph` is the height of what
/// is gathered in front, `step` the wheel's turn.
pub(super) fn petal_cart(cr: &Context, ph: f64, step: f64) {
    let (wood, wood_dark) = (rgb(140, 92, 50), rgb(96, 60, 30));
    let stride = DONKEY_STRIDE as f64;
    // the cart: an open box heaped with marigolds, on one big spoked wheel
    for (i, lx) in [-96.0, -84.0, -72.0, -60.0, -48.0, -36.0, -26.0].into_iter().enumerate() {
        let odd = (i % 2) as f64;
        marigold(cr, lx + 6.0, -46.0 - odd * 3.0, 6.5, MARIGOLD[i % MARIGOLD.len()]);
        marigold(cr, lx, -42.0 + odd * 2.0, 6.0, MARIGOLD[(i + 2) % MARIGOLD.len()]);
    }
    fill_rect(cr, wood, -100.0, -42.0, 78.0, 24.0);
    flat(cr, wood_dark, 1.2, -100.0, -34.0, -22.0, -34.0);
    flat(cr, wood_dark, 1.2, -100.0, -26.0, -22.0, -26.0);
    fill_rect(cr, wood_dark, -100.0, -44.0, 78.0, 3.0);
    for x in [-100.0, -61.0, -25.0] {
        fill_rect(cr, wood_dark, x, -44.0, 3.0, 26.0);
    }
    // a strip of papel picado along the side
    for k in 0..4 {
        fill_rect(cr, PICADO[k % PICADO.len()], -93.0 + k as f64 * 18.0, -40.0, 12.0, 6.0);
    }
    // the shafts to the donkey
    round(cr, wood_dark, 3.0, -24.0, -28.0, 16.0, -36.0);
    // the wheel
    fill_ellipse(cr, wood_dark, -78.0, -36.0, 36.0, 36.0);
    draw_ellipse(cr, wood, 2.5, -74.0, -32.0, 28.0, 28.0);
    for k in 0..6 {
        let a = step + k as f64 * PI / 3.0;
        flat(cr, wood, 2.0, -60.0, -18.0, -60.0 + a.cos() * 14.0, -18.0 + a.sin() * 14.0);
    }
    fill_ellipse(cr, wood_dark, -63.0, -21.0, 6.0, 6.0);

    // the donkey: grey, with long ears, a dark mane and a garland of marigolds round the neck
    let (fur, fur_dark, belly) = (rgb(132, 122, 116), rgb(92, 84, 80), rgb(196, 188, 180));
    donkey_leg(cr, 4.0, (step * stride + 1.2).sin() * 0.45, fur_dark);
    donkey_leg(cr, 34.0, (step * stride + 1.2 + PI).sin() * 0.45, fur_dark);
    // tail
    bezier(cr, fur_dark, 2.0, [0.0, -38.0, -8.0, -34.0, -8.0, -24.0, -6.0, -18.0]);
    fill_ellipse(cr, INK, -10.0, -22.0, 6.0, 7.0);
    fill_ellipse(cr, fur, -2.0, -46.0, 44.0, 22.0);
    fill_ellipse(cr, belly, 6.0, -32.0, 30.0, 9.0);
    donkey_leg(cr, 8.0, (step * stride + PI).sin() * 0.45, fur);
    donkey_leg(cr, 38.0, (step * stride).sin() * 0.45, fur);
    // harness
    flat(cr, rgb(150, 40, 40), 2.2, 14.0, -46.0, 14.0, -26.0);
    // neck and head
    let nod = (step * stride).sin() * 1.2;
    fill_polygon(cr, fur, &[(30.0, -44.0), (46.0, -62.0 + nod), (56.0, -56.0 + nod), (42.0, -30.0)]);
    fill_ellipse(cr, fur, 44.0, -66.0 + nod, 18.0, 12.0);
    fill_ellipse(cr, belly, 55.0, -62.0 + nod, 11.0, 9.0);
    fill_ellipse(cr, INK, 61.0, -59.5 + nod, 2.0, 2.0);
    fill_ellipse(cr, INK, 50.0, -63.0 + nod, 2.8, 2.8);
    // ears
    fill_polygon(cr, fur, &[(45.0, -64.0 + nod), (38.0, -80.0 + nod), (42.0, -81.0 + nod), (49.0, -65.0 + nod)]);
    fill_polygon(cr, fur_dark, &[(48.0, -65.0 + nod), (46.0, -82.0 + nod), (50.0, -82.0 + nod), (52.0, -65.0 + nod)]);
    // mane
    for k in 0..5 {
        let kf = k as f64;
        let lift = nod * kf / 5.0;
        round(cr, INK, 2.0, 32.0 + kf * 3.0, -46.0 - kf * 3.6 + lift, 29.0 + kf * 3.0, -50.0 - kf * 3.6 + lift);
    }
    // the marigold garland round the neck
    for k in 0..4 {
        let kf = k as f64;
        marigold(cr, 34.0 + kf * 4.0, -36.0 - kf * 5.0 + nod * kf / 4.0, 3.0, MARIGOLD[k]);
    }

    // the calaca with the broom, walking in front (its legs keep the donkey's time)
    let saved = cr.matrix();
    cr.translate(80.0, 0.0);
    cr.scale(1.1, 1.1);
    calaca(
        cr,
        CalacaPose {
            tunic: 2,
            gift: 0,
            walking: true,
            waving: false,
            carries_gift: false,
            walk: (step * stride).rem_euclid(4.0 * PI),
            stand: 0.0,
            wave: 0.0,
        },
    );
    cr.set_matrix(saved);
    // the broom: the handle from the calaca's hands down to the ground in front, the head swinging
    let swing = (step * stride * 2.0).sin() * 5.0;
    round(cr, wood_dark, 2.2, 82.0, -38.0, 96.0 + swing, -3.0);
    fill_polygon(
        cr,
        rgb(214, 170, 72),
        &[(92.0 + swing, -6.0), (102.0 + swing, -6.0), (108.0 + swing, 1.0), (88.0 + swing, 1.0)],
    );
    for k in 0..5 {
        let kf = k as f64;
        flat(cr, rgb(150, 110, 40), 0.8, 90.0 + swing + kf * 4.0, -5.0, 89.0 + swing + kf * 4.6, 1.0);
    }
    // petals gathered in front of the broom
    for (i, lx) in [100.0, 107.0, 114.0].into_iter().enumerate() {
        if (i as f64) * 6.0 < ph {
            fill_ellipse(cr, MARIGOLD[i % MARIGOLD.len()], lx + swing - 5.0, -6.0 - (i % 2) as f64 * 2.0, 10.0, 6.0);
        }
    }
}

// ---------------------------------------------------------------------- papel picado
/// The dead's form of the Christmas lights: a flag of thin cut paper in a bright colour hangs at every bulb's
/// place, a little turned with the string's slope, with a zigzag hem and a pattern cut out of it (the desktop shows
/// through the holes). Nothing in it moves, so it is drawn once into the strip's image, over the string. `w` is
/// the strip's width in pixels and `s` the screen's scale.
pub(super) fn papel_picado(cr: &Context, w: f64, s: f64) {
    let (span, sag, top) = (230.0 * s, 22.0 * s, 1.0);
    let (fw, fh, k) = (26.0 * s, 30.0 * s, s);
    let cy = fh * 0.48;
    let hole = rgb(0, 0, 0);
    let mut idx = 0usize;
    let mut x0 = -span * 0.3;
    while x0 < w {
        for b in 0..4 {
            let u = (b as f64 + 0.5) / 4.0;
            let (bx, by) = (x0 + u * span, top + sag * (1.0 - (2.0 * u - 1.0) * (2.0 * u - 1.0)));
            let slope = sag * -4.0 * (2.0 * u - 1.0) / span;
            let col = PICADO[idx % PICADO.len()];
            let saved = cr.matrix();
            cr.translate(bx, by);
            cr.rotate(slope.atan() * 0.6 + (idx as f64 * 1.9).sin() * 0.05);
            // the flag, with a zigzag hem
            let teeth = 6;
            let mut flag = vec![(-fw / 2.0, 0.0), (fw / 2.0, 0.0), (fw / 2.0, fh - 3.0 * s)];
            for t in 0..teeth {
                flag.push((fw / 2.0 - fw * (t as f64 + 0.5) / teeth as f64, fh));
                flag.push((fw / 2.0 - fw * (t + 1) as f64 / teeth as f64, fh - 3.0 * s));
            }
            fill_polygon(cr, col, &flag);
            // the pattern is cut out: these shapes take away what is there
            cr.set_operator(cairo::Operator::Clear);
            match idx % 3 {
                0 => {
                    // a flower: five petals around a hole
                    for j in 0..5 {
                        let a = j as f64 * 1.2566 - PI / 2.0;
                        fill_ellipse(cr, hole, a.cos() * 5.0 * k - 2.6 * k, cy + a.sin() * 5.0 * k - 2.6 * k, 5.2 * k, 5.2 * k);
                    }
                    fill_ellipse(cr, hole, -1.6 * k, cy - 1.6 * k, 3.2 * k, 3.2 * k);
                }
                1 => {
                    // a small skull: the head with eyes and nose left standing
                    fill_ellipse(cr, hole, -6.5 * k, cy - 7.0 * k, 13.0 * k, 12.0 * k);
                    fill_rect(cr, hole, -4.0 * k, cy + 3.0 * k, 8.0 * k, 4.5 * k);
                    cr.set_operator(cairo::Operator::Over);
                    fill_ellipse(cr, col, -4.4 * k, cy - 2.6 * k, 3.6 * k, 3.6 * k);
                    fill_ellipse(cr, col, 0.8 * k, cy - 2.6 * k, 3.6 * k, 3.6 * k);
                    fill_polygon(cr, col, &[(0.0, cy + 1.5 * k), (-1.2 * k, cy + 3.4 * k), (1.2 * k, cy + 3.4 * k)]);
                    for dx in [-2.0, 0.0, 2.0] {
                        flat(cr, col, 0.8 * k, dx * k, cy + 4.5 * k, dx * k, cy + 7.5 * k);
                    }
                    cr.set_operator(cairo::Operator::Clear);
                }
                _ => {
                    // four diamonds
                    for (dx, dy) in [(0.0, -6.0), (-6.0, 0.0), (6.0, 0.0), (0.0, 6.0)] {
                        fill_polygon(
                            cr,
                            hole,
                            &[
                                (dx * k, cy + (dy - 3.2) * k),
                                (dx * k + 3.2 * k, cy + dy * k),
                                (dx * k, cy + (dy + 3.2) * k),
                                (dx * k - 3.2 * k, cy + dy * k),
                            ],
                        );
                    }
                }
            }
            // a row of small holes along the top and the sides
            for j in 0..5 {
                fill_ellipse(cr, hole, -fw / 2.0 + fw * (j as f64 + 0.5) / 5.0 - k, 3.0 * k, 2.0 * k, 2.0 * k);
            }
            for yy in [fh * 0.3, fh * 0.55] {
                fill_ellipse(cr, hole, -fw / 2.0 + 2.0 * k, yy, 2.0 * k, 2.0 * k);
                fill_ellipse(cr, hole, fw / 2.0 - 4.0 * k, yy, 2.0 * k, 2.0 * k);
            }
            cr.set_operator(cairo::Operator::Over);
            // folded over the string
            fill_rect(cr, c(0, 0, 0, 40), -fw / 2.0, 0.0, fw, 1.4 * s);
            cr.set_matrix(saved);
            idx += 1;
        }
        x0 += span;
    }
}

// ---------------------------------------------------------------------- candles on the window edges
/// One of the small candles on a window's edge: `tall` points high, standing at the origin, with its flame and
/// glow at brightness `flicker` (about 0.65 to 1) and the flame leaning with `t`.
fn ledge_candle(cr: &Context, tall: f64, flicker: f64, t: f64) {
    glow(cr, c(255, 200, 90, (210.0 * flicker).clamp(0.0, 255.0) as u8), 0.0, -tall - 4.0, 20.0 * flicker);
    // the wax stub, lit from the left
    fill_rect(cr, rgb(250, 242, 222), -tall * 0.156, -tall * 0.94, tall * 0.3125, tall * 0.94);
    fill_rect(cr, rgb(222, 206, 176), tall * 0.03, -tall * 0.94, tall * 0.125, tall * 0.94);
    flat(cr, rgb(60, 40, 30), 0.8, 0.0, -tall * 0.94, 0.0, -tall * 0.94 - 2.0);
    let (fx, fw, fh) = ((t * 1.3).sin() * 0.4, 5.5, 9.0 * flicker);
    let fy = -tall - 3.5 * flicker - fh / 2.0;
    cr.new_path();
    cr.move_to(fx, fy);
    cr.curve_to(fx + fw * 0.47, fy + fh * 0.44, fx + fw * 0.34, fy + fh, fx, fy + fh);
    cr.curve_to(fx - fw * 0.34, fy + fh, fx - fw * 0.47, fy + fh * 0.44, fx, fy);
    cr.close_path();
    fill_with(cr, rgb(255, 170, 30));
    fill_ellipse(cr, rgb(255, 246, 200), fx - fw * 0.125, fy + fh * 0.45, fw * 0.25, fh * 0.4);
}

impl Layer {
    /// Small candles stand on the edges of windows where petals lie, half sunk into them, one about every 150
    /// points, at places fixed on the window (so they stay put while the petals grow). A candle only stands where
    /// the edge is not hidden by a window in front. The flames flicker, so the candles are drawn every frame over
    /// the cached petals (which clearing restores under them). Sizes are in the window snow's unit, `ledge_u`.
    pub(super) fn draw_ledge_candles(&mut self, st: &SceneState) {
        if !(st.muertos && st.window_snow) {
            return;
        }
        let u = st.ledge_u;
        let (ox, oy, w) = (self.rect.x as f32, self.rect.y as f32, self.w as f32);
        for l in st.ledges {
            if !self.shows(l) {
                continue;
            }
            let edge = l.settled.y - oy;
            let id = (l.id & 0xFFFF) as i32;
            let wide = l.settled.w / u;
            let count = (((wide - 40.0) / 150.0) as i32).max(1);
            let gap = (wide - 40.0) / count as f32;
            for k in 0..count {
                let jitter = ((id * 7 + k * 13) % 9 - 4) as f32 * 3.0;
                let gx = l.settled.x + (20.0 + gap * (k as f32 + 0.5) + jitter) * u;
                let tall = 14.0 + ((id + k * 5) % 3) as f32 * 2.5;
                if gx < ox - 20.0 * u || gx > ox + w + 20.0 * u || !l.is_visible(gx) {
                    continue;
                }
                let h = l.height_at(gx);
                if h < 1.2 * u {
                    continue; // no petals here yet: the candle comes with them
                }
                let (foot, x) = (edge - h * 0.55, gx - ox);
                let t = st.time * (7 + k % 3) as f64 + k as f64 * 1.7 + (id % 11) as f64;
                let flicker = 0.82 + 0.1 * t.sin() + 0.08 * (t * 2.3 + 1.0).sin();
                self.mark(x - 22.0 * u, foot - (tall + 26.0) * u, 44.0 * u, (tall + 28.0) * u);
                let cr = &self.canvas.cr;
                let saved = cr.matrix();
                cr.translate(x as f64, foot as f64);
                cr.scale(u as f64, u as f64);
                ledge_candle(cr, tall as f64, flicker, t);
                cr.set_matrix(saved);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn there_are_ten_petal_pictures_and_each_has_something_in_it() {
        let sprites = make_petal_sprites().unwrap();
        assert_eq!(sprites.len(), 10);
        for s in &sprites {
            assert_eq!(s.len(), LEAF_PX * LEAF_PX);
            assert!(s.iter().filter(|p| **p >> 24 > 200).count() > 300);
        }
    }

    #[test]
    fn every_figure_draws_at_every_stage_and_pose() {
        let img = Image::new(400, 300).unwrap();
        let cr = &img.cr;
        cr.translate(200.0, 250.0);
        for stage in 1..=12 {
            ofrenda(cr, stage);
        }
        monarchs(cr, 1.3);
        petal_cart(cr, 12.0, 2.5);
        for tunic in 0..4 {
            for (walking, waving, carries_gift) in [(true, false, false), (false, false, true), (false, true, false)] {
                let pose = CalacaPose { tunic, gift: tunic, walking, waving, carries_gift, walk: 1.0, stand: 0.7, wave: 2.0 };
                calaca(cr, pose);
            }
        }
        img.surface.flush();
        assert!(img.pixels.iter().any(|p| *p != 0));
    }

    #[test]
    fn the_papel_picado_has_holes_cut_through_the_flags() {
        let (w, h, s) = (460, 70, 1.0);
        let img = Image::new(w, h).unwrap();
        papel_picado(&img.cr, w as f64, s);
        img.surface.flush();
        // the second flag hangs three eighths of the way along the first span (which starts at x = -69), about 22
        // pixels down the sagging string: its middle column has both paper and holes (the cut-out skull)
        let (x, mut paper, mut holes) = ((-69.0 + 230.0 * 0.375) as usize, 0, 0);
        for y in 27..52 {
            if img.pixels[y * w as usize + x] >> 24 > 200 {
                paper += 1;
            } else if img.pixels[y * w as usize + x] >> 24 < 30 {
                holes += 1;
            }
        }
        assert!(paper > 3 && holes > 1, "paper {paper}, holes {holes}");
    }
}
