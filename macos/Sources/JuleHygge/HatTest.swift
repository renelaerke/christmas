import AppKit
import CoreImage
import Vision
import simd

/// Test aid for the camera's nisse hat (--nissehue-test=DIR[,IMAGE]). No camera is used.
///
/// Without an image it simulates people in front of a camera and runs the same tracking and drawing as the live
/// camera. The simulated people are deliberately NOT built the way the hat code thinks about heads: each is a set
/// of 3D bodies (skull, jaw, ears, hair of different kinds, neck, shoulders) seen by a real perspective camera,
/// with different head shapes, hair, distances, lenses and camera heights (level, from below, from above, a person
/// who habitually sits turned away). "Vision" is the true angles and face points with noise, misreadings and the
/// known too-symmetric guess for the far eye. The checks only use the truth: is the head above the brim covered,
/// does the hat fall into the eyes, does it keep its size and height while the head turns, does it shake.
extension NisseHat {
    struct SimPart { var c: V, r: V, head: Bool, top: Bool }
    struct SimPerson { var name: String, parts: [SimPart], eyes: [V], brows: [V], chin: V, crown: Double }
    /// `below`: how far below eye height the camera sits, as the angle it looks up (radians; negative = from above).
    /// `aside`: how far to the side of the lens axis the person sits (cm). `turned`: the person's habitual turn.
    struct SimCamera { var name: String, distance: Double, below: Double, fov: Double, aside: Double, turned: Double }

    static let simPivot = V(0, -10, -3)
    static let simW = 1280.0, simH = 720.0, maskW = 512, maskH = 384

    static func person(_ name: String, scale s: V = V(1, 1, 1), hair: [SimPart]) -> SimPerson {
        var parts = [SimPart(c: V(0, 2, -1) * s, r: V(7.6, 9.0, 9.6) * s, head: true, top: true),
                     SimPart(c: V(0, -5, 2.5) * s, r: V(6.3, 7.5, 6.5) * s, head: true, top: false),
                     SimPart(c: V(7.8, -1, -0.5) * s, r: V(1.2, 3, 2) * s, head: true, top: true),
                     SimPart(c: V(-7.8, -1, -0.5) * s, r: V(1.2, 3, 2) * s, head: true, top: true)]
        parts += hair.map { SimPart(c: $0.c * s, r: $0.r * s, head: true, top: true) }
        parts += [SimPart(c: V(0, -15, -2.5), r: V(5.2, 7.5, 5.5), head: false, top: false),
                  SimPart(c: V(0, -38, -3), r: V(23, 20, 12), head: false, top: false)]
        let crown = parts.filter { $0.top }.map { $0.c.y + $0.r.y }.max() ?? 11
        return SimPerson(name: name, parts: parts, eyes: [V(-3.2, 0, 7.3) * s, V(3.2, 0, 7.3) * s],
                         brows: [V(-3.3, 2.1, 7.8) * s, V(3.3, 2.1, 7.8) * s], chin: V(0, -12, 4.2) * s, crown: crown)
    }

    struct SimFrame {
        var face: Face
        var label: [UInt8]            // per mask pixel: 0 nothing, 1 skull/hair/ears, 2 the rest of the person
        var eyes: [CGPoint], brow: CGPoint, up: CGPoint, headPx: Double, centre: CGPoint
        var shape: NisseCostume.Shape      // what "Vision" gives the beard: jaw line, nose, lips
    }

    /// One frame of a simulated person: fills `mask` and returns what "Vision" reports and the truth.
    static func simulate(_ p: SimPerson, _ cam: SimCamera, yaw: Double, pitch: Double, roll: Double, frame: Int,
                         rng: inout SeededRandom, mask: CVPixelBuffer) -> SimFrame {
        let f = simW / 2 / tan(cam.fov / 2 * .pi / 180)
        let Rv = rotation(roll: 0, yaw: 0, pitch: -cam.below)
        let Rh = rotation(roll: roll, yaw: yaw + cam.turned, pitch: pitch)
        let t = V(cam.aside, 0, -cam.distance)
        func toCam(_ q: V, head: Bool) -> V { Rv * (head ? Rh * (q - simPivot) + simPivot : q) + t }
        func project(_ c: V) -> CGPoint { CGPoint(x: simW / 2 + f * c.x / -c.z, y: simH / 2 + f * c.y / -c.z) }
        // the mask: every body drawn into a depth buffer
        var depth = [Double](repeating: .infinity, count: maskW * maskH)
        var label = [UInt8](repeating: 0, count: maskW * maskH)
        let RvT = Rv.transpose, RhT = Rh.transpose
        for part in p.parts {
            let cc = toCam(part.c, head: part.head)
            let rmax = max(part.r.x, part.r.y, part.r.z)
            guard -cc.z > rmax + 1 else { continue }
            let pc = project(cc), rad = f * rmax / (-cc.z - rmax) * 1.15
            let x0 = max(0, Int((Double(pc.x) - rad) / simW * Double(maskW))), x1 = min(maskW - 1, Int((Double(pc.x) + rad) / simW * Double(maskW)) + 1)
            let y0 = max(0, Int((1 - (Double(pc.y) + rad) / simH) * Double(maskH))), y1 = min(maskH - 1, Int((1 - (Double(pc.y) - rad) / simH) * Double(maskH)) + 1)
            guard x0 <= x1, y0 <= y1 else { continue }
            let origin: V = part.head ? RhT * (RvT * (-t) - simPivot) + simPivot : RvT * (-t)
            let o = (origin - part.c) / part.r
            for my in y0...y1 { for mx in x0...x1 {
                let x = (Double(mx) + 0.5) / Double(maskW) * simW, y = (1 - (Double(my) + 0.5) / Double(maskH)) * simH
                let dc = V((x - simW / 2) / f, (y - simH / 2) / f, -1)
                let dir = (part.head ? RhT * (RvT * dc) : RvT * dc) / part.r
                let A = simd_dot(dir, dir), B = simd_dot(o, dir), C = simd_dot(o, o) - 1
                let disc = B * B - A * C
                if disc < 0 { continue }
                let hit = (-B - disc.squareRoot()) / A
                if hit > 0, hit < depth[my * maskW + mx] { depth[my * maskW + mx] = hit; label[my * maskW + mx] = part.top ? 1 : 2 }
            } }
        }
        // soft edges and a little noise, as a real mask has
        CVPixelBufferLockBaseAddress(mask, [])
        let base = CVPixelBufferGetBaseAddress(mask)!.assumingMemoryBound(to: UInt8.self), stride = CVPixelBufferGetBytesPerRow(mask)
        for my in 0..<maskH { for mx in 0..<maskW {
            var sum = 0, n = 0
            for dy in -1...1 { for dx in -1...1 {
                let xx = mx + dx, yy = my + dy
                if xx < 0 || yy < 0 || xx >= maskW || yy >= maskH { continue }
                n += 1; if label[yy * maskW + xx] != 0 { sum += 1 }
            } }
            let v = 255 * Double(sum) / Double(n) + (sum > 0 && sum < n ? (Double(rng.next()) - 0.5) * 50 : 0)
            base[my * stride + mx] = UInt8(max(0, min(255, v)))
        } }
        CVPixelBufferUnlockBaseAddress(mask, [])
        // "Vision": the head's rotation as the camera sees it, and the face points
        let R = Rv * Rh
        // (Vision's order: R = Rz(roll)·Rx(pitch)·Ry(yaw))
        var vy = atan2(-R[0][2], R[2][2]), vp = asin(max(-1, min(1, R[1][2])))
        let vr = atan2(-R[1][0], R[1][1]) + (Double(rng.next()) - 0.5) * 0.06
        vy += (Double(rng.next()) - 0.5) * 0.08; vp += (Double(rng.next()) - 0.5) * 0.08
        if frame % 41 == 40 { vy = -vy + 0.3 }      // a misreading: the wrong way altogether
        if frame % 53 == 52 { vp += 0.6 }
        var e = p.eyes.map { project(toCam($0, head: true)) }
        let trueEyes = e
        // turned far, the far eye is only guessed: too close to the near one
        let seenYaw = atan2(-R[0][2], R[2][2])
        if abs(seenYaw) > 0.9 { let far = seenYaw > 0 ? 1 : 0; e[far].x += (e[1 - far].x - e[far].x) * 0.3 }
        func noisy(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x + CGFloat(rng.next() * 3 - 1.5), y: q.y + CGFloat(rng.next() * 3 - 1.5)) }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        let b = p.brows.map { project(toCam($0, head: true)) }
        let brow = mid(b[0], b[1])
        let face = Face(eye: noisy(mid(e[0], e[1])), brow: noisy(brow), chin: noisy(project(toCam(p.chin, head: true))), roll: vr, yaw: vy, pitch: vp)
        let above = project(toCam((p.brows[0] + p.brows[1]) / 2 + V(0, 5, 0), head: true))
        let ul = max(1e-6, hypot(above.x - brow.x, above.y - brow.y))
        let cc = toCam(V(0, 0, 0), head: true)
        // the beard's points. The jaw line runs from ear to ear round the chin; turned, its far side is only a guess
        // by Vision: here the near side mirrored about the chin and drawn in, as seen live.
        let sc = p.chin.y / -12
        var jaw = (0...16).map { i -> CGPoint in
            let th = (Double(i) / 16 * 2 - 1) * .pi / 2, c = pow(max(0, cos(th)), 1.2)
            return project(toCam(V(6.5 * sin(th), -12 * c - 1 * (1 - c), 5 * cos(th)) * sc, head: true))
        }
        if abs(seenYaw) > 0.25 {
            let mid = jaw[8].x
            for i in 0..<8 {
                let (far, near) = seenYaw > 0 ? (16 - i, i) : (i, 16 - i)
                jaw[far] = CGPoint(x: mid + (mid - jaw[near].x) * 0.85, y: jaw[near].y)
            }
        }
        let nosePts = [V(-1.7, -4.4, 7.6), V(1.7, -4.4, 7.6), V(0, -4.8, 8.4), V(0, -3, 10), V(-1.2, -2, 8), V(1.2, -2, 8)].map { noisy(project(toCam($0 * sc, head: true))) }
        let lipPts = (0..<8).map { i -> CGPoint in
            let a = Double(i) / 8 * 2 * .pi, x = 2.4 * cos(a)
            return noisy(project(toCam(V(x, -7.2 + 0.7 * sin(a), 8 - 0.8 * (x / 2.4) * (x / 2.4)) * sc, head: true)))
        }
        let faceMid = project(toCam(V(0, -5, 7) * sc, head: true)), facePx = CGFloat(f / -cc.z * 14 * sc)
        var shape = NisseCostume.Shape(contour: jaw.map(noisy), nose: nosePts, lips: lipPts, centre: faceMid, fw: facePx, fh: facePx, roll: CGFloat(vr))
        shape.yaw = CGFloat(vy); shape.pitch = CGFloat(vp)
        return SimFrame(face: face, label: label, eyes: trueEyes, brow: brow, up: CGPoint(x: (above.x - brow.x) / ul, y: (above.y - brow.y) / ul),
                        headPx: f / -cc.z * (p.crown - p.chin.y), centre: project(cc), shape: shape)
    }

    /// The head's movement through the test: still, turn to one profile and the other, nod down and up, tilt.
    static func simPose(_ i: Int) -> (yaw: Double, pitch: Double, roll: Double) {
        let keys: [(Int, Double, Double, Double)] = [(0, 0, 0, 0), (29, 0, 0, 0), (59, 1.3, 0, 0), (69, 1.3, 0, 0), (99, -1.3, 0, 0), (104, -1.3, 0, 0),
                                                     (119, 0, 0, 0), (134, 0, 0.42, 0), (149, 0, -0.42, 0), (157, 0, 0, 0), (164, 0, 0, 0.35)]
        guard let hi = keys.firstIndex(where: { $0.0 >= i }), hi > 0 else { return (keys[0].1, keys[0].2, keys[0].3) }
        let a = keys[hi - 1], b = keys[hi]
        let u = Double(i - a.0) / Double(b.0 - a.0), s = u * u * (3 - 2 * u)
        return (a.1 + (b.1 - a.1) * s, a.2 + (b.2 - a.2) * s, a.3 + (b.3 - a.3) * s)
    }
    static let simFrames = 165, simShots = [29, 47, 66, 101, 133, 148, 164]

    static func test(dir: String, image: String?) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func write(_ img: CIImage, _ name: String) {
            guard let cg = GPU.ciContext.createCGImage(img, from: img.extent) else { return }
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
            print("skrev", name)
        }
        if let image, let src = CIImage(contentsOf: URL(fileURLWithPath: image)) {
            let hat = NisseHat()
            let handler = VNImageRequestHandler(ciImage: src, options: [:])
            try? handler.perform([hat.request])
            let lm = VNDetectFaceLandmarksRequest(); lm.inputFaceObservations = hat.request.results ?? []
            try? handler.perform([lm])
            let faces = lm.results ?? []
            let seg = VNGeneratePersonSegmentationRequest(); seg.qualityLevel = .balanced; seg.outputPixelFormat = kCVPixelFormatType_OneComponent8
            try? handler.perform([seg])
            guard let buf = seg.results?.first?.pixelBuffer else { print("ingen maske"); return }
            for _ in 0..<3 { hat.update(faces, mask: buf, extent: src.extent, transform: .identity, dt: 1) }
            let maskRaw = CIImage(cvPixelBuffer: buf)
            let mask = maskRaw.transformed(by: CGAffineTransform(scaleX: src.extent.width / maskRaw.extent.width, y: src.extent.height / maskRaw.extent.height))
            if let t = hat.tracks.first {
                print(String(format: "drej %.2f (omrids %.2f) nik %.2f hæld %.2f, halv hovedbredde %.0f px", t.yaw, t.yawFromOutline, t.pitch, t.roll, t.U))
            } else { print("intet ansigt med landmarks, eller intet hovedomrids") }
            write(hat.apply(to: src, person: mask).cropped(to: src.extent), "med-hue.png")
            return
        }

        let short = [SimPart(c: V(0, 3, -1.5), r: V(8.1, 9.3, 10.2), head: true, top: true)]
        let people = [
            person("almindeligt hoved, kort hår", hair: short),
            person("smalt og langt hoved, skaldet", scale: V(0.88, 1.03, 1.1), hair: []),
            person("bredt hoved, stort hår", scale: V(1.08, 0.97, 0.98), hair: [SimPart(c: V(0, 4.5, -2), r: V(12.5, 11.5, 12.5), head: true, top: true)]),
            person("knold på baghovedet", hair: short + [SimPart(c: V(0, 8.5, -9.5), r: V(4.2, 4.2, 4.2), head: true, top: true)]),
            person("langt hår", hair: short + [SimPart(c: V(0, -7, -4.5), r: V(9.6, 14, 7), head: true, top: true)]),
            person("barn", scale: V(0.9, 0.84, 0.9), hair: short),
            person("hestehale i siden", hair: short + [SimPart(c: V(8.5, 3, -6), r: V(3.5, 6, 3.5), head: true, top: true)]),
        ]
        let level = SimCamera(name: "lige på, 70 cm", distance: 70, below: 0, fov: 68, aside: 0, turned: 0)
        let laptop = SimCamera(name: "nedefra 30°, 50 cm, vidvinkel", distance: 50, below: 0.52, fov: 78, aside: 0, turned: 0)
        let high = SimCamera(name: "oppefra 18°, 110 cm, til siden", distance: 110, below: -0.31, fov: 60, aside: 18, turned: 0)
        let habit = SimCamera(name: "nedefra 12°, sidder drejet 30°", distance: 80, below: 0.21, fov: 68, aside: -15, turned: -0.52)
        var cases: [(SimPerson, SimCamera)] = people.map { ($0, level) }
        cases += [(people[0], laptop), (people[2], laptop), (people[4], laptop), (people[0], high), (people[1], high), (people[0], habit), (people[3], habit)]
        if let only = ProcessInfo.processInfo.environment["HUE_CASE"].flatMap({ Int($0) }), cases.indices.contains(only) { cases = [cases[only]] }

        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, maskW, maskH, kCVPixelFormatType_OneComponent8, nil, &pb)
        guard let mask = pb else { return }
        let W = Int(simW), H = Int(simH), full = CGRect(x: 0, y: 0, width: simW, height: simH)
        let dt = 1.0 / 15
        print("udækket: del af hovedet over kanten, som huen ikke dækker (værste billede) · øjne: billeder hvor huen dækker et øje")
        print("størrelse: huens målestok mod hovedets sande højde (skal holde sig ens) · kanthøjde: kantens forside over brynene i hovedhøjder · rysten: stille hoved")
        for (ci, (p, cam)) in cases.enumerated() {
            let hat = NisseHat(), costume = NisseCostume()
            var rng = SeededRandom(seed: UInt64(11 + ci))
            var worstOpen = 0.0, eyeFrames = 0, sizes: [Double] = [], brims: [Double] = [], tipX: [Double] = [], tipY: [Double] = [], lost = 0
            var sheet = CIImage(color: CIColor(red: 0.1, green: 0.14, blue: 0.22)).cropped(to: CGRect(x: 0, y: 0, width: 420 * simShots.count, height: 520))
            for i in 0..<simFrames {
                let pose = simPose(i)
                let fr = simulate(p, cam, yaw: pose.yaw, pitch: pose.pitch, roll: pose.roll, frame: i, rng: &rng, mask: mask)
                CVPixelBufferLockBaseAddress(mask, .readOnly)
                let reader = MaskReader(base: UnsafePointer(CVPixelBufferGetBaseAddress(mask)!.assumingMemoryBound(to: UInt8.self)), w: maskW, h: maskH,
                                        rowBytes: CVPixelBufferGetBytesPerRow(mask), extent: full, inverse: .identity)
                hat.feed([fr.face], mask: reader, dt: dt)
                CVPixelBufferUnlockBaseAddress(mask, .readOnly)
                costume.heads = hat.headsForCostume
                costume.ingest([fr.shape], dt: CGFloat(dt))
                guard let front = hat.frontForTest(), front.track.fresh else { if i > 2 { lost += 1 }; continue }
                if ProcessInfo.processInfo.environment["HUE_TRACE"] != nil, i % 4 == 0 {
                    let tr = front.track
                    print(String(format: "  %3d sand drej %5.2f nik %5.2f | set drej %5.2f nik %5.2f hæld %5.2f | målestok %.3f dybde %.2f kant %.0f px", i, pose.yaw + cam.turned, pose.pitch, tr.yaw, tr.pitch, tr.roll, tr.U / fr.headPx, tr.depth, tr.ringHalf))
                }
                if i >= 10 {
                    sizes.append(front.track.U / fr.headPx)
                    brims.append((Double(front.brimFront.x - fr.brow.x) * Double(fr.up.x) + Double(front.brimFront.y - fr.brow.y) * Double(fr.up.y)) / fr.headPx)
                }
                if (15..<30).contains(i) { tipX.append(Double(front.tip.x)); tipY.append(Double(front.tip.y)) }
                if i >= 10, i % 3 == 0, let g = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    let r = front.image.extent.intersection(full)
                    if !r.isEmpty, let cg = GPU.ciContext.createCGImage(front.image, from: r) { g.draw(cg, in: r) }
                    let data = g.data!.assumingMemoryBound(to: UInt8.self)
                    func covered(_ x: Double, _ y: Double) -> Bool {
                        let ix = Int(x), iy = H - 1 - Int(y)
                        return ix >= 0 && iy >= 0 && ix < W && iy < H && data[(iy * W + ix) * 4 + 3] > 128
                    }
                    var need = 0, open = 0
                    for my in 0..<maskH { for mx in 0..<maskW where fr.label[my * maskW + mx] == 1 {
                        let x = (Double(mx) + 0.5) / Double(maskW) * simW, y = (1 - (Double(my) + 0.5) / Double(maskH)) * simH
                        let h = (x - Double(fr.brow.x)) * Double(fr.up.x) + (y - Double(fr.brow.y)) * Double(fr.up.y)
                        if h > 0.26 * fr.headPx { need += 1; if !covered(x, y) { open += 1 } }
                    } }
                    if need > 0 { worstOpen = max(worstOpen, Double(open) / Double(need)) }
                    if fr.eyes.contains(where: { covered(Double($0.x), Double($0.y)) }) { eyeFrames += 1 }
                }
                if let si = simShots.firstIndex(of: i) {
                    // the person as the mask shows them (skull/hair lighter than face and body), with the hat on
                    var px = [UInt8](repeating: 255, count: maskW * maskH * 4)
                    for k in 0..<(maskW * maskH) {
                        let c: (UInt8, UInt8, UInt8) = fr.label[k] == 1 ? (176, 150, 128) : fr.label[k] == 2 ? (222, 190, 168) : (26, 36, 56)
                        px[k * 4] = c.0; px[k * 4 + 1] = c.1; px[k * 4 + 2] = c.2
                    }
                    let provider = CGDataProvider(data: Data(px) as CFData)!
                    let cg = CGImage(width: maskW, height: maskH, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: maskW * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
                    let scale = CGAffineTransform(scaleX: simW / Double(maskW), y: simH / Double(maskH))
                    var scene = CIImage(cgImage: cg).transformed(by: scale)
                    for e in fr.eyes { scene = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1)).cropped(to: CGRect(x: e.x - 3, y: e.y - 3, width: 6, height: 6)).composited(over: scene) }
                    if ProcessInfo.processInfo.environment["HUE_NOBEARD"] == nil, let beard = costume.beardImage(extent: full) { scene = beard.composited(over: scene) }
                    scene = hat.apply(to: scene, person: CIImage(cvPixelBuffer: mask).transformed(by: scale))
                    // a window around the head, sized by the head
                    let side = fr.headPx * 2.7
                    let win = CGRect(x: Double(fr.centre.x) - side / 2, y: Double(fr.centre.y) - side * 0.42, width: side, height: side * 1.238)
                    guard let shot = GPU.ciContext.createCGImage(scene.cropped(to: win).composited(over: CIImage(color: CIColor(red: 0.1, green: 0.14, blue: 0.22)).cropped(to: win)), from: win) else { continue }
                    let k = 420 / side
                    sheet = CIImage(cgImage: shot).transformed(by: CGAffineTransform(scaleX: k, y: k).concatenating(CGAffineTransform(translationX: Double(420 * si), y: 0))).composited(over: sheet)
                }
            }
            func sd(_ a: [Double]) -> Double { guard !a.isEmpty else { return 0 }; let m = a.reduce(0, +) / Double(a.count); return (a.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(a.count)).squareRoot() }
            let t = hat.tracks.first
            print(String(format: "%2d %@ · %@", ci, p.name, cam.name))
            print(String(format: "     udækket %4.1f %% · øjne %d · størrelse %.2f–%.2f · kanthøjde %.2f–%.2f · rysten %.1f/%.1f px · dybde/bredde %.2f · tabt %d",
                         worstOpen * 100, eyeFrames, sizes.min() ?? 0, sizes.max() ?? 0, brims.min() ?? 0, brims.max() ?? 0, sd(tipX), sd(tipY), t?.depth ?? 0, lost))
            write(sheet, String(format: "hue-%02d.png", ci))
        }
    }

    /// Runs the camera's hat, beard and suit again on camera pictures saved by --kamera-debug (raa-NNN.jpg in `dir`),
    /// one after the other with the same hat and costume, and writes ud-NNN.png (the costume on the person, with the
    /// beard's measuring points marked) and the measurements. For trying a change on real pictures without the camera.
    static func replay(dir: String) {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasPrefix("raa-") && $0.hasSuffix(".jpg") }.sorted()
        guard !names.isEmpty else { print("ingen raa-NNN.jpg i", dir); return }
        PersonParts.loadNow = true
        let hat = NisseHat(), costume = NisseCostume()
        let colours = [CIColor(red: 1, green: 0, blue: 0), CIColor(red: 0, green: 1, blue: 0), CIColor(red: 1, green: 1, blue: 0), CIColor(red: 1, green: 1, blue: 0),
                       CIColor(red: 0, green: 0.5, blue: 1), CIColor(red: 0, green: 0.5, blue: 1)]
        var partsMs: [Double] = []
        defer {
            // (the first picture also loads the model)
            let rest = partsMs.dropFirst()
            if rest.isEmpty { print("tøjmodel: ikke brugt (farvereglen i stedet)") }
            else { print(String(format: "tøjmodel: %.1f ms pr. billede i gennemsnit, højst %.1f (første billede med indlæsning %.0f ms)", rest.reduce(0, +) / Double(rest.count), rest.max() ?? 0, partsMs[0])) }
        }
        for name in names {
            guard let src = CIImage(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent(name)) else { continue }
            let handler = VNImageRequestHandler(ciImage: src, options: [:])
            let seg = VNGeneratePersonSegmentationRequest(); seg.qualityLevel = .balanced; seg.outputPixelFormat = kCVPixelFormatType_OneComponent8
            try? handler.perform([seg, hat.request])
            guard let buf = seg.results?.first?.pixelBuffer else { print(name, "ingen maske"); continue }
            let landmarks = costume.detect(handler, faces: hat.request.results ?? [])
            // the pictures are seconds apart: each is fed a few times, so the steadying settles on it
            for _ in 0..<5 {
                hat.update(landmarks, mask: buf, extent: src.extent, transform: .identity, dt: 0.2)
                costume.heads = hat.headsForCostume
                costume.update(landmarks, extent: src.extent, transform: .identity, dt: 0.2)
            }
            let maskRaw = CIImage(cvPixelBuffer: buf)
            let mask = maskRaw.transformed(by: CGAffineTransform(scaleX: src.extent.width / maskRaw.extent.width, y: src.extent.height / maskRaw.extent.height))
            // (HUE_MUERTOS=1 replays the Day of the Dead: make-up in the beard's place, no suit)
            let muertos = CameraCostume.muertos
            let tm = CFAbsoluteTimeGetCurrent()
            // (HUE_HALLOWEEN=1 replays the witch's hat: nothing in the beard's or the suit's place)
            var out = muertos ? costume.applyMakeup(to: src)
                : CameraCostume.halloween ? (CameraCostume.pumpkinHead ? src : costume.applyWitch(to: src, mask: mask))
                : CameraCostume.nytaar ? src   // (HUE_NYTAAR=1: the paper hat alone)
                : costume.applySuit(to: src, mask: mask, heads: hat.headOutlines)
            if muertos, let cg = GPU.ciContext.createCGImage(out, from: src.extent) {
                // (rendered here only to time it: what the camera pays for the make-up, model included)
                _ = cg
                print(name, String(format: "sminke %.1f ms", (CFAbsoluteTimeGetCurrent() - tm) * 1000))
            }
            if costume.parts.lastMs > 0, !costume.shapes.isEmpty { partsMs.append(costume.parts.lastMs) }
            // (autumn's costume has no beard; HUE_EFTERAAR=1 replays the sou'wester and the raincoat)
            if !CameraCostume.autumn, !muertos, CameraCostume.look.beard > 0, let beard = costume.beardImage(extent: src.extent) { out = beard.composited(over: out) }
            out = hat.apply(to: out, person: mask)
            for s in costume.shapes {
                for (i, p) in s.marks.enumerated() where p.x.isFinite && p.y.isFinite && !muertos {
                    out = CIImage(color: colours[min(i, colours.count - 1)]).cropped(to: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)).composited(over: out)
                }
                print(name, s.note)
            }
            if costume.shapes.isEmpty { print(name, "intet ansigt") }
            let half = out.cropped(to: src.extent).transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
            if let cg = GPU.ciContext.createCGImage(half, from: half.extent) {
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: dir).appendingPathComponent(name.replacingOccurrences(of: "raa-", with: "ud-").replacingOccurrences(of: ".jpg", with: ".png")))
            }
        }
    }
}
