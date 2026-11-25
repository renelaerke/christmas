import AppKit
import QuartzCore

/// The snowman the children build in the Christmas theme (SnowmanBuild has the story; as `src/LayerSnowman.cs`).
/// This part lets the plow run it down and draws the snowman, the three children and their snowballs on the
/// primary screen.
///
/// The snowman's balls and what it wears are one sprite, redrawn only when something in it has moved. Each child
/// is an image layer like a nisse: its poses are drawn once and kept (`kidFrames`), and the layer is moved,
/// mirrored and lifted. The snowballs are pooled images.
extension ScreenOverlay {
    /// The children's clothes: jacket, trousers, knitted hat, its pompom, mittens, and a scarf (or none).
    static let kidClothes: [(jacket: CGColor, trousers: CGColor, hat: CGColor, pompom: CGColor, mittens: CGColor, scarf: CGColor?)] = [
        (C(205, 50, 45), C(45, 65, 120), C(240, 240, 245), C(205, 40, 45), C(45, 65, 120), C(245, 190, 45)),
        (C(45, 125, 195), C(55, 55, 65), C(245, 185, 40), C(255, 255, 255), C(245, 185, 40), nil),
        (C(90, 170, 100), C(75, 150, 90), C(225, 90, 150), C(255, 255, 255), C(225, 90, 150), nil)]

    /// True where the children build: the primary screen in a theme where they do, with the snowman switched on.
    var buildsSnowman: Bool { isPrimary && cfg.snowman && c.theme.childrenBuild }

    /// Where the children build and play, in this screen's points (only while they do).
    func playZone() -> (left: F, right: F)? {
        guard buildsSnowman, build.playing else { return nil }
        return ((build.siteX - SnowmanBuild.playHalfWidth) * S, (build.siteX + SnowmanBuild.playHalfWidth) * S)
    }

    private func buildGround(_ x: F) -> F {
        groundY - heapAt(max(0, min(W - 1, x))) + 2 * S
    }

    func updateBuild(_ dt: F) {
        let b = build
        let plowHere = plowActive
        for k in b.kids { k.waving = plowHere && abs(k.x * S - plowX) < 170 * S }
        let blade = plowHere ? plowX + plowDir * 72 * S * plowScale : F.nan
        // Only where the blade arrives this frame: a snowman begun behind the plow, after it has passed, stays.
        if plowHere && b.hasSnow && !lastBlade.isNaN {
            for ball in b.balls where ball.present {
                let near = ball.x * S - plowDir * ball.r * S   // the ball's side facing the plow
                if (blade - near) * plowDir >= 0 && (lastBlade - near) * plowDir < 0 { runDownSnowman(); break }
            }
        }
        lastBlade = blade
        b.update(dt, W / S)
        if b.justFinished { c.snowmanCelebrate(on: self) }
        // a few minutes after the children have finished their snowman, the plow comes by and runs it down
        if b.wantsPlow { b.wantsPlow = false; c.plowWanted(by: self) }
    }

    /// The plow's blade has reached the snowman: it flies apart in chunks of snow, into the pile before the blade.
    private func runDownSnowman() {
        let b = build
        for ball in b.balls where ball.present {
            let bx = ball.x * S, by = buildGround(bx) - ball.y * S
            let n = 4 + Int(ball.r * 1.6)
            for _ in 0..<n {
                let p = PlowBit()
                p.x = bx + (R() - 0.5) * ball.r * S
                p.y = by + (R() - 0.5) * ball.r * S
                p.vx = plowDir * (60 + R() * 150) * S
                p.vy = -(70 + R() * 170) * S
                p.max = 2; p.life = 2
                p.size = (1.5 + R() * 3) * S
                plowBits.append(p)
            }
            c.plow.pushed += ball.r * ball.r * 2 * S
        }
        ErrorLog.debug("snowman: run down by the plow at x=\(Int(b.siteX)) (\(Int(b.t)) s into the build)")
        b.runOver()
    }

    func hideBuild() {
        if !kidLayer.isHidden { kidLayer.isHidden = true }
        snowballPool.begin(); snowballPool.end()
    }

    // ------------------------------------------------------------------ the snowman
    func renderBuild() {
        let b = build
        let sx = b.siteX * S, gy = buildGround(sx)
        snowmanPos = CGPoint(x: screenBounds.minX + sx, y: screenBounds.minY + gy)

        // The sprite covers just the balls (wherever they have been rolled to) and what the snowman wears. It is
        // redrawn when one of them has moved half a point, turned or grown: a few times a second while a ball
        // is rolled, never while the snowman just stands there.
        var r = CGRect.null
        var key = "\(b.dressed)"
        for ball in b.balls where ball.present {
            let bx = ball.x * S, by = buildGround(bx) - ball.y * S, rr = ball.r
            r = r.union(CGRect(x: bx - (rr + 2) * S, y: by - (rr + 2) * S, width: (2 * rr + 4) * S, height: (2 * rr + 6) * S))
            key += " \(Int(bx * 2)) \(Int(by * 2)) \(Int(rr * S * 4)) \(Int(ball.roll * 12))"
        }
        if b.bottom.present {
            let bx = b.bottom.x * S, rr = b.bottom.r * S
            r = r.union(CGRect(x: bx - rr * 1.1, y: buildGround(bx) - 2 * S, width: rr * 2.2, height: 4 * S))
        }
        if b.dressed > 0 { r = r.union(CGRect(x: sx - 30 * S, y: gy - 72 * S, width: 60 * S, height: 74 * S)); key += " \(Int(gy * 2))" }
        if r.isNull { snowmanSprite.hide(); snowmanKey = "" } else {
            r = r.integral
            key += " \(Int(r.minX)) \(Int(r.minY)) \(Int(r.width)) \(Int(r.height))"
            snowmanSprite.place(r, redraw: key != snowmanKey || snowmanSprite.layer.isHidden)
            snowmanKey = key
        }

        renderKids(b)
        renderSnowballs(b)
    }

    /// The snowman sprite's drawing, in the screen's coordinates.
    func drawBuild(_ g: CGContext) {
        let b = build
        let sx = b.siteX * S, gy = buildGround(sx)
        if b.bottom.present {
            let bx = b.bottom.x * S, r = b.bottom.r * S
            g.fillEllipse(C(60, 80, 110, 50), bx - r * 1.1, buildGround(bx) - 2 * S, r * 2.2, 4 * S)
        }
        for ball in b.balls where ball.present { drawBuildBall(g, ball) }
        if b.dressed > 0 { drawSnowmanDress(g, b.dressed, sx, gy) }
    }

    private func drawBuildBall(_ g: CGContext, _ ball: SnowmanBuild.Ball) {
        let bx = ball.x * S, by = buildGround(bx) - ball.y * S, r = ball.r
        g.saveGState()
        g.translateBy(x: bx, y: by)
        g.scaleBy(x: S, y: S)
        let rc = CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)
        let p = CGPath(ellipseIn: rc, transform: nil)
        g.fillGradient(p, C(255, 255, 255), C(200, 216, 238), from: CGPoint(x: rc.minX + r * 0.4, y: rc.minY), to: CGPoint(x: rc.maxX - r * 0.4, y: rc.maxY))
        g.stroke(C(140, 165, 200, 70), 1, p)
        // two lumps in the snow turn with the ball, so it can be seen rolling
        let lump = C(150, 170, 200, 70)
        for i in 0..<2 {
            let a = ball.roll + F(i) * 2.6
            let lr = r * (i == 0 ? 0.55 : 0.35), d = max(0.8, r * 0.12)
            g.fillEllipse(lump, cos(a) * lr - d, sin(a) * lr - d, 2 * d, 2 * d)
        }
        g.restoreGState()
    }

    /// What the children put on the finished stack, in order. The snowman looks to the right.
    private func drawSnowmanDress(_ g: CGContext, _ n: Int, _ sx: F, _ gy: F) {
        g.saveGState()
        g.translateBy(x: sx, y: gy)
        g.scaleBy(x: S, y: S)
        let my = -SnowmanBuild.middleY, hy = -SnowmanBuild.headY
        let coal = C(35, 35, 40)
        if n >= 4 {
            let wood = C(110, 70, 35)
            g.line(wood, 1.6, -8, my - 3, -21, my - 12, round: true)
            g.line(wood, 1.6, -17, my - 9.5, -18, my - 15, round: true)
            g.line(wood, 1.6, 8, my - 3, 21, my - 10, round: true)
            g.line(wood, 1.6, 17, my - 7.5, 20, my - 13, round: true)
        }
        if n >= 1 {
            g.fillEllipse(coal, 0.3, hy - 3.2, 2.2, 2.2)
            g.fillEllipse(coal, 4.3, hy - 3.2, 2.2, 2.2)
        }
        if n >= 2 { g.fillPoly(C(240, 130, 30), [(3, hy - 0.8), (12, hy + 0.2), (3, hy + 1.2)]) }
        if n >= 3 { for i in 0..<3 { g.fillEllipse(coal, 0.2, my - 5.8 + F(i) * 4.6, 2.4, 2.4) } }
        if n >= 5 {
            for i in 0..<4 {
                let x = 0.5 + F(i) * 1.7, y = hy + 3.6 + 0.5 * (1 - abs(F(i) - 1.5) / 1.5)
                g.fillEllipse(coal, x - 0.6, y - 0.6, 1.2, 1.2)
            }
        }
        if n >= 6 {
            let ny = hy + SnowmanBuild.headR - 1.5
            let scarf = C(200, 30, 40)
            g.fillRect(scarf, -7.5, ny, 15, 3.4)
            g.fillPoly(scarf, [(-5, ny + 2), (-1.5, ny + 2), (-2.5, ny + 11), (-6.5, ny + 10.5)])
            g.line(C(255, 255, 255), 1, -5.5, ny + 6, -2, ny + 6)
            g.line(C(255, 255, 255), 1, -6, ny + 8.5, -2.3, ny + 8.5)
        }
        if n >= 7 {
            // a green knitted hat with a pompom
            let top = hy - SnowmanBuild.headR
            g.fillDome(C(40, 140, 70), 0, top + 0.8, 6.8)
            g.fillRect(C(25, 105, 50), -7.3, top - 0.2, 14.6, 2.8)
            g.fillEllipse(C(255, 255, 255), -2.4, top - 8.4, 4.8, 4.8)
        }
        g.restoreGState()
    }

    // ------------------------------------------------------------------ the children
    /// Frames per cycle of each pose: the legs when walking or pushing, the arm when waving or patting snow, the
    /// arms when jumping, and the throw (winding up, then four steps of the swing). The rest stand still.
    private static func kidFrameCount(_ pose: SnowmanBuild.Pose) -> Int {
        switch pose {
        case .walk, .push: return 16
        case .wave, .pat, .jump: return 8
        case .throwing: return 5
        case .stand, .lift, .sad: return 1
        }
    }

    private static func kidFrame(_ k: SnowmanBuild.Kid) -> Int {
        func cycle(_ phase: F, _ n: Int) -> Int { Int((phase / (2 * .pi)).truncatingRemainder(dividingBy: 1) * F(n)) % n }
        switch k.pose {
        case .walk, .push: return cycle(k.walkPhase, 16)
        case .wave: return cycle(k.t * 11, 8)
        case .pat: return cycle(k.t * 9, 8)
        case .jump: return cycle(k.t * 6, 8)
        case .throwing: return k.throwT < 0.3 ? 0 : min(4, 1 + Int((k.throwT - 0.3) / 0.15 * 4))
        case .stand, .lift, .sad: return 0
        }
    }

    // A child's picture: 48 × 64 units with the feet at (24, 58), which leaves room for the pompom, the lifted
    // arms and the lean into a ball.
    private static let kidBox = CGSize(width: 48, height: 64), kidFeet = CGPoint(x: 24, y: 58)

    private func renderKids(_ b: SnowmanBuild) {
        if kidLayers.isEmpty {
            for _ in b.kids {
                let l = CALayer()
                l.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "transform": NSNull(), "hidden": NSNull()]
                kidLayer.addSublayer(l)
                kidLayers.append(l)
            }
        }
        if kidLayer.isHidden { kidLayer.isHidden = false }
        for (i, k) in b.kids.enumerated() {
            let ks = S * k.size
            let x = k.x * S, gy = buildGround(x) - k.lift * S
            let frame = Self.kidFrame(k)
            let key = k.look * 10_000 + k.pose.rawValue * 100 + frame
            let img = kidFrames[key] ?? renderKidFrame(k, frame, key)
            let l = kidLayers[i]
            if l.contents == nil || (l.contents as! CGImage) !== img { l.contents = img }
            l.bounds = CGRect(x: 0, y: 0, width: Self.kidBox.width * ks, height: Self.kidBox.height * ks)
            l.position = CGPoint(x: x, y: H - (gy - (Self.kidFeet.y - Self.kidBox.height / 2) * ks))
            l.setAffineTransform(CGAffineTransform(scaleX: k.dir < 0 ? -1 : 1, y: 1))
        }
    }

    private func renderKidFrame(_ k: SnowmanBuild.Kid, _ frame: Int, _ key: Int) -> CGImage {
        let ks = S * k.size
        let img = renderImage(width: Self.kidBox.width * ks, height: Self.kidBox.height * ks, scale: backingScale) { g in
            g.scaleBy(x: ks, y: ks)
            g.translateBy(x: Self.kidFeet.x, y: Self.kidFeet.y)
            drawKid(g, k.look, k.pose, frame)
        }!
        kidFrames[key] = img
        return img
    }

    /// One child in one pose, facing right with the feet at (0, 0); y up is negative. (The Windows version also
    /// draws a shadow under each child. It lies below the top of the snow pile, which is drawn over it, so it is
    /// never seen and is left out here.)
    private func drawKid(_ g: CGContext, _ look: Int, _ pose: SnowmanBuild.Pose, _ frame: Int) {
        let clothes = Self.kidClothes[look]
        let phase = F(frame) / F(Self.kidFrameCount(pose)) * 2 * .pi
        let walking = pose == .walk || pose == .push
        let legA: F = walking ? sin(phase) * 0.5 : 0
        let bob: F = pose == .walk ? -abs(sin(phase)) * 1.2 : 0
        let squat = pose == .pat
        if pose == .push { g.rotate(by: 12 * .pi / 180) }   // leaning into the ball

        let boot = C(50, 40, 35)
        func leg(_ hx: F, _ hy: F, _ a: F) {
            let fx = hx + sin(a) * 11, fy = hy + cos(a) * 11
            g.line(clothes.trousers, 5, hx, hy, fx, fy, round: true)
            g.fillEllipse(boot, fx - 3, fy - 2, 8, 4.5)
        }
        if squat {
            // knees forward, bottom down
            g.line(clothes.trousers, 5, -2, -8, 4, -9, round: true)
            g.line(clothes.trousers, 5, 4, -9, 3, -1.5, round: true)
            g.fillEllipse(boot, 1, -3, 8, 4.5)
            g.line(clothes.trousers, 5, 1, -8, -1, -1.5, round: true)
            g.fillEllipse(boot, -3, -3, 8, 4.5)
        } else {
            leg(-1.8, -14 + bob, legA)
            leg(1.8, -14 + bob, -legA)
        }

        g.translateBy(x: 0, y: squat ? 7 : bob)
        let back: F, front: F
        switch pose {
        case .wave: back = 0.15; front = 2.5 + sin(phase) * 0.45
        case .push: back = 1.45; front = 1.6
        case .lift: back = 2.55; front = 2.7
        case .pat: back = 1.1; front = 1.3 + sin(phase) * 0.3
        case .jump: back = 2.7 + sin(phase) * 0.2; front = 2.85 - sin(phase) * 0.2
        case .throwing: back = 0.6; front = -2.4 + F(frame) / 4 * 4.1   // wound up behind the head, then the swing
        case .sad: back = 0.05; front = 0.05
        case .walk: back = -legA * 0.9; front = legA * 0.9
        case .stand: back = 0.2; front = 0.1
        }

        func arm(_ sx: F, _ sy: F, _ a: F) {
            let hx = sx + sin(a) * 9, hy = sy + cos(a) * 9
            g.line(clothes.jacket, 4.2, sx, sy, hx, hy, round: true)
            g.fillEllipse(clothes.mittens, hx - 2.4, hy - 2.4, 4.8, 4.8)
        }
        arm(-1, -25, back)
        g.fillEllipse(clothes.jacket, -8.5, -31, 17, 18)
        g.line(C(0, 0, 0, 90), 0.8, 4.5, -29, 5, -15)

        g.fillEllipse(Self.skin, -5.5, -42, 11, 11)
        g.fillEllipse(C(240, 140, 140, 150), 1.2, -35.5, 3, 2.4)
        let eye = C(45, 40, 40)
        if pose == .sad { g.fillRect(eye, 2.2, -37, 2, 0.8) } else { g.fillEllipse(eye, 2.4, -37.6, 1.6, 1.6) }
        if let scarf = clothes.scarf {
            g.fillRect(scarf, -5, -32, 10, 3)
            g.fillPoly(scarf, [(-5, -31), (-2.5, -31), (-5.5, -23), (-8, -24)])
        }

        g.fillDome(clothes.hat, 0, -41.5, 6)
        g.fillRect(clothes.hat, -6.3, -42, 12.6, 3)
        g.line(C(0, 0, 0, 50), 0.7, -6.3, -40.5, 6.3, -40.5)
        g.fillEllipse(clothes.pompom, -2.2, -50, 4.4, 4.4)
        arm(1, -25, front)
    }

    // ------------------------------------------------------------------ snowballs
    private func renderSnowballs(_ b: SnowmanBuild) {
        snowballPool.begin()
        for s in b.snowballs {
            let x = s.x * S, y = buildGround(x) - s.y * S
            if s.life < 0 {
                let r = 1.9 * S
                snowballPool.add(images.snowball, x: x, y: y, w: 2 * r, h: 2 * r, opacity: 1)
            } else {
                // it bursts into a little puff
                let spread = (0.5 - s.life) * 18 * S, d = 1.1 * S
                for i in 0..<6 {
                    let a = F(i) * .pi / 3 + 0.4
                    snowballPool.add(images.chunk, x: x + cos(a) * spread, y: y - abs(sin(a)) * spread, w: 2 * d, h: 2 * d, opacity: 250.0 / 255)
                }
            }
        }
        snowballPool.end()
    }

    // ------------------------------------------------------------------ the walkers and the play zone
    /// A puff of sparkles where a nisse vanishes or reappears by magic.
    func magicPuff(_ n: Nisse) {
        let sc = S * n.size
        let gy = groundY - heapAt(max(0, min(W - 1, n.x))) + 2 * S
        for i in 0..<26 {
            let sp = Spark()
            sp.x = screenBounds.minX + n.x + (R() - 0.5) * 36 * sc
            sp.y = screenBounds.minY + gy - R() * 60 * sc
            sp.vx = (R() - 0.5) * 50 * S
            sp.vy = -(15 + R() * 45) * S
            sp.max = 0.8 + R() * 0.8; sp.life = sp.max
            sp.size = (1.5 + R() * 2.5) * S
            sp.gold = R() < 0.5
            sp.star = i % 4 == 0
            c.sparks.append(sp)
        }
    }
}

extension CGContext {
    /// The upper half of a disc: a knitted hat's dome (GDI+ FillPie from 180° over 180°).
    func fillDome(_ c: CGColor, _ cx: F, _ cy: F, _ r: F) {
        setFillColor(c)
        beginPath()
        move(to: CGPoint(x: cx - r, y: cy))
        addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
        closePath()
        fillPath()
    }
}
