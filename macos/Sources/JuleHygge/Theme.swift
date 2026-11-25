import AppKit

/// Which season the overlay shows. Jul is the original JuleHygge; the others carry the same elements over
/// (see docs/temaer/index.html for the idea behind each).
///
/// Efterår was built first, element by element. Until an element has its form in a theme it is simply left
/// out there (never shown in its Christmas form).
/// Día de los Muertos (`muertos`) follows the same pattern: marigold petals for snow, a carpet of petals at the
/// bottom and on the windows, an ofrenda (altar) for the snowman, monarch butterflies for Santa, calacas
/// (skeletons) for the nisser and papel picado for the lights. A donkey cart gathers the petals, and in the
/// camera the person wears a crown of marigolds and calavera make-up (CameraCostume.muertos).
/// Halloween (`halloween`, OverlayHalloween.swift): autumn's leaves fall, jack-o'-lanterns are carved in the
/// snowman's place, a witch on her broom flies in Santa's with bats after her, ghosts and children dressed up for
/// trick or treat walk in the nisser's, a garland of small pumpkin lanterns and hanging bats is in the lights',
/// and black cats sit and spiders hang on the window edges. A witch sweeps the leaves up or ghosts blow them
/// away (one or the other each time), and in the camera the person wears a witch's hat and nose or a pumpkin head.
/// New Year (`nytaar`, OverlayNytaar.swift): confetti and paper streamers fall all the time, a large clock on a
/// stand shows the real time in the snowman's place and is decorated hour by hour, volleys of rockets burst in a
/// band across the top in Santa's, party guests in paper hats walk in the nisser's, pennants and paper lanterns
/// hang in the lights', sparklers and party poppers are on the window edges, and a small street sweeper takes the
/// confetti. The theme has a moment: the countdown to midnight and a burst at the stroke (Controller.updateNewYear).
/// Nothing in the theme shows or suggests drinking (REL 2026-11-25).
/// What the camera dresses the person in. Set from the theme before each camera frame (the hat and the costume
/// are drawn on the camera's queue and do not see the controller): autumn's sou'wester and yellow raincoat
/// instead of the nisse hat and the red suit. Autumn has nothing in the beard's place.
enum CameraCostume {
    nonisolated(unsafe) static var autumn = ProcessInfo.processInfo.environment["HUE_EFTERAAR"] != nil
    /// The Day of the Dead: a crown of marigolds in the hat's place and calavera (sugar skull) make-up in the
    /// beard's; no suit. `HUE_MUERTOS=1` sets it in the tests.
    nonisolated(unsafe) static var muertos = ProcessInfo.processInfo.environment["HUE_MUERTOS"] != nil
    /// Who the person is dressed as in the Christmas theme (see Folk), set the same way. HUE_FOLK=1…5 sets it in the tests.
    nonisolated(unsafe) static var folk = Folk(rawValue: Int(ProcessInfo.processInfo.environment["HUE_FOLK"] ?? "") ?? 0) ?? .nisser
    /// Halloween: a witch's hat in the hat's place (black, tall and pointed with a bent tip, a purple band and a
    /// wide brim); nothing in the beard's or the suit's. `HUE_HALLOWEEN=1` sets it in the tests.
    nonisolated(unsafe) static var halloween = ProcessInfo.processInfo.environment["HUE_HALLOWEEN"] != nil
    /// Halloween's two costumes are alternatives (setting CameraHalloween, one choice in the menu): the witch's hat,
    /// or a pumpkin head: the person's whole head becomes a carved, lit jack-o'-lantern that turns and nods
    /// with it (NisseHat.pumpkinHead). `HUE_GRAESKAR=1` replays the pumpkin head in the tests instead of
    /// the hat.
    nonisolated(unsafe) static var witchHat = ProcessInfo.processInfo.environment["HUE_GRAESKAR"] == nil
    nonisolated(unsafe) static var pumpkinHead = ProcessInfo.processInfo.environment["HUE_GRAESKAR"] != nil
    /// New Year: a paper party hat in the hat's place (a stiff cone with a pompom); nothing in the beard's or the
    /// suit's. `HUE_NYTAAR=1` sets it in the tests.
    nonisolated(unsafe) static var nytaar = ProcessInfo.processInfo.environment["HUE_NYTAAR"] != nil
    static var look: CameraLook { halloween ? CameraLook.witch : nytaar ? CameraLook.party : CameraLook.of(folk) }
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
    /// Bands round the hat in a second colour, from brim to tip (nil = plain cloth): New Year's paper hat.
    var stripe: RGB?
    /// A stiff paper cone standing on the band's ring and pointing along its axis, not cloth laid on the head.
    var cone = false

    /// Halloween's witch hat: the same cloth on the measured head, black, half as long again and bent only a little,
    /// with a purple band; its brim is added in NisseHat.parts. No beard; the clothes are turned black and the skin
    /// green by Costume.applyWitch.
    static var witch: CameraLook {
        var l = CameraLook()
        l.cloth = (0.13, 0.12, 0.17); l.free = 1.5; l.bend = 0.45; l.band = .plain((0.48, 0.17, 0.75)); l.tip = .bare; l.beard = 0
        return l
    }

    /// New Year's paper party hat: a stiff straight cone in a bright colour with bands of a second colour round it, a gold
    /// band and a pompom on the tip. No beard and no suit.
    static var party: CameraLook {
        var l = CameraLook()
        l.free = 0.8; l.bend = 0; l.tip = .pompom; l.beard = 0; l.cone = true
        // (its colour is one of the guests' hats', drawn anew each time the camera is taken into use; the bands and
        // the brim are gold, or silver on a gold or orange hat)
        let p = Theme.confettiColours[partyHat % Theme.confettiColours.count].components ?? [0.14, 0.52, 0.86, 1]
        l.cloth = (Double(p[0]), Double(p[1]), Double(p[2]))
        let warm = p[0] > 0.85 && p[1] > 0.5 && p[2] < 0.4
        l.stripe = warm ? (0.88, 0.90, 0.94) : (0.96, 0.80, 0.26)
        l.band = .plain(warm ? (0.80, 0.82, 0.87) : (0.95, 0.76, 0.22))
        return l
    }
    /// Which of the guests' hat colours the camera's paper hat has (Theme.confettiColours). HUE_NYTAAR=N picks it in
    /// the tests (1 = the first).
    nonisolated(unsafe) static var partyHat = (Int(ProcessInfo.processInfo.environment["HUE_NYTAAR"] ?? "") ?? Int.random(in: 1...Theme.confettiColours.count)) - 1

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
    case jul = 0, efteraar = 1, muertos = 2, halloween = 3, nytaar = 4

    static let names = ["Jul", "Efterår", "De dødes dag", "Halloween", "Nytår"]

    /// Leaves (or petals) instead of snow: fewer and bigger pictures, turning as they fall, in several colours.
    /// Which pictures is `ScreenOverlay.fallImages` (leaves in autumn, marigold petals for the dead).
    var leaves: Bool { self != .jul }

    /// Fill and edge of the pile at the bottom of the screen and on the windows.
    /// (With leaves or petals the fill is the shade between the pieces that lie over it; see ScreenOverlay.renderLeafPile.)
    var pile: CGColor {
        switch self {
        case .jul: return C(248, 252, 255, 245)
        case .efteraar: return C(122, 62, 24, 245)
        case .muertos: return C(168, 72, 8, 245)
        case .halloween: return C(96, 46, 20, 245)
        case .nytaar: return C(92, 70, 120, 245)
        }
    }
    var pileEdge: CGColor { self == .jul ? C(170, 200, 230, 110) : withAlpha(pile, 0) }

    /// What flies over now and then: Santa and his sleigh, in autumn geese on their way south, for the dead a
    /// swarm of monarch butterflies (they are said to carry the souls home).
    var hasSanta: Bool { true }
    /// Santa leaves a trail of sparks; the geese and butterflies do not. (The geese's sound is Synth.geese
    /// instead of a tune; the butterflies are silent.)
    var santaSparkles: Bool { self == .jul }
    /// What is built: the snowman, in autumn a haystack with a scarecrow, for the dead an ofrenda (an altar
    /// with candles, marigolds and a sugar skull).
    var hasSnowman: Bool { true }
    /// In the Christmas theme three children build the snowman while you watch, and the plow runs it down
    /// (SnowmanBuild). Autumn's form of it grows one stage a day and gets the daily notice; the ofrenda grows one
    /// stage for every hour the app runs (Controller.snowmanStage, updateOfrenda).
    var childrenBuild: Bool { self == .jul }
    /// A theme that is only on for a couple of days builds its form of the snowman a stage for every hour the app
    /// runs, and keeps it finished until another theme is chosen (Controller.updateOfrenda): the ofrenda, and
    /// Halloween's jack-o'-lanterns.
    var growsByHour: Bool { self == .muertos || self == .halloween || self == .nytaar }
    /// New Year's walkers: party guests in paper hats, with party horns and crackers.
    var guests: Bool { self == .nytaar }
    /// Halloween's walkers: ghosts, and children dressed up for trick or treat.
    var spooks: Bool { self == .halloween }
    /// The walkers exist in every theme; in autumn they are hedgehogs and squirrels (`animals`), for the dead
    /// calacas, small skeletons in sombreros and catrina hats (`skeletons`).
    var hasNisser: Bool { true }
    var animals: Bool { self == .efteraar }
    var skeletons: Bool { self == .muertos }
    /// What hangs along the top of the screen: Christmas lights, in autumn a garland of leaves with lanterns,
    /// for the dead papel picado (cut paper flags).
    var hasLights: Bool { true }
    /// What clears the pile when it gets high: the snow plow, in autumn a leaf collector, for the dead a donkey
    /// cart: a calaca sweeps the petals up and they go in the cart, to be taken out to the graves. It sounds of
    /// hooves, a creaking wheel and the broom, and the donkey brays where the plow honks (Synth.donkeyCart and co.).
    /// On Halloween it is one of two, picked for each run with even odds (Controller.ghostsBlow): a small witch
    /// sweeps the leaves into a cauldron on a cart her cat pulls, or three ghosts float along and blow them away.
    var hasPlow: Bool { true }

    /// New Year's confetti and streamers: gold and silver, and a few strong colours.
    static let confettiColours: [CGColor] = [C(240, 196, 64), C(214, 220, 230), C(233, 50, 90), C(40, 160, 220), C(120, 200, 80), C(160, 90, 220), C(255, 140, 40)]

    /// The leaves' colours (the snow has none).
    static let leafColours: [CGColor] = [C(217, 84, 30), C(232, 160, 32), C(168, 67, 26), C(201, 162, 39), C(138, 59, 18)]
    /// The marigolds' (cempasúchil) colours: deep orange to golden yellow.
    static let marigoldColours: [CGColor] = [C(255, 140, 0), C(255, 176, 0), C(246, 112, 10), C(255, 206, 50), C(232, 96, 12)]
    /// The bright colours of the papel picado and the altar's cloths.
    static let picadoColours: [CGColor] = [C(233, 30, 99), C(255, 152, 0), C(0, 166, 166), C(123, 44, 191), C(255, 210, 63), C(46, 158, 79)]
}
