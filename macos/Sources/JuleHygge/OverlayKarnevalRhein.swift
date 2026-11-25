import AppKit

/// The Rhineland's street carnival (Carnival.rhein): the German form of the Karneval theme, as it is held in
/// Cologne, Düsseldorf and Mainz. The same slots as Rio's (OverlayKarneval.swift, which calls in here), in other
/// clothes: confetti and wrapped sweets (Kamelle) fall, a parade wagon with a great jester's head is built in the
/// snowman's place, a tractor pulls a wagon with a prince and a brass band along the ground and sweets are thrown
/// from it, and the walkers are the people of a Rose Monday parade, marching in time: a dancing guard girl and a
/// guardsman in the red and white of the old town guards, a patchwork clown, the prince, a tuba player, a drummer,
/// a jester and a child dressed as a bee. A string of pennants and jester caps hangs along the top, and jester
/// caps and doughnuts lie on the window edges.
/// Nothing here shows or suggests drinking, the guardsman carries flowers where the real ones carry a wooden
/// rifle with a flower in it, and the wagon shows no caricature of anyone: REL's rulings and the app's own.
extension ScreenOverlay {
    private static let rRed = C(214, 32, 48), rWhite = C(250, 248, 242), rBlue = C(40, 90, 190), rYellow = C(255, 204, 40), rGreen = C(40, 150, 80)

    /// A jester's cap (Narrenkappe) with its points to both sides and a bell on each; its brow at (0, 0), `w`
    /// wide. `ring` swings the bells.
    private func drawJesterCap(_ g: CGContext, _ w: F, ring: F = 0) {
        let k = w / 20
        let parts: [(F, F, CGColor)] = [(-13, -9, Self.rRed), (0, -15, Self.rYellow), (13, -9, Self.rBlue)]
        for (tx, ty, col) in parts {
            let p = CGMutablePath()
            p.start(-9 * k + (tx > 0 ? 9 * k : 0) + (tx == 0 ? 4 * k : 0), 0)
            p.curve((tx - 4) * k, -4 * k, (tx - 2) * k, (ty + 2) * k, (tx + ring) * k, ty * k)
            p.curve((tx + 3) * k, (ty + 4) * k, (tx + 5) * k, -3 * k, (tx > 0 ? 10 : tx == 0 ? 5 : 1) * k, 0)
            p.closeSubpath()
            g.fill(col, p)
            g.fillEllipse(Self.cGold, (tx + ring) * k - 1.8 * k, ty * k - 1.8 * k, 3.6 * k, 3.6 * k)
        }
        g.fillRect(Self.rWhite, -10 * k, -1.6 * k, 20 * k, 3.2 * k)
    }

    // ------------------------------------------------------------------ pragtvogn
    /// The float in the snowman's place, the Rhineland's form (Prunkwagen): the same twelve steps as Rio's
    /// (drawFloat), in red and white with gold, and in the sun's place a great jester's head.
    func drawPrunkwagen(_ g: CGContext, _ stage: Int) {
        let wood = C(120, 84, 52), dark = C(46, 44, 60)
        let red = Self.rRed, white = Self.rWhite, gold = Self.cGold
        g.fillEllipse(C(20, 16, 30, 55), -58, -3, 116, 6)
        g.fillRect(wood, -54, -14, 108, 5)
        for wx in [F(-38), 0, 38] {
            g.fillEllipse(dark, wx - 7, -14, 14, 14)
            g.fillEllipse(C(150, 154, 166), wx - 2.5, -9.5, 5, 5)
        }
        // 2: the lower deck, in red and white lozenges
        if stage >= 2 {
            g.fillRect(white, -56, -30, 112, 17)
            for k in 0..<14 { g.fillPoly(red, [(-56 + F(k) * 8 + 4, -30), (-56 + F(k) * 8 + 8, -21.5), (-56 + F(k) * 8 + 4, -13), (-56 + F(k) * 8, -21.5)]) }
        }
        // 3: a skirt with a fringe
        if stage >= 3 {
            g.fillRect(red, -57, -14, 114, 10)
            for k in 0..<19 { g.fillPoly(k % 2 == 0 ? white : red, [(-57 + F(k) * 6, -4), (-51 + F(k) * 6, -4), (-54 + F(k) * 6, 1.5)]) }
        }
        // 4: the upper deck and steps
        if stage >= 4 {
            g.fillRect(red, -36, -48, 72, 18)
            g.fillRect(shade(red, 0.8), -36, -33, 72, 3)
            for k in 0..<3 { g.fillRect(white, -52 + F(k) * 5, -34 - F(k) * 4.6, 6, 4.6 * F(k + 1)) }
        }
        // 5: gold trim
        if stage >= 5 {
            g.fillRect(gold, -56, -31.5, 112, 2.4)
            g.fillRect(gold, -36, -49.5, 72, 2.4)
            for k in 0..<6 { g.fillPoly(gold, starPoints(-30 + F(k) * 12, -40, 3.4, 1.5)) }
        }
        // 6: two columns
        if stage >= 6 {
            for cx in [F(-30), 30] {
                g.fillRect(white, cx - 3.5, -86, 7, 37)
                for k in 0..<5 { g.fillPoly(red, [(cx - 3.5, -84 + F(k) * 7), (cx + 3.5, -87 + F(k) * 7), (cx + 3.5, -84 + F(k) * 7), (cx - 3.5, -81 + F(k) * 7)]) }
                g.fillRect(gold, cx - 5.5, -89, 11, 3.4)
                g.fillRect(gold, cx - 5.5, -52, 11, 3)
            }
        }
        // 7: a great jester's head between them, 8: its cap with bells, 9: its face
        if stage >= 7 {
            g.fillEllipse(C(236, 190, 150), -19, -100, 38, 40)
            g.fillPoly(white, [(-16, -64), (-8, -58), (0, -64), (8, -58), (16, -64), (12, -70), (-12, -70)])
        }
        if stage >= 8 {
            g.saveGState()
            g.translateBy(x: 0, y: -94)
            drawJesterCap(g, 40)
            g.restoreGState()
        }
        if stage >= 9 {
            g.fillEllipse(Self.cInk, -9, -88, 4.4, 5.4); g.fillEllipse(Self.cInk, 4.6, -88, 4.4, 5.4)
            g.fillEllipse(red, -3.4, -82, 6.8, 6.8)
            g.bezier(Self.cInk, 1.8, -10, -74, -5, -66, 5, -66, 10, -74)
            g.fillEllipse(C(250, 150, 140, 150), -15, -80, 6, 4.4); g.fillEllipse(C(250, 150, 140, 150), 9, -80, 6, 4.4)
        }
        // 10: big rosettes at both ends
        if stage >= 10 {
            for side in [F(-1), 1] {
                for k in 0..<8 {
                    let a = F(k) * .pi / 4
                    g.fillEllipse(k % 2 == 0 ? red : white, side * 47 + cos(a) * 8 - 5, -40 + sin(a) * 8 - 5, 10, 10)
                }
                g.fillEllipse(gold, side * 47 - 4.5, -44.5, 9, 9)
            }
        }
        // 11: coloured bulbs along the decks
        if stage >= 11 {
            let bulbs = [Self.rYellow, Self.rBlue, Self.rGreen, red]
            for k in 0..<12 { g.fillEllipse(bulbs[k % 4], -55 + F(k) * 9.6, -35.5, 4.4, 4.4) }
            for k in 0..<8 { g.fillEllipse(bulbs[(k + 2) % 4], -35 + F(k) * 9.4, -53.5, 4.2, 4.2) }
        }
        // 12: streamers and pennants
        if stage >= 12 {
            for side in [F(-1), 1] {
                g.bezier(Self.rYellow, 1.6, side * 30, -88, side * 44, -84, side * 40, -66, side * 52, -60)
                g.bezier(Self.rBlue, 1.6, side * 30, -88, side * 38, -76, side * 48, -78, side * 56, -70)
                g.line(wood, 1.2, side * 30, -89, side * 30, -108)
                g.fillPoly(red, [(side * 30, -108), (side * 30 + side * 13, -104), (side * 30, -100)])
                g.fillPoly(white, [(side * 30, -104), (side * 30 + side * 13, -104), (side * 30, -100)])
            }
        }
    }

    // ------------------------------------------------------------------ karnevalsoptoget
    /// The Rhineland's walkers: the people of a Rose Monday parade (Jecken), marching in time with the band. Who
    /// each one is follows the walker itself (Nisse.look). "Waving" is each one's own turn: the guard girl kicks
    /// high, the prince throws, the musicians lift their instruments, the clown and the jester jump.
    func drawJeck(_ g: CGContext, _ n: Nisse, _ p: F, _ standPhase: F, _ wavePhase: F) {
        let walking = n.state == 0, waving = n.state == 2
        let who = n.look % 8
        let beat: F = walking ? p : (waving ? wavePhase : standPhase)
        let legA: F = walking ? sin(p) * 0.5 : sin(beat) * 0.1
        let bob: F = -abs(sin(beat)) * (waving ? 3 : 1.2)
        let skin = Self.cSkins[(n.look * 3 + n.tunicIndex) % Self.cSkins.count]
        let ink = Self.cInk, red = Self.rRed, white = Self.rWhite, gold = Self.cGold
        g.fillEllipse(C(30, 20, 40, 50), -11, -2, 22, 4)

        // legs: white tights and boots for the guards and the prince, patchwork for the clown, stripes for the bee
        let patch = [Self.rYellow, Self.rBlue, Self.rGreen, red]
        let kick: F = who == 0 && waving ? abs(sin(wavePhase)) * 1.5 : 0
        for (i, (hx, a)) in [(F(-2), legA), (2, -legA - kick)].enumerated() {
            let fx = hx + sin(a) * 13, fy = -14 + bob + cos(a) * 13
            let col: CGColor = who <= 1 || who == 3 ? white : who == 2 ? patch[(i * 2 + n.tunicIndex) % 4] : who == 7 ? ink : who == 6 ? (i == 0 ? red : Self.rYellow) : C(40, 50, 90)
            g.line(col, who == 0 ? 3.2 : 4, hx, -14 + bob, fx, fy, round: true)
            g.fillEllipse(who <= 1 ? ink : who == 2 ? red : ink, fx - 3, fy - 2, who == 2 ? 10 : 8, 4.2)
        }
        g.translateBy(x: 0, y: bob)

        func arm(_ sx: F, _ sy: F, _ a: F, _ sleeve: CGColor) -> (F, F) {
            let hx = sx + sin(a) * 10, hy = sy + cos(a) * 10
            g.line(sleeve, 3.2, sx, sy, hx, hy, round: true)
            g.fillEllipse(skin, hx - 2.2, hy - 2.2, 4.4, 4.4)
            return (hx, hy)
        }
        func coat(_ col: CGColor, flare: F = 6) {
            let j = CGMutablePath()
            j.start(-5.5, -33); j.to(5.5, -33); j.curve(6.5, -26, 6.5, -19, flare, -13); j.to(-flare, -13); j.curve(-6.5, -19, -6.5, -26, -5.5, -33)
            j.closeSubpath()
            g.fill(col, j)
        }
        /// The three-cornered hat of the town guards, with a plume.
        func tricorn(_ g: CGContext, _ plume: CGColor) {
            g.fillPoly(ink, [(-9, -5.4), (0, -11), (9.4, -5.4), (6, -3.6), (-6, -3.6)])
            g.line(gold, 1, -8, -5.6, 0, -10.4); g.line(gold, 1, 0, -10.4, 8.6, -5.6)
            g.fillEllipse(plume, -5, -15, 5, 8)
        }
        let swing: F = walking ? sin(p) * 0.8 : sin(beat) * 0.3
        var hat: (CGContext) -> Void = { _ in }
        switch who {
        case 0:   // the dancing guard girl (Tanzmariechen): a red and white uniform with a short skirt, and a high kick
            _ = arm(-1, -31, waving ? -2.6 : -swing, red)
            coat(red, flare: 5)
            for k in 0..<3 { g.fillRect(gold, -3.4, -31 + F(k) * 4.4, 6.8, 1.2) }
            let sk = CGMutablePath()
            sk.start(-5, -17); sk.to(5, -17); sk.to(10, -10); sk.to(-10, -10); sk.closeSubpath()
            g.fill(white, sk)
            g.fillRect(red, -10, -11.4, 20, 1.6)
            _ = arm(1, -31, waving ? 2.6 : swing, red)
            hat = { g in tricorn(g, white); g.fillEllipse(C(214, 170, 90), -8.6, -3, 5, 9); g.fillEllipse(C(214, 170, 90), 4.6, -3, 5, 9) }
        case 1:   // a guardsman (in the red and white of the old town guards), with a bunch of flowers to give away
            _ = arm(-1, -31, -swing, red)
            coat(red)
            g.fillPoly(white, [(-5.5, -33), (5.5, -33), (0, -22)])
            g.fillRect(white, -6.4, -16.5, 12.8, 2.4)
            for k in 0..<3 { g.fillEllipse(gold, 2.4, -28 + F(k) * 4, 1.8, 1.8) }
            let (hx, hy) = arm(1, -31, waving ? 2.5 + sin(wavePhase) * 0.3 : 1.5, red)
            g.line(Self.rGreen, 1.4, hx, hy, hx + 1, hy - 7)
            for (dx, dy, col) in [(F(-2.5), F(-9), Self.rYellow), (2.5, -9.5, C(255, 120, 170)), (0, -12, white)] { g.fillEllipse(col, hx + dx - 2.2, hy + dy - 2.2, 4.4, 4.4) }
            hat = { g in tricorn(g, red) }
        case 2:   // a patchwork clown (Lappenclown): a suit of coloured rags, a ruff and a small hat
            _ = arm(-1, -31, waving ? -2.5 : -swing, patch[n.tunicIndex % 4])
            g.saveGState()
            let j = CGMutablePath()
            j.start(-6, -33); j.to(6, -33); j.curve(8.5, -25, 8.5, -18, 7, -12); j.to(-7, -12); j.curve(-8.5, -18, -8.5, -25, -6, -33)
            j.closeSubpath()
            g.addPath(j); g.clip()
            for row in 0..<6 { for col in 0..<5 { g.fillRect(patch[(row * 3 + col + n.tunicIndex) % 4], -9 + F(col) * 3.8, -34 + F(row) * 3.8, 3.8, 3.8) } }
            g.restoreGState()
            for k in 0..<5 { g.fillEllipse(white, -7 + F(k) * 3, -35.4, 4.4, 4) }
            _ = arm(1, -31, waving ? 2.5 : swing, patch[(n.tunicIndex + 2) % 4])
            hat = { g in
                g.fillEllipse(C(232, 120, 40), -9, -5, 5, 7); g.fillEllipse(C(232, 120, 40), 5, -5, 5, 7)
                g.fillRect(Self.rGreen, -3.4, -11.4, 6.8, 5); g.fillRect(Self.rGreen, -5.6, -7.4, 11.2, 1.6)
                g.fillEllipse(Self.rRed, 4.2, -0.6, 3.8, 3.8)
            }
        case 3:   // the prince: a gold tunic and a cape, pheasant feathers in his cap; he throws when he "waves"
            let cape = CGMutablePath()
            cape.start(-5, -33); cape.curve(-11, -26, -12, -18, -10, -11); cape.to(-3, -12); cape.to(-2, -32); cape.closeSubpath()
            g.fill(red, cape)
            _ = arm(-1, -31, -swing * 0.6, gold)
            coat(gold)
            g.fillRect(white, -6.4, -17, 12.8, 2.4)
            g.fillPoly(white, [(-4, -33), (4, -33), (0, -29)])
            let (hx, hy) = arm(1, -31, waving ? 2.2 + sin(wavePhase) * 0.9 : 1.3, gold)
            if waving { for k in 0..<3 { g.fillEllipse(patch[k], hx + 3 + F(k) * 3.4, hy - 5 - F(k) * 2.6, 2.6, 2.2) } }
            hat = { g in
                g.fillEllipse(red, -7, -9.4, 14, 5.6)
                for k in 0..<3 { g.bezier(C(170, 120, 60), 1.4, -3 + F(k) * 2, -8, -6 + F(k) * 2, -16, -10 + F(k) * 3, -19, -13 + F(k) * 4, -18) }
            }
        case 4:   // the tuba player: a blue band uniform, the horn round the body and its bell over the shoulder
            _ = arm(-1, -31, 1.4, Self.rBlue)
            coat(Self.rBlue)
            for k in 0..<3 { g.fillRect(gold, -3.4, -31 + F(k) * 4.4, 6.8, 1.1) }
            g.strokeEllipse(C(214, 170, 60), 3, -2, -30, 14, 16)
            let lift: F = waving ? abs(sin(wavePhase)) * 3 : abs(sin(beat)) * 1
            g.fillEllipse(C(214, 170, 60), -13, -47 - lift, 14, 12); g.fillEllipse(C(150, 110, 30), -10.5, -45 - lift, 9, 7.6)
            _ = arm(1, -31, 1.6, Self.rBlue)
            hat = { g in g.fillRect(Self.rBlue, -6, -11, 12, 5.4); g.fillRect(ink, -1, -6.2, 9, 1.6); g.fillEllipse(gold, -1.6, -10, 3.2, 3.2) }
        case 5:   // the drummer: the same uniform, a side drum on a sling and two sticks
            _ = arm(-1, -31, 1.3 + abs(sin(beat + 1.5)) * 0.6, Self.rBlue)
            coat(Self.rBlue)
            g.line(white, 1.2, -4, -33, 6, -22)
            g.fillRect(white, 3, -24, 12, 10); g.fillRect(red, 3, -24, 12, 2); g.fillRect(red, 3, -16, 12, 2)
            for k in 0..<3 { g.line(red, 0.8, 5 + F(k) * 4, -22, 7 + F(k) * 4, -16) }
            let (hx, hy) = arm(1, -31, 1.4 + abs(sin(beat)) * 0.7, Self.rBlue)
            g.line(C(150, 110, 60), 1.2, hx, hy, hx + 5, hy + 3)
            hat = { g in g.fillRect(Self.rBlue, -6, -11, 12, 5.4); g.fillRect(ink, -1, -6.2, 9, 1.6); g.fillEllipse(gold, -1.6, -10, 3.2, 3.2) }
        case 6:   // the jester: half red and half yellow, with the cap and its bells, and a jump
            _ = arm(-1, -31, waving ? -2.5 : -swing, red)
            g.saveGState()
            let j = CGMutablePath()
            j.start(-5.5, -33); j.to(5.5, -33); j.curve(6.5, -26, 6.5, -19, 6, -13); j.to(-6, -13); j.curve(-6.5, -19, -6.5, -26, -5.5, -33)
            j.closeSubpath()
            g.addPath(j); g.clip()
            g.fillRect(red, -8, -34, 8, 22); g.fillRect(Self.rYellow, 0, -34, 8, 22)
            g.restoreGState()
            for k in 0..<4 { g.fillPoly(k % 2 == 0 ? Self.rYellow : red, [(-6 + F(k) * 3, -13), (-3 + F(k) * 3, -13), (-4.5 + F(k) * 3, -9.6)]) }
            _ = arm(1, -31, waving ? 2.5 : swing, Self.rYellow)
            let ring = sin(beat * 2) * 1.2
            hat = { g in g.translateBy(x: 0, y: -5); self.drawJesterCap(g, 15, ring: ring) }
        default:  // a child dressed as a bee: yellow and black stripes, small wings and feelers
            g.fillEllipse(C(255, 255, 255, 170), -13, -34, 10, 13); g.fillEllipse(C(255, 255, 255, 130), -11, -27, 8, 10)
            _ = arm(-1, -31, waving ? -2.5 : -swing, ink)
            g.fillEllipse(Self.rYellow, -7.5, -34, 15, 22)
            g.saveGState()
            g.addEllipse(in: CGRect(x: -7.5, y: -34, width: 15, height: 22)); g.clip()
            for k in 0..<3 { g.fillRect(ink, -8, -29 + F(k) * 6.4, 16, 3) }
            g.restoreGState()
            _ = arm(1, -31, waving ? 2.5 : swing, ink)
            hat = { g in
                g.fillEllipse(ink, -7, -8.6, 14, 6)
                for side in [F(-1), 1] { g.line(ink, 0.9, side * 3, -8, side * 5, -14); g.fillEllipse(Self.rYellow, side * 5 - 1.5, -16, 3, 3) }
            }
        }

        // a bag of sweets in the hand of those who carry something: it is what changes hands at a meeting
        if n.carriesGift && !waving && who != 1 && who != 4 && who != 5 {
            let col = Self.gifts[n.giftIndex % Self.gifts.count]
            g.fillPoly(col, [(8, -22), (15, -22), (16.5, -14), (6.5, -14)])
            g.fillPoly(shade(col, 1.25), [(9.4, -22), (11.5, -25.5), (13.6, -22)])
            g.fillEllipse(C(255, 255, 255, 140), 9, -20, 2.6, 2.6)
        }

        // the head, nodding with the beat
        g.saveGState()
        g.translateBy(x: 1, y: -40)
        g.rotate(by: sin(beat) * 0.06)
        g.fillEllipse(skin, -6.5, -6.5, 13, 13)
        g.fillEllipse(C(250, 150, 140, 130), 1.6, 0.4, 3.6, 2.6)
        g.fillEllipse(ink, 1.6, -2.2, 1.9, 2.5)
        g.fillEllipse(ink, 4.5, -2.2, 1.5, 2.3)
        g.bezier(ink, 0.8, 1.2, 2.2, 2.8, 4.6, 4.8, 4.6, 5.8, 2.2)
        hat(g)
        g.restoreGState()
    }

    // ------------------------------------------------------------------ festvogn
    /// The Rhineland's wagon in Santa's place: a tractor pulling a decorated wagon, the prince on it throwing
    /// sweets and a small brass band playing. The sweets themselves are thrown by the Controller as sparks
    /// (updateSanta). Facing +x, origin at the ground under its middle; `t` is the trip's clock.
    func drawFestwagen(_ g: CGContext, _ t: F) {
        let beat = F(c.beatCount) * .pi
        let dark = C(46, 44, 60), red = Self.rRed, white = Self.rWhite, gold = Self.cGold
        let roll = t * 5
        // the tractor: green, a big wheel behind and a small one in front, an exhaust pipe that shakes
        g.fillRect(dark, 86, -56 + sin(t * 20) * 0.6, 3, 16)
        let hood = CGMutablePath()
        hood.start(54, -18); hood.to(54, -40); hood.to(98, -40); hood.curve(104, -40, 106, -32, 106, -24); hood.to(106, -18); hood.closeSubpath()
        g.fill(Self.rGreen, hood)
        g.fillRect(shade(Self.rGreen, 0.8), 54, -22, 52, 4)
        g.fillRect(C(178, 214, 236), 56, -62, 20, 22); g.fillRect(Self.rGreen, 54, -66, 24, 4); g.fillRect(Self.rGreen, 54, -62, 2, 24); g.fillRect(Self.rGreen, 76, -62, 2, 24)
        g.fillEllipse(C(236, 190, 150), 61, -57, 8, 9); g.fillRect(C(60, 80, 120), 60, -58, 10, 3)
        for (wx, r) in [(F(64), F(17)), (98, 10)] {
            g.fillEllipse(dark, wx - r, -2 * r, 2 * r, 2 * r)
            g.fillEllipse(Self.rYellow, wx - r * 0.5, -r * 1.5, r, r)
            for k in 0..<4 { let a = roll * (17 / r) + F(k) * .pi / 2; g.line(dark, 1.4, wx, -r, wx + cos(a) * r * 0.5, -r + sin(a) * r * 0.5) }
        }
        g.line(dark, 2.4, 40, -16, 54, -18, round: true)
        // the wagon: a deck with a railing in red and white lozenges, a fringe, and wheels
        for wx in [F(-84), -6] { g.fillEllipse(dark, wx - 10, -20, 20, 20); g.fillEllipse(C(160, 164, 176), wx - 4, -14, 8, 8) }
        g.fillRect(white, -106, -38, 146, 22)
        for k in 0..<18 { g.fillPoly(red, [(-106 + F(k) * 8.1 + 4, -38), (-106 + F(k) * 8.1 + 8.1, -27), (-106 + F(k) * 8.1 + 4, -16), (-106 + F(k) * 8.1, -27)]) }
        g.fillRect(gold, -106, -40, 146, 3)
        for k in 0..<24 { g.fillPoly(k % 2 == 0 ? red : white, [(-106 + F(k) * 6.1, -16), (-99.9 + F(k) * 6.1, -16), (-103 + F(k) * 6.1, -11)]) }
        // at the back a great jester's cap on a post, its bells swinging with the beat
        g.fillRect(C(150, 110, 60), -96, -78, 4, 40)
        g.saveGState()
        g.translateBy(x: -94, y: -78)
        drawJesterCap(g, 34, ring: sin(beat) * 1.4)
        g.restoreGState()
        // on the deck: three of the band, and the prince at the front with his arm up
        let band: [(F, Int)] = [(-66, 0), (-44, 1), (-22, 2)]
        for (i, (x, kind)) in band.enumerated() {
            let b = sin(beat + F(i) * 0.5 * .pi)
            g.saveGState()
            g.translateBy(x: 0, y: -40 - abs(b) * 1.6)
            drawSmallPerson(g, x, 34, cloth: Self.rBlue, skin: Self.cSkins[(i * 2) % Self.cSkins.count], legs: dark, sway: b * 0.06, arm: 1.5 + abs(b) * 0.4)
            switch kind {
            case 0: g.strokeEllipse(C(214, 170, 60), 2.4, x - 3, -24, 12, 13); g.fillEllipse(C(214, 170, 60), x - 9, -40, 12, 10)       // a tuba
            case 1: g.line(C(214, 170, 60), 2.2, x + 3, -24, x + 15, -26); g.fillPoly(C(214, 170, 60), [(x + 14, -29.5), (x + 19, -31), (x + 19, -21), (x + 14, -22.5)])   // a trumpet
            default: g.fillRect(white, x + 4, -20, 10, 9); g.fillRect(red, x + 4, -20, 10, 1.8)   // a drum
            }
            g.fillRect(Self.rBlue, x - 5, -37.5, 11, 4)
            g.restoreGState()
        }
        let wave = sin(beat * 0.5)
        g.saveGState()
        g.translateBy(x: 0, y: -40)
        drawSmallPerson(g, 12, 38, cloth: gold, skin: Self.cSkins[0], legs: white, sway: wave * 0.08, arm: 2.4 + wave * 0.5)
        g.fillEllipse(red, 6, -41, 13, 5)
        g.bezier(C(170, 120, 60), 1.2, 10, -40, 7, -48, 3, -51, 0, -50)
        g.restoreGState()
        // bunting from the cap's post to the front
        for k in 0..<9 {
            let u = (F(k) + 0.5) / 9
            let x = -92 + u * 126, y = -76 + 22 * u + 12 * u * (1 - u) * 4 * 0.3
            g.fillPoly([red, white, Self.rYellow][k % 3], [(x - 4, y), (x + 4, y + 1), (x, y + 9)])
        }
        g.bezier(dark, 0.8, -92, -76, -50, -62, -8, -56, 34, -54)
    }

    // ------------------------------------------------------------------ vimpler og narrehuer
    /// The Rhineland's garland along the string: pennants in red, white and yellow, and a small jester's cap
    /// hanging between every two bulbs. (The bulbs are the Christmas lights' own.)
    func drawRhenishGarland(_ g: CGContext, span: F, sag: F, top: F) {
        let S = self.S
        let cols = [Self.rRed, Self.rWhite, Self.rYellow]
        var n = 0
        var x0 = -span * 0.3
        while x0 < W {
            func at(_ u: F) -> (F, F) { (x0 + u * span, top + sag * (1 - (2 * u - 1) * (2 * u - 1))) }
            for k in 0..<16 where k % 4 != 0 {
                let u = (F(k) + 0.5) / 16
                let a = at(u - 0.022), b = at(u + 0.022)
                let col = cols[(k + n) % 3]
                let tip = ((a.0 + b.0) / 2, (a.1 + b.1) / 2 + 13 * S)
                g.fillPoly(col, [a, b, tip])
                g.fillPoly(shade(col, 0.82), [((a.0 + b.0) / 2, (a.1 + b.1) / 2), b, tip])
            }
            for b in 0..<4 {
                let p = at(F(b) / 4)
                g.line(C(60, 50, 60), 0.9 * S, p.0, p.1, p.0, p.1 + 7 * S)
                g.saveGState()
                g.translateBy(x: p.0, y: p.1 + 17 * S)
                g.rotate(by: sin(F(n * 4 + b) * 1.9) * 0.14)
                drawJesterCap(g, 13 * S)
                g.restoreGState()
            }
            n += 1
            x0 += span
        }
    }

    // ------------------------------------------------------------------ narrehuer og berlinere på vindueskanterne
    /// The pictures on the window edges: a jester's cap lying there, its bells still or ringing, and a doughnut
    /// (the carnival's own cake, with sugar on top) on a paper napkin. Drawn once, at twice the size shown.
    private func makeCapImages() -> [CGImage] {
        var all: [CGImage] = []
        for ring in [F(0), 1.6, -1.6] {
            all.append(renderImage(width: 44, height: 30, scale: backingScale * 2) { g in
                g.translateBy(x: 22, y: 27)
                self.drawJesterCap(g, 26, ring: ring)
            }!)
        }
        all.append(renderImage(width: 30, height: 20, scale: backingScale * 2) { g in
            g.fillPoly(C(250, 248, 242), [(1, 19), (15, 14), (29, 19), (22, 20), (8, 20)])
            g.fillEllipse(C(206, 140, 70), 5, 6, 20, 13)
            g.fillEllipse(C(232, 180, 110), 6, 6, 18, 8)
            g.fillEllipse(C(255, 255, 255, 220), 8, 5.6, 14, 4.6)
            g.fillEllipse(C(214, 32, 48), 21.6, 11, 3.4, 2.6)
        }!)
        return all
    }

    /// On the window edges in the Rhineland's carnival: a jester's cap about every 380 points, its bells ringing
    /// for a moment now and then, and a doughnut beside every other one. Only where the edge is not hidden.
    func addLedgeCaps(to pool: DotPool) {
        if capImages.isEmpty { capImages = makeCapImages() }
        let ox = screenBounds.minX, oy = screenBounds.minY
        for l in c.ledgeList {
            let dragged = l.moving && l.rect.size == l.settled.size
            guard !dragged, l.settled.width > 200,
                  l.settled.maxX > ox && l.settled.minX < ox + W && l.settled.minY > oy && l.settled.minY <= oy + H else { continue }
            let edge = l.settled.minY - oy
            let id = Int(l.id % 9973)
            let count = max(1, Int(l.settled.width / 380))
            for k in 0..<count {
                let gx = l.settled.minX + l.settled.width * (F(k) + 0.5 + F((id + k * 31) % 40 - 20) / 100) / F(count)
                guard gx >= ox - 30 && gx <= ox + W + 30, l.isVisible(gx) else { continue }
                let t = c.time + Double(k) * 3.7 + Double(id % 23)
                // (the bells ring for half a second about every seven, in time with the band)
                let rings = t.truncatingRemainder(dividingBy: 7.3) < 0.6
                let pose = rings ? 1 + Int(c.beatCount * 2) % 2 : 0
                let y = edge - l.height(at: gx) * 0.8
                pool.add(capImages[pose], x: gx - ox, y: y - 12, w: 44, h: 30, opacity: 1)
                if (id + k) % 2 == 0, l.isVisible(gx + 40) { pool.add(capImages[3], x: gx - ox + 40, y: y - 8, w: 30, h: 20, opacity: 1) }
            }
        }
    }
}
