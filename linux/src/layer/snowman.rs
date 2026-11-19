//! The snowman the elves build on the primary screen, one step more each day from the first start (12 stages).
//! Ported from `DrawSnowman` in `src/Layer.cs`.

use cairo::{Context, LineCap};

use super::draw::*;

pub const MAX_STAGE: i32 = 12;

/// The box the snowman fills when it stands at (x, y) on a screen of scale `s`.
pub(super) fn bounds(x: f32, y: f32, s: f32) -> (f32, f32, f32, f32) {
    (x - 62.0 * s, y - 135.0 * s, 124.0 * s, 142.0 * s)
}

/// Draws the snowman at `stage` standing at (x, y). It is drawn into the cached ground image (`ground.rs`), so the
/// snow pile, drawn after it, covers its foot as on Windows.
pub(super) fn draw(cr: &Context, x: f64, y: f64, s: f64, stage: i32) {
    let saved = cr.matrix();
    cr.translate(x, y);
    cr.scale(s, s);

    fill_ellipse(cr, SHADOW, -30.0, -3.0, 60.0, 6.0);
    let wood = rgb(110, 70, 35);
    let stick = |x1, y1, x2, y2| line(cr, wood, 2.6, LineCap::Round, x1, y1, x2, y2);
    if stage >= 12 {
        stick(32.0, -6.0, 46.0, -104.0);
        fill_polygon(cr, rgb(215, 175, 90), &[(24.0, 6.0), (42.0, 6.0), (37.0, -14.0), (31.0, -14.0)]);
        line(cr, rgb(170, 30, 30), 2.0, LineCap::Butt, 30.0, -11.0, 38.0, -11.0);
    }
    if stage >= 8 {
        stick(-15.0, -66.0, -40.0, -84.0);
        stick(-33.0, -79.0, -37.0, -91.0);
        stick(-33.0, -79.0, -44.0, -78.0);
        stick(15.0, -66.0, 40.0, -80.0);
        stick(33.0, -76.0, 39.0, -88.0);
    }

    if stage == 1 {
        ball(cr, 0.0, -11.0, 11.0);
    } else {
        ball(cr, 0.0, -24.0, 25.0);
    }
    if stage >= 3 {
        ball(cr, 0.0, -62.0, 18.0);
    }
    if stage >= 4 {
        ball(cr, 0.0, -92.0, 13.0);
    }

    let coal = rgb(35, 35, 40);
    let red = rgb(200, 30, 40);
    if stage >= 7 {
        for i in 0..3 {
            fill_ellipse(cr, coal, -2.4, -72.4 + i as f64 * 9.0, 4.8, 4.8);
        }
    }
    if stage >= 10 {
        fill_rect(cr, red, -13.0, -82.0, 26.0, 6.0);
        fill_polygon(cr, red, &[(5.0, -78.0), (12.0, -78.0), (15.0, -57.0), (8.0, -57.0)]);
        line(cr, WHITE, 1.5, LineCap::Butt, 9.0, -66.0, 14.0, -66.0);
        line(cr, WHITE, 1.5, LineCap::Butt, 10.0, -61.0, 15.0, -61.0);
    }
    if stage >= 5 {
        fill_ellipse(cr, coal, -6.5, -98.0, 4.0, 4.0);
        fill_ellipse(cr, coal, 2.5, -98.0, 4.0, 4.0);
    }
    if stage >= 6 {
        fill_polygon(cr, rgb(240, 130, 30), &[(0.0, -93.0), (19.0, -89.5), (0.0, -87.0)]);
    }
    if stage >= 9 {
        for i in -2..=2 {
            let sx = i as f64 * 3.0;
            let sy = -86.0 + 2.0 * (1.0 - (sx / 6.0) * (sx / 6.0)) + 1.0;
            fill_ellipse(cr, coal, sx - 1.1, sy - 1.1, 2.2, 2.2);
        }
    }
    if stage >= 11 {
        fill_rect(cr, coal, -15.0, -106.0, 30.0, 4.0);
        fill_rect(cr, coal, -10.0, -127.0, 20.0, 22.0);
        fill_rect(cr, red, -10.0, -110.0, 20.0, 4.0);
    }
    if stage >= 12 {
        fill_rect(cr, rgb(40, 140, 70), -50.0, -13.0, 15.0, 13.0);
        line(cr, GOLD, 1.8, LineCap::Butt, -42.5, -13.0, -42.5, 0.0);
        line(cr, GOLD, 1.8, LineCap::Butt, -50.0, -6.5, -35.0, -6.5);
        draw_ellipse(cr, GOLD, 1.8, -46.0, -17.0, 3.5, 3.5);
        draw_ellipse(cr, GOLD, 1.8, -42.5, -17.0, 3.5, 3.5);
    }
    cr.set_matrix(saved);
}

/// A snowball, white at the top left shading to blue-grey (GDI+'s 50° gradient across its box).
fn ball(cr: &Context, cx: f64, cy: f64, r: f64) {
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
