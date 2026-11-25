import AppKit

/// New Year (Theme.nytaar): each Christmas element in its New Year form, drawn here beside the overlay's own code
/// (Overlay.swift calls in where the theme branches). Confetti and streamers fall and pile up in the leaves' place
/// (DotImages.confetti); the rest is: a large clock on a stand that shows the real time and is decorated step by
/// step in the snowman's place, party guests in paper hats in the nisser's, a string of pennants and paper
/// lanterns in the lights', sparklers and party poppers on the window edges, and a small street sweeper in the
/// plow's. The rockets in Santa's place are particles, not a figure: Controller.launchVolley.
/// Nothing here shows or suggests drinking: no glasses, bottles or corks (REL 2026-11-25).
/// All figures are original and drawn in code, like the rest.
extension ScreenOverlay {
    private static let ink = C(38, 34, 52)
    private static let skins = [C(255, 214, 186), C(232, 180, 140), C(170, 118, 84), C(250, 224, 200)]
    private static let hairs = [C(92, 60, 36), C(40, 34, 36), C(214, 170, 90), C(150, 70, 40)]
    private static let partyClothes = [C(36, 60, 120), C(196, 42, 82), C(30, 120, 110), C(120, 60, 160)]
    /// The eight guests (Nisse.look): a dress or a jacket, and which clothes, skin, hair and hat; three of them
    /// have a balloon when their hands are empty. A guest keeps its look: what changes hands at a meeting is only
    /// the cracker. (The first version took the look from the cracker's number, so two guests who swapped
    /// crackers swapped skin, hair and hats as well; REL 2026-11-25.)
    private static let guestLooks: [(dress: Bool, cloth: Int, skin: Int, hair: Int, hat: Int, balloon: Int?)] = [
        (false, 0, 0, 0, 2, nil), (true, 1, 2, 1, 4, 3), (false, 2, 1, 3, 0, nil), (true, 3, 3, 2, 6, nil),
        (true, 1, 0, 1, 3, nil), (false, 0, 2, 1, 5, 4), (true, 3, 1, 0, 2, 6), (false, 2, 3, 2, 4, nil)]

    // ------------------------------------------------------------------ uret
    /// The time the clock shows: hour (with its fraction), minute (with its fraction) and second.
    private var clockHands: (hour: F, minute: F, second: F) {
        let p = Calendar.current.dateComponents([.hour, .minute, .second], from: c.clockNow)
        let s = F(p.second ?? 0), m = F(p.minute ?? 0) + s / 60
        return (F((p.hour ?? 0) % 12) + m / 60, m, s)
    }

    /// When the clock must be drawn again: every minute, and every second while its second hand is shown.
    var clockKey: String {
        let p = Calendar.current.dateComponents([.hour, .minute, .second], from: c.clockNow)
        return "\(p.hour ?? 0):\(p.minute ?? 0)" + (c.newYearClose ? ":\(p.second ?? 0)" : "")
    }

    /// One paper lantern: a round ribbed ball, `r` wide to each side of (cx, cy), glowing a little.
    func drawPaperLantern(_ g: CGContext, _ cx: F, _ cy: F, _ r: F, _ colour: CGColor, lit: Bool = false) {
        let ry = r * 1.08
        if lit {
            let rim = withAlpha(colour, 0)
            g.saveGState()
            g.addEllipse(in: CGRect(x: cx - r * 2, y: cy - r * 2, width: r * 4, height: r * 4)); g.clip()
            g.drawRadialGradient(CGGradient(colorsSpace: nil, colors: [withAlpha(C(255, 226, 150), 120), rim] as CFArray, locations: [0, 1])!,
                                 startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: r * 2, options: [])
            g.restoreGState()
        }
        g.fillEllipse(shade(colour, lit ? 0.95 : 0.7), cx - r, cy - ry, 2 * r, 2 * ry)
        g.fillEllipse(lit ? shade(colour, 1.25) : shade(colour, 0.88), cx - r * 0.62, cy - ry, r * 1.24, 2 * ry)
        g.strokeEllipse(shade(colour, 0.55), max(0.5, r * 0.07), cx - r * 0.26, cy - ry, r * 0.52, 2 * ry)
        if lit { g.fillEllipse(C(255, 244, 200, 170), cx - r * 0.3, cy - ry * 0.4, r * 0.6, ry * 0.9) }
        // the rings at top and bottom
        g.fillRect(Self.ink, cx - r * 0.36, cy - ry - r * 0.12, r * 0.72, r * 0.2)
        g.fillRect(Self.ink, cx - r * 0.3, cy + ry - r * 0.08, r * 0.6, r * 0.18)
    }

    /// A row of pennants hanging from a line that sags from (x0, y0) to (x1, y1).
    private func drawPennantLine(_ g: CGContext, _ x0: F, _ y0: F, _ x1: F, _ y1: F, sag: F, count: Int, size: F, first: Int = 0) {
        func at(_ u: F) -> (F, F) { (x0 + (x1 - x0) * u, y0 + (y1 - y0) * u + sag * 4 * u * (1 - u)) }
        g.setStrokeColor(C(60, 50, 60, 220)); g.setLineWidth(max(0.6, size * 0.09)); g.setLineCap(.round)
        g.beginPath()
        for k in 0...16 { let p = at(F(k) / 16); if k == 0 { g.move(to: CGPoint(x: p.0, y: p.1)) } else { g.addLine(to: CGPoint(x: p.0, y: p.1)) } }
        g.strokePath()
        for k in 0..<count {
            let u = (F(k) + 0.5) / F(count), a = at(u - 0.4 / F(count)), b = at(u + 0.4 / F(count))
            let col = Theme.confettiColours[(first + k * 2) % Theme.confettiColours.count]
            g.fillPoly(col, [a, b, ((a.0 + b.0) / 2, (a.1 + b.1) / 2 + size)])
            g.fillPoly(shade(col, 0.8), [((a.0 + b.0) / 2, a.1 * 0.5 + b.1 * 0.5), b, ((a.0 + b.0) / 2, (a.1 + b.1) / 2 + size)])
        }
    }

    /// New Year's form of the snowman: a large clock on a stand whose hands show the real time, decorated a step
    /// for every hour the app runs (Controller.clockSteps), in the same place and frame as the snowman. The clock
    /// itself stands from the first step: it is the countdown. Origin at the ground, y up is negative.
    func drawPartyClock(_ g: CGContext, _ stage: Int) {
        let iron = C(52, 62, 86), ironLight = C(92, 104, 132), face = C(250, 246, 232)
        let cy: F = -84, r: F = 30
        g.fillEllipse(C(20, 16, 30, 55), -44, -3, 88, 6)

        // the poles the pennants and lanterns hang on (steps 5–8)
        for (side, from) in [(F(-1), 5), (1, 6)] where stage >= from {
            g.line(C(120, 88, 56), 2.2, side * 54, 0, side * 54, -70, round: true)
            drawPennantLine(g, side * 54, -70, side * 24, -100, sag: 9, count: 4, size: 8, first: side < 0 ? 0 : 3)
        }
        // balloons tied to the foot (steps 9 and 10)
        for (side, from) in [(F(-1), 9), (1, 10)] where stage >= from {
            for (k, b) in [(F(30), F(-40)), (42, -54)].enumerated() {
                let col = Theme.confettiColours[(k * 3 + (side < 0 ? 2 : 4)) % Theme.confettiColours.count]
                g.bezier(C(230, 230, 240, 170), 0.7, side * 10, -5, side * 14, -22, side * (b.0 - 8), b.1 + 26, side * b.0, b.1 + 10)
                g.fillEllipse(col, side * b.0 - 8, b.1 - 10, 16, 20)
                g.fillPoly(col, [(side * b.0 - 2, b.1 + 9.5), (side * b.0 + 2, b.1 + 9.5), (side * b.0, b.1 + 12.5)])
                g.fillEllipse(C(255, 255, 255, 110), side * b.0 - 5, b.1 - 7, 4.5, 7)
            }
        }

        // the stand: a foot, a post and a collar under the clock
        let foot = CGMutablePath()
        foot.start(-22, 0); foot.curve(-20, -7, -8, -8, -5, -12); foot.to(5, -12); foot.curve(8, -8, 20, -7, 22, 0); foot.closeSubpath()
        g.fill(iron, foot)
        g.fillRect(iron, -3.6, -56, 7.2, 46)
        g.fillRect(ironLight, -3.6, -56, 2.2, 46)
        g.fillRect(iron, -6.5, -57, 13, 4)
        // paper streamers wound round the post (step 4)
        if stage >= 4 {
            for k in 0..<6 {
                let y = -14 - F(k) * 7
                g.fillPoly(Theme.confettiColours[(k * 2) % Theme.confettiColours.count], [(-3.8, y), (3.8, y - 4), (3.8, y - 7), (-3.8, y - 3)])
            }
            g.bezier(Theme.confettiColours[2], 1.6, 3.8, -16, 12, -12, 8, -4, 15, -1)
            g.bezier(Theme.confettiColours[0], 1.6, -3.8, -22, -12, -18, -9, -8, -16, -2)
        }

        // the clock: a dark case, a pale face with twelve marks, two hands
        g.fillEllipse(C(20, 16, 30, 40), -r - 3, cy - r - 1, 2 * r + 6, 2 * r + 6)
        g.fillEllipse(iron, -r - 2, cy - r - 2, 2 * r + 4, 2 * r + 4)
        if stage >= 2 { g.strokeEllipse(Self.gold, 2.4, -r - 0.6, cy - r - 0.6, 2 * r + 1.2, 2 * r + 1.2) }
        g.fillEllipse(face, -r + 3, cy - r + 3, 2 * r - 6, 2 * r - 6)
        g.strokeEllipse(C(214, 204, 180), 1, -r + 4.5, cy - r + 4.5, 2 * r - 9, 2 * r - 9)
        for k in 0..<12 {
            let a = F(k) * .pi / 6, big = k % 3 == 0
            let r0 = r - (big ? 11 : 8.5), r1 = r - 5.5
            g.line(Self.ink, big ? 2.2 : 1.1, sin(a) * r0, cy - cos(a) * r0, sin(a) * r1, cy - cos(a) * r1, round: true)
        }
        let t = clockHands
        func hand(_ turn: F, _ len: F, _ w: F, _ col: CGColor, tail: F = 3) {
            let a = turn * 2 * .pi
            g.line(col, w, -sin(a) * tail, cy + cos(a) * tail, sin(a) * len, cy - cos(a) * len, round: true)
        }
        hand(t.hour / 12, 13.5, 3, Self.ink)
        hand(t.minute / 60, 20.5, 2, Self.ink)
        // the second hand is only there in the last minute before midnight
        if c.newYearClose { hand(t.second / 60, 21.5, 0.9, C(214, 40, 60), tail: 5) }
        g.fillEllipse(Self.gold, -2.2, cy - 2.2, 4.4, 4.4)
        // small gold bulbs round the case (step 2)
        if stage >= 2 {
            for k in 0..<12 { let a = (F(k) + 0.5) * .pi / 6; g.fillEllipse(C(255, 232, 150), sin(a) * (r + 1) - 1.6, cy - cos(a) * (r + 1) - 1.6, 3.2, 3.2) }
        }
        // a bow under the clock (step 3)
        if stage >= 3 {
            let red = C(214, 40, 70)
            g.fillPoly(red, [(0, -52), (-12, -58), (-12, -46)]); g.fillPoly(red, [(0, -52), (12, -58), (12, -46)])
            g.fillPoly(shade(red, 0.8), [(-2, -51), (-9, -38), (-4, -39), (0, -49)]); g.fillPoly(shade(red, 0.8), [(2, -51), (9, -38), (4, -39), (0, -49)])
            g.fillEllipse(shade(red, 1.15), -3, -55, 6, 6)
        }
        // a paper lantern on each pole (steps 7 and 8)
        if stage >= 7 { drawPaperLantern(g, -54, -79, 8, C(233, 60, 80), lit: true) }
        if stage >= 8 { drawPaperLantern(g, 54, -79, 8, C(255, 150, 40), lit: true) }
        // a gold star on top (step 11)
        if stage >= 11 {
            g.fillPoly(shade(Self.gold, 0.8), starPoints(0, -121, 9.5, 4.2))
            g.fillPoly(C(255, 226, 120), starPoints(0, -121, 7.5, 3.4))
        }
        // two sparklers behind the star, burning (step 12)
        if stage >= 12 {
            for side in [F(-1), 1] {
                g.line(C(90, 90, 100), 1, side * 5, -112, side * 17, -127, round: true)
                let x = side * 17, y: F = -127
                for k in 0..<8 {
                    let a = F(k) * .pi / 4 + side * 0.3, len: F = k % 2 == 0 ? 6 : 3.6
                    g.line(k % 2 == 0 ? C(255, 240, 190) : C(255, 206, 110), 0.8, x, y, x + cos(a) * len, y + sin(a) * len, round: true)
                }
                g.fillEllipse(C(255, 252, 230), x - 1.6, y - 1.6, 3.2, 3.2)
            }
        }
    }

    // ------------------------------------------------------------------ festgæster
    /// New Year's walkers. They are nisser in everything but looks: they walk, stop, wave, cross to the next
    /// screen and meet to hand something over (a party cracker). Each wears a paper hat; half are in a dress and
    /// half in jacket and trousers, and now and then one has a balloon on a string. "Waving" is a jump with a
    /// blow on a party horn. Drawn like a nisse: feet at (0, 0), y up is negative, facing right.
    func drawGuest(_ g: CGContext, _ n: Nisse, _ frame: Int) {
        let p: F = n.state == 0 ? F(frame) / F(Self.walkFrames) * 4 * .pi : 0
        let standPhase: F = n.state == 1 ? F(frame) / F(Self.standFrames) * 2 * .pi : 0
        let wavePhase: F = n.state == 2 ? F(frame) / F(Self.waveFrames) * 2 * .pi : 0
        let walking = n.state == 0, waving = n.state == 2
        let legA: F = walking ? sin(p) * 0.55 : 0
        // the jump: off the ground and down again, once for every blow of the horn
        let jump: F = waving ? abs(sin(wavePhase)) * 6 : 0
        let bob: F = walking ? -abs(sin(p)) * 1.5 : -jump
        let who = Self.guestLooks[n.look % Self.guestLooks.count]
        let dress = who.dress
        let cloth = Self.partyClothes[who.cloth], skin = Self.skins[who.skin], hair = Self.hairs[who.hair]
        let hatCol = Theme.confettiColours[who.hat]
        let ink = Self.ink
        g.fillEllipse(C(30, 20, 40, 50), -10, -2 , 20, 4)

        // a balloon on a string, for some of those with empty hands
        if !n.carriesGift, let balloon = who.balloon {
            let sway = sin(walking ? p * 0.5 : standPhase) * 2
            let col = Theme.confettiColours[balloon]
            g.bezier(C(235, 235, 245, 180), 0.7, -8, -24 + bob, -10, -36 + bob, -15 - sway * 0.5, -40, -14 - sway, -50)
            g.fillEllipse(col, -21 - sway, -66, 14, 17)
            g.fillPoly(col, [(-15.6 - sway, -49.6), (-12.4 - sway, -49.6), (-14 - sway, -47.4)])
            g.fillEllipse(C(255, 255, 255, 120), -18.6 - sway, -63.5, 4, 6)
        }

        // legs: tights under a dress, trousers otherwise
        let legCol = dress ? C(60, 54, 80) : shade(cloth, 0.62)
        func leg(_ hx: F, _ a: F) {
            let spread: F = waving ? (hx < 0 ? -0.35 : 0.35) * (jump / 6) : 0
            let fx = hx + sin(a + spread) * 13, fy = -14 + bob + cos(a + spread) * 13
            g.line(legCol, dress ? 3 : 4, hx, -14 + bob, fx, fy, round: true)
            g.fillEllipse(ink, fx - 3, fy - 2, 8, 4.2)
        }
        leg(-2, legA)
        leg(2, -legA)

        g.translateBy(x: 0, y: bob)
        let backArm: F, frontArm: F
        if waving { backArm = -2.5 - sin(wavePhase) * 0.3; frontArm = 1.9 }
        else if n.carriesGift { backArm = 1.3; frontArm = 1.3 }
        else { backArm = -legA * 0.9; frontArm = legA * 0.9 }
        func arm(_ sx: F, _ sy: F, _ a: F) {
            let hx = sx + sin(a) * 10, hy = sy + cos(a) * 10
            g.line(shade(cloth, 0.86), 3.2, sx, sy, hx, hy, round: true)
            g.fillEllipse(skin, hx - 2.2, hy - 2.2, 4.4, 4.4)
        }
        arm(-1, -31, backArm)

        if dress {
            let d = CGMutablePath()
            d.start(-5, -33); d.to(5, -33); d.curve(6.5, -26, 10, -18, 11.5, -11); d.to(-11.5, -11); d.curve(-10, -18, -6.5, -26, -5, -33)
            d.closeSubpath()
            g.fill(cloth, d)
            g.line(shade(cloth, 1.35), 1.4, -6.2, -24, 6.2, -24)
            // a few sequins
            for (dx, dy) in [(F(-4), F(-15)), (2, -18), (6, -14), (-1, -13)] { g.fillEllipse(C(255, 240, 190, 220), dx, dy, 1.4, 1.4) }
        } else {
            g.fillRect(shade(cloth, 0.62), -5, -16, 10, 4)
            let j = CGMutablePath()
            j.start(-5.5, -33); j.to(5.5, -33); j.curve(6.5, -26, 6.5, -19, 6, -13); j.to(-6, -13); j.curve(-6.5, -19, -6.5, -26, -5.5, -33)
            j.closeSubpath()
            g.fill(cloth, j)
            // a shirt front and a bow tie
            g.fillPoly(C(248, 248, 252), [(1.5, -33), (5.5, -33), (4.5, -22)])
            g.fillPoly(hatCol, [(3.6, -31), (1.2, -32.6), (1.2, -29.4)]); g.fillPoly(hatCol, [(3.6, -31), (6, -32.6), (6, -29.4)])
        }

        // the party cracker: a wrapped tube with a twist at each end
        if n.carriesGift && !waving {
            let col = Self.gifts[n.giftIndex % Self.gifts.count]
            g.saveGState()
            g.translateBy(x: 12.5, y: -20)
            g.rotate(by: -0.35)
            g.fillPoly(col, [(-9, -3.4), (-5, -1.4), (-5, 1.4), (-9, 3.4)]); g.fillPoly(col, [(9, -3.4), (5, -1.4), (5, 1.4), (9, 3.4)])
            g.fillRect(col, -5, -2.8, 10, 5.6)
            g.fillRect(Self.gold, -1.4, -2.8, 2.8, 5.6)
            g.fillRect(C(255, 255, 255, 150), -4.6, -2.8, 1.2, 5.6); g.fillRect(C(255, 255, 255, 150), 3.4, -2.8, 1.2, 5.6)
            g.restoreGState()
        }

        // the head, looking a little the way it walks
        let sway = sin(walking ? p * 0.5 : standPhase) * 0.05
        g.saveGState()
        g.translateBy(x: 1, y: -40)
        g.rotate(by: sway - (waving ? 0.12 : 0))
        if dress {
            // long hair down the back
            let h = CGMutablePath()
            h.start(-6.8, -3); h.curve(-9.5, 2, -9, 9, -6, 11); h.to(-2.5, 6); h.curve(-4, 3, -4, 0, -3, -3); h.closeSubpath()
            g.fill(hair, h)
        }
        g.fillEllipse(skin, -6.5, -6.5, 13, 13)
        g.fillEllipse(hair, -7, -7.4, 12.4, 7.4)
        g.fillEllipse(skin, -3.4, -4.6, 9.6, 6.4)
        g.fillEllipse(C(250, 160, 150, 140), 1.6, 0.4, 3.6, 2.6)
        g.fillEllipse(ink, 1.6, -2.2, 1.9, 2.5)
        g.fillEllipse(ink, 4.5, -2.2, 1.5, 2.3)
        if waving {
            g.fillEllipse(ink, 4.6, 2.2, 2.2, 2.2)
        } else {
            g.bezier(ink, 0.8, 1.6, 2.6, 3, 4.2, 4.6, 4.2, 5.6, 2.6)
        }
        // the paper hat: a striped cone with a pompom, a little askew
        g.saveGState()
        g.translateBy(x: -0.6, y: -6)
        g.rotate(by: -0.16)
        g.fillPoly(hatCol, [(-5.4, 0.6), (5.4, 0.6), (0.4, -14.5)])
        g.fillPoly(shade(hatCol, 1.3), [(-3.5, -4.6), (3.6, -4.6), (2.7, -7.2), (-2.6, -7.2)])
        g.fillPoly(Self.gold, [(-5.4, 0.6), (5.4, 0.6), (4.7, -1.6), (-4.7, -1.6)])
        g.fillEllipse(C(255, 255, 255), -1.8, -17.6, 4.6, 4.6)
        g.restoreGState()
        // the party horn: rolled up at the mouth, and blown out straight with its tip still curled
        if waving {
            let out = 9 + abs(sin(wavePhase)) * 11
            g.line(C(250, 250, 250), 1.8, 5.6, 3.2, 8.5, 3.6, round: true)
            for k in 0..<Int(out / 3) {
                g.line(k % 2 == 0 ? C(233, 50, 90) : Self.gold, 3, 8.5 + F(k) * 3, 3.6 - F(k) * 0.25, 8.5 + F(k + 1) * 3, 3.6 - F(k + 1) * 0.25)
            }
            let ex = 8.5 + F(Int(out / 3)) * 3, ey = 3.6 - F(Int(out / 3)) * 0.25
            g.strokeEllipse(C(233, 50, 90), 1.8, ex - 0.4, ey - 5, 5, 5)
        }
        g.restoreGState()

        arm(1, -31, frontArm)
    }

    // ------------------------------------------------------------------ vimpler og papirlanterner
    static let lanternColours = [C(233, 60, 80), C(255, 150, 40), C(60, 170, 210), C(170, 100, 220)]

    /// What twinkles at a bulb's place (`idx` counts them): every other one a small gold bulb, the others the lit
    /// inside of a paper lantern. Drawn into the bulb's own box (26 × 28 units, the string at its top middle).
    func drawPartyBulb(_ g: CGContext, _ idx: Int, _ bw: F) {
        let S = self.S
        if idx % 2 == 0 {
            // a soft glow that fades out to nothing (a flat disc looked like a grey plate on a dark desktop)
            let mid = CGPoint(x: bw / 2, y: 9 * S)
            g.drawRadialGradient(CGGradient(colorsSpace: nil, colors: [C(255, 220, 120, 150), C(255, 200, 90, 0)] as CFArray, locations: [0, 1])!,
                                 startCenter: mid, startRadius: 0, endCenter: mid, endRadius: 12 * S, options: [])
            g.fillEllipse(C(255, 226, 130), bw / 2 - 3.5 * S, 3 * S, 7 * S, 11 * S)
            g.fillEllipse(C(255, 255, 255, 170), bw / 2 - 1.8 * S, 5 * S, 2.4 * S, 3.6 * S)
        } else {
            drawPaperLantern(g, bw / 2, 13.5 * S, 7 * S, Self.lanternColours[(idx / 2) % Self.lanternColours.count], lit: true)
        }
    }

    /// The string itself: pennants in the confetti's colours between the bulbs, and at the bulbs' places the unlit
    /// gold bulbs and paper lanterns (`bulbs` are those places; the lit ones are the twinkling layers over them).
    func drawPartyGarland(_ g: CGContext, span: F, sag: F, top: F, bulbs: [(F, F)]) {
        let S = self.S
        var n = 0
        var x0 = -span * 0.3
        while x0 < W {
            for k in 0..<12 where k % 3 != 1 {
                let u = (F(k) + 0.5) / 12, du: F = 0.026
                func at(_ u: F) -> (F, F) { (x0 + u * span, top + sag * (1 - (2 * u - 1) * (2 * u - 1))) }
                let a = at(u - du), b = at(u + du)
                let col = Theme.confettiColours[(n * 3 + k) % Theme.confettiColours.count]
                let tip = ((a.0 + b.0) / 2 + sin(F(n + k) * 2.3) * 1.5 * S, (a.1 + b.1) / 2 + 15 * S)
                g.fillPoly(col, [a, b, tip])
                g.fillPoly(shade(col, 0.8), [((a.0 + b.0) / 2, (a.1 + b.1) / 2), b, tip])
            }
            n += 1
            x0 += span
        }
        for (idx, (bx, by)) in bulbs.enumerated() {
            if idx % 2 == 0 {
                g.fillRect(C(70, 60, 50), bx - 2.5 * S, by, 5 * S, 4 * S)
                g.fillEllipse(C(150, 118, 50), bx - 3.5 * S, by + 3 * S, 7 * S, 11 * S)
            } else {
                g.line(C(60, 50, 60), 1 * S, bx, by, bx, by + 6 * S)
                drawPaperLantern(g, bx, by + 13.5 * S, 7 * S, Self.lanternColours[(idx / 2) % Self.lanternColours.count])
            }
        }
    }

    // ------------------------------------------------------------------ fejemaskine
    /// New Year's form of the snow plow: a small street sweeper the morning after, with a round brush turning in
    /// front of it and a blinking amber lamp on the roof. Facing +x, origin at the ground, the brush where the
    /// plow's blade would be. It has no horn and leaves no smoke.
    func drawSweeper(_ g: CGContext, _ ph: F) {
        let step = plowWheel
        let body = C(40, 150, 160), bodyDark = C(26, 104, 116), dark = C(46, 48, 58), glass = C(178, 214, 236)
        // the hopper behind, with a window the confetti shows in
        let hop = CGMutablePath()
        hop.start(-64, -16); hop.to(-64, -52); hop.curve(-64, -60, -58, -62, -52, -62); hop.to(14, -62); hop.to(14, -16); hop.closeSubpath()
        g.fill(body, hop)
        g.fillRect(bodyDark, -64, -22, 78, 6)
        g.fillRect(C(232, 240, 244), -52, -52, 34, 18)
        for k in 0..<14 {
            let col = Theme.confettiColours[(k * 3) % Theme.confettiColours.count]
            g.fillRect(col, -51 + F(k * 7 % 31), -39 + F(k * 5 % 4) - min(11, ph * 0.3) * F(k % 3) / 2, 3.6, 2.6)
        }
        g.setStrokeColor(bodyDark); g.setLineWidth(1.4); g.stroke(CGRect(x: -52, y: -52, width: 34, height: 18))
        // yellow and black warning stripes at the back
        for k in 0..<4 { g.fillPoly(k % 2 == 0 ? C(250, 204, 50) : dark, [(-64, -28 - F(k) * 7), (-58, -28 - F(k) * 7), (-58, -35 - F(k) * 7), (-64, -35 - F(k) * 7)]) }
        // the cab in front: big windows all round
        let cab = CGMutablePath()
        cab.start(14, -16); cab.to(14, -66); cab.to(40, -66); cab.curve(48, -66, 54, -52, 56, -36); cab.to(56, -16); cab.closeSubpath()
        g.fill(shade(body, 1.12), cab)
        let pane = CGMutablePath()
        pane.start(20, -38); pane.to(20, -61); pane.to(39, -61); pane.curve(45, -61, 49, -50, 51, -38); pane.closeSubpath()
        g.fill(glass, pane)
        g.line(C(255, 255, 255, 150), 2, 26, -57, 34, -42)
        g.line(bodyDark, 1.4, 33, -61, 33, -38)
        g.fillRect(bodyDark, 14, -22, 42, 6)
        // the driver: a head in a cap
        g.fillEllipse(C(232, 180, 140), 36, -55, 9, 10)
        g.fillRect(C(250, 150, 40), 35.5, -56.5, 10, 3.6)
        g.fillRect(C(250, 150, 40), 44, -54.4, 4, 1.6)
        // the amber lamp, blinking
        let blink = sin(step * 1.3) > 0
        if blink { g.fillEllipse(C(255, 190, 60, 90), 18, -80, 20, 20) }
        g.fillRect(dark, 24, -68, 8, 2.4)
        g.fillEllipse(blink ? C(255, 196, 70) : C(190, 120, 30), 24.5, -74, 7, 8)
        // a headlamp and the bumper
        g.fillEllipse(C(255, 244, 190), 53, -30, 4.4, 5.4)
        g.fillRect(dark, 50, -17, 10, 4)
        // wheels
        for wx in [F(-42), 34] {
            g.fillEllipse(dark, wx - 11, -20, 22, 22)
            g.fillEllipse(C(150, 154, 166), wx - 5, -14, 10, 10)
            for k in 0..<3 { let a = step + F(k) * 2.094; g.line(dark, 1.4, wx, -9, wx + cos(a) * 5, -9 + sin(a) * 5) }
        }
        // the suction mouth between the wheels
        g.fillPoly(dark, [(-18, -16), (10, -16), (14, -3), (-22, -3)])
        // the arm and the round brush in front, turning: seen from the side it is a flat disc of bristles
        g.line(dark, 3, 52, -16, 74, -9, round: true)
        g.fillEllipse(dark, 71, -12, 7, 5)
        g.fillEllipse(C(96, 84, 70), 58, -8, 36, 9)
        for k in 0..<14 {
            let a = step * 2.4 + F(k) * (2 * .pi / 14)
            let bx = 76 + cos(a) * 19, lift = sin(a) * 2.6
            g.line(sin(a) > 0 ? C(226, 190, 120) : C(170, 138, 84), 1.5, 76 + cos(a) * 10, -5 + lift * 0.4, bx, 0.5 + lift, round: true)
        }
        // confetti gathered in front of the brush
        for (i, lx) in [F(96), 103, 110].enumerated() where F(i) * 6 < ph {
            g.fillRect(Theme.confettiColours[(i * 2 + 1) % Theme.confettiColours.count], lx, -5 - F(i % 2) * 2.4, 5, 3.4)
        }
    }

    // ------------------------------------------------------------------ stjernekastere og bordbomber på vindueskanterne
    /// The pictures the window edges' things are made of: a sparkler's bare wire, its grey coat, and a party
    /// popper lying on its side with its streamers out. Drawn once, at twice the size they are shown at.
    private func makePartyImages() -> [CGImage] {
        func picture(_ w: F, _ h: F, _ draw: (CGContext) -> Void) -> CGImage {
            renderImage(width: w, height: h, scale: backingScale * 2) { g in draw(g) }!
        }
        var all: [CGImage] = []
        all.append(picture(2, 8) { g in g.fillRect(C(70, 66, 74), 0.5, 0, 1, 8) })
        all.append(picture(3, 8) { g in g.fillRect(C(150, 150, 160), 0.3, 0, 2.4, 8); g.fillRect(C(190, 190, 200), 0.3, 0, 0.9, 8) })
        for flip in [F(1), -1] {
            all.append(picture(46, 20) { g in
                g.translateBy(x: 23, y: 19)
                g.scaleBy(x: flip, y: 1)
                // the streamers thrown out of it
                let cols = Theme.confettiColours
                g.bezier(cols[2], 1.4, 4, -8, 10, -18, 14, -4, 21, -10)
                g.bezier(cols[3], 1.4, 4, -6, 12, -8, 12, -1, 20, -2)
                g.bezier(cols[0], 1.4, 4, -9, 6, -16, 12, -17, 15, -12)
                for (k, d) in [(F(9), F(-13)), (15, -6), (18, -15), (11, -3), (20, -7)].enumerated() { g.fillRect(cols[(k * 2 + 1) % cols.count], d.0, d.1, 2.4, 1.8) }
                // the popper: a cone with a gold collar and a string at its tip
                g.fillPoly(C(60, 150, 210), [(-17, -3.4), (4, -11.5), (4, -0.4)])
                g.fillPoly(C(40, 110, 170), [(-17, -3.4), (4, -5), (4, -0.4)])
                g.fillPoly(C(240, 196, 64), [(1, -10.4), (4, -11.5), (4, -0.4), (1, -1)])
                g.bezier(C(240, 240, 245), 0.8, -17, -3.4, -20, -2, -19, 0, -22, -0.6)
            })
        }
        return all
    }

    /// On the window edges: sparklers standing here and there, each burning down from its tip in about half a
    /// minute and replaced by a new one a little later; and on every edge that is wide enough a party popper
    /// lying with its streamers out. Both only where the edge is not hidden by a window in front. They are put
    /// into the pool the Day of the Dead's candles use (`pool`), between its begin and end.
    func addLedgeParty(to pool: DotPool) {
        if partyImages.isEmpty { partyImages = makePartyImages() }
        let ox = screenBounds.minX, oy = screenBounds.minY
        for l in c.ledgeList {
            let dragged = l.moving && l.rect.size == l.settled.size
            guard !dragged, l.settled.width > 200,
                  l.settled.maxX > ox && l.settled.minX < ox + W && l.settled.minY > oy && l.settled.minY <= oy + H else { continue }
            let edge = l.settled.minY - oy
            let id = Int(l.id % 9973)
            // the popper: somewhere along the middle three fifths
            let px = l.settled.minX + l.settled.width * (0.2 + F(id * 53 % 60) / 100)
            if l.settled.width > 320, px >= ox - 30 && px <= ox + W + 30, l.isVisible(px) {
                pool.add(partyImages[2 + id % 2], x: px - ox, y: edge - l.height(at: px) * 0.9 - 8, w: 46, h: 20, opacity: 1)
            }
            // the sparklers: one about every 300 points
            let count = max(1, Int(l.settled.width / 300))
            for k in 0..<count {
                let gx = l.settled.minX + l.settled.width * (F(k) + 0.5 + F((id + k * 29) % 30 - 15) / 100) / F(count)
                guard gx >= ox - 20 && gx <= ox + W + 20, l.isVisible(gx), abs(gx - px) > 34 else { continue }
                // 34 s of burning, then 8 s before the next one is lit
                let t = (c.time + Double(k) * 13.7 + Double(id % 41)).truncatingRemainder(dividingBy: 42)
                // (it stands in the confetti, most of its bare wire above it)
                let foot = edge - l.height(at: gx) * 0.75, x = gx - ox
                let tall: F = 34, bare: F = 12
                if t > 34 { continue }
                let left = (tall - bare) * F(1 - t / 34)   // the coat that has not burnt yet
                pool.add(partyImages[0], x: x, y: foot - tall / 2, w: 1.4, h: tall, opacity: 1)
                pool.add(partyImages[1], x: x, y: foot - bare - left / 2, w: 2.6, h: left, opacity: 1)
                // the burning point: a glint that flickers, and a few sparks thrown off it
                let by = foot - bare - left
                let f = c.time * 23 + Double(k) * 1.7
                let flicker = F(0.75 + 0.25 * sin(f) * sin(f * 0.37 + 1))
                pool.add(images.glow, x: x, y: by, w: 26 * flicker, h: 26 * flicker, opacity: 0.55)
                pool.add(images.whiteGlint, x: x, y: by, w: 15 * flicker, h: 15 * flicker, opacity: 1, rotation: F(f * 0.3))
                for j in 0..<4 {
                    // each spark flies out and falls for a third of a second, then the next one starts
                    let q = c.time * 3 + Double(j) * 0.25 + Double(k)
                    let u = F(q - q.rounded(.down)), seed = F(Int(q) * 7 + j * 13 + k)
                    let a = seed * 2.4, reach = 9 + (seed * 3.7).truncatingRemainder(dividingBy: 6)
                    pool.add(images.goldDot, x: x + cos(a) * reach * u, y: by + sin(a) * reach * u + 8 * u * u, w: 2, h: 2, opacity: 1 - u)
                }
            }
        }
    }
}
