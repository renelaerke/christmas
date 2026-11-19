//! Santa's sleigh with four reindeer (Rudolph in front), and the sparks and stars, drawn where they are on this
//! screen. They move in global coordinates (`figures.rs`). Ported from `DrawSantaAndSparks` in `src/Layer.cs`.

use cairo::{Context, LineCap};

use super::draw::*;
use super::{Layer, SceneState};

const DEER: Argb = rgb(145, 95, 55);
const DEER_DARK: Argb = rgb(100, 62, 32);

impl Layer {
    pub(super) fn draw_santa_and_sparks(&mut self, st: &SceneState) {
        let (ox, oy) = (self.rect.x as f32, self.rect.y as f32);
        let (w, h) = (self.w as f32, self.h as f32);
        for sp in st.sparks {
            let (x, y) = (sp.x - ox, sp.y - oy);
            if x < -20.0 || y < -20.0 || x > w + 20.0 || y > h + 20.0 {
                continue;
            }
            let life = if sp.star { sp.life.min(1.0) } else { sp.life / sp.max };
            let a = (255.0 * life) as u8;
            let col = if sp.gold { (a, 255, 220, 120) } else { (a, 255, 255, 255) };
            self.mark(x - sp.size * 1.6, y - sp.size * 1.6, sp.size * 3.2, sp.size * 3.2);
            let (x, y, size) = (x as f64, y as f64, sp.size as f64);
            let cr = &self.canvas.cr;
            if sp.star {
                fill_polygon(cr, col, &star_points(x, y, size, size * 0.45, sp.life as f64));
            } else {
                fill_ellipse(cr, col, x - size / 2.0, y - size / 2.0, size, size);
            }
            if !sp.star && sp.size > 3.5 * self.s {
                line(cr, col, 1.0, LineCap::Butt, x - size * 1.5, y, x + size * 1.5, y);
                line(cr, col, 1.0, LineCap::Butt, x, y - size * 1.5, x, y + size * 1.5);
            }
        }

        let Some(santa) = st.santa else { return };
        let sc = santa.scale * 1.1;
        let (sx, sy) = (santa.x - ox, santa.y() - oy);
        if sx < -330.0 * sc || sx > w + 330.0 * sc || sy < -150.0 * sc || sy > h + 150.0 * sc {
            return;
        }
        self.mark(sx - 330.0 * sc, sy - 135.0 * sc, 660.0 * sc, 195.0 * sc);

        let cr = &self.canvas.cr;
        let saved = cr.matrix();
        cr.translate(sx as f64, sy as f64);
        cr.scale((santa.dir * sc) as f64, sc as f64);
        cr.rotate(((santa.phase as f64 * 0.9).cos() * -4.0 * santa.dir as f64).to_radians());
        let t = santa.phase as f64;

        let rx = [80.0, 140.0, 200.0, 260.0];
        let mut ry = [0.0; 4];
        for (i, y) in ry.iter_mut().enumerate() {
            *y = -40.0 + (t * 6.0 + i as f64 * 0.8).sin() * 3.0;
        }
        for i in 0..4 {
            line(cr, rgb(120, 60, 30), 1.4, LineCap::Butt, -14.0, -44.0, rx[i] + 4.0, ry[i] - 6.0);
        }
        for i in 0..4 {
            reindeer(cr, rx[i], ry[i], i as f64 * 0.8, i == 3, t);
        }

        // the sack with presents, and Santa
        fill_ellipse(cr, rgb(150, 110, 60), -92.0, -66.0, 36.0, 40.0);
        fill_rect(cr, rgb(40, 140, 70), -84.0, -74.0, 12.0, 12.0);
        fill_rect(cr, rgb(60, 100, 200), -72.0, -70.0, 10.0, 9.0);
        fill_rect(cr, GOLD, -79.0, -74.0, 2.0, 12.0);

        fill_ellipse(cr, SANTA_RED, -52.0, -58.0, 32.0, 42.0);
        line(cr, SANTA_RED, 7.0, LineCap::Round, -32.0, -48.0, -16.0, -44.0);
        let black = rgb(30, 30, 30);
        fill_ellipse(cr, black, -19.0, -48.0, 8.0, 8.0);
        fill_ellipse(cr, SKIN, -45.0, -76.0, 19.0, 19.0);
        fill_ellipse(cr, WHITE, -42.0, -68.0, 18.0, 20.0);
        fill_ellipse(cr, WHITE, -31.0, -70.0, 9.0, 5.0);
        fill_ellipse(cr, rgb(240, 150, 140), -28.0, -71.0, 5.0, 5.0);
        fill_ellipse(cr, black, -32.0, -74.0, 2.6, 2.6);
        fill_polygon(cr, SANTA_RED, &[(-47.0, -72.0), (-25.0, -74.0), (-40.0, -90.0), (-56.0, -86.0)]);
        fill_rect(cr, WHITE, -48.0, -76.0, 25.0, 5.0);
        fill_ellipse(cr, WHITE, -61.0, -91.0, 9.0, 9.0);

        // the sleigh
        cr.new_path();
        cr.move_to(-82.0, -46.0);
        cr.curve_to(-70.0, -36.0, -78.0, -4.0, -60.0, 2.0);
        cr.line_to(12.0, 2.0);
        cr.curve_to(26.0, 2.0, 30.0, -18.0, 40.0, -22.0);
        cr.line_to(34.0, -27.0);
        cr.curve_to(22.0, -16.0, 0.0, -21.0, -48.0, -23.0);
        cr.line_to(-72.0, -48.0);
        cr.close_path();
        let grad = cairo::LinearGradient::new(0.0, -46.0, 0.0, 4.0);
        grad.add_color_stop_rgb(0.0, 200.0 / 255.0, 30.0 / 255.0, 40.0 / 255.0);
        grad.add_color_stop_rgb(1.0, 120.0 / 255.0, 10.0 / 255.0, 20.0 / 255.0);
        let _ = cr.set_source(&grad);
        let _ = cr.fill_preserve();
        stroke(cr, GOLD, 2.0, LineCap::Butt);

        // runners
        line(cr, GOLD, 3.0, LineCap::Round, -55.0, 2.0, -55.0, 12.0);
        line(cr, GOLD, 3.0, LineCap::Round, 5.0, 2.0, 5.0, 12.0);
        line(cr, GOLD, 3.0, LineCap::Round, -72.0, 12.0, 22.0, 12.0);
        cr.new_path();
        cr.move_to(22.0, 12.0);
        cr.curve_to(36.0, 12.0, 38.0, -2.0, 28.0, -4.0);
        stroke(cr, GOLD, 3.0, LineCap::Round);
        cr.new_path();
        cr.move_to(-72.0, 12.0);
        cr.curve_to(-80.0, 12.0, -80.0, 4.0, -74.0, 4.0);
        stroke(cr, GOLD, 3.0, LineCap::Round);
        cr.set_matrix(saved);
    }
}

fn reindeer(cr: &Context, x: f64, y: f64, phase: f64, rudolph: bool, t: f64) {
    let gal = t * 9.0 + phase;
    let pi = std::f64::consts::PI;
    let leg = |c: Argb, w: f64, hx: f64, hy: f64, a: f64| {
        line(cr, c, w, LineCap::Round, hx, hy, hx + a.sin() * 15.0, hy + a.cos() * 15.0);
    };
    let far = rgb(85, 52, 28);
    leg(far, 3.2, x + 9.0, y + 4.0, (gal + 0.6).sin() * 0.8 + 0.5);
    leg(far, 3.2, x - 9.0, y + 4.0, (gal + pi + 0.6).sin() * 0.8 - 0.4);
    leg(DEER_DARK, 3.6, x + 14.0, y + 4.0, gal.sin() * 0.8 + 0.5);
    leg(DEER_DARK, 3.6, x - 14.0, y + 4.0, (gal + pi).sin() * 0.8 - 0.4);

    fill_ellipse(cr, WHITE, x - 27.0, y - 9.0, 8.0, 7.0);
    fill_ellipse(cr, DEER, x - 22.0, y - 10.0, 44.0, 20.0);
    fill_ellipse(cr, rgb(200, 160, 110), x - 14.0, y - 1.0, 28.0, 8.0);
    fill_polygon(cr, DEER, &[(x + 10.0, y - 6.0), (x + 18.0, y - 25.0), (x + 26.0, y - 22.0), (x + 21.0, y + 2.0)]);
    fill_ellipse(cr, DEER, x + 16.0, y - 32.0, 16.0, 11.0);
    fill_ellipse(cr, DEER, x + 26.0, y - 29.0, 11.0, 8.0);
    fill_ellipse(cr, DEER_DARK, x + 14.0, y - 33.0, 7.0, 4.0);
    fill_ellipse(cr, rgb(0, 0, 0), x + 23.0, y - 30.0, 2.5, 2.5);

    let ant = rgb(205, 175, 125);
    for (x1, y1, x2, y2) in [
        (20.0, -31.0, 16.0, -45.0),
        (17.0, -41.0, 11.0, -45.0),
        (16.0, -45.0, 20.0, -51.0),
        (23.0, -31.0, 27.0, -45.0),
        (26.0, -41.0, 32.0, -44.0),
    ] {
        line(cr, ant, 2.0, LineCap::Round, x + x1, y + y1, x + x2, y + y2);
    }
    line(cr, rgb(190, 20, 30), 3.0, LineCap::Butt, x + 8.0, y - 9.0, x + 5.0, y + 9.0);
    fill_ellipse(cr, GOLD, x + 3.0, y + 5.0, 4.5, 4.5);

    if rudolph {
        let a = (90.0 + 70.0 * (t * 6.0).sin()) as u8;
        fill_ellipse(cr, (a, 255, 60, 50), x + 30.0, y - 33.0, 15.0, 15.0);
        fill_ellipse(cr, rgb(240, 30, 30), x + 34.0, y - 29.0, 7.0, 7.0);
    } else {
        fill_ellipse(cr, rgb(40, 25, 15), x + 35.0, y - 27.0, 4.0, 4.0);
    }
}
