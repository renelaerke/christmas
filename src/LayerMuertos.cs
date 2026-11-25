using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace JuleHygge
{
    // De dødes dag (Día de los Muertos, Controller.Muertos), ported from the macOS version (Overlay.swift), where
    // each Christmas element has its form for the dead: marigold petals for snow (the pictures here, the falling
    // and the piles in Layer.cs with the leaves), an ofrenda for the snowman, monarch butterflies for Santa,
    // calacas for the nisser, papel picado for the lights, candles on the window edges and a donkey cart for the
    // plow. The drawing is kept line for line the same as there, with the helpers of LayerAutumn.cs.
    partial class Layer
    {
        // The marigolds' (cempasúchil) colours: deep orange to golden yellow.
        static readonly Color[] MarigoldColours = { C(255, 140, 0), C(255, 176, 0), C(246, 112, 10), C(255, 206, 50), C(232, 96, 12) };
        // The bright colours of the papel picado and the altar's cloths.
        static readonly Color[] PicadoColours = { C(233, 30, 99), C(255, 152, 0), C(0, 166, 166), C(123, 44, 191), C(255, 210, 63), C(46, 158, 79) };

        static Color Shade(Color c, float f)
        {
            return Color.FromArgb(c.A, (int)Math.Min(255, c.R * f), (int)Math.Min(255, c.G * f), (int)Math.Min(255, c.B * f));
        }

        // A shape of lines and curves, built the way the macOS version builds a path (start, to, curve, close).
        sealed class Shape
        {
            public readonly GraphicsPath Path = new GraphicsPath();
            float x, y;
            public Shape Start(float px, float py) { Path.StartFigure(); x = px; y = py; return this; }
            public Shape To(float px, float py) { Path.AddLine(x, y, px, py); x = px; y = py; return this; }
            public Shape Curve(float x1, float y1, float x2, float y2, float x3, float y3)
            {
                Path.AddBezier(x, y, x1, y1, x2, y2, x3, y3); x = x3; y = y3; return this;
            }
            // a curve with one control point (a quadratic one, as a cubic)
            public Shape Quad(float cx, float cy, float px, float py)
            {
                return Curve(x + (cx - x) * 2 / 3, y + (cy - y) * 2 / 3, px + (cx - px) * 2 / 3, py + (cy - py) * 2 / 3, px, py);
            }
            public Shape Close() { Path.CloseFigure(); return this; }
        }
        void Fill(Color c, Shape s) { T.FillPath(Br(c), s.Path); s.Path.Dispose(); }
        void Stroke(Color c, float width, Shape s)
        {
            using (var p = new Pen(c, width)) T.DrawPath(p, s.Path);
            s.Path.Dispose();
        }
        void FillGradient(Shape s, Color from, Color to, float x0, float y0, float x1, float y1)
        {
            using (var b = new LinearGradientBrush(new PointF(x0, y0), new PointF(x1, y1), from, to))
            {
                b.WrapMode = WrapMode.TileFlipXY;
                T.FillPath(b, s.Path);
            }
            s.Path.Dispose();
        }
        // A soft round light: `inner` in the middle, fading to nothing at the rim.
        void Glow(Color inner, float cx, float cy, float r)
        {
            using (var path = new GraphicsPath())
            {
                path.AddEllipse(cx - r, cy - r, 2 * r, 2 * r);
                using (var b = new PathGradientBrush(path))
                {
                    b.CenterPoint = new PointF(cx, cy);
                    b.CenterColor = inner;
                    b.SurroundColors = new[] { Color.FromArgb(0, inner) };
                    T.FillPath(b, path);
                }
            }
        }

        Bitmap picadoBmp;

        void DisposeMuertos()
        {
            if (picadoBmp != null) { picadoBmp.Dispose(); picadoBmp = null; }
        }

        // ------------------------------------------------------------------ kronblade
        // Marigold petals, each a short fan with a frilled outer edge, lying along x with the narrow base at the
        // left; and, one in five, a whole small flower head (frilled rings). Drawn once as small pictures and then
        // turned and scaled into the pixel buffer like the leaves (BlendLeaf). Per colour: a petal, then a head.
        static int[][] MakePetalSprites()
        {
            var all = new int[MarigoldColours.Length * 2][];
            float m = LeafPx / 2f;
            Color crease = C(150, 60, 0, 70);
            for (int ci = 0; ci < MarigoldColours.Length; ci++)
                for (int shape = 0; shape < 2; shape++)
                    using (var bmp = new Bitmap(LeafPx, LeafPx, PixelFormat.Format32bppPArgb))
                    {
                        Color colour = MarigoldColours[ci];
                        using (var lg = Graphics.FromImage(bmp))
                        using (var fill = new SolidBrush(colour))
                        using (var line = new Pen(crease, shape == 0 ? 2f : 1.5f))
                        {
                            lg.SmoothingMode = SmoothingMode.AntiAlias;
                            lg.Clear(Color.Transparent);
                            if (shape == 0)
                            {
                                var p = new Shape().Start(8, m).Quad(18, m - 22, 44, m - 22);
                                // the frilled edge: small scallops from top to bottom
                                const int n = 6;
                                for (int k = 0; k < n; k++)
                                {
                                    double a1 = -Math.PI / 2 + Math.PI * (k + 1) / n, am = -Math.PI / 2 + Math.PI * (k + 0.5) / n;
                                    p.Quad(38 + (float)Math.Cos(am) * 26, m + (float)Math.Sin(am) * 29, 38 + (float)Math.Cos(a1) * 18, m + (float)Math.Sin(a1) * 22);
                                }
                                p.Quad(18, m + 22, 8, m).Close();
                                lg.FillPath(fill, p.Path);
                                p.Path.Dispose();
                                line.StartCap = LineCap.Round; line.EndCap = LineCap.Round;
                                lg.DrawLine(line, 10, m, 48, m - 8);
                                lg.DrawLine(line, 10, m, 50, m + 6);
                            }
                            else
                            {
                                foreach (float r in new[] { 30f, 22f, 13f })
                                {
                                    var ring = new Shape();
                                    const int lobes = 12;
                                    for (int k = 0; k <= lobes; k++)
                                    {
                                        double a1 = 2 * Math.PI * k / lobes, am = a1 - Math.PI / lobes;
                                        float px = m + (float)Math.Cos(a1) * r * 0.86f, py = m + (float)Math.Sin(a1) * r * 0.86f;
                                        if (k == 0) ring.Start(px, py);
                                        else ring.Quad(m + (float)Math.Cos(am) * r * 1.12f, m + (float)Math.Sin(am) * r * 1.12f, px, py);
                                    }
                                    ring.Close();
                                    using (var rb = new SolidBrush(r == 22f ? Shade(colour, 0.85f) : colour)) lg.FillPath(rb, ring.Path);
                                    lg.DrawPath(line, ring.Path);
                                    ring.Path.Dispose();
                                }
                            }
                        }
                        var px2 = new int[LeafPx * LeafPx];
                        var data = bmp.LockBits(new Rectangle(0, 0, LeafPx, LeafPx), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
                        Marshal.Copy(data.Scan0, px2, 0, px2.Length);
                        bmp.UnlockBits(data);
                        all[ci * 2 + shape] = px2;
                    }
            return all;
        }

        // ------------------------------------------------------------------ small things the figures share
        // A small marigold head (cempasúchil) centred at (x, y): frilled rings in orange.
        void DrawMarigold(float x, float y, float r, Color colour)
        {
            FillEllipse(Shade(colour, 0.78f), x - r, y - r * 0.9f, r * 2, r * 1.8f);
            for (int k = 0; k < 7; k++)
            {
                double a = k * 0.8976;
                FillEllipse(colour, x + (float)Math.Cos(a) * r * 0.45f - r * 0.5f, y + (float)Math.Sin(a) * r * 0.4f - r * 0.45f, r, r * 0.9f);
            }
            FillEllipse(Shade(colour, 0.85f), x - r * 0.4f, y - r * 0.38f, r * 0.8f, r * 0.76f);
        }

        // A candle standing at (x, y) (its foot), with a flame and a soft glow.
        void DrawCandle(float x, float y, float h)
        {
            // a warm glow around the flame (a flat light disc read as a grey spot on a dark desktop)
            Glow(C(255, 190, 70, 120), x, y - h - 5, 9);
            FillRect(C(250, 242, 222), x - 2.6f, y - h, 5.2f, h);
            FillRect(C(220, 205, 175), x + 0.8f, y - h, 1.8f, h);
            Line(C(60, 40, 30), 0.8f, x, y - h, x, y - h - 1.8f);
            Fill(C(255, 180, 40), new Shape().Start(x, y - h - 9).Curve(x + 3.2f, y - h - 4.5f, x + 2.4f, y - h - 1, x, y - h - 1)
                .Curve(x - 2.4f, y - h - 1, x - 3.2f, y - h - 4.5f, x, y - h - 9).Close());
            FillEllipse(C(255, 245, 200), x - 0.9f, y - h - 4.6f, 1.8f, 3);
        }

        // A sugar skull (calavera de azúcar) centred at (x, y), `w` wide, with icing around the eyes.
        void DrawSugarSkull(float x, float y, float w, Color icing)
        {
            float k = w / 20;
            Color ink = C(36, 28, 40);
            FillEllipse(C(250, 246, 236), x - 10 * k, y - 10 * k, 20 * k, 17 * k);
            FillRect(C(250, 246, 236), x - 6 * k, y + 3 * k, 12 * k, 6 * k);
            StrokeEllipse(C(150, 140, 130, 140), 0.8f, x - 10 * k, y - 10 * k, 20 * k, 17 * k);
            foreach (float dx in new[] { -4.5f, 4.5f })
            {
                FillEllipse(icing, x + dx * k - 3.6f * k, y - 3.6f * k, 7.2f * k, 7.2f * k);
                FillEllipse(ink, x + dx * k - 2.4f * k, y - 2.4f * k, 4.8f * k, 4.8f * k);
            }
            FillPoly(ink, x, y + 1.5f * k, x - 1.4f * k, y + 4 * k, x + 1.4f * k, y + 4 * k);
            Line(ink, 0.8f, x - 4.5f * k, y + 6.5f * k, x + 4.5f * k, y + 6.5f * k);
            foreach (float dx in new[] { -3f, -1f, 1f, 3f }) Line(ink, 0.7f, x + dx * k, y + 5.3f * k, x + dx * k, y + 7.8f * k);
            // icing on the forehead: a small flower
            for (double a = 0; a < 6.28; a += 1.2566)
                FillEllipse(icing, x + (float)Math.Cos(a) * 2 * k - 1.2f * k, y - 6.5f * k + (float)Math.Sin(a) * 2 * k - 1.2f * k, 2.4f * k, 2.4f * k);
            FillEllipse(C(255, 210, 63), x - 1 * k, y - 7.5f * k, 2 * k, 2 * k);
        }

        // ------------------------------------------------------------------ monarksommerfugle
        // One monarch butterfly flying toward +x, seen from above: the body along x, the wings to both sides.
        // The wings beat by folding toward the body (their spread is |cos| of the flap).
        void DrawMonarch(float x, float y, float size, float flap)
        {
            var st = T.Save();
            T.TranslateTransform(x, y);
            T.ScaleTransform(size, size);
            float spread = 0.18f + 0.82f * Math.Abs((float)Math.Cos(flap));
            Color orange = C(255, 136, 0), deep = C(214, 92, 0), black = C(28, 22, 26), dot = C(255, 255, 255, 230);
            foreach (float side in new[] { -1f, 1f })
            {
                var st2 = T.Save();
                T.ScaleTransform(1, side * spread);
                // forewing (toward the head) and hindwing, black-edged with orange cells
                Fill(black, new Shape().Start(4, 0).Curve(10, -10, 22, -24, 14, -30).Curve(4, -30, -6, -20, -2, 0).Close());
                Fill(black, new Shape().Start(-1, 0).Curve(-2, -12, -10, -24, -18, -18).Curve(-22, -10, -12, -2, -1, 0).Close());
                FillGradient(new Shape().Start(4, -2).Curve(9, -10, 18, -21, 12, -26).Curve(5, -26, -3, -18, 0, -2).Close(), orange, deep, 4, -2, 12, -26);
                FillGradient(new Shape().Start(-2, -2).Curve(-3, -11, -9, -20, -16, -16).Curve(-19, -10, -11, -3, -2, -2).Close(), orange, deep, -2, -2, -16, -16);
                // the black veins and the white dots in the border
                Line(black, 1.1f, 2, -3, 12, -22); Line(black, 1.1f, 1, -3, 4, -24);
                Line(black, 1.1f, -2, -3, -12, -15); Line(black, 1.1f, -2, -3, -6, -18);
                float[,] dots = { { 15, -28 }, { 10, -29.5f }, { 5, -27.5f }, { -16, -18.5f }, { -19, -13 }, { -12, -20 } };
                for (int i = 0; i < dots.GetLength(0); i++) FillEllipse(dot, dots[i, 0] - 0.9f, dots[i, 1] - 0.9f, 1.8f, 1.8f);
                T.Restore(st2);
            }
            // body, head and antennae
            FillEllipse(black, -9, -1.6f, 16, 3.2f);
            FillEllipse(black, 5.5f, -2, 4, 4);
            Line(black, 0.8f, 9, -1, 14, -4); Line(black, 0.8f, 9, 1, 14, 4);
            T.Restore(st);
        }

        // The dead's flyer in Santa's place: a loose swarm of monarch butterflies (they are said to carry the souls
        // home). Each one flutters at its own pace and wanders up and down around its place in the swarm.
        // (Drawn in Santa's frame: translated to his place and scaled by his size and direction.)
        void DrawMonarchs(float t)
        {
            float[,] places = { { 230, -40, 1.1f }, { 180, -72, 0.8f }, { 150, -20, 1.0f }, { 100, -78, 0.9f }, { 70, -45, 1.2f },
                                { 20, -10, 0.8f }, { -10, -72, 1.0f }, { -60, -40, 0.9f }, { -110, -70, 0.75f }, { -150, -15, 0.85f } };
            for (int i = 0; i < places.GetLength(0); i++)
                DrawMonarch(places[i, 0] + (float)Math.Sin(t * 0.9 + i * 2.1) * 12, places[i, 1] + (float)Math.Sin(t * 1.3 + i * 1.7) * 14,
                    places[i, 2], t * (10 + (i % 3) * 1.5f) + i * 1.3f);
        }

        // ------------------------------------------------------------------ ofrenda
        // The dead's form of the snowman: an ofrenda, the home altar, put together piece by piece (a step for every
        // hour the app runs, Controller.OfrendaStage) in the same place and frame as the snowman. Three tiers under
        // coloured cloths, then candles, marigolds, a sugar skull, bread, a framed photo, an arch of marigolds and
        // a monarch resting on it. Origin at the ground, y up is negative.
        void DrawOfrenda(int stage)
        {
            FillEllipse(C(40, 20, 30, 60), -60, -3, 120, 6);
            Color[] cloth = PicadoColours;
            // the arch of marigolds behind the altar (stage 10): two bent canes thick with flowers
            if (stage >= 10)
            {
                Bezier(C(70, 110, 40), 2.4f, -50, -2, -54, -150, 54, -150, 50, -2);
                for (int k = 0; k <= 16; k++)
                {
                    float u = k / 16f, v = 1 - u;
                    float px = v * v * v * -50 + 3 * v * v * u * -54 + 3 * v * u * u * 54 + u * u * u * 50;
                    float py = v * v * v * -2 + 3 * v * v * u * -150 + 3 * v * u * u * -150 + u * u * u * -2;
                    DrawMarigold(px, py, 4.2f, MarigoldColours[k % MarigoldColours.Length]);
                }
            }
            if (stage >= 1) OfrendaTier(0, 112, 26, cloth[3]);
            if (stage >= 2) OfrendaTier(-26, 84, 26, cloth[0]);
            if (stage >= 3) OfrendaTier(-52, 56, 24, cloth[2]);
            // papel picado along the front of the bottom tier (stage 11)
            if (stage >= 11)
                for (int i = 0; i < 5; i++)
                {
                    float x = -44 + i * 22;
                    FillRect(cloth[(i + 1) % cloth.Length], x - 8, -14, 16, 10);
                    FillEllipse(C(96, 58, 34), x - 2, -11, 4, 4);
                }
            // the photo of the one remembered, at the back of the top tier (stage 9)
            if (stage >= 9)
            {
                FillRect(C(196, 150, 60), 8, -98, 18, 22);
                FillRect(C(232, 224, 205), 10.5f, -95.5f, 13, 17);
                FillEllipse(C(120, 100, 88), 12.5f, -87.5f, 9, 9);
                FillEllipse(C(150, 128, 110), 14.5f, -93, 5, 6);
            }
            // the sugar skull on top (stage 6)
            if (stage >= 6) DrawSugarSkull(-8, -86, 22, cloth[0]);
            // marigolds along each tier's edge (stage 5)
            if (stage >= 5)
            {
                float[,] rows = { { -27, 100 }, { -53, 72 } };
                for (int r = 0; r < 2; r++)
                {
                    int k = 0;
                    for (float x = -rows[r, 1] / 2; x <= rows[r, 1] / 2; x += 12, k++)
                        DrawMarigold(x, rows[r, 0], 4.6f, MarigoldColours[k % MarigoldColours.Length]);
                }
            }
            // bread of the dead (pan de muerto) on the middle tier (stage 8)
            if (stage >= 8)
            {
                FillEllipse(C(206, 146, 80), -38, -38, 22, 12);
                Line(C(244, 226, 190), 2.6f, -34, -35, -20, -31, true);
                Line(C(244, 226, 190), 2.6f, -34, -31, -20, -35, true);
                FillEllipse(C(244, 226, 190), -29.5f, -39.5f, 5, 5);
            }
            // candles: on the bottom tier (stage 4), the middle tier (stage 7)
            if (stage >= 4) { DrawCandle(-50, -26, 14); DrawCandle(50, -26, 14); }
            if (stage >= 7) { DrawCandle(-36, -52, 11); DrawCandle(36, -52, 11); }
            // a glass of water and small sugar skulls for the children (stage 12), and a monarch resting on the arch
            if (stage >= 12)
            {
                FillRect(C(190, 225, 245, 150), 14, -40, 8, 12);
                FillRect(C(150, 200, 235, 170), 14, -34, 8, 6);
                StrokeEllipse(C(255, 255, 255, 120), 0.8f, 14, -41, 8, 2);
                DrawSugarSkull(2, -32, 9, cloth[2]);
                DrawMonarch(24, -100, 0.55f, 0.5f);
            }
        }

        // One tier of the altar: a box under a cloth with a scalloped hem.
        void OfrendaTier(float y, float w, float h, Color col)
        {
            FillRect(C(96, 58, 34), -w / 2, y - h, w, h);
            var c2 = new Shape().Start(-w / 2 - 2, y - h).To(w / 2 + 2, y - h).To(w / 2 + 2, y - h + h * 0.62f);
            int n = (int)(w / 9);
            for (int i = 0; i < n; i++)
            {
                float x1 = w / 2 + 2 - (w + 4) * (i + 1) / n, xm = w / 2 + 2 - (w + 4) * (i + 0.5f) / n;
                c2.Quad(xm, y - h + h * 0.62f + 7, x1, y - h + h * 0.62f);
            }
            Fill(col, c2.Close());
            Line(Shade(col, 0.7f), 1, -w / 2 - 2, y - h + 0.5f, w / 2 + 2, y - h + 0.5f);
        }

        // ------------------------------------------------------------------ calacas
        // The Day of the Dead's walkers: small cheerful skeletons. They are nisser in everything but looks: they
        // walk, stop, wave (dance), cross to the next screen and meet to hand over a bunch of marigolds. Every other
        // one is a calaca in a sombrero with a striped serape, the others a catrina in a long dress and a wide hat
        // with flowers. The bones are white with a dark outline, so they show on light windows as well as dark ones.
        // Drawn like a nisse: feet at (0, 0), y up is negative, facing right.
        void DrawCalaca(Nisse n)
        {
            DrawCalaca(Math.Max(0, Array.IndexOf(Tunics, n.Tunic)), Math.Max(0, Array.IndexOf(Gifts, n.Gift)), n.State, n.CarriesGift,
                n.State == 0 ? n.WalkPhase : 0, n.State == 1 ? n.T * 1.5f : 0, n.State == 2 ? n.T * 11f : 0);
        }

        void CalacaBone(float x1, float y1, float x2, float y2, float w)
        {
            Line(C(34, 26, 40), w + 1.8f, x1, y1, x2, y2, true);
            Line(C(246, 242, 230), w, x1, y1, x2, y2, true);
        }

        void DrawCalaca(int tunicIndex, int giftIndex, int state, bool carriesGift, float p, float standPhase, float wavePhase)
        {
            bool walking = state == 0;
            float legA = walking ? (float)Math.Sin(p) * 0.55f : 0;
            float bob = walking ? -Math.Abs((float)Math.Sin(p)) * 1.5f : (state == 2 ? -Math.Abs((float)Math.Sin(wavePhase)) * 2 : 0);
            Color ink = C(34, 26, 40), bone = C(246, 242, 230);
            bool catrina = tunicIndex % 2 == 1;
            Color[] colours = PicadoColours;
            Color main = colours[(tunicIndex / 2 + (catrina ? 3 : 0)) % colours.Length];

            FillEllipse(C(40, 20, 30, 50), -11, -2, 22, 4);

            // legs and shoes (under a catrina's dress only the shoes step out)
            foreach (float side in new[] { -1f, 1f })
            {
                float hx = 2 * side, hy = -15 + bob, a = -legA * side;
                float fx = hx + (float)Math.Sin(a) * 13, fy = hy + (float)Math.Cos(a) * 13;
                if (!catrina) CalacaBone(hx, hy, fx, fy, 2.4f);
                FillEllipse(ink, fx - 3, fy - 2, 8.5f, 4.5f);
            }

            var st = T.Save();
            T.TranslateTransform(0, bob);
            float backArm, frontArm;
            if (state == 2) { backArm = -0.4f + (float)Math.Sin(wavePhase) * 0.3f; frontArm = 2.6f + (float)Math.Sin(wavePhase) * 0.5f; }
            else if (carriesGift) { backArm = 1.3f; frontArm = 1.3f; }
            else { backArm = -legA * 0.9f; frontArm = legA * 0.9f; }
            float sway = (float)Math.Sin(walking ? p * 0.5f : standPhase) * 0.06f;

            CalacaArm(-1, -33, backArm);

            if (catrina)
            {
                // the long dress, flaring from the waist, with a ruffle at the hem
                Fill(main, new Shape().Start(-5, -34).To(5, -34).Curve(7, -24, 12, -12, 13, -3).To(-13, -3).Curve(-12, -12, -7, -24, -5, -34).Close());
                Line(Shade(main, 0.65f), 1, -5, -34, 5, -34);
                for (int k = 0; k < 6; k++) FillEllipse(Shade(main, 0.75f), -13 + k * 4.3f, -5, 4.6f, 3.6f);
                Line(colours[(tunicIndex + 4) % colours.Length], 1.6f, -6.5f, -24, 6.5f, -24);   // the sash
            }
            else
            {
                // spine, pelvis and ribcage
                CalacaBone(0, -17, 0, -34, 1.8f);
                FillEllipse(ink, -6, -21, 12, 6.5f);
                FillEllipse(bone, -5, -20.2f, 10, 5);
                StrokeEllipse(ink, 3, -6.5f, -36, 13, 13);
                StrokeEllipse(bone, 1.6f, -6.5f, -36, 13, 13);
                CalacaBone(-5, -32, 5, -32, 1.1f);
                CalacaBone(-5, -28.5f, 5, -28.5f, 1.1f);
                // the striped serape over one shoulder
                Color[] stripe = { main, colours[(tunicIndex + 2) % colours.Length], C(250, 240, 210) };
                for (int k = 0; k < stripe.Length; k++)
                {
                    float o = k * 2.2f;
                    Line(stripe[k], 2.4f, -6 + o * 0.4f, -36 + o, 6 + o * 0.4f, -24 + o);
                }
            }

            if (carriesGift && state != 2)
            {
                // a bunch of marigolds
                Line(C(70, 110, 40), 1.2f, 10, -22, 12, -31);
                Line(C(70, 110, 40), 1.2f, 10, -22, 16, -30);
                DrawMarigold(11.5f, -32, 3.2f, MarigoldColours[giftIndex % MarigoldColours.Length]);
                DrawMarigold(16.5f, -31, 3, MarigoldColours[(giftIndex + 1) % MarigoldColours.Length]);
                DrawMarigold(14, -35.5f, 2.8f, MarigoldColours[(giftIndex + 3) % MarigoldColours.Length]);
            }

            // the skull, with the eye sockets ringed in colour like a sugar skull
            var st2 = T.Save();
            T.TranslateTransform(1, -44);
            T.RotateTransform(sway * 180 / (float)Math.PI);
            FillEllipse(ink, -7.6f, -7.6f, 15.2f, 14.2f);
            FillEllipse(bone, -6.7f, -6.7f, 13.4f, 12.4f);
            FillRect(bone, -3.6f, 3, 7.2f, 3.6f);
            StrokeEllipse(ink, 0.8f, -3.6f, 3, 7.2f, 3.6f);
            Color ring = colours[(tunicIndex + 1) % colours.Length];
            foreach (float dx in new[] { -0.5f, 4.4f })
            {
                FillEllipse(ring, dx - 2.9f, -2.9f, 5.8f, 5.8f);
                FillEllipse(ink, dx - 1.9f, -1.9f, 3.8f, 3.8f);
            }
            FillPoly(ink, 5.5f, 1.2f, 4.4f, 3, 6.4f, 3);
            foreach (float dx in new[] { -1.5f, 1f, 3.5f }) Line(ink, 0.6f, dx, 3.4f, dx, 6.2f);

            if (catrina)
            {
                // a wide hat tilted back, with flowers and a feather
                T.RotateTransform(-0.12f * 180 / (float)Math.PI);
                FillEllipse(ink, -15, -9, 30, 6);
                FillEllipse(Shade(main, 0.55f), -14, -8.4f, 28, 4.8f);
                Fill(Shade(main, 0.55f), new Shape().Start(-6, -7).Curve(-6, -14, 6, -14, 6, -7).Close());
                Bezier(C(250, 250, 250), 1.6f, -4, -11, -10, -20, -16, -20, -18, -14);
                DrawMarigold(-2, -10, 2.6f, MarigoldColours[0]);
                DrawMarigold(3, -9.5f, 2.4f, colours[0]);
                DrawMarigold(7.5f, -8.5f, 2.2f, MarigoldColours[3]);
            }
            else
            {
                // a sombrero: wide brim, tall crown and a coloured band
                FillEllipse(ink, -16, -9, 32, 6.5f);
                FillEllipse(C(214, 170, 72), -15, -8.4f, 30, 5.2f);
                Fill(C(214, 170, 72), new Shape().Start(-6.5f, -6.5f).Curve(-6, -19, 6, -19, 6.5f, -6.5f).Close());
                Stroke(C(120, 84, 30), 0.8f, new Shape().Start(-6.5f, -6.5f).Curve(-6, -19, 6, -19, 6.5f, -6.5f).Close());
                FillRect(main, -6.4f, -9.4f, 12.8f, 2.4f);
            }
            T.Restore(st2);

            CalacaArm(1, -33, frontArm);
            if (state == 2)
            {
                // dancing with a maraca in the raised hand
                float hx = 1 + (float)Math.Sin(frontArm) * 11, hy = -33 + (float)Math.Cos(frontArm) * 11;
                Line(C(120, 80, 40), 1.4f, hx, hy, hx + (float)Math.Sin(frontArm) * 4, hy + (float)Math.Cos(frontArm) * 4);
                FillEllipse(colours[(tunicIndex + 5) % colours.Length], hx + (float)Math.Sin(frontArm) * 6 - 3, hy + (float)Math.Cos(frontArm) * 6 - 3, 6, 6);
            }
            T.Restore(st);
        }

        void CalacaArm(float sx, float sy, float a)
        {
            float hx = sx + (float)Math.Sin(a) * 11, hy = sy + (float)Math.Cos(a) * 11;
            CalacaBone(sx, sy, hx, hy, 2);
            FillEllipse(C(246, 242, 230), hx - 2, hy - 2, 4, 4);
            StrokeEllipse(C(34, 26, 40), 0.8f, hx - 2, hy - 2, 4, 4);
        }

        // ------------------------------------------------------------------ æselkærre
        // The Day of the Dead's form of the snow plow: a donkey pulls a wooden cart, and a calaca walks in front
        // sweeping the marigold petals up with a broom; they fly back over the donkey into the cart, to be taken
        // out to the graves. Facing +x, origin at the ground, the broom where the plow's blade would be.
        void DrawPetalCart(float ph)
        {
            Color wood = C(140, 92, 50), woodDark = C(96, 60, 30), ink = C(34, 26, 40);
            float step = plowWheel;
            const float stride = Controller.DonkeyStride;
            // the cart: an open box heaped with marigolds, on one big spoked wheel
            float[] heapX = { -96, -84, -72, -60, -48, -36, -26 };
            for (int i = 0; i < heapX.Length; i++)
            {
                DrawMarigold(heapX[i] + 6, -46 - (i % 2) * 3, 6.5f, MarigoldColours[i % MarigoldColours.Length]);
                DrawMarigold(heapX[i], -42 + (i % 2) * 2, 6, MarigoldColours[(i + 2) % MarigoldColours.Length]);
            }
            FillRect(wood, -100, -42, 78, 24);
            Line(woodDark, 1.2f, -100, -34, -22, -34);
            Line(woodDark, 1.2f, -100, -26, -22, -26);
            FillRect(woodDark, -100, -44, 78, 3);
            foreach (float x in new[] { -100f, -61f, -25f }) FillRect(woodDark, x, -44, 3, 26);
            // a strip of papel picado along the side
            for (int k = 0; k < 4; k++) FillRect(PicadoColours[k % PicadoColours.Length], -93 + k * 18, -40, 12, 6);
            // the shafts to the donkey
            Line(woodDark, 3, -24, -28, 16, -36, true);
            // the wheel
            FillEllipse(woodDark, -78, -36, 36, 36);
            StrokeEllipse(wood, 2.5f, -74, -32, 28, 28);
            for (int k = 0; k < 6; k++)
            {
                double a = step + k * Math.PI / 3;
                Line(wood, 2, -60, -18, -60 + (float)Math.Cos(a) * 14, -18 + (float)Math.Sin(a) * 14);
            }
            FillEllipse(woodDark, -63, -21, 6, 6);

            // the donkey: grey, with long ears, a dark mane and a garland of marigolds round the neck
            Color fur = C(132, 122, 116), furDark = C(92, 84, 80), belly = C(196, 188, 180);
            DonkeyLeg(4, (float)Math.Sin(step * stride + 1.2) * 0.45f, furDark);
            DonkeyLeg(34, (float)Math.Sin(step * stride + 1.2 + Math.PI) * 0.45f, furDark);
            // tail
            Bezier(furDark, 2, 0, -38, -8, -34, -8, -24, -6, -18);
            FillEllipse(ink, -10, -22, 6, 7);
            FillEllipse(fur, -2, -46, 44, 22);
            FillEllipse(belly, 6, -32, 30, 9);
            DonkeyLeg(8, (float)Math.Sin(step * stride + Math.PI) * 0.45f, fur);
            DonkeyLeg(38, (float)Math.Sin(step * stride) * 0.45f, fur);
            // harness
            Line(C(150, 40, 40), 2.2f, 14, -46, 14, -26);
            // neck and head
            float nod = (float)Math.Sin(step * stride) * 1.2f;
            FillPoly(fur, 30, -44, 46, -62 + nod, 56, -56 + nod, 42, -30);
            FillEllipse(fur, 44, -66 + nod, 18, 12);
            FillEllipse(belly, 55, -62 + nod, 11, 9);
            FillEllipse(ink, 61, -59.5f + nod, 2, 2);
            FillEllipse(ink, 50, -63 + nod, 2.8f, 2.8f);
            // ears
            FillPoly(fur, 45, -64 + nod, 38, -80 + nod, 42, -81 + nod, 49, -65 + nod);
            FillPoly(furDark, 48, -65 + nod, 46, -82 + nod, 50, -82 + nod, 52, -65 + nod);
            // mane
            for (int k = 0; k < 5; k++) Line(ink, 2, 32 + k * 3, -46 - k * 3.6f + nod * k / 5, 29 + k * 3, -50 - k * 3.6f + nod * k / 5, true);
            // the marigold garland round the neck
            for (int k = 0; k < 4; k++) DrawMarigold(34 + k * 4, -36 - k * 5 + nod * k / 4, 3, MarigoldColours[k]);

            // the calaca with the broom, walking in front (its legs keep the donkey's time)
            var st = T.Save();
            T.TranslateTransform(80, 0);
            T.ScaleTransform(1.1f, 1.1f);
            DrawCalaca(2, 0, 0, false, (float)((step * stride) % (4 * Math.PI)), 0, 0);
            T.Restore(st);
            // the broom: the handle from the calaca's hands down to the ground in front, the head swinging
            float swing = (float)Math.Sin(step * stride * 2) * 5;
            Line(woodDark, 2.2f, 82, -38, 96 + swing, -3, true);
            FillPoly(C(214, 170, 72), 92 + swing, -6, 102 + swing, -6, 108 + swing, 1, 88 + swing, 1);
            for (int k = 0; k < 5; k++) Line(C(150, 110, 40), 0.8f, 90 + swing + k * 4, -5, 89 + swing + k * 4.6f, 1);
            // petals gathered in front of the broom
            float[] gathered = { 100, 107, 114 };
            for (int i = 0; i < gathered.Length; i++)
                if (i * 6 < ph) FillEllipse(MarigoldColours[i % MarigoldColours.Length], gathered[i] + swing - 5, -6 - (i % 2) * 2, 10, 6);
        }

        void DonkeyLeg(float hx, float a, Color col)
        {
            float kx = hx + (float)Math.Sin(a) * 9, ky = -14;
            Line(col, 4, hx, -28, kx, ky, true);
            Line(col, 3.4f, kx, ky, kx + (float)Math.Sin(a) * 3, 0, true);
            FillRect(C(34, 26, 40), kx + (float)Math.Sin(a) * 3 - 2, -2.5f, 5, 3);
        }

        // ------------------------------------------------------------------ papel picado
        // The dead's form of the Christmas lights: a flag of thin cut paper in a bright colour hangs at every bulb's
        // place, a little turned with the string's slope, with a zigzag hem and a pattern cut out of it (the desktop
        // shows through the holes). Nothing in it moves, so it is drawn once and kept (picadoBmp).
        void MakePapelPicado(int lh)
        {
            if (picadoBmp != null) picadoBmp.Dispose();
            picadoBmp = new Bitmap(W, lh, PixelFormat.Format32bppPArgb);
            float span = 230 * S, sag = 22 * S, top = 1;
            Color hole = Color.FromArgb(0, 0, 0, 0);
            using (var lg = Graphics.FromImage(picadoBmp))
            using (var wire = new Pen(C(40, 30, 36, 200), 2f * S))
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
                into = lg;
                float w = 26 * S, h = 30 * S, kk = S, cy = h * 0.48f;
                int idx = 0;
                for (float x0 = -span * 0.3f; x0 < W; x0 += span)
                    for (int b = 0; b < 4; b++, idx++)
                    {
                        float u = (b + 0.5f) / 4;
                        float bx = x0 + u * span, by = top + sag * (1 - (2 * u - 1) * (2 * u - 1));
                        float slope = sag * -4 * (2 * u - 1) / span;
                        Color col = PicadoColours[idx % PicadoColours.Length];
                        var st = lg.Save();
                        lg.TranslateTransform(bx, by);
                        lg.RotateTransform((float)((Math.Atan(slope) * 0.6 + Math.Sin(idx * 1.9) * 0.05) * 180 / Math.PI));
                        // the flag, with a zigzag hem
                        const int teeth = 6;
                        var flag = new List<float> { -w / 2, 0, w / 2, 0, w / 2, h - 3 * S };
                        for (int k = 0; k < teeth; k++)
                        {
                            flag.Add(w / 2 - w * (k + 0.5f) / teeth); flag.Add(h);
                            flag.Add(w / 2 - w * (k + 1) / teeth); flag.Add(h - 3 * S);
                        }
                        FillPoly(col, flag.ToArray());
                        // the pattern is cut out: these shapes replace what is there with nothing
                        lg.CompositingMode = CompositingMode.SourceCopy;
                        switch (idx % 3)
                        {
                            case 0:
                                // a flower: five petals around a hole
                                for (int j = 0; j < 5; j++)
                                {
                                    double a = j * 1.2566 - Math.PI / 2;
                                    FillEllipse(hole, (float)Math.Cos(a) * 5 * kk - 2.6f * kk, cy + (float)Math.Sin(a) * 5 * kk - 2.6f * kk, 5.2f * kk, 5.2f * kk);
                                }
                                FillEllipse(hole, -1.6f * kk, cy - 1.6f * kk, 3.2f * kk, 3.2f * kk);
                                break;
                            case 1:
                                // a small skull: the head with eyes and nose left standing
                                FillEllipse(hole, -6.5f * kk, cy - 7 * kk, 13 * kk, 12 * kk);
                                FillRect(hole, -4 * kk, cy + 3 * kk, 8 * kk, 4.5f * kk);
                                lg.CompositingMode = CompositingMode.SourceOver;
                                FillEllipse(col, -4.4f * kk, cy - 2.6f * kk, 3.6f * kk, 3.6f * kk);
                                FillEllipse(col, 0.8f * kk, cy - 2.6f * kk, 3.6f * kk, 3.6f * kk);
                                FillPoly(col, 0, cy + 1.5f * kk, -1.2f * kk, cy + 3.4f * kk, 1.2f * kk, cy + 3.4f * kk);
                                foreach (float dx in new[] { -2f, 0f, 2f }) Line(col, 0.8f * kk, dx * kk, cy + 4.5f * kk, dx * kk, cy + 7.5f * kk);
                                lg.CompositingMode = CompositingMode.SourceCopy;
                                break;
                            default:
                                // four diamonds
                                float[,] at = { { 0, -6 }, { -6, 0 }, { 6, 0 }, { 0, 6 } };
                                for (int j = 0; j < 4; j++)
                                {
                                    float dx = at[j, 0], dy = at[j, 1];
                                    FillPoly(hole, dx * kk, cy + (dy - 3.2f) * kk, dx * kk + 3.2f * kk, cy + dy * kk, dx * kk, cy + (dy + 3.2f) * kk, dx * kk - 3.2f * kk, cy + dy * kk);
                                }
                                break;
                        }
                        // a row of small holes along the top and the sides
                        for (int j = 0; j < 5; j++) FillEllipse(hole, -w / 2 + w * (j + 0.5f) / 5 - 1 * kk, 3 * kk, 2 * kk, 2 * kk);
                        foreach (float yy in new[] { h * 0.3f, h * 0.55f })
                        {
                            FillEllipse(hole, -w / 2 + 2 * kk, yy, 2 * kk, 2 * kk);
                            FillEllipse(hole, w / 2 - 4 * kk, yy, 2 * kk, 2 * kk);
                        }
                        lg.CompositingMode = CompositingMode.SourceOver;
                        // folded over the string
                        FillRect(C(0, 0, 0, 40), -w / 2, 0, w, 1.4f * S);
                        lg.Restore(st);
                    }
                into = null;
            }
        }

        void RenderPapelPicado(Graphics lg)
        {
            int lh = LightsHeight;
            if (picadoBmp == null || picadoBmp.Width != W || picadoBmp.Height != lh) MakePapelPicado(lh);
            lg.DrawImageUnscaled(picadoBmp, 0, 0);
        }

        // ------------------------------------------------------------------ lys på vindueskanterne
        // Small candles stand on the edges of windows where petals lie, half sunk into them, one about every 150
        // points, at places fixed on the window (so they stay put while the petals grow). A candle only stands where
        // the edge is not hidden by a window in front. The flames flicker. (Sizes in the window snow's unit, Ledge.U.)
        void DrawLedgeCandles()
        {
            if (!cfg.WindowSnow) return;
            float ox = ScreenBounds.X, oy = ScreenBounds.Y, u = Ledge.U;
            foreach (var l in c.LedgeList)
            {
                bool dragged = l.Moving && l.Rect.Size == l.Settled.Size;
                if (!l.HasSnow || dragged) continue;
                if (l.Settled.Right <= ox || l.Settled.Left >= ox + W || l.Settled.Top <= oy || l.Settled.Top > oy + H) continue;
                float edge = l.Settled.Top - oy;
                int id = (int)(l.Id & 0xFFFF);
                float wide = l.Settled.Width / u;
                int count = Math.Max(1, (int)((wide - 40) / 150));
                float gap = (wide - 40) / count;
                for (int k = 0; k < count; k++)
                {
                    float jitter = ((id * 7 + k * 13) % 9 - 4) * 3;
                    float gx = l.Settled.Left + (20 + gap * (k + 0.5f) + jitter) * u;
                    float tall = 14 + ((id + k * 5) % 3) * 2.5f;
                    if (gx < ox - 20 * u || gx > ox + W + 20 * u || !l.IsVisible(gx)) continue;
                    float h = l.HeightAt(gx);
                    if (h < 1.2f * u) continue;   // no petals here yet: the candle comes with them
                    float foot = edge - h * 0.55f, x = gx - ox;
                    double t = c.Time * (7 + k % 3) + k * 1.7 + id % 11;
                    float flicker = (float)(0.82 + 0.1 * Math.Sin(t) + 0.08 * Math.Sin(t * 2.3 + 1));
                    Mark(x - 22 * u, foot - (tall + 26) * u, 44 * u, (tall + 28) * u);
                    var st = g.Save();
                    g.TranslateTransform(x, foot);
                    g.ScaleTransform(u, u);
                    Glow(C(255, 200, 90, (int)(210 * flicker)), 0, -tall - 4, 20 * flicker);
                    // the wax stub, lit from the left
                    FillRect(C(250, 242, 222), -tall * 0.156f, -tall * 0.94f, tall * 0.3125f, tall * 0.94f);
                    FillRect(C(222, 206, 176), tall * 0.03f, -tall * 0.94f, tall * 0.125f, tall * 0.94f);
                    Line(C(60, 40, 30), 0.8f, 0, -tall * 0.94f, 0, -tall * 0.94f - 2);
                    float fx = (float)Math.Sin(t * 1.3) * 0.4f, fw = 5.5f, fh = 9 * flicker, fy = -tall - 3.5f * flicker - fh / 2;
                    Fill(C(255, 170, 30), new Shape().Start(fx, fy).Curve(fx + fw * 0.47f, fy + fh * 0.44f, fx + fw * 0.34f, fy + fh, fx, fy + fh)
                        .Curve(fx - fw * 0.34f, fy + fh, fx - fw * 0.47f, fy + fh * 0.44f, fx, fy).Close());
                    FillEllipse(C(255, 246, 200), fx - fw * 0.125f, fy + fh * 0.45f, fw * 0.25f, fh * 0.4f);
                    g.Restore(st);
                }
            }
        }
    }
}
