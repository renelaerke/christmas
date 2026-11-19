using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;
using Microsoft.Win32;

namespace JuleHygge
{
    // Styrer det hele: bakkeikon, hovedløkke, julemanden (på tværs af skærme), effekter og daglige begivenheder.
    // Selve tegningen sker i ét Layer-vindue pr. skærm.
    partial class Controller : ApplicationContext
    {
        [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder sb, int max);

        public readonly Settings Cfg = Settings.Load();
        public readonly Random Rnd = new Random();
        // Seconds since start. A double, because a float loses precision after a few days of uptime
        // and animations would start to stutter.
        public double Time, StormUntil = -1;
        public float Wind;
        public Rectangle FullscreenRect = Rectangle.Empty;
        public Icon AppIcon;

        // julemanden, i virtuelle skærmkoordinater
        public bool SantaActive;
        public float SantaX, SantaY0, SantaDir = 1, SantaSpeed, SantaPhase, SantaScale = 1f;
        float santaMinX, santaMaxX;
        public readonly List<Spark> Sparks = new List<Spark>();

        public const int SnowmanMaxStage = 12;
        public int SnowmanStage = 1;
        static readonly string[] SnowmanSteps = {
            "en lille snebold", "en stor snebold", "maven", "hovedet", "øjne af kul", "en gulerodsnæse",
            "knapper", "arme af grene", "et smil", "et rødt halstørklæde", "en høj hat", "en kost - snemanden er færdig!" };

        readonly List<Layer> layers = new List<Layer>();
        readonly Timer timer;
        readonly Stopwatch clock = Stopwatch.StartNew();
        readonly Control invoker;
        double lastT;
        float windTarget, windTimer, santaNext = 5f, sparkAcc, fsTimer, topTimer, dayTimer;
        double celebrateAt = -1;
        DateTime lastDay;
        NotifyIcon tray;
        ToolStripMenuItem countdownItem, snowmanItem;
        CalendarForm calendar;
        bool balloonOpensCalendar;

        public float SantaY { get { return SantaY0 + (float)Math.Sin(SantaPhase * 0.9) * 40 * SantaScale; } }
        // 0 light, 1 normal, 2 storm. Setting 3 ("Skiftende vejr") lets the weather pick (see Weather).
        public int EffectiveSnowLevel { get { float a = SnowAmount; return a > 1.5f ? 2 : a > 0.5f ? 1 : 0; } }
        // The same as a number that glides between the levels while the weather changes (0 light ... 2 storm): the
        // number of flakes follows this, so a change comes on gradually; wind, speed and drifts follow the level.
        public float SnowAmount { get { return Time < StormUntil ? 2f : Cfg.SnowLevel == 3 ? (float)Weather.Amount() : Cfg.SnowLevel; } }
        public bool SnowOn { get { return Cfg.Snow || Time < StormUntil; } }

        // Snowfall slowly drifts between ~60% and ~140% of the chosen amount (two slow waves of about
        // 3 and 7 minutes with random phases), so it feels organic but averages out to the chosen level.
        readonly double snowPhaseA = new Random().NextDouble() * 2 * Math.PI, snowPhaseB = new Random(7).NextDouble() * 2 * Math.PI;
        public float SnowIntensity
        {
            get
            {
                if (Time < StormUntil) return 1;
                return (float)(1 + 0.25 * Math.Sin(Time * 2 * Math.PI / 190 + snowPhaseA) + 0.15 * Math.Sin(Time * 2 * Math.PI / 430 + snowPhaseB));
            }
        }

        // Power-save mode: snow only in a band above the taskbar, partial screen updates, lower frame rate.
        public bool PowerSave { get; private set; }
        float powerTimer;

        void UpdatePowerSave()
        {
            bool onBattery = SystemInformation.PowerStatus.PowerLineStatus == PowerLineStatus.Offline;
            PowerSave = Cfg.PowerSave == 1 || (Cfg.PowerSave == 2 && onBattery);
            UpdateFrameRate();
        }

        // ------------------------------------------------------------------ frame rate
        // The calm scene runs at the chosen (low) frame rate; only fast things get more frames: Santa and his
        // sparks 60 fps, the slow snow plow 30 fps. Power-save caps the calm rate at 12.
        double DesiredFps
        {
            get
            {
                double f;
                if (double.TryParse(Environment.GetEnvironmentVariable("JULE_FPS"), System.Globalization.NumberStyles.Float,
                        System.Globalization.CultureInfo.InvariantCulture, out f) && f > 0) return f;
                double calm = PowerSave ? Math.Min(Cfg.FrameRate, 12) : Cfg.FrameRate;
                // Unlike macOS (60 fps for Santa), Windows uploads the whole overlay on every frame, so 60 fps
                // costs about a full core (measured). Santa and the plow are boosted to 30 fps at most.
                bool busy = SantaActive || Sparks.Count > 0 || Plow.Active || Clumps.Count > 0;
                foreach (var l in layers) if (l.IsBusy) busy = true;
                if (busy) return Math.Max(calm, PowerSave ? 20 : 30);
                return calm;
            }
        }

        void UpdateFrameRate()
        {
            if (timer == null) return;
            // WinForms timers tick on the system timer, usually every 15.625 ms. Round the period to the nearest
            // whole number of ticks and aim just below it, so e.g. 20 fps becomes 3 ticks (~21 fps) instead of
            // spilling into a 4th tick (16 fps). With a finer system timer this is still close to the target.
            const double tick = 15.625;
            double ticks = Math.Max(1, Math.Round(1000 / DesiredFps / tick));
            int interval = Math.Max(1, (int)(ticks * tick) - 1);
            if (timer.Interval != interval) timer.Interval = interval;
        }

        // ------------------------------------------------------------------ sleep
        // Everything stops while the PC is locked, suspended, the display is off or the screen saver runs.
        // Each reason is tracked on its own, so e.g. the screen saver ending in front of the lock screen
        // does not wake the overlay.
        bool locked, suspended, displayOff, screenSaver;
        PowerWatcher powerWatcher;
        Timer saverTimer;   // keeps polling for the screen saver while the main timer is stopped

        [DllImport("user32.dll")] static extern bool SystemParametersInfo(int action, int param, out bool result, int winIni);
        const int SPI_GETSCREENSAVERRUNNING = 0x72;

        void CheckScreenSaver()
        {
            bool running;
            if (!SystemParametersInfo(SPI_GETSCREENSAVERRUNNING, 0, out running, 0)) return;
            if (running != screenSaver) { screenSaver = running; UpdateAsleep(); }
        }

        void UpdateAsleep()
        {
            if (timer == null) return;   // a power notification can arrive while starting up
            bool asleep = locked || suspended || displayOff || screenSaver;
            if (asleep && timer.Enabled)
            {
                FinishRuns();
                timer.Stop();
                ErrorLog.Debug("asleep (locked=" + locked + " suspended=" + suspended + " displayOff=" + displayOff + " saver=" + screenSaver + ")");
            }
            else if (!asleep && !timer.Enabled)
            {
                lastT = clock.Elapsed.TotalSeconds;
                timer.Start();
                ErrorLog.Debug("awake");
            }
        }

        // Ends Santa's trip and the plow run at once, as if they had arrived, and stops the sound. Called when
        // the overlay stops (screen saver, display off, lock) or frames stalled: otherwise they stay "on the
        // way" and the jingle keeps looping.
        void FinishRuns()
        {
            if (SantaActive || Plow.Active) ErrorLog.Debug("finish runs: santa=" + SantaActive + " plow=" + Plow.Active);
            if (SantaActive) { SantaActive = false; santaNext = 60 + R() * 120; }
            Sparks.Clear();
            Clumps.Clear();
            if (Plow.Active) { Plow.Active = false; Plow.Cooldown = 30; }
            audio.StopAll();
        }

        void OnSessionSwitch(object sender, SessionSwitchEventArgs e)
        {
            if (e.Reason == SessionSwitchReason.SessionLock) locked = true;
            else if (e.Reason == SessionSwitchReason.SessionUnlock) { locked = false; screenSaver = false; }   // back in the session: the saver is over
            invoker.BeginInvoke(new Action(UpdateAsleep));
        }

        void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
        {
            if (e.Mode == PowerModes.Suspend) suspended = true;
            else if (e.Mode == PowerModes.Resume) suspended = false;
            invoker.BeginInvoke(new Action(UpdateAsleep));
        }

        // ------------------------------------------------------------------ neighbouring screens
        // The screen directly to the left (dir < 0) or right (dir > 0) of l, edge to edge and overlapping vertically.
        public Layer Neighbor(Layer l, float dir)
        {
            var b = l.ScreenBounds;
            foreach (var o in layers)
            {
                if (o == l) continue;
                var ob = o.ScreenBounds;
                bool touches = dir > 0 ? Math.Abs(ob.Left - b.Right) < 2 : Math.Abs(ob.Right - b.Left) < 2;
                if (touches && ob.Top < b.Bottom && ob.Bottom > b.Top) return o;
            }
            return null;
        }

        public Controller()
        {
            invoker = new Control();
            var h = invoker.Handle;   // sikrer et vindueshåndtag til BeginInvoke

            if (Cfg.FirstRun == DateTime.MinValue) { Cfg.FirstRun = JuleClock.Today; Cfg.Save(); }


            // three tunes for Santa; each trip picks one at random
            jingles = new Voice[Synth.Tune.All.Length];
            for (int i = 0; i < jingles.Length; i++)
            {
                var tune = Synth.Tune.All[i];
                jingles[i] = audio.CreateVoice(() => Synth.Jingle(tune), true);
            }
            plowEngine = audio.CreateVoice(Synth.PlowEngine, true);
            plowScrape = audio.CreateVoice(Synth.PlowScrape, true);
            plowHorn = audio.CreateVoice(Synth.PlowHorn, false);
            WarmSounds();

            AppIcon = MakeIcon();
            BuildTray();
            BuildLayers();
            UpdateDaily(true);
            StartUpdater();
            SystemEvents.DisplaySettingsChanged += OnDisplayChanged;
            SystemEvents.SessionSwitch += OnSessionSwitch;
            SystemEvents.PowerModeChanged += OnPowerModeChanged;
            powerWatcher = new PowerWatcher(on => { displayOff = !on; UpdateAsleep(); });
            saverTimer = new Timer();
            saverTimer.Interval = 1000;
            saverTimer.Tick += (s, e) => { try { CheckScreenSaver(); } catch (Exception ex) { ErrorLog.Write(ex); } };
            saverTimer.Start();

            timer = new Timer();
            timer.Tick += Tick;
            UpdatePowerSave();
            lastT = clock.Elapsed.TotalSeconds;
            timer.Start();
        }

        float R() { return (float)Rnd.NextDouble(); }

        // ------------------------------------------------------------------ skærme
        void BuildLayers()
        {
            foreach (var l in layers) { l.Close(); l.Dispose(); }
            layers.Clear();
            // window-snow sizes come from macOS points, scaled by the primary screen's DPI;
            // docking or undocking can change it, and the piles' column width depends on it
            float u = Math.Max(1f, Program.DpiScaleAt(Screen.PrimaryScreen.Bounds));
            if (u != Ledge.U) { Ledge.U = u; Ledges.Clear(); LedgeList.Clear(); Clumps.Clear(); }
            foreach (var s in Screen.AllScreens)
            {
                if (!Cfg.AllScreens && !s.Primary) continue;
                var l = new Layer(this, s);
                layers.Add(l);
                l.Show();
            }
            if (SantaActive) SantaActive = false;
            Plow.Active = false;   // its screens are gone
            Plow.Members.Clear();
        }

        void OnDisplayChanged(object sender, EventArgs e)
        {
            invoker.BeginInvoke(new Action(BuildLayers));
        }

        // ------------------------------------------------------------------ hovedløkke
        // Any error skips just this frame and is logged; the overlay must never show crash dialogs.
        void Tick(object sender, EventArgs e)
        {
            try { TickCore(); }
            catch (Exception ex) { ErrorLog.Write(ex); }
        }

        int frameCount; double fpsWindowStart;

        void TickCore()
        {
            double now = clock.Elapsed.TotalSeconds;
            // frames stopped for a while (e.g. a screen saver we got no notice of): let Santa and the plow arrive
            if (now - lastT > 2 && lastT > 0) FinishRuns();
            float dt = (float)Math.Min(0.1, now - lastT);
            lastT = now;
            Time += dt;

            dayTimer -= dt;
            if (dayTimer <= 0)
            {
                dayTimer = 30;
                if (JuleClock.Today != lastDay) UpdateDaily(false);
            }

            powerTimer -= dt;
            if (powerTimer <= 0)
            {
                powerTimer = 5;
                UpdatePowerSave();
            }

            fsTimer -= dt;
            if (fsTimer <= 0)
            {
                // With snow on windows the scan runs 4 times a second, so piles follow moved windows and fall
                // soon after a minimize; every frame while a window with snow moves.
                fsTimer = !Cfg.WindowSnow ? 1 : (LedgeMoving() ? 0 : 0.25f);
                // Always detected: layers either pause or move the snow ground to the screen bottom.
                FullscreenRect = GetFullscreenRect();
                if (Cfg.WindowSnow || Ledges.Count > 0) UpdateLedges(ScanWindows());
            }

            topTimer -= dt;
            if (topTimer <= 0)
            {
                topTimer = 2;
                foreach (var l in layers) l.KeepOnTop();
            }

            UpdateWind(dt);
            UpdateSanta(dt);
            UpdateSparks(dt);
            UpdatePlow(dt);
            UpdateWindowSnow(dt);
            if (celebrateAt > 0 && Time >= celebrateAt) { celebrateAt = -1; SnowmanCelebrate(); }
            if (plowAt >= 0 && Time >= plowAt) { plowAt = -1; SendPlow(); }

            // Per screen, so a failing screen (e.g. mid display change) does not stop the others.
            foreach (var l in layers)
            {
                try { l.Frame(dt); }
                catch (Exception ex) { ErrorLog.Write(ex); }
            }

            UpdateSound(dt);
            UpdateFrameRate();

            // With JULE_DEBUG=1, log the actual frame rate every 5 seconds (for measurements).
            frameCount++;
            if (Time - fpsWindowStart >= 5)
            {
                ErrorLog.Debug("fps " + (frameCount / (Time - fpsWindowStart)).ToString("F1", System.Globalization.CultureInfo.InvariantCulture) + " (wanted " + DesiredFps + ", interval " + timer.Interval + " ms)");
                frameCount = 0;
                fpsWindowStart = Time;
            }
        }

        // ------------------------------------------------------------------ snow plow
        // One plow run in global coordinates, driving continuously across side-by-side screens (like Santa).
        // Each Layer scrapes its own snow and draws the truck where it is on that screen.
        public sealed class PlowRun
        {
            public bool Active;
            public float GX, Dir = 1, NextDir = 1, Wheel, Pushed, Cooldown = 20;
            public float MinX, MaxX;
            public readonly HashSet<Layer> Members = new HashSet<Layer>();
        }
        public readonly PlowRun Plow = new PlowRun();
        public const float PlowSpeed = 170f, PlowScale = 1.15f;

        // Sends the plow out now (menu, --sneplov), starting from the primary screen's row of screens.
        public void SendPlow()
        {
            Layer start = null;
            foreach (var l in layers) if (l.IsPrimary) start = l;
            if (start == null && layers.Count > 0) start = layers[0];
            if (start != null) StartPlow(start);
        }

        void StartPlow(Layer start)
        {
            if (Plow.Active) return;
            // all screens joined edge to edge with the starting screen, left and right
            var row = new List<Layer> { start };
            for (bool grew = true; grew; )
            {
                grew = false;
                foreach (var l in layers)
                {
                    if (row.Contains(l)) continue;
                    foreach (var m in row)
                        if (Neighbor(m, -1) == l || Neighbor(m, 1) == l) { row.Add(l); grew = true; break; }
                    if (grew) break;
                }
            }
            Plow.Members.Clear();
            Plow.MinX = float.MaxValue; Plow.MaxX = float.MinValue;
            foreach (var l in row)
            {
                Plow.Members.Add(l);
                Plow.MinX = Math.Min(Plow.MinX, l.ScreenBounds.Left);
                Plow.MaxX = Math.Max(Plow.MaxX, l.ScreenBounds.Right);
            }
            Plow.Dir = Plow.NextDir;
            Plow.NextDir = -Plow.NextDir;
            float sc = start.S * PlowScale;
            Plow.GX = Plow.Dir > 0 ? Plow.MinX - 110 * sc : Plow.MaxX + 110 * sc;
            Plow.Pushed = 0;
            Plow.Active = true;
            ErrorLog.Debug("plow start dir=" + Plow.Dir + " from " + Plow.MinX + " to " + Plow.MaxX + " screens=" + row.Count);
        }

        void UpdatePlow(float dt)
        {
            if (!Plow.Active)
            {
                Plow.Cooldown -= dt;
                if (Cfg.Plow && Plow.Cooldown <= 0)
                    foreach (var l in layers)
                        if (l.HeapAverage > 18 * l.S * 0.75f) { StartPlow(l); break; }
                return;
            }
            // speed and size follow the screen the truck is on
            Layer here = null;
            foreach (var l in Plow.Members)
            {
                if (here == null) here = l;
                if (Plow.GX >= l.ScreenBounds.Left && Plow.GX < l.ScreenBounds.Right) { here = l; break; }
            }
            float s = here != null ? here.S : 1;
            Plow.GX += Plow.Dir * PlowSpeed * s * dt;
            Plow.Wheel += PlowSpeed * s * dt / (10 * s * PlowScale);
            if ((Plow.Dir > 0 && Plow.GX > Plow.MaxX + 260 * s * PlowScale) || (Plow.Dir < 0 && Plow.GX < Plow.MinX - 260 * s * PlowScale))
            {
                Plow.Active = false;
                Plow.Cooldown = 30;
                ErrorLog.Debug("plow done");
            }
        }

        // ------------------------------------------------------------------ sound
        readonly AudioHub audio = new AudioHub();
        readonly Voice[] jingles;
        readonly Voice plowEngine, plowScrape, plowHorn;
        int jingleIndex;
        bool hornedThisRun;

        float Volume { get { return new[] { 0.15f, 0.35f, 0.6f }[Math.Max(0, Math.Min(2, Cfg.SoundLevel))]; } }
        bool SoundMuted { get { return Cfg.PauseFullscreen && !FullscreenRect.IsEmpty; } }

        // Synthesizes the enabled sounds in the background ahead of time, so they are ready when needed.
        void WarmSounds()
        {
            if (Cfg.Sound) foreach (var j in jingles) j.Warm();
            if (Cfg.PlowSound) { plowEngine.Warm(); plowScrape.Warm(); plowHorn.Warm(); }
        }

        // Pans each sound with what makes it (Santa, the plow) across all screens and fades it at the edges.
        void UpdateSound(float dt)
        {
            {
                float span = Math.Max(1, santaMaxX - santaMinX);
                float margin = 330 * SantaScale;
                float presence = Math.Max(0, Math.Min(1, Math.Min(SantaX - (santaMinX - margin), (santaMaxX + margin) - SantaX) / margin));
                bool on = SantaActive && Cfg.Sound && !SoundMuted;
                // only this trip's tune plays; any other one still fading out keeps being updated until it is silent
                for (int i = 0; i < jingles.Length; i++)
                    if ((Cfg.Sound && i == jingleIndex) || jingles[i].Playing)
                        jingles[i].Update(on && i == jingleIndex ? presence * Volume : 0, (SantaX - santaMinX) / span * 2 - 1, dt);
            }
            if (Cfg.PlowSound || plowEngine.Playing || plowScrape.Playing)
            {
                float span = Math.Max(1, Plow.MaxX - Plow.MinX);
                const float margin = 300;
                float presence = Math.Max(0, Math.Min(1, Math.Min(Plow.GX - (Plow.MinX - margin), (Plow.MaxX + margin) - Plow.GX) / margin));
                float pan = (Plow.GX - Plow.MinX) / span * 2 - 1;
                bool on = Plow.Active && Cfg.PlowSound && !SoundMuted;
                plowEngine.Update(on ? presence * Volume * 0.8f : 0, pan, dt);
                // scraping gets louder with the amount of snow in front of the blade
                float load = (float)Math.Min(1, Math.Sqrt(Plow.Pushed / 2000));
                plowScrape.Update(on ? presence * Volume * (0.15f + 0.85f * load) : 0, pan, dt);
                if (on && !hornedThisRun && presence > 0.6f) { hornedThisRun = true; plowHorn.PlayOnce(Volume, pan); }
            }
            if (!Plow.Active) hornedThisRun = false;
            audio.IdleCheck(Time);
        }

        void UpdateWind(float dt)
        {
            windTimer -= dt;
            if (windTimer <= 0)
            {
                windTimer = 3 + R() * 6;
                bool storm = EffectiveSnowLevel == 2;
                windTarget = (R() * 2 - 1) * (storm ? 140 : 30) + (storm ? 60 : 0);
            }
            Wind += (windTarget - Wind) * Math.Min(1f, dt * 0.5f);
        }

        Rectangle GetFullscreenRect()
        {
            IntPtr fg = GetForegroundWindow();
            if (fg == IntPtr.Zero) return Rectangle.Empty;
            var sb = new StringBuilder(256);
            GetClassName(fg, sb, 256);
            string c = sb.ToString();
            if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd" || c == "Shell_SecondaryTrayWnd") return Rectangle.Empty;
            RECT r;
            if (!GetWindowRect(fg, out r)) return Rectangle.Empty;
            return Rectangle.FromLTRB(r.Left, r.Top, r.Right, r.Bottom);
        }

        // ------------------------------------------------------------------ julemanden
        public void LaunchSanta()
        {
            if (SantaActive || layers.Count == 0) return;
            var target = layers[Rnd.Next(layers.Count)];
            var b = target.ScreenBounds;
            // Size and pace are two separate things, each drawn per trip: ±15 % in size. The speed never follows the size.
            SantaScale = target.S * (0.85f + R() * 0.3f);
            SantaY0 = b.Y + b.Height * (0.12f + R() * 0.25f);

            // flyv over alle skærme der ligger i samme højde
            santaMinX = b.Left; santaMaxX = b.Right;
            foreach (var l in layers)
            {
                var lb = l.ScreenBounds;
                if (SantaY0 >= lb.Top && SantaY0 < lb.Bottom)
                {
                    santaMinX = Math.Min(santaMinX, lb.Left);
                    santaMaxX = Math.Max(santaMaxX, lb.Right);
                }
            }
            SantaDir = R() < 0.5f ? 1 : -1;
            SantaX = SantaDir > 0 ? santaMinX - 420 * SantaScale : santaMaxX + 420 * SantaScale;
            // ±10% speed per trip, and the tune plays at the same rate (a little faster and higher, or slower and lower)
            float pace = 0.9f + R() * 0.2f;
            jingleIndex = Rnd.Next(jingles.Length);
            jingles[jingleIndex].Rate = pace;
            SantaSpeed = 230 * pace * target.S * (santaMaxX - santaMinX > b.Width * 1.5f ? 1.6f : 1f);
            SantaPhase = 0;
            SantaActive = true;
        }

        void UpdateSanta(float dt)
        {
            if (!SantaActive)
            {
                if (Cfg.Santa) { santaNext -= dt; if (santaNext <= 0) { LaunchSanta(); santaNext = 60 + R() * 120; } }
                return;
            }
            SantaX += SantaDir * SantaSpeed * dt;
            SantaPhase += dt;
            sparkAcc += dt * 45;
            while (sparkAcc >= 1)
            {
                sparkAcc -= 1;
                var sp = new Spark();
                sp.X = SantaX - SantaDir * 90 * SantaScale + (R() - 0.5f) * 10 * SantaScale;
                sp.Y = SantaY + (R() - 0.3f) * 20 * SantaScale;
                sp.VX = -SantaDir * (10 + R() * 30) * SantaScale;
                sp.VY = (R() - 0.5f) * 20 * SantaScale;
                sp.Max = sp.Life = 0.8f + R() * 1.4f;
                sp.Size = (1.5f + R() * 3f) * SantaScale;
                sp.Gold = R() < 0.6f;
                Sparks.Add(sp);
            }
            if ((SantaDir > 0 && SantaX > santaMaxX + 450 * SantaScale) || (SantaDir < 0 && SantaX < santaMinX - 450 * SantaScale))
            {
                SantaActive = false;
                santaNext = 60 + R() * 120;
            }
        }

        void UpdateSparks(float dt)
        {
            for (int i = Sparks.Count - 1; i >= 0; i--)
            {
                var sp = Sparks[i];
                sp.Life -= dt;
                if (sp.Life <= 0) { Sparks.RemoveAt(i); continue; }
                sp.X += sp.VX * dt;
                sp.Y += sp.VY * dt;
                sp.VY += 12 * SantaScale * dt;
            }
        }

        // ------------------------------------------------------------------ effekter (bruges af julekalenderen)
        public void TriggerEffect(int effect)
        {
            switch (effect)
            {
                case 1: LaunchSanta(); break;
                case 2: StormUntil = Time + 25; break;
                case 3: NisseParty(); break;
                case 4: StarShower(); break;
                case 5: LaunchSanta(); StarShower(); NisseParty(); break;
            }
        }

        // Schedules a plow run a number of seconds from now (used by the --sneplov=N test flag).
        public void SendPlowAfter(float seconds)
        {
            plowAt = Time + (seconds > 0 ? seconds : 0);   // also covers 0, negative and NaN
        }
        double plowAt = -1;

        void NisseParty()
        {
            foreach (var l in layers) l.NisseWave(6f);
        }

        void StarShower()
        {
            foreach (var l in layers)
            {
                var b = l.ScreenBounds;
                for (int i = 0; i < 90; i++)
                {
                    var sp = new Spark();
                    sp.X = b.X + R() * b.Width;
                    sp.Y = b.Y - R() * b.Height * 0.8f;
                    sp.VX = (R() - 0.5f) * 20 * l.S;
                    sp.VY = (140 + R() * 140) * l.S;
                    sp.Max = sp.Life = 5 + R() * 3;
                    sp.Size = (3 + R() * 4) * l.S;
                    sp.Gold = R() < 0.8f;
                    sp.Star = true;
                    Sparks.Add(sp);
                }
            }
        }

        void SnowmanCelebrate()
        {
            if (!Cfg.Snowman) return;
            foreach (var l in layers)
            {
                if (!l.IsPrimary || l.SnowmanPos.IsEmpty) continue;
                var p = l.SnowmanPos;
                float s = l.S;
                for (int i = 0; i < 70; i++)
                {
                    var sp = new Spark();
                    sp.X = p.X + (R() - 0.5f) * 90 * s;
                    sp.Y = p.Y - R() * 120 * s;
                    sp.VX = (R() - 0.5f) * 60 * s;
                    sp.VY = -(20 + R() * 60) * s;
                    sp.Max = sp.Life = 1.5f + R() * 1.5f;
                    sp.Size = (2 + R() * 3) * s;
                    sp.Gold = R() < 0.6f;
                    Sparks.Add(sp);
                }
            }
        }

        // ------------------------------------------------------------------ daglige begivenheder
        void UpdateDaily(bool startup)
        {
            var today = JuleClock.Today;
            lastDay = today;
            CalendarContent.SyncYear(Cfg, today);

            SnowmanStage = Math.Max(1, Math.Min(SnowmanMaxStage, (today - Cfg.FirstRun).Days + 1));

            string title = null, msg = null;
            balloonOpensCalendar = false;
            if (SnowmanStage > Cfg.SnowmanSeenStage)
            {
                if (Cfg.SnowmanSeenStage > 0 && Cfg.Snowman)
                {
                    title = "Snemanden vokser!";
                    msg = "Nisserne har bygget videre på snemanden. I dag fik den " + SnowmanSteps[SnowmanStage - 1];
                    celebrateAt = Time + 2;
                }
                Cfg.SnowmanSeenStage = SnowmanStage;
                Cfg.Save();
            }
            if (today.Month == 12 && today.Day <= 24 && !Cfg.OpenedDoors.Contains(today.Day) && Cfg.LastDoorNotice != today)
            {
                title = "Dagens låge er klar!";
                msg = "Låge " + today.Day + " i julekalenderen venter på dig. Klik her for at åbne kalenderen.";
                balloonOpensCalendar = true;
                Cfg.LastDoorNotice = today;
                Cfg.Save();
            }
            if (msg == null && startup)
            {
                title = "Jule-hygge er tændt";
                msg = "Højreklik på snefnug-ikonet ved uret for indstillinger og julekalender. Dobbeltklik for at kalde på julemanden!";
            }
            if (msg != null) tray.ShowBalloonTip(6000, title, msg, ToolTipIcon.None);
        }

        public void ShowCalendar()
        {
            if (calendar == null || calendar.IsDisposed) calendar = new CalendarForm(this);
            calendar.Show();
            if (calendar.WindowState == FormWindowState.Minimized) calendar.WindowState = FormWindowState.Normal;
            // kort TopMost-trick, så vinduet også kommer forrest når Windows nægter at give fokus
            calendar.TopMost = true;
            calendar.Activate();
            calendar.TopMost = false;
        }

        // ------------------------------------------------------------------ bakkeikon og menu
        void BuildTray()
        {
            tray = new NotifyIcon();
            tray.Icon = AppIcon;
            tray.Text = "Jule-hygge";
            tray.Visible = true;
            tray.DoubleClick += (s, e) => LaunchSanta();
            tray.BalloonTipClicked += (s, e) => { if (balloonOpensCalendar) ShowCalendar(); };

            var menu = new ContextMenuStrip();
            var cal = new ToolStripMenuItem("Julekalender...");
            cal.Font = new Font(cal.Font, FontStyle.Bold);
            cal.Click += (s, e) => ShowCalendar();
            menu.Items.Add(cal);
            countdownItem = new ToolStripMenuItem(Countdown());
            countdownItem.Enabled = false;
            menu.Items.Add(countdownItem);
            menu.Items.Add(new ToolStripSeparator());

            menu.Items.Add(Toggle("Snevejr", () => Cfg.Snow, v => Cfg.Snow = v));
            var level = new ToolStripMenuItem("Snemængde");
            string[] names = { "Let sne", "Normal", "Snestorm", "Skiftende vejr" };
            for (int i = 0; i < names.Length; i++)
            {
                int li = i;
                var it = new ToolStripMenuItem(names[i]);
                it.Checked = Cfg.SnowLevel == li;
                it.Click += (s, e) =>
                {
                    Cfg.SnowLevel = li;
                    foreach (ToolStripMenuItem o in level.DropDownItems) o.Checked = o == it;
                    Cfg.Save();
                };
                level.DropDownItems.Add(it);
            }
            menu.Items.Add(level);
            menu.Items.Add(Toggle("Sne på proceslinjen", () => Cfg.SnowGround, v => Cfg.SnowGround = v));
            menu.Items.Add(Toggle("Sne på vinduerne", () => Cfg.WindowSnow, v => Cfg.WindowSnow = v));
            snowmanItem = Toggle("Snemand", () => Cfg.Snowman, v => Cfg.Snowman = v);
            menu.Items.Add(snowmanItem);
            menu.Items.Add(new ToolStripSeparator());

            menu.Items.Add(Toggle("Julemanden", () => Cfg.Santa, v => Cfg.Santa = v));
            var send = new ToolStripMenuItem("Send julemanden afsted nu!");
            send.Click += (s, e) => LaunchSanta();
            menu.Items.Add(send);
            menu.Items.Add(new ToolStripSeparator());

            menu.Items.Add(Toggle("Sneplov rydder proceslinjen", () => Cfg.Plow, v => Cfg.Plow = v));
            var plow = new ToolStripMenuItem("Send sneploven ud nu!");
            plow.Click += (s, e) => SendPlow();
            menu.Items.Add(plow);
            menu.Items.Add(new ToolStripSeparator());

            // Sound is off by default; each source is switched on separately.
            menu.Items.Add(Toggle("Lyd: bjælder og jingle når julemanden flyver", () => Cfg.Sound, v => { Cfg.Sound = v; WarmSounds(); }));
            menu.Items.Add(Toggle("Lyd: motor, skraben og horn fra sneploven", () => Cfg.PlowSound, v => { Cfg.PlowSound = v; WarmSounds(); }));
            menu.Items.Add(Choice("Lydstyrke", new[] { "Lav", "Middel", "Høj" }, new[] { 0, 1, 2 },
                () => Cfg.SoundLevel, v => Cfg.SoundLevel = v));
            menu.Items.Add(new ToolStripSeparator());

            menu.Items.Add(Toggle("Nisser", () => Cfg.Nisser, v => Cfg.Nisser = v));
            var count = new ToolStripMenuItem("Antal nisser pr. skærm");
            foreach (int c in new[] { 1, 2, 3, 5, 8, 12 })
            {
                int ci = c;
                var it = new ToolStripMenuItem(c.ToString());
                it.Checked = Cfg.NisseCount == ci;
                it.Click += (s, e) =>
                {
                    Cfg.NisseCount = ci;
                    foreach (ToolStripMenuItem o in count.DropDownItems) o.Checked = o == it;
                    Cfg.Save();
                };
                count.DropDownItems.Add(it);
            }
            menu.Items.Add(count);
            menu.Items.Add(new ToolStripSeparator());

            var power = new ToolStripMenuItem("Strømspare");
            string[] powerNames = { "Fra - normal billedfrekvens", "Til - færre billeder/s, stille blæser", "Kun når den bærbare kører på batteri" };
            int[] powerValues = { 1, 2, 0 };
            foreach (int pv in powerValues)
            {
                int pvi = pv;
                var it = new ToolStripMenuItem(powerNames[pv]);
                it.Checked = Cfg.PowerSave == pvi;
                it.Click += (s, e) =>
                {
                    Cfg.PowerSave = pvi;
                    foreach (ToolStripMenuItem o in power.DropDownItems) o.Checked = o == it;
                    Cfg.Save();
                    UpdatePowerSave();
                };
                power.DropDownItems.Add(it);
            }
            menu.Items.Add(power);
            menu.Items.Add(Choice("Billedfrekvens",
                new[] { "12 billeder/s - mindst strøm", "20 billeder/s - normal", "30 billeder/s - glattere sne", "60 billeder/s - mest strøm (når sjældent helt op på Windows)" },
                new[] { 12, 20, 30, 60 }, () => Cfg.FrameRate, v => { Cfg.FrameRate = v; UpdateFrameRate(); }));
            menu.Items.Add(Toggle("Julelys", () => Cfg.Lights, v => Cfg.Lights = v));
            menu.Items.Add(Toggle("Vis på alle skærme", () => Cfg.AllScreens, v => { Cfg.AllScreens = v; BuildLayers(); }));
            menu.Items.Add(Toggle("Pause ved fuldskærm (spil/film)", () => Cfg.PauseFullscreen, v => Cfg.PauseFullscreen = v));
            // The checkmark always mirrors the registry (re-read when the menu opens), and a failed
            // write (e.g. locked down by policy) just leaves the checkmark showing the real state.
            var autostart = new ToolStripMenuItem("Start med Windows");
            autostart.Checked = GetAutostart();
            autostart.CheckOnClick = true;
            autostart.CheckedChanged += (s, e) =>
            {
                if (syncingMenu) return;
                SetAutostart(autostart.Checked);
                syncingMenu = true;
                autostart.Checked = GetAutostart();
                syncingMenu = false;
            };
            menu.Items.Add(autostart);
            menu.Items.Add(new ToolStripSeparator());

            var version = new ToolStripMenuItem(Updater.IsReleaseBuild ? "Version " + Updater.Display(Updater.Current) : "Udviklerversion (opdaterer ikke)");
            version.Enabled = false;
            menu.Items.Add(version);
            if (Updater.IsReleaseBuild)
            {
                menu.Items.Add(Toggle("Opdatér automatisk", () => Cfg.AutoUpdate, v => Cfg.AutoUpdate = v));
                var checkNow = new ToolStripMenuItem("Søg efter opdatering nu");
                checkNow.Click += (s, e) => CheckForUpdate(true);
                menu.Items.Add(checkNow);
            }
            menu.Items.Add(new ToolStripSeparator());

            var exit = new ToolStripMenuItem("Afslut");
            exit.Click += (s, e) => Exit();
            menu.Items.Add(exit);

            menu.Opening += (s, e) =>
            {
                countdownItem.Text = Countdown();
                snowmanItem.Text = "Snemand (trin " + SnowmanStage + " af " + SnowmanMaxStage + ")";
                syncingMenu = true;
                autostart.Checked = GetAutostart();
                syncingMenu = false;
            };
            tray.ContextMenuStrip = menu;
        }

        ToolStripMenuItem Toggle(string text, Func<bool> get, Action<bool> set)
        {
            var item = new ToolStripMenuItem(text);
            item.Checked = get();
            item.CheckOnClick = true;
            item.CheckedChanged += (s, e) => { set(item.Checked); Cfg.Save(); };
            return item;
        }

        // A submenu where exactly one option is checked.
        ToolStripMenuItem Choice(string text, string[] names, int[] values, Func<int> get, Action<int> set)
        {
            var parent = new ToolStripMenuItem(text);
            for (int i = 0; i < names.Length; i++)
            {
                int v = values[i];
                var it = new ToolStripMenuItem(names[i]);
                it.Checked = get() == v;
                it.Click += (s, e) =>
                {
                    set(v);
                    foreach (ToolStripMenuItem o in parent.DropDownItems) o.Checked = o == it;
                    Cfg.Save();
                };
                parent.DropDownItems.Add(it);
            }
            return parent;
        }

        void Exit()
        {
            timer.Stop();
            audio.StopAll();
            SystemEvents.DisplaySettingsChanged -= OnDisplayChanged;
            SystemEvents.SessionSwitch -= OnSessionSwitch;
            SystemEvents.PowerModeChanged -= OnPowerModeChanged;
            if (powerWatcher != null) powerWatcher.Dispose();
            if (saverTimer != null) { saverTimer.Stop(); saverTimer.Dispose(); }
            if (updateTimer != null) { updateTimer.Stop(); updateTimer.Dispose(); }
            if (calendar != null && !calendar.IsDisposed) calendar.Close();
            foreach (var l in layers) { l.Close(); l.Dispose(); }
            layers.Clear();
            tray.Visible = false;
            tray.Dispose();
            Cfg.Save();
            ExitThread();
        }

        static string Countdown()
        {
            var today = JuleClock.Today;
            var eve = new DateTime(today.Year, 12, 24);
            if (today > eve) eve = eve.AddYears(1);
            int d = (int)(eve - today).TotalDays;
            if (d == 0) return "★ Glædelig jul! ★";
            if (d == 1) return "★ 1 dag til juleaften ★";
            return "★ " + d + " dage til juleaften ★";
        }

        bool syncingMenu;

        // ------------------------------------------------------------------ automatic update
        // A release build checks GitHub 1 minute after start and then every 6 hours. A newer release is
        // downloaded, checked and swapped in, and the app restarts into it (see Updater).
        Timer updateTimer;
        bool updateRunning;

        void StartUpdater()
        {
            if (!Updater.IsReleaseBuild) return;
            string now = Updater.Display(Updater.Current);
            if (Cfg.LastVersion != now)
            {
                if (Cfg.LastVersion != "")
                {
                    balloonOpensCalendar = false;
                    tray.ShowBalloonTip(6000, "Jule-hygge er opdateret", "Du kører nu version " + now + ".", ToolTipIcon.None);
                }
                Cfg.LastVersion = now;
                Cfg.Save();
            }
            updateTimer = new Timer();
            updateTimer.Interval = 60 * 1000;
            updateTimer.Tick += (s, e) =>
            {
                updateTimer.Interval = 6 * 60 * 60 * 1000;
                if (Cfg.AutoUpdate) CheckForUpdate(false);
            };
            updateTimer.Start();
        }

        // manual = the user asked from the menu, so report every outcome with a balloon.
        void CheckForUpdate(bool manual)
        {
            if (updateRunning) return;
            updateRunning = true;
            System.Threading.ThreadPool.QueueUserWorkItem(_ =>
            {
                var r = Updater.CheckAndDownload();
                try { invoker.BeginInvoke(new Action(() => FinishUpdate(r, manual))); }
                catch (InvalidOperationException) { }   // shutting down
            });
        }

        void FinishUpdate(Updater.Result r, bool manual)
        {
            updateRunning = false;
            balloonOpensCalendar = false;
            if (r.Error != null)
            {
                ErrorLog.Write("update failed: " + r.Error);
                if (manual) tray.ShowBalloonTip(6000, "Opdatering", "Kunne ikke opdatere: " + r.Error, ToolTipIcon.None);
                return;
            }
            if (r.NewExe == null)
            {
                if (manual) tray.ShowBalloonTip(4000, "Opdatering", "Du har den nyeste version (" + Updater.Display(Updater.Current) + ").", ToolTipIcon.None);
                return;
            }
            try { Updater.Install(r.NewExe); }
            catch (Exception ex)
            {
                ErrorLog.Write(ex);
                if (manual) tray.ShowBalloonTip(6000, "Opdatering", "Kunne ikke installere version " + Updater.Display(r.Version) + ": " + ex.Message, ToolTipIcon.None);
                return;
            }
            ErrorLog.Debug("update: installed " + Updater.Display(r.Version) + ", restarting");
            // Under the supervisor, a special exit code makes it start the new exe. Without one, start it here;
            // it waits for this process to let go of the single-instance mutex.
            if (Program.IsChild) Environment.ExitCode = Updater.RestartExitCode;
            else
            {
                try
                {
                    var psi = new System.Diagnostics.ProcessStartInfo(Program.ExePath);
                    psi.UseShellExecute = false;
                    psi.EnvironmentVariables["JULE_AFTER_UPDATE"] = "1";
                    System.Diagnostics.Process.Start(psi);
                }
                catch (Exception ex) { ErrorLog.Write(ex); }
            }
            Exit();
        }

        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        static string AutostartCommand { get { return "\"" + Application.ExecutablePath + "\""; } }

        // True only if the Run entry points at this exe; an entry for a moved or old copy counts as off.
        static bool GetAutostart()
        {
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(RunKey))
                    return k != null && string.Equals(k.GetValue("JuleHygge") as string, AutostartCommand, StringComparison.OrdinalIgnoreCase);
            }
            catch (Exception ex) { ErrorLog.Write(ex); return false; }
        }

        static void SetAutostart(bool on)
        {
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(RunKey, true))
                {
                    if (k == null) return;
                    if (on) k.SetValue("JuleHygge", AutostartCommand);
                    else k.DeleteValue("JuleHygge", false);
                }
            }
            catch (Exception ex) { ErrorLog.Write(ex); }
        }

        static Icon MakeIcon()
        {
            var bmp = new Bitmap(32, 32, PixelFormat.Format32bppArgb);
            using (var gg = Graphics.FromImage(bmp))
            {
                gg.SmoothingMode = SmoothingMode.AntiAlias;
                gg.Clear(Color.Transparent);
                using (var b = new SolidBrush(Color.FromArgb(200, 25, 35))) gg.FillEllipse(b, 1, 1, 30, 30);
                using (var p = new Pen(Color.White, 2.2f))
                {
                    p.StartCap = p.EndCap = LineCap.Round;
                    for (int k = 0; k < 3; k++)
                    {
                        double a = k * Math.PI / 3 + Math.PI / 2;
                        float dx = (float)Math.Cos(a) * 11, dy = (float)Math.Sin(a) * 11;
                        gg.DrawLine(p, 16 - dx, 16 - dy, 16 + dx, 16 + dy);
                        for (int sgn = -1; sgn <= 1; sgn += 2)
                        {
                            float ex = 16 + sgn * dx * 0.65f, ey = 16 + sgn * dy * 0.65f;
                            double a1 = a + (sgn > 0 ? 0 : Math.PI);
                            for (int side = -1; side <= 1; side += 2)
                            {
                                double ba = a1 + side * 2.4;
                                gg.DrawLine(p, ex, ey, ex + (float)Math.Cos(ba) * 4, ey + (float)Math.Sin(ba) * 4);
                            }
                        }
                    }
                }
            }
            return Icon.FromHandle(bmp.GetHicon());
        }
    }
}
