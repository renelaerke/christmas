//! The snow pile on the ground and the snowman standing in it, cached in an image of the bottom band of the
//! screen. Ported from `DrawGround` and `DrawSnowman` in `src/Layer.cs`.
//!
//! Windows draws the pile (a polygon as wide as the screen) every frame. It changes slowly, and on two 4K-class
//! screens drawing, clearing and sending it every frame cost more than all the snow and figures together. Here:
//! - clearing restores the band from the image (`Layer::clear_rects`), so snow and elves in front of it cost
//!   nothing;
//! - the image is redrawn only when the pile changed by half a pixel or more, at most 4 times a second (every
//!   frame while the plow is on this screen, so the scraped edge stays at the blade), and then only the pile's
//!   strip and the snowman's box are copied to the screen and sent.

use cairo::Context;

use super::draw::{set, Argb, Image};
use super::{blend_leaf, chance, heap_at, leaf_sprite, snowman, Layer, SceneState, HEAP_STEP};
use crate::x11::{Rect, Res};

pub(super) struct GroundImage {
    img: Image,
    /// The band's first row on the screen: room for the snowman and the tallest drift above the panel.
    y0: i32,
    /// What the image shows: the pile, the ground line and the snowman (stage, x, y) it was drawn with.
    heap: Vec<f32>,
    ground_y: f32,
    snowman: Option<(i32, i32, i32)>,
    /// Where they were drawn, in screen coordinates (cleared on the next redraw).
    pile_rect: Option<Rect>,
    snowman_rect: Option<Rect>,
    timer: f32,
}

impl GroundImage {
    fn new(w: i32, h: i32, y0: i32) -> Res<GroundImage> {
        Ok(GroundImage {
            img: Image::new(w, h - y0)?,
            y0,
            heap: Vec::new(),
            ground_y: -1.0,
            snowman: None,
            pile_rect: None,
            snowman_rect: None,
            timer: 0.0,
        })
    }
}

impl Layer {
    /// Restores row `y`, pixels `x0..x1`, from the ground image if it is shown there; false if not.
    pub(super) fn restore_ground(&mut self, y: i32, x0: usize, x1: usize) -> bool {
        let Some(g) = self.ground.as_ref().filter(|g| self.ground_shown && y >= g.y0) else { return false };
        let w = self.w as usize;
        let (dst, src) = (y as usize * w, (y - g.y0) as usize * w);
        self.canvas.pixels[dst + x0..dst + x1].copy_from_slice(&g.img.pixels[src + x0..src + x1]);
        true
    }

    pub(super) fn draw_ground(&mut self, dt: f32, st: &SceneState) {
        let (w, h, s) = (self.w, self.h, self.s);
        let y0 = ((self.panel_y - 160.0 * s - 8.0) as i32).max(0);
        if self.ground.as_ref().is_none_or(|g| g.y0 != y0) {
            // the panel moved: what the old band showed above the new one is cleared next frame
            if let Some(old) = &self.ground {
                let r = Rect::new(0, old.y0, w, y0 - old.y0);
                if !r.is_empty() {
                    self.dirty.push(r);
                }
            }
            match GroundImage::new(w, h, y0) {
                Ok(g) => self.ground = Some(g),
                Err(e) => {
                    crate::log::error(&format!("ground: {e}"));
                    return;
                }
            }
            self.ground_shown = false;
        }

        let g = self.ground_y;
        let max = self.heap.iter().cloned().fold(0.0f32, f32::max);
        // autumn's haystack stands on the pile at 78% of the width, on the primary screen only (the Christmas
        // snowman is built by children and drawn each frame: `build.rs`)
        let snowman = (self.primary && st.snowman_stage > 0 && st.leaves()).then(|| {
            let x = self.w as f32 * 0.78;
            (st.snowman_stage, x, g - heap_at(&self.heap, x) + 3.0 * s)
        });
        self.snowman_pos = snowman.map(|(_, x, y)| (self.rect.x as f32 + x, self.rect.y as f32 + y));
        let snowman_key = snowman.map(|(stage, x, y)| (stage, x as i32, y.round() as i32));
        let plow_here = self.plow_is_here(st);

        let shown = self.ground_shown;
        let Some(gi) = self.ground.as_mut() else { return };
        gi.timer -= dt;
        let drawn_max = gi.heap.iter().cloned().fold(0.0f32, f32::max);
        let changed = !shown
            || gi.ground_y != g
            || gi.snowman != snowman_key
            || (drawn_max >= 0.5) != (max >= 0.5)
            || gi.heap.iter().zip(&self.heap).any(|(a, b)| (a - b).abs() >= 0.5);
        if !changed || (shown && gi.timer > 0.0 && !plow_here) {
            return;
        }
        gi.timer = 0.25;

        // what to redraw: where the pile and the snowman were, and where they are now
        let pile_rect = (max >= 0.5).then(|| {
            // (in autumn with room for the leaves lying over the pile's top)
            let over = if st.leaves() { 16.0 * s } else { 0.0 };
            let top = (g - max - 4.0 * s - over).floor() as i32 - 2;
            Rect::new(0, top, w, (g + 4.0 * s).ceil() as i32 + 3 - top)
        });
        let snowman_rect = snowman.map(|(_, x, y)| {
            let (bx, by, bw, bh) = snowman::bounds(x, y, s);
            Rect::new(bx.floor() as i32 - 2, by.floor() as i32 - 2, bw.ceil() as i32 + 5, bh.ceil() as i32 + 5)
        });
        let join = |a: Option<Rect>, b: Option<Rect>| match (a, b) {
            (Some(a), Some(b)) => Some(Rect::union(&a, &b)),
            (a, b) => a.or(b),
        };
        let band = Rect::new(0, gi.y0, w, h - gi.y0);
        // (a snowman box overlapping the pile strip is fine: both are cleared, and the clip covers both)
        let redraw: Vec<Rect> = if shown {
            [join(gi.pile_rect, pile_rect), join(gi.snowman_rect, snowman_rect)]
                .into_iter()
                .flatten()
                .map(|r| clip_to(r, band))
                .filter(|r| !r.is_empty())
                .collect()
        } else {
            vec![band]
        };

        // clear those parts of the image, then draw the snowman and the pile over it (the pile covers his foot)
        let img = &mut gi.img;
        img.surface.flush();
        for r in &redraw {
            for y in r.y..r.bottom() {
                let start = (y - gi.y0) as usize * w as usize + r.x as usize;
                img.pixels[start..start + r.w as usize].fill(0);
            }
        }
        img.surface.mark_dirty();
        let cr = &img.cr;
        cr.save().ok();
        cr.new_path();
        for r in &redraw {
            cr.rectangle(r.x as f64, (r.y - gi.y0) as f64, r.w as f64, r.h as f64);
        }
        cr.clip();
        cr.translate(0.0, -gi.y0 as f64);
        if let Some((stage, x, y)) = snowman {
            snowman::draw(cr, x as f64, y as f64, s as f64, stage, st.muertos);
        }
        if max >= 0.5 {
            draw_pile(cr, &self.heap, g as f64, w as f64, s as f64, st.pile_fill());
        }
        cr.restore().ok();
        img.surface.flush();
        // a leaf pile is made of leaves: they are laid over its dark fill, in the pile's strip only (it is always
        // cleared and redrawn whole, so no leaf is laid twice)
        if let Some(pr) = pile_rect.filter(|_| st.leaves()).map(|r| clip_to(r, band)) {
            let rows = (g.ceil() as i32 + 2).min(pr.bottom()) - pr.y;
            if rows > 0 && pr.w == w {
                let start = (pr.y - gi.y0) as usize * w as usize;
                let buf = &mut img.pixels[start..start + rows as usize * w as usize];
                lay_leaves(buf, w, rows, &self.heap, &self.leaf_sprites, g - pr.y as f32, s);
                img.surface.mark_dirty();
            }
        }

        // copy the redrawn parts to the screen and send them
        self.canvas.surface.flush();
        for r in &redraw {
            for y in r.y..r.bottom() {
                let (dst, src) =
                    (y as usize * w as usize + r.x as usize, (y - gi.y0) as usize * w as usize + r.x as usize);
                self.canvas.pixels[dst..dst + r.w as usize].copy_from_slice(&img.pixels[src..src + r.w as usize]);
            }
        }
        self.canvas.surface.mark_dirty();
        self.present_only.extend_from_slice(&redraw);

        gi.heap.clone_from(&self.heap);
        gi.ground_y = g;
        gi.snowman = snowman_key;
        gi.pile_rect = pile_rect;
        gi.snowman_rect = snowman_rect;
        self.ground_shown = true;
        // snow on a window low enough to reach into the band stays in front of the copied ground
        self.canvas.surface.flush();
        for r in &redraw {
            for y in r.y..r.bottom() {
                self.overlay_ledges(y, r.x as usize, r.right() as usize);
            }
        }
        self.canvas.surface.mark_dirty();
    }
}

/// The leaves of a leaf pile (`DrawLeafPile` on Windows): single leaves of every shape and colour over the pile's
/// dark fill, in rows from its surface down, each a little off its place and turned its own way. Which leaf lies
/// where is fixed by its place (`chance`), so the pile does not flicker. `buf` is the pile's strip of the ground
/// image, `rows` high, with the ground line at row `gy`.
fn lay_leaves(buf: &mut [u32], w: i32, rows: i32, heap: &[f32], sprites: &[Vec<u32>], gy: f32, s: f32) {
    let (size, across, down) = (15.0 * s, 7.0 * s, 5.0 * s);
    let (mut x, mut column) = (-size / 2.0, 0i32);
    while x < w as f32 + size / 2.0 {
        let h = heap_at(heap, x.clamp(0.0, w as f32 - 1.0));
        if h > 1.5 {
            for row in 0..=(h / down) as i32 {
                let (a, b, d) = (chance(column, row), chance(row + 31, column), chance(column + 7, row + 3));
                let y = gy - h + row as f32 * down + (a - 0.5) * 4.0 * s - size * 0.12;
                if let Some(sprite) = sprites.get(leaf_sprite((a * 9973.0) as usize)) {
                    blend_leaf(buf, w, rows, sprite, x + (b - 0.5) * across, y, size * (0.75 + 0.55 * b), d * std::f32::consts::TAU, 255);
                }
            }
        }
        x += across;
        column += 1;
    }
}

/// The pile: a white bank with a faint blue outline along its top, as on Windows. In the autumn theme it is a
/// pile of leaves: here its dark fill, without an outline; the leaves are laid over it afterwards (`lay_leaves`).
fn draw_pile(cr: &Context, heap: &[f32], g: f64, w: f64, s: f64, leaf_fill: Option<Argb>) {
    let top = |cr: &Context| {
        for (i, h) in heap.iter().enumerate() {
            cr.line_to((i * HEAP_STEP) as f64, g - *h as f64);
        }
    };
    cr.new_path();
    top(cr);
    cr.line_to(w, g + 1.0);
    cr.line_to(0.0, g + 1.0);
    cr.close_path();
    if let Some(col) = leaf_fill {
        set(cr, col);
        let _ = cr.fill();
        return;
    }
    cr.set_source_rgba(248.0 / 255.0, 252.0 / 255.0, 1.0, 245.0 / 255.0);
    let _ = cr.fill();
    cr.new_path();
    top(cr);
    cr.set_source_rgba(170.0 / 255.0, 200.0 / 255.0, 230.0 / 255.0, 110.0 / 255.0);
    cr.set_line_width(1.5 * s);
    cr.set_line_join(cairo::LineJoin::Round);
    let _ = cr.stroke();
}

fn clip_to(r: Rect, band: Rect) -> Rect {
    let x0 = r.x.max(band.x);
    let y0 = r.y.max(band.y);
    let x1 = r.right().min(band.right());
    let y1 = r.bottom().min(band.bottom());
    Rect::new(x0, y0, (x1 - x0).max(0), (y1 - y0).max(0))
}
