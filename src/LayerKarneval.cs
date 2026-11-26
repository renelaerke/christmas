using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace JuleHygge
{
    // Carnival (Controller.Karneval), ported from the macOS version (OverlayKarneval.swift): Rio's parade, each
    // Christmas element in its carnival form. Confetti, streamers and feathers fall and pile up in the leaves' place
    // (New Year's confetti with a feather for every six, MakeCarnivalSprites); here are the carnival float built
    // step by step in the snowman's place, the truck with a band on it that drives along the ground in Santa's, the
    // people of a samba parade in the nisser's (walking in time with the drums: Controller.BeatCount), the fringe
    // garland with masks in the lights', the toucans on the window edges, and the street sweepers of Ash Wednesday
    // in the plow's. The Rhineland's form of each is in LayerKarnevalRhein.cs, and every entry here hands over to it.
    // Nothing here shows or suggests drinking (REL 2026-11-25). The figures are original, clothed and friendly.
    // The drawing is kept line for line the same as on macOS, with the helpers of LayerAutumn.cs and LayerMuertos.cs.
    partial class Layer
    {
        static readonly Color KInk = C(38, 34, 52), KGold = C(240, 196, 64);
        static readonly Color[] KSkins = { C(255, 214, 186), C(206, 150, 106), C(140, 92, 62), C(236, 190, 150), C(110, 72, 50) };
        static readonly Color[] CarnivalColours = { C(255, 64, 129), C(0, 176, 140), C(255, 196, 0), C(60, 120, 230), C(160, 80, 220), C(255, 120, 30), C(40, 190, 80) };

        static float Sf(double a) { return (float)Math.Sin(a); }
        static float Cf(double a) { return (float)Math.Cos(a); }
        void Turn(float radians) { T.RotateTransform(radians * 180 / (float)Math.PI); }
        static Color Alpha(Color c, int a) { return Color.FromArgb(a, c); }

        Bitmap carnivalGarlandBmp;
        int carnivalGarlandForm;

        void DisposeKarneval()
        {
            if (carnivalGarlandBmp != null) { carnivalGarlandBmp.Dispose(); carnivalGarlandBmp = null; }
        }

        // ------------------------------------------------------------------ konfetti med fjer eller karameller
        // What falls and piles up at carnival: New Year's confetti, and after every five of them a sixth picture in
        // the same colour: a feather at Rio's carnival, a wrapped sweet (Kamelle) at the Rhineland's.
        public const int CarnivalKinds = 42;
        static int[][] carnivalSprites, kamelleSprites;

        static int[][] MakeCarnivalSprites(bool sweets)
        {
            if (confettiSprites == null) confettiSprites = MakeConfettiSprites();
            var all = new int[CarnivalKinds][];
            const float m = LeafPx / 2f;
            for (int ci = 0; ci < ConfettiColours.Length; ci++)
            {
                for (int k = 0; k < 5; k++) all[ci * 6 + k] = confettiSprites[ci * 5 + k];
                using (var bmp = new Bitmap(LeafPx, LeafPx, PixelFormat.Format32bppPArgb))
                {
                    Color colour = ConfettiColours[ci];
                    using (var lg = Graphics.FromImage(bmp))
                    using (var fill = new SolidBrush(colour))
                    using (var light = new SolidBrush(Shade(colour, 1.2f)))
                    using (var shine = new SolidBrush(C(255, 255, 255, 110)))
                    using (var quill = new Pen(Shade(colour, 0.7f), 2))
                    using (var barb = new Pen(Shade(colour, 0.82f), 1.2f))
                    {
                        lg.SmoothingMode = SmoothingMode.AntiAlias;
                        lg.Clear(Color.Transparent);
                        if (sweets)
                        {
                            // a sweet in a paper twisted at both ends
                            lg.FillPolygon(light, new[] { new PointF(6, m - 12), new PointF(20, m - 4), new PointF(20, m + 4), new PointF(6, m + 12) });
                            lg.FillPolygon(light, new[] { new PointF(58, m - 12), new PointF(44, m - 4), new PointF(44, m + 4), new PointF(58, m + 12) });
                            lg.FillEllipse(fill, 16, m - 11, 32, 22);
                            lg.FillEllipse(shine, 22, m - 8, 12, 6);
                            lg.DrawLine(quill, 26, m - 10, 26, m + 10); lg.DrawLine(quill, 38, m - 10, 38, m + 10);
                        }
                        else
                        {
                            // a feather: a curved quill with a soft vane to both sides, the tip at the right
                            using (var vane = new GraphicsPath())
                            {
                                vane.AddBezier(12, m + 2, 24, m - 18, 48, m - 18, 60, m - 4);
                                vane.AddBezier(60, m - 4, 50, m + 14, 26, m + 16, 12, m + 2);
                                vane.CloseFigure();
                                lg.FillPath(fill, vane);
                            }
                            lg.DrawBezier(quill, 4, m + 4, 20, m + 2, 44, m - 2, 60, m - 4);
                            for (int k = 0; k < 5; k++) lg.DrawLine(barb, 18 + k * 8, m + 1 - k * 0.8f, 23 + k * 8, m - 9 + k * 0.6f);
                        }
                    }
                    var px = new int[LeafPx * LeafPx];
                    var data = bmp.LockBits(new Rectangle(0, 0, LeafPx, LeafPx), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
                    Marshal.Copy(data.Scan0, px, 0, px.Length);
                    bmp.UnlockBits(data);
                    all[ci * 6 + 5] = px;
                }
            }
            return all;
        }

        // ------------------------------------------------------------------ small people, shared by float, truck and sweepers
        // A small person standing at (x, 0), h tall: legs, a body in cloth, a head. sway leans it; arm is the near
        // arm's angle from straight down (radians, positive forward). For the band and the sweepers.
        void DrawSmallPerson(float x, float h, Color cloth, Color skin, Color legs, float sway, float arm, float step = 0)
        {
            float k = h / 40;
            var st = T.Save();
            T.TranslateTransform(x, 0);
            T.ScaleTransform(k, k);
            Line(legs, 3.4f, -2, -14, -2 + Sf(step) * 5, 0, true);
            Line(legs, 3.4f, 2, -14, 2 - Sf(step) * 5, 0, true);
            T.TranslateTransform(0, -14);
            Turn(sway);
            Fill(cloth, new Shape().Start(-5.5f, -18).To(5.5f, -18).Curve(6.5f, -11, 6.5f, -5, 6, 1).To(-6, 1).Curve(-6.5f, -5, -6.5f, -11, -5.5f, -18).Close());
            FillEllipse(skin, -5.5f, -30, 12, 12);
            FillEllipse(KInk, 2, -25.6f, 1.8f, 2.2f);
            Line(Shade(cloth, 0.85f), 3, 0, -15, Sf(arm) * 9, -15 + Cf(arm) * 9, true);
            FillEllipse(skin, Sf(arm) * 9 - 2, -15 + Cf(arm) * 9 - 2, 4, 4);
            T.Restore(st);
        }

        // ------------------------------------------------------------------ karnevalsvogn
        // Carnival's form of the snowman: a float (carro alegórico) being built, a step for every hour the app runs
        // (Controller.FloatSteps), in the same place and frame as the snowman. Origin at the ground, y up is negative.
        void DrawFloat(int stage)
        {
            if (c.Carnival == Controller.CarnivalRhein) { DrawPrunkwagen(stage); return; }
            Color[] cols = CarnivalColours;
            Color wood = C(120, 84, 52), dark = C(46, 44, 60);
            FillEllipse(C(20, 16, 30, 55), -58, -3, 116, 6);
            // 1: the chassis on its wheels
            FillRect(wood, -54, -14, 108, 5);
            foreach (float wx in new[] { -38f, 0f, 38f })
            {
                FillEllipse(dark, wx - 7, -14, 14, 14);
                FillEllipse(C(150, 154, 166), wx - 2.5f, -9.5f, 5, 5);
            }
            // 2: the lower deck
            if (stage >= 2)
            {
                FillRect(cols[3], -56, -30, 112, 17);
                FillRect(Shade(cols[3], 0.8f), -56, -17, 112, 4);
            }
            // 3: a skirt with a fringe that hides the wheels
            if (stage >= 3)
            {
                FillRect(cols[0], -57, -14, 114, 10);
                for (int k = 0; k < 19; k++) FillPoly(k % 2 == 0 ? cols[2] : cols[0], -57 + k * 6, -4, -51 + k * 6, -4, -54 + k * 6, 1.5f);
            }
            // 4: the upper deck, and steps up to it
            if (stage >= 4)
            {
                FillRect(cols[1], -36, -48, 72, 18);
                FillRect(Shade(cols[1], 0.8f), -36, -33, 72, 3);
                for (int k = 0; k < 3; k++) FillRect(C(250, 240, 220), -52 + k * 5, -34 - k * 4.6f, 6, 4.6f * (k + 1));
            }
            // 5: gold trim along both decks
            if (stage >= 5)
            {
                FillRect(KGold, -56, -31.5f, 112, 2.4f);
                FillRect(KGold, -36, -49.5f, 72, 2.4f);
                for (int k = 0; k < 9; k++) FillEllipse(KGold, -52 + k * 13, -25, 4, 4);
            }
            // 6: two columns
            if (stage >= 6)
                foreach (float cx in new[] { -30f, 30f })
                {
                    FillRect(C(250, 244, 230), cx - 3.5f, -86, 7, 37);
                    FillRect(C(222, 212, 192), cx + 1, -86, 2.5f, 37);
                    FillRect(KGold, cx - 5.5f, -89, 11, 3.4f);
                    FillRect(KGold, cx - 5.5f, -52, 11, 3);
                }
            // 7: a great sun between them, 8: its rays, 9: its face
            if (stage >= 8)
                for (int k = 0; k < 16; k++)
                {
                    double a = k * Math.PI / 8;
                    float r0 = 19, r1 = k % 2 == 0 ? 32 : 26;
                    FillPoly(k % 2 == 0 ? C(255, 170, 30) : KGold,
                        Cf(a - 0.14) * r0, -84 + Sf(a - 0.14) * r0, Cf(a) * r1, -84 + Sf(a) * r1, Cf(a + 0.14) * r0, -84 + Sf(a + 0.14) * r0);
                }
            if (stage >= 7)
            {
                FillEllipse(C(255, 170, 30), -21, -105, 42, 42);
                FillEllipse(C(255, 214, 80), -18, -102, 36, 36);
            }
            if (stage >= 9)
            {
                FillEllipse(KInk, -8.5f, -89, 4, 5); FillEllipse(KInk, 4.5f, -89, 4, 5);
                Bezier(KInk, 1.6f, -9, -79, -4, -72, 4, -72, 9, -79);
                FillEllipse(C(255, 140, 90, 150), -14, -82, 6, 4); FillEllipse(C(255, 140, 90, 150), 8, -82, 6, 4);
            }
            // 10: fans of feathers at both ends
            if (stage >= 10)
                foreach (float side in new[] { -1f, 1f })
                    for (int k = 0; k < 5; k++)
                    {
                        double a = -Math.PI / 2 + side * (0.25 + k * 0.26);
                        Color col = cols[(k + (side < 0 ? 0 : 3)) % cols.Length];
                        float tx = side * 46 + Cf(a) * 30, ty = -32 + Sf(a) * 30;
                        Bezier(Shade(col, 0.8f), 1.2f, side * 46, -32, side * 46 + Cf(a) * 12, -32 + Sf(a) * 14, tx - side * 2, ty + 4, tx, ty);
                        var st = T.Save();
                        T.TranslateTransform(side * 46 + Cf(a) * 20, -32 + Sf(a) * 20);
                        Turn((float)a);
                        FillEllipse(col, -11, -3.4f, 22, 6.8f);
                        T.Restore(st);
                    }
            // 11: coloured bulbs along the decks
            if (stage >= 11)
            {
                for (int k = 0; k < 12; k++) FillEllipse(cols[k % cols.Length], -55 + k * 9.6f, -35.5f, 4.4f, 4.4f);
                for (int k = 0; k < 8; k++) FillEllipse(cols[(k + 2) % cols.Length], -35 + k * 9.4f, -53.5f, 4.2f, 4.2f);
            }
            // 12: streamers from the columns, and a pennant on each
            if (stage >= 12)
                foreach (float side in new[] { -1f, 1f })
                {
                    Bezier(cols[0], 1.6f, side * 30, -88, side * 44, -84, side * 40, -66, side * 52, -60);
                    Bezier(cols[2], 1.6f, side * 30, -88, side * 38, -76, side * 48, -78, side * 56, -70);
                    Line(wood, 1.2f, side * 30, -89, side * 30, -108);
                    FillPoly(cols[side < 0 ? 4 : 5], side * 30, -108, side * 30 + side * 13, -104, side * 30, -100);
                }
        }

        // ------------------------------------------------------------------ sambaoptoget
        // One arm from the shoulder (sx, sy) at angle a from straight down, with a hand; returns where the hand is.
        PointF KArm(float sx, float sy, float a, Color sleeve, Color skin)
        {
            float hx = sx + Sf(a) * 10, hy = sy + Cf(a) * 10;
            Line(sleeve, 3.2f, sx, sy, hx, hy, true);
            FillEllipse(skin, hx - 2.2f, hy - 2.2f, 4.4f, 4.4f);
            return new PointF(hx, hy);
        }

        // The wide skirt of the flag bearer and the baiana; spin (0-1) swings it out.
        void KSkirt(Color col, Color trim, float spin)
        {
            float wide = 15 + spin * 4;
            Fill(col, new Shape().Start(-5, -24).To(5, -24).Curve(9, -18, wide, -8, wide + 1, -1).To(-wide - 1, -1).Curve(-wide, -8, -9, -18, -5, -24).Close());
            FillRect(trim, -wide - 1, -3.4f, 2 * wide + 2, 2.6f);
            for (int k = 0; k < 4; k++) Line(Alpha(trim, 150), 0.8f, -3 + k * 2, -22, (-wide + 4) + k * (2 * wide - 8) / 3, -4);
        }

        // Carnival's walkers: the people of a samba parade. They are nisser in everything but looks (they walk, stop,
        // wave, cross to the next screen and meet), and who each one is follows the walker itself (Nisse.Look), not
        // what it carries: the flag bearer and her escort, a baiana in a wide skirt, a dancer in a feather headdress,
        // two drummers, Pierrot and Harlequin. They step, stand and wave in time with the drums: the phases come
        // from the controller's beat, so every one on every screen moves together.
        // Drawn like a nisse: feet at (0, 0), y up is negative, facing right.
        void DrawReveller(Nisse n)
        {
            // each on the beat or just off it; a walking step takes two beats, standing and waving one bar
            double beats = c.BeatCount + n.Look % 2;
            bool walking = n.State == 0, waving = n.State == 2;
            float p = walking ? (float)((beats / 4 - Math.Floor(beats / 4)) * 4 * Math.PI) : 0;
            float bar = (float)((beats / 2 - Math.Floor(beats / 2)) * 2 * Math.PI);
            float standPhase = n.State == 1 ? bar : 0, wavePhase = waving ? bar : 0;
            int tunic = TunicIndex(n);
            if (c.Carnival == Controller.CarnivalRhein) { DrawJeck(n, p, standPhase, wavePhase, tunic); return; }
            int who = ((n.Look % 8) + 8) % 8;
            float beat = walking ? p : (waving ? wavePhase : standPhase);
            float legA = walking ? Sf(p) * 0.5f : Sf(beat) * 0.12f;
            // everyone bounces on the beat, also standing still
            float bob = -Math.Abs(Sf(beat)) * (waving ? 3 : 1.5f);
            Color skin = KSkins[(n.Look * 3 + tunic) % KSkins.Length];
            Color[] cols = CarnivalColours;
            Color ink = KInk;
            Color own = cols[(n.Look + tunic * 2) % cols.Length], second = cols[(n.Look + tunic * 2 + 3) % cols.Length];
            Color white = C(248, 246, 240), cream = C(250, 246, 236), lace = C(252, 250, 246), straw = C(238, 214, 150);
            FillEllipse(C(30, 20, 40, 50), -11, -2, 22, 4);

            // what each one wears below the waist: a wide skirt to the ground, or legs
            bool wideSkirt = who == 0 || who == 2;
            float spin = waving ? Math.Abs(Sf(wavePhase)) : 0;
            if (!wideSkirt)
            {
                Color legCol = who == 1 || who == 6 ? white : who == 7 ? second : who == 3 ? skin : Shade(own, 0.6f);
                for (int i = 0; i < 2; i++)
                {
                    float hx = i == 0 ? -2 : 2, a = i == 0 ? legA : -legA;
                    float fx = hx + Sf(a) * 13, fy = -14 + bob + Cf(a) * 13;
                    Line(legCol, who == 3 ? 3 : 4, hx, -14 + bob, fx, fy, true);
                    FillEllipse(who == 3 ? KGold : ink, fx - 3, fy - 2, 8, 4.2f);
                }
            }
            var st = T.Save();
            T.TranslateTransform(0, bob);

            float swing = walking ? Sf(p) * 0.8f : Sf(beat) * 0.3f;
            Action hat = () => { };
            PointF h;
            switch (who)
            {
                case 0:   // the flag bearer (porta-bandeira): a wide gown, and the flag held high
                    KArm(-1, -31, -0.5f - swing * 0.2f, cream, skin);
                    KSkirt(cream, KGold, spin);
                    FillRect(cream, -5, -33, 10, 10);
                    FillRect(KGold, -5, -26, 10, 2);
                    h = KArm(1, -31, 2.5f, cream, skin);
                    Line(C(150, 110, 60), 1.4f, h.X, h.Y + 6, h.X + 2, h.Y - 30);
                    float wave = Sf(beat * 2) * 2;
                    Fill(own, new Shape().Start(h.X + 2, h.Y - 30).Curve(h.X + 8, h.Y - 33 + wave, h.X + 14, h.Y - 27 - wave, h.X + 20, h.Y - 30 + wave)
                        .To(h.X + 20, h.Y - 17 + wave).Curve(h.X + 14, h.Y - 14 - wave, h.X + 8, h.Y - 20 + wave, h.X + 1.4f, h.Y - 17).Close());
                    FillEllipse(KGold, h.X + 8, h.Y - 27, 6, 6);
                    hat = () => FillPoly(KGold, -5, -6, -3, -11, -1, -7.5f, 1, -12, 3, -7.5f, 5.5f, -11, 6, -6);
                    break;
                case 1:   // her escort (mestre-sala): a white suit and a straw hat, lifted in a bow when he "waves"
                    KArm(-1, -31, -1.2f + swing * 0.3f, white, skin);
                    Fill(white, new Shape().Start(-5.5f, -33).To(5.5f, -33).Curve(6.5f, -26, 6.5f, -19, 6, -13).To(-6, -13).Curve(-6.5f, -19, -6.5f, -26, -5.5f, -33).Close());
                    FillRect(own, -6, -19, 12, 2.4f);
                    FillPoly(own, 2, -33, 5.5f, -33, 4.6f, -26);
                    h = KArm(1, -31, waving ? 2.4f : 1.2f - swing * 0.3f, white, skin);
                    if (waving)
                    {
                        FillEllipse(straw, h.X - 7, h.Y - 4, 14, 4); FillRect(straw, h.X - 4, h.Y - 8, 8, 5); FillRect(own, h.X - 4, h.Y - 5, 8, 1.6f);
                    }
                    else
                        hat = () => { FillEllipse(straw, -8.5f, -8, 17, 4.4f); FillRect(straw, -5, -12.4f, 10, 5.6f); FillRect(own, -5, -8.8f, 10, 1.8f); };
                    break;
                case 2:   // a baiana: white lace, a wide skirt that swings out when she spins, a head wrap and beads
                    KArm(-1, -31, -1.3f - spin * 0.6f, lace, skin);
                    KSkirt(lace, C(214, 226, 240), spin);
                    FillRect(lace, -5.5f, -33, 11, 10);
                    Bezier(own, 1.4f, -4, -32, -2, -27, 2, -27, 4, -32);
                    Bezier(second, 1.4f, -4.6f, -31, -2, -24.5f, 2, -24.5f, 4.6f, -31);
                    KArm(1, -31, 1.3f + spin * 0.6f, lace, skin);
                    hat = () => { FillEllipse(lace, -7, -11.5f, 14, 8); FillEllipse(C(226, 232, 242), -3, -13.5f, 7, 5); };
                    break;
                case 3:   // a dancer (passista): a sequin dress and a headdress of feathers, arms up
                    KArm(-1, -31, -2.4f + Sf(beat) * 0.4f, own, skin);
                    Fill(own, new Shape().Start(-5, -33).To(5, -33).Curve(6, -26, 8.5f, -19, 9.5f, -14).To(-9.5f, -14).Curve(-8.5f, -19, -6, -26, -5, -33).Close());
                    for (int k = 0; k < 6; k++) FillPoly(k % 2 == 0 ? second : KGold, -9.5f + k * 3.2f, -14, -6.3f + k * 3.2f, -14, -7.9f + k * 3.2f, -9.5f);
                    float[,] sequins = { { -3, -28 }, { 2, -25 }, { -1, -20 }, { 4, -19 }, { -5, -17 } };
                    for (int k = 0; k < 5; k++) FillEllipse(C(255, 250, 220, 230), sequins[k, 0], sequins[k, 1], 1.5f, 1.5f);
                    KArm(1, -31, 2.4f + Sf(beat) * 0.4f, own, skin);
                    hat = () =>
                    {
                        for (int k = 0; k < 7; k++)
                        {
                            double a = -Math.PI / 2 + (k - 3) * 0.3;
                            var fs = T.Save();
                            T.TranslateTransform(Cf(a) * 11, -6 + Sf(a) * 11);
                            Turn((float)a);
                            FillEllipse(k % 2 == 0 ? own : second, -8, -2.4f, 16, 4.8f);
                            T.Restore(fs);
                        }
                        FillRect(KGold, -6, -7.6f, 12, 2.6f);
                    };
                    break;
                case 4:   // the big drum (surdo): carried on a strap, struck on every beat
                    KArm(-1, -31, 0.9f, own, skin);
                    FillRect(own, -5.5f, -33, 11, 18); FillRect(second, -5.5f, -27, 11, 2.2f); FillRect(second, -5.5f, -22, 11, 2.2f);
                    FillRect(Shade(own, 0.6f), -5, -16, 10, 3);
                    Line(ink, 1.2f, -4, -33, 6, -22);
                    FillRect(C(214, 220, 230), 3, -27, 13, 15); FillRect(C(150, 156, 170), 3, -27, 13, 2); FillRect(C(150, 156, 170), 3, -14, 13, 2);
                    FillEllipse(cream, 3, -29, 13, 4);
                    h = KArm(1, -31, 1.5f + Math.Abs(Sf(beat)) * 0.9f, own, skin);
                    Line(C(150, 110, 60), 1.4f, h.X, h.Y, h.X + 5, h.Y + 3.5f); FillEllipse(cream, h.X + 3.6f, h.Y + 2, 4, 4);
                    hat = () => { FillEllipse(second, -7, -8.6f, 14, 5.4f); FillRect(second, 2, -6.4f, 7, 2); };
                    break;
                case 5:   // the small drum (tamborim): held up in one hand, a stick in the other
                    PointF b = KArm(-1, -31, 2.2f, own, skin);
                    FillRect(own, -5.5f, -33, 11, 18); FillRect(second, -5.5f, -24, 11, 3);
                    FillRect(Shade(own, 0.6f), -5, -16, 10, 3);
                    FillEllipse(KGold, b.X - 5, b.Y - 6, 10, 6); FillEllipse(cream, b.X - 4, b.Y - 5.6f, 8, 4.2f);
                    h = KArm(1, -31, 2.3f + Math.Abs(Sf(beat * 2)) * 0.5f, own, skin);
                    Line(C(150, 110, 60), 1.2f, h.X, h.Y, h.X - 7, h.Y - 3);
                    hat = () => { FillEllipse(straw, -8, -8, 16, 4.2f); FillRect(straw, -4.6f, -11.6f, 9.2f, 4.6f); };
                    break;
                case 6:   // Pierrot: baggy white with black pompoms, a ruff and a black cap
                    KArm(-1, -31, -swing, white, skin);
                    Fill(white, new Shape().Start(-6, -33).To(6, -33).Curve(9, -25, 9, -18, 7.5f, -12).To(-7.5f, -12).Curve(-9, -18, -9, -25, -6, -33).Close());
                    foreach (float dy in new[] { -27f, -21f, -15.5f }) FillEllipse(ink, 0.6f, dy, 3.2f, 3.2f);
                    for (int k = 0; k < 5; k++) FillEllipse(C(232, 236, 244), -7 + k * 3, -35.4f, 4.4f, 4);
                    KArm(1, -31, waving ? 2.6f + Sf(wavePhase) * 0.4f : swing, white, skin);
                    hat = () => FillEllipse(ink, -6.6f, -8.6f, 13.2f, 6);
                    break;
                default:  // Harlequin: a suit of diamonds in two colours, and a two-cornered hat
                    KArm(-1, -31, -swing, own, skin);
                    {
                        var cs = T.Save();
                        var suit = new Shape().Start(-5.5f, -33).To(5.5f, -33).Curve(6.5f, -26, 6.5f, -19, 6, -13).To(-6, -13).Curve(-6.5f, -19, -6.5f, -26, -5.5f, -33).Close();
                        T.SetClip(suit.Path, CombineMode.Intersect);
                        suit.Path.Dispose();
                        FillRect(own, -8, -34, 16, 22);
                        for (int row = 0; row < 5; row++)
                            for (int col = 0; col < 4; col++)
                            {
                                float cx = -6 + col * 4 + (row % 2 == 0 ? 0 : 2), cy = -32 + row * 4.4f;
                                FillPoly(second, cx, cy - 2.2f, cx + 2, cy, cx, cy + 2.2f, cx - 2, cy);
                            }
                        T.Restore(cs);
                    }
                    FillPoly(C(250, 250, 250), -4, -34, 4, -34, 0, -30.5f);
                    KArm(1, -31, waving ? 2.6f + Sf(wavePhase) * 0.4f : swing, second, skin);
                    hat = () => { FillPoly(ink, -9, -5, -6, -10, 0, -8, 6, -10, 9, -5); FillEllipse(own, -1.6f, -11.4f, 3.2f, 3.2f); };
                    break;
            }

            // a shaker (chocalho) in the hand of those who carry something: it is what changes hands at a meeting
            if (n.CarriesGift && !waving && who != 0 && who != 4 && who != 5)
            {
                Line(C(150, 110, 60), 1.4f, 11, -22, 14, -16);
                FillEllipse(n.Gift, 6.5f, -28, 8, 7); FillEllipse(C(255, 255, 255, 120), 8, -27, 2.4f, 2.4f);
            }

            // the head, nodding with the beat
            var hs = T.Save();
            T.TranslateTransform(1, -40);
            Turn(Sf(beat) * 0.07f);
            FillEllipse(skin, -6.5f, -6.5f, 13, 13);
            if (who == 6) FillEllipse(C(250, 250, 250), -6.5f, -6.5f, 13, 13);   // Pierrot's white face
            FillEllipse(C(250, 150, 140, 130), 1.6f, 0.4f, 3.6f, 2.6f);
            FillEllipse(ink, 1.6f, -2.2f, 1.9f, 2.5f);
            FillEllipse(ink, 4.5f, -2.2f, 1.5f, 2.3f);
            Bezier(ink, 0.8f, 1.2f, 2.2f, 2.8f, 4.6f, 4.8f, 4.6f, 5.8f, 2.2f);
            hat();
            T.Restore(hs);
            T.Restore(st);
        }

        // ------------------------------------------------------------------ orkesterbil
        // Carnival's "flyer" in Santa's place does not fly: a truck with a band on it drives along the ground, the
        // drums playing while it passes. Drawn in Santa's frame moved down to the ground (DrawSanta): facing +x,
        // origin at the ground under its middle; t is the trip's clock.
        void DrawBandTruck(float t)
        {
            if (c.Carnival == Controller.CarnivalRhein) { DrawFestwagen(t); return; }
            Color[] cols = CarnivalColours;
            double beat = c.BeatCount * Math.PI;
            Color dark = C(46, 44, 60), body = C(250, 196, 40), bodyDark = C(214, 150, 20);
            float roll = t * 5;
            // wheels
            foreach (float wx in new[] { -78f, -52f, 58f })
            {
                FillEllipse(dark, wx - 11, -22, 22, 22);
                FillEllipse(C(160, 164, 176), wx - 4.5f, -15.5f, 9, 9);
                for (int k = 0; k < 3; k++) { double a = roll + k * 2.094; Line(dark, 1.4f, wx, -11, wx + Cf(a) * 4.5f, -11 + Sf(a) * 4.5f); }
            }
            // the cab at the front
            Fill(body, new Shape().Start(40, -16).To(40, -58).To(66, -58).Curve(76, -58, 84, -44, 86, -34).To(92, -30).To(92, -16).Close());
            Fill(C(178, 214, 236), new Shape().Start(52, -36).To(52, -53).To(66, -53).Curve(72, -53, 78, -44, 80, -36).Close());
            FillEllipse(C(206, 150, 106), 60, -49, 8, 9);
            FillRect(bodyDark, 40, -22, 52, 6);
            FillEllipse(C(255, 244, 190), 88, -28, 4.4f, 5.4f);
            // the bed: a stage with a fringed skirt and a row of bulbs that light in turn with the beat
            FillRect(cols[0], -104, -34, 144, 18);
            FillRect(cols[4], -104, -38, 144, 5);
            for (int k = 0; k < 24; k++) FillPoly(k % 2 == 0 ? cols[2] : cols[1], -104 + k * 6, -16, -98 + k * 6, -16, -101 + k * 6, -11);
            int lit = (int)(c.BeatCount * 2);
            for (int k = 0; k < 12; k++)
            {
                bool on = (k + lit) % 3 == 0;
                FillEllipse(on ? C(255, 250, 200) : Shade(cols[k % cols.Length], 0.75f), -101 + k * 12, -30, 5, 5);
            }
            // stacks of loudspeakers at both ends, their cones pumping
            foreach (float sx in new[] { -104f, 18f })
            {
                FillRect(dark, sx, -86, 22, 48);
                for (int k = 0; k < 2; k++)
                {
                    float r = 7 + Math.Abs(Sf(beat)) * 1.2f;
                    FillEllipse(C(96, 96, 112), sx + 11 - r, -74 + k * 22 - r, 2 * r, 2 * r);
                    FillEllipse(dark, sx + 8, -77 + k * 22, 6, 6);
                }
            }
            // the band: a singer, a guitarist and two drummers, bouncing on the beat
            float[] places = { -70, -48, -24, 0 };
            for (int kind = 0; kind < 4; kind++)
            {
                float x = places[kind], b = Sf(beat + kind * 0.5 * Math.PI);
                var st = T.Save();
                T.TranslateTransform(0, -38 - Math.Abs(b) * 2);
                Color skin = KSkins[(kind * 2 + 1) % KSkins.Length];
                DrawSmallPerson(x, 34, cols[(kind + 1) % cols.Length], skin, dark, b * 0.08f, kind == 0 ? 2.3f : 1.2f + Math.Abs(b) * 0.7f);
                switch (kind)
                {
                    case 0: FillEllipse(dark, x + 5, -30, 3.4f, 3.4f); break;   // a microphone
                    case 1:   // a small guitar
                        FillEllipse(C(170, 110, 50), x - 2, -20, 10, 8); Line(C(120, 80, 40), 1.6f, x + 6, -17, x + 16, -24); break;
                    case 2: FillRect(C(214, 220, 230), x + 4, -22, 10, 11); FillEllipse(C(250, 246, 236), x + 4, -24, 10, 4); break;
                    default: FillEllipse(KGold, x + 5, -27, 9, 5); break;
                }
                T.Restore(st);
            }
            // a canopy over them, with a fringe
            Line(dark, 1.6f, -93, -86, -93, -104); Line(dark, 1.6f, 29, -86, 29, -104);
            FillRect(cols[1], -94, -110, 124, 7);
            for (int k = 0; k < 20; k++) FillPoly(k % 2 == 0 ? cols[2] : cols[0], -94 + k * 6.2f, -103, -87.8f + k * 6.2f, -103, -90.9f + k * 6.2f, -98);
        }

        // ------------------------------------------------------------------ gadefejerne
        // Carnival's form of the snow plow: the street sweepers of Ash Wednesday. Two sweepers in orange walk in
        // front with their brooms, one of them dancing as he sweeps, and a cart follows for what they sweep up.
        // Facing +x, origin at the ground, the brooms where the plow's blade would be. No horn and no smoke.
        void DrawStreetSweepers(float ph)
        {
            float step = plowWheel * Controller.DonkeyStride;
            Color orange = C(245, 130, 30), dark = C(46, 44, 60), wood = C(150, 110, 60), trousers = C(60, 70, 110);
            Color[] cols = CarnivalColours;
            // the cart: a bin on two wheels, confetti heaped in it, pushed by a third sweeper
            for (int k = 0; k < 10; k++) FillRect(cols[k % cols.Length], -66 + (k * 7 % 40), -50 - (k % 3) * 3, 5, 3.4f);
            Fill(C(60, 150, 90), new Shape().Start(-74, -46).To(-22, -46).To(-27, -14).To(-69, -14).Close());
            FillRect(C(40, 110, 66), -76, -48, 56, 4);
            foreach (float wx in new[] { -62f, -34f }) { FillEllipse(dark, wx - 8, -16, 16, 16); FillEllipse(C(160, 164, 176), wx - 3, -11, 6, 6); }
            Line(dark, 2, -76, -44, -92, -34, true);
            DrawSmallPerson(-100, 46, orange, KSkins[2], trousers, 0.08f, 1.3f, step);
            // the two with brooms: the second one dances (he turns his broom and bounces)
            for (int i = 0; i < 2; i++)
            {
                float x = i == 0 ? 20 : 62;
                bool dance = i == 1;
                float sw = Sf(step * (dance ? 2 : 1) + i * 1.4);
                var st = T.Save();
                T.TranslateTransform(0, dance ? -Math.Abs(sw) * 3 : 0);
                DrawSmallPerson(x, 48, orange, KSkins[i * 3], trousers, dance ? sw * 0.14f : 0.05f, 0.9f + sw * 0.35f, step + i);
                // a cap, and the broom from the hands down to the ground in front
                FillRect(orange, x - 5, -57.5f, 12, 3.6f);
                T.Restore(st);
                float bx = x + 26 + sw * 7;
                Line(wood, 2, x + 6, -30, bx, -5, true);
                for (int k = 0; k < 6; k++) Line(k % 2 == 0 ? C(214, 170, 72) : C(176, 132, 52), 1.6f, bx, -6, bx - 6 + k * 3.4f, 1, true);
            }
            // confetti gathered in front of the brooms
            float[] gathered = { 96, 103, 110 };
            for (int i = 0; i < gathered.Length; i++)
                if (i * 6 < ph) FillRect(cols[(i * 2 + 1) % cols.Length], gathered[i], -5 - (i % 2) * 2.4f, 5, 3.4f);
        }

        // ------------------------------------------------------------------ frynseguirlande med masker
        // One carnival mask hanging by its ribbon from (x, y): a half-mask with two eye holes and three small plumes.
        void DrawGarlandMask(float x, float y, Color colour, Color plume)
        {
            Line(C(60, 50, 60), 0.9f * S, x, y, x, y + 5 * S);
            for (int k = 0; k < 3; k++)
            {
                var st = T.Save();
                T.TranslateTransform(x + (k - 1) * 3.4f * S, y + 7 * S);
                Turn(-(float)Math.PI / 2 + (k - 1) * 0.45f);
                FillEllipse(plume, 0, -1.4f * S, 8 * S, 2.8f * S);
                T.Restore(st);
            }
            // (the eye holes are left out of the shape itself: what hangs behind the mask shows through them)
            Func<Shape> outline = () => new Shape().Start(x - 9 * S, y + 8 * S)
                .Curve(x - 5 * S, y + 5.5f * S, x + 5 * S, y + 5.5f * S, x + 9 * S, y + 8 * S)
                .Curve(x + 9.5f * S, y + 13 * S, x + 4 * S, y + 15 * S, x + 1.2f * S, y + 11.6f * S)
                .To(x - 1.2f * S, y + 11.6f * S)
                .Curve(x - 4 * S, y + 15 * S, x - 9.5f * S, y + 13 * S, x - 9 * S, y + 8 * S).Close();
            var mask = outline();
            mask.Path.FillMode = FillMode.Alternate;
            mask.Path.AddEllipse(x - 6.4f * S, y + 8.4f * S, 4.2f * S, 2.8f * S);
            mask.Path.AddEllipse(x + 2.2f * S, y + 8.4f * S, 4.2f * S, 2.8f * S);
            Fill(colour, mask);
            Stroke(KGold, 0.9f * S, outline());
        }

        // The garland along the string: a fringe of foil strips in bright colours all the way, and a mask hanging
        // between every two bulbs. Nothing in it moves, so it is drawn once and kept (carnivalGarlandBmp); the bulbs
        // over it are the Christmas lights' own and twinkle as they do (RenderLights).
        void RenderCarnivalGarland(Graphics lg)
        {
            int lh = LightsHeight;
            if (carnivalGarlandBmp == null || carnivalGarlandBmp.Width != W || carnivalGarlandBmp.Height != lh || carnivalGarlandForm != c.Carnival)
            {
                if (carnivalGarlandBmp != null) carnivalGarlandBmp.Dispose();
                carnivalGarlandBmp = new Bitmap(W, lh, PixelFormat.Format32bppPArgb);
                carnivalGarlandForm = c.Carnival;
                float span = 230 * S, sag = 22 * S, top = 1;
                using (var bg = Graphics.FromImage(carnivalGarlandBmp))
                {
                    bg.SmoothingMode = SmoothingMode.AntiAlias;
                    bg.Clear(Color.Transparent);
                    into = bg;
                    if (c.Carnival == Controller.CarnivalRhein) DrawRhenishGarland(span, sag, top);
                    else
                    {
                        Color[] cols = CarnivalColours;
                        int n = 0;
                        for (float x0 = -span * 0.3f; x0 < W; x0 += span, n++)
                        {
                            const int strips = 46;
                            for (int k = 0; k < strips; k++)
                            {
                                float u = (k + 0.5f) / strips;
                                float x = x0 + u * span, y = top + sag * (1 - (2 * u - 1) * (2 * u - 1));
                                float len = (7 + ((k * 7 + n * 3) % 5) * 1.4f) * S;
                                FillRect(cols[(k + n) % cols.Length], x - 1.6f * S, y, 3.2f * S, len);
                            }
                            for (int b = 0; b < 4; b++)
                            {
                                float u = b / 4f;
                                float x = x0 + u * span, y = top + sag * (1 - (2 * u - 1) * (2 * u - 1));
                                DrawGarlandMask(x, y + 6 * S, cols[(b + n * 2) % cols.Length], cols[(b + n * 2 + 3) % cols.Length]);
                            }
                        }
                    }
                    into = null;
                }
            }
            lg.DrawImageUnscaled(carnivalGarlandBmp, 0, 0);
        }

        // ------------------------------------------------------------------ tukaner på vindueskanterne
        // One toucan perched on y = 0, about 30 high, looking right: black with a white throat, a big orange beak
        // with a dark tip (open when it calls), a blue ring round the eye and a tail down behind.
        void DrawToucan(bool calls, float look)
        {
            Color black = C(26, 26, 32);
            FillPoly(black, -7, -8, -13, 6, -8, 6, -3, -6);
            FillEllipse(black, -8, -22, 15, 22);
            FillEllipse(C(250, 246, 236), -1, -19.5f, 8.5f, 11);
            FillEllipse(C(232, 60, 50), -3, -4, 6, 4);
            Line(C(110, 130, 150), 1.4f, -1, -1, -1, 1.4f); Line(C(110, 130, 150), 1.4f, 3, -1, 3, 1.4f);
            var st = T.Save();
            T.TranslateTransform(2, -22);
            Turn(look);
            FillEllipse(black, -6.5f, -6.5f, 13, 12.5f);
            // the beak: the upper half, and the lower one dropped when it calls
            Fill(C(255, 150, 30), new Shape().Start(4, -4).Curve(11, -7.5f, 20, -5, 22, 0.6f).To(4, 0.6f).Close());
            FillPoly(C(255, 214, 80), 4, -3.4f, 13, -5.4f, 14, -2.6f, 4, -1.6f);
            FillPoly(C(40, 30, 30), 18.6f, -2.6f, 22, 0.6f, 18, 0.6f);
            var jaw = T.Save();
            T.TranslateTransform(4, 0.6f);
            Turn(calls ? 0.3f : 0);
            Fill(C(240, 120, 20), new Shape().Start(0, 0).To(17, 0).Curve(13, 3.6f, 5, 4, 0, 2.8f).Close());
            T.Restore(jaw);
            FillEllipse(C(70, 170, 230), 0.4f, -4.6f, 4.6f, 4.6f);
            FillEllipse(black, 1.9f, -3.1f, 1.7f, 1.7f);
            T.Restore(st);
        }

        // Toucans sit on the window edges, one about every 380 points, at places fixed on the window; each looks about
        // and now and then calls. Only where the edge is not hidden by a window in front. (Sizes in the window
        // snow's unit, Ledge.U.) The Rhineland has jester caps and doughnuts there instead (DrawLedgeCaps).
        void DrawLedgeCarnival()
        {
            if (!cfg.WindowSnow) return;
            bool rhein = c.Carnival == Controller.CarnivalRhein;
            float ox = ScreenBounds.X, oy = ScreenBounds.Y, u = Ledge.U;
            foreach (var l in c.LedgeList)
            {
                bool dragged = l.Moving && l.Rect.Size == l.Settled.Size;
                if (dragged || l.Settled.Width <= 200 * u) continue;
                if (l.Settled.Right <= ox || l.Settled.Left >= ox + W || l.Settled.Top <= oy || l.Settled.Top > oy + H) continue;
                float edge = l.Settled.Top - oy;
                int id = (int)(l.Id % 9973);
                int count = Math.Max(1, (int)(l.Settled.Width / (380 * u)));
                for (int k = 0; k < count; k++)
                {
                    float gx = l.Settled.Left + l.Settled.Width * (k + 0.5f + ((id + k * 31) % 40 - 20) / 100f) / count;
                    if (gx < ox - 30 * u || gx > ox + W + 30 * u || !l.IsVisible(gx)) continue;
                    double t = c.Time + k * 3.7 + id % 23;
                    float x = gx - ox, y = edge - l.HeightAt(gx) * 0.8f;
                    if (rhein) { DrawLedgeCap(l, gx, x, y, t, (id + k) % 2 == 0, u); continue; }
                    // (it looks up for a moment every few seconds, and calls about every nine)
                    int pose = t % 9.1 < 0.5 ? 2 : (t % 3.3 < 0.7 ? 1 : 0);
                    bool flipped = (id + k) % 2 == 1;
                    Mark(x - 27 * u, y - 36 * u, 54 * u, 44 * u);
                    var st = g.Save();
                    g.TranslateTransform(x, y);
                    g.ScaleTransform(flipped ? -u : u, u);
                    DrawToucan(pose == 2, pose == 1 ? -0.3f : pose == 2 ? -0.12f : 0);
                    g.Restore(st);
                }
            }
        }
    }
}
