import AppKit
import CoreImage
import Vision
import simd

/// A virtual nisse hat in the JuleHygge Kamera picture, built on the head's measured outline.
///
/// Nothing here assumes a particular person, head shape, hair, camera or seat. Every frame measures:
/// 1. **Where the head is and what shape it has: the person mask.** The head's outline (with hair) is scanned from
///    below the eyes to the top of the head, along the head's own axis. The hat's brim is exactly as wide as the
///    outline is at the brim's height, and the cloth is the smallest bulging shape (no waist) around the outline
///    above the brim and the hat's tip. So the hat cannot leave the head or be drawn across its outline, whatever
///    the angles say.
/// 2. **How the head is turned: Vision's face angles** (roll, yaw, pitch of the face rectangle, relative to the
///    camera). They only shape the hat: how the brim curves across the forehead, which way the tip leans. A camera
///    that looks up at the person, or down, is just another pitch. Yaw is checked against the outline in every
///    frame (the face sits off-centre in the outline when the head is turned), and a reading that disagrees with
///    both the outline and the last frames is not used.
/// 3. **How big the hat is: the head's greatest breadth** (with hair, from just below the eyes up), which does not change when the head nods
///    or when the camera looks up or down at it. The hat's own proportions (fur, length) are multiples of it.
///
/// The one thing a single frame cannot show is how deep the head is compared to its breadth. It starts as an
/// ordinary head and is learned from how the outline's width changes as the person turns. Until then a turned
/// head's breadth is only as good as that start.
///
/// Vision's angles: the head turns about its own upright axis (yaw), then nods (pitch), then tilts in the picture
/// (roll): R = Rz(roll)·Rx(pitch)·Ry(yaw). So the roll is the direction of the head's upright axis in the picture,
/// not of the eye line. (Checked against live readings 2026-11-17: with the head turned and seen from below, the
/// eye line slopes by atan(sin pitch · tan yaw) more than the roll, as this order predicts; the other order,
/// where the roll is the eye line's slope, did not fit.)
final class NisseHat {
    /// Face rectangles (the landmarks request is run on these; see Costume.detect).
    let request: VNDetectFaceRectanglesRequest = {
        let r = VNDetectFaceRectanglesRequest()
        if VNDetectFaceRectanglesRequest.supportedRevisions.contains(VNDetectFaceRectanglesRequestRevision3) {
            r.revision = VNDetectFaceRectanglesRequestRevision3
        }
        return r
    }()

    /// Vision's roll sign mapped to ours (counter-clockwise positive, y up). Used by the costume too.
    static let rollSign: CGFloat = 1

    typealias V = SIMD3<Double>
    typealias P2 = SIMD2<Double>

    // ------------------------------------------------------------------ the hat's own proportions
    // All in units of U: half the head's greatest breadth (with hair, from just below the eyes up), as measured. These describe the hat,
    // not the person.

    /// The brim lies on a tilted plane: high on the forehead, low at the nape.
    static let brimTilt = 0.30
    /// Radius of the fur band's tufts, and the gap between the eyebrows and the fur's lower edge.
    static let fur = 0.13, browGap = 0.14
    /// The fur band reaches this many tuft radii below its centre line.
    static let furBelow = 1.5
    /// The cloth lies this far outside the measured outline.
    static let cloth = 0.05
    /// How far the cone reaches above the top of the head, and where it starts to bend over.
    static let free = 2.2, bendStart = 0.3
    /// How far the tip bends over (radians).
    static let bend = 2.3
    static let pompom = 0.22
    /// The outline is measured from this far below the eyes.
    static let below = 1.5
    /// Depth of a head against its breadth before the person has turned (with hair); then learned.
    static let ordinaryDepth = 1.25

    // ------------------------------------------------------------------ one frame's measurements

    /// What Vision shows of one face, in output pixels (y up) and radians.
    /// Yaw: positive toward the picture's right. Pitch: positive nodding down. Both relative to the camera.
    struct Face {
        var eye: CGPoint      // between the eyes
        var brow: CGPoint     // between the eyebrows
        var chin: CGPoint
        var roll: Double, yaw: Double, pitch: Double
    }

    /// The person mask, read in output coordinates.
    struct MaskReader {
        let base: UnsafePointer<UInt8>
        let w: Int, h: Int, rowBytes: Int
        /// output → mask pixels
        let ax: Double, bx: Double, cx: Double, ay: Double, by: Double, cy: Double
        /// one mask pixel in output pixels
        let px: Double

        init(base: UnsafePointer<UInt8>, w: Int, h: Int, rowBytes: Int, extent: CGRect, inverse inv: CGAffineTransform) {
            self.base = base; self.w = w; self.h = h; self.rowBytes = rowBytes
            let sx = Double(w) / Double(extent.width), sy = Double(h) / Double(extent.height)
            // camera x = inv.a·x + inv.c·y + inv.tx; mask x = (camera x − minX)·sx − ½
            ax = Double(inv.a) * sx; bx = Double(inv.c) * sx; cx = (Double(inv.tx) - Double(extent.minX)) * sx - 0.5
            // mask rows run downwards
            ay = -Double(inv.b) * sy; by = -Double(inv.d) * sy; cy = Double(h) - (Double(inv.ty) - Double(extent.minY)) * sy - 0.5
            px = 1 / max(1e-6, hypot(Double(inv.a), Double(inv.b)) * sx)
        }

        /// The mask at an output point, 0…255, between the mask's pixels.
        func value(_ x: Double, _ y: Double) -> Double {
            let fx = ax * x + bx * y + cx, fy = ay * x + by * y + cy
            let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
            guard x0 >= -1, y0 >= -1, x0 < w, y0 < h else { return 0 }
            func at(_ ix: Int, _ iy: Int) -> Double { ix < 0 || iy < 0 || ix >= w || iy >= h ? 0 : Double(base[iy * rowBytes + ix]) }
            let tx = fx - Double(x0), ty = fy - Double(y0)
            let top = at(x0, y0) * (1 - tx) + at(x0 + 1, y0) * tx
            let bottom = at(x0, y0 + 1) * (1 - tx) + at(x0 + 1, y0 + 1) * tx
            return top * (1 - ty) + bottom * ty
        }
    }

    /// The head's outline in one frame, in the head's own frame: origin between the eyes, x along the eye line,
    /// v up along the head. Each row has the outline's left and right edge (nil where the row ran into something
    /// that is not the head: a shoulder, a raised hand).
    struct Scan {
        var rows: [(v: Double, l: Double?, r: Double?)]
        var crown: Double, crownX: Double
    }

    /// Scans the head's outline in the mask, from `low` below the eyes upward. `reach` is how far to the side a
    /// row may run before it is taken to have left the head (a shoulder, a raised arm), `tall` how far up the
    /// head may go; both generous.
    static func scan(_ m: MaskReader, eye: CGPoint, roll: Double, low: Double, reach limit: Double, tall: Double) -> Scan? {
        let rx = cos(roll), ry = sin(roll), ex = Double(eye.x), ey = Double(eye.y)
        func val(_ x: Double, _ v: Double) -> Double { m.value(ex + rx * x - ry * v, ey + ry * x + rx * v) }
        let step = max(1, m.px * 0.6)
        let dv = max(step, tall / 90)
        /// The edge from an inside point along the row; nil if it never ends within reach.
        func edge(_ x0: Double, _ v: Double, _ dir: Double) -> Double? {
            var x = x0, lastIn = x0, lastVal = val(x0, v), gap = 0
            while abs(x - x0) < limit {
                x += dir * step
                let a = val(x, v)
                if a >= 127 { lastIn = x; lastVal = a; gap = 0 } else {
                    gap += 1
                    if gap > 2 {
                        let out = val(lastIn + dir * step, v)
                        return lastIn + dir * step * min(1, max(0, (lastVal - 127) / max(1, lastVal - out)))
                    }
                }
            }
            return nil
        }
        var rows: [(v: Double, l: Double?, r: Double?)] = []
        var mid = 0.0, span = (-0.25 * limit, 0.25 * limit), misses = 0
        var v = -low
        var ended = false
        while v < tall {
            var x0: Double? = val(mid, v) >= 127 ? mid : nil
            if x0 == nil {   // the nearest inside point within the row below
                var o = step
                while o <= max(span.1 - mid, mid - span.0) {
                    if mid + o <= span.1, val(mid + o, v) >= 127 { x0 = mid + o; break }
                    if mid - o >= span.0, val(mid - o, v) >= 127 { x0 = mid - o; break }
                    o += step
                }
            }
            guard let x = x0 else {
                if !rows.isEmpty { misses += 1; if misses > 2 { ended = true; break } }
                v += dv; continue
            }
            misses = 0
            let l = edge(x, v, -1), r = edge(x, v, 1)
            rows.append((v, l, r))
            if let l, let r { mid = (l + r) / 2; span = (l, r) }
            v += dv
        }
        // the head must end (otherwise something else in the mask continues above it)
        guard ended, let last = rows.last, rows.count >= 8 else { return nil }
        // the top of the head: straight up from the middle of the top row
        var top = last.v, lastVal = val(mid, last.v), up = last.v
        while up < last.v + 4 * dv {
            up += step
            let a = val(mid, up)
            if a >= 127 { top = up; lastVal = a } else {
                top += step * min(1, max(0, (lastVal - 127) / max(1, lastVal - a))); break
            }
        }
        guard top > 0.12 * tall else { return nil }
        return Scan(rows: rows, crown: top, crownX: mid)
    }

    // ------------------------------------------------------------------ tracking

    /// A measured value whose sudden jumps are doubted. Several readings in a row show where the value is going;
    /// one reading far from there is most likely a misreading and is left out, unless the next frames agree with
    /// it. "Far" is judged against how much this value usually strays in the current conditions.
    struct Gated {
        var last: Double, speed = 0.0, typical: Double, held = 0
        let floor: Double
        init(_ v: Double, floor: Double) { last = v; self.floor = floor; typical = floor / 4 }
        /// Returns the value to use, and whether the reading was left out.
        mutating func take(_ v: Double, dt: Double) -> (Double, Bool) {
            let expected = last + speed * dt
            let off = abs(v - expected)
            if off > max(floor, 4 * typical), held < 3 {
                held += 1; speed *= 0.5
                return (last, true)
            }
            if held == 0 { typical += (min(off, 4 * max(typical, floor / 4)) - typical) * 0.05 }
            held = 0
            speed += ((v - last) / max(dt, 1e-3) - speed) * 0.5
            last = v
            return (v, false)
        }
    }

    static let samples = 34

    final class Track {
        var lost: CGFloat = 0, fresh = true
        /// where the face was last seen (to recognise it in the next frame)
        var seen: CGPoint
        // ---- what is drawn (all steadied)
        /// origin of the head's frame in the picture: on the eye line, in the middle of the head's outline
        var origin: CGPoint
        var roll: Double, yaw: Double, pitch: Double
        /// the hat's yardstick: half the head's greatest breadth, pixels
        var U: Double
        /// the head's height in the picture (crown to chin) and the usual nod: only to compare frames when learning the depth
        var tall: Double, usualPitch: Double
        /// heights above the eye line: eyebrows, top of the head; and the top's sideways position
        var browV: Double, crownV: Double, crownX: Double
        /// This frame's outline exactly as scanned (not steadied): rows by height above the eye line, edges sideways
        /// from `scanOrigin` (nil where a row ran out of the head). For what must lie exactly on the outline.
        var scanRows: [(v: Double, l: Double?, r: Double?)] = []
        var scanOrigin = CGPoint.zero
        /// the chin's height (below the eye line, so negative)
        var chinV = 0.0
        /// the chin's sideways position from the head frame's origin
        var chinX = 0.0
        var fChin = OneEuro(minCutoff: 0.5, beta: 0.03), fChinX = OneEuro(minCutoff: 0.5, beta: 0.03)
        /// the outline's left and right edge at `samples` heights from `below·U` under the eyes to the crown
        var l: [Double], r: [Double]
        /// depth of the head against its breadth, learned from the outline while the person turns
        var depth = NisseHat.ordinaryDepth
        /// The crown's height above the eye line as a share of the head's breadth, learned while the head is seen
        /// straight on (see `parts`); nil until then.
        var crownShare: Double?
        var sums = (cc: 0.0, cs: 0.0, ss: 0.0, bc: 0.0, bs: 0.0)
        // ---- steadying
        var fOrigin = [OneEuro(minCutoff: 0.9, beta: 0.03), OneEuro(minCutoff: 0.9, beta: 0.03)]
        var fAngle = (0..<3).map { _ in OneEuro(minCutoff: 0.8, beta: 2.0, dCutoff: 1.0) }
        var fU = OneEuro(minCutoff: 0.3, beta: 0.02), fTall = OneEuro(minCutoff: 0.12, beta: 0.01)
        var fBrow = OneEuro(minCutoff: 0.5, beta: 0.03), fCrown = OneEuro(minCutoff: 0.6, beta: 0.03), fCrownX = OneEuro(minCutoff: 0.6, beta: 0.03)
        var fL: [OneEuro], fR: [OneEuro]
        var gRoll: Gated, gYaw: Gated, gPitch: Gated
        var gL: [Gated], gR: [Gated]
        /// how far Vision's yaw usually is from what the outline suggests
        var yawGap = 0.15, yawDoubt = 0
        // ---- for the log
        var yawFromOutline = 0.0, leftOut = (angles: 0, edges: 0), ringHalf = 0.0

        init(face f: Face, origin o: CGPoint, U: Double, tall: Double, browV: Double, crownV: Double, crownX: Double, l: [Double], r: [Double]) {
            seen = f.eye; origin = o
            roll = f.roll; yaw = f.yaw; pitch = f.pitch
            self.U = U; self.tall = tall; usualPitch = f.pitch; self.browV = browV; self.crownV = crownV; self.crownX = crownX; self.l = l; self.r = r
            fL = l.map { _ in OneEuro(minCutoff: 0.6, beta: 0.04) }; fR = fL
            gRoll = Gated(f.roll, floor: 0.2); gYaw = Gated(f.yaw, floor: 0.25); gPitch = Gated(f.pitch, floor: 0.2)
            gL = l.map { Gated($0, floor: 0.18 * U) }; gR = r.map { Gated($0, floor: 0.18 * U) }
            _ = fOrigin[0].filter(Double(o.x), dt: 0); _ = fOrigin[1].filter(Double(o.y), dt: 0)
            _ = fAngle[0].filter(roll, dt: 0); _ = fAngle[1].filter(yaw, dt: 0); _ = fAngle[2].filter(pitch, dt: 0)
            _ = fU.filter(U, dt: 0); _ = fTall.filter(tall, dt: 0); _ = fBrow.filter(browV, dt: 0); _ = fCrown.filter(crownV, dt: 0); _ = fCrownX.filter(crownX, dt: 0)
            for i in l.indices { _ = fL[i].filter(l[i], dt: 0); _ = fR[i].filter(r[i], dt: 0) }
        }
    }
    private(set) var tracks: [Track] = []
    private static let keepLost: CGFloat = 0.4, fadeOut: CGFloat = 0.3
    private var lastLog: CFTimeInterval = 0

    /// What Vision found in a face, in output coordinates. Needs the landmarks (eyes, chin).
    static func face(_ o: VNFaceObservation, extent: CGRect, transform: CGAffineTransform) -> Face? {
        guard let lm = o.landmarks, let le = lm.leftEye, let re = lm.rightEye, let contour = lm.faceContour else { return nil }
        func pts(_ r: VNFaceLandmarkRegion2D) -> [CGPoint] {
            r.pointsInImage(imageSize: extent.size).map { CGPoint(x: $0.x + extent.minX, y: $0.y + extent.minY).applying(transform) }
        }
        func mean(_ p: [CGPoint]) -> CGPoint { CGPoint(x: p.map(\.x).reduce(0, +) / CGFloat(p.count), y: p.map(\.y).reduce(0, +) / CGFloat(p.count)) }
        let e1 = pts(le), e2 = pts(re), c = pts(contour)
        guard !e1.isEmpty, !e2.isEmpty, c.count >= 3 else { return nil }
        let a = mean(e1), b = mean(e2)
        let eye = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let chin = c[c.count / 2]
        var brow: CGPoint
        if let lb = lm.leftEyebrow, let rb = lm.rightEyebrow, lb.pointCount > 0, rb.pointCount > 0 {
            let p = mean(pts(lb)), q = mean(pts(rb))
            brow = CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
        } else {
            // no eyebrows found: about a fifth of the way from the chin to the eyes further up, as on most faces
            brow = CGPoint(x: eye.x + (eye.x - chin.x) * 0.2, y: eye.y + (eye.y - chin.y) * 0.2)
        }
        let yaw = o.yaw?.doubleValue ?? 0, pitch = o.pitch?.doubleValue ?? 0
        guard [eye.x, eye.y, chin.x, chin.y, brow.x, brow.y, a.x, a.y, b.x, b.y].allSatisfy({ $0.isFinite }), yaw.isFinite, pitch.isFinite else { return nil }
        let (l, r) = a.x < b.x ? (a, b) : (b, a)
        let roll = o.roll.map { Double(rollSign) * $0.doubleValue } ?? Double(atan2(r.y - l.y, r.x - l.x))
        guard roll.isFinite else { return nil }
        return Face(eye: eye, brow: brow, chin: chin, roll: roll, yaw: yaw, pitch: pitch)
    }

    /// Feeds this frame's landmark results. `extent` is the camera image, `transform` the same aspect-fill transform
    /// the camera picture gets.
    func update(_ observations: [VNFaceObservation], mask: CVPixelBuffer? = nil, extent: CGRect, transform: CGAffineTransform, dt: CGFloat) {
        let faces = observations.prefix(3).compactMap { Self.face($0, extent: extent, transform: transform) }
        guard let mask else { feed(faces, mask: nil, dt: Double(dt)); return }
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask)?.assumingMemoryBound(to: UInt8.self) else { feed(faces, mask: nil, dt: Double(dt)); return }
        let reader = MaskReader(base: UnsafePointer(base), w: CVPixelBufferGetWidth(mask), h: CVPixelBufferGetHeight(mask),
                                rowBytes: CVPixelBufferGetBytesPerRow(mask), extent: extent, inverse: transform.inverted())
        feed(faces, mask: reader, dt: Double(dt))
    }

    /// One frame: the faces Vision found and the person mask.
    func feed(_ faces: [Face], mask: MaskReader?, dt: Double) {
        for t in tracks { t.fresh = false }
        if let mask { for f in faces { measure(f, mask, dt) } }
        // A value that is not a number would stay in the steadying for ever and make the head unrecognisable in
        // every later frame (live 2026-11-17: the hat then started over about once a second). Such a head is
        // dropped, and the log says which value it was.
        tracks.removeAll { t in
            let values: [(String, Double)] = [("sted", Double(t.seen.x + t.seen.y)), ("midte", Double(t.origin.x + t.origin.y)), ("hæld", t.roll), ("drej", t.yaw), ("nik", t.pitch),
                                              ("bredde", t.U), ("højde", t.tall), ("bryn", t.browV), ("isse", t.crownV + t.crownX), ("hage", t.chinV),
                                              ("dybde", t.depth), ("omrids", t.l.reduce(0, +) + t.r.reduce(0, +))]
            guard let bad = values.first(where: { !$0.1.isFinite }) else { return false }
            camLog.error("hue: hoved droppet, ugyldig værdi i \(bad.0, privacy: .public)")
            return true
        }
        for t in tracks where !t.fresh { t.lost += CGFloat(dt) }
        tracks.removeAll { $0.lost > Self.keepLost + Self.fadeOut }
        let now = CACurrentMediaTime()
        if now - lastLog > 2, let t = tracks.first(where: { $0.fresh }) {
            lastLog = now
            camLog.info("hue: drej vision \(String(format: "%.2f", t.gYaw.last), privacy: .public) omrids \(String(format: "%.2f", t.yawFromOutline), privacy: .public) (typisk afstand \(String(format: "%.2f", t.yawGap), privacy: .public)) nik \(String(format: "%.2f", t.pitch), privacy: .public) hæld \(String(format: "%.2f", t.roll), privacy: .public) | halv hovedbredde \(String(format: "%.0f", t.U), privacy: .public) px, halvt omrids ved kanten \(String(format: "%.0f", t.ringHalf), privacy: .public) px, dybde/bredde \(String(format: "%.2f", t.depth), privacy: .public) | udeladt siden sidst: vinkler \(t.leftOut.angles, privacy: .public), kantpunkter \(t.leftOut.edges, privacy: .public)")
            t.leftOut = (0, 0)
        }
    }

    /// Why a frame's measurement was not used (logged at most once a second).
    private var lastNote: CFTimeInterval = 0, newTracks = 0
    private func note(_ why: String, _ t: Track?) {
        let now = CACurrentMediaTime()
        guard now - lastNote > 1 else { return }
        lastNote = now
        camLog.info("hue: måling ikke brugt: \(why, privacy: .public) (\(t == nil ? "nyt hoved" : "kendt hoved", privacy: .public), \(self.tracks.count, privacy: .public) hoveder, \(self.newTracks, privacy: .public) nye i alt)")
    }

    private func measure(_ f: Face, _ m: MaskReader, _ dt: Double) {
        let near = tracks.filter { !$0.fresh && $0.seen.x.isFinite && $0.seen.y.isFinite && $0.U.isFinite }.min { hypot($0.seen.x - f.eye.x, $0.seen.y - f.eye.y) < hypot($1.seen.x - f.eye.x, $1.seen.y - f.eye.y) }
        let t = near.flatMap { hypot($0.seen.x - f.eye.x, $0.seen.y - f.eye.y) < CGFloat(2 * $0.U) ? $0 : nil }
        // the head's own upright direction in the picture: the roll (steadied with the track, so the outline is
        // measured in a calm frame)
        var roll = f.roll
        if let t {
            let (v, out) = t.gRoll.take(f.roll, dt: dt)
            if out { t.leftOut.angles += 1 }
            roll = t.fAngle[0].filter(v, dt: dt)
        }
        let rx = cos(roll), ry = sin(roll)
        func height(_ p: CGPoint) -> Double { -ry * Double(p.x - f.eye.x) + rx * Double(p.y - f.eye.y) }
        let chinV = height(f.chin), browRaw = height(f.brow)
        let eyeToChin = Double(hypot(f.chin.x - f.eye.x, f.chin.y - f.eye.y))
        guard eyeToChin > 12 else { return }
        // how far to look: by the head as measured so far, else by the face (generously)
        let low = t.map { 1.7 * $0.U } ?? 1.2 * eyeToChin
        let reach = t.map { 2.3 * $0.U } ?? 1.7 * eyeToChin
        let tall = t.map { 5.5 * $0.U } ?? 3.6 * eyeToChin
        guard let sc = Self.scan(m, eye: f.eye, roll: roll, low: low, reach: reach, tall: tall) else { note("intet hovedomrids fundet", t); return }
        let tallRaw = sc.crown - chinV
        guard tallRaw.isFinite, tallRaw > 8, sc.crownX.isFinite, browRaw.isFinite else { note("ugyldig højde", t); return }
        // the head's size must be believable against what it was (else: something else was measured)
        if let t, tallRaw < 0.5 * t.tall || tallRaw > 1.8 * t.tall { note(String(format: "hovedhøjde %.0f mod før %.0f", tallRaw, t.tall), t); return }
        // the outline at fixed fractions of the way from below the eyes to the crown
        let K = Self.samples
        // (a new head has no breadth yet: a first value from the row at the eyes)
        var U = t?.U ?? 0
        if t == nil {
            guard let row = sc.rows.first(where: { $0.v >= 0 }), let l = row.l, let r = row.r, r - l > 16 else { return }
            let R = Self.headRotation(yaw: f.yaw, pitch: f.pitch)
            let X = R * V(1, 0, 0), Z = R * V(0, 0, 1)
            U = (r - l) / 2 / max(0.35, (X.x * X.x + Self.ordinaryDepth * Self.ordinaryDepth * Z.x * Z.x).squareRoot())
        }
        let vLow = -Self.below * U
        func side(_ pick: ((v: Double, l: Double?, r: Double?)) -> Double?) -> [Double]? {
            let valid = sc.rows.compactMap { row in pick(row).map { (row.v, $0) } }
            guard valid.count >= 6 else { return nil }
            return (0..<K).map { k in
                let v = vLow + (sc.crown - vLow) * 0.97 * Double(k) / Double(K - 1)
                guard let hi = valid.firstIndex(where: { $0.0 >= v }) else { return valid[valid.count - 1].1 }
                if hi == 0 { return valid[0].1 }
                let a = valid[hi - 1], b = valid[hi]
                return a.1 + (b.1 - a.1) * (v - a.0) / max(1e-6, b.0 - a.0)
            }
        }
        guard var l = side({ $0.l }), var r = side({ $0.r }), (l + r).allSatisfy({ $0.isFinite }) else { note("for få rækker med kant", t); return }
        // the head frame's origin: on the eye line, in the middle of the outline there
        let eyeIndex = Double(K - 1) * (0 - vLow) / max(1, (sc.crown - vLow) * 0.97)
        let i0 = min(K - 2, max(0, Int(eyeIndex))), w0 = min(1, max(0, eyeIndex - Double(i0)))
        let l0 = l[i0] + (l[i0 + 1] - l[i0]) * w0, r0 = r[i0] + (r[i0 + 1] - r[i0]) * w0
        let x0 = (l0 + r0) / 2, half0 = max(4, (r0 - l0) / 2)
        for i in 0..<K { l[i] -= x0; r[i] -= x0 }
        let crownX = sc.crownX - x0
        let chinX = rx * Double(f.chin.x - f.eye.x) + ry * Double(f.chin.y - f.eye.y) - x0
        let origin = CGPoint(x: Double(f.eye.x) + rx * x0, y: Double(f.eye.y) + ry * x0)
        // how far the head is turned, as the outline shows it: the face sits off the outline's middle
        let fromOutline = asin(min(1, max(-1, -x0 / half0)))

        let scanRows = sc.rows.map { (v: $0.v, l: $0.l.map { $0 - x0 }, r: $0.r.map { $0 - x0 }) }
        guard let t else {
            let n = Track(face: f, origin: origin, U: U, tall: tallRaw, browV: browRaw, crownV: sc.crown, crownX: crownX, l: l, r: r)
            n.roll = roll; n.yawFromOutline = fromOutline; n.scanRows = scanRows; n.scanOrigin = origin; n.chinV = n.fChin.filter(chinV, dt: 0); n.chinX = n.fChinX.filter(chinX, dt: 0)
            tracks.append(n); newTracks += 1
            note(String(format: "nyt hoved ved %.0f,%.0f (nærmeste kendte %.0f px væk, grænse %.0f)", f.eye.x, f.eye.y, near.map { Double(hypot($0.seen.x - f.eye.x, $0.seen.y - f.eye.y)) } ?? -1, near.map { 2 * $0.U } ?? -1), nil)
            return
        }
        t.seen = f.eye; t.lost = 0; t.fresh = true
        t.scanRows = scanRows; t.scanOrigin = origin
        t.roll = roll
        // yaw: Vision's reading, unless it is far from both the outline and where the last frames were going
        let gap = abs(f.yaw - fromOutline)
        let trusted = t.gYaw.last
        var (yaw, yawOut) = t.gYaw.take(f.yaw, dt: dt)
        if !yawOut, gap > max(0.5, 3 * t.yawGap), abs(fromOutline - trusted) < abs(f.yaw - trusted), t.yawDoubt < 3 {
            // (the gate has already taken it; put the last trusted value back)
            t.yawDoubt += 1
            yaw = trusted; yawOut = true; t.gYaw.last = trusted
        } else if !yawOut { t.yawDoubt = 0 }
        // the usual gap follows every frame, so a head whose outline is lopsided (hair) is not doubted for ever
        t.yawGap += (min(gap, 1) - t.yawGap) * 0.03
        if yawOut { t.leftOut.angles += 1 }
        t.yawFromOutline = fromOutline
        t.yaw = t.fAngle[1].filter(yaw, dt: dt)
        let (pitch, pitchOut) = t.gPitch.take(f.pitch, dt: dt)
        if pitchOut { t.leftOut.angles += 1 }
        t.pitch = t.fAngle[2].filter(pitch, dt: dt)
        t.usualPitch += (t.pitch - t.usualPitch) * 0.01

        t.origin = CGPoint(x: t.fOrigin[0].filter(Double(origin.x), dt: dt), y: t.fOrigin[1].filter(Double(origin.y), dt: dt))
        t.browV = t.fBrow.filter(browRaw, dt: dt)
        t.chinV = t.fChin.filter(chinV, dt: dt)
        if chinX.isFinite { t.chinX = t.fChinX.filter(chinX, dt: dt) }
        t.crownV = t.fCrown.filter(sc.crown, dt: dt)
        t.crownX = t.fCrownX.filter(crownX, dt: dt)
        for i in 0..<K {
            let (a, outA) = t.gL[i].take(l[i], dt: dt), (b, outB) = t.gR[i].take(r[i], dt: dt)
            if outA { t.leftOut.edges += 1 }; if outB { t.leftOut.edges += 1 }
            t.l[i] = t.fL[i].filter(a, dt: dt); t.r[i] = t.fR[i].filter(b, dt: dt)
        }
        // the yardstick: the head's breadth at the brim, as this frame shows it
        if let ring = Self.ring(t) {
            t.ringHalf = ring.half
            if ring.widest.isFinite, ring.widest > 4 { t.U = t.fU.filter(ring.widest, dt: dt) }
            // the head's height in the picture changes with a nod, so it only follows while the nod is the usual one
            let usual = abs(t.pitch - t.usualPitch) < 0.12
            if usual { t.tall = t.fTall.filter(tallRaw, dt: dt) }
            if usual { learnDepth(t, ring) }
        }
    }

    /// The head's depth against its breadth, from how wide the outline is at the brim at different turns:
    /// (half width)² = a²·(cos² + depth²·sin²). A running least-squares fit over the last minute or so; while the
    /// person has not turned, it stays near an ordinary head. The head's height in the picture takes the distance
    /// to the camera out of it (it does not change with the turn).
    private func learnDepth(_ t: Track, _ ring: Ring) {
        guard t.tall > 8, ring.half.isFinite else { return }
        let y = (ring.half / t.tall) * (ring.half / t.tall), c2 = ring.c2, s2 = ring.s2
        guard y.isFinite, y < 100 else { return }
        let keep = 1 - 1.0 / 600
        t.sums.cc = t.sums.cc * keep + c2 * c2; t.sums.cs = t.sums.cs * keep + c2 * s2; t.sums.ss = t.sums.ss * keep + s2 * s2
        t.sums.bc = t.sums.bc * keep + y * c2; t.sums.bs = t.sums.bs * keep + y * s2
        let k0 = Self.ordinaryDepth * Self.ordinaryDepth
        let e = 0.03 * (t.sums.cc + t.sums.ss)
        let m00 = t.sums.cc + e * k0 * k0, m01 = t.sums.cs - e * k0, m11 = t.sums.ss + e
        let det = m00 * m11 - m01 * m01
        guard det > 1e-12 else { return }
        let A = (t.sums.bc * m11 - t.sums.bs * m01) / det, C = (m00 * t.sums.bs - m01 * t.sums.bc) / det
        guard A > 1e-6, C > 1e-6, (C / A).isFinite else { return }
        t.depth += (min(1.7, max(0.85, (C / A).squareRoot())) - t.depth) * 0.15
    }

    // ------------------------------------------------------------------ the hat on the measured head

    /// The head as the camera sees it with the tilt taken out: turned about its own upright axis, then nodded.
    /// x to the picture's right, y up, z toward the camera; yaw positive toward the picture's right, pitch
    /// positive nodding down.
    static func headRotation(yaw: Double, pitch: Double) -> simd_double3x3 {
        let (cy, sy) = (cos(yaw), sin(yaw)), (cp, sp) = (cos(pitch), sin(pitch))
        let ry = simd_double3x3(rows: [V(cy, 0, sy), V(0, 1, 0), V(-sy, 0, cy)])
        let rx = simd_double3x3(rows: [V(1, 0, 0), V(0, cp, -sp), V(0, sp, cp)])
        return rx * ry
    }

    /// The whole rotation: tilt (z) · nod (x) · turn (y).
    static func rotation(roll: Double, yaw: Double, pitch: Double) -> simd_double3x3 {
        let (cr, sr) = (cos(roll), sin(roll))
        return simd_double3x3(rows: [V(cr, -sr, 0), V(sr, cr, 0), V(0, 0, 1)]) * headRotation(yaw: yaw, pitch: pitch)
    }

    /// Rotation by |w| about w (Rodrigues).
    static func rotationMatrix(_ w: V) -> simd_double3x3 {
        let a = simd_length(w)
        guard a > 1e-9 else { return matrix_identity_double3x3 }
        let k = w / a
        let K = simd_double3x3(rows: [V(0, -k.z, k.y), V(k.z, 0, -k.x), V(-k.y, k.x, 0)])
        return matrix_identity_double3x3 + sin(a) * K + (1 - cos(a)) * (K * K)
    }

    /// The outline's edges at height `v` above the eye line (head frame, pixels).
    static func outline(_ t: Track, at v: Double) -> (Double, Double) {
        let K = samples, vLow = -below * t.U
        let span = max(1, (t.crownV - vLow) * 0.97)
        let f = (v - vLow) / span * Double(K - 1)
        if f <= 0 { return (t.l[0], t.r[0]) }
        if f >= Double(K - 1) {   // above the top sample the head closes at the crown
            let u = min(1, max(0, (v - (vLow + span)) / max(1, t.crownV - (vLow + span))))
            return (t.l[K - 1] + (t.crownX - t.l[K - 1]) * u, t.r[K - 1] + (t.crownX - t.r[K - 1]) * u)
        }
        let i = Int(f), w = f - Double(i)
        return (t.l[i] + (t.l[i + 1] - t.l[i]) * w, t.r[i] + (t.r[i + 1] - t.r[i]) * w)
    }

    struct Ring {
        var X: V, Y: V, Z: V          // the head's axes as the camera sees them (roll taken out)
        var B: V, N: V                // the brim plane's front direction and its normal
        var centre: V, a: Double      // centre and sideways half-axis (the front-back one is a·depth)
        var half: Double              // half the outline's width where the brim meets it
        var widest: Double            // half the head's greatest breadth, turn taken out
        var c2: Double, s2: Double
        var rf: Double
    }

    /// The brim: a tilted ring round the head. Its width is the outline's width where the ring meets it, its front
    /// sits just above the eyebrows; the head's turn and nod decide how it curves between those.
    static func ring(_ t: Track) -> Ring? {
        let U = t.U
        guard U > 9 else { return nil }
        let R = headRotation(yaw: t.yaw, pitch: min(1.0, max(-1.0, t.pitch)))
        let X = R * V(1, 0, 0), Y = R * V(0, 1, 0), Z = R * V(0, 0, 1)
        let B = cos(brimTilt) * Z + sin(brimTilt) * Y, N = cos(brimTilt) * Y - sin(brimTilt) * Z
        let rf = fur * U, k = t.depth
        // The forehead is seen shortened when the head nods, the tufts are not: the fur's lower edge stays above
        // the eyebrows, so the hat never comes down over the eyes.
        let vFront = t.browV + browGap * U * max(0.35, Y.y) + furBelow * rf
        let vLow = -below * U
        let c2 = X.x * X.x, s2 = B.x * B.x
        let gx = max(0.35, (c2 + k * k * s2).squareRoot())
        // the ring's outermost points to the right and left sit this much above and below its centre (per unit a)
        let side = (X.x * X.y + k * k * B.x * B.y) / gx
        var vc = t.browV, a = U, xc = 0.0, half = 0.0
        for _ in 0..<5 {
            let r = outline(t, at: vc + a * side).1, l = outline(t, at: vc - a * side).0
            half = max(4, (r - l) / 2); xc = (l + r) / 2
            a += (half / gx - a) * 0.7
            vc = max(vLow, vFront - a * k * B.y)
        }
        // the head's greatest breadth (it does not depend on where the brim happens to sit)
        // From the brim's sides up: the brim sits on the head (at the ears, also when the head is seen from below),
        // so nothing below the head is in it. (Live 2026-11-17: measured from a fixed distance below the eyes,
        // the shoulders came into it when the person looked down, and the hat grew to three times its size.)
        var widest = 0.0
        let from = min(0, vc)
        for i in 0...16 {
            let (l, r) = outline(t, at: from + (t.crownV - from) * Double(i) / 19)
            widest = max(widest, (r - l) / 2)
        }
        return Ring(X: X, Y: Y, Z: Z, B: B, N: N, centre: V(xc, vc, 0), a: a, half: half, widest: widest / gx, c2: c2, s2: s2, rf: rf)
    }

    /// Convex hull (counter-clockwise).
    static func hull(_ pts: [P2]) -> [P2] {
        let p = pts.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard p.count > 2 else { return p }
        func cross(_ o: P2, _ a: P2, _ b: P2) -> Double { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [P2] = [], upper: [P2] = []
        for q in p { while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], q) <= 0 { lower.removeLast() }; lower.append(q) }
        for q in p.reversed() { while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], q) <= 0 { upper.removeLast() }; upper.append(q) }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// Where a convex polygon crosses the height `y`: its left and right x.
    static func row(_ poly: [P2], _ y: Double) -> (Double, Double)? {
        var lo = Double.infinity, hi = -Double.infinity
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            if (a.y - y) * (b.y - y) > 0 { continue }
            if abs(a.y - b.y) < 1e-9 { lo = min(lo, a.x, b.x); hi = max(hi, a.x, b.x); continue }
            let x = a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y)
            lo = min(lo, x); hi = max(hi, x)
        }
        return lo <= hi ? (lo, hi) : nil
    }

    /// The last crown share learned from any head (see `parts`).
    private var crownShareSeen: Double?
    private enum Item { case quad([V], CGColor), ball(V, Double, Double) }
    private static let light = simd_normalize(V(-0.45, 0.6, 0.7))

    /// Everything the hat is made of, in the head's frame (pixels; x along the eye line, y up the head, z toward the
    /// camera): what lies behind the head, and what lies in front. Each with its depth for drawing back to front.
    private func parts(_ t: Track) -> (back: [(Double, Item)], front: [(Double, Item)], tip: V)? {
        guard let g = Self.ring(t) else { return nil }
        let U = t.U, k = t.depth, rf = g.rf, X = g.X, Y = g.Y, Z = g.Z
        // The hat's own height. A hat keeps its shape when the head moves, but the crown as it shows in the outline
        // does not: leaning back and turned, the top of the outline is the forehead and the hair above it, far
        // below where the crown is seen from the front (live 2026-11-19: 88 px above the eye line against 125–145,
        // and all that was left of the sou'wester over the brim was a thin strip). So the crown's height is
        // learned as a share of the head's breadth while the head is seen straight on, and the hat is never lower
        // than that (less a little, and shortened as the head's upright axis leans from the picture's plane).
        if abs(t.yaw) < 0.2, abs(t.pitch) < 0.18, t.crownV > 0.5 * U {
            let s = t.crownV / U
            t.crownShare = t.crownShare.map { $0 + (s - $0) * 0.05 } ?? s
            crownShareSeen = t.crownShare
        }
        let vc = g.centre.y, vLow = -Self.below * U
        // (a head that is found again after a quick move starts as a new one: until it has been seen straight
        // on itself, the last share learned stands in; heads differ little in this)
        let top = max(t.crownV, (t.crownShare ?? crownShareSeen ?? 0) * U * Y.y * 0.9)
        guard top > vc + 4, Y.y > 0.3 else { return nil }
        // the light keeps its place in the picture while the head's frame rolls
        let cr = cos(t.roll), sr = sin(t.roll)
        let lightH = V(Self.light.x * cr + Self.light.y * sr, -Self.light.x * sr + Self.light.y * cr, Self.light.z)
        let halfway = simd_normalize(lightH + V(0, 0, 1))
        var back: [(Double, Item)] = [], front: [(Double, Item)] = []

        // ---- the cloth: the smallest shape without a waist around the brim, the measured outline above it, and the tip
        let mg = Self.cloth * U
        var pts: [P2] = [P2(g.centre.x - g.half - 0.45 * rf, vc), P2(g.centre.x + g.half + 0.45 * rf, vc)]
        let n = 16
        for i in 1...n {
            let v = vc + (top - vc) * Double(i) / Double(n + 1)
            let (l, r) = Self.outline(t, at: v)
            pts.append(P2(l - mg, v)); pts.append(P2(r + mg, v))
        }
        pts.append(P2(t.crownX, top + mg))
        // (a sou'wester's crown is low and round: two more points beside the top one keep it from ending in a peak)
        if CameraCostume.autumn { pts.append(P2(t.crownX - 0.38 * U, top + mg * 0.8)); pts.append(P2(t.crownX + 0.38 * U, top + mg * 0.8)) }
        let L = Self.free * U
        // Autumn's hat is a sou'wester: the same cloth on the measured head, but closed in a dome over the crown
        // instead of running on into a long bent tip, and with a stiff brim in place of the fur (see below).
        let autumn = CameraCostume.autumn
        let apex = autumn ? P2(t.crownX, top + mg) : P2(t.crownX + L * Y.x, top + L * Y.y)
        if !autumn { pts.append(apex) }
        let poly = Self.hull(pts)

        // the part above the head bends over: the centre line by its length, and how far it has turned there
        let vBend = top + Self.bendStart * U * Y.y
        let Lf = (Self.free - Self.bendStart) * U
        let D = simd_normalize(X * 0.8 - Z * 0.6)   // toward the person's side and back
        let axis = simd_normalize(simd_cross(Y, D))
        let steps = 48
        var curve = [V(0, 0, 0)]
        for i in 1...steps {
            let al = Self.bend * pow((Double(i) - 0.5) / Double(steps), 1.6)
            let dirn: V = cos(al) * Y + sin(al) * D
            curve.append(curve[i - 1] + dirn * (Lf / Double(steps)))
        }
        func bent(_ w: Double) -> V {
            let f = min(1, max(0, w)) * Double(steps), i = min(steps - 1, Int(f))
            return curve[i] + (curve[i + 1] - curve[i]) * (f - Double(i))
        }
        func depthOnAxis(_ v: Double) -> Double { (v - vc) * Y.z / Y.y }
        var Qb = V(0, 0, 0)
        if !autumn {
            guard let (bl, br) = Self.row(poly, vBend) else { return nil }
            Qb = V((bl + br) / 2, vBend, depthOnAxis(vBend))
        }

        let M = 38, segs = 36
        var rings: [[V]] = [], centres: [V] = []
        for j in 0...M {
            let v = vc + Double(j) / Double(M) * 0.97 * (apex.y - vc)
            guard let (l, r) = Self.row(poly, v) else { continue }
            let h = (r - l) / 2
            let onHead = min(1, max(0, (v - vc) / (top - vc)))            // 0 at the brim … 1 at the crown
            let above = min(1, max(0, (v - top) / max(1, apex.y - top)))   // 0 at the crown … 1 at the tip
            let tilt = Self.brimTilt * (1 - onHead)
            let kj = 1 + (k - 1) * (1 - above) * (1 - above)              // the tip is round
            let Bj = cos(tilt) * Z + sin(tilt) * Y
            let gx = max(0.35, (X.x * X.x + kj * kj * Bj.x * Bj.x).squareRoot())
            let aj = h / gx
            var c = V((l + r) / 2, v, depthOnAxis(v))
            var ring = (0..<segs).map { i -> V in
                let ph = Double(i) / Double(segs) * 2 * .pi
                let side: V = (aj * sin(ph)) * X, fore: V = (aj * kj * cos(ph)) * Bj
                return c + side + fore
            }
            if v > vBend && !autumn {
                let along = (v - vBend) / Y.y, w = along / Lf
                let Rb = Self.rotationMatrix(axis * (Self.bend * pow(min(1, w), 1.6)))
                let straight = Qb + Y * along, moved = Qb + bent(w)
                ring = ring.map { moved + Rb * ($0 - straight) }
                c = moved + Rb * (c - straight)
            }
            rings.append(ring); centres.append(c)
        }
        guard rings.count > 3 else { return nil }
        if autumn, let last = centres.last {
            // close the dome: one last ring drawn together in a point just above the top ring
            let cap = V(last.x, apex.y, depthOnAxis(apex.y))
            rings.append(Array(repeating: cap, count: segs)); centres.append(cap)
        }
        for j in 0..<(rings.count - 1) {
            let a = rings[j], b = rings[j + 1], mid = (centres[j] + centres[j + 1]) / 2
            for i in 0..<segs {
                let i1 = (i + 1) % segs
                let q = [a[i], a[i1], b[i1], b[i]]
                let m = (q[0] + q[1] + q[2] + q[3]) / 4
                var nrm = simd_cross(q[1] - q[0], q[3] - q[0])
                let len = simd_length(nrm)
                if len < 1e-9 { continue }
                nrm /= len
                if simd_dot(nrm, m - mid) < 0 { nrm = -nrm }
                if nrm.z < -0.02 { continue }   // faces away from the camera
                let diffuse = max(0, simd_dot(nrm, lightH)), spec = pow(max(0, simd_dot(nrm, halfway)), 16) * 0.22
                let shade = 0.32 + 0.68 * diffuse
                let col = autumn
                    ? CGColor(srgbRed: min(1, 0.97 * shade + spec), green: min(1, 0.77 * shade + spec), blue: min(1, 0.08 * shade + spec * 0.8), alpha: 1)
                    : CGColor(srgbRed: min(1, 0.80 * shade + spec), green: min(1, 0.07 * shade + spec * 0.9),
                              blue: min(1, 0.12 * shade + spec * 0.9), alpha: 1)
                front.append((m.z, .quad(q, col)))
            }
        }
        if autumn {
            // ---- the sou'wester's brim: a stiff ring that slopes down and out from where the fur would sit,
            // narrow over the forehead and long at the back of the neck. Seen from above it is lit like the
            // cloth; where its underside shows it is in shade.
            let n = 48
            func edge(_ i: Int) -> (inner: V, outer: V, out: V) {
                let ph = Double(i) / Double(n) * 2 * .pi, sp = sin(ph), cp = cos(ph)
                let out: V = simd_normalize((k * sp) * X + cp * g.B)
                let inner: V = g.centre + (g.a * sp) * X + (g.a * k * cp) * g.B
                let w = U * (0.40 + 0.38 * max(0, -cp))
                // turned up over the forehead (so it never comes down over the eyes), level at the sides,
                // sloping down at the back
                let rise = cp > 0 ? 0.75 * cp : 0.5 * cp
                return (inner, inner + out * (w * (cp > 0 ? 1 - 0.45 * cp : 1)) + g.N * (w * rise), out)
            }
            for i in 0..<n {
                let a = edge(i), b = edge(i + 1)
                let q = [a.inner, b.inner, b.outer, a.outer]
                let m = (q[0] + q[1] + q[2] + q[3]) / 4
                var nrm = simd_cross(q[1] - q[0], q[3] - q[0])
                let len = simd_length(nrm)
                if len < 1e-9 { continue }
                nrm /= len
                if simd_dot(nrm, g.N) < 0 { nrm = -nrm }           // the upper side's normal
                let under = nrm.z < 0                                // the camera sees the underside
                if under { nrm = -nrm }
                let diffuse = max(0, simd_dot(nrm, lightH))
                // (the turned-up front shows its outer side to the camera with the light from above behind it:
                // lit like the cloth it came out dark brown, so the brim never goes below a clear yellow)
                let shade = 0.58 + 0.42 * diffuse
                let col = CGColor(srgbRed: min(1, 0.97 * shade), green: min(1, 0.77 * shade), blue: min(1, 0.08 * shade), alpha: 1)
                let facing = (a.out + b.out).z
                if facing >= 0 { front.append((1e6 + m.z, .quad(q, col))) }
                else if m.y >= vLow { back.append((m.z, .quad(q, col))) }
            }
            return (back, front, centres.last ?? g.centre)
        }
        // pompom at the tip
        let tip = Qb + bent(1)
        front.append((tip.z + Self.pompom * U, .ball(tip, Self.pompom * U, 0.9)))

        // ---- the fur brim: two rows of fluffy balls round the ring, a little out from the head
        let balls = 56
        for (rowIndex, spec) in [(-0.3, 1.0, 0.9), (0.57, 0.85, 0.6)].enumerated() {
            let (lift, size, out) = spec
            for i in 0..<balls {
                let ph = (Double(i) + (rowIndex == 1 ? 0.5 : 0)) / Double(balls) * 2 * .pi
                let nrm: V = simd_normalize((k * sin(ph)) * X + cos(ph) * g.B)
                let sp = sin(ph), cp = cos(ph)
                let onRing: V = g.centre + (g.a * sp) * X + (g.a * k * cp) * g.B
                var c: V = onRing + nrm * (rf * size * out) + g.N * (lift * rf)
                if nrm.z < 0 {
                    // Behind the head the brim lies on the head. What can be seen of it is what reaches past the
                    // head's outline, so it is kept on the measured outline there (the ring's own depth is a
                    // guess, the outline is not); below where the outline was measured it is left out.
                    if c.y < vLow { continue }
                    let (ol, or) = Self.outline(t, at: c.y)
                    // (a tuft straight behind the head sits on the outline; toward the sides it stands out from it)
                    let stands = rf * size * out * (1 - nrm.z * nrm.z).squareRoot()
                    c.x = min(max(c.x, ol - stands), or + stands)
                }
                let shade = 0.6 + 0.4 * max(0, simd_dot(nrm, lightH))
                let item = Item.ball(c, rf * size, shade)
                // the half that faces the camera lies on the forehead; the other half goes round behind the head
                // The fur lies outside the cloth all the way round, so on the near side it is always drawn after the
                // cloth. (Sorted by depth together with the cloth, cloth a little further round the head came out
                // in front of the fur at the head's outline: seen from the side the fur was nearly gone at the
                // forehead. Live 2026-11-17.)
                if nrm.z >= 0 { front.append((1e6 + c.z, item)) } else { back.append((c.z, item)) }
            }
        }
        return (back, front, tip)
    }

    /// Draws a list of parts; returns the image positioned in output coordinates.
    private func draw(_ list: [(Double, Item)], _ t: Track, alpha: CGFloat) -> CIImage? {
        let cr = cos(t.roll), sr = sin(t.roll), ox = Double(t.origin.x), oy = Double(t.origin.y)
        func screen(_ p: V) -> CGPoint { CGPoint(x: ox + cr * p.x - sr * p.y, y: oy + sr * p.x + cr * p.y) }
        var bounds = CGRect.null
        var items: [(Double, [CGPoint], CGColor?, CGFloat, Double)] = []
        for (z, it) in list {
            switch it {
            case let .quad(q, col):
                let s = q.map(screen)
                for p in s { bounds = bounds.union(CGRect(origin: p, size: .zero)) }
                items.append((z, s, col, 0, 0))
            case let .ball(c, r, shade):
                let p = screen(c)
                bounds = bounds.union(CGRect(x: p.x - r * 1.5, y: p.y - r * 1.5, width: r * 3, height: r * 3))
                items.append((z, [p], nil, CGFloat(r), shade))
            }
        }
        bounds = bounds.insetBy(dx: -4, dy: -4).integral
        guard !bounds.isNull, bounds.width > 4, bounds.height > 4, bounds.width < 4000, bounds.height < 4000,
              let g = CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        g.translateBy(x: -bounds.minX, y: -bounds.minY)
        g.setAlpha(alpha)
        g.setLineWidth(1); g.setLineJoin(.round)
        items.sort { $0.0 < $1.0 }
        for (_, pts, col, r, shade) in items {
            if let col {
                g.setFillColor(col); g.setStrokeColor(col)
                g.addLines(between: pts); g.closePath(); g.drawPath(using: .fillStroke)
            } else {
                let p = pts[0]
                let rect = CGRect(x: p.x - r * 1.4, y: p.y - r * 1.4, width: r * 2.8, height: r * 2.8)
                g.draw(Self.fluffLight, in: rect)
                g.setAlpha(alpha * CGFloat(max(0, min(1, (1 - shade) * 1.1))))
                g.draw(Self.fluffDark, in: rect)
                g.setAlpha(alpha)
            }
        }
        guard let img = g.makeImage() else { return nil }
        return CIImage(cgImage: img).transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
    }

    /// The heads as measured in this frame, each as its outline in the picture: face, ears and hair. For the costume:
    /// what is inside is head, never clothes.
    ///
    /// From the eye line up it is the outline measured in the person mask. Below the eye line the mask cannot show
    /// the head: there it runs together with the neck, the shoulders, a hood. So the lower half is a rounded jaw
    /// from the outline's two edges at the eye line down to the measured chin (its lowest point, wherever the chin
    /// is: in the middle seen from the front, at the front edge seen from the side). A straight edge across at the
    /// chin's height (the first version) kept the red off a whole band of clothes beside the jaw.
    var headOutlines: [[CGPoint]] {
        tracks.filter { $0.fresh }.map { t in
            let cr = cos(t.roll), sr = sin(t.roll), ox = Double(t.origin.x), oy = Double(t.origin.y)
            func screen(_ x: Double, _ v: Double) -> CGPoint { CGPoint(x: ox + cr * x - sr * v, y: oy + sr * x + cr * v) }
            let n = 20
            let levels = (0...n).map { t.crownV * Double($0) / Double(n) }
            var pts = levels.map { screen(Self.outline(t, at: $0).0, $0) } + levels.reversed().map { screen(Self.outline(t, at: $0).1, $0) }
            let (l0, r0) = Self.outline(t, at: 0)
            let width = max(1, r0 - l0), deep = max(4, -t.chinV * 1.05)
            let cx = min(r0 - 0.1 * width, max(l0 + 0.1 * width, t.chinX))
            // a full, rounded jaw: (x/a)^p + (y/deep)^p = 1 on each side of the chin
            let p = 2.5, m = 10
            func drop(_ u: Double) -> Double { -deep * pow(max(0, 1 - pow(u, p)), 1 / p) }
            for i in 1...m { let u = 1 - Double(i) / Double(m); pts.append(screen(cx + (r0 - cx) * u, drop(u))) }
            for i in 1..<m { let u = Double(i) / Double(m); pts.append(screen(cx - (cx - l0) * u, drop(u))) }
            return pts
        }
    }

    /// A head as measured, for the costume: where its upright axis is in the picture (a point on the eye line in the
    /// middle of the outline), its angles (steadied), half its breadth, and the outline's left and right edge at a
    /// height above the eye line, both from the axis.
    struct Head {
        var origin: CGPoint, roll: Double, yaw: Double, pitch: Double, U: Double, edges: (Double) -> (Double, Double)
        /// The outline exactly as scanned in this frame: the left and right edge at a height above the eye line,
        /// sideways from `scanOrigin`; nil where the row did not end on the head.
        var scanOrigin: CGPoint, scanned: (Double) -> (Double?, Double?)
    }
    var headsForCostume: [Head] {
        tracks.filter { $0.lost <= Self.keepLost }.map { t in
            let rows = t.fresh ? t.scanRows : []
            return Head(origin: t.origin, roll: t.roll, yaw: t.yaw, pitch: t.pitch, U: t.U, edges: { Self.outline(t, at: $0) },
                        scanOrigin: t.scanOrigin, scanned: { v in
                guard let hi = rows.firstIndex(where: { $0.v >= v }), hi > 0 else { return (nil, nil) }
                let a = rows[hi - 1], b = rows[hi], w = (v - a.v) / max(1e-6, b.v - a.v)
                func between(_ p: Double?, _ q: Double?) -> Double? { p.flatMap { p in q.map { p + ($0 - p) * w } } }
                return (between(a.l, b.l), between(a.r, b.r))
            })
        }
    }

    /// For --kamera-debug: the measurements as text.
    var debugText: String {
        tracks.map { t in
            String(format: "hue: drej vision %.2f (brugt %.2f) omrids %.2f nik %.2f hæld %.2f | halv hovedbredde %.0f, halvt omrids ved kanten %.0f, dybde/bredde %.2f | over øjenlinjen: bryn %.0f isse %.0f hage %.0f | set i %.1f s siden",
                   t.gYaw.last, t.yaw, t.yawFromOutline, t.pitch, t.roll, t.U, t.ringHalf, t.depth, t.browV, t.crownV, t.chinV, Double(t.lost))
        }.joined(separator: "\n")
    }

    /// Puts a hat on every tracked head, on top of `image`.
    /// `person` is the person mask in output coordinates: the half of the brim that goes round behind the head is
    /// hidden wherever the person is, and seen only beside the head.
    func apply(to image: CIImage, person: CIImage? = nil) -> CIImage {
        var out = image
        for t in tracks {
            let alpha = t.lost <= Self.keepLost ? 1 : max(0, 1 - (t.lost - Self.keepLost) / Self.fadeOut)
            if alpha <= 0 { continue }
            guard let p = parts(t) else { continue }
            if let person, var back = draw(p.back, t, alpha: alpha) {
                let notPerson = person.applyingFilter("CIColorInvert").cropped(to: image.extent)
                back = back.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: notPerson])
                out = back.composited(over: out)
            }
            if let hat = draw(p.front, t, alpha: alpha) { out = hat.composited(over: out) }
        }
        return out
    }

    /// A soft fuzzy fur ball (lit), and the same shape in shadow colour to fade over it. The shadow is a soft
    /// neutral grey: a blue-grey one made the brim look grey-blue instead of white next to the beard.
    static let fluffLight = fluff(C(255, 255, 255), C(246, 246, 244))
    static let fluffDark = fluff(C(196, 194, 196), C(182, 180, 184))
    private static func fluff(_ inner: CGColor, _ outer: CGColor) -> CGImage {
        let s = 96
        let g = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var rng = SeededRandom(seed: 7)
        let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [inner, outer, outer.copy(alpha: 0)!] as CFArray, locations: [0, 0.78, 1])!
        for _ in 0..<14 {
            let a = Double(rng.next()) * 2 * .pi, d = Double(rng.next()) * 14
            let c = CGPoint(x: 48 + cos(a) * d, y: 48 + sin(a) * d)
            g.drawRadialGradient(grad, startCenter: CGPoint(x: c.x - 6, y: c.y + 6), startRadius: 0, endCenter: c, endRadius: 34, options: [])
        }
        return g.makeImage()!
    }

    // ------------------------------------------------------------------ for the test (HatTest.swift)

    /// The front of the hat alone (what covers the head), and where its tip and brim are in the picture.
    func frontForTest() -> (image: CIImage, tip: CGPoint, brimFront: CGPoint, track: Track)? {
        guard let t = tracks.first, let p = parts(t), let g = Self.ring(t), let img = draw(p.front, t, alpha: 1) else { return nil }
        let cr = cos(t.roll), sr = sin(t.roll)
        func screen(_ q: V) -> CGPoint { CGPoint(x: Double(t.origin.x) + cr * q.x - sr * q.y, y: Double(t.origin.y) + sr * q.x + cr * q.y) }
        return (img, screen(p.tip), screen(g.centre + g.a * t.depth * g.B), t)
    }
}
