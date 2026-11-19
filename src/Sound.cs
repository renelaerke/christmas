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

        // ------------------------------------------------------------------ geese (autumn's flyer)
        // The two moods of a flock of geese passing over; each trip picks one (alone twice as often as in wind).
        public static readonly string[] GooseMoods = { "alene", "blaest" };

        // The flock itself is a recording (assets/lyd/gaes-flok.wav, see KILDER.md there): synthesized calls
        // sounded far too artificial. build.ps1 puts the file into the exe as a resource. Mixed to mono at the
        // synth's sample rate, peak 0.6. Null if it is missing or not 16-bit PCM: no goose sound then.
        static float[] gooseRecording;
        static bool gooseLoaded;
        static readonly object gooseGate = new object();

        static float[] GooseRecording()
        {
            lock (gooseGate)
            {
                if (gooseLoaded) return gooseRecording;
                gooseLoaded = true;
                try
                {
                    byte[] d;
                    using (var s = System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream("gaes-flok.wav"))
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
                    gooseRecording = rec;
                }
                catch (Exception ex) { ErrorLog.Write(ex); }
                return gooseRecording;
            }
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
