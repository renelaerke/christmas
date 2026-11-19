//! Snow piles on other apps' window edges that cross this screen (`window_snow.rs`), with the drape hanging down
//! over the edge. Only stretches where snow has actually landed are drawn (no thin line on bare edges). Ported from
//! `DrawLedges` and `DrawLedgeRun` in `src/Layer.cs`.
//!
//! The snow sits on those windows, so the light string and everything that moves is drawn over it (as on Windows):
//! where a pile reaches into the lights strip, that part is cleared first and the strip blended over the snow.
//!
//! Windows draws every pile every frame. Here each window's stretches are cached as they look on screen (lights
//! blended in), and clearing restores them (`Layer::clear_rects`), like the ground and the lights. A window's snow is
//! redrawn only when it changed by half a pixel (at most 4 times a second), when the window moved or is covered
//! differently, when the lights over it twinkled, or when it is gone. A cached stretch overlapping one that is
//! redrawn is redrawn with it, so clearing one never erases the other.

use cairo::{Context, LineCap};

use super::draw::*;
use super::{Layer, SceneState};
use crate::window_snow::{FRect, Ledge};
use crate::x11::Rect;

/// One stretch of snow: (x, pile height, drape) per column, on an edge at `base_y` (screen coordinates).
struct Run {
    pts: Vec<(f32, f32, f32)>,
    base_y: f32,
    rect: Rect,
}

/// A window's snow as it is on this screen: what it was drawn from, and the pixels of each stretch's box.
pub(super) struct CachedLedge {
    id: u32,
    cols: Vec<f32>,
    hang: Vec<f32>,
    settled: FRect,
    visible: Vec<(f32, f32)>,
    runs: Vec<(Rect, Vec<u32>)>,
    timer: f32,
}

fn overlaps(a: &Rect, b: &Rect) -> bool {
    a.x < b.right() && b.x < a.right() && a.y < b.bottom() && b.y < a.bottom()
}

impl Layer {
    /// True when this screen shows the ledge's snow now.
    fn shows(&self, l: &Ledge) -> bool {
        // a window dragged around (same size) takes its snow along, so the pile is hidden until it settles; a
        // window that shrinks (minimize) or is resized leaves the snow where it was until it is gone
        let dragged = l.moving && l.rect.w == l.settled.w && l.rect.h == l.settled.h;
        let (ox, oy, w, h) = (self.rect.x as f32, self.rect.y as f32, self.w as f32, self.h as f32);
        let s = l.settled;
        l.has_snow && !dragged && !(s.right() <= ox || s.x >= ox + w || s.y <= oy || s.y > oy + h)
    }

    /// The stretches of snow on one window's edge, in screen coordinates.
    fn runs_for(&self, l: &Ledge, u: f32) -> Vec<Run> {
        let (ox, oy, w) = (self.rect.x as f32, self.rect.y as f32, self.w as f32);
        let mut runs = Vec::new();
        let mut cur: Vec<(f32, f32, f32)> = Vec::new();
        let flush = |cur: &mut Vec<(f32, f32, f32)>, base_y: f32, runs: &mut Vec<Run>| {
            if cur.len() >= 2 {
                let max_h = cur.iter().map(|p| p.1).fold(0.0, f32::max);
                let max_d = cur.iter().map(|p| p.2).fold(0.0, f32::max);
                let (x0, x1) = (cur[0].0, cur[cur.len() - 1].0);
                // as `mark()` with the run's box
                let (bx, by, bw, bh) = (x0 - 2.0, base_y - max_h - 3.0, x1 - x0 + 4.0, max_h + max_d + 6.0);
                let rect =
                    Rect::new(bx.floor() as i32 - 2, by.floor() as i32 - 2, bw.ceil() as i32 + 5, bh.ceil() as i32 + 5);
                runs.push(Run { pts: std::mem::take(cur), base_y, rect });
            }
            cur.clear();
        };
        let (base_y, step) = (l.settled.y - oy, l.step());
        for &(a, b) in &l.visible {
            let (x0, x1) = (a.max(ox), b.min(ox + w));
            if x1 - x0 < 4.0 {
                continue;
            }
            let mut x = x0;
            while x <= x1 {
                let (hh, d) = (l.height_at(x), l.hang_at(x));
                if hh > 0.6 * u || d > 0.6 * u {
                    // start and end each stretch on the edge itself, so the pile tapers off
                    if cur.is_empty() {
                        cur.push(((x0.max(x - step)) - ox, 0.0, 0.0));
                    }
                    cur.push((x - ox, hh, d));
                } else if !cur.is_empty() {
                    cur.push((x - ox, 0.0, 0.0));
                    flush(&mut cur, base_y, &mut runs);
                }
                x += step;
            }
            if !cur.is_empty() {
                cur.push((x1.min(x) - ox, 0.0, 0.0));
                flush(&mut cur, base_y, &mut runs);
            }
        }
        runs
    }

    /// Copies the cached snow on windows over row `y`, pixels `x0..x1` (after the row's background is restored).
    pub(super) fn overlay_ledges(&mut self, y: i32, x0: usize, x1: usize) {
        let w = self.w as usize;
        for c in &self.ledge_cache {
            for (r, px) in &c.runs {
                if y < r.y || y >= r.bottom() {
                    continue;
                }
                let (a, b) = ((r.x as usize).max(x0), (r.right() as usize).min(x1));
                if a >= b {
                    continue;
                }
                let src = (y - r.y) as usize * r.w as usize + (a - r.x as usize);
                let dst = y as usize * w + a;
                self.canvas.pixels[dst..dst + (b - a)].copy_from_slice(&px[src..src + (b - a)]);
            }
        }
    }

    /// Forgets the cached snow on windows (the screen was cleared, e.g. for a fullscreen pause).
    pub(super) fn forget_ledges(&mut self) {
        self.ledge_cache.clear();
    }

    pub(super) fn draw_ledges(&mut self, dt: f32, st: &SceneState) {
        let u = st.ledge_u;
        let strip = self.lights_strip_height();
        let lights_changed = std::mem::take(&mut self.lights_redrawn);
        let wanted: Vec<&Ledge> =
            if st.window_snow { st.ledges.iter().filter(|l| self.shows(l)).collect() } else { Vec::new() };

        // what to redraw: new windows, changed or moved ones, ones under lights that twinkled; and gone ones go
        let mut redraw: Vec<u32> = Vec::new();
        let mut gone: Vec<u32> = Vec::new();
        for c in &mut self.ledge_cache {
            c.timer -= dt;
            match wanted.iter().find(|l| l.id == c.id) {
                None => gone.push(c.id),
                Some(l) => {
                    let moved = c.settled != l.settled || c.visible != l.visible;
                    let grown = c.cols.len() != l.cols.len()
                        || c.cols
                            .iter()
                            .zip(&l.cols)
                            .chain(c.hang.iter().zip(&l.hang))
                            .any(|(a, b)| (a - b).abs() >= 0.5);
                    let under_lights = lights_changed && c.runs.iter().any(|(r, _)| r.y < strip);
                    if moved || under_lights || (grown && c.timer <= 0.0) {
                        redraw.push(c.id);
                    }
                }
            }
        }
        for l in &wanted {
            if !self.ledge_cache.iter().any(|c| c.id == l.id) {
                redraw.push(l.id);
            }
        }
        if redraw.is_empty() && gone.is_empty() {
            return;
        }
        // a cached stretch overlapping one that is cleared now must be drawn again too
        loop {
            let cleared: Vec<Rect> = self
                .ledge_cache
                .iter()
                .filter(|c| redraw.contains(&c.id) || gone.contains(&c.id))
                .flat_map(|c| c.runs.iter().map(|(r, _)| *r))
                .collect();
            let more: Vec<u32> = self
                .ledge_cache
                .iter()
                .filter(|c| !redraw.contains(&c.id) && !gone.contains(&c.id))
                .filter(|c| c.runs.iter().any(|(r, _)| cleared.iter().any(|o| overlaps(r, o))))
                .map(|c| c.id)
                .collect();
            if more.is_empty() {
                break;
            }
            redraw.extend(more);
        }

        // take the old stretches out and put the background back where they were
        let mut old: Vec<Rect> = Vec::new();
        let mut timers: Vec<(u32, f32)> = Vec::new();
        self.ledge_cache.retain(|c| {
            let keep = !redraw.contains(&c.id) && !gone.contains(&c.id);
            if !keep {
                old.extend(c.runs.iter().map(|(r, _)| *r));
                timers.push((c.id, c.timer));
            }
            keep
        });
        self.canvas.surface.flush();
        for r in &old {
            for y in r.y..r.bottom() {
                self.restore_background(y, r.x as usize, r.right() as usize);
            }
        }

        // draw the redrawn ones: under the lights strip clear first, so the strip can be blended over the snow
        let mut fresh: Vec<(&Ledge, Vec<Run>)> = Vec::new();
        for l in wanted.iter().filter(|l| redraw.contains(&l.id)) {
            let runs: Vec<Run> = self
                .runs_for(l, u)
                .into_iter()
                .map(|mut r| {
                    r.rect = r.rect.clip(self.w, self.h);
                    r
                })
                .filter(|r| !r.rect.is_empty())
                .collect();
            fresh.push((l, runs));
        }
        let under: Vec<Rect> = fresh
            .iter()
            .flat_map(|(_, runs)| runs.iter().map(|r| r.rect.clip(self.w, strip)))
            .filter(|r| !r.is_empty())
            .collect();
        for r in &under {
            for y in r.y..r.bottom() {
                let start = y as usize * self.w as usize + r.x as usize;
                self.canvas.pixels[start..start + r.w as usize].fill(0);
            }
        }
        self.canvas.surface.mark_dirty();
        for (_, runs) in &fresh {
            for run in runs {
                draw_run(&self.canvas.cr, run, u as f64);
            }
        }
        self.canvas.surface.flush();
        for r in &under {
            self.blend_lights_over(*r);
        }

        // keep what is on screen now as each window's cached snow, and send the old and new places
        let w = self.w as usize;
        for (l, runs) in fresh {
            let cached: Vec<(Rect, Vec<u32>)> = runs
                .iter()
                .map(|run| {
                    let r = run.rect;
                    let mut px = Vec::with_capacity((r.w * r.h) as usize);
                    for y in r.y..r.bottom() {
                        let s = y as usize * w + r.x as usize;
                        px.extend_from_slice(&self.canvas.pixels[s..s + r.w as usize]);
                    }
                    (r, px)
                })
                .collect();
            self.present_only.extend(cached.iter().map(|(r, _)| *r));
            // a window that was only redrawn for its neighbour keeps its rate limit
            let timer = timers.iter().find(|(id, _)| *id == l.id).map_or(0.0, |t| t.1);
            self.ledge_cache.push(CachedLedge {
                id: l.id,
                cols: l.cols.clone(),
                hang: l.hang.clone(),
                settled: l.settled,
                visible: l.visible.clone(),
                runs: cached,
                timer: if timer > 0.0 { timer } else { 0.25 },
            });
        }
        self.canvas.surface.mark_dirty();
        self.present_only.extend(old);
    }
}

/// One stretch: the pile's top from left to right, then back along the drape hanging below the edge.
fn draw_run(cr: &Context, run: &Run, u: f64) {
    let b = run.base_y as f64;
    let top: Vec<(f64, f64)> = run.pts.iter().map(|p| (p.0 as f64, b - p.1 as f64)).collect();
    let low: Vec<(f64, f64)> = run.pts.iter().rev().map(|p| (p.0 as f64, b + 0.5 + p.2 as f64)).collect();
    let max_d = run.pts.iter().map(|p| p.2).fold(0.0, f32::max) as f64;
    cr.new_path();
    curve_path(cr, &top);
    curve_path_joined(cr, &low);
    cr.close_path();
    set(cr, (245, 248, 252, 255));
    let _ = cr.fill();
    let line = (110, 170, 200, 230);
    cr.new_path();
    curve_path(cr, &top);
    stroke(cr, line, 1.2 * u, LineCap::Butt);
    // a faint outline under the drape where it hangs down, for depth
    if max_d > u {
        cr.new_path();
        curve_path(cr, &low);
        stroke(cr, line, 1.2 * u, LineCap::Butt);
    }
}
