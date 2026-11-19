//! The advent calendar: what is behind the 24 doors and when they may be opened (`CalendarContent`), and the
//! calendar window (`CalendarForm`). Ported from `src/Calendar.cs`.
//!
//! The window is drawn with Cairo and Pango into memory and sent to an ordinary X11 window (`x11::AppWindow`). The
//! background (gradient, snow dots, title) is rendered once; afterwards only doors that move are redrawn: an
//! opening door, and the gold border pulsing around doors that may be opened.

use cairo::{Context, LineCap};
use chrono::{Datelike, NaiveDate};
use pangocairo::pango;
use x11rb::protocol::Event;

use crate::layer::draw::*;
use crate::settings::Settings;
use crate::text;
use crate::x11::{AppWindow, Display, Rect, Res};

// ---------------------------------------------------------------------- content and rules
/// The effect behind each door: 0 none, 1 Santa, 2 snowstorm, 3 elf party, 4 star shower, 5 all of it.
pub const EFFECTS: [i32; 24] = [3, 0, 0, 4, 0, 0, 0, 2, 0, 0, 3, 1, 4, 0, 0, 0, 2, 0, 0, 4, 3, 1, 0, 5];

/// The calendar of a December stays open through January.
pub fn calendar_year_for(d: NaiveDate) -> i32 {
    if d.month() == 1 {
        d.year() - 1
    } else {
        d.year()
    }
}

/// The highest door that may be opened on `d` (0: none).
pub fn openable_up_to(d: NaiveDate) -> i32 {
    match d.month() {
        12 => (d.day() as i32).min(24),
        1 => 24,
        _ => 0,
    }
}

/// A new calendar year closes all doors again. Returns true when the settings changed (and were saved).
pub fn sync_year(s: &mut Settings, d: NaiveDate) -> bool {
    let y = calendar_year_for(d);
    if s.calendar_year == y {
        return false;
    }
    s.calendar_year = y;
    s.opened_doors.clear();
    s.save();
    true
}

// ---------------------------------------------------------------------- the window
/// Where each door sits in the 6 x 4 grid, read row by row.
const ORDER: [usize; 24] = [7, 15, 2, 22, 11, 18, 4, 20, 13, 1, 9, 24, 16, 6, 23, 10, 3, 19, 12, 21, 5, 17, 14, 8];
const DOOR_FILLS: [Argb; 3] = [rgb(165, 28, 38), rgb(238, 228, 204), rgb(30, 105, 60)];
const GOLD_C: Argb = rgb(240, 205, 110);

/// What a click or key in the calendar asks the controller to do.
#[derive(Debug, PartialEq, Eq)]
pub enum CalendarAction {
    None,
    Closed,
    /// A door was opened (or opened again): play its effect.
    Effect(i32),
}

#[derive(Clone, Copy)]
struct RectF {
    x: f64,
    y: f64,
    w: f64,
    h: f64,
}

impl RectF {
    fn inflate(&self, d: f64) -> RectF {
        RectF { x: self.x - d, y: self.y - d, w: self.w + 2.0 * d, h: self.h + 2.0 * d }
    }
    fn contains(&self, x: f64, y: f64) -> bool {
        x >= self.x && x < self.x + self.w && y >= self.y && y < self.y + self.h
    }
    fn to_rect(self) -> Rect {
        let (x0, y0) = (self.x.floor() as i32, self.y.floor() as i32);
        Rect::new(x0, y0, (self.x + self.w).ceil() as i32 - x0, (self.y + self.h).ceil() as i32 - y0)
    }
}

pub struct Calendar {
    win: AppWindow,
    w: i32,
    h: i32,
    /// Scale: the desktop's DPI / 96.
    k: f64,
    title: String,
    /// What is on screen, and the background it is drawn over.
    img: Image,
    background: Image,
    doors: [RectF; 25],
    open_anim: [f32; 25],
    pulse: f32,
    pulse_acc: f32,
    selected: i32,
    message: String,
    /// The pointer is over a door (hand cursor).
    hand: bool,
}

impl Calendar {
    /// Opens the calendar window centred on `on` (the primary monitor, global coordinates).
    pub fn open(display: &Display, cfg: &Settings, on: Rect) -> Res<Calendar> {
        let k = display.dpi_scale as f64;
        let (w, h) = ((820.0 * k) as i32, (720.0 * k) as i32);
        let today = crate::clock::today();
        let title = text::calendar_title(calendar_year_for(today));
        let icons: Vec<(i32, Vec<u32>)> =
            [16, 32, 48, 64, 128].iter().filter_map(|&s| crate::icon::argb_u32(s).ok().map(|p| (s, p))).collect();
        let win = display.create_app_window(&title, w, h, on, &icons)?;

        let (size, gap) = (110.0 * k, 15.0 * k);
        let (left, top) = ((w as f64 - (6.0 * size + 5.0 * gap)) / 2.0, 95.0 * k);
        let mut doors = [RectF { x: 0.0, y: 0.0, w: 0.0, h: 0.0 }; 25];
        for (i, &d) in ORDER.iter().enumerate() {
            doors[d] = RectF {
                x: left + (i % 6) as f64 * (size + gap),
                y: top + (i / 6) as f64 * (size + gap),
                w: size,
                h: size,
            };
        }
        let mut open_anim = [0.0f32; 25];
        for d in 1..=24 {
            if cfg.opened_doors.contains(&d) {
                open_anim[d as usize] = 1.0;
            }
        }
        let mut c = Calendar {
            win,
            w,
            h,
            k,
            title,
            img: Image::new(w, h)?,
            background: Image::new(w, h)?,
            doors,
            open_anim,
            pulse: 0.0,
            pulse_acc: 0.0,
            selected: 0,
            message: initial_message(cfg, today),
            hand: false,
        };
        c.render_background();
        c.render_all(cfg);
        Ok(c)
    }

    pub fn window(&self) -> u32 {
        self.win.win
    }

    /// Brings the window to the front again (the menu or a notification asked for the calendar).
    pub fn raise(&self, display: &Display) {
        display.activate(&self.win);
    }

    pub fn close(self, display: &Display) {
        display.destroy_app_window(&self.win);
    }

    /// Handles an event for the calendar window.
    pub fn handle(&mut self, display: &mut Display, e: &Event, cfg: &mut Settings) -> CalendarAction {
        match e {
            Event::Expose(x) if x.count == 0 => self.present(display, &[Rect::new(0, 0, self.w, self.h)]),
            Event::ButtonPress(b) if b.detail == 1 => {
                if let Some(d) = self.hit_test(b.event_x as f64, b.event_y as f64) {
                    let action = self.click_door(d, cfg);
                    self.render_all(cfg);
                    self.present(display, &[Rect::new(0, 0, self.w, self.h)]);
                    return action;
                }
            }
            Event::MotionNotify(m) => {
                let hand = self.hit_test(m.event_x as f64, m.event_y as f64).is_some();
                if hand != self.hand {
                    self.hand = hand;
                    display.set_hand_cursor(&self.win, hand);
                }
            }
            Event::KeyPress(k) if display.is_escape(k.detail) => return CalendarAction::Closed,
            Event::ClientMessage(m) if display.is_close_request(m) => return CalendarAction::Closed,
            Event::DestroyNotify(_) => return CalendarAction::Closed,
            _ => {}
        }
        CalendarAction::None
    }

    /// Animation, called every frame: repaints only doors that move. The pulse is slow, so its doors are
    /// repainted 12.5 times a second, as on Windows.
    pub fn tick(&mut self, display: &mut Display, dt: f32, cfg: &Settings) {
        // Windows steps 0.04 (pulse) and 0.07 (opening) every 40 ms
        self.pulse += dt;
        self.pulse_acc += dt;
        let pulse_frame = self.pulse_acc >= 0.08;
        if pulse_frame {
            self.pulse_acc = 0.0;
        }
        let up_to = openable_up_to(crate::clock::today());
        let mut changed = Vec::new();
        for (d, a) in self.open_anim.iter_mut().enumerate().skip(1) {
            if *a > 0.0 && *a < 1.0 {
                *a = (*a + dt * 1.75).min(1.0);
                changed.push(d);
            } else if pulse_frame && d as i32 <= up_to && !cfg.opened_doors.contains(&(d as i32)) {
                changed.push(d);
            }
        }
        if changed.is_empty() {
            return;
        }
        let rects: Vec<Rect> = changed.iter().map(|&d| self.doors[d].inflate(8.0 * self.k).to_rect()).collect();
        for (&d, r) in changed.iter().zip(&rects) {
            self.render_door_area(d, *r, cfg, up_to);
        }
        self.present(display, &rects);
    }

    fn present(&mut self, display: &mut Display, rects: &[Rect]) {
        let rects: Vec<Rect> = rects.iter().map(|r| r.clip(self.w, self.h)).filter(|r| !r.is_empty()).collect();
        if let Err(e) = display.put_app(&self.win, &self.img.pixels, self.w as usize, &rects) {
            crate::log::error(&format!("calendar: {e}"));
        }
    }

    fn hit_test(&self, x: f64, y: f64) -> Option<i32> {
        (1..=24).find(|&d| self.doors[d as usize].contains(x, y))
    }

    fn click_door(&mut self, d: i32, cfg: &mut Settings) -> CalendarAction {
        let today = crate::clock::today();
        sync_year(cfg, today);
        if d <= openable_up_to(today) {
            if cfg.opened_doors.insert(d) {
                cfg.save();
                self.open_anim[d as usize] = 0.01;
            }
            self.selected = d;
            self.message = text::calendar_door(d, text::DOOR_TEXTS[d as usize - 1]);
            return CalendarAction::Effect(EFFECTS[d as usize - 1]);
        }
        self.selected = 0;
        self.message = if today.month() == 12 {
            text::calendar_patience(d, d as i64 - today.day() as i64)
        } else {
            text::calendar_opens_on(d)
        };
        CalendarAction::None
    }

    // ------------------------------------------------------------------ drawing
    fn render_background(&mut self) {
        let (w, h, k) = (self.w as f64, self.h as f64, self.k);
        let cr = &self.background.cr;
        let grad = cairo::LinearGradient::new(0.0, 0.0, 0.0, h);
        grad.add_color_stop_rgb(0.0, 24.0 / 255.0, 72.0 / 255.0, 46.0 / 255.0);
        grad.add_color_stop_rgb(1.0, 8.0 / 255.0, 28.0 / 255.0, 18.0 / 255.0);
        let _ = cr.set_source(&grad);
        let _ = cr.paint();
        // the same snow dots every time (Windows uses Random(7); any fixed pattern will do)
        let mut r = crate::rng::NetRandom::new(7);
        for _ in 0..90 {
            let rad = (1.0 + r.next_double() * 2.5) * k;
            let (x, y) = (r.next_double() * w, r.next_double() * h);
            fill_ellipse(cr, (55, 255, 255, 255), x, y, rad * 2.0, rad * 2.0);
        }
        text_in(cr, &self.title, "Serif Bold", 32.0 * k, GOLD_C, (0.0, 15.0 * k, w, 70.0 * k), true);
        self.background.surface.flush();
    }

    fn render_all(&mut self, cfg: &Settings) {
        let up_to = openable_up_to(crate::clock::today());
        self.img.surface.flush();
        self.img.pixels.copy_from_slice(&self.background.pixels);
        self.img.surface.mark_dirty();
        for d in 1..=24 {
            self.draw_door(d, cfg, up_to);
        }
        let k = self.k;
        let mr = (40.0 * k, 605.0 * k, self.w as f64 - 80.0 * k, 95.0 * k);
        let cr = &self.img.cr;
        rounded(cr, RectF { x: mr.0, y: mr.1, w: mr.2, h: mr.3 }, 12.0 * k);
        set(cr, (45, 255, 255, 255));
        let _ = cr.fill();
        let inner = (mr.0 + 18.0 * k, mr.1 + 8.0 * k, mr.2 - 36.0 * k, mr.3 - 16.0 * k);
        text_in(cr, &self.message, "Sans", 16.0 * k, WHITE, inner, false);
        self.img.surface.flush();
    }

    /// Restores the background in `r` and draws the door over it.
    fn render_door_area(&mut self, d: usize, r: Rect, cfg: &Settings, up_to: i32) {
        let r = r.clip(self.w, self.h);
        self.img.surface.flush();
        for y in r.y..r.bottom() {
            let s = y as usize * self.w as usize + r.x as usize;
            self.img.pixels[s..s + r.w as usize].copy_from_slice(&self.background.pixels[s..s + r.w as usize]);
        }
        self.img.surface.mark_dirty();
        let cr = &self.img.cr;
        cr.save().ok();
        cr.rectangle(r.x as f64, r.y as f64, r.w as f64, r.h as f64);
        cr.clip();
        self.draw_door(d as i32, cfg, up_to);
        self.img.cr.restore().ok();
        self.img.surface.flush();
    }

    fn draw_door(&self, d: i32, cfg: &Settings, up_to: i32) {
        let cr = &self.img.cr;
        let k = self.k;
        let rc = self.doors[d as usize];
        let fill = DOOR_FILLS[d as usize % 3];
        let num_col = if d % 3 == 1 { rgb(165, 28, 38) } else { WHITE };
        let rad = 10.0 * k;

        if cfg.opened_doors.contains(&d) {
            rounded(cr, rc, rad);
            let grad = cairo::LinearGradient::new(0.0, rc.y, 0.0, rc.y + rc.h);
            grad.add_color_stop_rgb(0.0, 70.0 / 255.0, 40.0 / 255.0, 28.0 / 255.0);
            grad.add_color_stop_rgb(1.0, 35.0 / 255.0, 20.0 / 255.0, 14.0 / 255.0);
            let _ = cr.set_source(&grad);
            let _ = cr.fill();
            let inner = RectF { x: rc.x + rc.w * 0.2, y: rc.y + rc.h * 0.2, w: rc.w * 0.6, h: rc.h * 0.6 };
            draw_icon(cr, d, inner);
            text_at(cr, &d.to_string(), "Serif Bold", 12.0 * k, rgb(200, 180, 140), rc.x + 6.0 * k, rc.y + 4.0 * k);

            let a = self.open_anim[d as usize] as f64;
            if a < 1.0 {
                // the door swings open around its left hinge
                let dr = RectF { x: rc.x, y: rc.y, w: rc.w * (1.0 - a), h: rc.h };
                if dr.w > 2.0 {
                    rounded(cr, dr, rad.min(dr.w / 2.0));
                    set(cr, shade(fill, 1.0 - a * 0.5));
                    let _ = cr.fill();
                }
            } else {
                fill_rect(cr, shade(fill, 0.6), rc.x - 4.0 * k, rc.y + 6.0 * k, 5.0 * k, rc.h - 12.0 * k);
            }
        } else {
            rounded(cr, rc, rad);
            // GDI+'s 60° gradient across the door: lighter at the top left
            let a = 60f64.to_radians();
            let reach = (rc.w * a.cos() + rc.h * a.sin()) / 2.0;
            let (cx, cy) = (rc.x + rc.w / 2.0, rc.y + rc.h / 2.0);
            let grad = cairo::LinearGradient::new(
                cx - a.cos() * reach,
                cy - a.sin() * reach,
                cx + a.cos() * reach,
                cy + a.sin() * reach,
            );
            let (c0, c1) = (shade(fill, 1.1), shade(fill, 0.85));
            grad.add_color_stop_rgb(0.0, c0.1 as f64 / 255.0, c0.2 as f64 / 255.0, c0.3 as f64 / 255.0);
            grad.add_color_stop_rgb(1.0, c1.1 as f64 / 255.0, c1.2 as f64 / 255.0, c1.3 as f64 / 255.0);
            let _ = cr.set_source(&grad);
            let _ = cr.fill_preserve();
            stroke(cr, (80, 255, 255, 255), 1.2 * k, LineCap::Butt);
            rounded(cr, rc.inflate(-7.0 * k), rad * 0.6);
            cr.set_dash(&[3.0 * k, k], 0.0);
            stroke(cr, (70, 0, 0, 0), k, LineCap::Butt);
            cr.set_dash(&[], 0.0);
            text_in(cr, &d.to_string(), "Serif Bold", 35.0 * k, num_col, (rc.x, rc.y, rc.w, rc.h), true);

            if d <= up_to {
                let al = (150.0 + 100.0 * (self.pulse as f64 * 3.0).sin()) as u8;
                rounded(cr, rc.inflate(2.0 * k), rad + 2.0 * k);
                stroke(cr, (al, GOLD_C.1, GOLD_C.2, GOLD_C.3), 3.5 * k, LineCap::Butt);
            }
        }
        if self.selected == d {
            rounded(cr, rc.inflate(3.0 * k), rad + 3.0 * k);
            stroke(cr, WHITE, 2.5 * k, LineCap::Butt);
        }
    }
}

fn initial_message(cfg: &Settings, today: NaiveDate) -> String {
    if openable_up_to(today) == 0 {
        let dec1 = NaiveDate::from_ymd_opt(today.year(), 12, 1).unwrap_or(today);
        return text::calendar_opens_in((dec1 - today).num_days());
    }
    if today.month() == 12 && today.day() <= 24 && !cfg.opened_doors.contains(&(today.day() as i32)) {
        return text::calendar_todays_door(today.day());
    }
    text::CALENDAR_READ_AGAIN.into()
}

fn shade(c: Argb, f: f64) -> Argb {
    let s = |v: u8| (v as f64 * f).min(255.0) as u8;
    (c.0, s(c.1), s(c.2), s(c.3))
}

/// A rectangle with rounded corners, as the current path.
fn rounded(cr: &Context, r: RectF, rad: f64) {
    let rad = rad.max(0.05);
    let pi = std::f64::consts::PI;
    cr.new_path();
    cr.arc(r.x + rad, r.y + rad, rad, pi, 1.5 * pi);
    cr.arc(r.x + r.w - rad, r.y + rad, rad, 1.5 * pi, 2.0 * pi);
    cr.arc(r.x + r.w - rad, r.y + r.h - rad, rad, 0.0, 0.5 * pi);
    cr.arc(r.x + rad, r.y + r.h - rad, rad, 0.5 * pi, pi);
    cr.close_path();
}

fn layout(cr: &Context, s: &str, font: &str, px: f64) -> pango::Layout {
    let layout = pangocairo::functions::create_layout(cr);
    let mut fd = pango::FontDescription::from_string(font);
    fd.set_absolute_size(px * pango::SCALE as f64);
    layout.set_font_description(Some(&fd));
    layout.set_text(s);
    layout
}

/// Text in a box: centred both ways (`center`), or wrapped at the box width, left aligned and centred vertically.
fn text_in(cr: &Context, s: &str, font: &str, px: f64, c: Argb, (x, y, w, h): (f64, f64, f64, f64), center: bool) {
    let l = layout(cr, s, font, px);
    if center {
        l.set_alignment(pango::Alignment::Center);
    } else {
        l.set_wrap(pango::WrapMode::WordChar);
    }
    l.set_width((w * pango::SCALE as f64) as i32);
    let (_, th) = l.pixel_size();
    set(cr, c);
    cr.move_to(x, y + (h - th as f64) / 2.0);
    pangocairo::functions::show_layout(cr, &l);
}

fn text_at(cr: &Context, s: &str, font: &str, px: f64, c: Argb, x: f64, y: f64) {
    let l = layout(cr, s, font, px);
    set(cr, c);
    cr.move_to(x, y);
    pangocairo::functions::show_layout(cr, &l);
}

/// A five-pointed star (outer radius `r_out`, inner `r_in`) as the current path.
fn star(cr: &Context, cx: f64, cy: f64, r_out: f64, r_in: f64) {
    polygon_path(cr, &star_points(cx, cy, r_out, r_in, 0.0));
}

/// The little picture behind each opened door: star, tree, gift, heart, candle or bell.
fn draw_icon(cr: &Context, d: i32, r: RectF) {
    let (cx, cy, w, h) = (r.x + r.w / 2.0, r.y + r.h / 2.0, r.w, r.h);
    fill_ellipse(cr, (40, 255, 220, 140), r.x - w * 0.15, r.y - h * 0.15, w * 1.3, h * 1.3);
    let red = rgb(205, 35, 45);
    let green = rgb(40, 140, 70);
    let white = rgb(245, 240, 230);
    match d % 6 {
        0 => {
            star(cr, cx, cy, w * 0.48, w * 0.2);
            set(cr, GOLD_C);
            let _ = cr.fill();
        }
        1 => {
            // tree
            for i in 0..3 {
                let (ty, tw) = (cy - h * 0.38 + i as f64 * h * 0.2, w * (0.38 + i as f64 * 0.14));
                fill_polygon(cr, green, &[(cx, ty), (cx + tw / 2.0, ty + h * 0.3), (cx - tw / 2.0, ty + h * 0.3)]);
            }
            fill_rect(cr, rgb(110, 70, 35), cx - w * 0.06, cy + h * 0.32, w * 0.12, h * 0.14);
            star(cr, cx, cy - h * 0.42, w * 0.12, w * 0.05);
            set(cr, GOLD_C);
            let _ = cr.fill();
            fill_ellipse(cr, red, cx - w * 0.15, cy - h * 0.02, w * 0.08, w * 0.08);
            fill_ellipse(cr, GOLD_C, cx + w * 0.08, cy + h * 0.15, w * 0.08, w * 0.08);
        }
        2 => {
            // gift
            fill_rect(cr, red, cx - w * 0.38, cy - h * 0.15, w * 0.76, h * 0.55);
            fill_rect(cr, rgb(178, 34, 34), cx - w * 0.42, cy - h * 0.27, w * 0.84, h * 0.14);
            fill_rect(cr, GOLD_C, cx - w * 0.06, cy - h * 0.27, w * 0.12, h * 0.67);
            fill_ellipse(cr, GOLD_C, cx - w * 0.28, cy - h * 0.45, w * 0.26, h * 0.2);
            fill_ellipse(cr, GOLD_C, cx + w * 0.02, cy - h * 0.45, w * 0.26, h * 0.2);
        }
        3 => {
            // heart
            cr.new_path();
            cr.move_to(cx, cy + h * 0.38);
            cr.curve_to(cx - w * 0.65, cy - h * 0.05, cx - w * 0.35, cy - h * 0.5, cx, cy - h * 0.18);
            cr.curve_to(cx + w * 0.35, cy - h * 0.5, cx + w * 0.65, cy - h * 0.05, cx, cy + h * 0.38);
            set(cr, red);
            let _ = cr.fill();
        }
        4 => {
            // candle
            fill_ellipse(cr, (70, 255, 200, 80), cx - w * 0.22, cy - h * 0.55, w * 0.44, h * 0.44);
            fill_rect(cr, white, cx - w * 0.13, cy - h * 0.15, w * 0.26, h * 0.6);
            fill_rect(cr, red, cx - w * 0.13, cy + h * 0.1, w * 0.26, h * 0.06);
            fill_ellipse(cr, GOLD_C, cx - w * 0.07, cy - h * 0.42, w * 0.14, h * 0.24);
        }
        _ => {
            // bell
            cr.new_path();
            cr.move_to(cx - w * 0.38, cy + h * 0.25);
            cr.curve_to(cx - w * 0.3, cy - h * 0.05, cx - w * 0.28, cy - h * 0.4, cx, cy - h * 0.4);
            cr.curve_to(cx + w * 0.28, cy - h * 0.4, cx + w * 0.3, cy - h * 0.05, cx + w * 0.38, cy + h * 0.25);
            cr.close_path();
            set(cr, GOLD_C);
            let _ = cr.fill();
            fill_ellipse(cr, GOLD_C, cx - w * 0.08, cy + h * 0.2, w * 0.16, w * 0.16);
            fill_ellipse(cr, red, cx - w * 0.2, cy - h * 0.52, w * 0.18, h * 0.14);
            fill_ellipse(cr, red, cx + w * 0.02, cy - h * 0.52, w * 0.18, h * 0.14);
        }
    }
}

/// `--calendar-snapshot`: the calendar as it would look, drawn without a window (for checking the drawing).
pub fn render_to_png(cfg: &Settings, k: f64, path: &std::path::Path) -> Res<()> {
    let (w, h) = ((820.0 * k) as i32, (720.0 * k) as i32);
    let today = crate::clock::today();
    // the window parts are not needed to draw; build the drawing state alone
    let size = 110.0 * k;
    let gap = 15.0 * k;
    let (left, top) = ((w as f64 - (6.0 * size + 5.0 * gap)) / 2.0, 95.0 * k);
    let mut doors = [RectF { x: 0.0, y: 0.0, w: 0.0, h: 0.0 }; 25];
    for (i, &d) in ORDER.iter().enumerate() {
        doors[d] =
            RectF { x: left + (i % 6) as f64 * (size + gap), y: top + (i / 6) as f64 * (size + gap), w: size, h: size };
    }
    let mut open_anim = [0.0f32; 25];
    for d in cfg.opened_doors.iter() {
        open_anim[*d as usize] = 1.0;
    }
    let mut c = Calendar {
        win: AppWindow::none(),
        w,
        h,
        k,
        title: text::calendar_title(calendar_year_for(today)),
        img: Image::new(w, h)?,
        background: Image::new(w, h)?,
        doors,
        open_anim,
        pulse: 0.5,
        pulse_acc: 0.0,
        selected: cfg.opened_doors.iter().next_back().copied().unwrap_or(0),
        message: initial_message(cfg, today),
        hand: false,
    };
    if c.selected > 0 {
        c.message = text::calendar_door(c.selected, text::DOOR_TEXTS[c.selected as usize - 1]);
    }
    c.render_background();
    c.render_all(cfg);
    let mut f = std::fs::File::create(path)?;
    c.img.surface.write_to_png(&mut f)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(y: i32, m: u32, day: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(y, m, day).unwrap()
    }

    #[test]
    fn door_rules() {
        assert_eq!(openable_up_to(d(2026, 11, 30)), 0);
        assert_eq!(openable_up_to(d(2026, 12, 1)), 1);
        assert_eq!(openable_up_to(d(2026, 12, 13)), 13);
        assert_eq!(openable_up_to(d(2026, 12, 31)), 24);
        assert_eq!(openable_up_to(d(2027, 1, 15)), 24);
        assert_eq!(openable_up_to(d(2027, 2, 1)), 0);
        // the December calendar stays open through January
        assert_eq!(calendar_year_for(d(2027, 1, 15)), 2026);
        assert_eq!(calendar_year_for(d(2026, 12, 24)), 2026);
    }

    #[test]
    fn every_door_has_text_and_a_known_effect() {
        assert!(text::DOOR_TEXTS.iter().all(|t| !t.is_empty()));
        assert!(EFFECTS.iter().all(|e| (0..=5).contains(e)));
        let mut seen: Vec<usize> = ORDER.to_vec();
        seen.sort();
        assert_eq!(seen, (1..=24).collect::<Vec<_>>(), "every door once in the grid");
    }

    #[test]
    fn opening_messages() {
        let s = Settings::default();
        assert!(initial_message(&s, d(2026, 11, 29)).contains("om 2 dage"));
        assert!(initial_message(&s, d(2026, 11, 30)).contains("om 1 dag."));
        assert!(initial_message(&s, d(2026, 12, 5)).contains("nummer 5"));
        let mut opened = Settings::default();
        opened.opened_doors.insert(5);
        assert_eq!(initial_message(&opened, d(2026, 12, 5)), text::CALENDAR_READ_AGAIN);
    }
}
