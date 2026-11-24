//! What grows one stage a day on the primary screen, from the first start (12 stages): autumn's haystack and
//! scarecrow. (In the Christmas theme children build the snowman while you watch: `build.rs`.) Ported from
//! `DrawSnowman` and `DrawScarecrow` in `src/Layer.cs`.

use cairo::{Context, LineCap};

use super::draw::*;

pub const MAX_STAGE: i32 = 12;

/// What is built in the snowman's place where it grows by stages: autumn's haystack and scarecrow, the ofrenda of
/// De dødes dag (`muertos.rs`), or Halloween's jack-o'-lanterns (`halloween.rs`).
#[derive(Clone, Copy)]
pub(super) enum Built {
    Scarecrow,
    Ofrenda,
    Pumpkins,
}

/// The box the snowman fills when it stands at (x, y) on a screen of scale `s`.
pub(super) fn bounds(x: f32, y: f32, s: f32) -> (f32, f32, f32, f32) {
    (x - 62.0 * s, y - 135.0 * s, 124.0 * s, 142.0 * s)
}

/// Draws the haystack and scarecrow at `stage` standing at (x, y). It is drawn into the cached ground image
/// (`ground.rs`), so the pile, drawn after it, covers its foot as on Windows.
/// What stands there follows the theme (`Built`), each in the same place and box.
pub(super) fn draw(cr: &Context, x: f64, y: f64, s: f64, stage: i32, what: Built) {
    let saved = cr.matrix();
    cr.translate(x, y);
    cr.scale(s, s);
    match what {
        Built::Scarecrow => scarecrow(cr, stage),
        Built::Ofrenda => super::muertos::ofrenda(cr, stage),
        Built::Pumpkins => super::halloween::pumpkins(cr, stage),
    }
    cr.set_matrix(saved);
}

/// Autumn's form of the snowman (as in the macOS and Windows versions): a haystack that grows (stage 1-3) and a
/// scarecrow put up beside it piece by piece (4-12), in the same place and the same box as the snowman. Origin at
/// the ground, y up is negative.
fn scarecrow(cr: &Context, stage: i32) {
    // (red, green, blue, alpha), as the colours are written in the other two versions
    let c = |r: u8, g: u8, b: u8, a: u8| -> Argb { (a, r, g, b) };
    let round = |col: Argb, width: f64, x1: f64, y1: f64, x2: f64, y2: f64| {
        line(cr, col, width, LineCap::Round, x1, y1, x2, y2);
    };
    let flat = |col: Argb, width: f64, x1: f64, y1: f64, x2: f64, y2: f64| {
        line(cr, col, width, LineCap::Butt, x1, y1, x2, y2);
    };
    fill_ellipse(cr, c(50, 35, 20, 50), -58.0, -3.0, 120.0, 6.0);
    let (wood, straw, straw_dark, coal) = (rgb(110, 70, 35), rgb(228, 188, 84), c(160, 110, 35, 170), rgb(35, 35, 40));

    // the haystack: a dome with loose straws
    let cx = -22.0;
    let (w, h) = match stage {
        1 => (18.0, 14.0),
        2 => (27.0, 30.0),
        _ => (34.0, 46.0),
    };
    cr.new_path();
    cr.move_to(cx - w, 0.0);
    cr.curve_to(cx - w, -h * 0.9, cx - w * 0.55, -h, cx, -h);
    cr.curve_to(cx + w * 0.55, -h, cx + w, -h * 0.9, cx + w, 0.0);
    cr.close_path();
    let grad = cairo::LinearGradient::new(cx - w * 0.5, -h, cx + w * 0.5, 0.0);
    grad.add_color_stop_rgb(0.0, 238.0 / 255.0, 200.0 / 255.0, 100.0 / 255.0);
    grad.add_color_stop_rgb(1.0, 188.0 / 255.0, 138.0 / 255.0, 48.0 / 255.0);
    let _ = cr.set_source(&grad);
    let _ = cr.fill_preserve();
    stroke(cr, c(140, 95, 30, 110), 1.0, LineCap::Butt);
    let straws = match stage {
        1 => 6,
        2 => 12,
        _ => 20,
    };
    for i in 0..straws {
        let t = (i as f64 + 0.5) / straws as f64;
        let u = (i as f64 * 0.618).fract();
        let px = cx + (t * 2.0 - 1.0) * w * 0.8;
        let off = (px - cx) / w;
        let top = -h * (1.0 - off * off).sqrt();
        let py = top * (0.12 + u * 0.7);
        let lean = (if off < 0.0 { -3.0 } else { 3.0 }) * (0.4 + u);
        let col = if i % 3 == 0 { c(250, 225, 150, 170) } else { straw_dark };
        round(col, 1.2, px, py, px + lean, py + 8.0);
    }
    if stage >= 3 {
        round(straw, 1.4, cx - 4.0, -h + 1.0, cx - 9.0, -h - 6.0);
        round(straw, 1.4, cx + 2.0, -h + 1.0, cx + 4.0, -h - 7.0);
        round(straw, 1.4, cx + w - 3.0, -6.0, cx + w + 5.0, -9.0);
    }

    // the scarecrow
    let x = 30.0;
    if stage >= 4 {
        round(wood, 3.4, x, 0.0, x, -104.0);
    }
    if stage >= 5 {
        round(wood, 3.0, x - 24.0, -80.0, x + 24.0, -80.0);
    }
    if stage >= 7 {
        let (shirt, check) = (rgb(170, 62, 40), c(235, 190, 110, 120));
        fill_polygon(cr, shirt, &[(x - 10.0, -87.0), (x + 10.0, -87.0), (x + 12.0, -44.0), (x - 12.0, -44.0)]);
        fill_polygon(cr, shirt, &[(x - 10.0, -87.0), (x - 22.0, -85.0), (x - 22.0, -75.0), (x - 10.0, -73.0)]);
        fill_polygon(cr, shirt, &[(x + 10.0, -87.0), (x + 22.0, -85.0), (x + 22.0, -75.0), (x + 10.0, -73.0)]);
        for dx in [-5.0, 0.0, 5.0] {
            flat(check, 1.0, x + dx, -87.0, x + dx * 1.2, -44.0);
        }
        for y in [-76.0, -65.0, -54.0] {
            flat(check, 1.0, x - 11.0, y, x + 11.0, y);
        }
        fill_rect(cr, rgb(60, 90, 140), x + 2.0, -62.0, 6.0, 6.0);
        for dx in [-9.0, -4.0, 3.0, 8.0] {
            round(straw, 1.3, x + dx, -44.0, x + dx * 1.25, -37.0);
        }
    }
    if stage >= 8 {
        for dy in [-5.0, 0.0, 5.0] {
            round(straw, 1.4, x - 22.0, -80.0, x - 30.0, -80.0 + dy);
            round(straw, 1.4, x + 22.0, -80.0, x + 30.0, -80.0 + dy);
        }
    }
    if stage >= 6 {
        fill_ellipse(cr, rgb(222, 196, 150), x - 11.0, -109.0, 22.0, 22.0);
        draw_ellipse(cr, c(150, 120, 80, 130), 1.0, x - 11.0, -109.0, 22.0, 22.0);
        round(rgb(120, 80, 40), 1.6, x - 7.0, -88.5, x + 7.0, -88.5);
    }
    if stage >= 9 {
        let stitch = rgb(95, 55, 30);
        fill_ellipse(cr, coal, x - 6.0, -102.0, 3.6, 3.6);
        fill_ellipse(cr, coal, x + 2.4, -102.0, 3.6, 3.6);
        fill_polygon(cr, rgb(205, 95, 40), &[(x - 1.5, -97.5), (x + 3.0, -95.5), (x - 1.5, -94.0)]);
        cr.new_path();
        cr.move_to(x - 6.0, -93.0);
        cr.curve_to(x - 3.0, -89.5, x + 3.0, -89.5, x + 6.0, -93.0);
        stroke(cr, stitch, 1.2, LineCap::Round);
        for dx in [-3.5, 0.0, 3.5] {
            flat(stitch, 1.0, x + dx, -92.6, x + dx, -89.4);
        }
    }
    if stage >= 10 {
        let scarf = rgb(40, 120, 90);
        fill_rect(cr, scarf, x - 9.0, -90.0, 18.0, 5.0);
        fill_polygon(cr, scarf, &[(x + 3.0, -87.0), (x + 9.0, -87.0), (x + 13.0, -68.0), (x + 7.0, -68.0)]);
        flat(rgb(240, 225, 170), 1.3, x + 7.5, -74.0, x + 12.0, -74.0);
    }
    if stage >= 11 {
        let hat = rgb(214, 170, 72);
        fill_ellipse(cr, hat, x - 17.0, -112.0, 34.0, 7.0);
        fill_polygon(cr, hat, &[(x - 9.0, -109.0), (x + 9.0, -109.0), (x + 6.0, -123.0), (x - 6.0, -123.0)]);
        fill_rect(cr, rgb(150, 50, 35), x - 8.4, -113.0, 16.8, 3.0);
        round(straw, 1.2, x - 15.0, -108.0, x - 20.0, -104.0);
    }
    if stage >= 12 {
        // a pumpkin at its foot and a crow that is not the least bit scared
        fill_ellipse(cr, rgb(226, 120, 26), x + 10.0, -13.0, 19.0, 13.0);
        draw_ellipse(cr, rgb(180, 86, 16), 1.0, x + 15.5, -13.0, 8.0, 13.0);
        round(rgb(70, 110, 40), 2.0, x + 19.5, -13.0, x + 20.5, -17.0);
        let bx = x - 19.0;
        fill_polygon(cr, coal, &[(bx + 5.0, -87.0), (bx + 11.0, -89.0), (bx + 7.0, -84.0)]);
        fill_ellipse(cr, coal, bx - 5.0, -91.0, 11.0, 7.0);
        fill_ellipse(cr, coal, bx - 7.0, -94.0, 6.0, 6.0);
        fill_polygon(cr, rgb(230, 170, 40), &[(bx - 6.5, -92.0), (bx - 10.5, -90.8), (bx - 6.5, -89.8)]);
        flat(coal, 1.0, bx, -84.5, bx, -81.5);
    }
}

/// A snowball, white at the top left shading to blue-grey (GDI+'s 50° gradient across its box).
pub(super) fn ball(cr: &Context, cx: f64, cy: f64, r: f64) {
    let a = 50f64.to_radians();
    let reach = r * (a.cos() + a.sin());
    let (dx, dy) = (a.cos() * reach, a.sin() * reach);
    let grad = cairo::LinearGradient::new(cx - dx, cy - dy, cx + dx, cy + dy);
    grad.add_color_stop_rgb(0.0, 1.0, 1.0, 1.0);
    grad.add_color_stop_rgb(1.0, 200.0 / 255.0, 216.0 / 255.0, 238.0 / 255.0);
    cr.new_path();
    ellipse_path(cr, cx - r, cy - r, 2.0 * r, 2.0 * r);
    let _ = cr.set_source(&grad);
    let _ = cr.fill_preserve();
    stroke(cr, (70, 140, 165, 200), 1.0, LineCap::Butt);
}
