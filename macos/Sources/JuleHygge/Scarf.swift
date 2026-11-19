import AppKit
import CoreImage

/// PUT AWAY FOR LATER (2026-11-19): REL tried the scarf on recorded pictures and it did not work for him. Nothing
/// calls `scarfImage` now, and autumn has nothing in the beard's place. (Rosy cheeks and nose were tried the
/// same day and dropped.) To try it
/// again, composite `scarfImage` over the cut-out picture, masked to the person, as the beard is in VirtualCamera.
///
/// Autumn's scarf in the camera picture: a knitted scarf wound round the neck, with one end hanging down the chest.
///
/// Where: the neck itself. The parts model (PersonParts) gives the bare neck under the chin, its middle, its
/// breadth and where the clothes begin; the scarf covers that and laps over the collar. With a high collar (no
/// neck showing) or without the model it sits right under the chin on the head's axis. The jaw and chin stay in
/// front of it: the model's face skin is cut out of it. All sizes are in units of the head's measured breadth.
extension NisseCostume {
    struct ScarfPlace { var x: CGFloat, half: CGFloat, top: CGFloat, bottom: CGFloat, U: CGFloat }

    /// The scarves for all faces as one image to lay over the picture, or nil when there is no face.
    func scarfImage(extent: CGRect) -> CIImage? {
        guard !shapes.isEmpty else { scarfSteady = []; return nil }
        var places: [ScarfPlace] = []
        for (i, s) in shapes.enumerated() {
            let under = s.under
            let chinNow = s.face.map { CGPoint(x: under.x + s.up.x * $0.chinY, y: under.y + s.up.y * $0.chinY) } ?? s.chin
            var U = s.fw * 0.5, axis = chinNow
            if let h = heads.min(by: { hypot($0.origin.x - s.centre.x, $0.origin.y - s.centre.y) < hypot($1.origin.x - s.centre.x, $1.origin.y - s.centre.y) }),
               hypot(h.origin.x - s.centre.x, h.origin.y - s.centre.y) < s.fh * 1.5, h.U > 8 {
                U = CGFloat(h.U)
                // the neck leaves the head on its axis, not under the chin (which is in front of it when turned)
                let d = (chinNow.x - h.origin.x) * s.up.x + (chinNow.y - h.origin.y) * s.up.y
                axis = CGPoint(x: h.origin.x + s.up.x * d, y: h.origin.y + s.up.y * d)
            }
            let neck = parts.neck(chin: axis, reach: U * 1.2)
            var p = ScarfPlace(x: neck?.x ?? axis.x, half: max(neck?.half ?? 0, 0.6 * U), top: axis.y,
                               bottom: min(axis.y - 0.15 * U, max(axis.y - 1.2 * U, neck?.bottom ?? axis.y - 0.3 * U)), U: U)
            // steadied: the model's cells are coarse, and the scarf must not hop from cell to cell
            if i < scarfSteady.count, abs(scarfSteady[i].x - p.x) < U {
                let o = scarfSteady[i], k: CGFloat = 0.35
                p.x = o.x + (p.x - o.x) * k; p.half = o.half + (p.half - o.half) * k
                p.top = o.top + (p.top - o.top) * 0.6; p.bottom = o.bottom + (p.bottom - o.bottom) * k
            }
            places.append(p)
        }
        scarfSteady = places
        var bounds = CGRect.null
        for p in places {
            let w = max(p.half * 1.45, 0.8 * p.U) + 0.5 * p.U
            bounds = bounds.union(CGRect(x: p.x - w, y: p.bottom - 1.6 * p.U, width: 2 * w, height: p.top - p.bottom + 2.0 * p.U))
        }
        bounds = bounds.intersection(extent).integral
        guard bounds.width > 8, bounds.height > 8,
              let g = CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        g.translateBy(x: -bounds.minX, y: -bounds.minY)
        let hasFace = parts.faceMask() != nil
        for p in places { drawScarf(p, into: g, underJaw: hasFace) }
        guard let cg = g.makeImage() else { return nil }
        var image = CIImage(cgImage: cg).transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
        // the jaw and chin are in front of the scarf
        if let face = parts.faceMask() {
            let notFace = face.applyingFilter("CIColorInvert").cropped(to: extent)
            image = image.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: notFace])
        }
        return image.cropped(to: extent)
    }

    private func drawScarf(_ p: ScarfPlace, into g: CGContext, underJaw: Bool) {
        let u = p.U, x = p.x
        let base = CGColor(srgbRed: 0.70, green: 0.20, blue: 0.15, alpha: 1), dark = CGColor(srgbRed: 0.42, green: 0.10, blue: 0.09, alpha: 1)
        let cream = CGColor(srgbRed: 0.96, green: 0.89, blue: 0.74, alpha: 1)
        let W = max(p.half * 1.45, 0.8 * u)
        // up behind the jaw when the face can be cut out of it, else no higher than the chin
        let yT = p.top + (underJaw ? 0.18 * u : -0.04 * u)
        let yB = min(p.bottom - 0.3 * u, yT - 0.75 * u)

        // ---- the hanging end (behind the wound part)
        let ax = x - W * 0.42, t0 = CGPoint(x: ax, y: yB + 0.35 * u), t1 = CGPoint(x: ax + 0.07 * u, y: yB - 1.0 * u)
        let tw: CGFloat = 0.27 * u
        func onTail(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            CGPoint(x: t0.x + (t1.x - t0.x) * along + across * tw * (1 + 0.12 * along), y: t0.y + (t1.y - t0.y) * along)
        }
        let tail = CGMutablePath()
        tail.addLines(between: [onTail(0, -1), onTail(0, 1), onTail(1, 1), onTail(1, -1)]); tail.closeSubpath()
        g.saveGState()
        g.addPath(tail); g.clip()
        g.setFillColor(base); g.fill(tail.boundingBox)
        g.setFillColor(cream)
        for (a, b) in [(0.70, 0.78), (0.84, 0.92)] as [(CGFloat, CGFloat)] {
            g.addLines(between: [onTail(a, -1.1), onTail(a, 1.1), onTail(b, 1.1), onTail(b, -1.1)]); g.closePath(); g.fillPath()
        }
        // the knitting's ribs, along the scarf
        g.setStrokeColor(dark.copy(alpha: 0.4)!); g.setLineWidth(max(1, 0.022 * u))
        for i in -3...3 { g.move(to: onTail(0, CGFloat(i) / 3.5)); g.addLine(to: onTail(1, CGFloat(i) / 3.5)) }
        g.strokePath()
        // darker toward the wound part, which shades it
        if let grad = CGGradient(colorsSpace: nil, colors: [CGColor(gray: 0, alpha: 0.35), CGColor(gray: 0, alpha: 0)] as CFArray, locations: [0, 1]) {
            g.drawLinearGradient(grad, start: t0, end: CGPoint(x: t0.x, y: t0.y - 0.55 * u), options: [])
        }
        g.restoreGState()
        // fringe
        g.setStrokeColor(base); g.setLineWidth(max(1, 0.035 * u)); g.setLineCap(.round)
        for i in -4...4 {
            let a = onTail(1, CGFloat(i) / 4.4)
            g.move(to: a); g.addLine(to: CGPoint(x: a.x + CGFloat(i) * 0.008 * u, y: a.y - 0.15 * u))
        }
        g.strokePath()

        // ---- the wound part: round the neck, sagging a little in the middle, thick at the sides
        let band = CGMutablePath()
        band.move(to: CGPoint(x: x - W, y: yT))
        band.addCurve(to: CGPoint(x: x + W, y: yT), control1: CGPoint(x: x - W * 0.45, y: yT - 0.26 * u), control2: CGPoint(x: x + W * 0.45, y: yT - 0.26 * u))
        band.addCurve(to: CGPoint(x: x + W * 1.04, y: yB + 0.3 * u), control1: CGPoint(x: x + W * 1.12, y: yT - 0.1 * u), control2: CGPoint(x: x + W * 1.14, y: yB + 0.5 * u))
        band.addCurve(to: CGPoint(x: x - W * 1.04, y: yB + 0.3 * u), control1: CGPoint(x: x + W * 0.55, y: yB - 0.16 * u), control2: CGPoint(x: x - W * 0.55, y: yB - 0.16 * u))
        band.addCurve(to: CGPoint(x: x - W, y: yT), control1: CGPoint(x: x - W * 1.14, y: yB + 0.5 * u), control2: CGPoint(x: x - W * 1.12, y: yT - 0.1 * u))
        band.closeSubpath()
        g.saveGState()
        g.addPath(band); g.clip()
        g.setFillColor(base); g.fill(band.boundingBox)
        // ribs across the wound scarf, fanning a little as it goes round the neck
        g.setStrokeColor(dark.copy(alpha: 0.4)!); g.setLineWidth(max(1, 0.022 * u))
        let count = Int(2 * W / (0.085 * u))
        for i in 0...max(1, count) {
            let f = CGFloat(i) / CGFloat(max(1, count)) * 2 - 1
            g.move(to: CGPoint(x: x + f * W * 0.94, y: yT + 0.1 * u)); g.addLine(to: CGPoint(x: x + f * W * 1.1, y: yB - 0.2 * u))
        }
        g.strokePath()
        // light from above, shade below
        if let grad = CGGradient(colorsSpace: nil, colors: [CGColor(gray: 1, alpha: 0.14), CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.3)] as CFArray,
                                 locations: [0, 0.45, 1]) {
            g.drawLinearGradient(grad, start: CGPoint(x: x, y: yT), end: CGPoint(x: x, y: yB), options: [])
        }
        // the fold where the second turn lies over the first
        g.setStrokeColor(dark.copy(alpha: 0.55)!); g.setLineWidth(max(1.5, 0.04 * u))
        g.move(to: CGPoint(x: x - W * 1.05, y: yT - 0.22 * u))
        g.addCurve(to: CGPoint(x: x + W * 1.05, y: (yT + yB) / 2 - 0.02 * u), control1: CGPoint(x: x - W * 0.4, y: (yT + yB) / 2 - 0.2 * u),
                   control2: CGPoint(x: x + W * 0.4, y: (yT + yB) / 2 - 0.3 * u))
        g.strokePath()
        g.restoreGState()
        g.setStrokeColor(dark.copy(alpha: 0.5)!); g.setLineWidth(max(1, 0.02 * u))
        g.addPath(band); g.strokePath()
    }
}
