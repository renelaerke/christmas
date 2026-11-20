using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;

namespace JuleHygge
{
    // The autumn theme's figures (Controller.Autumn), ported from the macOS version (Overlay.swift), where each
    // Christmas element has its autumn form. The drawing is kept line for line the same as there: the helpers
    // below have the same shape as the macOS version's (Util.swift), with y pointing down.
    // The leaves and their piles are in Layer.cs, beside the snow they stand in for.
    partial class Layer
    {
        static Color C(int r, int gr, int b) { return Color.FromArgb(r, gr, b); }
        static Color C(int r, int gr, int b, int a) { return Color.FromArgb(a, r, gr, b); }

        // Where the helpers draw: the screen's surface, or a cached picture while one is being made (see `into`).
        Graphics into;
        Graphics T { get { return into ?? g; } }

        readonly Dictionary<int, SolidBrush> brushes = new Dictionary<int, SolidBrush>();
        SolidBrush Br(Color c)
        {
            SolidBrush b;
            if (!brushes.TryGetValue(c.ToArgb(), out b)) { b = new SolidBrush(c); brushes[c.ToArgb()] = b; }
            return b;
        }

        void DisposeAutumn()
        {
            foreach (var b in brushes.Values) b.Dispose();
            brushes.Clear();
            if (garlandBmp != null) { garlandBmp.Dispose(); garlandBmp = null; }
        }

        void FillEllipse(Color c, float x, float y, float w, float h) { T.FillEllipse(Br(c), x, y, w, h); }
        void FillRect(Color c, float x, float y, float w, float h) { T.FillRectangle(Br(c), x, y, w, h); }

        void StrokeEllipse(Color c, float width, float x, float y, float w, float h)
        {
            using (var p = new Pen(c, width)) T.DrawEllipse(p, x, y, w, h);
        }

        void Line(Color c, float width, float x1, float y1, float x2, float y2, bool round = false)
        {
            using (var p = new Pen(c, width))
            {
                if (round) { p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; }
                T.DrawLine(p, x1, y1, x2, y2);
            }
        }

        // x0, y0, x1, y1, ...
        void FillPoly(Color c, params float[] xy)
        {
            var pts = new PointF[xy.Length / 2];
            for (int i = 0; i < pts.Length; i++) pts[i] = new PointF(xy[2 * i], xy[2 * i + 1]);
            T.FillPolygon(Br(c), pts);
        }

        void Bezier(Color c, float width, float x0, float y0, float x1, float y1, float x2, float y2, float x3, float y3)
        {
            using (var p = new Pen(c, width))
            {
                p.StartCap = LineCap.Round; p.EndCap = LineCap.Round;
                T.DrawBezier(p, x0, y0, x1, y1, x2, y2, x3, y3);
            }
        }

        // ------------------------------------------------------------------ løvranke med lygter
        // Autumn's form of the Christmas lights: a brown vine with leaves hanging from it, and small lanterns
        // where the bulbs are. The vine, the leaves and the lanterns' frames never change, so they are drawn once
        // and kept (garlandBmp); only the lanterns' lit panes twinkle and are drawn over it each time the strip
        // is made again (RenderLights).
        static readonly Color[] LanternColors = { Color.FromArgb(255, 170, 50), Color.FromArgb(255, 140, 40), Color.FromArgb(255, 200, 90) };
        Bitmap garlandBmp;

        unsafe void MakeGarland(int lh)
        {
            if (garlandBmp != null) garlandBmp.Dispose();
            garlandBmp = new Bitmap(W, lh, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            float span = 230 * S, sag = 22 * S, top = 1;
            using (var lg = Graphics.FromImage(garlandBmp))
            using (var wire = new Pen(C(104, 68, 34, 235), 2f * S))
            {
                lg.SmoothingMode = SmoothingMode.AntiAlias;
                lg.Clear(Color.Transparent);
                wire.StartCap = LineCap.Round; wire.EndCap = LineCap.Round;
                for (float x0 = -span * 0.3f; x0 < W; x0 += span)
                {
                    var pts = new PointF[25];
                    for (int k = 0; k <= 24; k++)
                    {
                        float u = k / 24f;
                        pts[k] = new PointF(x0 + u * span, top + sag * (1 - (2 * u - 1) * (2 * u - 1)));
                    }
                    lg.DrawLines(wire, pts);
                }
            }
            // leaves along the vine, each hanging by its stalk at its own angle (none where a lantern hangs)
            var data = garlandBmp.LockBits(new Rectangle(0, 0, W, lh), System.Drawing.Imaging.ImageLockMode.ReadWrite, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            uint* buf = (uint*)data.Scan0.ToPointer();
            int n = 0;
            for (float x0 = -span * 0.3f; x0 < W; x0 += span)
                for (int k = 0; k < 12; k++)
                {
                    if (k % 3 == 1) continue;
                    float u = (k + 0.5f) / 12;
                    float size = (15 + (n * 7) % 5 * 1.5f) * S;
                    float rot = (float)(Math.PI / 2 + Math.Sin(n * 2.3) * 0.8);
                    float px = x0 + u * span, py = top + sag * (1 - (2 * u - 1) * (2 * u - 1));
                    // the stalk (the left end of the leaf's picture) sits on the vine
                    float reach = size / 2 - S;
                    BlendLeaf(buf, W, lh, LeafSprite(n * 3), px + (float)Math.Cos(rot) * reach, py + (float)Math.Sin(rot) * reach, size, rot, 255);
                    n++;
                }
            garlandBmp.UnlockBits(data);
            // the lanterns: a hook, a roof, the unlit pane and a foot
            using (var lg = Graphics.FromImage(garlandBmp))
            {
                lg.SmoothingMode = SmoothingMode.AntiAlias;
                into = lg;
                Color frame = C(52, 40, 30), dim = C(120, 72, 22);
                for (float x0 = -span * 0.3f; x0 < W; x0 += span)
                    for (int b = 0; b < 4; b++)
                    {
                        float u = (b + 0.5f) / 4;
                        float bx = x0 + u * span, by = top + sag * (1 - (2 * u - 1) * (2 * u - 1));
                        Line(frame, 1.2f * S, bx, by, bx, by + 2.5f * S);
                        FillRect(frame, bx - 4.5f * S, by + 2 * S, 9 * S, 2.5f * S);
                        FillRect(dim, bx - 3.5f * S, by + 4.5f * S, 7 * S, 9 * S);
                        FillRect(frame, bx - 4.5f * S, by + 13.5f * S, 9 * S, 2 * S);
                    }
                into = null;
            }
        }

        void RenderGarland(Graphics lg)
        {
            int lh = LightsHeight;
            if (garlandBmp == null || garlandBmp.Width != W || garlandBmp.Height != lh) MakeGarland(lh);
            lg.DrawImageUnscaled(garlandBmp, 0, 0);
            float span = 230 * S, sag = 22 * S, top = 1;
            int idx = 0;
            for (float x0 = -span * 0.3f; x0 < W; x0 += span)
                for (int b = 0; b < 4; b++, idx++)
                {
                    float u = (b + 0.5f) / 4;
                    float bx = x0 + u * span, by = top + sag * (1 - (2 * u - 1) * (2 * u - 1));
                    Color col = LanternColors[idx % LanternColors.Length];
                    // the same slow twinkle as the bulbs
                    float br = 0.55f + 0.45f * (float)Math.Sin(c.Time * (1.3 + (idx * 37 % 10) * 0.12) + idx * 1.7);
                    using (var glow = new SolidBrush(Color.FromArgb((int)(70 * br), col)))
                        lg.FillEllipse(glow, bx - 13 * S, by + 1 * S, 26 * S, 26 * S);
                    // the lit pane of a small lantern, with its flame
                    using (var pane = new SolidBrush(Color.FromArgb((int)(255 * br), col)))
                        lg.FillRectangle(pane, bx - 3.5f * S, by + 4.5f * S, 7 * S, 9 * S);
                    using (var flame = new SolidBrush(Color.FromArgb((int)(230 * br), 255, 250, 215)))
                        lg.FillEllipse(flame, bx - 1.5f * S, by + 7.5f * S, 3 * S, 5 * S);
                }
        }

        // ------------------------------------------------------------------ trækgæs
        // Autumn's flyer in Santa's place: geese on their way south in a wedge, the leader in front and one arm
        // longer than the other. Each bird beats its wings in its own time and rides a little up and down.
        // (Drawn in Santa's frame: translated to his place and scaled by his size and direction.)
        void DrawGeese(float t)
        {
            float[,] places = { { 250, -35 }, { 182, -54 }, { 114, -73 }, { 46, -92 }, { -22, -111 }, { 182, -16 }, { 114, 3 }, { 46, 22 } };
            for (int i = places.GetLength(0) - 1; i >= 0; i--)
                DrawGoose(places[i, 0], places[i, 1] + (float)Math.Sin(t * 1.7 + i * 1.3) * 3, i * 1.9f, t);
        }

        // One goose flying toward +x, seen from the side: grey-brown, neck stretched out, orange beak.
        void DrawGoose(float x, float y, float phase, float t)
        {
            float flap = (float)Math.Sin(t * 7 + phase);
            Color body = C(140, 125, 105), dark = C(96, 84, 68), neck = C(118, 104, 88);
            // the far wing, a little shorter and lighter
            FillPoly(C(168, 154, 134), x + 5, y - 3, x - 7, y - 3, x - 5, y - 3 - 20 * flap, x + 3, y - 3 - 21 * flap);
            FillPoly(dark, x - 15, y - 2, x - 26, y - 0.5f, x - 15, y + 3);
            FillEllipse(body, x - 17, y - 5, 34, 10);
            FillEllipse(C(208, 198, 178), x - 11, y + 0.5f, 21, 4.5f);
            Line(neck, 3.4f, x + 14, y - 1, x + 31, y - 5, true);
            FillEllipse(neck, x + 28.5f, y - 9, 8.5f, 6.5f);
            FillPoly(C(236, 140, 36), x + 36, y - 7.2f, x + 42.5f, y - 5.4f, x + 36, y - 4.2f);
            FillEllipse(C(25, 25, 28), x + 33, y - 7.6f, 1.8f, 1.8f);
            // the near wing over the body
            FillPoly(dark, x + 8, y - 2, x - 9, y - 2, x - 11, y - 2 - 25 * flap, x - 2, y - 2 - 27 * flap);
            Line(C(70, 60, 48), 1.6f, x - 11, y - 2 - 25 * flap, x - 2, y - 2 - 27 * flap, true);
        }

        // A filled shape of curves: the start point, then three points (two control points and the end) per curve.
        void FillCurves(Color c, float x0, float y0, params float[] xy)
        {
            using (var path = new GraphicsPath())
            {
                float px = x0, py = y0;
                for (int i = 0; i + 5 < xy.Length; i += 6)
                {
                    path.AddBezier(px, py, xy[i], xy[i + 1], xy[i + 2], xy[i + 3], xy[i + 4], xy[i + 5]);
                    px = xy[i + 4]; py = xy[i + 5];
                }
                path.CloseFigure();
                T.FillPath(Br(c), path);
            }
        }

        // ------------------------------------------------------------------ drage
        // A kite hangs in the wind over the primary screen, its string tied to the scarecrow's hand (or to the
        // ground there, until the scarecrow has an arm). It drifts with the wind: further out and higher when it
        // blows, nearer and lower when it is calm. The tail flutters.
        float kiteX, kiteY, kiteLean;
        bool kiteSet;

        void DrawKite(float dt)
        {
            float baseX = W * 0.78f, baseY = groundY - HeapAt(W * 0.78f) + 3 * S;
            bool held = cfg.Snowman && c.SnowmanStage >= 5;
            float ax = baseX + (held ? 54 : 30) * S, ay = held ? baseY - 80 * S : baseY - 2 * S;
            float blow = Math.Max(-1, Math.Min(1, c.Wind / 90));
            float strength = Math.Min(1, Math.Abs(c.Wind) / 60);
            // the wind carries it to the lee side; with no wind it hangs to the left, over the open screen
            float side = Math.Abs(blow) < 0.08f ? -1 : (blow < 0 ? -1 : 1);
            float wantX = Math.Max(60 * S, Math.Min(W - 60 * S, ax + side * (170 + 150 * strength) * S + (float)Math.Sin(c.Time * 0.5) * 14 * S));
            float wantY = Math.Max(110 * S, ay - H * (0.34f + 0.16f * strength) + (float)Math.Sin(c.Time * 0.8 + 1) * 10 * S);
            if (!kiteSet) { kiteX = wantX; kiteY = wantY; kiteSet = true; }
            // (it closes 4 % of the way ten times a second, whatever the frame rate)
            float k = 1 - (float)Math.Pow(0.96, dt * 10);
            kiteX += (wantX - kiteX) * k;
            kiteY += (wantY - kiteY) * k;
            kiteLean = Math.Max(-0.6f, Math.Min(0.6f, (kiteX - ax) / (300 * S) * 0.45f));

            // the string sags a little between the hand and the kite's lower corner
            float kx = kiteX - (float)Math.Sin(kiteLean) * 34 * S, ky = kiteY + (float)Math.Cos(kiteLean) * 34 * S;
            float mx = (ax + kx) / 2, my = (ay + ky) / 2 + 50 * S;
            Mark(Math.Min(ax, kx) - 2, Math.Min(Math.Min(ay, ky), my) - 2, Math.Abs(kx - ax) + 4, Math.Max(Math.Max(ay, ky), my) - Math.Min(Math.Min(ay, ky), my) + 4);
            Mark(kiteX - 60 * S, kiteY - 60 * S, 120 * S, 170 * S);
            Bezier(C(235, 225, 200, 170), 1 * S, ax, ay, ax + (mx - ax) * 2 / 3, ay + (my - ay) * 2 / 3, kx + (mx - kx) * 2 / 3, ky + (my - ky) * 2 / 3, kx, ky);

            var st = g.Save();
            g.TranslateTransform(kiteX, kiteY);
            g.ScaleTransform(S, S);
            g.RotateTransform(kiteLean * 180 / (float)Math.PI);
            Color red = C(206, 62, 40), yellow = C(242, 184, 52), spar = C(70, 45, 25);
            // a diamond in four panels
            FillPoly(red, 0, -34, 22, -8, 0, -8);
            FillPoly(yellow, 0, -34, -22, -8, 0, -8);
            FillPoly(yellow, 0, -8, 22, -8, 0, 34);
            FillPoly(red, 0, -8, -22, -8, 0, 34);
            Line(spar, 1.2f, 0, -34, 0, 34);
            Line(spar, 1.2f, -22, -8, 22, -8);
            // the tail: a line of bows that flutters
            float t = (float)c.Time;
            float px = 0, py = 34;
            for (int i = 1; i <= 4; i++)
            {
                float nx = (float)Math.Sin(t * 3.1 + i * 1.2) * (4 + i * 2.2f) - kiteLean * i * 9, ny = 34 + i * 17;
                Line(C(235, 225, 200, 200), 1, px, py, nx, ny);
                Color bow = i % 2 == 0 ? red : yellow;
                FillPoly(bow, nx, ny, nx - 6, ny - 3.5f, nx - 6, ny + 3.5f);
                FillPoly(bow, nx, ny, nx + 6, ny - 3.5f, nx + 6, ny + 3.5f);
                px = nx; py = ny;
            }
            g.Restore(st);
        }

        // ------------------------------------------------------------------ regn (efterårsstorm)
        // In autumn a storm brings rain with it: it sets in as the weather passes "normal" on its way to storm
        // and thins out again as the storm dies down (the same gliding amount that sets the number of leaves).
        // The drops fall fast and slant with the wind; they are short streaks.
        struct RainDrop { public float X, Y, Speed; }
        readonly List<RainDrop> rain = new List<RainDrop>();
        // JULE_NO_RAIN=1 leaves the rain out, to measure what it costs
        static readonly bool NoRain = Environment.GetEnvironmentVariable("JULE_NO_RAIN") != null;

        void UpdateRain(float dt)
        {
            float strength = c.Autumn && c.SnowOn && !NoRain ? Math.Max(0, Math.Min(1, c.SnowAmount - 1)) : 0;
            int target = (int)(strength * (PS ? 70 : 130) * Math.Min(2f, W * (float)H / (1920f * 1080f)));
            for (int add = Math.Max(1, target / 30); add > 0 && rain.Count < target; add--)
            {
                var d = new RainDrop();
                d.X = -100 + Rnd() * (W + 200);
                d.Y = rain.Count < target / 2 ? Rnd() * groundY : -Rnd() * 80 * S;
                d.Speed = (620 + Rnd() * 260) * S;
                rain.Add(d);
            }
            if (rain.Count == 0) return;
            float slant = c.Wind * S * 1.6f;
            for (int k = rain.Count - 1; k >= 0; k--)
            {
                var d = rain[k];
                d.Y += d.Speed * dt;
                d.X += slant * dt;
                if (d.Y >= groundY - HeapAt(d.X))
                {
                    if (rain.Count > target) { rain.RemoveAt(k); continue; }
                    d.X = -100 + Rnd() * (W + 200); d.Y = -Rnd() * 80 * S;
                }
                rain[k] = d;
            }
        }

        void DrawRain()
        {
            if (rain.Count == 0) return;
            // one slant for all drops: they fall at about the same speed
            float vx = c.Wind * S * 1.6f, vy = 750 * S;
            float len = (float)Math.Sqrt(vx * vx + vy * vy);
            float dx = vx / len * 8 * S, dy = vy / len * 8 * S;
            using (var pen = new Pen(C(190, 215, 240, 107), 1.7f * S))
            {
                pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round;
                foreach (var d in rain)
                {
                    if (d.Y <= -20 * S || d.X < -10 * S || d.X > W + 10 * S) continue;
                    Mark(Math.Min(d.X - dx, d.X + dx) - S, d.Y - dy - S, Math.Abs(dx) * 2 + 2 * S, dy * 2 + 2 * S);
                    g.DrawLine(pen, d.X - dx, d.Y - dy, d.X + dx, d.Y + dy);
                }
            }
        }

        // ------------------------------------------------------------------ pindsvin og egern
        // The autumn theme's walkers. They are nisser in everything but looks: they walk, stop, wave, cross to the
        // next screen and meet to hand over what they carry. A hedgehog carries an apple on its spines, a squirrel
        // an acorn in its paws. Which animal a walker is follows its clothes, so it stays the same animal.
        // Drawn in the nisse's frame: feet at (0, 0), y up is negative, facing right.
        void DrawAnimal(Nisse n)
        {
            bool walking = n.State == 0;
            float p = walking ? n.WalkPhase : 0;
            float standPhase = n.State == 1 ? n.T * 1.5f : 0;
            float wavePhase = n.State == 2 ? n.T * 11f : 0;
            Color dark = C(52, 36, 26);
            FillEllipse(C(60, 40, 20, 50), -13, -2, 26, 4);
            bool carrying = n.CarriesGift && n.State != 2;

            if (Math.Max(0, Array.IndexOf(Tunics, n.Tunic)) % 2 == 0)
            {
                // ---- hedgehog
                Color spine = C(104, 74, 50), spineDark = C(70, 48, 32), fur = C(216, 182, 142);
                float bob = walking ? -Math.Abs((float)Math.Sin(p)) * 1.0f : 0;
                // sniffing the air when it "waves"
                float sniff = n.State == 2 ? -4 - (float)Math.Sin(wavePhase) * 2 : (float)Math.Sin(standPhase) * 0.6f;
                float[] feetX = { -10, -4, 5, 11 };
                double[] feetPhase = { 0, Math.PI, Math.PI, 0 };
                for (int i = 0; i < 4; i++)
                {
                    float fx = feetX[i] + (walking ? (float)Math.Sin(p + feetPhase[i]) * 3 : 0);
                    Line(spineDark, 3.6f, feetX[i], -5 + bob, fx, 0, true);
                }
                T.TranslateTransform(0, bob);
                // the face: a tan cone ending in the nose
                FillCurves(fur, 4, -22, 14, -22, 20, -14, 25, -7 + sniff, 22, -3, 14, -2, 4, -2);
                // the spiny back
                FillCurves(spine, -19, -2, -22, -22, -6, -29, 6, -24, 12, -20, 12, -8, 8, -2);
                for (int i = 0; i < 10; i++)
                {
                    double a = Math.PI * (1.02 - 0.84 * i / 9);
                    float bx = -5 + (float)Math.Cos(a) * 15, by = -11 - (float)Math.Sin(a) * 15;
                    Line(spineDark, 1.8f, bx, by, bx + (float)Math.Cos(a) * 6, by - (float)Math.Sin(a) * 6, true);
                }
                for (int i = 0; i < 6; i++)
                {
                    double a = Math.PI * (0.9 - 0.7 * i / 5);
                    float bx = -5 + (float)Math.Cos(a) * 8, by = -9 - (float)Math.Sin(a) * 8;
                    Line(spineDark, 1.4f, bx, by, bx + (float)Math.Cos(a) * 5, by - (float)Math.Sin(a) * 5, true);
                }
                FillEllipse(spine, 6, -22, 6, 6);                          // ear
                FillEllipse(dark, 14, -15 + sniff * 0.4f, 3.2f, 3.2f);     // eye
                FillEllipse(dark, 22.5f, -9.5f + sniff, 4.5f, 4.5f);       // nose
                if (carrying)
                {
                    // an apple stuck on the spines
                    Color[] apples = { C(206, 48, 44), C(196, 176, 52), C(222, 120, 40) };
                    FillEllipse(apples[Math.Max(0, Array.IndexOf(Gifts, n.Gift)) % 3], -11, -41, 13, 12);
                    Line(spineDark, 1.6f, -4.5f, -41, -3.5f, -45, true);
                    FillEllipse(C(88, 150, 60), -3.5f, -47, 6, 3.5f);
                    FillEllipse(C(255, 255, 255, 120), -8.5f, -39, 3, 3);
                }
            }
            else
            {
                // ---- squirrel
                Color rust = C(192, 94, 46), rustDark = C(150, 66, 30), cream = C(242, 222, 190);
                float bob = walking ? -Math.Abs((float)Math.Sin(p)) * 3.0f : 0;
                float flick = walking ? (float)Math.Sin(p * 0.5) * 2
                    : (float)Math.Sin(standPhase) * 1.5f + (n.State == 2 ? (float)Math.Sin(wavePhase) * 3 : 0);
                T.TranslateTransform(0, bob);
                // the bushy tail, curling up behind the back
                FillCurves(rust, -7, -5, -31, -6, -33 + flick, -38, -16 + flick, -47,
                           -7 + flick, -51, -1 + flick, -41, -8, -35, -17, -28, -13, -15, -5, -9);
                Line(rustDark, 1.4f, -18 + flick * 0.6f, -40, -22, -20, true);
                // hind leg and foot
                float step = walking ? (float)Math.Sin(p) * 3 : 0;
                FillEllipse(rustDark, -7, -11, 15, 10);
                Line(rustDark, 4, 1, -3, 8 + step, -1, true);
                // body and belly
                FillEllipse(rust, -9, -30, 17, 27);
                FillEllipse(cream, -1, -25, 8, 19);
                // head, ear, eye, nose
                FillEllipse(rust, 0, -43, 16, 14);
                FillPoly(rustDark, 3, -41, 5, -51, 10, -42);
                FillEllipse(cream, 9, -36, 7, 6);
                FillEllipse(dark, 9.5f, -39, 3, 3);
                FillEllipse(dark, 15, -35, 2.6f, 2.6f);
                // the front paw: holding the acorn, waving, or swinging
                float handX, handY;
                if (n.State == 2) { handX = 11; handY = -37 + (float)Math.Sin(wavePhase) * 3; }
                else if (n.CarriesGift) { handX = 11; handY = -24; }
                else { handX = 9 + (walking ? (float)Math.Sin(p) * 2 : 0); handY = -20; }
                if (carrying)
                {
                    FillEllipse(C(176, 128, 66), 9, -27, 8, 10);
                    FillEllipse(C(104, 70, 34), 8.5f, -29, 9, 5);
                    Line(C(104, 70, 34), 1.4f, 13, -29, 13, -31.5f, true);
                }
                Line(rustDark, 3.4f, 3, -25, handX, handY, true);
            }
        }

        // ------------------------------------------------------------------ løvsuger
        // Autumn's form of the snow plow: the same truck in green, with a suction nozzle and hose in place of the
        // blade, and an open body heaped with leaves in place of the salt spreader. `ph` is how much it has taken
        // (the height the snow pile in front of the blade would have). Drawn in the plow's frame.
        void DrawLeafCollector(float ph)
        {
            Color o = C(72, 138, 78), od = C(44, 96, 52);
            Color dark = C(50, 50, 55), grey = C(110, 110, 115), glass = C(175, 210, 235);
            // exhaust stack
            FillRect(grey, -4, -76, 4, 30);
            // the hose rises in front of the cab and bends back over it into the body (drawn first, so the cab hides part of it)
            Bezier(C(38, 38, 42), 8, 62, -12, 66, -62, 38, -80, -10, -56);
            Bezier(C(90, 90, 96), 1.5f, 62, -12, 66, -62, 38, -80, -10, -56);
            // leaves heaped over the edge of the body
            float[] heapX = { -74, -63, -52, -41, -30, -19 };
            for (int i = 0; i < heapX.Length; i++)
            {
                FillEllipse(LeafColours[(i * 2) % LeafColours.Length], heapX[i] - 8, -62 + (i % 2) * 3, 16, 12);
                FillEllipse(LeafColours[(i * 2 + 1) % LeafColours.Length], heapX[i] - 2, -59 - (i % 2) * 3, 12, 9);
            }
            // dump body with ribs and a reflective stripe
            FillRect(o, -80, -50, 74, 36);
            FillRect(od, -82, -53, 78, 5);
            foreach (float rx in new[] { -62f, -44f, -26f }) Line(od, 2, rx, -48, rx, -16);
            // cab
            FillPoly(o, -2, -14, -2, -64, 26, -64, 40, -44, 43, -14);
            FillPoly(glass, 14, -59, 25, -59, 36, -43, 14, -43);
            FillRect(glass, 1, -59, 10, 16);
            Line(od, 1.2f, 12, -60, 12, -16);
            FillRect(dark, 4, -38, 5, 2);
            FillRect(C(255, 255, 255, 230), -80, -26, 123, 3);
            FillEllipse(C(255, 245, 190), 38, -26, 5, 5);
            // amber beacon on the roof, flashing
            FillRect(dark, 12, -68, 10, 4);
            float flash = 0.5f + 0.5f * (float)Math.Sin(c.Time * 12);
            FillEllipse(C(255, 170, 0, (int)(150 * flash)), 3, -82, 28, 24);
            FillEllipse(C(255, 200 + (int)(55 * flash), 120 + (int)(60 * flash)), 13, -74, 8, 7);
            // chassis and wheels with rotating spokes
            FillRect(dark, -86, -16, 132, 7);
            foreach (float wx in new[] { -58f, -32f, 26f })
            {
                FillEllipse(C(30, 30, 32), wx - 10, -20, 20, 20);
                FillEllipse(C(160, 160, 165), wx - 5, -15, 10, 10);
                for (int k = 0; k < 3; k++)
                {
                    double a = plowWheel + k * Math.PI / 3;
                    float dx = (float)Math.Cos(a) * 5, dy = (float)Math.Sin(a) * 5;
                    Line(C(60, 60, 65), 1.6f, wx - dx, -10 - dy, wx + dx, -10 + dy);
                }
            }
            // the leaves it is about to take, and the wide nozzle at the ground with a warning stripe
            float[] aheadX = { 74, 82, 90, 98 };
            for (int i = 0; i < aheadX.Length; i++)
                if (i * 7 < ph) FillEllipse(LeafColours[i % LeafColours.Length], aheadX[i] - 7, -7 - (i % 2) * 3, 14, 9);
            Line(C(80, 80, 85), 3, 42, -12, 56, -14);
            FillPoly(dark, 54, -18, 70, -18, 80, 2, 50, 2);
            FillRect(C(250, 195, 30), 51, -3, 28, 3);
        }

        // ------------------------------------------------------------------ høstak og fugleskræmsel
        // Autumn's form of the snowman: a haystack that grows (stage 1-3) and a scarecrow put up beside it piece
        // by piece (4-12), in the same place and the same frame as the snowman. Origin at the ground, y up is negative.
        void DrawScarecrow(int stage)
        {
            FillEllipse(C(50, 35, 20, 50), -58, -3, 120, 6);
            Color wood = C(110, 70, 35), straw = C(228, 188, 84), strawDark = C(160, 110, 35, 170), coal = C(35, 35, 40);

            // the haystack: a dome with loose straws
            float cx = -22;
            float w = stage == 1 ? 18 : stage == 2 ? 27 : 34;
            float h = stage == 1 ? 14 : stage == 2 ? 30 : 46;
            using (var stack = new GraphicsPath())
            {
                stack.AddBezier(cx - w, 0, cx - w, -h * 0.9f, cx - w * 0.55f, -h, cx, -h);
                stack.AddBezier(cx, -h, cx + w * 0.55f, -h, cx + w, -h * 0.9f, cx + w, 0);
                stack.CloseFigure();
                // (light at the top left, darker toward the bottom right, across the whole stack)
                var box = new RectangleF(cx - w, -h, 2 * w, h);
                using (var fill = new LinearGradientBrush(box, C(238, 200, 100), C(188, 138, 48), (float)(Math.Atan2(h, w) * 180 / Math.PI)))
                    T.FillPath(fill, stack);
                using (var edge = new Pen(C(140, 95, 30, 110), 1f)) T.DrawPath(edge, stack);
            }
            int straws = stage == 1 ? 6 : stage == 2 ? 12 : 20;
            for (int i = 0; i < straws; i++)
            {
                float t = (i + 0.5f) / straws;
                float u = (i * 0.618f) % 1f;
                float px = cx + (t * 2 - 1) * w * 0.8f;
                float off = (px - cx) / w;
                float top = -h * (float)Math.Sqrt(1 - off * off);
                float py = top * (0.12f + u * 0.7f);
                float lean = (off < 0 ? -3 : 3) * (0.4f + u);
                Line(i % 3 == 0 ? C(250, 225, 150, 170) : strawDark, 1.2f, px, py, px + lean, py + 8, true);
            }
            if (stage >= 3)
            {
                Line(straw, 1.4f, cx - 4, -h + 1, cx - 9, -h - 6, true);
                Line(straw, 1.4f, cx + 2, -h + 1, cx + 4, -h - 7, true);
                Line(straw, 1.4f, cx + w - 3, -6, cx + w + 5, -9, true);
            }

            // the scarecrow
            float x = 30;
            if (stage >= 4) Line(wood, 3.4f, x, 0, x, -104, true);
            if (stage >= 5) Line(wood, 3, x - 24, -80, x + 24, -80, true);
            if (stage >= 7)
            {
                Color shirt = C(170, 62, 40), check = C(235, 190, 110, 120);
                FillPoly(shirt, x - 10, -87, x + 10, -87, x + 12, -44, x - 12, -44);
                FillPoly(shirt, x - 10, -87, x - 22, -85, x - 22, -75, x - 10, -73);
                FillPoly(shirt, x + 10, -87, x + 22, -85, x + 22, -75, x + 10, -73);
                foreach (float dx in new[] { -5f, 0f, 5f }) Line(check, 1, x + dx, -87, x + dx * 1.2f, -44);
                foreach (float y in new[] { -76f, -65f, -54f }) Line(check, 1, x - 11, y, x + 11, y);
                FillRect(C(60, 90, 140), x + 2, -62, 6, 6);
                foreach (float dx in new[] { -9f, -4f, 3f, 8f }) Line(straw, 1.3f, x + dx, -44, x + dx * 1.25f, -37, true);
            }
            if (stage >= 8)
                foreach (float dy in new[] { -5f, 0f, 5f })
                {
                    Line(straw, 1.4f, x - 22, -80, x - 30, -80 + dy, true);
                    Line(straw, 1.4f, x + 22, -80, x + 30, -80 + dy, true);
                }
            if (stage >= 6)
            {
                FillEllipse(C(222, 196, 150), x - 11, -109, 22, 22);
                StrokeEllipse(C(150, 120, 80, 130), 1, x - 11, -109, 22, 22);
                Line(C(120, 80, 40), 1.6f, x - 7, -88.5f, x + 7, -88.5f, true);
            }
            if (stage >= 9)
            {
                Color stitch = C(95, 55, 30);
                FillEllipse(coal, x - 6, -102, 3.6f, 3.6f);
                FillEllipse(coal, x + 2.4f, -102, 3.6f, 3.6f);
                FillPoly(C(205, 95, 40), x - 1.5f, -97.5f, x + 3, -95.5f, x - 1.5f, -94);
                Bezier(stitch, 1.2f, x - 6, -93, x - 3, -89.5f, x + 3, -89.5f, x + 6, -93);
                foreach (float dx in new[] { -3.5f, 0f, 3.5f }) Line(stitch, 1, x + dx, -92.6f, x + dx, -89.4f);
            }
            if (stage >= 10)
            {
                Color scarf = C(40, 120, 90);
                FillRect(scarf, x - 9, -90, 18, 5);
                FillPoly(scarf, x + 3, -87, x + 9, -87, x + 13, -68, x + 7, -68);
                Line(C(240, 225, 170), 1.3f, x + 7.5f, -74, x + 12, -74);
            }
            if (stage >= 11)
            {
                Color hat = C(214, 170, 72);
                FillEllipse(hat, x - 17, -112, 34, 7);
                FillPoly(hat, x - 9, -109, x + 9, -109, x + 6, -123, x - 6, -123);
                FillRect(C(150, 50, 35), x - 8.4f, -113, 16.8f, 3);
                Line(straw, 1.2f, x - 15, -108, x - 20, -104, true);
            }
            if (stage >= 12)
            {
                // a pumpkin at its foot and a crow that is not the least bit scared
                FillEllipse(C(226, 120, 26), x + 10, -13, 19, 13);
                StrokeEllipse(C(180, 86, 16), 1, x + 15.5f, -13, 8, 13);
                Line(C(70, 110, 40), 2, x + 19.5f, -13, x + 20.5f, -17, true);
                float bx = x - 19;
                FillPoly(coal, bx + 5, -87, bx + 11, -89, bx + 7, -84);
                FillEllipse(coal, bx - 5, -91, 11, 7);
                FillEllipse(coal, bx - 7, -94, 6, 6);
                FillPoly(C(230, 170, 40), bx - 6.5f, -92, bx - 10.5f, -90.8f, bx - 6.5f, -89.8f);
                Line(coal, 1, bx, -84.5f, bx, -81.5f);
            }
        }
    }
}
