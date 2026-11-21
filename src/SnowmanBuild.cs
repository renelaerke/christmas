using System;
using System.Collections.Generic;
using System.Globalization;

namespace JuleHygge
{
    // The snowman in the Christmas theme (Windows only so far): three children build it on the taskbar of the
    // primary screen in about 15 minutes. They roll the three balls one by one, lift them on top of each other
    // and dress it (eyes, nose, buttons, arms, smile, scarf, hat). When it is finished they cheer and have a
    // snowball fight, and a few minutes later the snow plow comes by and runs it down. The children then walk
    // to another place and start again.
    //
    // This class is only the story; Layer (LayerSnowman.cs) moves it on the screen, lets the plow run it down
    // and draws it. Positions are in logical units (pixels / Layer.S) from the primary screen's left edge, and
    // heights are above the ground. The state lives in the Controller, so it survives the layers being rebuilt.
    // JULE_SNOWMAN_SPEED=N runs it N times faster (for testing).
    class SnowmanBuild
    {
        public const float BuildTime = 900;
        // When each part is rolled and lifted (seconds into the build).
        const float BottomEnd = 330, MiddleStart = 150, MiddleEnd = 540, MiddleLift = 565,
                    HeadStart = 565, HeadEnd = 735, HeadLift = 760, DressStart = 760;
        public const int Items = 7;   // eyes, nose, buttons, arms, smile, scarf, hat
        const float ItemTime = (BuildTime - DressStart) / Items;
        public const float BottomR = 14, MiddleR = 10, HeadR = 7.5f;
        // the centres of the stacked balls, above the ground
        public const float BottomY = BottomR, MiddleY = 2 * BottomR - 3 + MiddleR, HeadY = MiddleY + MiddleR - 2.5f + HeadR;

        public sealed class Ball { public float X, Y, R, Roll, Vx; public bool Present; }

        public sealed class Kid
        {
            public int Look;              // which of the three children (clothes and size)
            public float Size, Speed;     // Speed in units per second
            public float X, Dir = 1, Lift, WalkPhase, T, TargetX, FaceDir, ThrowT = -1;
            public int Pose, Want;        // the pose drawn now, and the one to take at the target
            public bool Waving;           // the plow is passing (set by the layer)
        }

        public sealed class Snowball { public float X, Y, VX, VY, TargetX, Life = -1; }

        public const int Walk = 0, Stand = 1, Wave = 2, Push = 3, Lift = 4, Pat = 5, Jump = 6, Throw = 7, Sad = 8;

        public readonly Ball Bottom = new Ball(), Middle = new Ball(), Head = new Ball();
        public readonly Ball[] Balls;
        public readonly Kid[] Kids;
        public readonly List<Snowball> Snowballs = new List<Snowball>();
        public float SiteX;
        public int Dressed;           // how many of the Items are on
        public int State;             // 0 walking to the place, 1 building, 2 finished, 3 run down
        public float T;               // seconds into the build
        public bool WantsPlow;        // the Controller sends the plow (and clears this)
        public bool JustFinished;     // true for the one update in which the snowman was finished

        const int Walking = 0, Building = 1, Finished = 2, RunDown = 3;
        const float Gravity = 110;
        readonly Random rnd = new Random();
        readonly float speed = 1;
        bool started;
        float clock, plowAt = -1, stateTimer, throwTimer, wanderTimer;
        int nextThrower;

        public SnowmanBuild()
        {
            Balls = new[] { Bottom, Middle, Head };
            Kids = new[] {
                new Kid { Look = 0, Size = 1f, Speed = 30 },
                new Kid { Look = 1, Size = 0.95f, Speed = 30 },
                new Kid { Look = 2, Size = 0.8f, Speed = 24 } };
            float f;
            if (float.TryParse(Environment.GetEnvironmentVariable("JULE_SNOWMAN_SPEED"), NumberStyles.Float,
                    CultureInfo.InvariantCulture, out f) && f > 0) speed = f;
        }

        float R() { return (float)rnd.NextDouble(); }

        public bool HasSnow { get { return Bottom.Present || Middle.Present || Head.Present; } }

        // The children's playground while they build and play (half its width, in units round SiteX): the walkers
        // turn before they reach it. The place is chosen far enough from the screen's edges that the playground
        // never covers one (a walker coming in at an edge would otherwise have nowhere to go).
        public const float PlayHalfWidth = 85;
        public bool Playing { get { return State == Building || State == Finished; } }

        public void Update(float dt, float widthU)
        {
            dt *= speed;
            clock += dt;
            JustFinished = false;
            float lo = PlayHalfWidth + 40, hi = Math.Max(lo, widthU - PlayHalfWidth - 40);
            if (!started)
            {
                // The app may start in the middle of a build: somewhere, some way along.
                started = true;
                SiteX = lo + R() * (hi - lo);
                State = Building;
                T = R() * BuildTime * 0.95f;
                foreach (var k in Kids) k.X = k.TargetX = SiteX + (R() - 0.5f) * 80;
                ErrorLog.Debug("snowman: building at x=" + (int)SiteX + ", " + (int)T + " s along");
            }
            SiteX = Math.Max(lo, Math.Min(hi, SiteX));

            switch (State)
            {
                case Walking:
                    bool there = true;
                    foreach (var k in Kids) if (Math.Abs(k.X - k.TargetX) > 1.5f) there = false;
                    if (there) { State = Building; T = 0; ErrorLog.Debug("snowman: starting a new one at x=" + (int)SiteX); }
                    break;
                case Building:
                    T += dt;
                    if (T >= BuildTime)
                    {
                        T = BuildTime;
                        State = Finished;
                        stateTimer = 0;
                        throwTimer = 3;
                        JustFinished = true;
                        plowAt = clock + 120 + R() * 120;
                        ErrorLog.Debug("snowman: finished, the plow comes in " + (int)(plowAt - clock) + " s");
                    }
                    break;
                case Finished:
                    stateTimer += dt;
                    // If the plow cannot come now (already out, or switched off), ask again a minute later.
                    if (plowAt >= 0 && clock >= plowAt) { WantsPlow = true; plowAt = clock + 60; }
                    break;
                case RunDown:
                    stateTimer -= dt;
                    bool waving = false;
                    foreach (var k in Kids) if (k.Waving) waving = true;
                    if (stateTimer <= 0 && !waving) MoveOn(lo, hi);
                    break;
            }

            PlaceBalls(dt);
            SetTargets(dt);
            MoveKids(dt, widthU);
            UpdateSnowballs(dt);
        }

        // The plow has reached the snowman: it is gone, and the children start again elsewhere after a while.
        public void RunOver()
        {
            State = RunDown;
            stateTimer = 5;
            plowAt = -1;
            WantsPlow = false;
            Snowballs.Clear();
            foreach (var b in Balls) b.Present = false;
            Dressed = 0;
            foreach (var k in Kids) { k.ThrowT = -1; Go(k, k.X, Sad, Math.Sign(SiteX - k.X)); }
        }

        void MoveOn(float lo, float hi)
        {
            float old = SiteX, away = Math.Min(250, (hi - lo) * 0.3f);
            for (int i = 0; i < 12; i++)
            {
                SiteX = lo + R() * (hi - lo);
                if (Math.Abs(SiteX - old) >= away) break;
            }
            State = Walking;
            Go(Kids[0], SiteX - 20, Stand, 1);
            Go(Kids[1], SiteX + 40, Pat, -1);
            Go(Kids[2], SiteX + 15, Stand, -1);
            ErrorLog.Debug("snowman: the children walk from x=" + (int)old + " to x=" + (int)SiteX);
        }

        // ------------------------------------------------------------------ the balls
        void PlaceBalls(float dt)
        {
            bool built = State == Building || State == Finished;
            float t = State == Finished ? BuildTime : T;
            foreach (var b in Balls) b.Vx = 0;

            float x0 = Bottom.X;
            Bottom.Present = built;
            if (Bottom.Present) Roll(Bottom, t, 0, BottomEnd, SiteX, 30, 50, BottomR);

            float x1 = Middle.X;
            Middle.Present = built && t >= MiddleStart;
            if (Middle.Present)
            {
                Roll(Middle, t, MiddleStart, MiddleEnd, SiteX + 42, 22, 44, MiddleR);
                LiftOnto(Middle, t, MiddleEnd + 10, MiddleLift, SiteX + 42, SiteX, MiddleY);
            }

            float x2 = Head.X;
            Head.Present = built && t >= HeadStart;
            if (Head.Present)
            {
                Roll(Head, t, HeadStart, HeadEnd, SiteX - 34, 14, 36, HeadR);
                LiftOnto(Head, t, HeadEnd + 8, HeadLift, SiteX - 34, SiteX, HeadY);
            }

            if (dt > 0)
            {
                Bottom.Vx = (Bottom.X - x0) / dt;
                Middle.Vx = (Middle.X - x1) / dt;
                Head.Vx = (Head.X - x2) / dt;
            }
            Dressed = t < DressStart ? 0 : Math.Min(Items, (int)((t - DressStart) / ItemTime));
        }

        static float Smooth(float a, float b, float x)
        {
            float f = Math.Max(0, Math.Min(1, (x - a) / (b - a)));
            return f * f * (3 - 2 * f);
        }

        // A ball rolled back and forth around its home while it grows, coming to rest at home.
        static void Roll(Ball b, float t, float t0, float t1, float home, float amp, float period, float r)
        {
            float u = Math.Min(t, t1) - t0;
            float f = Math.Max(0, Math.Min(1, u / (t1 - t0)));
            b.R = 2.5f + (r - 2.5f) * (float)Math.Pow(f, 0.6);
            float settle = 1 - Smooth(t1 - 0.15f * (t1 - t0), t1, t0 + u);
            b.X = home + amp * (float)Math.Sin(2 * Math.PI * u / period) * settle;
            b.Y = b.R;
            b.Roll = (b.X - home) / Math.Max(1, b.R);
        }

        // Lifted in an arc from where it was rolled onto the ball below.
        static void LiftOnto(Ball b, float t, float t0, float t1, float from, float to, float y)
        {
            if (t < t0) return;
            float f = Smooth(t0, t1, t);
            b.X = from + (to - from) * f;
            b.Y = b.R + (y - b.R) * f + (float)Math.Sin(Math.PI * f) * 6;
        }

        // ------------------------------------------------------------------ the children
        void Go(Kid k, float x, int want, float face)
        {
            k.TargetX = x;
            k.Want = want;
            k.FaceDir = face;
        }

        void PushBall(Kid k, Ball b)
        {
            // from behind, in the direction it rolls
            float dir = Math.Abs(b.Vx) > 0.05f ? Math.Sign(b.Vx) : (k.FaceDir != 0 ? k.FaceDir : 1);
            Go(k, b.X - dir * (b.R + 6), Push, dir);
        }

        // Each item is put on by one of the two big children in turn, reaching up for the last seconds of its turn.
        void Dress(Kid k, int parity, float x, float face)
        {
            float u = T - DressStart;
            int slot = (int)(u / ItemTime);
            bool mine = slot < Items && slot % 2 == parity && u - slot * ItemTime > ItemTime - 7;
            Go(k, x, mine ? Lift : Stand, face);
        }

        void SetTargets(float dt)
        {
            Kid a = Kids[0], b = Kids[1], small = Kids[2];
            float t = T;
            if (State == Building)
            {
                // the oldest rolls the bottom ball, helps lift the middle one, rolls the head and dresses it
                if (t < BottomEnd) PushBall(a, Bottom);
                else if (t < MiddleEnd + 10) Go(a, SiteX - BottomR - 7, Pat, 1);
                else if (t < MiddleLift) Go(a, SiteX - BottomR - 5, Lift, 1);
                else if (t < HeadEnd) PushBall(a, Head);
                else if (t < HeadLift) Go(a, SiteX - BottomR - 6, Lift, 1);
                else Dress(a, 0, SiteX - BottomR - 6, 1);

                // the second makes snow ready, then rolls the middle ball and lifts it up
                if (t < MiddleStart) Go(b, SiteX + 40, Pat, -1);
                else if (t < MiddleEnd) PushBall(b, Middle);
                else if (t < MiddleEnd + 10) Go(b, SiteX + 42 + MiddleR + 5, Stand, -1);
                else if (t < MiddleLift) Go(b, SiteX + BottomR + 5, Lift, -1);
                else if (t < HeadLift) Go(b, SiteX + BottomR + 7, Pat, -1);
                else Dress(b, 1, SiteX + BottomR + 6, -1);
            }
            else if (State == Finished)
            {
                if (stateTimer < 5)
                {
                    // hooray, beside it (not in front, where they would hide it)
                    Go(a, SiteX - 30, Jump, 1);
                    Go(b, SiteX + 30, Jump, -1);
                    Go(small, SiteX + 48, Jump, -1);
                }
                else
                {
                    // a snowball fight in front of the snowman
                    if (a.ThrowT < 0) Go(a, SiteX - 60, Stand, 1);
                    if (b.ThrowT < 0) Go(b, SiteX + 60, Stand, -1);
                    throwTimer -= dt;
                    bool ready = Math.Abs(a.X - a.TargetX) < 1 && Math.Abs(b.X - b.TargetX) < 1;
                    if (throwTimer <= 0 && ready)
                    {
                        var thrower = nextThrower == 0 ? a : b;
                        nextThrower ^= 1;
                        thrower.ThrowT = 0;
                        throwTimer = 2.5f + R() * 4;
                    }
                }
            }

            // the little one wanders about, pats snow and jumps
            if (State == Building || (State == Finished && stateTimer >= 5))
            {
                wanderTimer -= dt;
                if (wanderTimer <= 0)
                {
                    wanderTimer = 6 + R() * 6;
                    float r = R();
                    float x = SiteX + (R() - 0.5f) * 110;
                    Go(small, x, r < 0.45f ? Pat : r < 0.7f ? Jump : Stand, Math.Sign(SiteX - x));
                }
            }
        }

        void MoveKids(float dt, float widthU)
        {
            foreach (var k in Kids)
            {
                k.T += dt;
                if (k.T > 200 * (float)Math.PI) k.T -= 200 * (float)Math.PI;
                k.TargetX = Math.Max(10, Math.Min(widthU - 10, k.TargetX));
                float d = k.TargetX - k.X;
                if (k.Waving)
                {
                    k.Pose = Wave;
                    k.Lift = 0;
                    continue;
                }
                if (Math.Abs(d) > 1)
                {
                    float step = Math.Sign(d) * Math.Min(Math.Abs(d), k.Speed * dt);
                    k.X += step;
                    k.Dir = Math.Sign(d);
                    k.Pose = Walk;
                    k.WalkPhase += Math.Abs(step) / (4.5f * k.Size);
                }
                else
                {
                    // at the target (a pushed ball moves on slowly: the legs keep walking)
                    k.WalkPhase += Math.Abs(d) / (4.5f * k.Size);
                    k.X = k.TargetX;
                    k.Pose = k.Want;
                    if (k.FaceDir != 0) k.Dir = k.FaceDir;
                }
                if (k.ThrowT >= 0)
                {
                    float before = k.ThrowT;
                    k.ThrowT += dt;
                    k.Pose = Throw;
                    if (before < 0.3f && k.ThrowT >= 0.3f) ThrowAt(k, k == Kids[0] ? Kids[1] : Kids[0]);
                    if (k.ThrowT > 0.7f) k.ThrowT = -1;
                }
                k.Lift = k.Pose == Jump ? Math.Abs((float)Math.Sin(k.T * 6)) * 7 : 0;
            }
        }

        // ------------------------------------------------------------------ snowballs
        void ThrowAt(Kid from, Kid to)
        {
            var s = new Snowball();
            s.X = from.X + from.Dir * 7 * from.Size;
            s.Y = 32 * from.Size;
            float flight = 0.9f + R() * 0.3f;
            s.TargetX = to.X + (R() - 0.5f) * 16;
            float ty = 26 * to.Size;
            s.VX = (s.TargetX - s.X) / flight;
            s.VY = (ty - s.Y + 0.5f * Gravity * flight * flight) / flight;
            Snowballs.Add(s);
        }

        void UpdateSnowballs(float dt)
        {
            for (int i = Snowballs.Count - 1; i >= 0; i--)
            {
                var s = Snowballs[i];
                if (s.Life >= 0)
                {
                    s.Life -= dt;
                    if (s.Life < 0) Snowballs.RemoveAt(i);
                    continue;
                }
                s.X += s.VX * dt;
                s.Y += s.VY * dt;
                s.VY -= Gravity * dt;
                bool past = s.VX > 0 ? s.X >= s.TargetX : s.X <= s.TargetX;
                if (past || s.Y <= 0) { s.Y = Math.Max(0, s.Y); s.Life = 0.5f; }
            }
        }
    }
}
