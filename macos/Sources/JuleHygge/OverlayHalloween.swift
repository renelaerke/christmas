import AppKit

/// Halloween (Theme.halloween): each Christmas element in its Halloween form, drawn here beside the overlay's own
/// code (Overlay.swift calls in where the theme branches). Autumn's leaves fall and pile up as they are; the rest
/// is: jack-o'-lanterns carved step by step in the snowman's place, a witch on her broom with bats after her in
/// Santa's, ghosts and children dressed up for trick or treat in the nisser's, a garland of small pumpkin
/// lanterns and hanging bats in the lights', and black cats and spiders on the window edges.
/// All figures are original and drawn in code, like the rest.
extension ScreenOverlay {
    static let pumpkinColours = [C(255, 122, 26), C(224, 106, 18), C(217, 84, 30)]
    private static let night = C(23, 21, 29), candleLight = C(255, 224, 138)

    // ------------------------------------------------------------------ small things the figures share
    /// A soft round light: `inner` in the middle, fading to nothing at the rim.
    private func halo(_ g: CGContext, _ inner: CGColor, _ cx: F, _ cy: F, _ r: F) {
        let rim = withAlpha(inner, 0)
        let p = CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil)
        g.saveGState(); g.addPath(p); g.clip()
        g.drawRadialGradient(CGGradient(colorsSpace: nil, colors: [inner, rim] as CFArray, locations: [0, 1])!,
                             startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: [])
        g.restoreGState()
    }

    /// One pumpkin standing on the ground at x = `cx`, `r` wide to each side: ribbed, with a stalk, and when carved
    /// a face (eyes from `face` 1, the mouth too from 2) that is dark until a candle is lit inside it.
    func drawPumpkin(_ g: CGContext, _ cx: F, _ r: F, _ colour: CGColor, stalk: Bool, face: Int, lit: Bool) {
        let ry = r * 0.82, cy = -ry
        if lit { halo(g, withAlpha(C(255, 179, 71), 90), cx, cy, r * 1.9) }
        g.fillEllipse(shade(colour, 0.72), cx - r, cy - ry, 2 * r, 2 * ry)
        // the ribs: lighter lobes from the middle out
        g.fillEllipse(shade(colour, 0.88), cx - r * 0.86, cy - ry * 0.97, r * 1.72, ry * 1.94)
        g.fillEllipse(colour, cx - r * 0.58, cy - ry, r * 1.16, 2 * ry)
        g.strokeEllipse(shade(colour, 0.6), max(0.8, r * 0.035), cx - r * 0.28, cy - ry, r * 0.56, 2 * ry)
        if stalk {
            let s = CGMutablePath()
            s.start(cx - r * 0.1, cy - ry * 0.92); s.curve(cx - r * 0.1, cy - ry * 1.2, cx + r * 0.05, cy - ry * 1.3, cx + r * 0.26, cy - ry * 1.34)
            s.to(cx + r * 0.3, cy - ry * 1.2); s.curve(cx + r * 0.16, cy - ry * 1.18, cx + r * 0.12, cy - ry * 1.05, cx + r * 0.12, cy - ry * 0.92)
            s.closeSubpath()
            g.fill(C(72, 120, 48), s)
        }
        guard face > 0 else { return }
        let inside = lit ? Self.candleLight : C(58, 28, 8)
        g.fillPoly(inside, [(cx - r * 0.5, cy - ry * 0.08), (cx - r * 0.3, cy - ry * 0.48), (cx - r * 0.1, cy - ry * 0.08)])
        g.fillPoly(inside, [(cx + r * 0.1, cy - ry * 0.08), (cx + r * 0.3, cy - ry * 0.48), (cx + r * 0.5, cy - ry * 0.08)])
        g.fillPoly(inside, [(cx - r * 0.07, cy + ry * 0.2), (cx, cy + ry * 0.02), (cx + r * 0.07, cy + ry * 0.2)])
        if face > 1 {
            // a wide grin with teeth left standing
            let m = CGMutablePath()
            m.start(cx - r * 0.58, cy + ry * 0.26)
            m.addQuadCurve(to: CGPoint(x: cx + r * 0.58, y: cy + ry * 0.26), control: CGPoint(x: cx, y: cy + ry * 0.5))
            m.addQuadCurve(to: CGPoint(x: cx - r * 0.58, y: cy + ry * 0.26), control: CGPoint(x: cx, y: cy + ry * 1.0))
            m.closeSubpath()
            g.fill(inside, m)
            for dx in [F(-0.26), 0.2] { g.fillRect(colour, cx + dx * r, cy + ry * 0.3, r * 0.14, ry * 0.16) }
            g.fillRect(colour, cx - r * 0.04, cy + ry * 0.56, r * 0.14, ry * 0.16)
        }
    }

    /// A small bat seen from the front, wings out: `flap` -1…1 lifts and lowers the wing tips.
    func drawBat(_ g: CGContext, _ x: F, _ y: F, _ size: F, _ flap: F) {
        g.saveGState()
        g.translateBy(x: x, y: y)
        g.scaleBy(x: size, y: size)
        let lift = flap * 7
        for side in [F(-1), 1] {
            let w = CGMutablePath()
            w.start(side * 2, -1)
            w.curve(side * 8, -8 - lift, side * 15, -7 - lift, side * 20, -1 - lift)
            // the scalloped trailing edge
            w.addQuadCurve(to: CGPoint(x: side * 14, y: 2 - lift * 0.6), control: CGPoint(x: side * 17, y: -2 - lift * 0.7))
            w.addQuadCurve(to: CGPoint(x: side * 8, y: 4 - lift * 0.3), control: CGPoint(x: side * 11, y: 0 - lift * 0.4))
            w.addQuadCurve(to: CGPoint(x: side * 2, y: 4), control: CGPoint(x: side * 5, y: 1))
            w.closeSubpath()
            g.fill(Self.night, w)
        }
        g.fillEllipse(Self.night, -3, -4, 6, 9)
        g.fillPoly(Self.night, [(-2.6, -3), (-2.2, -7.5), (-0.4, -4)])
        g.fillPoly(Self.night, [(2.6, -3), (2.2, -7.5), (0.4, -4)])
        g.fillEllipse(C(255, 210, 90), -1.9, -2.6, 1.3, 1.3)
        g.fillEllipse(C(255, 210, 90), 0.6, -2.6, 1.3, 1.3)
        g.restoreGState()
    }

    /// A black cat sitting, seen from the side and looking at us, its tail curled to the right (`tail` -1…1 swings
    /// its tip). Sits on y = 0, about 26 high, centred on x = 0.
    func drawCat(_ g: CGContext, tail: F, eyesOpen: Bool = true) {
        let black = Self.night
        g.bezier(black, 3, 8, -3, 20, -2, 20 + tail * 3, -14, 14 + tail * 5, -19)
        // haunches, chest and head
        g.fillEllipse(black, -9, -13, 20, 13)
        let chest = CGMutablePath()
        chest.start(-8, -1); chest.curve(-10, -12, -7, -19, -3, -21); chest.to(4, -21); chest.curve(8, -15, 9, -8, 8, -1); chest.closeSubpath()
        g.fill(black, chest)
        g.fillEllipse(black, -8, -29, 15, 13)
        g.fillPoly(black, [(-7.5, -24), (-7, -33), (-2, -28)])
        g.fillPoly(black, [(6.5, -24), (6, -33), (1, -28)])
        g.fillEllipse(black, -8, -3, 6, 3.4)
        g.fillEllipse(black, 1, -3, 6, 3.4)
        if eyesOpen {
            for dx in [F(-4.2), 1.2] {
                g.fillEllipse(C(255, 214, 64), dx, -24.5, 3.2, 2.6)
                g.fillRect(black, dx + 1.3, -24.5, 0.7, 2.6)
            }
        } else {
            g.line(C(255, 214, 64), 0.7, -4, -23.2, -1.2, -23.2)
            g.line(C(255, 214, 64), 0.7, 1.4, -23.2, 4.2, -23.2)
        }
    }

    // ------------------------------------------------------------------ græskarlygter
    /// Halloween's form of the snowman: three pumpkins put out and carved into jack-o'-lanterns, a step for every
    /// hour the app runs (Controller.pumpkinSteps), in the same place and frame as the snowman. Origin at the
    /// ground, y up is negative.
    func drawPumpkins(_ g: CGContext, _ stage: Int) {
        g.fillEllipse(C(20, 12, 8, 60), -60, -3, 120, 6)
        let cols = Self.pumpkinColours
        let stalks = stage >= 4
        // the curling vine behind them (stage 4)
        if stalks {
            g.bezier(C(72, 120, 48), 1.6, -30, -30, -24, -52, -8, -40, -14, -56)
            g.bezier(C(72, 120, 48), 1.6, 30, -26, 40, -44, 22, -44, 30, -54)
            g.fillEllipse(C(86, 138, 56), -22, -50, 9, 6)
        }
        if stage >= 1 { drawPumpkin(g, -38, 20, cols[1], stalk: stalks, face: stage >= 8 ? 2 : 0, lit: stage >= 10) }
        if stage >= 2 { drawPumpkin(g, 38, 18, cols[2], stalk: stalks, face: stage >= 9 ? 2 : 0, lit: stage >= 10) }
        if stage >= 3 { drawPumpkin(g, 0, 32, cols[0], stalk: stalks, face: stage >= 6 ? 2 : stage >= 5 ? 1 : 0, lit: stage >= 7) }
        // a witch's hat on the right pumpkin (stage 11)
        if stage >= 11 {
            g.saveGState()
            g.translateBy(x: 40, y: -29)
            g.rotate(by: 0.22)
            g.fillEllipse(Self.night, -15, -3, 30, 7)
            g.fillPoly(Self.night, [(-8, -1), (2, -30), (8, -1)])
            g.fillRect(C(123, 44, 191), -7.4, -5.5, 14.8, 3)
            g.fillRect(C(255, 210, 63), -2, -6, 4, 4)
            g.restoreGState()
        }
        // a black cat on the left pumpkin (stage 12)
        if stage >= 12 {
            g.saveGState()
            g.translateBy(x: -40, y: -31)
            g.scaleBy(x: 0.9, y: 0.9)
            drawCat(g, tail: 0.3)
            g.restoreGState()
        }
    }

    // ------------------------------------------------------------------ spøgelser og udklædte børn
    /// Halloween's walkers. They are nisser in everything but looks: they walk, stop, wave, cross to the next
    /// screen and meet to hand something over (a bucket of sweets). Every other one is a ghost under a sheet,
    /// floating a little above the ground; the others are children dressed up for trick or treat, a small witch
    /// or a small pumpkin. Drawn like a nisse: feet at (0, 0), y up is negative, facing right.
    func drawSpook(_ g: CGContext, _ n: Nisse, _ frame: Int) {
        let p: F = n.state == 0 ? F(frame) / F(Self.walkFrames) * 4 * .pi : 0
        let standPhase: F = n.state == 1 ? F(frame) / F(Self.standFrames) * 2 * .pi : 0
        let wavePhase: F = n.state == 2 ? F(frame) / F(Self.waveFrames) * 2 * .pi : 0
        if n.tunicIndex % 2 == 0 { drawGhost(g, n, p, standPhase, wavePhase) } else { drawTreater(g, n, p, standPhase, wavePhase) }
    }

    /// The bucket of sweets a walker carries: a small pumpkin pail with a handle.
    private func drawSweetBucket(_ g: CGContext, _ x: F, _ y: F) {
        g.bezier(C(60, 40, 30), 1, x - 4, y - 6, x - 3, y - 11, x + 3, y - 11, x + 4, y - 6)
        g.fillEllipse(Self.pumpkinColours[0], x - 5.5, y - 7, 11, 9)
        g.fillPoly(C(58, 28, 8), [(x - 3, y - 3.4), (x - 1.8, y - 5.2), (x - 0.6, y - 3.4)])
        g.fillPoly(C(58, 28, 8), [(x + 0.6, y - 3.4), (x + 1.8, y - 5.2), (x + 3, y - 3.4)])
        g.fillEllipse(C(233, 30, 99), x - 3.4, y - 9.2, 3, 3)
        g.fillEllipse(C(255, 210, 63), x + 0.2, y - 9.6, 3, 3)
    }

    private func drawGhost(_ g: CGContext, _ n: Nisse, _ p: F, _ standPhase: F, _ wavePhase: F) {
        let walking = n.state == 0, waving = n.state == 2
        // it floats: up and down as it goes, a little higher when it says boo
        let bob: F = walking ? sin(p) * 2 : (waving ? -3 - abs(sin(wavePhase)) * 2 : sin(standPhase) * 1.2)
        let hem: F = walking ? p : standPhase
        let sheet = n.tunicIndex == 2 ? C(236, 228, 250) : C(248, 250, 252), fold = C(196, 204, 226), edge = C(110, 120, 150, 190)
        g.fillEllipse(C(30, 20, 40, 45), -10, -2, 20, 4)
        g.translateBy(x: 0, y: bob - 4)

        let arm: F = waving ? 0.9 + sin(wavePhase) * 0.25 : 0.25
        func outline() -> CGMutablePath {
            let s = CGMutablePath()
            s.start(-11, -4)
            s.curve(-11, -20, -12, -46, 0, -46)
            s.curve(12, -46, 11, -20, 11, -4)
            // the wavy hem, right to left
            let n = 4
            for k in 0..<n {
                let x1 = 11 - 22 * F(k + 1) / F(n), xm = 11 - 22 * (F(k) + 0.5) / F(n)
                s.addQuadCurve(to: CGPoint(x: x1, y: -4), control: CGPoint(x: xm, y: -4 + 5 + sin(hem + F(k) * 1.6) * 2))
            }
            s.closeSubpath()
            return s
        }
        // the arms under the sheet: stubs out to the sides, up when it says boo
        for side in [F(-1), 1] {
            let a = CGMutablePath()
            a.start(side * 8, -30)
            a.curve(side * 14, -30 - arm * 4, side * 19, -28 - arm * 14, side * 18, -24 - arm * 16)
            a.curve(side * 15, -20 - arm * 10, side * 12, -20, side * 8, -20)
            a.closeSubpath()
            g.fill(sheet, a); g.stroke(edge, 1, a)
        }
        let body = outline()
        g.fill(sheet, body)
        g.stroke(edge, 1, body)
        // a fold of shade down one side
        let shadeSide = CGMutablePath()
        shadeSide.start(-10.2, -6); shadeSide.curve(-10.4, -20, -11, -40, -3, -45); shadeSide.curve(-8, -36, -7, -18, -7, -6); shadeSide.closeSubpath()
        g.fill(withAlpha(fold, 150), shadeSide)
        // the face: two dark eyes and a round mouth (wide open at boo)
        let ink = C(34, 30, 48)
        g.fillEllipse(ink, -3.2, -36, 4, 5.4)
        g.fillEllipse(ink, 3.4, -36, 4, 5.4)
        let mouth: F = waving ? 5.5 : 2.6
        g.fillEllipse(ink, 0.6, -28.5, 3.4, mouth)

        if n.carriesGift && !waving { drawSweetBucket(g, 15, -14) }
    }

    private func drawTreater(_ g: CGContext, _ n: Nisse, _ p: F, _ standPhase: F, _ wavePhase: F) {
        let walking = n.state == 0, waving = n.state == 2
        let legA: F = walking ? sin(p) * 0.55 : 0
        let bob: F = walking ? -abs(sin(p)) * 1.5 : (waving ? -abs(sin(wavePhase)) * 2 : 0)
        let witch = n.tunicIndex % 4 == 1
        let ink = C(34, 26, 40), skin = C(255, 214, 186)
        g.fillEllipse(C(30, 20, 40, 50), -10, -2, 20, 4)

        // legs: striped stockings for the witch, green tights for the pumpkin
        func leg(_ hx: F, _ a: F) {
            let fx = hx + sin(a) * 12, fy = -13 + bob + cos(a) * 12
            g.line(witch ? C(123, 44, 191) : C(72, 120, 48), 3.4, hx, -13 + bob, fx, fy, round: true)
            if witch { g.line(C(255, 152, 0), 3.4, hx + sin(a) * 4, -13 + bob + cos(a) * 4, hx + sin(a) * 7, -13 + bob + cos(a) * 7) }
            g.fillEllipse(ink, fx - 3, fy - 2, 8, 4.4)
        }
        leg(-2, legA)
        leg(2, -legA)

        g.translateBy(x: 0, y: bob)
        let backArm: F, frontArm: F
        if waving { backArm = -0.4 + sin(wavePhase) * 0.3; frontArm = 2.6 + sin(wavePhase) * 0.5 }
        else if n.carriesGift { backArm = 1.3; frontArm = 1.3 }
        else { backArm = -legA * 0.9; frontArm = legA * 0.9 }
        let sleeve = witch ? C(40, 30, 54) : C(72, 120, 48)
        func arm(_ sx: F, _ sy: F, _ a: F) {
            let hx = sx + sin(a) * 10, hy = sy + cos(a) * 10
            g.line(sleeve, 3.2, sx, sy, hx, hy, round: true)
            g.fillEllipse(skin, hx - 2.2, hy - 2.2, 4.4, 4.4)
        }
        arm(-1, -30, backArm)

        if witch {
            // a dark dress flaring to the hem, with a purple sash
            let dress = CGMutablePath()
            dress.start(-5, -32); dress.to(5, -32); dress.curve(7, -24, 10, -16, 11, -10); dress.to(-11, -10); dress.curve(-10, -16, -7, -24, -5, -32)
            dress.closeSubpath()
            g.fill(C(40, 30, 54), dress)
            for k in 0..<5 { g.fillPoly(C(40, 30, 54), [(-11 + F(k) * 4.4, -10), (-8.8 + F(k) * 4.4, -6.5), (-6.6 + F(k) * 4.4, -10)]) }
            g.line(C(123, 44, 191), 1.6, -6.4, -22, 6.4, -22)
        } else {
            // a round pumpkin costume with ribs and a carved face
            g.fillEllipse(shade(Self.pumpkinColours[0], 0.8), -11, -33, 22, 22)
            g.fillEllipse(Self.pumpkinColours[0], -7, -33, 14, 22)
            g.strokeEllipse(shade(Self.pumpkinColours[0], 0.6), 0.8, -3.2, -33, 6.4, 22)
            g.fillPoly(ink, [(-5.5, -22), (-3.5, -26), (-1.5, -22)])
            g.fillPoly(ink, [(1.5, -22), (3.5, -26), (5.5, -22)])
            g.bezier(ink, 1.4, -5, -18, -2, -15, 2, -15, 5, -18)
        }

        if n.carriesGift && !waving { drawSweetBucket(g, 13, -17) }

        // the head, looking a little the way it walks
        let sway = sin(walking ? p * 0.5 : standPhase) * 0.05
        g.saveGState()
        g.translateBy(x: 1, y: -39)
        g.rotate(by: sway)
        g.fillEllipse(skin, -6.5, -6.5, 13, 13)
        g.fillEllipse(C(250, 170, 160, 150), 1.5, 0.2, 3.6, 2.6)
        g.fillEllipse(ink, 1.4, -2.4, 2, 2.6)
        g.fillEllipse(ink, 4.4, -2.4, 1.6, 2.4)
        g.bezier(ink, 0.8, 1.6, 2.6, 3, 4, 4.4, 4, 5.4, 2.6)
        if witch {
            // hair, and a pointed hat with a bent tip and a buckle
            g.fillEllipse(C(214, 110, 40), -8, -4, 6, 11)
            g.fillEllipse(ink, -11, -8.2, 22, 5)
            let hat = CGMutablePath()
            hat.start(-6, -6.5); hat.curve(-4, -16, -1, -22, 5, -23); hat.curve(2, -19, 5, -12, 6, -6.5); hat.closeSubpath()
            g.fill(ink, hat)
            g.fillRect(C(123, 44, 191), -5.6, -9, 11.4, 2.2)
            g.fillRect(C(255, 210, 63), -1.4, -9.4, 3, 3)
        } else {
            // the pumpkin's cap: a green stalk and two leaves
            g.fillEllipse(C(72, 120, 48), -6.8, -8.4, 13.6, 5.4)
            g.fillRect(C(60, 100, 40), -1, -12.6, 2.6, 5)
            g.fillEllipse(C(86, 138, 56), 1, -11.4, 6, 3)
        }
        g.restoreGState()

        arm(1, -30, frontArm)
        if waving {
            // waving a lollipop
            let hx = 1 + sin(frontArm) * 10, hy = -30 + cos(frontArm) * 10
            g.line(C(250, 250, 250), 1, hx, hy, hx + sin(frontArm) * 6, hy + cos(frontArm) * 6)
            g.fillEllipse(C(233, 30, 99), hx + sin(frontArm) * 8 - 3, hy + cos(frontArm) * 8 - 3, 6, 6)
            g.strokeEllipse(C(255, 255, 255, 200), 0.8, hx + sin(frontArm) * 8 - 1.5, hy + cos(frontArm) * 8 - 1.5, 3, 3)
        }
    }

    // ------------------------------------------------------------------ heks på kost
    /// Halloween's flyer in Santa's place: a witch on her broom, flying toward +x, her cape and the broom's twigs
    /// streaming behind, a cat riding at the back, and a handful of bats after her. Drawn in Santa's frame
    /// (translated to his place and scaled by his size and direction); `t` is the trip's clock.
    func drawWitch(_ g: CGContext, _ t: F) {
        // the bats: each beats its wings in its own time and wanders around its place behind her
        let places: [(F, F, F)] = [(-150, -46, 1.0), (-205, -8, 0.8), (-120, 30, 0.9), (-250, -58, 0.7), (-285, 16, 0.85), (-190, 52, 0.7)]
        for (i, pl) in places.enumerated() {
            let fi = F(i)
            drawBat(g, pl.0 + sin(t * 1.1 + fi * 2.3) * 10, pl.1 + sin(t * 1.7 + fi * 1.3) * 9, pl.2 * 1.25, sin(t * (11 + fi) + fi * 2))
        }
        g.translateBy(x: 0, y: sin(t * 1.8) * 5)
        g.rotate(by: -0.06 + sin(t * 1.8 + 1) * 0.03)
        let ink = Self.night, wood = C(120, 80, 40), skin = C(132, 178, 96)
        let flutter = sin(t * 9)
        // the broom: the stick, and the twigs bound at the back, shaking in the wind
        for k in 0..<7 {
            let a = (F(k) - 3) * 0.09
            g.line(k % 2 == 0 ? C(214, 170, 72) : C(176, 132, 52), 2.2, -62, 2, -108, 2 + a * 46 + flutter * F(k % 3 - 1) * 2.2, round: true)
        }
        g.fillRect(C(96, 60, 30), -66, -1.6, 6, 7.2)
        g.line(wood, 3.6, -64, 2, 104, -5, round: true)
        // the cat riding at the back
        g.saveGState()
        g.translateBy(x: -40, y: 0)
        g.scaleBy(x: 0.8, y: 0.8)
        drawCat(g, tail: flutter * 0.6)
        g.restoreGState()
        // the cape streaming behind her
        let cape = CGMutablePath()
        cape.start(18, -42)
        cape.curve(0, -44, -22, -40 + flutter * 3, -40, -30 + flutter * 5)
        cape.addQuadCurve(to: CGPoint(x: -30, y: -20 + flutter * 3), control: CGPoint(x: -30, y: -26 + flutter * 4))
        cape.addQuadCurve(to: CGPoint(x: -18, y: -12 + flutter * 2), control: CGPoint(x: -20, y: -18 + flutter * 3))
        cape.curve(0, -12, 12, -18, 22, -30)
        cape.closeSubpath()
        g.fill(C(74, 38, 110), cape)
        // her leg forward along the stick: a striped stocking and a pointed shoe
        g.line(C(123, 44, 191), 5, 26, -8, 52, -9, round: true)
        for k in 0..<3 { g.line(C(255, 152, 0), 5, 31 + F(k) * 7, -8.2 - F(k) * 0.3, 34 + F(k) * 7, -8.3 - F(k) * 0.3) }
        g.fillPoly(ink, [(50, -13), (64, -11), (62, -6), (50, -5)])
        // the dress, leaning forward over the stick
        let dress = CGMutablePath()
        dress.start(14, -44); dress.curve(26, -46, 36, -36, 38, -22); dress.curve(36, -8, 22, -2, 10, -4); dress.curve(8, -18, 10, -34, 14, -44)
        dress.closeSubpath()
        g.fill(ink, dress)
        // arms to the stick
        g.line(ink, 4, 28, -36, 44, -14, round: true)
        g.fillEllipse(skin, 42, -15, 6, 6)
        // head, with a long nose and chin, and hair flying back
        g.bezier(C(214, 110, 40), 3, 22, -52, 8, -52, 0, -44 + flutter * 2, -8, -46 + flutter * 3)
        g.bezier(C(214, 110, 40), 3, 22, -48, 10, -46, 4, -40 + flutter * 2, -4, -38 + flutter * 3)
        g.fillEllipse(skin, 20, -60, 17, 17)
        g.fillPoly(skin, [(35, -53), (44, -50), (35, -48)])
        g.fillPoly(skin, [(31, -46), (38, -42), (28, -43)])
        g.fillEllipse(ink, 30, -55, 2.4, 2.8)
        g.bezier(ink, 0.9, 31, -46.5, 33, -45.5, 35, -45.5, 36, -47)
        // the pointed hat, its tip bent back
        g.saveGState()
        g.translateBy(x: 27, y: -59)
        g.rotate(by: -0.2)
        g.fillEllipse(ink, -17, -3.5, 34, 8)
        let hat = CGMutablePath()
        hat.start(-9, -1); hat.curve(-7, -18, -6, -30, -16 + flutter * 1.5, -40); hat.curve(-2, -34, 6, -18, 9, -1); hat.closeSubpath()
        g.fill(ink, hat)
        g.fillRect(C(123, 44, 191), -8.6, -6.4, 17.4, 3.4)
        g.fillRect(C(255, 210, 63), -2.4, -7, 4.8, 4.8)
        g.restoreGState()
    }

    // ------------------------------------------------------------------ heksen fejer, eller spøgelserne puster
    /// Halloween has two forms of the snow plow, one or the other each run (Controller.ghostsBlow). This is the
    /// first: a small witch walks in front sweeping the leaves up with her broom; they fly back into a cauldron on
    /// a cart that her black cat pulls. Facing +x, origin at the ground, the broom where the plow's blade would be.
    func drawWitchSweeper(_ g: CGContext, _ ph: F) {
        let step = plowWheel, stride = ScreenOverlay.donkeyStride
        let ink = Self.night, wood = C(120, 80, 40), woodDark = C(84, 54, 28)
        // the cart: a flat bed on two small wheels, and on it the cauldron heaped with leaves
        for (i, lx) in [F(-90), -80, -70, -60, -50].enumerated() {
            g.fillEllipse(Theme.leafColours[(i * 2) % Theme.leafColours.count], lx - 8, -66 + F(i % 2) * 4, 17, 12)
            g.fillEllipse(Theme.leafColours[(i * 2 + 1) % Theme.leafColours.count], lx - 2, -60 - F(i % 2) * 3, 15, 11)
        }
        g.fillEllipse(ink, -98, -62, 56, 46)
        g.fillEllipse(C(52, 48, 62), -92, -58, 18, 30)
        g.fillEllipse(C(64, 60, 76), -100, -62, 60, 10)
        g.fillEllipse(ink, -96, -60.5, 52, 6)
        g.fillRect(woodDark, -104, -18, 70, 5)
        for wx in [F(-92), -48] {
            g.fillEllipse(woodDark, wx - 9, -18, 18, 18)
            g.strokeEllipse(wood, 1.8, wx - 6.5, -15.5, 13, 13)
            for k in 0..<4 {
                let a = step * 1.6 + F(k) * .pi / 2
                g.line(wood, 1.4, wx, -9, wx + cos(a) * 6.5, -9 + sin(a) * 6.5)
            }
        }
        // the shaft and the cat that pulls: black, tail up, its legs going
        g.line(woodDark, 2.4, -36, -16, 6, -20, round: true)
        func leg(_ hx: F, _ a: F) {
            g.line(ink, 3.2, hx, -16, hx + sin(a) * 6, -7, round: true)
            g.line(ink, 2.8, hx + sin(a) * 6, -7, hx + sin(a) * 8, 0, round: true)
        }
        leg(-2, sin(step * stride + 1.2) * 0.5); leg(22, sin(step * stride + 1.2 + .pi) * 0.5)
        g.bezier(ink, 3, -6, -22, -16, -26, -18, -40, -10, -46 + sin(step * stride) * 2)
        g.fillEllipse(ink, -8, -28, 40, 15)
        leg(2, sin(step * stride + .pi) * 0.5); leg(26, sin(step * stride) * 0.5)
        let nod = sin(step * stride) * 1
        g.fillEllipse(ink, 24, -38 + nod, 16, 14)
        g.fillPoly(ink, [(26, -34 + nod), (26.5, -44 + nod), (31, -37 + nod)])
        g.fillPoly(ink, [(38, -34 + nod), (38, -44 + nod), (33.5, -37 + nod)])
        g.fillEllipse(C(255, 214, 64), 33, -33 + nod, 3, 2.6)
        g.line(C(200, 60, 60), 1.6, 22, -28, 26, -22)   // the harness
        // the small witch with the broom, walking in front
        let walker = Nisse()
        walker.tunicIndex = 1; walker.state = 0
        let frame = Int((step * stride / (4 * .pi)).truncatingRemainder(dividingBy: 1) * F(Self.walkFrames)) % Self.walkFrames
        g.saveGState()
        g.translateBy(x: 78, y: 0)
        g.scaleBy(x: 1.3, y: 1.3)
        drawSpook(g, walker, frame)
        g.restoreGState()
        // the broom: the handle from her hands down to the ground in front, the twigs swinging
        let swing = sin(step * stride * 2) * 5
        g.line(wood, 2.2, 80, -42, 98 + swing, -4, round: true)
        for k in 0..<6 { g.line(k % 2 == 0 ? C(214, 170, 72) : C(176, 132, 52), 1.6, 97 + swing, -6, 92 + swing + F(k) * 3.4, 1, round: true) }
        g.fillRect(woodDark, 94 + swing, -8, 7, 3)
        // leaves gathered in front of the broom
        for (i, lx) in [F(102), 109, 116].enumerated() where F(i) * 6 < ph {
            g.fillEllipse(Theme.leafColours[i % Theme.leafColours.count], lx + swing - 5, -6 - F(i % 2) * 2, 10, 6)
        }
    }

    /// The second: three ghosts float along in a row, leaning forward, and blow; the leaves whirl up in front of
    /// them and are carried off. Facing +x, origin at the ground.
    func drawGhostBlowers(_ g: CGContext, _ ph: F) {
        let t = plowWheel
        let places: [(F, F, F, Int)] = [(-64, -8, 1.15, 0), (-8, -20, 1.3, 2), (46, -4, 1.2, 0)]
        for (i, pl) in places.enumerated() {
            let fi = F(i)
            let ghost = Nisse()
            ghost.tunicIndex = pl.3; ghost.state = 0
            g.saveGState()
            g.translateBy(x: pl.0, y: pl.1 + sin(t * 0.9 + fi * 2.1) * 3)
            g.rotate(by: 0.30 + sin(t * 0.7 + fi) * 0.04)
            g.scaleBy(x: pl.2, y: pl.2)
            let frame = Int(((t * 0.5 + fi * 0.37) / (4 * .pi)).truncatingRemainder(dividingBy: 1) * F(Self.walkFrames)) % Self.walkFrames
            drawSpook(g, ghost, frame)
            // cheeks puffed and a round mouth, blowing
            g.fillEllipse(C(34, 30, 48), 2.6, -33, 5, 5.6)
            g.fillEllipse(C(244, 200, 210, 150), -5.4, -30, 4, 3)
            g.restoreGState()
            // its breath: thin pale streaks out in front, wavering
            let bx = pl.0 + 22 * pl.2, by = pl.1 - 30 * pl.2
            for k in 0..<3 {
                let fk = F(k), w = sin(t * 3 + fi * 1.7 + fk * 2) * 3
                g.bezier(C(255, 255, 255, 110 - k * 25), 1.6 - fk * 0.3, bx + 4, by + fk * 5 - 3, bx + 18, by + fk * 6 - 6 + w,
                         bx + 30, by + fk * 7 + 4 - w, bx + 44 + fk * 6, by + fk * 8 + w * 0.5)
            }
        }
        // leaves lifted off the pile just ahead of them
        for (i, lx) in [F(88), 100, 112].enumerated() where F(i) * 6 < ph {
            g.fillEllipse(Theme.leafColours[(i + 1) % Theme.leafColours.count], lx - 5, -8 - F(i) * 5 + sin(t * 4 + F(i)) * 3, 10, 6)
        }
    }

    // ------------------------------------------------------------------ lyskæde med græskar og flagermus
    /// A small pumpkin lantern hanging at a bulb's place, its top at (bx, by): dark when `lit` is false (drawn once
    /// with the string), glowing when true (the twinkling layer over it).
    func drawGarlandPumpkin(_ g: CGContext, _ bx: F, _ by: F, lit: Bool) {
        let S = self.S
        let col = lit ? C(255, 140, 30) : C(140, 70, 16), face = lit ? Self.candleLight : C(48, 24, 8)
        if lit { halo(g, withAlpha(C(255, 170, 60), 110), bx, by + 10 * S, 13 * S) }
        g.line(C(60, 44, 30), 1.2 * S, bx, by, bx, by + 4 * S)
        g.fillRect(C(72, 120, 48), bx - 1.2 * S, by + 3 * S, 2.4 * S, 2.4 * S)
        g.fillEllipse(shade(col, 0.8), bx - 6.5 * S, by + 4.6 * S, 13 * S, 10.8 * S)
        g.fillEllipse(col, bx - 4 * S, by + 4.6 * S, 8 * S, 10.8 * S)
        g.fillPoly(face, [(bx - 3.6 * S, by + 9.6 * S), (bx - 2.2 * S, by + 7 * S), (bx - 0.8 * S, by + 9.6 * S)])
        g.fillPoly(face, [(bx + 0.8 * S, by + 9.6 * S), (bx + 2.2 * S, by + 7 * S), (bx + 3.6 * S, by + 9.6 * S)])
        g.fillPoly(face, [(bx - 3.4 * S, by + 11.2 * S), (bx + 3.4 * S, by + 11.2 * S), (bx, by + 13.6 * S)])
    }

    /// The garland itself, over the string: bats hanging by their feet, asleep with their wings folded round them,
    /// and the unlit pumpkin lanterns where the bulbs are (`bulbs` are those places).
    func drawSpookGarland(_ g: CGContext, span: F, sag: F, top: F, bulbs: [(F, F)]) {
        let S = self.S
        var n = 0
        var x0 = -span * 0.3
        while x0 < W {
            for k in 0..<12 where k % 3 != 1 && (n + k) % 2 == 0 {
                let u = (F(k) + 0.5) / 12
                let x = x0 + u * span, y = top + sag * (1 - (2 * u - 1) * (2 * u - 1))
                let size = (0.8 + F((n * 7 + k) % 4) * 0.12) * S
                g.saveGState()
                g.translateBy(x: x, y: y)
                g.rotate(by: sin(F(n + k) * 2.3) * 0.12)
                g.scaleBy(x: size, y: size)
                // the folded wings as a pointed cloak, the head and ears below, two small feet on the string
                g.line(Self.night, 1, -1.4, 0, -1.4, 2.4); g.line(Self.night, 1, 1.4, 0, 1.4, 2.4)
                let cloak = CGMutablePath()
                cloak.start(0, 1.6); cloak.curve(-6.5, 4, -5.5, 12, -1, 15.5); cloak.to(1, 15.5); cloak.curve(5.5, 12, 6.5, 4, 0, 1.6); cloak.closeSubpath()
                g.fill(Self.night, cloak)
                g.fillEllipse(Self.night, -2.8, 13.6, 5.6, 5.4)
                g.fillPoly(Self.night, [(-2.6, 17.4), (-2.9, 21.4), (-0.6, 18.6)])
                g.fillPoly(Self.night, [(2.6, 17.4), (2.9, 21.4), (0.6, 18.6)])
                g.restoreGState()
            }
            n += 1
            x0 += span
        }
        for (bx, by) in bulbs { drawGarlandPumpkin(g, bx, by, lit: false) }
    }

    // ------------------------------------------------------------------ katte og edderkopper på vindueskanterne
    /// The pictures the window edges' figures are made of: a cat with its tail to either side and one blinking,
    /// a spider, and a thread. Drawn once, at twice the size they are shown at.
    private func makeSpookImages() -> [CGImage] {
        func picture(_ w: F, _ h: F, _ draw: (CGContext) -> Void) -> CGImage {
            renderImage(width: w, height: h, scale: backingScale * 2) { g in draw(g) }!
        }
        var all: [CGImage] = []
        for (tail, open) in [(F(-0.6), true), (0.8, true), (0.2, false)] {
            all.append(picture(44, 36) { g in
                g.translateBy(x: 18, y: 35)
                self.drawCat(g, tail: tail, eyesOpen: open)
            })
        }
        all.append(picture(20, 16) { g in
            g.translateBy(x: 10, y: 8)
            let black = Self.night
            for side in [F(-1), 1] {
                for k in 0..<4 {
                    let a = F(k) * 0.42 - 0.6
                    g.bezier(black, 0.9, side * 2, -1 + F(k) * 0.8, side * 6, -4 + F(k) * 1.6 + a, side * 8, -2 + F(k) * 2, side * 9, 1 + F(k) * 1.8)
                }
            }
            g.fillEllipse(black, -3.4, -2.4, 6.8, 7.4)
            g.fillEllipse(black, -2.2, -5, 4.4, 4)
            g.fillEllipse(C(220, 40, 40), -1.4, -4, 1, 1); g.fillEllipse(C(220, 40, 40), 0.4, -4, 1, 1)
        })
        all.append(picture(2, 8) { g in g.fillRect(C(235, 235, 245, 170), 0.6, 0, 0.8, 8) })
        return all
    }

    /// A black cat sits on every window's top edge that is wide enough, at a place fixed on the window, swinging its
    /// tail and blinking now and then; and here and there a spider hangs under the edge on its thread, letting
    /// itself down and climbing up again. Both only where the edge is not hidden by a window in front. They are
    /// put into the pool the Day of the Dead's candles use (`pool`), between its begin and end.
    func addLedgeSpooks(to pool: DotPool) {
        if spookImages.isEmpty { spookImages = makeSpookImages() }
        let ox = screenBounds.minX, oy = screenBounds.minY
        for l in c.ledgeList {
            let dragged = l.moving && l.rect.size == l.settled.size
            guard !dragged, l.settled.width > 260,
                  l.settled.maxX > ox && l.settled.minX < ox + W && l.settled.minY > oy && l.settled.minY <= oy + H else { continue }
            let edge = l.settled.minY - oy
            let id = Int(l.id % 9973)
            // the cat: somewhere along the middle three fifths
            let catX = l.settled.minX + l.settled.width * (0.2 + F(id * 37 % 60) / 100)
            if catX >= ox - 30 && catX <= ox + W + 30, l.isVisible(catX) {
                let foot = edge - l.height(at: catX) * 0.55
                let t = c.time + Double(id % 17)
                // (it blinks for a moment every five seconds or so, and its tail goes over about once a second)
                let pose = t.truncatingRemainder(dividingBy: 5.3) < 0.18 ? 2 : (Int(t * 1.1) % 2)
                pool.add(spookImages[pose], x: catX - ox + 4, y: foot - 17, w: 44, h: 36, opacity: 1)
            }
            // the spiders: one about every 420 points, hanging under the edge
            let count = Int(l.settled.width / 420)
            for k in 0..<count {
                let gx = l.settled.minX + l.settled.width * (F(k) + 0.5 + F((id + k * 29) % 30 - 15) / 100) / F(count)
                guard gx >= ox - 20 && gx <= ox + W + 20, l.isVisible(gx) else { continue }
                let t = c.time * 0.5 + Double(k) * 2.1 + Double(id % 13)
                let drop = 26 + F(k % 3) * 14 + F(sin(t)) * 16
                pool.add(spookImages[4], x: gx - ox, y: edge + drop / 2, w: 2, h: drop, opacity: 1)
                pool.add(spookImages[3], x: gx - ox, y: edge + drop + 4, w: 20, h: 16, opacity: 1)
            }
        }
    }
}
