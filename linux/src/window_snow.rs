//! Snow on the top edge of other apps' windows (not fullscreen or maximized ones). Some of the falling flakes land
//! there; when the window goes away (minimized, closed, another workspace) the snow falls down as clumps and lands
//! in the pile at the bottom. All in global coordinates, so a window that spans two screens carries one pile.
//! Ported from `src/WindowSnow.cs` (itself from macOS `WindowSnow.swift`); the macOS sizes are in points, here they
//! are scaled by the desktop scale (`u`), as on Windows.
//!
//! Only X11 windows can be seen (`x11::Display::client_windows`): on Ubuntu's Wayland desktop native Wayland windows
//! are invisible to the app and simply carry no snow.

use crate::rng::Rng;
use crate::x11::Rect;

/// A rectangle in global coordinates, as floats (the piles' x positions are fractional).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FRect {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
}

impl FRect {
    pub fn from(r: Rect) -> FRect {
        FRect { x: r.x as f32, y: r.y as f32, w: r.w as f32, h: r.h as f32 }
    }
    pub fn right(&self) -> f32 {
        self.x + self.w
    }
    pub fn bottom(&self) -> f32 {
        self.y + self.h
    }
}

/// One window's top edge and the snow on it.
pub struct Ledge {
    pub id: u32,
    pub rect: FRect,
    /// Where the window last stood still. The snow sits there: while a window moves (or shrinks when it is
    /// minimized) the pile stays put, and if the window goes away, the snow falls from this spot.
    pub settled: FRect,
    /// Snow height per `step` from the window's left edge.
    pub cols: Vec<f32>,
    /// How far the snow hangs down over the edge (in front of the window), per column. It creeps out slowly once
    /// the pile is deep, in uneven lobes (fixed per window) and a little more around the corners.
    pub hang: Vec<f32>,
    lobes: Vec<f32>,
    /// Parts of the top edge (global x) not covered by a window in front.
    pub visible: Vec<(f32, f32)>,
    /// True while the window is moved or resized: the pile is hidden and catches nothing.
    pub moving: bool,
    pub has_snow: bool,
    step: f32,
    u: f32,
}

impl Ledge {
    fn new(id: u32, rect: FRect, u: f32) -> Ledge {
        let step = 4.0 * u;
        let n = (rect.w / step) as usize + 1;
        let mut l = Ledge {
            id,
            rect,
            settled: rect,
            cols: vec![0.0; n],
            hang: vec![0.0; n],
            lobes: Vec::new(),
            visible: Vec::new(),
            moving: false,
            has_snow: false,
            step,
            u,
        };
        l.make_lobes();
        l
    }

    /// Uneven drapes: two slow waves with a phase from the window id, sharpened so some places hang well down and
    /// others hardly at all.
    fn make_lobes(&mut self) {
        let (p1, p2) = ((self.id % 97) as f64 * 0.61, (self.id % 89) as f64 * 1.37);
        self.lobes = (0..self.cols.len())
            .map(|i| {
                let v = 0.5 + 0.5 * (0.6 * (i as f64 * 0.23 + p1).sin() + 0.4 * (i as f64 * 0.57 + p2).sin());
                v.clamp(0.0, 1.0).powf(2.2) as f32
            })
            .collect();
    }

    pub fn step(&self) -> f32 {
        self.step
    }

    fn index(&self, x: f32) -> Option<usize> {
        let i = ((x - self.settled.x) / self.step).floor();
        (i >= 0.0 && (i as usize) < self.cols.len()).then_some(i as usize)
    }
    pub fn height_at(&self, x: f32) -> f32 {
        self.index(x).map_or(0.0, |i| self.cols[i])
    }
    pub fn hang_at(&self, x: f32) -> f32 {
        self.index(x).map_or(0.0, |i| self.hang[i])
    }
    pub fn is_visible(&self, x: f32) -> bool {
        self.visible.iter().any(|&(a, b)| x >= a && x <= b)
    }

    /// `r` is the flake radius without the screen scale (about 1-4.5).
    pub fn deposit(&mut self, x: f32, r: f32) {
        let Some(i) = self.index(x) else { return };
        let amount = 0.3 * r * self.u;
        for k in -1i32..=1 {
            if let Some(c) = self.cols.get_mut((i as i32 + k) as usize) {
                *c += if k == 0 { amount } else { amount * 0.5 };
            }
        }
        self.has_snow = true;
    }

    /// Keeps the width in step with the window, keeping the snow that is still on it.
    fn resize(&mut self, width: f32) {
        let n = (width / self.step) as usize + 1;
        self.cols.resize(n, 0.0);
        self.hang.resize(n, 0.0);
        self.make_lobes();
    }
}

/// A lump of snow falling off a window that went away; the screen below catches it in its ground pile.
pub struct Clump {
    pub x: f32,
    pub y: f32,
    vx: f32,
    vy: f32,
    /// In macOS points (drawn and deposited scaled by the screen's figure scale).
    pub r: f32,
    pub dead: bool,
    /// Part of a whole window's snow falling (minimized, closed): worth a higher frame rate. A stretch breaking
    /// off a full edge is not (see `WindowSnow::busy`).
    bulk: bool,
}

/// A window found by the scan that can carry snow: its visible frame and the uncovered parts of its top edge.
#[derive(Clone, Debug, PartialEq)]
pub struct WinInfo {
    pub id: u32,
    pub rect: FRect,
    pub visible: Vec<(f32, f32)>,
}

/// A window as the X server describes it, front to back (`x11::Display::client_windows`).
#[derive(Clone, Debug)]
pub struct ClientWindow {
    pub id: u32,
    /// The visible frame (title bar included, invisible shadows left out), global coordinates.
    pub rect: Rect,
    /// Normal app window on the current workspace, shown, not ours: it hides what is behind it.
    pub shown: bool,
    pub maximized: bool,
}

/// Windows that can carry snow, each with the parts of its top edge not hidden by a window in front (`ScanWindows`
/// on Windows). `wins` is front to back. Maximized windows (top edge at the screen top, so the pile would be
/// off-screen) and fullscreen windows carry no snow but still hide what is behind them.
pub fn scan(wins: &[ClientWindow], screens: &[Rect], u: f32) -> Vec<WinInfo> {
    let pile_room = 16.0 * u; // a window in front just above the edge still hides the snow
    let mut occluders: Vec<FRect> = Vec::new();
    let mut out = Vec::new();
    for w in wins.iter().filter(|w| w.shown) {
        let r = FRect::from(w.rect);
        if r.w < 2.0 || r.h < 2.0 {
            continue;
        }
        let mut full = false;
        let mut top_on_screen = false;
        for s in screens {
            let s = FRect::from(*s);
            if (s.x - r.x).abs() < 2.0 && (s.y - r.y).abs() < 2.0 && (s.w - r.w).abs() < 2.0 && (s.h - r.h).abs() < 2.0
            {
                full = true;
            }
            let mx = r.x + r.w / 2.0;
            if mx >= s.x && mx < s.right() && r.y + 1.0 >= s.y + 12.0 * u && r.y + 1.0 < s.bottom() {
                top_on_screen = true;
            }
        }
        if !full && !w.maximized && top_on_screen && r.w >= 150.0 * u && r.h >= 80.0 * u {
            // the top edge minus the parts covered by windows in front (and the rounded corners)
            let y = r.y;
            let mut vis = vec![(r.x + 6.0 * u, r.right() - 6.0 * u)];
            for f in &occluders {
                if !(f.y < y + 1.0 && f.bottom() > y - pile_room) {
                    continue;
                }
                let mut next = Vec::new();
                for &(a, b) in &vis {
                    if f.right() <= a || f.x >= b {
                        next.push((a, b));
                        continue;
                    }
                    if f.x > a {
                        next.push((a, f.x));
                    }
                    if f.right() < b {
                        next.push((f.right(), b));
                    }
                }
                vis = next;
            }
            vis.retain(|&(a, b)| b - a >= 8.0 * u);
            out.push(WinInfo { id: w.id, rect: r, visible: vis });
        }
        occluders.push(r);
    }
    out
}

pub struct WindowSnow {
    pub ledges: Vec<Ledge>,
    pub clumps: Vec<Clump>,
    /// Pixels per macOS point: the desktop scale.
    u: f32,
    rng: Rng,
}

impl WindowSnow {
    pub fn new(u: f32, seed: u64) -> WindowSnow {
        WindowSnow { ledges: Vec::new(), clumps: Vec::new(), u: u.max(1.0), rng: Rng::new(seed) }
    }

    /// The desktop scale changed (the piles' column width depends on it): start over.
    pub fn set_scale(&mut self, u: f32) {
        let u = u.max(1.0);
        if u != self.u {
            self.u = u;
            self.ledges.clear();
            self.clumps.clear();
        }
    }

    /// True while a window with snow is being moved: the scan then runs every frame, so the pile follows.
    pub fn moving(&self) -> bool {
        self.ledges.iter().any(|l| l.moving && l.has_snow)
    }

    /// True while a whole window's snow is falling: the frame rate is boosted, as for Santa and the plow.
    ///
    /// Unlike Windows, snow breaking off a full edge does not count: in a storm with several full windows a stretch
    /// breaks off every few seconds, so clumps were nearly always falling and kept the app at 30 fps (40-50% CPU
    /// against about 25% on the Mint test machine). Those small falls look fine at the calm frame rate.
    pub fn busy(&self) -> bool {
        self.clumps.iter().any(|c| c.bulk && !c.dead)
    }

    /// Ends what is falling (`FinishRuns()`).
    pub fn finish(&mut self) {
        self.clumps.clear();
    }

    /// Matches the scanned windows with the existing ledges: windows that moved hide their snow until they settle,
    /// and windows that are gone let their snow fall.
    pub fn update_ledges(&mut self, wins: Vec<WinInfo>) {
        let mut seen = Vec::with_capacity(wins.len());
        for w in wins {
            seen.push(w.id);
            if let Some(l) = self.ledges.iter_mut().find(|l| l.id == w.id) {
                if l.rect != w.rect {
                    l.rect = w.rect;
                    l.moving = true;
                } else if l.moving {
                    // came to rest: the snow moves along (and keeps what still fits on a resized window)
                    if l.settled.w != l.rect.w {
                        l.resize(l.rect.w);
                    }
                    l.settled = l.rect;
                    l.moving = false;
                }
                l.visible = w.visible;
            } else {
                let mut l = Ledge::new(w.id, w.rect, self.u);
                l.visible = w.visible;
                self.ledges.push(l);
            }
        }
        let mut i = 0;
        while i < self.ledges.len() {
            if seen.contains(&self.ledges[i].id) {
                i += 1;
                continue;
            }
            let l = self.ledges.swap_remove(i);
            if l.has_snow {
                self.drop_snow(&l);
            }
        }
    }

    /// The window went away: its snow falls as clumps, straight down from where the window stood.
    fn drop_snow(&mut self, l: &Ledge) {
        let u = self.u;
        for i in 0..l.cols.len() {
            let h = l.cols[i] + l.hang[i];
            if h <= 0.5 * u {
                continue;
            }
            let n = ((h / (2.5 * u)) as usize + 1).min(4);
            for _ in 0..n {
                if self.clumps.len() >= 700 {
                    break;
                }
                let r = &mut self.rng;
                self.clumps.push(Clump {
                    x: l.settled.x + i as f32 * l.step + r.f() * l.step,
                    y: l.settled.y - r.f() * h,
                    vx: (r.f() - 0.5) * 6.0 * u,
                    vy: r.f() * 20.0 * u,
                    r: 1.6 + r.f() * 1.8,
                    dead: false,
                    bulk: true,
                });
            }
        }
        crate::log::debug(&format!("window {:#x} gone: {} clumps falling", l.id, self.clumps.len()));
    }

    /// When the snow hangs far down somewhere, or the pile is nearly full, there is about a 1-in-15 chance per
    /// second that a 20-50 pt stretch around the heaviest visible spot breaks off: the drape and most of the pile
    /// above it fall as clumps (softly tapered at the ends of the break), and the edge then fills up again.
    fn break_off(&mut self, li: usize, dt: f32, storm: bool, wind: f32) {
        let u = self.u;
        let n = self.ledges[li].cols.len();
        if n <= 8 || self.rng.f() >= dt / 15.0 {
            return;
        }
        let l = &self.ledges[li];
        let max_hang = l.hang.iter().cloned().fold(0.0, f32::max);
        let max_col = l.cols.iter().cloned().fold(0.0, f32::max);
        if !(max_hang > 9.0 * u || max_col > if storm { 12.5 } else { 9.0 } * u) {
            return;
        }
        let mut best = None;
        let mut best_load = 0.0;
        for i in 0..n {
            if !l.is_visible(l.settled.x + i as f32 * l.step) {
                continue;
            }
            let load = l.hang[i] + l.cols[i] * 0.5;
            if load > best_load {
                best_load = load;
                best = Some(i);
            }
        }
        let Some(best) = best else { return };
        let half = 2 + (self.rng.f() * 5.0) as usize; // 5-13 columns, about 20-50 pt
        for j in best.saturating_sub(half)..=(best + half).min(n - 1) {
            let l = &mut self.ledges[li];
            let x = l.settled.x + j as f32 * l.step;
            if !l.is_visible(x) {
                continue; // a part hidden behind a window in front stays put
            }
            let k = 1.0 - (j as f32 - best as f32).abs() / (half + 1) as f32; // 1 in the middle, tapering off
            let fall = 0.5 + 0.5 * ((1.0 - k) as f64 * std::f64::consts::PI).cos() as f32; // soft edges
            let (drop_pile, drop_hang) = (l.cols[j] * 0.65 * fall, l.hang[j] * fall);
            l.cols[j] -= drop_pile;
            l.hang[j] -= drop_hang;
            let (top, step) = (l.settled.y, l.step);
            let amount = drop_pile + drop_hang;
            if amount <= 0.4 * u {
                continue;
            }
            let count = ((amount / (2.5 * u)) as usize + 1).min(4);
            for _ in 0..count {
                if self.clumps.len() >= 700 {
                    break;
                }
                let r = &mut self.rng;
                self.clumps.push(Clump {
                    x: x + r.f() * step,
                    // from the pile's top down to the drape's end
                    y: top - drop_pile * r.f() + drop_hang * r.f(),
                    vx: ((r.f() - 0.5) * 8.0 + wind * 0.05) * u,
                    vy: r.f() * 15.0 * u,
                    r: 1.6 + r.f() * 2.0,
                    dead: false,
                    bulk: false,
                });
            }
        }
        crate::log::debug(&format!(
            "window {:#x}: snow broke off at column {best} ({} columns)",
            self.ledges[li].id,
            half * 2 + 1
        ));
    }

    /// Settles each pile (slopes, rounded ends, no higher than about 10 pt), melts it when snow is off, lets the
    /// snowstorm push it into drifts, grows the drape over the edge, and moves the falling clumps (`UpdateWindowSnow`).
    /// `melt`: snow or window snow is off. `bottom`: the lowest screen edge (clumps below it are gone).
    pub fn update(&mut self, dt: f32, melt: bool, storm: bool, wind: f32, bottom: f32) {
        let u = self.u;
        // in a snowstorm the wind pushes the snow along the edge, so it drifts up against the downwind end
        let storm = storm && !melt;
        let wind_norm = (wind / 140.0).clamp(-1.5, 1.5);
        let (max_h, slope) = (if storm { 14.0 } else { 10.0 } * u, 1.4 * u);
        for li in 0..self.ledges.len() {
            let l = &mut self.ledges[li];
            if !l.has_snow {
                continue;
            }
            let mut any = false;
            let n = l.cols.len();
            if storm && wind_norm.abs() > 0.15 && n > 2 {
                let rate = 0.03 * wind_norm.abs() * dt;
                let moved: Vec<f32> = l.cols.iter().map(|c| c * rate).collect();
                for (i, m) in moved.iter().enumerate() {
                    let j = if wind_norm > 0.0 { i + 1 } else { i.wrapping_sub(1) };
                    if j >= n {
                        continue; // the end column keeps what reaches it: the drift
                    }
                    l.cols[i] -= m;
                    l.cols[j] += m;
                }
            }
            for i in 0..n.saturating_sub(1) {
                let d = l.cols[i] - l.cols[i + 1];
                if d > slope {
                    let m = (d - slope) * 0.3;
                    l.cols[i] -= m;
                    l.cols[i + 1] += m;
                } else if d < -slope {
                    let m = (-d - slope) * 0.3;
                    l.cols[i] += m;
                    l.cols[i + 1] -= m;
                }
            }
            for i in 0..n {
                let edge = i.min(n - 1 - i) as f32 * l.step;
                // snow rounds off toward the window's corners; in a storm the downwind end builds a steeper drift
                let downwind = storm && ((wind_norm > 0.15 && i > n / 2) || (wind_norm < -0.15 && i < n / 2));
                // a full pile keeps soft bumps on top: the height limit itself wavers along the edge
                let bumps = 0.72
                    + 0.28
                        * ((i as f64 * 0.41 + (l.id % 53) as f64).sin() * 0.6
                            + (i as f64 * 0.97 + (l.id % 31) as f64).sin() * 0.4) as f32;
                let cap = (max_h * bumps)
                    .min((edge - if downwind { 2.0 } else { 6.0 } * u).max(0.0) * if downwind { 1.0 } else { 0.5 });
                if melt {
                    l.cols[i] = (l.cols[i] - 3.0 * u * dt).max(0.0);
                }
                // above the cap it settles back slowly (a drift sinks after the storm instead of being cut off)
                if l.cols[i] > cap {
                    l.cols[i] = cap.max(l.cols[i] - (2.0 * u * dt).max(l.cols[i] - cap - 6.0 * u));
                }
                if l.cols[i] > 0.3 * u {
                    any = true;
                }
            }
            // the drape: once the pile is deeper than about 3 pt it creeps over the edge (about 0.7 pt/s), as far as
            // the lobes allow, a bit further near the corners where the snow rounds over; it melts back quicker
            for i in 0..n {
                let (a, b) = (i.saturating_sub(3), (i + 3).min(n - 1));
                let pile = l.cols[a..=b].iter().sum::<f32>() / (b - a + 1) as f32;
                let edge = i.min(n - 1 - i) as f32 * l.step;
                let corner = if edge < 24.0 * u { 1.0 + (24.0 * u - edge) / (24.0 * u) * 0.6 } else { 1.0 };
                let target =
                    if melt { 0.0 } else { (pile - 3.0 * u).max(0.0) * 2.6 * (0.12 + 0.88 * l.lobes[i]) * corner };
                let old = l.hang[i];
                l.hang[i] = if target > old { target.min(old + 0.7 * u * dt) } else { target.max(old - 3.0 * u * dt) };
                if l.hang[i] > 0.3 * u {
                    any = true;
                }
            }
            let moving = l.moving;
            // a full edge does not just keep growing: now and then a heavy stretch breaks off and falls
            if !melt && any && !moving {
                self.break_off(li, dt, storm, wind);
            }
            self.ledges[li].has_snow = any;
        }

        for c in &mut self.clumps {
            c.vy += 700.0 * u * dt;
            c.x += c.vx * dt;
            c.y += c.vy * dt;
        }
        self.clumps.retain(|c| !c.dead && c.y <= bottom + 50.0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn win(id: u32, x: i32, y: i32, w: i32, h: i32) -> ClientWindow {
        ClientWindow { id, rect: Rect::new(x, y, w, h), shown: true, maximized: false }
    }

    #[test]
    fn windows_in_front_hide_the_edge_behind_them() {
        let screens = [Rect::new(0, 0, 1920, 1080)];
        // front to back: a small window over the middle of the back window's top edge
        let wins = [win(2, 700, 150, 400, 300), win(1, 200, 200, 1200, 600)];
        let found = scan(&wins, &screens, 1.0);
        assert_eq!(found.len(), 2);
        let back = &found[1];
        assert_eq!(back.id, 1);
        assert_eq!(back.visible, vec![(206.0, 700.0), (1100.0, 1394.0)]);
    }

    #[test]
    fn maximized_fullscreen_small_and_hidden_windows_carry_no_snow() {
        let screens = [Rect::new(0, 0, 1920, 1080), Rect::new(1920, 0, 1920, 1080)];
        let mut maximized = win(1, 0, 40, 1920, 1000);
        maximized.maximized = true;
        let full = win(2, 1920, 0, 1920, 1080);
        let small = win(3, 300, 300, 100, 60);
        let mut minimized = win(4, 300, 300, 800, 600);
        minimized.shown = false;
        assert!(scan(&[maximized, full, small, minimized], &screens, 1.0).is_empty());
        // but a maximized window still hides a window behind it
        let mut maximized = win(1, 0, 40, 1920, 1000);
        maximized.maximized = true;
        let behind = win(5, 100, 100, 800, 600);
        let found = scan(&[maximized, behind], &screens, 1.0);
        assert_eq!(found.len(), 1);
        assert!(found[0].visible.is_empty());
    }

    #[test]
    fn snow_falls_when_the_window_goes_and_follows_a_moved_window() {
        let mut ws = WindowSnow::new(1.0, 3);
        let info =
            |id, x| WinInfo { id, rect: FRect { x, y: 300.0, w: 600.0, h: 400.0 }, visible: vec![(x, x + 600.0)] };
        ws.update_ledges(vec![info(1, 100.0)]);
        for k in 0..400 {
            ws.ledges[0].deposit(120.0 + (k % 140) as f32 * 4.0, 3.0);
            ws.update(0.05, false, false, 0.0, 1080.0);
        }
        assert!(ws.ledges[0].has_snow);
        assert!(ws.ledges[0].cols.iter().cloned().fold(0.0, f32::max) <= 14.0 + 6.0);
        // dragged: hidden while moving, then settles at the new place with its snow
        ws.update_ledges(vec![info(1, 500.0)]);
        assert!(ws.ledges[0].moving);
        ws.update_ledges(vec![info(1, 500.0)]);
        assert!(!ws.ledges[0].moving && ws.ledges[0].settled.x == 500.0 && ws.ledges[0].has_snow);
        // closed: the snow falls as clumps (boosting the frame rate), and they leave below the screen
        ws.update_ledges(vec![]);
        assert!(ws.ledges.is_empty() && !ws.clumps.is_empty());
        assert!(ws.busy());
        for _ in 0..200 {
            ws.update(0.05, false, false, 0.0, 1080.0);
        }
        assert!(ws.clumps.is_empty() && !ws.busy());
    }

    #[test]
    fn breaking_off_does_not_boost_the_frame_rate() {
        let mut ws = WindowSnow::new(1.0, 9);
        let info = WinInfo { id: 7, rect: FRect { x: 0.0, y: 300.0, w: 800.0, h: 400.0 }, visible: vec![(0.0, 800.0)] };
        ws.update_ledges(vec![info]);
        // a deep, full edge: within a minute or so a stretch breaks off
        let mut broke = false;
        for k in 0..4000 {
            ws.ledges[0].deposit(20.0 + (k % 190) as f32 * 4.0, 4.0);
            ws.update(0.05, false, true, 0.0, 1080.0);
            if !ws.clumps.is_empty() {
                broke = true;
                assert!(!ws.busy(), "break-off clumps boosted the frame rate");
            }
        }
        assert!(broke, "nothing broke off");
    }
}
