import Foundation

/// Same keys and format as the Windows version's settings.ini, stored in
/// ~/Library/Application Support/JuleHygge/settings.ini (JULE_SETTINGS overrides the path, handy for tests).
final class Settings {
    var snow = true, snowGround = true, santa = true, nisser = true, lights = true,
        pauseFullscreen = true, snowman = true, allScreens = true, plow = true,
        cameraPausesScreens = true, windowSnow = true, cameraHat = true, cameraFront = true, cameraBeard = true, cameraSuit = true,
        sound = false, plowSound = false   // lyd er slået fra, indtil man selv slår den til
    var theme = 0              // 0 = jul, 1 = efterår (Theme)
    var kite = true            // efterårets drage
    var folk = 0               // 0 = automatisk efter sprog og land, ellers 1 nisser, 2 alfer, 3 Wichtel, 4 kabouters, 5 päkapikud (Folk)
    var autoUpdate = true      // install new GitHub releases by itself
    var lastVersion = ""       // the version that ran last time, to announce an update
    var snowLevel = 3          // 0 = let, 1 = normal, 2 = snestorm, 3 = skiftende vejr (Weather), som er standard
    var nisseCount = 3         // pr. skærm
    var powerSave = 2          // 0 = fra, 1 = altid til, 2 = kun på batteri
    var soundLevel = 1         // 0 = lav, 1 = middel, 2 = høj
    var frameRate = 20         // billeder/s når scenen er rolig (12, 20, 30 eller 60)
    var snowmanSeenStage = 0
    var calendarYear = 0
    var firstRun: Date? = nil, lastDoorNotice: Date? = nil
    var openedDoors = Set<Int>()
    private var loadFailed = false

    static var fileURL: URL {
        if let p = ProcessInfo.processInfo.environment["JULE_SETTINGS"], !p.isEmpty { return URL(fileURLWithPath: p) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JuleHygge/settings.ini")
    }

    static func load() -> Settings {
        let s = Settings()
        var d = [String: String]()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            // If the file exists but cannot be read, run on defaults and never save over it.
            if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
                for line in text.split(whereSeparator: \.isNewline) {
                    if let i = line.firstIndex(of: "="), i != line.startIndex {
                        d[line[..<i].trimmingCharacters(in: .whitespaces)] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
                    }
                }
            } else { s.loadFailed = true }
        }
        func b(_ k: String, _ def: Bool) -> Bool { d[k].map { $0 == "1" } ?? def }
        func i(_ k: String, _ def: Int) -> Int { d[k].flatMap { Int($0) } ?? def }
        s.snow = b("Snow", s.snow)
        s.snowGround = b("SnowGround", s.snowGround)
        s.santa = b("Santa", s.santa)
        s.nisser = b("Nisser", s.nisser)
        s.lights = b("Lights", s.lights)
        s.pauseFullscreen = b("PauseFullscreen", s.pauseFullscreen)
        s.snowman = b("Snowman", s.snowman)
        s.allScreens = b("AllScreens", s.allScreens)
        s.plow = b("Plow", s.plow)
        s.windowSnow = b("WindowSnow", s.windowSnow)
        s.cameraHat = b("CameraHat", s.cameraHat)
        s.cameraFront = b("CameraFront", s.cameraFront)
        s.cameraBeard = b("CameraBeard", s.cameraBeard)
        s.cameraSuit = b("CameraSuit", s.cameraSuit)
        s.sound = b("Sound", s.sound)
        s.cameraPausesScreens = b("CameraPausesScreens", s.cameraPausesScreens)
        s.plowSound = b("PlowSound", s.plowSound)
        s.soundLevel = max(0, min(2, i("SoundLevel", s.soundLevel)))
        s.snowLevel = max(0, min(3, i("SnowLevel", s.snowLevel)))
        s.nisseCount = max(1, min(12, i("NisseCount", s.nisseCount)))
        s.powerSave = max(0, min(2, i("PowerSave", s.powerSave)))
        s.frameRate = [12, 20, 30, 60].contains(i("FrameRate", 20)) ? i("FrameRate", 20) : 20
        s.theme = Theme(rawValue: i("Theme", 0)) != nil ? i("Theme", 0) : 0
        s.kite = b("Kite", s.kite)
        s.folk = Folk(rawValue: i("Folk", s.folk)) != nil ? i("Folk", s.folk) : 0
        s.autoUpdate = b("AutoUpdate", s.autoUpdate)
        s.lastVersion = d["LastVersion"] ?? ""
        s.snowmanSeenStage = i("SnowmanSeenStage", 0)
        s.calendarYear = i("CalendarYear", 0)
        s.firstRun = d["FirstRun"].flatMap(JuleClock.parse)
        s.lastDoorNotice = d["LastDoorNotice"].flatMap(JuleClock.parse)
        if let od = d["OpenedDoors"] {
            for part in od.split(separator: ",") { if let n = Int(part), (1...24).contains(n) { s.openedDoors.insert(n) } }
        }
        return s
    }

    func save() {
        if loadFailed { return }
        func b(_ v: Bool) -> String { v ? "1" : "0" }
        func ds(_ d: Date?) -> String { d.map(JuleClock.format) ?? "" }
        let lines = [
            "Snow=" + b(snow), "SnowGround=" + b(snowGround), "Santa=" + b(santa),
            "Nisser=" + b(nisser), "Lights=" + b(lights), "PauseFullscreen=" + b(pauseFullscreen),
            "Snowman=" + b(snowman), "AllScreens=" + b(allScreens), "Plow=" + b(plow), "WindowSnow=" + b(windowSnow), "CameraHat=" + b(cameraHat), "CameraFront=" + b(cameraFront), "CameraBeard=" + b(cameraBeard), "CameraSuit=" + b(cameraSuit), "Sound=" + b(sound), "CameraPausesScreens=" + b(cameraPausesScreens), "PlowSound=" + b(plowSound), "SoundLevel=\(soundLevel)",
            "SnowLevel=\(snowLevel)", "NisseCount=\(nisseCount)", "PowerSave=\(powerSave)", "FrameRate=\(frameRate)",
            "Theme=\(theme)", "Kite=" + b(kite), "Folk=\(folk)", "AutoUpdate=" + b(autoUpdate), "LastVersion=" + lastVersion,
            "SnowmanSeenStage=\(snowmanSeenStage)", "CalendarYear=\(calendarYear)",
            "FirstRun=" + ds(firstRun), "LastDoorNotice=" + ds(lastDoorNotice),
            "OpenedDoors=" + openedDoors.sorted().map(String.init).joined(separator: ","),
        ]
        do {
            try FileManager.default.createDirectory(at: Settings.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // atomically: written to a temp file and swapped in, so a crash never leaves half a file
            try (lines.joined(separator: "\n") + "\n").write(to: Settings.fileURL, atomically: true, encoding: .utf8)
        } catch { ErrorLog.write("save settings: \(error)") }
    }
}
