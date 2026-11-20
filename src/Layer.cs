using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace JuleHygge
{
    // Ét gennemsigtigt, klik-igennem overlay-vindue for én skærm.
    partial class Layer : Form
    {
        #region Win32
        const int WS_EX_LAYERED = 0x80000, WS_EX_TRANSPARENT = 0x20, WS_EX_TOOLWINDOW = 0x80,
                  WS_EX_NOACTIVATE = 0x8000000, WS_EX_TOPMOST = 0x8;

        [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; public POINT(int x, int y) { X = x; Y = y; } }
        [StructLayout(LayoutKind.Sequential)] struct SIZE { public int CX, CY; public SIZE(int a, int b) { CX = a; CY = b; } }
        [StructLayout(LayoutKind.Sequential, Pack = 1)] struct BLENDFUNCTION { public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat; }
        [StructLayout(LayoutKind.Sequential)]
        struct BITMAPINFOHEADER
        {
            public uint biSize; public int biWidth, biHeight; public ushort biPlanes, biBitCount;
            public uint biCompression, biSizeImage; public int biXPelsPerMeter, biYPelsPerMeter;
            public uint biClrUsed, biClrImportant;
        }

        [DllImport("user32.dll", SetLastError = true)]
        static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc, ref POINT pprSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);
        [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
        [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
        [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
        [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
        [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr o);
        [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr o);
        [DllImport("gdi32.dll")] static extern IntPtr CreateDIBSection(IntPtr hdc, ref BITMAPINFOHEADER bmi, uint usage, out IntPtr bits, IntPtr hSection, uint offset);
        [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
        [DllImport("msvcrt.dll", CallingConvention = CallingConvention.Cdecl)] static extern IntPtr memset(IntPtr dest, int c, UIntPtr count);

        [StructLayout(LayoutKind.Sequential)]
        struct UPDATELAYEREDWINDOWINFO
        {
            public uint cbSize;
            public IntPtr hdcDst, pptDst, psize, hdcSrc, pptSrc;
            public uint crKey;
            public IntPtr pblend;
            public uint dwFlags;
            public IntPtr prcDirty;
        }
        [DllImport("user32.dll", SetLastError = true)]
        static extern bool UpdateLayeredWindowIndirect(IntPtr hwnd, ref UPDATELAYEREDWINDOWINFO info);
        #endregion

        readonly Controller c;
        Settings cfg { get { return c.Cfg; } }
        readonly Random rnd;
        public readonly bool IsPrimary;
        public Rectangle ScreenBounds { get; private set; }
        public float S;
        public PointF SnowmanPos { get; private set; }
        int W, H;
        float groundY, dpiScale = 1f;
        // Top of the taskbar. The snow ground sits here, or at the screen bottom while a fullscreen app hides the taskbar.
        float taskbarY;

        IntPtr memDc, hDib, hOldBmp, pixels;
        Bitmap canvas;
        Graphics g;

        readonly List<Flake> flakes = new List<Flake>();
        float[] heap;
        const int HeapStep = 4;
        readonly List<Nisse> nisser = new List<Nisse>();
        Bitmap lightsBmp;
        float lightsTimer;
        bool paused;

        // områder der er tegnet på, så kun de skal ryddes næste frame
        List<Rectangle> dirty = new List<Rectangle>(), prevDirty = new List<Rectangle>();
        // Areas that changed on screen without needing a clear next frame (e.g. the cached lights strip).
        readonly List<Rectangle> presentOnly = new List<Rectangle>();
        bool fullPresent = true, lightsShown;
        // Unmanaged buffers for UpdateLayeredWindowIndirect (point, size, source point, blend, dirty rect).
        IntPtr ulwDst, ulwSize, ulwSrc, ulwBlend, ulwDirty;

        bool PS { get { return c.PowerSave; } }
        bool NisserOn { get { return cfg.Nisser; } }
        int LightsHeight { get { return (int)(70 * S); } }

        static readonly Color SantaRed = Color.FromArgb(205, 25, 35), Gold = Color.FromArgb(235, 195, 70),
            Skin = Color.FromArgb(255, 214, 186), Deer = Color.FromArgb(145, 95, 55), DeerDark = Color.FromArgb(100, 62, 32),
            HatRed = Color.FromArgb(210, 30, 40);
        readonly Pen[] flakePens = new Pen[16];

        public Layer(Controller controller, Screen scr)
        {
            c = controller;
            rnd = new Random(c.Rnd.Next());
            IsPrimary = scr.Primary;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            TopMost = true;
            Text = "JuleHygge";
            for (int i = 0; i < 16; i++) flakePens[i] = new Pen(Color.FromArgb(60 + i * 13, 255, 255, 255), 1.2f);
            InitSurface(scr);
        }

        protected override CreateParams CreateParams
        {
            get
            {
                var cp = base.CreateParams;
                cp.ExStyle |= WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST;
                return cp;
            }
        }
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override void OnPaintBackground(PaintEventArgs e) { }
        protected override void OnPaint(PaintEventArgs e) { }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            FreeSurface();
            if (lightsBmp != null) { lightsBmp.Dispose(); lightsBmp = null; }
            if (pileBmp != null) { pileBmp.Dispose(); pileBmp = null; }
            DisposeAutumn();
            foreach (var p in flakePens) p.Dispose();
            base.OnFormClosed(e);
        }

        public void KeepOnTop()
        {
            SetWindowPos(Handle, new IntPtr(-1), 0, 0, 0, 0, 0x1 | 0x2 | 0x10);
        }

        float Rnd() { return (float)rnd.NextDouble(); }

        void Mark(float x, float y, float w, float h)
        {
            dirty.Add(new Rectangle((int)Math.Floor(x) - 2, (int)Math.Floor(y) - 2, (int)Math.Ceiling(w) + 5, (int)Math.Ceiling(h) + 5));
        }

        // ------------------------------------------------------------------ tegneflade
        void InitSurface(Screen scr)
        {
            ScreenBounds = scr.Bounds;
            W = ScreenBounds.Width; H = ScreenBounds.Height;
            taskbarY = scr.WorkingArea.Bottom - ScreenBounds.Top;
            groundY = taskbarY;
            S = Math.Max(0.6f, H / 1080f);
            dpiScale = Math.Max(1f, Program.DpiScaleAt(ScreenBounds));

            var bih = new BITMAPINFOHEADER();
            bih.biSize = (uint)Marshal.SizeOf(typeof(BITMAPINFOHEADER));
            bih.biWidth = W; bih.biHeight = -H; bih.biPlanes = 1; bih.biBitCount = 32;
            IntPtr screenDc = GetDC(IntPtr.Zero);
            memDc = CreateCompatibleDC(screenDc);
            hDib = CreateDIBSection(screenDc, ref bih, 0, out pixels, IntPtr.Zero, 0);
            ReleaseDC(IntPtr.Zero, screenDc);
            hOldBmp = SelectObject(memDc, hDib);

            canvas = new Bitmap(W, H, W * 4, PixelFormat.Format32bppPArgb, pixels);
            g = Graphics.FromImage(canvas);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.CompositingQuality = CompositingQuality.HighSpeed;

            heap = new float[W / HeapStep + 2];
            // JULE_DEEPSNOW=1 starts with a full snow drift (for testing the snow plow).
            if (Environment.GetEnvironmentVariable("JULE_DEEPSNOW") == "1") for (int i = 0; i < heap.Length; i++) heap[i] = 18 * S;
            Bounds = ScreenBounds;

            ulwDst = Marshal.AllocHGlobal(8); ulwSize = Marshal.AllocHGlobal(8); ulwSrc = Marshal.AllocHGlobal(8);
            ulwBlend = Marshal.AllocHGlobal(4); ulwDirty = Marshal.AllocHGlobal(16);
            Marshal.WriteInt32(ulwDst, 0, ScreenBounds.X); Marshal.WriteInt32(ulwDst, 4, ScreenBounds.Y);
            Marshal.WriteInt32(ulwSize, 0, W); Marshal.WriteInt32(ulwSize, 4, H);
            Marshal.WriteInt32(ulwSrc, 0, 0); Marshal.WriteInt32(ulwSrc, 4, 0);
            // BLENDFUNCTION bytes: AC_SRC_OVER, 0, SourceConstantAlpha 255, AC_SRC_ALPHA
            Marshal.WriteByte(ulwBlend, 0, 0); Marshal.WriteByte(ulwBlend, 1, 0);
            Marshal.WriteByte(ulwBlend, 2, 255); Marshal.WriteByte(ulwBlend, 3, 1);
        }

        void FreeSurface()
        {
            if (g != null) { g.Dispose(); g = null; }
            if (canvas != null) { canvas.Dispose(); canvas = null; }
            if (memDc != IntPtr.Zero)
            {
                SelectObject(memDc, hOldBmp);
                DeleteObject(hDib);
                DeleteDC(memDc);
                memDc = IntPtr.Zero;
            }
            foreach (var p in new[] { ulwDst, ulwSize, ulwSrc, ulwBlend, ulwDirty })
                if (p != IntPtr.Zero) Marshal.FreeHGlobal(p);
            ulwDst = ulwSize = ulwSrc = ulwBlend = ulwDirty = IntPtr.Zero;
        }

        void Present()
        {
            g.Flush(FlushIntention.Sync);
            IntPtr screenDc = GetDC(IntPtr.Zero);
            var dst = new POINT(ScreenBounds.X, ScreenBounds.Y);
            var size = new SIZE(W, H);
            var src = new POINT(0, 0);
            var bf = new BLENDFUNCTION { BlendOp = 0, BlendFlags = 0, SourceConstantAlpha = 255, AlphaFormat = 1 };
            UpdateLayeredWindow(Handle, screenDc, ref dst, ref size, memDc, ref src, 0, ref bf, 2);
            ReleaseDC(IntPtr.Zero, screenDc);
            fullPresent = false;
        }

        // Pushes only the changed parts of the surface to the screen. The changed rectangles are merged
        // into at most three boxes (lights strip at the top, the sky, the band above the taskbar), each
        // sent with UpdateLayeredWindowIndirect's dirty rect so DWM only uploads those pixels.
        void PresentRegions(List<Rectangle> a, List<Rectangle> b, List<Rectangle> extra)
        {
            if (fullPresent) { Present(); return; }
            int topLimit = LightsHeight + 4;
            int bottomStart = (int)(groundY - 150 * S - 10);
            var boxes = new Rectangle[3];
            var has = new bool[3];
            foreach (var list in new[] { a, b, extra })
                foreach (var r0 in list)
                {
                    var r = Rectangle.Intersect(r0, new Rectangle(0, 0, W, H));
                    if (r.Width <= 0 || r.Height <= 0) continue;
                    int gi = r.Bottom <= topLimit ? 0 : (r.Top >= bottomStart ? 2 : 1);
                    boxes[gi] = has[gi] ? Rectangle.Union(boxes[gi], r) : r;
                    has[gi] = true;
                }

            long area = 0;
            for (int i = 0; i < 3; i++) if (has[i]) area += (long)boxes[i].Width * boxes[i].Height;
            if (area == 0) return;
            if (area > (long)W * H / 2) { Present(); return; }   // mostly everything changed: one full update is cheaper

            g.Flush(FlushIntention.Sync);
            IntPtr screenDc = GetDC(IntPtr.Zero);
            var info = new UPDATELAYEREDWINDOWINFO();
            info.cbSize = (uint)Marshal.SizeOf(typeof(UPDATELAYEREDWINDOWINFO));
            info.hdcDst = screenDc; info.pptDst = ulwDst; info.psize = ulwSize;
            info.hdcSrc = memDc; info.pptSrc = ulwSrc; info.pblend = ulwBlend;
            info.dwFlags = 2;  // ULW_ALPHA
            info.prcDirty = ulwDirty;
            bool ok = true;
            for (int i = 0; i < 3 && ok; i++)
            {
                if (!has[i]) continue;
                Marshal.WriteInt32(ulwDirty, 0, boxes[i].Left); Marshal.WriteInt32(ulwDirty, 4, boxes[i].Top);
                Marshal.WriteInt32(ulwDirty, 8, boxes[i].Right); Marshal.WriteInt32(ulwDirty, 12, boxes[i].Bottom);
                ok = UpdateLayeredWindowIndirect(Handle, ref info);
            }
            ReleaseDC(IntPtr.Zero, screenDc);
            if (!ok) Present();   // fall back to a full update if partial updates are not supported
        }

        void ClearAll()
        {
            g.Flush(FlushIntention.Sync);
            memset(pixels, 0, new UIntPtr((ulong)W * (ulong)H * 4));
        }

        unsafe void ClearRects(List<Rectangle> rects)
        {
            g.Flush(FlushIntention.Sync);
            uint* buf = (uint*)pixels.ToPointer();
            foreach (var r in rects)
            {
                int x0 = Math.Max(0, r.Left), x1 = Math.Min(W, r.Right);
                int y0 = Math.Max(0, r.Top), y1 = Math.Min(H, r.Bottom);
                if (x0 >= x1 || y0 >= y1) continue;
                int n = x1 - x0;
                for (int y = y0; y < y1; y++)
                {
                    uint* p = buf + (long)y * W + x0;
                    for (int i = 0; i < n; i++) p[i] = 0;
                }
            }
        }

        // ------------------------------------------------------------------ én frame
        public void Frame(float dt)
        {
            var fs = c.FullscreenRect;
            bool fullscreen = !fs.IsEmpty && fs.Contains(ScreenBounds);
            // With "pause on fullscreen" off, a fullscreen app hides the taskbar, so the snow piles up at the
            // very bottom of the screen instead (nisser, snowman and plow follow the ground automatically).
            groundY = fullscreen ? H : taskbarY;
            if (fullscreen && cfg.PauseFullscreen)
            {
                if (!paused) { ClearAll(); Present(); paused = true; prevDirty.Clear(); lightsShown = false; }
                return;
            }
            if (paused) { paused = false; fullPresent = true; }


            UpdateSnow(dt);
            UpdateRain(dt);
            UpdatePlow(dt);
            UpdateNisser(dt);

            // Clear what was drawn last frame. If that touched the lights strip, the strip must be redrawn.
            var cleared = prevDirty;
            ClearRects(cleared);
            var lightsRect = new Rectangle(0, 0, W, LightsHeight);
            bool lightsDamaged = false;
            foreach (var r in cleared) if (r.IntersectsWith(lightsRect)) { lightsDamaged = true; break; }

            presentOnly.Clear();
            // Snow on other windows sits on those windows, so the light string and everything that moves
            // (Santa, sparks, nisser) is drawn over it. In power-save mode the strip is not cleared every frame,
            // so clear it before the snow when the lights are drawn again (they are blended over the snow).
            bool lightsDraw = false;
            if (cfg.Lights)
            {
                lightsDraw = PrepareLights(dt, lightsDamaged);
                if (lightsDraw && PS) { ClearRects(new List<Rectangle> { lightsRect }); presentOnly.Add(lightsRect); }
            }
            else if (lightsShown) { Mark(0, 0, W, LightsHeight); lightsShown = false; }
            DrawLedges();
            if (lightsDraw) DrawLightsStrip();
            DrawSantaAndSparks();
            if (IsPrimary && cfg.Kite && c.Autumn) DrawKite(dt); else kiteSet = false;
            if (IsPrimary && cfg.Snowman) DrawSnowman(); else SnowmanPos = PointF.Empty;
            DrawGround();
            foreach (var n in nisser) DrawNisse(n);
            DrawPlow();
            DrawRain();   // behind the leaves
            DrawSnow();
            PresentRegions(cleared, dirty, presentOnly);

            cleared.Clear();
            prevDirty = dirty;
            dirty = cleared;
        }

        // ------------------------------------------------------------------ sne
        void UpdateSnow(float dt)
        {
            float[] baseCount = { 110f, 260f, 650f };
            // between two levels while the weather changes
            float amount = Math.Max(0f, Math.Min(2f, c.SnowAmount));
            int lower = Math.Min(1, (int)amount);
            float flakesWanted = baseCount[lower] + (baseCount[lower + 1] - baseCount[lower]) * (amount - lower);
            // (leaves are much bigger than flakes, so far fewer are needed)
            if (c.Autumn) flakesWanted *= 0.2f;
            float logicalArea = W * (float)H / (dpiScale * dpiScale);
            // Snow covers the whole screen also in power-save mode (like macOS); power-save only lowers the frame rate.
            // SnowIntensity makes the amount drift slowly between ~60% and ~140% of the chosen level.
            int target = c.SnowOn ? (int)(flakesWanted * Math.Min(2f, logicalArea / (1920f * 1080f)) * c.SnowIntensity) : 0;
            // nye fnug kommer ind fra toppen; overskydende fnug forsvinder først når de lander
            int add = flakes.Count == 0 ? target : Math.Max(1, target / 60);
            for (int i = 0; i < add && flakes.Count < target; i++) flakes.Add(NewFlake(flakes.Count == 0 || c.Time < 1f));

            float wind = c.Wind * S;
            float ox = ScreenBounds.X, oy = ScreenBounds.Y;
            bool ledges = cfg.WindowSnow && c.LedgeList.Count > 0;
            for (int i = flakes.Count - 1; i >= 0; i--)
            {
                var f = flakes[i];
                float prevY = f.Y;
                f.Y += f.Vy * dt;
                f.X += (wind * (0.4f + f.R / (4 * S)) + (float)Math.Cos(c.Time * f.SwaySpd + f.Phase) * f.Sway) * dt;
                f.Rot += f.RotSpd * dt;
                if (f.X < -60) f.X += W + 120; else if (f.X > W + 60) f.X -= W + 120;
                // some flakes land on a window's top edge (or the snow already on it)
                if (f.Catches && ledges)
                {
                    float gx = f.X + ox, gy = f.Y + oy, py = prevY + oy;
                    Ledge hit = null;
                    foreach (var l in c.LedgeList)
                    {
                        if (l.Moving) continue;
                        float top = l.Settled.Top - l.HeightAt(gx);
                        if (py < top && gy >= top && l.IsVisible(gx)) { hit = l; break; }
                    }
                    if (hit != null)
                    {
                        hit.Deposit(gx, f.R / S);
                        if (flakes.Count > target) flakes.RemoveAt(i);
                        else flakes[i] = NewFlake(false);
                        continue;
                    }
                }
                if (f.Y >= groundY - HeapAt(f.X))
                {
                    if (cfg.SnowGround) Deposit(f.X, f.R);
                    if (flakes.Count > target) flakes.RemoveAt(i);
                    else flakes[i] = NewFlake(false);
                }
            }

            // Snowstorm: the wind carries snow along the pile, so it drifts up against the downwind screen edge,
            // and flakes settle in long soft waves (the dune factor in Deposit). Drifts may grow taller and sink
            // back slowly afterwards.
            bool storm = c.EffectiveSnowLevel == 2 && c.SnowOn;
            float windNorm = Math.Max(-1.5f, Math.Min(1.5f, c.Wind / 140));
            if (storm && Math.Abs(windNorm) > 0.15f && heap.Length > 2)
            {
                float rate = 0.02f * Math.Abs(windNorm) * dt;
                int dir = windNorm > 0 ? 1 : -1;
                var moved = new float[heap.Length];
                for (int i = 0; i < heap.Length; i++) moved[i] = heap[i] * rate;
                for (int i = 0; i < heap.Length; i++)
                {
                    int j = i + dir;
                    if (j < 0 || j >= heap.Length) continue;
                    heap[i] -= moved[i]; heap[j] += moved[i];
                }
            }
            float maxH = (storm ? 30 : 18) * S, slope = 1.2f * S;
            for (int i = 0; i < heap.Length - 1; i++)
            {
                float d = heap[i] - heap[i + 1];
                if (d > slope) { float m = (d - slope) * 0.3f; heap[i] -= m; heap[i + 1] += m; }
                else if (d < -slope) { float m = (-d - slope) * 0.3f; heap[i] += m; heap[i + 1] -= m; }
            }
            // snow falling off a window that went away lands in the pile below
            foreach (var cl in c.Clumps)
            {
                if (cl.Dead) continue;
                float x = cl.X - ox, y = cl.Y - oy;
                if (x >= 0 && x < W && y >= 0 && y >= groundY - HeapAt(x))
                {
                    if (cfg.SnowGround) Deposit(x, cl.R * S);
                    cl.Dead = true;
                }
            }
            bool melt = !c.SnowOn || !cfg.SnowGround;
            for (int i = 0; i < heap.Length; i++)
            {
                if (melt) heap[i] = Math.Max(0, heap[i] - 3 * S * dt);
                // a full pile keeps soft bumps: the limit wavers along the screen (in global x, so screens line up),
                // and above it the snow sinks back slowly instead of being cut off
                double gxi = i * HeapStep + ox;
                float lim = maxH * (0.78f + 0.22f * (float)(0.6 * Math.Sin(gxi / (37 * dpiScale)) + 0.4 * Math.Sin(gxi / (13.7 * dpiScale))));
                if (heap[i] > lim) heap[i] = Math.Max(lim, heap[i] - 2 * S * dt);
            }
        }

        Flake NewFlake(bool anywhere)
        {
            var f = new Flake();
            float depth = Rnd();
            f.R = (1f + depth * depth * 3.5f) * S;
            f.Vy = (25f + depth * 55f + Rnd() * 15f) * S * (c.EffectiveSnowLevel == 2 ? 1.5f : 1f);
            f.X = rnd.Next(-50, W + 50);
            f.Y = anywhere ? Rnd() * groundY : -10 - Rnd() * 60;
            f.Phase = Rnd() * 6.28f;
            f.Sway = (8 + Rnd() * 20) * S;
            f.SwaySpd = 0.5f + Rnd() * 1.2f;
            f.A = (int)(110 + depth * 145);
            f.Crystal = depth > 0.8f && Rnd() < 0.5f;
            if (f.Crystal) f.R *= 1.6f;
            f.Rot = Rnd() * 6.28f;
            f.RotSpd = (Rnd() - 0.5f) * 2f;
            f.Catches = Rnd() < 0.5f;
            if (c.Autumn)
            {
                // a leaf: bigger, opaque, swaying wide and turning as it falls
                f.R = (5 + depth * 7) * S;
                f.Vy = (30 + depth * 40 + Rnd() * 20) * S * (c.EffectiveSnowLevel == 2 ? 1.4f : 1f);
                f.Sway = (25 + Rnd() * 45) * S;
                f.SwaySpd = 0.6f + Rnd() * 1.0f;
                f.A = (int)(215 + depth * 40);
                f.Crystal = false;
                f.RotSpd = (Rnd() - 0.5f) * 5;
                f.Kind = rnd.Next(LeafKinds);
            }
            return f;
        }

        // ------------------------------------------------------------------ efterår: blade
        // The autumn theme (Controller.Autumn) has leaves for snow, as the macOS version (Overlay.swift): two
        // kinds in five colours, a pointed oval and, one in five, a maple. Each is drawn once as a small picture
        // and then turned and scaled straight into the pixel buffer (BlendLeaf), as the flakes are (BlendDot).
        static readonly Color[] LeafColours = {
            Color.FromArgb(217, 84, 30), Color.FromArgb(232, 160, 32), Color.FromArgb(168, 67, 26),
            Color.FromArgb(201, 162, 39), Color.FromArgb(138, 59, 18) };
        // The dark between the leaves of a pile (the leaves themselves lie over it).
        static readonly Color PileFill = Color.FromArgb(245, 122, 62, 24);
        const int LeafPx = 64;
        // Four ovals for every maple in each colour, so any pick gives 80 % ovals.
        const int LeafKinds = 25;
        static int[][] leafSprites;   // premultiplied ARGB, LeafPx x LeafPx: per colour an oval, then a maple

        static int[] LeafSprite(int kind)
        {
            if (leafSprites == null) leafSprites = MakeLeafSprites();
            kind = ((kind % LeafKinds) + LeafKinds) % LeafKinds;
            return leafSprites[(kind / 5) * 2 + (kind % 5 == 4 ? 1 : 0)];
        }

        static int[][] MakeLeafSprites()
        {
            var all = new int[LeafColours.Length * 2][];
            float m = LeafPx / 2f;
            // The maple has the eleven points of a sugar maple: the tip, and on each side the top lobe's side
            // point, the side lobe's three points and the small bottom lobe. (Along the axis 0..1 from blade to
            // tip, and out from the axis in units of the leaf's length.)
            float[,] half = { { 0.14f, 0 }, { 0.17f, 0.26f }, { 0.24f, 0.22f }, { 0.30f, 0.44f }, { 0.34f, 0.40f }, { 0.46f, 0.50f },
                              { 0.50f, 0.42f }, { 0.60f, 0.44f }, { 0.50f, 0.17f }, { 0.74f, 0.22f }, { 0.72f, 0.12f }, { 1, 0 } };
            int n = half.GetLength(0);
            var maple = new PointF[2 * n - 2];
            for (int i = 0; i < n; i++) maple[i] = new PointF(12 + half[i, 0] * 51, m - half[i, 1] * 58);
            for (int i = n - 2; i >= 1; i--) maple[2 * n - 2 - i] = new PointF(maple[i].X, 2 * m - maple[i].Y);
            // The veins are faint and light. Dark ones made a small leaf read as a beetle seen from the side.
            using (var vein = new Pen(Color.FromArgb(70, 90, 44, 14), 2.5f))
            using (var side = new Pen(Color.FromArgb(50, 255, 236, 196), 1.5f))
            {
                vein.StartCap = LineCap.Round; vein.EndCap = LineCap.Round;
                for (int ci = 0; ci < LeafColours.Length; ci++)
                    for (int shape = 0; shape < 2; shape++)
                        using (var bmp = new Bitmap(LeafPx, LeafPx, PixelFormat.Format32bppPArgb))
                        {
                            using (var lg = Graphics.FromImage(bmp))
                            using (var fill = new SolidBrush(LeafColours[ci]))
                            {
                                lg.SmoothingMode = SmoothingMode.AntiAlias;
                                lg.Clear(Color.Transparent);
                                if (shape == 0)
                                {
                                    // stalk at the left, tip at the right; two curves through (34, 2) and (34, 62)
                                    using (var path = new GraphicsPath())
                                    {
                                        path.AddBezier(10, m, 26, m + (2 - m) * 2 / 3, 43.33f, m + (2 - m) * 2 / 3, 62, m);
                                        path.AddBezier(62, m, 43.33f, m + (62 - m) * 2 / 3, 26, m + (62 - m) * 2 / 3, 10, m);
                                        path.CloseFigure();
                                        lg.FillPath(fill, path);
                                    }
                                    lg.DrawLine(vein, 1, m, 56, m);
                                    lg.DrawLine(side, 26, m, 36, m - 12); lg.DrawLine(side, 26, m, 36, m + 12);
                                    lg.DrawLine(side, 40, m, 48, m - 9); lg.DrawLine(side, 40, m, 48, m + 9);
                                }
                                else
                                {
                                    lg.FillPolygon(fill, maple);
                                    lg.DrawLine(vein, 1, m, 58, m);
                                    lg.DrawLine(side, 21, m, 35, 6); lg.DrawLine(side, 21, m, 35, 58);
                                }
                            }
                            var px = new int[LeafPx * LeafPx];
                            var data = bmp.LockBits(new Rectangle(0, 0, LeafPx, LeafPx), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
                            Marshal.Copy(data.Scan0, px, 0, px.Length);
                            bmp.UnlockBits(data);
                            all[ci * 2 + shape] = px;
                        }
            }
            return all;
        }

        // One leaf, turned by rot and `size` pixels across, blended into a premultiplied pixel buffer (the
        // screen's, or a cached picture's). Each screen pixel is looked up in the leaf's picture, between its
        // four nearest points.
        static unsafe void BlendLeaf(uint* buf, int bw, int bh, int[] sprite, float cx, float cy, float size, float rot, int alpha)
        {
            if (size < 2) return;
            float reach = size * 0.7072f;
            int x0 = Math.Max(0, (int)(cx - reach)), x1 = Math.Min(bw - 1, (int)(cx + reach) + 1);
            int y0 = Math.Max(0, (int)(cy - reach)), y1 = Math.Min(bh - 1, (int)(cy + reach) + 1);
            if (x0 > x1 || y0 > y1) return;
            float k = LeafPx / size, mid = LeafPx * 0.5f - 0.5f;
            float cs = (float)Math.Cos(rot) * k, sn = (float)Math.Sin(rot) * k;
            fixed (int* sp = sprite)
            {
                for (int y = y0; y <= y1; y++)
                {
                    float dy = y + 0.5f - cy;
                    uint* row = buf + (long)y * bw;
                    for (int x = x0; x <= x1; x++)
                    {
                        float dx = x + 0.5f - cx;
                        float u = dx * cs + dy * sn + mid, v = dy * cs - dx * sn + mid;
                        if (u < 0 || v < 0 || u >= LeafPx - 1 || v >= LeafPx - 1) continue;
                        int iu = (int)u, iv = (int)v;
                        int* p = sp + iv * LeafPx + iu;
                        uint a = (uint)p[0], b = (uint)p[1], cc = (uint)p[LeafPx], d = (uint)p[LeafPx + 1];
                        if (((a | b | cc | d) >> 24) == 0) continue;
                        float fu = u - iu, fv = v - iv;
                        float wa = (1 - fu) * (1 - fv), wb = fu * (1 - fv), wc = (1 - fu) * fv, wd = fu * fv;
                        float f = alpha / 255f;
                        int sa = (int)((((a >> 24) & 0xFF) * wa + ((b >> 24) & 0xFF) * wb + ((cc >> 24) & 0xFF) * wc + ((d >> 24) & 0xFF) * wd) * f);
                        if (sa <= 0) continue;
                        int sr = (int)((((a >> 16) & 0xFF) * wa + ((b >> 16) & 0xFF) * wb + ((cc >> 16) & 0xFF) * wc + ((d >> 16) & 0xFF) * wd) * f);
                        int sg = (int)((((a >> 8) & 0xFF) * wa + ((b >> 8) & 0xFF) * wb + ((cc >> 8) & 0xFF) * wc + ((d >> 8) & 0xFF) * wd) * f);
                        int sb = (int)(((a & 0xFF) * wa + (b & 0xFF) * wb + (cc & 0xFF) * wc + (d & 0xFF) * wd) * f);
                        uint o = row[x];
                        int inv = 255 - sa;
                        uint da = (uint)(sa + (((o >> 24) & 0xFF) * inv) / 255);
                        uint dr = (uint)(sr + (((o >> 16) & 0xFF) * inv) / 255);
                        uint dg = (uint)(sg + (((o >> 8) & 0xFF) * inv) / 255);
                        uint db = (uint)(sb + ((o & 0xFF) * inv) / 255);
                        row[x] = (da << 24) | (dr << 16) | (dg << 8) | db;
                    }
                }
            }
        }

        // The falling leaves, and the leaves of a window's pile that falls when the window goes away.
        unsafe void DrawLeaves()
        {
            g.Flush(FlushIntention.Sync);
            uint* buf = (uint*)pixels.ToPointer();
            foreach (var f in flakes)
            {
                float size = f.R * 2.6f;
                if (f.Y < -size) continue;
                Mark(f.X - size * 0.71f, f.Y - size * 0.71f, size * 1.42f, size * 1.42f);
                BlendLeaf(buf, W, H, LeafSprite(f.Kind), f.X, f.Y, size, f.Rot, f.A);
            }
            float ox = ScreenBounds.X, oy = ScreenBounds.Y;
            foreach (var cl in c.Clumps)
            {
                if (cl.Dead) continue;
                float x = cl.X - ox, y = cl.Y - oy, size = cl.R * 2 * S;
                if (x < -10 || x > W + 10 || y < -10 || y > H + 10) continue;
                Mark(x - size * 0.71f, y - size * 0.71f, size * 1.42f, size * 1.42f);
                BlendLeaf(buf, W, H, LeafSprite((int)Math.Abs(cl.X)), x, y, size, 0, 242);
            }
        }

        // Which leaf lies where in a pile is fixed by its place, so the pile does not flicker: 0..1 from two whole numbers.
        static float Chance(int i, int j)
        {
            double v = Math.Sin(i * 12.9898 + j * 78.233) * 43758.5453;
            return (float)(v - Math.Floor(v));
        }

        Bitmap pileBmp;
        float pileDrawn = -1;
        double pileAt = -10;

        // A leaf pile is made of leaves: single leaves of every shape and colour lie over the pile's dark fill,
        // in rows from its surface down, each a little off its place and turned its own way. (As a plain shape
        // the pile looked flat and nothing like leaves.) That is far too many leaves to lay out every frame, so
        // the pile is kept as a picture and laid out again only when it has changed, at most twice a second.
        unsafe void DrawLeafPile()
        {
            float max = 0;
            for (int i = 0; i < heap.Length; i++) if (heap[i] > max) max = heap[i];
            if (max < 0.5f) return;
            float size = 15 * S, across = 7 * S, down = 5 * S;
            int room = (int)(34 * S + size);   // the highest drift (30 S in a storm) and the leaves lying over its top
            int bw = W, bh = room + 2;
            if (pileBmp == null || pileBmp.Width != bw || pileBmp.Height != bh)
            {
                if (pileBmp != null) pileBmp.Dispose();
                pileBmp = new Bitmap(bw, bh, PixelFormat.Format32bppPArgb);
                pileDrawn = -1;
            }
            float sum = 0;
            for (int i = 0; i < heap.Length; i++) sum += (float)Math.Round(heap[i] * 0.5f);
            if (pileDrawn < 0 || (sum != pileDrawn && c.Time - pileAt >= 0.5))
            {
                pileDrawn = sum; pileAt = c.Time;
                float gy = room;   // the ground's height in the picture
                using (var pg = Graphics.FromImage(pileBmp))
                using (var fill = new SolidBrush(PileFill))
                {
                    pg.SmoothingMode = SmoothingMode.AntiAlias;
                    pg.Clear(Color.Transparent);
                    var pts = new PointF[heap.Length + 2];
                    for (int i = 0; i < heap.Length; i++) pts[i] = new PointF(i * HeapStep, gy - heap[i]);
                    pts[heap.Length] = new PointF(W, gy + 1);
                    pts[heap.Length + 1] = new PointF(0, gy + 1);
                    pg.FillPolygon(fill, pts);
                }
                var data = pileBmp.LockBits(new Rectangle(0, 0, bw, bh), ImageLockMode.ReadWrite, PixelFormat.Format32bppPArgb);
                uint* buf = (uint*)data.Scan0.ToPointer();
                int column = 0;
                for (float x = -size / 2; x < W + size / 2; x += across, column++)
                {
                    float h = HeapAt(Math.Max(0, Math.Min(W - 1, x)));
                    if (h <= 1.5f) continue;
                    int rows = (int)(h / down);
                    for (int row = 0; row <= rows; row++)
                    {
                        float a = Chance(column, row), b = Chance(row + 31, column), d = Chance(column + 7, row + 3);
                        float y = gy - h + row * down + (a - 0.5f) * 4 * S - size * 0.12f;
                        BlendLeaf(buf, bw, bh, LeafSprite((int)(a * 9973)), x + (b - 0.5f) * across, y, size * (0.75f + 0.55f * b), d * 6.28f, 255);
                    }
                }
                pileBmp.UnlockBits(data);
            }
            Mark(0, groundY - max - size, W, max + size + 4 * S);
            g.CompositingMode = CompositingMode.SourceOver;
            g.DrawImageUnscaled(pileBmp, 0, (int)groundY - room);
        }

        // The piles on the windows are made of leaves too: single leaves over the dark fill, from the pile's top
        // down to where it hangs below the window's edge. (Sizes in the window snow's own unit, Ledge.U.)
        unsafe void DrawLedgeLeaves()
        {
            g.Flush(FlushIntention.Sync);
            uint* buf = (uint*)pixels.ToPointer();
            float ox = ScreenBounds.X, oy = ScreenBounds.Y, u = Ledge.U;
            float size = 13 * u, across = 6 * u, down = 4.5f * u;
            foreach (var l in c.LedgeList)
            {
                bool dragged = l.Moving && l.Rect.Size == l.Settled.Size;
                if (!l.HasSnow || dragged) continue;
                if (l.Settled.Right <= ox || l.Settled.Left >= ox + W || l.Settled.Top <= oy || l.Settled.Top > oy + H) continue;
                float edge = l.Settled.Top - oy;
                int id = (int)(l.Id & 0xFFFF);
                foreach (var seg in l.Visible)
                {
                    float x0 = Math.Max(seg[0], ox), x1 = Math.Min(seg[1], ox + W);
                    if (x1 - x0 < 4) continue;
                    float top = 0, low = 0;
                    int column = (int)(x0 / across);
                    for (float x = x0; x <= x1; x += across, column++)
                    {
                        float h = l.HeightAt(x), d = l.HangAt(x);
                        if (h <= 0.4f * u) continue;
                        top = Math.Max(top, h); low = Math.Max(low, d);
                        int rows = (int)((h + d) / down);
                        for (int row = 0; row <= rows; row++)
                        {
                            float p = Chance(column, row + id), q = Chance(row + 31, column), t = Chance(column + 7, row + 3);
                            float y = edge - h + row * down + (p - 0.5f) * 3 * u - size * 0.1f;
                            BlendLeaf(buf, W, H, LeafSprite((int)(p * 9973)), x - ox + (q - 0.5f) * across, y, size * (0.75f + 0.5f * q), t * 6.28f, 255);
                        }
                    }
                    if (top > 0) Mark(x0 - ox - size, edge - top - size, x1 - x0 + 2 * size, top + low + 2 * size);
                }
            }
        }

        void Deposit(float x, float r)
        {
            int idx = (int)(x / HeapStep);
            float amount = 0.35f * r;
            if (c.EffectiveSnowLevel == 2)
            {
                // dunes: long waves in global x (so they line up across screens), slowly wandering with the wind
                double gx = x + ScreenBounds.X;
                double dune = 0.5 + 0.5 * Math.Sin(gx / (240 * S) * 2 * Math.PI - c.Time * 0.03 * (c.Wind > 0 ? 1 : -1));
                amount *= 0.3f + 1.4f * (float)dune;
            }
            for (int k = -1; k <= 1; k++)
            {
                int j = idx + k;
                if (j >= 0 && j < heap.Length) heap[j] += k == 0 ? amount : amount * 0.5f;
            }
        }

        float HeapAt(float x)
        {
            float fx = x / HeapStep;
            int i = (int)Math.Floor(fx);
            if (i < 0) return heap[0];
            if (i >= heap.Length - 1) return heap[heap.Length - 1];
            float t = fx - i;
            return heap[i] * (1 - t) + heap[i + 1] * t;
        }

        // blød hvid prik direkte i den præmultiplicerede pixelbuffer (meget hurtigere end GDI+)
        unsafe void BlendDot(float cx, float cy, float r, int alpha)
        {
            int x0 = Math.Max(0, (int)(cx - r - 1)), x1 = Math.Min(W - 1, (int)(cx + r + 1));
            int y0 = Math.Max(0, (int)(cy - r - 1)), y1 = Math.Min(H - 1, (int)(cy + r + 1));
            if (x0 > x1 || y0 > y1) return;
            uint* buf = (uint*)pixels.ToPointer();
            for (int y = y0; y <= y1; y++)
            {
                float dy = y + 0.5f - cy;
                uint* row = buf + (long)y * W;
                for (int x = x0; x <= x1; x++)
                {
                    float dx = x + 0.5f - cx;
                    float cov = r + 0.5f - (float)Math.Sqrt(dx * dx + dy * dy);
                    if (cov <= 0) continue;
                    if (cov > 1) cov = 1;
                    int a = (int)(alpha * cov);
                    if (a <= 0) continue;
                    uint d = row[x];
                    int inv = 255 - a;
                    uint da = (uint)(a + (((d >> 24) & 0xFF) * inv) / 255);
                    uint dr = (uint)(a + (((d >> 16) & 0xFF) * inv) / 255);
                    uint dg = (uint)(a + (((d >> 8) & 0xFF) * inv) / 255);
                    uint db = (uint)(a + ((d & 0xFF) * inv) / 255);
                    row[x] = (da << 24) | (dr << 16) | (dg << 8) | db;
                }
            }
        }

        void DrawSnow()
        {
            if (c.Autumn) { DrawLeaves(); return; }
            g.Flush(FlushIntention.Sync);
            foreach (var f in flakes)
            {
                if (f.Y < -f.R * 2) continue;
                Mark(f.X - f.R, f.Y - f.R, f.R * 2, f.R * 2);
                if (!f.Crystal) BlendDot(f.X, f.Y, f.R, f.A);
            }
            // clumps falling off a window that went away
            float ox = ScreenBounds.X, oy = ScreenBounds.Y;
            foreach (var cl in c.Clumps)
            {
                if (cl.Dead) continue;
                float x = cl.X - ox, y = cl.Y - oy, r = cl.R * S;
                if (x < -10 || x > W + 10 || y < -10 || y > H + 10) continue;
                Mark(x - r, y - r, r * 2, r * 2);
                BlendDot(x, y, r, 242);
            }
            foreach (var f in flakes)
            {
                if (!f.Crystal || f.Y < -f.R * 2) continue;
                int alpha = f.A;
                if (alpha < 60) continue;
                var pen = flakePens[Math.Max(0, Math.Min(15, (alpha - 60) / 13))];
                pen.Width = Math.Max(1f, 0.9f * S);
                for (int k = 0; k < 3; k++)
                {
                    float a = f.Rot + k * 1.0472f;
                    float dx = (float)Math.Cos(a) * f.R, dy = (float)Math.Sin(a) * f.R;
                    g.DrawLine(pen, f.X - dx, f.Y - dy, f.X + dx, f.Y + dy);
                }
            }
        }

        // Snow piles on other apps' window edges that cross this screen (WindowSnow.cs), with the drape hanging
        // down over the edge. Only stretches where snow has actually landed are drawn (no thin line on bare edges).
        void DrawLedges()
        {
            if (!cfg.WindowSnow || c.LedgeList.Count == 0) return;
            float ox = ScreenBounds.X, oy = ScreenBounds.Y, step = Ledge.Step, u = Ledge.U;
            var xs = new List<float>();
            var hs = new List<float>();
            var ds = new List<float>();
            // (in autumn the piles are leaves: the dark between them here, without an outline, and the leaves over it below)
            bool autumn = c.Autumn;
            using (var fill = new SolidBrush(autumn ? PileFill : Color.FromArgb(245, 248, 252, 255)))
            using (var line = new Pen(Color.FromArgb(autumn ? 0 : 110, 170, 200, 230), 1.2f * u))
            {
                foreach (var l in c.LedgeList)
                {
                    // a window dragged around (same size) takes its snow along, so the pile is hidden until it settles;
                    // a window that shrinks (minimize) or is resized leaves the snow where it was until it is gone
                    bool dragged = l.Moving && l.Rect.Size == l.Settled.Size;
                    if (!l.HasSnow || dragged) continue;
                    if (l.Settled.Right <= ox || l.Settled.Left >= ox + W || l.Settled.Top <= oy || l.Settled.Top > oy + H) continue;
                    float baseY = l.Settled.Top - oy;
                    Action flush = () =>
                    {
                        if (xs.Count >= 2) DrawLedgeRun(xs, hs, ds, baseY, fill, line);
                        xs.Clear(); hs.Clear(); ds.Clear();
                    };
                    foreach (var seg in l.Visible)
                    {
                        float x0 = Math.Max(seg[0], ox), x1 = Math.Min(seg[1], ox + W);
                        if (x1 - x0 < 4) continue;
                        float x = x0;
                        for (; x <= x1; x += step)
                        {
                            float h = l.HeightAt(x), d = l.HangAt(x);
                            if (h > 0.6f * u || d > 0.6f * u)
                            {
                                // start and end each stretch on the edge itself, so the pile tapers off
                                if (xs.Count == 0) { xs.Add(Math.Max(x0, x - step) - ox); hs.Add(0); ds.Add(0); }
                                xs.Add(x - ox); hs.Add(h); ds.Add(d);
                            }
                            else if (xs.Count > 0) { xs.Add(x - ox); hs.Add(0); ds.Add(0); flush(); }
                        }
                        if (xs.Count > 0) { xs.Add(Math.Min(x1, x) - ox); hs.Add(0); ds.Add(0); flush(); }
                    }
                }
            }
            if (autumn) DrawLedgeLeaves();
        }

        // One stretch: the pile's top from left to right, then back along the drape hanging below the edge.
        void DrawLedgeRun(List<float> xs, List<float> hs, List<float> ds, float baseY, Brush fill, Pen line)
        {
            int n = xs.Count;
            var top = new PointF[n];
            var low = new PointF[n];
            float maxH = 0, maxD = 0;
            for (int i = 0; i < n; i++)
            {
                top[i] = new PointF(xs[i], baseY - hs[i]);
                low[n - 1 - i] = new PointF(xs[i], baseY + 0.5f + ds[i]);
                maxH = Math.Max(maxH, hs[i]); maxD = Math.Max(maxD, ds[i]);
            }
            Mark(xs[0] - 2, baseY - maxH - 3, xs[n - 1] - xs[0] + 4, maxH + maxD + 6);
            using (var path = new GraphicsPath())
            {
                path.AddCurve(top, 0.5f);
                path.AddCurve(low, 0.5f);
                path.CloseFigure();
                g.FillPath(fill, path);
            }
            if (c.Autumn) return;   // a leaf pile has no outline
            g.DrawCurve(line, top, 0.5f);
            // a faint outline under the drape where it hangs down, for depth
            if (maxD > Ledge.U) g.DrawCurve(line, low, 0.5f);
        }

        void DrawGround()
        {
            if (c.Autumn) { DrawLeafPile(); return; }
            float max = 0;
            for (int i = 0; i < heap.Length; i++) if (heap[i] > max) max = heap[i];
            if (max < 0.5f) return;
            Mark(0, groundY - max - 4 * S, W, max + 8 * S);
            var pts = new PointF[heap.Length + 2];
            for (int i = 0; i < heap.Length; i++) pts[i] = new PointF(i * HeapStep, groundY - heap[i]);
            pts[heap.Length] = new PointF(W, groundY + 1);
            pts[heap.Length + 1] = new PointF(0, groundY + 1);
            using (var b = new SolidBrush(Color.FromArgb(245, 248, 252, 255))) g.FillPolygon(b, pts);
            using (var p = new Pen(Color.FromArgb(110, 170, 200, 230), 1.5f * S))
            {
                var top = new PointF[heap.Length];
                Array.Copy(pts, top, heap.Length);
                g.DrawLines(p, top);
            }
        }

        // ------------------------------------------------------------------ julemanden og gnister
        void DrawSantaAndSparks()
        {
            float ox = ScreenBounds.X, oy = ScreenBounds.Y;
            foreach (var sp in c.Sparks)
            {
                float x = sp.X - ox, y = sp.Y - oy;
                if (x < -20 || y < -20 || x > W + 20 || y > H + 20) continue;
                float life = sp.Star ? Math.Min(1f, sp.Life) : sp.Life / sp.Max;
                int a = (int)(255 * life);
                Color col = sp.Gold ? Color.FromArgb(a, 255, 220, 120) : Color.FromArgb(a, 255, 255, 255);
                Mark(x - sp.Size * 1.6f, y - sp.Size * 1.6f, sp.Size * 3.2f, sp.Size * 3.2f);
                using (var b = new SolidBrush(col))
                {
                    if (sp.Star) g.FillPolygon(b, StarPoints(x, y, sp.Size, sp.Size * 0.45f, sp.Life));
                    else g.FillEllipse(b, x - sp.Size / 2, y - sp.Size / 2, sp.Size, sp.Size);
                }
                if (!sp.Star && sp.Size > 3.5f * S)
                    using (var p = new Pen(col, 1f))
                    {
                        g.DrawLine(p, x - sp.Size * 1.5f, y, x + sp.Size * 1.5f, y);
                        g.DrawLine(p, x, y - sp.Size * 1.5f, x, y + sp.Size * 1.5f);
                    }
            }
            if (!c.SantaActive) return;

            float sc = c.SantaScale * 1.1f;
            float sx = c.SantaX - ox, sy = c.SantaY - oy;
            if (sx < -330 * sc || sx > W + 330 * sc || sy < -150 * sc || sy > H + 150 * sc) return;
            Mark(sx - 330 * sc, sy - 135 * sc, 660 * sc, 195 * sc);

            var st = g.Save();
            g.TranslateTransform(sx, sy);
            g.ScaleTransform(c.SantaDir * sc, sc);
            float t = c.SantaPhase;
            if (c.Autumn) { DrawGeese(t); g.Restore(st); return; }
            g.RotateTransform((float)Math.Cos(c.SantaPhase * 0.9) * -4f * c.SantaDir);

            float[] rx = { 80, 140, 200, 260 };
            float[] ry = new float[4];
            for (int i = 0; i < 4; i++) ry[i] = -40 + (float)Math.Sin(t * 6 + i * 0.8) * 3;

            using (var rein = new Pen(Color.FromArgb(120, 60, 30), 1.4f))
                for (int i = 0; i < 4; i++) g.DrawLine(rein, -14, -44, rx[i] + 4, ry[i] - 6);
            for (int i = 0; i < 4; i++) DrawReindeer(rx[i], ry[i], i * 0.8f, i == 3, t);

            using (var red = new SolidBrush(SantaRed))
            using (var white = new SolidBrush(Color.White))
            using (var skin = new SolidBrush(Skin))
            using (var black = new SolidBrush(Color.FromArgb(30, 30, 30)))
            using (var sack = new SolidBrush(Color.FromArgb(150, 110, 60)))
            using (var gold = new SolidBrush(Gold))
            {
                g.FillEllipse(sack, -92, -66, 36, 40);
                using (var gb = new SolidBrush(Color.FromArgb(40, 140, 70))) g.FillRectangle(gb, -84, -74, 12, 12);
                using (var gb = new SolidBrush(Color.FromArgb(60, 100, 200))) g.FillRectangle(gb, -72, -70, 10, 9);
                g.FillRectangle(gold, -79, -74, 2, 12);

                g.FillEllipse(red, -52, -58, 32, 42);
                using (var arm = new Pen(SantaRed, 7f)) { arm.StartCap = arm.EndCap = LineCap.Round; g.DrawLine(arm, -32, -48, -16, -44); }
                g.FillEllipse(black, -19, -48, 8, 8);
                g.FillEllipse(skin, -45, -76, 19, 19);
                g.FillEllipse(white, -42, -68, 18, 20);
                g.FillEllipse(white, -31, -70, 9, 5);
                using (var nose = new SolidBrush(Color.FromArgb(240, 150, 140))) g.FillEllipse(nose, -28, -71, 5, 5);
                g.FillEllipse(black, -32, -74, 2.6f, 2.6f);
                g.FillPolygon(red, new[] { new PointF(-47, -72), new PointF(-25, -74), new PointF(-40, -90), new PointF(-56, -86) });
                g.FillRectangle(white, -48, -76, 25, 5);
                g.FillEllipse(white, -61, -91, 9, 9);
            }

            using (var path = new GraphicsPath())
            {
                path.AddBezier(-82, -46, -70, -36, -78, -4, -60, 2);
                path.AddLine(-60, 2, 12, 2);
                path.AddBezier(12, 2, 26, 2, 30, -18, 40, -22);
                path.AddLine(40, -22, 34, -27);
                path.AddBezier(34, -27, 22, -16, 0, -21, -48, -23);
                path.AddLine(-48, -23, -72, -48);
                path.CloseFigure();
                using (var b = new LinearGradientBrush(new PointF(0, -46), new PointF(0, 4), Color.FromArgb(200, 30, 40), Color.FromArgb(120, 10, 20)))
                    g.FillPath(b, path);
                using (var p = new Pen(Gold, 2f)) g.DrawPath(p, path);
            }
            using (var p = new Pen(Gold, 3f))
            {
                p.StartCap = p.EndCap = LineCap.Round;
                g.DrawLine(p, -55, 2, -55, 12);
                g.DrawLine(p, 5, 2, 5, 12);
                g.DrawLine(p, -72, 12, 22, 12);
                g.DrawBezier(p, 22, 12, 36, 12, 38, -2, 28, -4);
                g.DrawBezier(p, -72, 12, -80, 12, -80, 4, -74, 4);
            }
            g.Restore(st);
        }

        static PointF[] StarPoints(float cx, float cy, float outer, float inner, float rot)
        {
            var p = new PointF[10];
            for (int i = 0; i < 10; i++)
            {
                double a = -Math.PI / 2 + i * Math.PI / 5 + rot;
                float r = i % 2 == 0 ? outer : inner;
                p[i] = new PointF(cx + (float)Math.Cos(a) * r, cy + (float)Math.Sin(a) * r);
            }
            return p;
        }

        void DrawReindeer(float x, float y, float phase, bool rudolph, float t)
        {
            float gal = t * 9 + phase;
            using (var legFar = new Pen(Color.FromArgb(85, 52, 28), 3.2f))
            using (var legNear = new Pen(DeerDark, 3.6f))
            {
                legFar.StartCap = legFar.EndCap = legNear.StartCap = legNear.EndCap = LineCap.Round;
                Leg(legFar, x + 9, y + 4, (float)Math.Sin(gal + 0.6) * 0.8f + 0.5f);
                Leg(legFar, x - 9, y + 4, (float)Math.Sin(gal + Math.PI + 0.6) * 0.8f - 0.4f);
                Leg(legNear, x + 14, y + 4, (float)Math.Sin(gal) * 0.8f + 0.5f);
                Leg(legNear, x - 14, y + 4, (float)Math.Sin(gal + Math.PI) * 0.8f - 0.4f);
            }
            using (var deer = new SolidBrush(Deer))
            using (var dark = new SolidBrush(DeerDark))
            using (var light = new SolidBrush(Color.FromArgb(200, 160, 110)))
            using (var white = new SolidBrush(Color.White))
            {
                g.FillEllipse(white, x - 27, y - 9, 8, 7);
                g.FillEllipse(deer, x - 22, y - 10, 44, 20);
                g.FillEllipse(light, x - 14, y - 1, 28, 8);
                g.FillPolygon(deer, new[] { new PointF(x + 10, y - 6), new PointF(x + 18, y - 25), new PointF(x + 26, y - 22), new PointF(x + 21, y + 2) });
                g.FillEllipse(deer, x + 16, y - 32, 16, 11);
                g.FillEllipse(deer, x + 26, y - 29, 11, 8);
                g.FillEllipse(dark, x + 14, y - 33, 7, 4);
                using (var eye = new SolidBrush(Color.Black)) g.FillEllipse(eye, x + 23, y - 30, 2.5f, 2.5f);
            }
            using (var ant = new Pen(Color.FromArgb(205, 175, 125), 2f))
            {
                ant.StartCap = ant.EndCap = LineCap.Round;
                g.DrawLine(ant, x + 20, y - 31, x + 16, y - 45);
                g.DrawLine(ant, x + 17, y - 41, x + 11, y - 45);
                g.DrawLine(ant, x + 16, y - 45, x + 20, y - 51);
                g.DrawLine(ant, x + 23, y - 31, x + 27, y - 45);
                g.DrawLine(ant, x + 26, y - 41, x + 32, y - 44);
            }
            using (var harness = new Pen(Color.FromArgb(190, 20, 30), 3f)) g.DrawLine(harness, x + 8, y - 9, x + 5, y + 9);
            using (var bell = new SolidBrush(Gold)) g.FillEllipse(bell, x + 3, y + 5, 4.5f, 4.5f);

            if (rudolph)
            {
                int a = (int)(90 + 70 * Math.Sin(t * 6));
                using (var glow = new SolidBrush(Color.FromArgb(a, 255, 60, 50))) g.FillEllipse(glow, x + 30, y - 33, 15, 15);
                using (var nose = new SolidBrush(Color.FromArgb(240, 30, 30))) g.FillEllipse(nose, x + 34, y - 29, 7, 7);
            }
            else using (var nose = new SolidBrush(Color.FromArgb(40, 25, 15))) g.FillEllipse(nose, x + 35, y - 27, 4, 4);
        }

        void Leg(Pen p, float hx, float hy, float a)
        {
            g.DrawLine(p, hx, hy, hx + (float)Math.Sin(a) * 15, hy + (float)Math.Cos(a) * 15);
        }

        // ------------------------------------------------------------------ snemand (bygges lidt mere hver dag)
        void DrawSnowman()
        {
            int stage = c.SnowmanStage;
            float x = W * 0.78f, y = groundY - HeapAt(x) + 3 * S;
            SnowmanPos = new PointF(ScreenBounds.X + x, ScreenBounds.Y + y);
            Mark(x - 62 * S, y - 135 * S, 124 * S, 142 * S);

            var st = g.Save();
            g.TranslateTransform(x, y);
            g.ScaleTransform(S, S);
            if (c.Autumn) { DrawScarecrow(stage); g.Restore(st); return; }

            using (var shadow = new SolidBrush(Color.FromArgb(50, 60, 80, 110))) g.FillEllipse(shadow, -30, -3, 60, 6);
            using (var wood = new Pen(Color.FromArgb(110, 70, 35), 2.6f))
            {
                wood.StartCap = wood.EndCap = LineCap.Round;
                if (stage >= 12)
                {
                    g.DrawLine(wood, 32, -6, 46, -104);
                    using (var straw = new SolidBrush(Color.FromArgb(215, 175, 90)))
                        g.FillPolygon(straw, new[] { new PointF(24, 6), new PointF(42, 6), new PointF(37, -14), new PointF(31, -14) });
                    using (var bind = new Pen(Color.FromArgb(170, 30, 30), 2f)) g.DrawLine(bind, 30, -11, 38, -11);
                }
                if (stage >= 8)
                {
                    g.DrawLine(wood, -15, -66, -40, -84);
                    g.DrawLine(wood, -33, -79, -37, -91);
                    g.DrawLine(wood, -33, -79, -44, -78);
                    g.DrawLine(wood, 15, -66, 40, -80);
                    g.DrawLine(wood, 33, -76, 39, -88);
                }
            }

            if (stage == 1) Ball(0, -11, 11); else Ball(0, -24, 25);
            if (stage >= 3) Ball(0, -62, 18);
            if (stage >= 4) Ball(0, -92, 13);

            using (var coal = new SolidBrush(Color.FromArgb(35, 35, 40)))
            {
                if (stage >= 7) for (int i = 0; i < 3; i++) g.FillEllipse(coal, -2.4f, -72.4f + i * 9, 4.8f, 4.8f);
                if (stage >= 10)
                {
                    using (var scarf = new SolidBrush(Color.FromArgb(200, 30, 40)))
                    {
                        g.FillRectangle(scarf, -13, -82, 26, 6);
                        g.FillPolygon(scarf, new[] { new PointF(5, -78), new PointF(12, -78), new PointF(15, -57), new PointF(8, -57) });
                    }
                    using (var stripe = new Pen(Color.White, 1.5f))
                    {
                        g.DrawLine(stripe, 9, -66, 14, -66);
                        g.DrawLine(stripe, 10, -61, 15, -61);
                    }
                }
                if (stage >= 5)
                {
                    g.FillEllipse(coal, -6.5f, -98, 4, 4);
                    g.FillEllipse(coal, 2.5f, -98, 4, 4);
                }
                if (stage >= 6)
                    using (var carrot = new SolidBrush(Color.FromArgb(240, 130, 30)))
                        g.FillPolygon(carrot, new[] { new PointF(0, -93), new PointF(19, -89.5f), new PointF(0, -87) });
                if (stage >= 9)
                    for (int i = -2; i <= 2; i++)
                    {
                        float sx = i * 3f, sy = -86 + 2 * (1 - (sx / 6) * (sx / 6)) + 1;
                        g.FillEllipse(coal, sx - 1.1f, sy - 1.1f, 2.2f, 2.2f);
                    }
                if (stage >= 11)
                {
                    g.FillRectangle(coal, -15, -106, 30, 4);
                    g.FillRectangle(coal, -10, -127, 20, 22);
                    using (var band = new SolidBrush(Color.FromArgb(200, 30, 40))) g.FillRectangle(band, -10, -110, 20, 4);
                }
            }
            if (stage >= 12)
            {
                using (var gift = new SolidBrush(Color.FromArgb(40, 140, 70))) g.FillRectangle(gift, -50, -13, 15, 13);
                using (var rib = new Pen(Gold, 1.8f))
                {
                    g.DrawLine(rib, -42.5f, -13, -42.5f, 0);
                    g.DrawLine(rib, -50, -6.5f, -35, -6.5f);
                    g.DrawEllipse(rib, -46, -17, 3.5f, 3.5f);
                    g.DrawEllipse(rib, -42.5f, -17, 3.5f, 3.5f);
                }
            }
            g.Restore(st);
        }

        void Ball(float cx, float cy, float r)
        {
            var rc = new RectangleF(cx - r, cy - r, 2 * r, 2 * r);
            using (var b = new LinearGradientBrush(rc, Color.White, Color.FromArgb(200, 216, 238), 50f)) g.FillEllipse(b, rc);
            using (var p = new Pen(Color.FromArgb(70, 140, 165, 200), 1f)) g.DrawEllipse(p, rc);
        }

        // ------------------------------------------------------------------ snow plow
        // An orange plow truck clears the taskbar when the snow gets high, alternating direction each run.
        // Snow it scrapes up builds a growing pile in front of the blade and is thrown up as chunks.
        // (Kind: which leaf this is, when the plow is autumn's leaf collector)
        class PlowBit { public float X, Y, VX, VY, Life, Max, Size; public bool Smoke; public int Kind; }
        readonly List<PlowBit> plowBits = new List<PlowBit>();
        float plowSmokeTimer, plowChunkAcc;
        const float PlowScale = Controller.PlowScale;

        // The truck itself is driven by the Controller in global coordinates, so one plow drives continuously
        // across neighbouring screens. These read its state in this screen's coordinates.
        bool plowActive { get { return c.Plow.Active && c.Plow.Members.Contains(this); } }
        float plowX { get { return c.Plow.GX - ScreenBounds.X; } }
        float plowDir { get { return c.Plow.Dir; } }
        float plowWheel { get { return c.Plow.Wheel; } }
        bool PlowOnScreen { get { float m = 140 * S * PlowScale; return plowActive && plowX > -m && plowX < W + m; } }
        float PlowPileHeight { get { return Math.Min(34f, 4f + (float)Math.Sqrt(c.Plow.Pushed / S) * 0.3f); } }

        // True while snow chunks or smoke from the plow are still flying on this screen (needs more frames).
        public bool IsBusy { get { return plowBits.Count > 0; } }

        // Average height of the snow pile (the Controller sends the plow when it gets high).
        public float HeapAverage
        {
            get { float sum = 0; for (int i = 0; i < heap.Length; i++) sum += heap[i]; return sum / heap.Length; }
        }

        void UpdatePlow(float dt)
        {
            float sc = S * PlowScale;
            if (plowActive)
            {
                // Everything between the edge where the plow entered this screen and the blade stays scraped down.
                float blade = plowX + plowDir * 72 * sc;
                float residue = 1.5f * S;
                float from = plowDir > 0 ? 0 : W;
                if ((plowDir > 0 && blade > 0) || (plowDir < 0 && blade < W))
                {
                    int i0 = Math.Max(0, (int)(Math.Max(0, Math.Min(from, blade)) / HeapStep));
                    int i1 = Math.Min(heap.Length - 1, (int)(Math.Min(W, Math.Max(from, blade)) / HeapStep));
                    for (int i = i0; i <= i1; i++)
                        if (heap[i] > residue) { c.Plow.Pushed += heap[i] - residue; heap[i] = residue; }
                }
            }
            if (PlowOnScreen)
            {
                float gy = groundY - HeapAt(plowX) + S;
                float ph = PlowPileHeight;
                if (c.Autumn)
                {
                    // the leaf collector: leaves whirl up around its nozzle and are left behind in the air for a moment
                    if (ph > 6)
                    {
                        plowChunkAcc += dt * 14;
                        while (plowChunkAcc >= 1)
                        {
                            plowChunkAcc -= 1;
                            var b = new PlowBit();
                            b.X = plowX + plowDir * (58 + Rnd() * 26) * sc;
                            b.Y = gy - (2 + Rnd() * 10) * sc;
                            b.VX = plowDir * (Rnd() - 0.35f) * 110 * S;
                            b.VY = -(90 + Rnd() * 150) * S;
                            b.Max = b.Life = 2f;
                            b.Size = (4 + Rnd() * 3) * S;
                            b.Kind = rnd.Next(1000);
                            plowBits.Add(b);
                        }
                    }
                }
                else if (ph > 10)
                {
                    plowChunkAcc += dt * 30;
                    while (plowChunkAcc >= 1)
                    {
                        plowChunkAcc -= 1;
                        var b = new PlowBit();
                        b.X = plowX + plowDir * (70 + Rnd() * ph) * sc;
                        b.Y = gy - ph * sc;
                        b.VX = plowDir * (80 + Rnd() * 140) * S;
                        b.VY = -(60 + Rnd() * 140) * S;
                        b.Max = b.Life = 2f;
                        b.Size = (1.5f + Rnd() * 2.5f) * S;
                        plowBits.Add(b);
                    }
                }
                plowSmokeTimer -= dt;
                if (plowSmokeTimer <= 0)
                {
                    plowSmokeTimer = 0.2f;
                    var b = new PlowBit();
                    b.Smoke = true;
                    b.X = plowX - plowDir * 2 * sc;
                    b.Y = gy - 76 * sc;
                    b.VX = -plowDir * 25 * S;
                    b.VY = -30 * S;
                    b.Max = b.Life = 1.6f;
                    b.Size = 5 * S;
                    plowBits.Add(b);
                }

                // Nisser wave at the truck as it passes.
                foreach (var n in nisser)
                    if (n.State != 2 && Math.Abs(n.X - plowX) < 140 * S) { n.State = 2; n.StateTimer = 1.5f; }

                if ((int)(c.Time * 2) != (int)((c.Time - dt) * 2))
                    ErrorLog.Debug("plow on screen x=" + ScreenBounds.X + ": x=" + (int)plowX + " gy=" + (int)gy + " pushed=" + (int)c.Plow.Pushed);
            }

            for (int i = plowBits.Count - 1; i >= 0; i--)
            {
                var b = plowBits[i];
                b.Life -= dt;
                b.X += b.VX * dt;
                b.Y += b.VY * dt;
                if (b.Smoke) b.Size += 6 * S * dt;
                else b.VY += 420 * S * dt;
                if (b.Life <= 0 || (!b.Smoke && b.VY > 0 && b.Y >= groundY - HeapAt(b.X))) plowBits.RemoveAt(i);
            }
        }

        // The leaves the leaf collector whirls up, turning as they fly (straight into the pixel buffer, as the falling ones).
        unsafe void DrawPlowLeaves()
        {
            g.Flush(FlushIntention.Sync);
            uint* buf = (uint*)pixels.ToPointer();
            foreach (var b in plowBits)
            {
                if (b.Smoke) continue;
                float size = b.Size * 2.6f;
                Mark(b.X - size * 0.71f, b.Y - size * 0.71f, size * 1.42f, size * 1.42f);
                BlendLeaf(buf, W, H, LeafSprite(b.Kind), b.X, b.Y, size, b.Life * 7 + b.Kind, 255);
            }
        }

        void DrawPlow()
        {
            bool autumn = c.Autumn;
            if (autumn && plowBits.Count > 0) DrawPlowLeaves();
            foreach (var b in plowBits)
            {
                if (autumn && !b.Smoke) continue;
                Mark(b.X - b.Size, b.Y - b.Size, b.Size * 2, b.Size * 2);
                int a = b.Smoke ? (int)(90 * b.Life / b.Max) : 235;
                using (var br = new SolidBrush(b.Smoke ? Color.FromArgb(a, 120, 120, 125) : Color.FromArgb(a, 250, 252, 255)))
                    g.FillEllipse(br, b.X - b.Size, b.Y - b.Size, b.Size * 2, b.Size * 2);
            }
            if (!PlowOnScreen) return;

            float sc = S * PlowScale;
            float gy = groundY - HeapAt(plowX) + S;
            float ph = PlowPileHeight;
            Mark(plowX - 130 * sc, gy - 100 * sc, 260 * sc, 106 * sc);

            var st = g.Save();
            g.TranslateTransform(plowX, gy);
            g.ScaleTransform(plowDir * sc, sc);
            if (autumn) { DrawLeafCollector(ph); g.Restore(st); return; }

            Color orange = Color.FromArgb(235, 130, 20), orangeDark = Color.FromArgb(185, 95, 10);
            using (var o = new SolidBrush(orange))
            using (var od = new SolidBrush(orangeDark))
            using (var dark = new SolidBrush(Color.FromArgb(50, 50, 55)))
            using (var grey = new SolidBrush(Color.FromArgb(110, 110, 115)))
            using (var glass = new SolidBrush(Color.FromArgb(175, 210, 235)))
            {
                // exhaust stack
                g.FillRectangle(grey, -4, -76, 4, 30);

                // salt spreader at the back, with a spinning disc
                g.FillRectangle(grey, -92, -32, 12, 16);
                using (var p = new Pen(Color.FromArgb(70, 70, 75), 2f))
                {
                    float sa = plowWheel * 2;
                    g.DrawLine(p, -86 - (float)Math.Cos(sa) * 6, -14, -86 + (float)Math.Cos(sa) * 6, -14);
                }

                // dump body with ribs and a reflective stripe
                g.FillRectangle(o, -80, -50, 74, 36);
                g.FillRectangle(od, -82, -53, 78, 5);
                using (var rib = new Pen(orangeDark, 2f))
                    foreach (float rx in new[] { -62f, -44f, -26f }) g.DrawLine(rib, rx, -48, rx, -16);

                // cab
                g.FillPolygon(o, new[] { new PointF(-2, -14), new PointF(-2, -64), new PointF(26, -64), new PointF(40, -44), new PointF(43, -14) });
                g.FillPolygon(glass, new[] { new PointF(14, -59), new PointF(25, -59), new PointF(36, -43), new PointF(14, -43) });
                g.FillRectangle(glass, 1, -59, 10, 16);
                using (var door = new Pen(orangeDark, 1.2f)) g.DrawLine(door, 12, -60, 12, -16);
                g.FillRectangle(dark, 4, -38, 5, 2);
                using (var stripe = new SolidBrush(Color.FromArgb(230, 255, 255, 255))) g.FillRectangle(stripe, -80, -26, 123, 3);
                using (var lamp = new SolidBrush(Color.FromArgb(255, 245, 190))) g.FillEllipse(lamp, 38, -26, 5, 5);

                // amber beacon on the roof, flashing
                g.FillRectangle(dark, 12, -68, 10, 4);
                float flash = 0.5f + 0.5f * (float)Math.Sin(c.Time * 12);
                using (var glow = new SolidBrush(Color.FromArgb((int)(150 * flash), 255, 170, 0)))
                    g.FillEllipse(glow, 3, -82, 28, 24);
                using (var beacon = new SolidBrush(Color.FromArgb(255, 200 + (int)(55 * flash), 120 + (int)(60 * flash), 0)))
                    g.FillEllipse(beacon, 13, -74, 8, 7);

                // chassis and wheels with rotating spokes
                g.FillRectangle(dark, -86, -16, 132, 7);
                using (var tyre = new SolidBrush(Color.FromArgb(30, 30, 32)))
                using (var hub = new SolidBrush(Color.FromArgb(160, 160, 165)))
                using (var spoke = new Pen(Color.FromArgb(60, 60, 65), 1.6f))
                    foreach (float wx in new[] { -58f, -32f, 26f })
                    {
                        g.FillEllipse(tyre, wx - 10, -20, 20, 20);
                        g.FillEllipse(hub, wx - 5, -15, 10, 10);
                        for (int k = 0; k < 3; k++)
                        {
                            double a = plowWheel + k * Math.PI / 3;
                            float dx = (float)Math.Cos(a) * 5, dy = (float)Math.Sin(a) * 5;
                            g.DrawLine(spoke, wx - dx, -10 - dy, wx + dx, -10 + dy);
                        }
                    }

                // snow pile in front of the blade
                using (var pile = new GraphicsPath())
                {
                    pile.AddBezier(56, 1, 60, -ph, 74 + ph * 0.6f, -ph * 0.95f, 72 + ph * 1.6f, 1);
                    pile.CloseFigure();
                    using (var sb = new SolidBrush(Color.FromArgb(250, 250, 252, 255))) g.FillPath(sb, pile);
                    using (var sp = new Pen(Color.FromArgb(120, 170, 200, 230), 1f)) g.DrawPath(sp, pile);
                }

                // plow arm and curved yellow blade with black warning stripes
                using (var arm = new Pen(Color.FromArgb(80, 80, 85), 3f)) g.DrawLine(arm, 42, -12, 55, -16);
                using (var bladePath = new GraphicsPath())
                {
                    bladePath.AddBezier(54, -38, 66, -30, 70, -14, 68, 2);
                    bladePath.AddLine(68, 2, 56, 2);
                    bladePath.AddBezier(56, 2, 58, -12, 54, -28, 50, -38);
                    bladePath.CloseFigure();
                    using (var yb = new SolidBrush(Color.FromArgb(250, 195, 30))) g.FillPath(yb, bladePath);
                    var clip = g.Save();
                    g.SetClip(bladePath, CombineMode.Intersect);
                    using (var stripes = new Pen(Color.FromArgb(40, 40, 40), 3f))
                        for (float sy = -44; sy < 8; sy += 9) g.DrawLine(stripes, 46, sy, 74, sy + 14);
                    g.Restore(clip);
                    using (var edge = new Pen(Color.FromArgb(130, 95, 10), 1.2f)) g.DrawPath(edge, bladePath);
                }
            }
            g.Restore(st);
        }

        // ------------------------------------------------------------------ nisser
        static readonly Color[] Tunics = {
            Color.FromArgb(115, 120, 130), Color.FromArgb(40, 105, 65), Color.FromArgb(150, 35, 45), Color.FromArgb(70, 85, 145) };
        static readonly Color[] Gifts = {
            Color.FromArgb(40, 140, 70), Color.FromArgb(60, 100, 200), Color.FromArgb(200, 40, 60), Color.FromArgb(150, 80, 180) };

        public void NisseWave(float seconds)
        {
            foreach (var n in nisser) { n.State = 2; n.StateTimer = seconds; }
        }

        // Number of nisser above/below the chosen count right now (drifts by at most ±2).
        int nisseOffset;
        float nisseChangeTimer = 90;

        void UpdateNisser(float dt)
        {
            // Every 1½–3 minutes a nisse arrives or leaves. The offset is pulled back toward 0, so the
            // number swings a little up and down but stays around the chosen count over time.
            nisseChangeTimer -= dt;
            if (nisseChangeTimer <= 0)
            {
                // JULE_NISSE_SECONDS=N changes the interval (for testing)
                float over;
                nisseChangeTimer = float.TryParse(Environment.GetEnvironmentVariable("JULE_NISSE_SECONDS"), System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture, out over) && over > 0 ? over : 90 + Rnd() * 90;
                if (nisseOffset == 0) nisseOffset = Rnd() < 0.5f ? -1 : 1;
                else if (Rnd() < 0.7f) nisseOffset += nisseOffset > 0 ? -1 : 1;
                else nisseOffset = Math.Max(-2, Math.Min(2, nisseOffset + (nisseOffset > 0 ? 1 : -1)));
            }
            int target = NisserOn ? Math.Max(1, cfg.NisseCount + nisseOffset) : 0;
            int staying = 0;
            foreach (var n in nisser) if (!n.Leaving) staying++;
            if (staying < target)
            {
                // At start-up everyone is already there; later arrivals walk in from a screen edge.
                bool arriving = nisser.Count > 0 || c.Time > 2;
                for (int i = 0; i < (arriving ? 1 : target - staying); i++) AddNisse(arriving);
            }
            else if (staying > target)
            {
                if (!NisserOn) nisser.Clear();
                else
                {
                    Nisse n = null;
                    for (int i = nisser.Count - 1; i >= 0 && n == null; i--)
                        if (!nisser[i].Leaving && !nisser[i].Entering && !nisser[i].Crossing) n = nisser[i];
                    if (n != null)
                    {
                        // Walks off at an edge with no screen beyond it if there is one (so the count really goes
                        // down), otherwise at the nearest edge, where it crosses to the neighbouring screen.
                        n.Leaving = true;
                        n.State = 0;
                        bool leftFree = c.Neighbor(this, -1) == null, rightFree = c.Neighbor(this, 1) == null;
                        if (leftFree != rightFree) n.Dir = leftFree ? -1 : 1;
                        else n.Dir = n.X < W / 2 ? -1 : 1;
                    }
                }
            }

            MeetNisser();
            foreach (var n in nisser)
            {
                n.MeetCooldown = Math.Max(0, n.MeetCooldown - dt);
                if (n.MeetTimer > 0)
                {
                    float before = n.MeetTimer;
                    n.MeetTimer -= dt;
                    // halfway through the meeting the gift changes hands
                    if (before > MeetTime / 2 && n.MeetTimer <= MeetTime / 2 && n.MeetWith != null) ExchangeGifts(n, n.MeetWith);
                    if (n.MeetTimer <= 0)
                    {
                        // say goodbye and walk on, each in its own direction (past each other)
                        n.MeetWith = null;
                        n.State = 0;
                        n.StateTimer = 4 + Rnd() * 6;
                        n.MeetCooldown = 20;
                    }
                    n.T += dt;
                    continue;
                }
                // Wrap at 200π (a whole number of periods for both the wave and the hat sway) so the
                // float never grows large enough to lose precision during long uptimes.
                n.T += dt;
                if (n.T > 200 * (float)Math.PI) n.T -= 200 * (float)Math.PI;
                n.StateTimer -= dt;
                if (n.State == 0)
                {
                    n.X += n.Dir * n.Speed * dt;
                    n.WalkPhase += dt * n.Speed / (4.5f * S);
                    if (n.Entering && n.X > 30 * S && n.X < W - 30 * S) n.Entering = false;
                    if (!n.Entering && !n.Leaving && !n.Crossing)
                    {
                        // At an edge with a neighbouring screen, about half the nisser walk on over to it.
                        if (n.X < 30 * S)
                        {
                            if (c.Neighbor(this, -1) != null && Rnd() < 0.5f) n.Crossing = true; else { n.X = 30 * S; n.Dir = 1; }
                        }
                        if (n.X > W - 30 * S)
                        {
                            if (c.Neighbor(this, 1) != null && Rnd() < 0.5f) n.Crossing = true; else { n.X = W - 30 * S; n.Dir = -1; }
                        }
                    }
                    // no stopping or turning while arriving, leaving or crossing to another screen
                    if (n.Entering || n.Leaving || n.Crossing) continue;
                    if (n.StateTimer <= 0)
                    {
                        float r = Rnd();
                        if (r < 0.3f) { n.State = 1; n.StateTimer = 2 + Rnd() * 3; }
                        else if (r < 0.5f) { n.State = 2; n.StateTimer = 2.5f; }
                        else { if (r < 0.7f) n.Dir = -n.Dir; n.StateTimer = 4 + Rnd() * 8; }
                    }
                }
                else if (n.Leaving) n.State = 0;   // stop waving and keep walking out
                else if (n.StateTimer <= 0)
                {
                    n.State = 0;
                    n.StateTimer = 4 + Rnd() * 8;
                    if (Rnd() < 0.4f) n.Dir = -n.Dir;
                }
            }

            // Nisser that have walked off the screen continue on the neighbouring screen in that direction,
            // if there is one; otherwise they are gone.
            for (int i = nisser.Count - 1; i >= 0; i--)
            {
                var n = nisser[i];
                if (!(n.Leaving || n.Crossing) || (n.X >= -45 * S && n.X <= W + 45 * S)) continue;
                nisser.RemoveAt(i);
                var next = c.Neighbor(this, n.Dir);
                if (next != null && NisserOn) next.ReceiveNisse(n, S);
            }
        }

        const float MeetTime = 2.4f;

        static bool FreeToMeet(Nisse n)
        {
            return n.State == 0 && n.MeetTimer <= 0 && n.MeetCooldown <= 0 && !n.Entering && !n.Leaving && !n.Crossing;
        }

        // Two nisser walking toward each other stop when they meet, if at least one of them carries a gift.
        void MeetNisser()
        {
            foreach (var a in nisser)
            {
                if (!FreeToMeet(a)) continue;
                foreach (var b in nisser)
                {
                    if (b == a || !FreeToMeet(b) || a.Dir == b.Dir || !(a.CarriesGift || b.CarriesGift)) continue;
                    float d = b.X - a.X;
                    // b is in front of a, close enough to reach out
                    if (d * a.Dir <= 0 || Math.Abs(d) >= 24 * S * (a.Size + b.Size) / 2) continue;
                    a.MeetTimer = b.MeetTimer = MeetTime;
                    a.State = b.State = 1;
                    a.MeetWith = b;
                    b.MeetWith = null;
                    return;   // one meeting at a time is plenty
                }
            }
        }

        // One gift: it goes to the other nisse. Two gifts: they swap.
        static void ExchangeGifts(Nisse a, Nisse b)
        {
            if (a.CarriesGift && b.CarriesGift)
            {
                var t = a.Gift; a.Gift = b.Gift; b.Gift = t;
            }
            else
            {
                Nisse giver = a.CarriesGift ? a : b, taker = a.CarriesGift ? b : a;
                taker.CarriesGift = true;
                taker.Gift = giver.Gift;
                giver.CarriesGift = false;
            }
            ErrorLog.Debug("nisser mødtes: gave " + (a.CarriesGift && b.CarriesGift ? "byttet" : "overrakt"));
        }

        void AddNisse(bool walkingIn)
        {
            var n = new Nisse();
            n.Dir = Rnd() < 0.5f ? -1 : 1;
            if (walkingIn)
            {
                n.Entering = true;
                n.X = n.Dir > 0 ? -40 * S : W + 40 * S;
            }
            else n.X = 60 * S + Rnd() * (W - 120 * S);
            n.Speed = (22 + Rnd() * 18) * S;
            n.Size = 0.85f + Rnd() * 0.3f;
            n.Tunic = Tunics[rnd.Next(Tunics.Length)];
            n.Mitten = n.Tunic.R > 140 ? Color.FromArgb(40, 105, 65) : HatRed;
            n.CarriesGift = Rnd() < 0.4f;
            n.Gift = Gifts[rnd.Next(Gifts.Length)];
            n.StateTimer = 4 + Rnd() * 6;
            n.T = Rnd() * 10;
            nisser.Add(n);
        }

        // A nisse arriving from the neighbouring screen: it walks in at the matching edge, same clothes and direction.
        public void ReceiveNisse(Nisse n, float fromScale)
        {
            n.Crossing = false;
            n.Leaving = false;
            n.Entering = true;
            n.State = 0;
            n.Speed = n.Speed / fromScale * S;
            n.X = n.Dir > 0 ? -40 * S : W + 40 * S;
            n.StateTimer = 4 + Rnd() * 6;
            nisser.Add(n);
            ErrorLog.Debug("nisse crossed to screen x=" + ScreenBounds.X + " dir=" + n.Dir + " (" + nisser.Count + " here now)");
        }

        void DrawNisse(Nisse n)
        {
            float sc = S * n.Size;
            float gy = groundY - HeapAt(n.X) + 2 * S;
            Mark(n.X - 32 * sc, gy - 72 * sc, 64 * sc, 80 * sc);

            var st = g.Save();
            g.TranslateTransform(n.X, gy);
            g.ScaleTransform(n.Dir * sc, sc);
            if (c.Autumn) { DrawAnimal(n); g.Restore(st); return; }
            switch (c.WalkerFolk)
            {
                case Folk.Alfer: DrawElf(n); g.Restore(st); return;
                case Folk.Wichtel: DrawWichtel(n); g.Restore(st); return;
                case Folk.Kabouter: DrawKabouter(n); g.Restore(st); return;
                case Folk.Paekapikk: DrawPaekapikk(n); g.Restore(st); return;
            }

            bool walking = n.State == 0;
            float p = n.WalkPhase;
            float legA = walking ? (float)Math.Sin(p) * 0.55f : 0f;
            float bob = walking ? -Math.Abs((float)Math.Sin(p)) * 1.5f : 0f;

            using (var shadow = new SolidBrush(Color.FromArgb(50, 60, 80, 110))) g.FillEllipse(shadow, -11, -2, 22, 4);

            using (var pants = new Pen(Color.FromArgb(80, 80, 92), 5f))
            using (var boot = new SolidBrush(Color.FromArgb(62, 40, 28)))
            {
                pants.StartCap = pants.EndCap = LineCap.Round;
                NisseLeg(pants, boot, -2, -15 + bob, legA);
                NisseLeg(pants, boot, 2, -15 + bob, -legA);
            }

            g.TranslateTransform(0, bob);
            float backArm, frontArm;
            if (n.State == 2) { backArm = -legA * 0.8f; frontArm = 2.5f + (float)Math.Sin(n.T * 11) * 0.45f; }
            else if (n.CarriesGift) { backArm = 1.3f; frontArm = 1.3f; }
            else { backArm = -legA * 0.9f; frontArm = legA * 0.9f; }

            using (var tunic = new SolidBrush(n.Tunic))
            using (var armPen = new Pen(n.Tunic, 4.2f))
            using (var mitten = new SolidBrush(n.Mitten))
            {
                armPen.StartCap = armPen.EndCap = LineCap.Round;
                NisseArm(armPen, mitten, -1, -29, backArm);
                g.FillEllipse(tunic, -10, -34, 20, 22);
                using (var belt = new SolidBrush(Color.FromArgb(35, 30, 30))) g.FillRectangle(belt, -9.5f, -20, 19, 3);
                using (var buckle = new SolidBrush(Gold)) g.FillRectangle(buckle, 2, -20.5f, 3.5f, 4);

                if (n.CarriesGift && n.State != 2)
                {
                    using (var gift = new SolidBrush(n.Gift)) g.FillRectangle(gift, 6, -31, 11, 10);
                    using (var rib = new Pen(Gold, 1.6f))
                    {
                        g.DrawLine(rib, 11.5f, -31, 11.5f, -21);
                        g.DrawLine(rib, 6, -26, 17, -26);
                        g.DrawEllipse(rib, 9, -34, 3, 3);
                        g.DrawEllipse(rib, 12, -34, 3, 3);
                    }
                }

                using (var skin = new SolidBrush(Skin)) g.FillEllipse(skin, -6, -44, 13, 12);
                using (var beard = new GraphicsPath())
                {
                    beard.AddBezier(-6, -39, -7, -30, -2, -22, 3, -20);
                    beard.AddBezier(3, -20, 7, -24, 9, -32, 7.5f, -39);
                    beard.CloseFigure();
                    using (var white = new SolidBrush(Color.FromArgb(250, 250, 250))) g.FillPath(white, beard);
                }
                NisseArm(armPen, mitten, 1, -29, frontArm);
                using (var nose = new SolidBrush(Color.FromArgb(240, 160, 150))) g.FillEllipse(nose, 4, -40, 5, 5);

                float sway = (float)Math.Sin(walking ? p * 0.5f : n.T * 1.5f) * 2.5f;
                float tipX = -14 + sway, tipY = -57;
                using (var hat = new GraphicsPath())
                {
                    hat.AddLine(-7.5f, -39, 8, -39);
                    hat.AddBezier(8, -39, 9, -54, 0, -62, tipX, tipY);
                    hat.AddBezier(tipX, tipY, -6, -57, -7, -49, -7.5f, -39);
                    hat.CloseFigure();
                    using (var hb = new SolidBrush(HatRed)) g.FillPath(hb, hat);
                }
                using (var brim = new Pen(Color.FromArgb(150, 15, 25), 2f)) g.DrawLine(brim, -7.5f, -39.5f, 8, -39.5f);
                using (var pom = new SolidBrush(Color.White)) g.FillEllipse(pom, tipX - 3, tipY - 3, 6, 6);
            }
            g.Restore(st);
        }

        void NisseLeg(Pen pants, Brush boot, float hx, float hy, float a)
        {
            float fx = hx + (float)Math.Sin(a) * 12, fy = hy + (float)Math.Cos(a) * 12;
            g.DrawLine(pants, hx, hy, fx, fy);
            g.FillEllipse(boot, fx - 3, fy - 2, 9, 5);
        }

        void NisseArm(Pen arm, Brush mitten, float sx, float sy, float a)
        {
            float hx = sx + (float)Math.Sin(a) * 10, hy = sy + (float)Math.Cos(a) * 10;
            g.DrawLine(arm, sx, sy, hx, hy);
            g.FillEllipse(mitten, hx - 2.5f, hy - 2.5f, 5, 5);
        }

        // ------------------------------------------------------------------ julelys
        static readonly Color[] BulbColors = {
            Color.FromArgb(255, 60, 60), Color.FromArgb(60, 220, 90), Color.FromArgb(255, 200, 60),
            Color.FromArgb(80, 150, 255), Color.FromArgb(255, 110, 200) };

        // Updates the cached strip; returns true when it must be drawn this frame (see DrawLightsStrip).
        bool PrepareLights(float dt, bool damaged)
        {
            int lh = LightsHeight;
            if (lightsBmp == null || lightsBmp.Width != W || lightsBmp.Height != lh)
            {
                if (lightsBmp != null) lightsBmp.Dispose();
                lightsBmp = new Bitmap(W, lh, PixelFormat.Format32bppPArgb);
                lightsTimer = 0;
            }
            lightsTimer -= dt;
            bool rerendered = false;
            if (lightsTimer <= 0)
            {
                lightsTimer = PS ? 0.25f : 0.1f;   // the twinkle is slow, so 4 updates/s is enough in power-save mode
                using (var lg = Graphics.FromImage(lightsBmp))
                {
                    lg.SmoothingMode = SmoothingMode.AntiAlias;
                    lg.Clear(Color.Transparent);
                    RenderLights(lg);
                }
                rerendered = true;
            }
            // Normal mode redraws the strip every frame. Power-save mode leaves it in the buffer and only
            // draws it again when it changed or something else cleared part of it.
            bool draw = !PS || rerendered || damaged || !lightsShown;
            if (!PS) Mark(0, 0, W, lh);
            lightsShown = true;
            return draw;
        }

        // Blends the strip over what is already drawn (the strip area was cleared earlier this frame).
        void DrawLightsStrip()
        {
            g.CompositingMode = CompositingMode.SourceOver;
            g.DrawImageUnscaled(lightsBmp, 0, 0);
        }

        void RenderLights(Graphics lg)
        {
            if (c.Autumn) { RenderGarland(lg); return; }
            float span = 230 * S, sag = 22 * S, top = 1;
            int perSpan = 4, idx = 0;
            using (var wire = new Pen(Color.FromArgb(220, 25, 60, 35), 2f * S))
            using (var socket = new SolidBrush(Color.FromArgb(255, 30, 70, 40)))
            {
                for (float x0 = -span * 0.3f; x0 < W; x0 += span)
                {
                    var pts = new PointF[13];
                    for (int k = 0; k <= 12; k++)
                    {
                        float u = k / 12f;
                        pts[k] = new PointF(x0 + u * span, top + sag * (1 - (2 * u - 1) * (2 * u - 1)));
                    }
                    lg.DrawCurve(wire, pts);

                    for (int b = 0; b < perSpan; b++, idx++)
                    {
                        float u = (b + 0.5f) / perSpan;
                        float bx = x0 + u * span, by = top + sag * (1 - (2 * u - 1) * (2 * u - 1));
                        Color col = BulbColors[idx % BulbColors.Length];
                        float br = 0.55f + 0.45f * (float)Math.Sin(c.Time * (1.3 + (idx * 37 % 10) * 0.12) + idx * 1.7);
                        float w = 7 * S, h = 11 * S;
                        using (var glow = new SolidBrush(Color.FromArgb((int)(70 * br), col)))
                            lg.FillEllipse(glow, bx - 13 * S, by + 1 * S, 26 * S, 26 * S);
                        lg.FillRectangle(socket, bx - 2.5f * S, by, 5 * S, 4 * S);
                        Color bc = Color.FromArgb(255,
                            (int)(col.R * (0.5f + 0.5f * br)), (int)(col.G * (0.5f + 0.5f * br)), (int)(col.B * (0.5f + 0.5f * br)));
                        using (var bulb = new SolidBrush(bc)) lg.FillEllipse(bulb, bx - w / 2, by + 3 * S, w, h);
                        using (var shine = new SolidBrush(Color.FromArgb((int)(160 * br), 255, 255, 255)))
                            lg.FillEllipse(shine, bx - w / 4, by + 5 * S, w / 3, h / 3);
                    }
                }
            }
        }
    }
}
