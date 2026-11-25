using System;
using System.Drawing;
using System.Drawing.Drawing2D;

namespace JuleHygge
{
    // The Rhineland's street carnival (Controller.CarnivalRhein), ported from the macOS version
    // (OverlayKarnevalRhein.swift): the German form of the Karneval theme, as it is held in Cologne, Düsseldorf and
    // Mainz. The same slots as Rio's (LayerKarneval.cs, which calls in here), in other clothes: confetti and wrapped
    // sweets (Kamelle) fall, a parade wagon with a great jester's head is built in the snowman's place, a tractor
    // pulls a wagon with a prince and a brass band along the ground and sweets are thrown from it, and the walkers
    // are the people of a Rose Monday parade, marching in time: a dancing guard girl and a guardsman in the red and
    // white of the old town guards, a patchwork clown, the prince, a tuba player, a drummer, a jester and a child
    // dressed as a bee. A string of pennants and jester caps hangs along the top, and jester caps and doughnuts lie
    // on the window edges.
    // Nothing here shows or suggests drinking, the guardsman carries flowers where the real ones carry a wooden
    // rifle with a flower in it, and the wagon shows no caricature of anyone: REL's rulings and the app's own.
    partial class Layer
    {
        static readonly Color RRed = C(214, 32, 48), RWhite = C(250, 248, 242), RBlue = C(40, 90, 190), RYellow = C(255, 204, 40), RGreen = C(40, 150, 80);

        // A jester's cap (Narrenkappe) with its points to both sides and a bell on each; its brow at (0, 0), w wide.
        // ring swings the bells.
        void DrawJesterCap(float w, float ring = 0)
        {
            float k = w / 20;
            float[,] parts = { { -13, -9 }, { 0, -15 }, { 13, -9 } };
            Color[] colours = { RRed, RYellow, RBlue };
            for (int i = 0; i < 3; i++)
            {
                float tx = parts[i, 0], ty = parts[i, 1];
                Fill(colours[i], new Shape().Start(-9 * k + (tx > 0 ? 9 * k : 0) + (tx == 0 ? 4 * k : 0), 0)
                    .Curve((tx - 4) * k, -4 * k, (tx - 2) * k, (ty + 2) * k, (tx + ring) * k, ty * k)
                    .Curve((tx + 3) * k, (ty + 4) * k, (tx + 5) * k, -3 * k, (tx > 0 ? 10 : tx == 0 ? 5 : 1) * k, 0).Close());
                FillEllipse(KGold, (tx + ring) * k - 1.8f * k, ty * k - 1.8f * k, 3.6f * k, 3.6f * k);
            }
            FillRect(RWhite, -10 * k, -1.6f * k, 20 * k, 3.2f * k);
        }

        // ------------------------------------------------------------------ pragtvogn
        // The float in the snowman's place, the Rhineland's form (Prunkwagen): the same twelve steps as Rio's
        // (DrawFloat), in red and white with gold, and in the sun's place a great jester's head.
        void DrawPrunkwagen(int stage)
        {
            Color wood = C(120, 84, 52), dark = C(46, 44, 60);
            Color red = RRed, white = RWhite, gold = KGold;
            FillEllipse(C(20, 16, 30, 55), -58, -3, 116, 6);
            FillRect(wood, -54, -14, 108, 5);
            foreach (float wx in new[] { -38f, 0f, 38f })
            {
                FillEllipse(dark, wx - 7, -14, 14, 14);
                FillEllipse(C(150, 154, 166), wx - 2.5f, -9.5f, 5, 5);
            }
            // 2: the lower deck, in red and white lozenges
            if (stage >= 2)
            {
                FillRect(white, -56, -30, 112, 17);
                for (int k = 0; k < 14; k++) FillPoly(red, -56 + k * 8 + 4, -30, -56 + k * 8 + 8, -21.5f, -56 + k * 8 + 4, -13, -56 + k * 8, -21.5f);
            }
            // 3: a skirt with a fringe
            if (stage >= 3)
            {
                FillRect(red, -57, -14, 114, 10);
                for (int k = 0; k < 19; k++) FillPoly(k % 2 == 0 ? white : red, -57 + k * 6, -4, -51 + k * 6, -4, -54 + k * 6, 1.5f);
            }
            // 4: the upper deck and steps
            if (stage >= 4)
            {
                FillRect(red, -36, -48, 72, 18);
                FillRect(Shade(red, 0.8f), -36, -33, 72, 3);
                for (int k = 0; k < 3; k++) FillRect(white, -52 + k * 5, -34 - k * 4.6f, 6, 4.6f * (k + 1));
            }
            // 5: gold trim
            if (stage >= 5)
            {
                FillRect(gold, -56, -31.5f, 112, 2.4f);
                FillRect(gold, -36, -49.5f, 72, 2.4f);
                for (int k = 0; k < 6; k++) T.FillPolygon(Br(gold), StarPoints(-30 + k * 12, -40, 3.4f, 1.5f, 0));
            }
            // 6: two columns
            if (stage >= 6)
                foreach (float cx in new[] { -30f, 30f })
                {
                    FillRect(white, cx - 3.5f, -86, 7, 37);
                    for (int k = 0; k < 5; k++) FillPoly(red, cx - 3.5f, -84 + k * 7, cx + 3.5f, -87 + k * 7, cx + 3.5f, -84 + k * 7, cx - 3.5f, -81 + k * 7);
                    FillRect(gold, cx - 5.5f, -89, 11, 3.4f);
                    FillRect(gold, cx - 5.5f, -52, 11, 3);
                }
            // 7: a great jester's head between them, 8: its cap with bells, 9: its face
            if (stage >= 7)
            {
                FillEllipse(C(236, 190, 150), -19, -100, 38, 40);
                FillPoly(white, -16, -64, -8, -58, 0, -64, 8, -58, 16, -64, 12, -70, -12, -70);
            }
            if (stage >= 8)
            {
                var st = T.Save();
                T.TranslateTransform(0, -94);
                DrawJesterCap(40);
                T.Restore(st);
            }
            if (stage >= 9)
            {
                FillEllipse(KInk, -9, -88, 4.4f, 5.4f); FillEllipse(KInk, 4.6f, -88, 4.4f, 5.4f);
                FillEllipse(red, -3.4f, -82, 6.8f, 6.8f);
                Bezier(KInk, 1.8f, -10, -74, -5, -66, 5, -66, 10, -74);
                FillEllipse(C(250, 150, 140, 150), -15, -80, 6, 4.4f); FillEllipse(C(250, 150, 140, 150), 9, -80, 6, 4.4f);
            }
            // 10: big rosettes at both ends
            if (stage >= 10)
                foreach (float side in new[] { -1f, 1f })
                {
                    for (int k = 0; k < 8; k++)
                    {
                        double a = k * Math.PI / 4;
                        FillEllipse(k % 2 == 0 ? red : white, side * 47 + Cf(a) * 8 - 5, -40 + Sf(a) * 8 - 5, 10, 10);
                    }
                    FillEllipse(gold, side * 47 - 4.5f, -44.5f, 9, 9);
                }
            // 11: coloured bulbs along the decks
            if (stage >= 11)
            {
                Color[] bulbs = { RYellow, RBlue, RGreen, red };
                for (int k = 0; k < 12; k++) FillEllipse(bulbs[k % 4], -55 + k * 9.6f, -35.5f, 4.4f, 4.4f);
                for (int k = 0; k < 8; k++) FillEllipse(bulbs[(k + 2) % 4], -35 + k * 9.4f, -53.5f, 4.2f, 4.2f);
            }
            // 12: streamers and pennants
            if (stage >= 12)
                foreach (float side in new[] { -1f, 1f })
                {
                    Bezier(RYellow, 1.6f, side * 30, -88, side * 44, -84, side * 40, -66, side * 52, -60);
                    Bezier(RBlue, 1.6f, side * 30, -88, side * 38, -76, side * 48, -78, side * 56, -70);
                    Line(wood, 1.2f, side * 30, -89, side * 30, -108);
                    FillPoly(red, side * 30, -108, side * 30 + side * 13, -104, side * 30, -100);
                    FillPoly(white, side * 30, -104, side * 30 + side * 13, -104, side * 30, -100);
                }
        }

        // ------------------------------------------------------------------ karnevalsoptoget
        void KCoat(Color col, float flare = 6)
        {
            Fill(col, new Shape().Start(-5.5f, -33).To(5.5f, -33).Curve(6.5f, -26, 6.5f, -19, flare, -13).To(-flare, -13).Curve(-6.5f, -19, -6.5f, -26, -5.5f, -33).Close());
        }

        // The three-cornered hat of the town guards, with a plume.
        void KTricorn(Color plume)
        {
            FillPoly(KInk, -9, -5.4f, 0, -11, 9.4f, -5.4f, 6, -3.6f, -6, -3.6f);
            Line(KGold, 1, -8, -5.6f, 0, -10.4f); Line(KGold, 1, 0, -10.4f, 8.6f, -5.6f);
            FillEllipse(plume, -5, -15, 5, 8);
        }

        // The band's cap: blue with a peak and a gold badge.
        void KBandCap()
        {
            FillRect(RBlue, -6, -11, 12, 5.4f); FillRect(KInk, -1, -6.2f, 9, 1.6f); FillEllipse(KGold, -1.6f, -10, 3.2f, 3.2f);
        }

        // The Rhineland's walkers: the people of a Rose Monday parade (Jecken), marching in time with the band. Who
        // each one is follows the walker itself (Nisse.Look). "Waving" is each one's own turn: the guard girl kicks
        // high, the prince throws, the musicians lift their instruments, the clown and the jester jump.
        // (Called from DrawReveller, which works out the phases from the beat.)
        void DrawJeck(Nisse n, float p, float standPhase, float wavePhase, int tunic)
        {
            bool walking = n.State == 0, waving = n.State == 2;
            int who = ((n.Look % 8) + 8) % 8;
            float beat = walking ? p : (waving ? wavePhase : standPhase);
            float legA = walking ? Sf(p) * 0.5f : Sf(beat) * 0.1f;
            float bob = -Math.Abs(Sf(beat)) * (waving ? 3 : 1.2f);
            Color skin = KSkins[(n.Look * 3 + tunic) % KSkins.Length];
            Color ink = KInk, red = RRed, white = RWhite, gold = KGold;
            FillEllipse(C(30, 20, 40, 50), -11, -2, 22, 4);

            // legs: white tights and boots for the guards and the prince, patchwork for the clown, stripes for the bee
            Color[] patch = { RYellow, RBlue, RGreen, red };
            float kick = who == 0 && waving ? Math.Abs(Sf(wavePhase)) * 1.5f : 0;
            for (int i = 0; i < 2; i++)
            {
                float hx = i == 0 ? -2 : 2, a = i == 0 ? legA : -legA - kick;
                float fx = hx + Sf(a) * 13, fy = -14 + bob + Cf(a) * 13;
                Color col = who <= 1 || who == 3 ? white : who == 2 ? patch[(i * 2 + tunic) % 4] : who == 7 ? ink : who == 6 ? (i == 0 ? red : RYellow) : C(40, 50, 90);
                Line(col, who == 0 ? 3.2f : 4, hx, -14 + bob, fx, fy, true);
                FillEllipse(who == 2 ? red : ink, fx - 3, fy - 2, who == 2 ? 10 : 8, 4.2f);
            }
            var st = T.Save();
            T.TranslateTransform(0, bob);

            float swing = walking ? Sf(p) * 0.8f : Sf(beat) * 0.3f;
            Action hat = () => { };
            PointF h;
            switch (who)
            {
                case 0:   // the dancing guard girl (Tanzmariechen): a red and white uniform with a short skirt, and a high kick
                    KArm(-1, -31, waving ? -2.6f : -swing, red, skin);
                    KCoat(red, 5);
                    for (int k = 0; k < 3; k++) FillRect(gold, -3.4f, -31 + k * 4.4f, 6.8f, 1.2f);
                    FillPoly(white, -5, -17, 5, -17, 10, -10, -10, -10);
                    FillRect(red, -10, -11.4f, 20, 1.6f);
                    KArm(1, -31, waving ? 2.6f : swing, red, skin);
                    hat = () => { KTricorn(white); FillEllipse(C(214, 170, 90), -8.6f, -3, 5, 9); FillEllipse(C(214, 170, 90), 4.6f, -3, 5, 9); };
                    break;
                case 1:   // a guardsman (in the red and white of the old town guards), with a bunch of flowers to give away
                    KArm(-1, -31, -swing, red, skin);
                    KCoat(red);
                    FillPoly(white, -5.5f, -33, 5.5f, -33, 0, -22);
                    FillRect(white, -6.4f, -16.5f, 12.8f, 2.4f);
                    for (int k = 0; k < 3; k++) FillEllipse(gold, 2.4f, -28 + k * 4, 1.8f, 1.8f);
                    h = KArm(1, -31, waving ? 2.5f + Sf(wavePhase) * 0.3f : 1.5f, red, skin);
                    Line(RGreen, 1.4f, h.X, h.Y, h.X + 1, h.Y - 7);
                    FillEllipse(RYellow, h.X - 2.5f - 2.2f, h.Y - 9 - 2.2f, 4.4f, 4.4f);
                    FillEllipse(C(255, 120, 170), h.X + 2.5f - 2.2f, h.Y - 9.5f - 2.2f, 4.4f, 4.4f);
                    FillEllipse(white, h.X - 2.2f, h.Y - 12 - 2.2f, 4.4f, 4.4f);
                    hat = () => KTricorn(red);
                    break;
                case 2:   // a patchwork clown (Lappenclown): a suit of coloured rags, a ruff and a small hat
                    KArm(-1, -31, waving ? -2.5f : -swing, patch[tunic % 4], skin);
                    {
                        var cs = T.Save();
                        var suit = new Shape().Start(-6, -33).To(6, -33).Curve(8.5f, -25, 8.5f, -18, 7, -12).To(-7, -12).Curve(-8.5f, -18, -8.5f, -25, -6, -33).Close();
                        T.SetClip(suit.Path, CombineMode.Intersect);
                        suit.Path.Dispose();
                        for (int row = 0; row < 6; row++)
                            for (int col = 0; col < 5; col++)
                                FillRect(patch[(row * 3 + col + tunic) % 4], -9 + col * 3.8f, -34 + row * 3.8f, 3.8f, 3.8f);
                        T.Restore(cs);
                    }
                    for (int k = 0; k < 5; k++) FillEllipse(white, -7 + k * 3, -35.4f, 4.4f, 4);
                    KArm(1, -31, waving ? 2.5f : swing, patch[(tunic + 2) % 4], skin);
                    hat = () =>
                    {
                        FillEllipse(C(232, 120, 40), -9, -5, 5, 7); FillEllipse(C(232, 120, 40), 5, -5, 5, 7);
                        FillRect(RGreen, -3.4f, -11.4f, 6.8f, 5); FillRect(RGreen, -5.6f, -7.4f, 11.2f, 1.6f);
                        FillEllipse(RRed, 4.2f, -0.6f, 3.8f, 3.8f);
                    };
                    break;
                case 3:   // the prince: a gold tunic and a cape, pheasant feathers in his cap; he throws when he "waves"
                    Fill(red, new Shape().Start(-5, -33).Curve(-11, -26, -12, -18, -10, -11).To(-3, -12).To(-2, -32).Close());
                    KArm(-1, -31, -swing * 0.6f, gold, skin);
                    KCoat(gold);
                    FillRect(white, -6.4f, -17, 12.8f, 2.4f);
                    FillPoly(white, -4, -33, 4, -33, 0, -29);
                    h = KArm(1, -31, waving ? 2.2f + Sf(wavePhase) * 0.9f : 1.3f, gold, skin);
                    if (waving) for (int k = 0; k < 3; k++) FillEllipse(patch[k], h.X + 3 + k * 3.4f, h.Y - 5 - k * 2.6f, 2.6f, 2.2f);
                    hat = () =>
                    {
                        FillEllipse(red, -7, -9.4f, 14, 5.6f);
                        for (int k = 0; k < 3; k++) Bezier(C(170, 120, 60), 1.4f, -3 + k * 2, -8, -6 + k * 2, -16, -10 + k * 3, -19, -13 + k * 4, -18);
                    };
                    break;
                case 4:   // the tuba player: a blue band uniform, the horn round the body and its bell over the shoulder
                    KArm(-1, -31, 1.4f, RBlue, skin);
                    KCoat(RBlue);
                    for (int k = 0; k < 3; k++) FillRect(gold, -3.4f, -31 + k * 4.4f, 6.8f, 1.1f);
                    StrokeEllipse(C(214, 170, 60), 3, -2, -30, 14, 16);
                    float lift = waving ? Math.Abs(Sf(wavePhase)) * 3 : Math.Abs(Sf(beat)) * 1;
                    FillEllipse(C(214, 170, 60), -13, -47 - lift, 14, 12); FillEllipse(C(150, 110, 30), -10.5f, -45 - lift, 9, 7.6f);
                    KArm(1, -31, 1.6f, RBlue, skin);
                    hat = KBandCap;
                    break;
                case 5:   // the drummer: the same uniform, a side drum on a sling and two sticks
                    KArm(-1, -31, 1.3f + Math.Abs(Sf(beat + 1.5)) * 0.6f, RBlue, skin);
                    KCoat(RBlue);
                    Line(white, 1.2f, -4, -33, 6, -22);
                    FillRect(white, 3, -24, 12, 10); FillRect(red, 3, -24, 12, 2); FillRect(red, 3, -16, 12, 2);
                    for (int k = 0; k < 3; k++) Line(red, 0.8f, 5 + k * 4, -22, 7 + k * 4, -16);
                    h = KArm(1, -31, 1.4f + Math.Abs(Sf(beat)) * 0.7f, RBlue, skin);
                    Line(C(150, 110, 60), 1.2f, h.X, h.Y, h.X + 5, h.Y + 3);
                    hat = KBandCap;
                    break;
                case 6:   // the jester: half red and half yellow, with the cap and its bells, and a jump
                    KArm(-1, -31, waving ? -2.5f : -swing, red, skin);
                    {
                        var cs = T.Save();
                        var suit = new Shape().Start(-5.5f, -33).To(5.5f, -33).Curve(6.5f, -26, 6.5f, -19, 6, -13).To(-6, -13).Curve(-6.5f, -19, -6.5f, -26, -5.5f, -33).Close();
                        T.SetClip(suit.Path, CombineMode.Intersect);
                        suit.Path.Dispose();
                        FillRect(red, -8, -34, 8, 22); FillRect(RYellow, 0, -34, 8, 22);
                        T.Restore(cs);
                    }
                    for (int k = 0; k < 4; k++) FillPoly(k % 2 == 0 ? RYellow : red, -6 + k * 3, -13, -3 + k * 3, -13, -4.5f + k * 3, -9.6f);
                    KArm(1, -31, waving ? 2.5f : swing, RYellow, skin);
                    float ring = Sf(beat * 2) * 1.2f;
                    hat = () => { T.TranslateTransform(0, -5); DrawJesterCap(15, ring); };
                    break;
                default:  // a child dressed as a bee: yellow and black stripes, small wings and feelers
                    FillEllipse(C(255, 255, 255, 170), -13, -34, 10, 13); FillEllipse(C(255, 255, 255, 130), -11, -27, 8, 10);
                    KArm(-1, -31, waving ? -2.5f : -swing, ink, skin);
                    FillEllipse(RYellow, -7.5f, -34, 15, 22);
                    {
                        var cs = T.Save();
                        using (var body = new GraphicsPath())
                        {
                            body.AddEllipse(-7.5f, -34, 15, 22);
                            T.SetClip(body, CombineMode.Intersect);
                        }
                        for (int k = 0; k < 3; k++) FillRect(ink, -8, -29 + k * 6.4f, 16, 3);
                        T.Restore(cs);
                    }
                    KArm(1, -31, waving ? 2.5f : swing, ink, skin);
                    hat = () =>
                    {
                        FillEllipse(ink, -7, -8.6f, 14, 6);
                        foreach (float side in new[] { -1f, 1f }) { Line(ink, 0.9f, side * 3, -8, side * 5, -14); FillEllipse(RYellow, side * 5 - 1.5f, -16, 3, 3); }
                    };
                    break;
            }

            // a bag of sweets in the hand of those who carry something: it is what changes hands at a meeting
            if (n.CarriesGift && !waving && who != 1 && who != 4 && who != 5)
            {
                Color col = n.Gift;
                FillPoly(col, 8, -22, 15, -22, 16.5f, -14, 6.5f, -14);
                FillPoly(Shade(col, 1.25f), 9.4f, -22, 11.5f, -25.5f, 13.6f, -22);
                FillEllipse(C(255, 255, 255, 140), 9, -20, 2.6f, 2.6f);
            }

            // the head, nodding with the beat
            var hs = T.Save();
            T.TranslateTransform(1, -40);
            Turn(Sf(beat) * 0.06f);
            FillEllipse(skin, -6.5f, -6.5f, 13, 13);
            FillEllipse(C(250, 150, 140, 130), 1.6f, 0.4f, 3.6f, 2.6f);
            FillEllipse(ink, 1.6f, -2.2f, 1.9f, 2.5f);
            FillEllipse(ink, 4.5f, -2.2f, 1.5f, 2.3f);
            Bezier(ink, 0.8f, 1.2f, 2.2f, 2.8f, 4.6f, 4.8f, 4.6f, 5.8f, 2.2f);
            hat();
            T.Restore(hs);
            T.Restore(st);
        }

        // ------------------------------------------------------------------ festvogn
        // The Rhineland's wagon in Santa's place: a tractor pulling a decorated wagon, the prince on it throwing
        // sweets and a small brass band playing. The sweets themselves are thrown by the Controller as sparks
        // (UpdateSanta). Facing +x, origin at the ground under its middle; t is the trip's clock.
        void DrawFestwagen(float t)
        {
            double beat = c.BeatCount * Math.PI;
            Color dark = C(46, 44, 60), red = RRed, white = RWhite, gold = KGold, brass = C(214, 170, 60);
            float roll = t * 5;
            // the tractor: green, a big wheel behind and a small one in front, an exhaust pipe that shakes
            FillRect(dark, 86, -56 + Sf(t * 20) * 0.6f, 3, 16);
            Fill(RGreen, new Shape().Start(54, -18).To(54, -40).To(98, -40).Curve(104, -40, 106, -32, 106, -24).To(106, -18).Close());
            FillRect(Shade(RGreen, 0.8f), 54, -22, 52, 4);
            FillRect(C(178, 214, 236), 56, -62, 20, 22); FillRect(RGreen, 54, -66, 24, 4); FillRect(RGreen, 54, -62, 2, 24); FillRect(RGreen, 76, -62, 2, 24);
            FillEllipse(C(236, 190, 150), 61, -57, 8, 9); FillRect(C(60, 80, 120), 60, -58, 10, 3);
            float[,] wheels = { { 64, 17 }, { 98, 10 } };
            for (int i = 0; i < 2; i++)
            {
                float wx = wheels[i, 0], r = wheels[i, 1];
                FillEllipse(dark, wx - r, -2 * r, 2 * r, 2 * r);
                FillEllipse(RYellow, wx - r * 0.5f, -r * 1.5f, r, r);
                for (int k = 0; k < 4; k++) { double a = roll * (17 / r) + k * Math.PI / 2; Line(dark, 1.4f, wx, -r, wx + Cf(a) * r * 0.5f, -r + Sf(a) * r * 0.5f); }
            }
            Line(dark, 2.4f, 40, -16, 54, -18, true);
            // the wagon: a deck with a railing in red and white lozenges, a fringe, and wheels
            foreach (float wx in new[] { -84f, -6f }) { FillEllipse(dark, wx - 10, -20, 20, 20); FillEllipse(C(160, 164, 176), wx - 4, -14, 8, 8); }
            FillRect(white, -106, -38, 146, 22);
            for (int k = 0; k < 18; k++) FillPoly(red, -106 + k * 8.1f + 4, -38, -106 + k * 8.1f + 8.1f, -27, -106 + k * 8.1f + 4, -16, -106 + k * 8.1f, -27);
            FillRect(gold, -106, -40, 146, 3);
            for (int k = 0; k < 24; k++) FillPoly(k % 2 == 0 ? red : white, -106 + k * 6.1f, -16, -99.9f + k * 6.1f, -16, -103 + k * 6.1f, -11);
            // at the back a great jester's cap on a post, its bells swinging with the beat
            FillRect(C(150, 110, 60), -96, -78, 4, 40);
            var st = T.Save();
            T.TranslateTransform(-94, -78);
            DrawJesterCap(34, Sf(beat) * 1.4f);
            T.Restore(st);
            // on the deck: three of the band, and the prince at the front with his arm up
            float[] band = { -66, -44, -22 };
            for (int i = 0; i < 3; i++)
            {
                float x = band[i], b = Sf(beat + i * 0.5 * Math.PI);
                st = T.Save();
                T.TranslateTransform(0, -40 - Math.Abs(b) * 1.6f);
                DrawSmallPerson(x, 34, RBlue, KSkins[(i * 2) % KSkins.Length], dark, b * 0.06f, 1.5f + Math.Abs(b) * 0.4f);
                switch (i)
                {
                    case 0: StrokeEllipse(brass, 2.4f, x - 3, -24, 12, 13); FillEllipse(brass, x - 9, -40, 12, 10); break;   // a tuba
                    case 1: Line(brass, 2.2f, x + 3, -24, x + 15, -26); FillPoly(brass, x + 14, -29.5f, x + 19, -31, x + 19, -21, x + 14, -22.5f); break;   // a trumpet
                    default: FillRect(white, x + 4, -20, 10, 9); FillRect(red, x + 4, -20, 10, 1.8f); break;   // a drum
                }
                FillRect(RBlue, x - 5, -37.5f, 11, 4);
                T.Restore(st);
            }
            float wave = Sf(beat * 0.5);
            st = T.Save();
            T.TranslateTransform(0, -40);
            DrawSmallPerson(12, 38, gold, KSkins[0], white, wave * 0.08f, 2.4f + wave * 0.5f);
            FillEllipse(red, 6, -41, 13, 5);
            Bezier(C(170, 120, 60), 1.2f, 10, -40, 7, -48, 3, -51, 0, -50);
            T.Restore(st);
            // bunting from the cap's post to the front
            Color[] flags = { red, white, RYellow };
            for (int k = 0; k < 9; k++)
            {
                float u = (k + 0.5f) / 9;
                float x = -92 + u * 126, y = -76 + 22 * u + 12 * u * (1 - u) * 4 * 0.3f;
                FillPoly(flags[k % 3], x - 4, y, x + 4, y + 1, x, y + 9);
            }
            Bezier(dark, 0.8f, -92, -76, -50, -62, -8, -56, 34, -54);
        }

        // ------------------------------------------------------------------ vimpler og narrehuer
        // The Rhineland's garland along the string: pennants in red, white and yellow, and a small jester's cap
        // hanging between every two bulbs. (Drawn into the kept picture by RenderCarnivalGarland; the bulbs are the
        // Christmas lights' own.)
        void DrawRhenishGarland(float span, float sag, float top)
        {
            Color[] cols = { RRed, RWhite, RYellow };
            int n = 0;
            for (float x0 = -span * 0.3f; x0 < W; x0 += span, n++)
            {
                float start = x0;
                Func<float, PointF> at = u => new PointF(start + u * span, top + sag * (1 - (2 * u - 1) * (2 * u - 1)));
                for (int k = 0; k < 16; k++)
                {
                    if (k % 4 == 0) continue;
                    float u = (k + 0.5f) / 16;
                    PointF a = at(u - 0.022f), b = at(u + 0.022f);
                    Color col = cols[(k + n) % 3];
                    float mx = (a.X + b.X) / 2, my = (a.Y + b.Y) / 2;
                    FillPoly(col, a.X, a.Y, b.X, b.Y, mx, my + 13 * S);
                    FillPoly(Shade(col, 0.82f), mx, my, b.X, b.Y, mx, my + 13 * S);
                }
                for (int b = 0; b < 4; b++)
                {
                    PointF p = at(b / 4f);
                    Line(C(60, 50, 60), 0.9f * S, p.X, p.Y, p.X, p.Y + 7 * S);
                    var st = T.Save();
                    T.TranslateTransform(p.X, p.Y + 17 * S);
                    Turn(Sf((n * 4 + b) * 1.9) * 0.14f);
                    DrawJesterCap(13 * S);
                    T.Restore(st);
                }
            }
        }

        // ------------------------------------------------------------------ narrehuer og berlinere på vindueskanterne
        // On a window edge in the Rhineland's carnival (called from DrawLedgeCarnival for each place): a jester's
        // cap lying there, its bells ringing for half a second about every seven in time with the band, and beside
        // every other one a doughnut (the carnival's own cake, with sugar on top) on a paper napkin.
        void DrawLedgeCap(Ledge l, float gx, float x, float y, double t, bool doughnut, float u)
        {
            bool rings = t % 7.3 < 0.6;
            float ring = rings ? ((int)(c.BeatCount * 2) % 2 == 0 ? 1.6f : -1.6f) : 0;
            Mark(x - 23 * u, y - 28 * u, 46 * u, 32 * u);
            var st = g.Save();
            g.TranslateTransform(x, y);
            g.ScaleTransform(u, u);
            DrawJesterCap(26, ring);
            g.Restore(st);
            if (!doughnut || !l.IsVisible(gx + 40 * u)) return;
            Mark(x + 24 * u, y - 19 * u, 32 * u, 22 * u);
            st = g.Save();
            g.TranslateTransform(x + 25 * u, y - 18 * u);
            g.ScaleTransform(u, u);
            FillPoly(C(250, 248, 242), 1, 19, 15, 14, 29, 19, 22, 20, 8, 20);
            FillEllipse(C(206, 140, 70), 5, 6, 20, 13);
            FillEllipse(C(232, 180, 110), 6, 6, 18, 8);
            FillEllipse(C(255, 255, 255, 220), 8, 5.6f, 14, 4.6f);
            FillEllipse(C(214, 32, 48), 21.6f, 11, 3.4f, 2.6f);
            g.Restore(st);
        }
    }
}
