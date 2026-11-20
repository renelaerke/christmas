//! The string of Christmas lights along the top of the screen, twinkling slowly. Ported from `DrawLights` and
//! `RenderLights` in `src/Layer.cs`.
//!
//! Windows renders, copies and presents the whole strip every frame, because falling snow keeps erasing it. Here:
//! - clearing restores the strip from its image (`Layer::clear_rects`), so snow passing through costs nothing;
//! - the wire never changes, so it is rendered once (`wire`); 10 times a second (4 in power-save mode) only each
//!   bulb's own box is restored from it, its bulb drawn at the new brightness, and just that box copied to the
//!   screen and sent. The bulbs are far enough apart that their glows never overlap.

use cairo::{Context, LineCap};

use super::draw::*;
use super::{blend_leaf, leaf_sprite, Layer, SceneState};
use crate::x11::{Rect, Res};

/// The lanterns' light in the autumn theme (`LanternColors` on Windows).
const LANTERN_COLORS: [Argb; 3] = [rgb(255, 170, 50), rgb(255, 140, 40), rgb(255, 200, 90)];

const BULB_COLORS: [Argb; 5] =
    [rgb(255, 60, 60), rgb(60, 220, 90), rgb(255, 200, 60), rgb(80, 150, 255), rgb(255, 110, 200)];
const PER_SPAN: usize = 4;

struct Bulb {
    x: f64,
    y: f64,
    color: Argb,
    index: usize,
    /// The box its glow, socket and bulb fit in, clipped to the strip.
    rect: Rect,
}

pub(super) struct LightsImage {
    /// What is on screen in the strip: the wire and the bulbs as last drawn. Clearing restores from this.
    current: Image,
    /// The wire alone.
    wire: Image,
    bulbs: Vec<Bulb>,
    pub(super) h: i32,
    w: i32,
    timer: f32,
    /// The autumn theme's form: a vine of leaves with small lanterns (`MakeGarland` on Windows).
    autumn: bool,
}

impl LightsImage {
    fn new(w: i32, h: i32, s: f64, autumn: bool, leaves: &[Vec<u32>]) -> Res<LightsImage> {
        let (span, sag, top) = (230.0 * s, 22.0 * s, 1.0);
        let mut wire = Image::new(w, h)?;
        let mut bulbs = Vec::new();
        let mut x0 = -span * 0.3;
        while x0 < w as f64 {
            let pts: Vec<(f64, f64)> = (0..=12)
                .map(|k| {
                    let u = k as f64 / 12.0;
                    (x0 + u * span, top + sag * (1.0 - (2.0 * u - 1.0) * (2.0 * u - 1.0)))
                })
                .collect();
            wire.cr.new_path();
            curve_path(&wire.cr, &pts);
            if autumn {
                stroke(&wire.cr, (235, 104, 68, 34), 2.0 * s, LineCap::Round);
            } else {
                stroke(&wire.cr, (220, 25, 60, 35), 2.0 * s, LineCap::Butt);
            }
            for b in 0..PER_SPAN {
                let u = (b as f64 + 0.5) / PER_SPAN as f64;
                let (x, y) = (x0 + u * span, top + sag * (1.0 - (2.0 * u - 1.0) * (2.0 * u - 1.0)));
                let index = bulbs.len();
                // the glow is the widest part: 26 points across, from 1 point below the socket
                let r = Rect::new(
                    (x - 14.0 * s) as i32 - 1,
                    (y - 1.0) as i32 - 1,
                    (28.0 * s) as i32 + 3,
                    (29.0 * s) as i32 + 3,
                );
                let color = if autumn {
                    LANTERN_COLORS[index % LANTERN_COLORS.len()]
                } else {
                    BULB_COLORS[index % BULB_COLORS.len()]
                };
                bulbs.push(Bulb { x, y, color, index, rect: r.clip(w, h) });
            }
            x0 += span;
        }
        wire.surface.flush();
        if autumn {
            // leaves along the vine, each hanging by its stalk at its own angle (none where a lantern hangs)
            let (sf, mut n) = (s as f32, 0usize);
            let mut x0 = -span * 0.3;
            while x0 < w as f64 {
                for k in (0..12).filter(|k| k % 3 != 1) {
                    let u = (k as f64 + 0.5) / 12.0;
                    let size = (15.0 + ((n * 7) % 5) as f32 * 1.5) * sf;
                    let rot = (std::f64::consts::FRAC_PI_2 + (n as f64 * 2.3).sin() * 0.8) as f32;
                    let px = (x0 + u * span) as f32;
                    let py = (top + sag * (1.0 - (2.0 * u - 1.0) * (2.0 * u - 1.0))) as f32;
                    // the stalk (the left end of the leaf's picture) sits on the vine
                    let reach = size / 2.0 - sf;
                    if let Some(sprite) = leaves.get(leaf_sprite(n * 3)) {
                        let (cx, cy) = (px + rot.cos() * reach, py + rot.sin() * reach);
                        blend_leaf(&mut wire.pixels, w, h, sprite, cx, cy, size, rot, 255);
                    }
                    n += 1;
                }
                x0 += span;
            }
            wire.surface.mark_dirty();
            // the lanterns: a hook, a roof, the unlit pane and a foot
            let (frame, dim) = (rgb(52, 40, 30), rgb(120, 72, 22));
            let cr = &wire.cr;
            for b in &bulbs {
                let (bx, by) = (b.x, b.y);
                line(cr, frame, 1.2 * s, LineCap::Butt, bx, by, bx, by + 2.5 * s);
                fill_rect(cr, frame, bx - 4.5 * s, by + 2.0 * s, 9.0 * s, 2.5 * s);
                fill_rect(cr, dim, bx - 3.5 * s, by + 4.5 * s, 7.0 * s, 9.0 * s);
                fill_rect(cr, frame, bx - 4.5 * s, by + 13.5 * s, 9.0 * s, 2.0 * s);
            }
            wire.surface.flush();
        }
        let current = Image::new(w, h)?;
        let mut l = LightsImage { current, wire, bulbs, h, w, timer: 0.0, autumn };
        l.current.pixels.copy_from_slice(&l.wire.pixels);
        Ok(l)
    }

    /// Redraws every bulb at the brightness for `time`, each in its own box over the wire.
    fn twinkle(&mut self, s: f64, time: f64) {
        let w = self.w as usize;
        let cur = &mut self.current;
        cur.surface.flush();
        for b in &self.bulbs {
            for y in b.rect.y..b.rect.bottom() {
                let start = y as usize * w + b.rect.x as usize;
                let end = start + b.rect.w as usize;
                cur.pixels[start..end].copy_from_slice(&self.wire.pixels[start..end]);
            }
        }
        cur.surface.mark_dirty();
        for b in &self.bulbs {
            if self.autumn {
                draw_lantern(&cur.cr, b, s, time);
            } else {
                draw_bulb(&cur.cr, b, s, time);
            }
        }
        cur.surface.flush();
    }
}

fn draw_bulb(cr: &Context, b: &Bulb, s: f64, time: f64) {
    let (bx, by, col, idx) = (b.x, b.y, b.color, b.index);
    let br = 0.55 + 0.45 * (time * (1.3 + ((idx * 37) % 10) as f64 * 0.12) + idx as f64 * 1.7).sin();
    let (bw, bh) = (7.0 * s, 11.0 * s);
    fill_ellipse(cr, ((70.0 * br) as u8, col.1, col.2, col.3), bx - 13.0 * s, by + s, 26.0 * s, 26.0 * s);
    fill_rect(cr, rgb(30, 70, 40), bx - 2.5 * s, by, 5.0 * s, 4.0 * s);
    let k = 0.5 + 0.5 * br;
    let bulb = rgb((col.1 as f64 * k) as u8, (col.2 as f64 * k) as u8, (col.3 as f64 * k) as u8);
    fill_ellipse(cr, bulb, bx - bw / 2.0, by + 3.0 * s, bw, bh);
    fill_ellipse(cr, ((160.0 * br) as u8, 255, 255, 255), bx - bw / 4.0, by + 5.0 * s, bw / 3.0, bh / 3.0);
}

/// The lit pane of a small lantern with its flame, over the unlit lantern in the vine's image. The same slow
/// twinkle as the bulbs.
fn draw_lantern(cr: &Context, b: &Bulb, s: f64, time: f64) {
    let (bx, by, col, idx) = (b.x, b.y, b.color, b.index);
    let br = 0.55 + 0.45 * (time * (1.3 + ((idx * 37) % 10) as f64 * 0.12) + idx as f64 * 1.7).sin();
    fill_ellipse(cr, ((70.0 * br) as u8, col.1, col.2, col.3), bx - 13.0 * s, by + s, 26.0 * s, 26.0 * s);
    fill_rect(cr, ((255.0 * br) as u8, col.1, col.2, col.3), bx - 3.5 * s, by + 4.5 * s, 7.0 * s, 9.0 * s);
    fill_ellipse(cr, ((230.0 * br) as u8, 255, 250, 215), bx - 1.5 * s, by + 7.5 * s, 3.0 * s, 5.0 * s);
}

impl Layer {
    /// Height of the lights strip.
    fn lights_height(&self) -> i32 {
        (70.0 * self.s) as i32
    }

    /// Rows of the lights strip as shown now (0 when the lights are off).
    pub(super) fn lights_strip_height(&self) -> i32 {
        self.lights.as_ref().filter(|_| self.lights_shown).map_or(0, |l| l.h)
    }

    /// Blends the strip over what is in `r` (premultiplied "over"), for snow on windows under the lights.
    /// Cairo must be flushed before and marked dirty after.
    pub(super) fn blend_lights_over(&mut self, r: Rect) {
        let Some(l) = self.lights.as_ref().filter(|_| self.lights_shown) else { return };
        let r = r.clip(self.w, l.h);
        let w = self.w as usize;
        for y in r.y..r.bottom() {
            let start = y as usize * w + r.x as usize;
            let (src, dst) =
                (&l.current.pixels[start..start + r.w as usize], &mut self.canvas.pixels[start..start + r.w as usize]);
            for (d, s) in dst.iter_mut().zip(src) {
                let sa = s >> 24;
                if sa == 0 {
                    continue;
                }
                let inv = 255 - sa;
                let ch = |sh: u32| (((s >> sh) & 0xFF) + ((*d >> sh) & 0xFF) * inv / 255).min(255);
                *d = (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0);
            }
        }
    }

    /// Restores row `y`, pixels `x0..x1`, from the lights strip if it is shown there; false if not.
    pub(super) fn restore_lights(&mut self, y: i32, x0: usize, x1: usize) -> bool {
        let Some(l) = self.lights.as_ref().filter(|l| self.lights_shown && y < l.h) else { return false };
        let start = y as usize * self.w as usize;
        self.canvas.pixels[start + x0..start + x1].copy_from_slice(&l.current.pixels[start + x0..start + x1]);
        true
    }

    pub(super) fn draw_lights(&mut self, dt: f32, st: &SceneState) {
        let lh = self.lights_height().min(self.h);
        if !st.lights {
            if self.lights_shown {
                // clear the strip next frame (it is no longer restored from the image)
                self.lights_shown = false;
                self.lights_redrawn = true;
                self.mark(0.0, 0.0, self.w as f32, lh as f32);
            }
            return;
        }
        if self.lights.as_ref().is_none_or(|l| l.h != lh || l.autumn != st.autumn) {
            match LightsImage::new(self.w, lh, self.s as f64, st.autumn, &self.leaf_sprites) {
                Ok(l) => self.lights = Some(l),
                Err(e) => {
                    crate::log::error(&format!("lights: {e}"));
                    return;
                }
            }
            self.lights_shown = false;
        }
        let interval = if st.power_save { 0.25 } else { 0.1 };
        let (w, s) = (self.w as usize, self.s as f64);
        let Some(img) = self.lights.as_mut() else { return };
        img.timer -= dt;
        if img.timer > 0.0 && self.lights_shown {
            return;
        }
        // the twinkle is slow, so 10 updates a second (4 in power-save mode) are enough
        img.timer = interval;
        img.twinkle(s, st.time);

        // copy into the screen and send: the whole strip when it appears, afterwards only the bulbs' boxes
        self.canvas.surface.flush();
        if self.lights_shown {
            for b in &img.bulbs {
                for y in b.rect.y..b.rect.bottom() {
                    let start = y as usize * w + b.rect.x as usize;
                    let end = start + b.rect.w as usize;
                    self.canvas.pixels[start..end].copy_from_slice(&img.current.pixels[start..end]);
                }
                self.present_only.push(b.rect);
            }
        } else {
            let n = img.current.pixels.len();
            self.canvas.pixels[..n].copy_from_slice(&img.current.pixels);
            self.present_only.push(Rect::new(0, 0, w as i32, lh));
        }
        self.canvas.surface.mark_dirty();
        self.lights_shown = true;
        self.lights_redrawn = true;
    }
}
