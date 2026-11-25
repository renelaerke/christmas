import AppKit

/// Snow on the top edge of other apps' windows (not fullscreen ones). Some of the falling flakes land there;
/// when the window disappears (minimized, closed, hidden, another Space) the snow falls down as clumps
/// and lands in the pile at the bottom. All in global coordinates (origin top-left of the primary screen, y down),
/// like `ScreenOverlay.screenBounds`, so a window that spans two screens carries one pile.
final class Ledge {
    static let step: F = 4
    let id: Int
    var rect: CGRect
    /// Where the window last stood still. The snow sits there: while a window moves (or shrinks into the Dock
    /// when minimized) the pile stays put, and if the window goes away, the snow falls from this spot.
    var settled: CGRect
    /// Snow height per `step` points from the window's left edge.
    var cols: [F]
    /// How far the snow hangs down over the edge (in front of the window), per column. It creeps out slowly
    /// once the pile is deep, in uneven lobes (`lobes`, fixed per window) and a little more around the corners.
    var hang: [F]
    private(set) var lobes: [F] = []
    /// Parts of the top edge (global x) not covered by a window in front.
    var visible: [(F, F)] = []
    /// True while the window is being moved or resized: the pile is hidden and catches nothing until it settles.
    var moving = false
    /// Bumped whenever the drawn shape changes, so each overlay only rebuilds its path when needed.
    var version = 0
    var hasSnow = false

    init(id: Int, rect: CGRect) {
        self.id = id; self.rect = rect; self.settled = rect
        cols = Array(repeating: 0, count: Int(rect.width / Ledge.step) + 1)
        hang = cols
        // JULE_DEEPSNOW=1 also starts every window with a full pile, to test what falls when it is minimized
        if ProcessInfo.processInfo.environment["JULE_DEEPSNOW"] != nil { cols = cols.map { _ in 8 }; hasSnow = true }
        makeLobes()
    }

    /// Uneven drapes: two slow waves with a phase from the window number, sharpened so some places hang
    /// well down and others hardly at all.
    private func makeLobes() {
        let p1 = F(id % 97) * 0.61, p2 = F(id % 89) * 1.37
        lobes = (0..<cols.count).map { i in
            let v = 0.5 + 0.5 * (0.6 * sin(F(i) * 0.23 + p1) + 0.4 * sin(F(i) * 0.57 + p2))
            return pow(max(0, min(1, v)), 2.2)
        }
    }

    func hang(at x: F) -> F {
        let i = Int((x - settled.minX) / Ledge.step)
        return i >= 0 && i < hang.count ? hang[i] : 0
    }

    func isVisible(_ x: F) -> Bool { visible.contains { x >= $0.0 && x <= $0.1 } }

    func height(at x: F) -> F {
        let i = Int((x - settled.minX) / Ledge.step)
        return i >= 0 && i < cols.count ? cols[i] : 0
    }

    func deposit(at x: F, r: F) {
        let i = Int((x - settled.minX) / Ledge.step)
        let amount = 0.3 * r
        for k in -1...1 where i + k >= 0 && i + k < cols.count { cols[i + k] += k == 0 ? amount : amount * 0.5 }
        hasSnow = true
        version += 1
    }

    /// Keeps the width in step with the window, keeping the snow that is still on it.
    func resize(to width: F) {
        let n = Int(width / Ledge.step) + 1
        if n < cols.count { cols.removeLast(cols.count - n); hang.removeLast(hang.count - n) }
        else if n > cols.count { cols += Array(repeating: 0, count: n - cols.count); hang += Array(repeating: 0, count: n - hang.count) }
        makeLobes()
    }
}

/// A lump of snow falling off a window that went away; the overlay below catches it in its ground pile.
final class SnowClump {
    var x: F = 0, y: F = 0, vx: F = 0, vy: F = 0, r: F = 0
    var dead = false
}


extension Ledge {
    /// Where the candles stand on this window (Día de los Muertos): one about every 150 points, at places fixed on
    /// the window, each with its own height. Global x.
    var candleSpots: [(gx: F, tall: F, k: Int)] {
        let count = max(1, Int((settled.width - 40) / 150))
        let gap = (settled.width - 40) / F(count)
        var spots: [(gx: F, tall: F, k: Int)] = []
        for k in 0..<count {
            let jitter: F = F((id * 7 + k * 13) % 9 - 4) * 3
            let gx: F = settled.minX + 20 + gap * (F(k) + 0.5) + jitter
            let tall: F = 14 + F((id + k * 5) % 3) * 2.5
            spots.append((gx, tall, k))
        }
        return spots
    }
}

extension Controller {
    /// Windows that can carry snow, front to back, plus the windows that cover a whole screen.
    static func scanWindows() -> (ledges: [(id: Int, rect: CGRect)], fullscreen: [CGRect]) {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return ([], []) }
        let me = ProcessInfo.processInfo.processIdentifier
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = NSScreen.screens.map { CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
        var ledges: [(Int, CGRect)] = [], full: [CGRect] = []
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bd) else { continue }
            if screens.contains(where: { abs($0.minX - r.minX) < 2 && abs($0.minY - r.minY) < 2 && abs($0.width - r.width) < 2 && abs($0.height - r.height) < 2 }) {
                full.append(r)
                continue
            }
            // ordinary, visible windows of a reasonable size whose top edge is on a screen
            let alpha = (w[kCGWindowAlpha as String] as? Double) ?? 1
            guard alpha > 0.5, r.width >= 150, r.height >= 80, let id = w[kCGWindowNumber as String] as? Int,
                  screens.contains(where: { $0.contains(CGPoint(x: r.midX, y: r.minY + 1)) }) else { continue }
            ledges.append((id, r))
        }
        return (ledges, full)
    }

    /// Matches the scanned windows with the existing ledges: windows that moved hide their snow until they settle,
    /// and windows that are gone let their snow fall.
    func updateLedges(_ wins: [(id: Int, rect: CGRect)]) {
        var seen = Set<Int>()
        let pileRoom: F = 16   // a window in front just above the edge still hides the snow
        for (i, w) in wins.enumerated() {
            seen.insert(w.id)
            let y = w.rect.minY
            var vis: [(F, F)] = [(w.rect.minX + 6, w.rect.maxX - 6)]   // rounded corners
            for f in wins[..<i] where f.rect.minY < y + 1 && f.rect.maxY > y - pileRoom {
                vis = vis.flatMap { seg -> [(F, F)] in
                    if f.rect.maxX <= seg.0 || f.rect.minX >= seg.1 { return [seg] }
                    var out: [(F, F)] = []
                    if f.rect.minX > seg.0 { out.append((seg.0, f.rect.minX)) }
                    if f.rect.maxX < seg.1 { out.append((f.rect.maxX, seg.1)) }
                    return out
                }
            }
            vis = vis.filter { $0.1 - $0.0 >= 8 }
            if let l = ledges[w.id] {
                if l.rect != w.rect {
                    l.rect = w.rect
                    if !l.moving { l.moving = true; l.version += 1 }
                } else if l.moving {
                    // came to rest: the snow moves along (and keeps what still fits on a resized window)
                    if l.settled.width != l.rect.width { l.resize(to: l.rect.width) }
                    l.settled = l.rect
                    l.moving = false; l.version += 1
                }
                if l.visible.count != vis.count || zip(l.visible, vis).contains(where: { $0.0 != $1.0 || $0.1 != $1.1 }) {
                    l.visible = vis; l.version += 1
                }
            } else {
                let l = Ledge(id: w.id, rect: w.rect)
                l.visible = vis
                ledges[w.id] = l
            }
        }
        for (id, l) in ledges where !seen.contains(id) {
            if l.hasSnow { dropSnow(from: l) }
            ledges[id] = nil
        }
        ledgeList = Array(ledges.values)
    }

    /// The window went away: its snow falls as clumps.
    private func dropSnow(from l: Ledge) {
        // At most 700 clumps fall at a time. The room that is left is shared evenly along the whole edge:
        // filling it from the left let a wide window (a maximized one needs well over 700) drop its snow from
        // its left part only, as if the window were narrower. Measured with tools/window-probe.swift: the
        // window's reported width is right until it leaves the list, so the width was never the problem.
        var wanted = 0
        for (i, h0) in l.cols.enumerated() where h0 + l.hang[i] > 0.5 { wanted += min(4, Int((h0 + l.hang[i]) / 2.5) + 1) }
        let room = max(60, 700 - clumps.count)
        let keep: F = wanted > room ? F(room) / F(wanted) : 1
        let bigger: F = min(1.5, (1 / keep).squareRoot())   // fewer clumps carry a little more each
        for (i, h0) in l.cols.enumerated() where h0 + l.hang[i] > 0.5 {
            let h = h0 + l.hang[i]
            let n = min(4, Int(h / 2.5) + 1)
            for _ in 0..<n where R() < keep {
                let c = SnowClump()
                // straight down from where the window stood, only a little spread
                c.x = l.settled.minX + F(i) * Ledge.step + R() * Ledge.step
                c.y = l.settled.minY - R() * h
                c.vx = (R() - 0.5) * 6
                c.vy = R() * 20
                c.r = (1.6 + R() * 1.8) * bigger
                clumps.append(c)
            }
        }
        ErrorLog.debug("window \(l.id) gone: wanted \(wanted) clumps over \(l.cols.count) columns, kept \(Int(keep * 100)) %, \(clumps.count) falling")
    }

    /// When the snow hangs far down somewhere, or the pile is nearly full, there is about a 1-in-15 chance per
    /// second that a 20–50 pt stretch around the longest drape breaks off: the drape and most of the pile above
    /// it fall as clumps (softly tapered at the ends of the break), and the edge then fills up again.
    private func breakOff(_ l: Ledge, _ dt: F) {
        let n = l.cols.count
        guard n > 8 else { return }
        // cheap checks first: the scan for the heaviest stretch only runs on the rare frames something breaks off
        let full = l.hang.max() ?? 0 > 9 || (l.cols.max() ?? 0) > (effectiveSnowLevel == 2 ? 12.5 : 9)
        guard full, R() < dt / 15 else { return }
        var best = -1, bestLoad: F = 0
        for i in 0..<n {
            let x = l.settled.minX + F(i) * Ledge.step
            guard l.isVisible(x) else { continue }
            let load = l.hang[i] + l.cols[i] * 0.5
            if load > bestLoad { bestLoad = load; best = i }
        }
        guard best >= 0 else { return }
        let half = 2 + Int(R() * 5)            // 5–13 columns ≈ 20–50 pt
        for j in max(0, best - half)...min(n - 1, best + half) {
            // parts of the edge hidden behind a window in front stay put (their clumps would fall in front of it)
            guard l.isVisible(l.settled.minX + F(j) * Ledge.step) else { continue }
            let k = 1 - F(abs(j - best)) / F(half + 1)       // 1 in the middle, tapering toward the ends
            let fall = 0.5 + 0.5 * cos((1 - k) * .pi)          // soft edges of the break
            let dropPile = l.cols[j] * 0.65 * fall, dropHang = l.hang[j] * fall
            l.cols[j] -= dropPile; l.hang[j] -= dropHang
            let amount = dropPile + dropHang
            guard amount > 0.4 else { continue }
            for _ in 0..<min(4, Int(amount / 2.5) + 1) where clumps.count < 700 {
                let c = SnowClump()
                c.x = l.settled.minX + F(j) * Ledge.step + R() * Ledge.step
                c.y = l.settled.minY - dropPile * R() + dropHang * R()   // from the pile's top down to the drape's end
                c.vx = (R() - 0.5) * 8 + wind * 0.05
                c.vy = R() * 15
                c.r = 1.6 + R() * 2
                clumps.append(c)
            }
        }
        l.version += 1
        ErrorLog.debug("window \(l.id): snow broke off at column \(best) (\(half * 2 + 1) columns)")
    }

    /// Settles each pile (slopes, rounded ends, no higher than ~10 pt), melts it when snow is off,
    /// and moves the falling clumps.
    func updateWindowSnow(_ dt: F) {
        let melt = !snowOn || !cfg.windowSnow
        if ProcessInfo.processInfo.environment["JULE_DEBUG"] == "1", Int(time / 5) != Int((time - Double(dt)) / 5) {
            ErrorLog.debug("ledges: " + ledgeList.map { "\($0.id) \(Int($0.settled.minX)),\(Int($0.settled.minY)) w\(Int($0.settled.width)) vis\($0.visible.count) mov\($0.moving) max\(String(format: "%.1f", $0.cols.max() ?? 0))" }.joined(separator: " | "))
        }
        // in a snowstorm the wind pushes the snow along the edge, so it drifts up against the downwind end
        let storm = effectiveSnowLevel == 2 && !melt
        let windNorm = max(-1.5, min(1.5, wind / 140))
        let maxH: F = storm ? 14 : 10, slope: F = 1.4
        for l in ledgeList where l.hasSnow {
            var any = false
            let n = l.cols.count
            if storm && abs(windNorm) > 0.15 && n > 2 {
                let rate = 0.03 * abs(windNorm) * dt, dir = windNorm > 0 ? 1 : -1
                let moved = l.cols.map { $0 * rate }
                for i in 0..<n {
                    let j = i + dir
                    if j < 0 || j >= n { continue }   // the end column keeps what reaches it: the drift
                    l.cols[i] -= moved[i]; l.cols[j] += moved[i]
                }
            }
            for i in 0..<(n - 1) {
                let d = l.cols[i] - l.cols[i + 1]
                if d > slope { let m = (d - slope) * 0.3; l.cols[i] -= m; l.cols[i + 1] += m }
                else if d < -slope { let m = (-d - slope) * 0.3; l.cols[i] += m; l.cols[i + 1] -= m }
            }
            for i in 0..<n {
                let edge = F(min(i, n - 1 - i)) * Ledge.step
                // snow rounds off toward the window's corners; in a storm the downwind end builds a steeper drift
                let downwindEnd = storm && ((windNorm > 0.15 && i > n / 2) || (windNorm < -0.15 && i < n / 2))
                // a full pile keeps soft bumps on top: the height limit itself wavers along the edge
                let bumps = 0.72 + 0.28 * F(sin(Double(i) * 0.41 + Double(l.id % 53)) * 0.6 + sin(Double(i) * 0.97 + Double(l.id % 31)) * 0.4)
                let cap = min(maxH * bumps, max(0, edge - (downwindEnd ? 2 : 6)) * (downwindEnd ? 1.0 : 0.5))
                if melt { l.cols[i] = max(0, l.cols[i] - 3 * dt) }
                // above the cap it settles back slowly (a drift sinks after the storm instead of being cut off)
                if l.cols[i] > cap { l.cols[i] = max(cap, l.cols[i] - max(2 * dt, l.cols[i] - cap - 6)) }
                if l.cols[i] > 0.3 { any = true }
            }
            // the drape: once the pile is deeper than ~3 pt it creeps over the edge (≈0.7 pt/s), as far as the
            // lobes allow, a bit further near the corners where the snow rounds over; it melts back quicker
            var hangChanged: F = 0
            for i in 0..<n {
                var s: F = 0, k = 0
                for j in max(0, i - 3)...min(n - 1, i + 3) { s += l.cols[j]; k += 1 }
                let pile = s / F(k)
                let edge = F(min(i, n - 1 - i)) * Ledge.step
                let corner: F = edge < 24 ? 1 + (24 - edge) / 24 * 0.6 : 1
                let target = melt ? 0 : max(0, pile - 3) * 2.6 * (0.12 + 0.88 * l.lobes[i]) * corner
                let old = l.hang[i]
                if target > old { l.hang[i] = min(target, old + 0.7 * dt) } else { l.hang[i] = max(target, old - 3 * dt) }
                hangChanged += abs(l.hang[i] - old)
                if l.hang[i] > 0.3 { any = true }
            }
            // a full edge does not just keep growing: now and then a heavy stretch breaks off and falls
            if !melt && any { breakOff(l, dt) }
            if melt || !any || hangChanged > 0.5 { l.version += 1 }
            l.hasSnow = any
        }
        if !clumps.isEmpty {
            for c in clumps {
                c.vy += 700 * dt
                c.x += c.vx * dt
                c.y += c.vy * dt
                if c.y > 100_000 { c.dead = true }
            }
            let bottom = overlays.filter { !$0.isVirtual }.map { $0.screenBounds.maxY }.max() ?? 0
            clumps.removeAll { $0.dead || $0.y > bottom + 50 }
        }
    }
}
