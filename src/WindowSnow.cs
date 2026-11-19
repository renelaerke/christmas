using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace JuleHygge
{
    // Snow on the top edge of other apps' windows (not fullscreen or maximized ones). Some of the falling flakes
    // land there; when the window goes away (minimized, closed, hidden, another virtual desktop) the snow falls
    // down as clumps and lands in the pile at the bottom. All in global screen coordinates, so a window that
    // spans two screens carries one pile. Ported from macos/Sources/JuleHygge/WindowSnow.swift; the macOS
    // sizes are in points, here they are scaled by the system DPI (Ledge.U).
    sealed class Ledge
    {
        public static float U = 1;                      // pixels per macOS point (primary screen DPI / 96)
        public static float Step { get { return 4 * U; } }

        public readonly long Id;
        public RectangleF Rect;
        // Where the window last stood still. The snow sits there: while a window moves (or shrinks when it is
        // minimized) the pile stays put, and if the window goes away, the snow falls from this spot.
        public RectangleF Settled;
        public float[] Cols;    // snow height per Step from the window's left edge
        // How far the snow hangs down over the edge (in front of the window), per column. It creeps out slowly
        // once the pile is deep, in uneven lobes (fixed per window) and a little more around the corners.
        public float[] Hang;
        float[] lobes;
        public List<float[]> Visible = new List<float[]>();   // parts of the top edge (global x) not covered by a window in front
        public bool Moving;     // true while the window is moved or resized: the pile is hidden and catches nothing
        public bool HasSnow;

        public Ledge(long id, RectangleF rect)
        {
            Id = id; Rect = rect; Settled = rect;
            Cols = new float[(int)(rect.Width / Step) + 1];
            Hang = new float[Cols.Length];
            MakeLobes();
        }

        // Uneven drapes: two slow waves with a phase from the window id, sharpened so some places hang well
        // down and others hardly at all.
        void MakeLobes()
        {
            float p1 = (float)(Math.Abs(Id) % 97) * 0.61f, p2 = (float)(Math.Abs(Id) % 89) * 1.37f;
            lobes = new float[Cols.Length];
            for (int i = 0; i < lobes.Length; i++)
            {
                double v = 0.5 + 0.5 * (0.6 * Math.Sin(i * 0.23 + p1) + 0.4 * Math.Sin(i * 0.57 + p2));
                lobes[i] = (float)Math.Pow(Math.Max(0, Math.Min(1, v)), 2.2);
            }
        }
        public float Lobe(int i) { return lobes[i]; }

        int Index(float x) { return (int)((x - Settled.Left) / Step); }
        public float HeightAt(float x) { int i = Index(x); return i >= 0 && i < Cols.Length ? Cols[i] : 0; }
        public float HangAt(float x) { int i = Index(x); return i >= 0 && i < Hang.Length ? Hang[i] : 0; }

        public bool IsVisible(float x)
        {
            foreach (var seg in Visible) if (x >= seg[0] && x <= seg[1]) return true;
            return false;
        }

        // r is the flake radius without the screen scale (about 1–4.5).
        public void Deposit(float x, float r)
        {
            int i = Index(x);
            float amount = 0.3f * r * U;
            for (int k = -1; k <= 1; k++)
                if (i + k >= 0 && i + k < Cols.Length) Cols[i + k] += k == 0 ? amount : amount * 0.5f;
            HasSnow = true;
        }

        // Keeps the width in step with the window, keeping the snow that is still on it.
        public void Resize(float width)
        {
            int n = (int)(width / Step) + 1;
            Array.Resize(ref Cols, n);
            Array.Resize(ref Hang, n);
            MakeLobes();
        }
    }

    // A lump of snow falling off a window that went away; the overlay below catches it in its ground pile.
    sealed class SnowClump
    {
        public float X, Y, VX, VY, R;   // R in macOS points (drawn and deposited scaled by the screen's S)
        public bool Dead;
    }

    partial class Controller
    {
        public readonly Dictionary<long, Ledge> Ledges = new Dictionary<long, Ledge>();
        public readonly List<Ledge> LedgeList = new List<Ledge>();
        public readonly List<SnowClump> Clumps = new List<SnowClump>();

        sealed class WinInfo { public long Id; public RectangleF Rect; public List<float[]> Visible; }

        delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc proc, IntPtr lParam);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
        [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr hWnd);
        [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int index);
        [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hWnd, int cmd);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
        [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out int value, int size);
        [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out RECT value, int size);
        const int GWL_EXSTYLE = -20, GW_OWNER = 4, DWMWA_EXTENDED_FRAME_BOUNDS = 9, DWMWA_CLOAKED = 14;
        const int WS_EX_TRANSPARENT = 0x20, WS_EX_TOOLWINDOW = 0x80, WS_EX_APPWINDOW = 0x40000, WS_EX_NOACTIVATE = 0x8000000;
        static readonly uint myPid = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;

        bool LedgeMoving()
        {
            foreach (var l in LedgeList) if (l.Moving && l.HasSnow) return true;
            return false;
        }

        // Windows that can carry snow, front to back, each with the parts of its top edge not hidden by a window
        // in front. Maximized windows (top edge at the screen top, so the pile would be off-screen) and
        // fullscreen windows carry no snow but still hide what is behind them.
        List<WinInfo> ScanWindows()
        {
            var occluders = new List<RectangleF>();
            var result = new List<WinInfo>();
            var screens = new List<Rectangle>();
            foreach (var l in layers) screens.Add(l.ScreenBounds);
            float u = Ledge.U, pileRoom = 16 * u;   // a window in front just above the edge still hides the snow
            var cls = new StringBuilder(64);
            EnumWindows((h, p) =>
            {
                if (!IsWindowVisible(h) || IsIconic(h)) return true;
                uint pid; GetWindowThreadProcessId(h, out pid);
                if (pid == myPid) return true;
                int ex = GetWindowLong(h, GWL_EXSTYLE);
                if ((ex & (WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT)) != 0) return true;
                if (GetWindow(h, GW_OWNER) != IntPtr.Zero && (ex & WS_EX_APPWINDOW) == 0) return true;
                int cloaked;
                if (DwmGetWindowAttribute(h, DWMWA_CLOAKED, out cloaked, 4) == 0 && cloaked != 0) return true;   // other desktop, hidden UWP
                cls.Length = 0; GetClassName(h, cls, cls.Capacity);
                string c = cls.ToString();
                if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd" || c == "Shell_SecondaryTrayWnd") return true;
                RECT r;
                if (DwmGetWindowAttribute(h, DWMWA_EXTENDED_FRAME_BOUNDS, out r, Marshal.SizeOf(typeof(RECT))) != 0 && !GetWindowRect(h, out r)) return true;
                var rect = RectangleF.FromLTRB(r.Left, r.Top, r.Right, r.Bottom);
                if (rect.Width < 2 || rect.Height < 2) return true;

                bool full = false, topOnScreen = false;
                foreach (var s in screens)
                {
                    if (Math.Abs(s.Left - rect.Left) < 2 && Math.Abs(s.Top - rect.Top) < 2 && Math.Abs(s.Width - rect.Width) < 2 && Math.Abs(s.Height - rect.Height) < 2) full = true;
                    float mx = rect.Left + rect.Width / 2;
                    if (mx >= s.Left && mx < s.Right && rect.Top + 1 >= s.Top + 12 * u && rect.Top + 1 < s.Bottom) topOnScreen = true;
                }
                if (!full && !IsZoomed(h) && topOnScreen && rect.Width >= 150 * u && rect.Height >= 80 * u)
                {
                    // the top edge minus the parts covered by windows in front
                    float y = rect.Top;
                    var vis = new List<float[]> { new[] { rect.Left + 6 * u, rect.Right - 6 * u } };   // rounded corners
                    foreach (var f in occluders)
                    {
                        if (!(f.Top < y + 1 && f.Bottom > y - pileRoom)) continue;
                        var next = new List<float[]>();
                        foreach (var seg in vis)
                        {
                            if (f.Right <= seg[0] || f.Left >= seg[1]) { next.Add(seg); continue; }
                            if (f.Left > seg[0]) next.Add(new[] { seg[0], f.Left });
                            if (f.Right < seg[1]) next.Add(new[] { f.Right, seg[1] });
                        }
                        vis = next;
                    }
                    vis.RemoveAll(s => s[1] - s[0] < 8 * u);
                    result.Add(new WinInfo { Id = h.ToInt64(), Rect = rect, Visible = vis });
                }
                occluders.Add(rect);
                return true;
            }, IntPtr.Zero);
            return result;
        }

        // Matches the scanned windows with the existing ledges: windows that moved hide their snow until they
        // settle, and windows that are gone let their snow fall.
        void UpdateLedges(List<WinInfo> wins)
        {
            var seen = new HashSet<long>();
            foreach (var w in wins)
            {
                seen.Add(w.Id);
                Ledge l;
                if (Ledges.TryGetValue(w.Id, out l))
                {
                    if (l.Rect != w.Rect) { l.Rect = w.Rect; l.Moving = true; }
                    else if (l.Moving)
                    {
                        // came to rest: the snow moves along (and keeps what still fits on a resized window)
                        if (l.Settled.Width != l.Rect.Width) l.Resize(l.Rect.Width);
                        l.Settled = l.Rect;
                        l.Moving = false;
                    }
                    l.Visible = w.Visible;
                }
                else
                {
                    l = new Ledge(w.Id, w.Rect);
                    l.Visible = w.Visible;
                    Ledges[w.Id] = l;
                }
            }
            var gone = new List<long>();
            foreach (var kv in Ledges) if (!seen.Contains(kv.Key)) gone.Add(kv.Key);
            foreach (var id in gone)
            {
                if (Ledges[id].HasSnow) DropSnow(Ledges[id]);
                Ledges.Remove(id);
            }
            LedgeList.Clear();
            LedgeList.AddRange(Ledges.Values);
        }

        // The window went away: its snow falls as clumps, straight down from where the window stood.
        void DropSnow(Ledge l)
        {
            float u = Ledge.U;
            // At most 700 clumps fall at a time. The room that is left is shared evenly along the whole edge:
            // filling it from the left let a wide window (a maximized one needs well over 700) drop its snow
            // from its left part only, as if the window were narrower.
            int wanted = 0;
            for (int i = 0; i < l.Cols.Length; i++)
            {
                float h = l.Cols[i] + l.Hang[i];
                if (h > 0.5f * u) wanted += Math.Min(4, (int)(h / (2.5f * u)) + 1);
            }
            int room = Math.Max(60, 700 - Clumps.Count);
            float keep = wanted > room ? (float)room / wanted : 1f;
            float bigger = Math.Min(1.5f, (float)Math.Sqrt(1 / keep));   // fewer clumps carry a little more each
            for (int i = 0; i < l.Cols.Length; i++)
            {
                float h = l.Cols[i] + l.Hang[i];
                if (h <= 0.5f * u) continue;
                int n = Math.Min(4, (int)(h / (2.5f * u)) + 1);
                for (int k = 0; k < n; k++)
                {
                    if (R() >= keep) continue;
                    var c = new SnowClump();
                    c.X = l.Settled.Left + i * Ledge.Step + R() * Ledge.Step;
                    c.Y = l.Settled.Top - R() * h;
                    c.VX = (R() - 0.5f) * 6 * u;
                    c.VY = R() * 20 * u;
                    c.R = (1.6f + R() * 1.8f) * bigger;
                    Clumps.Add(c);
                }
            }
            ErrorLog.Debug("window " + l.Id + " gone: " + Clumps.Count + " clumps falling");
        }

        // When the snow hangs far down somewhere, or the pile is nearly full, there is about a 1-in-15 chance per
        // second that a 20–50 pt stretch around the heaviest visible spot breaks off: the drape and most of the
        // pile above it fall as clumps (softly tapered at the ends of the break), and the edge then fills up again.
        // Ported from macOS (PR #3), with the cheap checks first and hidden columns skipped.
        void BreakOff(Ledge l, float dt)
        {
            float u = Ledge.U;
            int n = l.Cols.Length;
            if (n <= 8 || R() >= dt / 15) return;
            float maxHang = 0, maxCol = 0;
            for (int i = 0; i < n; i++) { maxHang = Math.Max(maxHang, l.Hang[i]); maxCol = Math.Max(maxCol, l.Cols[i]); }
            bool full = maxHang > 9 * u || maxCol > (EffectiveSnowLevel == 2 ? 12.5f : 9) * u;
            if (!full) return;
            int best = -1; float bestLoad = 0;
            for (int i = 0; i < n; i++)
            {
                if (!l.IsVisible(l.Settled.Left + i * Ledge.Step)) continue;
                float load = l.Hang[i] + l.Cols[i] * 0.5f;
                if (load > bestLoad) { bestLoad = load; best = i; }
            }
            if (best < 0) return;
            int half = 2 + (int)(R() * 5);   // 5–13 columns ≈ 20–50 pt
            for (int j = Math.Max(0, best - half); j <= Math.Min(n - 1, best + half); j++)
            {
                float x = l.Settled.Left + j * Ledge.Step;
                if (!l.IsVisible(x)) continue;   // a part hidden behind a window in front stays put
                float k = 1 - (float)Math.Abs(j - best) / (half + 1);    // 1 in the middle, tapering toward the ends
                float fall = 0.5f + 0.5f * (float)Math.Cos((1 - k) * Math.PI);   // soft edges of the break
                float dropPile = l.Cols[j] * 0.65f * fall, dropHang = l.Hang[j] * fall;
                l.Cols[j] -= dropPile; l.Hang[j] -= dropHang;
                float amount = dropPile + dropHang;
                if (amount <= 0.4f * u) continue;
                int count = Math.Min(4, (int)(amount / (2.5f * u)) + 1);
                for (int c = 0; c < count && Clumps.Count < 700; c++)
                {
                    var cl = new SnowClump();
                    cl.X = x + R() * Ledge.Step;
                    cl.Y = l.Settled.Top - dropPile * R() + dropHang * R();   // from the pile's top down to the drape's end
                    cl.VX = ((R() - 0.5f) * 8 + Wind * 0.05f) * u;
                    cl.VY = R() * 15 * u;
                    cl.R = 1.6f + R() * 2;
                    Clumps.Add(cl);
                }
            }
            ErrorLog.Debug("window " + l.Id + ": snow broke off at column " + best + " (" + (half * 2 + 1) + " columns)");
        }

        // Settles each pile (slopes, rounded ends, no higher than ~10 pt), melts it when snow is off, lets the
        // snowstorm push it into drifts, grows the drape over the edge, and moves the falling clumps.
        void UpdateWindowSnow(float dt)
        {
            float u = Ledge.U;
            bool melt = !SnowOn || !Cfg.WindowSnow;
            if ((int)(Time / 5) != (int)((Time - dt) / 5) && LedgeList.Count > 0)
            {
                var sb = new StringBuilder("ledges:");
                foreach (var l in LedgeList)
                {
                    float mx = 0; foreach (var v in l.Cols) mx = Math.Max(mx, v);
                    sb.Append(" | ").Append(l.Id).Append(' ').Append((int)l.Settled.Left).Append(',').Append((int)l.Settled.Top)
                      .Append(" w").Append((int)l.Settled.Width).Append(" vis").Append(l.Visible.Count).Append(" mov").Append(l.Moving)
                      .Append(" max").Append(mx.ToString("F1", System.Globalization.CultureInfo.InvariantCulture));
                }
                ErrorLog.Debug(sb.ToString());
            }
            // in a snowstorm the wind pushes the snow along the edge, so it drifts up against the downwind end
            bool storm = EffectiveSnowLevel == 2 && !melt;
            float windNorm = Math.Max(-1.5f, Math.Min(1.5f, Wind / 140));
            float maxH = (storm ? 14 : 10) * u, slope = 1.4f * u;
            foreach (var l in LedgeList)
            {
                if (!l.HasSnow) continue;
                bool any = false;
                int n = l.Cols.Length;
                if (storm && Math.Abs(windNorm) > 0.15f && n > 2)
                {
                    float rate = 0.03f * Math.Abs(windNorm) * dt;
                    int dir = windNorm > 0 ? 1 : -1;
                    var moved = new float[n];
                    for (int i = 0; i < n; i++) moved[i] = l.Cols[i] * rate;
                    for (int i = 0; i < n; i++)
                    {
                        int j = i + dir;
                        if (j < 0 || j >= n) continue;   // the end column keeps what reaches it: the drift
                        l.Cols[i] -= moved[i]; l.Cols[j] += moved[i];
                    }
                }
                for (int i = 0; i < n - 1; i++)
                {
                    float d = l.Cols[i] - l.Cols[i + 1];
                    if (d > slope) { float m = (d - slope) * 0.3f; l.Cols[i] -= m; l.Cols[i + 1] += m; }
                    else if (d < -slope) { float m = (-d - slope) * 0.3f; l.Cols[i] += m; l.Cols[i + 1] -= m; }
                }
                for (int i = 0; i < n; i++)
                {
                    float edge = Math.Min(i, n - 1 - i) * Ledge.Step;
                    // snow rounds off toward the window's corners; in a storm the downwind end builds a steeper drift
                    bool downwindEnd = storm && ((windNorm > 0.15f && i > n / 2) || (windNorm < -0.15f && i < n / 2));
                    // a full pile keeps soft bumps on top: the height limit itself wavers along the edge
                    float bumps = 0.72f + 0.28f * (float)(Math.Sin(i * 0.41 + l.Id % 53) * 0.6 + Math.Sin(i * 0.97 + l.Id % 31) * 0.4);
                    float cap = Math.Min(maxH * bumps, Math.Max(0, edge - (downwindEnd ? 2 : 6) * u) * (downwindEnd ? 1.0f : 0.5f));
                    if (melt) l.Cols[i] = Math.Max(0, l.Cols[i] - 3 * u * dt);
                    // above the cap it settles back slowly (a drift sinks after the storm instead of being cut off)
                    if (l.Cols[i] > cap) l.Cols[i] = Math.Max(cap, l.Cols[i] - Math.Max(2 * u * dt, l.Cols[i] - cap - 6 * u));
                    if (l.Cols[i] > 0.3f * u) any = true;
                }
                // the drape: once the pile is deeper than ~3 pt it creeps over the edge (~0.7 pt/s), as far as the
                // lobes allow, a bit further near the corners where the snow rounds over; it melts back quicker
                for (int i = 0; i < n; i++)
                {
                    float s = 0; int k = 0;
                    for (int j = Math.Max(0, i - 3); j <= Math.Min(n - 1, i + 3); j++) { s += l.Cols[j]; k++; }
                    float pile = s / k;
                    float edge = Math.Min(i, n - 1 - i) * Ledge.Step;
                    float corner = edge < 24 * u ? 1 + (24 * u - edge) / (24 * u) * 0.6f : 1;
                    float target = melt ? 0 : Math.Max(0, pile - 3 * u) * 2.6f * (0.12f + 0.88f * l.Lobe(i)) * corner;
                    float old = l.Hang[i];
                    l.Hang[i] = target > old ? Math.Min(target, old + 0.7f * u * dt) : Math.Max(target, old - 3 * u * dt);
                    if (l.Hang[i] > 0.3f * u) any = true;
                }
                // a full edge does not just keep growing: now and then a heavy stretch breaks off and falls
                if (!melt && any && !l.Moving) BreakOff(l, dt);
                l.HasSnow = any;
            }

            if (Clumps.Count > 0)
            {
                float bottom = 0;
                foreach (var l in layers) bottom = Math.Max(bottom, l.ScreenBounds.Bottom);
                foreach (var c in Clumps)
                {
                    c.VY += 700 * u * dt;
                    c.X += c.VX * dt;
                    c.Y += c.VY * dt;
                }
                Clumps.RemoveAll(c => c.Dead || c.Y > bottom + 50);
            }
        }
    }
}
