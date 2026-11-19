import AVFoundation

/// Synthesized sound effects (the project has no sound files): Santa's sleigh bells with the
/// "Jingle Bells" chorus (James Lord Pierpont, 1857), "Deck the Halls" (Welsh traditional) or "We Wish You a
/// Merry Christmas" (English traditional), all public domain, and the snow plow's engine, scraping
/// and horn. One audio engine is shared and only runs while something is audible, so it costs nothing
/// the rest of the time.
final class AudioHub {
    private let engine = AVAudioEngine()
    private var voices: [Voice] = []
    private var running = false
    private var quietSince: CFTimeInterval = 0

    func voice(_ make: @escaping () -> AVAudioPCMBuffer?, loops: Bool, varispeed: Bool = false) -> Voice {
        let v = Voice(hub: self, make: make, loops: loops)
        engine.attach(v.player)
        if varispeed { let vs = AVAudioUnitVarispeed(); engine.attach(vs); v.varispeed = vs }
        voices.append(v)
        return v
    }

    fileprivate func ensureRunning(for v: Voice) -> Bool {
        guard let buf = v.buffer else { return false }
        if !v.connected {
            if let vs = v.varispeed {
                engine.connect(v.player, to: vs, format: buf.format)
                engine.connect(vs, to: engine.mainMixerNode, format: buf.format)
            } else { engine.connect(v.player, to: engine.mainMixerNode, format: buf.format) }
            v.connected = true
        }
        if !running {
            do { try engine.start() } catch { ErrorLog.write("sound: \(error)"); return false }
            running = true
        }
        return true
    }

    /// Called once per frame after the voices were updated: stops the engine when everything is quiet.
    func idleCheck() {
        guard running else { return }
        if voices.contains(where: { $0.playing }) { quietSince = 0; return }
        let now = CACurrentMediaTime()
        if quietSince == 0 { quietSince = now }
        if now - quietSince > 1 { stopAll() }
    }

    func stopAll() {
        for v in voices { v.halt() }
        if running { engine.stop(); running = false }
        quietSince = 0
    }
}

/// One sound: a looping buffer whose volume and pan follow something on screen, or a one-shot.
final class Voice {
    fileprivate let player = AVAudioPlayerNode()
    private unowned let hub: AudioHub
    private let make: () -> AVAudioPCMBuffer?
    private let loops: Bool
    fileprivate var buffer: AVAudioPCMBuffer?
    fileprivate var connected = false
    fileprivate var varispeed: AVAudioUnitVarispeed?
    /// Playback speed (tempo and pitch together, like a tape), only for voices made with `varispeed: true`.
    var rate: Float {
        get { varispeed?.rate ?? 1 }
        set { varispeed?.rate = max(0.5, min(2, newValue)) }
    }
    private(set) var playing = false
    private var gain: Float = 0

    fileprivate init(hub: AudioHub, make: @escaping () -> AVAudioPCMBuffer?, loops: Bool) {
        self.hub = hub; self.make = make; self.loops = loops
    }

    private func prepare() -> Bool {
        if buffer == nil { buffer = make() }
        return hub.ensureRunning(for: self)
    }

    /// Looping voice: fades smoothly (about half a second) toward `level` (0…1) and pans to `pan` (−1…1).
    func update(level: Float, pan: Float, dt: Float) {
        if level > 0 && !playing {
            guard prepare(), let buffer else { return }
            gain = 0
            player.volume = 0
            player.scheduleBuffer(buffer, at: nil, options: loops ? .loops : [])
            player.play()
            playing = true
        }
        guard playing else { return }
        gain += (level - gain) * min(1, dt * 4)
        player.volume = gain
        player.pan = max(-1, min(1, pan))
        if level == 0 && gain < 0.003 { halt() }
    }

    /// Plays the whole buffer once.
    func playOnce(level: Float, pan: Float) {
        guard prepare(), let buffer else { return }
        player.stop()
        player.volume = level
        player.pan = max(-1, min(1, pan))
        playing = true
        player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async { self?.playing = false }
        }
        player.play()
    }

    fileprivate func halt() {
        if playing { player.stop() }
        playing = false
        gain = 0
    }
}

enum Synth {
    static let sampleRate = 44_100.0

    static func makeBuffer(seconds: Double, _ fill: (UnsafeMutablePointer<Float>, Int) -> Void) -> AVAudioPCMBuffer? {
        let n = Int(seconds * sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { return nil }
        buf.frameLength = AVAudioFrameCount(n)
        let out = buf.floatChannelData![0]
        for i in 0..<n { out[i] = 0 }
        fill(out, n)
        var peak: Float = 0
        for i in 0..<n { peak = max(peak, abs(out[i])) }
        if peak > 0.9 { let k = 0.9 / peak; for i in 0..<n { out[i] *= k } }
        return buf
    }

    /// Diesel idle-ish rumble. Every frequency is a whole number of cycles per loop, so the loop is seamless.
    static func plowEngine() -> AVAudioPCMBuffer? {
        let len = 2.0
        return makeBuffer(seconds: len) { out, n in
            var rng = SeededRandom(seed: 42)
            var lp = 0.0
            for i in 0..<n {
                let t = Double(i) / sampleRate
                // firing pulses at 24 Hz shape a 48 Hz fundamental with harmonics
                let firing = 0.6 + 0.4 * pow(max(0, sin(2 * .pi * 24 * t)), 3)
                var v = 0.0
                for (h, a) in [(48.0, 1.0), (96.0, 0.5), (144.0, 0.3), (192.0, 0.18), (240.0, 0.1)] { v += a * sin(2 * .pi * h * t + h) }
                // a little rattle: low-passed noise
                lp += (Double(rng.next()) * 2 - 1 - lp) * 0.05
                v = v * firing + lp * 0.6
                out[i] = Float(v * 0.2)
            }
        }
    }

    /// Scraping snow: band-limited noise with a slow grainy texture.
    static func plowScrape() -> AVAudioPCMBuffer? {
        return makeBuffer(seconds: 2.0) { out, n in
            var rng = SeededRandom(seed: 7)
            var lp = 0.0, hp = 0.0, prev = 0.0
            for i in 0..<n {
                let t = Double(i) / sampleRate
                let white = Double(rng.next()) * 2 - 1
                lp += (white - lp) * 0.35          // tame the hiss
                hp = 0.97 * (hp + lp - prev)       // remove the rumble
                prev = lp
                let grain = 0.7 + 0.3 * sin(2 * .pi * 7 * t) * sin(2 * .pi * 3 * t)
                out[i] = Float(hp * grain * 0.5)
            }
            let fade = Int(0.02 * sampleRate)
            for i in 0..<fade { let k = Float(i) / Float(fade); out[i] *= k; out[n - 1 - i] *= k }
        }
    }

    /// The leaf collector's suction (autumn's form of the scraping): a rush of air through a wide hose, i.e.
    /// noise shaped by a broad resonance and a hollow one from the hose, over the fan's steady whine.
    static func leafSuction() -> AVAudioPCMBuffer? {
        let len = 3.0
        return makeBuffer(seconds: len) { out, n in
            var rng = SeededRandom(seed: 77)
            let over = Int(0.3 * sampleRate)
            var air = [Float](repeating: 0, count: n + over)
            // two resonators (state-variable band-passes): the rush around 900 Hz and the hose around 260 Hz
            var lowA = 0.0, bandA = 0.0, lowB = 0.0, bandB = 0.0
            let fA: Double = 2 * sin(Double.pi * 900 / sampleRate), fB: Double = 2 * sin(Double.pi * 260 / sampleRate)
            for i in 0..<(n + over) {
                let t: Double = Double(i) / sampleRate
                let white: Double = Double(rng.next()) * 2 - 1
                let highA: Double = white - lowA - 1.4 * bandA
                bandA += fA * highA
                lowA += fA * bandA
                let highB: Double = white - lowB - 0.5 * bandB
                bandB += fB * highB
                lowB += fB * bandB
                // the air flutters a little as leaves pass through (whole cycles per loop)
                let w: Double = 2 * Double.pi * t / len
                let flutter: Double = 0.85 + 0.15 * sin(w * 4) * sin(w * 11 + 0.7)
                air[i] = Float((bandA * 0.55 + bandB * 0.12) * flutter)
            }
            for i in 0..<over {
                let k = Float(i) / Float(over)
                air[i] = air[i] * k + air[n + i] * (1 - k)
            }
            for i in 0..<n {
                let t: Double = Double(i) / sampleRate
                // the fan: a whine with a slow beat between two close tones (all whole cycles per loop)
                let whine: Double = 0.05 * sin(2 * Double.pi * 520 * t) + 0.035 * sin(2 * Double.pi * 524 * t)
                    + 0.02 * sin(2 * Double.pi * 1040 * t) + 0.012 * sin(2 * Double.pi * 1563 * t)
                out[i] = air[i] * 0.8 + Float(whine * 1.6)
            }
        }
    }

    /// Two-tone truck horn: "baa-baaa".
    static func plowHorn() -> AVAudioPCMBuffer? {
        return makeBuffer(seconds: 1.0) { out, n in
            func honk(_ t0: Double, _ len: Double) {
                let start = Int(t0 * sampleRate), count = Int(len * sampleRate)
                for k in 0..<count where start + k < n {
                    let t = Double(k) / sampleRate
                    let env = min(1, t / 0.02) * min(1, (len - t) / 0.05)
                    var v = 0.0
                    for f in [311.0, 370.0] {        // a slightly sour third, like a real truck horn
                        for h in 1...5 { v += sin(2 * .pi * f * Double(h) * t) / Double(h) }
                    }
                    out[start + k] += Float(v * env * 0.12)
                }
            }
            honk(0, 0.22)
            honk(0.32, 0.5)
        }
    }

    // ------------------------------------------------------------------ geese (autumn's flyer)

    /// The two moods of a flock of geese passing over; each trip picks one (alone twice as often as in wind).
    static let gooseMoods = ["alene", "blaest"]

    /// The flock itself is a recording (assets/lyd/gaes-flok.wav, see KILDER.md there; copied into the app's
    /// Resources by the build scripts): synthesized calls sounded far too artificial. It is the project's one
    /// sound file. Mixed to mono at the synth's sample rate, peak 0.6. Nil if the file is missing: no sound then.
    private static let gooseRecording: [Float]? = {
        guard let url = Bundle.main.url(forResource: "gaes-flok", withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url) else { return nil }
        let fmt = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 1, let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames),
              (try? file.read(into: buf)) != nil, let ch = buf.floatChannelData else { return nil }
        let m = Int(buf.frameLength), chans = Int(fmt.channelCount)
        guard m > 1, chans > 0 else { return nil }
        var mono = [Float](repeating: 0, count: m)
        for c in 0..<chans { for i in 0..<m { mono[i] += ch[c][i] / Float(chans) } }
        let ratio: Double = fmt.sampleRate / sampleRate
        let outN = Int(Double(m - 1) / ratio)
        var r = [Float](repeating: 0, count: max(0, outN))
        var peak: Float = 0
        for i in 0..<outN {
            let p: Double = Double(i) * ratio
            let j = min(m - 2, Int(p))
            let f = Float(p - Double(j))
            r[i] = mono[j] * (1 - f) + mono[j + 1] * f
            peak = max(peak, abs(r[i]))
        }
        if peak > 0 { let k = 0.6 / peak; for i in 0..<outN { r[i] *= k } }
        return r
    }()

    /// One seamless loop of geese calling, as long as the recording: 0 = the flock alone, 1 = farther off
    /// (quieter and duller) over synthesized gusts of wind.
    static func geese(mood: Int) -> AVAudioPCMBuffer? {
        guard let rec = gooseRecording else { return nil }
        let over = Int(0.5 * sampleRate)
        guard rec.count > over * 4 else { return nil }
        let seconds = Double(rec.count - over) / sampleRate
        return makeBuffer(seconds: seconds) { out, n in fillGeese(out, n, rec, mood: mood, len: seconds) }
    }

    private static func fillGeese(_ out: UnsafeMutablePointer<Float>, _ n: Int, _ rec: [Float], mood: Int, len: Double) {
        do {
            var rng = SeededRandom(seed: UInt64(1200 + mood))
            func rnd() -> Double { Double(rng.next()) }

            // The recording, its tail cross-faded into its start so the loop has no seam; a far flock is
            // quieter and has lost its brightness (a one-pole low-pass).
            let tail = max(0, min(rec.count - n, n))
            let level: Float = mood == 0 ? 1 : 0.6
            let open: Float = mood == 0 ? 1 : 0.35
            var smooth: Float = 0
            for i in 0..<min(n, rec.count) {
                var s = rec[i]
                if i < tail { let k = Float(i) / Float(tail); s = s * k + rec[n + i] * (1 - k) }
                smooth += (s - smooth) * open
                out[i] = smooth * level
            }

            guard mood > 0 else { return }
            // The wind under the calls: made a little longer than the loop and cross-faded into its own
            // start, so the loop has no seam. (A third mood with rain was tried and dropped: it did not work.)
            let over = Int(0.5 * sampleRate)
            var bed = [Float](repeating: 0, count: n + over)
            var lp1 = 0.0, lp2 = 0.0
            for i in 0..<(n + over) {
                let tt = Double(i) / sampleRate
                let white = rnd() * 2 - 1
                // gusts: the wind grows louder and brighter together (whole cycles per loop)
                let w: Double = 2 * Double.pi * tt / len
                let g: Double = 0.5 + 0.5 * (0.6 * sin(w * 2) + 0.4 * sin(w * 5 + 1.3))
                let gust: Double = g * g
                let a: Double = 0.012 + 0.05 * gust
                lp1 += (white - lp1) * a
                lp2 += (lp1 - lp2) * a
                bed[i] = Float(lp2 * (0.25 + 0.75 * gust) * 1.9)
            }
            for i in 0..<over {
                let k = Float(i) / Float(over)
                bed[i] = bed[i] * k + bed[n + i] * (1 - k)
            }
            for i in 0..<n { out[i] += bed[i] }
        }
    }

    // ------------------------------------------------------------------ synthesis

    /// A tune for Santa's sleigh: melody as (MIDI note, beats; 0 = rest), one bass root per bar.
    /// `bassOffset` is the pickup (beats before the first full bar); the loop is a whole number of bars.
    struct Tune {
        let name: String
        let beat: Double            // seconds per beat
        let beatsPerBar: Int
        let bassOffset: Double
        let melody: [(Int, Double)]
        let bassRoots: [Int]

        static let all = [jingleBells, deckTheHalls, weWishYou]

        static let jingleBells: Tune = {
            let E5 = 76, F5 = 77, G5 = 79, C5 = 72, D5 = 74
            return Tune(name: "jingle-bells", beat: 0.36, beatsPerBar: 4, bassOffset: 0, melody: [
                (E5, 1), (E5, 1), (E5, 2),
                (E5, 1), (E5, 1), (E5, 2),
                (E5, 1), (G5, 1), (C5, 1.5), (D5, 0.5),
                (E5, 4),
                (F5, 1), (F5, 1), (F5, 1.5), (F5, 0.5),
                (F5, 1), (E5, 1), (E5, 1), (E5, 0.5), (E5, 0.5),
                (E5, 1), (D5, 1), (D5, 1), (E5, 1),
                (D5, 2), (G5, 2),
                (E5, 1), (E5, 1), (E5, 2),
                (E5, 1), (E5, 1), (E5, 2),
                (E5, 1), (G5, 1), (C5, 1.5), (D5, 0.5),
                (E5, 4),
                (F5, 1), (F5, 1), (F5, 1.5), (F5, 0.5),
                (F5, 1), (E5, 1), (E5, 1), (E5, 0.5), (E5, 0.5),
                (G5, 1), (G5, 1), (F5, 1), (D5, 1),
                (C5, 3), (0, 1),
            ], bassRoots: [C5, C5, C5, C5, F5, C5, D5, G5, C5, C5, C5, C5, F5, C5, G5, C5].map { $0 - 24 })
        }()

        /// "Deck the Halls", whole verse with its "fa la la" lines, in C.
        static let deckTheHalls: Tune = {
            let B4 = 71, C5 = 72, D5 = 74, E5 = 76, F5 = 77, Fs5 = 78, G5 = 79, A5 = 81, B5 = 83, C6 = 84
            let line1: [(Int, Double)] = [
                (G5, 1.5), (F5, 0.5), (E5, 1), (D5, 1),
                (C5, 1), (D5, 1), (E5, 1), (C5, 1),
                (D5, 0.5), (E5, 0.5), (F5, 0.5), (D5, 0.5), (E5, 1.5), (D5, 0.5),
                (C5, 1), (B4, 1), (C5, 2),
            ]
            let line3: [(Int, Double)] = [
                (D5, 1.5), (E5, 0.5), (F5, 1), (D5, 1),
                (E5, 1.5), (F5, 0.5), (G5, 1), (D5, 1),
                (E5, 0.5), (Fs5, 0.5), (G5, 1), (A5, 0.5), (B5, 0.5), (C6, 1),
                (B5, 1), (A5, 1), (G5, 2),
            ]
            let line4: [(Int, Double)] = [
                (G5, 1.5), (F5, 0.5), (E5, 1), (D5, 1),
                (C5, 1), (D5, 1), (E5, 1), (C5, 1),
                (A5, 0.5), (A5, 0.5), (A5, 0.5), (A5, 0.5), (G5, 1.5), (F5, 0.5),
                (E5, 1), (D5, 1), (C5, 2),
            ]
            let C = 48, F = 53, G = 55, D = 50
            return Tune(name: "deck-the-halls", beat: 0.34, beatsPerBar: 4, bassOffset: 0,
                        melody: line1 + line1 + line3 + line4,
                        bassRoots: [C, C, G, C, C, C, G, C, G, C, D, G, C, C, F, C])
        }()

        /// "We Wish You a Merry Christmas" in 3/4, in C. The pickup note sits at the end of the loop.
        static let weWishYou: Tune = {
            let G4 = 67, A4 = 69, B4 = 71, C5 = 72, D5 = 74, E5 = 76, F5 = 77
            let C = 48, F = 53, G = 55, D = 50, E = 52, A = 45
            return Tune(name: "we-wish-you", beat: 0.4, beatsPerBar: 3, bassOffset: 0, melody: [
                (C5, 1), (C5, 0.5), (D5, 0.5), (C5, 0.5), (B4, 0.5),
                (A4, 1), (A4, 1), (A4, 1),
                (D5, 1), (D5, 0.5), (E5, 0.5), (D5, 0.5), (C5, 0.5),
                (B4, 1), (G4, 1), (G4, 1),
                (E5, 1), (E5, 0.5), (F5, 0.5), (E5, 0.5), (D5, 0.5),
                (C5, 1), (A4, 1), (G4, 0.5), (G4, 0.5),
                (A4, 1), (D5, 1), (B4, 1),
                (C5, 2), (G4, 1),          // "year" + the pickup "We" of the next round
            ], bassRoots: [C, F, D, G, E, A, F, C])
        }()
    }

    /// Renders one loop of `tune`: the melody on a music-box/celesta-like tone, a soft bass and shaken sleigh bells.
    static func jingle(_ tune: Tune) -> AVAudioPCMBuffer? {
        let sampleRate = Synth.sampleRate
        let beat = tune.beat
        let melody = tune.melody
        let totalBeats = melody.reduce(0) { $0 + $1.1 }
        let seconds = totalBeats * beat
        let n = Int(seconds * sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { return nil }
        buf.frameLength = AVAudioFrameCount(n)
        let out = buf.floatChannelData![0]
        for i in 0..<n { out[i] = 0 }

        func freq(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

        /// Celesta-like note: a few slightly inharmonic partials with a bright attack and a ringing decay.
        func addBell(_ t0: Double, _ midi: Int, _ len: Double, _ amp: Double) {
            let f = freq(midi)
            let partials: [(Double, Double, Double)] = [(1, 1.0, 2.2), (2.0, 0.35, 4), (3.01, 0.12, 7), (4.17, 0.06, 10)]
            let dur = min(len + 0.6, 2.5)
            let start = Int(t0 * sampleRate), count = Int(dur * sampleRate)
            for k in 0..<count {
                let idx = start + k
                if idx >= n { break }
                let t = Double(k) / sampleRate
                let attack = min(1, t / 0.004)
                var v = 0.0
                for (mul, a, decay) in partials { v += a * exp(-t * decay) * sin(2 * .pi * f * mul * t) }
                out[idx] += Float(v * amp * attack)
            }
        }

        /// Soft round bass note.
        func addBass(_ t0: Double, _ midi: Int, _ len: Double) {
            let f = freq(midi)
            let start = Int(t0 * sampleRate), count = Int(len * sampleRate)
            for k in 0..<count {
                let idx = start + k
                if idx >= n { break }
                let t = Double(k) / sampleRate
                let env = min(1, t / 0.01) * exp(-t * 3)
                out[idx] += Float(0.16 * env * (sin(2 * .pi * f * t) + 0.3 * sin(4 * .pi * f * t)))
            }
        }

        /// One sleigh bell: a short, bright cluster of inharmonic partials plus a little noise.
        var rng = SeededRandom(seed: 1857)
        func addJingle(_ t0: Double, _ amp: Double) {
            let base = 2300 + Double(rng.next()) * 500
            let partials: [Double] = [1, 1.47, 2.09, 2.56, 3.18]
            let start = Int(t0 * sampleRate), count = Int(0.09 * sampleRate)
            for k in 0..<count {
                let idx = start + k
                if idx >= n || idx < 0 { break }
                let t = Double(k) / sampleRate
                let env = exp(-t * 55)
                var v = 0.0
                for (j, p) in partials.enumerated() { v += sin(2 * .pi * base * p * t + Double(j)) / Double(j + 2) }
                v += (Double(rng.next()) * 2 - 1) * 0.35 * exp(-t * 120)
                out[idx] += Float(v * env * amp)
            }
        }

        // melody
        var t = 0.0
        for (note, len) in melody {
            if note > 0 { addBell(t, note, len * beat, 0.22) }
            t += len * beat
        }
        // bass: the root on the first beat of each bar and the fifth on the third
        let bpb = tune.beatsPerBar
        let bars = Int((totalBeats - tune.bassOffset) / Double(bpb))
        for b in 0..<bars {
            let root = tune.bassRoots[b % tune.bassRoots.count]
            let t0 = tune.bassOffset + Double(b * bpb)
            addBass(t0 * beat, root, beat * 1.8)
            addBass((t0 + 2) * beat, root + 7, beat * (Double(bpb) - 2 + 0.8))
        }
        // sleigh bells: a shake on every eighth note, accented on the beat, each shake a few bells
        var e = 0
        while Double(e) * 0.5 < totalBeats {
            let tb = Double(e) * 0.5 * beat
            let accent = e % 2 == 0 ? 1.0 : 0.6
            for j in 0..<4 { addJingle(tb + Double(j) * 0.012 + Double(rng.next()) * 0.006, 0.05 * accent) }
            e += 1
        }

        // gentle limiter so overlapping notes never clip
        var peak: Float = 0
        for i in 0..<n { peak = max(peak, abs(out[i])) }
        if peak > 0.9 { let k = 0.9 / peak; for i in 0..<n { out[i] *= k } }
        // tiny fades at the loop seam
        let fade = Int(0.01 * sampleRate)
        for i in 0..<fade { let k = Float(i) / Float(fade); out[i] *= k; out[n - 1 - i] *= k }
        return buf
    }

    // ------------------------------------------------------------------ de dødes dag
    /// The butterflies' tune: an original little waltz in D minor (16 bars of 3/4, about 18 s, looping) in the
    /// style of a Mexican son: the melody on a marimba (long notes rolled, as marimba players do) over a guitar
    /// that plays the bass on the first beat and strums the chord on the second and third (down, up, down).
    /// Written for JuleHygge, so it is free of rights.
    static func muertosSon() -> AVAudioPCMBuffer? {
        let beat = 0.38
        let A4 = 69, Cs5 = 73, C5 = 72, D5 = 74, E5 = 76, F5 = 77, G5 = 79, A5 = 81, Bb5 = 82, C6 = 84, D6 = 86
        let melody: [(Int, Double)] = [
            (A4, 1), (D5, 1), (F5, 1),            (A5, 2), (G5, 0.5), (F5, 0.5),
            (E5, 1.5), (F5, 0.5), (G5, 1),        (A5, 2), (0, 1),
            (F5, 1), (E5, 0.5), (D5, 0.5), (F5, 1), (A5, 1), (D6, 1), (A5, 1),
            (Bb5, 1), (A5, 0.5), (G5, 0.5), (F5, 1), (E5, 2), (0, 1),
            (C5, 1), (F5, 1), (A5, 1),            (C6, 2), (A5, 1),
            (Bb5, 1), (G5, 1), (E5, 1),           (E5, 1), (G5, 1), (Bb5, 1),
            (A5, 1.5), (G5, 0.5), (F5, 1),        (F5, 1), (E5, 0.5), (D5, 0.5), (A5, 1),
            (G5, 1), (E5, 1), (Cs5, 1),           (D5, 2), (0, 1),
        ]
        // the guitar's chords, lowest string first (the first note is the bass)
        let Dm = [50, 57, 62, 65], A7 = [45, 52, 55, 61, 64], Gm = [43, 50, 55, 58, 62], Fmaj = [41, 48, 53, 57, 60], C7 = [48, 52, 58, 60, 64]
        let chords = [Dm, Dm, A7, A7, Dm, Dm, Gm, A7, Fmaj, Fmaj, C7, C7, Gm, Dm, A7, Dm]
        let totalBeats = melody.reduce(0) { $0 + $1.1 }
        let n = Int(totalBeats * beat * sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { return nil }
        buf.frameLength = AVAudioFrameCount(n)
        let out = buf.floatChannelData![0]
        for i in 0..<n { out[i] = 0 }
        func freq(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }
        var rng = SeededRandom(seed: 1102)

        /// One marimba stroke: the bar's fundamental with its 4th and 10th partials (a marimba bar is tuned so),
        /// all dying fast, plus a soft knock of the mallet. Wraps round the loop's end, so the seam is clean.
        func strike(_ t0: Double, _ midi: Int, _ amp: Double) {
            let f = freq(midi)
            let start = Int(t0 * sampleRate), count = Int(1.2 * sampleRate)
            for k in 0..<count {
                let t = Double(k) / sampleRate
                let env = min(1, t / 0.002)
                var v = exp(-t * 4.5) * sin(2 * .pi * f * t)
                v += 0.22 * exp(-t * 14) * sin(2 * .pi * f * 4 * t)
                v += 0.05 * exp(-t * 30) * sin(2 * .pi * f * 10 * t)
                v += 0.15 * exp(-t * 300) * sin(2 * .pi * 180 * t)
                out[(start + k) % n] += Float(v * env * amp)
            }
        }

        /// One plucked string (Karplus-Strong): a burst of soft noise circulating in a delay line one period
        /// long, averaged a little each round, so it rings and darkens like a nylon string.
        func pluck(_ t0: Double, _ midi: Int, _ amp: Double, _ len: Double) {
            let period = max(2, Int(sampleRate / freq(midi)))
            var line = [Double](repeating: 0, count: period)
            var prev = 0.0
            for i in 0..<period { let r = Double(rng.next()) * 2 - 1; prev = prev * 0.5 + r * 0.5; line[i] = prev }
            let start = Int(t0 * sampleRate), count = Int(len * sampleRate)
            var i = 0
            for k in 0..<count {
                let j = i % period, j2 = (i + 1) % period
                let v = line[j]
                line[j] = 0.4985 * (line[j] + line[j2])
                let fadeOut = k > count - 800 ? Double(count - k) / 800 : 1
                out[(start + k) % n] += Float(v * amp * fadeOut)
                i += 1
            }
        }

        func strum(_ t0: Double, _ chord: [Int], down: Bool, _ amp: Double) {
            let strings = down ? Array(chord.dropFirst()) : Array(chord.suffix(3).reversed())
            for (k, m) in strings.enumerated() { pluck(t0 + Double(k) * 0.011, m, amp, beat * 1.4) }
        }

        // melody: short notes struck once, long ones rolled
        var t = 0.0
        for (note, len) in melody {
            if note > 0 {
                if len >= 1.5 {
                    var r = 0.0
                    while r < len * beat - 0.1 { strike(t + r, note, r == 0 ? 0.30 : 0.17); r += 0.085 }
                } else {
                    strike(t, note, 0.30)
                }
            }
            t += len * beat
        }
        // guitar: bass on 1, strum down on 2, up on the "and", down on 3
        for (b, chord) in chords.enumerated() {
            let t0 = Double(b * 3) * beat
            pluck(t0, chord[0], 0.38, beat * 2.2)
            strum(t0 + beat, chord, down: true, 0.16)
            strum(t0 + beat * 1.5, chord, down: false, 0.10)
            strum(t0 + beat * 2, chord, down: true, 0.14)
        }

        var peak: Float = 0
        for i in 0..<n { peak = max(peak, abs(out[i])) }
        if peak > 0.9 { let k = 0.9 / peak; for i in 0..<n { out[i] *= k } }
        return buf
    }
}
