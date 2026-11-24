import AppKit

/// Which season the overlay shows. Jul is the original JuleHygge; the others carry the same elements over
/// (see docs/temaer/index.html for the idea behind each).
///
/// Efterår is being built first, element by element. Until an element has its autumn form it is simply left
/// out in that theme (never shown in its Christmas form): so far what falls, the pile at the bottom of the
/// screen, the piles on the windows, the walkers (hedgehogs and squirrels for nisser) and what is built day by
/// day (a haystack with a scarecrow for the snowman) are done.
/// What the camera dresses the person in. Set from the theme before each camera frame (the hat and the costume
/// are drawn on the camera's queue and do not see the controller): autumn's sou'wester and yellow raincoat
/// instead of the nisse hat and the red suit. Autumn has nothing in the beard's place.
enum CameraCostume {
    nonisolated(unsafe) static var autumn = ProcessInfo.processInfo.environment["HUE_EFTERAAR"] != nil
    /// Who the person is dressed as in the Christmas theme (see Folk), set the same way. HUE_FOLK=1…5 sets it in the tests.
    nonisolated(unsafe) static var folk = Folk(rawValue: Int(ProcessInfo.processInfo.environment["HUE_FOLK"] ?? "") ?? 0) ?? .nisser
    static var look: CameraLook { CameraLook.of(folk) }
}

/// What tells one folk's hat, beard and suit from another's in the camera. The hat is always the same cloth on the
/// measured head (Hat.swift) and the beard the same band on the face (Costume.swift); these are the differences.
struct CameraLook {
    typealias RGB = (r: Double, g: Double, b: Double)
    enum Band { case fur, plain(RGB), jagged(RGB) }
    enum Tip { case pompom, bell, bare }

    /// The hat's cloth.
    var cloth: RGB = (0.80, 0.07, 0.12)
    /// The tip's length and how far it bends over, against the nisse hat's (0 bend = a stiff, straight cone).
    var free = 1.0, bend = 1.0
    /// Round the brow: the fur band, or a band of cloth (plain, or with teeth pointing up onto the hat).
    var band = Band.fur
    var tip = Tip.pompom
    /// The beard's length against the nisse beard's (0 = no beard).
    var beard = 1.0
    /// The suit: the clothes' own light and shade times `suit`, plus `suitFloor` (so dark clothes get colour too).
    var suit: RGB = (0.9, 0.10, 0.12), suitFloor: RGB = (0.38, 0.01, 0.03)

    static func of(_ folk: Folk) -> CameraLook {
        var l = CameraLook()
        switch folk {
        case .nisser: break
        case .alfer:      // a green cap with a red toothed band and a bell, no beard, green clothes
            l.cloth = (0.16, 0.56, 0.28); l.band = .jagged((0.80, 0.14, 0.18)); l.tip = .bell; l.beard = 0
            l.suit = (0.14, 0.56, 0.22); l.suitFloor = (0.02, 0.22, 0.06)
        case .wichtel:    // a tall grey felt cap that hardly bends, a long beard, a moss green coat
            l.cloth = (0.56, 0.57, 0.61); l.free = 1.35; l.bend = 0.4; l.band = .plain((0.40, 0.41, 0.45)); l.tip = .bare; l.beard = 1.6
            l.suit = (0.36, 0.44, 0.22); l.suitFloor = (0.10, 0.15, 0.05)
        case .kabouter:   // a stiff red cone, a short beard, a rust jacket
            l.free = 1.15; l.bend = 0; l.band = .plain((0.58, 0.05, 0.09)); l.tip = .bare; l.beard = 0.6
            l.suit = (0.72, 0.36, 0.15); l.suitFloor = (0.28, 0.10, 0.02)
        case .paekapikk:  // the nisse's hat and red clothes, no beard
            l.beard = 0
        }
        return l
    }
}

enum Theme: Int {
    case jul = 0, efteraar = 1

    static let names = ["Jul", "Efterår"]

    /// Leaves instead of snow: fewer and bigger, turning as they fall, in several colours.
    var leaves: Bool { self == .efteraar }

    /// Fill and edge of the pile at the bottom of the screen and on the windows.
    /// (In autumn the fill is the shade between the leaves that lie over it; see ScreenOverlay.renderLeafPile.)
    var pile: CGColor { self == .efteraar ? C(122, 62, 24, 245) : C(248, 252, 255, 245) }
    var pileEdge: CGColor { self == .efteraar ? C(122, 62, 24, 0) : C(170, 200, 230, 110) }

    /// The elements that only exist in their Christmas form so far.
    /// What flies over now and then: Santa and his sleigh, or in autumn geese on their way south.
    var hasSanta: Bool { true }
    /// Santa leaves a trail of sparks; the geese do not. (Their sound is Synth.geese instead of a tune.)
    var santaSparkles: Bool { self == .jul }
    /// What is built: the snowman, or in autumn a haystack with a scarecrow.
    var hasSnowman: Bool { true }
    /// In the Christmas theme three children build the snowman while you watch, and the plow runs it down
    /// (SnowmanBuild). Every other theme's form of it grows one stage a day (Controller.snowmanStage) and gets
    /// the daily notice.
    var childrenBuild: Bool { self == .jul }
    /// The walkers exist in every theme so far; in autumn they are hedgehogs and squirrels (`animals`).
    var hasNisser: Bool { true }
    var animals: Bool { self == .efteraar }
    /// What hangs along the top of the screen: Christmas lights, or in autumn a garland of leaves with lanterns.
    var hasLights: Bool { true }
    /// What clears the pile when it gets high: the snow plow, or in autumn a leaf collector.
    var hasPlow: Bool { true }

    /// The leaves' colours (the snow has none).
    static let leafColours: [CGColor] = [C(217, 84, 30), C(232, 160, 32), C(168, 67, 26), C(201, 162, 39), C(138, 59, 18)]
}
