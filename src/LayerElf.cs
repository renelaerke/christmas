using System;
using System.Drawing;

namespace JuleHygge
{
    // The Christmas elf, for the parts of the world where a nisse means nothing (see Folk). It has the nisse's
    // skeleton and poses, so walking, waving, meeting and gifts are the same; only the looks differ: a green or
    // red tunic with a jagged collar and hem, striped stockings, shoes with a curled toe, a pointed ear, and a
    // pointed cap with a bell where the nisse has its pompom. No beard. An original figure like the nisse: no
    // known character. Kept line for line the same as the macOS version (drawElf in Overlay.swift).
    partial class Layer
    {
        // The tunic and cap, and the colour of collar, cap band and mittens that goes with it.
        static readonly Color[] ElfTunics = { C(46, 139, 74), C(196, 42, 52), C(30, 110, 92), C(112, 158, 58) };
        static readonly Color[] ElfTrims = { C(205, 40, 50), C(46, 139, 74), C(235, 195, 70), C(205, 40, 50) };

        // Called from DrawNisse with the transform set: feet at (0, 0), y up is negative, facing right.
        void DrawElf(Nisse n)
        {
            bool walking = n.State == 0;
            float p = n.WalkPhase;
            float legA = walking ? (float)Math.Sin(p) * 0.55f : 0f;
            float bob = walking ? -Math.Abs((float)Math.Sin(p)) * 1.5f : 0f;
            // which clothes follows the nisse's own, so a walker keeps its colours
            int ti = Math.Max(0, Array.IndexOf(Tunics, n.Tunic)) % ElfTunics.Length;
            Color tunic = ElfTunics[ti], trim = ElfTrims[ti];
            Color stripe = ti == 1 ? ElfTunics[0] : C(205, 40, 50);   // the red tunic gets green stripes

            FillEllipse(C(60, 80, 110, 50), -11, -2, 22, 4);

            ElfLeg(stripe, -2, -15 + bob, legA);
            ElfLeg(stripe, 2, -15 + bob, -legA);

            T.TranslateTransform(0, bob);
            float backArm, frontArm;
            if (n.State == 2) { backArm = -legA * 0.8f; frontArm = 2.5f + (float)Math.Sin(n.T * 11) * 0.45f; }
            else if (n.CarriesGift) { backArm = 1.3f; frontArm = 1.3f; }
            else { backArm = -legA * 0.9f; frontArm = legA * 0.9f; }

            ElfArm(tunic, trim, -1, -29, backArm);
            FillEllipse(tunic, -9, -34, 18, 20);
            FillPoly(tunic, -8.7f, -19, -9.5f, -12.5f, -6, -15.5f, -3, -12, 0, -15.5f, 3, -12, 6, -15.5f, 9.5f, -12.5f, 8.7f, -19);
            FillRect(C(35, 30, 30), -8.8f, -21, 17.6f, 3);
            FillRect(Gold, 1.5f, -21.5f, 3.5f, 4);
            FillPoly(trim, -7, -34, -5.6f, -28.5f, -3, -31.3f, -0.5f, -27.8f, 2, -31.3f, 4.6f, -28.5f, 7, -34);

            if (n.CarriesGift && n.State != 2)
            {
                FillRect(n.Gift, 6, -31, 11, 10);
                Line(Gold, 1.6f, 11.5f, -31, 11.5f, -21);
                Line(Gold, 1.6f, 6, -26, 17, -26);
                StrokeEllipse(Gold, 1.6f, 9, -34, 3, 3);
                StrokeEllipse(Gold, 1.6f, 12, -34, 3, 3);
            }

            FillPoly(Skin, -4.5f, -36, -11.5f, -42, -3.5f, -41);
            Line(C(225, 170, 140), 0.8f, -5.2f, -38, -9, -41);
            FillEllipse(Skin, -6, -44, 13, 12);
            FillEllipse(C(245, 150, 140, 150), 0.8f, -36.4f, 3.2f, 2.4f);
            FillEllipse(C(45, 32, 30), 2.7f, -38.4f, 1.7f, 2);
            Bezier(C(150, 70, 60), 0.8f, 2.6f, -34.4f, 3.6f, -33.4f, 5, -33.5f, 5.9f, -34.6f);
            ElfArm(tunic, trim, 1, -29, frontArm);
            FillEllipse(C(240, 160, 150), 5.2f, -38, 3.2f, 3.2f);

            float sway = (float)Math.Sin(walking ? p * 0.5f : n.T * 1.5f) * 2.5f;
            float tipX = -13 + sway, tipY = -60;
            FillCurves(tunic, 7.5f, -41, 7.5f, -52, 1, -60, tipX, tipY, -6, -56, -6.5f, -49, -6.5f, -41);
            FillPoly(trim, -7.5f, -43, 8.5f, -43, 8.5f, -40.8f, 6.5f, -39.2f, 4.5f, -40.8f, 2.5f, -39.2f, 0.5f, -40.8f,
                     -1.5f, -39.2f, -3.5f, -40.8f, -5.5f, -39.2f, -7.5f, -40.8f);
            FillEllipse(Gold, tipX - 2.6f, tipY - 2.6f, 5.2f, 5.2f);
            Line(C(150, 110, 20), 0.9f, tipX - 1.4f, tipY + 0.7f, tipX + 1.4f, tipY + 0.7f);
        }

        // A striped stocking and a shoe with a curled toe and a bell on its tip.
        void ElfLeg(Color stripe, float hx, float hy, float a)
        {
            float dx = (float)Math.Sin(a), dy = (float)Math.Cos(a);
            float fx = hx + dx * 12, fy = hy + dy * 12;
            Line(C(248, 246, 240), 4.6f, hx, hy, fx, fy, true);
            foreach (float k in new[] { 0.34f, 0.62f, 0.9f })
                Line(stripe, 4.6f, hx + dx * 12 * (k - 0.09f), hy + dy * 12 * (k - 0.09f), hx + dx * 12 * (k + 0.09f), hy + dy * 12 * (k + 0.09f));
            FillCurves(C(34, 92, 58), fx - 3.5f, fy + 3,
                       fx - 4.5f, fy - 1.5f, fx + 0.5f, fy - 3, fx + 4.5f, fy + 0.3f,
                       fx + 6.5f, fy + 1.5f, fx + 8.5f, fy - 0.5f, fx + 8.8f, fy - 3.8f,
                       fx + 11.5f, fy + 0.5f, fx + 9, fy + 3, fx + 6, fy + 3);
            FillEllipse(Gold, fx + 7.6f, fy - 5.6f, 2.4f, 2.4f);
        }

        void ElfArm(Color tunic, Color mitten, float sx, float sy, float a)
        {
            float hx = sx + (float)Math.Sin(a) * 10, hy = sy + (float)Math.Cos(a) * 10;
            Line(tunic, 4.2f, sx, sy, hx, hy, true);
            FillEllipse(mitten, hx - 2.5f, hy - 2.5f, 5, 5);
        }
        // ------------------------------------------------------------------ Wichtel, kabouter og päkapikk
        // Three more looks for the same walker (see Folk), for the countries whose own figure is close to the
        // nisse but not the same. Each has the nisse's skeleton and poses. Original figures: no known characters.
        // Kept line for line the same as the macOS version (Overlay.swift).
        static readonly Color[] WichtelCoats = { C(120, 122, 128), C(138, 44, 50), C(84, 108, 64), C(72, 86, 112) };
        static readonly Color[] WichtelCaps = { C(150, 38, 46), C(96, 100, 108), C(150, 38, 46), C(176, 128, 52) };
        static readonly Color[] KabouterJackets = { C(62, 122, 82), C(190, 140, 52), C(152, 88, 52), C(70, 112, 140) };
        static readonly Color[] PaekapikkReds = { C(202, 36, 46), C(178, 32, 48), C(214, 62, 50), C(164, 36, 62) };

        // The walker's pose, the same for every folk.
        struct Pose { public bool Walking; public float P, LegA, Bob, BackArm, FrontArm, Sway; }

        static Pose PoseOf(Nisse n)
        {
            var q = new Pose();
            q.Walking = n.State == 0;
            q.P = n.WalkPhase;
            q.LegA = q.Walking ? (float)Math.Sin(q.P) * 0.55f : 0f;
            q.Bob = q.Walking ? -Math.Abs((float)Math.Sin(q.P)) * 1.5f : 0f;
            if (n.State == 2) { q.BackArm = -q.LegA * 0.8f; q.FrontArm = 2.5f + (float)Math.Sin(n.T * 11) * 0.45f; }
            else if (n.CarriesGift) { q.BackArm = 1.3f; q.FrontArm = 1.3f; }
            else { q.BackArm = -q.LegA * 0.9f; q.FrontArm = q.LegA * 0.9f; }
            q.Sway = (float)Math.Sin(q.Walking ? q.P * 0.5f : n.T * 1.5f);
            return q;
        }

        int TunicIndex(Nisse n) { return Math.Max(0, Array.IndexOf(Tunics, n.Tunic)); }

        void DrawGift(Nisse n)
        {
            if (!n.CarriesGift || n.State == 2) return;
            FillRect(n.Gift, 6, -31, 11, 10);
            Line(Gold, 1.6f, 11.5f, -31, 11.5f, -21);
            Line(Gold, 1.6f, 6, -26, 17, -26);
            StrokeEllipse(Gold, 1.6f, 9, -34, 3, 3);
            StrokeEllipse(Gold, 1.6f, 12, -34, 3, 3);
        }

        // A leg of the given length with a boot, and an arm of the given length with a hand.
        void FolkLeg(Color cloth, float width, Color boot, float len, float hx, float hy, float a)
        {
            float fx = hx + (float)Math.Sin(a) * len, fy = hy + (float)Math.Cos(a) * len;
            Line(cloth, width, hx, hy, fx, fy, true);
            FillEllipse(boot, fx - 3, fy - 2, 9, 5);
        }

        void FolkArm(Color cloth, float width, Color hand, float handSize, float len, float sx, float sy, float a)
        {
            float hx = sx + (float)Math.Sin(a) * len, hy = sy + (float)Math.Cos(a) * len;
            Line(cloth, width, sx, sy, hx, hy, true);
            FillEllipse(hand, hx - handSize / 2, hy - handSize / 2, handSize, handSize);
        }

        // The German Wichtel: a tall felt cap pulled down over the eyes, so only a round nose and a long beard
        // show, and a bell-shaped coat that nearly reaches the ground, with two boots under it.
        void DrawWichtel(Nisse n)
        {
            Pose q = PoseOf(n);
            int ti = TunicIndex(n) % WichtelCoats.Length;
            Color coat = WichtelCoats[ti], cap = WichtelCaps[ti], mitten = C(70, 60, 55);

            FillEllipse(C(60, 80, 110, 50), -12, -2, 24, 4);
            FolkLeg(C(60, 50, 45), 4.5f, C(62, 40, 28), 6, -2.5f, -9 + q.Bob, q.LegA);
            FolkLeg(C(60, 50, 45), 4.5f, C(62, 40, 28), 6, 2.5f, -9 + q.Bob, -q.LegA);

            T.TranslateTransform(0, q.Bob);
            FolkArm(coat, 4.4f, mitten, 5, 9, -1, -27, q.BackArm);
            FillCurves(coat, -10, -7, -11, -20, -8, -31, 0, -32, 8, -31, 11, -20, 10, -7);
            DrawGift(n);

            FillEllipse(Skin, -6, -43, 13, 12);
            FillCurves(C(240, 240, 236), -6.5f, -37, -8, -24, -3, -13, 1, -9, 5, -13, 9.5f, -24, 8, -37);
            FolkArm(coat, 4.4f, mitten, 5, 9, 1, -27, q.FrontArm);
            FillEllipse(C(235, 165, 150), 1.5f, -39, 7, 7);

            float tipX = -9 + q.Sway * 2.5f * 1.6f, tipY = -68;
            FillCurves(cap, 10, -37, 9, -52, 2, -64, tipX, tipY, -7, -60, -9, -50, -9.5f, -37);
            Line(C(0, 0, 0, 60), 2.4f, -9.5f, -37.8f, 10, -37.8f);
        }

        // The Dutch kabouter: a stiff, straight cone hat, an open face with a short round beard, a jacket with a
        // belt, brown trousers and yellow clogs.
        void DrawKabouter(Nisse n)
        {
            Pose q = PoseOf(n);
            Color jacket = KabouterJackets[TunicIndex(n) % KabouterJackets.Length];

            FillEllipse(C(60, 80, 110, 50), -11, -2, 22, 4);
            KabouterLeg(-2, -15 + q.Bob, q.LegA);
            KabouterLeg(2, -15 + q.Bob, -q.LegA);

            T.TranslateTransform(0, q.Bob);
            FolkArm(jacket, 4.2f, Skin, 4.6f, 10, -1, -29, q.BackArm);
            FillEllipse(jacket, -10, -34, 20, 22);
            FillRect(C(60, 40, 25), -9.5f, -20, 19, 3);
            FillRect(Gold, 2, -20.5f, 3.5f, 4);
            DrawGift(n);

            FillEllipse(Skin, -6, -44, 13, 12);
            FillCurves(C(250, 250, 250), -6, -38, -7.5f, -31, -3, -27, 1.5f, -27, 6, -27, 9, -31, 7.5f, -38);
            FillEllipse(C(245, 150, 140, 150), 0.6f, -39.6f, 3.2f, 2.4f);
            FillEllipse(C(45, 32, 30), 2.8f, -41.3f, 1.6f, 1.9f);
            FolkArm(jacket, 4.2f, Skin, 4.6f, 10, 1, -29, q.FrontArm);
            FillEllipse(C(240, 160, 150), 4.2f, -40.2f, 4, 4);

            FillPoly(HatRed, -7.5f, -42, 8, -42, 0.5f + q.Sway * 1.2f, -67);
            Line(C(150, 15, 25), 1.8f, -7.5f, -42.4f, 8, -42.4f);
        }

        void KabouterLeg(float hx, float hy, float a)
        {
            float fx = hx + (float)Math.Sin(a) * 12, fy = hy + (float)Math.Cos(a) * 12;
            Color clog = C(232, 190, 80);
            Line(C(105, 75, 50), 5, hx, hy, fx, fy, true);
            FillEllipse(clog, fx - 3.5f, fy - 2, 10, 5);
            FillPoly(clog, fx + 3.5f, fy - 1.6f, fx + 9.5f, fy - 3.6f, fx + 6.5f, fy + 2.4f);
        }

        // The Estonian päkapikk: all in red with white trim, a short floppy cap with a fur band and a pompom, an
        // open, beardless face with fair hair showing under the cap.
        void DrawPaekapikk(Nisse n)
        {
            Pose q = PoseOf(n);
            Color red = PaekapikkReds[TunicIndex(n) % PaekapikkReds.Length], white = C(248, 248, 248);

            FillEllipse(C(60, 80, 110, 50), -11, -2, 22, 4);
            PaekapikkLeg(red, white, -2, -15 + q.Bob, q.LegA);
            PaekapikkLeg(red, white, 2, -15 + q.Bob, -q.LegA);

            T.TranslateTransform(0, q.Bob);
            FolkArm(red, 4.2f, white, 5, 10, -1, -29, q.BackArm);
            FillEllipse(red, -9.5f, -34, 19, 21);
            Line(white, 3, -7.6f, -15.2f, 7.6f, -15.2f, true);
            FillRect(C(35, 30, 30), -9.2f, -22, 18.4f, 2.6f);
            FillRect(Gold, 1.8f, -22.5f, 3.3f, 3.6f);
            FillEllipse(white, -5.5f, -34.6f, 12, 4.2f);
            DrawGift(n);

            FillEllipse(C(232, 192, 96), -7.2f, -42.5f, 6, 6);
            FillEllipse(Skin, -6, -44, 13, 12);
            FillEllipse(C(240, 196, 168), -5.2f, -39.6f, 2.6f, 3.4f);
            FillEllipse(C(245, 150, 140, 150), 0.8f, -36.6f, 3.2f, 2.4f);
            FillEllipse(C(45, 32, 30), 2.8f, -38.8f, 1.7f, 2);
            Bezier(C(150, 70, 60), 0.8f, 2.6f, -34.6f, 3.6f, -33.6f, 5, -33.7f, 5.9f, -34.8f);
            FolkArm(red, 4.2f, white, 5, 10, 1, -29, q.FrontArm);
            FillEllipse(C(240, 160, 150), 5, -38.3f, 3.4f, 3.4f);

            float tipX = -12 + q.Sway * 2.5f, tipY = -55;
            FillCurves(red, 8, -41, 8.5f, -52, 0, -58, tipX, tipY, -6, -54, -7, -48, -7, -41);
            Line(white, 3.6f, -7, -41.4f, 8, -41.4f, true);
            FillEllipse(white, tipX - 3, tipY - 3, 6, 6);
        }

        void PaekapikkLeg(Color red, Color white, float hx, float hy, float a)
        {
            float dx = (float)Math.Sin(a), dy = (float)Math.Cos(a);
            float fx = hx + dx * 12, fy = hy + dy * 12;
            Line(red, 4.8f, hx, hy, fx, fy, true);
            Line(white, 4.8f, hx + dx * 8.2f, hy + dy * 8.2f, hx + dx * 10.2f, hy + dy * 10.2f);
            FillEllipse(C(40, 36, 40), fx - 3, fy - 2, 9, 5);
        }
    }
}
