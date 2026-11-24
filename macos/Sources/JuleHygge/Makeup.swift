import AppKit
import CoreImage

/// The Day of the Dead's make-up in the JuleHygge Kamera picture: a calavera (sugar skull) painted on the face, in
/// the beard's place.
///
/// Everything is placed and sized from Vision's face landmarks in every frame (steadied like the beard's), so it
/// follows the face as it moves, turns and comes nearer; nothing is fitted to one face:
/// - **The base:** the face is painted white, keeping its own light and shade (the paint is the picture's own
///   brightness lifted toward white). Where: inside the jaw line and an arch over the forehead up from the temples,
///   and only on what the parts model calls face skin, so hair, a fringe, a beard and the neck stay as they are.
///   (Without the model, on macOS 14 or while it loads, the outline alone decides.)
/// - **Eye sockets:** black, scalloped like a flower, from under the eye up to the eyebrow, with a ring of coloured
///   petals round them. The eye's own opening is left free, so the person's eyes look out of the skull.
/// - **Nose:** a black upside-down heart over the tip of the nose.
/// - **Mouth:** the lips darkened and a line of stitches across them, from beyond one corner to beyond the other.
/// - **Decoration:** a small flower on the forehead with dots over the eyebrows, a heart on each cheek, dots on
///   the chin.
extension NisseCostume {
    /// The camera picture with the make-up painted on every face that has eyes and eyebrows.
    func applyMakeup(to cam: CIImage) -> CIImage {
        let ready = shapes.filter { $0.leftEye.count >= 3 && $0.rightEye.count >= 3 && $0.leftBrow.count >= 2 && $0.rightBrow.count >= 2 }
        guard !ready.isEmpty else { return cam }
        let extent = cam.extent
        var bounds = CGRect.null
        for s in ready {
            let r = max(s.fw, s.fh)
            bounds = bounds.union(CGRect(x: s.centre.x - r * 1.2, y: s.centre.y - r * 1.2, width: r * 2.4, height: r * 2.6))
        }
        bounds = bounds.intersection(extent).integral
        guard bounds.width > 8, bounds.height > 8, bounds.width < 4000, bounds.height < 4000 else { return cam }
        func context() -> CGContext? {
            guard let g = CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            g.translateBy(x: -bounds.minX, y: -bounds.minY)
            return g
        }
        guard let upper = context(), let lower = context(), let paint = context() else { return cam }
        for s in ready {
            Self.drawBase(s, into: upper, above: true)
            Self.drawBase(s, into: lower, above: false)
            Self.drawPaint(s, into: paint)
        }
        guard let upperImage = upper.makeImage(), let lowerImage = lower.makeImage(), let paintImage = paint.makeImage() else { return cam }
        let shift = CGAffineTransform(translationX: bounds.minX, y: bounds.minY)
        // the base's edge is soft (paint fades out at the hairline and the jaw), by a share of the face's size
        let soft = max(1.5, (ready.map(\.fw).max() ?? 100) * 0.025)
        func area(_ img: CGImage) -> CIImage { CIImage(cgImage: img).transformed(by: shift).applyingGaussianBlur(sigma: soft).cropped(to: extent) }
        // Above the eyes the skin model keeps the paint off the hair. Below them the jaw line alone decides: the
        // model calls stubble (and a beard) hair, and the white then stopped under the nose (replay 2026-11-24).
        var top = area(upperImage)
        if let skin = parts.faceSkin(cam: cam) {
            top = top.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: skin])
        }
        var area = top.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: area(lowerImage)]).cropped(to: extent)
        // a little of the skin shows through the paint
        area = area.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.92, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.92, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0.92, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
        // the paint: the picture's own brightness (so the face keeps its shape), lifted toward an ivory white
        let white = cam.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 0.7, kCIInputBrightnessKey: 0.4])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.98, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.93, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
            .applyingFilter("CIColorClamp")
        let painted = white.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: cam, kCIInputMaskImageKey: area])
        return CIImage(cgImage: paintImage).transformed(by: shift).composited(over: painted).cropped(to: extent)
    }

    // ------------------------------------------------------------------ the face's own measures

    private struct Look {
        var up: CGPoint, right: CGPoint
        var eyes: [(c: CGPoint, half: CGFloat, pts: [CGPoint], brow: CGPoint, out: CGFloat)]
        var eyeMid: CGPoint, browMid: CGPoint
        /// how far the eyebrows are above the eyes
        var browGap: CGFloat
        var fw: CGFloat
    }

    private static func mean(_ p: [CGPoint]) -> CGPoint {
        var x: CGFloat = 0, y: CGFloat = 0
        for q in p { x += q.x; y += q.y }
        let n = CGFloat(max(1, p.count))
        return CGPoint(x: x / n, y: y / n)
    }

    private static func look(_ s: Shape) -> Look {
        let up = s.up, right = s.right
        let brows = [mean(s.leftBrow), mean(s.rightBrow)]
        let eyePts = [s.leftEye, s.rightEye]
        let eyeMid = mean(eyePts.map(mean))
        var eyes: [(c: CGPoint, half: CGFloat, pts: [CGPoint], brow: CGPoint, out: CGFloat)] = []
        for pts in eyePts {
            let c = mean(pts)
            let xs = pts.map { dot($0 - c, right) }
            let half = max(2, ((xs.max() ?? 0) - (xs.min() ?? 0)) / 2)
            // each eye's own eyebrow is the nearer one
            let brow = brows.min { dist($0, c) < dist($1, c) } ?? c + up * half
            eyes.append((c, half, pts, brow, dot(c - eyeMid, right) < 0 ? -1 : 1))
        }
        let browMid = mean(brows)
        return Look(up: up, right: right, eyes: eyes, eyeMid: eyeMid, browMid: browMid,
                    browGap: max(2, dot(browMid - eyeMid, up)), fw: s.fw)
    }

    // ------------------------------------------------------------------ the white base

    /// Where the white goes: the jaw line from temple round the chin to temple, closed by an arch over the forehead.
    /// `above`: only the part above the eye line, or only the part below it.
    private static func drawBase(_ s: Shape, into g: CGContext, above: Bool) {
        guard let first = s.contour.first, let last = s.contour.last else { return }
        let l = look(s)
        // the forehead's top: well up toward the hairline (the skin mask stops it where the hair begins)
        let top = l.browMid + l.up * max(l.browGap * 3, s.fh * 0.35)
        let mid = (first + last) * 0.5
        let half = first - mid
        let rise = max(4, dot(top - mid, l.up))
        let path = CGMutablePath()
        path.addLines(between: s.contour)
        let n = 16
        for i in 0...n {
            let th = CGFloat.pi * CGFloat(n - i) / CGFloat(n)      // from the last point over the top to the first
            path.addLine(to: mid + half * cos(th) + l.up * (rise * sin(th)))
        }
        path.closeSubpath()
        // the half-plane above (or below) the eye line, turned with the head
        let far = s.fh * 4
        let side = l.eyeMid + l.up * (above ? far : -far)
        g.saveGState()
        g.addLines(between: [l.eyeMid - l.right * far, l.eyeMid + l.right * far, side + l.right * far, side - l.right * far])
        g.closePath(); g.clip()
        g.setFillColor(CGColor(gray: 1, alpha: 1))
        g.addPath(path); g.fillPath()
        g.restoreGState()
    }

    // ------------------------------------------------------------------ the black and the colours

    private static let ink = CGColor(srgbRed: 0.06, green: 0.04, blue: 0.06, alpha: 0.93)

    private static func drawPaint(_ s: Shape, into g: CGContext) {
        let l = look(s)
        let up = l.up, right = l.right
        let colours = Theme.picadoColours, marigold = Theme.marigoldColours
        func ellipse(_ c: CGPoint, _ along: CGPoint, _ a: CGFloat, _ b: CGFloat, _ col: CGColor) {
            let across = CGPoint(x: -along.y, y: along.x)
            let path = CGMutablePath()
            for i in 0..<20 {
                let th = CGFloat(i) / 20 * 2 * .pi
                let p = c + along * (a * cos(th)) + across * (b * sin(th))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            g.setFillColor(col); g.addPath(path); g.fillPath()
        }
        func spot(_ c: CGPoint, _ r: CGFloat, _ col: CGColor) { ellipse(c, right, r, r, col) }
        /// a heart; `point` is the way its tip points
        func heart(_ c: CGPoint, _ size: CGFloat, point: CGPoint, _ col: CGColor) {
            let side = CGPoint(x: -point.y, y: point.x)
            let lobe = size * 0.5
            spot(c - point * (lobe * 0.55) + side * (lobe * 0.9), lobe, col)
            spot(c - point * (lobe * 0.55) - side * (lobe * 0.9), lobe, col)
            g.setFillColor(col)
            g.addLines(between: [c - point * (lobe * 0.35) + side * (lobe * 1.85), c + point * (size * 1.25), c - point * (lobe * 0.35) - side * (lobe * 1.85)])
            g.closePath(); g.fillPath()
        }

        // ---- eye sockets: a ring of petals, then the black scalloped socket over their inner halves
        var sockets: [(c: CGPoint, rx: CGFloat, upR: CGFloat, downR: CGFloat)] = []
        for e in l.eyes {
            let c = e.c + up * (e.half * 0.1)
            // big and round, like a skull's: out past the eye's corners, from the eyebrow to the cheekbone
            let rx = e.half * 1.8
            let upR = max(e.half * 1.2, Swift.min(e.half * 2.0, dot(e.brow - e.c, up) * 1.1))
            let downR = e.half * 1.5
            sockets.append((c, rx, upR, downR))
        }
        func socketPoint(_ k: Int, _ th: CGFloat, grow: CGFloat = 1) -> CGPoint {
            let sk = sockets[k]
            // seven lobes round the edge, like a flower
            let lobe = 1 + 0.07 * cos(7 * th)
            let ry = sin(th) > 0 ? sk.upR : sk.downR
            return sk.c + right * (sk.rx * cos(th) * lobe * grow) + up * (ry * sin(th) * lobe * grow)
        }
        for k in sockets.indices {
            let petals = 9
            for i in 0..<petals {
                let th = (CGFloat(i) + 0.5) / CGFloat(petals) * 2 * .pi
                let edge = socketPoint(k, th)
                var out = edge - sockets[k].c
                let len = max(1, hypot(out.x, out.y)); out = out * (1 / len)
                let size = l.eyes[k].half * 0.42
                ellipse(edge + out * (size * 0.9), out, size * 1.15, size * 0.6, colours[(i + k * 3) % colours.count])
            }
        }
        g.setFillColor(ink)
        for k in sockets.indices {
            let path = CGMutablePath()
            for i in 0..<48 {
                let p = socketPoint(k, CGFloat(i) / 48 * 2 * .pi)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            g.addPath(path); g.fillPath()
        }
        // the eyes themselves look out of the sockets: their opening (a little larger) is cleared
        g.setBlendMode(.clear)
        for e in l.eyes {
            g.addLines(between: e.pts.map { e.c + ($0 - e.c) * 1.15 }); g.closePath(); g.fillPath()
        }
        g.setBlendMode(.normal)

        // ---- the nose: a black heart with its tip up the bridge, its lobes over the nostrils
        if s.nose.count >= 3 {
            let xs = s.nose.map { dot($0 - s.under, right) }
            let nw = max(2, ((xs.max() ?? 0) - (xs.min() ?? 0)) / 2)
            heart(s.under + up * (nw * 0.55), nw * 0.95, point: up, ink)
        }

        // ---- the mouth: darkened lips and a line of stitches across them
        if s.lips.count >= 4 {
            let mc = mean(s.lips)
            let xs = s.lips.map { dot($0 - mc, right) }, ys = s.lips.map { dot($0 - mc, up) }
            let half = ((xs.max() ?? 0) - (xs.min() ?? 0)) / 2, lipH = max(2, ((ys.max() ?? 0) - (ys.min() ?? 0)) / 2)
            g.setFillColor(ink.copy(alpha: 0.7)!)
            g.addLines(between: s.lips); g.closePath(); g.fillPath()
            let reach = half + l.fw * 0.1
            let width = max(1.2, l.fw * 0.011)
            g.setStrokeColor(ink); g.setLineWidth(width); g.setLineCap(.round)
            g.move(to: mc - right * reach); g.addLine(to: mc + right * reach); g.strokePath()
            let n = 11
            for i in 0..<n {
                let u = CGFloat(i) / CGFloat(n - 1) * 2 - 1
                let p = mc + right * (u * reach * 0.95)
                let h = (lipH * 1.25 + l.fw * 0.015) * (1 - 0.55 * u * u)
                g.move(to: p - up * h); g.addLine(to: p + up * h); g.strokePath()
            }
            // dots on the chin, between the lips and the chin
            let low = mc + up * (ys.min() ?? 0)
            let chinMid = low + (s.chin - low) * 0.55
            let r = l.fw * 0.014
            for (i, off) in [right * (l.fw * 0.035), right * (-l.fw * 0.035), up * (-l.fw * 0.03)].enumerated() {
                spot(chinMid + off, r, marigold[i % marigold.count])
            }
        }

        // ---- the forehead: a small flower over the nose, and a row of dots over each eyebrow
        let fc = l.browMid + up * max(l.browGap * 1.3, l.fw * 0.08)
        let fr = l.fw * 0.05
        for i in 0..<8 {
            let th = CGFloat(i) / 8 * 2 * .pi
            let out = right * cos(th) + up * sin(th)
            ellipse(fc + out * (fr * 0.75), out, fr * 0.55, fr * 0.3, colours[3])
        }
        spot(fc, fr * 0.35, marigold[1])
        for e in l.eyes {
            for i in 0..<4 {
                let u = CGFloat(i) / 3
                let p = e.brow + up * (l.browGap * (0.45 + 0.15 * sin(u * .pi))) + right * (e.out * e.half * (u * 1.6 - 0.4))
                spot(p, l.fw * 0.01, colours[2])
            }
        }

        // ---- the cheeks: a heart below each socket, out toward the ear
        for (k, e) in l.eyes.enumerated() {
            let c = sockets[k].c - up * (sockets[k].downR * 1.55) + right * (e.out * e.half * 0.7)
            heart(c, l.fw * 0.03, point: up * -1, colours[0])
        }
    }
}
