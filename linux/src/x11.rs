//! Everything that talks to the X server: monitors, the transparent click-through overlay windows, and pushing
//! changed pixels to them. On Ubuntu's Wayland desktop this runs through XWayland.
//!
//! The overlay windows correspond to the `WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST` forms in `src/Layer.cs`:
//! - a 32-bit ARGB visual, so the compositor blends them with alpha (needs a running compositor);
//! - `override_redirect`, so the window manager neither decorates them nor lists them in the taskbar or alt-tab,
//!   and they are raised again when an app window has come above them (checked every 2 seconds, like
//!   `KeepOnTop()`), but never above menus and other popups (`needs_raise`);
//! - an empty input shape (XFixes), so every click goes through to the windows below.
//!
//! Pixels reach the window through MIT-SHM where possible: each screen is drawn straight into a shared memory
//! segment, and a frame sends one tiny `ShmPutImage` per changed rectangle. Plain `PutImage` (every pixel copied
//! through the socket) is the fallback, e.g. for a remote display; in a snowstorm it cost several times more.
//!
//! The calendar is an ordinary managed window (`create_app_window`): drawn with Cairo into memory and sent with
//! `PutImage` in the root window's visual, on the same connection, so its events arrive in the main loop.
//!
//! It also reads what the snow needs to know about the desktop: where each monitor's bottom panel starts, whether
//! the active window is fullscreen, and whether the display is switched off (DPMS).

use x11rb::connection::{Connection, RequestConnection};
use x11rb::protocol::dpms::{self, ConnectionExt as _};
use x11rb::protocol::randr::{self, ConnectionExt as _};
use x11rb::protocol::shape;
use x11rb::protocol::shm::{self, ConnectionExt as _};
use x11rb::protocol::xfixes::ConnectionExt as _;
use x11rb::protocol::xproto::{
    AtomEnum, ChangeWindowAttributesAux, ColormapAlloc, ConfigureWindowAux, ConnectionExt as _, CreateGCAux,
    CreateWindowAux, EventMask, ImageFormat, ImageOrder, PropMode, StackMode, VisualClass, Window, WindowClass,
};
use x11rb::protocol::Event;
use x11rb::rust_connection::RustConnection;
use x11rb::wrapper::ConnectionExt as _;

pub type Res<T> = Result<T, Box<dyn std::error::Error>>;

/// A rectangle in pixels. `w` and `h` are never negative after `clip`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
}

impl Rect {
    pub fn new(x: i32, y: i32, w: i32, h: i32) -> Self {
        Rect { x, y, w, h }
    }
    pub fn right(&self) -> i32 {
        self.x + self.w
    }
    pub fn bottom(&self) -> i32 {
        self.y + self.h
    }
    pub fn is_empty(&self) -> bool {
        self.w <= 0 || self.h <= 0
    }
    pub fn area(&self) -> i64 {
        if self.is_empty() {
            0
        } else {
            self.w as i64 * self.h as i64
        }
    }
    /// The smallest rectangle around both.
    pub fn union(a: &Rect, b: &Rect) -> Rect {
        let (x, y) = (a.x.min(b.x), a.y.min(b.y));
        Rect::new(x, y, a.right().max(b.right()) - x, a.bottom().max(b.bottom()) - y)
    }
    /// True when `o` lies completely inside `self`.
    pub fn contains(&self, o: &Rect) -> bool {
        o.x >= self.x && o.y >= self.y && o.right() <= self.right() && o.bottom() <= self.bottom()
    }
    /// The part of `self` inside a `w` x `h` surface.
    pub fn clip(&self, w: i32, h: i32) -> Rect {
        let x0 = self.x.max(0);
        let y0 = self.y.max(0);
        let x1 = self.right().min(w);
        let y1 = self.bottom().min(h);
        Rect { x: x0, y: y0, w: (x1 - x0).max(0), h: (y1 - y0).max(0) }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Monitor {
    /// In global (root window) coordinates.
    pub rect: Rect,
    pub primary: bool,
    pub name: String,
}

x11rb::atom_manager! {
    pub Atoms: AtomsCookie {
        _NET_WM_NAME,
        _NET_WM_WINDOW_TYPE,
        _NET_WM_WINDOW_TYPE_NOTIFICATION,
        _NET_WM_BYPASS_COMPOSITOR,
        _NET_WM_WINDOW_TYPE_DESKTOP,
        _NET_WM_WINDOW_TYPE_DOCK,
        _NET_WM_STATE,
        _NET_WM_STATE_FULLSCREEN,
        _NET_WM_STATE_MAXIMIZED_VERT,
        _NET_WM_STATE_MAXIMIZED_HORZ,
        _NET_WM_STRUT,
        _NET_WM_STRUT_PARTIAL,
        _NET_ACTIVE_WINDOW,
        _NET_CLIENT_LIST,
        _NET_CURRENT_DESKTOP,
        _GTK_FRAME_EXTENTS,
        _NET_WM_ICON,
        _NET_WM_PID,
        _NET_WM_DESKTOP,
        _NET_WM_STATE_HIDDEN,
        _NET_WM_STATE_SKIP_TASKBAR,
        _NET_WM_WINDOW_TYPE_DIALOG,
        _NET_FRAME_EXTENTS,
        _NET_CLIENT_LIST_STACKING,
        _NET_WM_WINDOW_TYPE_NORMAL,
        WM_PROTOCOLS,
        WM_DELETE_WINDOW,
        UTF8_STRING,
    }
}

/// One overlay window (one per monitor).
pub struct OverlayWindow {
    pub win: Window,
    gc: u32,
    /// The MIT-SHM segment the X server reads this window's pixels from.
    shm_seg: Option<shm::Seg>,
}

/// A screen's pixels in a System V shared memory segment that the X server has attached as well. The segment is
/// already marked for removal, so the kernel frees it when both sides have let go, also after a crash.
pub struct ShmBuffer {
    ptr: *mut u32,
    len: usize,
}

impl ShmBuffer {
    fn new(len: usize) -> Option<(ShmBuffer, i32)> {
        // SAFETY: plain System V calls; the pointer is checked before use and only used for `len` values.
        unsafe {
            let id = libc::shmget(libc::IPC_PRIVATE, len * 4, libc::IPC_CREAT | 0o600);
            if id < 0 {
                return None;
            }
            let ptr = libc::shmat(id, std::ptr::null(), 0);
            if ptr as isize == -1 {
                libc::shmctl(id, libc::IPC_RMID, std::ptr::null_mut());
                return None;
            }
            Some((ShmBuffer { ptr: ptr as *mut u32, len }, id))
        }
    }
}

impl std::ops::Deref for ShmBuffer {
    type Target = [u32];
    fn deref(&self) -> &[u32] {
        // SAFETY: the segment is mapped for `len` u32 values until drop.
        unsafe { std::slice::from_raw_parts(self.ptr, self.len) }
    }
}

impl std::ops::DerefMut for ShmBuffer {
    fn deref_mut(&mut self) -> &mut [u32] {
        // SAFETY: as above, and `&mut self` makes this the only access from this process.
        unsafe { std::slice::from_raw_parts_mut(self.ptr, self.len) }
    }
}

impl Drop for ShmBuffer {
    fn drop(&mut self) {
        // SAFETY: the pointer came from shmat and is detached once.
        unsafe {
            libc::shmdt(self.ptr as *const libc::c_void);
        }
    }
}

pub struct Display {
    pub conn: RustConnection,
    pub root: Window,
    screen_w: i32,
    screen_h: i32,
    /// The 32-bit TrueColor (ARGB) visual, if the server has one.
    argb_visual: Option<(u32, u32)>, // (visual id, colormap)
    lsb_first: bool,
    max_request_bytes: usize,
    atoms: Atoms,
    cm_atom: u32,
    randr_monitors: bool,
    has_dpms: bool,
    /// MIT-SHM can be used: the extension is there and the server stores pixels in this machine's byte order.
    use_shm: bool,
    /// Xft.dpi / 96 (or JULE_SCALE), at least 1.
    pub dpi_scale: f32,
    scratch: Vec<u8>,
    /// The root window's depth and visual, for ordinary windows (the calendar); only usable when the server
    /// stores that depth as 32 bits per pixel, as every current server does for depth 24.
    root_depth: u8,
    root_visual: u32,
    root_32bpp: bool,
    /// Keycodes that produce Escape (closes the calendar), and the hand and arrow cursors.
    escape_keys: Vec<u8>,
    cursors: Option<(u32, u32)>,
}

/// An ordinary window (the calendar) and the graphics context to draw into it.
pub struct AppWindow {
    pub win: Window,
    gc: u32,
}

impl AppWindow {
    /// No window: for drawing the calendar into a file (`--calendar-snapshot`).
    pub fn none() -> AppWindow {
        AppWindow { win: x11rb::NONE, gc: x11rb::NONE }
    }
}

impl Display {
    pub fn open() -> Res<Display> {
        let (conn, screen_num) = x11rb::connect(None)?;
        let (root, screen_w, screen_h, argb_visual_id) = {
            let screen = &conn.setup().roots[screen_num];
            let mut visual = None;
            for d in screen.allowed_depths.iter().filter(|d| d.depth == 32) {
                if let Some(v) = d.visuals.iter().find(|v| v.class == VisualClass::TRUE_COLOR) {
                    visual = Some(v.visual_id);
                    break;
                }
            }
            (screen.root, screen.width_in_pixels as i32, screen.height_in_pixels as i32, visual)
        };
        let lsb_first = conn.setup().image_byte_order == ImageOrder::LSB_FIRST;
        let (root_depth, root_visual) = {
            let screen = &conn.setup().roots[screen_num];
            (screen.root_depth, screen.root_visual)
        };
        let root_32bpp = conn.setup().pixmap_formats.iter().any(|f| f.depth == root_depth && f.bits_per_pixel == 32);
        let escape_keys = escape_keycodes(&conn);
        let cursors = hand_and_arrow_cursors(&conn);

        let atoms = Atoms::new(&conn)?.reply()?;
        let cm_atom = conn.intern_atom(false, format!("_NET_WM_CM_S{screen_num}").as_bytes())?.reply()?.atom;

        // XFixes must be told which version we speak before its requests can be used (input shapes).
        conn.xfixes_query_version(5, 0)?.reply()?;
        let randr_monitors = match conn.randr_query_version(1, 5) {
            Ok(c) => c.reply().map(|r| r.major_version > 1 || r.minor_version >= 5).unwrap_or(false),
            Err(_) => false,
        };
        if randr_monitors {
            let mask =
                randr::NotifyMask::SCREEN_CHANGE | randr::NotifyMask::CRTC_CHANGE | randr::NotifyMask::OUTPUT_CHANGE;
            conn.randr_select_input(root, mask)?;
        }

        let argb_visual = match argb_visual_id {
            Some(v) => {
                let cmap = conn.generate_id()?;
                conn.create_colormap(ColormapAlloc::NONE, cmap, root, v)?;
                Some((v, cmap))
            }
            None => None,
        };

        let has_dpms = conn.extension_information(dpms::X11_EXTENSION_NAME).ok().flatten().is_some();
        let use_shm = lsb_first == cfg!(target_endian = "little")
            && std::env::var("JULE_NO_SHM").is_err()
            && conn.extension_information(shm::X11_EXTENSION_NAME).ok().flatten().is_some()
            && conn.shm_query_version().ok().and_then(|c| c.reply().ok()).is_some();
        let max_request_bytes = conn.maximum_request_bytes();
        let dpi_scale = read_dpi_scale(&conn, root);
        conn.flush()?;
        crate::log::debug(&format!(
            "X11: screen {screen_w}x{screen_h}, argb visual {:?}, randr 1.5 {randr_monitors}, dpms {has_dpms}, shm {use_shm}, lsb {lsb_first}, max request {max_request_bytes} bytes, scale {dpi_scale}",
            argb_visual_id
        ));
        Ok(Display {
            conn,
            root,
            screen_w,
            screen_h,
            argb_visual,
            lsb_first,
            max_request_bytes,
            atoms,
            cm_atom,
            randr_monitors,
            has_dpms,
            use_shm,
            dpi_scale,
            scratch: Vec::new(),
            root_depth,
            root_visual,
            root_32bpp,
            escape_keys,
            cursors,
        })
    }

    /// True when a compositing manager runs (it owns `_NET_WM_CM_S<n>`) and the server has an ARGB visual.
    /// Without both, a 32-bit window shows black instead of being see-through.
    pub fn can_overlay(&self) -> bool {
        self.argb_visual.is_some() && self.has_compositor()
    }

    pub fn has_compositor(&self) -> bool {
        match self.conn.get_selection_owner(self.cm_atom) {
            Ok(c) => c.reply().map(|r| r.owner != x11rb::NONE).unwrap_or(false),
            Err(_) => false,
        }
    }

    /// The monitors in global coordinates (RandR 1.5), or the whole screen as one monitor.
    pub fn monitors(&self) -> Vec<Monitor> {
        let mut out = Vec::new();
        if self.randr_monitors {
            if let Ok(reply) = self
                .conn
                .randr_get_monitors(self.root, true)
                .map_err(|e| e.to_string())
                .and_then(|c| c.reply().map_err(|e| e.to_string()))
            {
                for m in reply.monitors {
                    if m.width == 0 || m.height == 0 {
                        continue;
                    }
                    let name = self
                        .conn
                        .get_atom_name(m.name)
                        .ok()
                        .and_then(|c| c.reply().ok())
                        .map(|r| String::from_utf8_lossy(&r.name).into_owned())
                        .unwrap_or_default();
                    out.push(Monitor {
                        rect: Rect::new(m.x as i32, m.y as i32, m.width as i32, m.height as i32),
                        primary: m.primary,
                        name,
                    });
                }
            }
        }
        if out.is_empty() {
            out.push(Monitor {
                rect: Rect::new(0, 0, self.screen_w, self.screen_h),
                primary: true,
                name: "screen".into(),
            });
        }
        if !out.iter().any(|m| m.primary) {
            out[0].primary = true;
        }
        out
    }

    /// Shared memory for a `w` x `h` screen, attached by the X server; None when MIT-SHM cannot be used (then the
    /// screen draws into ordinary memory and `put` copies the pixels through the socket).
    pub fn shm_buffer(&self, w: i32, h: i32) -> Option<(ShmBuffer, shm::Seg)> {
        if !self.use_shm {
            return None;
        }
        let (buf, id) = ShmBuffer::new(w as usize * h as usize)?;
        let seg = self.conn.generate_id().ok()?;
        // checked, so a server that cannot attach it (e.g. over the network) is noticed here
        let attached = self.conn.shm_attach(seg, id as u32, true).ok().map(|c| c.check().is_ok()).unwrap_or(false);
        // SAFETY: removing the id only stops new attachments; both mappings stay valid until they detach.
        unsafe {
            libc::shmctl(id, libc::IPC_RMID, std::ptr::null_mut());
        }
        if !attached {
            crate::log::debug("MIT-SHM attach failed: sending pixels through the socket");
            return None;
        }
        Some((buf, seg))
    }

    /// Creates and shows a transparent, click-through, always-on-top window covering `r` (global coordinates).
    /// `shm_seg` is the segment from `shm_buffer` that holds this window's pixels, if any.
    pub fn create_overlay(&self, r: Rect, shm_seg: Option<shm::Seg>) -> Res<OverlayWindow> {
        let (visual, colormap) = self.argb_visual.ok_or("no 32-bit visual")?;
        let win = self.conn.generate_id()?;
        // border_pixel and colormap are required when the visual differs from the root's (else BadMatch).
        let aux = CreateWindowAux::new()
            .background_pixel(0)
            .border_pixel(0)
            .colormap(colormap)
            .override_redirect(1)
            .event_mask(EventMask::EXPOSURE);
        self.conn.create_window(
            32,
            win,
            self.root,
            r.x as i16,
            r.y as i16,
            r.w as u16,
            r.h as u16,
            0,
            WindowClass::INPUT_OUTPUT,
            visual,
            &aux,
        )?;
        self.conn.change_property8(PropMode::REPLACE, win, AtomEnum::WM_NAME, AtomEnum::STRING, b"JuleHygge")?;
        self.conn.change_property8(
            PropMode::REPLACE,
            win,
            self.atoms._NET_WM_NAME,
            self.atoms.UTF8_STRING,
            b"JuleHygge",
        )?;
        self.conn.change_property8(
            PropMode::REPLACE,
            win,
            AtomEnum::WM_CLASS,
            AtomEnum::STRING,
            b"julehygge\0JuleHygge\0",
        )?;
        // Hints for compositors: a notification-like window, and never unredirect (2 = do not bypass compositing).
        self.conn.change_property32(
            PropMode::REPLACE,
            win,
            self.atoms._NET_WM_WINDOW_TYPE,
            AtomEnum::ATOM,
            &[self.atoms._NET_WM_WINDOW_TYPE_NOTIFICATION],
        )?;
        self.conn.change_property32(
            PropMode::REPLACE,
            win,
            self.atoms._NET_WM_BYPASS_COMPOSITOR,
            AtomEnum::CARDINAL,
            &[2],
        )?;

        // Empty input region: clicks, scrolling and hovering all reach the windows below.
        let region = self.conn.generate_id()?;
        self.conn.xfixes_create_region(region, &[])?;
        self.conn.xfixes_set_window_shape_region(win, shape::SK::INPUT, 0, 0, region)?;
        self.conn.xfixes_destroy_region(region)?;

        let gc = self.conn.generate_id()?;
        self.conn.create_gc(gc, win, &CreateGCAux::new().graphics_exposures(0))?;
        self.conn.map_window(win)?;
        self.conn.flush()?;
        Ok(OverlayWindow { win, gc, shm_seg })
    }

    pub fn destroy_overlay(&self, w: &OverlayWindow) {
        if let Some(seg) = w.shm_seg {
            let _ = self.conn.shm_detach(seg);
        }
        let _ = self.conn.free_gc(w.gc);
        let _ = self.conn.destroy_window(w.win);
        let _ = self.conn.flush();
    }

    /// Hides the window while a fullscreen app pauses the snow, and shows it again afterwards.
    pub fn set_mapped(&self, w: &OverlayWindow, mapped: bool) {
        let _ = if mapped { self.conn.map_window(w.win) } else { self.conn.unmap_window(w.win) };
    }

    /// True when a visible managed window (an app window in its frame) is stacked above any of the overlays, so
    /// they must be raised again. Windows the window manager does not manage (`override_redirect`: menus, the
    /// tray's popup menu, tooltips, the desktop's own popups) are left above the snow: raising over them would
    /// hide an open menu behind the snow a moment after it appears.
    pub fn needs_raise(&self, overlays: &[Window]) -> bool {
        let Some(tree) = self.conn.query_tree(self.root).ok().and_then(|c| c.reply().ok()) else { return true };
        // children are listed bottom to top; everything above the lowest overlay is a candidate
        let Some(lowest) = tree.children.iter().position(|w| overlays.contains(w)) else { return true };
        let above: Vec<Window> =
            tree.children[lowest + 1..].iter().copied().filter(|w| !overlays.contains(w)).collect();
        let cookies: Vec<_> = above.iter().map(|&w| self.conn.get_window_attributes(w).ok()).collect();
        cookies
            .into_iter()
            .flatten()
            .filter_map(|c| c.reply().ok())
            .any(|a| !a.override_redirect && a.map_state == x11rb::protocol::xproto::MapState::VIEWABLE)
    }

    /// Puts the window above all others again (the `KeepOnTop()` of `src/Layer.cs`).
    pub fn raise(&self, w: &OverlayWindow) {
        let _ = self.conn.configure_window(w.win, &ConfigureWindowAux::new().stack_mode(StackMode::ABOVE));
    }

    /// Sends the given rectangles of a premultiplied ARGB32 buffer (`stride` x `height` pixels) to the window.
    /// With shared memory each rectangle is one small request; otherwise it is split into bands of rows that fit
    /// in one request. After shared-memory puts, call `sync` before the buffer is drawn on again.
    pub fn put(&mut self, w: &OverlayWindow, pixels: &[u32], stride: usize, height: i32, rects: &[Rect]) -> Res<()> {
        if w.shm_seg.is_none() {
            return self.put_socket(w.win, w.gc, 32, pixels, stride, rects);
        }
        if let Some(seg) = w.shm_seg {
            for r in rects.iter().filter(|r| !r.is_empty()) {
                self.conn.shm_put_image(
                    w.win,
                    w.gc,
                    stride as u16,
                    height as u16,
                    r.x as u16,
                    r.y as u16,
                    r.w as u16,
                    r.h as u16,
                    r.x as i16,
                    r.y as i16,
                    32,
                    ImageFormat::Z_PIXMAP.into(),
                    false,
                    seg,
                    0,
                )?;
            }
        }
        Ok(())
    }

    /// Sends rectangles of a 32-bit-per-pixel buffer through the socket, in bands of rows that fit in a request.
    fn put_socket(
        &mut self,
        win: Window,
        gc: u32,
        depth: u8,
        pixels: &[u32],
        stride: usize,
        rects: &[Rect],
    ) -> Res<()> {
        for r in rects {
            if r.is_empty() {
                continue;
            }
            let row_bytes = r.w as usize * 4;
            // PutImage header is 24 bytes; keep a little room.
            let rows_per_req = ((self.max_request_bytes.saturating_sub(64)) / row_bytes).max(1);
            let mut y = r.y;
            while y < r.bottom() {
                let rows = (r.bottom() - y).min(rows_per_req as i32);
                self.scratch.clear();
                self.scratch.reserve(rows as usize * row_bytes);
                for yy in y..y + rows {
                    let start = yy as usize * stride + r.x as usize;
                    let row = &pixels[start..start + r.w as usize];
                    if self.lsb_first {
                        for p in row {
                            self.scratch.extend_from_slice(&p.to_le_bytes());
                        }
                    } else {
                        for p in row {
                            self.scratch.extend_from_slice(&p.to_be_bytes());
                        }
                    }
                }
                self.conn.put_image(
                    ImageFormat::Z_PIXMAP,
                    win,
                    gc,
                    r.w as u16,
                    rows as u16,
                    r.x as i16,
                    y as i16,
                    0,
                    depth,
                    &self.scratch,
                )?;
                y += rows;
            }
        }
        Ok(())
    }

    pub fn flush(&self) -> Res<()> {
        self.conn.flush()?;
        Ok(())
    }

    /// Waits until the X server has handled every request sent so far, so it has finished reading the shared
    /// memory of the last frame before the next one is drawn into it.
    pub fn sync(&self) -> Res<()> {
        self.conn.get_input_focus()?.reply()?;
        Ok(())
    }

    // ------------------------------------------------------------------ ordinary windows (the calendar)
    /// Creates and shows a fixed-size, decorated window of `w` x `h` pixels, centred on `on` (global coordinates),
    /// with a title, the app icon (`icon`: ARGB values of a `icon_size` square) and a close button that sends
    /// `WM_DELETE_WINDOW` instead of killing the connection.
    pub fn create_app_window(&self, title: &str, w: i32, h: i32, on: Rect, icon: &[(i32, Vec<u32>)]) -> Res<AppWindow> {
        if !self.root_32bpp {
            return Err("the X server does not store the root depth as 32 bits per pixel".into());
        }
        let a = &self.atoms;
        let win = self.conn.generate_id()?;
        let (x, y) = (on.x + (on.w - w) / 2, on.y + (on.h - h) / 2);
        let events = EventMask::EXPOSURE
            | EventMask::BUTTON_PRESS
            | EventMask::POINTER_MOTION
            | EventMask::KEY_PRESS
            | EventMask::STRUCTURE_NOTIFY;
        let aux = CreateWindowAux::new().background_pixel(0x0f2d1e).event_mask(events);
        self.conn.create_window(
            self.root_depth,
            win,
            self.root,
            x as i16,
            y as i16,
            w as u16,
            h as u16,
            0,
            WindowClass::INPUT_OUTPUT,
            self.root_visual,
            &aux,
        )?;
        self.conn.change_property8(PropMode::REPLACE, win, AtomEnum::WM_NAME, AtomEnum::STRING, title.as_bytes())?;
        self.conn.change_property8(PropMode::REPLACE, win, a._NET_WM_NAME, a.UTF8_STRING, title.as_bytes())?;
        self.conn.change_property8(
            PropMode::REPLACE,
            win,
            AtomEnum::WM_CLASS,
            AtomEnum::STRING,
            b"julehygge\0JuleHygge\0",
        )?;
        self.conn.change_property32(PropMode::REPLACE, win, a.WM_PROTOCOLS, AtomEnum::ATOM, &[a.WM_DELETE_WINDOW])?;
        self.conn.change_property32(
            PropMode::REPLACE,
            win,
            a._NET_WM_WINDOW_TYPE,
            AtomEnum::ATOM,
            &[a._NET_WM_WINDOW_TYPE_NORMAL],
        )?;
        self.conn.change_property32(
            PropMode::REPLACE,
            win,
            a._NET_WM_PID,
            AtomEnum::CARDINAL,
            &[std::process::id()],
        )?;
        let mut icon_data = Vec::new();
        for (size, argb) in icon {
            icon_data.extend_from_slice(&[*size as u32, *size as u32]);
            icon_data.extend_from_slice(argb);
        }
        self.conn.change_property32(PropMode::REPLACE, win, a._NET_WM_ICON, AtomEnum::CARDINAL, &icon_data)?;
        // fixed size at a chosen position (WM_NORMAL_HINTS: flags USPosition|PPosition|PMinSize|PMaxSize)
        let mut hints = [0u32; 18];
        hints[0] = 1 | 4 | 16 | 32;
        hints[1] = x as u32;
        hints[2] = y as u32;
        hints[5] = w as u32;
        hints[6] = h as u32;
        hints[7] = w as u32;
        hints[8] = h as u32;
        self.conn.change_property32(
            PropMode::REPLACE,
            win,
            AtomEnum::WM_NORMAL_HINTS,
            AtomEnum::WM_SIZE_HINTS,
            &hints,
        )?;
        let gc = self.conn.generate_id()?;
        self.conn.create_gc(gc, win, &CreateGCAux::new().graphics_exposures(0))?;
        self.conn.map_window(win)?;
        self.conn.flush()?;
        Ok(AppWindow { win, gc })
    }

    pub fn destroy_app_window(&self, w: &AppWindow) {
        let _ = self.conn.free_gc(w.gc);
        let _ = self.conn.destroy_window(w.win);
        let _ = self.conn.flush();
    }

    /// Sends rectangles of an opaque 32-bit buffer (`stride` pixels per row) to an ordinary window.
    pub fn put_app(&mut self, w: &AppWindow, pixels: &[u32], stride: usize, rects: &[Rect]) -> Res<()> {
        self.put_socket(w.win, w.gc, self.root_depth, pixels, stride, rects)
    }

    /// Brings the window to the front and gives it focus (asking the window manager, which may refuse focus
    /// stealing but then usually flashes it in the panel).
    pub fn activate(&self, w: &AppWindow) {
        let _ = self.conn.map_window(w.win);
        let ev = x11rb::protocol::xproto::ClientMessageEvent::new(
            32,
            w.win,
            self.atoms._NET_ACTIVE_WINDOW,
            [1u32, x11rb::CURRENT_TIME, 0, 0, 0],
        );
        let mask = EventMask::SUBSTRUCTURE_REDIRECT | EventMask::SUBSTRUCTURE_NOTIFY;
        let _ = self.conn.send_event(false, self.root, mask, ev);
        let _ = self.conn.flush();
    }

    /// The hand cursor over something clickable, the normal arrow elsewhere.
    pub fn set_hand_cursor(&self, w: &AppWindow, hand: bool) {
        if let Some((hand_c, arrow)) = self.cursors {
            let aux = ChangeWindowAttributesAux::new().cursor(if hand { hand_c } else { arrow });
            let _ = self.conn.change_window_attributes(w.win, &aux);
        }
    }

    /// True for a `WM_DELETE_WINDOW` message (the close button).
    pub fn is_close_request(&self, e: &x11rb::protocol::xproto::ClientMessageEvent) -> bool {
        e.type_ == self.atoms.WM_PROTOCOLS && e.data.as_data32()[0] == self.atoms.WM_DELETE_WINDOW
    }

    pub fn is_escape(&self, keycode: u8) -> bool {
        self.escape_keys.contains(&keycode)
    }

    // ------------------------------------------------------------------ the desktop
    /// 32-bit values of a window property (empty when it is missing).
    fn prop32(&self, win: Window, prop: u32, ty: impl Into<u32>, max: u32) -> Vec<u32> {
        self.conn
            .get_property(false, win, prop, ty, 0, max)
            .ok()
            .and_then(|c| c.reply().ok())
            .and_then(|r| r.value32().map(|v| v.collect()))
            .unwrap_or_default()
    }

    /// Where the snow lies on each monitor: the top of a panel along its bottom edge, in the monitor's own y, or
    /// None for the screen bottom.
    ///
    /// Mutter-based desktops (Cinnamon, GNOME on Xorg) draw their panels themselves, so there is no panel window to
    /// ask; they publish one work area per monitor in `_GTK_WORKAREAS_D<desktop>`. Other desktops (Xfce, MATE,
    /// KDE) have panel windows of type DOCK with `_NET_WM_STRUT_PARTIAL`. `_NET_WORKAREA` is one rectangle for all
    /// monitors together, so it cannot tell monitors with and without a panel apart.
    pub fn panel_tops(&self, monitors: &[Rect]) -> Vec<Option<i32>> {
        let desktop = self.prop32(self.root, self.atoms._NET_CURRENT_DESKTOP, AtomEnum::CARDINAL, 1);
        let name = format!("_GTK_WORKAREAS_D{}", desktop.first().copied().unwrap_or(0));
        let areas: Vec<Rect> = self
            .conn
            .intern_atom(true, name.as_bytes())
            .ok()
            .and_then(|c| c.reply().ok())
            .filter(|r| r.atom != x11rb::NONE)
            .map(|r| self.prop32(self.root, r.atom, AtomEnum::CARDINAL, 4 * 64))
            .unwrap_or_default()
            .as_chunks::<4>()
            .0
            .iter()
            .map(|v| Rect::new(v[0] as i32, v[1] as i32, v[2] as i32, v[3] as i32))
            .collect();
        if !areas.is_empty() {
            return monitors.iter().map(|m| panel_top_from_workareas(*m, &areas)).collect();
        }

        let mut tops: Vec<Option<i32>> = vec![None; monitors.len()];
        let clients = self.prop32(self.root, self.atoms._NET_CLIENT_LIST, AtomEnum::WINDOW, 4096);
        for w in clients {
            let ty = self.prop32(w, self.atoms._NET_WM_WINDOW_TYPE, AtomEnum::ATOM, 16);
            if !ty.contains(&self.atoms._NET_WM_WINDOW_TYPE_DOCK) {
                continue;
            }
            let mut strut = self.prop32(w, self.atoms._NET_WM_STRUT_PARTIAL, AtomEnum::CARDINAL, 12);
            if strut.len() < 12 {
                // the older form reserves the whole width
                strut = self.prop32(w, self.atoms._NET_WM_STRUT, AtomEnum::CARDINAL, 4);
                if strut.len() < 4 {
                    continue;
                }
                strut.resize(12, 0);
                strut[11] = self.screen_w.max(1) as u32 - 1;
            }
            if strut[3] == 0 {
                continue;
            }
            // the bottom strut is counted from the bottom of the whole X screen
            let top = self.screen_h - strut[3] as i32;
            let (x0, x1) = (strut[10] as i32, strut[11] as i32);
            for (r, t) in monitors.iter().zip(tops.iter_mut()) {
                if x0 < r.right() && x1 >= r.x && top > r.y + r.h / 2 && top < r.bottom() {
                    let local = top - r.y;
                    *t = Some(t.map_or(local, |v| v.min(local)));
                }
            }
        }
        tops
    }

    /// The active window in global coordinates, when it is fullscreen. A window counts when the window manager
    /// says so, or when it covers a monitor without being maximized (some games skip the hint). Maximized windows
    /// never count: on a monitor without a panel they also cover it.
    pub fn fullscreen_window(&self) -> Option<Rect> {
        let a = &self.atoms;
        let win = *self.prop32(self.root, a._NET_ACTIVE_WINDOW, AtomEnum::WINDOW, 1).first()?;
        if win == x11rb::NONE {
            return None;
        }
        let ty = self.prop32(win, a._NET_WM_WINDOW_TYPE, AtomEnum::ATOM, 16);
        if ty.contains(&a._NET_WM_WINDOW_TYPE_DESKTOP) || ty.contains(&a._NET_WM_WINDOW_TYPE_DOCK) {
            return None;
        }
        let geo = self.conn.get_geometry(win).ok()?.reply().ok()?;
        let pos = self.conn.translate_coordinates(win, self.root, 0, 0).ok()?.reply().ok()?;
        let mut r = Rect::new(pos.dst_x as i32, pos.dst_y as i32, geo.width as i32, geo.height as i32);
        // client-side decorations: the window includes an invisible shadow
        if let [left, right, top, bottom] = self.prop32(win, a._GTK_FRAME_EXTENTS, AtomEnum::CARDINAL, 4)[..] {
            r = Rect::new(
                r.x + left as i32,
                r.y + top as i32,
                r.w - (left + right) as i32,
                r.h - (top + bottom) as i32,
            );
        }
        let state = self.prop32(win, a._NET_WM_STATE, AtomEnum::ATOM, 32);
        if state.contains(&a._NET_WM_STATE_FULLSCREEN) {
            return Some(r);
        }
        let maximized =
            state.contains(&a._NET_WM_STATE_MAXIMIZED_VERT) && state.contains(&a._NET_WM_STATE_MAXIMIZED_HORZ);
        if !maximized && self.monitors().iter().any(|m| r.contains(&m.rect)) {
            return Some(r);
        }
        None
    }

    /// The managed windows, front to back, with their visible frames: what snow on windows needs to know
    /// (`ScanWindows` on Windows). A window "shown" is a normal app window (not a dialog, panel, desktop or
    /// taskbar-less helper), not minimized, on the current workspace (or on all), and not one of ours.
    ///
    /// The visible frame is the client area moved out by the window manager's decorations (`_NET_FRAME_EXTENTS`,
    /// the title bar) and in by a client-side decorated window's invisible shadow (`_GTK_FRAME_EXTENTS`). All
    /// requests are sent before the first reply is read, so a scan costs about one round trip.
    pub fn client_windows(&self) -> Vec<crate::window_snow::ClientWindow> {
        let a = &self.atoms;
        let stacking = self.prop32(self.root, a._NET_CLIENT_LIST_STACKING, AtomEnum::WINDOW, 4096);
        let desktop = self.prop32(self.root, a._NET_CURRENT_DESKTOP, AtomEnum::CARDINAL, 1).first().copied();
        let me = std::process::id();
        let get =
            |w: Window, prop: u32, ty: AtomEnum, len: u32| self.conn.get_property(false, w, prop, ty, 0, len).ok();
        // bottom-to-top in the list; the snow needs front to back
        let pending: Vec<_> = stacking
            .iter()
            .rev()
            .map(|&w| {
                (
                    w,
                    get(w, a._NET_WM_STATE, AtomEnum::ATOM, 32),
                    get(w, a._NET_WM_WINDOW_TYPE, AtomEnum::ATOM, 16),
                    get(w, a._NET_WM_DESKTOP, AtomEnum::CARDINAL, 1),
                    get(w, a._NET_WM_PID, AtomEnum::CARDINAL, 1),
                    get(w, a._NET_FRAME_EXTENTS, AtomEnum::CARDINAL, 4),
                    get(w, a._GTK_FRAME_EXTENTS, AtomEnum::CARDINAL, 4),
                    self.conn.get_geometry(w).ok(),
                    self.conn.translate_coordinates(w, self.root, 0, 0).ok(),
                )
            })
            .collect();
        let vals = |c: Option<x11rb::cookie::Cookie<'_, RustConnection, x11rb::protocol::xproto::GetPropertyReply>>| {
            c.and_then(|c| c.reply().ok())
                .and_then(|r| r.value32().map(|v| v.collect::<Vec<u32>>()))
                .unwrap_or_default()
        };
        let mut out = Vec::with_capacity(pending.len());
        for (w, state, ty, desk, pid, frame, gtk, geo, pos) in pending {
            let (state, ty, desk, pid, frame, gtk) =
                (vals(state), vals(ty), vals(desk), vals(pid), vals(frame), vals(gtk));
            let (Some(geo), Some(pos)) = (geo.and_then(|c| c.reply().ok()), pos.and_then(|c| c.reply().ok())) else {
                continue; // closed while we asked
            };
            let mut r = Rect::new(pos.dst_x as i32, pos.dst_y as i32, geo.width as i32, geo.height as i32);
            if let [l, rr, t, b] = gtk[..] {
                r = Rect::new(r.x + l as i32, r.y + t as i32, r.w - (l + rr) as i32, r.h - (t + b) as i32);
            }
            if let [l, rr, t, b] = frame[..] {
                r = Rect::new(r.x - l as i32, r.y - t as i32, r.w + (l + rr) as i32, r.h + (t + b) as i32);
            }
            let normal = ty.is_empty() || ty.contains(&a._NET_WM_WINDOW_TYPE_NORMAL);
            let on_this_desktop = match (desk.first(), desktop) {
                (Some(&d), Some(cur)) => d == cur || d == 0xFFFF_FFFF,
                _ => true,
            };
            let shown = normal
                && on_this_desktop
                && !state.contains(&a._NET_WM_STATE_HIDDEN)
                && !state.contains(&a._NET_WM_STATE_SKIP_TASKBAR)
                && pid.first() != Some(&me);
            let maximized =
                state.contains(&a._NET_WM_STATE_MAXIMIZED_VERT) && state.contains(&a._NET_WM_STATE_MAXIMIZED_HORZ);
            out.push(crate::window_snow::ClientWindow { id: w, rect: r, shown, maximized });
        }
        out
    }

    /// True when DPMS has switched the display off (standby, suspend or off).
    pub fn display_off(&self) -> bool {
        if !self.has_dpms {
            return false;
        }
        match self.conn.dpms_info().ok().and_then(|c| c.reply().ok()) {
            Some(info) => info.state && info.power_level != dpms::DPMSMode::ON,
            None => false,
        }
    }

    /// All events that have arrived, without waiting. An error here means the X server is gone.
    pub fn poll_events(&self) -> Res<Vec<Event>> {
        let mut v = Vec::new();
        while let Some(e) = self.conn.poll_for_event()? {
            v.push(e);
        }
        Ok(v)
    }
}

/// The keycodes that produce the Escape keysym in the current keyboard map.
fn escape_keycodes(conn: &RustConnection) -> Vec<u8> {
    const XK_ESCAPE: u32 = 0xff1b;
    let setup = conn.setup();
    let (min, max) = (setup.min_keycode, setup.max_keycode);
    let Some(map) = conn.get_keyboard_mapping(min, max - min + 1).ok().and_then(|c| c.reply().ok()) else {
        return vec![9]; // the usual keycode for Escape
    };
    let per = map.keysyms_per_keycode.max(1) as usize;
    map.keysyms
        .chunks(per)
        .enumerate()
        .filter(|(_, syms)| syms.contains(&XK_ESCAPE))
        .map(|(i, _)| min + i as u8)
        .collect()
}

/// The hand and arrow cursors from the standard cursor font.
fn hand_and_arrow_cursors(conn: &RustConnection) -> Option<(u32, u32)> {
    const XC_HAND2: u16 = 60;
    const XC_LEFT_PTR: u16 = 68;
    let font = conn.generate_id().ok()?;
    conn.open_font(font, b"cursor").ok()?;
    let make = |glyph: u16| -> Option<u32> {
        let c = conn.generate_id().ok()?;
        conn.create_glyph_cursor(c, font, font, glyph, glyph + 1, 0, 0, 0, 0xffff, 0xffff, 0xffff).ok()?;
        Some(c)
    };
    let cursors = (make(XC_HAND2)?, make(XC_LEFT_PTR)?);
    let _ = conn.close_font(font);
    Some(cursors)
}

/// The top of a panel along the bottom of monitor `m` (local y), from per-monitor work areas: the work area that
/// lies on the monitor, if it ends above the monitor's bottom edge.
fn panel_top_from_workareas(m: Rect, areas: &[Rect]) -> Option<i32> {
    let wa = areas.iter().find(|a| m.contains(a) && !a.is_empty())?;
    let gap = m.bottom() - wa.bottom();
    // a work area that ends in the upper half is not about a bottom panel
    (gap > 0 && wa.bottom() > m.y + m.h / 2).then(|| wa.bottom() - m.y)
}

/// The desktop's scale factor: `JULE_SCALE`, else `Xft.dpi / 96` from the X resources (set by GNOME and Cinnamon
/// for HiDPI), at least 1. X11 has no per-monitor scale.
fn read_dpi_scale(conn: &RustConnection, root: Window) -> f32 {
    if let Some(s) = std::env::var("JULE_SCALE").ok().and_then(|v| v.trim().parse::<f32>().ok()) {
        if s > 0.0 {
            return s.max(1.0);
        }
    }
    let prop = conn
        .get_property(false, root, AtomEnum::RESOURCE_MANAGER, AtomEnum::STRING, 0, 1 << 20)
        .ok()
        .and_then(|c| c.reply().ok());
    if let Some(p) = prop {
        let text = String::from_utf8_lossy(&p.value);
        if let Some(dpi) = parse_xft_dpi(&text) {
            return (dpi / 96.0).max(1.0);
        }
    }
    1.0
}

fn parse_xft_dpi(resources: &str) -> Option<f32> {
    resources.lines().find_map(|l| {
        let (k, v) = l.split_once(':')?;
        if k.trim() == "Xft.dpi" {
            v.trim().parse::<f32>().ok()
        } else {
            None
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clip_keeps_inside() {
        assert_eq!(Rect::new(-5, -5, 20, 20).clip(10, 10), Rect::new(0, 0, 10, 10));
        assert!(Rect::new(50, 0, 5, 5).clip(10, 10).is_empty());
        assert_eq!(Rect::new(2, 3, 4, 5).clip(100, 100), Rect::new(2, 3, 4, 5));
    }

    #[test]
    fn workareas_per_monitor() {
        // Linux Mint: two monitors side by side, a 100 px panel at the bottom of each (_GTK_WORKAREAS_D0)
        let areas = [Rect::new(6144, 0, 5120, 2780), Rect::new(0, 0, 6144, 3356)];
        assert_eq!(panel_top_from_workareas(Rect::new(0, 0, 6144, 3456), &areas), Some(3356));
        assert_eq!(panel_top_from_workareas(Rect::new(6144, 0, 5120, 2880), &areas), Some(2780));
        // a monitor whose panel is at the top or side keeps the snow at the screen bottom
        let top_panel = [Rect::new(0, 40, 1920, 1040)];
        assert_eq!(panel_top_from_workareas(Rect::new(0, 0, 1920, 1080), &top_panel), None);
        assert_eq!(panel_top_from_workareas(Rect::new(1920, 0, 1920, 1080), &top_panel), None);
    }

    #[test]
    fn xft_dpi() {
        assert_eq!(parse_xft_dpi("Xft.antialias:\t1\nXft.dpi:\t168\nXcursor.size:\t24\n"), Some(168.0));
        assert_eq!(parse_xft_dpi("Xcursor.size: 24"), None);
    }
}
