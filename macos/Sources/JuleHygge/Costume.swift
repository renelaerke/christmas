import AppKit
import CoreImage
import Vision

/// Nisse beard and nisse suit for the person in the JuleHygge Kamera picture.
///
/// - **Beard:** Vision's face landmarks (jaw line, nose, lips) give the shape of the lower face in every frame.
///   A white full beard is drawn along the jaw and hanging below the chin, with a moustache under the nose and the
///   mouth left open so you can be seen talking. It follows turns and tilts because the landmarks do.
/// - **Suit:** the person's clothes (everything but the head) are recoloured Christmas red, keeping their light and
///   shade (folds stay). The neck is always left free (a soft oval under the chin from the face landmarks, so it
///   works in any light), and a hue-based skin rule keeps hands as they are.
/// Everything is drawn in output coordinates (y up), with the same aspect-fill transform as the camera picture.
final class NisseCostume {
    /// Landmarks for the faces the hat's rectangle request found.
    let request = VNDetectFaceLandmarksRequest()

    /// One face's shape, smoothed between frames.
    struct Shape {
        var contour: [CGPoint]      // jaw line, from one temple round the chin to the other
        var nose: [CGPoint]         // the nose outline
        var lips: [CGPoint]         // outer lips
        var centre: CGPoint, fw: CGFloat, fh: CGFloat, roll: CGFloat
        /// Turn and nod (radians), to know when the face looks straight ahead.
        var yaw: CGFloat = 0, pitch: CGFloat = 0
        var frontal: Bool { abs(yaw) < 0.3 && abs(pitch) < 0.25 }
        /// Eyes and eyebrows (the person's own left and right), for the Day of the Dead's make-up; may be empty.
        var leftEye: [CGPoint] = [], rightEye: [CGPoint] = [], leftBrow: [CGPoint] = [], rightBrow: [CGPoint] = []
        var up: CGPoint { CGPoint(x: -sin(roll), y: cos(roll)) }
        var right: CGPoint { CGPoint(x: cos(roll), y: sin(roll)) }
        /// The face as the rounded front of the head, measured with the head (see `measureFace`); nil until then.
        var face: Face?
        /// For --kamera-debug: the points the face was measured from, and the numbers.
        var marks: [CGPoint] = [], note = ""
        /// The point just under the nose: where the moustache meets, and what the beard is built from.
        var under: CGPoint {
            // Sideways: the middle point of Vision's nose outline, which runs from one nostril's wing along the
            // base of the nose to the other. (The average of the lowest points was tried first: those are the two
            // wings, and when the head is turned the far one is a guess, so the point lagged behind the nose and
            // the moustache did not sit under it.) Height: the lowest points, which are steady.
            let low = nose.sorted { dot($0, up) < dot($1, up) }.prefix(3)
            let lowest = low.reduce(CGPoint.zero) { $0 + $1 } * (1 / CGFloat(max(1, low.count)))
            let base = nose.isEmpty ? lowest : nose[nose.count / 2]
            return base + up * (dot(lowest - base, up) - fh * 0.04)
        }
        /// Lowest point of the jaw along the head's own up.
        var chin: CGPoint { contour.min { dot($0, up) < dot($1, up) } ?? centre }
    }
    /// The front of the head seen from above, round the head's upright axis (pixels).
    struct Face {
        var jaw: CGFloat      // half the face's breadth at the mouth's height
        var ear: CGFloat      // half its breadth up by the ears
        var front: CGFloat    // how far the face's middle line is in front of the axis
        var back: CGFloat     // how far the ears are behind the axis
        var eyeY: CGFloat     // the eye line above the point under the nose
        var chinY: CGFloat    // the chin below it (negative)
        var size: CGFloat     // the beard's yardstick: the head's breadth (does not change when the head turns)
        var lo: CGFloat, hi: CGFloat   // the person mask's edges at the mouth's height, sideways from under the nose
        /// the person mask's edges at a height above the point under the nose, sideways from it
        var edges: (CGFloat) -> (CGFloat, CGFloat) = { _ in (-.infinity, .infinity) }
    }
    private(set) var shapes: [Shape] = []
    /// Tells the person's clothes from skin and hair (for the suit).
    let parts = PersonParts()

    /// One Euro filters for one face: every landmark coordinate, the face size and the tilt. Steady while the
    /// head is still, quick when it moves.
    private final class Steady {
        var centre: CGPoint
        var points: [OneEuro] = []
        var fw = OneEuro(minCutoff: 0.15, beta: 0.005), fh = OneEuro(minCutoff: 0.15, beta: 0.005), roll = OneEuro(minCutoff: 0.3, beta: 0.3)
        var yaw = OneEuro(minCutoff: 0.8, beta: 2.0, dCutoff: 1.0)
        var jaw = OneEuro(minCutoff: 0.15, beta: 0.005), front = OneEuro(minCutoff: 0.15, beta: 0.005), chin = OneEuro(minCutoff: 0.15, beta: 0.005)
        /// as shares of the head's breadth, so they hold when the person moves nearer or turns
        var jawShare: CGFloat?, frontShare: CGFloat?, chinShare: CGFloat?
        init(centre: CGPoint) { self.centre = centre }
        func filter(_ pts: [CGPoint], dt: CGFloat) -> [CGPoint] {
            if points.count != pts.count * 2 { points = (0..<pts.count * 2).map { _ in OneEuro(minCutoff: 0.3, beta: 0.02) } }
            return pts.enumerated().map { i, p in CGPoint(x: points[2 * i].filter(p.x, dt: dt), y: points[2 * i + 1].filter(p.y, dt: dt)) }
        }
    }
    private var steady: [Steady] = []

    // ------------------------------------------------------------------ landmarks

    /// Runs the landmarks request for `faces` (from the rectangles request) on the same frame.
    func detect(_ handler: VNImageRequestHandler, faces: [VNFaceObservation]) -> [VNFaceObservation] {
        guard !faces.isEmpty else { return [] }
        request.inputFaceObservations = Array(faces.prefix(3))
        try? handler.perform([request])
        return request.results ?? []
    }

    /// The heads as the hat measured them in this frame (NisseHat.headsForCostume): set before `update`.
    var heads: [NisseHat.Head] = []

    /// Turns landmark results into shapes in output coordinates, smoothed against the previous frame.
    func update(_ observations: [VNFaceObservation], extent: CGRect, transform: CGAffineTransform, dt: CGFloat = 1.0 / 30) {
        let k = hypot(transform.a, transform.b)
        var raw: [Shape] = []
        for o in observations {
            guard let lm = o.landmarks, let contour = lm.faceContour, let nose = lm.nose, let lips = lm.outerLips else { continue }
            func pts(_ r: VNFaceLandmarkRegion2D) -> [CGPoint] {
                r.pointsInImage(imageSize: extent.size).map { CGPoint(x: $0.x + extent.minX, y: $0.y + extent.minY).applying(transform) }
            }
            let b = o.boundingBox
            let c = CGPoint(x: extent.minX + b.midX * extent.width, y: extent.minY + b.midY * extent.height).applying(transform)
            var s = Shape(contour: pts(contour), nose: pts(nose), lips: pts(lips), centre: c,
                          fw: b.width * extent.width * k, fh: b.height * extent.height * k,
                          roll: NisseHat.rollSign * CGFloat(o.roll?.doubleValue ?? 0))
            s.yaw = CGFloat(o.yaw?.doubleValue ?? 0); s.pitch = CGFloat(o.pitch?.doubleValue ?? 0)
            s.leftEye = lm.leftEye.map(pts) ?? []; s.rightEye = lm.rightEye.map(pts) ?? []
            s.leftBrow = lm.leftEyebrow.map(pts) ?? []; s.rightBrow = lm.rightEyebrow.map(pts) ?? []
            raw.append(s)
        }
        ingest(raw, dt: dt)
    }

    /// This frame's faces as found (also fed directly by the test): matched to the last frame's, steadied, measured.
    func ingest(_ raw: [Shape], dt: CGFloat) {
        var next: [Shape] = [], used: [Steady] = []
        for var s in raw {
            let c = s.centre
            // the same face as last frame (nearest), filtered so the beard and suit do not flicker
            let f = steady.filter { st in !used.contains { $0 === st } }.min { dist($0.centre, c) < dist($1.centre, c) }
            let st = f.map { dist($0.centre, c) < s.fw * 0.8 ? $0 : Steady(centre: c) } ?? Steady(centre: c)
            used.append(st)
            st.centre = c
            let groups = [s.contour, s.nose, s.lips, s.leftEye, s.rightEye, s.leftBrow, s.rightBrow]
            let all = st.filter(groups.flatMap { $0 }, dt: dt)
            var at = 0
            let back = groups.map { g -> [CGPoint] in defer { at += g.count }; return Array(all[at..<(at + g.count)]) }
            s.contour = back[0]; s.nose = back[1]; s.lips = back[2]
            s.leftEye = back[3]; s.rightEye = back[4]; s.leftBrow = back[5]; s.rightBrow = back[6]
            s.fw = st.fw.filter(s.fw, dt: dt); s.fh = st.fh.filter(s.fh, dt: dt); s.roll = st.roll.filter(s.roll, dt: dt)
            s.yaw = st.yaw.filter(s.yaw, dt: dt)
            if s.contour.count >= 7 && s.nose.count >= 3 && s.lips.count >= 4 { measureFace(&s, st, dt) }
            if s.contour.count >= 7 && s.nose.count >= 3 && s.lips.count >= 4 { next.append(s) }
        }
        shapes = next
        steady = used
    }

    /// Measures the face for the beard, with the head the hat measured for the same face.
    ///
    /// Seen from above, the front of the head is taken as a rounded band round the head's upright axis, from ear to
    /// ear. The axis is the middle of the head's outline in the person mask (the hat's origin). What is measured,
    /// each only in the views that show it, and kept (as a share of the head's size) in the others:
    /// - how far the face's middle line is in front of the axis: from how far the point under the nose is seen
    ///   from the axis when the head is clearly turned (Vision places that point well then too);
    /// - half the face's breadth at the mouth's height: seen from the front, the person mask's edges there (cheek
    ///   against background, below the ears), not wider than Vision's jaw line (hair beside the cheeks);
    /// - the chin's height: seen from the front (turned, Vision's jaw line is a guess and its lowest point is not
    ///   the chin; live 2026-11-17 it sat in the middle of the cheek).
    /// Working the breadth out from a turned view was tried and dropped: it is the small difference of two large
    /// numbers there, and came out anywhere between 49 and 128 px for the same face.
    /// The ears' breadth is the head's own, and how far they sit behind the axis is an ordinary head's.
    /// Where the beard ends up by the ears, as shares of half the head's breadth: just in front of the ear, not on
    /// it. (At the ear itself, 0.92 broad and 0.45 behind the axis, the beard went in over the ears; live 2026-11-17.)
    static let sideburn = (breadth: CGFloat(0.84), back: CGFloat(0.2))

    private func measureFace(_ s: inout Shape, _ st: Steady, _ dt: CGFloat) {
        guard let h = heads.min(by: { dist($0.origin, s.centre) < dist($1.origin, s.centre) }), dist(h.origin, s.centre) < s.fh * 1.5 else { s.face = nil; return }
        // the hat's angles are the steadied ones, with misreadings left out
        s.yaw = CGFloat(h.yaw); s.roll = CGFloat(h.roll)
        let up = s.up, right = s.right
        let under = s.under
        let lc = s.lips.reduce(CGPoint.zero) { $0 + $1 } * (1 / CGFloat(s.lips.count))
        let (l, r) = h.edges(Double(dot(lc - h.origin, up)))
        let sy = sin(s.yaw), U = CGFloat(h.U)
        let underSide = dot(under - h.origin, right), eyeY = max(4, dot(h.origin - under, up))
        let chinNow = dot(s.chin - under, up)
        guard U > 8 else { s.face = nil; return }
        if abs(sy) > 0.45 {
            let share = underSide / sy / U
            if share.isFinite, share > 0.8, share < 1.8 { st.frontShare = st.front.filter(share, dt: dt) }
        }
        var jawNow: CGFloat?
        // (only straight on: nodding, the jaw line is seen shortened and the mouth's height crosses it elsewhere;
        // live, one look down took the breadth from 0.77 to 0.54 of the head's and left the beard narrow)
        if abs(s.yaw) < 0.2, abs(h.pitch) < 0.18 {
            var a = CGFloat(r - l) / 2
            let mouthY = dot(lc - under, up)
            var sides: [CGFloat] = []
            for k in 0..<(s.contour.count - 1) {
                let p = s.contour[k] - under, q = s.contour[k + 1] - under
                let hp = dot(p, up) - mouthY, hq = dot(q, up) - mouthY
                if hp * hq > 0 || hp == hq { continue }
                sides.append(dot(p, right) + (dot(q, right) - dot(p, right)) * (hp / (hp - hq)))
            }
            if let lo = sides.min(), let hi = sides.max(), hi - lo > 8 { a = min(a, (hi - lo) / 2) }
            if a.isFinite, a > 0.45 * U, a < 1.05 * U { jawNow = a; st.jawShare = st.jaw.filter(a / U, dt: dt) }
            if chinNow < -4 { st.chinShare = st.chin.filter(-chinNow / U, dt: dt) }
        }
        // turned, the chin is at least where it was from the front (an open mouth may take it lower)
        let chinY = min(chinNow, -(st.chinShare ?? 0) * U)
        s.face = Face(jaw: (st.jawShare ?? 0.78) * U, ear: Self.sideburn.breadth * U, front: (st.frontShare ?? 1.25) * U, back: Self.sideburn.back * U,
                      eyeY: eyeY, chinY: chinY, size: 2.1 * U, lo: CGFloat(l) - underSide, hi: CGFloat(r) - underSide)
        // For keeping the beard on the skin, the outline exactly as scanned in this frame is used: the steadied
        // one can be a few pixels off where the face narrows toward the chin, and the beard then stood out over
        // the background or stopped short of the cheek (live 2026-11-17).
        let scanUp = dot(under - h.scanOrigin, up), scanSide = dot(under - h.scanOrigin, right)
        s.face!.edges = { y in
            let (a, b) = h.scanned(Double(scanUp + y))
            return (a.map { CGFloat($0) - scanSide } ?? -.infinity, b.map { CGFloat($0) - scanSide } ?? .infinity)
        }
        let mh = dot(lc - h.origin, up)
        s.marks = [h.origin, under, h.origin + right * CGFloat(l) + up * mh, h.origin + right * CGFloat(r) + up * mh, lc, s.chin]
        s.note = String(format: "skæg: drej %.2f hæld %.2f | akse %.0f,%.0f under næsen %.0f,%.0f (%.0f px fra aksen) | maskens kanter i mundhøjde %.0f og %.0f fra aksen | målt nu: halv bredde %@, hage %.0f | brugt: halv bredde %.0f (andel %@), foran aksen %.0f (andel %@), hage %.0f, øjenlinje %.0f over næsen | halv hovedbredde %.0f, ansigtshøjde %.0f",
                        s.yaw, s.roll, h.origin.x, h.origin.y, under.x, under.y, underSide, l, r,
                        jawNow.map { String(format: "%.0f", $0) } ?? "ikke forfra", -chinNow, s.face!.jaw, st.jawShare.map { String(format: "%.2f", $0) } ?? "start 0,78",
                        s.face!.front, st.frontShare.map { String(format: "%.2f", $0) } ?? "start 1,25", -chinY, eyeY, U, s.fh)
    }

    // ------------------------------------------------------------------ suit

    /// The camera picture with the clothes (everything but the heads) recoloured Christmas red.
    /// `mask` is the person mask in the same coordinates.
    /// `heads`: each head's measured outline (NisseHat.headOutlines). Where there is a face there is a head, and
    /// everything inside its outline (hair, ears) is head: never coloured, whatever its colour.
    func applySuit(to cam: CIImage, mask: CIImage, heads: [[CGPoint]] = []) -> CIImage {
        guard !shapes.isEmpty else { return cam }
        let extent = cam.extent
        // red cloth with the clothes' own light and shade
        let gray = cam.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.25, kCIInputBrightnessKey: 0.02])
        // (in autumn the same cloth is a yellow raincoat)
        // (and each folk has its own colour: see CameraLook)
        let autumn = CameraCostume.autumn, look = CameraCostume.look
        let red = gray.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: autumn ? 0.50 : look.suit.r, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: autumn ? 0.42 : look.suit.g, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: autumn ? 0.03 : look.suit.b, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            // (dark clothes came out olive with the red suit's small lift: the yellow needs a higher floor)
            // (both a touch clearer 2026-11-19: yellow from mustard toward oilskin, red with less grey in it)
            "inputBiasVector": autumn ? CIVector(x: 0.60, y: 0.47, z: 0.0, w: 0) : CIVector(x: look.suitFloor.r, y: look.suitFloor.g, z: look.suitFloor.b, w: 0)])
        // where: the person, not the head, and only the clothes
        // The cut-out fades the person out over a few pixels at the outline. The red must cover the clothes all the
        // way through that fade (what lies outside is cut away anyway); fading the red with the same mask left a
        // rim of the clothes' own colour, a halo, round the outline.
        let person = mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 6, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 6, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 6, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
            .applyingFilter("CIColorClamp")
        // The clothes, from the parts model when it is there (see PersonParts): it knows clothes from skin and hair
        // by what they are, not by their colour, so neck, hands, hair and beard stay as they are in any light and
        // whatever the clothes look like.
        if let cloth = parts.clothes(cam: cam) {
            let body = person.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: cloth])
            return red.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: cam, kCIInputMaskImageKey: body]).cropped(to: extent)
        }
        // Without the model (before macOS 15, or while it loads) the clothes are found by colour, which is less
        // sure: skin in shade and clothes in warm light look alike, and a jacket in several colours stops it.
        // everything but the head: a soft oval around each face and its hair (turning and tilting with the
        // head) is left out, so the red flows into all the clothes, up the neck of a hoodie too
        var notHead: CIImage?
        for s in shapes {
            let centre = s.centre + s.up * (s.fh * 0.22)
            let oval = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: 0, y: 0), "inputRadius0": 0.82, "inputRadius1": 1.0,
                "inputColor0": CIColor(red: 0, green: 0, blue: 0), "inputColor1": CIColor(red: 1, green: 1, blue: 1)])!.outputImage!
                .transformed(by: CGAffineTransform(scaleX: s.fw * 0.68, y: s.fh * 0.8)
                    .concatenating(CGAffineTransform(rotationAngle: s.roll))
                    .concatenating(CGAffineTransform(translationX: centre.x, y: centre.y)))
                .cropped(to: extent)
            notHead = notHead.map { oval.applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: $0]) } ?? oval
        }
        // hands stay as they are (a hue-based skin rule), and the neck is found by its contrast with the clothes
        // (see neckMask) and left free, however far down it shows and whatever the light
        var free = cam.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": Self.cubeSize, "inputCubeData": notSkinCube(cam: cam), "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB)!])
        // HUE_INGEN_HUDREGEL=1 (replay only) leaves the skin rule out, to see what it takes away
        if ProcessInfo.processInfo.environment["HUE_INGEN_HUDREGEL"] != nil { free = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent) }
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: extent)
        for (i, s) in shapes.enumerated() {
            guard let neck = neckMask(s, cam: cam, slot: i) else { continue }
            let notNeck = neck.composited(over: black).applyingFilter("CIColorInvert").cropped(to: extent)
            free = notNeck.applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: free])
        }
        // softened, then tightened again so the red reaches the edge of the skin instead of fading out before it
        let clothes = free.applyingGaussianBlur(sigma: 3).cropped(to: extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 2.5, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 2.5, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 2.5, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
            .applyingFilter("CIColorClamp")
        var body = person.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: notHead!])
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: clothes])
        // and only what belongs to the clothes themselves (see clothMask): this, not the head's position, decides
        // how far up the red goes
        if let cloth = clothMask(cam: cam, mask: mask, heads: heads) {
            body = body.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: cloth])
        }
        let out = red.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: cam, kCIInputMaskImageKey: body]).cropped(to: extent)
        return out
    }

    // ------------------------------------------------------------------ clothes

    private var clothHistory: (w: Int, h: Int, v: [Float])?

    /// The clothes, found from the clothes themselves. Well below the chin everything on the person is clothes.
    /// From there the region grows upward and sideways over the person as long as the colour changes only
    /// gradually from cell to cell: up over the shoulders, a collar, a hood, wherever they are in the picture. It
    /// stops at the edge to hair and skin. So how the head is held (nodding, leaning forward) does not change what
    /// is clothes; an earlier limit ("never above the mouth") left the shoulders uncoloured when looking down.
    /// White = clothes. Works on a coarse grid of the whole picture, averaged with the last frames.
    private func clothMask(cam: CIImage, mask: CIImage, heads: [[CGPoint]]) -> CIImage? {
        let extent = cam.extent
        guard extent.width > 32, extent.height > 32 else { return nil }
        let gw = 160, gh = max(16, Int(160 * extent.height / extent.width))
        let shrink = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
            .concatenating(CGAffineTransform(scaleX: CGFloat(gw) / extent.width, y: CGFloat(gh) / extent.height))
        let grid = CGRect(x: 0, y: 0, width: gw, height: gh)
        var px = [UInt8](repeating: 0, count: gw * gh * 4), pm = px
        GPU.ciContext.render(cam.transformed(by: shrink), toBitmap: &px, rowBytes: gw * 4, bounds: grid, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        GPU.ciContext.render(mask.transformed(by: shrink), toBitmap: &pm, rowBytes: gw * 4, bounds: grid, format: .RGBA8, colorSpace: nil)
        // row 0 is the top of the picture
        var Y = [Float](repeating: 0, count: gw * gh), Cb = Y, Cr = Y
        for k in 0..<(gw * gh) {
            let r = Float(px[4 * k]), g = Float(px[4 * k + 1]), b = Float(px[4 * k + 2])
            Y[k] = 0.299 * r + 0.587 * g + 0.114 * b
            Cb[k] = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b
            Cr[k] = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b
        }
        // folds make light and shade, but the cloth's colour stays: brightness counts less than colour
        func d(_ a: Int, _ b: Int) -> Float { let y = (Y[a] - Y[b]) * 0.35, cb = Cb[a] - Cb[b], cr = Cr[a] - Cr[b]; return (y * y + cb * cb + cr * cr).squareRoot() }
        // the heads, as measured: no clothes there, and the growth does not pass through them
        var head = [Bool](repeating: false, count: gw * gh)
        if !heads.isEmpty, let g = CGContext(data: nil, width: gw, height: gh, bitsPerComponent: 8, bytesPerRow: gw, space: CGColorSpaceCreateDeviceGray(),
                                             bitmapInfo: CGImageAlphaInfo.none.rawValue), let data = g.data {
            g.setFillColor(gray: 1, alpha: 1)
            g.setShouldAntialias(false)
            for outline in heads where outline.count > 2 {
                g.addLines(between: outline.map { $0.applying(shrink) }); g.closePath(); g.fillPath()
            }
            let bytes = data.assumingMemoryBound(to: UInt8.self), stride = g.bytesPerRow
            for y in 0..<gh { for x in 0..<gw where bytes[y * stride + x] > 127 { head[y * gw + x] = true } }
        }
        func person(_ k: Int) -> Bool { pm[4 * k] > 127 && !head[k] }
        // the start line: a face's height below the lowest chin (or the bottom of the picture, if that is outside it)
        var line = gh - 3
        for s in shapes {
            let y = s.chin.y - s.fh * 0.9
            line = min(line, max(0, Int((extent.maxY - y) / extent.height * CGFloat(gh))))
        }
        var cloth = [Bool](repeating: false, count: gw * gh)
        var stack: [Int] = []
        for y in line..<gh { for x in 0..<gw {
            let k = y * gw + x
            guard person(k) else { continue }
            cloth[k] = true
            // growth starts from the line's own rows, but not from bare skin there (an open collar)
            if y < line + 3, !(Cr[k] > 136 && Cb[k] < 124) { stack.append(k) }
        } }
        guard !stack.isEmpty else { return nil }
        while let k = stack.popLast() {
            let x = k % gw, y = k / gw
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                guard nx >= 0, nx < gw, ny >= 0, ny < line else { continue }
                let n = ny * gw + nx
                if cloth[n] || !person(n) { continue }
                if d(n, k) < 7 { cloth[n] = true; stack.append(n) }
            }
        }
        // The cells along an edge are a mix of the clothes and what is beside them, so the growth stops one cell
        // short. One cell is added all round (skin and the neck are kept free by their own masks), and two more
        // outward across the person's outline.
        for pass in 0..<3 {
            let before = cloth
            for k in 0..<(gw * gh) where !before[k] && !head[k] && (pass == 0 || pm[4 * k] < 230) {
                let x = k % gw, y = k / gw
                if (x > 0 && before[k - 1]) || (x < gw - 1 && before[k + 1]) || (y > 0 && before[k - gw]) || (y < gh - 1 && before[k + gw]) { cloth[k] = true }
            }
        }
        var v = cloth.map { $0 ? Float(1) : 0 }
        if let old = clothHistory, old.w == gw, old.h == gh {
            for k in 0..<v.count { v[k] = old.v[k] * 0.5 + v[k] * 0.5 }
        }
        clothHistory = (gw, gh, v)
        let bytes = Data(v.map { UInt8(max(0, min(255, $0 * 255))) })
        return CIImage(bitmapData: bytes, bytesPerRow: gw, size: CGSize(width: gw, height: gh), format: .L8, colorSpace: nil)
            .applyingGaussianBlur(sigma: 0.7)
            .transformed(by: shrink.inverted())
            .cropped(to: extent)
    }

    // ------------------------------------------------------------------ neck

    private var neckHistory: [Int: (w: Int, h: Int, v: [Float])] = [:]
    /// The face's skin tone per face slot, learned while looking straight ahead.
    private var skinRef: [Int: (y: Float, cb: Float, cr: Float)] = [:]

    /// The neck, found by its contrast with the clothes: in a small, scaled-down cut-out of the camera picture
    /// under the chin, a region grows from a row of pixels just below the chin (always neck) as long as the
    /// colour stays close to the neck's own and changes only gradually from pixel to pixel; it stops at the clear
    /// edge to the collar. Averaged with the last frames so it does not flicker. White = neck.
    private func neckMask(_ s: Shape, cam: CIImage, slot: Int) -> CIImage? {
        let region = CGRect(x: s.chin.x - s.fw * 0.7, y: s.chin.y - s.fh * 1.4, width: s.fw * 1.4, height: s.fh * 1.45)
            .intersection(cam.extent)
        guard region.width > 16, region.height > 16 else { return nil }
        let gw = 64, gh = max(16, min(160, Int(64 * region.height / region.width)))
        let small = cam.cropped(to: region)
            .transformed(by: CGAffineTransform(translationX: -region.minX, y: -region.minY)
                .concatenating(CGAffineTransform(scaleX: CGFloat(gw) / region.width, y: CGFloat(gh) / region.height)))
        var px = [UInt8](repeating: 0, count: gw * gh * 4)
        GPU.ciContext.render(small, toBitmap: &px, rowBytes: gw * 4, bounds: CGRect(x: 0, y: 0, width: gw, height: gh),
                             format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        // row 0 is the top of the cut-out (both when rendering to and reading from a bitmap)
        var Y = [Float](repeating: 0, count: gw * gh), Cb = Y, Cr = Y
        for k in 0..<(gw * gh) {
            let r = Float(px[4 * k]), g = Float(px[4 * k + 1]), b = Float(px[4 * k + 2])
            Y[k] = 0.299 * r + 0.587 * g + 0.114 * b
            Cb[k] = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b
            Cr[k] = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b
        }
        func d(_ a: Int, _ b: Int) -> Float { let y = (Y[a] - Y[b]) * 0.6, cb = Cb[a] - Cb[b], cr = Cr[a] - Cr[b]; return (y * y + cb * cb + cr * cr).squareRoot() }
        // seeds: in a band just under the chin, the pixels that look like the face's own skin (sampled on the
        // cheeks in the same frame), allowing for the neck being darker; the chin point alone may sit on the
        // collar when the head is turned
        // the skin tone is learned only while looking straight ahead (and slowly); turned or tilted back the
        // cheeks fall into shadow, so the remembered tone is used instead of a darker measurement
        if s.frontal, let t = cheekTone(s, cam: cam) {
            if let r = skinRef[slot] {
                skinRef[slot] = (r.y + (t.y - r.y) * 0.1, r.cb + (t.cb - r.cb) * 0.1, r.cr + (t.cr - r.cr) * 0.1)
            } else { skinRef[slot] = t }
        }
        guard let tone = skinRef[slot] ?? cheekTone(s, cam: cam) else { return nil }
        func rowOf(_ y: CGFloat) -> Int { max(0, min(gh - 1, Int((region.maxY - y) / region.height * CGFloat(gh)))) }
        let top = rowOf(s.chin.y - s.fh * 0.02), bottom = rowOf(s.chin.y - s.fh * 0.3)
        let cx = (s.chin.x - region.minX) / region.width * CGFloat(gw)
        let half = Int(s.fw * 0.35 / region.width * CGFloat(gw))
        var seeds: [Int] = []
        for y in top...max(top, bottom) {
            for x in max(0, Int(cx) - half)...min(gw - 1, Int(cx) + half) {
                let k = y * gw + x
                let dcb: Float = Cb[k] - tone.cb, dcr: Float = Cr[k] - tone.cr
                let dy: Float = max(0, Y[k] - tone.y) * 0.4 + max(0, tone.y - Y[k]) * 0.15
                let chroma: Float = (dcb * dcb + dcr * dcr).squareRoot()
                // close to the cheeks' tone and warm like skin (a grey collar in shadow must not pass)
                if chroma + dy < 11 && Cr[k] > 132 && Cb[k] < 127 { seeds.append(k) }
            }
        }
        let row = top
        guard seeds.count >= 3 else {
            if slot == 99 { print(String(format: "hals: ingen frø (kindtone Y %.0f Cb %.0f Cr %.0f)", tone.y, tone.cb, tone.cr)) }
            return nil
        }
        let mY = seeds.map { Y[$0] }.reduce(0, +) / Float(seeds.count)
        let mCb = seeds.map { Cb[$0] }.reduce(0, +) / Float(seeds.count), mCr = seeds.map { Cr[$0] }.reduce(0, +) / Float(seeds.count)
        func dSeed(_ a: Int) -> Float { let y = (Y[a] - mY) * 0.6, cb = Cb[a] - mCb, cr = Cr[a] - mCr; return (y * y + cb * cb + cr * cr).squareRoot() }
        // grow downward from the seed row (above it is the face)
        var neck = [Bool](repeating: false, count: gw * gh)
        var stack = seeds
        for k in stack { neck[k] = true }
        while let k = stack.popLast() {
            let x = k % gw, y = k / gw
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y + 1), (x, y - 1)] {
                guard nx >= 0, nx < gw, ny >= top, ny < gh else { continue }
                let n = ny * gw + nx
                if neck[n] { continue }
                if dSeed(n) < 22 && d(n, k) < 8 && Cr[n] > 130 { neck[n] = true; stack.append(n) }
            }
        }
        if slot == 99 {
            print(String(format: "hals: udsnit %.0f,%.0f %.0f×%.0f, gitter %d×%d, frørække %d, %d frø, frøfarve Y %.0f Cb %.0f Cr %.0f, hage %.0f,%.0f fh %.0f fw %.0f, vokset %d",
                         region.minX, region.minY, region.width, region.height, gw, gh, row, seeds.count, mY, mCb, mCr, s.chin.x, s.chin.y, s.fh, s.fw, neck.filter { $0 }.count))
        }
        // a little wider (the edge pixels are half neck), and averaged with the previous frames
        var v = [Float](repeating: 0, count: gw * gh)
        for k in 0..<(gw * gh) where neck[k] {
            let x = k % gw, y = k / gw
            for (nx, ny) in [(x, y), (x - 1, y), (x + 1, y), (x, y + 1)] where nx >= 0 && nx < gw && ny < gh { v[ny * gw + nx] = 1 }
        }
        if let old = neckHistory[slot], old.w == gw, old.h == gh {
            for k in 0..<v.count { v[k] = old.v[k] * 0.5 + v[k] * 0.5 }
        }
        neckHistory[slot] = (gw, gh, v)
        let bytes = Data(v.map { UInt8(max(0, min(255, $0 * 255))) })
        return CIImage(bitmapData: bytes, bytesPerRow: gw, size: CGSize(width: gw, height: gh), format: .L8, colorSpace: nil)
            .applyingGaussianBlur(sigma: 0.8)
            .transformed(by: CGAffineTransform(scaleX: region.width / CGFloat(gw), y: region.height / CGFloat(gh))
                .concatenating(CGAffineTransform(translationX: region.minX, y: region.minY)))
            .cropped(to: region)
    }

    /// The face's own skin tone in this frame: the average of two patches on the cheeks (beside the nose).
    private func cheekTone(_ s: Shape, cam: CIImage) -> (y: Float, cb: Float, cr: Float)? {
        let lc = s.lips.reduce(CGPoint.zero) { $0 + $1 } * (1 / CGFloat(s.lips.count))
        let nc = s.nose.reduce(CGPoint.zero) { $0 + $1 } * (1 / CGFloat(s.nose.count))
        var acc: [Float] = [0, 0, 0], n: Float = 0
        for side in [-1.0, 1.0] as [CGFloat] {
            let p = (lc + nc) * 0.5 + s.right * (side * s.fw * 0.22)
            let r = CGRect(x: p.x - s.fw * 0.06, y: p.y - s.fw * 0.06, width: s.fw * 0.12, height: s.fw * 0.12)
            guard cam.extent.contains(r) else { continue }
            var px = [UInt8](repeating: 0, count: 4)
            GPU.ciContext.render(cam.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: r)]), toBitmap: &px, rowBytes: 4,
                                 bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            let R = Float(px[0]), G = Float(px[1]), B = Float(px[2])
            acc[0] += 0.299 * R + 0.587 * G + 0.114 * B
            acc[1] += 128 - 0.168736 * R - 0.331264 * G + 0.5 * B
            acc[2] += 128 + 0.5 * R - 0.418688 * G - 0.081312 * B
            n += 1
        }
        return n > 0 ? (acc[0] / n, acc[1] / n, acc[2] / n) : nil
    }

    /// Test aid: the neck mask of the first face on its own (white = neck), in picture coordinates.
    func neckMaskForTest(cam: CIImage) -> CIImage? { shapes.first.flatMap { neckMask($0, cam: cam, slot: 99) } }

    // ------------------------------------------------------------------ skin

    /// Colour cube: 1 for everything that is not skin-coloured, 0 for skin, soft in between. Skin is judged on
    /// its hue (YCbCr chroma), not its brightness. With no measured skin tone the range is everything that could
    /// be skin (Cb 80–125, Cr 139–173); grey (Cr ≈ 128) stays clothes.
    private static let notSkinCube: Data = makeNotSkinCube(cb: 80...125, cr: 139...173)

    private static func makeNotSkinCube(cb cbRange: ClosedRange<Float>, cr crRange: ClosedRange<Float>) -> Data {
        let n = cubeSize
        func ramp(_ v: Float, _ lo: Float, _ hi: Float, _ soft: Float) -> Float {
            min(max((v - (lo - soft)) / soft, 0), 1) * min(max(((hi + soft) - v) / soft, 0), 1)
        }
        var data = [Float](repeating: 0, count: n * n * n * 4)
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            let R = Float(r) / Float(n - 1) * 255, G = Float(g) / Float(n - 1) * 255, B = Float(b) / Float(n - 1) * 255
            let y = 0.299 * R + 0.587 * G + 0.114 * B
            let cb = 128 - 0.168736 * R - 0.331264 * G + 0.5 * B
            let cr = 128 + 0.5 * R - 0.418688 * G - 0.081312 * B
            let skin = ramp(cb, cbRange.lowerBound, cbRange.upperBound, 6) * ramp(cr, crRange.lowerBound, crRange.upperBound, 6) * min(max((y - 25) / 20, 0), 1)
            let v = 1 - skin
            let i = ((b * n + g) * n + r) * 4
            data[i] = v; data[i + 1] = v; data[i + 2] = v; data[i + 3] = 1
        } } }
        return data.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// The skin rule for this picture: skin is what has the hue of the cheeks of the people in it, measured now
    /// (and steadied over the last frames), not everything that could be anyone's skin. The wide range took
    /// clothes for skin: a grey sweater in warm lamp light fell inside it in patches that changed from frame to
    /// frame, so the suit flickered and had holes on the shoulders (live 2026-11-18).
    private var skinTone: (cb: Float, cr: Float)?
    private var skinCube: (cb: Float, cr: Float, data: Data)?
    private func notSkinCube(cam: CIImage) -> Data {
        let tones = shapes.compactMap { cheekTone($0, cam: cam) }
        guard !tones.isEmpty else { return skinCube?.data ?? Self.notSkinCube }
        let cb = tones.map(\.cb).reduce(0, +) / Float(tones.count), cr = tones.map(\.cr).reduce(0, +) / Float(tones.count)
        var t: (cb: Float, cr: Float) = (cb, cr)
        if let s = skinTone { t = (s.cb + (cb - s.cb) * 0.1, s.cr + (cr - s.cr) * 0.1) }
        skinTone = t
        if let c = skinCube, abs(c.cb - t.cb) < 1.5, abs(c.cr - t.cr) < 1.5 { return c.data }
        // hands and neck differ a little from the cheeks; several people in the picture share one range
        let spread: Float = tones.count > 1 ? 14 : 9
        let data = Self.makeNotSkinCube(cb: (t.cb - spread)...(t.cb + spread), cr: (t.cr - spread)...(t.cr + spread))
        skinCube = (t.cb, t.cr, data)
        return data
    }

    // ------------------------------------------------------------------ beard

    /// The beards (and moustaches) for all faces, as one image to lay over the picture; with `mouth` the mouth
    /// stays open (see VirtualCamera: the opening is only cut where the person is behind it).
    func beardImage(extent: CGRect, mouth: Bool = true) -> CIImage? {
        guard !shapes.isEmpty else { return nil }
        var bounds = CGRect.null
        for s in shapes {
            for p in s.contour { bounds = bounds.union(CGRect(origin: p, size: .zero)) }
            // (a longer beard, as the Wichtel's, needs more room below the chin)
            bounds = bounds.union(CGRect(origin: s.chin - s.up * (s.fh * 0.6 * max(1, CameraCostume.look.beard)), size: .zero))
            bounds = bounds.union(CGRect(x: s.centre.x - s.fh * 1.5, y: s.centre.y - s.fh * 1.7, width: s.fh * 3, height: s.fh * 2.6))
        }
        bounds = bounds.insetBy(dx: -40, dy: -40).intersection(extent).integral
        guard bounds.width > 4, bounds.height > 4,
              let g = CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        g.translateBy(x: -bounds.minX, y: -bounds.minY)
        for s in shapes { drawBeard(s, into: g, mouth: mouth) }
        guard let img = g.makeImage() else { return nil }
        return CIImage(cgImage: img).transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
    }

    /// The beard as a band lying on the face, turned with the head.
    ///
    /// Round the front of the head (see `measureFace`), from in front of one ear past the chin to the other: its top
    /// edge runs from the ear down across the cheek to the point under the nose, its bottom edge follows the jaw and
    /// hangs below the chin. By the ears it is as broad as the head, at the jaw as broad as the face there. Only the
    /// part that is turned toward the camera is drawn: on the far side the beard ends at the face's own profile
    /// (never outside the person mask's edge there), and on the near side it reaches back to the ear.
    private func wrappedBeard(_ s: Shape, _ f: Face) -> CGMutablePath? {
        guard f.jaw > 4, f.front > 4, f.chinY < -4 else { return nil }
        let up = s.up, right = s.right, under = s.under
        let cy = cos(s.yaw), sy = sin(s.yaw)
        let deep = f.front + f.back
        let earY = 0.6 * f.eyeY
        let pad = f.size * 0.03
        let reach: CGFloat = 1.5, m = 60
        /// How far the beard stands out from the skin at a height: thin up by the ear, full at the chin and below.
        func thickness(_ y: CGFloat) -> CGFloat {
            f.size * (0.025 + 0.075 * min(1, max(0, (earY - y) / max(1, earY - f.chinY))))
        }
        var top: [CGPoint] = [], bottom: [CGPoint] = [], seen: [Bool] = [], lit: [CGFloat] = []
        for k in 0...m {
            let phi = (CGFloat(k) / CGFloat(m) * 2 - 1) * reach      // 0 at the chin, ±reach by the ears
            let sp = sin(phi), cp = cos(phi), u = abs(phi) / reach
            let wTop = f.jaw + (f.ear - f.jaw) * u * u, wBottom = f.jaw + (f.ear - f.jaw) * pow(u, 4)
            // the face's surface there, and which way it faces
            var nx = sp / wTop, nz = cp / deep
            let nl = max(1e-6, hypot(nx, nz)); nx /= nl; nz /= nl
            seen.append(-nx * sy + nz * cy > -0.03)
            // how much light the face's surface gets there (the light comes from the upper left, in front)
            lit.append(0.62 + 0.38 * max(0, (nx * cy + nz * sy) * -0.45 + (-nx * sy + nz * cy) * 0.75 + 0.2))
            func place(_ x: CGFloat, _ z: CGFloat, _ y: CGFloat) -> CGPoint {
                var side = x * cy + (z - f.front) * sy
                // A beard grows out from the skin: its inside sits on the face, its outside stands out from it by
                // the beard's thickness, also past the face's outline. What must not happen is beard further out
                // than that, with nothing but background behind it ("hanging in the air"). So a point may lie at
                // most the thickness outside the person's outline at its height (the outline exactly as scanned in
                // this frame); below the chin, outside the outline at the chin.
                // (First it was kept inside the outline: then it looked painted on, cut off flat at the profile.)
                let (lo, hi) = f.edges(max(y, f.chinY * 0.92))
                let t = thickness(y)
                if hi - lo > 4 * pad { side = min(max(side, lo - t), hi + t) }
                return under + right * side + up * y
            }
            let z = deep * cp - f.back
            // top edge: from the ear down across the cheek to under the nose
            top.append(place(wTop * sp, z, earY * pow(u, 1.3) - f.size * 0.05 * sin(.pi * u)))
            // bottom edge: along the jaw, a little out from it, hanging below the chin (longest in the middle)
            // The jaw bone runs from the chin out to the jaw's corner at nearly the same height, and only there
            // turns up toward the ear. The beard's edge does the same, so it covers the whole jaw: it stays low and
            // full out to the corner and then goes fairly straight up. (As a curve rising evenly from the chin it
            // was a parabola that left the jaw bone bare; live 2026-11-17.)
            let corner: CGFloat = 0.76
            let alongJaw = f.chinY * (1 - 0.22 * pow(min(u, corner) / corner, 1.6))
            let rise = max(0, (u - corner) / (1 - corner)), up2 = rise * rise * (3 - 2 * rise)
            let jawLine = alongJaw + (earY * 0.8 - alongJaw) * up2
            let curl = f.size * 0.04 * (1 - u) * (abs(sin(u * 13 + (phi < 0 ? 1.7 : 0))) * 0.8 + abs(sin(u * 31)) * 0.2)
            let out = f.size * (0.03 + 0.05 * (1 - up2)) + curl
            // Longest under the chin and getting shorter out along the jaw, so the beard narrows toward its end
            // instead of being as broad at the bottom as at the jaw; a little is left under the jaw's corner, so
            // the jaw bone stays covered. (Nearly full length all the way out made the bottom too broad.)
            // (rounded: full under the chin and a good way out, then shorter; a straight shortening from the chin
            // out made the beard end in a point)
            // (the folk's beard is longer or shorter than the nisse's: only what hangs below the jaw changes)
            let hang = f.size * (0.5 * CGFloat(CameraCostume.look.beard) * max(0, 1 - pow(u / 0.95, 1.5)) + 0.06) * (1 - up2)
            bottom.append(place(wBottom * sp + out * nx, z + out * nz, jawLine - hang))
        }
        guard let a = seen.firstIndex(of: true), let b = seen.lastIndex(of: true), b - a >= 4 else { return nil }
        // Where the band ends at the face's profile (not by an ear), the hanging part is rounded up to the jaw
        // over the last stretch: cut straight off there, the beard had a long vertical edge down from the profile.
        let round = 12
        for k in a...b {
            let fromEnd = min(a > 0 ? k - a : round, b < m ? b - k : round)
            guard fromEnd < round else { continue }
            let t = CGFloat(fromEnd) / CGFloat(round), keep = t * t * (3 - 2 * t)
            let jawLine = top[k] + (bottom[k] - top[k]) * 0.55
            bottom[k] = jawLine + (bottom[k] - jawLine) * keep
        }
        // Where the band ends at the face's profile, the beard stands out past the profile by its thickness (the
        // face's surface turns away from the camera there, the hair on it does not). The band is drawn out to that
        // gradually over its last stretch. (Moving only its very end out left a square tab sticking out beside
        // the cheek; live 2026-11-17.)
        for (end, side) in [(a, CGFloat(-1)), (b, CGFloat(1))] where (end == a ? a > 0 : b < m) {
            for d in 0..<round {
                let k = end == a ? a + d : b - d
                guard k >= a, k <= b else { break }
                let t = CGFloat(d) / CGFloat(round), share = 1 - t * t * (3 - 2 * t)
                for isTop in [true, false] {
                    let p = isTop ? top[k] : bottom[k]
                    let y = dot(p - under, up), across = dot(p - under, right)
                    let (lo, hi) = f.edges(max(y, f.chinY * 0.92))
                    let edge = side < 0 ? lo : hi
                    guard edge.isFinite else { continue }
                    var out = edge + side * thickness(y) * (isTop ? 0.5 : 0.85)
                    guard (out - across) * side > 0 else { continue }
                    // Never more than about the thickness out from where the face itself is taken to be: low on the
                    // face the person's outline is not the face's but the hood's or the shoulder's beside it, and
                    // the beard was drawn out to that in a long point (live 2026-11-17).
                    out = across + side * min((out - across) * side, thickness(y) * 1.2)
                    let q = under + right * (across + (out - across) * share) + up * y
                    if isTop { top[k] = q } else { bottom[k] = q }
                }
            }
        }
        let path = CGMutablePath()
        path.move(to: bottom[a])
        smoothCurve(path, through: Array(bottom[a...b]))
        path.addLine(to: top[b])
        smoothCurve(path, through: Array(top[a...b].reversed()))
        path.closeSubpath()
        return path
    }


    /// The beard drawn flat from Vision's jaw line: used until the head has been measured. Right from the front,
    /// but it does not turn with the head (the far side of the jaw line is a guess then).
    private func flatBeard(_ s: Shape) -> CGMutablePath {
        let up = s.up, right = s.right, under = s.under
        let n = s.contour.count
        let i0 = max(1, Int(CGFloat(n) * 0.14)), i1 = min(n - 2, Int(CGFloat(n) * 0.86))
        // outer edge: the jaw line pushed a little out, hanging well below the chin (longest in the middle)
        var outer: [CGPoint] = []
        let sub = 4   // several points between two landmarks, so the edge can curl
        for k in i0...i1 {
            for j in 0..<(k < i1 ? sub : 1) {
                let f = CGFloat(j) / CGFloat(sub)
                let p = k < i1 ? s.contour[k] + (s.contour[k + 1] - s.contour[k]) * f : s.contour[k]
                let t = (CGFloat(k - i0) + f) / CGFloat(max(1, i1 - i0))
                let out = norm(p - s.centre)
                let hang = pow(sin(.pi * t), 1.3) * s.fh * 0.5 * CGFloat(CameraCostume.look.beard)
                // soft curls: a small wave along the edge, fixed to the beard (not flickering)
                let curl = s.fw * 0.05 * sin(.pi * t) * (abs(sin(t * 26)) * 0.8 + abs(sin(t * 63)) * 0.2)
                outer.append(p + out * (s.fw * (0.04 + 0.08 * sin(.pi * t)) + curl) - up * hang)
            }
        }
        // top edge: from the cheek in under the nose and out to the other cheek (the moustache line)
        let beard = CGMutablePath()
        beard.move(to: outer[0])
        smoothCurve(beard, through: outer)
        beard.addQuadCurve(to: under + right * (s.fw * 0.12), control: s.contour[i1] + (under - s.contour[i1]) * 0.5 - up * (s.fh * 0.06))
        beard.addLine(to: under - right * (s.fw * 0.12))
        beard.addQuadCurve(to: outer[0], control: s.contour[i0] + (under - s.contour[i0]) * 0.5 - up * (s.fh * 0.06))
        beard.closeSubpath()
        return beard
    }

    private func drawBeard(_ s: Shape, into g: CGContext, mouth open: Bool) {
        let up = s.up, right = s.right
        let under = s.under
        let cy = cos(s.yaw), sy = sin(s.yaw)
        /// A point on the face: `x` to the person's side, `y` up, `z` out of the face, from the point under the nose.
        func onFace(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint { under + right * (x * cy + z * sy) + up * y }
        let wrapped = s.face.flatMap { wrappedBeard(s, $0) }
        let beard = wrapped ?? flatBeard(s)
        // sizes follow the head's breadth when it is measured: Vision's face height shrinks when the head turns
        let size = s.face?.size ?? s.fh
        // the mouth stays open
        let lc = s.lips.reduce(CGPoint.zero) { $0 + $1 } * (1 / CGFloat(s.lips.count))
        let mouth = CGMutablePath()
        let lips = s.lips.map { lc + ($0 - lc) * 1.2 - up * (size * 0.01) }
        mouth.move(to: lips[0]); smoothCurve(mouth, through: lips + [lips[0]]); mouth.closeSubpath()
        if open { beard.addPath(mouth) }

        // Moustache: two lobes from under the nose curling out past the mouth corners. It is the costume's own
        // shape, so its size is a share of the face's height (which does not change when the head turns), and it
        // lies on the face in depth: the lobes curve back round the cheeks. It is turned with the head (Vision's
        // yaw), so the lobe on the side turned away gets narrower and disappears behind the nose, and the near
        // one reaches back along the cheek. (Drawn flat from the lip corners, it stayed as wide as from the front
        // however far the head turned.) The depths are kept modest: with the cheeks' full depth the two lobes
        // became so unequal at a 35° turn that the moustache looked crooked against the beard, which is not turned.
        let mouthY = dot(lc - under, up)   // how far below the nose the mouth is, as measured
        let moustache = CGMutablePath()
        for side in [-1.0 as CGFloat, 1.0] {
            // On the measured face the lobes lie on the same rounded front as the beard (`angle` round it from the
            // middle line), so the two turn together; until the head is measured, on a face of ordinary depth.
            func lobe(_ angle: CGFloat, _ y: CGFloat) -> CGPoint {
                guard let f = s.face else { return onFace(side * size * 0.5 * sin(angle), y, -size * 0.35 * (1 - cos(angle))) }
                var across = side * f.jaw * sin(angle) * cy + f.front * (cos(angle) - 1) * sy
                // like the beard: on the side the face turns toward, not outside the face's profile
                if s.yaw > 0.25 { across = min(across, f.hi) } else if s.yaw < -0.25 { across = max(across, f.lo) }
                return under + right * across + up * y
            }
            let tip = lobe(0.62, mouthY - size * 0.07)
            // turned away so far that the lobe points back behind the nose: it cannot be seen
            if dot(tip - under, right) * side < size * 0.02 { continue }
            let start = under + up * (size * 0.03), bend = lobe(0.42, size * 0.02)
            moustache.move(to: start)
            moustache.addQuadCurve(to: tip, control: bend)
            moustache.addQuadCurve(to: under - up * (size * 0.05), control: lobe(0.38, mouthY + size * 0.05))
            moustache.closeSubpath()
        }

        /// The shape itself: a soft white glow makes the edge fuzzy, a soft shadow under it gives depth against the
        /// face, and inside it wavy strands and a little shading toward the sides.
        func fur(_ path: CGPath, evenOdd: Bool, pattern: Bool) {
            for (blur, colour, dy) in [(size * 0.035, C(255, 255, 255, 230), CGFloat(0)), (size * 0.05, C(60, 50, 50, 110), -size * 0.015)] {
                g.saveGState()
                g.setShadow(offset: CGSize(width: 0, height: dy), blur: blur, color: colour)
                g.addPath(path); g.setFillColor(C(242, 243, 247))
                if evenOdd { g.fillPath(using: .evenOdd) } else { g.fillPath() }
                g.restoreGState()
            }
            g.saveGState()
            g.addPath(path)
            if evenOdd { g.clip(using: .evenOdd) } else { g.clip() }
            let box = path.boundingBoxOfPath
            if pattern { g.setAlpha(0.35); g.draw(Self.furTexture, in: box); g.setAlpha(1) }
            let shade = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                   colors: [C(255, 255, 255, 0), C(255, 255, 255, 0), C(140, 150, 175, 130)] as CFArray, locations: [0, 0.45, 1])!
            let lightAt = CGPoint(x: box.midX - box.width * 0.08, y: box.midY + box.height * 0.12)
            g.drawRadialGradient(shade, startCenter: lightAt, startRadius: 0, endCenter: lightAt,
                                 endRadius: max(box.width, box.height) * 0.62, options: [.drawsAfterEndLocation])
            g.restoreGState()
        }
        if wrapped != nil {
            // cotton wool (see `cotton`); the moustache lies on top of the beard with its own soft shadow
            g.saveGState()
            if open {
                // the softening would close a narrow mouth: the opening is kept as measured
                let around = CGMutablePath()
                around.addRect(beard.boundingBoxOfPath.insetBy(dx: -size, dy: -size)); around.addPath(mouth)
                g.addPath(around); g.clip(using: .evenOdd)
            }
            cotton(beard, evenOdd: true, into: g, s, size: size, shadow: 0.9)
            g.restoreGState()
            if !moustache.isEmpty { cotton(moustache, evenOdd: false, into: g, s, size: size, shadow: 1.5) }
        } else {
            fur(beard, evenOdd: true, pattern: true)
            if !moustache.isEmpty { fur(moustache, evenOdd: false, pattern: true) }
        }
    }

    // ------------------------------------------------------------------ cotton wool

    /// Smooth random fields that repeat every `noiseSize` cells: `lumps` are broad soft clumps (a few sizes laid
    /// over each other), `fibres` a fine ridged tangle.
    private static let noiseSize = 256
    private static let noise: (lumps: [Float], fibres: [Float]) = {
        let n = noiseSize
        var rng = SeededRandom(seed: 91)
        func layer(_ cells: Int) -> [Float] {
            let grid = (0..<(cells * cells)).map { _ in Float(rng.next()) }
            var out = [Float](repeating: 0, count: n * n)
            for y in 0..<n { for x in 0..<n {
                let fx = Float(x) / Float(n) * Float(cells), fy = Float(y) / Float(n) * Float(cells)
                let x0 = Int(fx), y0 = Int(fy), x1 = (x0 + 1) % cells, y1 = (y0 + 1) % cells
                var tx = fx - Float(x0), ty = fy - Float(y0)
                tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty)
                let a = grid[y0 * cells + x0] * (1 - tx) + grid[y0 * cells + x1] * tx
                let b = grid[y1 * cells + x0] * (1 - tx) + grid[y1 * cells + x1] * tx
                out[y * n + x] = a * (1 - ty) + b * ty
            } }
            return out
        }
        let l1 = layer(4), l2 = layer(9), l3 = layer(19), f1 = layer(40), f2 = layer(83)
        var lumps = [Float](repeating: 0, count: n * n), fibres = lumps
        for i in 0..<(n * n) {
            lumps[i] = l1[i] * 0.5 + l2[i] * 0.32 + l3[i] * 0.18
            // ridges: bright where a field crosses its middle, so thin tangled lines instead of dots
            fibres[i] = (1 - abs(2 * f1[i] - 1)) * 0.6 + (1 - abs(2 * f2[i] - 1)) * 0.4
        }
        return (lumps, fibres)
    }()

    /// Fills a shape with cotton wool and draws it.
    ///
    /// Cotton wool has no outline and no pattern: it is a soft mass with a ragged, half see-through edge, clumps
    /// that catch the light on one side and shade the other, and a fine tangle of fibres. So the shape is first
    /// softened (its edge becomes a ramp), then clumps of several sizes are added to the ramp: where the sum is
    /// high there is wool, and the edge becomes ragged where the clumps cross it. The same sum is the wool's
    /// thickness, and its slope toward the light gives each clump a lit and a shaded side. The clumps and fibres
    /// are fixed to the face (measured from the point under the nose along the head's axes), so they move with it.
    /// Worked out at half size and scaled up, which only makes it softer.
    /// (Rejected live 2026-11-17: round tufts = "circles piled up", wavy strokes = "white yarn", soft round
    /// gradients = "a board spray-painted with ball prints".)
    private func cotton(_ path: CGPath, evenOdd: Bool, into g: CGContext, _ s: Shape, size: CGFloat, shadow: CGFloat) {
        let margin = size * 0.09
        let box = path.boundingBoxOfPath.insetBy(dx: -margin, dy: -margin).integral
        let scale: CGFloat = 0.5
        let w = Int(box.width * scale), h = Int(box.height * scale)
        guard w > 8, h > 8, w < 1500, h < 1500,
              let m = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue), let data = m.data else { return }
        m.scaleBy(x: scale, y: scale); m.translateBy(x: -box.minX, y: -box.minY)
        m.setFillColor(gray: 1, alpha: 1)
        m.addPath(path)
        if evenOdd { m.fillPath(using: .evenOdd) } else { m.fillPath() }
        let bytes = data.assumingMemoryBound(to: UInt8.self), stride = m.bytesPerRow
        // the shape, softened: three passes of a running average, across and down
        var soft = [Float](repeating: 0, count: w * h), tmp = soft
        for y in 0..<h { for x in 0..<w { soft[y * w + x] = Float(bytes[y * stride + x]) / 255 } }
        let r = max(1, Int(size * 0.028 * scale))
        for _ in 0..<3 {
            for y in 0..<h {
                var sum: Float = 0
                for x in -r...r { sum += soft[y * w + min(w - 1, max(0, x))] }
                for x in 0..<w {
                    tmp[y * w + x] = sum / Float(2 * r + 1)
                    sum += soft[y * w + min(w - 1, x + r + 1)] - soft[y * w + max(0, x - r)]
                }
            }
            for x in 0..<w {
                var sum: Float = 0
                for y in -r...r { sum += tmp[min(h - 1, max(0, y)) * w + x] }
                for y in 0..<h {
                    soft[y * w + x] = sum / Float(2 * r + 1)
                    sum += tmp[min(h - 1, y + r + 1) * w + x] - tmp[max(0, y - r) * w + x]
                }
            }
        }
        // thickness: the softened shape with clumps on it
        let n = Self.noiseSize
        let under = s.under, up = s.up, right = s.right
        let perTile = size * 0.75          // one repeat of the fields, in picture pixels
        var thick = [Float](repeating: 0, count: w * h), fine = thick, strand = thick
        for y in 0..<h { for x in 0..<w {
            // (row 0 of the bitmap is the top)
            let p = CGPoint(x: box.minX + (CGFloat(x) + 0.5) / scale, y: box.maxY - (CGFloat(y) + 0.5) / scale)
            let u = dot(p - under, right) / perTile, v = dot(p - under, up) / perTile
            let nx = Int((u - u.rounded(.down)) * CGFloat(n)) % n, ny = Int((v - v.rounded(.down)) * CGFloat(n)) % n
            let i = y * w + x
            thick[i] = soft[i] + (Self.noise.lumps[ny * n + nx] - 0.5) * 0.55
            fine[i] = Self.noise.fibres[ny * n + nx]
            // Hair: the same tangle read stretched along the way the beard grows (down the head), and bent a
            // little by the clumps, gives long fine strands that wave instead of dots.
            let bendBy = CGFloat(Self.noise.lumps[ny * n + nx]) * 0.35
            let su = u * 5.5 + bendBy, sv = v * 0.42
            let sx = Int((su - su.rounded(.down)) * CGFloat(n)) % n, sy2 = Int((sv - sv.rounded(.down)) * CGFloat(n)) % n
            strand[i] = Self.noise.fibres[sy2 * n + sx]
        } }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            let t = thick[i] + (fine[i] - 0.5) * 0.06 + (strand[i] - 0.5) * 0.16
            // wool where the thickness is over a threshold; just under it, thin and see-through
            var alpha: Float = (t - 0.44) / 0.20
            alpha = max(0, min(1, alpha)); alpha = alpha * alpha * (3 - 2 * alpha)
            if alpha <= 0 { continue }
            // the slope of the thickness toward the light (upper left): a lit side and a shaded side on every clump
            let ya: Int = max(0, y - 2), xa: Int = max(0, x - 2), yb: Int = min(h - 1, y + 2), xb: Int = min(w - 1, x + 2)
            let a: Float = thick[ya * w + xa], b: Float = thick[yb * w + xb]
            var light: Float = 0.72 + (b - a) * 3.2
            light += (fine[i] - 0.5) * 0.05 + (strand[i] - 0.5) * 0.30
            // deeper in the mass a little darker than at the top of the clumps
            light -= max(0, 0.9 - thick[i]) * 0.08
            light = max(0, min(1, light))
            let red: Float = 196 + 59 * light, green: Float = 200 + 55 * light, blue: Float = 212 + 43 * light
            let r8: Float = red * alpha, g8: Float = green * alpha, b8: Float = blue * alpha, a8: Float = 255 * alpha
            px[i * 4] = UInt8(r8); px[i * 4 + 1] = UInt8(g8); px[i * 4 + 2] = UInt8(b8); px[i * 4 + 3] = UInt8(a8)
        } }
        guard let provider = CGDataProvider(data: Data(px) as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
                                  shouldInterpolate: true, intent: .defaultIntent) else { return }
        g.saveGState()
        g.interpolationQuality = .high
        // a soft shadow under the wool, following its ragged edge, sets it off from the face
        g.setShadow(offset: CGSize(width: 0, height: -size * 0.012 * shadow), blur: size * 0.03 * shadow, color: C(50, 44, 48, 105))
        g.draw(image, in: box)
        g.restoreGState()
    }

    // ------------------------------------------------------------------ resources

    private static let cubeSize = 32
    /// Wavy white strands for the beard's texture.
    private static let furTexture: CGImage = {
        let s = 256
        let g = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var rng = SeededRandom(seed: 1224)
        g.setLineCap(.round)
        // small curls (arcs at random angles), light and shadowed, so the beard looks woolly
        for _ in 0..<520 {
            let x = CGFloat(rng.next()) * CGFloat(s), y = CGFloat(rng.next()) * CGFloat(s)
            let r = 4 + CGFloat(rng.next()) * 7, a0 = CGFloat(rng.next()) * 2 * .pi
            let light = rng.next() < 0.55
            g.setStrokeColor(light ? C(255, 255, 255, 210) : C(165, 174, 195, 140))
            g.setLineWidth(1 + CGFloat(rng.next()) * 1.4)
            g.addArc(center: CGPoint(x: x, y: y), radius: r, startAngle: a0, endAngle: a0 + 2.6, clockwise: false)
            g.strokePath()
        }
        return g.makeImage()!
    }()

    // ------------------------------------------------------------------ test

    /// Test aid (--nissedragt-test=DIR,IMAGE): puts beard and suit on the person in a photo (med-nissedragt.png).
    static func test(dir: String, image: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let src = CIImage(contentsOf: URL(fileURLWithPath: image)) else { print("kan ikke læse", image); return }
        let handler = VNImageRequestHandler(ciImage: src, options: [:])
        let hat = NisseHat(), costume = NisseCostume()
        let seg = VNGeneratePersonSegmentationRequest()
        seg.qualityLevel = .balanced
        seg.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try? handler.perform([seg, hat.request])
        let faces = hat.request.results ?? []
        let t0 = CACurrentMediaTime()
        let lm = costume.detect(handler, faces: faces)
        print(String(format: "%d ansigt(er), landmarks på %.1f ms", lm.count, (CACurrentMediaTime() - t0) * 1000))
        guard let maskBuffer = seg.results?.first?.pixelBuffer else { print("ingen maske"); return }
        let maskRaw = CIImage(cvPixelBuffer: maskBuffer)
        let mask = maskRaw.transformed(by: CGAffineTransform(scaleX: src.extent.width / maskRaw.extent.width, y: src.extent.height / maskRaw.extent.height))
        costume.update(lm, extent: src.extent, transform: .identity)
        let t1 = CACurrentMediaTime()
        var out = costume.applySuit(to: src, mask: mask)
        if let beard = costume.beardImage(extent: src.extent) { out = beard.composited(over: out) }
        guard let cg = GPU.ciContext.createCGImage(out.cropped(to: src.extent), from: src.extent) else { return }
        print(String(format: "dragt og skæg på %.1f ms", (CACurrentMediaTime() - t1) * 1000))
        try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("med-nissedragt.png"))
        print("skrev med-nissedragt.png")
        // the neck as found (green over the photo), to check that it stops at the collar
        if let neck = costume.neckMaskForTest(cam: src) {
            let green = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 0.6)).cropped(to: src.extent)
            let over = green.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: src, kCIInputMaskImageKey: neck.composited(over: CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: src.extent))])
            if let cg = GPU.ciContext.createCGImage(over.cropped(to: src.extent), from: src.extent) {
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: dir).appendingPathComponent("hals.png"))
                print("skrev hals.png")
            }
        }
    }
}

// small point helpers (shared with Makeup.swift)
func dot(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x * b.x + a.y * b.y }
func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
func norm(_ a: CGPoint) -> CGPoint { let l = max(0.0001, hypot(a.x, a.y)); return CGPoint(x: a.x / l, y: a.y / l) }
func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
/// Smooth curve through points (midpoint quadratic curves); the path must already be at `pts[0]`.
private func smoothCurve(_ path: CGMutablePath, through pts: [CGPoint]) {
    guard pts.count > 1 else { return }
    for i in 1..<pts.count {
        let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
        path.addQuadCurve(to: mid, control: pts[i - 1])
    }
    path.addLine(to: pts[pts.count - 1])
}
