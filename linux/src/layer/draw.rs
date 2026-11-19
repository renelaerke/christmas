//! Small Cairo helpers that read like the GDI+ calls in `src/Layer.cs`, so the figures can be ported line by line.
//! Colors are (alpha, red, green, blue) as in `Color.FromArgb`. Line widths and coordinates are in the current
//! user space, so they scale with the figure, as GDI+ pens do.

use cairo::{Context, Format, ImageSurface, LineCap};

use crate::x11::Res;

pub type Argb = (u8, u8, u8, u8);

/// `w` x `h` premultiplied pixels with a Cairo context drawing into them.
/// Field order matters, as in `Canvas`: the context and surface go before the pixels.
pub struct Image {
    pub cr: Context,
    pub surface: ImageSurface,
    pub pixels: Vec<u32>,
}

impl Image {
    pub fn new(w: i32, h: i32) -> Res<Image> {
        let mut pixels = vec![0u32; w as usize * h as usize];
        // SAFETY: as in `Canvas::new`: a w*h buffer with a stride of w*4 that is never reallocated and outlives
        // the surface and context.
        let surface = unsafe {
            ImageSurface::create_for_data_unsafe(pixels.as_mut_ptr() as *mut u8, Format::ARgb32, w, h, w * 4)?
        };
        let cr = Context::new(&surface)?;
        Ok(Image { cr, surface, pixels })
    }
}

pub const fn rgb(r: u8, g: u8, b: u8) -> Argb {
    (255, r, g, b)
}

pub fn set(cr: &Context, c: Argb) {
    cr.set_source_rgba(c.1 as f64 / 255.0, c.2 as f64 / 255.0, c.3 as f64 / 255.0, c.0 as f64 / 255.0);
}

/// An ellipse in the bounding box (x, y, w, h), added to the current path.
pub fn ellipse_path(cr: &Context, x: f64, y: f64, w: f64, h: f64) {
    if w <= 0.0 || h <= 0.0 {
        return;
    }
    let m = cr.matrix();
    cr.translate(x + w / 2.0, y + h / 2.0);
    cr.scale(w / 2.0, h / 2.0);
    cr.new_sub_path();
    cr.arc(0.0, 0.0, 1.0, 0.0, std::f64::consts::TAU);
    cr.close_path();
    cr.set_matrix(m);
}

pub fn fill_ellipse(cr: &Context, c: Argb, x: f64, y: f64, w: f64, h: f64) {
    cr.new_path();
    ellipse_path(cr, x, y, w, h);
    set(cr, c);
    let _ = cr.fill();
}

pub fn draw_ellipse(cr: &Context, c: Argb, width: f64, x: f64, y: f64, w: f64, h: f64) {
    cr.new_path();
    ellipse_path(cr, x, y, w, h);
    stroke(cr, c, width, LineCap::Butt);
}

pub fn fill_rect(cr: &Context, c: Argb, x: f64, y: f64, w: f64, h: f64) {
    cr.new_path();
    cr.rectangle(x, y, w, h);
    set(cr, c);
    let _ = cr.fill();
}

pub fn polygon_path(cr: &Context, pts: &[(f64, f64)]) {
    cr.new_path();
    for &(x, y) in pts {
        cr.line_to(x, y);
    }
    cr.close_path();
}

pub fn fill_polygon(cr: &Context, c: Argb, pts: &[(f64, f64)]) {
    polygon_path(cr, pts);
    set(cr, c);
    let _ = cr.fill();
}

/// Strokes the current path.
pub fn stroke(cr: &Context, c: Argb, width: f64, cap: LineCap) {
    set(cr, c);
    cr.set_line_width(width);
    cr.set_line_cap(cap);
    cr.set_line_join(cairo::LineJoin::Round);
    let _ = cr.stroke();
}

#[allow(clippy::too_many_arguments)] // reads like GDI+ DrawLine(pen, x1, y1, x2, y2)
pub fn line(cr: &Context, c: Argb, width: f64, cap: LineCap, x1: f64, y1: f64, x2: f64, y2: f64) {
    cr.new_path();
    cr.move_to(x1, y1);
    cr.line_to(x2, y2);
    stroke(cr, c, width, cap);
}

/// A smooth curve through all points, like GDI+ `DrawCurve` (a cardinal spline with tension 0.5), added to the
/// current path.
pub fn curve_path(cr: &Context, pts: &[(f64, f64)]) {
    curve(cr, pts, false);
}

/// As `curve_path`, but joined to the current path with a straight line (GDI+ `AddCurve` on a path that already
/// has a figure).
pub fn curve_path_joined(cr: &Context, pts: &[(f64, f64)]) {
    curve(cr, pts, true);
}

fn curve(cr: &Context, pts: &[(f64, f64)], joined: bool) {
    let Some(&(x0, y0)) = pts.first() else { return };
    if joined {
        cr.line_to(x0, y0);
    } else {
        cr.move_to(x0, y0);
    }
    let k = 0.5 / 3.0;
    let n = pts.len();
    for i in 0..n - 1 {
        let (p0, p1, p2) = (pts[i.saturating_sub(1)], pts[i], pts[i + 1]);
        let p3 = pts[(i + 2).min(n - 1)];
        cr.curve_to(
            p1.0 + (p2.0 - p0.0) * k,
            p1.1 + (p2.1 - p0.1) * k,
            p2.0 - (p3.0 - p1.0) * k,
            p2.1 - (p3.1 - p1.1) * k,
            p2.0,
            p2.1,
        );
    }
}

/// The ten points of a five-pointed star.
pub fn star_points(cx: f64, cy: f64, outer: f64, inner: f64, rot: f64) -> [(f64, f64); 10] {
    let mut p = [(0.0, 0.0); 10];
    for (i, q) in p.iter_mut().enumerate() {
        let a = -std::f64::consts::FRAC_PI_2 + i as f64 * std::f64::consts::PI / 5.0 + rot;
        let r = if i % 2 == 0 { outer } else { inner };
        *q = (cx + a.cos() * r, cy + a.sin() * r);
    }
    p
}

/// Colors shared by several figures (the same values as on Windows).
pub const SANTA_RED: Argb = rgb(205, 25, 35);
pub const GOLD: Argb = rgb(235, 195, 70);
pub const SKIN: Argb = rgb(255, 214, 186);
pub const WHITE: Argb = rgb(255, 255, 255);
pub const HAT_RED: Argb = rgb(210, 30, 40);
pub const SHADOW: Argb = (50, 60, 80, 110);
