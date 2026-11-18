// Measures what CGWindowListCopyWindowInfo reports for a window while it is minimized, so the window snow
// (WindowSnow.swift) can tell a window on its way into the Dock from one that was moved or resized.
// Opens a window of its own, minimizes it (first at its normal size, then zoomed) and prints every change in
// the reported bounds with the time since the minimize started.
//
// Run from macos/:  swift tools/window-probe.swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let win = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 640, height: 420),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
win.title = "JuleHygge vinduesprobe"
win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

func spin(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

/// The bounds the window list reports for our window among the on-screen windows (nil = not listed).
func reported() -> String {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return "ingen liste" }
    for w in list where (w[kCGWindowNumber as String] as? Int) == win.windowNumber {
        guard let bd = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: bd) else { return "uden mål" }
        let alpha = (w[kCGWindowAlpha as String] as? Double) ?? 1
        return "x\(Int(r.minX)) y\(Int(r.minY)) b\(Int(r.width)) h\(Int(r.height)) alpha \(alpha)"
    }
    return "ikke på listen"
}

func watch(_ label: String, seconds: Double, _ action: () -> Void) {
    print("--- \(label): før: \(reported())")
    let start = Date()
    action()
    var last = ""
    var samples = 0
    while Date().timeIntervalSince(start) < seconds {
        let now = reported()
        samples += 1
        if now != last { print(String(format: "  %5.0f ms  %@", Date().timeIntervalSince(start) * 1000, now)); last = now }
        spin(0.008)
    }
    print("  (\(samples) målinger)")
}

spin(1)
watch("minimér ved normal størrelse", seconds: 2.5) { win.miniaturize(nil) }
watch("gendan", seconds: 2) { win.deminiaturize(nil) }
watch("maksimér (zoom)", seconds: 2) { win.zoom(nil) }
watch("minimér maksimeret", seconds: 2.5) { win.miniaturize(nil) }
watch("gendan", seconds: 2) { win.deminiaturize(nil) }
win.close()
