// Trial: a flock of geese made in code, from what the recording shows when it is measured (sound-probe.swift on
// assets/lyd/gaes-flok.wav, 2026-11-19), to hear whether the recording can be replaced by synthesis.
//
//   swift tools/goose-synth.swift OUT.wav [SEED]
//
// What was measured, and is built in here:
// - A call is short, 70–220 ms, and often two in a row from the same bird (a short lower one, 60–100 ms pause, a
//   longer higher one).
// - Its pitch is high: 730–930 Hz. It rises about 10 % through the first half of the call (733→817 Hz in 60 ms,
//   809→926 Hz in 90 ms) and sinks a per cent or two at the end.
// - The second overtone is the strongest (the first is 8 dB under it, the third 7, then 10, 12, 14, 18, 24, 29):
//   most of the sound lies at 1.5–2 kHz.
// - In many calls the voice breaks for a while into half or a third of its pitch (394–413 Hz against 810, 280
//   against 840): tones appear between the overtones. That roughness is what makes it a goose and not a horn.
// - Four to six calls a second from the whole flock, from birds at different distances.
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else { print("brug: goose-synth UD.wav [FRØ]"); exit(1) }
var seed = UInt64(args.count > 2 ? args[2] : "") ?? 7
func R() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
func R(_ a: Double, _ b: Double) -> Double { a + (b - a) * R() }

let rate = 44100.0, seconds = 16.0, total = Int(rate * seconds)
var out = [Double](repeating: 0, count: total)

/// How strong a tone at `hz` is in a goose's call (dB under the strongest), between the measured overtones.
// (second try: the first one's high overtones came out 5–10 dB stronger than the recording's, so the top is lower)
// (third: still 4–7 dB too much from 3 kHz up, and too little at 1–1.5 kHz, where the broken voice's tones lie)
let shape: [(Double, Double)] = [(0, -34), (425, -17), (850, -8), (1275, -1), (1700, 0), (2125, -4), (2550, -8), (3400, -13), (4250, -17),
                                 (5100, -22), (5950, -28), (6800, -36), (7650, -42), (9000, -50), (12000, -60)]
func level(_ hz: Double, far: Double) -> Double {
    var db = -48.0
    for i in 1..<shape.count where hz <= shape[i].0 {
        let (a, b) = (shape[i - 1], shape[i])
        db = a.1 + (b.1 - a.1) * (hz - a.0) / (b.0 - a.0)
        break
    }
    // the air takes the high tones first: a far bird is duller as well as fainter
    return pow(10, (db - far * 3.2 * hz / 1000) / 20)
}

/// One call: `F` its top pitch, `from` where the pitch starts as a share of it, `split` 0 for a whole voice, 2 or
/// 3 when it breaks into a half or a third of its pitch between `a` and `b` (shares of the call's length).
func call(at t0: Double, length: Double, F: Double, from: Double, gain: Double, far: Double, split: Int, a: Double, b: Double) {
    let n = Int(length * rate), first = Int(t0 * rate)
    var phase = 0.0, wobble = 0.0, flutter = 0.0, hiss = 0.0, hissLow = 0.0, hissTop = 0.0
    // (second try: in the recording's picture no two calls have the same curve. The top comes early in some and
    // late in others, with a point to it, and the pitch falls clearly afterwards; and some calls are hoarse.)
    let top = R(0.3, 0.7), fall = R(0.02, 0.1), rasp = R() < 0.35 ? R(0.3, 0.8) : R(0, 0.15)
    for i in 0..<n {
        let u = Double(i) / Double(n), t = Double(i) / rate
        // pitch: up to its top, down again; never quite steady
        let bend = u < top ? (1 - from) * pow(1 - u / top, 1.3) : fall * pow((u - top) / (1 - top), 1.3)
        wobble += (R(-1, 1) - wobble) * 0.02
        let f = F * (1 - bend) * (1 + (0.012 + 0.03 * rasp) * wobble)
        phase += 2 * .pi * f / rate
        // loudness: a quick start, a slight swell, a short tail
        let attack = min(1, t / 0.012), release = min(1, (length - t) / 0.03)
        flutter += (R(-1, 1) - flutter) * 0.01
        let env = (0.5 - 0.5 * cos(.pi * attack)) * (0.5 - 0.5 * cos(.pi * release)) * (0.8 + 0.2 * sin(.pi * u)) * (1 + 0.1 * flutter)
        // the break: comes and goes softly
        let broken = split == 0 ? 0 : min(1, max(0, min((u - a) / 0.08, (b - u) / 0.08)))
        var s = 0.0
        var h = 1.0
        while h * f < 9000 {
            s += level(h * f, far: far) * sin(h * phase) * (1 - 0.35 * broken)
            if broken > 0 {
                if split == 2 { s += 1.0 * broken * level((h - 0.5) * f, far: far) * sin((h - 0.5) * phase) }
                else {
                    s += 0.8 * broken * level((h - 1.0 / 3) * f, far: far) * sin((h - 1.0 / 3) * phase)
                    s += 0.8 * broken * level((h - 2.0 / 3) * f, far: far) * sin((h - 2.0 / 3) * phase)
                }
            }
            h += 1
        }
        // a little breath in it, where the voice itself is strongest
        // (two steps down from white noise: with one, the breath was brighter than anything in the recording)
        hissTop += (R(-1, 1) - hissTop) * 0.4
        let white = hissTop
        hissLow += (white - hissLow) * 0.35
        hiss += (hissLow - hiss) * 0.12
        s += (0.3 + 2.2 * rasp) * (hissLow - hiss) * (1 - 0.5 * far)
        let k = (first + i) % total
        out[k] += s * env * gain
    }
}

// ---- the flock: each bird has its own voice and distance, and calls when it feels like it
let birds = 9
for bird in 0..<birds {
    let voice = R(800, 960), far = Double(bird) / Double(birds - 1) * 0.95
    let gain = 1 - 0.78 * far
    var t = R(0, 2)
    while t < seconds {
        let F = voice * R(0.975, 1.025)
        let split = R() < 0.5 ? (R() < 0.65 ? 2 : 3) : 0, a = R(0, 0.4), b = R(0.6, 1.05)
        if R() < 0.5 {
            // two in a row: a short lower one, then the longer higher one
            let d1 = R(0.07, 0.10), gap = R(0.06, 0.10)
            call(at: t, length: d1, F: F * 0.89, from: 0.9, gain: gain * 0.7, far: far, split: 0, a: 0, b: 0)
            call(at: t + d1 + gap, length: R(0.12, 0.2), F: F, from: R(0.86, 0.9), gain: gain, far: far, split: split, a: a, b: b)
            t += d1 + gap
        } else {
            call(at: t, length: R(0.09, 0.2), F: F, from: R(0.87, 0.92), gain: gain, far: far, split: split, a: a, b: b)
        }
        // now and then a few calls close together, then a longer pause
        t += 0.35 - 0.9 * log(max(1e-6, R())) * (R() < 0.3 ? 0.3 : 1)
    }
}

// ---- the open air: the calls come back faintly from the ground and the trees (a few soft, duller echoes; they
// wrap round the end, so the loop has no seam), and there is a breath of air under it all. In the first try
// every call stood alone against dead silence, as thin lines in the picture where the recording has a haze.
let dry = out
var dull = 0.0
for (delay, amount) in [(0.031, 0.3), (0.057, 0.22), (0.094, 0.16), (0.151, 0.1)] {
    let d = Int(delay * rate)
    dull = 0
    for i in 0..<(total + 2000) {
        dull += (dry[(i - d + 2 * total) % total] - dull) * 0.25
        if i >= 2000 { out[i % total] += dull * amount } else { _ = dull }
    }
}
var airLow = 0.0, air = 0.0
let callPeak = out.map { abs($0) }.max() ?? 1
for i in 0..<total {
    airLow += (R(-1, 1) - airLow) * 0.02
    air += (airLow - air) * 0.2
    // (faded at the two ends so the loop closes on silence in the air too)
    let edge = min(1, Double(min(i, total - i)) / (0.2 * rate))
    out[i] += air * callPeak * 0.05 * edge
}

// ---- write it (16 bit, one channel)
let peak = out.map { abs($0) }.max() ?? 1
var data = Data()
func put32(_ v: Int) { var x = UInt32(v).littleEndian; data.append(Data(bytes: &x, count: 4)) }
func put16(_ v: Int) { var x = UInt16(truncatingIfNeeded: v).littleEndian; data.append(Data(bytes: &x, count: 2)) }
data.append("RIFF".data(using: .ascii)!); put32(36 + total * 2); data.append("WAVEfmt ".data(using: .ascii)!)
put32(16); put16(1); put16(1); put32(Int(rate)); put32(Int(rate) * 2); put16(2); put16(16)
data.append("data".data(using: .ascii)!); put32(total * 2)
for v in out { put16(Int((v / peak * 0.6 * 32767).rounded())) }
try data.write(to: URL(fileURLWithPath: args[1]))
print("skrev \(args[1]): \(seconds) s, \(birds) gæs")
