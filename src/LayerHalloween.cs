using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace JuleHygge
{
    // Halloween (Controller.Halloween), ported from the macOS version (OverlayHalloween.swift), where each Christmas
    // element has its Halloween form. Autumn's leaves fall and pile up as they are (Layer.cs); here are the
    // jack-o'-lanterns that stand in the snowman's place, the witch on her broom that flies in Santa's, the ghosts
    // and children dressed up for trick or treat that walk in the nisser's, the string of pumpkin lanterns and bats
    // that hangs in the lights', the cats and spiders on the window edges, and the two forms of the plow: a witch
    // who sweeps the leaves up, or ghosts who blow them away. The drawing is kept line for line the same as there,
    // with the helpers of LayerAutumn.cs and LayerMuertos.cs. All figures are original.
    partial class Layer
    {
        static readonly Color[] PumpkinColours = { C(255, 122, 26), C(224, 106, 18), C(217, 84, 30) };
        static readonly Color Night = C(23, 21, 29), CandleLight = C(255, 224, 138);

        Bitmap spookGarlandBmp;

        void DisposeHalloween()
        {
            if (spookGarlandBmp != null) { spookGarlandBmp.Dispose(); spookGarlandBmp = null; }
        }

        // The same shape filled and outlined (the two build it anew: a shape is used up when it is drawn).
        void FillStroke(Color fill, Color edge, float width, Func<Shape> make)
        {
            Fill(fill, make());
            Stroke(edge, width, make());
        }

        // ------------------------------------------------------------------ small things the figures share
        // One pumpkin standing on the ground at x = cx, r wide to each side: ribbed, with a stalk, and when carved a
        // face (eyes from face 1, the mouth too from 2) that is dark until a candle is lit inside it.
        void DrawPumpkin(float cx, float r, Color colour, bool stalk, int face, bool lit)
        {
            float ry = r * 0.82f, cy = -ry;
            if (lit) Glow(C(255, 179, 71, 90), cx, cy, r * 1.9f);
            FillEllipse(Shade(colour, 0.72f), cx - r, cy - ry, 2 * r, 2 * ry);
            // the ribs: lighter lobes from the middle out
            FillEllipse(Shade(colour, 0.88f), cx - r * 0.86f, cy - ry * 0.97f, r * 1.72f, ry * 1.94f);
            FillEllipse(colour, cx - r * 0.58f, cy - ry, r * 1.16f, 2 * ry);
            StrokeEllipse(Shade(colour, 0.6f), Math.Max(0.8f, r * 0.035f), cx - r * 0.28f, cy - ry, r * 0.56f, 2 * ry);
            if (stalk)
                Fill(C(72, 120, 48), new Shape().Start(cx - r * 0.1f, cy - ry * 0.92f)
                    .Curve(cx - r * 0.1f, cy - ry * 1.2f, cx + r * 0.05f, cy - ry * 1.3f, cx + r * 0.26f, cy - ry * 1.34f)
                    .To(cx + r * 0.3f, cy - ry * 1.2f)
                    .Curve(cx + r * 0.16f, cy - ry * 1.18f, cx + r * 0.12f, cy - ry * 1.05f, cx + r * 0.12f, cy - ry * 0.92f).Close());
            if (face <= 0) return;
            Color inside = lit ? CandleLight : C(58, 28, 8);
            FillPoly(inside, cx - r * 0.5f, cy - ry * 0.08f, cx - r * 0.3f, cy - ry * 0.48f, cx - r * 0.1f, cy - ry * 0.08f);
            FillPoly(inside, cx + r * 0.1f, cy - ry * 0.08f, cx + r * 0.3f, cy - ry * 0.48f, cx + r * 0.5f, cy - ry * 0.08f);
            FillPoly(inside, cx - r * 0.07f, cy + ry * 0.2f, cx, cy + ry * 0.02f, cx + r * 0.07f, cy + ry * 0.2f);
            if (face > 1)
            {
                // a wide grin with teeth left standing
                Fill(inside, new Shape().Start(cx - r * 0.58f, cy + ry * 0.26f)
                    .Quad(cx, cy + ry * 0.5f, cx + r * 0.58f, cy + ry * 0.26f)
                    .Quad(cx, cy + ry * 1.0f, cx - r * 0.58f, cy + ry * 0.26f).Close());
                FillRect(colour, cx - 0.26f * r, cy + ry * 0.3f, r * 0.14f, ry * 0.16f);
                FillRect(colour, cx + 0.2f * r, cy + ry * 0.3f, r * 0.14f, ry * 0.16f);
                FillRect(colour, cx - r * 0.04f, cy + ry * 0.56f, r * 0.14f, ry * 0.16f);
            }
        }

        // A small bat seen from the front, wings out: flap -1..1 lifts and lowers the wing tips.
        void DrawBat(float x, float y, float size, float flap)
        {
            var st = T.Save();
            T.TranslateTransform(x, y);
            T.ScaleTransform(size, size);
            float lift = flap * 7;
            foreach (float side in new[] { -1f, 1f })
                Fill(Night, new Shape().Start(side * 2, -1)
                    .Curve(side * 8, -8 - lift, side * 15, -7 - lift, side * 20, -1 - lift)
                    // the scalloped trailing edge
                    .Quad(side * 17, -2 - lift * 0.7f, side * 14, 2 - lift * 0.6f)
                    .Quad(side * 11, 0 - lift * 0.4f, side * 8, 4 - lift * 0.3f)
                    .Quad(side * 5, 1, side * 2, 4).Close());
            FillEllipse(Night, -3, -4, 6, 9);
            FillPoly(Night, -2.6f, -3, -2.2f, -7.5f, -0.4f, -4);
            FillPoly(Night, 2.6f, -3, 2.2f, -7.5f, 0.4f, -4);
            FillEllipse(C(255, 210, 90), -1.9f, -2.6f, 1.3f, 1.3f);
            FillEllipse(C(255, 210, 90), 0.6f, -2.6f, 1.3f, 1.3f);
            T.Restore(st);
        }

        // A black cat sitting, looking at us, its tail curled to the right (tail -1..1 swings its tip). Sits on
        // y = 0, about 26 high, centred on x = 0.
        void DrawCat(float tail, bool eyesOpen = true)
        {
            Color black = Night;
            Bezier(black, 3, 8, -3, 20, -2, 20 + tail * 3, -14, 14 + tail * 5, -19);
            // haunches, chest and head
            FillEllipse(black, -9, -13, 20, 13);
            Fill(black, new Shape().Start(-8, -1).Curve(-10, -12, -7, -19, -3, -21).To(4, -21).Curve(8, -15, 9, -8, 8, -1).Close());
            FillEllipse(black, -8, -29, 15, 13);
            FillPoly(black, -7.5f, -24, -7, -33, -2, -28);
            FillPoly(black, 6.5f, -24, 6, -33, 1, -28);
            FillEllipse(black, -8, -3, 6, 3.4f);
            FillEllipse(black, 1, -3, 6, 3.4f);
            if (eyesOpen)
            {
                foreach (float dx in new[] { -4.2f, 1.2f })
                {
                    FillEllipse(C(255, 214, 64), dx, -24.5f, 3.2f, 2.6f);
                    FillRect(black, dx + 1.3f, -24.5f, 0.7f, 2.6f);
                }
            }
            else
            {
                Line(C(255, 214, 64), 0.7f, -4, -23.2f, -1.2f, -23.2f);
                Line(C(255, 214, 64), 0.7f, 1.4f, -23.2f, 4.2f, -23.2f);
            }
        }

        // ------------------------------------------------------------------ græskarlygter
        // Halloween's form of the snowman: three pumpkins put out and carved into jack-o'-lanterns, a step for every
        // hour the app runs (Controller.OfrendaStage), in the same place and frame as the snowman. Origin at the
        // ground, y up is negative.
        void DrawPumpkins(int stage)
        {
            FillEllipse(C(20, 12, 8, 60), -60, -3, 120, 6);
            bool stalks = stage >= 4;
            // the curling vine behind them (stage 4)
            if (stalks)
            {
                Bezier(C(72, 120, 48), 1.6f, -30, -30, -24, -52, -8, -40, -14, -56);
                Bezier(C(72, 120, 48), 1.6f, 30, -26, 40, -44, 22, -44, 30, -54);
                FillEllipse(C(86, 138, 56), -22, -50, 9, 6);
            }
            if (stage >= 1) DrawPumpkin(-38, 20, PumpkinColours[1], stalks, stage >= 8 ? 2 : 0, stage >= 10);
            if (stage >= 2) DrawPumpkin(38, 18, PumpkinColours[2], stalks, stage >= 9 ? 2 : 0, stage >= 10);
            if (stage >= 3) DrawPumpkin(0, 32, PumpkinColours[0], stalks, stage >= 6 ? 2 : stage >= 5 ? 1 : 0, stage >= 7);
            // a witch's hat on the right pumpkin (stage 11)
            if (stage >= 11)
            {
                var st = T.Save();
                T.TranslateTransform(40, -29);
                T.RotateTransform(0.22f * 180 / (float)Math.PI);
                FillEllipse(Night, -15, -3, 30, 7);
                FillPoly(Night, -8, -1, 2, -30, 8, -1);
                FillRect(C(123, 44, 191), -7.4f, -5.5f, 14.8f, 3);
                FillRect(C(255, 210, 63), -2, -6, 4, 4);
                T.Restore(st);
            }
            // a black cat on the left pumpkin (stage 12)
            if (stage >= 12)
            {
                var st = T.Save();
                T.TranslateTransform(-40, -31);
                T.ScaleTransform(0.9f, 0.9f);
                DrawCat(0.3f);
                T.Restore(st);
            }
        }

        // ------------------------------------------------------------------ spøgelser og udklædte børn
        // Halloween's walkers. They are nisser in everything but looks: they walk, stop, wave, cross to the next
        // screen and meet to hand something over (a bucket of sweets). Every other one is a ghost under a sheet,
        // floating a little above the ground; the others are children dressed up for trick or treat, a small witch
        // or a small pumpkin. Drawn like a nisse: feet at (0, 0), y up is negative, facing right.
        void DrawSpook(Nisse n)
        {
            DrawSpook(Math.Max(0, Array.IndexOf(Tunics, n.Tunic)), n.State, n.CarriesGift,
                n.State == 0 ? n.WalkPhase : 0, n.State == 1 ? n.T * 1.5f : 0, n.State == 2 ? n.T * 11f : 0);
        }

        void DrawSpook(int tunicIndex, int state, bool carriesGift, float p, float standPhase, float wavePhase)
        {
            if (tunicIndex % 2 == 0) DrawGhost(tunicIndex, state, carriesGift, p, standPhase, wavePhase);
            else DrawTreater(tunicIndex, state, carriesGift, p, standPhase, wavePhase);
        }

        // The bucket of sweets a walker carries: a small pumpkin pail with a handle.
        void DrawSweetBucket(float x, float y)
        {
            Bezier(C(60, 40, 30), 1, x - 4, y - 6, x - 3, y - 11, x + 3, y - 11, x + 4, y - 6);
            FillEllipse(PumpkinColours[0], x - 5.5f, y - 7, 11, 9);
            FillPoly(C(58, 28, 8), x - 3, y - 3.4f, x - 1.8f, y - 5.2f, x - 0.6f, y - 3.4f);
            FillPoly(C(58, 28, 8), x + 0.6f, y - 3.4f, x + 1.8f, y - 5.2f, x + 3, y - 3.4f);
            FillEllipse(C(233, 30, 99), x - 3.4f, y - 9.2f, 3, 3);
            FillEllipse(C(255, 210, 63), x + 0.2f, y - 9.6f, 3, 3);
        }

        void DrawGhost(int tunicIndex, int state, bool carriesGift, float p, float standPhase, float wavePhase)
        {
            bool walking = state == 0, waving = state == 2;
            // it floats: up and down as it goes, a little higher when it says boo
            float bob = walking ? (float)Math.Sin(p) * 2 : (waving ? -3 - Math.Abs((float)Math.Sin(wavePhase)) * 2 : (float)Math.Sin(standPhase) * 1.2f);
            float hem = walking ? p : standPhase;
            Color sheet = tunicIndex == 2 ? C(236, 228, 250) : C(248, 250, 252), fold = C(196, 204, 226), edge = C(110, 120, 150, 190);
            FillEllipse(C(30, 20, 40, 45), -10, -2, 20, 4);
            var st = T.Save();
            T.TranslateTransform(0, bob - 4);

            float arm = waving ? 0.9f + (float)Math.Sin(wavePhase) * 0.25f : 0.25f;
            // the arms under the sheet: stubs out to the sides, up when it says boo
            foreach (float s in new[] { -1f, 1f })
            {
                float side = s;
                FillStroke(sheet, edge, 1, () => new Shape().Start(side * 8, -30)
                    .Curve(side * 14, -30 - arm * 4, side * 19, -28 - arm * 14, side * 18, -24 - arm * 16)
                    .Curve(side * 15, -20 - arm * 10, side * 12, -20, side * 8, -20).Close());
            }
            FillStroke(sheet, edge, 1, () =>
            {
                var body = new Shape().Start(-11, -4).Curve(-11, -20, -12, -46, 0, -46).Curve(12, -46, 11, -20, 11, -4);
                // the wavy hem, right to left
                const int waves = 4;
                for (int k = 0; k < waves; k++)
                {
                    float x1 = 11 - 22f * (k + 1) / waves, xm = 11 - 22f * (k + 0.5f) / waves;
                    body.Quad(xm, -4 + 5 + (float)Math.Sin(hem + k * 1.6) * 2, x1, -4);
                }
                return body.Close();
            });
            // a fold of shade down one side
            Fill(Color.FromArgb(150, fold), new Shape().Start(-10.2f, -6).Curve(-10.4f, -20, -11, -40, -3, -45).Curve(-8, -36, -7, -18, -7, -6).Close());
            // the face: two dark eyes and a round mouth (wide open at boo)
            Color ink = C(34, 30, 48);
            FillEllipse(ink, -3.2f, -36, 4, 5.4f);
            FillEllipse(ink, 3.4f, -36, 4, 5.4f);
            FillEllipse(ink, 0.6f, -28.5f, 3.4f, waving ? 5.5f : 2.6f);

            if (carriesGift && !waving) DrawSweetBucket(15, -14);
            T.Restore(st);
        }

        void DrawTreater(int tunicIndex, int state, bool carriesGift, float p, float standPhase, float wavePhase)
        {
            bool walking = state == 0, waving = state == 2;
            float legA = walking ? (float)Math.Sin(p) * 0.55f : 0;
            float bob = walking ? -Math.Abs((float)Math.Sin(p)) * 1.5f : (waving ? -Math.Abs((float)Math.Sin(wavePhase)) * 2 : 0);
            bool witch = tunicIndex % 4 == 1;
            Color ink = C(34, 26, 40), skin = C(255, 214, 186);
            FillEllipse(C(30, 20, 40, 50), -10, -2, 20, 4);

            // legs: striped stockings for the witch, green tights for the pumpkin
            foreach (float s in new[] { -1f, 1f })
            {
                float hx = 2 * s, a = -legA * s;
                float fx = hx + (float)Math.Sin(a) * 12, fy = -13 + bob + (float)Math.Cos(a) * 12;
                Line(witch ? C(123, 44, 191) : C(72, 120, 48), 3.4f, hx, -13 + bob, fx, fy, true);
                if (witch) Line(C(255, 152, 0), 3.4f, hx + (float)Math.Sin(a) * 4, -13 + bob + (float)Math.Cos(a) * 4, hx + (float)Math.Sin(a) * 7, -13 + bob + (float)Math.Cos(a) * 7);
                FillEllipse(ink, fx - 3, fy - 2, 8, 4.4f);
            }

            var st = T.Save();
            T.TranslateTransform(0, bob);
            float backArm, frontArm;
            if (waving) { backArm = -0.4f + (float)Math.Sin(wavePhase) * 0.3f; frontArm = 2.6f + (float)Math.Sin(wavePhase) * 0.5f; }
            else if (carriesGift) { backArm = 1.3f; frontArm = 1.3f; }
            else { backArm = -legA * 0.9f; frontArm = legA * 0.9f; }
            Color sleeve = witch ? C(40, 30, 54) : C(72, 120, 48);
            TreaterArm(-1, -30, backArm, sleeve, skin);

            if (witch)
            {
                // a dark dress flaring to the hem, with a purple sash
                Fill(C(40, 30, 54), new Shape().Start(-5, -32).To(5, -32).Curve(7, -24, 10, -16, 11, -10).To(-11, -10).Curve(-10, -16, -7, -24, -5, -32).Close());
                for (int k = 0; k < 5; k++) FillPoly(C(40, 30, 54), -11 + k * 4.4f, -10, -8.8f + k * 4.4f, -6.5f, -6.6f + k * 4.4f, -10);
                Line(C(123, 44, 191), 1.6f, -6.4f, -22, 6.4f, -22);
            }
            else
            {
                // a round pumpkin costume with ribs and a carved face
                FillEllipse(Shade(PumpkinColours[0], 0.8f), -11, -33, 22, 22);
                FillEllipse(PumpkinColours[0], -7, -33, 14, 22);
                StrokeEllipse(Shade(PumpkinColours[0], 0.6f), 0.8f, -3.2f, -33, 6.4f, 22);
                FillPoly(ink, -5.5f, -22, -3.5f, -26, -1.5f, -22);
                FillPoly(ink, 1.5f, -22, 3.5f, -26, 5.5f, -22);
                Bezier(ink, 1.4f, -5, -18, -2, -15, 2, -15, 5, -18);
            }

            if (carriesGift && !waving) DrawSweetBucket(13, -17);

            // the head, looking a little the way it walks
            float sway = (float)Math.Sin(walking ? p * 0.5f : standPhase) * 0.05f;
            var st2 = T.Save();
            T.TranslateTransform(1, -39);
            T.RotateTransform(sway * 180 / (float)Math.PI);
            FillEllipse(skin, -6.5f, -6.5f, 13, 13);
            FillEllipse(C(250, 170, 160, 150), 1.5f, 0.2f, 3.6f, 2.6f);
            FillEllipse(ink, 1.4f, -2.4f, 2, 2.6f);
            FillEllipse(ink, 4.4f, -2.4f, 1.6f, 2.4f);
            Bezier(ink, 0.8f, 1.6f, 2.6f, 3, 4, 4.4f, 4, 5.4f, 2.6f);
            if (witch)
            {
                // hair, and a pointed hat with a bent tip and a buckle
                FillEllipse(C(214, 110, 40), -8, -4, 6, 11);
                FillEllipse(ink, -11, -8.2f, 22, 5);
                Fill(ink, new Shape().Start(-6, -6.5f).Curve(-4, -16, -1, -22, 5, -23).Curve(2, -19, 5, -12, 6, -6.5f).Close());
                FillRect(C(123, 44, 191), -5.6f, -9, 11.4f, 2.2f);
                FillRect(C(255, 210, 63), -1.4f, -9.4f, 3, 3);
            }
            else
            {
                // the pumpkin's cap: a green stalk and two leaves
                FillEllipse(C(72, 120, 48), -6.8f, -8.4f, 13.6f, 5.4f);
                FillRect(C(60, 100, 40), -1, -12.6f, 2.6f, 5);
                FillEllipse(C(86, 138, 56), 1, -11.4f, 6, 3);
            }
            T.Restore(st2);

            TreaterArm(1, -30, frontArm, sleeve, skin);
            if (waving)
            {
                // waving a lollipop
                float sa = (float)Math.Sin(frontArm), ca = (float)Math.Cos(frontArm);
                float hx = 1 + sa * 10, hy = -30 + ca * 10;
                Line(C(250, 250, 250), 1, hx, hy, hx + sa * 6, hy + ca * 6);
                FillEllipse(C(233, 30, 99), hx + sa * 8 - 3, hy + ca * 8 - 3, 6, 6);
                StrokeEllipse(C(255, 255, 255, 200), 0.8f, hx + sa * 8 - 1.5f, hy + ca * 8 - 1.5f, 3, 3);
            }
            T.Restore(st);
        }

        void TreaterArm(float sx, float sy, float a, Color sleeve, Color skin)
        {
            float hx = sx + (float)Math.Sin(a) * 10, hy = sy + (float)Math.Cos(a) * 10;
            Line(sleeve, 3.2f, sx, sy, hx, hy, true);
            FillEllipse(skin, hx - 2.2f, hy - 2.2f, 4.4f, 4.4f);
        }

        // ------------------------------------------------------------------ heks på kost
        // Halloween's flyer in Santa's place: a witch on her broom, flying toward +x, her cape and the broom's twigs
        // streaming behind, a cat riding at the back, and a handful of bats after her. Drawn in Santa's frame
        // (translated to his place and scaled by his size and direction); t is the trip's clock.
        void DrawWitch(float t)
        {
            // the bats: each beats its wings in its own time and wanders around its place behind her
            float[,] places = { { -150, -46, 1.0f }, { -205, -8, 0.8f }, { -120, 30, 0.9f }, { -250, -58, 0.7f }, { -285, 16, 0.85f }, { -190, 52, 0.7f } };
            for (int i = 0; i < places.GetLength(0); i++)
                DrawBat(places[i, 0] + (float)Math.Sin(t * 1.1 + i * 2.3) * 10, places[i, 1] + (float)Math.Sin(t * 1.7 + i * 1.3) * 9,
                    places[i, 2] * 1.25f, (float)Math.Sin(t * (11 + i) + i * 2));
            var st = T.Save();
            T.TranslateTransform(0, (float)Math.Sin(t * 1.8) * 5);
            T.RotateTransform((float)((-0.06 + Math.Sin(t * 1.8 + 1) * 0.03) * 180 / Math.PI));
            Color ink = Night, wood = C(120, 80, 40), skin = C(132, 178, 96);
            float flutter = (float)Math.Sin(t * 9);
            // the broom: the stick, and the twigs bound at the back, shaking in the wind
            for (int k = 0; k < 7; k++)
            {
                float a = (k - 3) * 0.09f;
                Line(k % 2 == 0 ? C(214, 170, 72) : C(176, 132, 52), 2.2f, -62, 2, -108, 2 + a * 46 + flutter * (k % 3 - 1) * 2.2f, true);
            }
            FillRect(C(96, 60, 30), -66, -1.6f, 6, 7.2f);
            Line(wood, 3.6f, -64, 2, 104, -5, true);
            // the cat riding at the back
            var st2 = T.Save();
            T.TranslateTransform(-40, 0);
            T.ScaleTransform(0.8f, 0.8f);
            DrawCat(flutter * 0.6f);
            T.Restore(st2);
            // the cape streaming behind her
            Fill(C(74, 38, 110), new Shape().Start(18, -42)
                .Curve(0, -44, -22, -40 + flutter * 3, -40, -30 + flutter * 5)
                .Quad(-30, -26 + flutter * 4, -30, -20 + flutter * 3)
                .Quad(-20, -18 + flutter * 3, -18, -12 + flutter * 2)
                .Curve(0, -12, 12, -18, 22, -30).Close());
            // her leg forward along the stick: a striped stocking and a pointed shoe
            Line(C(123, 44, 191), 5, 26, -8, 52, -9, true);
            for (int k = 0; k < 3; k++) Line(C(255, 152, 0), 5, 31 + k * 7, -8.2f - k * 0.3f, 34 + k * 7, -8.3f - k * 0.3f);
            FillPoly(ink, 50, -13, 64, -11, 62, -6, 50, -5);
            // the dress, leaning forward over the stick
            Fill(ink, new Shape().Start(14, -44).Curve(26, -46, 36, -36, 38, -22).Curve(36, -8, 22, -2, 10, -4).Curve(8, -18, 10, -34, 14, -44).Close());
            // arms to the stick
            Line(ink, 4, 28, -36, 44, -14, true);
            FillEllipse(skin, 42, -15, 6, 6);
            // head, with a long nose and chin, and hair flying back
            Bezier(C(214, 110, 40), 3, 22, -52, 8, -52, 0, -44 + flutter * 2, -8, -46 + flutter * 3);
            Bezier(C(214, 110, 40), 3, 22, -48, 10, -46, 4, -40 + flutter * 2, -4, -38 + flutter * 3);
            FillEllipse(skin, 20, -60, 17, 17);
            FillPoly(skin, 35, -53, 44, -50, 35, -48);
            FillPoly(skin, 31, -46, 38, -42, 28, -43);
            FillEllipse(ink, 30, -55, 2.4f, 2.8f);
            Bezier(ink, 0.9f, 31, -46.5f, 33, -45.5f, 35, -45.5f, 36, -47);
            // the pointed hat, its tip bent back
            var st3 = T.Save();
            T.TranslateTransform(27, -59);
            T.RotateTransform(-0.2f * 180 / (float)Math.PI);
            FillEllipse(ink, -17, -3.5f, 34, 8);
            Fill(ink, new Shape().Start(-9, -1).Curve(-7, -18, -6, -30, -16 + flutter * 1.5f, -40).Curve(-2, -34, 6, -18, 9, -1).Close());
            FillRect(C(123, 44, 191), -8.6f, -6.4f, 17.4f, 3.4f);
            FillRect(C(255, 210, 63), -2.4f, -7, 4.8f, 4.8f);
            T.Restore(st3);
            T.Restore(st);
        }

        // ------------------------------------------------------------------ heksen fejer, eller spøgelserne puster
        // Halloween has two forms of the snow plow, one or the other each run (Controller.GhostsBlow). This is the
        // first: a small witch walks in front sweeping the leaves up with her broom; they fly back into a cauldron on
        // a cart that her black cat pulls. Facing +x, origin at the ground, the broom where the plow's blade would be.
        void DrawWitchSweeper(float ph)
        {
            float step = plowWheel;
            const float stride = Controller.DonkeyStride;
            Color ink = Night, wood = C(120, 80, 40), woodDark = C(84, 54, 28);
            // the cart: a flat bed on two small wheels, and on it the cauldron heaped with leaves
            float[] heapX = { -90, -80, -70, -60, -50 };
            for (int i = 0; i < heapX.Length; i++)
            {
                FillEllipse(LeafColours[(i * 2) % LeafColours.Length], heapX[i] - 8, -66 + (i % 2) * 4, 17, 12);
                FillEllipse(LeafColours[(i * 2 + 1) % LeafColours.Length], heapX[i] - 2, -60 - (i % 2) * 3, 15, 11);
            }
            FillEllipse(ink, -98, -62, 56, 46);
            FillEllipse(C(52, 48, 62), -92, -58, 18, 30);
            FillEllipse(C(64, 60, 76), -100, -62, 60, 10);
            FillEllipse(ink, -96, -60.5f, 52, 6);
            FillRect(woodDark, -104, -18, 70, 5);
            foreach (float wx in new[] { -92f, -48f })
            {
                FillEllipse(woodDark, wx - 9, -18, 18, 18);
                StrokeEllipse(wood, 1.8f, wx - 6.5f, -15.5f, 13, 13);
                for (int k = 0; k < 4; k++)
                {
                    double a = step * 1.6 + k * Math.PI / 2;
                    Line(wood, 1.4f, wx, -9, wx + (float)Math.Cos(a) * 6.5f, -9 + (float)Math.Sin(a) * 6.5f);
                }
            }
            // the shaft and the cat that pulls: black, tail up, its legs going
            Line(woodDark, 2.4f, -36, -16, 6, -20, true);
            CatLeg(-2, (float)Math.Sin(step * stride + 1.2) * 0.5f); CatLeg(22, (float)Math.Sin(step * stride + 1.2 + Math.PI) * 0.5f);
            Bezier(ink, 3, -6, -22, -16, -26, -18, -40, -10, -46 + (float)Math.Sin(step * stride) * 2);
            FillEllipse(ink, -8, -28, 40, 15);
            CatLeg(2, (float)Math.Sin(step * stride + Math.PI) * 0.5f); CatLeg(26, (float)Math.Sin(step * stride) * 0.5f);
            float nod = (float)Math.Sin(step * stride);
            FillEllipse(ink, 24, -38 + nod, 16, 14);
            FillPoly(ink, 26, -34 + nod, 26.5f, -44 + nod, 31, -37 + nod);
            FillPoly(ink, 38, -34 + nod, 38, -44 + nod, 33.5f, -37 + nod);
            FillEllipse(C(255, 214, 64), 33, -33 + nod, 3, 2.6f);
            Line(C(200, 60, 60), 1.6f, 22, -28, 26, -22);   // the harness
            // the small witch with the broom, walking in front (her legs keep the cat's time)
            var st = T.Save();
            T.TranslateTransform(78, 0);
            T.ScaleTransform(1.3f, 1.3f);
            DrawSpook(1, 0, false, (float)((step * stride) % (4 * Math.PI)), 0, 0);
            T.Restore(st);
            // the broom: the handle from her hands down to the ground in front, the twigs swinging
            float swing = (float)Math.Sin(step * stride * 2) * 5;
            Line(wood, 2.2f, 80, -42, 98 + swing, -4, true);
            for (int k = 0; k < 6; k++) Line(k % 2 == 0 ? C(214, 170, 72) : C(176, 132, 52), 1.6f, 97 + swing, -6, 92 + swing + k * 3.4f, 1, true);
            FillRect(woodDark, 94 + swing, -8, 7, 3);
            // leaves gathered in front of the broom
            float[] gathered = { 102, 109, 116 };
            for (int i = 0; i < gathered.Length; i++)
                if (i * 6 < ph) FillEllipse(LeafColours[i % LeafColours.Length], gathered[i] + swing - 5, -6 - (i % 2) * 2, 10, 6);
        }

        void CatLeg(float hx, float a)
        {
            float s = (float)Math.Sin(a);
            Line(Night, 3.2f, hx, -16, hx + s * 6, -7, true);
            Line(Night, 2.8f, hx + s * 6, -7, hx + s * 8, 0, true);
        }

        // The second: three ghosts float along in a row, leaning forward, and blow; the leaves whirl up in front of
        // them and are carried off. Facing +x, origin at the ground.
        void DrawGhostBlowers(float ph)
        {
            float t = plowWheel;
            float[,] places = { { -64, -8, 1.15f, 0 }, { -8, -20, 1.3f, 2 }, { 46, -4, 1.2f, 0 } };
            for (int i = 0; i < places.GetLength(0); i++)
            {
                float px = places[i, 0], py = places[i, 1], size = places[i, 2];
                var st = T.Save();
                T.TranslateTransform(px, py + (float)Math.Sin(t * 0.9 + i * 2.1) * 3);
                T.RotateTransform((float)((0.30 + Math.Sin(t * 0.7 + i) * 0.04) * 180 / Math.PI));
                T.ScaleTransform(size, size);
                DrawSpook((int)places[i, 3], 0, false, (float)((t * 0.5 + i * 0.37) % (4 * Math.PI)), 0, 0);
                // cheeks puffed and a round mouth, blowing
                FillEllipse(C(34, 30, 48), 2.6f, -33, 5, 5.6f);
                FillEllipse(C(244, 200, 210, 150), -5.4f, -30, 4, 3);
                T.Restore(st);
                // its breath: thin pale streaks out in front, wavering
                float bx = px + 22 * size, by = py - 30 * size;
                for (int k = 0; k < 3; k++)
                {
                    float w = (float)Math.Sin(t * 3 + i * 1.7 + k * 2) * 3;
                    Bezier(C(255, 255, 255, 110 - k * 25), 1.6f - k * 0.3f, bx + 4, by + k * 5 - 3, bx + 18, by + k * 6 - 6 + w,
                        bx + 30, by + k * 7 + 4 - w, bx + 44 + k * 6, by + k * 8 + w * 0.5f);
                }
            }
            // leaves lifted off the pile just ahead of them
            float[] lifted = { 88, 100, 112 };
            for (int i = 0; i < lifted.Length; i++)
                if (i * 6 < ph) FillEllipse(LeafColours[(i + 1) % LeafColours.Length], lifted[i] - 5, -8 - i * 5 + (float)Math.Sin(t * 4 + i) * 3, 10, 6);
        }

        // ------------------------------------------------------------------ lyskæde med græskar og flagermus
        // A small pumpkin lantern hanging at a bulb's place, its top at (bx, by): dark when alpha is 0 (drawn once
        // with the string), and its lit form over it at `alpha` (0-255) as it twinkles.
        void DrawGarlandPumpkin(float bx, float by, bool lit, int alpha)
        {
            Color col = lit ? C(255, 140, 30, alpha) : C(140, 70, 16), face = lit ? Color.FromArgb(alpha, CandleLight) : C(48, 24, 8);
            if (lit) Glow(C(255, 170, 60, 110 * alpha / 255), bx, by + 10 * S, 13 * S);
            else
            {
                Line(C(60, 44, 30), 1.2f * S, bx, by, bx, by + 4 * S);
                FillRect(C(72, 120, 48), bx - 1.2f * S, by + 3 * S, 2.4f * S, 2.4f * S);
            }
            FillEllipse(lit ? Color.FromArgb(alpha, Shade(Color.FromArgb(255, col), 0.8f)) : Shade(col, 0.8f), bx - 6.5f * S, by + 4.6f * S, 13 * S, 10.8f * S);
            FillEllipse(col, bx - 4 * S, by + 4.6f * S, 8 * S, 10.8f * S);
            FillPoly(face, bx - 3.6f * S, by + 9.6f * S, bx - 2.2f * S, by + 7 * S, bx - 0.8f * S, by + 9.6f * S);
            FillPoly(face, bx + 0.8f * S, by + 9.6f * S, bx + 2.2f * S, by + 7 * S, bx + 3.6f * S, by + 9.6f * S);
            FillPoly(face, bx - 3.4f * S, by + 11.2f * S, bx + 3.4f * S, by + 11.2f * S, bx, by + 13.6f * S);
        }

        // The garland itself: the string, bats hanging by their feet, asleep with their wings folded round them, and
        // the unlit pumpkin lanterns where the bulbs are. Nothing in it moves, so it is drawn once and kept
        // (spookGarlandBmp); the lanterns' lit forms are drawn over it each time the strip is made again.
        void MakeSpookGarland(int lh)
        {
            if (spookGarlandBmp != null) spookGarlandBmp.Dispose();
            spookGarlandBmp = new Bitmap(W, lh, PixelFormat.Format32bppPArgb);
            float span = 230 * S, sag = 22 * S, top = 1;
            using (var lg = Graphics.FromImage(spookGarlandBmp))
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
                int n = 0;
                for (float x0 = -span * 0.3f; x0 < W; x0 += span, n++)
                    for (int k = 0; k < 12; k++)
                    {
                        if (k % 3 == 1 || (n + k) % 2 != 0) continue;
                        float u = (k + 0.5f) / 12;
                        float x = x0 + u * span, y = top + sag * (1 - (2 * u - 1) * (2 * u - 1));
                        float size = (0.8f + ((n * 7 + k) % 4) * 0.12f) * S;
                        var st = lg.Save();
                        lg.TranslateTransform(x, y);
                        lg.RotateTransform((float)(Math.Sin((n + k) * 2.3) * 0.12 * 180 / Math.PI));
                        lg.ScaleTransform(size, size);
                        // the folded wings as a pointed cloak, the head and ears below, two small feet on the string
                        Line(Night, 1, -1.4f, 0, -1.4f, 2.4f); Line(Night, 1, 1.4f, 0, 1.4f, 2.4f);
                        Fill(Night, new Shape().Start(0, 1.6f).Curve(-6.5f, 4, -5.5f, 12, -1, 15.5f).To(1, 15.5f).Curve(5.5f, 12, 6.5f, 4, 0, 1.6f).Close());
                        FillEllipse(Night, -2.8f, 13.6f, 5.6f, 5.4f);
                        FillPoly(Night, -2.6f, 17.4f, -2.9f, 21.4f, -0.6f, 18.6f);
                        FillPoly(Night, 2.6f, 17.4f, 2.9f, 21.4f, 0.6f, 18.6f);
                        lg.Restore(st);
                    }
                for (float x0 = -span * 0.3f; x0 < W; x0 += span)
                    for (int b = 0; b < 4; b++)
                    {
                        float u = (b + 0.5f) / 4;
                        DrawGarlandPumpkin(x0 + u * span, top + sag * (1 - (2 * u - 1) * (2 * u - 1)), false, 0);
                    }
                into = null;
            }
        }

        void RenderSpookGarland(Graphics lg)
        {
            int lh = LightsHeight;
            if (spookGarlandBmp == null || spookGarlandBmp.Width != W || spookGarlandBmp.Height != lh) MakeSpookGarland(lh);
            lg.DrawImageUnscaled(spookGarlandBmp, 0, 0);
            float span = 230 * S, sag = 22 * S, top = 1;
            int idx = 0;
            into = lg;
            for (float x0 = -span * 0.3f; x0 < W; x0 += span)
                for (int b = 0; b < 4; b++, idx++)
                {
                    float u = (b + 0.5f) / 4;
                    // the same slow twinkle as the bulbs
                    float br = 0.55f + 0.45f * (float)Math.Sin(c.Time * (1.3 + (idx * 37 % 10) * 0.12) + idx * 1.7);
                    DrawGarlandPumpkin(x0 + u * span, top + sag * (1 - (2 * u - 1) * (2 * u - 1)), true, Math.Max(0, Math.Min(255, (int)(255 * br))));
                }
            into = null;
        }

        // ------------------------------------------------------------------ katte og edderkopper på vindueskanterne
        // A black cat sits on every window's top edge that is wide enough, at a place fixed on the window, swinging its
        // tail and blinking now and then; and here and there a spider hangs under the edge on its thread, letting
        // itself down and climbing up again. Both only where the edge is not hidden by a window in front. (Sizes in
        // the window snow's unit, Ledge.U.)
        void DrawLedgeSpooks()
        {
            if (!cfg.WindowSnow) return;
            float ox = ScreenBounds.X, oy = ScreenBounds.Y, u = Ledge.U;
            foreach (var l in c.LedgeList)
            {
                bool dragged = l.Moving && l.Rect.Size == l.Settled.Size;
                if (dragged || l.Settled.Width <= 260 * u) continue;
                if (l.Settled.Right <= ox || l.Settled.Left >= ox + W || l.Settled.Top <= oy || l.Settled.Top > oy + H) continue;
                float edge = l.Settled.Top - oy;
                int id = (int)(l.Id % 9973);
                // the cat: somewhere along the middle three fifths
                float catX = l.Settled.Left + l.Settled.Width * (0.2f + (id * 37 % 60) / 100f);
                if (catX >= ox - 30 * u && catX <= ox + W + 30 * u && l.IsVisible(catX))
                {
                    float foot = edge - l.HeightAt(catX) * 0.55f, x = catX - ox;
                    double t = c.Time + id % 17;
                    // (it blinks for a moment every five seconds or so, and its tail goes over about once a second)
                    bool blink = t % 5.3 < 0.18;
                    float tail = blink ? 0.2f : ((int)(t * 1.1) % 2 == 0 ? -0.6f : 0.8f);
                    Mark(x - 22 * u, foot - 36 * u, 50 * u, 38 * u);
                    var st = g.Save();
                    g.TranslateTransform(x, foot);
                    g.ScaleTransform(u, u);
                    DrawCat(tail, !blink);
                    g.Restore(st);
                }
                // the spiders: one about every 420 points, hanging under the edge
                int count = (int)(l.Settled.Width / (420 * u));
                for (int k = 0; k < count; k++)
                {
                    float gx = l.Settled.Left + l.Settled.Width * (k + 0.5f + ((id + k * 29) % 30 - 15) / 100f) / count;
                    if (gx < ox - 20 * u || gx > ox + W + 20 * u || !l.IsVisible(gx)) continue;
                    double t = c.Time * 0.5 + k * 2.1 + id % 13;
                    float drop = 26 + (k % 3) * 14 + (float)Math.Sin(t) * 16, x = gx - ox;
                    Mark(x - 12 * u, edge - 2, 24 * u, (drop + 16) * u);
                    var st = g.Save();
                    g.TranslateTransform(x, edge);
                    g.ScaleTransform(u, u);
                    Line(C(235, 235, 245, 170), 0.8f, 0, 0, 0, drop);
                    g.TranslateTransform(0, drop + 4);
                    foreach (float side in new[] { -1f, 1f })
                        for (int j = 0; j < 4; j++)
                        {
                            float a = j * 0.42f - 0.6f;
                            Bezier(Night, 0.9f, side * 2, -1 + j * 0.8f, side * 6, -4 + j * 1.6f + a, side * 8, -2 + j * 2, side * 9, 1 + j * 1.8f);
                        }
                    FillEllipse(Night, -3.4f, -2.4f, 6.8f, 7.4f);
                    FillEllipse(Night, -2.2f, -5, 4.4f, 4);
                    FillEllipse(C(220, 40, 40), -1.4f, -4, 1, 1); FillEllipse(C(220, 40, 40), 0.4f, -4, 1, 1);
                    g.Restore(st);
                }
            }
        }
    }
}
