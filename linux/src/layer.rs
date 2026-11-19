//! One screen's scene: a premultiplied ARGB32 pixel buffer the size of the monitor, and what is drawn on it.
//! Ported from `src/Layer.cs` (and `macos/Sources/JuleHygge/Overlay.swift`); origin top left, as in both.
//!
//! Falling snow (dots and crystals), the snow pile on the ground (at the top of a bottom panel, or the screen
//! bottom) with storm drifts, and the fullscreen pause live here. The figures are in submodules, which as child
//! modules share this file's private fields (like the one big `Layer` class on Windows): the Christmas lights
//! (`lights`), Santa and the sparks (`santa`), the snowman (`snowman`), the snow plow (`plow`) and the elves
//! (`elves`), and snow on other windows' top edges (`ledges`); `draw` has the Cairo helpers they use.
//!
//! The Windows optimisations are kept, because the overlay covers whole 4K screens:
//! - only what was drawn in the previous frame is cleared (`mark()` and `clear_rects()`), and only that plus
//!   what is drawn now is sent to the X server;
//! - snowflakes are blended straight into the pixel buffer (`blend_dot()`), not drawn with Cairo;
//! - the number of flakes is scaled by the logical screen size.
//!
//! Everything drawn MUST be registered with `mark()`, or it stays on screen as a trail.

use std::f32::consts::{FRAC_PI_3, TAU};

use cairo::{Context, Format, ImageSurface};

pub(crate) mod draw;
mod elves;
mod ground;
mod ledges;
mod lights;
mod plow;
mod santa;
mod snowman;

pub use elves::Elf;
pub use snowman::MAX_STAGE as SNOWMAN_MAX_STAGE;

use crate::figures::{PlowRun, Santa, Spark};
use crate::rng::Rng;
use crate::window_snow::{Clump, Ledge};
use crate::x11::{Rect, Res};

/// What the controller shares with every screen for one frame.
#[derive(Clone, Copy)]
pub struct SceneState<'a> {
    /// Seconds since start. A double, because a float loses precision after a few days of uptime and animations
    /// would start to stutter (as on Windows).
    pub time: f64,
    /// Horizontal wind in points per second (positive to the right).
    pub wind: f32,
    /// 0 light ... 2 storm, gliding while the weather changes.
    pub snow_amount: f32,
    /// 0 light, 1 normal, 2 storm.
    pub snow_level: i32,
    pub snow_on: bool,
    /// Drifts slowly between ~0.6 and ~1.4.
    pub snow_intensity: f32,
    /// Snow settles in a pile on the ground (setting `SnowGround`).
    pub snow_ground: bool,
    /// The active window, in global coordinates, if it is fullscreen. A screen it covers either pauses (setting
    /// `PauseFullscreen`) or moves its ground to the screen bottom, because the app hides the panel.
    pub fullscreen: Option<Rect>,
    pub pause_fullscreen: bool,
    /// Power-save mode: the lights twinkle with fewer updates.
    pub power_save: bool,
    pub lights: bool,
    pub elves: bool,
    /// Chosen number of elves per screen (setting `NisseCount`).
    pub elf_count: i32,
    /// The snowman's stage today (1..=12), or 0 when it is switched off. Only the primary screen has one.
    pub snowman_stage: i32,
    pub santa: Option<&'a Santa>,
    pub sparks: &'a [Spark],
    pub plow: Option<&'a PlowRun>,
    /// Snow on windows (setting `WindowSnow`): the windows' edges and the clumps falling off, in global
    /// coordinates, and the scale their sizes are in (the desktop scale).
    pub window_snow: bool,
    pub ledges: &'a [Ledge],
    pub clumps: &'a [Clump],
    pub ledge_u: f32,
}

/// Width in pixels of one column of the snow pile, as on Windows.
const HEAP_STEP: usize = 4;

struct Flake {
    x: f32,
    y: f32,
    r: f32,
    vy: f32,
    phase: f32,
    sway: f32,
    sway_spd: f32,
    rot: f32,
    rot_spd: f32,
    a: i32,
    crystal: bool,
    /// About half the flakes can land on a window's top edge (the rest fall past to the ground).
    catches: bool,
}

/// Memory that holds a screen's pixels: a plain `Vec<u32>`, or a shared memory segment the X server reads
/// directly (`x11::ShmBuffer`).
pub trait PixelStore: std::ops::DerefMut<Target = [u32]> {}
impl<T: std::ops::DerefMut<Target = [u32]>> PixelStore for T {}

/// The pixel buffer with a Cairo surface drawing into the same memory.
/// Field order matters: the context and surface are dropped before the pixels they point into.
struct Canvas {
    cr: Context,
    surface: ImageSurface,
    pixels: Box<dyn PixelStore>,
}

impl Canvas {
    fn new(w: i32, h: i32, mut pixels: Box<dyn PixelStore>) -> Res<Canvas> {
        if pixels.len() != w as usize * h as usize {
            return Err("pixel buffer has the wrong size".into());
        }
        pixels.fill(0);
        // SAFETY: the buffer is w*h*4 bytes with a stride of w*4 (valid for ARGB32), it is never reallocated
        // (a boxed store keeps its memory in place), and it outlives the surface and context (field order above).
        let surface = unsafe {
            ImageSurface::create_for_data_unsafe(pixels.as_mut_ptr() as *mut u8, Format::ARgb32, w, h, w * 4)?
        };
        let cr = Context::new(&surface)?;
        Ok(Canvas { cr, surface, pixels })
    }
}

/// What the controller should send to the window after a frame.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Present {
    Nothing,
    /// The rectangles in `Layer::present_rects()`.
    Rects,
    Full,
}

pub struct Layer {
    /// The monitor in global coordinates.
    pub rect: Rect,
    /// Only the primary screen gets the snowman.
    pub primary: bool,
    /// This screen's place in the controller's list (the plow run names its screens by it).
    pub index: usize,
    /// There is a screen directly to the left / right (elves walk over to it).
    pub neighbor_left: bool,
    pub neighbor_right: bool,
    w: i32,
    h: i32,
    /// Scale of all figures: screen height / 1080 (at least 0.6), as on Windows.
    s: f32,
    dpi_scale: f32,
    ground_y: f32,
    /// Top of a panel at the bottom of this screen (local y), or the screen height when there is none.
    panel_y: f32,
    /// Height of the snow pile per HEAP_STEP pixels.
    heap: Vec<f32>,
    heap_moved: Vec<f32>,
    /// A fullscreen app covers this screen and the scene is paused (the controller hides the window).
    paused: bool,
    canvas: Canvas,
    rng: Rng,
    flakes: Vec<Flake>,
    dirty: Vec<Rect>,
    prev_dirty: Vec<Rect>,
    /// Changed this frame but not to be cleared next frame (the lights strip after it was re-rendered).
    present_only: Vec<Rect>,
    present: Vec<Rect>,
    full_present: bool,

    ground: Option<ground::GroundImage>,
    /// The cached ground is in the buffer, so clearing restores it.
    ground_shown: bool,
    lights: Option<lights::LightsImage>,
    /// The lights strip changed on screen this frame (twinkled, appeared or went): snow on windows under it is
    /// drawn again, since its cache has the strip blended in.
    lights_redrawn: bool,
    /// Snow on windows as it is on this screen, restored by clearing (`ledges.rs`).
    ledge_cache: Vec<ledges::CachedLedge>,
    /// The lights strip is in the buffer, so clearing restores it instead of leaving it empty.
    lights_shown: bool,
    /// Where the snowman stands, in global coordinates (for the celebration sparks in phase 4).
    snowman_pos: Option<(f32, f32)>,
    plow_bits: Vec<plow::PlowBit>,
    plow_smoke_timer: f32,
    plow_chunk_acc: f32,
    plow_pushed: f32,
    elves: Vec<Elf>,
    outgoing: Vec<Elf>,
    next_elf_id: u64,
    elf_offset: i32,
    elf_change_timer: f32,
    /// Flakes that landed on a window's edge this frame (ledge index, global x, radius without the screen
    /// scale), and clumps that reached this screen's pile; the controller applies them.
    ledge_hits: Vec<(usize, f32, f32)>,
    clumps_landed: Vec<usize>,
}

impl Layer {
    #[cfg(test)]
    pub fn new(rect: Rect, primary: bool, dpi_scale: f32, seed: u64) -> Res<Layer> {
        Self::with_pixels(rect, primary, dpi_scale, seed, Box::new(vec![0u32; rect.w as usize * rect.h as usize]))
    }

    /// A layer drawing into `pixels` (rect.w * rect.h values).
    pub fn with_pixels(
        rect: Rect,
        primary: bool,
        dpi_scale: f32,
        seed: u64,
        pixels: Box<dyn PixelStore>,
    ) -> Res<Layer> {
        let (w, h) = (rect.w, rect.h);
        let s = (h as f32 / 1080.0).max(0.6);
        let mut heap = vec![0.0; w as usize / HEAP_STEP + 2];
        // JULE_DEEPSNOW=1 starts with a full snow drift (for testing the snow plow).
        if std::env::var("JULE_DEEPSNOW").is_ok_and(|v| v == "1") {
            heap.fill(18.0 * s);
        }
        Ok(Layer {
            rect,
            primary,
            index: 0,
            neighbor_left: false,
            neighbor_right: false,
            w,
            h,
            s,
            dpi_scale: dpi_scale.max(1.0),
            ground_y: h as f32,
            panel_y: h as f32,
            heap_moved: vec![0.0; heap.len()],
            heap,
            paused: false,
            canvas: Canvas::new(w, h, pixels)?,
            rng: Rng::new(seed),
            flakes: Vec::new(),
            dirty: Vec::new(),
            prev_dirty: Vec::new(),
            present_only: Vec::new(),
            present: Vec::new(),
            full_present: true,
            ground: None,
            ground_shown: false,
            lights: None,
            lights_redrawn: false,
            ledge_cache: Vec::new(),
            lights_shown: false,
            snowman_pos: None,
            plow_bits: Vec::new(),
            plow_smoke_timer: 0.0,
            plow_chunk_acc: 0.0,
            plow_pushed: 0.0,
            elves: Vec::new(),
            outgoing: Vec::new(),
            // seeds differ per screen, so elf ids from different screens do not collide
            next_elf_id: seed << 20,
            elf_offset: 0,
            elf_change_timer: 90.0,
            ledge_hits: Vec::new(),
            clumps_landed: Vec::new(),
        })
    }

    pub fn width(&self) -> i32 {
        self.w
    }
    pub fn height(&self) -> i32 {
        self.h
    }
    pub fn pixels(&self) -> &[u32] {
        &self.canvas.pixels
    }
    pub fn present_rects(&self) -> &[Rect] {
        &self.present
    }
    /// The window was exposed (e.g. just mapped): send everything next frame.
    pub fn invalidate(&mut self) {
        self.full_present = true;
    }
    pub fn flake_count(&self) -> usize {
        self.flakes.len()
    }
    pub fn paused(&self) -> bool {
        self.paused
    }
    /// The figure scale: screen height / 1080.
    pub fn scale(&self) -> f32 {
        self.s
    }
    /// Flakes that landed on window edges since the last call: (ledge index, global x, radius in points).
    pub fn take_ledge_hits(&mut self) -> Vec<(usize, f32, f32)> {
        std::mem::take(&mut self.ledge_hits)
    }
    /// Clumps (indexes) that landed in this screen's pile since the last call.
    pub fn take_clumps_landed(&mut self) -> Vec<usize> {
        std::mem::take(&mut self.clumps_landed)
    }
    /// Average height of the pile (the snow plow comes when it gets high).
    pub fn heap_average(&self) -> f32 {
        self.heap.iter().sum::<f32>() / self.heap.len() as f32
    }
    pub fn snowman_pos(&self) -> Option<(f32, f32)> {
        self.snowman_pos
    }
    /// The top of a bottom panel in local y (None: no panel, the snow lies on the screen bottom).
    pub fn set_panel_top(&mut self, y: Option<i32>) {
        let y = y.map_or(self.h as f32, |y| (y as f32).clamp(self.h as f32 * 0.5, self.h as f32));
        if y != self.panel_y {
            crate::log::debug(&format!("screen at {},{}: ground at y={y}", self.rect.x, self.rect.y));
            self.panel_y = y;
        }
    }

    fn mark(&mut self, x: f32, y: f32, w: f32, h: f32) {
        self.dirty.push(Rect::new(
            x.floor() as i32 - 2,
            y.floor() as i32 - 2,
            w.ceil() as i32 + 5,
            h.ceil() as i32 + 5,
        ));
    }

    // ------------------------------------------------------------------ one frame
    pub fn frame(&mut self, dt: f32, st: &SceneState) -> Present {
        let fullscreen = st.fullscreen.is_some_and(|fs| fs.contains(&self.rect));
        // With "pause on fullscreen" off, a fullscreen app hides the panel, so the snow piles up at the very
        // bottom of the screen instead.
        self.ground_y = if fullscreen { self.h as f32 } else { self.panel_y };
        if fullscreen && st.pause_fullscreen {
            if !self.paused {
                // Leave an empty buffer behind; the controller unmaps the window, so a fullscreen game is not
                // composited under a see-through window, and maps it again (with a full present) afterwards.
                self.canvas.surface.flush();
                self.canvas.pixels.fill(0);
                self.canvas.surface.mark_dirty();
                self.prev_dirty.clear();
                // the strip and the ground are copied in again when the screen resumes
                self.lights_shown = false;
                self.ground_shown = false;
                self.forget_ledges();
                self.paused = true;
            }
            return Present::Nothing;
        }
        if self.paused {
            self.paused = false;
            self.full_present = true;
        }

        self.update_snow(dt, st);
        self.update_plow(dt, st);
        self.update_elves(dt, st);

        // Clear what was drawn last frame (Cairo must finish before the buffer is touched directly).
        self.canvas.surface.flush();
        let cleared = std::mem::take(&mut self.prev_dirty);
        self.clear_rects(&cleared);
        self.canvas.surface.mark_dirty();

        // back to front, as on Windows
        self.present_only.clear();
        self.draw_lights(dt, st);
        // snow on other windows sits on those windows: the light string (blended over it in `draw_ledges`) and
        // everything that moves is drawn over it, as on Windows
        self.draw_ledges(dt, st);
        self.draw_ground(dt, st);
        self.draw_santa_and_sparks(st);
        self.draw_elves();
        self.draw_plow(st);
        self.draw_snow(st);
        self.canvas.surface.flush();

        let result = self.plan_present(&cleared);
        // What was drawn now is cleared next frame; reuse the old list's memory.
        self.prev_dirty = std::mem::replace(&mut self.dirty, cleared);
        self.dirty.clear();
        result
    }

    /// Collects the rectangles that changed on screen: last frame's (now cleared) and this frame's.
    /// Unlike Windows, which merges them into three boxes for UpdateLayeredWindowIndirect, X11 gets small
    /// rectangles: a few thousand tiny requests cost far less than one full 4K upload. A flake's old and new
    /// rectangle mostly overlap, so neighbours are merged first (`merge_rects`), which halves the requests.
    fn plan_present(&mut self, cleared: &[Rect]) -> Present {
        if self.full_present {
            self.full_present = false;
            return Present::Full;
        }
        self.present.clear();
        let mut area = 0i64;
        for r in cleared.iter().chain(&self.dirty).chain(&self.present_only) {
            let c = r.clip(self.w, self.h);
            if c.is_empty() {
                continue;
            }
            area += c.area();
            self.present.push(c);
        }
        if self.present.is_empty() {
            return Present::Nothing;
        }
        merge_rects(&mut self.present);
        // mostly everything changed: one full update is cheaper
        if area > self.w as i64 * self.h as i64 / 2 {
            return Present::Full;
        }
        Present::Rects
    }

    /// Empties the rectangles again, except where cached things are shown (the lights strip, the ground, snow on
    /// windows): there their images are restored.
    fn clear_rects(&mut self, rects: &[Rect]) {
        for r in rects {
            let c = r.clip(self.w, self.h);
            if c.is_empty() {
                continue;
            }
            let (x0, x1) = (c.x as usize, c.right() as usize);
            for y in c.y..c.bottom() {
                self.restore_background(y, x0, x1);
                self.overlay_ledges(y, x0, x1);
            }
        }
    }

    /// Row `y`, pixels `x0..x1`, as the lights strip or the ground leave it, or empty.
    fn restore_background(&mut self, y: i32, x0: usize, x1: usize) {
        if !self.restore_lights(y, x0, x1) && !self.restore_ground(y, x0, x1) {
            let start = y as usize * self.w as usize;
            self.canvas.pixels[start + x0..start + x1].fill(0);
        }
    }

    // ------------------------------------------------------------------ snow
    fn update_snow(&mut self, dt: f32, st: &SceneState) {
        const BASE: [f32; 3] = [110.0, 260.0, 650.0];
        // between two levels while the weather changes
        let amount = st.snow_amount.clamp(0.0, 2.0);
        let lower = (amount as usize).min(1);
        let wanted = BASE[lower] + (BASE[lower + 1] - BASE[lower]) * (amount - lower as f32);
        let logical_area = self.w as f32 * self.h as f32 / (self.dpi_scale * self.dpi_scale);
        // Snow covers the whole screen also in power-save mode; power-save only lowers the frame rate.
        let target = if st.snow_on {
            (wanted * (logical_area / (1920.0 * 1080.0)).min(2.0) * st.snow_intensity) as usize
        } else {
            0
        };
        // new flakes come in from the top; extra flakes only disappear when they land
        let add = if self.flakes.is_empty() { target } else { (target / 60).max(1) };
        for _ in 0..add {
            if self.flakes.len() >= target {
                break;
            }
            let anywhere = self.flakes.is_empty() || st.time < 1.0;
            let f = self.new_flake(anywhere, st);
            self.flakes.push(f);
        }

        let wind = st.wind * self.s;
        let (w, s, ground) = (self.w as f32, self.s, self.ground_y);
        let (ox, oy) = (self.rect.x as f32, self.rect.y as f32);
        let ledges = st.window_snow && !st.ledges.is_empty();
        let mut i = self.flakes.len();
        while i > 0 {
            i -= 1;
            let f = &mut self.flakes[i];
            let prev_y = f.y;
            f.y += f.vy * dt;
            let sway = (st.time * f.sway_spd as f64 + f.phase as f64).cos() as f32;
            f.x += (wind * (0.4 + f.r / (4.0 * s)) + sway * f.sway) * dt;
            f.rot += f.rot_spd * dt;
            if f.x < -60.0 {
                f.x += w + 120.0;
            } else if f.x > w + 60.0 {
                f.x -= w + 120.0;
            }
            // some flakes land on a window's top edge (or the snow already on it)
            if f.catches && ledges {
                let (gx, gy, py) = (f.x + ox, f.y + oy, prev_y + oy);
                let hit = st.ledges.iter().position(|l| {
                    let top = l.settled.y - l.height_at(gx);
                    !l.moving && py < top && gy >= top && l.is_visible(gx)
                });
                if let Some(li) = hit {
                    self.ledge_hits.push((li, gx, f.r / s));
                    if self.flakes.len() > target {
                        self.flakes.swap_remove(i);
                    } else {
                        let nf = self.new_flake(false, st);
                        self.flakes[i] = nf;
                    }
                    continue;
                }
            }
            if f.y >= ground - heap_at(&self.heap, f.x) {
                let (x, r) = (f.x, f.r);
                if st.snow_ground {
                    self.deposit(x, r, st);
                }
                if self.flakes.len() > target {
                    self.flakes.swap_remove(i);
                } else {
                    let nf = self.new_flake(false, st);
                    self.flakes[i] = nf;
                }
            }
        }
        self.update_heap(dt, st);
    }

    /// Storm drifts, sliding, melting and the height limit of the pile (the second half of `UpdateSnow` in
    /// `src/Layer.cs`).
    fn update_heap(&mut self, dt: f32, st: &SceneState) {
        let s = self.s;
        let n = self.heap.len();
        // Snowstorm: the wind carries snow along the pile, so it drifts up against the downwind screen edge, and
        // flakes settle in long soft waves (the dune factor in `deposit`). Drifts may grow taller and sink back
        // slowly afterwards.
        let storm = st.snow_level == 2 && st.snow_on;
        let wind_norm = (st.wind / 140.0).clamp(-1.5, 1.5);
        if storm && wind_norm.abs() > 0.15 && n > 2 {
            let rate = 0.02 * wind_norm.abs() * dt;
            for (m, h) in self.heap_moved.iter_mut().zip(&self.heap) {
                *m = h * rate;
            }
            for i in 0..n {
                let Some(j) = i.checked_add_signed(if wind_norm > 0.0 { 1 } else { -1 }).filter(|&j| j < n) else {
                    continue;
                };
                self.heap[i] -= self.heap_moved[i];
                self.heap[j] += self.heap_moved[i];
            }
        }
        let max_h = if storm { 30.0 } else { 18.0 } * s;
        let slope = 1.2 * s;
        for i in 0..n - 1 {
            let d = self.heap[i] - self.heap[i + 1];
            if d > slope {
                let m = (d - slope) * 0.3;
                self.heap[i] -= m;
                self.heap[i + 1] += m;
            } else if d < -slope {
                let m = (-d - slope) * 0.3;
                self.heap[i] += m;
                self.heap[i + 1] -= m;
            }
        }
        // snow falling off a window that went away lands in the pile below
        let (ox, oy) = (self.rect.x as f32, self.rect.y as f32);
        for (ci, c) in st.clumps.iter().enumerate() {
            let (x, y) = (c.x - ox, c.y - oy);
            if !c.dead && x >= 0.0 && x < self.w as f32 && y >= 0.0 && y >= self.ground_y - heap_at(&self.heap, x) {
                if st.snow_ground {
                    self.deposit(x, c.r * s, st);
                }
                self.clumps_landed.push(ci);
            }
        }
        let melt = !st.snow_on || !st.snow_ground;
        let (ox, dpi) = (self.rect.x as f64, self.dpi_scale as f64);
        for (i, h) in self.heap.iter_mut().enumerate() {
            if melt {
                *h = (*h - 3.0 * s * dt).max(0.0);
            }
            // A full pile keeps soft bumps: the limit wavers along the screen (in global x, so screens line up),
            // and above it the snow sinks back slowly instead of being cut off.
            let gx = (i * HEAP_STEP) as f64 + ox;
            let lim =
                max_h * (0.78 + 0.22 * (0.6 * (gx / (37.0 * dpi)).sin() + 0.4 * (gx / (13.7 * dpi)).sin()) as f32);
            if *h > lim {
                *h = (*h - 2.0 * s * dt).max(lim);
            }
        }
    }

    /// A landed flake of radius `r` adds to the pile around `x`.
    fn deposit(&mut self, x: f32, r: f32, st: &SceneState) {
        let mut amount = 0.35 * r;
        if st.snow_level == 2 {
            // dunes: long waves in global x (so they line up across screens), slowly wandering with the wind
            let gx = x as f64 + self.rect.x as f64;
            let dir = if st.wind > 0.0 { 1.0 } else { -1.0 };
            let dune =
                0.5 + 0.5 * (gx / (240.0 * self.s as f64) * 2.0 * std::f64::consts::PI - st.time * 0.03 * dir).sin();
            amount *= 0.3 + 1.4 * dune as f32;
        }
        let idx = (x / HEAP_STEP as f32) as isize;
        for k in -1..=1isize {
            if let Some(h) = usize::try_from(idx + k).ok().and_then(|j| self.heap.get_mut(j)) {
                *h += if k == 0 { amount } else { amount * 0.5 };
            }
        }
    }

    fn new_flake(&mut self, anywhere: bool, st: &SceneState) -> Flake {
        let s = self.s;
        let depth = self.rng.f();
        let mut r = (1.0 + depth * depth * 3.5) * s;
        let vy = (25.0 + depth * 55.0 + self.rng.f() * 15.0) * s * if st.snow_level == 2 { 1.5 } else { 1.0 };
        let x = self.rng.range(-50, self.w + 50) as f32;
        let y = if anywhere { self.rng.f() * self.ground_y } else { -10.0 - self.rng.f() * 60.0 };
        let phase = self.rng.f() * TAU;
        let sway = (8.0 + self.rng.f() * 20.0) * s;
        let sway_spd = 0.5 + self.rng.f() * 1.2;
        let a = (110.0 + depth * 145.0) as i32;
        let crystal = depth > 0.8 && self.rng.f() < 0.5;
        if crystal {
            r *= 1.6;
        }
        let rot = self.rng.f() * TAU;
        let rot_spd = (self.rng.f() - 0.5) * 2.0;
        let catches = self.rng.f() < 0.5;
        Flake { x, y, r, vy, phase, sway, sway_spd, rot, rot_spd, a, crystal, catches }
    }

    /// A soft white dot blended straight into the premultiplied buffer (much faster than Cairo for thousands
    /// of tiny dots). Same arithmetic as `BlendDot` in `src/Layer.cs`.
    fn blend_dot(&mut self, cx: f32, cy: f32, r: f32, alpha: i32) {
        let x0 = ((cx - r - 1.0) as i32).max(0);
        let x1 = ((cx + r + 1.0) as i32).min(self.w - 1);
        let y0 = ((cy - r - 1.0) as i32).max(0);
        let y1 = ((cy + r + 1.0) as i32).min(self.h - 1);
        if x0 > x1 || y0 > y1 {
            return;
        }
        let w = self.w as usize;
        for y in y0..=y1 {
            let dy = y as f32 + 0.5 - cy;
            let row = &mut self.canvas.pixels[y as usize * w..(y as usize + 1) * w];
            for x in x0..=x1 {
                let dx = x as f32 + 0.5 - cx;
                let mut cov = r + 0.5 - (dx * dx + dy * dy).sqrt();
                if cov <= 0.0 {
                    continue;
                }
                if cov > 1.0 {
                    cov = 1.0;
                }
                let a = (alpha as f32 * cov) as u32;
                if a == 0 {
                    continue;
                }
                let d = row[x as usize];
                let inv = 255 - a;
                let da = a + ((d >> 24) & 0xFF) * inv / 255;
                let dr = a + ((d >> 16) & 0xFF) * inv / 255;
                let dg = a + ((d >> 8) & 0xFF) * inv / 255;
                let db = a + (d & 0xFF) * inv / 255;
                row[x as usize] = (da << 24) | (dr << 16) | (dg << 8) | db;
            }
        }
    }

    fn draw_snow(&mut self, st: &SceneState) {
        // Dots go straight into the buffer, so Cairo must finish the figures first.
        self.canvas.surface.flush();
        for i in 0..self.flakes.len() {
            let (x, y, r, a, crystal) = {
                let f = &self.flakes[i];
                (f.x, f.y, f.r, f.a, f.crystal)
            };
            if y < -r * 2.0 {
                continue;
            }
            self.mark(x - r, y - r, r * 2.0, r * 2.0);
            if !crystal {
                self.blend_dot(x, y, r, a);
            }
        }
        // clumps falling off a window that went away
        let (ox, oy) = (self.rect.x as f32, self.rect.y as f32);
        for c in st.clumps {
            let (x, y, r) = (c.x - ox, c.y - oy, c.r * self.s);
            if c.dead || x < -10.0 || x > self.w as f32 + 10.0 || y < -10.0 || y > self.h as f32 + 10.0 {
                continue;
            }
            self.mark(x - r, y - r, r * 2.0, r * 2.0);
            self.blend_dot(x, y, r, 242);
        }

        // Crystals: three crossing lines, drawn with Cairo.
        self.canvas.surface.mark_dirty();
        let cr = &self.canvas.cr;
        cr.set_line_width((0.9 * self.s).max(1.0) as f64);
        cr.set_line_cap(cairo::LineCap::Butt);
        for f in &self.flakes {
            if !f.crystal || f.y < -f.r * 2.0 || f.a < 60 {
                continue;
            }
            // 16 steps of alpha, as the 16 pens on Windows
            let step = ((f.a - 60) / 13).clamp(0, 15);
            cr.set_source_rgba(1.0, 1.0, 1.0, (60 + step * 13) as f64 / 255.0);
            for k in 0..3 {
                let a = f.rot + k as f32 * FRAC_PI_3;
                let (dx, dy) = (a.cos() * f.r, a.sin() * f.r);
                cr.move_to((f.x - dx) as f64, (f.y - dy) as f64);
                cr.line_to((f.x + dx) as f64, (f.y + dy) as f64);
            }
            let _ = cr.stroke();
        }
    }

    // ------------------------------------------------------------------ test aid
    /// Writes the overlay over a dark background as a PNG (`--snapshot`), like the macOS version.
    pub fn write_snapshot(&self, path: &std::path::Path) -> Res<()> {
        let out = ImageSurface::create(Format::ARgb32, self.w, self.h)?;
        {
            let cr = Context::new(&out)?;
            cr.set_source_rgb(40.0 / 255.0, 55.0 / 255.0, 80.0 / 255.0);
            cr.paint()?;
            cr.set_source_surface(&self.canvas.surface, 0.0, 0.0)?;
            cr.paint()?;
        }
        let mut file = std::fs::File::create(path)?;
        out.write_to_png(&mut file)?;
        Ok(())
    }
}

/// Merges rectangles that lie close together when their bounding box is hardly bigger than the two of them (a
/// flake's position last frame and now, or overlapping flakes), so the X server gets fewer, non-overlapping
/// copies. Sorted into bands of rows first, so neighbours meet; each rectangle is compared with a few before it.
fn merge_rects(rects: &mut Vec<Rect>) {
    const BAND: i32 = 64;
    const LOOK_BACK: usize = 6;
    rects.sort_unstable_by_key(|r| (r.y / BAND, r.x));
    let mut out: Vec<Rect> = Vec::with_capacity(rects.len());
    'next: for r in rects.drain(..) {
        let start = out.len().saturating_sub(LOOK_BACK);
        for o in out[start..].iter_mut() {
            let u = Rect::union(o, &r);
            // worth it when the union wastes at most a quarter of what the two cover
            if u.area() * 4 <= (o.area() + r.area()) * 5 {
                *o = u;
                continue 'next;
            }
        }
        out.push(r);
    }
    *rects = out;
}

/// Height of the pile at `x`, between two columns.
fn heap_at(heap: &[f32], x: f32) -> f32 {
    let fx = x / HEAP_STEP as f32;
    let i = fx.floor();
    if i < 0.0 {
        return heap[0];
    }
    let i = i as usize;
    if i >= heap.len() - 1 {
        return heap[heap.len() - 1];
    }
    let t = fx - i as f32;
    heap[i] * (1.0 - t) + heap[i + 1] * t
}

#[cfg(test)]
mod tests {
    use super::*;

    fn state() -> SceneState<'static> {
        SceneState {
            time: 5.0,
            wind: 20.0,
            snow_amount: 1.0,
            snow_level: 1,
            snow_on: true,
            snow_intensity: 1.0,
            snow_ground: true,
            fullscreen: None,
            pause_fullscreen: true,
            power_save: false,
            // the figures are off here; tests that need them switch them on
            lights: false,
            elves: false,
            elf_count: 3,
            snowman_stage: 0,
            santa: None,
            sparks: &[],
            plow: None,
            window_snow: true,
            ledges: &[],
            clumps: &[],
            ledge_u: 1.0,
        }
    }

    #[test]
    fn snow_fills_and_trails_are_cleared() {
        let mut l = Layer::new(Rect::new(0, 0, 640, 360), true, 1.0, 42).unwrap();
        let st = state();
        assert_eq!(l.frame(0.05, &st), Present::Full);
        assert!(l.flake_count() > 0);
        for _ in 0..200 {
            l.frame(0.05, &st);
        }
        // Every lit pixel must lie inside something drawn in the last frame, or be what clearing restores there
        // (the cached ground): nothing is left behind.
        let background = l.background();
        let w = l.width();
        for (i, (p, b)) in l.pixels().iter().zip(&background).enumerate() {
            if *p == 0 || p == b {
                continue;
            }
            let (x, y) = ((i as i32) % w, (i as i32) / w);
            assert!(
                l.prev_dirty.iter().any(|r| x >= r.x && x < r.right() && y >= r.y && y < r.bottom()),
                "trail at {x},{y}"
            );
        }
    }

    #[test]
    fn no_snow_means_nothing_drawn() {
        let mut l = Layer::new(Rect::new(0, 0, 320, 200), true, 1.0, 1).unwrap();
        let st = SceneState { snow_on: false, ..state() };
        l.frame(0.05, &st);
        assert_eq!(l.frame(0.05, &st), Present::Nothing);
        assert!(l.pixels().iter().all(|p| *p == 0));
    }

    #[test]
    fn snow_piles_up_on_the_panel() {
        let mut l = Layer::new(Rect::new(0, 0, 640, 360), true, 1.0, 7).unwrap();
        l.set_panel_top(Some(330));
        let st = state();
        // five minutes: a small screen has few flakes, so the pile grows slowly (as on Windows)
        for _ in 0..6000 {
            l.frame(0.05, &st);
        }
        assert!(l.heap_average() > 2.0, "pile {}", l.heap_average());
        // the pile stays within its limit (18 points at this size) and sits on the panel, not below it
        let s = l.s;
        assert!(l.heap.iter().all(|h| *h <= 18.0 * s + 1.0));
        let w = l.width() as usize;
        assert!(l.pixels()[332 * w..].iter().all(|p| *p == 0), "something drawn over the panel");
        assert!(l.pixels()[325 * w..330 * w].iter().any(|p| *p >> 24 > 200), "no snow on the ground");
    }

    #[test]
    fn no_ground_snow_means_no_pile_and_it_melts() {
        let mut l = Layer::new(Rect::new(0, 0, 640, 360), true, 1.0, 3).unwrap();
        let st = state();
        for _ in 0..6000 {
            l.frame(0.05, &st);
        }
        assert!(l.heap_average() > 2.0);
        let off = SceneState { snow_ground: false, ..st };
        for _ in 0..400 {
            l.frame(0.05, &off);
        }
        assert_eq!(l.heap_average(), 0.0);
    }

    #[test]
    fn storm_drifts_downwind() {
        // a half-height pile and storm wind, but no new flakes, so only the drift moves snow
        let mut l = Layer::new(Rect::new(0, 0, 640, 360), true, 1.0, 5).unwrap();
        let h0 = 6.0 * l.s;
        l.heap.fill(h0);
        let storm = SceneState { wind: 150.0, snow_level: 2, snow_amount: 2.0, snow_intensity: 0.0, ..state() };
        for _ in 0..2400 {
            l.frame(0.05, &storm);
        }
        let n = l.heap.len();
        let (left, right) = (l.heap[..n / 4].iter().sum::<f32>(), l.heap[n - n / 4..].iter().sum::<f32>());
        // slow on purpose, as on Windows: about 2% of a column's snow moves one column on per second
        assert!(right > left * 1.05, "left {left} right {right}");
        assert!(l.heap[n - 1] > h0, "no drift against the downwind edge");
    }

    #[test]
    fn fullscreen_pauses_and_resumes() {
        let rect = Rect::new(100, 0, 320, 200);
        let mut l = Layer::new(rect, true, 1.0, 9).unwrap();
        let st = state();
        for _ in 0..20 {
            l.frame(0.05, &st);
        }
        let fs = SceneState { fullscreen: Some(Rect::new(0, 0, 1000, 1000)), ..st };
        assert_eq!(l.frame(0.05, &fs), Present::Nothing);
        assert!(l.paused());
        assert!(l.pixels().iter().all(|p| *p == 0));
        assert_eq!(l.frame(0.05, &st), Present::Full);
        assert!(!l.paused());
        // a fullscreen window on another screen changes nothing here
        let other = SceneState { fullscreen: Some(Rect::new(1000, 0, 500, 500)), ..st };
        assert_ne!(l.frame(0.05, &other), Present::Nothing);
        assert!(!l.paused());
        // with the pause off, the ground moves to the screen bottom under the hidden panel
        l.set_panel_top(Some(180));
        let no_pause = SceneState { pause_fullscreen: false, ..fs };
        l.frame(0.05, &no_pause);
        assert_eq!(l.ground_y, 200.0);
        l.frame(0.05, &st);
        assert_eq!(l.ground_y, 180.0);
    }

    #[test]
    fn figures_leave_no_trails() {
        use crate::figures::{Figures, ScreenInfo};
        // one 1280x720 screen with every figure: lights, elves, the finished snowman, Santa and the plow
        let rect = Rect::new(0, 0, 1280, 720);
        let mut l = Layer::new(rect, true, 1.0, 11).unwrap();
        l.heap.fill(18.0 * l.s);
        let mut f = Figures::new(4);
        let info = |l: &Layer| vec![ScreenInfo { rect, s: l.s, primary: true, heap_average: l.heap_average() }];
        f.launch_santa(&info(&l));
        f.send_plow(&info(&l));
        let mut t = 0.0;
        let mut drew_elves = false;
        for _ in 0..1200 {
            t += 0.05;
            f.update(0.05, t, &info(&l), true, true);
            let st = SceneState {
                time: t,
                lights: true,
                elves: true,
                snowman_stage: 12,
                santa: f.santa.as_ref(),
                sparks: &f.sparks,
                plow: Some(&f.plow),
                ..state()
            };
            l.frame(0.05, &st);
            f.plow.pushed += l.take_pushed();
            drew_elves |= !l.elves.is_empty();
        }
        assert!(drew_elves);
        assert!(f.plow.pushed > 0.0, "the plow scraped nothing");
        // Everything off: once the last flakes have landed (up to ~40 s on this screen) and the pile has melted,
        // the screen must be completely empty again.
        let off = SceneState { time: t, snow_on: false, snow_ground: false, ..state() };
        f.finish_runs();
        for _ in 0..1200 {
            l.frame(0.05, &off);
        }
        assert_eq!(l.flake_count(), 0);
        let w = l.width();
        if let Some(i) = l.pixels().iter().position(|p| *p != 0) {
            panic!("trail at {},{}", i as i32 % w, i as i32 / w);
        }
    }

    impl Layer {
        /// What clearing the whole screen would leave: the cached lights and ground, empty elsewhere.
        fn background(&mut self) -> Vec<u32> {
            let keep = self.canvas.pixels.to_vec();
            self.clear_rects(&[Rect::new(0, 0, self.w, self.h)]);
            let bg = self.canvas.pixels.to_vec();
            self.canvas.pixels.copy_from_slice(&keep);
            bg
        }
    }

    #[test]
    fn lights_survive_falling_snow() {
        // flakes falling through the strip must not erase the lights
        let mut l = Layer::new(Rect::new(0, 0, 1280, 720), true, 1.0, 12).unwrap();
        let st = SceneState { lights: true, snow_amount: 2.0, ..state() };
        for _ in 0..3 {
            l.frame(0.05, &st);
        }
        let lh = l.lights.as_ref().unwrap().h;
        let w = l.width();
        for _ in 0..20 {
            l.frame(0.03, &st);
            let restored = l.background();
            for (i, (p, q)) in l.pixels()[..(lh * w) as usize].iter().zip(&restored).enumerate() {
                let (x, y) = (i as i32 % w, i as i32 / w);
                let drawn = l.prev_dirty.iter().any(|r| x >= r.x && x < r.right() && y >= r.y && y < r.bottom());
                assert!(drawn || p == q, "lights erased at {x},{y}");
            }
        }
    }

    #[test]
    fn flakes_land_on_window_edges_and_the_snow_is_drawn_under_the_lights() {
        use crate::window_snow::{FRect, WinInfo, WindowSnow};
        let rect = Rect::new(0, 0, 1280, 720);
        let mut l = Layer::new(rect, true, 1.0, 21).unwrap();
        let mut ws = WindowSnow::new(1.0, 5);
        // one window whose top edge is inside the lights strip (y 30 < 70 * s), one lower down
        let win =
            |id, y| WinInfo { id, rect: FRect { x: 200.0, y, w: 700.0, h: 300.0 }, visible: vec![(206.0, 894.0)] };
        ws.update_ledges(vec![win(1, 30.0), win(2, 400.0)]);
        let mut t = 5.0;
        for _ in 0..1200 {
            t += 0.05;
            let st = SceneState {
                time: t,
                lights: true,
                snow_amount: 2.0,
                ledges: &ws.ledges,
                clumps: &ws.clumps,
                ..state()
            };
            l.frame(0.05, &st);
            for (li, x, r) in l.take_ledge_hits() {
                ws.ledges[li].deposit(x, r);
            }
            ws.update(0.05, false, false, 0.0, 720.0);
        }
        assert!(ws.ledges.iter().all(|e| e.has_snow), "no snow landed on a window");
        // the cached snow on windows is what clearing restores: every lit pixel was drawn this frame or is that
        let background = l.background();
        let w = l.width();
        for (i, (p, b)) in l.pixels().iter().zip(&background).enumerate() {
            let (x, y) = (i as i32 % w, i as i32 / w);
            let drawn = l.prev_dirty.iter().any(|r| x >= r.x && x < r.right() && y >= r.y && y < r.bottom());
            assert!(*p == *b || drawn, "stale pixel at {x},{y}");
        }
        assert!(background[396 * w as usize..400 * w as usize].iter().any(|p| *p >> 24 > 200), "no cached snow");
        // snow on the edge at y 30: white pixels just above it, and the lights still on top somewhere in the strip
        let w = l.width() as usize;
        let white = (200..900).filter(|&x| l.pixels()[28 * w + x] >> 24 > 200).count();
        assert!(white > 100, "only {white} snow pixels on the edge under the lights");
        // closing both windows lets the snow fall, and it lands in this screen's pile
        ws.update_ledges(vec![]);
        let falling = ws.clumps.len();
        assert!(falling > 0);
        let mut landed = 0;
        for _ in 0..100 {
            t += 0.05;
            let st = SceneState { time: t, ledges: &ws.ledges, clumps: &ws.clumps, ..state() };
            l.frame(0.05, &st);
            for ci in l.take_clumps_landed() {
                ws.clumps[ci].dead = true;
                landed += 1;
            }
            ws.update(0.05, false, false, 0.0, 720.0);
        }
        assert!(ws.clumps.is_empty());
        // all of them land on this screen's ground (none fall past it)
        assert_eq!(landed, falling, "the clumps did not reach the pile");
        // and nothing of the windows' snow is left: not on screen, not in the cache
        let background = l.background();
        assert!(background[396 * w..400 * w].iter().all(|p| *p == 0), "cached snow left where the window was");
        assert!(l.pixels()[396 * w + 300..396 * w + 800].iter().all(|p| *p >> 24 < 200), "snow left on screen");
    }

    #[test]
    fn merged_rects_cover_everything() {
        // a flake's old and new box merge into one; boxes far apart stay apart
        let mut v = vec![Rect::new(100, 100, 20, 20), Rect::new(500, 100, 20, 20), Rect::new(102, 103, 20, 20)];
        let before = v.clone();
        merge_rects(&mut v);
        assert_eq!(v.len(), 2);
        for r in &before {
            assert!(v.iter().any(|m| m.contains(r)), "{r:?} lost");
        }
    }

    #[test]
    fn blend_dot_is_premultiplied_white() {
        let mut l = Layer::new(Rect::new(0, 0, 20, 20), true, 1.0, 1).unwrap();
        l.blend_dot(10.0, 10.0, 3.0, 200);
        let p = l.pixels()[10 * 20 + 10];
        let (a, r, g, b) = (p >> 24, (p >> 16) & 0xFF, (p >> 8) & 0xFF, p & 0xFF);
        assert_eq!(a, 200);
        assert!(r == a && g == a && b == a);
    }
}
