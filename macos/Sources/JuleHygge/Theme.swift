import AppKit

/// Which season the overlay shows. Jul is the original JuleHygge; the others carry the same elements over
/// (see docs/temaer/index.html for the idea behind each).
///
/// Efterår is being built first, element by element. Until an element has its autumn form it is simply left
/// out in that theme (never shown in its Christmas form): so far what falls, the pile at the bottom of the
/// screen, the piles on the windows, the walkers (hedgehogs and squirrels for nisser) and what is built day by
/// day (a haystack with a scarecrow for the snowman) are done.
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
    /// What is built a little more every day: the snowman, or in autumn a haystack with a scarecrow.
    var hasSnowman: Bool { true }
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
