import AppKit

typealias F = CGFloat

func R() -> F { F.random(in: 0..<1) }

/// sRGB color from 0–255 components (same argument order as GDI+ Color.FromArgb(r, g, b) with alpha last).
func C(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) -> CGColor {
    CGColor(srgbRed: F(r) / 255, green: F(g) / 255, blue: F(b) / 255, alpha: F(max(0, min(255, a))) / 255)
}

func withAlpha(_ c: CGColor, _ a: Int) -> CGColor { c.copy(alpha: F(max(0, min(255, a))) / 255) ?? c }

func shade(_ c: CGColor, _ f: F) -> CGColor {
    let p = c.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components ?? [0, 0, 0, 1]
    return CGColor(srgbRed: min(1, p[0] * f), green: min(1, p[1] * f), blue: min(1, p[2] * f), alpha: p.count > 3 ? p[3] : 1)
}

enum JuleClock {
    /// Sæt miljøvariablen JULE_DATE=2026-12-10 for at teste julekalender og snemand på en anden dato.
    static var today: Date {
        if let s = ProcessInfo.processInfo.environment["JULE_DATE"], let d = parse(s) { return d }
        return Calendar.current.startOfDay(for: Date())
    }

    static func parse(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: s) else { return nil }
        return Calendar.current.startOfDay(for: d)
    }

    static func format(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    static func parts(_ d: Date) -> (year: Int, month: Int, day: Int) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return (c.year!, c.month!, c.day!)
    }

    static func make(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    static func days(from a: Date, to b: Date) -> Int {
        Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
    }
}

/// Appends errors to ~/Library/Logs/JuleHygge.log (JULE_LOG overrides), capped so a repeating error cannot grow it forever.
enum ErrorLog {
    nonisolated(unsafe) static var written = 0

    static func write(_ msg: String) {
        guard written < 200 else { return }
        written += 1
        let url = ProcessInfo.processInfo.environment["JULE_LOG"].map { URL(fileURLWithPath: $0) }   // tests log inside the project
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/JuleHygge.log")
        let line = "\(JuleClock.format(Date())) \(msg)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func debug(_ msg: String) {
        if ProcessInfo.processInfo.environment["JULE_DEBUG"] == "1" { write("[debug] " + msg) }
    }
}

final class Flake {
    var x: F = 0, y: F = 0, r: F = 0, vy: F = 0, phase: F = 0, sway: F = 0, swaySpd: F = 0, rot: F = 0, rotSpd: F = 0
    var a = 0
    var crystal = false
    /// Which leaf this is, its shape and colour (autumn theme): an index into DotImages.leaves.
    var kind = 0
    /// Only some flakes land on window edges; the rest fall past them.
    var catches = false
}

/// One raindrop in autumn's storm.
struct RainDrop {
    var x: F, y: F, speed: F
}

final class Spark {
    var x: F = 0, y: F = 0, vx: F = 0, vy: F = 0, life: F = 0, max: F = 0, size: F = 0
    var gold = false, star = false
}

final class Nisse {
    var x: F = 0, dir: F = 1, speed: F = 0, walkPhase: F = 0, t: F = 0, stateTimer: F = 0, size: F = 1
    var state = 0           // 0 = går, 1 = står stille, 2 = vinker
    var carriesGift = false
    var variant = ""
    var entering = false, leaving = false, crossing = false
    var tunic = C(115, 120, 130), mitten = C(210, 30, 40), gift = C(40, 140, 70)
    var tunicIndex = 0, giftIndex = 0
    /// Meeting another nisse: both stop face to face, and halfway through the gift changes hands
    /// (handed over, or swapped if both carry one). `meetWith` is set on one of the two only.
    var meetTimer: F = 0, meetCooldown: F = 0
    weak var meetWith: Nisse?
    /// Magic past the children's snowman: gone for `magic` seconds, then back at `magicTo`.
    /// `zoneBumps` counts the turns at the play zone since the last time.
    var magic: F = 0, magicTo: F = 0
    var zoneBumps = 0
    func refreshVariant() { variant = "\(tunicIndex)-\(carriesGift ? giftIndex : -1)" }
}

final class PlowBit {
    var x: F = 0, y: F = 0, vx: F = 0, vy: F = 0, life: F = 0, max: F = 0, size: F = 0
    var smoke = false
    /// Which leaf this is, when the plow is autumn's leaf collector (an index into DotImages.leaves).
    var kind = 0
}

// MARK: - GDI+-agtige tegnehjælpere (y-aksen peger nedad i alle tegnefunktioner)

extension CGContext {
    func fillEllipse(_ c: CGColor, _ x: F, _ y: F, _ w: F, _ h: F) {
        setFillColor(c); fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
    }

    func strokeEllipse(_ c: CGColor, _ width: F, _ x: F, _ y: F, _ w: F, _ h: F) {
        setStrokeColor(c); setLineWidth(width); strokeEllipse(in: CGRect(x: x, y: y, width: w, height: h))
    }

    func fillRect(_ c: CGColor, _ x: F, _ y: F, _ w: F, _ h: F) {
        setFillColor(c); fill(CGRect(x: x, y: y, width: w, height: h))
    }

    func line(_ c: CGColor, _ width: F, _ x1: F, _ y1: F, _ x2: F, _ y2: F, round: Bool = false) {
        setStrokeColor(c); setLineWidth(width); setLineCap(round ? .round : .butt)
        beginPath(); move(to: CGPoint(x: x1, y: y1)); addLine(to: CGPoint(x: x2, y: y2)); strokePath()
    }

    func fillPoly(_ c: CGColor, _ pts: [(F, F)]) {
        guard let f = pts.first else { return }
        setFillColor(c); beginPath(); move(to: CGPoint(x: f.0, y: f.1))
        for p in pts.dropFirst() { addLine(to: CGPoint(x: p.0, y: p.1)) }
        closePath(); fillPath()
    }

    func fill(_ c: CGColor, _ path: CGPath) { setFillColor(c); addPath(path); fillPath() }

    func stroke(_ c: CGColor, _ width: F, _ path: CGPath) {
        setStrokeColor(c); setLineWidth(width); setLineCap(.butt); setLineJoin(.round); addPath(path); strokePath()
    }

    func bezier(_ c: CGColor, _ width: F, _ x0: F, _ y0: F, _ x1: F, _ y1: F, _ x2: F, _ y2: F, _ x3: F, _ y3: F) {
        setStrokeColor(c); setLineWidth(width); setLineCap(.round)
        beginPath(); move(to: CGPoint(x: x0, y: y0))
        addCurve(to: CGPoint(x: x3, y: y3), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
        strokePath()
    }

    /// Fills a path with a linear gradient between two points.
    func fillGradient(_ path: CGPath, _ c1: CGColor, _ c2: CGColor, from: CGPoint, to: CGPoint) {
        guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [c1, c2] as CFArray, locations: [0, 1]) else { return }
        saveGState(); addPath(path); clip()
        drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }
}

extension CGMutablePath {
    func curve(_ x1: F, _ y1: F, _ x2: F, _ y2: F, _ x3: F, _ y3: F) {
        addCurve(to: CGPoint(x: x3, y: y3), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
    }
    func to(_ x: F, _ y: F) { addLine(to: CGPoint(x: x, y: y)) }
    func start(_ x: F, _ y: F) { move(to: CGPoint(x: x, y: y)) }
}

func starPoints(_ cx: F, _ cy: F, _ outer: F, _ inner: F, _ rot: F = 0) -> [(F, F)] {
    (0..<10).map { i in
        let a = -F.pi / 2 + F(i) * F.pi / 5 + rot
        let r = i % 2 == 0 ? outer : inner
        return (cx + cos(a) * r, cy + sin(a) * r)
    }
}

/// Renders a small image (y-down drawing) at the given point size and pixel scale.
func renderImage(width: F, height: F, scale: F, _ draw: (CGContext) -> Void) -> CGImage? {
    let pw = max(1, Int(ceil(width * scale))), ph = max(1, Int(ceil(height * scale)))
    guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.translateBy(x: 0, y: F(ph)); ctx.scaleBy(x: scale, y: -scale)
    draw(ctx)
    return ctx.makeImage()
}

/// One Euro filter (Casiez et al., 2012): smooths a noisy signal strongly while it holds still and follows
/// quickly when it moves, by raising the cutoff frequency with the signal's speed. Used to keep the camera's hat,
/// beard and suit steady without making them lag behind the head.
struct OneEuro {
    /// Cutoff (Hz) while still: lower = steadier. `beta` raises it per unit of speed: higher = less lag when moving.
    var minCutoff: Double, beta: Double, dCutoff: Double = 1
    private var x: Double?, dx: Double = 0
    /// `dCutoff` smooths the speed estimate; kept low so tracking noise is not mistaken for movement.
    /// Tuned on a simulated head (±4 px noise at 30 fps): position (0.3, 0.02, 0.2) shakes ~60 % less than a
    /// plain 0.45 blend and lags 5 px instead of 12 px at 300 px/s.
    init(minCutoff: Double, beta: Double, dCutoff: Double = 0.2) { self.minCutoff = minCutoff; self.beta = beta; self.dCutoff = dCutoff }

    private static func alpha(_ cutoff: Double, _ dt: Double) -> Double { 1 / (1 + 1 / (2 * .pi * cutoff * dt)) }

    mutating func filter(_ v: Double, dt: Double) -> Double {
        guard let prev = x else { x = v; return v }
        let dt = dt > 0 ? dt : 1.0 / 30
        dx += Self.alpha(dCutoff, dt) * ((v - prev) / dt - dx)
        let next = prev + Self.alpha(minCutoff + beta * abs(dx), dt) * (v - prev)
        x = next
        return next
    }
    mutating func filter(_ v: CGFloat, dt: CGFloat) -> CGFloat { CGFloat(filter(Double(v), dt: Double(dt))) }
}
