import Foundation

/// The snowman in the Christmas theme (as `src/SnowmanBuild.cs`, line for line): three children build it at the
/// bottom of the primary screen in about 15 minutes. They roll the three balls one by one, lift them on top of
/// each other and dress it (eyes, nose, buttons, arms, smile, scarf, hat). When it is finished they cheer and
/// have a snowball fight, and a few minutes later the snow plow comes by and runs it down. The children then
/// walk to another place and start again.
///
/// This class is only the story; ScreenOverlay (OverlaySnowman.swift) moves it on the screen, lets the plow run
/// it down and draws it. Positions are in logical units (points / ScreenOverlay.S) from the screen's left edge,
/// and heights are above the ground. The state lives in the Controller, so it survives the overlays being
/// rebuilt (the camera's own scene has one of its own).
/// JULE_SNOWMAN_SPEED=N runs it N times faster, and JULE_SNOWMAN_START=T[,X] starts T seconds into the build
/// (at X units from the left edge) instead of somewhere at random (both for testing).
final class SnowmanBuild {
    static let buildTime: F = 900
    // When each part is rolled and lifted (seconds into the build).
    private static let bottomEnd: F = 330, middleStart: F = 150, middleEnd: F = 540, middleLift: F = 565,
                       headStart: F = 565, headEnd: F = 735, headLift: F = 760, dressStart: F = 760
    static let items = 7   // eyes, nose, buttons, arms, smile, scarf, hat
    private static let itemTime: F = (buildTime - dressStart) / F(items)
    static let bottomR: F = 14, middleR: F = 10, headR: F = 7.5
    // the centres of the stacked balls, above the ground
    static let bottomY: F = bottomR, middleY: F = 2 * bottomR - 3 + middleR, headY: F = middleY + middleR - 2.5 + headR

    final class Ball { var x: F = 0, y: F = 0, r: F = 0, roll: F = 0, vx: F = 0; var present = false }

    enum Pose: Int { case walk, stand, wave, push, lift, pat, jump, throwing, sad }

    final class Kid {
        let look: Int                 // which of the three children (clothes and size)
        let size: F, speed: F         // speed in units per second
        var x: F = 0, dir: F = 1, lift: F = 0, walkPhase: F = 0, t: F = 0, targetX: F = 0, faceDir: F = 0, throwT: F = -1
        var pose = Pose.walk, want = Pose.walk   // the pose drawn now, and the one to take at the target
        var waving = false            // the plow is passing (set by the overlay)
        init(look: Int, size: F, speed: F) { self.look = look; self.size = size; self.speed = speed }
    }

    final class Snowball { var x: F = 0, y: F = 0, vx: F = 0, vy: F = 0, targetX: F = 0, life: F = -1 }

    enum State { case walking, building, finished, runDown }

    let bottom = Ball(), middle = Ball(), head = Ball()
    let balls: [Ball]
    let kids = [Kid(look: 0, size: 1, speed: 30), Kid(look: 1, size: 0.95, speed: 30), Kid(look: 2, size: 0.8, speed: 24)]
    private(set) var snowballs: [Snowball] = []
    private(set) var siteX: F = 0
    private(set) var dressed = 0             // how many of the items are on
    private(set) var state = State.walking
    private(set) var t: F = 0                // seconds into the build
    var wantsPlow = false                    // the Controller sends the plow (and this is cleared)
    private(set) var justFinished = false    // true for the one update in which the snowman was finished

    private static let gravity: F = 110
    private let speed: F = {
        let f = Double(ProcessInfo.processInfo.environment["JULE_SNOWMAN_SPEED"] ?? "") ?? 1
        return f > 0 ? F(f) : 1
    }()
    private var started = false
    private var clock: F = 0, plowAt: F = -1, stateTimer: F = 0, throwTimer: F = 0, wanderTimer: F = 0
    private var nextThrower = 0

    init() { balls = [bottom, middle, head] }

    var hasSnow: Bool { bottom.present || middle.present || head.present }

    /// The children's playground while they build and play (half its width, in units round siteX): the walkers
    /// turn before they reach it. The place is chosen far enough from the screen's edges that the playground
    /// never covers one (a walker coming in at an edge would otherwise have nowhere to go).
    static let playHalfWidth: F = 85
    var playing: Bool { state == .building || state == .finished }

    private static func sign(_ v: F) -> F { v > 0 ? 1 : v < 0 ? -1 : 0 }

    func update(_ dt: F, _ widthU: F) {
        let dt = dt * speed
        clock += dt
        justFinished = false
        let lo = Self.playHalfWidth + 40, hi = max(lo, widthU - Self.playHalfWidth - 40)
        if !started {
            // The app may start in the middle of a build: somewhere, some way along.
            started = true
            siteX = lo + R() * (hi - lo)
            state = .building
            t = R() * Self.buildTime * 0.95
            let test = (ProcessInfo.processInfo.environment["JULE_SNOWMAN_START"] ?? "").split(separator: ",").map { Double($0) }
            if let s = test.first ?? nil { t = max(0, min(Self.buildTime - 1, F(s))) }
            if test.count > 1, let x = test[1] { siteX = max(lo, min(hi, F(x))) }
            for k in kids { k.x = siteX + (R() - 0.5) * 80; k.targetX = k.x }
            ErrorLog.debug("snowman: building at x=\(Int(siteX)), \(Int(t)) s along")
        }
        siteX = max(lo, min(hi, siteX))

        switch state {
        case .walking:
            if !kids.contains(where: { abs($0.x - $0.targetX) > 1.5 }) {
                state = .building; t = 0
                ErrorLog.debug("snowman: starting a new one at x=\(Int(siteX))")
            }
        case .building:
            t += dt
            if t >= Self.buildTime {
                t = Self.buildTime
                state = .finished
                stateTimer = 0
                throwTimer = 3
                justFinished = true
                plowAt = clock + 120 + R() * 120
                ErrorLog.debug("snowman: finished, the plow comes in \(Int(plowAt - clock)) s")
            }
        case .finished:
            stateTimer += dt
            // If the plow cannot come now (already out, or switched off), ask again a minute later.
            if plowAt >= 0 && clock >= plowAt { wantsPlow = true; plowAt = clock + 60 }
        case .runDown:
            stateTimer -= dt
            if stateTimer <= 0 && !kids.contains(where: { $0.waving }) { moveOn(lo, hi) }
        }

        placeBalls(dt)
        setTargets(dt)
        moveKids(dt, widthU)
        updateSnowballs(dt)
    }

    /// The plow has reached the snowman: it is gone, and the children start again elsewhere after a while.
    func runOver() {
        state = .runDown
        stateTimer = 5
        plowAt = -1
        wantsPlow = false
        snowballs.removeAll()
        for b in balls { b.present = false }
        dressed = 0
        for k in kids { k.throwT = -1; go(k, k.x, .sad, Self.sign(siteX - k.x)) }
    }

    private func moveOn(_ lo: F, _ hi: F) {
        let old = siteX, away = min(250, (hi - lo) * 0.3)
        for _ in 0..<12 {
            siteX = lo + R() * (hi - lo)
            if abs(siteX - old) >= away { break }
        }
        state = .walking
        go(kids[0], siteX - 20, .stand, 1)
        go(kids[1], siteX + 40, .pat, -1)
        go(kids[2], siteX + 15, .stand, -1)
        ErrorLog.debug("snowman: the children walk from x=\(Int(old)) to x=\(Int(siteX))")
    }

    // ------------------------------------------------------------------ the balls
    private func placeBalls(_ dt: F) {
        let built = state == .building || state == .finished
        let t = state == .finished ? Self.buildTime : self.t
        for b in balls { b.vx = 0 }

        let x0 = bottom.x
        bottom.present = built
        if bottom.present { Self.roll(bottom, t, 0, Self.bottomEnd, siteX, 30, 50, Self.bottomR) }

        let x1 = middle.x
        middle.present = built && t >= Self.middleStart
        if middle.present {
            Self.roll(middle, t, Self.middleStart, Self.middleEnd, siteX + 42, 22, 44, Self.middleR)
            Self.liftOnto(middle, t, Self.middleEnd + 10, Self.middleLift, siteX + 42, siteX, Self.middleY)
        }

        let x2 = head.x
        head.present = built && t >= Self.headStart
        if head.present {
            Self.roll(head, t, Self.headStart, Self.headEnd, siteX - 34, 14, 36, Self.headR)
            Self.liftOnto(head, t, Self.headEnd + 8, Self.headLift, siteX - 34, siteX, Self.headY)
        }

        if dt > 0 {
            bottom.vx = (bottom.x - x0) / dt
            middle.vx = (middle.x - x1) / dt
            head.vx = (head.x - x2) / dt
        }
        // (nothing is worn once the plow has run it down: the build's clock stands still until they begin again)
        dressed = !built || t < Self.dressStart ? 0 : min(Self.items, Int((t - Self.dressStart) / Self.itemTime))
    }

    private static func smooth(_ a: F, _ b: F, _ x: F) -> F {
        let f = max(0, min(1, (x - a) / (b - a)))
        return f * f * (3 - 2 * f)
    }

    /// A ball rolled back and forth around its home while it grows, coming to rest at home.
    private static func roll(_ b: Ball, _ t: F, _ t0: F, _ t1: F, _ home: F, _ amp: F, _ period: F, _ r: F) {
        let u = min(t, t1) - t0
        let f = max(0, min(1, u / (t1 - t0)))
        b.r = 2.5 + (r - 2.5) * pow(f, 0.6)
        let settle = 1 - smooth(t1 - 0.15 * (t1 - t0), t1, t0 + u)
        b.x = home + amp * sin(2 * .pi * u / period) * settle
        b.y = b.r
        b.roll = (b.x - home) / max(1, b.r)
    }

    /// Lifted in an arc from where it was rolled onto the ball below.
    private static func liftOnto(_ b: Ball, _ t: F, _ t0: F, _ t1: F, _ from: F, _ to: F, _ y: F) {
        if t < t0 { return }
        let f = smooth(t0, t1, t)
        b.x = from + (to - from) * f
        b.y = b.r + (y - b.r) * f + sin(.pi * f) * 6
    }

    // ------------------------------------------------------------------ the children
    private func go(_ k: Kid, _ x: F, _ want: Pose, _ face: F) {
        k.targetX = x
        k.want = want
        k.faceDir = face
    }

    private func pushBall(_ k: Kid, _ b: Ball) {
        // from behind, in the direction it rolls
        let dir = abs(b.vx) > 0.05 ? Self.sign(b.vx) : (k.faceDir != 0 ? k.faceDir : 1)
        go(k, b.x - dir * (b.r + 6), .push, dir)
    }

    /// Each item is put on by one of the two big children in turn, reaching up for the last seconds of its turn.
    private func dress(_ k: Kid, _ parity: Int, _ x: F, _ face: F) {
        let u = t - Self.dressStart
        let slot = Int(u / Self.itemTime)
        let mine = slot < Self.items && slot % 2 == parity && u - F(slot) * Self.itemTime > Self.itemTime - 7
        go(k, x, mine ? .lift : .stand, face)
    }

    private func setTargets(_ dt: F) {
        let a = kids[0], b = kids[1], small = kids[2]
        let br = Self.bottomR
        if state == .building {
            // the oldest rolls the bottom ball, helps lift the middle one, rolls the head and dresses it
            if t < Self.bottomEnd { pushBall(a, bottom) }
            else if t < Self.middleEnd + 10 { go(a, siteX - br - 7, .pat, 1) }
            else if t < Self.middleLift { go(a, siteX - br - 5, .lift, 1) }
            else if t < Self.headEnd { pushBall(a, head) }
            else if t < Self.headLift { go(a, siteX - br - 6, .lift, 1) }
            else { dress(a, 0, siteX - br - 6, 1) }

            // the second makes snow ready, then rolls the middle ball and lifts it up
            if t < Self.middleStart { go(b, siteX + 40, .pat, -1) }
            else if t < Self.middleEnd { pushBall(b, middle) }
            else if t < Self.middleEnd + 10 { go(b, siteX + 42 + Self.middleR + 5, .stand, -1) }
            else if t < Self.middleLift { go(b, siteX + br + 5, .lift, -1) }
            else if t < Self.headLift { go(b, siteX + br + 7, .pat, -1) }
            else { dress(b, 1, siteX + br + 6, -1) }
        } else if state == .finished {
            if stateTimer < 5 {
                // hooray, beside it (not in front, where they would hide it)
                go(a, siteX - 30, .jump, 1)
                go(b, siteX + 30, .jump, -1)
                go(small, siteX + 48, .jump, -1)
            } else {
                // a snowball fight in front of the snowman
                if a.throwT < 0 { go(a, siteX - 60, .stand, 1) }
                if b.throwT < 0 { go(b, siteX + 60, .stand, -1) }
                throwTimer -= dt
                let ready = abs(a.x - a.targetX) < 1 && abs(b.x - b.targetX) < 1
                if throwTimer <= 0 && ready {
                    let thrower = nextThrower == 0 ? a : b
                    nextThrower ^= 1
                    thrower.throwT = 0
                    throwTimer = 2.5 + R() * 4
                }
            }
        }

        // the little one wanders about, pats snow and jumps
        if state == .building || (state == .finished && stateTimer >= 5) {
            wanderTimer -= dt
            if wanderTimer <= 0 {
                wanderTimer = 6 + R() * 6
                let r = R()
                let x = siteX + (R() - 0.5) * 110
                go(small, x, r < 0.45 ? .pat : r < 0.7 ? .jump : .stand, Self.sign(siteX - x))
            }
        }
    }

    private func moveKids(_ dt: F, _ widthU: F) {
        for k in kids {
            k.t += dt
            if k.t > 200 * .pi { k.t -= 200 * .pi }
            k.targetX = max(10, min(widthU - 10, k.targetX))
            let d = k.targetX - k.x
            if k.waving {
                k.pose = .wave
                k.lift = 0
                continue
            }
            if abs(d) > 1 {
                let step = Self.sign(d) * min(abs(d), k.speed * dt)
                k.x += step
                k.dir = Self.sign(d)
                k.pose = .walk
                k.walkPhase += abs(step) / (4.5 * k.size)
            } else {
                // at the target (a pushed ball moves on slowly: the legs keep walking)
                k.walkPhase += abs(d) / (4.5 * k.size)
                k.x = k.targetX
                k.pose = k.want
                if k.faceDir != 0 { k.dir = k.faceDir }
            }
            if k.throwT >= 0 {
                let before = k.throwT
                k.throwT += dt
                k.pose = .throwing
                if before < 0.3 && k.throwT >= 0.3 { throwAt(k, k === kids[0] ? kids[1] : kids[0]) }
                if k.throwT > 0.7 { k.throwT = -1 }
            }
            k.lift = k.pose == .jump ? abs(sin(k.t * 6)) * 7 : 0
        }
    }

    // ------------------------------------------------------------------ snowballs
    private func throwAt(_ from: Kid, _ to: Kid) {
        let s = Snowball()
        s.x = from.x + from.dir * 7 * from.size
        s.y = 32 * from.size
        let flight = 0.9 + R() * 0.3
        s.targetX = to.x + (R() - 0.5) * 16
        let ty = 26 * to.size
        s.vx = (s.targetX - s.x) / flight
        s.vy = (ty - s.y + 0.5 * Self.gravity * flight * flight) / flight
        snowballs.append(s)
    }

    private func updateSnowballs(_ dt: F) {
        for i in stride(from: snowballs.count - 1, through: 0, by: -1) {
            let s = snowballs[i]
            if s.life >= 0 {
                s.life -= dt
                if s.life < 0 { snowballs.remove(at: i) }
                continue
            }
            s.x += s.vx * dt
            s.y += s.vy * dt
            s.vy -= Self.gravity * dt
            let past = s.vx > 0 ? s.x >= s.targetX : s.x <= s.targetX
            if past || s.y <= 0 { s.y = max(0, s.y); s.life = 0.5 }
        }
    }
}
