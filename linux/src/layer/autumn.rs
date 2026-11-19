//! What only the autumn theme has: the kite over the primary screen and the rain of an autumn storm. Ported from
//! `DrawKite`, `UpdateRain` and `DrawRain` in `src/LayerAutumn.cs`.

use cairo::LineCap;

use super::draw::*;
use super::{heap_at, Layer, SceneState};

/// Where the kite hangs now (it glides toward where the wind wants it).
#[derive(Clone, Copy)]
pub(super) struct Kite {
    x: f32,
    y: f32,
}

pub(super) struct RainDrop {
    x: f32,
    y: f32,
    speed: f32,
}

impl Layer {
    /// A kite hangs in the wind over the primary screen, its string tied to the scarecrow's hand (or to the ground
    /// there, until the scarecrow has an arm). It drifts with the wind: further out and higher when it blows,
    /// nearer and lower when it is calm. The tail flutters.
    pub(super) fn draw_kite(&mut self, dt: f32, st: &SceneState) {
        if !(self.primary && st.kite && st.autumn) {
            self.kite = None;
            return;
        }
        let (s, w, h) = (self.s, self.w as f32, self.h as f32);
        let base_x = w * 0.78;
        let base_y = self.ground_y - heap_at(&self.heap, base_x) + 3.0 * s;
        let held = st.snowman_stage >= 5;
        let (ax, ay) = if held { (base_x + 54.0 * s, base_y - 80.0 * s) } else { (base_x + 30.0 * s, base_y - 2.0 * s) };
        let blow = (st.wind / 90.0).clamp(-1.0, 1.0);
        let strength = (st.wind.abs() / 60.0).min(1.0);
        // the wind carries it to the lee side; with no wind it hangs to the left, over the open screen
        let side = if blow.abs() < 0.08 || blow < 0.0 { -1.0 } else { 1.0 };
        let time = st.time;
        let sway_x = (time * 0.5).sin() as f32 * 14.0 * s;
        let sway_y = (time * 0.8 + 1.0).sin() as f32 * 10.0 * s;
        let want_x = (ax + side * (170.0 + 150.0 * strength) * s + sway_x).min(w - 60.0 * s).max(60.0 * s);
        let want_y = (ay - h * (0.34 + 0.16 * strength) + sway_y).max(110.0 * s);
        let mut kite = self.kite.unwrap_or(Kite { x: want_x, y: want_y });
        // (it closes 4 % of the way ten times a second, whatever the frame rate)
        let k = 1.0 - 0.96f32.powf(dt * 10.0);
        kite.x += (want_x - kite.x) * k;
        kite.y += (want_y - kite.y) * k;
        self.kite = Some(kite);
        let lean = ((kite.x - ax) / (300.0 * s) * 0.45).clamp(-0.6, 0.6);

        // the string sags a little between the hand and the kite's lower corner
        let (kx, ky) = (kite.x - lean.sin() * 34.0 * s, kite.y + lean.cos() * 34.0 * s);
        let (mx, my) = ((ax + kx) / 2.0, (ay + ky) / 2.0 + 50.0 * s);
        let (top, bottom) = (ay.min(ky).min(my), ay.max(ky).max(my));
        self.mark(ax.min(kx) - 2.0, top - 2.0, (kx - ax).abs() + 4.0, bottom - top + 4.0);
        self.mark(kite.x - 60.0 * s, kite.y - 60.0 * s, 120.0 * s, 170.0 * s);

        let cr = &self.canvas.cr;
        cr.new_path();
        cr.move_to(ax as f64, ay as f64);
        cr.curve_to(
            (ax + (mx - ax) * 2.0 / 3.0) as f64,
            (ay + (my - ay) * 2.0 / 3.0) as f64,
            (kx + (mx - kx) * 2.0 / 3.0) as f64,
            (ky + (my - ky) * 2.0 / 3.0) as f64,
            kx as f64,
            ky as f64,
        );
        stroke(cr, (170, 235, 225, 200), s as f64, LineCap::Round);

        let saved = cr.matrix();
        cr.translate(kite.x as f64, kite.y as f64);
        cr.scale(s as f64, s as f64);
        cr.rotate(lean as f64);
        let (red, yellow, spar) = (rgb(206, 62, 40), rgb(242, 184, 52), rgb(70, 45, 25));
        // a diamond in four panels
        fill_polygon(cr, red, &[(0.0, -34.0), (22.0, -8.0), (0.0, -8.0)]);
        fill_polygon(cr, yellow, &[(0.0, -34.0), (-22.0, -8.0), (0.0, -8.0)]);
        fill_polygon(cr, yellow, &[(0.0, -8.0), (22.0, -8.0), (0.0, 34.0)]);
        fill_polygon(cr, red, &[(0.0, -8.0), (-22.0, -8.0), (0.0, 34.0)]);
        line(cr, spar, 1.2, LineCap::Butt, 0.0, -34.0, 0.0, 34.0);
        line(cr, spar, 1.2, LineCap::Butt, -22.0, -8.0, 22.0, -8.0);
        // the tail: a line of bows that flutters
        let (mut px, mut py) = (0.0, 34.0);
        for i in 1..=4 {
            let n = i as f64;
            let nx = (time * 3.1 + n * 1.2).sin() * (4.0 + n * 2.2) - lean as f64 * n * 9.0;
            let ny = 34.0 + n * 17.0;
            line(cr, (200, 235, 225, 200), 1.0, LineCap::Butt, px, py, nx, ny);
            let bow = if i % 2 == 0 { red } else { yellow };
            fill_polygon(cr, bow, &[(nx, ny), (nx - 6.0, ny - 3.5), (nx - 6.0, ny + 3.5)]);
            fill_polygon(cr, bow, &[(nx, ny), (nx + 6.0, ny - 3.5), (nx + 6.0, ny + 3.5)]);
            (px, py) = (nx, ny);
        }
        cr.set_matrix(saved);
    }

    /// In autumn a storm brings rain with it: it sets in as the weather passes "normal" on its way to storm and
    /// thins out again as the storm dies down (the same gliding amount that sets the number of leaves). The drops
    /// fall fast and slant with the wind.
    pub(super) fn update_rain(&mut self, dt: f32, st: &SceneState) {
        let (s, w, h) = (self.s, self.w as f32, self.h as f32);
        let strength = if st.autumn && st.snow_on { (st.snow_amount - 1.0).clamp(0.0, 1.0) } else { 0.0 };
        let most = if st.power_save { 70.0 } else { 130.0 };
        let target = (strength * most * (w * h / (1920.0 * 1080.0)).min(2.0)) as usize;
        let mut add = (target / 30).max(1);
        while add > 0 && self.rain.len() < target {
            let r = &mut self.rng;
            let x = -100.0 + r.f() * (w + 200.0);
            // the first half starts spread over the screen, so a storm does not begin as one sheet from the top
            let y = if self.rain.len() < target / 2 { r.f() * self.ground_y } else { -r.f() * 80.0 * s };
            let speed = (620.0 + r.f() * 260.0) * s;
            self.rain.push(RainDrop { x, y, speed });
            add -= 1;
        }
        if self.rain.is_empty() {
            return;
        }
        let slant = st.wind * s * 1.6;
        let mut over = self.rain.len().saturating_sub(target);
        let (ground, heap, rng) = (self.ground_y, &self.heap, &mut self.rng);
        self.rain.retain_mut(|d| {
            d.y += d.speed * dt;
            d.x += slant * dt;
            if d.y >= ground - heap_at(heap, d.x) {
                if over > 0 {
                    over -= 1;
                    return false;
                }
                d.x = -100.0 + rng.f() * (w + 200.0);
                d.y = -rng.f() * 80.0 * s;
            }
            true
        });
    }

    /// The drops are short streaks, all with one slant: they fall at about the same speed.
    pub(super) fn draw_rain(&mut self, st: &SceneState) {
        if self.rain.is_empty() {
            return;
        }
        let (s, w) = (self.s, self.w as f32);
        let (vx, vy) = (st.wind * s * 1.6, 750.0 * s);
        let len = (vx * vx + vy * vy).sqrt();
        let (dx, dy) = (vx / len * 8.0 * s, vy / len * 8.0 * s);
        for i in 0..self.rain.len() {
            let (x, y) = (self.rain[i].x, self.rain[i].y);
            if y <= -20.0 * s || x < -10.0 * s || x > w + 10.0 * s {
                continue;
            }
            self.mark((x - dx).min(x + dx) - s, y - dy - s, dx.abs() * 2.0 + 2.0 * s, dy * 2.0 + 2.0 * s);
            let (x1, y1, x2, y2) = ((x - dx) as f64, (y - dy) as f64, (x + dx) as f64, (y + dy) as f64);
            line(&self.canvas.cr, (107, 190, 215, 240), 1.7 * s as f64, LineCap::Round, x1, y1, x2, y2);
        }
    }
}
