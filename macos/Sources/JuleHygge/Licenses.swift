import AppKit

/// The licences of what in the app is not JuleHygge's own, read from the menu:
/// - the recording of a brass band on the Rhineland carnival's wagon (assets/lyd/KILDER.md): CC BY 3.0 asks for
///   the credit, a link to the licence and what was changed;
/// - the parts model in JuleHygge Kamera (see PersonParts and assets/model/KILDER.md): Apache 2.0 asks that its
///   text goes with every copy, so it is in the app (macos/licenses/Apache-2.0.txt, copied to Resources by
///   build.sh and the Xcode project).
/// Only the macOS version has either, so only it has this.
/// (Called from the menu, on the main thread, like the rest of the controller's menu actions.)
enum LicenseWindow {
    nonisolated(unsafe) private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "Licenser i JuleHygge"
            w.isReleasedWhenClosed = false
            let scroll = NSTextView.scrollableTextView()
            scroll.frame = w.contentView!.bounds
            scroll.autoresizingMask = [.width, .height]
            if let text = scroll.documentView as? NSTextView {
                text.isEditable = false
                text.textContainerInset = NSSize(width: 14, height: 14)
                text.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                text.string = Self.text
            }
            w.contentView!.addSubview(scroll)
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private static var text: String {
        let intro = """
        MUSIKKEN PÅ KARNEVALSVOGNEN (Rhinlandets karneval)

        "Hannerl Polka" af Hans Kummerer, spillet af Blaskapelle Franz Stremnitzer \
        (fra cd'en "30 Jahre Blasmusik Franz Stremnitzer"). Udgivet af Franz Stremnitzer på Wikimedia Commons under \
        Creative Commons Attribution 3.0 Unported: https://creativecommons.org/licenses/by/3.0/
        Kilde: https://commons.wikimedia.org/wiki/File:Hannerl_Polka.ogg
        Ændret: JuleHygge bruger et uddrag på 63 sekunder, i mono, som spilles i ring.


        TØJMODELLEN I JULEHYGGE KAMERA

        JuleHygge Kamera finder tøjet på personen i billedet med en trænet model: \
        "Multiclass Selfie Segmentation" (selfie_multiclass_256x256) fra Google MediaPipe.

        Modellen er udgivet af Google under Apache License, Version 2.0. Udgaven i JuleHygge er omsat \
        til Core ML-format af en tredjepart (kpgalligan/rasterize-models på GitHub).

        Modellen bruges kun i macOS-udgaven, og kun når nissedragten eller regnfrakken er slået til i kameraet. \
        Billederne behandles på denne Mac og sendes ingen steder hen.

        Licensens fulde tekst (på engelsk):


        """
        let licence = Bundle.main.url(forResource: "Apache-2.0", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        return intro + (licence ?? "Licensteksten mangler i denne kopi af appen. Den findes på https://www.apache.org/licenses/LICENSE-2.0")
    }
}
