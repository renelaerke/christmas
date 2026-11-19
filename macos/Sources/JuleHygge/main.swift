import AppKit
import AVFoundation

let args = CommandLine.arguments

// build.sh: write the app icon as an .iconset folder and quit.
if let i = args.firstIndex(of: "--icon"), i + 1 < args.count {
    AppIcon.writeIconset(to: args[i + 1])
    exit(0)
}

// --lyd-test=DIR: write the synthesized sounds as WAV files (to listen to them) and quit.
if let a = args.first(where: { $0.hasPrefix("--lyd-test=") }) {
    let dir = String(a.dropFirst(11))
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for (name, make) in Synth.Tune.all.map({ t in ("julemand-" + t.name, { Synth.jingle(t) }) }) + [("sneplov-motor", Synth.plowEngine), ("sneplov-skraben", Synth.plowScrape), ("sneplov-horn", Synth.plowHorn), ("loevsuger-sug", Synth.leafSuction)]
        + Synth.gooseMoods.enumerated().map({ m in ("gaes-" + m.element, { Synth.geese(mood: m.offset) }) }) {
        guard let buf = make() else { continue }
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name + ".wav")
        if let f = try? AVAudioFile(forWriting: url, settings: buf.format.settings) { try? f.write(from: buf) }
        var peak: Float = 0, sum: Float = 0
        let d = buf.floatChannelData![0]
        for i in 0..<Int(buf.frameLength) { peak = max(peak, abs(d[i])); sum += d[i] * d[i] }
        print(name, String(format: "%.1f s  peak %.2f  rms %.3f", Double(buf.frameLength) / Synth.sampleRate, peak, sqrt(sum / Float(buf.frameLength))))
    }
    exit(0)
}

// --register-login / --unregister-login: turn start at login (with restart after a crash) on or off and quit.
// Used by install.sh, which then lets launchd start the app.
if args.contains("--register-login") { Controller.migrateAutostart(); Controller.setAutostart(true); exit(Controller.autostart ? 0 : 1) }
if args.contains("--unregister-login") { Controller.setAutostart(false); exit(0) }

// Supervisor: the app first starts as a small watchdog that runs the real app as a child process and
// restarts it if it crashes (after 5 s; it gives up after 3 crashes within a minute of each start).
// A normal quit ("Afslut") exits with 0, and then the watchdog quits too.
// --nissehue-test=DIR[,IMAGE]: draws the camera's nisse hat (and puts it on the face in IMAGE) and quits.
if let a = args.first(where: { $0.hasPrefix("--nissehue-test=") }) {
    let parts = a.dropFirst(16).split(separator: ",", maxSplits: 1).map(String.init)
    NisseHat.test(dir: parts[0], image: parts.count > 1 ? parts[1] : nil)
    exit(0)
}
// --kamera-replay=DIR: runs hat, beard and suit again on the camera pictures saved there by --kamera-debug, and quits.
if let a = args.first(where: { $0.hasPrefix("--kamera-replay=") }) {
    NisseHat.replay(dir: String(a.dropFirst(16)))
    exit(0)
}
// --opdatering-test=ZIP,VERSION: installs ZIP as if it were a downloaded release of VERSION, in place of the app
// this is run from, and quits. For a copy of the app only.
if let a = args.first(where: { $0.hasPrefix("--opdatering-test=") }) {
    let parts = a.dropFirst(18).split(separator: ",", maxSplits: 1).map(String.init)
    if parts.count == 2 { Updater.test(zip: parts[0], version: parts[1]) }
    exit(0)
}
// --vejr-test[=DAYS]: prints how "Skiftende vejr" changes over today and the following days, and quits.
if let a = args.first(where: { $0.hasPrefix("--vejr-test") }) {
    Weather.test(days: Int(a.dropFirst(12)) ?? 30)
    exit(0)
}
// --nissedragt-test=DIR,IMAGE: puts the camera's nisse beard and suit on the person in a photo, and quits.
if let a = args.first(where: { $0.hasPrefix("--nissedragt-test=") }) {
    let parts = a.dropFirst(18).split(separator: ",", maxSplits: 1).map(String.init)
    if parts.count == 2 { NisseCostume.test(dir: parts[0], image: parts[1]) }
    exit(0)
}
let isChild = ProcessInfo.processInfo.environment["JULE_SUPERVISOR"] != nil
let testFlags = ["--nissehue-test", "--vejr-test", "--opdatering-test", "--kamera-replay", "--kamera-scene-test", "--kalender", "--julemand", "--sneplov", "--snapshot", "--effekt", "--skærmskift-test"]
let wantsSupervisor = !isChild && ProcessInfo.processInfo.environment["JULE_NO_SUPERVISOR"] == nil
    && !args.dropFirst().contains(where: { a in testFlags.contains(where: { a.hasPrefix($0) }) })
if wantsSupervisor {
    if let id = Bundle.main.bundleIdentifier,
       NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != getpid() }) {
        exit(0)   // already running
    }
    var quickCrashes = 0
    while true {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = Array(args.dropFirst())
        var env = ProcessInfo.processInfo.environment
        env["JULE_SUPERVISOR"] = String(getpid())
        child.environment = env
        let started = Date()
        do { try child.run() } catch { ErrorLog.write("supervisor: \(error)"); exit(1) }
        child.waitUntilExit()
        if child.terminationReason == .exit && child.terminationStatus == 0 { exit(0) }   // normal quit
        // The child installed a new version of the app in this app's place: start that and step down (this
        // process is still the old program).
        if child.terminationReason == .exit && child.terminationStatus == Updater.restartExitCode {
            Updater.relaunchAfterExit()
            exit(0)
        }
        ErrorLog.write("JuleHygge stoppede uventet (\(child.terminationReason == .uncaughtSignal ? "signal" : "kode") \(child.terminationStatus)); genstarter")
        quickCrashes = Date().timeIntervalSince(started) < 60 ? quickCrashes + 1 : 0
        if quickCrashes >= 3 { ErrorLog.write("supervisor: crasher igen og igen, giver op"); exit(1) }
        sleep(5)
    }
}

// Only one copy at a time.
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: {
       $0.processIdentifier != getpid() && String($0.processIdentifier) != ProcessInfo.processInfo.environment["JULE_SUPERVISOR"] }) {
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon; lives in the menu bar
if let icon = AppIcon.image(size: 512, background: true, scale: 1) { app.applicationIconImage = icon }

Controller.migrateAutostart()
let controller = Controller()
if args.contains("--kalender") { controller.showCalendar() }
// --sneplov sends the snow plow after 3 s; --sneplov=N after N seconds (handy for testing).
for a in args {
    if a == "--sneplov" { controller.sendPlowAfter(3) }
    else if a.hasPrefix("--sneplov="), let s = Double(a.dropFirst(10)) { controller.sendPlowAfter(s) }
    // --julemand sends Santa right away, --effekt=N triggers a calendar effect (testing).
    else if a.hasPrefix("--snapshot=") {
        let parts = a.dropFirst(11).split(separator: ",")
        if let dir = parts.first { controller.snapshot = (String(dir), parts.count > 1 ? Double(parts[1]) ?? 5 : 5) }
    }
    else if a.hasPrefix("--kamera-scene-test=") { controller.testVirtualScene(dir: String(a.dropFirst(20))) }
    // --installer-kamera submits the camera extension activation (replaces an older version)
    else if a == "--installer-kamera" { DispatchQueue.main.async { controller.installCamera() } }
    else if a == "--skærmskift-test" { controller.startDisplayChangeTest() }
    else if a == "--julemand" { DispatchQueue.main.async { controller.launchSanta() } }
    else if a.hasPrefix("--effekt="), let n = Int(a.dropFirst(9)) { DispatchQueue.main.async { controller.triggerEffect(n) } }
}
app.run()
