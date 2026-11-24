using System;
using System.Drawing;
using System.Drawing.Drawing2D;

namespace JuleHygge
{
    // The snowman the children build in the Christmas theme (SnowmanBuild has the story). This part lets the
    // plow run it down and draws the snowman, the three children and their snowballs on the primary screen.
    partial class Layer
    {
        // The children's clothes: jacket, trousers, knitted hat, its pompom, mittens, and a scarf (or empty).
        static readonly Color[][] KidClothes = {
            new[] { Color.FromArgb(205, 50, 45), Color.FromArgb(45, 65, 120), Color.FromArgb(240, 240, 245), Color.FromArgb(205, 40, 45), Color.FromArgb(45, 65, 120), Color.FromArgb(245, 190, 45) },
            new[] { Color.FromArgb(45, 125, 195), Color.FromArgb(55, 55, 65), Color.FromArgb(245, 185, 40), Color.White, Color.FromArgb(245, 185, 40), Color.Empty },
            new[] { Color.FromArgb(90, 170, 100), Color.FromArgb(75, 150, 90), Color.FromArgb(225, 90, 150), Color.White, Color.FromArgb(225, 90, 150), Color.Empty } };

        // Where the children build and play, in this screen's pixels (only on the primary screen, while they do).
        bool PlayZone(out float left, out float right)
        {
            var b = c.Build;
            left = (b.SiteX - SnowmanBuild.PlayHalfWidth) * S;
            right = (b.SiteX + SnowmanBuild.PlayHalfWidth) * S;
            return IsPrimary && cfg.Snowman && !c.Autumn && b.Playing;
        }

        float BuildGround(float x)
        {
            return groundY - HeapAt(Math.Max(0, Math.Min(W - 1, x))) + 2 * S;
        }

        float lastBlade = float.NaN;

        void UpdateBuild(float dt)
        {
            var b = c.Build;
            bool plowHere = plowActive;
            foreach (var k in b.Kids) k.Waving = plowHere && Math.Abs(k.X * S - plowX) < 170 * S;
            float blade = plowHere ? plowX + plowDir * 72 * S * PlowScale : float.NaN;
            // Only where the blade arrives this frame: a snowman begun behind the plow, after it has passed, stays.
            if (plowHere && b.HasSnow && !float.IsNaN(lastBlade))
            {
                foreach (var ball in b.Balls)
                {
                    if (!ball.Present) continue;
                    float near = ball.X * S - plowDir * ball.R * S;   // the ball's side facing the plow
                    if ((blade - near) * plowDir >= 0 && (lastBlade - near) * plowDir < 0) { RunDownSnowman(); break; }
                }
            }
            lastBlade = blade;
            b.Update(dt, W / S);
            if (b.JustFinished) c.SnowmanCelebrate();
        }

        // The plow's blade has reached the snowman: it flies apart in chunks of snow, into the pile before the blade.
        void RunDownSnowman()
        {
            var b = c.Build;
            foreach (var ball in b.Balls)
            {
                if (!ball.Present) continue;
                float bx = ball.X * S, by = BuildGround(bx) - ball.Y * S;
                int n = 4 + (int)(ball.R * 1.6f);
                for (int i = 0; i < n; i++)
                {
                    var p = new PlowBit();
                    p.X = bx + (Rnd() - 0.5f) * ball.R * S;
                    p.Y = by + (Rnd() - 0.5f) * ball.R * S;
                    p.VX = plowDir * (60 + Rnd() * 150) * S;
                    p.VY = -(70 + Rnd() * 170) * S;
                    p.Max = p.Life = 2f;
                    p.Size = (1.5f + Rnd() * 3f) * S;
                    plowBits.Add(p);
                }
                c.Plow.Pushed += ball.R * ball.R * 2 * S;
            }
            ErrorLog.Debug("snowman: run down by the plow at x=" + (int)b.SiteX + " (" + (int)b.T + " s into the build)");
            b.RunOver();
        }

        void DrawBuild()
        {
            var b = c.Build;
            float sx = b.SiteX * S, gy = BuildGround(sx);
            SnowmanPos = new PointF(ScreenBounds.X + sx, ScreenBounds.Y + gy);

            if (b.Bottom.Present)
                using (var shadow = new SolidBrush(Color.FromArgb(50, 60, 80, 110)))
                {
                    float bx = b.Bottom.X * S, r = b.Bottom.R * S;
                    g.FillEllipse(shadow, bx - r * 1.1f, BuildGround(bx) - 2 * S, r * 2.2f, 4 * S);
                }
            foreach (var ball in b.Balls) if (ball.Present) DrawBuildBall(ball);
            if (b.Dressed > 0) DrawSnowmanDress(b.Dressed, sx, gy);
            foreach (var k in b.Kids) DrawKid(k);
            DrawSnowballs(b);
        }

        void DrawBuildBall(SnowmanBuild.Ball ball)
        {
            float bx = ball.X * S, by = BuildGround(bx) - ball.Y * S, r = ball.R;
            Mark(bx - (r + 2) * S, by - (r + 2) * S, (2 * r + 4) * S, (2 * r + 6) * S);
            var st = g.Save();
            g.TranslateTransform(bx, by);
            g.ScaleTransform(S, S);
            Ball(0, 0, r);
            // two lumps in the snow turn with the ball, so it can be seen rolling
            using (var lump = new SolidBrush(Color.FromArgb(70, 150, 170, 200)))
                for (int i = 0; i < 2; i++)
                {
                    double a = ball.Roll + i * 2.6;
                    float lr = r * (i == 0 ? 0.55f : 0.35f), d = Math.Max(0.8f, r * 0.12f);
                    g.FillEllipse(lump, (float)Math.Cos(a) * lr - d, (float)Math.Sin(a) * lr - d, 2 * d, 2 * d);
                }
            g.Restore(st);
        }

        // What the children put on the finished stack, in order. The snowman looks to the right.
        void DrawSnowmanDress(int n, float sx, float gy)
        {
            Mark(sx - 30 * S, gy - 72 * S, 60 * S, 74 * S);
            var st = g.Save();
            g.TranslateTransform(sx, gy);
            g.ScaleTransform(S, S);
            float my = -SnowmanBuild.MiddleY, hy = -SnowmanBuild.HeadY;
            using (var coal = new SolidBrush(Color.FromArgb(35, 35, 40)))
            {
                if (n >= 4)
                    using (var wood = new Pen(Color.FromArgb(110, 70, 35), 1.6f))
                    {
                        wood.StartCap = wood.EndCap = LineCap.Round;
                        g.DrawLine(wood, -8, my - 3, -21, my - 12);
                        g.DrawLine(wood, -17, my - 9.5f, -18, my - 15);
                        g.DrawLine(wood, 8, my - 3, 21, my - 10);
                        g.DrawLine(wood, 17, my - 7.5f, 20, my - 13);
                    }
                if (n >= 1)
                {
                    g.FillEllipse(coal, 0.3f, hy - 3.2f, 2.2f, 2.2f);
                    g.FillEllipse(coal, 4.3f, hy - 3.2f, 2.2f, 2.2f);
                }
                if (n >= 2)
                    using (var carrot = new SolidBrush(Color.FromArgb(240, 130, 30)))
                        g.FillPolygon(carrot, new[] { new PointF(3, hy - 0.8f), new PointF(12, hy + 0.2f), new PointF(3, hy + 1.2f) });
                if (n >= 3)
                    for (int i = 0; i < 3; i++) g.FillEllipse(coal, 0.2f, my - 5.8f + i * 4.6f, 2.4f, 2.4f);
                if (n >= 5)
                    for (int i = 0; i < 4; i++)
                    {
                        float x = 0.5f + i * 1.7f, y = hy + 3.6f + 0.5f * (1 - Math.Abs(i - 1.5f) / 1.5f);
                        g.FillEllipse(coal, x - 0.6f, y - 0.6f, 1.2f, 1.2f);
                    }
            }
            if (n >= 6)
            {
                float ny = hy + SnowmanBuild.HeadR - 1.5f;
                using (var scarf = new SolidBrush(Color.FromArgb(200, 30, 40)))
                {
                    g.FillRectangle(scarf, -7.5f, ny, 15, 3.4f);
                    g.FillPolygon(scarf, new[] { new PointF(-5, ny + 2), new PointF(-1.5f, ny + 2), new PointF(-2.5f, ny + 11), new PointF(-6.5f, ny + 10.5f) });
                }
                using (var stripe = new Pen(Color.White, 1f))
                {
                    g.DrawLine(stripe, -5.5f, ny + 6, -2f, ny + 6);
                    g.DrawLine(stripe, -6f, ny + 8.5f, -2.3f, ny + 8.5f);
                }
            }
            if (n >= 7)
            {
                // a green knitted hat with a pompom
                float top = hy - SnowmanBuild.HeadR;
                using (var knit = new SolidBrush(Color.FromArgb(40, 140, 70)))
                using (var brim = new SolidBrush(Color.FromArgb(25, 105, 50)))
                using (var pom = new SolidBrush(Color.White))
                {
                    g.FillPie(knit, -6.8f, top - 6, 13.6f, 13.6f, 180, 180);
                    g.FillRectangle(brim, -7.3f, top - 0.2f, 14.6f, 2.8f);
                    g.FillEllipse(pom, -2.4f, top - 8.4f, 4.8f, 4.8f);
                }
            }
            g.Restore(st);
        }

        void DrawKid(SnowmanBuild.Kid k)
        {
            float ks = S * k.Size;
            float x = k.X * S, ground = BuildGround(x), gy = ground - k.Lift * S;
            Mark(x - 18 * ks, gy - 56 * ks, 36 * ks, ground - gy + 60 * ks);
            var clothes = KidClothes[k.Look];
            Color jacket = clothes[0], trousers = clothes[1], hat = clothes[2], pompom = clothes[3], mittens = clothes[4], scarf = clothes[5];

            using (var shadow = new SolidBrush(Color.FromArgb(45, 60, 80, 110)))
                g.FillEllipse(shadow, x - 8 * ks, ground - 1.5f * ks, 16 * ks, 3 * ks);

            var st = g.Save();
            g.TranslateTransform(x, gy);
            g.ScaleTransform(k.Dir * ks, ks);

            int pose = k.Pose;
            bool walking = pose == SnowmanBuild.Walk || pose == SnowmanBuild.Push;
            float legA = walking ? (float)Math.Sin(k.WalkPhase) * 0.5f : 0f;
            float bob = pose == SnowmanBuild.Walk ? -Math.Abs((float)Math.Sin(k.WalkPhase)) * 1.2f : 0f;
            bool squat = pose == SnowmanBuild.Pat;
            if (pose == SnowmanBuild.Push) g.RotateTransform(12);   // leaning into the ball

            using (var legs = new Pen(trousers, 5f))
            using (var boot = new SolidBrush(Color.FromArgb(50, 40, 35)))
            {
                legs.StartCap = legs.EndCap = LineCap.Round;
                if (squat)
                {
                    // knees forward, bottom down
                    g.DrawLine(legs, -2, -8, 4, -9);
                    g.DrawLine(legs, 4, -9, 3, -1.5f);
                    g.FillEllipse(boot, 1, -3, 8, 4.5f);
                    g.DrawLine(legs, 1, -8, -1, -1.5f);
                    g.FillEllipse(boot, -3, -3, 8, 4.5f);
                }
                else
                {
                    KidLeg(legs, boot, -1.8f, -14 + bob, legA);
                    KidLeg(legs, boot, 1.8f, -14 + bob, -legA);
                }
            }

            g.TranslateTransform(0, squat ? 7 : bob);
            float back, front;
            switch (pose)
            {
                case SnowmanBuild.Wave: back = 0.15f; front = 2.5f + (float)Math.Sin(k.T * 11) * 0.45f; break;
                case SnowmanBuild.Push: back = 1.45f; front = 1.6f; break;
                case SnowmanBuild.Lift: back = 2.55f; front = 2.7f; break;
                case SnowmanBuild.Pat: back = 1.1f; front = 1.3f + (float)Math.Sin(k.T * 9) * 0.3f; break;
                case SnowmanBuild.Jump: back = 2.7f + (float)Math.Sin(k.T * 6) * 0.2f; front = 2.85f - (float)Math.Sin(k.T * 6) * 0.2f; break;
                case SnowmanBuild.Throw:
                    back = 0.6f;
                    front = k.ThrowT < 0.3f ? -2.4f : -2.4f + Math.Min(1, (k.ThrowT - 0.3f) / 0.15f) * 4.1f;
                    break;
                case SnowmanBuild.Sad: back = 0.05f; front = 0.05f; break;
                case SnowmanBuild.Walk: back = -legA * 0.9f; front = legA * 0.9f; break;
                default: back = 0.2f; front = 0.1f; break;
            }

            using (var coat = new SolidBrush(jacket))
            using (var arm = new Pen(jacket, 4.2f))
            using (var mitten = new SolidBrush(mittens))
            {
                arm.StartCap = arm.EndCap = LineCap.Round;
                KidArm(arm, mitten, -1, -25, back);
                g.FillEllipse(coat, -8.5f, -31, 17, 18);
                using (var zip = new Pen(Color.FromArgb(90, 0, 0, 0), 0.8f)) g.DrawLine(zip, 4.5f, -29, 5, -15);

                using (var skin = new SolidBrush(Skin)) g.FillEllipse(skin, -5.5f, -42, 11, 11);
                using (var cheek = new SolidBrush(Color.FromArgb(150, 240, 140, 140))) g.FillEllipse(cheek, 1.2f, -35.5f, 3, 2.4f);
                using (var eye = new SolidBrush(Color.FromArgb(45, 40, 40)))
                {
                    if (pose == SnowmanBuild.Sad) g.FillRectangle(eye, 2.2f, -37, 2, 0.8f);
                    else g.FillEllipse(eye, 2.4f, -37.6f, 1.6f, 1.6f);
                }
                if (scarf != Color.Empty)
                    using (var sc = new SolidBrush(scarf))
                    {
                        g.FillRectangle(sc, -5, -32, 10, 3);
                        g.FillPolygon(sc, new[] { new PointF(-5, -31), new PointF(-2.5f, -31), new PointF(-5.5f, -23), new PointF(-8, -24) });
                    }

                using (var cap = new SolidBrush(hat))
                using (var pom = new SolidBrush(pompom))
                {
                    g.FillPie(cap, -6, -47.5f, 12, 12, 180, 180);
                    g.FillRectangle(cap, -6.3f, -42, 12.6f, 3);
                    using (var rib = new Pen(Color.FromArgb(50, 0, 0, 0), 0.7f)) g.DrawLine(rib, -6.3f, -40.5f, 6.3f, -40.5f);
                    g.FillEllipse(pom, -2.2f, -50, 4.4f, 4.4f);
                }
                KidArm(arm, mitten, 1, -25, front);
            }
            g.Restore(st);
        }

        void KidLeg(Pen legs, Brush boot, float hx, float hy, float a)
        {
            float fx = hx + (float)Math.Sin(a) * 11, fy = hy + (float)Math.Cos(a) * 11;
            g.DrawLine(legs, hx, hy, fx, fy);
            g.FillEllipse(boot, fx - 3, fy - 2, 8, 4.5f);
        }

        void KidArm(Pen arm, Brush mitten, float sx, float sy, float a)
        {
            float hx = sx + (float)Math.Sin(a) * 9, hy = sy + (float)Math.Cos(a) * 9;
            g.DrawLine(arm, sx, sy, hx, hy);
            g.FillEllipse(mitten, hx - 2.4f, hy - 2.4f, 4.8f, 4.8f);
        }

        void DrawSnowballs(SnowmanBuild b)
        {
            if (b.Snowballs.Count == 0) return;
            using (var snow = new SolidBrush(Color.FromArgb(250, 250, 252, 255)))
            using (var edge = new Pen(Color.FromArgb(110, 150, 175, 205), 0.8f))
                foreach (var s in b.Snowballs)
                {
                    float x = s.X * S, y = BuildGround(x) - s.Y * S;
                    if (s.Life < 0)
                    {
                        float r = 1.9f * S;
                        Mark(x - r - 2, y - r - 2, 2 * r + 4, 2 * r + 4);
                        g.FillEllipse(snow, x - r, y - r, 2 * r, 2 * r);
                        g.DrawEllipse(edge, x - r, y - r, 2 * r, 2 * r);
                    }
                    else
                    {
                        // it bursts into a little puff
                        float spread = (0.5f - s.Life) * 18 * S, d = 1.1f * S;
                        Mark(x - spread - 2 * d, y - spread - 2 * d, 2 * spread + 4 * d, 2 * spread + 4 * d);
                        for (int i = 0; i < 6; i++)
                        {
                            double a = i * Math.PI / 3 + 0.4;
                            g.FillEllipse(snow, x + (float)Math.Cos(a) * spread - d, y - Math.Abs((float)Math.Sin(a)) * spread - d, 2 * d, 2 * d);
                        }
                    }
                }
        }
    }
}
