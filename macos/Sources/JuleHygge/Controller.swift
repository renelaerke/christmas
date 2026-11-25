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
    /// How far what stands in the snowman's place has come. Autumn's haystack grows a stage a day (`dailyStage`);
    /// the ofrenda of De dødes dag grows a stage for every hour the app runs with that theme (`ofrendaStage`),
    /// since the theme is only on for a couple of days.
    var snowmanStage: Int { theme.growsByHour ? ofrendaStage : dailyStage }
    private var dailyStage = 1
    /// One step of the ofrenda takes this long (seconds the app runs with the theme on).
    static let ofrendaStepTime: Double = 3600
    /// Finished, it stands until another theme is chosen; choosing the theme again starts a new altar.
    var ofrendaStage: Int { max(1, min(Self.snowmanMaxStage, Int(cfg.ofrendaSeconds / Self.ofrendaStepTime) + 1)) }
    private var ofrendaSaveTimer: F = 0
    /// JULE_SNOWMAN_SPEED=N builds the ofrenda N times faster too (3600 gives a step a second).
    private let ofrendaSpeed = max(0.01, Double(ProcessInfo.processInfo.environment["JULE_SNOWMAN_SPEED"] ?? "") ?? 1)
    /// The Christmas snowman is built by children in real time (SnowmanBuild, drawn in OverlaySnowman.swift).
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
    static let ofrendaSteps = [
        "et nederste trin med lilla dug", "et midterste trin med pink dug", "et øverste trin med turkis dug", "lys på nederste trin",
        "tagetes langs trinene", "et sukkerkranie", "lys på midterste trin", "pan de muerto (de dødes brød)", "et billede af en, vi savner",
        "en bue af tagetes", "papel picado foran alteret", "et glas vand, et lille sukkerkranie og en monarksommerfugl - ofrendaen er færdig!"]
    /// Halloween: the jack-o'-lanterns, a step for every hour the app runs, as the ofrenda.
    static let pumpkinSteps = [
        "et lille græskar", "et græskar til", "et stort græskar i midten", "stilke og en snoet ranke", "øjne i det store græskar",
        "en mund med tænder", "et lys inde i det store græskar", "et ansigt i det venstre græskar", "et ansigt i det højre græskar",
        "lys i de to små græskar", "en heksehat", "en sort kat - græskarlygterne er færdige!"]
    /// What the menu items are called on Halloween, by their Christmas title (one not here keeps its title).
    static let halloweenTitles: [String: String] = [
        "Snevejr": "Løvfald", "Snemængde": "Mængde af blade", "Let sne": "Få blade", "Snestorm": "Efterårsstorm",
        "Sne i bunden af skærmen": "Blade i bunden af skærmen", "Sne på vinduerne": "Blade, katte og edderkopper på vinduerne",
        "Snemand": "Græskarlygter", "Julemanden": "Heks på kost", "Send julemanden afsted nu!": "Send heksen afsted nu!",
        "Lyd: bjælder og jingle når julemanden flyver": "Lyd: uhyggelig melodi når heksen flyver",
        "Nisser": "Spøgelser og udklædte børn", "Antal nisser pr. skærm": "Antal spøgelser pr. skærm",
        "Fra - fuld sne på hele skærmen": "Fra - blade på hele skærmen", "Til - sne kun nederst, stille blæser": "Til - blade kun nederst, stille blæser",
        "30 billeder/s - glattere sne": "30 billeder/s - glattere løvfald", "Send julemanden ind i kameraet": "Send heksen ind i kameraet",
        "Nisser og sne foran mig i kameraet": "Spøgelser og blade foran mig i kameraet", "Julelys": "Lyskæde med græskar og flagermus",
        "Sneplov rydder sneen": "Heks eller spøgelser rydder bladene", "Send sneploven ud nu!": "Send dem ud nu!",
        "Lyd: motor, skraben og horn fra sneploven": "Lyd: kost eller spøgelsessus når bladene ryddes",
        "Send sneploven ind i kameraet": "Send dem ind i kameraet"]
    /// New Year: the clock is there from the first step (its hands are the countdown) and is decorated from then on.
    static let clockSteps = [
        "et stort ur på en stander", "en guldkant med små pærer", "en rød sløjfe", "serpentiner om standeren", "en række vimpler til venstre",
        "en række vimpler til højre", "en papirlanterne", "en papirlanterne til", "to balloner", "to balloner til", "en guldstjerne på toppen",
        "to stjernekastere - uret er pyntet færdigt!"]
    /// What the menu items are called at New Year, by their Christmas title (one not here keeps its title).
    static let nytaarTitles: [String: String] = [
        "Snevejr": "Konfetti", "Snemængde": "Mængde af konfetti", "Let sne": "Lidt konfetti", "Snestorm": "Konfettistorm",
        "Sne i bunden af skærmen": "Konfetti i bunden af skærmen", "Sne på vinduerne": "Konfetti, stjernekastere og bordbomber på vinduerne",
        "Snemand": "Ur med pynt", "Julemanden": "Raketter", "Send julemanden afsted nu!": "Send raketter op nu!",
        "Lyd: bjælder og jingle når julemanden flyver": "Lyd: melodi til raketterne og klokkeslag ved midnat",
        "Nisser": "Festgæster", "Antal nisser pr. skærm": "Antal gæster pr. skærm",
        "Fra - fuld sne på hele skærmen": "Fra - konfetti på hele skærmen", "Til - sne kun nederst, stille blæser": "Til - konfetti kun nederst, stille blæser",
        "30 billeder/s - glattere sne": "30 billeder/s - glattere konfetti", "Send julemanden ind i kameraet": "Send raketter op i kameraet",
        "Nisser og sne foran mig i kameraet": "Gæster og konfetti foran mig i kameraet", "Julelys": "Vimpler og papirlanterner",
        "Sneplov rydder sneen": "Fejemaskine rydder konfettien", "Send sneploven ud nu!": "Send fejemaskinen ud nu!",
        "Lyd: motor, skraben og horn fra sneploven": "Lyd: motor og sug fra fejemaskinen",
        "Send sneploven ind i kameraet": "Send fejemaskinen ind i kameraet", "Nissehue på i kameraet": "Festhat på i kameraet"]
    /// What New Year does not have: the advent calendar, the choice of folk, and anything in the beard's or the
    /// suit's place in the camera. (The countdown line stays: here it counts down to midnight.)
    static let nytaarHidden: Set<String> = [
        "Julekalender…", "Nisser eller alfer", "Nisseskæg i kameraet", "Nissedragt i kameraet"]
    /// What Halloween has its own item for: in the camera one choice of costume
    /// (`halloweenCameraItem`: a witch's hat or a pumpkin head) in place of hat, beard and suit.
    static let halloweenHidden: Set<String> = [
        "Nissehue på i kameraet", "Nisseskæg i kameraet", "Nissedragt i kameraet"]
    private var kiteItem: NSMenuItem!, halloweenCameraItem: NSMenuItem!
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
        if santaActive || !sparks.isEmpty || !rockets.isEmpty { return max(calm, powerSave ? 30 : 60) }
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
        rockets.removeAll()
        midnightUntil = -1
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
        rockets.removeAll()
        volleyScreens = []
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
        updateOfrenda(dt)
        updateNewYear(dt)
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
        // (New Year's flyer is a volley of rockets)
        if theme == .nytaar { launchVolley(on: screen, seconds: 12 + Double(R()) * 6); return }
        // ordinary trips go over the real screens; the camera scene only gets Santa when sent there
        guard let target = screen ?? overlays.filter({ !$0.isVirtual }).randomElement() else { return }
        let b = target.screenBounds
        // In the camera picture Santa is smaller and flies in a band where the whole sleigh (with its bobbing)
        // stays inside the picture; on the desktop anywhere in the upper part of the screen.
        let baseScale: F = target.isVirtual ? 0.85 : target.S
        // Size and pace are two separate things, each drawn per trip: Santa is ±15 % in size, and the geese
        // pass anywhere from far off (half size, and quieter) to close by. The speed never follows the size.
        // In the camera picture nothing grows: the band it flies in only has room for the ordinary size.
        flyerDepth = theme != .jul ? 0.5 + R() * 0.7 : 0.85 + R() * 0.3
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
        if theme == .muertos { butterflyTune.rate = Float(pace) }
        if theme == .halloween { witchTune.rate = Float(pace) }
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
        if theme == .nytaar { updateVolley(dt); return }
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

    // ------------------------------------------------------------------ raketter (nytår)
    // New Year's flyer in Santa's place: a volley of rockets. Each rises from the bottom of a screen with a tail
    // of sparks and bursts in a band across the top into one soft bloom of coloured sparks, which fades over a
    // second or two (never a flash, and nothing below the top band). The volley keeps Santa's schedule, his menu
    // items and his switch, and counts as "Santa is flying" for the frame rate and the tune.
    var rockets: [Rocket] = []
    private var volleyScreens: [ScreenOverlay] = []
    private var volleyLength: Double = 0, volleyNext: F = 0, volleyGap: F = 0.85

    /// Starts a volley over `screen` only (the camera's scene) or over every real screen, lasting `seconds`;
    /// `gap` is the average time between two rockets on one screen.
    private func launchVolley(on screen: ScreenOverlay?, seconds: Double, gap: F = 0.85) {
        let screens = screen.map { [$0] } ?? overlays.filter { !$0.isVirtual }
        guard !screens.isEmpty else { return }
        volleyScreens = screens
        volleyLength = seconds
        volleyGap = gap
        volleyNext = 0.3
        santaMinX = screens.map { $0.screenBounds.minX }.min()!
        santaMaxX = screens.map { $0.screenBounds.maxX }.max()!
        santaX = (santaMinX + santaMaxX) / 2
        santaY0 = screens[0].screenBounds.minY + screens[0].screenBounds.height * 0.2
        santaScale = screens[0].isVirtual ? 0.85 : screens[0].S
        santaDir = 1
        flyerDepth = 1
        auldTune.rate = Float(0.95 + R() * 0.1)
        santaPhase = 0
        santaActive = true
        ErrorLog.debug("volley: \(Int(seconds)) s over \(screens.count) screen(s)")
    }

    private func updateVolley(_ dt: F) {
        santaPhase += dt
        if Double(santaPhase) < volleyLength {
            volleyNext -= dt
            while volleyNext <= 0 {
                volleyNext += volleyGap * (0.45 + R() * 1.1) / F(volleyScreens.count)
                guard let o = volleyScreens.randomElement() else { break }
                let b = o.screenBounds
                let r = Rocket()
                r.scale = o.isVirtual ? 1 : o.S
                r.x = b.minX + b.width * (0.07 + R() * 0.86)
                r.y = b.maxY - 4 * r.scale
                r.burstY = b.minY + b.height * (0.10 + R() * 0.22)
                r.vy = -(r.y - r.burstY) / (0.9 + R() * 0.45)
                r.sway = R() * 6.28
                r.colour = 1 + Int(R() * F(Theme.confettiColours.count)) % Theme.confettiColours.count
                rockets.append(r)
            }
        } else if rockets.isEmpty && Double(santaPhase) > volleyLength + 2.5 {
            santaActive = false
            santaNext = 60 + R() * 120
            volleyScreens = []
        }
    }

    /// The rockets rise, each leaving a short tail of gold sparks, and burst where they were aimed.
    private func updateRockets(_ dt: F) {
        guard !rockets.isEmpty else { return }
        rockets.removeAll { r in
            r.y += r.vy * dt
            r.x += sin(r.sway + r.y * 0.012) * 14 * r.scale * dt
            r.trail += dt * 48
            while r.trail >= 1 {
                r.trail -= 1
                let sp = Spark()
                sp.x = r.x + (R() - 0.5) * 3 * r.scale; sp.y = r.y + R() * 8 * r.scale
                sp.vx = (R() - 0.5) * 16 * r.scale; sp.vy = (20 + R() * 30) * r.scale
                sp.max = 0.3 + R() * 0.35; sp.life = sp.max
                sp.size = (1.6 + R() * 1.6) * r.scale
                sp.gold = true
                sp.gravity = 60 * r.scale
                sparks.append(sp)
            }
            guard r.y <= r.burstY else { return false }
            burst(r)
            return true
        }
    }

    /// One burst: a round bloom of sparks in the rocket's colour, slowed by the air and sinking a little as they
    /// fade. Most are thrown out at nearly the same speed and make the shell; the rest fill it, and a few are white.
    private func burst(_ r: Rocket) {
        let n = 64
        for k in 0..<n {
            let a = 2 * F.pi * (F(k) + R()) / F(n)
            let shell = k % 3 != 0
            let v = 195 * (shell ? 0.86 + R() * 0.2 : 0.25 + R() * 0.55) * r.scale
            let sp = Spark()
            sp.x = r.x; sp.y = r.y
            sp.vx = cos(a) * v; sp.vy = sin(a) * v
            sp.drag = 1.9; sp.gravity = 30 * r.scale
            sp.max = (shell ? 1.35 : 1.0) + R() * 0.85; sp.life = sp.max
            sp.size = (shell ? 3.4 + R() * 2.4 : 2.4 + R() * 1.6) * r.scale
            sp.colour = k % 8 == 4 ? 2 : r.colour
            sparks.append(sp)
        }
    }

    // ------------------------------------------------------------------ midnat (nytår)
    // New Year is the one theme with a moment. The clock it goes by is the Mac's own, moved by the test aids:
    // JULE_DATE=2026-12-31 keeps the time of day on that date, and JULE_NYTAAR_OM=N puts midnight N seconds
    // after the app started.
    private let clockShift: TimeInterval = {
        let env = ProcessInfo.processInfo.environment
        if let n = Double(env["JULE_NYTAAR_OM"] ?? "") { return Controller.nextNewYear(after: Date()).timeIntervalSinceNow - n }
        if env["JULE_DATE"] != nil { return JuleClock.today.timeIntervalSince(Calendar.current.startOfDay(for: Date())) }
        return 0
    }()
    /// The time the New Year theme goes by (the clock's hands show it).
    var clockNow: Date { Date().addingTimeInterval(clockShift) }
    static func nextNewYear(after d: Date) -> Date { JuleClock.make(JuleClock.parts(d).year + 1, 1, 1) }
    /// The midnight that is counted down to. It stays for an hour after it has passed, then it is next year's.
    private lazy var newYearAt = Controller.nextNewYear(after: clockNow)
    /// Seconds to midnight (negative for the hour after it).
    var newYearLeft: Double { newYearAt.timeIntervalSince(clockNow) }
    /// The last minute: the clock gets its second hand.
    var newYearClose: Bool { theme == .nytaar && newYearLeft > 0 && newYearLeft <= 60 }
    /// The last ten minutes, and the minute of the burst: the guests stand round the clock.
    var gatherAtClock: Bool { theme == .nytaar && ((newYearLeft > 0 && newYearLeft <= 600) || time < midnightUntil) }
    private var lastLeft = Double.infinity, midnightUntil: Double = -1, yearAgainAt: Double = -1, jumpAt: Double = -1, tuneHoldUntil: Double = -1
    private var countedSecond = 0
    private var statusText = ""

    /// What stands beside the snowflake in the menu bar on New Year's Eve: the time left as hours:minutes, the
    /// seconds alone in the last minute, and the new year's number for the ten minutes after. Digits only, so it
    /// needs no translation. Empty on every other day.
    static func menuBarCountdown(left: Double, year: Int) -> String {
        if left > 86400 || left < -600 { return "" }
        if left <= 0 { return "\(year)" }
        if left <= 60 { return "\(Int(left.rounded(.up)))" }
        let minutes = Int((left / 60).rounded(.up))
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    private func setStatusText(_ text: String) {
        guard text != statusText else { return }
        statusText = text
        statusItem.length = text.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        statusItem.button?.imagePosition = text.isEmpty ? .imageOnly : .imageLeft
        statusItem.button?.title = text.isEmpty ? "" : " " + text
        ErrorLog.debug("menu bar: '\(text)'")
    }

    private func updateNewYear(_ dt: F) {
        guard theme == .nytaar else {
            setStatusText("")
            lastLeft = .infinity
            return
        }
        var left = newYearLeft
        if left < -3600 { newYearAt = Self.nextNewYear(after: clockNow); left = newYearLeft }
        setStatusText(Self.menuBarCountdown(left: left, year: JuleClock.parts(newYearAt).year))
        // (after the screens have slept the time left has jumped: nothing is played late)
        let running = lastLeft - left < 2
        // the last ten seconds, written in sparks over the clock, one number at a time
        let second = Int(left.rounded(.up))
        if running && left > 0 && second <= 10 && second != countedSecond {
            countedSecond = second
            countDown(second)
        }
        if running && lastLeft > 0 && left <= 0 { midnight() }
        lastLeft = left

        guard time < midnightUntil else { return }
        if jumpAt >= 0 && time >= jumpAt { jumpAt = time + 9; nisseParty() }
        if yearAgainAt >= 0 && time >= yearAgainAt { yearAgainAt = -1; writeYear() }
    }

    /// The stroke of midnight: about a minute of the big effect. Rockets one after the other over every screen
    /// (unless they are switched off), a burst of confetti, the guests jump, and the new year's number in sparks.
    /// With the sound on, twelve strokes of a bell first, and the tune after them.
    private func midnight() {
        ErrorLog.debug("midnight: \(JuleClock.parts(newYearAt).year)")
        midnightUntil = time + 60
        stormUntil = time + 35
        jumpAt = time
        writeYear()
        yearAgainAt = time + 24
        if cfg.sound && !soundMuted {
            midnightBell.playOnce(level: volume, pan: 0)
            tuneHoldUntil = time + 16.5
        }
        if cfg.santa {
            santaActive = false
            launchVolley(on: screensPausedForCamera ? virtualScene : nil, seconds: 46, gap: 0.5)
        }
    }

    // The digits are written as dots on a grid of five by seven.
    private static let digitDots: [[String]] = [
        ["01110", "10001", "10011", "10101", "11001", "10001", "01110"], ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        ["01110", "10001", "00001", "00010", "00100", "01000", "11111"], ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        ["00010", "00110", "01010", "10010", "11111", "00010", "00010"], ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        ["00110", "01000", "10000", "11110", "10001", "10001", "01110"], ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        ["01110", "10001", "10001", "01110", "10001", "10001", "01110"], ["01110", "10001", "10001", "01111", "00001", "00010", "01100"]]

    /// Writes a number in sparks, centred on (x, y) in global coordinates and `height` tall. The sparks stay lit
    /// for `life` seconds, sinking slowly, and go out at the end.
    private func writeInSparks(_ number: Int, x: F, y: F, height: F, life: F, scale: F) {
        let digits = String(number).compactMap { $0.wholeNumberValue }
        let pitch = height / 7, wide = 5 * pitch, gap = pitch * 1.7
        let total = F(digits.count) * wide + F(digits.count - 1) * gap
        for (i, d) in digits.enumerated() {
            let x0 = x - total / 2 + F(i) * (wide + gap) + pitch / 2
            for (row, line) in Self.digitDots[d].enumerated() {
                for (col, ch) in line.enumerated() where ch == "1" {
                    let sp = Spark()
                    sp.x = x0 + F(col) * pitch; sp.y = y - height / 2 + (F(row) + 0.5) * pitch
                    // (they hardly move: a number that drifts apart cannot be read)
                    sp.vx = (R() - 0.5) * 1.6 * scale; sp.vy = (R() - 0.5) * 1.6 * scale
                    sp.gravity = 1.5 * scale
                    sp.max = life * (0.85 + R() * 0.15); sp.life = sp.max
                    sp.size = pitch * 0.42
                    sp.colour = 1; sp.holds = true
                    sparks.append(sp)
                }
            }
        }
    }

    /// One of the last ten seconds: its number over the clock (or over the middle of the screen, if the clock is
    /// switched off).
    private func countDown(_ second: Int) {
        guard let o = overlays.first(where: { $0.isPrimary && !$0.isVirtual }) else { return }
        let b = o.screenBounds
        if let p = o.snowmanPos { writeInSparks(second, x: p.x, y: p.y - 178 * o.S, height: 60 * o.S, life: 0.95, scale: o.S) }
        else { writeInSparks(second, x: b.midX, y: b.minY + b.height * 0.45, height: 60 * o.S, life: 0.95, scale: o.S) }
    }

    /// The new year's number, large, in the top third of every screen.
    private func writeYear() {
        let year = JuleClock.parts(newYearAt).year
        for o in overlays {
            let b = o.screenBounds, s = o.isVirtual ? 1 : o.S
            writeInSparks(year, x: b.midX, y: b.minY + b.height * 0.3, height: min(150 * s, b.width / 7), life: 9, scale: s)
        }
    }

    // ------------------------------------------------------------------ lyd
    private let audio = AudioHub()
    /// Three tunes; each of Santa's trips picks one at random.
    private lazy var jingles = Synth.Tune.all.map { t in audio.voice({ Synth.jingle(t) }, loops: true, varispeed: true) }
    /// Autumn's flyer has two moods instead of tunes (the flock alone, or in wind); `jingleIndex` picks one.
    private lazy var gooseVoices = (0..<Synth.gooseMoods.count).map { m in audio.voice({ Synth.geese(mood: m) }, loops: true, varispeed: true) }
    /// The Day of the Dead's butterflies have their own tune (guitar and marimba).
    private lazy var butterflyTune = audio.voice(Synth.muertosSon, loops: true, varispeed: true)
    /// Halloween's witch has hers too (a thin wavering voice over a low organ).
    private lazy var witchTune = audio.voice(Synth.witchTune, loops: true, varispeed: true)
    /// New Year's rockets go up to "Auld Lang Syne" (a traditional melody, free of rights; the arrangement is ours),
    /// and midnight has twelve strokes of a bell.
    private lazy var auldTune = audio.voice(Synth.auldLangSyne, loops: true, varispeed: true)
    private lazy var midnightBell = audio.voice(Synth.midnightBell, loops: false)
    private var jingleIndex = 0
    /// This trip's size (1 = the ordinary size); for the geese also how loud they are.
    private var flyerDepth: F = 1
    private lazy var plowEngine = audio.voice(Synth.plowEngine, loops: true)
    private lazy var plowScrape = audio.voice(Synth.plowScrape, loops: true)
    private lazy var leafSuction = audio.voice(Synth.leafSuction, loops: true)
    private lazy var plowHorn = audio.voice(Synth.plowHorn, loops: false)
    /// The donkey cart's sounds: hooves and wheel, the calaca's broom, and the bray in place of the horn.
    private lazy var cartRoll = audio.voice({ Synth.donkeyCart(cycle: Controller.donkeyStepCycle) }, loops: true)
    private lazy var broomSweep = audio.voice({ Synth.broomSweep(cycle: Controller.donkeyStepCycle) }, loops: true)
    private lazy var donkeyBray = audio.voice(Synth.donkeyBray, loops: false)
    /// Halloween: the wind the ghosts blow the leaves away with.
    private lazy var ghostWind = audio.voice(Synth.ghostWind, loops: true)
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
        let autumn = theme == .efteraar, christmas = theme == .jul
        let pan = Float((santaX - santaMinX) / span * 2 - 1)
        // the flyer's own sound for the theme; the other theme's sound fades out if it was playing
        for (i, v) in jingles.enumerated() where (cfg.sound && christmas && i == jingleIndex) || v.playing {
            v.update(level: on && christmas && i == jingleIndex ? Float(presence) * volume : 0, pan: pan, dt: d)
        }
        let muertos = theme == .muertos
        if (cfg.sound && muertos) || butterflyTune.playing {
            butterflyTune.update(level: on && muertos ? Float(presence * min(1, flyerDepth)) * volume : 0, pan: pan, dt: d)
        }
        let halloween = theme == .halloween
        if (cfg.sound && halloween) || witchTune.playing {
            witchTune.update(level: on && halloween ? Float(presence * min(1, flyerDepth)) * volume : 0, pan: pan, dt: d)
        }
        let nytaar = theme == .nytaar
        if (cfg.sound && nytaar) || auldTune.playing {
            // (at midnight the tune waits for the bell's twelve strokes)
            auldTune.update(level: on && nytaar && time >= tuneHoldUntil ? Float(presence) * volume : 0, pan: 0, dt: d)
        }
        for (i, v) in gooseVoices.enumerated() where (cfg.sound && autumn && i == jingleIndex) || v.playing {
            v.update(level: on && autumn && i == jingleIndex ? Float(presence * min(1, flyerDepth)) * volume : 0, pan: pan, dt: d)
        }
        if cfg.plowSound || plowEngine.playing || plowScrape.playing || leafSuction.playing || cartRoll.playing || broomSweep.playing || ghostWind.playing {
            let span = max(1, plow.maxX - plow.minX)
            let margin: F = 300
            let presence = max(0, min(1, min(plow.gx - (plow.minX - margin), (plow.maxX + margin) - plow.gx) / margin))
            let pan = Float((plow.gx - plow.minX) / span * 2 - 1)
            let on = plow.active && cfg.plowSound && !soundMuted
            // (New Year's street sweeper is a small machine: a quieter engine, and the leaf collector's suction)
            plowEngine.update(level: on && !muertos && !halloween ? Float(presence) * volume * (nytaar ? 0.4 : 0.8) : 0, pan: pan, dt: d)
            // scraping gets louder with the amount of snow in front of the blade
            let load = Float(min(1, sqrt(plow.pushed / 2000)))
            plowScrape.update(level: on && christmas ? Float(presence) * volume * (0.15 + 0.85 * load) : 0, pan: pan, dt: d)
            // the donkey cart: hooves and wheel all the way, the broom louder with more petals in front of it
            // (Halloween's witch has the same broom; the ghosts a hollow wind of their own)
            let sweeps = muertos || (halloween && !ghostsBlow)
            if sweeps || cartRoll.playing || broomSweep.playing {
                cartRoll.update(level: on && muertos ? Float(presence) * volume * 0.9 : 0, pan: pan, dt: d)
                broomSweep.update(level: on && sweeps ? Float(presence) * volume * (0.25 + 0.75 * load) * 0.7 : 0, pan: pan, dt: d)
            }
            if (halloween && ghostsBlow) || ghostWind.playing {
                ghostWind.update(level: on && halloween && ghostsBlow ? Float(presence) * volume * (0.5 + 0.5 * load) : 0, pan: pan, dt: d)
            }
            // the leaf collector sucks instead of scraping: the fan runs all the time, a little harder with a full nozzle
            if autumn || nytaar || leafSuction.playing {
                leafSuction.update(level: on && (autumn || nytaar) ? Float(presence) * volume * (0.55 + 0.45 * load) : 0, pan: pan, dt: d)
            }
            if on && !hornedThisRun && presence > 0.6 {
                hornedThisRun = true
                // (Halloween's witch and ghosts have nothing in the horn's place: a truck's honk does not belong there)
                // (nor has New Year's sweeper: it comes the morning after)
                if !halloween && !nytaar { (muertos ? donkeyBray : plowHorn).playOnce(level: volume, pan: pan) }
            }
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
            if sp.drag > 0 { let k = exp(-sp.drag * dt); sp.vx *= k; sp.vy *= k }
            sp.vy += (sp.gravity >= 0 ? sp.gravity : 12 * santaScale) * dt
            return false
        }
        updateRockets(dt)
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
    private let plowSpeed: F = Controller.plowSpeed, plowScale: F = Controller.plowScale
    static let plowSpeed: F = 170, plowScale: F = 1.15
    /// The donkey cart walks at a donkey's pace (a share of the plow's speed).
    static let cartPace: F = 0.45
    /// Seconds per step cycle of the donkey's legs (each leg lands once), worked out from how the drawing moves
    /// them: the legs swing with sin(wheel × ScreenOverlay.donkeyStride), and the wheel turns
    /// speed × pace / (10 × scale) radians a second. The cart's hooves sound at that pace.
    static var donkeyStepCycle: Double {
        Double(2 * F.pi / ScreenOverlay.donkeyStride / (plowSpeed * cartPace / (10 * plowScale)))
    }

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

    /// Halloween's plow is one of two each run: three ghosts that blow the leaves away (true), or a witch who
    /// sweeps them up (false). Which one is random, but drawn two at a time (one of each, in random order), so
    /// over time each comes exactly half the times. `JULE_HALLOWEEN_PLOV=heks` or `=spoegelser` fixes it for tests.
    private(set) var ghostsBlow = false
    private var plowForms: [Bool] = []
    private func pickHalloweenPlow() {
        if plowForms.isEmpty { plowForms = [true, false].shuffled() }
        ghostsBlow = plowForms.removeLast()
        switch ProcessInfo.processInfo.environment["JULE_HALLOWEEN_PLOV"] {
        case "heks": ghostsBlow = false
        case "spoegelser": ghostsBlow = true
        default: break
        }
        ErrorLog.debug("halloween plow: \(ghostsBlow ? "ghosts blow" : "witch sweeps")")
    }

    private func startPlow(from start: ScreenOverlay) {
        if plow.active { return }
        if theme == .halloween { pickHalloweenPlow() }
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
        // the donkey cart walks at a donkey's pace
        // (so does Halloween's witch; the ghosts float a little faster)
        // (New Year's street sweeper trundles)
        let pace: F = theme == .muertos ? Controller.cartPace : theme == .halloween ? (ghostsBlow ? 0.6 : Controller.cartPace) : theme == .nytaar ? 0.6 : 1
        plow.gx += plow.dir * plowSpeed * pace * s * dt
        plow.wheel += plowSpeed * pace * s * dt / (10 * s * plowScale)
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
        dailyStage = max(1, min(Self.snowmanMaxStage, JuleClock.days(from: cfg.firstRun ?? today, to: today) + 1))

        var title: String?, msg: String?, opensCalendar = false
        if dailyStage > cfg.snowmanSeenStage {
            // (only what grows by the day gets the notice: the Christmas snowman is built while you watch, and the
            // ofrenda by the hour, see updateOfrenda)
            if cfg.snowmanSeenStage > 0 && cfg.snowman && theme == .efteraar {
                title = "Høstakken vokser!"
                msg = "Pindsvinene og egernene har bygget videre. I dag kom der " + Self.scarecrowSteps[dailyStage - 1]
                celebrateAt = time + 2
            }
            cfg.snowmanSeenStage = dailyStage
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

    /// The ofrenda of De dødes dag: a step for every hour the app runs with the theme on (the timer stands still
    /// while the screens sleep or are locked, so that time does not count). Each new step gets sparkles; the last
    /// one also a notice. Finished, it stands as it is until another theme is chosen (`themeChanged`).
    private func updateOfrenda(_ dt: F) {
        guard theme.growsByHour, cfg.snowman, ofrendaStage < Self.snowmanMaxStage else { return }
        let before = ofrendaStage
        cfg.ofrendaSeconds += Double(dt) * ofrendaSpeed
        ofrendaSaveTimer += dt
        let stage = ofrendaStage
        if stage != before {
            ErrorLog.debug("ofrenda: step \(stage) of \(Self.snowmanMaxStage)")
            celebrateAt = time + 0.5
            if stage == Self.snowmanMaxStage {
                if theme == .nytaar {
                    notify("Uret er pyntet færdigt!", "Gæsterne har pyntet det. Til sidst kom der " + Self.clockSteps[stage - 1], opensCalendar: false)
                } else if theme == .halloween {
                    notify("Græskarlygterne er færdige!", "Spøgelserne har skåret dem ud. Til sidst kom der " + Self.pumpkinSteps[stage - 1], opensCalendar: false)
                } else {
                    notify("Ofrendaen er færdig!", "Calacas har pyntet alteret. Til sidst kom der " + Self.ofrendaSteps[stage - 1], opensCalendar: false)
                }
            }
        }
        // (kept across a restart: saved at each step and once a minute)
        if stage != before || ofrendaSaveTimer >= 60 { ofrendaSaveTimer = 0; cfg.save() }
    }

    /// Another theme was chosen in the menu: the ofrenda is taken down, so a new one is built from its first step
    /// the next time De dødes dag is chosen.
    private func themeChanged() {
        cfg.ofrendaSeconds = 0
        ofrendaSaveTimer = 0
        celebrateAt = -1
        buildOverlays()
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
    /// `muertos` is the Day of the Dead's title (nil = hidden there). `folk` holds the Christmas title for a folk that
    /// is not called nisser there (none = the same title; an empty title = that folk has no such thing, so the item
    /// is hidden).
    private var themedItems: [(item: NSMenuItem, jul: String, efteraar: String?, muertos: String?, folk: [Folk: String])] = []
    private var folkItem: NSMenuItem!
    /// Every menu item with its Danish title, which is the key to its text in the user's language (see Lang). The
    /// titles are set each time the menu opens, so a change of language shows at once.
    private var titledItems: [(item: NSMenuItem, da: String)] = []
    private var calendarItem: NSMenuItem!, versionItem: NSMenuItem!, languageItem: NSMenuItem!

    private func themed(_ it: NSMenuItem, _ efteraar: String?, _ muertos: String?, alfer: String? = nil, folk: [Folk: String] = [:]) -> NSMenuItem {
        themedItems.append((it, it.title, efteraar, muertos, alfer.map { [.alfer: $0] } ?? folk))
        return it
    }

    /// The same for a submenu's own title and its choices (nil keeps a choice's text).
    private func themed(_ parent: NSMenuItem, _ efteraar: String, _ muertos: String, choices: [String?], muertosChoices: [String?] = [],
                        folk: [Folk: String] = [:]) -> NSMenuItem {
        themedItems.append((parent, parent.title, efteraar, muertos, folk))
        for (k, it) in (parent.submenu?.items ?? []).enumerated() {
            let a = k < choices.count ? choices[k] : nil, b = k < muertosChoices.count ? muertosChoices[k] : nil
            if a != nil || b != nil { themedItems.append((it, it.title, a ?? it.title, b ?? it.title, [:])) }
        }
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
        menu.addItem(themed(cal, nil, nil))
        countdownItem = NSMenuItem(title: Self.countdown(), action: nil, keyEquivalent: "")
        countdownItem.isEnabled = false
        menu.addItem(themed(countdownItem, nil, nil))
        menu.addItem(themed(.separator(), nil, nil))

        menu.addItem(choice("Tema", Theme.names, [0, 1, 2, 3, 4], { $0.theme }, { [unowned self] in if $0.theme != $1 { $0.theme = $1; themeChanged() } }))
        menu.addItem(themed(toggle("Snevejr", { $0.snow }, { $0.snow = $1 }), "Løvfald", "Kronblade fra tagetes"))
        menu.addItem(themed(choice("Snemængde", ["Let sne", "Normal", "Snestorm", "Skiftende vejr"], [0, 1, 2, 3], { $0.snowLevel }, { $0.snowLevel = $1 }),
                            "Mængde af blade", "Mængde af kronblade", choices: ["Få blade", nil, "Efterårsstorm", nil], muertosChoices: ["Få kronblade", nil, "Kronbladsstorm", nil]))
        menu.addItem(themed(toggle("Sne i bunden af skærmen", { $0.snowGround }, { $0.snowGround = $1 }), "Blade i bunden af skærmen", "Tagetes-tæppe i bunden af skærmen"))
        menu.addItem(themed(toggle("Sne på vinduerne", { $0.windowSnow }, { $0.windowSnow = $1 }), "Blade på vinduerne", "Kronblade på vinduerne"))
        snowmanItem = toggle("Snemand", { $0.snowman }, { $0.snowman = $1 })
        menu.addItem(themed(snowmanItem, "Høstak med fugleskræmsel", "Ofrenda (alter)"))
        // the kite only exists in autumn: shown there, hidden in the Christmas theme
        kiteItem = toggle("Drage", { $0.kite }, { $0.kite = $1 })
        menu.addItem(kiteItem)
        menu.addItem(.separator())

        menu.addItem(themed(toggle("Julemanden", { $0.santa }, { $0.santa = $1 }), "Trækgæs", "Monarksommerfugle"))
        menu.addItem(themed(item("Send julemanden afsted nu!") { [unowned self] _ in
            if screensPausedForCamera { sendSantaToCamera() } else { launchSanta() }
        }, "Send gæssene afsted nu!", "Send sommerfuglene afsted nu!"))
        menu.addItem(themed(toggle("Lyd: bjælder og jingle når julemanden flyver", { $0.sound }, { $0.sound = $1 }), "Lyd: gåsetræk når gæssene flyver", "Lyd: guitar og marimba når sommerfuglene flyver"))
        menu.addItem(.separator())

        menu.addItem(themed(toggle("Sneplov rydder sneen", { $0.plow }, { $0.plow = $1 }), "Løvsuger rydder bladene", "Æselkærre samler kronbladene"))
        menu.addItem(themed(item("Send sneploven ud nu!") { [unowned self] _ in sendPlow() }, "Send løvsugeren ud nu!", "Send æselkærren ud nu!"))
        menu.addItem(themed(toggle("Lyd: motor, skraben og horn fra sneploven", { $0.plowSound }, { $0.plowSound = $1 }), "Lyd: motor, sug og horn fra løvsugeren", "Lyd: hovtramp, hjulknirk og æselbrøl fra æselkærren"))
        menu.addItem(choice("Lydstyrke", ["Lav", "Middel", "Høj"], [0, 1, 2], { $0.soundLevel }, { $0.soundLevel = $1 }))
        menu.addItem(.separator())

        menu.addItem(themed(toggle("Nisser", { $0.nisser }, { $0.nisser = $1 }), "Pindsvin og egern", "Calacas (skeletter)",
                            folk: [.alfer: "Alfer", .wichtel: "Wichtel", .kabouter: "Kabouters", .paekapikk: "Päkapikud"]))
        menu.addItem(themed(choice("Antal nisser pr. skærm", ["1", "2", "3", "5", "8", "12"], [1, 2, 3, 5, 8, 12], { $0.nisseCount }, { $0.nisseCount = $1 }),
                            "Antal dyr pr. skærm", "Antal calacas pr. skærm", choices: [],
                            folk: [.alfer: "Antal alfer pr. skærm", .wichtel: "Antal Wichtel pr. skærm", .kabouter: "Antal kabouters pr. skærm", .paekapikk: "Antal päkapikud pr. skærm"]))
        // Nisser or elves: automatic follows the Mac's language and region; the other two are for when that is wrong.
        // The walkers change clothes at once (their pictures are kept per folk), so nothing is rebuilt.
        // (In autumn and on the Day of the Dead the walkers are animals and calacas, whatever the folk: hidden there.)
        folkItem = choice("Nisser eller alfer", ["Automatisk efter sprog og land"] + Folk.names, [0] + Folk.allCases.map(\.rawValue), { $0.folk }, { $0.folk = $1 })
        menu.addItem(themed(folkItem, nil, nil))
        menu.addItem(.separator())

        menu.addItem(themed(choice("Strømspare",
                            ["Fra - fuld sne på hele skærmen", "Til - sne kun nederst, stille blæser", "Kun på batteri eller i strømsparetilstand"],
                            [0, 1, 2], { $0.powerSave }, { [unowned self] in $0.powerSave = $1; updatePowerSave() }),
                            "Strømspare", "Strømspare", choices: ["Fra - blade på hele skærmen", "Til - blade kun nederst, stille blæser", nil], muertosChoices: ["Fra - kronblade på hele skærmen", "Til - kronblade kun nederst, stille blæser", nil]))
        menu.addItem(themed(choice("Billedfrekvens",
                            ["12 billeder/s - mindst strøm", "20 billeder/s - normal", "30 billeder/s - glattere sne", "60 billeder/s - helt glat, mest strøm"],
                            [12, 20, 30, 60], { $0.frameRate }, { [unowned self] in $0.frameRate = $1; startTimer() }),
                            "Billedfrekvens", "Billedfrekvens", choices: [nil, nil, "30 billeder/s - glattere løvfald", nil], muertosChoices: [nil, nil, "30 billeder/s - glattere kronbladsfald", nil]))
        santaCameraItem = item("Send julemanden ind i kameraet") { [unowned self] _ in sendSantaToCamera() }
        plowCameraItem = item("Send sneploven ind i kameraet") { [unowned self] _ in sendPlowToCamera() }
        menu.addItem(themed(santaCameraItem, "Send gæssene ind i kameraet", "Send sommerfuglene ind i kameraet"))
        menu.addItem(themed(plowCameraItem, "Send løvsugeren ind i kameraet", "Send æselkærren ind i kameraet"))
        // Halloween has one choice in the place of hat, beard and suit: the two costumes are alternatives
        halloweenCameraItem = choice("Udklædning i kameraet", ["Ingen", "Heksehat og heksenæse", "Græskarhoved"], [0, 1, 2], { $0.cameraHalloween }, { $0.cameraHalloween = $1 })
        menu.addItem(halloweenCameraItem)
        menu.addItem(themed(toggle("Nissehue på i kameraet", { $0.cameraHat }, { $0.cameraHat = $1 }), "Sydvest på i kameraet", "Blomsterkrans i håret i kameraet",
                            folk: [.alfer: "Alfehue på i kameraet", .wichtel: "Wichtelhue på i kameraet", .kabouter: "Kabouterhue på i kameraet", .paekapikk: "Päkapikk-hue på i kameraet"]))
        menu.addItem(themed(toggle("Nisseskæg i kameraet", { $0.cameraBeard }, { $0.cameraBeard = $1 }), nil, "Calavera-sminke på ansigtet i kameraet",
                            folk: [.alfer: "", .wichtel: "Wichtelskæg i kameraet", .kabouter: "Kabouterskæg i kameraet", .paekapikk: ""]))
        menu.addItem(themed(toggle("Nissedragt i kameraet", { $0.cameraSuit }, { $0.cameraSuit = $1 }), "Regnfrakke i kameraet", nil,
                            folk: [.alfer: "Alfedragt i kameraet", .wichtel: "Wichtelfrakke i kameraet", .kabouter: "Kabouterjakke i kameraet", .paekapikk: "Päkapikk-dragt i kameraet"]))
        menu.addItem(themed(toggle("Nisser og sne foran mig i kameraet", { $0.cameraFront }, { $0.cameraFront = $1 }), "Dyr og blade foran mig i kameraet", "Calacas og kronblade foran mig i kameraet",
                            folk: [.alfer: "Alfer og sne foran mig i kameraet", .wichtel: "Wichtel og sne foran mig i kameraet", .kabouter: "Kabouters og sne foran mig i kameraet", .paekapikk: "Päkapikud og sne foran mig i kameraet"]))
        menu.addItem(item("Installér JuleHygge Kamera (baggrund i Teams)…") { [unowned self] _ in cameraInstaller.install() })
        menu.addItem(toggle("Pause skærmene mens JuleHygge Kamera bruges", { $0.cameraPausesScreens }, { $0.cameraPausesScreens = $1 }))
        menu.addItem(item("Fjern JuleHygge Kamera") { [unowned self] _ in cameraInstaller.remove() })
        menu.addItem(item("Licens for tøjmodellen i kameraet…") { _ in LicenseWindow.show() })
        menu.addItem(.separator())
        menu.addItem(themed(toggle("Julelys", { $0.lights }, { $0.lights = $1 }), "Løvranke med lygter", "Papel picado"))
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
        let autumn = theme == .efteraar, muertos = theme == .muertos
        // every text in the user's language: first each item's own title, then the ones that follow the theme
        // and the folk, then the ones with a number or a name in them
        for t in titledItems { t.item.title = L(t.da) }
        for t in themedItems {
            let own = t.folk[folk]
            if theme == .nytaar {
                t.item.isHidden = Self.nytaarHidden.contains(t.jul)
                if !t.item.isSeparatorItem { t.item.title = L(Self.nytaarTitles[t.jul] ?? t.jul) }
            } else if theme == .halloween {
                // (hidden where the Day of the Dead hides it too: the calendar, the countdown, the choice of folk)
                t.item.isHidden = t.muertos == nil || Self.halloweenHidden.contains(t.jul)
                if !t.item.isSeparatorItem { t.item.title = L(Self.halloweenTitles[t.jul] ?? t.jul) }
            } else if muertos {
                t.item.isHidden = t.muertos == nil
                if !t.item.isSeparatorItem { t.item.title = L(t.muertos ?? t.jul) }
            } else {
                t.item.isHidden = autumn ? t.efteraar == nil : own == ""
                if !t.item.isSeparatorItem { t.item.title = L(autumn ? (t.efteraar ?? t.jul) : (own ?? t.jul)) }
            }
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
        halloweenCameraItem.isHidden = theme != .halloween
        countdownItem.title = theme == .nytaar ? newYearCountdown() : Self.countdown()
        // (the Christmas snowman has no stage: the children build it while you watch)
        if theme == .nytaar { snowmanItem.title = L("Ur med pynt (trin {0} af {1})", snowmanStage, Self.snowmanMaxStage) }
        else if theme == .halloween { snowmanItem.title = L("Græskarlygter (trin {0} af {1})", snowmanStage, Self.snowmanMaxStage) }
        else if muertos { snowmanItem.title = L("Ofrenda (alter) (trin {0} af {1})", snowmanStage, Self.snowmanMaxStage) }
        else if autumn { snowmanItem.title = L("Høstak med fugleskræmsel (trin {0} af {1})", snowmanStage, Self.snowmanMaxStage) }
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

    /// New Year's countdown line: the days to New Year's Eve, on the day itself the hours and minutes to midnight,
    /// and a greeting for the first hour of the new year.
    private func newYearCountdown() -> String {
        let left = newYearLeft
        if left <= 0 { return L("★ Godt nytår! ★") }
        let cal = Calendar.current
        let days = JuleClock.days(from: cal.startOfDay(for: clockNow), to: cal.startOfDay(for: newYearAt)) - 1
        if days >= 2 { return L("★ {0} dage til nytårsaften ★", days) }
        if days == 1 { return L("★ 1 dag til nytårsaften ★") }
        let minutes = Int((left / 60).rounded(.up))
        return L("★ {0}:{1} til midnat ★", minutes / 60, String(format: "%02d", minutes % 60))
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
