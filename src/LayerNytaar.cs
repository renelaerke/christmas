using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace JuleHygge
{
    // New Year (Controller.Nytaar), ported from the macOS version (OverlayNytaar.swift), where each Christmas element
    // has its New Year form. Confetti and paper streamers fall and pile up in the leaves' place (the same code with
    // other pictures, MakeConfettiSprites); here are the large clock that shows the time and is decorated step by
    // step in the snowman's place, the party guests in paper hats that walk in the nisser's, the string of pennants
    // and paper lanterns that hangs in the lights', the sparklers and party poppers on the window edges, and the
    // small street sweeper in the plow's. The rockets in Santa's place are particles, not a figure: see
    // Controller.LaunchVolley. Nothing here shows or suggests drinking: no glasses, bottles or corks.
    // The drawing is kept line for line the same as there, with the helpers of LayerAutumn.cs and LayerMuertos.cs.
    // All figures are original.
    partial class Layer
    {
        // New Year's confetti and streamers: gold and silver, and a few strong colours.
        public static readonly Color[] ConfettiColours = {
            C(240, 196, 64), C(214, 220, 230), C(233, 50, 90), C(40, 160, 220), C(120, 200, 80), C(160, 90, 220), C(255, 140, 40) };
        static readonly Color PartyInk = C(38, 34, 52), PartyGold = C(235, 195, 70);
        static readonly Color[] Skins = { C(255, 214, 186), C(232, 180, 140), C(170, 118, 84), C(250, 224, 200) };
        static readonly Color[] Hairs = { C(92, 60, 36), C(40, 34, 36), C(214, 170, 90), C(150, 70, 40) };
        static readonly Color[] PartyClothes = { C(36, 60, 120), C(196, 42, 82), C(30, 120, 110), C(120, 60, 160) };
        static readonly Color[] LanternColours = { C(233, 60, 80), C(255, 150, 40), C(60, 170, 210), C(170, 100, 220) };
        // The eight guests (Nisse.Look): a dress or a jacket, and which clothes, skin, hair and hat; a balloon's colour
        // for the three who have one when their hands are empty (-1 = none). A guest keeps its look: what changes
        // hands at a meeting is only the cracker.
        static readonly int[,] GuestLooks = {
            { 0, 0, 0, 0, 2, -1 }, { 1, 1, 2, 1, 4, 3 }, { 0, 2, 1, 3, 0, -1 }, { 1, 3, 3, 2, 6, -1 },
            { 1, 1, 0, 1, 3, -1 }, { 0, 0, 2, 1, 5, 4 }, { 1, 3, 1, 0, 2, 6 }, { 0, 2, 3, 2, 4, -1 } };

        Bitmap partyGarlandBmp;

        void DisposeNytaar()
        {
            if (partyGarlandBmp != null) { partyGarlandBmp.Dispose(); partyGarlandBmp = null; }
        }

        static Color Faded(Color c, int alpha) { return Color.FromArgb(c.A * Math.Max(0, Math.Min(255, alpha)) / 255, c); }

        // ------------------------------------------------------------------ konfetti
        // The pictures that fall and pile up: in every colour two slips of paper seen at a slant (one half in shade,
        // as if folded), a round piece, a narrow slip, and a curl of paper streamer. Laid out colour by colour, five
        // to each (ConfettiKinds in all), and blended like the leaves (BlendLeaf).
        public const int ConfettiKinds = 35;
        static int[][] confettiSprites;

        static int[][] MakeConfettiSprites()
        {
            var all = new int[ConfettiKinds][];
            for (int ci = 0; ci < ConfettiColours.Length; ci++)
                for (int shape = 0; shape < 5; shape++)
                    using (var bmp = new Bitmap(LeafPx, LeafPx, PixelFormat.Format32bppPArgb))
                    {
                        Color colour = ConfettiColours[ci], dark = Shade(colour, 0.78f);
                        using (var lg = Graphics.FromImage(bmp))
                        using (var fill = new SolidBrush(colour))
                        using (var shadow = new SolidBrush(dark))
                        {
                            lg.SmoothingMode = SmoothingMode.AntiAlias;
                            lg.Clear(Color.Transparent);
                            switch (shape)
                            {
                                case 0:
                                    lg.FillPolygon(fill, new[] { new PointF(14, 22), new PointF(48, 16), new PointF(52, 40), new PointF(18, 46) });
                                    lg.FillPolygon(shadow, new[] { new PointF(31, 19), new PointF(48, 16), new PointF(52, 40), new PointF(35, 43) });
                                    break;
                                case 1:
                                    lg.FillPolygon(fill, new[] { new PointF(20, 14), new PointF(44, 20), new PointF(40, 50), new PointF(16, 44) });
                                    lg.FillPolygon(shadow, new[] { new PointF(18, 29), new PointF(42, 35), new PointF(40, 50), new PointF(16, 44) });
                                    break;
                                case 2:
                                    lg.FillEllipse(fill, 16, 18, 32, 28);
                                    lg.FillEllipse(shadow, 30, 22, 18, 24);
                                    break;
                                case 3:
                                    lg.FillPolygon(fill, new[] { new PointF(8, 26), new PointF(54, 20), new PointF(56, 30), new PointF(10, 36) });
                                    lg.FillPolygon(shadow, new[] { new PointF(32, 23), new PointF(54, 20), new PointF(56, 30), new PointF(34, 33) });
                                    break;
                                default:
                                    // a streamer: a ribbon in an S with a curl at one end
                                    using (var wide = new Pen(dark, 7))
                                    using (var light = new Pen(colour, 7))
                                    using (var thin = new Pen(colour, 5))
                                    {
                                        wide.StartCap = wide.EndCap = light.StartCap = light.EndCap = thin.StartCap = thin.EndCap = LineCap.Round;
                                        lg.DrawBezier(wide, 6, 40, 18, 12, 30, 52, 44, 26);
                                        lg.DrawBezier(light, 44, 26, 50, 14, 62, 20, 56, 30);
                                        lg.DrawBezier(thin, 56, 30, 52, 36, 46, 32, 49, 27);
                                    }
                                    break;
                            }
                        }
                        var px = new int[LeafPx * LeafPx];
                        var data = bmp.LockBits(new Rectangle(0, 0, LeafPx, LeafPx), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
                        Marshal.Copy(data.Scan0, px, 0, px.Length);
                        bmp.UnlockBits(data);
                        all[ci * 5 + shape] = px;
                    }
            return all;
        }

        // ------------------------------------------------------------------ uret
        // One paper lantern: a round ribbed ball, r wide to each side of (cx, cy). Lit, it glows; `alpha` fades the
        // whole of it (the garland's lit lanterns twinkle over their unlit forms).
        void DrawPaperLantern(float cx, float cy, float r, Color colour, bool lit = false, int alpha = 255)
        {
            float ry = r * 1.08f;
            if (lit) Glow(Faded(C(255, 226, 150, 120), alpha), cx, cy, r * 2);
            FillEllipse(Faded(Shade(colour, lit ? 0.95f : 0.7f), alpha), cx - r, cy - ry, 2 * r, 2 * ry);
            FillEllipse(Faded(lit ? Shade(colour, 1.25f) : Shade(colour, 0.88f), alpha), cx - r * 0.62f, cy - ry, r * 1.24f, 2 * ry);
            StrokeEllipse(Faded(Shade(colour, 0.55f), alpha), Math.Max(0.5f, r * 0.07f), cx - r * 0.26f, cy - ry, r * 0.52f, 2 * ry);
            if (lit) FillEllipse(Faded(C(255, 244, 200, 170), alpha), cx - r * 0.3f, cy - ry * 0.4f, r * 0.6f, ry * 0.9f);
            // the rings at top and bottom
            FillRect(Faded(PartyInk, alpha), cx - r * 0.36f, cy - ry - r * 0.12f, r * 0.72f, r * 0.2f);
            FillRect(Faded(PartyInk, alpha), cx - r * 0.3f, cy + ry - r * 0.08f, r * 0.6f, r * 0.18f);
        }

        // A row of pennants hanging from a line that sags from (x0, y0) to (x1, y1).
        void DrawPennantLine(float x0, float y0, float x1, float y1, float sag, int count, float size, int first)
        {
            Func<float, PointF> at = u => new PointF(x0 + (x1 - x0) * u, y0 + (y1 - y0) * u + sag * 4 * u * (1 - u));
            var pts = new PointF[17];
            for (int k = 0; k <= 16; k++) pts[k] = at(k / 16f);
            using (var pen = new Pen(C(60, 50, 60, 220), Math.Max(0.6f, size * 0.09f)))
            {
                pen.StartCap = pen.EndCap = LineCap.Round;
                T.DrawLines(pen, pts);
            }
            for (int k = 0; k < count; k++)
            {
                float u = (k + 0.5f) / count;
                PointF a = at(u - 0.4f / count), b = at(u + 0.4f / count);
                Color col = ConfettiColours[(first + k * 2) % ConfettiColours.Length];
                float mx = (a.X + b.X) / 2, my = (a.Y + b.Y) / 2;
                FillPoly(col, a.X, a.Y, b.X, b.Y, mx, my + size);
                FillPoly(Shade(col, 0.8f), mx, my, b.X, b.Y, mx, my + size);
            }
        }

        void ClockHand(float cy, float turn, float len, float width, Color col, float tail)
        {
            double a = turn * 2 * Math.PI;
            float s = (float)Math.Sin(a), co = (float)Math.Cos(a);
            Line(col, width, -s * tail, cy + co * tail, s * len, cy - co * len, true);
        }

        // New Year's form of the snowman: a large clock on a stand whose hands show the time, decorated a step for
        // every hour the app runs (Controller.ClockSteps), in the same place and frame as the snowman. The clock
        // itself stands from the first step: it is the countdown. Origin at the ground, y up is negative.
        void DrawPartyClock(int stage)
        {
            Color iron = C(52, 62, 86), ironLight = C(92, 104, 132), face = C(250, 246, 232);
            const float cy = -84, r = 30;
            FillEllipse(C(20, 16, 30, 55), -44, -3, 88, 6);

            // the poles the pennants and lanterns hang on (steps 5-8)
            for (int i = 0; i < 2; i++)
            {
                float side = i == 0 ? -1 : 1;
                if (stage < 5 + i) continue;
                Line(C(120, 88, 56), 2.2f, side * 54, 0, side * 54, -70, true);
                DrawPennantLine(side * 54, -70, side * 24, -100, 9, 4, 8, side < 0 ? 0 : 3);
            }
            // balloons tied to the foot (steps 9 and 10)
            float[,] balloons = { { 30, -40 }, { 42, -54 } };
            for (int i = 0; i < 2; i++)
            {
                float side = i == 0 ? -1 : 1;
                if (stage < 9 + i) continue;
                for (int k = 0; k < 2; k++)
                {
                    float bx = balloons[k, 0], by = balloons[k, 1];
                    Color col = ConfettiColours[(k * 3 + (side < 0 ? 2 : 4)) % ConfettiColours.Length];
                    Bezier(C(230, 230, 240, 170), 0.7f, side * 10, -5, side * 14, -22, side * (bx - 8), by + 26, side * bx, by + 10);
                    FillEllipse(col, side * bx - 8, by - 10, 16, 20);
                    FillPoly(col, side * bx - 2, by + 9.5f, side * bx + 2, by + 9.5f, side * bx, by + 12.5f);
                    FillEllipse(C(255, 255, 255, 110), side * bx - 5, by - 7, 4.5f, 7);
                }
            }

            // the stand: a foot, a post and a collar under the clock
            Fill(iron, new Shape().Start(-22, 0).Curve(-20, -7, -8, -8, -5, -12).To(5, -12).Curve(8, -8, 20, -7, 22, 0).Close());
            FillRect(iron, -3.6f, -56, 7.2f, 46);
            FillRect(ironLight, -3.6f, -56, 2.2f, 46);
            FillRect(iron, -6.5f, -57, 13, 4);
            // paper streamers wound round the post (step 4)
            if (stage >= 4)
            {
                for (int k = 0; k < 6; k++)
                {
                    float y = -14 - k * 7;
                    FillPoly(ConfettiColours[(k * 2) % ConfettiColours.Length], -3.8f, y, 3.8f, y - 4, 3.8f, y - 7, -3.8f, y - 3);
                }
                Bezier(ConfettiColours[2], 1.6f, 3.8f, -16, 12, -12, 8, -4, 15, -1);
                Bezier(ConfettiColours[0], 1.6f, -3.8f, -22, -12, -18, -9, -8, -16, -2);
            }

            // the clock: a dark case, a pale face with twelve marks, two hands
            FillEllipse(C(20, 16, 30, 40), -r - 3, cy - r - 1, 2 * r + 6, 2 * r + 6);
            FillEllipse(iron, -r - 2, cy - r - 2, 2 * r + 4, 2 * r + 4);
            if (stage >= 2) StrokeEllipse(PartyGold, 2.4f, -r - 0.6f, cy - r - 0.6f, 2 * r + 1.2f, 2 * r + 1.2f);
            FillEllipse(face, -r + 3, cy - r + 3, 2 * r - 6, 2 * r - 6);
            StrokeEllipse(C(214, 204, 180), 1, -r + 4.5f, cy - r + 4.5f, 2 * r - 9, 2 * r - 9);
            for (int k = 0; k < 12; k++)
            {
                double a = k * Math.PI / 6;
                bool big = k % 3 == 0;
                float r0 = r - (big ? 11 : 8.5f), r1 = r - 5.5f, s = (float)Math.Sin(a), co = (float)Math.Cos(a);
                Line(PartyInk, big ? 2.2f : 1.1f, s * r0, cy - co * r0, s * r1, cy - co * r1, true);
            }
            DateTime now = c.ClockNow;
            float second = now.Second, minute = now.Minute + second / 60, hour = now.Hour % 12 + minute / 60;
            ClockHand(cy, hour / 12, 13.5f, 3, PartyInk, 3);
            ClockHand(cy, minute / 60, 20.5f, 2, PartyInk, 3);
            // the second hand is only there in the last minute before midnight
            if (c.NewYearClose) ClockHand(cy, second / 60, 21.5f, 0.9f, C(214, 40, 60), 5);
            FillEllipse(PartyGold, -2.2f, cy - 2.2f, 4.4f, 4.4f);
            // small gold bulbs round the case (step 2)
            if (stage >= 2)
                for (int k = 0; k < 12; k++)
                {
                    double a = (k + 0.5) * Math.PI / 6;
                    FillEllipse(C(255, 232, 150), (float)Math.Sin(a) * (r + 1) - 1.6f, cy - (float)Math.Cos(a) * (r + 1) - 1.6f, 3.2f, 3.2f);
                }
            // a bow under the clock (step 3)
            if (stage >= 3)
            {
                Color red = C(214, 40, 70);
                FillPoly(red, 0, -52, -12, -58, -12, -46); FillPoly(red, 0, -52, 12, -58, 12, -46);
                FillPoly(Shade(red, 0.8f), -2, -51, -9, -38, -4, -39, 0, -49); FillPoly(Shade(red, 0.8f), 2, -51, 9, -38, 4, -39, 0, -49);
                FillEllipse(Shade(red, 1.15f), -3, -55, 6, 6);
            }
            // a paper lantern on each pole (steps 7 and 8)
            if (stage >= 7) DrawPaperLantern(-54, -79, 8, C(233, 60, 80), true);
            if (stage >= 8) DrawPaperLantern(54, -79, 8, C(255, 150, 40), true);
            // a gold star on top (step 11)
            if (stage >= 11)
            {
                T.FillPolygon(Br(Shade(PartyGold, 0.8f)), StarPoints(0, -121, 9.5f, 4.2f, 0));
                T.FillPolygon(Br(C(255, 226, 120)), StarPoints(0, -121, 7.5f, 3.4f, 0));
            }
            // two sparklers behind the star, burning (step 12)
            if (stage >= 12)
                foreach (float side in new[] { -1f, 1f })
                {
                    Line(C(90, 90, 100), 1, side * 5, -112, side * 17, -127, true);
                    float x = side * 17, y = -127;
                    for (int k = 0; k < 8; k++)
                    {
                        double a = k * Math.PI / 4 + side * 0.3;
                        float len = k % 2 == 0 ? 6 : 3.6f;
                        Line(k % 2 == 0 ? C(255, 240, 190) : C(255, 206, 110), 0.8f, x, y, x + (float)Math.Cos(a) * len, y + (float)Math.Sin(a) * len, true);
                    }
                    FillEllipse(C(255, 252, 230), x - 1.6f, y - 1.6f, 3.2f, 3.2f);
                }
        }

        // ------------------------------------------------------------------ festgæster
        // New Year's walkers. They are nisser in everything but looks: they walk, stop, wave, cross to the next
        // screen and meet to hand something over (a party cracker). Each wears a paper hat; half are in a dress and
        // half in jacket and trousers, and now and then one has a balloon on a string. "Waving" is a jump with a
        // blow on a party horn. Drawn like a nisse: feet at (0, 0), y up is negative, facing right.
        void DrawGuest(Nisse n)
        {
            float p = n.State == 0 ? n.WalkPhase : 0, standPhase = n.State == 1 ? n.T * 1.5f : 0, wavePhase = n.State == 2 ? n.T * 11f : 0;
            bool walking = n.State == 0, waving = n.State == 2;
            float legA = walking ? (float)Math.Sin(p) * 0.55f : 0;
            // the jump: off the ground and down again, once for every blow of the horn
            float jump = waving ? Math.Abs((float)Math.Sin(wavePhase)) * 6 : 0;
            float bob = walking ? -Math.Abs((float)Math.Sin(p)) * 1.5f : -jump;
            int who = ((n.Look % 8) + 8) % 8;
            bool dress = GuestLooks[who, 0] == 1;
            Color cloth = PartyClothes[GuestLooks[who, 1]], skin = Skins[GuestLooks[who, 2]], hair = Hairs[GuestLooks[who, 3]];
            Color hatCol = ConfettiColours[GuestLooks[who, 4]], ink = PartyInk;
            int balloon = GuestLooks[who, 5];
            int giftIndex = Math.Max(0, Array.IndexOf(Gifts, n.Gift));
            FillEllipse(C(30, 20, 40, 50), -10, -2, 20, 4);

            // a balloon on a string, for some of those with empty hands
            if (!n.CarriesGift && balloon >= 0)
            {
                float sw = (float)Math.Sin(walking ? p * 0.5f : standPhase) * 2;
                Color col = ConfettiColours[balloon];
                Bezier(C(235, 235, 245, 180), 0.7f, -8, -24 + bob, -10, -36 + bob, -15 - sw * 0.5f, -40, -14 - sw, -50);
                FillEllipse(col, -21 - sw, -66, 14, 17);
                FillPoly(col, -15.6f - sw, -49.6f, -12.4f - sw, -49.6f, -14 - sw, -47.4f);
                FillEllipse(C(255, 255, 255, 120), -18.6f - sw, -63.5f, 4, 6);
            }

            // legs: tights under a dress, trousers otherwise
            Color legCol = dress ? C(60, 54, 80) : Shade(cloth, 0.62f);
            foreach (float s in new[] { -1f, 1f })
            {
                float hx = 2 * s, a = -legA * s;
                float spread = waving ? (hx < 0 ? -0.35f : 0.35f) * (jump / 6) : 0;
                float fx = hx + (float)Math.Sin(a + spread) * 13, fy = -14 + bob + (float)Math.Cos(a + spread) * 13;
                Line(legCol, dress ? 3 : 4, hx, -14 + bob, fx, fy, true);
                FillEllipse(ink, fx - 3, fy - 2, 8, 4.2f);
            }

            var st = T.Save();
            T.TranslateTransform(0, bob);
            float backArm, frontArm;
            if (waving) { backArm = -2.5f - (float)Math.Sin(wavePhase) * 0.3f; frontArm = 1.9f; }
            else if (n.CarriesGift) { backArm = 1.3f; frontArm = 1.3f; }
            else { backArm = -legA * 0.9f; frontArm = legA * 0.9f; }
            TreaterArm(-1, -31, backArm, Shade(cloth, 0.86f), skin);

            if (dress)
            {
                Fill(cloth, new Shape().Start(-5, -33).To(5, -33).Curve(6.5f, -26, 10, -18, 11.5f, -11).To(-11.5f, -11).Curve(-10, -18, -6.5f, -26, -5, -33).Close());
                Line(Shade(cloth, 1.35f), 1.4f, -6.2f, -24, 6.2f, -24);
                // a few sequins
                float[,] sequins = { { -4, -15 }, { 2, -18 }, { 6, -14 }, { -1, -13 } };
                for (int k = 0; k < 4; k++) FillEllipse(C(255, 240, 190, 220), sequins[k, 0], sequins[k, 1], 1.4f, 1.4f);
            }
            else
            {
                FillRect(Shade(cloth, 0.62f), -5, -16, 10, 4);
                Fill(cloth, new Shape().Start(-5.5f, -33).To(5.5f, -33).Curve(6.5f, -26, 6.5f, -19, 6, -13).To(-6, -13).Curve(-6.5f, -19, -6.5f, -26, -5.5f, -33).Close());
                // a shirt front and a bow tie
                FillPoly(C(248, 248, 252), 1.5f, -33, 5.5f, -33, 4.5f, -22);
                FillPoly(hatCol, 3.6f, -31, 1.2f, -32.6f, 1.2f, -29.4f); FillPoly(hatCol, 3.6f, -31, 6, -32.6f, 6, -29.4f);
            }

            // the party cracker: a wrapped tube with a twist at each end
            if (n.CarriesGift && !waving)
            {
                Color col = Gifts[giftIndex % Gifts.Length];
                var st2 = T.Save();
                T.TranslateTransform(12.5f, -20);
                T.RotateTransform(-0.35f * 180 / (float)Math.PI);
                FillPoly(col, -9, -3.4f, -5, -1.4f, -5, 1.4f, -9, 3.4f); FillPoly(col, 9, -3.4f, 5, -1.4f, 5, 1.4f, 9, 3.4f);
                FillRect(col, -5, -2.8f, 10, 5.6f);
                FillRect(PartyGold, -1.4f, -2.8f, 2.8f, 5.6f);
                FillRect(C(255, 255, 255, 150), -4.6f, -2.8f, 1.2f, 5.6f); FillRect(C(255, 255, 255, 150), 3.4f, -2.8f, 1.2f, 5.6f);
                T.Restore(st2);
            }

            // the head, looking a little the way it walks
            float sway = (float)Math.Sin(walking ? p * 0.5f : standPhase) * 0.05f;
            var st3 = T.Save();
            T.TranslateTransform(1, -40);
            T.RotateTransform((sway - (waving ? 0.12f : 0)) * 180 / (float)Math.PI);
            if (dress)   // long hair down the back
                Fill(hair, new Shape().Start(-6.8f, -3).Curve(-9.5f, 2, -9, 9, -6, 11).To(-2.5f, 6).Curve(-4, 3, -4, 0, -3, -3).Close());
            FillEllipse(skin, -6.5f, -6.5f, 13, 13);
            FillEllipse(hair, -7, -7.4f, 12.4f, 7.4f);
            FillEllipse(skin, -3.4f, -4.6f, 9.6f, 6.4f);
            FillEllipse(C(250, 160, 150, 140), 1.6f, 0.4f, 3.6f, 2.6f);
            FillEllipse(ink, 1.6f, -2.2f, 1.9f, 2.5f);
            FillEllipse(ink, 4.5f, -2.2f, 1.5f, 2.3f);
            if (waving) FillEllipse(ink, 4.6f, 2.2f, 2.2f, 2.2f);
            else Bezier(ink, 0.8f, 1.6f, 2.6f, 3, 4.2f, 4.6f, 4.2f, 5.6f, 2.6f);
            // the paper hat: a striped cone with a pompom, a little askew
            var st4 = T.Save();
            T.TranslateTransform(-0.6f, -6);
            T.RotateTransform(-0.16f * 180 / (float)Math.PI);
            FillPoly(hatCol, -5.4f, 0.6f, 5.4f, 0.6f, 0.4f, -14.5f);
            FillPoly(Shade(hatCol, 1.3f), -3.5f, -4.6f, 3.6f, -4.6f, 2.7f, -7.2f, -2.6f, -7.2f);
            FillPoly(PartyGold, -5.4f, 0.6f, 5.4f, 0.6f, 4.7f, -1.6f, -4.7f, -1.6f);
            FillEllipse(C(255, 255, 255), -1.8f, -17.6f, 4.6f, 4.6f);
            T.Restore(st4);
            // the party horn: blown out straight with its tip still curled
            if (waving)
            {
                // (no longer than the walker's own box is wide: that is all that is cleared behind it)
                float reach = 8 + Math.Abs((float)Math.Sin(wavePhase)) * 8;
                int parts = (int)(reach / 3);
                Line(C(250, 250, 250), 1.8f, 5.6f, 3.2f, 8.5f, 3.6f, true);
                for (int k = 0; k < parts; k++)
                    Line(k % 2 == 0 ? C(233, 50, 90) : PartyGold, 3, 8.5f + k * 3, 3.6f - k * 0.25f, 8.5f + (k + 1) * 3, 3.6f - (k + 1) * 0.25f);
                float ex = 8.5f + parts * 3, ey = 3.6f - parts * 0.25f;
                StrokeEllipse(C(233, 50, 90), 1.8f, ex - 0.4f, ey - 5, 5, 5);
            }
            T.Restore(st3);

            TreaterArm(1, -31, frontArm, Shade(cloth, 0.86f), skin);
            T.Restore(st);
        }

        // ------------------------------------------------------------------ vimpler og papirlanterner
        // What hangs at a bulb's place (idx counts them): every other one a small gold bulb, the others a paper
        // lantern. Unlit it is drawn once with the string; lit, over it at `alpha` (0-255) as it twinkles.
        void DrawPartyBulb(int idx, float bx, float by, bool lit, int alpha)
        {
            if (idx % 2 == 0)
            {
                if (!lit)
                {
                    FillRect(C(70, 60, 50), bx - 2.5f * S, by, 5 * S, 4 * S);
                    FillEllipse(C(150, 118, 50), bx - 3.5f * S, by + 3 * S, 7 * S, 11 * S);
                    return;
                }
                // a soft glow that fades out to nothing (a flat disc looks like a grey plate on a dark desktop)
                Glow(C(255, 220, 120, 150 * alpha / 255), bx, by + 9 * S, 12 * S);
                FillEllipse(C(255, 226, 130, alpha), bx - 3.5f * S, by + 3 * S, 7 * S, 11 * S);
                FillEllipse(C(255, 255, 255, 170 * alpha / 255), bx - 1.8f * S, by + 5 * S, 2.4f * S, 3.6f * S);
                return;
            }
            Color col = LanternColours[(idx / 2) % LanternColours.Length];
            if (!lit) Line(C(60, 50, 60), 1 * S, bx, by, bx, by + 6 * S);
            DrawPaperLantern(bx, by + 13.5f * S, 7 * S, col, lit, lit ? alpha : 255);
        }

        // The string itself: pennants in the confetti's colours between the bulbs, and at the bulbs' places the unlit
        // gold bulbs and paper lanterns. Nothing in it moves, so it is drawn once and kept (partyGarlandBmp); the lit
        // forms are drawn over it each time the strip is made again.
        void MakePartyGarland(int lh)
        {
            if (partyGarlandBmp != null) partyGarlandBmp.Dispose();
            partyGarlandBmp = new Bitmap(W, lh, PixelFormat.Format32bppPArgb);
            float span = 230 * S, sag = 22 * S, top = 1;
            using (var lg = Graphics.FromImage(partyGarlandBmp))
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
                int n = 0, idx = 0;
                for (float x0 = -span * 0.3f; x0 < W; x0 += span, n++)
                    for (int k = 0; k < 12; k++)
                    {
                        if (k % 3 == 1) continue;
                        float u = (k + 0.5f) / 12, du = 0.026f;
                        float ua = u - du, ub = u + du;
                        float ax = x0 + ua * span, ay = top + sag * (1 - (2 * ua - 1) * (2 * ua - 1));
                        float bx = x0 + ub * span, by = top + sag * (1 - (2 * ub - 1) * (2 * ub - 1));
                        Color col = ConfettiColours[(n * 3 + k) % ConfettiColours.Length];
                        float tx = (ax + bx) / 2 + (float)Math.Sin((n + k) * 2.3) * 1.5f * S, ty = (ay + by) / 2 + 15 * S;
                        FillPoly(col, ax, ay, bx, by, tx, ty);
                        FillPoly(Shade(col, 0.8f), (ax + bx) / 2, (ay + by) / 2, bx, by, tx, ty);
                    }
                for (float x0 = -span * 0.3f; x0 < W; x0 += span)
                    for (int b = 0; b < 4; b++, idx++)
                    {
                        float u = (b + 0.5f) / 4;
                        DrawPartyBulb(idx, x0 + u * span, top + sag * (1 - (2 * u - 1) * (2 * u - 1)), false, 255);
                    }
                into = null;
            }
        }

        void RenderPartyGarland(Graphics lg)
        {
            int lh = LightsHeight;
            if (partyGarlandBmp == null || partyGarlandBmp.Width != W || partyGarlandBmp.Height != lh) MakePartyGarland(lh);
            lg.DrawImageUnscaled(partyGarlandBmp, 0, 0);
            float span = 230 * S, sag = 22 * S, top = 1;
            int idx = 0;
            into = lg;
            for (float x0 = -span * 0.3f; x0 < W; x0 += span)
                for (int b = 0; b < 4; b++, idx++)
                {
                    float u = (b + 0.5f) / 4;
                    // the same slow twinkle as the bulbs
                    float br = 0.55f + 0.45f * (float)Math.Sin(c.Time * (1.3 + (idx * 37 % 10) * 0.12) + idx * 1.7);
                    DrawPartyBulb(idx, x0 + u * span, top + sag * (1 - (2 * u - 1) * (2 * u - 1)), true, Math.Max(0, Math.Min(255, (int)(255 * br))));
                }
            into = null;
        }

        // ------------------------------------------------------------------ fejemaskine
        // New Year's form of the snow plow: a small street sweeper the morning after, with a round brush turning in
        // front of it and a blinking amber lamp on the roof. Facing +x, origin at the ground, the brush where the
        // plow's blade would be. It has no horn and leaves no smoke.
        void DrawSweeper(float ph)
        {
            float step = plowWheel;
            Color body = C(40, 150, 160), bodyDark = C(26, 104, 116), dark = C(46, 48, 58), glass = C(178, 214, 236);
            // the hopper behind, with a window the confetti shows in
            Fill(body, new Shape().Start(-64, -16).To(-64, -52).Curve(-64, -60, -58, -62, -52, -62).To(14, -62).To(14, -16).Close());
            FillRect(bodyDark, -64, -22, 78, 6);
            FillRect(C(232, 240, 244), -52, -52, 34, 18);
            for (int k = 0; k < 14; k++)
                FillRect(ConfettiColours[(k * 3) % ConfettiColours.Length], -51 + (k * 7 % 31), -39 + (k * 5 % 4) - Math.Min(11, ph * 0.3f) * (k % 3) / 2f, 3.6f, 2.6f);
            using (var pen = new Pen(bodyDark, 1.4f)) T.DrawRectangle(pen, -52, -52, 34, 18);
            // yellow and black warning stripes at the back
            for (int k = 0; k < 4; k++)
                FillPoly(k % 2 == 0 ? C(250, 204, 50) : dark, -64, -28 - k * 7, -58, -28 - k * 7, -58, -35 - k * 7, -64, -35 - k * 7);
            // the cab in front: big windows all round
            Fill(Shade(body, 1.12f), new Shape().Start(14, -16).To(14, -66).To(40, -66).Curve(48, -66, 54, -52, 56, -36).To(56, -16).Close());
            Fill(glass, new Shape().Start(20, -38).To(20, -61).To(39, -61).Curve(45, -61, 49, -50, 51, -38).Close());
            Line(C(255, 255, 255, 150), 2, 26, -57, 34, -42);
            Line(bodyDark, 1.4f, 33, -61, 33, -38);
            FillRect(bodyDark, 14, -22, 42, 6);
            // the driver: a head in a cap
            FillEllipse(C(232, 180, 140), 36, -55, 9, 10);
            FillRect(C(250, 150, 40), 35.5f, -56.5f, 10, 3.6f);
            FillRect(C(250, 150, 40), 44, -54.4f, 4, 1.6f);
            // the amber lamp, blinking
            bool blink = Math.Sin(step * 1.3) > 0;
            if (blink) FillEllipse(C(255, 190, 60, 90), 18, -80, 20, 20);
            FillRect(dark, 24, -68, 8, 2.4f);
            FillEllipse(blink ? C(255, 196, 70) : C(190, 120, 30), 24.5f, -74, 7, 8);
            // a headlamp and the bumper
            FillEllipse(C(255, 244, 190), 53, -30, 4.4f, 5.4f);
            FillRect(dark, 50, -17, 10, 4);
            // wheels
            foreach (float wx in new[] { -42f, 34f })
            {
                FillEllipse(dark, wx - 11, -20, 22, 22);
                FillEllipse(C(150, 154, 166), wx - 5, -14, 10, 10);
                for (int k = 0; k < 3; k++)
                {
                    double a = step + k * 2.094;
                    Line(dark, 1.4f, wx, -9, wx + (float)Math.Cos(a) * 5, -9 + (float)Math.Sin(a) * 5);
                }
            }
            // the suction mouth between the wheels
            FillPoly(dark, -18, -16, 10, -16, 14, -3, -22, -3);
            // the arm and the round brush in front, turning: seen from the side it is a flat disc of bristles
            Line(dark, 3, 52, -16, 74, -9, true);
            FillEllipse(dark, 71, -12, 7, 5);
            FillEllipse(C(96, 84, 70), 58, -8, 36, 9);
            for (int k = 0; k < 14; k++)
            {
                double a = step * 2.4 + k * (2 * Math.PI / 14);
                float co = (float)Math.Cos(a), si = (float)Math.Sin(a);
                Line(si > 0 ? C(226, 190, 120) : C(170, 138, 84), 1.5f, 76 + co * 10, -5 + si * 2.6f * 0.4f, 76 + co * 19, 0.5f + si * 2.6f, true);
            }
            // confetti gathered in front of the brush
            float[] gathered = { 96, 103, 110 };
            for (int i = 0; i < gathered.Length; i++)
                if (i * 6 < ph) FillRect(ConfettiColours[(i * 2 + 1) % ConfettiColours.Length], gathered[i], -5 - (i % 2) * 2.4f, 5, 3.4f);
        }

        // ------------------------------------------------------------------ stjernekastere og bordbomber på vindueskanterne
        // On the window edges: sparklers standing here and there, each burning down from its tip in about half a
        // minute and replaced by a new one a little later; and on every edge that is wide enough a party popper
        // lying with its streamers out. Both only where the edge is not hidden by a window in front. (Sizes in the
        // window snow's unit, Ledge.U.)
        void DrawLedgeParty()
        {
            if (!cfg.WindowSnow) return;
            float ox = ScreenBounds.X, oy = ScreenBounds.Y, u = Ledge.U;
            foreach (var l in c.LedgeList)
            {
                bool dragged = l.Moving && l.Rect.Size == l.Settled.Size;
                if (dragged || l.Settled.Width <= 200 * u) continue;
                if (l.Settled.Right <= ox || l.Settled.Left >= ox + W || l.Settled.Top <= oy || l.Settled.Top > oy + H) continue;
                float edge = l.Settled.Top - oy;
                int id = (int)(l.Id % 9973);
                // the popper: somewhere along the middle three fifths
                float px = l.Settled.Left + l.Settled.Width * (0.2f + (id * 53 % 60) / 100f);
                if (l.Settled.Width > 320 * u && px >= ox - 30 * u && px <= ox + W + 30 * u && l.IsVisible(px))
                {
                    float x = px - ox, y = edge - l.HeightAt(px) * 0.9f + 2 * u;
                    Mark(x - 24 * u, y - 20 * u, 48 * u, 22 * u);
                    var st = g.Save();
                    g.TranslateTransform(x, y);
                    g.ScaleTransform(id % 2 == 0 ? u : -u, u);
                    // the streamers thrown out of it
                    Bezier(ConfettiColours[2], 1.4f, 4, -8, 10, -18, 14, -4, 21, -10);
                    Bezier(ConfettiColours[3], 1.4f, 4, -6, 12, -8, 12, -1, 20, -2);
                    Bezier(ConfettiColours[0], 1.4f, 4, -9, 6, -16, 12, -17, 15, -12);
                    float[,] bits = { { 9, -13 }, { 15, -6 }, { 18, -15 }, { 11, -3 }, { 20, -7 } };
                    for (int k = 0; k < 5; k++) FillRect(ConfettiColours[(k * 2 + 1) % ConfettiColours.Length], bits[k, 0], bits[k, 1], 2.4f, 1.8f);
                    // the popper: a cone with a gold collar and a string at its tip
                    FillPoly(C(60, 150, 210), -17, -3.4f, 4, -11.5f, 4, -0.4f);
                    FillPoly(C(40, 110, 170), -17, -3.4f, 4, -5, 4, -0.4f);
                    FillPoly(C(240, 196, 64), 1, -10.4f, 4, -11.5f, 4, -0.4f, 1, -1);
                    Bezier(C(240, 240, 245), 0.8f, -17, -3.4f, -20, -2, -19, 0, -22, -0.6f);
                    g.Restore(st);
                }
                // the sparklers: one about every 300 points
                int count = Math.Max(1, (int)(l.Settled.Width / (300 * u)));
                for (int k = 0; k < count; k++)
                {
                    float gx = l.Settled.Left + l.Settled.Width * (k + 0.5f + ((id + k * 29) % 30 - 15) / 100f) / count;
                    if (gx < ox - 20 * u || gx > ox + W + 20 * u || !l.IsVisible(gx) || Math.Abs(gx - px) <= 34 * u) continue;
                    // 34 s of burning, then 8 s before the next one is lit
                    double t = (c.Time + k * 13.7 + id % 41) % 42;
                    if (t > 34) continue;
                    // (it stands in the confetti, most of its bare wire above it)
                    float foot = edge - l.HeightAt(gx) * 0.75f, x = gx - ox;
                    const float tall = 34, bare = 12;
                    float left = (tall - bare) * (float)(1 - t / 34);   // the coat that has not burnt yet
                    // (down to where its sparks fall when it has burnt low)
                    Mark(x - 16 * u, foot - (tall + 16) * u, 32 * u, (tall + 30) * u);
                    var st = g.Save();
                    g.TranslateTransform(x, foot);
                    g.ScaleTransform(u, u);
                    Line(C(70, 66, 74), 1.2f, 0, 0, 0, -tall);
                    Line(C(150, 150, 160), 2.4f, 0, -bare, 0, -bare - left);
                    // the burning point: a glint that flickers, and a few sparks thrown off it
                    float by = -bare - left;
                    double f = c.Time * 23 + k * 1.7;
                    float flicker = (float)(0.75 + 0.25 * Math.Sin(f) * Math.Sin(f * 0.37 + 1));
                    Glow(C(255, 200, 90, 120), 0, by, 13 * flicker);
                    for (int j = 0; j < 4; j++)
                    {
                        double a = f * 0.3 + j * Math.PI / 4;
                        float len = 7.5f * flicker * (j % 2 == 0 ? 1 : 0.6f);
                        Line(C(255, 250, 225), 0.9f, -(float)Math.Cos(a) * len, by - (float)Math.Sin(a) * len, (float)Math.Cos(a) * len, by + (float)Math.Sin(a) * len, true);
                    }
                    FillEllipse(C(255, 255, 255), -1.8f, by - 1.8f, 3.6f, 3.6f);
                    for (int j = 0; j < 4; j++)
                    {
                        // each spark flies out and falls for a third of a second, then the next one starts
                        double q = c.Time * 3 + j * 0.25 + k;
                        float w = (float)(q - Math.Floor(q)), seed = (int)Math.Floor(q) * 7 + j * 13 + k;
                        float a = seed * 2.4f, reach = 9 + (seed * 3.7f) % 6;
                        FillEllipse(C(255, 220, 120, (int)(255 * (1 - w))), (float)Math.Cos(a) * reach * w - 1, by + (float)Math.Sin(a) * reach * w + 8 * w * w - 1, 2, 2);
                    }
                    g.Restore(st);
                }
            }
        }
    }
}
