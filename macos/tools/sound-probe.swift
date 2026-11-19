// Probe: looks at a sound (16-bit WAV) the way a synthesizer needs to know it. Writes a spectrogram as PNG
// (time across, 0–8 kHz upward) and prints the loudness over time, the pitch of the loud frames, how strong
// each overtone is, and the long-term spectrum.
//
//   swift tools/sound-probe.swift IN.wav OUT.png [FROM_SECONDS TO_SECONDS]
import Accelerate
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let data = FileManager.default.contents(atPath: args[1]), data.count > 44 else { print("brug: sound-probe IND.wav UD.png [FRA TIL]"); exit(1) }
func u16(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 }
func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
// find the fmt and data chunks
var pos = 12, channels = 1, rate = 44100, bits = 16, start = 44, bytes = data.count - 44
while pos + 8 <= data.count {
    let id = String(bytes: data[pos..<pos + 4], encoding: .ascii) ?? "", size = u32(pos + 4)
    if id == "fmt " { channels = u16(pos + 10); rate = u32(pos + 12); bits = u16(pos + 22) }
    if id == "data" { start = pos + 8; bytes = min(size, data.count - start); break }
    pos += 8 + size + (size & 1)
}
guard bits == 16 else { print("kun 16 bit"); exit(1) }
let frames = bytes / (2 * channels)
var x = [Float](repeating: 0, count: frames)
for i in 0..<frames {
    var s = 0
    for c in 0..<channels { let o = start + (i * channels + c) * 2; s += Int(Int16(bitPattern: UInt16(u16(o)))) }
    x[i] = Float(s) / Float(channels) / 32768
}
if args.count >= 5, let a = Double(args[3]), let b = Double(args[4]) {
    x = Array(x[max(0, Int(a * Double(rate)))..<min(frames, Int(b * Double(rate)))])
}
print(String(format: "%d kanaler, %d Hz, %.2f s", channels, rate, Double(x.count) / Double(rate)))

// ---- spectrogram: 1024-point windows (32 ms at 32 kHz), a new one every 5 ms
let N = 1024, hop = rate / 200, half = N / 2
let log2n = vDSP_Length(10)
let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
var window = [Float](repeating: 0, count: N)
vDSP_hann_window(&window, vDSP_Length(N), Int32(vDSP_HANN_NORM))
let count = max(1, (x.count - N) / hop)
var spec = [[Float]](repeating: [], count: count)
var re = [Float](repeating: 0, count: half), im = re, buf = [Float](repeating: 0, count: N)
for t in 0..<count {
    vDSP_vmul(Array(x[(t * hop)..<(t * hop + N)]), 1, window, 1, &buf, 1, vDSP_Length(N))
    var mag = [Float](repeating: 0, count: half)
    re.withUnsafeMutableBufferPointer { rp in im.withUnsafeMutableBufferPointer { ip in
        var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
        buf.withUnsafeBufferPointer { bp in
            bp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half)) }
        }
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvabs(&split, 1, &mag, 1, vDSP_Length(half))
    } }
    spec[t] = mag.map { $0 / Float(N) }
}
let binHz = Double(rate) / Double(N)

// ---- picture: 0–8 kHz, brightness by level (60 dB range)
let top = min(half, Int(8000 / binHz)), W = count, H = top
var px = [UInt8](repeating: 0, count: W * H * 4)
let peak = spec.map { $0.max() ?? 0 }.max() ?? 1
for t in 0..<W { for b in 0..<H {
    let db = 20 * log10(max(1e-9, spec[t][b] / peak))
    let v = max(0, min(1, (db + 60) / 60))
    let i = ((H - 1 - b) * W + t) * 4
    px[i] = UInt8(255 * min(1, v * 1.6)); px[i + 1] = UInt8(255 * max(0, min(1, v * 1.8 - 0.5))); px[i + 2] = UInt8(255 * max(0, v * 3 - 2)); px[i + 3] = 255
} }
let space = CGColorSpaceCreateDeviceRGB()
if let g = px.withUnsafeMutableBytes({ CGContext(data: $0.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage() }) {
    try NSBitmapImageRep(cgImage: g).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
    print("skrev \(args[2]): \(W)×\(H) (5 ms pr. punkt vandret, \(String(format: "%.1f", binHz)) Hz pr. punkt lodret)")
}

// ---- loudness, in tenths of a second
var loud: [Float] = []
for t in stride(from: 0, to: count, by: 20) {
    var e: Float = 0
    for k in t..<min(count, t + 20) { e += spec[k].reduce(0) { $0 + $1 * $1 } }
    loud.append(10 * log10(max(1e-12, e)))
}
let lmax = loud.max() ?? 0
print("styrke pr. 0,1 s (dB under højeste): " + loud.map { String(format: "%.0f", lmax - $0) }.joined(separator: " "))

// ---- pitch of the loud frames: the fundamental that best explains the peaks (harmonic sum, 200–1200 Hz)
func pitch(_ m: [Float]) -> (hz: Double, strength: Float) {
    var best = 0.0, bestV: Float = 0, total: Float = 0
    for b in 4..<top { total += m[b] }
    var f = 200.0
    while f < 1200 {
        var v: Float = 0
        for h in 1...8 {
            let b = Int((f * Double(h) / binHz).rounded())
            if b + 1 < half { v += max(m[b - 1], m[b], m[b + 1]) / Float(h).squareRoot() }
        }
        if v > bestV { bestV = v; best = f }
        f *= 1.01
    }
    return (best, total > 0 ? bestV / total : 0)
}
// (the harmonic sum above proved a poor judge of how sure the pitch is; the waveform's own repetition is better:
// the shortest lag at which a 32 ms frame is nearly as like itself as at its best lag, 250–1300 Hz)
func repeats(_ t: Int) -> (hz: Double, strength: Float) {
    let a = t * hop, lo = rate / 1300, hi = rate / 250
    var r0: Float = 0
    vDSP_svesq(Array(x[a..<a + N]), 1, &r0, vDSP_Length(N))
    guard r0 > 0 else { return (0, 0) }
    var r = [Float](repeating: 0, count: hi + 2)
    for lag in lo...(hi + 1) {
        var s: Float = 0
        x.withUnsafeBufferPointer { p in vDSP_dotpr(p.baseAddress! + a, 1, p.baseAddress! + a + lag, 1, &s, vDSP_Length(N - lag)) }
        r[lag] = s / r0 * Float(N) / Float(N - lag)
    }
    let best = r[lo...hi].max() ?? 0
    for lag in (lo + 1)..<hi where r[lag] >= best * 0.9 && r[lag] >= r[lag - 1] && r[lag] >= r[lag + 1] {
        // the peak's place between the samples
        let d = r[lag - 1] - 2 * r[lag] + r[lag + 1], off = d != 0 ? Double(0.5 * (r[lag - 1] - r[lag + 1]) / d) : 0
        return (Double(rate) / (Double(lag) + off), r[lag])
    }
    return (0, 0)
}
_ = pitch
var hist = [Int](repeating: 0, count: 21), harm = [Float](repeating: 0, count: 12), harmN: Float = 0
let energy = spec.map { $0.reduce(0) { $0 + $1 * $1 } }, emax = energy.max() ?? 1
var track = ""
for t in 0..<count where energy[t] > emax * 0.02 {
    let (hz, s) = repeats(t)
    if count < 600, t % 2 == 0 { track += s > 0.5 ? String(format: " %d:%.0f", t * 5, hz) : String(format: " %d:-", t * 5) }
    guard s > 0.5 else { continue }
    hist[min(20, Int((hz - 200) / 50))] += 1
    for h in 1...12 { let b = Int((hz * Double(h) / binHz).rounded()); if b + 1 < half { harm[h - 1] += max(spec[t][b - 1], spec[t][b], spec[t][b + 1]) } }
    harmN += 1
}
if !track.isEmpty { print("tonehøjde over tid (ms:Hz, - = ingen klar tone):" + track) }
print("tonehøjde i de kraftige øjeblikke (antal pr. 50 Hz fra 200 Hz): " + hist.enumerated().map { "\(200 + $0.offset * 50):\($0.element)" }.joined(separator: " "))
if harmN > 0 {
    let h1 = max(1e-9, harm.max() ?? 1)
    print("overtonernes styrke (dB under den stærkeste), 1.–12.: " + harm.map { String(format: "%.0f", -20 * log10(max(1e-9, $0 / h1))) }.joined(separator: " "))
}
// ---- long-term spectrum in 250 Hz bands
var bands = [Float](repeating: 0, count: 32)
for t in 0..<count { for b in 0..<top { bands[min(31, Int(Double(b) * binHz / 250))] += spec[t][b] * spec[t][b] } }
let bmax = bands.max() ?? 1
print("gennemsnitligt spektrum pr. 250 Hz (dB under toppen): " + bands.map { String(format: "%.0f", -10 * log10(max(1e-12, $0 / bmax))) }.joined(separator: " "))
