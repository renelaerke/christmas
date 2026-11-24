import AppKit
import IOKit.ps
import QuartzCore
import ServiceManagement
import UserNotifications

/// Styrer det hele: menulinje-ikon, hovedløkke, julemanden (på tværs af skærme), effekter og daglige begivenheder.
/// Selve tegningen sker i ét ScreenOverlay-vindue pr. skærm.
final class Controller: NSObject, NSMenuDelegate, UNUserNotificationCenterDelegate {
    let cfg = Settings.load()
    /// Seconds since start (a Double, so long uptimes do not lose precision).
    var time: Double = 0
    var stormUntil: Double = -1
    var wind: F = 0
    var fullscreenRects: [CGRect] = []
    /// Snow on other apps' window edges (WindowSnow.swift): window number → pile, the same as a list, and falling clumps.
    var ledges: [Int: Ledge] = [:]
    var ledgeList: [Ledge] = []
    var clumps: [SnowClump] = []

    // julemanden, i globale koordinater (origo øverst til venstre på hovedskærmen)
    var santaActive = false
    var santaX: F = 0, santaY0: F = 0, santaDir: F = 1, santaSpeed: F = 0, santaPhase: F = 0, santaScale: F = 1
    private var santaMinX: F = 0, santaMaxX: F = 0
    var sparks: [Spark] = []

    static let snowmanMaxStage = 12
    var snowmanStage = 1
    /// The Christmas snowman is built by children in real time (SnowmanBuild, drawn in OverlaySnowman.swift);
    /// only the other themes' form of it still grows by the day (snowmanStage).
    let build = SnowmanBuild()

    private(set) var overlays: [ScreenOverlay] = []
    /// The offscreen "third screen" behind the user in the virtual camera; only exists while the camera is in use.
    private var virtualScene: ScreenOverlay?
    private(set) lazy var camera = VirtualCamera(controller: self)
    private let cameraInstaller = CameraInstaller()
    func installCamera() { cameraInstaller.install() }
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var tickCount = 0, tickWindow: CFTimeInterval = 0
    private var lastT = CACurrentMediaTime()
    private var windTarget: F = 0, windTimer: F = 0, santaNext: F = 5, sparkAcc: F = 0, fsTimer: F = 0, topTimer: F = 0, dayTimer: F = 0
    private var powerTimer: F = 0
    private var celebrateAt: Double = -1, plowAt: Double = -1
    private var lastDay: Date?
    private var statusItem: NSStatusItem!
    private var calendarWindow: CalendarWindow?
    private var menuActions: [MenuAction] = []
    private var santaCameraItem: NSMenuItem!, plowCameraItem: NSMenuItem!
    /// The same twelve days in autumn: the haystack grows, then the scarecrow is put up beside it.
    static let scarecrowSteps = [
        "en lille bunke hø", "mere hø", "en hel høstak", "en stolpe til fugleskræmslet", "en tværpind til armene", "et hoved af sækkelærred",
        "en ternet skjorte", "hænder af halm", "et ansigt", "et grønt halstørklæde", "en stråhat", "et græskar og en krage - fugleskræmslet er færdigt!"]
    private var kiteItem: NSMenuItem!
    private var countdownItem: NSMenuItem!,snowmanItem: NSMenuItem!, autostartItem: NSMenuItem!
    private(set) var powerSave = false

    var santaY: F { santaY0 + sin(santaPhase * 0.9) * 40 * santaScale }
    /// 0 light, 1 normal, 2 storm. Setting 3 ("Skiftende vejr") lets the weather pick (see Weather).
    var effectiveSnowLevel: Int { let a = snowAmount; return a > 1.5 ? 2 : a > 0.5 ? 1 : 0 }
    /// The same as a number that glides between the levels while the weather changes (0 light … 2 storm): the
    /// number of flakes follows this, so a change comes on gradually; wind, speed and drifts follow the level.
    var snowAmount: F { time < stormUntil ? 2 : cfg.snowLevel == 3 ? F(Weather.amount()) : F(cfg.snowLevel) }
    var snowOn: Bool { cfg.snow || time < stormUntil }
    var theme: Theme { Theme(rawValue: cfg.theme) ?? .jul }
    /// Nisser or elves in the Christmas theme: the user's choice, or by language and region (see Folk).
    var folk: Folk { Folk.chosen(cfg.folk) }

    /// Snowfall slowly drifts between ~60 % and ~140 % of the chosen amount (two slow waves of about
    /// 3 and 7 minutes with random phases), so it feels organic but averages out to the chosen level.
    private let snowPhaseA = Double.random(in: 0..<(2 * .pi)), snowPhaseB = Double.random(in: 0..<(2 * .pi))
    var snowIntensity: F {
        if time < stormUntil { return 1 }
        return F(1 + 0.25 * sin(time * 2 * .pi / 190 + snowPhaseA) + 0.15 * sin(time * 2 * .pi / 430 + snowPhaseB))
    }

    override init() {
        super.init()
        if cfg.firstRun == nil { cfg.firstRun = JuleClock.today; cfg.save() }
        buildStatusItem()
        buildOverlays()
        startUpdater()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            DispatchQueue.main.async { self.updateDaily(startup: true) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        }
        // Stop completely while the displays sleep, the screen saver runs, the screen is locked or another user is active.
        // Each reason is tracked on its own, so e.g. the screen saver ending in front of the lock screen does not wake the overlay.
        let ws = NSWorkspace.shared.notificationCenter
        for (name, reason, sleeping) in [(NSWorkspace.screensDidSleepNotification, "display", true), (NSWorkspace.screensDidWakeNotification, "display", false),
                                         (NSWorkspace.sessionDidResignActiveNotification, "session", true), (NSWorkspace.sessionDidBecomeActiveNotification, "session", false)] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.setAsleep(reason, sleeping) }
        }
        let dnc = DistributedNotificationCenter.default()
        for (name, reason, sleeping) in [("com.apple.screenIsLocked", "lock", true), ("com.apple.screenIsUnlocked", "lock", false),
                                         ("com.apple.screensaver.didstart", "saver", true), ("com.apple.screensaver.didstop", "saver", false)] {
            dnc.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in self?.setAsleep(reason, sleeping) }
        }
        updatePowerSave()
        startTimer()
    }

    private var asleep = false
    private var currentFps: Double = 0

    /// Every screen update makes WindowServer recomposite the overlay, which is what really costs power.
    /// So the calm scene runs at a low frame rate, and only fast things (Santa, the plow, sparks) get a smooth 60 fps.
    private var desiredFps: Double {
        if let f = Double(ProcessInfo.processInfo.environment["JULE_FPS"] ?? "") { return f }
        let calm = Double(powerSave ? min(cfg.frameRate, 12) : cfg.frameRate)
        // the camera background is small and blended with the camera: 20 fps is plenty, also while Santa flies
        if camera.active && cfg.cameraPausesScreens {
            // 30 fps while Santa or the plow moves in the camera picture, otherwise 20
            let moving = santaActive || plow.active || !sparks.isEmpty
            return moving ? 30 : 20
        }
        // Santa (and his sparks/star showers) moves fast and needs 60 fps to look fluent.
        if santaActive || !sparks.isEmpty { return max(calm, powerSave ? 30 : 60) }
        // The plow is slow (~175 pt/s), so 30 fps is smooth enough and costs about half as much.
        if plow.active || !clumps.isEmpty || overlays.contains(where: { $0.isBusy }) { return max(calm, powerSave ? 20 : 30) }
        return calm
    }
    private var sleepReasons = Set<String>()
    private func setAsleep(_ reason: String, _ on: Bool) {
        if on { sleepReasons.insert(reason) } else { sleepReasons.remove(reason) }
        // once the user is back in their session, the screen saver is certainly over
        if !on && (reason == "lock" || reason == "session") { sleepReasons.remove("saver") }
        ErrorLog.debug("asleep \(reason)=\(on) -> \(sleepReasons.sorted())")
        let s = !sleepReasons.isEmpty
        if s == asleep { return }
        asleep = s
        if s { finishRuns(); stopTicker() } else { lastT = CACurrentMediaTime(); startTimer() }
    }

    /// Ends Santa's trip and the plow run at once, as if they had arrived. Called when the overlay stops
    /// (screen saver, display sleep, lock) or the frames stalled: otherwise they stay "on the way" with the jingle looping.
    private func finishRuns() {
        if santaActive || plow.active { ErrorLog.debug("finish runs: santa=\(santaActive) plow=\(plow.active)") }
        if santaActive { santaActive = false; santaNext = 60 + R() * 120 }
        sparks.removeAll()
        clumps.removeAll()
        if plow.active { plow.active = false; plow.cooldown = 30 }
        audio.stopAll()
    }

    /// Frames follow the display's refresh (a display link), so at e.g. 20 fps on a 120 Hz screen every frame
    /// lands exactly 6 refreshes apart. A plain Timer drifts against the refresh and makes motion judder.
    private func startTimer() {
        stopTicker()
        let fps = desiredFps
        currentFps = fps
        guard let screen = NSScreen.screens.first else { return }
        let l = screen.displayLink(target: self, selector: #selector(linkFired(_:)))
        let f = Float(fps)
        l.preferredFrameRateRange = CAFrameRateRange(minimum: f, maximum: f, preferred: f)
        l.add(to: .main, forMode: .common)   // keeps running while the menu is open
        link = l
    }

    private func stopTicker() { link?.invalidate(); link = nil }

    @objc private func linkFired(_ l: CADisplayLink) {
        // Safety net in case the system delivers more callbacks than asked for: skip early ones.
        let now = CACurrentMediaTime()
        if now - lastTick < 1 / currentFps - 0.004 { return }
        lastTick = now
        if ProcessInfo.processInfo.environment["JULE_TICKS"] != nil {
            tickCount += 1
            if now - tickWindow >= 5 {
                FileHandle.standardError.write("ticks/s: \(Double(tickCount) / (now - tickWindow))\n".data(using: .utf8)!)
                tickCount = 0; tickWindow = now
            }
        }
        tick()
    }

    private func updatePowerSave() {
        var onBattery = false
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String? {
            onBattery = type == "Battery Power"
        }
        let low = ProcessInfo.processInfo.isLowPowerModeEnabled
        let ps = cfg.powerSave == 1 || (cfg.powerSave == 2 && (onBattery || low))
        if ps != powerSave { powerSave = ps; if link != nil && !asleep { startTimer() } }
    }

    // ------------------------------------------------------------------ skærme
    /// Test aid (--skærmskift-test): rebuilds the overlays every 0.3 s, like rapid display changes.
    func startDisplayChangeTest() {
        let t = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in self?.buildOverlays() }
        RunLoop.main.add(t, forMode: .common)
    }

    /// Test aid (--kamera-scene-test=DIR): runs the virtual camera background without a camera and saves it as PNG.
    func testVirtualScene(dir: String) {
        let v = ScreenOverlay(virtualFor: self, width: F(VirtualCamera.width), height: F(VirtualCamera.height))
        virtualScene = v
        overlays.append(v)
        santaNext = 1000
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.sendSantaToCamera(); self?.sendPlowToCamera() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            func save(_ img: CGImage?, _ name: String) {
                guard let img else { return }
                try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
            }
            save(v.renderSceneImage(), "kamera-baggrund.png")
            let (back, front) = v.renderSceneImages()
            save(back, "kamera-bag-personen.png"); save(front, "kamera-foran-personen.png")
        }
    }

    /// Creates or removes the virtual screen when the camera starts or stops being used.
    func virtualSceneChanged() {
        if camera.wantsScene, virtualScene == nil {
            let v = ScreenOverlay(virtualFor: self, width: F(VirtualCamera.width), height: F(VirtualCamera.height))
            virtualScene = v
            overlays.append(v)
            santaNext = min(santaNext, 8)   // let Santa visit the meeting early on
        } else if !camera.wantsScene, let v = virtualScene {
            overlays.removeAll { $0 === v }
            v.close()
            virtualScene = nil
        }
    }

    /// The screen directly to the left (dir < 0) or right (dir > 0) of `o`, edge to edge, if any.
    func neighbor(of o: ScreenOverlay, dir: F) -> ScreenOverlay? {
        overlays.first { other in
            other !== o && (dir > 0 ? abs(other.screenBounds.minX - o.screenBounds.maxX) < 2 : abs(other.screenBounds.maxX - o.screenBounds.minX) < 2)
        }
    }

    /// Display changes arrive in bursts (connecting a screen sends many notifications within milliseconds),
    /// so the overlays are rebuilt once things have settled, and the frame source is moved to the current main screen.
    private var screenChangeWork: DispatchWorkItem?
    private func screensChanged() {
        screenChangeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            buildOverlays()
            if !asleep { startTimer() }
        }
        screenChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func buildOverlays() {
        for o in overlays { o.close() }
        overlays.removeAll()
        for s in NSScreen.screens {
            if !cfg.allScreens && s.frame.origin != .zero { continue }
            overlays.append(ScreenOverlay(controller: self, screen: s))
        }
        if let v = virtualScene { overlays.append(v) }
        santaActive = false
        plow.active = false
    }

    // ------------------------------------------------------------------ hovedløkke
    private func tick() {
        let now = CACurrentMediaTime()
        // frames stopped for a while (e.g. a screen saver we got no notice of): let Santa and the plow arrive
        if now - lastT > 2 && lastT > 0 { finishRuns() }
        let dt = F(min(0.1, now - lastT))
        lastT = now
        time += Double(dt)

        dayTimer -= dt
        if dayTimer <= 0 {
            dayTimer = 30
            if JuleClock.today != lastDay { updateDaily(startup: false) }
        }
        powerTimer -= dt
        if powerTimer <= 0 { powerTimer = 5; updatePowerSave() }
        fsTimer -= dt
        if fsTimer <= 0 {
            // with snow on windows the scan runs 4× a second, so piles follow moved windows and fall soon after a minimize
            // and every frame while a window with snow moves, so a minimized window drops its snow at once
            fsTimer = !cfg.windowSnow ? 1 : ledgeList.contains(where: { $0.moving && $0.hasSnow }) ? 0 : 0.25
            let scan = Self.scanWindows()
            fullscreenRects = scan.fullscreen
            updateLedges(scan.ledges)
        }
        topTimer -= dt
        if topTimer <= 0 { topTimer = 5; for o in overlays { o.keepOnTop() } }

        updateWind(dt)
        updateSanta(dt)
        updateSound(dt)
        updateSparks(dt)
        updatePlow(dt)
        updateWindowSnow(dt)
        if celebrateAt > 0 && time >= celebrateAt { celebrateAt = -1; snowmanCelebrate() }
        if plowAt >= 0 && time >= plowAt { plowAt = -1; sendPlow() }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // While JuleHygge Kamera is in use the desktop overlay pauses, so only the camera picture is computed.
        let screensSuspended = camera.active && cfg.cameraPausesScreens
        for o in overlays where !o.isVirtual { o.setSuspended(screensSuspended) }
        for o in overlays { o.frame(dt) }
        CATransaction.commit()
        camera.tick(dt, scene: virtualScene)
        if desiredFps != currentFps && !asleep { startTimer() }
        if let s = snapshot, time >= s.at { snapshot = nil; writeSnapshots(to: s.dir) }
    }

    /// Test aid (--snapshot=DIR[,SECONDS]): renders each screen's overlay onto a dark background as a PNG,
    /// since screenshots need the Screen Recording permission.
    var snapshot: (dir: String, at: Double)?

    private func writeSnapshots(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // JULE_SNAPSHOT_SCALE=3 saves the pictures at that many pixels per point, to look at small figures close up.
        // (Those are drawn layer by layer, as for the camera: CALayer.render takes many seconds at that size.)
        let k = F(Double(ProcessInfo.processInfo.environment["JULE_SNAPSHOT_SCALE"] ?? "") ?? 0)
        for (i, o) in overlays.enumerated() {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("screen\(i).png")
            if k >= 1 {
                if let img = o.renderSceneImage(scale: min(4, k), background: C(40, 55, 80)) {
                    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: url)
                }
                continue
            }
            let w = Int(o.W), h = Int(o.H)
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.setFillColor(C(40, 55, 80)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            (o.root.presentation() ?? o.root).render(in: ctx)
            if let img = ctx.makeImage() {
                try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: url)
            }
        }
        if let v = calendarWindow?.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("calendar.png"))
        }
        ErrorLog.debug("snapshot written to \(dir)")
    }

    private func updateWind(_ dt: F) {
        windTimer -= dt
        if windTimer <= 0 {
            windTimer = 3 + R() * 6
            let storm = effectiveSnowLevel == 2
            windTarget = (R() * 2 - 1) * (storm ? 140 : 30) + (storm ? 60 : 0)
        }
        wind += (windTarget - wind) * min(1, dt * 0.5)
    }

    // ------------------------------------------------------------------ julemanden
    /// Sends Santa over a random screen, or over `screen` only (e.g. the camera scene).
    func launchSanta(on screen: ScreenOverlay? = nil) {
        if santaActive || overlays.isEmpty { return }
        // ordinary trips go over the real screens; the camera scene only gets Santa when sent there
        guard let target = screen ?? overlays.filter({ !$0.isVirtual }).randomElement() else { return }
        let b = target.screenBounds
        // In the camera picture Santa is smaller and flies in a band where the whole sleigh (with its bobbing)
        // stays inside the picture; on the desktop anywhere in the upper part of the screen.
        let baseScale: F = target.isVirtual ? 0.85 : target.S
        // Size and pace are two separate things, each drawn per trip: Santa is ±15 % in size, and the geese
        // pass anywhere from far off (half size, and quieter) to close by. The speed never follows the size.
        // In the camera picture nothing grows: the band it flies in only has room for the ordinary size.
        flyerDepth = theme == .efteraar ? 0.5 + R() * 0.7 : 0.85 + R() * 0.3
        if target.isVirtual { flyerDepth = min(1, flyerDepth) }
        santaScale = baseScale * flyerDepth
        santaY0 = b.minY + b.height * (target.isVirtual ? 0.25 + R() * 0.06 : 0.12 + R() * 0.25)
        // fly over every real screen at the same height (the camera scene is a world of its own)
        santaMinX = b.minX; santaMaxX = b.maxX
        if !target.isVirtual {
            for o in overlays where !o.isVirtual {
                let lb = o.screenBounds
                if santaY0 >= lb.minY && santaY0 < lb.maxY { santaMinX = min(santaMinX, lb.minX); santaMaxX = max(santaMaxX, lb.maxX) }
            }
        }
        santaDir = R() < 0.5 ? 1 : -1
        santaX = santaDir > 0 ? santaMinX - 420 * santaScale : santaMaxX + 420 * santaScale
        // ±10 % speed per trip, and the jingle plays at the same rate (a little faster and higher, or slower and lower)
        let pace = 0.9 + R() * 0.2
        jingleIndex = Int.random(in: 0..<jingles.count)
        jingles[jingleIndex].rate = Float(pace)
        // the geese: alone two trips out of three, otherwise in wind; in a storm always the one with the wind
        if theme == .efteraar {
            jingleIndex = effectiveSnowLevel == 2 || R() < 1.0 / 3 ? 1 : 0
            gooseVoices[jingleIndex].rate = Float(pace)
        }
        santaSpeed = 230 * pace * baseScale * (santaMaxX - santaMinX > b.width * 1.5 ? 1.6 : 1)
        santaPhase = 0
        santaActive = true
    }

    private func updateSanta(_ dt: F) {
        if !santaActive {
            if cfg.santa && theme.hasSanta {
                santaNext -= dt
                if santaNext <= 0 {
                    // while the desktop is paused for the camera, Santa visits the meeting instead
                    if screensPausedForCamera, let v = virtualScene { launchSanta(on: v) } else { launchSanta() }
                    santaNext = 60 + R() * 120
                }
            }
            return
        }
        santaX += santaDir * santaSpeed * dt
        santaPhase += dt
        if theme.santaSparkles { sparkAcc += dt * 45 }
        while sparkAcc >= 1 {
            sparkAcc -= 1
            let sp = Spark()
            sp.x = santaX - santaDir * 90 * santaScale + (R() - 0.5) * 10 * santaScale
            sp.y = santaY + (R() - 0.3) * 20 * santaScale
            sp.vx = -santaDir * (10 + R() * 30) * santaScale
            sp.vy = (R() - 0.5) * 20 * santaScale
            sp.max = 0.8 + R() * 1.4; sp.life = sp.max
            sp.size = (1.5 + R() * 3) * santaScale
            sp.gold = R() < 0.6
            sparks.append(sp)
        }
        if (santaDir > 0 && santaX > santaMaxX + 450 * santaScale) || (santaDir < 0 && santaX < santaMinX - 450 * santaScale) {
            santaActive = false
            santaNext = 60 + R() * 120
        }
    }

    // ------------------------------------------------------------------ lyd
    private let audio = AudioHub()
    /// Three tunes; each of Santa's trips picks one at random.
    private lazy var jingles = Synth.Tune.all.map { t in audio.voice({ Synth.jingle(t) }, loops: true, varispeed: true) }
    /// Autumn's flyer has two moods instead of tunes (the flock alone, or in wind); `jingleIndex` picks one.
    private lazy var gooseVoices = (0..<Synth.gooseMoods.count).map { m in audio.voice({ Synth.geese(mood: m) }, loops: true, varispeed: true) }
    private var jingleIndex = 0
    /// This trip's size (1 = the ordinary size); for the geese also how loud they are.
    private var flyerDepth: F = 1
    private lazy var plowEngine = audio.voice(Synth.plowEngine, loops: true)
    private lazy var plowScrape = audio.voice(Synth.plowScrape, loops: true)
    private lazy var leafSuction = audio.voice(Synth.leafSuction, loops: true)
    private lazy var plowHorn = audio.voice(Synth.plowHorn, loops: false)
    private var hornedThisRun = false

    private var volume: Float { [0.15, 0.35, 0.6][max(0, min(2, cfg.soundLevel))] }
    private var soundMuted: Bool { cfg.pauseFullscreen && !fullscreenRects.isEmpty }

    /// Pans each sound with what makes it (Santa, the plow) across all screens and fades it at the edges.
    private func updateSound(_ dt: F) {
        let d = Float(dt)
        let span = max(1, santaMaxX - santaMinX)
        let margin = 330 * santaScale
        let presence = max(0, min(1, min(santaX - (santaMinX - margin), (santaMaxX + margin) - santaX) / margin))
        let on = santaActive && cfg.sound && !soundMuted
        let autumn = theme == .efteraar
        let pan = Float((santaX - santaMinX) / span * 2 - 1)
        // the flyer's own sound for the theme; the other theme's sound fades out if it was playing
        for (i, v) in jingles.enumerated() where (cfg.sound && !autumn && i == jingleIndex) || v.playing {
            v.update(level: on && !autumn && i == jingleIndex ? Float(presence) * volume : 0, pan: pan, dt: d)
        }
        for (i, v) in gooseVoices.enumerated() where (cfg.sound && autumn && i == jingleIndex) || v.playing {
            v.update(level: on && autumn && i == jingleIndex ? Float(presence * min(1, flyerDepth)) * volume : 0, pan: pan, dt: d)
        }
        if cfg.plowSound || plowEngine.playing || plowScrape.playing || leafSuction.playing {
            let span = max(1, plow.maxX - plow.minX)
            let margin: F = 300
            let presence = max(0, min(1, min(plow.gx - (plow.minX - margin), (plow.maxX + margin) - plow.gx) / margin))
            let pan = Float((plow.gx - plow.minX) / span * 2 - 1)
            let on = plow.active && cfg.plowSound && !soundMuted
            plowEngine.update(level: on ? Float(presence) * volume * 0.8 : 0, pan: pan, dt: d)
            // scraping gets louder with the amount of snow in front of the blade
            let load = Float(min(1, sqrt(plow.pushed / 2000)))
            plowScrape.update(level: on && !autumn ? Float(presence) * volume * (0.15 + 0.85 * load) : 0, pan: pan, dt: d)
            // the leaf collector sucks instead of scraping: the fan runs all the time, a little harder with a full nozzle
            if autumn || leafSuction.playing {
                leafSuction.update(level: on && autumn ? Float(presence) * volume * (0.55 + 0.45 * load) : 0, pan: pan, dt: d)
            }
            if on && !hornedThisRun && presence > 0.6 { hornedThisRun = true; plowHorn.playOnce(level: volume, pan: pan) }
        }
        if !plow.active { hornedThisRun = false }
        audio.idleCheck()
    }


    private func updateSparks(_ dt: F) {
        sparks.removeAll { sp in
            sp.life -= dt
            if sp.life <= 0 { return true }
            sp.x += sp.vx * dt
            sp.y += sp.vy * dt
            sp.vy += 12 * santaScale * dt
            return false
        }
    }

    // ------------------------------------------------------------------ effekter (bruges af julekalenderen)
    func triggerEffect(_ effect: Int) {
        switch effect {
        case 1: launchSanta()
        case 2: stormUntil = time + 25
        case 3: nisseParty()
        case 4: starShower()
        case 5: launchSanta(); starShower(); nisseParty()
        default: break
        }
    }

    // ------------------------------------------------------------------ sneplov
    /// One plow run in global coordinates, driving continuously across side-by-side screens (like Santa).
    final class PlowRun {
        var active = false
        var gx: F = 0, dir: F = 1, nextDir: F = 1, wheel: F = 0, pushed: F = 0, cooldown: F = 20
        var minX: F = 0, maxX: F = 0
        var members = Set<ObjectIdentifier>()
    }
    let plow = PlowRun()
    private let plowSpeed: F = 170, plowScale: F = 1.15

    /// Sends the plow out now (menu, --sneplov), starting from the main screen's row of screens.
    /// Sends Santa into the JuleHygge Kamera picture (only while the camera is in use).
    func sendSantaToCamera() {
        guard let v = virtualScene else { return }
        if santaActive { santaActive = false; sparks.removeAll() }   // take him off the desktop and into the meeting
        launchSanta(on: v)
    }

    /// Sends the snow plow across the JuleHygge Kamera picture (only while the camera is in use).
    func sendPlowToCamera() {
        guard let v = virtualScene else { return }
        if plow.active { plow.active = false }
        startPlow(from: v)
    }

    /// True while the desktop overlay is paused because JuleHygge Kamera is in use: then everything happens in the camera picture.
    private var screensPausedForCamera: Bool { camera.active && cfg.cameraPausesScreens && virtualScene != nil }

    func sendPlow() {
        if screensPausedForCamera { sendPlowToCamera(); return }
        if let o = overlays.first(where: { $0.isPrimary && !$0.isVirtual }) ?? overlays.first(where: { !$0.isVirtual }) { startPlow(from: o) }
    }

    private func startPlow(from start: ScreenOverlay) {
        if plow.active { return }
        // all screens joined edge to edge with the starting screen, left and right
        var row = [start]
        var grew = true
        while grew {
            grew = false
            let lo = row.map { $0.screenBounds.minX }.min()!, hi = row.map { $0.screenBounds.maxX }.max()!
            for o in overlays where !row.contains(where: { $0 === o }) {
                let b = o.screenBounds
                if abs(b.maxX - lo) < 2 || abs(b.minX - hi) < 2 { row.append(o); grew = true }
            }
        }
        plow.minX = row.map { $0.screenBounds.minX }.min()!
        plow.maxX = row.map { $0.screenBounds.maxX }.max()!
        plow.members = Set(row.map { ObjectIdentifier($0) })
        plow.dir = plow.nextDir
        plow.nextDir = -plow.nextDir
        let sc = start.S * plowScale
        plow.gx = plow.dir > 0 ? plow.minX - 110 * sc : plow.maxX + 110 * sc
        plow.pushed = 0
        plow.active = true
        ErrorLog.debug("plow start dir=\(plow.dir) from \(plow.minX) to \(plow.maxX)")
    }

    private func updatePlow(_ dt: F) {
        if !plow.active {
            plow.cooldown -= dt
            // while the screens are paused for the camera only the camera picture is plowed (the others are hidden)
            if cfg.plow && theme.hasPlow && plow.cooldown <= 0,
               let o = overlays.first(where: { $0.isVirtual == screensPausedForCamera && $0.heapAverage > 18 * $0.S * 0.75 }) { startPlow(from: o) }
            return
        }
        // speed and size follow the screen the truck is on
        let here = overlays.first { plow.members.contains(ObjectIdentifier($0)) && plow.gx >= $0.screenBounds.minX && plow.gx < $0.screenBounds.maxX }
            ?? overlays.first { plow.members.contains(ObjectIdentifier($0)) }
        let s = here?.S ?? 1
        plow.gx += plow.dir * plowSpeed * s * dt
        plow.wheel += plowSpeed * s * dt / (10 * s * plowScale)
        if (plow.dir > 0 && plow.gx > plow.maxX + 260 * s * plowScale) || (plow.dir < 0 && plow.gx < plow.minX - 260 * s * plowScale) {
            plow.active = false
            plow.cooldown = 30
            ErrorLog.debug("plow done")
        }
    }

    /// A few minutes after the children have finished their snowman on `o`, the plow comes by and runs it down.
    /// (If it cannot come now, the children ask again a minute later.)
    func plowWanted(by o: ScreenOverlay) {
        guard cfg.plow && cfg.snowman && theme.childrenBuild && !plow.active else { return }
        // while the screens are paused for the camera only the camera picture is plowed (the others are hidden)
        if o.isVirtual != screensPausedForCamera { return }
        startPlow(from: o)
    }

    func sendPlowAfter(_ seconds: Double) { plowAt = time + (seconds > 0 ? seconds : 0) }

    private func nisseParty() { for o in overlays { o.nisseWave(6) } }

    private func starShower() {
        for o in overlays {
            let b = o.screenBounds
            for _ in 0..<90 {
                let sp = Spark()
                sp.x = b.minX + R() * b.width
                sp.y = b.minY - R() * b.height * 0.8
                sp.vx = (R() - 0.5) * 20 * o.S
                sp.vy = (140 + R() * 140) * o.S
                sp.max = 5 + R() * 3; sp.life = sp.max
                sp.size = (3 + R() * 4) * o.S
                sp.gold = R() < 0.8
                sp.star = true
                sparks.append(sp)
            }
        }
    }

    /// Sparkles around the snowman (the children's, when finished: on that screen only) or around what grows
    /// by the day in the other themes (a new stage).
    func snowmanCelebrate(on screen: ScreenOverlay? = nil) {
        guard cfg.snowman else { return }
        let small = theme.childrenBuild
        let wide: F = small ? 60 : 90, high: F = small ? 70 : 120
        for o in overlays where screen == nil || o === screen {
            guard o.isPrimary, let p = o.snowmanPos else { continue }
            let s = o.S
            for _ in 0..<(small ? 45 : 70) {
                let sp = Spark()
                sp.x = p.x + (R() - 0.5) * wide * s
                sp.y = p.y - R() * high * s
                sp.vx = (R() - 0.5) * 60 * s
                sp.vy = -(20 + R() * 60) * s
                sp.max = 1.5 + R() * 1.5; sp.life = sp.max
                sp.size = (2 + R() * 3) * s
                sp.gold = R() < 0.6
                sparks.append(sp)
            }
        }
    }

    // ------------------------------------------------------------------ daglige begivenheder
    private func updateDaily(startup: Bool) {
        let today = JuleClock.today
        lastDay = today
        CalendarContent.syncYear(cfg, today)
        snowmanStage = max(1, min(Self.snowmanMaxStage, JuleClock.days(from: cfg.firstRun ?? today, to: today) + 1))

        var title: String?, msg: String?, opensCalendar = false
        if snowmanStage > cfg.snowmanSeenStage {
            // (only what grows by the day gets the notice; the Christmas snowman is built while you watch)
            if cfg.snowmanSeenStage > 0 && cfg.snowman && !theme.childrenBuild {
                title = "Høstakken vokser!"
                msg = "Pindsvinene og egernene har bygget videre. I dag kom der " + Self.scarecrowSteps[snowmanStage - 1]
                celebrateAt = time + 2
            }
            cfg.snowmanSeenStage = snowmanStage
            cfg.save()
        }
        let d = JuleClock.parts(today)
        if d.month == 12 && d.day <= 24 && !cfg.openedDoors.contains(d.day) && cfg.lastDoorNotice != today {
            title = "Dagens låge er klar!"
            msg = "Låge \(d.day) i julekalenderen venter på dig. Klik her for at åbne kalenderen."
            opensCalendar = true
            cfg.lastDoorNotice = today
            cfg.save()
        }
        if msg == nil && startup {
            title = "Jule-hygge er tændt"
            msg = "Klik på snefnug-ikonet i menulinjen for indstillinger og julekalender."
        }
        if let title, let msg { notify(title, msg, opensCalendar: opensCalendar) }
    }

    private func notify(_ title: String, _ body: String, opensCalendar: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["kalender": opensCalendar]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { err in
            if let err { ErrorLog.write("notification: \(err)") }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let opens = response.notification.request.content.userInfo["kalender"] as? Bool ?? false
        DispatchQueue.main.async { if opens { self.showCalendar() } }
        completionHandler()
    }

    func showCalendar() {
        if calendarWindow == nil { calendarWindow = CalendarWindow(controller: self) { [weak self] in self?.calendarWindow = nil } }
        NSApp.activate(ignoringOtherApps: true)
        calendarWindow?.makeKeyAndOrderFront(nil)
    }

    // ------------------------------------------------------------------ menulinje-ikon og menu
    /// Menu items whose text follows the theme: the Christmas title, and the autumn one (nil = the element has no
    /// autumn form yet, so the item is hidden there). Applied each time the menu opens (menuNeedsUpdate).
    /// `folk` holds the Christmas title for a folk that is not called nisser there (none = the same title; an empty
    /// title = that folk has no such thing, so the item is hidden).
    private var themedItems: [(item: NSMenuItem, jul: String, efteraar: String?, folk: [Folk: String])] = []
    private var folkItem: NSMenuItem!
    /// Every menu item with its Danish title, which is the key to its text in the user's language (see Lang). The
    /// titles are set each time the menu opens, so a change of language shows at once.
    private var titledItems: [(item: NSMenuItem, da: String)] = []
    private var calendarItem: NSMenuItem!, versionItem: NSMenuItem!, languageItem: NSMenuItem!

    private func themed(_ it: NSMenuItem, _ efteraar: String?, alfer: String? = nil, folk: [Folk: String] = [:]) -> NSMenuItem {
        themedItems.append((it, it.title, efteraar, alfer.map { [.alfer: $0] } ?? folk))
        return it
    }

    /// The same for a submenu's own title and its choices (nil keeps a choice's text).
    private func themed(_ parent: NSMenuItem, _ efteraar: String, choices: [String?], folk: [Folk: String] = [:]) -> NSMenuItem {
        themedItems.append((parent, parent.title, efteraar, folk))
        for (it, name) in zip(parent.submenu?.items ?? [], choices) { if let name { themedItems.append((it, it.title, name, [:])) } }
        return parent
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = AppIcon.menuBarImage
        statusItem.button?.toolTip = "Jule-hygge"

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let cal = item("Julekalender…") { [unowned self] _ in showCalendar() }
        cal.attributedTitle = NSAttributedString(string: "Julekalender…", attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
        calendarItem = cal
        menu.addItem(themed(cal, nil))
        countdownItem = NSMenuItem(title: Self.countdown(), action: nil, keyEquivalent: "")
        countdownItem.isEnabled = false
        menu.addItem(themed(countdownItem, nil))
        menu.addItem(themed(.separator(), nil))

        menu.addItem(choice("Tema", Theme.names, [0, 1], { $0.theme }, { [unowned self] in $0.theme = $1; buildOverlays() }))
        menu.addItem(themed(toggle("Snevejr", { $0.snow }, { $0.snow = $1 }), "Løvfald"))
        menu.addItem(themed(choice("Snemængde", ["Let sne", "Normal", "Snestorm", "Skiftende vejr"], [0, 1, 2, 3], { $0.snowLevel }, { $0.snowLevel = $1 }),
                            "Mængde af blade", choices: ["Få blade", nil, "Efterårsstorm", nil]))
        menu.addItem(themed(toggle("Sne i bunden af skærmen", { $0.snowGround }, { $0.snowGround = $1 }), "Blade i bunden af skærmen"))
        menu.addItem(themed(toggle("Sne på vinduerne", { $0.windowSnow }, { $0.windowSnow = $1 }), "Blade på vinduerne"))
        snowmanItem = toggle("Snemand", { $0.snowman }, { $0.snowman = $1 })
        menu.addItem(themed(snowmanItem, "Høstak med fugleskræmsel"))
        // the kite only exists in autumn: shown there, hidden in the Christmas theme
        kiteItem = toggle("Drage", { $0.kite }, { $0.kite = $1 })
        menu.addItem(kiteItem)
        menu.addItem(.separator())

        menu.addItem(themed(toggle("Julemanden", { $0.santa }, { $0.santa = $1 }), "Trækgæs"))
        menu.addItem(themed(item("Send julemanden afsted nu!") { [unowned self] _ in
            if screensPausedForCamera { sendSantaToCamera() } else { launchSanta() }
        }, "Send gæssene afsted nu!"))
        menu.addItem(themed(toggle("Lyd: bjælder og jingle når julemanden flyver", { $0.sound }, { $0.sound = $1 }), "Lyd: gåsetræk når gæssene flyver"))
        menu.addItem(.separator())

        menu.addItem(themed(toggle("Sneplov rydder sneen", { $0.plow }, { $0.plow = $1 }), "Løvsuger rydder bladene"))
        menu.addItem(themed(item("Send sneploven ud nu!") { [unowned self] _ in sendPlow() }, "Send løvsugeren ud nu!"))
        menu.addItem(themed(toggle("Lyd: motor, skraben og horn fra sneploven", { $0.plowSound }, { $0.plowSound = $1 }), "Lyd: motor, sug og horn fra løvsugeren"))
        menu.addItem(choice("Lydstyrke", ["Lav", "Middel", "Høj"], [0, 1, 2], { $0.soundLevel }, { $0.soundLevel = $1 }))
        menu.addItem(.separator())

        menu.addItem(themed(toggle("Nisser", { $0.nisser }, { $0.nisser = $1 }), "Pindsvin og egern",
                            folk: [.alfer: "Alfer", .wichtel: "Wichtel", .kabouter: "Kabouters", .paekapikk: "Päkapikud"]))
        menu.addItem(themed(choice("Antal nisser pr. skærm", ["1", "2", "3", "5", "8", "12"], [1, 2, 3, 5, 8, 12], { $0.nisseCount }, { $0.nisseCount = $1 }),
                            "Antal dyr pr. skærm", choices: [],
                            folk: [.alfer: "Antal alfer pr. skærm", .wichtel: "Antal Wichtel pr. skærm", .kabouter: "Antal kabouters pr. skærm", .paekapikk: "Antal päkapikud pr. skærm"]))
        // Nisser or elves: automatic follows the Mac's language and region; the other two are for when that is wrong.
        // The walkers change clothes at once (their pictures are kept per folk), so nothing is rebuilt.
        folkItem = choice("Nisser eller alfer", ["Automatisk efter sprog og land"] + Folk.names, [0] + Folk.allCases.map(\.rawValue), { $0.folk }, { $0.folk = $1 })
        menu.addItem(themed(folkItem, nil))
        menu.addItem(.separator())

        menu.addItem(themed(choice("Strømspare",
                            ["Fra - fuld sne på hele skærmen", "Til - sne kun nederst, stille blæser", "Kun på batteri eller i strømsparetilstand"],
                            [0, 1, 2], { $0.powerSave }, { [unowned self] in $0.powerSave = $1; updatePowerSave() }),
                            "Strømspare", choices: ["Fra - blade på hele skærmen", "Til - blade kun nederst, stille blæser", nil]))
        menu.addItem(themed(choice("Billedfrekvens",
                            ["12 billeder/s - mindst strøm", "20 billeder/s - normal", "30 billeder/s - glattere sne", "60 billeder/s - helt glat, mest strøm"],
                            [12, 20, 30, 60], { $0.frameRate }, { [unowned self] in $0.frameRate = $1; startTimer() }),
                            "Billedfrekvens", choices: [nil, nil, "30 billeder/s - glattere løvfald", nil]))
        santaCameraItem = item("Send julemanden ind i kameraet") { [unowned self] _ in sendSantaToCamera() }
        plowCameraItem = item("Send sneploven ind i kameraet") { [unowned self] _ in sendPlowToCamera() }
        menu.addItem(themed(santaCameraItem, "Send gæssene ind i kameraet"))
        menu.addItem(themed(plowCameraItem, "Send løvsugeren ind i kameraet"))
        menu.addItem(themed(toggle("Nissehue på i kameraet", { $0.cameraHat }, { $0.cameraHat = $1 }), "Sydvest på i kameraet",
                            folk: [.alfer: "Alfehue på i kameraet", .wichtel: "Wichtelhue på i kameraet", .kabouter: "Kabouterhue på i kameraet", .paekapikk: "Päkapikk-hue på i kameraet"]))
        menu.addItem(themed(toggle("Nisseskæg i kameraet", { $0.cameraBeard }, { $0.cameraBeard = $1 }), nil,
                            folk: [.alfer: "", .wichtel: "Wichtelskæg i kameraet", .kabouter: "Kabouterskæg i kameraet", .paekapikk: ""]))
        menu.addItem(themed(toggle("Nissedragt i kameraet", { $0.cameraSuit }, { $0.cameraSuit = $1 }), "Regnfrakke i kameraet",
                            folk: [.alfer: "Alfedragt i kameraet", .wichtel: "Wichtelfrakke i kameraet", .kabouter: "Kabouterjakke i kameraet", .paekapikk: "Päkapikk-dragt i kameraet"]))
        menu.addItem(themed(toggle("Nisser og sne foran mig i kameraet", { $0.cameraFront }, { $0.cameraFront = $1 }), "Dyr og blade foran mig i kameraet",
                            folk: [.alfer: "Alfer og sne foran mig i kameraet", .wichtel: "Wichtel og sne foran mig i kameraet", .kabouter: "Kabouters og sne foran mig i kameraet", .paekapikk: "Päkapikud og sne foran mig i kameraet"]))
        menu.addItem(item("Installér JuleHygge Kamera (baggrund i Teams)…") { [unowned self] _ in cameraInstaller.install() })
        menu.addItem(toggle("Pause skærmene mens JuleHygge Kamera bruges", { $0.cameraPausesScreens }, { $0.cameraPausesScreens = $1 }))
        menu.addItem(item("Fjern JuleHygge Kamera") { [unowned self] _ in cameraInstaller.remove() })
        menu.addItem(item("Licens for tøjmodellen i kameraet…") { _ in LicenseWindow.show() })
        menu.addItem(.separator())
        menu.addItem(themed(toggle("Julelys", { $0.lights }, { $0.lights = $1 }), "Løvranke med lygter"))
        menu.addItem(toggle("Vis på alle skærme", { $0.allScreens }, { [unowned self] in $0.allScreens = $1; buildOverlays() }))
        menu.addItem(toggle("Pause ved fuldskærm (spil/film)", { $0.pauseFullscreen }, { $0.pauseFullscreen = $1 }))
        autostartItem = item("Start ved login") { it in
            Self.setAutostart(!Self.autostart)
            it.state = Self.autostart ? .on : .off
        }
        menu.addItem(autostartItem)
        menu.addItem(.separator())
        languageItem = languageMenu()
        menu.addItem(languageItem)
        menu.addItem(.separator())
        versionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        if Updater.isReleaseBuild {
            menu.addItem(toggle("Opdatér automatisk", { $0.autoUpdate }, { $0.autoUpdate = $1 }))
            menu.addItem(item("Søg efter opdatering nu") { [unowned self] _ in checkForUpdate(manual: true) })
        }
        menu.addItem(.separator())
        menu.addItem(item("Afslut") { [unowned self] _ in exit() })
        statusItem.menu = menu
        // Test aid: JULE_MENU_DUMP=FILE writes the menu as it would open, one line per item (to check a language).
        if let path = ProcessInfo.processInfo.environment["JULE_MENU_DUMP"], !path.isEmpty {
            menuNeedsUpdate(menu)
            var lines: [String] = []
            func dump(_ m: NSMenu, _ indent: String) {
                for it in m.items where !it.isHidden {
                    lines.append(it.isSeparatorItem ? indent + "---" : indent + (it.state == .on ? "✓ " : "  ") + it.title)
                    if let sub = it.submenu { dump(sub, indent + "    ") }
                }
            }
            dump(menu, "")
            try? (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // only meaningful while an app (Teams, Photo Booth…) uses JuleHygge Kamera
        let inCamera = virtualScene != nil
        santaCameraItem.isEnabled = inCamera
        plowCameraItem.isEnabled = inCamera
        santaCameraItem.toolTip = inCamera ? nil : L("Virker når JuleHygge Kamera er i brug i Teams eller en anden app")
        plowCameraItem.toolTip = santaCameraItem.toolTip
        let autumn = theme == .efteraar
        // every text in the user's language: first each item's own title, then the ones that follow the theme
        // and the folk, then the ones with a number or a name in them
        for t in titledItems { t.item.title = L(t.da) }
        for t in themedItems {
            let own = t.folk[folk]
            t.item.isHidden = autumn ? t.efteraar == nil : own == ""
            if !t.item.isSeparatorItem { t.item.title = L(autumn ? (t.efteraar ?? t.jul) : (own ?? t.jul)) }
        }
        calendarItem.attributedTitle = NSAttributedString(string: L("Julekalender…"), attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
        folkItem.submenu?.items.first?.title = L("Automatisk efter sprog og land ({0})", L(Folk.system.name))
        versionItem.title = Updater.isReleaseBuild ? L("Version {0}", Updater.current) : L(Updater.notUpdatingReason)
        // (the menu "Sprog" also says "Language", so it can be found by someone who cannot read the language chosen)
        languageItem.title = L("Sprog") == "Language" ? "Language" : L("Sprog") + " / Language"
        let chosen = Lang.all[cfg.language] != nil ? cfg.language : ""
        for it in languageItem.submenu?.items ?? [] { it.state = (it.representedObject as? String) == chosen ? .on : .off }
        languageItem.submenu?.items.first?.title = L("Automatisk ({0})", Lang.all[Lang.automatic]?.name ?? Lang.automatic)
        kiteItem.isHidden = !autumn
        countdownItem.title = Self.countdown()
        // (the Christmas snowman has no stage: the children build it while you watch)
        if autumn { snowmanItem.title = L("Høstak med fugleskræmsel (trin {0} af {1})", snowmanStage, Self.snowmanMaxStage) }
        autostartItem.state = Self.autostart ? .on : .off
    }

    /// `title` is Danish and is shown in the user's language (false: it is a name or a number, shown as it is).
    private func item(_ title: String, translated: Bool = true, _ action: @escaping (NSMenuItem) -> Void) -> NSMenuItem {
        let a = MenuAction(action)
        menuActions.append(a)
        let it = NSMenuItem(title: title, action: #selector(MenuAction.run(_:)), keyEquivalent: "")
        it.target = a
        if translated { titledItems.append((it, title)) }
        return it
    }

    /// The menu "Sprog": automatic (the Mac's own language, or English when there is no file for it), and every
    /// language there is a file for, each under its own name.
    private func languageMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Sprog", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        for (name, code) in [("", "")] + Lang.listed.map({ ($0.name, $0.code) }) {
            let it = item(name, translated: false) { [unowned self] _ in
                cfg.language = code
                Lang.setting = code
                cfg.save()
            }
            it.representedObject = code
            sub.addItem(it)
        }
        parent.submenu = sub
        return parent
    }

    private func toggle(_ title: String, _ get: @escaping (Settings) -> Bool, _ set: @escaping (Settings, Bool) -> Void) -> NSMenuItem {
        let it = item(title) { [unowned self] it in
            set(cfg, !get(cfg))
            it.state = get(cfg) ? .on : .off
            cfg.save()
        }
        it.state = get(cfg) ? .on : .off
        return it
    }

    private func choice(_ title: String, _ names: [String], _ values: [Int], _ get: @escaping (Settings) -> Int,
                        _ set: @escaping (Settings, Int) -> Void) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        titledItems.append((parent, title))
        let sub = NSMenu()
        sub.autoenablesItems = false
        for (name, v) in zip(names, values) {
            let it = item(name) { [unowned self] _ in
                set(cfg, v)
                for o in sub.items { o.state = o.tag == v ? .on : .off }
                cfg.save()
            }
            it.tag = v
            it.state = get(cfg) == v ? .on : .off
            sub.addItem(it)
        }
        parent.submenu = sub
        return parent
    }

    // ------------------------------------------------------------------ automatic update
    // A release build checks GitHub 1 minute after start and then every 6 hours. A newer release is downloaded,
    // checked and swapped in, and the app restarts into it (see Updater).
    private var updateTimer: Timer?
    private var updateRunning = false

    private func startUpdater() {
        guard Updater.isReleaseBuild else { return }
        let now = Updater.current.description
        if cfg.lastVersion != now {
            if !cfg.lastVersion.isEmpty { notify("Jule-hygge er opdateret", "Du kører nu version \(now).", opensCalendar: false) }
            cfg.lastVersion = now
            cfg.save()
        }
        // (JULE_UPDATE_DELAY=seconds shortens the wait before the first check, for tests)
        let first = ProcessInfo.processInfo.environment["JULE_UPDATE_DELAY"].flatMap(Double.init) ?? 60
        updateTimer = Timer.scheduledTimer(withTimeInterval: first, repeats: false) { [weak self] _ in
            guard let self else { return }
            if cfg.autoUpdate { checkForUpdate(manual: false) }
            updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
                guard let self, cfg.autoUpdate else { return }
                checkForUpdate(manual: false)
            }
        }
    }

    /// manual = the user asked from the menu, so every outcome is reported.
    private func checkForUpdate(manual: Bool) {
        if updateRunning { return }
        updateRunning = true
        DispatchQueue.global(qos: .utility).async {
            let r = Updater.checkAndDownload()
            DispatchQueue.main.async { [weak self] in self?.finishUpdate(r, manual: manual) }
        }
    }

    private func finishUpdate(_ r: Updater.Result, manual: Bool) {
        updateRunning = false
        if let error = r.error {
            ErrorLog.write("update failed: \(error)")
            if manual { notify("Opdatering", "Kunne ikke opdatere: \(error)", opensCalendar: false) }
            return
        }
        guard let app = r.newApp, let version = r.version else {
            if manual { notify("Opdatering", "Du har den nyeste version (\(Updater.current)).", opensCalendar: false) }
            return
        }
        do { try Updater.install(app) }
        catch {
            ErrorLog.write("update install: \(error)")
            if manual { notify("Opdatering", "Kunne ikke installere version \(version): \(error.localizedDescription)", opensCalendar: false) }
            return
        }
        ErrorLog.debug("update: installed \(version), restarting")
        // Under the supervisor, a special exit code makes it start the new app. Without one, it is started from here.
        shutDown()
        if ProcessInfo.processInfo.environment["JULE_SUPERVISOR"] != nil { Foundation.exit(Updater.restartExitCode) }
        Updater.relaunchAfterExit()
        Foundation.exit(0)
    }

    private func exit() {
        shutDown()
        NSApp.terminate(nil)
    }

    /// Stops everything and saves the settings.
    private func shutDown() {
        camera.stop()
        audio.stopAll()
        stopTicker()
        calendarWindow?.close()
        for o in overlays { o.close() }
        overlays.removeAll()
        cfg.save()
    }

    static func countdown() -> String {
        let today = JuleClock.today
        let y = JuleClock.parts(today).year
        var eve = JuleClock.make(y, 12, 24)
        if today > eve { eve = JuleClock.make(y + 1, 12, 24) }
        let d = JuleClock.days(from: today, to: eve)
        if d == 0 { return L("★ Glædelig jul! ★") }
        if d == 1 { return L("★ 1 dag til juleaften ★") }
        return L("★ {0} dage til juleaften ★", d)
    }

    /// Start at login is a plain login item. (Restart after a crash is handled by the supervisor in main.swift:
    /// launch agents via SMAppService.agent are tied to the code signature, which changes with every ad-hoc build.)
    static var autostart: Bool { SMAppService.mainApp.status == .enabled }

    static func setAutostart(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { ErrorLog.write("autostart: \(error)") }
    }

    /// A short-lived test version registered a launch agent; remove it and keep a plain login item instead.
    static func migrateAutostart() {
        let agent = SMAppService.agent(plistName: "dk.julehygge.JuleHygge.agent.plist")
        if agent.status != .notRegistered {
            try? agent.unregister()
            if !autostart { setAutostart(true) }
        }
    }
}

/// Lets a closure be the target of a menu item.
final class MenuAction: NSObject {
    let action: (NSMenuItem) -> Void
    init(_ action: @escaping (NSMenuItem) -> Void) { self.action = action }
    @objc func run(_ sender: NSMenuItem) { action(sender) }
}
