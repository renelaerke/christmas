using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace JuleHygge
{
    // Synthesized sound effects (the project has no sound files): Santa's sleigh bells with one of three
    // public-domain tunes (see Synth.Tune), and the snow plow's engine,
    // scraping and horn. Ported from macos/Sources/JuleHygge/Sound.swift.
    //
    // Playback uses the waveOut API that ships with Windows. Mixing runs on a background thread that only
    // exists while something is audible, so sound costs nothing the rest of the time.
    sealed class AudioHub
    {
        public const int SampleRate = 44100;
        const int BufferFrames = 2048;   // ~46 ms per buffer
        // How long after it is mixed a sound is heard: the buffers queued ahead of it (the device's own delay is
        // not known and not counted).
        public const double Latency = (double)BufferCount * BufferFrames / SampleRate;
        const int BufferCount = 4;       // ~186 ms queued, so a busy UI thread never causes gaps

        internal readonly object Gate = new object();
        readonly List<Voice> voices = new List<Voice>();
        Thread thread;
        volatile bool stopRequested;
        bool running;
        double quietSince = -1;

        public Voice CreateVoice(Func<float[]> make, bool loops)
        {
            var v = new Voice(this, make, loops);
            lock (Gate) voices.Add(v);
            return v;
        }

        internal void EnsureRunning()
        {
            if (running) return;
            stopRequested = false;
            running = true;
            thread = new Thread(Run);
            thread.IsBackground = true;
            thread.Name = "JuleHygge audio";
            thread.Priority = ThreadPriority.AboveNormal;
            thread.Start();
        }

        // Called once per frame on the UI thread: stops the audio thread after a second of silence.
        public void IdleCheck(double now)
        {
            if (!running) return;
            bool any = false;
            lock (Gate) foreach (var v in voices) if (v.Playing) { any = true; break; }
            if (any) { quietSince = -1; return; }
            if (quietSince < 0) quietSince = now;
            if (now - quietSince > 1) StopAll();
        }

        public void StopAll()
        {
            lock (Gate) foreach (var v in voices) v.Halt();
            if (running)
            {
                stopRequested = true;
                if (thread != null) thread.Join(1000);
                thread = null;
                running = false;
            }
            quietSince = -1;
        }

        // ------------------------------------------------------------------ waveOut playback thread
        [StructLayout(LayoutKind.Sequential)]
        struct WAVEFORMATEX { public ushort wFormatTag, nChannels; public uint nSamplesPerSec, nAvgBytesPerSec; public ushort nBlockAlign, wBitsPerSample, cbSize; }
        [StructLayout(LayoutKind.Sequential)]
        struct WAVEHDR { public IntPtr lpData; public uint dwBufferLength, dwBytesRecorded; public IntPtr dwUser; public uint dwFlags, dwLoops; public IntPtr lpNext, reserved; }

        [DllImport("winmm.dll")] static extern int waveOutOpen(out IntPtr hwo, uint deviceId, ref WAVEFORMATEX fmt, IntPtr callback, IntPtr instance, uint flags);
        [DllImport("winmm.dll")] static extern int waveOutPrepareHeader(IntPtr hwo, IntPtr hdr, int size);
        [DllImport("winmm.dll")] static extern int waveOutUnprepareHeader(IntPtr hwo, IntPtr hdr, int size);
        [DllImport("winmm.dll")] static extern int waveOutWrite(IntPtr hwo, IntPtr hdr, int size);
        [DllImport("winmm.dll")] static extern int waveOutReset(IntPtr hwo);
        [DllImport("winmm.dll")] static extern int waveOutClose(IntPtr hwo);
        const uint WAVE_MAPPER = 0xFFFFFFFF, CALLBACK_EVENT = 0x50000;
        const int WHDR_DONE = 1;

        void Run()
        {
            IntPtr hwo = IntPtr.Zero;
            var done = new AutoResetEvent(false);
            var hdrs = new IntPtr[BufferCount];
            var data = new IntPtr[BufferCount];
            int hdrSize = Marshal.SizeOf(typeof(WAVEHDR));
            int flagsOffset = (int)Marshal.OffsetOf(typeof(WAVEHDR), "dwFlags");
            var mix = new short[BufferFrames * 2];
            var acc = new float[BufferFrames * 2];
            try
            {
                var fmt = new WAVEFORMATEX();
                fmt.wFormatTag = 1; fmt.nChannels = 2; fmt.nSamplesPerSec = SampleRate; fmt.wBitsPerSample = 16;
                fmt.nBlockAlign = 4; fmt.nAvgBytesPerSec = SampleRate * 4;
                int r = waveOutOpen(out hwo, WAVE_MAPPER, ref fmt, done.SafeWaitHandle.DangerousGetHandle(), IntPtr.Zero, CALLBACK_EVENT);
                if (r != 0) { hwo = IntPtr.Zero; ErrorLog.Write(new InvalidOperationException("waveOutOpen failed: " + r)); return; }
                ErrorLog.Debug("audio started");

                for (int i = 0; i < BufferCount; i++)
                {
                    data[i] = Marshal.AllocHGlobal(mix.Length * 2);
                    hdrs[i] = Marshal.AllocHGlobal(hdrSize);
                    var h = new WAVEHDR();
                    h.lpData = data[i];
                    h.dwBufferLength = (uint)(mix.Length * 2);
                    Marshal.StructureToPtr(h, hdrs[i], false);
                    waveOutPrepareHeader(hwo, hdrs[i], hdrSize);
                    Fill(acc, mix, data[i]);
                    waveOutWrite(hwo, hdrs[i], hdrSize);
                }
                while (!stopRequested)
                {
                    done.WaitOne(50);
                    for (int i = 0; i < BufferCount && !stopRequested; i++)
                    {
                        if ((Marshal.ReadInt32(hdrs[i], flagsOffset) & WHDR_DONE) == 0) continue;
                        Fill(acc, mix, data[i]);
                        waveOutWrite(hwo, hdrs[i], hdrSize);
                    }
                }
            }
            catch (Exception ex) { ErrorLog.Write(ex); }
            finally
            {
                if (hwo != IntPtr.Zero)
                {
                    waveOutReset(hwo);
                    for (int i = 0; i < BufferCount; i++) if (hdrs[i] != IntPtr.Zero) waveOutUnprepareHeader(hwo, hdrs[i], hdrSize);
                    waveOutClose(hwo);
                }
                for (int i = 0; i < BufferCount; i++)
                {
                    if (hdrs[i] != IntPtr.Zero) Marshal.FreeHGlobal(hdrs[i]);
                    if (data[i] != IntPtr.Zero) Marshal.FreeHGlobal(data[i]);
                }
                done.Dispose();
                ErrorLog.Debug("audio stopped");
            }
        }

        // Mixes all playing voices into one stereo 16-bit buffer.
        void Fill(float[] acc, short[] mix, IntPtr dest)
        {
            Array.Clear(acc, 0, acc.Length);
            lock (Gate) foreach (var v in voices) v.MixInto(acc, BufferFrames);
            for (int i = 0; i < acc.Length; i++)
            {
                float s = acc[i];
                if (s > 1) s = 1; else if (s < -1) s = -1;
                mix[i] = (short)(s * 32000);
            }
            Marshal.Copy(mix, 0, dest, mix.Length);
        }
    }

    // One sound: a looping buffer whose volume and pan follow something on screen, or a one-shot.
    sealed class Voice
    {
        readonly AudioHub hub;
        readonly Func<float[]> make;
        readonly bool loops;
        volatile float[] samples;
        int generating;
        double pos;   // fractional, so the voice can play faster or slower than recorded
        float gain, pan, appliedGain, appliedPan;
        volatile float rate = 1;

        public bool Playing { get; private set; }

        // How far into its buffer the voice is, in seconds (-1 while it is silent). What comes out of the speakers
        // lags the mixing by AudioHub.Latency, which is taken off here.
        public double Position
        {
            get
            {
                lock (hub.Gate)
                {
                    if (!Playing || samples == null || samples.Length == 0) return -1;
                    // (what is heard is what was mixed a few buffers ago)
                    double at = pos - AudioHub.Latency * AudioHub.SampleRate;
                    if (at < 0) at = loops ? at + samples.Length : 0;
                    return at / AudioHub.SampleRate;
                }
            }
        }

        // Playback speed, tempo and pitch together (like a tape): Santa's tune follows his pace.
        public float Rate { get { return rate; } set { rate = Math.Max(0.5f, Math.Min(2f, value)); } }

        internal Voice(AudioHub hub, Func<float[]> make, bool loops) { this.hub = hub; this.make = make; this.loops = loops; }

        // The sound is synthesized in the background the first time it is needed (it takes up to a second).
        public void Warm() { Prepare(); }

        bool Prepare()
        {
            if (samples != null) return true;
            if (Interlocked.Exchange(ref generating, 1) == 0)
                ThreadPool.QueueUserWorkItem(_ =>
                {
                    try { samples = make(); }
                    catch (Exception ex) { ErrorLog.Write(ex); }
                });
            return false;
        }

        // Looping voice: fades smoothly (about half a second) toward level (0..1) and pans to pan (-1..1).
        public void Update(float level, float newPan, float dt)
        {
            if (level > 0 && !Playing)
            {
                if (!Prepare()) return;
                lock (hub.Gate) { pos = 0; gain = 0; appliedGain = 0; pan = Clamp(newPan); appliedPan = pan; Playing = true; }
                hub.EnsureRunning();
            }
            if (!Playing) return;
            lock (hub.Gate)
            {
                gain += (level - gain) * Math.Min(1f, dt * 4);
                pan = Clamp(newPan);
            }
            if (level == 0 && gain < 0.003f) Halt();
        }

        // Plays the whole buffer once.
        public void PlayOnce(float level, float newPan)
        {
            if (!Prepare()) return;
            lock (hub.Gate) { pos = 0; gain = level; appliedGain = level; pan = Clamp(newPan); appliedPan = pan; Playing = true; }
            hub.EnsureRunning();
        }

        internal void Halt()
        {
            lock (hub.Gate) { Playing = false; gain = 0; appliedGain = 0; }
        }

        static float Clamp(float p) { return Math.Max(-1f, Math.Min(1f, p)); }

        // Audio thread, under hub.Gate: adds this voice to the stereo mix, ramping gain and pan across the
        // buffer so volume changes never click. Equal-power panning.
        internal void MixInto(float[] acc, int frames)
        {
            var s = samples;
            if (!Playing || s == null || s.Length == 0) return;
            float g0 = appliedGain, g1 = gain, p0 = appliedPan, p1 = pan;
            double step = rate;
            for (int i = 0; i < frames; i++)
            {
                float t = (float)i / frames;
                float g = g0 + (g1 - g0) * t;
                double a = ((p0 + (p1 - p0) * t) + 1) * Math.PI / 4;
                // linear interpolation between neighbouring samples (wrapping at the loop seam)
                int i0 = (int)pos;
                int i1 = i0 + 1 < s.Length ? i0 + 1 : (loops ? 0 : i0);
                float frac = (float)(pos - i0);
                float v = (s[i0] + (s[i1] - s[i0]) * frac) * g;
                acc[2 * i] += v * (float)Math.Cos(a);
                acc[2 * i + 1] += v * (float)Math.Sin(a);
                pos += step;
                if (pos >= s.Length)
                {
                    if (loops) pos -= s.Length;
                    else { Playing = false; break; }
                }
            }
            appliedGain = g1;
            appliedPan = p1;
        }
    }

    static class Synth
    {
        const double Rate = AudioHub.SampleRate;

        static float[] MakeBuffer(double seconds, Action<float[], int> fill)
        {
            int n = (int)(seconds * Rate);
            var output = new float[n];
            fill(output, n);
            Normalize(output);
            return output;
        }

        static void Normalize(float[] output)
        {
            float peak = 0;
            foreach (var x in output) peak = Math.Max(peak, Math.Abs(x));
            if (peak > 0.9f) { float k = 0.9f / peak; for (int i = 0; i < output.Length; i++) output[i] *= k; }
        }

        static double Noise(Random rng) { return rng.NextDouble() * 2 - 1; }

        // Diesel idle-ish rumble. Every frequency is a whole number of cycles per loop, so the loop is seamless.
        public static float[] PlowEngine()
        {
            return MakeBuffer(2.0, (output, n) =>
            {
                var rng = new Random(42);
                double lp = 0;
                double[][] harmonics = { new[] { 48.0, 1.0 }, new[] { 96.0, 0.5 }, new[] { 144.0, 0.3 }, new[] { 192.0, 0.18 }, new[] { 240.0, 0.1 } };
                for (int i = 0; i < n; i++)
                {
                    double t = i / Rate;
                    // firing pulses at 24 Hz shape a 48 Hz fundamental with harmonics
                    double firing = 0.6 + 0.4 * Math.Pow(Math.Max(0, Math.Sin(2 * Math.PI * 24 * t)), 3);
                    double v = 0;
                    foreach (var h in harmonics) v += h[1] * Math.Sin(2 * Math.PI * h[0] * t + h[0]);
                    lp += (Noise(rng) - lp) * 0.05;   // a little rattle: low-passed noise
                    v = v * firing + lp * 0.6;
                    output[i] = (float)(v * 0.2);
                }
            });
        }

        // Scraping snow: band-limited noise with a slow grainy texture.
        public static float[] PlowScrape()
        {
            return MakeBuffer(2.0, (output, n) =>
            {
                var rng = new Random(7);
                double lp = 0, hp = 0, prev = 0;
                for (int i = 0; i < n; i++)
                {
                    double t = i / Rate;
                    lp += (Noise(rng) - lp) * 0.35;    // tame the hiss
                    hp = 0.97 * (hp + lp - prev);      // remove the rumble
                    prev = lp;
                    double grain = 0.7 + 0.3 * Math.Sin(2 * Math.PI * 7 * t) * Math.Sin(2 * Math.PI * 3 * t);
                    output[i] = (float)(hp * grain * 0.5);
                }
                int fade = (int)(0.02 * Rate);
                for (int i = 0; i < fade; i++) { float k = (float)i / fade; output[i] *= k; output[n - 1 - i] *= k; }
            });
        }

        // The leaf collector's suction (autumn's form of the scraping): a rush of air through a wide hose, i.e.
        // noise shaped by a broad resonance and a hollow one from the hose, over the fan's steady whine.
        public static float[] LeafSuction()
        {
            const double len = 3.0;
            return MakeBuffer(len, (output, n) =>
            {
                var rng = new Random(77);
                int over = (int)(0.3 * Rate);
                var air = new float[n + over];
                // two resonators (state-variable band-passes): the rush around 900 Hz and the hose around 260 Hz
                double lowA = 0, bandA = 0, lowB = 0, bandB = 0;
                double fA = 2 * Math.Sin(Math.PI * 900 / Rate), fB = 2 * Math.Sin(Math.PI * 260 / Rate);
                for (int i = 0; i < n + over; i++)
                {
                    double t = i / Rate;
                    double white = Noise(rng);
                    double highA = white - lowA - 1.4 * bandA;
                    bandA += fA * highA;
                    lowA += fA * bandA;
                    double highB = white - lowB - 0.5 * bandB;
                    bandB += fB * highB;
                    lowB += fB * bandB;
                    // the air flutters a little as leaves pass through (whole cycles per loop)
                    double w = 2 * Math.PI * t / len;
                    double flutter = 0.85 + 0.15 * Math.Sin(w * 4) * Math.Sin(w * 11 + 0.7);
                    air[i] = (float)((bandA * 0.55 + bandB * 0.12) * flutter);
                }
                // made a little longer than the loop and cross-faded into its own start, so the loop has no seam
                for (int i = 0; i < over; i++)
                {
                    float k = (float)i / over;
                    air[i] = air[i] * k + air[n + i] * (1 - k);
                }
                for (int i = 0; i < n; i++)
                {
                    double t = i / Rate;
                    // the fan: a whine with a slow beat between two close tones (all whole cycles per loop)
                    double whine = 0.05 * Math.Sin(2 * Math.PI * 520 * t) + 0.035 * Math.Sin(2 * Math.PI * 524 * t)
                        + 0.02 * Math.Sin(2 * Math.PI * 1040 * t) + 0.012 * Math.Sin(2 * Math.PI * 1563 * t);
                    output[i] = air[i] * 0.8f + (float)(whine * 1.6);
                }
            });
        }

        // ------------------------------------------------------------------ the donkey cart (the Day of the Dead's plow)
        // The leg phases at which the drawn donkey's hooves land, as shares of a step cycle, with how loud each is
        // and its pitch: the near legs (phases 0 and pi in DrawPetalCart) louder than the far ones (1.2 and 1.2 + pi).
        static readonly double[,] HoofFalls = {
            { 0, 1, 1.0 }, { 1.2 / (2 * Math.PI), 0.7, 0.86 }, { 0.5, 0.95, 1.07 }, { 0.5 + 1.2 / (2 * Math.PI), 0.65, 0.9 } };

        // Adds make(k) (k = samples since the start) at `start`, wrapping round the end of a loop of n samples.
        static void AddWrapped(float[] output, int n, int start, int count, Func<int, double> make)
        {
            for (int k = 0; k < count; k++) output[((start + k) % n + n) % n] += (float)make(k);
        }

        // The donkey cart rolling: four hooves per step cycle (`cycle` seconds, Controller.DonkeyStepCycle) and the
        // wooden wheel creaking once a turn, over the low rumble of the wheel. The loop is 8 step cycles, which is
        // exactly 5 turns of the wheel (the legs swing 1.6 times per turn of it), so both repeat seamlessly.
        public static float[] DonkeyCart(double cycle)
        {
            cycle = Math.Max(0.2, Math.Min(2, cycle));
            double len = 8 * cycle;
            return MakeBuffer(len, (output, n) =>
            {
                var rng = new Random(1102);
                // hooves: a short hollow "tok" (two inharmonic modes of the hoof and the ground) with a soft thump
                // and a click of grit, each a little different
                for (int c = 0; c < 8; c++)
                    for (int f = 0; f < HoofFalls.GetLength(0); f++)
                    {
                        double t0 = (c + HoofFalls[f, 0]) * cycle + (rng.NextDouble() - 0.5) * 0.012;
                        double f1 = (760 + rng.NextDouble() * 160) * HoofFalls[f, 2], f2 = f1 * 2.37;
                        double loud = HoofFalls[f, 1] * (0.8 + 0.25 * rng.NextDouble());
                        AddWrapped(output, n, (int)(t0 * Rate), (int)(0.12 * Rate), k =>
                        {
                            double t = k / Rate;
                            double tok = 0.55 * Math.Sin(2 * Math.PI * f1 * t) * Math.Exp(-t / 0.016) + 0.22 * Math.Sin(2 * Math.PI * f2 * t) * Math.Exp(-t / 0.008);
                            double thump = 0.5 * Math.Sin(2 * Math.PI * 120 * t) * Math.Exp(-t / 0.035);
                            double grit = Noise(rng) * 0.35 * Math.Exp(-t / 0.003);
                            return loud * (tok + thump + grit) * 0.55;
                        });
                    }
                // the wheel creaks once a turn: stick-slip pulses, getting quicker, ringing a wooden resonance
                double turn = len / 5;
                for (int w = 0; w < 5; w++)
                {
                    double t0 = w * turn + turn * 0.35 + (rng.NextDouble() - 0.5) * 0.04;
                    double dur = 0.2 + rng.NextDouble() * 0.08, f0 = 150 + rng.NextDouble() * 40, rise = 1.5 + rng.NextDouble() * 0.3;
                    double res = 1250 + rng.NextDouble() * 300;
                    double rr = 0.9965, cw = 2 * rr * Math.Cos(2 * Math.PI * res / Rate);
                    double y1 = 0, y2 = 0, phase = 0;
                    AddWrapped(output, n, (int)(t0 * Rate), (int)((dur + 0.06) * Rate), k =>
                    {
                        double t = k / Rate, x = 0;
                        if (t < dur)
                        {
                            phase += f0 * (1 + (rise - 1) * t / dur) / Rate;
                            if (phase >= 1) { phase -= 1; x = 1; }
                        }
                        double y = cw * y1 - rr * rr * y2 + x;
                        y2 = y1; y1 = y;
                        double env = t < dur ? Math.Sin(Math.PI * Math.Min(1, t / dur)) : 1;
                        return y * env * 0.012;
                    });
                }
                // the rumble of the wheel on the ground: low-passed noise, cross-faded over the loop's seam
                int over = (int)(0.2 * Rate);
                double lp = 0, lp2 = 0;
                var rumble = new double[n + over];
                for (int i = 0; i < n + over; i++)
                {
                    lp += (Noise(rng) - lp) * 0.02;
                    lp2 += (lp - lp2) * 0.05;
                    rumble[i] = lp2;
                }
                for (int i = 0; i < over; i++) { double k = (double)i / over; rumble[i] = rumble[i] * k + rumble[n + i] * (1 - k); }
                for (int i = 0; i < n; i++) output[i] += (float)(rumble[i] * 0.2);
            });
        }

        // The calaca's broom: a swish on each forward stroke (the broom swings twice per step cycle), with a
        // rustle of petals. Same loop length as DonkeyCart, so the two keep the same pace.
        public static float[] BroomSweep(double cycle)
        {
            cycle = Math.Max(0.2, Math.Min(2, cycle));
            return MakeBuffer(8 * cycle, (output, n) =>
            {
                var rng = new Random(2011);
                for (int s = 0; s < 16; s++)
                {
                    double t0 = (s * 0.5 + 0.12) * cycle + (rng.NextDouble() - 0.5) * 0.01;
                    double dur = cycle * 0.3, loud = 0.8 + 0.3 * rng.NextDouble();
                    // band-passed noise whose centre falls as the bristles slow down
                    double low = 0, band = 0;
                    AddWrapped(output, n, (int)(t0 * Rate), (int)(dur * Rate), k =>
                    {
                        double t = k / Rate, u = t / dur;
                        double fc = 3200 - 1700 * u;
                        double f = 2 * Math.Sin(Math.PI * fc / Rate);
                        double high = Noise(rng) - low - 0.9 * band;
                        band += f * high;
                        low += f * band;
                        double env = Math.Pow(Math.Sin(Math.PI * u), 2) * (1 - 0.4 * u);
                        // petals: a few tiny ticks in the swish
                        double tick = rng.NextDouble() < 0.0015 ? (rng.NextDouble() - 0.5) * 1.2 : 0;
                        return (band * 0.5 + tick) * env * loud;
                    });
                }
            });
        }

        // The donkey's bray (the cart's form of the horn): "hee-haw, hee-haw". The "hee" is drawn in, high and
        // thin; the "haw" pushed out, low, loud and rough. A buzzy source (harmonics up to 5 kHz) through two
        // formant resonances for each vowel.
        public static float[] DonkeyBray()
        {
            return MakeBuffer(1.9, (output, n) =>
            {
                var rng = new Random(315);
                // start, length, f0 from, f0 to, formant 1, formant 2, loudness, roughness
                double[,] parts = {
                    { 0.00, 0.30, 470, 560, 1150, 2700, 0.45, 0.10 },
                    { 0.34, 0.42, 210, 150, 720, 1150, 1.00, 0.35 },
                    { 0.84, 0.26, 450, 530, 1150, 2700, 0.40, 0.10 },
                    { 1.14, 0.48, 200, 135, 700, 1100, 0.95, 0.40 } };
                for (int p = 0; p < parts.GetLength(0); p++)
                {
                    int start = (int)(parts[p, 0] * Rate), count = (int)(parts[p, 1] * Rate);
                    double length = parts[p, 1];
                    double phase = 0, l1 = 0, b1 = 0, l2 = 0, b2 = 0, jitter = 0;
                    double g1 = 2 * Math.Sin(Math.PI * parts[p, 4] / Rate), g2 = 2 * Math.Sin(Math.PI * parts[p, 5] / Rate);
                    for (int k = 0; k < count && start + k < n; k++)
                    {
                        double t = k / Rate, u = t / length;
                        // the pitch rises (hee) or falls (haw) along a curve, with a little wobble
                        jitter += (Noise(rng) - jitter) * 0.002;
                        double glide = parts[p, 2] + (parts[p, 3] - parts[p, 2]) * Math.Sin(Math.PI / 2 * u);
                        double f0 = glide * (1 + 0.025 * Math.Sin(2 * Math.PI * 6 * t) + 0.05 * jitter);
                        phase += f0 / Rate;
                        if (phase >= 1) phase -= 1;
                        double src = 0;
                        int harmonics = Math.Max(1, (int)(5000 / f0));
                        for (int h = 1; h <= harmonics; h++) src += Math.Sin(2 * Math.PI * h * phase) / h;
                        // roughness: the voice flutters at about 28 Hz
                        double flutter = 0.5 + 0.5 * Math.Sin(2 * Math.PI * 28 * t);
                        src *= 1 - parts[p, 7] * flutter;
                        double h1 = src - l1 - 0.25 * b1; b1 += g1 * h1; l1 += g1 * b1;
                        double h2 = src - l2 - 0.3 * b2; b2 += g2 * h2; l2 += g2 * b2;
                        double env = Math.Min(1, t / 0.03) * Math.Min(1, (length - t) / 0.06);
                        double voice = b1 * 0.6 + b2 * 0.35 + src * 0.05;
                        output[start + k] += (float)(voice * env * parts[p, 6] * 0.3);
                    }
                }
            });
        }

        // ------------------------------------------------------------------ halloween
        // The witch's tune: an original slow waltz in A minor (8 bars of 3/4, about 10 s, looping), sung by a thin
        // wavering voice that slides from note to note (like a theremin) over a low organ holding the bar's root and
        // fifth. Written for JuleHygge, so it is free of rights. Same as macOS Sound.swift (Synth.witchTune).
        public static float[] WitchTune()
        {
            const double beat = 0.42;
            const int E4 = 64, Gs4 = 68, A4 = 69, B4 = 71, C5 = 72, D5 = 74, E5 = 76;
            double[,] melody = {
                { E5, 2 }, { C5, 1 },   { D5, 2 }, { B4, 1 },   { C5, 1 }, { B4, 1 }, { A4, 1 },   { E4, 3 },
                { A4, 2 }, { C5, 1 },   { B4, 2 }, { Gs4, 1 },  { A4, 3 },                         { 0, 3 } };
            int[] roots = { 45, 40, 45, 40, 41, 40, 45, 45 };
            Func<double, double> freq = midi => 440 * Math.Pow(2, (midi - 69) / 12.0);
            double total = 0;
            int notes = melody.GetLength(0);
            for (int i = 0; i < notes; i++) total += melody[i, 1] * beat;
            return MakeBuffer(total, (output, n) =>
            {
                // the voice: the pitch glides toward each note, with a slow vibrato that deepens as the note is held
                double phase = 0, pitch = freq(melody[0, 0]), level = 0;
                double noteStart = 0, noteEnd = melody[0, 1] * beat;
                int idx = 0;
                for (int i = 0; i < n; i++)
                {
                    double t = i / Rate;
                    while (t >= noteEnd && idx < notes - 1) { idx++; noteStart = noteEnd; noteEnd += melody[idx, 1] * beat; }
                    double note = melody[idx, 0];
                    double held = t - noteStart, left = noteEnd - t;
                    if (note > 0) pitch += (freq(note) - pitch) * 0.0009;
                    double want = note > 0 ? Math.Min(1, held / 0.06) * Math.Min(1, left / 0.09) : 0;
                    level += (want - level) * 0.002;
                    double vibrato = 1 + 0.008 * Math.Min(1, held / 0.35) * Math.Sin(2 * Math.PI * 5.6 * t);
                    phase += pitch * vibrato / Rate;
                    if (phase >= 1) phase -= 1;
                    double voice = Math.Sin(2 * Math.PI * phase) + 0.16 * Math.Sin(4 * Math.PI * phase) + 0.05 * Math.Sin(6 * Math.PI * phase);
                    output[i] += (float)(voice * level * 0.34);
                }
                // the organ: root and fifth per bar, soft, swelling in and out so the loop has no click
                double[,] stops = { { 1.0, 1.0 }, { 1.5, 0.55 }, { 2.0, 0.4 }, { 3.0, 0.18 }, { 4.0, 0.1 } };
                for (int b = 0; b < roots.Length; b++)
                {
                    int start = (int)(b * 3 * beat * Rate), count = (int)(3 * beat * Rate);
                    double f = freq(roots[b]);
                    for (int k = 0; k < count && start + k < n; k++)
                    {
                        double t = k / Rate, u = (double)k / count;
                        double env = Math.Min(1, u / 0.12) * Math.Min(1, (1 - u) / 0.12);
                        double v = 0;
                        for (int h = 0; h < stops.GetLength(0); h++) v += stops[h, 1] * Math.Sin(2 * Math.PI * f * stops[h, 0] * t);
                        output[start + k] += (float)(v * env * 0.1);
                    }
                }
            });
        }

        // ------------------------------------------------------------------ nytår
        // New Year's tune, to the rockets: "Auld Lang Syne", verse and refrain (16 bars of 4/4, about 29 s, looping).
        // The melody is traditional (Scottish, 18th century) and free of rights; this arrangement is ours: a soft
        // reed voice like an accordion over a slow bass and a held chord. Same as macOS Sound.swift (Synth.auldLangSyne).
        public static float[] AuldLangSyne()
        {
            const double beat = 0.46;
            const int C4 = 60, D4 = 62, F4 = 65, G4 = 67, A4 = 69, C5 = 72, D5 = 74;
            // every bar is a dotted quarter, an eighth and two quarters; the long notes take three beats, and the
            // fourth is the upbeat to the next line
            double[,] melody = {
                { F4, 1.5 }, { F4, 0.5 }, { F4, 1 }, { A4, 1 },   { G4, 1.5 }, { F4, 0.5 }, { G4, 1 }, { A4, 1 },
                { F4, 1.5 }, { F4, 0.5 }, { A4, 1 }, { C5, 1 },   { D5, 3 }, { D5, 1 },
                { C5, 1.5 }, { A4, 0.5 }, { A4, 1 }, { F4, 1 },   { G4, 1.5 }, { F4, 0.5 }, { G4, 1 }, { A4, 1 },
                { F4, 1.5 }, { D4, 0.5 }, { D4, 1 }, { C4, 1 },   { F4, 3 }, { D5, 1 },
                { C5, 1.5 }, { A4, 0.5 }, { A4, 1 }, { F4, 1 },   { G4, 1.5 }, { F4, 0.5 }, { G4, 1 }, { D5, 1 },
                { C5, 1.5 }, { A4, 0.5 }, { A4, 1 }, { C5, 1 },   { D5, 3 }, { D5, 1 },
                { C5, 1.5 }, { A4, 0.5 }, { A4, 1 }, { F4, 1 },   { G4, 1.5 }, { F4, 0.5 }, { G4, 1 }, { A4, 1 },
                { F4, 1.5 }, { D4, 0.5 }, { D4, 1 }, { C4, 1 },   { F4, 3 }, { C4, 1 } };
            // one chord a bar: F, C, F, B flat | F, C, B flat, F, twice (root, third, fifth)
            int[] fa = { 41, 57, 60 }, ce = { 36, 55, 60 }, be = { 34, 58, 62 };
            int[][] chords = { fa, ce, fa, be, fa, ce, be, fa, fa, ce, fa, be, fa, ce, be, fa };
            Func<double, double> freq = midi => 440 * Math.Pow(2, (midi - 69) / 12.0);
            double total = 0;
            int notes = melody.GetLength(0);
            for (int i = 0; i < notes; i++) total += melody[i, 1] * beat;
            double[,] reed = { { 1, 1 }, { 2, 0.42 }, { 3, 0.2 }, { 4, 0.1 }, { 5, 0.05 } };
            return MakeBuffer(total, (output, n) =>
            {
                // the melody: two reeds a few cents apart (their slow beating is the accordion's tremolo)
                double t0 = 0;
                for (int i = 0; i < notes; i++)
                {
                    double f = freq(melody[i, 0]), dur = melody[i, 1] * beat;
                    int start = (int)(t0 * Rate), count = (int)(dur * Rate);
                    for (int k = 0; k < count && start + k < n; k++)
                    {
                        double t = k / Rate, left = dur - t;
                        double env = Math.Min(1, t / 0.035) * Math.Min(1, left / 0.07) * (0.85 + 0.15 * Math.Exp(-t * 2.5));
                        double v = 0;
                        for (int h = 0; h < 5; h++)
                            v += reed[h, 1] * (Math.Sin(2 * Math.PI * f * reed[h, 0] * t) + 0.8 * Math.Sin(2 * Math.PI * f * 1.006 * reed[h, 0] * t));
                        output[start + k] += (float)(v * env * 0.085);
                    }
                    t0 += dur;
                }
                // the left hand: the root on the first beat, the chord on the second and fourth, each note dying away
                Action<double, int, double, double> tone = (at, midi, len, amp) =>
                {
                    double f = freq(midi);
                    int start = (int)(at * beat * Rate), count = (int)(len * beat * Rate);
                    for (int k = 0; k < count && start + k < n; k++)
                    {
                        double t = k / Rate, u = k / (double)count;
                        double env = Math.Min(1, t / 0.02) * (1 - u) * (1 - u);
                        output[start + k] += (float)(amp * env * (Math.Sin(2 * Math.PI * f * t) + 0.35 * Math.Sin(4 * Math.PI * f * t) + 0.12 * Math.Sin(6 * Math.PI * f * t)));
                    }
                };
                for (int b = 0; b < chords.Length; b++)
                {
                    double bar = b * 4;
                    tone(bar, chords[b][0], 2.2, 0.2);
                    tone(bar + 2, chords[b][0] + 7, 1.8, 0.12);
                    foreach (double at in new[] { 1.0, 3.0 }) { tone(bar + at, chords[b][1], 0.9, 0.06); tone(bar + at, chords[b][2], 0.9, 0.06); }
                }
            });
        }

        // Midnight: twelve strokes of a tower bell, one every 1.3 s, each ringing on under the next. The partials are
        // a bell's (hum, prime, minor third, fifth, octave and above), the low ones ringing longest. Same as macOS
        // (Synth.midnightBell).
        public static float[] MidnightBell()
        {
            const double gap = 1.3, f = 233.0;
            double[,] partials = { { 0.5, 0.55, 0.55 }, { 1, 1, 0.9 }, { 1.19, 0.6, 1.3 }, { 1.5, 0.35, 1.8 }, { 2, 0.5, 2.2 }, { 2.74, 0.22, 3.2 }, { 4.07, 0.12, 5 } };
            return MakeBuffer(gap * 12 + 4.5, (output, n) =>
            {
                for (int s = 0; s < 12; s++)
                {
                    int start = (int)(s * gap * Rate), count = (int)(5.5 * Rate);
                    for (int k = 0; k < count && start + k < n; k++)
                    {
                        double t = k / Rate, v = 0;
                        for (int p = 0; p < partials.GetLength(0); p++)
                            v += partials[p, 1] * Math.Exp(-t * partials[p, 2]) * Math.Sin(2 * Math.PI * f * partials[p, 0] * t);
                        // the clapper's knock
                        v += 0.5 * Math.Exp(-t * 60) * Math.Sin(2 * Math.PI * 1300 * t);
                        output[start + k] += (float)(v * Math.Min(1, t / 0.003) * 0.16);
                    }
                }
                int fade = (int)(0.6 * Rate);
                for (int i = 0; i < fade && n - 1 - i >= 0; i++) output[n - 1 - i] *= i / (float)fade;
            });
        }

        // The wind Halloween's ghosts blow the leaves away with: a hollow rush of air that rises and falls, and under
        // it two wavering "oooo" voices a third apart. A 4 s loop: every tone and every swell is a whole number of
        // cycles in it, and the air is made a little longer and faded into its own start, so there is no seam.
        public static float[] GhostWind()
        {
            const double len = 4.0;
            return MakeBuffer(len, (output, n) =>
            {
                var rng = new Random(3110);
                int over = (int)(0.3 * Rate);
                var air = new double[n + over];
                double low = 0, band = 0;
                for (int i = 0; i < n + over; i++)
                {
                    double t = i / Rate;
                    // a resonance that slides up and down between about 350 and 900 Hz
                    double fc = 620 + 280 * Math.Sin(2 * Math.PI * 0.5 * t);
                    double f = 2 * Math.Sin(Math.PI * fc / Rate);
                    double high = Noise(rng) - low - 0.35 * band;
                    band += f * high;
                    low += f * band;
                    air[i] = band * (0.6 + 0.4 * Math.Sin(2 * Math.PI * 0.25 * t));
                }
                for (int i = 0; i < over; i++) { double k = (double)i / over; air[i] = air[i] * k + air[n + i] * (1 - k); }
                for (int i = 0; i < n; i++)
                {
                    double t = i / Rate;
                    double swell = 0.5 + 0.5 * Math.Sin(2 * Math.PI * 0.25 * t - 1);
                    double vib = 1 + 0.012 * Math.Sin(2 * Math.PI * 5 * t);
                    double voices = Math.Sin(2 * Math.PI * 330 * vib * t) + 0.8 * Math.Sin(2 * Math.PI * 392 * vib * t + 1) + 0.25 * Math.Sin(2 * Math.PI * 660 * vib * t);
                    output[i] = (float)(air[i] * 0.22 + voices * swell * 0.035);
                }
            });
        }

        // ------------------------------------------------------------------ de dødes dag
        // The butterflies' tune: an original little waltz in D minor (16 bars of 3/4, about 18 s, looping) in the
        // style of a Mexican son: the melody on a marimba (long notes rolled, as marimba players do) over a guitar
        // that plays the bass on the first beat and strums the chord on the second and third (down, up, down).
        // Written for JuleHygge, so it is free of rights. Same as macOS Sound.swift (Synth.muertosSon).
        public static float[] MuertosSon()
        {
            const double beat = 0.38;
            const int A4 = 69, Cs5 = 73, C5 = 72, D5 = 74, E5 = 76, F5 = 77, G5 = 79, A5 = 81, Bb5 = 82, C6 = 84, D6 = 86;
            double[,] melody = {
                { A4, 1 }, { D5, 1 }, { F5, 1 },             { A5, 2 }, { G5, 0.5 }, { F5, 0.5 },
                { E5, 1.5 }, { F5, 0.5 }, { G5, 1 },         { A5, 2 }, { 0, 1 },
                { F5, 1 }, { E5, 0.5 }, { D5, 0.5 }, { F5, 1 }, { A5, 1 }, { D6, 1 }, { A5, 1 },
                { Bb5, 1 }, { A5, 0.5 }, { G5, 0.5 }, { F5, 1 }, { E5, 2 }, { 0, 1 },
                { C5, 1 }, { F5, 1 }, { A5, 1 },             { C6, 2 }, { A5, 1 },
                { Bb5, 1 }, { G5, 1 }, { E5, 1 },            { E5, 1 }, { G5, 1 }, { Bb5, 1 },
                { A5, 1.5 }, { G5, 0.5 }, { F5, 1 },         { F5, 1 }, { E5, 0.5 }, { D5, 0.5 }, { A5, 1 },
                { G5, 1 }, { E5, 1 }, { Cs5, 1 },            { D5, 2 }, { 0, 1 } };
            // the guitar's chords, lowest string first (the first note is the bass)
            int[] Dm = { 50, 57, 62, 65 }, A7 = { 45, 52, 55, 61, 64 }, Gm = { 43, 50, 55, 58, 62 }, Fmaj = { 41, 48, 53, 57, 60 }, C7 = { 48, 52, 58, 60, 64 };
            int[][] chords = { Dm, Dm, A7, A7, Dm, Dm, Gm, A7, Fmaj, Fmaj, C7, C7, Gm, Dm, A7, Dm };
            double totalBeats = 0;
            for (int i = 0; i < melody.GetLength(0); i++) totalBeats += melody[i, 1];
            int n = (int)(totalBeats * beat * Rate);
            var output = new float[n];
            Func<int, double> freq = midi => 440 * Math.Pow(2, (midi - 69) / 12.0);
            var rng = new Random(1102);

            // One marimba stroke: the bar's fundamental with its 4th and 10th partials (a marimba bar is tuned so),
            // all dying fast, plus a soft knock of the mallet. Wraps round the loop's end, so the seam is clean.
            Action<double, int, double> strike = (t0, midi, amp) =>
            {
                double f = freq(midi);
                int start = (int)(t0 * Rate), count = (int)(1.2 * Rate);
                for (int k = 0; k < count; k++)
                {
                    double t = k / Rate;
                    double env = Math.Min(1, t / 0.002);
                    double v = Math.Exp(-t * 4.5) * Math.Sin(2 * Math.PI * f * t);
                    v += 0.22 * Math.Exp(-t * 14) * Math.Sin(2 * Math.PI * f * 4 * t);
                    v += 0.05 * Math.Exp(-t * 30) * Math.Sin(2 * Math.PI * f * 10 * t);
                    v += 0.15 * Math.Exp(-t * 300) * Math.Sin(2 * Math.PI * 180 * t);
                    output[(start + k) % n] += (float)(v * env * amp);
                }
            };
            // One plucked string (Karplus-Strong): a burst of soft noise circulating in a delay line one period
            // long, averaged a little each round, so it rings and darkens like a nylon string.
            Action<double, int, double, double> pluck = (t0, midi, amp, len) =>
            {
                int period = Math.Max(2, (int)(Rate / freq(midi)));
                var line = new double[period];
                double prev = 0;
                for (int i = 0; i < period; i++) { prev = prev * 0.5 + Noise(rng) * 0.5; line[i] = prev; }
                int start = (int)(t0 * Rate), count = (int)(len * Rate);
                for (int k = 0; k < count; k++)
                {
                    int j = k % period, j2 = (k + 1) % period;
                    double v = line[j];
                    line[j] = 0.4985 * (line[j] + line[j2]);
                    double fadeOut = k > count - 800 ? (count - k) / 800.0 : 1;
                    output[(start + k) % n] += (float)(v * amp * fadeOut);
                }
            };
            Action<double, int[], bool, double> strum = (t0, chord, down, amp) =>
            {
                // down: every string but the bass, lowest first; up: the three highest, highest first
                int count = down ? chord.Length - 1 : 3;
                for (int k = 0; k < count; k++)
                    pluck(t0 + k * 0.011, down ? chord[1 + k] : chord[chord.Length - 1 - k], amp, beat * 1.4);
            };

            // melody: short notes struck once, long ones rolled
            double at = 0;
            for (int i = 0; i < melody.GetLength(0); i++)
            {
                int note = (int)melody[i, 0];
                double len = melody[i, 1];
                if (note > 0)
                {
                    if (len >= 1.5) { for (double r = 0; r < len * beat - 0.1; r += 0.085) strike(at + r, note, r == 0 ? 0.30 : 0.17); }
                    else strike(at, note, 0.30);
                }
                at += len * beat;
            }
            // guitar: bass on 1, strum down on 2, up on the "and", down on 3
            for (int b = 0; b < chords.Length; b++)
            {
                double t0 = b * 3 * beat;
                pluck(t0, chords[b][0], 0.38, beat * 2.2);
                strum(t0 + beat, chords[b], true, 0.16);
                strum(t0 + beat * 1.5, chords[b], false, 0.10);
                strum(t0 + beat * 2, chords[b], true, 0.14);
            }
            Normalize(output);
            return output;
        }

        // ------------------------------------------------------------------ geese (autumn's flyer)
        // The two moods of a flock of geese passing over; each trip picks one (alone twice as often as in wind).
        public static readonly string[] GooseMoods = { "alene", "blaest" };

        // The flock itself is a recording (assets/lyd/gaes-flok.wav, see KILDER.md there): synthesized calls
        // sounded far too artificial. build.ps1 puts the file into the exe as a resource. Mixed to mono at the
        // synth's sample rate, peak 0.6. Null if it is missing or not 16-bit PCM: no goose sound then.
        static readonly Dictionary<string, float[]> recordings = new Dictionary<string, float[]>();
        static readonly object gooseGate = new object();

        static float[] GooseRecording() { return Recording("gaes-flok.wav"); }

        // A recording built into the exe as a resource (assets/lyd), read once.
        static float[] Recording(string name)
        {
            lock (gooseGate)
            {
                float[] gooseRecording;
                if (recordings.TryGetValue(name, out gooseRecording)) return gooseRecording;
                recordings[name] = null;
                try
                {
                    byte[] d;
                    using (var s = System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
                    {
                        if (s == null) return null;
                        d = new byte[s.Length];
                        int got = 0;
                        while (got < d.Length) { int r = s.Read(d, got, d.Length - got); if (r <= 0) break; got += r; }
                    }
                    // find the format and the samples
                    int channels = 0, rate = 0, bits = 0, start = -1, bytes = 0;
                    for (int pos = 12; pos + 8 <= d.Length; )
                    {
                        string id = System.Text.Encoding.ASCII.GetString(d, pos, 4);
                        int size = BitConverter.ToInt32(d, pos + 4);
                        if (id == "fmt ") { channels = BitConverter.ToInt16(d, pos + 10); rate = BitConverter.ToInt32(d, pos + 12); bits = BitConverter.ToInt16(d, pos + 22); }
                        if (id == "data") { start = pos + 8; bytes = Math.Min(size, d.Length - start); break; }
                        pos += 8 + size + (size & 1);
                    }
                    if (start < 0 || bits != 16 || channels < 1 || rate < 8000) return null;
                    int m = bytes / (2 * channels);
                    if (m < 2) return null;
                    var mono = new float[m];
                    for (int i = 0; i < m; i++)
                    {
                        int sum = 0;
                        for (int ch = 0; ch < channels; ch++) sum += BitConverter.ToInt16(d, start + (i * channels + ch) * 2);
                        mono[i] = sum / (float)channels / 32768f;
                    }
                    double ratio = rate / Rate;
                    int outN = (int)((m - 1) / ratio);
                    var rec = new float[Math.Max(0, outN)];
                    float peak = 0;
                    for (int i = 0; i < outN; i++)
                    {
                        double p = i * ratio;
                        int j = Math.Min(m - 2, (int)p);
                        float f = (float)(p - j);
                        rec[i] = mono[j] * (1 - f) + mono[j + 1] * f;
                        peak = Math.Max(peak, Math.Abs(rec[i]));
                    }
                    if (peak > 0) { float k = 0.6f / peak; for (int i = 0; i < outN; i++) rec[i] *= k; }
                    recordings[name] = gooseRecording = rec;
                }
                catch (Exception ex) { ErrorLog.Write(ex); }
                return gooseRecording;
            }
        }

        // ------------------------------------------------------------------ karneval
        // What the Rhineland carnival's wagon plays: a recording of a real village brass band (an excerpt of the
        // Hannerl Polka played by Blaskapelle Franz Stremnitzer, CC BY 3.0; source, licence and how it was cut in
        // assets/lyd/KILDER.md), because synthesized marches never came to sound like brass on macOS. build.ps1
        // puts it into the exe with the times of its beats. Null if it is missing: the wagon is silent then.
        public static float[] RheinBand() { return Recording("hannerl-polka.wav"); }

        // Where every beat of that excerpt falls, in seconds from its start (found by tools/takt.py: a band never
        // keeps one tempo exactly, and the walkers step on the band's beats, not on a clock's). The last number is
        // the excerpt's length, where the first beat comes round again. Null without it.
        static double[] rheinBeats;
        static bool rheinBeatsRead;
        public static double[] RheinBeats()
        {
            lock (gooseGate)
            {
                if (rheinBeatsRead) return rheinBeats;
                rheinBeatsRead = true;
                try
                {
                    using (var s = System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream("hannerl-polka.takt"))
                    {
                        if (s == null) return null;
                        var t = new List<double>();
                        using (var reader = new System.IO.StreamReader(s))
                            for (string line; (line = reader.ReadLine()) != null; )
                            {
                                double v;
                                if (double.TryParse(line.Trim(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out v)) t.Add(v);
                            }
                        bool rising = t.Count > 8;
                        for (int i = 1; i < t.Count; i++) if (t[i] <= t[i - 1]) rising = false;
                        if (rising) rheinBeats = t.ToArray();
                    }
                }
                catch (Exception ex) { ErrorLog.Write(ex); }
                return rheinBeats;
            }
        }

        // The beat number (whole numbers on the beats) at `position` seconds into the excerpt; -1 without the beats.
        public static double RheinBeat(double position)
        {
            var t = RheinBeats();
            if (t == null) return -1;
            double p = Math.Max(t[0], Math.Min(t[t.Length - 1], position));
            int lo = 0, hi = t.Length - 1;
            while (hi - lo > 1) { int m = (lo + hi) / 2; if (t[m] <= p) lo = m; else hi = m; }
            return lo + (p - t[lo]) / (t[hi] - t[lo]);
        }

        // The band truck's drums at Rio's carnival: a samba batucada, two bars of 2/4 at 120 beats a minute (4 s,
        // looping; the beat the walkers step to, Controller.Beat). An original pattern for the instruments of a
        // bateria, the same as the macOS version's (Synth.batucada): the low surdo on the second beat of each bar
        // with a softer answer on the first, the snare (caixa) running in sixteenths with accents, the small
        // tamborim in its off-beat figure, two bells (agogô), a shaker throughout, and a whistle at the start.
        public static float[] Batucada()
        {
            const double step = 0.125;
            const int steps = 32;
            return MakeBuffer(step * steps, (output, n) =>
            {
                var rng = new Random(2027);
                Action<double, double, Func<double, double>> add = (t0, len, f) =>
                {
                    int start = (int)(t0 * Rate), count = (int)(len * Rate);
                    // (a hit near the end rings on into the start: the loop has no seam)
                    for (int k = 0; k < count; k++) output[(start + k) % n] += (float)f(k / Rate);
                };
                double[] accents = { 1.0, 0.35, 0.5, 0.8 };
                for (int s = 0; s < steps; s++)
                {
                    double t = s * step;
                    int inBar = s % 16, sixteenth = s;
                    // surdo: a deep drum, its pitch dropping a little as it rings
                    if (inBar == 4 || inBar == 12) add(t, 0.5, x => 0.55 * Math.Exp(-x * 6) * Math.Sin(2 * Math.PI * (62 + 18 * Math.Exp(-x * 30)) * x));
                    if (inBar == 0 || inBar == 8) add(t, 0.3, x => 0.28 * Math.Exp(-x * 14) * Math.Sin(2 * Math.PI * (78 + 14 * Math.Exp(-x * 30)) * x));
                    // caixa: sixteenths of filtered noise, accented on the off-beats
                    double accent = accents[s % 4], last = 0;
                    add(t, 0.07, x => { double v = Noise(rng), hp = v - last; last = v; return 0.16 * accent * Math.Exp(-x * 60) * hp; });
                    // tamborim: a dry high tap in the figure of a telecoteco
                    if (inBar == 0 || inBar == 3 || inBar == 6 || inBar == 10 || inBar == 12 || inBar == 15)
                        add(t, 0.06, x => 0.2 * Math.Exp(-x * 70) * (Math.Sin(2 * Math.PI * 1900 * x) + 0.5 * Math.Sin(2 * Math.PI * 2850 * x)));
                    // agogô: two bells, high and low
                    if (inBar == 2 || inBar == 6 || inBar == 9 || inBar == 14)
                    {
                        double f = inBar == 2 || inBar == 9 ? 880.0 : 660.0;
                        add(t, 0.25, x => 0.12 * Math.Exp(-x * 12) * (Math.Sin(2 * Math.PI * f * x) + 0.4 * Math.Sin(2 * Math.PI * f * 2.76 * x)));
                    }
                    // shaker: soft hiss on every sixteenth
                    add(t, 0.05, x => 0.05 * (sixteenth % 2 == 0 ? 1 : 0.6) * Math.Sin(Math.PI * Math.Min(1, x / 0.05)) * Noise(rng));
                }
                // the whistle at the start: three short calls, each with the pea's trill
                double[,] calls = { { 0.0, 0.12 }, { 0.25, 0.12 }, { 0.5, 0.3 } };
                for (int k = 0; k < 3; k++)
                {
                    double len = calls[k, 1];
                    add(calls[k, 0], len, x => 0.1 * Math.Min(1, x / 0.01) * Math.Min(1, (len - x) / 0.02) * Math.Sin(2 * Math.PI * 2700 * x + 2.5 * Math.Sin(2 * Math.PI * 38 * x)));
                }
            });
        }

        // One seamless loop of geese calling, as long as the recording: 0 = the flock alone, 1 = farther off
        // (quieter and duller) over synthesized gusts of wind. Null without the recording.
        public static float[] Geese(int mood)
        {
            var rec = GooseRecording();
            int over = (int)(0.5 * Rate);
            if (rec == null || rec.Length <= over * 4) return null;
            int n = rec.Length - over;
            double len = n / Rate;
            var output = new float[n];

            // The recording, its tail cross-faded into its start so the loop has no seam; a far flock is
            // quieter and has lost its brightness (a one-pole low-pass).
            int tail = Math.Max(0, Math.Min(rec.Length - n, n));
            float level = mood == 0 ? 1f : 0.6f, open = mood == 0 ? 1f : 0.35f, smooth = 0;
            for (int i = 0; i < n; i++)
            {
                float s = rec[i];
                if (i < tail) { float k = (float)i / tail; s = s * k + rec[n + i] * (1 - k); }
                smooth += (s - smooth) * open;
                output[i] = smooth * level;
            }
            if (mood > 0)
            {
                // The wind under the calls: made a little longer than the loop and cross-faded into its own
                // start, so the loop has no seam. (A third mood with rain was tried and dropped: it did not work.)
                var rng = new Random(1200 + mood);
                var bed = new float[n + over];
                double lp1 = 0, lp2 = 0;
                for (int i = 0; i < n + over; i++)
                {
                    double tt = i / Rate;
                    // gusts: the wind grows louder and brighter together (whole cycles per loop)
                    double w = 2 * Math.PI * tt / len;
                    double gq = 0.5 + 0.5 * (0.6 * Math.Sin(w * 2) + 0.4 * Math.Sin(w * 5 + 1.3));
                    double gust = gq * gq;
                    double a = 0.012 + 0.05 * gust;
                    lp1 += (Noise(rng) - lp1) * a;
                    lp2 += (lp1 - lp2) * a;
                    bed[i] = (float)(lp2 * (0.25 + 0.75 * gust) * 1.9);
                }
                for (int i = 0; i < over; i++)
                {
                    float k = (float)i / over;
                    bed[i] = bed[i] * k + bed[n + i] * (1 - k);
                }
                for (int i = 0; i < n; i++) output[i] += bed[i];
            }
            Normalize(output);
            return output;
        }

        // Two-tone truck horn: "baa-baaa".
        public static float[] PlowHorn()
        {
            return MakeBuffer(1.0, (output, n) =>
            {
                Action<double, double> honk = (t0, len) =>
                {
                    int start = (int)(t0 * Rate), count = (int)(len * Rate);
                    for (int k = 0; k < count && start + k < n; k++)
                    {
                        double t = k / Rate;
                        double env = Math.Min(1, t / 0.02) * Math.Min(1, (len - t) / 0.05);
                        double v = 0;
                        foreach (double f in new[] { 311.0, 370.0 })      // a slightly sour third, like a real truck horn
                            for (int h = 1; h <= 5; h++) v += Math.Sin(2 * Math.PI * f * h * t) / h;
                        output[start + k] += (float)(v * env * 0.12);
                    }
                };
                honk(0, 0.22);
                honk(0.32, 0.5);
            });
        }

        // A tune for Santa's sleigh: melody as (MIDI note, beats; 0 = rest), one bass root per bar (MIDI).
        // All three are public domain: "Jingle Bells" (James Lord Pierpont, 1857), "Deck the Halls" (Welsh
        // traditional) and "We Wish You a Merry Christmas" (English traditional). Same as macOS Sound.swift.
        public sealed class Tune
        {
            public string Name;
            public double Beat;          // seconds per beat
            public int BeatsPerBar;
            public double[,] Melody;
            public int[] BassRoots;

            public static readonly Tune[] All = { JingleBells(), DeckTheHalls(), WeWishYou() };

            static Tune JingleBells()
            {
                const int E5 = 76, F5 = 77, G5 = 79, C5 = 72, D5 = 74;
                var t = new Tune { Name = "jingle-bells", Beat = 0.36, BeatsPerBar = 4 };
                t.Melody = new double[,] {
                    {E5,1},{E5,1},{E5,2}, {E5,1},{E5,1},{E5,2}, {E5,1},{G5,1},{C5,1.5},{D5,0.5}, {E5,4},
                    {F5,1},{F5,1},{F5,1.5},{F5,0.5}, {F5,1},{E5,1},{E5,1},{E5,0.5},{E5,0.5}, {E5,1},{D5,1},{D5,1},{E5,1}, {D5,2},{G5,2},
                    {E5,1},{E5,1},{E5,2}, {E5,1},{E5,1},{E5,2}, {E5,1},{G5,1},{C5,1.5},{D5,0.5}, {E5,4},
                    {F5,1},{F5,1},{F5,1.5},{F5,0.5}, {F5,1},{E5,1},{E5,1},{E5,0.5},{E5,0.5}, {G5,1},{G5,1},{F5,1},{D5,1}, {C5,3},{0,1} };
                t.BassRoots = new[] { C5, C5, C5, C5, F5, C5, D5, G5, C5, C5, C5, C5, F5, C5, G5, C5 };
                for (int i = 0; i < t.BassRoots.Length; i++) t.BassRoots[i] -= 24;
                return t;
            }

            // "Deck the Halls", whole verse with its "fa la la" lines, in C.
            static Tune DeckTheHalls()
            {
                const int B4 = 71, C5 = 72, D5 = 74, E5 = 76, F5 = 77, Fs5 = 78, G5 = 79, A5 = 81, B5 = 83, C6 = 84;
                double[,] line1 = { {G5,1.5},{F5,0.5},{E5,1},{D5,1}, {C5,1},{D5,1},{E5,1},{C5,1},
                                    {D5,0.5},{E5,0.5},{F5,0.5},{D5,0.5},{E5,1.5},{D5,0.5}, {C5,1},{B4,1},{C5,2} };
                double[,] line3 = { {D5,1.5},{E5,0.5},{F5,1},{D5,1}, {E5,1.5},{F5,0.5},{G5,1},{D5,1},
                                    {E5,0.5},{Fs5,0.5},{G5,1},{A5,0.5},{B5,0.5},{C6,1}, {B5,1},{A5,1},{G5,2} };
                double[,] line4 = { {G5,1.5},{F5,0.5},{E5,1},{D5,1}, {C5,1},{D5,1},{E5,1},{C5,1},
                                    {A5,0.5},{A5,0.5},{A5,0.5},{A5,0.5},{G5,1.5},{F5,0.5}, {E5,1},{D5,1},{C5,2} };
                const int C = 48, F = 53, G = 55, D = 50;
                return new Tune { Name = "deck-the-halls", Beat = 0.34, BeatsPerBar = 4,
                    Melody = Concat(line1, line1, line3, line4),
                    BassRoots = new[] { C, C, G, C, C, C, G, C, G, C, D, G, C, C, F, C } };
            }

            // "We Wish You a Merry Christmas" in 3/4, in C. The pickup note sits at the end of the loop.
            static Tune WeWishYou()
            {
                const int G4 = 67, A4 = 69, B4 = 71, C5 = 72, D5 = 74, E5 = 76, F5 = 77;
                const int C = 48, F = 53, G = 55, D = 50, E = 52, A = 45;
                return new Tune { Name = "we-wish-you", Beat = 0.4, BeatsPerBar = 3,
                    Melody = new double[,] {
                        {C5,1},{C5,0.5},{D5,0.5},{C5,0.5},{B4,0.5}, {A4,1},{A4,1},{A4,1},
                        {D5,1},{D5,0.5},{E5,0.5},{D5,0.5},{C5,0.5}, {B4,1},{G4,1},{G4,1},
                        {E5,1},{E5,0.5},{F5,0.5},{E5,0.5},{D5,0.5}, {C5,1},{A4,1},{G4,0.5},{G4,0.5},
                        {A4,1},{D5,1},{B4,1}, {C5,2},{G4,1} },   // "year" + the pickup "We" of the next round
                    BassRoots = new[] { C, F, D, G, E, A, F, C } };
            }

            static double[,] Concat(params double[][,] parts)
            {
                int n = 0;
                foreach (var p in parts) n += p.GetLength(0);
                var all = new double[n, 2];
                int k = 0;
                foreach (var p in parts)
                    for (int i = 0; i < p.GetLength(0); i++, k++) { all[k, 0] = p[i, 0]; all[k, 1] = p[i, 1]; }
                return all;
            }
        }

        // One loop of a tune: the melody on a music-box/celesta-like tone, a soft bass and shaken sleigh bells.
        public static float[] Jingle(Tune tune)
        {
            double beat = tune.Beat;
            double[,] melody = tune.Melody;

            double totalBeats = 0;
            for (int i = 0; i < melody.GetLength(0); i++) totalBeats += melody[i, 1];
            int n = (int)(totalBeats * beat * Rate);
            var output = new float[n];
            Func<int, double> freq = midi => 440 * Math.Pow(2, (midi - 69) / 12.0);

            // Celesta-like note: a few slightly inharmonic partials with a bright attack and a ringing decay.
            double[][] partials = { new[] { 1, 1.0, 2.2 }, new[] { 2.0, 0.35, 4 }, new[] { 3.01, 0.12, 7 }, new[] { 4.17, 0.06, 10 } };
            Action<double, int, double, double> addBell = (t0, midi, len, amp) =>
            {
                double f = freq(midi);
                double dur = Math.Min(len + 0.6, 2.5);
                int start = (int)(t0 * Rate), count = (int)(dur * Rate);
                for (int k = 0; k < count && start + k < n; k++)
                {
                    double t = k / Rate;
                    double v = 0;
                    foreach (var p in partials) v += p[1] * Math.Exp(-t * p[2]) * Math.Sin(2 * Math.PI * f * p[0] * t);
                    output[start + k] += (float)(v * amp * Math.Min(1, t / 0.004));
                }
            };
            // Soft round bass note.
            Action<double, int, double> addBass = (t0, midi, len) =>
            {
                double f = freq(midi);
                int start = (int)(t0 * Rate), count = (int)(len * Rate);
                for (int k = 0; k < count && start + k < n; k++)
                {
                    double t = k / Rate;
                    double env = Math.Min(1, t / 0.01) * Math.Exp(-t * 3);
                    output[start + k] += (float)(0.16 * env * (Math.Sin(2 * Math.PI * f * t) + 0.3 * Math.Sin(4 * Math.PI * f * t)));
                }
            };
            // One sleigh bell: a short, bright cluster of inharmonic partials plus a little noise.
            var rng = new Random(1857);
            double[] bellPartials = { 1, 1.47, 2.09, 2.56, 3.18 };
            Action<double, double> addJingle = (t0, amp) =>
            {
                double b = 2300 + rng.NextDouble() * 500;
                int start = (int)(t0 * Rate), count = (int)(0.09 * Rate);
                for (int k = 0; k < count; k++)
                {
                    int idx = start + k;
                    if (idx >= n || idx < 0) break;
                    double t = k / Rate;
                    double v = 0;
                    for (int j = 0; j < bellPartials.Length; j++) v += Math.Sin(2 * Math.PI * b * bellPartials[j] * t + j) / (j + 2);
                    v += Noise(rng) * 0.35 * Math.Exp(-t * 120);
                    output[idx] += (float)(v * Math.Exp(-t * 55) * amp);
                }
            };

            double time = 0;
            for (int i = 0; i < melody.GetLength(0); i++)
            {
                int note = (int)melody[i, 0];
                if (note > 0) addBell(time, note, melody[i, 1] * beat, 0.22);
                time += melody[i, 1] * beat;
            }
            // bass: the root on the first beat of each bar and the fifth on the third
            int bpb = tune.BeatsPerBar;
            int bars = (int)(totalBeats / bpb);
            for (int b = 0; b < bars; b++)
            {
                int root = tune.BassRoots[b % tune.BassRoots.Length];
                double t0 = b * bpb;
                addBass(t0 * beat, root, beat * 1.8);
                addBass((t0 + 2) * beat, root + 7, beat * (bpb - 2 + 0.8));
            }
            // sleigh bells: a shake on every eighth note, accented on the beat, each shake a few bells
            for (int e = 0; e * 0.5 < totalBeats; e++)
            {
                double tb = e * 0.5 * beat;
                double accent = e % 2 == 0 ? 1.0 : 0.6;
                for (int j = 0; j < 4; j++) addJingle(tb + j * 0.012 + rng.NextDouble() * 0.006, 0.05 * accent);
            }

            Normalize(output);   // gentle limiter so overlapping notes never clip
            int fade = (int)(0.01 * Rate);
            for (int i = 0; i < fade; i++) { float k = (float)i / fade; output[i] *= k; output[n - 1 - i] *= k; }
            return output;
        }

        // --lyd-test=DIR: writes each sound as a 16-bit mono WAV file plus a summary, so they can be listened to.
        public static void WriteTestFiles(string dir)
        {
            Directory.CreateDirectory(dir);
            var summary = new List<string>();
            var sounds = new Dictionary<string, Func<float[]>>();
            foreach (var t in Tune.All) { var tune = t; sounds.Add("julemand-" + tune.Name, () => Jingle(tune)); }
            sounds.Add("sneplov-motor", PlowEngine);
            sounds.Add("sneplov-skraben", PlowScrape);
            sounds.Add("sneplov-horn", PlowHorn);
            sounds.Add("loevsuger-sug", LeafSuction);
            sounds.Add("sommerfugle-son", MuertosSon);
            sounds.Add("aeselkaerre-rul", () => DonkeyCart(Controller.DonkeyStepCycle));
            sounds.Add("aeselkaerre-kost", () => BroomSweep(Controller.DonkeyStepCycle));
            sounds.Add("aeselkaerre-broel", DonkeyBray);
            sounds.Add("heks-melodi", WitchTune);
            sounds.Add("spoegelser-sus", GhostWind);
            sounds.Add("nytaar-melodi", AuldLangSyne);
            sounds.Add("nytaar-klokke", MidnightBell);
            sounds.Add("karneval-trommer", Batucada);
            sounds.Add("karneval-rhein", RheinBand);
            for (int m = 0; m < GooseMoods.Length; m++) { int mood = m; sounds.Add("gaes-" + GooseMoods[m], () => Geese(mood)); }
            foreach (var kv in sounds)
            {
                var s = kv.Value();
                if (s == null) { summary.Add(kv.Key + ": mangler (optagelsen er ikke i denne exe)"); continue; }
                using (var w = new BinaryWriter(File.Create(Path.Combine(dir, kv.Key + ".wav"))))
                {
                    w.Write(new[] { 'R', 'I', 'F', 'F' }); w.Write(36 + s.Length * 2); w.Write(new[] { 'W', 'A', 'V', 'E' });
                    w.Write(new[] { 'f', 'm', 't', ' ' }); w.Write(16); w.Write((short)1); w.Write((short)1);
                    w.Write(AudioHub.SampleRate); w.Write(AudioHub.SampleRate * 2); w.Write((short)2); w.Write((short)16);
                    w.Write(new[] { 'd', 'a', 't', 'a' }); w.Write(s.Length * 2);
                    foreach (var x in s) w.Write((short)(Math.Max(-1f, Math.Min(1f, x)) * 32000));
                }
                double peak = 0, sum = 0;
                foreach (var x in s) { peak = Math.Max(peak, Math.Abs(x)); sum += x * x; }
                summary.Add(string.Format(System.Globalization.CultureInfo.InvariantCulture, "{0}: {1:F1} s  peak {2:F2}  rms {3:F3}",
                    kv.Key, s.Length / Rate, peak, Math.Sqrt(sum / s.Length)));
            }
            File.WriteAllLines(Path.Combine(dir, "summary.txt"), summary);
        }
    }
}
