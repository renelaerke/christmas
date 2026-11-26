import AppKit

/// Carnival (Theme.karneval): Rio's parade, each Christmas element in its carnival form, drawn here beside the
/// overlay's own code (Overlay.swift calls in where the theme branches). Confetti, streamers and feathers fall and
/// pile up in the leaves' place (DotImages.carnival); the rest is: a carnival float built step by step in the
/// snowman's place, a truck with a band on it that drives along the ground in Santa's, the people of a samba
/// parade in the nisser's (walking in time with the drums: Controller.beat), a fringe garland with masks in the
/// lights', toucans on the window edges, and the street sweepers of Ash Wednesday in the plow's.
/// Nothing here shows or suggests drinking (REL 2026-11-25). The figures are original, clothed and friendly, with
/// the range of skin tones New Year's guests have. The camera has nothing yet: see docs/karneval-ide.md.
extension ScreenOverlay {
    static let cInk = C(38, 34, 52), cGold = C(240, 196, 64)
    static let cSkins = [C(255, 214, 186), C(206, 150, 106), C(140, 92, 62), C(236, 190, 150), C(110, 72, 50)]
    static let carnivalColours = [C(255, 64, 129), C(0, 176, 140), C(255, 196, 0), C(60, 120, 230), C(160, 80, 220), C(255, 120, 30), C(40, 190, 80)]

    // ------------------------------------------------------------------ small people, shared by float, truck and sweepers
    /// A small person standing at (x, 0), `h` tall: legs, a body in `cloth`, a head. `sway` leans it; `arm` is
    /// the near arm's angle from straight down (radians, positive forward). For the band and the sweepers.
    func drawSmallPerson(_ g: CGContext, _ x: F, _ h: F, cloth: CGColor, skin: CGColor, legs: CGColor, sway: F, arm: F, step: F = 0) {
        let k = h / 40
        g.saveGState()
        g.translateBy(x: x, y: 0)
        g.scaleBy(x: k, y: k)
        g.line(legs, 3.4, -2, -14, -2 + sin(step) * 5, 0, round: true)
        g.line(legs, 3.4, 2, -14, 2 - sin(step) * 5, 0, round: true)
        g.translateBy(x: 0, y: -14)
        g.rotate(by: sway)
        let body = CGMutablePath()
        body.start(-5.5, -18); body.to(5.5, -18); body.curve(6.5, -11, 6.5, -5, 6, 1); body.to(-6, 1); body.curve(-6.5, -5, -6.5, -11, -5.5, -18)
        body.closeSubpath()
        g.fill(cloth, body)
        g.fillEllipse(skin, -5.5, -30, 12, 12)
        g.fillEllipse(Self.cInk, 2, -25.6, 1.8, 2.2)
        g.line(shade(cloth, 0.85), 3, 0, -15, sin(arm) * 9, -15 + cos(arm) * 9, round: true)
        g.fillEllipse(skin, sin(arm) * 9 - 2, -15 + cos(arm) * 9 - 2, 4, 4)
        g.restoreGState()
    }

    // ------------------------------------------------------------------ karnevalsvogn
    /// Carnival's form of the snowman: a float (carro alegórico) being built, a step for every hour the app runs
    /// (Controller.floatSteps), in the same place and frame as the snowman. Origin at the ground, y up is negative.
    func drawFloat(_ g: CGContext, _ stage: Int) {
        if c.carnival == .rhein { drawPrunkwagen(g, stage); return }
        let cols = Self.carnivalColours
        let wood = C(120, 84, 52), dark = C(46, 44, 60)
        g.fillEllipse(C(20, 16, 30, 55), -58, -3, 116, 6)
        // 1: the chassis on its wheels
        g.fillRect(wood, -54, -14, 108, 5)
        for wx in [F(-38), 0, 38] {
            g.fillEllipse(dark, wx - 7, -14, 14, 14)
            g.fillEllipse(C(150, 154, 166), wx - 2.5, -9.5, 5, 5)
        }
        // 2: the lower deck
        if stage >= 2 {
            g.fillRect(cols[3], -56, -30, 112, 17)
            g.fillRect(shade(cols[3], 0.8), -56, -17, 112, 4)
        }
        // 3: a skirt with a fringe that hides the wheels
        if stage >= 3 {
            g.fillRect(cols[0], -57, -14, 114, 10)
            for k in 0..<19 { g.fillPoly(k % 2 == 0 ? cols[2] : cols[0], [(-57 + F(k) * 6, -4), (-51 + F(k) * 6, -4), (-54 + F(k) * 6, 1.5)]) }
        }
        // 4: the upper deck, and steps up to it
        if stage >= 4 {
            g.fillRect(cols[1], -36, -48, 72, 18)
            g.fillRect(shade(cols[1], 0.8), -36, -33, 72, 3)
            for k in 0..<3 { g.fillRect(C(250, 240, 220), -52 + F(k) * 5, -34 - F(k) * 4.6, 6, 4.6 * F(k + 1)) }
        }
        // 5: gold trim along both decks
        if stage >= 5 {
            g.fillRect(Self.cGold, -56, -31.5, 112, 2.4)
            g.fillRect(Self.cGold, -36, -49.5, 72, 2.4)
            for k in 0..<9 { g.fillEllipse(Self.cGold, -52 + F(k) * 13, -25, 4, 4) }
        }
        // 6: two columns
        if stage >= 6 {
            for cx in [F(-30), 30] {
                g.fillRect(C(250, 244, 230), cx - 3.5, -86, 7, 37)
                g.fillRect(C(222, 212, 192), cx + 1, -86, 2.5, 37)
                g.fillRect(Self.cGold, cx - 5.5, -89, 11, 3.4)
                g.fillRect(Self.cGold, cx - 5.5, -52, 11, 3)
            }
        }
        // 7: a great sun between them, 8: its rays, 9: its face
        if stage >= 8 {
            for k in 0..<16 {
                let a = F(k) * .pi / 8, r0: F = 19, r1: F = k % 2 == 0 ? 32 : 26
                g.fillPoly(k % 2 == 0 ? C(255, 170, 30) : Self.cGold,
                           [(cos(a - 0.14) * r0, -84 + sin(a - 0.14) * r0), (cos(a) * r1, -84 + sin(a) * r1), (cos(a + 0.14) * r0, -84 + sin(a + 0.14) * r0)])
            }
        }
        if stage >= 7 {
            g.fillEllipse(C(255, 170, 30), -21, -105, 42, 42)
            g.fillEllipse(C(255, 214, 80), -18, -102, 36, 36)
        }
        if stage >= 9 {
            g.fillEllipse(Self.cInk, -8.5, -89, 4, 5); g.fillEllipse(Self.cInk, 4.5, -89, 4, 5)
            g.bezier(Self.cInk, 1.6, -9, -79, -4, -72, 4, -72, 9, -79)
            g.fillEllipse(C(255, 140, 90, 150), -14, -82, 6, 4); g.fillEllipse(C(255, 140, 90, 150), 8, -82, 6, 4)
        }
        // 10: fans of feathers at both ends
        if stage >= 10 {
            for side in [F(-1), 1] {
                for k in 0..<5 {
                    let a = -F.pi / 2 + side * (0.25 + F(k) * 0.26)
                    let col = cols[(k + (side < 0 ? 0 : 3)) % cols.count]
                    let tx = side * 46 + cos(a) * 30, ty = -32 + sin(a) * 30
                    g.bezier(shade(col, 0.8), 1.2, side * 46, -32, side * 46 + cos(a) * 12, -32 + sin(a) * 14, tx - side * 2, ty + 4, tx, ty)
                    g.saveGState()
                    g.translateBy(x: side * 46 + cos(a) * 20, y: -32 + sin(a) * 20)
                    g.rotate(by: a)
                    g.fillEllipse(col, -11, -3.4, 22, 6.8)
                    g.restoreGState()
                }
            }
        }
        // 11: coloured bulbs along the decks
        if stage >= 11 {
            for k in 0..<12 { g.fillEllipse(cols[k % cols.count], -55 + F(k) * 9.6, -35.5, 4.4, 4.4) }
            for k in 0..<8 { g.fillEllipse(cols[(k + 2) % cols.count], -35 + F(k) * 9.4, -53.5, 4.2, 4.2) }
        }
        // 12: streamers from the columns, and a pennant on each
        if stage >= 12 {
            for side in [F(-1), 1] {
                g.bezier(cols[0], 1.6, side * 30, -88, side * 44, -84, side * 40, -66, side * 52, -60)
                g.bezier(cols[2], 1.6, side * 30, -88, side * 38, -76, side * 48, -78, side * 56, -70)
                g.line(wood, 1.2, side * 30, -89, side * 30, -108)
                g.fillPoly(cols[side < 0 ? 4 : 5], [(side * 30, -108), (side * 30 + side * 13, -104), (side * 30, -100)])
            }
        }
    }

    // ------------------------------------------------------------------ sambaoptoget
    /// Carnival's walkers: the people of a samba parade. They are nisser in everything but looks (they walk, stop,
    /// wave, cross to the next screen and meet), and who each one is follows the walker itself (Nisse.look), not
    /// what it carries: the flag bearer and her escort, a baiana in a wide skirt, a dancer in a feather headdress,
    /// two drummers, Pierrot and Harlequin. They step, stand and wave in time with the drums: the frames are
    /// chosen from the controller's beat (renderNisser), so every one on every screen moves together.
    /// Drawn like a nisse: feet at (0, 0), y up is negative, facing right.
    func drawReveller(_ g: CGContext, _ n: Nisse, _ frame: Int) {
        let p: F = n.state == 0 ? F(frame) / F(Self.walkFrames) * 4 * .pi : 0
        let standPhase: F = n.state == 1 ? F(frame) / F(Self.standFrames) * 2 * .pi : 0
        let wavePhase: F = n.state == 2 ? F(frame) / F(Self.waveFrames) * 2 * .pi : 0
        let walking = n.state == 0, waving = n.state == 2
        if c.carnival == .rhein { drawJeck(g, n, p, standPhase, wavePhase); return }
        let who = n.look % 8
        let beat: F = walking ? p : (waving ? wavePhase : standPhase)
        let legA: F = walking ? sin(p) * 0.5 : sin(beat) * 0.12
        // everyone bounces on the beat, also standing still
        let bob: F = -abs(sin(beat)) * (waving ? 3 : 1.5)
        let skin = Self.cSkins[(n.look * 3 + n.tunicIndex) % Self.cSkins.count]
        let cols = Self.carnivalColours, ink = Self.cInk
        let own = cols[(n.look + n.tunicIndex * 2) % cols.count], second = cols[(n.look + n.tunicIndex * 2 + 3) % cols.count]
        g.fillEllipse(C(30, 20, 40, 50), -11, -2, 22, 4)

        // what each one wears below the waist: a wide skirt to the ground, or legs
        let wideSkirt = who == 0 || who == 2
        let spin: F = waving ? abs(sin(wavePhase)) : 0
        if !wideSkirt {
            let legCol: CGColor = who == 1 || who == 6 ? C(248, 246, 240) : who == 7 ? second : who == 3 ? skin : shade(own, 0.6)
            for (hx, a) in [(F(-2), legA), (2, -legA)] {
                let fx = hx + sin(a) * 13, fy = -14 + bob + cos(a) * 13
                g.line(legCol, who == 3 ? 3 : 4, hx, -14 + bob, fx, fy, round: true)
                g.fillEllipse(who == 3 ? Self.cGold : ink, fx - 3, fy - 2, 8, 4.2)
            }
        }
        g.translateBy(x: 0, y: bob)

        func arm(_ sx: F, _ sy: F, _ a: F, _ sleeve: CGColor) -> (F, F) {
            let hx = sx + sin(a) * 10, hy = sy + cos(a) * 10
            g.line(sleeve, 3.2, sx, sy, hx, hy, round: true)
            g.fillEllipse(skin, hx - 2.2, hy - 2.2, 4.4, 4.4)
            return (hx, hy)
        }
        func skirt(_ col: CGColor, _ trim: CGColor) {
            let wide: F = 15 + spin * 4
            let s = CGMutablePath()
            s.start(-5, -24); s.to(5, -24); s.curve(9, -18, wide, -8, wide + 1, -1); s.to(-wide - 1, -1); s.curve(-wide, -8, -9, -18, -5, -24)
            s.closeSubpath()
            g.fill(col, s)
            g.fillRect(trim, -wide - 1, -3.4, 2 * wide + 2, 2.6)
            for k in 0..<4 { g.line(withAlpha(trim, 150), 0.8, -3 + F(k) * 2, -22, (-wide + 4) + F(k) * (2 * wide - 8) / 3, -4) }
        }

        let swing: F = walking ? sin(p) * 0.8 : sin(beat) * 0.3
        var hat: (CGContext) -> Void = { _ in }
        switch who {
        case 0:   // the flag bearer (porta-bandeira): a wide gown, and the flag held high
            _ = arm(-1, -31, -0.5 - swing * 0.2, C(250, 246, 236))
            skirt(C(250, 246, 236), Self.cGold)
            g.fillRect(C(250, 246, 236), -5, -33, 10, 10)
            g.fillRect(Self.cGold, -5, -26, 10, 2)
            let (hx, hy) = arm(1, -31, 2.5, C(250, 246, 236))
            g.line(C(150, 110, 60), 1.4, hx, hy + 6, hx + 2, hy - 30)
            let wave = sin(beat * 2) * 2
            let flag = CGMutablePath()
            flag.start(hx + 2, hy - 30); flag.curve(hx + 8, hy - 33 + wave, hx + 14, hy - 27 - wave, hx + 20, hy - 30 + wave)
            flag.to(hx + 20, hy - 17 + wave); flag.curve(hx + 14, hy - 14 - wave, hx + 8, hy - 20 + wave, hx + 1.4, hy - 17)
            flag.closeSubpath()
            g.fill(own, flag)
            g.fillEllipse(Self.cGold, hx + 8, hy - 27, 6, 6)
            hat = { g in g.fillPoly(Self.cGold, [(-5, -6), (-3, -11), (-1, -7.5), (1, -12), (3, -7.5), (5.5, -11), (6, -6)]) }
        case 1:   // her escort (mestre-sala): a white suit and a straw hat, lifted in a bow when he "waves"
            _ = arm(-1, -31, -1.2 + swing * 0.3, C(248, 246, 240))
            let j = CGMutablePath()
            j.start(-5.5, -33); j.to(5.5, -33); j.curve(6.5, -26, 6.5, -19, 6, -13); j.to(-6, -13); j.curve(-6.5, -19, -6.5, -26, -5.5, -33)
            j.closeSubpath()
            g.fill(C(248, 246, 240), j)
            g.fillRect(own, -6, -19, 12, 2.4)
            g.fillPoly(own, [(2, -33), (5.5, -33), (4.6, -26)])
            let (hx, hy) = arm(1, -31, waving ? 2.4 : 1.2 - swing * 0.3, C(248, 246, 240))
            if waving {
                g.fillEllipse(C(238, 214, 150), hx - 7, hy - 4, 14, 4); g.fillRect(C(238, 214, 150), hx - 4, hy - 8, 8, 5); g.fillRect(own, hx - 4, hy - 5, 8, 1.6)
            } else {
                hat = { g in g.fillEllipse(C(238, 214, 150), -8.5, -8, 17, 4.4); g.fillRect(C(238, 214, 150), -5, -12.4, 10, 5.6); g.fillRect(own, -5, -8.8, 10, 1.8) }
            }
        case 2:   // a baiana: white lace, a wide skirt that swings out when she spins, a head wrap and beads
            _ = arm(-1, -31, -1.3 - spin * 0.6, C(252, 250, 246))
            skirt(C(252, 250, 246), C(214, 226, 240))
            g.fillRect(C(252, 250, 246), -5.5, -33, 11, 10)
            g.bezier(own, 1.4, -4, -32, -2, -27, 2, -27, 4, -32)
            g.bezier(second, 1.4, -4.6, -31, -2, -24.5, 2, -24.5, 4.6, -31)
            _ = arm(1, -31, 1.3 + spin * 0.6, C(252, 250, 246))
            hat = { g in g.fillEllipse(C(252, 250, 246), -7, -11.5, 14, 8); g.fillEllipse(C(226, 232, 242), -3, -13.5, 7, 5) }
        case 3:   // a dancer (passista): a sequin dress and a headdress of feathers, arms up
            _ = arm(-1, -31, -2.4 + sin(beat) * 0.4, own)
            let d = CGMutablePath()
            d.start(-5, -33); d.to(5, -33); d.curve(6, -26, 8.5, -19, 9.5, -14); d.to(-9.5, -14); d.curve(-8.5, -19, -6, -26, -5, -33)
            d.closeSubpath()
            g.fill(own, d)
            for k in 0..<6 { g.fillPoly(k % 2 == 0 ? second : Self.cGold, [(-9.5 + F(k) * 3.2, -14), (-6.3 + F(k) * 3.2, -14), (-7.9 + F(k) * 3.2, -9.5)]) }
            for (dx, dy) in [(F(-3), F(-28)), (2, -25), (-1, -20), (4, -19), (-5, -17)] { g.fillEllipse(C(255, 250, 220, 230), dx, dy, 1.5, 1.5) }
            _ = arm(1, -31, 2.4 + sin(beat) * 0.4, own)
            hat = { g in
                for k in 0..<7 {
                    let a = -F.pi / 2 + (F(k) - 3) * 0.3
                    g.saveGState()
                    g.translateBy(x: cos(a) * 11, y: -6 + sin(a) * 11)
                    g.rotate(by: a)
                    g.fillEllipse(k % 2 == 0 ? own : second, -8, -2.4, 16, 4.8)
                    g.restoreGState()
                }
                g.fillRect(Self.cGold, -6, -7.6, 12, 2.6)
            }
        case 4:   // the big drum (surdo): carried on a strap, struck on every beat
            _ = arm(-1, -31, 0.9, own)
            g.fillRect(own, -5.5, -33, 11, 18); g.fillRect(second, -5.5, -27, 11, 2.2); g.fillRect(second, -5.5, -22, 11, 2.2)
            g.fillRect(shade(own, 0.6), -5, -16, 10, 3)
            g.line(ink, 1.2, -4, -33, 6, -22)
            g.fillRect(C(214, 220, 230), 3, -27, 13, 15); g.fillRect(C(150, 156, 170), 3, -27, 13, 2); g.fillRect(C(150, 156, 170), 3, -14, 13, 2)
            g.fillEllipse(C(250, 246, 236), 3, -29, 13, 4)
            let (hx, hy) = arm(1, -31, 1.5 + abs(sin(beat)) * 0.9, own)
            g.line(C(150, 110, 60), 1.4, hx, hy, hx + 5, hy + 3.5); g.fillEllipse(C(250, 246, 236), hx + 3.6, hy + 2, 4, 4)
            hat = { g in g.fillEllipse(second, -7, -8.6, 14, 5.4); g.fillRect(second, 2, -6.4, 7, 2) }
        case 5:   // the small drum (tamborim): held up in one hand, a stick in the other
            let (bx, by) = arm(-1, -31, 2.2, own)
            g.fillRect(own, -5.5, -33, 11, 18); g.fillRect(second, -5.5, -24, 11, 3)
            g.fillRect(shade(own, 0.6), -5, -16, 10, 3)
            g.fillEllipse(Self.cGold, bx - 5, by - 6, 10, 6); g.fillEllipse(C(250, 246, 236), bx - 4, by - 5.6, 8, 4.2)
            let (hx, hy) = arm(1, -31, 2.3 + abs(sin(beat * 2)) * 0.5, own)
            g.line(C(150, 110, 60), 1.2, hx, hy, hx - 7, hy - 3)
            hat = { g in g.fillEllipse(C(238, 214, 150), -8, -8, 16, 4.2); g.fillRect(C(238, 214, 150), -4.6, -11.6, 9.2, 4.6) }
        case 6:   // Pierrot: baggy white with black pompoms, a ruff and a black cap
            _ = arm(-1, -31, -swing, C(248, 246, 240))
            let j = CGMutablePath()
            j.start(-6, -33); j.to(6, -33); j.curve(9, -25, 9, -18, 7.5, -12); j.to(-7.5, -12); j.curve(-9, -18, -9, -25, -6, -33)
            j.closeSubpath()
            g.fill(C(248, 246, 240), j)
            for dy in [F(-27), -21, -15.5] { g.fillEllipse(ink, 0.6, dy, 3.2, 3.2) }
            for k in 0..<5 { g.fillEllipse(C(232, 236, 244), -7 + F(k) * 3, -35.4, 4.4, 4) }
            _ = arm(1, -31, waving ? 2.6 + sin(wavePhase) * 0.4 : swing, C(248, 246, 240))
            hat = { g in g.fillEllipse(ink, -6.6, -8.6, 13.2, 6) }
        default:  // Harlequin: a suit of diamonds in two colours, and a two-cornered hat
            _ = arm(-1, -31, -swing, own)
            g.saveGState()
            let j = CGMutablePath()
            j.start(-5.5, -33); j.to(5.5, -33); j.curve(6.5, -26, 6.5, -19, 6, -13); j.to(-6, -13); j.curve(-6.5, -19, -6.5, -26, -5.5, -33)
            j.closeSubpath()
            g.addPath(j); g.clip()
            g.fillRect(own, -8, -34, 16, 22)
            for row in 0..<5 {
                for col in 0..<4 {
                    let cx = -6 + F(col) * 4 + (row % 2 == 0 ? 0 : 2), cy = -32 + F(row) * 4.4
                    g.fillPoly(second, [(cx, cy - 2.2), (cx + 2, cy), (cx, cy + 2.2), (cx - 2, cy)])
                }
            }
            g.restoreGState()
            g.fillPoly(C(250, 250, 250), [(-4, -34), (4, -34), (0, -30.5)])
            _ = arm(1, -31, waving ? 2.6 + sin(wavePhase) * 0.4 : swing, second)
            hat = { g in g.fillPoly(ink, [(-9, -5), (-6, -10), (0, -8), (6, -10), (9, -5)]); g.fillEllipse(own, -1.6, -11.4, 3.2, 3.2) }
        }

        // a shaker (chocalho) in the hand of those who carry something: it is what changes hands at a meeting
        if n.carriesGift && !waving && who != 0 && who != 4 && who != 5 {
            let col = Self.gifts[n.giftIndex % Self.gifts.count]
            g.line(C(150, 110, 60), 1.4, 11, -22, 14, -16)
            g.fillEllipse(col, 6.5, -28, 8, 7); g.fillEllipse(C(255, 255, 255, 120), 8, -27, 2.4, 2.4)
        }

        // the head, nodding with the beat
        g.saveGState()
        g.translateBy(x: 1, y: -40)
        g.rotate(by: sin(beat) * 0.07)
        g.fillEllipse(skin, -6.5, -6.5, 13, 13)
        if who == 6 { g.fillEllipse(C(250, 250, 250), -6.5, -6.5, 13, 13) }   // Pierrot's white face
        g.fillEllipse(C(250, 150, 140, 130), 1.6, 0.4, 3.6, 2.6)
        g.fillEllipse(ink, 1.6, -2.2, 1.9, 2.5)
        g.fillEllipse(ink, 4.5, -2.2, 1.5, 2.3)
        g.bezier(ink, 0.8, 1.2, 2.2, 2.8, 4.6, 4.8, 4.6, 5.8, 2.2)
        hat(g)
        g.restoreGState()
    }

    // ------------------------------------------------------------------ orkesterbil
    /// Carnival's "flyer" in Santa's place does not fly: a truck with a band on it drives along the ground, the
    /// drums playing while it passes. Drawn in Santa's frame moved down to the ground (ScreenOverlay.flyerPoint):
    /// facing +x, origin at the ground under its middle; `t` is the trip's clock.
    func drawBandTruck(_ g: CGContext, _ t: F) {
        if c.carnival == .rhein { drawFestwagen(g, t); return }
        let cols = Self.carnivalColours
        let beat = F(c.beatCount) * .pi
        let dark = C(46, 44, 60), body = C(250, 196, 40), bodyDark = C(214, 150, 20)
        let roll = t * 5
        // wheels
        for wx in [F(-78), -52, 58] {
            g.fillEllipse(dark, wx - 11, -22, 22, 22)
            g.fillEllipse(C(160, 164, 176), wx - 4.5, -15.5, 9, 9)
            for k in 0..<3 { let a = roll + F(k) * 2.094; g.line(dark, 1.4, wx, -11, wx + cos(a) * 4.5, -11 + sin(a) * 4.5) }
        }
        // the cab at the front
        let cab = CGMutablePath()
        cab.start(40, -16); cab.to(40, -58); cab.to(66, -58); cab.curve(76, -58, 84, -44, 86, -34); cab.to(92, -30); cab.to(92, -16); cab.closeSubpath()
        g.fill(body, cab)
        let pane = CGMutablePath()
        pane.start(52, -36); pane.to(52, -53); pane.to(66, -53); pane.curve(72, -53, 78, -44, 80, -36); pane.closeSubpath()
        g.fill(C(178, 214, 236), pane)
        g.fillEllipse(C(206, 150, 106), 60, -49, 8, 9)
        g.fillRect(bodyDark, 40, -22, 52, 6)
        g.fillEllipse(C(255, 244, 190), 88, -28, 4.4, 5.4)
        // the bed: a stage with a fringed skirt and a row of bulbs that light in turn with the beat
        g.fillRect(cols[0], -104, -34, 144, 18)
        g.fillRect(cols[4], -104, -38, 144, 5)
        for k in 0..<24 { g.fillPoly(k % 2 == 0 ? cols[2] : cols[1], [(-104 + F(k) * 6, -16), (-98 + F(k) * 6, -16), (-101 + F(k) * 6, -11)]) }
        let lit = Int(c.beatCount * 2)
        for k in 0..<12 {
            let on = (k + lit) % 3 == 0
            g.fillEllipse(on ? C(255, 250, 200) : shade(cols[k % cols.count], 0.75), -101 + F(k) * 12, -30, 5, 5)
        }
        // stacks of loudspeakers at both ends, their cones pumping
        for sx in [F(-104), 18] {
            g.fillRect(dark, sx, -86, 22, 48)
            for k in 0..<2 {
                let r: F = 7 + abs(sin(beat)) * 1.2
                g.fillEllipse(C(96, 96, 112), sx + 11 - r, -74 + F(k) * 22 - r, 2 * r, 2 * r)
                g.fillEllipse(dark, sx + 8, -77 + F(k) * 22, 6, 6)
            }
        }
        // the band: a singer, a guitarist and two drummers, bouncing on the beat
        let places: [(F, Int, F)] = [(-70, 0, 0.0), (-48, 1, 0.5), (-24, 2, 1.0), (0, 3, 1.5)]
        for (x, kind, off) in places {
            let b = sin(beat + off * .pi)
            g.saveGState()
            g.translateBy(x: 0, y: -38 - abs(b) * 2)
            let skin = Self.cSkins[(kind * 2 + 1) % Self.cSkins.count]
            drawSmallPerson(g, x, 34, cloth: cols[(kind + 1) % cols.count], skin: skin, legs: dark, sway: b * 0.08,
                            arm: kind == 0 ? 2.3 : 1.2 + abs(b) * 0.7)
            switch kind {
            case 0: g.fillEllipse(dark, x + 5, -30, 3.4, 3.4)   // a microphone
            case 1:   // a small guitar
                g.fillEllipse(C(170, 110, 50), x - 2, -20, 10, 8); g.line(C(120, 80, 40), 1.6, x + 6, -17, x + 16, -24)
            case 2: g.fillRect(C(214, 220, 230), x + 4, -22, 10, 11); g.fillEllipse(C(250, 246, 236), x + 4, -24, 10, 4)
            default: g.fillEllipse(Self.cGold, x + 5, -27, 9, 5)
            }
            g.restoreGState()
        }
        // a canopy over them, with a fringe
        g.line(dark, 1.6, -93, -86, -93, -104); g.line(dark, 1.6, 29, -86, 29, -104)
        g.fillRect(cols[1], -94, -110, 124, 7)
        for k in 0..<20 { g.fillPoly(k % 2 == 0 ? cols[2] : cols[0], [(-94 + F(k) * 6.2, -103), (-87.8 + F(k) * 6.2, -103), (-90.9 + F(k) * 6.2, -98)]) }
    }

    // ------------------------------------------------------------------ gadefejerne
    /// Carnival's form of the snow plow: the street sweepers of Ash Wednesday. Two sweepers in orange walk in
    /// front with their brooms, one of them dancing as he sweeps, and a cart follows for what they sweep up.
    /// Facing +x, origin at the ground, the brooms where the plow's blade would be. No horn and no smoke.
    func drawStreetSweepers(_ g: CGContext, _ ph: F) {
        let step = plowWheel * ScreenOverlay.donkeyStride
        let orange = C(245, 130, 30), dark = C(46, 44, 60), wood = C(150, 110, 60)
        let cols = Self.carnivalColours
        // the cart: a bin on two wheels, confetti heaped in it, pushed by a third sweeper
        for k in 0..<10 { g.fillRect(cols[k % cols.count], -66 + F(k * 7 % 40), -50 - F(k % 3) * 3, 5, 3.4) }
        let bin = CGMutablePath()
        bin.start(-74, -46); bin.to(-22, -46); bin.to(-27, -14); bin.to(-69, -14); bin.closeSubpath()
        g.fill(C(60, 150, 90), bin)
        g.fillRect(C(40, 110, 66), -76, -48, 56, 4)
        for wx in [F(-62), -34] { g.fillEllipse(dark, wx - 8, -16, 16, 16); g.fillEllipse(C(160, 164, 176), wx - 3, -11, 6, 6) }
        g.line(dark, 2, -76, -44, -92, -34, round: true)
        g.saveGState()
        g.translateBy(x: 0, y: 0)
        drawSmallPerson(g, -100, 46, cloth: orange, skin: Self.cSkins[2], legs: C(60, 70, 110), sway: 0.08, arm: 1.3, step: step)
        g.restoreGState()
        // the two with brooms: the second one dances (he turns his broom and bounces)
        for (i, x) in [F(20), 62].enumerated() {
            let dance = i == 1
            let sw = sin(step * (dance ? 2 : 1) + F(i) * 1.4)
            g.saveGState()
            g.translateBy(x: 0, y: dance ? -abs(sw) * 3 : 0)
            drawSmallPerson(g, x, 48, cloth: orange, skin: Self.cSkins[i * 3], legs: C(60, 70, 110), sway: dance ? sw * 0.14 : 0.05,
                            arm: 0.9 + sw * 0.35, step: step + F(i))
            // a cap, and the broom from the hands down to the ground in front
            g.fillRect(orange, x - 5, -57.5, 12, 3.6)
            g.restoreGState()
            let bx = x + 26 + sw * 7
            g.line(wood, 2, x + 6, -30, bx, -5, round: true)
            for k in 0..<6 { g.line(k % 2 == 0 ? C(214, 170, 72) : C(176, 132, 52), 1.6, bx, -6, bx - 6 + F(k) * 3.4, 1, round: true) }
        }
        // confetti gathered in front of the brooms
        for (i, lx) in [F(96), 103, 110].enumerated() where F(i) * 6 < ph {
            g.fillRect(cols[(i * 2 + 1) % cols.count], lx, -5 - F(i % 2) * 2.4, 5, 3.4)
        }
    }

    // ------------------------------------------------------------------ frynseguirlande med masker
    /// One carnival mask hanging by its ribbon from (x, y): a half-mask with two eye holes and three small plumes.
    private func drawGarlandMask(_ g: CGContext, _ x: F, _ y: F, _ colour: CGColor, _ plume: CGColor) {
        let S = self.S
        g.line(C(60, 50, 60), 0.9 * S, x, y, x, y + 5 * S)
        for k in 0..<3 {
            g.saveGState()
            g.translateBy(x: x + (F(k) - 1) * 3.4 * S, y: y + 7 * S)
            g.rotate(by: -.pi / 2 + (F(k) - 1) * 0.45)
            g.fillEllipse(plume, 0, -1.4 * S, 8 * S, 2.8 * S)
            g.restoreGState()
        }
        let m = CGMutablePath()
        m.start(x - 9 * S, y + 8 * S)
        m.curve(x - 5 * S, y + 5.5 * S, x + 5 * S, y + 5.5 * S, x + 9 * S, y + 8 * S)
        m.curve(x + 9.5 * S, y + 13 * S, x + 4 * S, y + 15 * S, x + 1.2 * S, y + 11.6 * S)
        m.to(x - 1.2 * S, y + 11.6 * S)
        m.curve(x - 4 * S, y + 15 * S, x - 9.5 * S, y + 13 * S, x - 9 * S, y + 8 * S)
        m.closeSubpath()
        g.fill(colour, m)
        g.stroke(Self.cGold, 0.9 * S, m)
        g.setBlendMode(.clear)
        g.fillEllipse(C(0, 0, 0), x - 6.4 * S, y + 8.4 * S, 4.2 * S, 2.8 * S)
        g.fillEllipse(C(0, 0, 0), x + 2.2 * S, y + 8.4 * S, 4.2 * S, 2.8 * S)
        g.setBlendMode(.normal)
    }

    /// The garland along the string: a fringe of foil strips in bright colours all the way, and a mask hanging
    /// between every two bulbs. (The bulbs are the Christmas lights' own and twinkle as they do.)
    func drawCarnivalGarland(_ g: CGContext, span: F, sag: F, top: F) {
        if c.carnival == .rhein { drawRhenishGarland(g, span: span, sag: sag, top: top); return }
        let S = self.S, cols = Self.carnivalColours
        var n = 0
        var x0 = -span * 0.3
        while x0 < W {
            let strips = 46
            for k in 0..<strips {
                let u = (F(k) + 0.5) / F(strips)
                let x = x0 + u * span, y = top + sag * (1 - (2 * u - 1) * (2 * u - 1))
                let len = (7 + F((k * 7 + n * 3) % 5) * 1.4) * S
                g.fillRect(cols[(k + n) % cols.count], x - 1.6 * S, y, 3.2 * S, len)
            }
            g.beginTransparencyLayer(auxiliaryInfo: nil)
            for b in 0..<4 {
                let u = F(b) / 4
                let x = x0 + u * span, y = top + sag * (1 - (2 * u - 1) * (2 * u - 1))
                drawGarlandMask(g, x, y + 6 * S, cols[(b + n * 2) % cols.count], cols[(b + n * 2 + 3) % cols.count])
            }
            g.endTransparencyLayer()
            n += 1
            x0 += span
        }
    }

    // ------------------------------------------------------------------ tukaner på vindueskanterne
    /// One toucan perched on y = 0, about 30 high, looking right: black with a white throat, a big orange beak
    /// with a dark tip (open when `calls`), a blue ring round the eye and a tail down behind.
    private func drawToucan(_ g: CGContext, calls: Bool, look: F) {
        let black = C(26, 26, 32)
        g.fillPoly(black, [(-7, -8), (-13, 6), (-8, 6), (-3, -6)])
        g.fillEllipse(black, -8, -22, 15, 22)
        g.fillEllipse(C(250, 246, 236), -1, -19.5, 8.5, 11)
        g.fillEllipse(C(232, 60, 50), -3, -4, 6, 4)
        g.line(C(110, 130, 150), 1.4, -1, -1, -1, 1.4); g.line(C(110, 130, 150), 1.4, 3, -1, 3, 1.4)
        g.saveGState()
        g.translateBy(x: 2, y: -22)
        g.rotate(by: look)
        g.fillEllipse(black, -6.5, -6.5, 13, 12.5)
        // the beak: the upper half, and the lower one dropped when it calls
        let upper = CGMutablePath()
        upper.start(4, -4); upper.curve(11, -7.5, 20, -5, 22, 0.6); upper.to(4, 0.6); upper.closeSubpath()
        g.fill(C(255, 150, 30), upper)
        g.fillPoly(C(255, 214, 80), [(4, -3.4), (13, -5.4), (14, -2.6), (4, -1.6)])
        g.fillPoly(C(40, 30, 30), [(18.6, -2.6), (22, 0.6), (18, 0.6)])
        g.saveGState()
        g.translateBy(x: 4, y: 0.6)
        g.rotate(by: calls ? 0.3 : 0)
        let lower = CGMutablePath()
        lower.start(0, 0); lower.to(17, 0); lower.curve(13, 3.6, 5, 4, 0, 2.8); lower.closeSubpath()
        g.fill(C(240, 120, 20), lower)
        g.restoreGState()
        g.fillEllipse(C(70, 170, 230), 0.4, -4.6, 4.6, 4.6)
        g.fillEllipse(black, 1.9, -3.1, 1.7, 1.7)
        g.restoreGState()
    }

    /// The pictures of the toucans: looking ahead, looking up a little, and calling; each also turned the other
    /// way. Drawn once, at twice the size they are shown at.
    private func makeToucanImages() -> [CGImage] {
        var all: [CGImage] = []
        for flip in [F(1), -1] {
            for (calls, look) in [(false, F(0)), (false, -0.3), (true, -0.12)] {
                all.append(renderImage(width: 52, height: 38, scale: backingScale * 2) { g in
                    g.translateBy(x: 26, y: 35)
                    g.scaleBy(x: flip, y: 1)
                    self.drawToucan(g, calls: calls, look: look)
                }!)
            }
        }
        return all
    }

    /// Toucans sit on the window edges, one about every 380 points, at places fixed on the window; each looks about
    /// and now and then calls. Only where the edge is not hidden by a window in front. They are put into the pool
    /// the Day of the Dead's candles use (`pool`), between its begin and end.
    func addLedgeToucans(to pool: DotPool) {
        if c.carnival == .rhein { addLedgeCaps(to: pool); return }
        if toucanImages.isEmpty { toucanImages = makeToucanImages() }
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
                // (it looks up for a moment every few seconds, and calls about every nine)
                let t = c.time + Double(k) * 3.7 + Double(id % 23)
                let pose = t.truncatingRemainder(dividingBy: 9.1) < 0.5 ? 2 : (t.truncatingRemainder(dividingBy: 3.3) < 0.7 ? 1 : 0)
                let flipped = (id + k) % 2 == 1
                pool.add(toucanImages[(flipped ? 3 : 0) + pose], x: gx - ox, y: edge - l.height(at: gx) * 0.8 - 16, w: 52, h: 38, opacity: 1)
            }
        }
    }
}
