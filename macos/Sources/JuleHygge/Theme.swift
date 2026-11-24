import AppKit

/// Which season the overlay shows. Jul is the original JuleHygge; the others carry the same elements over
/// (see docs/temaer/index.html for the idea behind each).
///
/// Efterår was built first, element by element. Until an element has its form in a theme it is simply left
/// out there (never shown in its Christmas form).
/// Día de los Muertos (`muertos`) follows the same pattern: marigold petals for snow, a carpet of petals at the
/// bottom and on the windows, an ofrenda (altar) for the snowman, monarch butterflies for Santa, calacas
/// (skeletons) for the nisser and papel picado for the lights. A donkey cart gathers the petals, and the
/// camera has no costume in this theme yet.
/// What the camera dresses the person in. Set from the theme before each camera frame (the hat and the costume
/// are drawn on the camera's queue and do not see the controller): autumn's sou'wester and yellow raincoat
/// instead of the nisse hat and the red suit. Autumn has nothing in the beard's place.
enum CameraCostume {
    nonisolated(unsafe) static var autumn = ProcessInfo.processInfo.environment["HUE_EFTERAAR"] != nil
}

enum Theme: Int {
    case jul = 0, efteraar = 1, muertos = 2

    static let names = ["Jul", "Efterår", "De dødes dag"]

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
        }
    }
    var pileEdge: CGColor { self == .jul ? C(170, 200, 230, 110) : withAlpha(pile, 0) }

    /// What flies over now and then: Santa and his sleigh, in autumn geese on their way south, for the dead a
    /// swarm of monarch butterflies (they are said to carry the souls home).
    var hasSanta: Bool { true }
    /// Santa leaves a trail of sparks; the geese and butterflies do not. (The geese's sound is Synth.geese
    /// instead of a tune; the butterflies are silent.)
    var santaSparkles: Bool { self == .jul }
    /// What is built a little more every day: the snowman, in autumn a haystack with a scarecrow, for the dead
    /// an ofrenda (an altar with candles, marigolds and a sugar skull).
    var hasSnowman: Bool { true }
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
    var hasPlow: Bool { true }
    /// The camera's costume (hat, beard, suit). The dead have none yet: the calavera make-up and flower crown
    /// from docs/temaer are still to be made.
    var hasCameraCostume: Bool { self != .muertos }

    /// The leaves' colours (the snow has none).
    static let leafColours: [CGColor] = [C(217, 84, 30), C(232, 160, 32), C(168, 67, 26), C(201, 162, 39), C(138, 59, 18)]
    /// The marigolds' (cempasúchil) colours: deep orange to golden yellow.
    static let marigoldColours: [CGColor] = [C(255, 140, 0), C(255, 176, 0), C(246, 112, 10), C(255, 206, 50), C(232, 96, 12)]
    /// The bright colours of the papel picado and the altar's cloths.
    static let picadoColours: [CGColor] = [C(233, 30, 99), C(255, 152, 0), C(0, 166, 166), C(123, 44, 191), C(255, 210, 63), C(46, 158, 79)]
}
