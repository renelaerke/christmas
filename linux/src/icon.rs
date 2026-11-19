//! The snowflake icon (red disc, white flake), drawn in code like in `build.ps1`, so the repo has no image files.

use std::f64::consts::PI;

use cairo::{Context, Format, ImageSurface, LinearGradient};

use crate::x11::Res;

/// Draws the icon at `size` x `size` pixels. The design is on a 32-unit grid.
pub fn draw(cr: &Context, size: f64) -> Res<()> {
    let k = size / 32.0;
    let bg = LinearGradient::new(0.0, 1.0 * k, 0.0, 31.0 * k);
    bg.add_color_stop_rgb(0.0, 225.0 / 255.0, 45.0 / 255.0, 55.0 / 255.0);
    bg.add_color_stop_rgb(1.0, 160.0 / 255.0, 15.0 / 255.0, 25.0 / 255.0);
    cr.arc(16.0 * k, 16.0 * k, 15.0 * k, 0.0, 2.0 * PI);
    cr.set_source(&bg)?;
    cr.fill()?;

    cr.set_source_rgb(1.0, 1.0, 1.0);
    cr.set_line_width((2.2 * k).max(1.2));
    cr.set_line_cap(cairo::LineCap::Round);
    let c = 16.0 * k;
    for i in 0..3 {
        let a = i as f64 * PI / 3.0 + PI / 2.0;
        let (dx, dy) = (a.cos() * 11.0 * k, a.sin() * 11.0 * k);
        cr.move_to(c - dx, c - dy);
        cr.line_to(c + dx, c + dy);
        if size < 24.0 {
            continue; // branches are just noise at tiny sizes
        }
        for sgn in [-1.0, 1.0] {
            let (ex, ey) = (c + sgn * dx * 0.65, c + sgn * dy * 0.65);
            let a1 = a + if sgn > 0.0 { 0.0 } else { PI };
            for side in [-1.0, 1.0] {
                let ba = a1 + side * 2.4;
                cr.move_to(ex, ey);
                cr.line_to(ex + ba.cos() * 4.0 * k, ey + ba.sin() * 4.0 * k);
            }
        }
    }
    cr.stroke()?;
    Ok(())
}

/// The icon as straight (not premultiplied) ARGB32 in network byte order, as StatusNotifierItem wants it.
pub fn argb_be(size: i32) -> Res<Vec<u8>> {
    let mut surface = ImageSurface::create(Format::ARgb32, size, size)?;
    {
        let cr = Context::new(&surface)?;
        draw(&cr, size as f64)?;
    }
    surface.flush();
    let stride = surface.stride() as usize;
    let data = surface.data()?;
    let mut out = Vec::with_capacity(size as usize * size as usize * 4);
    for y in 0..size as usize {
        for x in 0..size as usize {
            let i = y * stride + x * 4;
            let p = u32::from_ne_bytes([data[i], data[i + 1], data[i + 2], data[i + 3]]);
            let a = p >> 24;
            let un = |c: u32| (c * 255 + a / 2).checked_div(a).map_or(0, |v| v.min(255) as u8);
            out.extend_from_slice(&[a as u8, un((p >> 16) & 0xFF), un((p >> 8) & 0xFF), un(p & 0xFF)]);
        }
    }
    Ok(out)
}

/// Writes the icon as a PNG of `size` pixels (`--write-icon`, for the menu entry `install.sh` makes).
pub fn write_png(size: i32, path: &std::path::Path) -> Res<()> {
    let surface = ImageSurface::create(Format::ARgb32, size, size)?;
    {
        let cr = Context::new(&surface)?;
        draw(&cr, size as f64)?;
    }
    if let Some(dir) = path.parent().filter(|d| !d.as_os_str().is_empty()) {
        std::fs::create_dir_all(dir)?;
    }
    let mut f = std::fs::File::create(path)?;
    surface.write_to_png(&mut f)?;
    Ok(())
}

/// The icon as straight ARGB values, as `_NET_WM_ICON` wants it.
pub fn argb_u32(size: i32) -> Res<Vec<u32>> {
    Ok(argb_be(size)?.as_chunks::<4>().0.iter().map(|c| u32::from_be_bytes(*c)).collect())
}

/// The icon as straight RGBA bytes, as a notification's `image-data` wants it.
pub fn rgba(size: i32) -> Res<Vec<u8>> {
    Ok(argb_be(size)?.as_chunks::<4>().0.iter().flat_map(|c| [c[1], c[2], c[3], c[0]]).collect())
}

#[cfg(test)]
mod tests {
    #[test]
    fn icon_has_red_disc_and_white_centre() {
        let size = 32;
        let px = super::argb_be(size).unwrap();
        let at = |x: usize, y: usize| {
            let i = (y * size as usize + x) * 4;
            (px[i], px[i + 1], px[i + 2], px[i + 3])
        };
        assert_eq!(at(0, 0).0, 0, "corner is transparent");
        let (a, r, g, b) = at(16, 16);
        assert_eq!(a, 255);
        assert!(r > 240 && g > 240 && b > 240, "centre is white: {r},{g},{b}");
        let (a, r, g, _) = at(6, 16);
        assert_eq!(a, 255);
        assert!(r > 150 && g < 60, "disc is red");
    }
}
