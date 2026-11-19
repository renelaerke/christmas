import AppKit
import CoreImage
import QuartzCore

/// A small layer whose content is redrawn by a closure. The closure draws in the screen's own
/// coordinates (origin top-left, y down), like the GDI+ code in the Windows version.
final class Sprite: NSObject, CALayerDelegate {
    let layer = CALayer()
    private(set) var rect = CGRect.zero
    private let screenHeight: F
    let painter: (CGContext) -> Void

    init(parent: CALayer, screenHeight: F, scale: F, painter: @escaping (CGContext) -> Void) {
        self.screenHeight = screenHeight
        self.painter = painter
        super.init()
        layer.delegate = self
        layer.contentsScale = scale
        layer.contentsGravity = .topLeft
        layer.isHidden = true
        parent.addSublayer(layer)
    }

    /// Moves the sprite to `r` (screen coordinates, y down) and optionally redraws it.
    func place(_ r: CGRect, redraw: Bool = true) {
        // Origin is rounded and size kept stable, so moving the layer without a redraw never rescales its content.
        let r = CGRect(x: floor(r.minX), y: floor(r.minY), width: ceil(r.width) + 1, height: ceil(r.height) + 1)
        if r != rect {
            rect = r
            layer.frame = CGRect(x: r.minX, y: screenHeight - r.maxY, width: r.width, height: r.height)
        }
        layer.isHidden = false
        if redraw { layer.setNeedsDisplay() }
    }

    func hide() { layer.isHidden = true }

    /// Disconnects the layer from this sprite, so it can never ask for a drawing again (used when a screen goes away).
    func detach() {
        layer.delegate = nil
        layer.removeFromSuperlayer()
    }

    func draw(_ layer: CALayer, in ctx: CGContext) {
        ctx.translateBy(x: 0, y: layer.bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        painter(ctx)
    }

    func action(for layer: CALayer, forKey event: String) -> CAAction? { NSNull() }
}

/// A pool of image layers (snowflakes, sparks, snow chunks) reused from frame to frame.
final class DotPool {
    private let parent = CALayer()
    /// The layer holding all of this pool's images (e.g. to draw it separately).
    var container: CALayer { parent }
    private var layers: [CALayer] = []
    private var used = 0
    private let screenHeight: F

    init(in root: CALayer, screenHeight: F) {
        self.screenHeight = screenHeight
        parent.frame = root.bounds
        root.addSublayer(parent)
    }

    func begin() { used = 0 }

    /// Places one image centered at (x, y) in screen coordinates (y down).
    func add(_ image: CGImage, x: F, y: F, w: F, h: F, opacity: F, rotation: F = 0) {
        let l: CALayer
        if used < layers.count { l = layers[used] } else {
            l = CALayer()
            l.actions = ["position": NSNull(), "bounds": NSNull(), "opacity": NSNull(), "transform": NSNull(),
                         "contents": NSNull(), "hidden": NSNull()]
            parent.addSublayer(l)
            layers.append(l)
        }
        used += 1
        if l.contents == nil || (l.contents as! CGImage) !== image { l.contents = image }
        l.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        l.position = CGPoint(x: x, y: screenHeight - y)
        l.opacity = Float(opacity)
        l.setAffineTransform(rotation == 0 ? .identity : CGAffineTransform(rotationAngle: -rotation))
        l.isHidden = false
    }

    func end() {
        var i = used
        while i < layers.count {
            if !layers[i].isHidden { layers[i].isHidden = true }
            i += 1
        }
    }
}

/// Pre-rendered images for the pooled layers (drawn once per screen scale).
/// Core Image context for the camera compositing (GPU).
enum GPU {
    static let ciContext = CIContext(options: [.cacheIntermediates: false])
}

final class DotImages {
    let flake, crystal, goldDot, whiteDot, goldGlint, whiteGlint, goldStar, whiteStar, smoke, chunk: CGImage
    /// A raindrop's streak (autumn storm): an upright line, drawn narrow and tall and turned with the wind.
    let rain: CGImage
    /// Autumn leaves in each colour, four ovals for every maple, lying along x (drawn turned as they fall).
    let leaves: [CGImage]

    init(scale: F) {
        let s: F = 64, m: F = 32
        func img(_ d: (CGContext) -> Void) -> CGImage { renderImage(width: s, height: s, scale: scale / 4, d)! }
        flake = img { $0.fillEllipse(C(255, 255, 255), 0, 0, s, s) }
        crystal = img { g in
            for k in 0..<3 {
                let a = F(k) * 1.0472, dx = cos(a) * m, dy = sin(a) * m
                g.line(C(255, 255, 255), 5, m - dx, m - dy, m + dx, m + dy, round: true)
            }
        }
        goldDot = img { $0.fillEllipse(C(255, 220, 120), 0, 0, s, s) }
        whiteDot = flake
        func glint(_ c: CGColor) -> CGImage {
            img { g in
                g.fillEllipse(c, m - 10, m - 10, 20, 20)
                g.line(c, 2.2, m - 30, m, m + 30, m); g.line(c, 2.2, m, m - 30, m, m + 30)
            }
        }
        goldGlint = glint(C(255, 220, 120)); whiteGlint = glint(C(255, 255, 255))
        goldStar = img { $0.fillPoly(C(255, 220, 120), starPoints(m, m, m, m * 0.45)) }
        whiteStar = img { $0.fillPoly(C(255, 255, 255), starPoints(m, m, m, m * 0.45)) }
        smoke = img { $0.fillEllipse(C(120, 120, 125), 0, 0, s, s) }
        chunk = img { $0.fillEllipse(C(250, 252, 255), 0, 0, s, s) }
        rain = img { $0.line(C(190, 215, 240), 22, m, 6, m, s - 6, round: true) }
        // Two kinds of leaf in every colour, both with the stalk at the left and the tip at the right:
        // a pointed oval (beech) and, one in five, a maple.
        // The veins are faint and light. Dark ones made a small leaf read as a beetle seen from the side: the
        // midrib a body and the side veins legs.
        let vein = C(90, 44, 14, 70), sideVein = C(255, 236, 196, 50)
        func mirrored(_ upper: [CGPoint]) -> [CGPoint] { upper + upper.dropFirst().dropLast().reversed().map { CGPoint(x: $0.x, y: 2 * m - $0.y) } }
        // The maple has the eleven points of a sugar maple: the tip, and on each side the top lobe's side point,
        // the side lobe's three points and the small bottom lobe. (Along the axis 0…1 from blade to tip, and out
        // from the axis in units of the leaf's length.)
        let half: [(F, F)] = [(0.14, 0), (0.17, 0.26), (0.24, 0.22), (0.30, 0.44), (0.34, 0.40), (0.46, 0.50), (0.50, 0.42),
                              (0.60, 0.44), (0.50, 0.17), (0.74, 0.22), (0.72, 0.12), (1, 0)]
        let maple = mirrored(half.map { CGPoint(x: 12 + $0.0 * 51, y: m - $0.1 * 58) })
        var all: [CGImage] = []
        // Four ovals for every maple in each colour, so any pick from the list gives 80 % ovals.
        for colour in Theme.leafColours {
            let oval = img { g in
                let leaf = CGMutablePath()
                leaf.move(to: CGPoint(x: 10, y: m))
                leaf.addQuadCurve(to: CGPoint(x: 62, y: m), control: CGPoint(x: 34, y: 2))
                leaf.addQuadCurve(to: CGPoint(x: 10, y: m), control: CGPoint(x: 34, y: 62))
                g.addPath(leaf); g.setFillColor(colour); g.fillPath()
                g.line(vein, 2.5, 1, m, 56, m, round: true)
                g.line(sideVein, 1.5, 26, m, 36, m - 12); g.line(sideVein, 1.5, 26, m, 36, m + 12)
                g.line(sideVein, 1.5, 40, m, 48, m - 9); g.line(sideVein, 1.5, 40, m, 48, m + 9)
            }
            all += [oval, oval, oval, oval]
            all.append(img { g in
                g.fillPoly(colour, maple.map { ($0.x, $0.y) })
                g.line(vein, 2.5, 1, m, 58, m, round: true)
                g.line(sideVein, 1.5, 21, m, 35, 6); g.line(sideVein, 1.5, 21, m, 35, 58)
            })
        }
        leaves = all
    }
}

/// Ét gennemsigtigt, klik-igennem overlay-vindue for én skærm.
final class ScreenOverlay {
    unowned let c: Controller
    var cfg: Settings { c.cfg }
    /// nil for the virtual screen used as the camera background (it has no window).
    let window: NSWindow?
    /// True for the offscreen "third screen" behind the user in the virtual camera.
    let isVirtual: Bool
    private let backingScale: F
    let root: CALayer
    let isPrimary: Bool
    /// The screen in global coordinates with origin top-left of the primary screen, y down.
    let screenBounds: CGRect
    let S: F
    private(set) var snowmanPos: CGPoint?
    let W: F, H: F
    private let groundY: F
    private let lightsTop: F
    private let images: DotImages

    private var flakes: [Flake] = []
    private var heap: [F]
    private let heapStep: F = 4
    private var nisser: [Nisse] = []
    /// How many nisser more or fewer than the chosen number are around right now (−2…+2).
    private var nisseOffset = 0
    private var nisseChangeTimer: F = F(Double(ProcessInfo.processInfo.environment["JULE_NISSE_SECONDS"] ?? "") ?? Double(90 + R() * 90))
    private var nisseLayers: [CALayer] = []
    /// Pre-rendered poses, shared by every nisse with the same clothes: key = variant + state + frame.
    private var nisseFrames: [String: CGImage] = [:]
    private var paused = false
    private var frameNo = 0
    private var groundTimer: F = 0

    // layers, in drawing order (back to front)
    private var lightsSprite: Sprite!, santaSprite: Sprite!, snowmanSprite: Sprite!, plowSprite: Sprite!
    private var sparkPool: DotPool!
    private let groundFill = CAShapeLayer(), groundLine = CAShapeLayer()
    private let nisseLayer = CALayer()
    /// Snow piles on other apps' window edges: one fill + outline per window, rebuilt when the pile's version changes.
    private let ledgeLayer = CALayer()
    private var ledgeShapes: [Int: (fill: CAShapeLayer, line: CAShapeLayer, version: Int)] = [:]
    private var plowBitPool: DotPool!
    private var flakePool: DotPool!
    private var rainPool: DotPool!
    private var rain: [RainDrop] = []
    private var leafPool: DotPool!
    private var leafPileDrawn: F = -1, leafPileAt = -10.0
    private var ledgeLeafPool: DotPool!
    private var ledgeLeavesAt = -10.0
    private var bulbLayers: [(layer: CALayer, omega: Double, phase: Double)] = []
    private let lightsLayer = CALayer()
    private var bulbsBuilt = false
    private var snowmanKey = ""

    private var PS: Bool { c.powerSave }
    private var lightsHeight: F { 70 * S }

    static let santaRed = C(205, 25, 35), gold = C(235, 195, 70), skin = C(255, 214, 186),
        deer = C(145, 95, 55), deerDark = C(100, 62, 32), hatRed = C(210, 30, 40)

    convenience init(controller: Controller, screen: NSScreen) {
        let frame = screen.frame
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        self.init(controller: controller,
                  bounds: CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height),
                  lightsTop: max(0, frame.maxY - screen.visibleFrame.maxY),   // the lights hang just below the menu bar
                  scale: screen.backingScaleFactor, isPrimary: frame.origin == .zero, screenFrame: frame)
    }

    /// The virtual "third screen" for the camera background: no window, rendered offscreen with `render(into:)`.
    /// It sits far away from the real screens in global coordinates, so nothing crosses into it by accident.
    convenience init(virtualFor controller: Controller, width: F, height: F) {
        self.init(controller: controller, bounds: CGRect(x: 1_000_000, y: 0, width: width, height: height),
                  lightsTop: 0, scale: 1, isPrimary: true, screenFrame: nil)
    }

    private init(controller: Controller, bounds: CGRect, lightsTop: F, scale: F, isPrimary: Bool, screenFrame: CGRect?) {
        c = controller
        screenBounds = bounds
        W = bounds.width; H = bounds.height
        self.isPrimary = isPrimary
        isVirtual = screenFrame == nil
        groundY = H
        self.lightsTop = lightsTop
        // The camera picture is small and the person covers the middle, so figures are drawn larger there.
        S = screenFrame == nil ? 1.25 : max(0.6, H / 1080)
        backingScale = scale
        images = DotImages(scale: scale)
        // JULE_DEEPSNOW=1 starts with a full snow pile (to test the plow throwing snow).
        heap = Array(repeating: ProcessInfo.processInfo.environment["JULE_DEEPSNOW"] != nil ? 18 * max(0.6, bounds.height / 1080) : 0, count: Int(W / heapStep) + 2)

        if let frame = screenFrame {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H), styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .statusBar   // over the Dock
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.isReleasedWhenClosed = false
            window.title = "JuleHygge"
            let view = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
            view.wantsLayer = true
            window.contentView = view
            window.setFrame(frame, display: false)
            root = view.layer!
            self.window = window
        } else {
            // Offscreen: a plain layer tree with a winter night sky behind everything.
            root = CALayer()
            root.frame = CGRect(x: 0, y: 0, width: W, height: H)
            root.isGeometryFlipped = false
            let sky = CAGradientLayer()
            sky.frame = root.bounds
            sky.colors = [C(52, 78, 120), C(14, 24, 48)]   // bottom → top (layer y is up)
            sky.startPoint = CGPoint(x: 0.5, y: 0)
            sky.endPoint = CGPoint(x: 0.5, y: 1)
            root.addSublayer(sky)
            window = nil
        }

        let h = H
        // snow on other windows sits on those windows, so the light string and everything that moves
        // (Santa, sparks, nisser) is drawn over it
        ledgeLayer.frame = root.bounds
        root.addSublayer(ledgeLayer)
        // the single leaves the piles on the windows are made of (see renderLedgeLeaves): with the piles, so
        // under the light string too
        ledgeLeafPool = DotPool(in: root, screenHeight: h)
        lightsSprite = Sprite(parent: root, screenHeight: h, scale: scale) { [weak self] g in self?.renderLights(g) }
        lightsLayer.frame = root.bounds
        lightsLayer.isHidden = true
        root.addSublayer(lightsLayer)
        sparkPool = DotPool(in: root, screenHeight: h)
        santaSprite = Sprite(parent: root, screenHeight: h, scale: scale) { [weak self] g in self?.drawSanta(g) }
        // autumn's kite: its string is a shape layer, the kite a small sprite at the string's end
        kiteString.frame = root.bounds
        kiteString.fillColor = nil
        kiteString.strokeColor = C(235, 225, 200, 170)
        kiteString.lineWidth = 1 * S
        kiteString.actions = ["path": NSNull(), "hidden": NSNull()]
        kiteString.isHidden = true
        root.addSublayer(kiteString)
        kiteSprite = Sprite(parent: root, screenHeight: h, scale: scale) { [weak self] g in self?.drawKite(g) }
        snowmanSprite = Sprite(parent: root, screenHeight: h, scale: scale) { [weak self] g in self?.drawSnowman(g) }
        for l in [groundFill, groundLine] {
            l.frame = root.bounds
            l.actions = ["path": NSNull(), "hidden": NSNull()]
            root.addSublayer(l)
        }
        groundFill.fillColor = c.theme.pile
        groundLine.fillColor = nil
        groundLine.strokeColor = c.theme.pileEdge
        groundLine.lineWidth = 1.5 * S
        // the single leaves a leaf pile is made of lie over its fill (see renderLeafPile)
        leafPool = DotPool(in: root, screenHeight: h)
        nisseLayer.frame = root.bounds
        root.addSublayer(nisseLayer)
        plowBitPool = DotPool(in: root, screenHeight: h)
        plowSprite = Sprite(parent: root, screenHeight: h, scale: scale) { [weak self] g in self?.drawPlow(g) }
        rainPool = DotPool(in: root, screenHeight: h)   // behind the leaves
        flakePool = DotPool(in: root, screenHeight: h)

        window?.orderFrontRegardless()
    }

    /// Renders the virtual screen to an image (camera background). The layer tree is walked and drawn by hand:
    /// CALayer.render(in:) creates an offscreen buffer for every layer with transparency, which made ~260
    /// snowflakes take ~900 ms per frame. Drawn directly, each flake is one image draw with an alpha value.
    /// Layers drawn in front of the person in the camera picture: the snow pile, the snowman, the nisser, the plow and its spray.
    private var foregroundLayers: [CALayer] { [snowmanSprite.layer, groundFill, groundLine, leafPool.container, nisseLayer, plowBitPool.container, plowSprite.layer] }

    /// The camera scene in two images: everything behind the person (sky, lights, snowfall, Santa) and, with a
    /// transparent background, what stands in front of the person (see `foregroundLayers`).
    func renderSceneImages() -> (back: CGImage?, front: CGImage?) {
        let w = Int(W), h = Int(H)
        func context() -> CGContext? {
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            ctx?.interpolationQuality = .low
            return ctx
        }
        let front = Set(foregroundLayers.map { ObjectIdentifier($0) })
        guard let b = context(), let f = context() else { return (nil, nil) }
        Self.drawTree(root, into: b, alpha: 1, skip: front)
        // the root sits at the origin with no transform, so its sublayers can be drawn on their own
        for l in root.sublayers ?? [] where front.contains(ObjectIdentifier(l)) { Self.drawTree(l, into: f, alpha: 1) }
        return (b.makeImage(), f.makeImage())
    }

    func renderSceneImage() -> CGImage? {
        let w = Int(W), h = Int(H)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.interpolationQuality = .low
        Self.drawTree(root, into: ctx, alpha: 1)
        return ctx.makeImage()
    }

    /// Draws a layer and its sublayers (the kinds this app uses: images, sprites, shapes, a gradient).
    /// The context is y-up, like the layers.
    private static func drawTree(_ l: CALayer, into g: CGContext, alpha: CGFloat, skip: Set<ObjectIdentifier> = []) {
        if l.isHidden || l.opacity <= 0 || skip.contains(ObjectIdentifier(l)) { return }
        let a = alpha * CGFloat(l.opacity)
        g.saveGState()
        g.translateBy(x: l.position.x, y: l.position.y)
        g.concatenate(l.affineTransform())
        g.translateBy(x: -l.bounds.width * l.anchorPoint.x, y: -l.bounds.height * l.anchorPoint.y)
        g.setAlpha(a)
        let r = CGRect(origin: .zero, size: l.bounds.size)
        if let grad = l as? CAGradientLayer, let colors = grad.colors as? [CGColor],
           let gr = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil) {
            g.drawLinearGradient(gr, start: CGPoint(x: grad.startPoint.x * r.width, y: grad.startPoint.y * r.height),
                                 end: CGPoint(x: grad.endPoint.x * r.width, y: grad.endPoint.y * r.height),
                                 options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        } else if let shape = l as? CAShapeLayer, let path = shape.path {
            if let f = shape.fillColor { g.setFillColor(f); g.addPath(path); g.fillPath() }
            if let st = shape.strokeColor, shape.lineWidth > 0 {
                g.setStrokeColor(st); g.setLineWidth(shape.lineWidth); g.addPath(path); g.strokePath()
            }
        } else if let c = l.contents, CFGetTypeID(c as CFTypeRef) == CGImage.typeID {
            g.draw(c as! CGImage, in: r)
        } else if let sprite = l.delegate as? Sprite {
            sprite.draw(l, in: g)
        }
        for sub in l.sublayers ?? [] { drawTree(sub, into: g, alpha: a, skip: skip) }
        g.restoreGState()
    }

    /// Tears the overlay down in a safe order: first every sprite is disconnected from its layer, then the
    /// layers are removed, and only then is the window closed. (A display change can make AppKit redraw
    /// layers of a window that is being released; a sprite must not draw for an overlay that is going away.)
    func close() {
        for sp in [lightsSprite, santaSprite, snowmanSprite, plowSprite, kiteSprite] { sp?.detach() }
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        window?.orderOut(nil)
        window?.close()
    }

    func keepOnTop() { if !paused { window?.orderFrontRegardless() } }

    /// Hidden and not updated while JuleHygge Kamera is in use (saves the work for the camera picture).
    private(set) var suspended = false
    func setSuspended(_ on: Bool) {
        guard on != suspended else { return }
        suspended = on
        root.isHidden = on || paused
    }

    // ------------------------------------------------------------------ én frame
    func frame(_ dt: F) {
        if suspended { return }
        let fullscreen = c.fullscreenRects.contains { abs($0.minX - screenBounds.minX) < 2 && abs($0.minY - screenBounds.minY) < 2 &&
            abs($0.width - screenBounds.width) < 2 && abs($0.height - screenBounds.height) < 2 }
        if fullscreen && cfg.pauseFullscreen {
            if !paused { paused = true; root.isHidden = true }
            return
        }
        if paused { paused = false; root.isHidden = false }
        frameNo += 1

        updateSnow(dt)
        updateRain(dt)
        updatePlow(dt)
        updateNisser(dt)

        renderLightsLayer()
        renderSparks()
        renderSanta()
        renderSnowman()
        renderKite()
        groundTimer -= dt
        if groundTimer <= 0 { groundTimer = 0.2; renderGround() }   // the pile changes slowly
        renderLedges()
        renderNisser()
        renderPlow()
        renderSnow()
        renderRain()
    }

    // ------------------------------------------------------------------ sne
    private func updateSnow(_ dt: F) {
        let baseCount: [F] = [110, 260, 650]
        // between two levels while the weather changes
        let amount = max(0, min(2, c.snowAmount)), lower = min(1, Int(amount))
        // (leaves are much bigger than flakes, so far fewer are needed)
        let flakesWanted = (baseCount[lower] + (baseCount[lower + 1] - baseCount[lower]) * (amount - F(lower))) * (c.theme.leaves ? 0.2 : 1)
        let logicalArea = W * H
        // Snow covers the whole screen also in power-save mode: a Mac handles it easily, power-save only lowers the frame rate.
        let areaShare: F = 1
        let target = c.snowOn ? Int(flakesWanted * min(2, logicalArea / (1920 * 1080)) * areaShare * c.snowIntensity * (isVirtual ? 1.8 : 1)) : 0
        // new flakes come in from the top; surplus flakes disappear only when they land
        let add = flakes.isEmpty ? target : max(1, target / 60)
        var i = 0
        while i < add && flakes.count < target { flakes.append(newFlake(anywhere: flakes.isEmpty || c.time < 1)); i += 1 }

        let wind = c.wind * S
        let t = c.time
        let ox = screenBounds.minX, oy = screenBounds.minY
        let ledges = !isVirtual && cfg.windowSnow && c.snowOn ? c.ledgeList.filter { !$0.moving && !$0.visible.isEmpty } : []
        var k = flakes.count - 1
        while k >= 0 {
            let f = flakes[k]
            let prevY = f.y
            f.y += f.vy * dt
            f.x += (wind * (0.4 + f.r / (4 * S)) + F(cos(t * Double(f.swaySpd) + Double(f.phase))) * f.sway) * dt
            f.rot += f.rotSpd * dt
            if f.x < -60 { f.x += W + 120 } else if f.x > W + 60 { f.x -= W + 120 }
            // some flakes land on a window's top edge (or the snow already on it)
            if f.catches && !ledges.isEmpty {
                let gx = f.x + ox, gy = f.y + oy, py = prevY + oy
                if let l = ledges.first(where: { l in
                    let top = l.settled.minY - l.height(at: gx)
                    return py < top && gy >= top && l.isVisible(gx)
                }) {
                    l.deposit(at: gx, r: f.r / S)
                    if flakes.count > target { flakes.remove(at: k) } else { flakes[k] = newFlake(anywhere: false) }
                    k -= 1
                    continue
                }
            }
            if f.y >= groundY - heapAt(f.x) {
                if cfg.snowGround { deposit(f.x, f.r) }
                if flakes.count > target { flakes.remove(at: k) } else { flakes[k] = newFlake(anywhere: false) }
            }
            k -= 1
        }

        // Snowstorm: the wind carries snow along the pile, so it drifts up against the downwind screen edge,
        // and flakes settle in long soft waves (`dune` in deposit). Drifts may grow taller and sink back slowly afterwards.
        let storm = c.effectiveSnowLevel == 2 && c.snowOn && !isVirtual
        let windNorm = max(-1.5, min(1.5, c.wind / 140))
        if storm && abs(windNorm) > 0.15 && heap.count > 2 {
            let rate = 0.02 * abs(windNorm) * dt, dir = windNorm > 0 ? 1 : -1
            let moved = heap.map { $0 * rate }
            for i in 0..<heap.count {
                let j = i + dir
                if j < 0 || j >= heap.count { continue }
                heap[i] -= moved[i]; heap[j] += moved[i]
            }
        }
        let maxH = (storm ? 30 : 18) * S, slope = 1.2 * S
        for i in 0..<(heap.count - 1) {
            let d = heap[i] - heap[i + 1]
            if d > slope { let m = (d - slope) * 0.3; heap[i] -= m; heap[i + 1] += m }
            else if d < -slope { let m = (-d - slope) * 0.3; heap[i] += m; heap[i + 1] -= m }
        }
        // snow falling off a window that went away lands in the pile below
        if !isVirtual {
            for cl in c.clumps where !cl.dead {
                let x = cl.x - ox, y = cl.y - oy
                if x >= 0 && x < W && y >= 0 && y >= groundY - heapAt(x) {
                    if cfg.snowGround { deposit(x, cl.r * S) }
                    cl.dead = true
                }
            }
        }
        let melt = !c.snowOn || !cfg.snowGround
        for i in 0..<heap.count {
            if melt { heap[i] = max(0, heap[i] - 3 * S * dt) }
            // a full pile keeps soft bumps: the limit wavers along the screen (in global x, so screens line up)
            let gx = Double(F(i) * heapStep + screenBounds.minX)
            let lim = maxH * (0.78 + 0.22 * F(0.6 * sin(gx / 37) + 0.4 * sin(gx / 13.7)))
            if heap[i] > lim { heap[i] = max(lim, heap[i] - 2 * S * dt) }
        }
    }

    // ------------------------------------------------------------------ regn (efterårsstorm)
    // In autumn a storm brings rain with it: it sets in as the weather passes "normal" on its way to storm and
    // thins out again as the storm dies down (the same gliding amount that sets the number of leaves). The
    // drops fall fast and slant with the wind; they are short streaks from one shared image.
    private static let noRain = ProcessInfo.processInfo.environment["JULE_NO_RAIN"] != nil

    private func updateRain(_ dt: F) {
        // JULE_NO_RAIN=1 leaves the rain out, to measure what it costs (measure.sh with and without)
        let strength: F = c.theme == .efteraar && c.snowOn && !Self.noRain ? max(0, min(1, c.snowAmount - 1)) : 0
        let target = Int(strength * (PS ? 70 : 130) * min(2, W * H / (1920 * 1080)))
        var add = max(1, target / 30)
        while add > 0 && rain.count < target {
            rain.append(RainDrop(x: -100 + R() * (W + 200), y: rain.count < target / 2 ? R() * groundY : -R() * 80 * S, speed: (620 + R() * 260) * S))
            add -= 1
        }
        guard !rain.isEmpty else { return }
        let slant = c.wind * S * 1.6
        var k = rain.count - 1
        while k >= 0 {
            rain[k].y += rain[k].speed * dt
            rain[k].x += slant * dt
            if rain[k].y >= groundY - heapAt(rain[k].x) {
                if rain.count > target { rain.remove(at: k) }
                else { rain[k].x = -100 + R() * (W + 200); rain[k].y = -R() * 80 * S }
            }
            k -= 1
        }
    }

    private func renderRain() {
        rainPool.begin()
        if !rain.isEmpty {
            // one angle for all drops: they fall at about the same speed
            let angle = -atan2(c.wind * S * 1.6, 750 * S)
            for d in rain where d.y > -20 * S {
                rainPool.add(images.rain, x: d.x, y: d.y, w: 5 * S, h: 20 * S, opacity: 0.42, rotation: angle)
            }
        }
        rainPool.end()
    }

    private func newFlake(anywhere: Bool) -> Flake {
        let f = Flake()
        let depth = R()
        f.r = (1 + depth * depth * 3.5) * S
        f.vy = (25 + depth * 55 + R() * 15) * S * (c.effectiveSnowLevel == 2 ? 1.5 : 1)
        f.x = -50 + R() * (W + 100)
        f.y = anywhere ? R() * groundY : -10 - R() * 60
        f.phase = R() * 6.28
        f.sway = (8 + R() * 20) * S
        f.swaySpd = 0.5 + R() * 1.2
        f.a = Int(110 + depth * 145)
        f.crystal = depth > 0.8 && R() < 0.5
        if f.crystal { f.r *= 1.6 }
        f.rot = R() * 6.28
        f.rotSpd = (R() - 0.5) * 2
        f.catches = R() < 0.5
        if c.theme.leaves {
            // a leaf: bigger, opaque, swaying wide and turning as it falls
            f.r = (5 + depth * 7) * S
            f.vy = (30 + depth * 40 + R() * 20) * S * (c.effectiveSnowLevel == 2 ? 1.4 : 1)
            f.sway = (25 + R() * 45) * S
            f.swaySpd = 0.6 + R() * 1.0
            f.a = Int(215 + depth * 40)
            f.crystal = false
            f.rotSpd = (R() - 0.5) * 5
            f.kind = Int(R() * F(images.leaves.count)) % images.leaves.count
        }
        return f
    }


    private func renderSnow() {
        flakePool.begin()
        for f in flakes {
            if f.y < -f.r * 2 { continue }
            let a = F(f.a)
            if c.theme.leaves {
                flakePool.add(images.leaves[f.kind], x: f.x, y: f.y, w: f.r * 2.6, h: f.r * 2.6, opacity: a / 255, rotation: f.rot)
            } else if f.crystal {
                if a < 60 { continue }
                flakePool.add(images.crystal, x: f.x, y: f.y, w: f.r * 2, h: f.r * 2, opacity: a / 255, rotation: f.rot)
            } else {
                // GDI version draws a dot of radius r plus half a pixel of anti-aliasing
                flakePool.add(images.flake, x: f.x, y: f.y, w: f.r * 2 + 0.5, h: f.r * 2 + 0.5, opacity: a / 255)
            }
        }
        if !isVirtual {
            let ox = screenBounds.minX, oy = screenBounds.minY
            for cl in c.clumps where !cl.dead {
                let x = cl.x - ox, y = cl.y - oy
                if x < -10 || x > W + 10 || y < -10 || y > H + 10 { continue }
                flakePool.add(c.theme.leaves ? images.leaves[Int(abs(cl.x)) % images.leaves.count] : images.flake, x: x, y: y, w: cl.r * 2 * S, h: cl.r * 2 * S, opacity: 0.95)
            }
        }
        flakePool.end()
    }


    private func deposit(_ x: F, _ r: F) {
        let idx = Int(x / heapStep)
        var amount = 0.35 * r
        if c.effectiveSnowLevel == 2 && !isVirtual {
            // dunes: long waves in global x (so they line up across screens), slowly wandering with the wind
            let gx = x + screenBounds.minX
            let dune = 0.5 + 0.5 * sin(Double(gx / (240 * S)) * 2 * .pi - c.time * 0.03 * Double(c.wind > 0 ? 1 : -1))
            amount *= 0.3 + 1.4 * F(dune)
        }
        for k in -1...1 {
            let j = idx + k
            if j >= 0 && j < heap.count { heap[j] += k == 0 ? amount : amount * 0.5 }
        }
    }

    private func heapAt(_ x: F) -> F {
        let fx = x / heapStep
        let i = Int(floor(fx))
        if i < 0 { return heap[0] }
        if i >= heap.count - 1 { return heap[heap.count - 1] }
        let t = fx - F(i)
        return heap[i] * (1 - t) + heap[i + 1] * t
    }

    /// Draws the snow on window edges that cross this screen; a path is only rebuilt when its pile changed.
    /// The piles on the windows are made of leaves too, like the pile at the bottom (renderLeafPile): single
    /// leaves over the dark fill, from the pile's top down to where it hangs below the window's edge.
    /// Laid out again a few times a second; which leaf lies where is fixed by its place on the window.
    private func renderLedgeLeaves() {
        guard c.theme.leaves, c.time - ledgeLeavesAt >= 0.3 else { return }
        ledgeLeavesAt = c.time
        func chance(_ i: Int, _ j: Int) -> F { let v = sin(F(i) * 12.9898 + F(j) * 78.233) * 43758.5453; return v - v.rounded(.down) }
        let ox = screenBounds.minX, oy = screenBounds.minY
        let size = 13 * S, across = 6 * S, down = 4.5 * S
        ledgeLeafPool.begin()
        for l in c.ledgeList {
            let dragged = l.moving && l.rect.size == l.settled.size
            guard l.hasSnow && !dragged && cfg.windowSnow,
                  l.settled.maxX > ox && l.settled.minX < ox + W && l.settled.minY > oy && l.settled.minY <= oy + H else { continue }
            let edge = l.settled.minY - oy
            for (a, b) in l.visible {
                var x = max(a, ox), column = Int(max(a, ox) / across)
                while x <= min(b, ox + W) {
                    let h = l.height(at: x), d = l.hang(at: x)
                    if h > 0.4 {
                        for row in 0...Int((h + d) / down) {
                            let p = chance(column, row + l.id), q = chance(row + 31, column), t = chance(column + 7, row + 3)
                            let y = edge - h + F(row) * down + (p - 0.5) * 3 * S - size * 0.1
                            let w = size * (0.75 + 0.5 * q)
                            ledgeLeafPool.add(images.leaves[Int(p * 9973) % images.leaves.count], x: x - ox + (q - 0.5) * across, y: y, w: w, h: w, opacity: 1, rotation: t * 6.28)
                        }
                    }
                    x += across; column += 1
                }
            }
        }
        ledgeLeafPool.end()
    }

    private func renderLedges() {
        if isVirtual { return }
        renderLedgeLeaves()
        let ox = screenBounds.minX, oy = screenBounds.minY
        var seen = Set<Int>()
        for l in c.ledgeList {
            // a window dragged around (same size) takes its snow along, so the pile is hidden until it settles;
            // a window that shrinks (minimize into the Dock) or is resized leaves the snow where it was until it is gone
            let dragged = l.moving && l.rect.size == l.settled.size
            let show = l.hasSnow && !dragged && cfg.windowSnow &&
                l.settled.maxX > ox && l.settled.minX < ox + W && l.settled.minY > oy && l.settled.minY <= oy + H
            if !show { continue }
            seen.insert(l.id)
            var e = ledgeShapes[l.id] ?? {
                let fill = CAShapeLayer(), line = CAShapeLayer()
                for sl in [fill, line] { sl.frame = ledgeLayer.bounds; sl.actions = ["path": NSNull(), "hidden": NSNull()]; ledgeLayer.addSublayer(sl) }
                fill.fillColor = c.theme.pile
                line.fillColor = nil
                line.strokeColor = c.theme.pileEdge
                line.lineWidth = 1.2
                return (fill, line, -1)
            }()
            if e.version == l.version { continue }
            e.version = l.version
            // shape layers are y-up: y' = H - y; the snow sits on the window's top edge
            let base = H - (l.settled.minY - oy)
            let fill = CGMutablePath(), line = CGMutablePath()
            for (a, b) in l.visible {
                let x0 = max(a, ox), x1 = min(b, ox + W)
                if x1 - x0 < 4 { continue }
                // only the stretches where snow has actually landed: a bare edge draws nothing (no thin white line).
                // Each stretch: the pile's top from left to right, then back along the drape hanging below the edge.
                var run: [(x: CGFloat, h: CGFloat, d: CGFloat)] = []
                func flush() {
                    if run.count >= 2 {
                        let top = run.map { CGPoint(x: $0.x, y: base + $0.h) }
                        fill.move(to: top[0])
                        for i in 1..<top.count {
                            let mid = CGPoint(x: (top[i - 1].x + top[i].x) / 2, y: (top[i - 1].y + top[i].y) / 2)
                            fill.addQuadCurve(to: mid, control: top[i - 1])
                        }
                        // the drape's lower edge, rounded through the midpoints so the lobes look soft
                        let low = run.reversed().map { CGPoint(x: $0.x, y: base - 0.5 - $0.d) }
                        // round over the end: from the pile's end down to the drape's end in a curve
                        fill.addQuadCurve(to: low[0], control: CGPoint(x: low[0].x + Ledge.step * 0.8, y: base))
                        for i in 1..<low.count {
                            let mid = CGPoint(x: (low[i - 1].x + low[i].x) / 2, y: (low[i - 1].y + low[i].y) / 2)
                            fill.addQuadCurve(to: mid, control: low[i - 1])
                        }
                        fill.addQuadCurve(to: top[0], control: CGPoint(x: low[low.count - 1].x - Ledge.step * 0.8, y: base))
                        fill.closeSubpath()
                        line.addLines(between: top)
                        // a faint outline under the drape where it hangs down, for depth
                        if run.contains(where: { $0.d > 1 }) {
                            line.move(to: low[0])
                            for i in 1..<low.count {
                                let mid = CGPoint(x: (low[i - 1].x + low[i].x) / 2, y: (low[i - 1].y + low[i].y) / 2)
                                line.addQuadCurve(to: mid, control: low[i - 1])
                            }
                        }
                    }
                    run.removeAll()
                }
                var x = x0
                while x <= x1 {
                    let h = l.height(at: x), d = l.hang(at: x)
                    if h > 0.6 || d > 0.6 {
                        // start and end each stretch on the edge itself, so the pile tapers off
                        if run.isEmpty { run.append((max(x0, x - Ledge.step) - ox, 0, 0)) }
                        run.append((x - ox, h, d))
                    } else if !run.isEmpty {
                        run.append((x - ox, 0, 0))
                        flush()
                    }
                    x += Ledge.step
                }
                if !run.isEmpty { run.append((min(x1, x) - ox, 0, 0)); flush() }
            }
            e.fill.path = fill
            e.line.path = line
            e.fill.isHidden = false; e.line.isHidden = false
            ledgeShapes[l.id] = e
        }
        for (id, e) in ledgeShapes where !seen.contains(id) {
            if c.ledges[id] == nil { e.fill.removeFromSuperlayer(); e.line.removeFromSuperlayer(); ledgeShapes[id] = nil }
            else if !e.fill.isHidden { e.fill.isHidden = true; e.line.isHidden = true; ledgeShapes[id]?.version = -1 }
        }
    }

    private var groundShown = false
    /// A leaf pile is made of leaves: single leaves of every shape and colour lie over the pile's dark fill, in
    /// rows from its surface down, each a little off its place and turned its own way. The fill only shows as
    /// shade between them. (As a plain orange shape the pile looked flat and nothing like leaves.)
    /// Which leaf lies where is fixed by its place, so the pile does not flicker; it is laid out again at most
    /// twice a second, and only when the pile has changed.
    private func renderLeafPile() {
        guard c.theme.leaves else { return }
        let sum = heap.reduce(0) { $0 + ($1 * 0.5).rounded() }
        if sum == leafPileDrawn || c.time - leafPileAt < 0.5 { return }
        leafPileDrawn = sum; leafPileAt = c.time
        func chance(_ i: Int, _ j: Int) -> F { let v = sin(F(i) * 12.9898 + F(j) * 78.233) * 43758.5453; return v - v.rounded(.down) }
        leafPool.begin()
        let size = 15 * S, across = 7 * S, down = 5 * S
        var x = -size / 2, column = 0
        while x < W + size / 2 {
            let h = heapAt(max(0, min(W - 1, x)))
            if h > 1.5 {
                for row in 0...Int(h / down) {
                    let a = chance(column, row), b = chance(row + 31, column), d = chance(column + 7, row + 3)
                    let y = groundY - h + F(row) * down + (a - 0.5) * 4 * S - size * 0.12
                    let w = size * (0.75 + 0.55 * b)
                    leafPool.add(images.leaves[Int(a * 9973) % images.leaves.count], x: x + (b - 0.5) * across, y: y, w: w, h: w, opacity: 1, rotation: d * 6.28)
                }
            }
            x += across; column += 1
        }
        leafPool.end()
    }

    private func renderGround() {
        renderLeafPile()
        let mx = heap.max() ?? 0
        if mx < 0.5 {
            if groundShown { groundFill.isHidden = true; groundLine.isHidden = true; groundShown = false }
            return
        }
        // Shape layers use the layer's y-up coordinates: y' = H - y.
        let fill = CGMutablePath(), line = CGMutablePath()
        fill.move(to: CGPoint(x: 0, y: H - groundY - 1))
        for i in 0..<heap.count {
            let p = CGPoint(x: F(i) * heapStep, y: H - (groundY - heap[i]))
            fill.addLine(to: p)
            if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
        }
        fill.addLine(to: CGPoint(x: W, y: H - groundY - 1))
        fill.closeSubpath()
        groundFill.path = fill
        groundLine.path = line
        if !groundShown { groundFill.isHidden = false; groundLine.isHidden = false; groundShown = true }
    }

    // ------------------------------------------------------------------ julemanden og gnister
    private func renderSparks() {
        let ox = screenBounds.minX, oy = screenBounds.minY
        sparkPool.begin()
        for sp in c.sparks {
            let x = sp.x - ox, y = sp.y - oy
            if x < -20 || y < -20 || x > W + 20 || y > H + 20 { continue }
            let life = sp.star ? min(1, sp.life) : sp.life / sp.max
            if sp.star {
                sparkPool.add(sp.gold ? images.goldStar : images.whiteStar, x: x, y: y, w: sp.size * 2, h: sp.size * 2,
                              opacity: life, rotation: sp.life)
            } else if sp.size > 3.5 * S {
                sparkPool.add(sp.gold ? images.goldGlint : images.whiteGlint, x: x, y: y, w: sp.size * 3.2, h: sp.size * 3.2, opacity: life)
            } else {
                sparkPool.add(sp.gold ? images.goldDot : images.whiteDot, x: x, y: y, w: sp.size, h: sp.size, opacity: life)
            }
        }
        sparkPool.end()
    }

    private func renderSanta() {
        guard c.santaActive else { santaSprite.hide(); return }
        let sc = c.santaScale * 1.1
        let sx = c.santaX - screenBounds.minX, sy = c.santaY - screenBounds.minY
        if sx < -330 * sc || sx > W + 330 * sc || sy < -150 * sc || sy > H + 150 * sc { santaSprite.hide(); return }
        santaSprite.place(CGRect(x: sx - 330 * sc, y: sy - 135 * sc, width: 660 * sc, height: 195 * sc), redraw: frameNo % 2 == 0 || santaSprite.layer.isHidden)   // moves every frame, limbs at half rate
    }

    /// One goose flying toward +x, seen from the side: grey-brown, neck stretched out, orange beak.
    private func drawGoose(_ g: CGContext, _ x: F, _ y: F, _ phase: F, _ t: F) {
        let flap: F = sin(t * 7 + phase)
        let body = C(140, 125, 105), dark = C(96, 84, 68), neck = C(118, 104, 88)
        // the far wing, a little shorter and lighter
        g.fillPoly(C(168, 154, 134), [(x + 5, y - 3), (x - 7, y - 3), (x - 5, y - 3 - 20 * flap), (x + 3, y - 3 - 21 * flap)])
        g.fillPoly(dark, [(x - 15, y - 2), (x - 26, y - 0.5), (x - 15, y + 3)])
        g.fillEllipse(body, x - 17, y - 5, 34, 10)
        g.fillEllipse(C(208, 198, 178), x - 11, y + 0.5, 21, 4.5)
        g.line(neck, 3.4, x + 14, y - 1, x + 31, y - 5, round: true)
        g.fillEllipse(neck, x + 28.5, y - 9, 8.5, 6.5)
        g.fillPoly(C(236, 140, 36), [(x + 36, y - 7.2), (x + 42.5, y - 5.4), (x + 36, y - 4.2)])
        g.fillEllipse(C(25, 25, 28), x + 33, y - 7.6, 1.8, 1.8)
        // the near wing over the body
        g.fillPoly(dark, [(x + 8, y - 2), (x - 9, y - 2), (x - 11, y - 2 - 25 * flap), (x - 2, y - 2 - 27 * flap)])
        g.line(C(70, 60, 48), 1.6, x - 11, y - 2 - 25 * flap, x - 2, y - 2 - 27 * flap, round: true)
    }

    private func drawSanta(_ g: CGContext) {
        let sc = c.santaScale * 1.1
        let sx = c.santaX - screenBounds.minX, sy = c.santaY - screenBounds.minY
        g.translateBy(x: sx, y: sy)
        g.scaleBy(x: c.santaDir * sc, y: sc)
        let t = c.santaPhase
        if c.theme == .efteraar {
            // Autumn's flyer: geese on their way south in a wedge, the leader in front and one arm longer than
            // the other. Each bird beats its wings in its own time and rides a little up and down.
            let places: [(F, F)] = [(250, -35), (182, -54), (114, -73), (46, -92), (-22, -111), (182, -16), (114, 3), (46, 22)]
            for (i, p) in places.enumerated().reversed() {
                drawGoose(g, p.0, p.1 + sin(t * 1.7 + F(i) * 1.3) * 3, F(i) * 1.9, t)
            }
            return
        }
        g.rotate(by: cos(c.santaPhase * 0.9) * -4 * c.santaDir * .pi / 180)

        let rx: [F] = [80, 140, 200, 260]
        let ry = (0..<4).map { i in -40 + sin(t * 6 + F(i) * 0.8) * 3 }
        for i in 0..<4 { g.line(C(120, 60, 30), 1.4, -14, -44, rx[i] + 4, ry[i] - 6) }
        for i in 0..<4 { drawReindeer(g, rx[i], ry[i], F(i) * 0.8, i == 3, t) }

        let red = Self.santaRed, white = C(255, 255, 255), black = C(30, 30, 30)
        g.fillEllipse(C(150, 110, 60), -92, -66, 36, 40)
        g.fillRect(C(40, 140, 70), -84, -74, 12, 12)
        g.fillRect(C(60, 100, 200), -72, -70, 10, 9)
        g.fillRect(Self.gold, -79, -74, 2, 12)

        g.fillEllipse(red, -52, -58, 32, 42)
        g.line(red, 7, -32, -48, -16, -44, round: true)
        g.fillEllipse(black, -19, -48, 8, 8)
        g.fillEllipse(Self.skin, -45, -76, 19, 19)
        g.fillEllipse(white, -42, -68, 18, 20)
        g.fillEllipse(white, -31, -70, 9, 5)
        g.fillEllipse(C(240, 150, 140), -28, -71, 5, 5)
        g.fillEllipse(black, -32, -74, 2.6, 2.6)
        g.fillPoly(red, [(-47, -72), (-25, -74), (-40, -90), (-56, -86)])
        g.fillRect(white, -48, -76, 25, 5)
        g.fillEllipse(white, -61, -91, 9, 9)

        let path = CGMutablePath()
        path.start(-82, -46)
        path.curve(-70, -36, -78, -4, -60, 2)
        path.to(12, 2)
        path.curve(26, 2, 30, -18, 40, -22)
        path.to(34, -27)
        path.curve(22, -16, 0, -21, -48, -23)
        path.to(-72, -48)
        path.closeSubpath()
        g.fillGradient(path, C(200, 30, 40), C(120, 10, 20), from: CGPoint(x: 0, y: -46), to: CGPoint(x: 0, y: 4))
        g.stroke(Self.gold, 2, path)

        let gold = Self.gold
        g.line(gold, 3, -55, 2, -55, 12, round: true)
        g.line(gold, 3, 5, 2, 5, 12, round: true)
        g.line(gold, 3, -72, 12, 22, 12, round: true)
        g.bezier(gold, 3, 22, 12, 36, 12, 38, -2, 28, -4)
        g.bezier(gold, 3, -72, 12, -80, 12, -80, 4, -74, 4)
    }

    private func drawReindeer(_ g: CGContext, _ x: F, _ y: F, _ phase: F, _ rudolph: Bool, _ t: F) {
        let gal = t * 9 + phase
        func leg(_ col: CGColor, _ w: F, _ hx: F, _ hy: F, _ a: F) {
            g.line(col, w, hx, hy, hx + sin(a) * 15, hy + cos(a) * 15, round: true)
        }
        let far = C(85, 52, 28)
        leg(far, 3.2, x + 9, y + 4, sin(gal + 0.6) * 0.8 + 0.5)
        leg(far, 3.2, x - 9, y + 4, sin(gal + .pi + 0.6) * 0.8 - 0.4)
        leg(Self.deerDark, 3.6, x + 14, y + 4, sin(gal) * 0.8 + 0.5)
        leg(Self.deerDark, 3.6, x - 14, y + 4, sin(gal + .pi) * 0.8 - 0.4)

        g.fillEllipse(C(255, 255, 255), x - 27, y - 9, 8, 7)
        g.fillEllipse(Self.deer, x - 22, y - 10, 44, 20)
        g.fillEllipse(C(200, 160, 110), x - 14, y - 1, 28, 8)
        g.fillPoly(Self.deer, [(x + 10, y - 6), (x + 18, y - 25), (x + 26, y - 22), (x + 21, y + 2)])
        g.fillEllipse(Self.deer, x + 16, y - 32, 16, 11)
        g.fillEllipse(Self.deer, x + 26, y - 29, 11, 8)
        g.fillEllipse(Self.deerDark, x + 14, y - 33, 7, 4)
        g.fillEllipse(C(0, 0, 0), x + 23, y - 30, 2.5, 2.5)

        let ant = C(205, 175, 125)
        g.line(ant, 2, x + 20, y - 31, x + 16, y - 45, round: true)
        g.line(ant, 2, x + 17, y - 41, x + 11, y - 45, round: true)
        g.line(ant, 2, x + 16, y - 45, x + 20, y - 51, round: true)
        g.line(ant, 2, x + 23, y - 31, x + 27, y - 45, round: true)
        g.line(ant, 2, x + 26, y - 41, x + 32, y - 44, round: true)
        g.line(C(190, 20, 30), 3, x + 8, y - 9, x + 5, y + 9)
        g.fillEllipse(Self.gold, x + 3, y + 5, 4.5, 4.5)

        if rudolph {
            let a = Int(90 + 70 * sin(t * 6))
            g.fillEllipse(C(255, 60, 50, a), x + 30, y - 33, 15, 15)
            g.fillEllipse(C(240, 30, 30), x + 34, y - 29, 7, 7)
        } else {
            g.fillEllipse(C(40, 25, 15), x + 35, y - 27, 4, 4)
        }
    }

    // ------------------------------------------------------------------ drage (efterår)
    // A kite hangs in the wind over the primary screen, its string tied to the scarecrow's hand (or to the
    // ground there, until the scarecrow has an arm). It drifts with the wind: further out and higher when it
    // blows, nearer and lower when it is calm. The kite and string move every other frame, the tail flutters.
    private let kiteString = CAShapeLayer()
    private var kiteSprite: Sprite!
    private var kiteX: F = 0, kiteY: F = 0, kiteLean: F = 0, kiteSet = false

    private func renderKite() {
        guard isPrimary && !isVirtual && cfg.kite && c.theme == .efteraar else { kiteSprite.hide(); kiteString.isHidden = true; return }
        guard frameNo % 2 == 0 || kiteSprite.layer.isHidden else { return }
        let baseX = W * 0.78, baseY = groundY - heapAt(W * 0.78) + 3 * S
        let held = cfg.snowman && c.snowmanStage >= 5
        let ax = baseX + (held ? 54 : 30) * S, ay = held ? baseY - 80 * S : baseY - 2 * S
        let blow = max(-1, min(1, c.wind / 90))
        let strength = min(1, abs(c.wind) / 60)
        // the wind carries it to the lee side; with no wind it hangs to the left, over the open screen
        let side: F = abs(blow) < 0.08 ? -1 : (blow < 0 ? -1 : 1)
        let wantX = max(60 * S, min(W - 60 * S, ax + side * (170 + 150 * strength) * S + F(sin(c.time * 0.5)) * 14 * S))
        let wantY = max(lightsTop + 110 * S, ay - H * (0.34 + 0.16 * strength) + F(sin(c.time * 0.8 + 1)) * 10 * S)
        if !kiteSet { kiteX = wantX; kiteY = wantY; kiteSet = true }
        kiteX += (wantX - kiteX) * 0.04
        kiteY += (wantY - kiteY) * 0.04
        kiteLean = max(-0.6, min(0.6, (kiteX - ax) / (300 * S) * 0.45))
        kiteSprite.place(CGRect(x: kiteX - 60 * S, y: kiteY - 60 * S, width: 120 * S, height: 170 * S))
        // the string sags a little between the hand and the kite's lower corner
        let kx = kiteX - sin(kiteLean) * 34 * S, ky = kiteY + cos(kiteLean) * 34 * S
        let p = CGMutablePath()
        p.move(to: CGPoint(x: ax, y: H - ay))
        p.addQuadCurve(to: CGPoint(x: kx, y: H - ky), control: CGPoint(x: (ax + kx) / 2, y: H - ((ay + ky) / 2 + 50 * S)))
        kiteString.path = p
        kiteString.isHidden = false
    }

    private func drawKite(_ g: CGContext) {
        g.translateBy(x: kiteX, y: kiteY)
        g.scaleBy(x: S, y: S)
        g.rotate(by: kiteLean)
        let red = C(206, 62, 40), yellow = C(242, 184, 52), spar = C(70, 45, 25)
        // a diamond in four panels
        g.fillPoly(red, [(0, -34), (22, -8), (0, -8)])
        g.fillPoly(yellow, [(0, -34), (-22, -8), (0, -8)])
        g.fillPoly(yellow, [(0, -8), (22, -8), (0, 34)])
        g.fillPoly(red, [(0, -8), (-22, -8), (0, 34)])
        g.line(spar, 1.2, 0, -34, 0, 34)
        g.line(spar, 1.2, -22, -8, 22, -8)
        // the tail: a line of bows that flutters
        let t = F(c.time)
        var px: F = 0, py: F = 34
        for k in 1...4 {
            let nx = sin(t * 3.1 + F(k) * 1.2) * (4 + F(k) * 2.2) - kiteLean * F(k) * 9, ny = 34 + F(k) * 17
            g.line(C(235, 225, 200, 200), 1, px, py, nx, ny)
            let bow = k % 2 == 0 ? red : yellow
            g.fillPoly(bow, [(nx, ny), (nx - 6, ny - 3.5), (nx - 6, ny + 3.5)])
            g.fillPoly(bow, [(nx, ny), (nx + 6, ny - 3.5), (nx + 6, ny + 3.5)])
            px = nx; py = ny
        }
    }

    // ------------------------------------------------------------------ snemand (bygges lidt mere hver dag)
    private func renderSnowman() {
        guard isPrimary && cfg.snowman && c.theme.hasSnowman else { snowmanPos = nil; snowmanSprite.hide(); return }
        let x = W * 0.78, y = groundY - heapAt(W * 0.78) + 3 * S
        snowmanPos = CGPoint(x: screenBounds.minX + x, y: screenBounds.minY + y)
        let key = "\(c.snowmanStage) \(Int(y))"
        let r = CGRect(x: x - 62 * S, y: y - 135 * S, width: 124 * S, height: 142 * S)
        snowmanSprite.place(r, redraw: key != snowmanKey)
        snowmanKey = key
    }

    /// Autumn's form of the snowman: a haystack that grows (stage 1–3) and a scarecrow put up beside it piece
    /// by piece (4–12), in the same place and the same frame as the snowman. Origin at the ground, y up is negative.
    private func drawScarecrow(_ g: CGContext, _ stage: Int) {
        g.fillEllipse(C(50, 35, 20, 50), -58, -3, 120, 6)
        let wood = C(110, 70, 35), straw = C(228, 188, 84), strawDark = C(160, 110, 35, 170), coal = C(35, 35, 40)

        // the haystack: a dome with loose straws
        let cx: F = -22
        let w: F = stage == 1 ? 18 : stage == 2 ? 27 : 34
        let h: F = stage == 1 ? 14 : stage == 2 ? 30 : 46
        let stack = CGMutablePath()
        stack.start(cx - w, 0)
        stack.curve(cx - w, -h * 0.9, cx - w * 0.55, -h, cx, -h)
        stack.curve(cx + w * 0.55, -h, cx + w, -h * 0.9, cx + w, 0)
        stack.closeSubpath()
        g.fillGradient(stack, C(238, 200, 100), C(188, 138, 48), from: CGPoint(x: cx - w * 0.5, y: -h), to: CGPoint(x: cx + w * 0.5, y: 0))
        g.stroke(C(140, 95, 30, 110), 1, stack)
        let straws = stage == 1 ? 6 : stage == 2 ? 12 : 20
        for i in 0..<straws {
            let t: F = (F(i) + 0.5) / F(straws)
            let u: F = (F(i) * 0.618).truncatingRemainder(dividingBy: 1)
            let px: F = cx + (t * 2 - 1) * w * 0.8
            let off: F = (px - cx) / w
            let top: F = -h * (1 - off * off).squareRoot()
            let py: F = top * (0.12 + u * 0.7)
            let lean: F = (off < 0 ? -3 : 3) * (0.4 + u)
            g.line(i % 3 == 0 ? C(250, 225, 150, 170) : strawDark, 1.2, px, py, px + lean, py + 8, round: true)
        }
        if stage >= 3 {
            g.line(straw, 1.4, cx - 4, -h + 1, cx - 9, -h - 6, round: true)
            g.line(straw, 1.4, cx + 2, -h + 1, cx + 4, -h - 7, round: true)
            g.line(straw, 1.4, cx + w - 3, -6, cx + w + 5, -9, round: true)
        }

        // the scarecrow
        let x: F = 30
        if stage >= 4 { g.line(wood, 3.4, x, 0, x, -104, round: true) }
        if stage >= 5 { g.line(wood, 3, x - 24, -80, x + 24, -80, round: true) }
        if stage >= 7 {
            let shirt = C(170, 62, 40), check = C(235, 190, 110, 120)
            g.fillPoly(shirt, [(x - 10, -87), (x + 10, -87), (x + 12, -44), (x - 12, -44)])
            g.fillPoly(shirt, [(x - 10, -87), (x - 22, -85), (x - 22, -75), (x - 10, -73)])
            g.fillPoly(shirt, [(x + 10, -87), (x + 22, -85), (x + 22, -75), (x + 10, -73)])
            for dx in [F(-5), 0, 5] { g.line(check, 1, x + dx, -87, x + dx * 1.2, -44) }
            for y in [F(-76), -65, -54] { g.line(check, 1, x - 11, y, x + 11, y) }
            g.fillRect(C(60, 90, 140), x + 2, -62, 6, 6)
            for dx in [F(-9), -4, 3, 8] { g.line(straw, 1.3, x + dx, -44, x + dx * 1.25, -37, round: true) }
        }
        if stage >= 8 {
            for dy in [F(-5), 0, 5] {
                g.line(straw, 1.4, x - 22, -80, x - 30, -80 + dy, round: true)
                g.line(straw, 1.4, x + 22, -80, x + 30, -80 + dy, round: true)
            }
        }
        if stage >= 6 {
            g.fillEllipse(C(222, 196, 150), x - 11, -109, 22, 22)
            g.strokeEllipse(C(150, 120, 80, 130), 1, x - 11, -109, 22, 22)
            g.line(C(120, 80, 40), 1.6, x - 7, -88.5, x + 7, -88.5, round: true)
        }
        if stage >= 9 {
            let stitch = C(95, 55, 30)
            g.fillEllipse(coal, x - 6, -102, 3.6, 3.6)
            g.fillEllipse(coal, x + 2.4, -102, 3.6, 3.6)
            g.fillPoly(C(205, 95, 40), [(x - 1.5, -97.5), (x + 3, -95.5), (x - 1.5, -94)])
            g.bezier(stitch, 1.2, x - 6, -93, x - 3, -89.5, x + 3, -89.5, x + 6, -93)
            for dx in [F(-3.5), 0, 3.5] { g.line(stitch, 1, x + dx, -92.6, x + dx, -89.4) }
        }
        if stage >= 10 {
            let scarf = C(40, 120, 90)
            g.fillRect(scarf, x - 9, -90, 18, 5)
            g.fillPoly(scarf, [(x + 3, -87), (x + 9, -87), (x + 13, -68), (x + 7, -68)])
            g.line(C(240, 225, 170), 1.3, x + 7.5, -74, x + 12, -74)
        }
        if stage >= 11 {
            let hat = C(214, 170, 72)
            g.fillEllipse(hat, x - 17, -112, 34, 7)
            g.fillPoly(hat, [(x - 9, -109), (x + 9, -109), (x + 6, -123), (x - 6, -123)])
            g.fillRect(C(150, 50, 35), x - 8.4, -113, 16.8, 3)
            g.line(straw, 1.2, x - 15, -108, x - 20, -104, round: true)
        }
        if stage >= 12 {
            // a pumpkin at its foot and a crow that is not the least bit scared
            g.fillEllipse(C(226, 120, 26), x + 10, -13, 19, 13)
            g.strokeEllipse(C(180, 86, 16), 1, x + 15.5, -13, 8, 13)
            g.line(C(70, 110, 40), 2, x + 19.5, -13, x + 20.5, -17, round: true)
            let bx: F = x - 19
            g.fillPoly(coal, [(bx + 5, -87), (bx + 11, -89), (bx + 7, -84)])
            g.fillEllipse(coal, bx - 5, -91, 11, 7)
            g.fillEllipse(coal, bx - 7, -94, 6, 6)
            g.fillPoly(C(230, 170, 40), [(bx - 6.5, -92), (bx - 10.5, -90.8), (bx - 6.5, -89.8)])
            g.line(coal, 1, bx, -84.5, bx, -81.5)
        }
    }

    private func drawSnowman(_ g: CGContext) {
        let stage = c.snowmanStage
        let x = W * 0.78, y = groundY - heapAt(x) + 3 * S
        g.translateBy(x: x, y: y)
        g.scaleBy(x: S, y: S)
        if c.theme == .efteraar { drawScarecrow(g, stage); return }

        g.fillEllipse(C(60, 80, 110, 50), -30, -3, 60, 6)
        let wood = C(110, 70, 35)
        if stage >= 12 {
            g.line(wood, 2.6, 32, -6, 46, -104, round: true)
            g.fillPoly(C(215, 175, 90), [(24, 6), (42, 6), (37, -14), (31, -14)])
            g.line(C(170, 30, 30), 2, 30, -11, 38, -11)
        }
        if stage >= 8 {
            g.line(wood, 2.6, -15, -66, -40, -84, round: true)
            g.line(wood, 2.6, -33, -79, -37, -91, round: true)
            g.line(wood, 2.6, -33, -79, -44, -78, round: true)
            g.line(wood, 2.6, 15, -66, 40, -80, round: true)
            g.line(wood, 2.6, 33, -76, 39, -88, round: true)
        }

        func ball(_ cx: F, _ cy: F, _ r: F) {
            let rc = CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)
            let p = CGPath(ellipseIn: rc, transform: nil)
            g.fillGradient(p, C(255, 255, 255), C(200, 216, 238), from: CGPoint(x: rc.minX + r * 0.4, y: rc.minY), to: CGPoint(x: rc.maxX - r * 0.4, y: rc.maxY))
            g.stroke(C(140, 165, 200, 70), 1, p)
        }
        if stage == 1 { ball(0, -11, 11) } else { ball(0, -24, 25) }
        if stage >= 3 { ball(0, -62, 18) }
        if stage >= 4 { ball(0, -92, 13) }

        let coal = C(35, 35, 40)
        if stage >= 7 { for i in 0..<3 { g.fillEllipse(coal, -2.4, -72.4 + F(i) * 9, 4.8, 4.8) } }
        if stage >= 10 {
            let scarf = C(200, 30, 40)
            g.fillRect(scarf, -13, -82, 26, 6)
            g.fillPoly(scarf, [(5, -78), (12, -78), (15, -57), (8, -57)])
            g.line(C(255, 255, 255), 1.5, 9, -66, 14, -66)
            g.line(C(255, 255, 255), 1.5, 10, -61, 15, -61)
        }
        if stage >= 5 {
            g.fillEllipse(coal, -6.5, -98, 4, 4)
            g.fillEllipse(coal, 2.5, -98, 4, 4)
        }
        if stage >= 6 { g.fillPoly(C(240, 130, 30), [(0, -93), (19, -89.5), (0, -87)]) }
        if stage >= 9 {
            for i in -2...2 {
                let sx = F(i) * 3, sy = -86 + 2 * (1 - (sx / 6) * (sx / 6)) + 1
                g.fillEllipse(coal, sx - 1.1, sy - 1.1, 2.2, 2.2)
            }
        }
        if stage >= 11 {
            g.fillRect(coal, -15, -106, 30, 4)
            g.fillRect(coal, -10, -127, 20, 22)
            g.fillRect(C(200, 30, 40), -10, -110, 20, 4)
        }
        if stage >= 12 {
            g.fillRect(C(40, 140, 70), -50, -13, 15, 13)
            g.line(Self.gold, 1.8, -42.5, -13, -42.5, 0)
            g.line(Self.gold, 1.8, -50, -6.5, -35, -6.5)
            g.strokeEllipse(Self.gold, 1.8, -46, -17, 3.5, 3.5)
            g.strokeEllipse(Self.gold, 1.8, -42.5, -17, 3.5, 3.5)
        }
    }

    // ------------------------------------------------------------------ sneplov
    // An orange plow truck clears the snow when it gets high, alternating direction each run.
    // Snow it scrapes up builds a growing pile in front of the blade and is thrown up as chunks.
    private var plowBits: [PlowBit] = []
    private var plowSmokeTimer: F = 0, plowChunkAcc: F = 0
    private let plowScale: F = 1.15

    // The truck itself is driven by the Controller in global coordinates, so one plow drives continuously
    // across neighbouring screens. These read its state in this screen's coordinates.
    private var plowActive: Bool { c.plow.active && c.plow.members.contains(ObjectIdentifier(self)) }
    private var plowX: F { c.plow.gx - screenBounds.minX }
    private var plowDir: F { c.plow.dir }
    private var plowWheel: F { c.plow.wheel }
    private var plowOnScreen: Bool { plowActive && plowX > -140 * S * plowScale && plowX < W + 140 * S * plowScale }
    private var plowPileHeight: F { min(34, 4 + sqrt(c.plow.pushed / S) * 0.3) }

    /// True while snow chunks or smoke from the plow are still flying on this screen.
    var isBusy: Bool { !plowBits.isEmpty }

    /// Average height of the snow pile (the Controller sends the plow when it gets high).
    var heapAverage: F { heap.reduce(0, +) / F(heap.count) }

    private func updatePlow(_ dt: F) {
        let sc = S * plowScale
        if plowActive {
            // Everything between the edge where the plow entered this screen and the blade stays scraped down.
            let blade = plowX + plowDir * 72 * sc
            let residue = 1.5 * S
            let from: F = plowDir > 0 ? 0 : W
            if (plowDir > 0 && blade > 0) || (plowDir < 0 && blade < W) {
                let i0 = max(0, Int(max(0, min(from, blade)) / heapStep))
                let i1 = min(heap.count - 1, Int(min(W, max(from, blade)) / heapStep))
                if i0 <= i1 {
                    for i in i0...i1 where heap[i] > residue { c.plow.pushed += heap[i] - residue; heap[i] = residue }
                }
            }
        }
        if plowOnScreen {
            let gy = groundY - heapAt(plowX) + S
            let ph = plowPileHeight
            if c.theme.leaves {
                // the leaf collector: leaves whirl up around its nozzle and are left behind in the air for a moment
                if ph > 6 {
                    plowChunkAcc += dt * 14
                    while plowChunkAcc >= 1 {
                        plowChunkAcc -= 1
                        let b = PlowBit()
                        b.x = plowX + plowDir * (58 + R() * 26) * sc
                        b.y = gy - (2 + R() * 10) * sc
                        b.vx = plowDir * (R() - 0.35) * 110 * S
                        b.vy = -(90 + R() * 150) * S
                        b.max = 2; b.life = 2
                        b.size = (4 + R() * 3) * S
                        b.kind = Int(R() * 1000)
                        plowBits.append(b)
                    }
                }
            } else if ph > 10 {
                plowChunkAcc += dt * 30
                while plowChunkAcc >= 1 {
                    plowChunkAcc -= 1
                    let b = PlowBit()
                    b.x = plowX + plowDir * (70 + R() * ph) * sc
                    b.y = gy - ph * sc
                    b.vx = plowDir * (80 + R() * 140) * S
                    b.vy = -(60 + R() * 140) * S
                    b.max = 2; b.life = 2
                    b.size = (1.5 + R() * 2.5) * S
                    plowBits.append(b)
                }
            }
            plowSmokeTimer -= dt
            if plowSmokeTimer <= 0 {
                plowSmokeTimer = 0.2
                let b = PlowBit()
                b.smoke = true
                b.x = plowX - plowDir * 2 * sc
                b.y = gy - 76 * sc
                b.vx = -plowDir * 25 * S
                b.vy = -30 * S
                b.max = 1.6; b.life = 1.6
                b.size = 5 * S
                plowBits.append(b)
            }
            // Nisser wave at the truck as it passes.
            for n in nisser where n.state != 2 && abs(n.x - plowX) < 140 * S { n.state = 2; n.stateTimer = 1.5 }
        }

        var i = plowBits.count - 1
        while i >= 0 {
            let b = plowBits[i]
            b.life -= dt
            b.x += b.vx * dt
            b.y += b.vy * dt
            if b.smoke { b.size += 6 * S * dt } else { b.vy += 420 * S * dt }
            if b.life <= 0 || (!b.smoke && b.vy > 0 && b.y >= groundY - heapAt(b.x)) { plowBits.remove(at: i) }
            i -= 1
        }
    }

    private func renderPlow() {
        plowBitPool.begin()
        for b in plowBits {
            if !b.smoke && c.theme.leaves {
                plowBitPool.add(images.leaves[b.kind % images.leaves.count], x: b.x, y: b.y, w: b.size * 2.6, h: b.size * 2.6,
                                opacity: 1, rotation: b.life * 7 + F(b.kind))
                continue
            }
            plowBitPool.add(b.smoke ? images.smoke : images.chunk, x: b.x, y: b.y, w: b.size * 2, h: b.size * 2,
                            opacity: b.smoke ? 90 / 255 * b.life / b.max : 235 / 255)
        }
        plowBitPool.end()
        guard plowOnScreen else { plowSprite.hide(); return }
        let sc = S * plowScale
        let gy = groundY - heapAt(plowX) + S
        plowSprite.place(CGRect(x: plowX - 130 * sc, y: gy - 100 * sc, width: 260 * sc, height: 106 * sc), redraw: frameNo % 2 == 0 || plowSprite.layer.isHidden)
    }

    private func drawPlow(_ g: CGContext) {
        let sc = S * plowScale
        let gy = groundY - heapAt(plowX) + S
        let ph = plowPileHeight
        g.translateBy(x: plowX, y: gy)
        g.scaleBy(x: plowDir * sc, y: sc)

        // Autumn's form is a leaf collector: the same truck in green, with a suction nozzle and hose in place
        // of the blade, and an open body heaped with leaves in place of the salt spreader.
        let autumn = c.theme == .efteraar
        let o = autumn ? C(72, 138, 78) : C(235, 130, 20), od = autumn ? C(44, 96, 52) : C(185, 95, 10)
        let dark = C(50, 50, 55), grey = C(110, 110, 115), glass = C(175, 210, 235)
        // exhaust stack
        g.fillRect(grey, -4, -76, 4, 30)
        if autumn {
            // the hose rises in front of the cab and bends back over it into the body (drawn first, so the cab hides part of it)
            g.bezier(C(38, 38, 42), 8, 62, -12, 66, -62, 38, -80, -10, -56)
            g.bezier(C(90, 90, 96), 1.5, 62, -12, 66, -62, 38, -80, -10, -56)
            // leaves heaped over the edge of the body
            for (i, lx) in [F(-74), -63, -52, -41, -30, -19].enumerated() {
                g.fillEllipse(Theme.leafColours[(i * 2) % Theme.leafColours.count], lx - 8, -62 + F(i % 2) * 3, 16, 12)
                g.fillEllipse(Theme.leafColours[(i * 2 + 1) % Theme.leafColours.count], lx - 2, -59 - F(i % 2) * 3, 12, 9)
            }
        } else {
            // salt spreader at the back, with a spinning disc
            g.fillRect(grey, -92, -32, 12, 16)
            let sa = plowWheel * 2
            g.line(C(70, 70, 75), 2, -86 - cos(sa) * 6, -14, -86 + cos(sa) * 6, -14)
        }
        // dump body with ribs and a reflective stripe
        g.fillRect(o, -80, -50, 74, 36)
        g.fillRect(od, -82, -53, 78, 5)
        for rx: F in [-62, -44, -26] { g.line(od, 2, rx, -48, rx, -16) }
        // cab
        g.fillPoly(o, [(-2, -14), (-2, -64), (26, -64), (40, -44), (43, -14)])
        g.fillPoly(glass, [(14, -59), (25, -59), (36, -43), (14, -43)])
        g.fillRect(glass, 1, -59, 10, 16)
        g.line(od, 1.2, 12, -60, 12, -16)
        g.fillRect(dark, 4, -38, 5, 2)
        g.fillRect(C(255, 255, 255, 230), -80, -26, 123, 3)
        g.fillEllipse(C(255, 245, 190), 38, -26, 5, 5)
        // amber beacon on the roof, flashing
        g.fillRect(dark, 12, -68, 10, 4)
        let flash = 0.5 + 0.5 * F(sin(c.time * 12))
        g.fillEllipse(C(255, 170, 0, Int(150 * flash)), 3, -82, 28, 24)
        g.fillEllipse(C(255, 200 + Int(55 * flash), 120 + Int(60 * flash)), 13, -74, 8, 7)
        // chassis and wheels with rotating spokes
        g.fillRect(dark, -86, -16, 132, 7)
        for wx: F in [-58, -32, 26] {
            g.fillEllipse(C(30, 30, 32), wx - 10, -20, 20, 20)
            g.fillEllipse(C(160, 160, 165), wx - 5, -15, 10, 10)
            for k in 0..<3 {
                let a = plowWheel + F(k) * .pi / 3
                let dx = cos(a) * 5, dy = sin(a) * 5
                g.line(C(60, 60, 65), 1.6, wx - dx, -10 - dy, wx + dx, -10 + dy)
            }
        }
        if autumn {
            // the leaves it is about to take, and the wide nozzle at the ground with a warning stripe
            for (i, lx) in [F(74), 82, 90, 98].enumerated() where F(i) * 7 < ph {
                g.fillEllipse(Theme.leafColours[i % Theme.leafColours.count], lx - 7, -7 - F(i % 2) * 3, 14, 9)
            }
            g.line(C(80, 80, 85), 3, 42, -12, 56, -14)
            g.fillPoly(dark, [(54, -18), (70, -18), (80, 2), (50, 2)])
            g.fillRect(C(250, 195, 30), 51, -3, 28, 3)
            return
        }
        // snow pile in front of the blade
        let pile = CGMutablePath()
        pile.start(56, 1)
        pile.curve(60, -ph, 74 + ph * 0.6, -ph * 0.95, 72 + ph * 1.6, 1)
        pile.closeSubpath()
        g.fill(C(250, 252, 255, 250), pile)
        g.stroke(C(170, 200, 230, 120), 1, pile)
        // plow arm and curved yellow blade with black warning stripes
        g.line(C(80, 80, 85), 3, 42, -12, 55, -16)
        let blade = CGMutablePath()
        blade.start(54, -38)
        blade.curve(66, -30, 70, -14, 68, 2)
        blade.to(56, 2)
        blade.curve(58, -12, 54, -28, 50, -38)
        blade.closeSubpath()
        g.fill(C(250, 195, 30), blade)
        g.saveGState()
        g.addPath(blade); g.clip()
        var sy: F = -44
        while sy < 8 { g.line(C(40, 40, 40), 3, 46, sy, 74, sy + 14); sy += 9 }
        g.restoreGState()
        g.stroke(C(130, 95, 10), 1.2, blade)
    }

    // ------------------------------------------------------------------ nisser
    static let tunics = [C(115, 120, 130), C(40, 105, 65), C(150, 35, 45), C(70, 85, 145)]
    static let gifts = [C(40, 140, 70), C(60, 100, 200), C(200, 40, 60), C(150, 80, 180)]

    func nisseWave(_ seconds: F) {
        for n in nisser { n.state = 2; n.stateTimer = seconds }
    }

    private func updateNisser(_ dt: F) {
        // Every 1½–3 minutes a nisse arrives or leaves. The offset is pulled back toward 0, so the
        // number swings a little up and down but stays around the chosen count over time.
        nisseChangeTimer -= dt
        if nisseChangeTimer <= 0 {
            // JULE_NISSE_SECONDS=N changes the interval (for testing)
            nisseChangeTimer = F(Double(ProcessInfo.processInfo.environment["JULE_NISSE_SECONDS"] ?? "") ?? Double(90 + R() * 90))
            if nisseOffset == 0 { nisseOffset = R() < 0.5 ? -1 : 1 }
            else if R() < 0.7 { nisseOffset += nisseOffset > 0 ? -1 : 1 }
            else { nisseOffset = max(-2, min(2, nisseOffset + (nisseOffset > 0 ? 1 : -1))) }
        }
        let nisserOn = cfg.nisser && c.theme.hasNisser
        let target = nisserOn ? max(1, cfg.nisseCount + nisseOffset) : 0
        if ProcessInfo.processInfo.environment["JULE_NISSE_SECONDS"] != nil, frameNo % 40 == 0, isPrimary {
            FileHandle.standardError.write("t=\(Int(c.time)) target=\(target) nisser=\(nisser.count) leaving=\(nisser.filter { $0.leaving }.count) entering=\(nisser.filter { $0.entering }.count) snow=\(String(format: "%.2f", c.snowIntensity))\n".data(using: .utf8)!)
        }
        let staying = nisser.filter { !$0.leaving }.count
        if staying < target {
            // At start-up everyone is already there; later arrivals walk in from a screen edge.
            let arriving = !nisser.isEmpty || c.time > 2
            for _ in 0..<(arriving ? 1 : target - staying) { addNisse(walkingIn: arriving) }
        } else if staying > target {
            if !nisserOn {
                while !nisser.isEmpty { removeNisse(at: nisser.count - 1) }
            } else if let n = nisser.last(where: { !$0.leaving && !$0.entering && !$0.crossing }) {
                // Walks off at an edge with no screen beyond it if there is one (so the count really goes down),
                // otherwise at the nearest edge, where it crosses to the neighbouring screen.
                n.leaving = true
                n.state = 0
                let left = c.neighbor(of: self, dir: -1) == nil, right = c.neighbor(of: self, dir: 1) == nil
                if left != right { n.dir = left ? -1 : 1 } else { n.dir = n.x < W / 2 ? -1 : 1 }
            }
        }

        meetNisser()
        for n in nisser {
            n.meetCooldown = max(0, n.meetCooldown - dt)
            if n.meetTimer > 0 {
                let before = n.meetTimer
                n.meetTimer -= dt
                // halfway through the meeting the gift changes hands
                if before > Self.meetTime / 2 && n.meetTimer <= Self.meetTime / 2, let o = n.meetWith { exchangeGifts(n, o) }
                if n.meetTimer <= 0 {
                    // say goodbye and walk on, each in its own direction (past each other)
                    n.meetWith = nil
                    n.state = 0
                    n.stateTimer = 4 + R() * 6
                    n.meetCooldown = 20
                }
                n.t += dt
                continue
            }
            // Wrap at 200π (a whole number of periods for both the wave and the hat sway).
            n.t += dt
            if n.t > 200 * .pi { n.t -= 200 * .pi }
            n.stateTimer -= dt
            if n.state == 0 {
                n.x += n.dir * n.speed * dt
                n.walkPhase += dt * n.speed / (4.5 * S)
                if n.entering && n.x > 30 * S && n.x < W - 30 * S { n.entering = false }
                if !n.entering && !n.leaving && !n.crossing {
                    // At an edge with a neighbouring screen, about half the nisser walk on over to it.
                    if n.x < 30 * S {
                        if c.neighbor(of: self, dir: -1) != nil && R() < 0.5 { n.crossing = true } else { n.x = 30 * S; n.dir = 1 }
                    }
                    if n.x > W - 30 * S {
                        if c.neighbor(of: self, dir: 1) != nil && R() < 0.5 { n.crossing = true } else { n.x = W - 30 * S; n.dir = -1 }
                    }
                }
                // no stopping or turning while arriving, leaving or crossing to another screen
                if n.entering || n.leaving || n.crossing { continue }
                if n.stateTimer <= 0 {
                    let r = R()
                    if r < 0.3 { n.state = 1; n.stateTimer = 2 + R() * 3 }
                    else if r < 0.5 { n.state = 2; n.stateTimer = 2.5 }
                    else { if r < 0.7 { n.dir = -n.dir }; n.stateTimer = 4 + R() * 8 }
                }
            } else if n.leaving {
                n.state = 0   // stop waving and keep walking out
            } else if n.stateTimer <= 0 {
                n.state = 0
                n.stateTimer = 4 + R() * 8
                if R() < 0.4 { n.dir = -n.dir }
            }
        }
    }

    static let meetTime: F = 2.4

    /// Two nisser walking toward each other stop when they meet, if at least one of them carries a gift.
    private func meetNisser() {
        func free(_ n: Nisse) -> Bool {
            n.state == 0 && n.meetTimer <= 0 && n.meetCooldown <= 0 && !n.entering && !n.leaving && !n.crossing
        }
        for a in nisser where free(a) {
            for b in nisser where b !== a && free(b) && a.dir != b.dir && (a.carriesGift || b.carriesGift) {
                let d = b.x - a.x
                // b is in front of a, close enough to reach out
                guard d * a.dir > 0, abs(d) < 24 * S * (a.size + b.size) / 2 else { continue }
                for n in [a, b] { n.meetTimer = Self.meetTime; n.state = 1; n.meetWith = nil }
                a.meetWith = b
                return   // one meeting at a time is plenty
            }
        }
    }

    /// One gift: it goes to the other nisse. Two gifts: they swap.
    private func exchangeGifts(_ a: Nisse, _ b: Nisse) {
        if a.carriesGift && b.carriesGift {
            swap(&a.gift, &b.gift); swap(&a.giftIndex, &b.giftIndex)
        } else {
            let (giver, taker) = a.carriesGift ? (a, b) : (b, a)
            taker.carriesGift = true; taker.gift = giver.gift; taker.giftIndex = giver.giftIndex
            giver.carriesGift = false
        }
        a.refreshVariant(); b.refreshVariant()
        if ProcessInfo.processInfo.environment["JULE_DEBUG"] == "1" { ErrorLog.debug("nisser mødtes: gave \(a.carriesGift && b.carriesGift ? "byttet" : "overrakt")") }
    }

    private func addNisse(walkingIn: Bool) {
        let n = Nisse()
        n.dir = R() < 0.5 ? -1 : 1
        if walkingIn {
            n.entering = true
            n.x = n.dir > 0 ? -40 * S : W + 40 * S
        } else {
            n.x = 60 * S + R() * (W - 120 * S)
        }
        n.speed = (22 + R() * 18) * S
        n.size = 0.85 + R() * 0.3
        let ti = Int.random(in: 0..<Self.tunics.count)
        n.tunic = Self.tunics[ti]
        n.mitten = ti == 2 ? C(40, 105, 65) : Self.hatRed   // red tunic gets green mittens
        n.carriesGift = R() < 0.4
        let gi = Int.random(in: 0..<Self.gifts.count)
        n.gift = Self.gifts[gi]
        n.tunicIndex = ti
        n.giftIndex = gi
        n.refreshVariant()
        n.stateTimer = 4 + R() * 6
        n.t = R() * 10
        appendNisse(n)
    }

    private func appendNisse(_ n: Nisse) {
        nisser.append(n)
        let l = CALayer()
        l.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "transform": NSNull(), "hidden": NSNull()]
        nisseLayer.addSublayer(l)
        nisseLayers.append(l)
    }

    /// A nisse arriving from the neighbouring screen: it walks in at the matching edge, same clothes and direction.
    func receiveNisse(_ n: Nisse, fromScale oldS: F) {
        n.crossing = false
        n.leaving = false
        n.entering = true
        n.state = 0
        n.speed = n.speed / oldS * S
        n.x = n.dir > 0 ? -40 * S : W + 40 * S
        n.stateTimer = 4 + R() * 6
        appendNisse(n)
        if ProcessInfo.processInfo.environment["JULE_NISSE_SECONDS"] != nil {
            FileHandle.standardError.write("t=\(Int(c.time)) nisse krydsede til skærm ved x=\(Int(screenBounds.minX)) retning \(n.dir > 0 ? "→" : "←") (\(nisser.count) nisser her nu)\n".data(using: .utf8)!)
        }
    }

    private func removeNisse(at i: Int) {
        nisser.remove(at: i)
        nisseLayers.remove(at: i).removeFromSuperlayer()
    }

    // Frames per cycle: walking (legs + hat sway, period 4π of the walk phase), standing (hat sway), waving (arm).
    private static let walkFrames = 16, standFrames = 8, waveFrames = 8

    private func renderNisser() {
        // Nisser that have walked off the screen continue on the neighbouring screen in that direction, if there
        // is one; otherwise they are gone.
        for i in stride(from: nisser.count - 1, through: 0, by: -1) {
            let n = nisser[i]
            guard (n.leaving || n.crossing) && (n.x < -45 * S || n.x > W + 45 * S) else { continue }
            removeNisse(at: i)
            if let next = c.neighbor(of: self, dir: n.dir), cfg.nisser { next.receiveNisse(n, fromScale: S) }
        }
        for (i, n) in nisser.enumerated() {
            let sc = S * n.size
            let gy = groundY - heapAt(n.x) + 2 * S
            let frame: Int
            switch n.state {
            case 0: frame = Int((n.walkPhase / (4 * .pi)).truncatingRemainder(dividingBy: 1) * F(Self.walkFrames)) % Self.walkFrames
            case 1: frame = Int((n.t * 1.5 / (2 * .pi)).truncatingRemainder(dividingBy: 1) * F(Self.standFrames)) % Self.standFrames
            default: frame = Int((n.t * 11 / (2 * .pi)).truncatingRemainder(dividingBy: 1) * F(Self.waveFrames)) % Self.waveFrames
            }
            let key = "\(n.variant)-\(n.state)-\(frame)"
            let img = nisseFrames[key] ?? renderNisseFrame(n, frame, key)
            let l = nisseLayers[i]
            if l.contents == nil || (l.contents as! CGImage) !== img { l.contents = img }
            l.bounds = CGRect(x: 0, y: 0, width: 64 * sc, height: 80 * sc)
            l.position = CGPoint(x: n.x, y: H - (gy - 32 * sc))
            l.setAffineTransform(CGAffineTransform(scaleX: n.dir, y: 1))
        }
    }

    /// Draws one pose at the largest nisse size; smaller nisser and the walking direction are GPU scaling.
    private func renderNisseFrame(_ n: Nisse, _ frame: Int, _ key: String) -> CGImage {
        let maxSc = S * 1.15
        let img = renderImage(width: 64 * maxSc, height: 80 * maxSc, scale: backingScale) { g in
            g.scaleBy(x: maxSc, y: maxSc)
            g.translateBy(x: 32, y: 72)
            if c.theme.animals { drawAnimal(g, n, frame) } else { drawNisse(g, n, frame) }
        }!
        nisseFrames[key] = img
        return img
    }

    private func drawNisse(_ g: CGContext, _ n: Nisse, _ frame: Int) {
        let p: F = n.state == 0 ? F(frame) / F(Self.walkFrames) * 4 * .pi : 0
        let standPhase: F = n.state == 1 ? F(frame) / F(Self.standFrames) * 2 * .pi : 0
        let wavePhase: F = n.state == 2 ? F(frame) / F(Self.waveFrames) * 2 * .pi : 0
        let walking = n.state == 0
        let legA: F = walking ? sin(p) * 0.55 : 0
        let bob: F = walking ? -abs(sin(p)) * 1.5 : 0

        g.fillEllipse(C(60, 80, 110, 50), -11, -2, 22, 4)

        func leg(_ hx: F, _ hy: F, _ a: F) {
            let fx = hx + sin(a) * 12, fy = hy + cos(a) * 12
            g.line(C(80, 80, 92), 5, hx, hy, fx, fy, round: true)
            g.fillEllipse(C(62, 40, 28), fx - 3, fy - 2, 9, 5)
        }
        leg(-2, -15 + bob, legA)
        leg(2, -15 + bob, -legA)

        g.translateBy(x: 0, y: bob)
        let backArm: F, frontArm: F
        if n.state == 2 { backArm = -legA * 0.8; frontArm = 2.5 + sin(wavePhase) * 0.45 }
        else if n.carriesGift { backArm = 1.3; frontArm = 1.3 }
        else { backArm = -legA * 0.9; frontArm = legA * 0.9 }

        func arm(_ sx: F, _ sy: F, _ a: F) {
            let hx = sx + sin(a) * 10, hy = sy + cos(a) * 10
            g.line(n.tunic, 4.2, sx, sy, hx, hy, round: true)
            g.fillEllipse(n.mitten, hx - 2.5, hy - 2.5, 5, 5)
        }
        arm(-1, -29, backArm)
        g.fillEllipse(n.tunic, -10, -34, 20, 22)
        g.fillRect(C(35, 30, 30), -9.5, -20, 19, 3)
        g.fillRect(Self.gold, 2, -20.5, 3.5, 4)

        if n.carriesGift && n.state != 2 {
            g.fillRect(n.gift, 6, -31, 11, 10)
            g.line(Self.gold, 1.6, 11.5, -31, 11.5, -21)
            g.line(Self.gold, 1.6, 6, -26, 17, -26)
            g.strokeEllipse(Self.gold, 1.6, 9, -34, 3, 3)
            g.strokeEllipse(Self.gold, 1.6, 12, -34, 3, 3)
        }

        g.fillEllipse(Self.skin, -6, -44, 13, 12)
        let beard = CGMutablePath()
        beard.start(-6, -39)
        beard.curve(-7, -30, -2, -22, 3, -20)
        beard.curve(7, -24, 9, -32, 7.5, -39)
        beard.closeSubpath()
        g.fill(C(250, 250, 250), beard)
        arm(1, -29, frontArm)
        g.fillEllipse(C(240, 160, 150), 4, -40, 5, 5)

        let sway = sin(walking ? p * 0.5 : standPhase) * 2.5
        let tipX = -14 + sway, tipY: F = -57
        let hat = CGMutablePath()
        hat.start(-7.5, -39)
        hat.to(8, -39)
        hat.curve(9, -54, 0, -62, tipX, tipY)
        hat.curve(-6, -57, -7, -49, -7.5, -39)
        hat.closeSubpath()
        g.fill(Self.hatRed, hat)
        g.line(C(150, 15, 25), 2, -7.5, -39.5, 8, -39.5)
        g.fillEllipse(C(255, 255, 255), tipX - 3, tipY - 3, 6, 6)
    }

    // ------------------------------------------------------------------ pindsvin og egern (efterår)
    /// The autumn theme's walkers. They are nisser in everything but looks: they walk, stop, wave, cross to the
    /// next screen and meet to hand over what they carry. A hedgehog carries an apple on its spines, a squirrel an
    /// acorn in its paws. Which animal a walker is follows its clothes' number, so it stays the same animal.
    /// Drawn like a nisse: feet at (0, 0), y up is negative, facing right.
    private func drawAnimal(_ g: CGContext, _ n: Nisse, _ frame: Int) {
        let p: F = n.state == 0 ? F(frame) / F(Self.walkFrames) * 4 * .pi : 0
        let standPhase: F = n.state == 1 ? F(frame) / F(Self.standFrames) * 2 * .pi : 0
        let wavePhase: F = n.state == 2 ? F(frame) / F(Self.waveFrames) * 2 * .pi : 0
        let walking = n.state == 0
        let dark = C(52, 36, 26)
        g.fillEllipse(C(60, 40, 20, 50), -13, -2, 26, 4)

        if n.tunicIndex % 2 == 0 {
            // ---- hedgehog
            let spine = C(104, 74, 50), spineDark = C(70, 48, 32), fur = C(216, 182, 142)
            let bob: F = walking ? -abs(sin(p)) * 1.0 : 0
            // sniffing the air when it "waves"
            let sniff: F = n.state == 2 ? -4 - sin(wavePhase) * 2 : sin(standPhase) * 0.6
            for (hx, phase) in [(F(-10), F(0)), (-4, .pi), (5, .pi), (11, 0)] {
                let fx = hx + (walking ? sin(p + phase) * 3 : 0)
                g.line(spineDark, 3.6, hx, -5 + bob, fx, 0, round: true)
            }
            g.translateBy(x: 0, y: bob)
            // the face: a tan cone ending in the nose
            let face = CGMutablePath()
            face.start(4, -22)
            face.curve(14, -22, 20, -14, 25, -7 + sniff)
            face.curve(22, -3, 14, -2, 4, -2)
            face.closeSubpath()
            g.fill(fur, face)
            // the spiny back
            let back = CGMutablePath()
            back.start(-19, -2)
            back.curve(-22, -22, -6, -29, 6, -24)
            back.curve(12, -20, 12, -8, 8, -2)
            back.closeSubpath()
            g.fill(spine, back)
            for i in 0..<10 {
                let a = F.pi * (1.02 - 0.84 * F(i) / 9)
                let bx = -5 + cos(a) * 15, by = -11 - sin(a) * 15
                g.line(spineDark, 1.8, bx, by, bx + cos(a) * 6, by - sin(a) * 6, round: true)
            }
            for i in 0..<6 {
                let a = F.pi * (0.9 - 0.7 * F(i) / 5)
                let bx = -5 + cos(a) * 8, by = -9 - sin(a) * 8
                g.line(spineDark, 1.4, bx, by, bx + cos(a) * 5, by - sin(a) * 5, round: true)
            }
            g.fillEllipse(spine, 6, -22, 6, 6)                      // ear
            g.fillEllipse(dark, 14, -15 + sniff * 0.4, 3.2, 3.2)     // eye
            g.fillEllipse(dark, 22.5, -9.5 + sniff, 4.5, 4.5)        // nose
            if n.carriesGift && n.state != 2 {
                // an apple stuck on the spines
                let apple = [C(206, 48, 44), C(196, 176, 52), C(222, 120, 40)][n.giftIndex % 3]
                g.fillEllipse(apple, -11, -41, 13, 12)
                g.line(spineDark, 1.6, -4.5, -41, -3.5, -45, round: true)
                g.fillEllipse(C(88, 150, 60), -3.5, -47, 6, 3.5)
                g.fillEllipse(C(255, 255, 255, 120), -8.5, -39, 3, 3)
            }
        } else {
            // ---- squirrel
            let rust = C(192, 94, 46), rustDark = C(150, 66, 30), cream = C(242, 222, 190)
            let bob: F = walking ? -abs(sin(p)) * 3.0 : 0
            let flick: F = walking ? sin(p * 0.5) * 2 : sin(standPhase) * 1.5 + (n.state == 2 ? sin(wavePhase) * 3 : 0)
            g.translateBy(x: 0, y: bob)
            // the bushy tail, curling up behind the back
            let tail = CGMutablePath()
            tail.start(-7, -5)
            tail.curve(-31, -6, -33 + flick, -38, -16 + flick, -47)
            tail.curve(-7 + flick, -51, -1 + flick, -41, -8, -35)
            tail.curve(-17, -28, -13, -15, -5, -9)
            tail.closeSubpath()
            g.fill(rust, tail)
            g.line(rustDark, 1.4, -18 + flick * 0.6, -40, -22, -20, round: true)
            // hind leg and foot
            let step: F = walking ? sin(p) * 3 : 0
            g.fillEllipse(rustDark, -7, -11, 15, 10)
            g.line(rustDark, 4, 1, -3, 8 + step, -1, round: true)
            // body and belly
            g.fillEllipse(rust, -9, -30, 17, 27)
            g.fillEllipse(cream, -1, -25, 8, 19)
            // head, ear, eye, nose
            g.fillEllipse(rust, 0, -43, 16, 14)
            let ear = CGMutablePath()
            ear.start(3, -41); ear.to(5, -51); ear.to(10, -42); ear.closeSubpath()
            g.fill(rustDark, ear)
            g.fillEllipse(cream, 9, -36, 7, 6)
            g.fillEllipse(dark, 9.5, -39, 3, 3)
            g.fillEllipse(dark, 15, -35, 2.6, 2.6)
            // the front paw: holding the acorn, waving, or swinging
            let hand: CGPoint
            if n.state == 2 { hand = CGPoint(x: 11, y: -37 + sin(wavePhase) * 3) }
            else if n.carriesGift { hand = CGPoint(x: 11, y: -24) }
            else { hand = CGPoint(x: 9 + (walking ? sin(p) * 2 : 0), y: -20) }
            if n.carriesGift && n.state != 2 {
                g.fillEllipse(C(176, 128, 66), 9, -27, 8, 10)
                g.fillEllipse(C(104, 70, 34), 8.5, -29, 9, 5)
                g.line(C(104, 70, 34), 1.4, 13, -29, 13, -31.5, round: true)
            }
            g.line(rustDark, 3.4, 3, -25, hand.x, hand.y, round: true)
        }
    }

    // ------------------------------------------------------------------ julelys
    static let bulbColors = [C(255, 60, 60), C(60, 220, 90), C(255, 200, 60), C(80, 150, 255), C(255, 110, 200)]
    /// The lanterns on autumn's garland all burn warm.
    static let lanternColors = [C(255, 170, 50), C(255, 140, 40), C(255, 200, 90)]

    // The wire, sockets and dimmed bulbs are drawn once. Each bulb's bright version (glow, colour, shine)
    // is a separate layer whose opacity twinkles via a Core Animation loop, so the twinkle costs no CPU.
    private func renderLightsLayer() {
        guard cfg.lights && c.theme.hasLights else { lightsSprite.hide(); lightsLayer.isHidden = true; return }
        if lightsSprite.layer.isHidden { lightsSprite.place(CGRect(x: 0, y: lightsTop, width: W, height: lightsHeight)) }
        if !bulbsBuilt { buildBulbs(); bulbsBuilt = true }
        lightsLayer.isHidden = false
        // The twinkle is slow, so 10 updates/s (5 in power-save mode) is plenty.
        lightsTimer -= 1
        if lightsTimer <= 0 {
            lightsTimer = PS ? 3 : 3
            for b in bulbLayers {
                // brightness 0.55 + 0.45·sin(ω·t + φ), as in the Windows version (0.1…1 over the dimmed bulb)
                b.layer.opacity = Float(0.55 + 0.45 * sin(c.time * b.omega + b.phase))
            }
        }
    }
    private var lightsTimer = 0

    private func forEachBulb(_ body: (_ idx: Int, _ bx: F, _ by: F) -> Void) {
        let span = 230 * S, sag = 22 * S, top = lightsTop + 1
        var idx = 0
        var x0 = -span * 0.3
        while x0 < W {
            for b in 0..<4 {
                let u = (F(b) + 0.5) / 4
                body(idx, x0 + u * span, top + sag * (1 - (2 * u - 1) * (2 * u - 1)))
                idx += 1
            }
            x0 += span
        }
    }

    private func buildBulbs() {
        let scale = backingScale
        let w = 7 * S, h = 11 * S, bw = 26 * S, bh = 28 * S
        let autumn = c.theme == .efteraar
        let S = self.S
        let bright = (autumn ? Self.lanternColors : Self.bulbColors).map { col in
            renderImage(width: bw, height: bh, scale: scale) { g in
                g.fillEllipse(withAlpha(col, 70), 0, 1 * S, 26 * S, 26 * S)
                if autumn {
                    // the lit pane of a small lantern, with its flame
                    g.fillRect(col, bw / 2 - 3.5 * S, 4.5 * S, 7 * S, 9 * S)
                    g.fillEllipse(C(255, 250, 215, 230), bw / 2 - 1.5 * S, 7.5 * S, 3 * S, 5 * S)
                } else {
                    g.fillEllipse(col, bw / 2 - w / 2, 3 * S, w, h)
                    g.fillEllipse(C(255, 255, 255, 160), bw / 2 - w / 4, 5 * S, w / 3, h / 3)
                }
            }
        }
        forEachBulb { idx, bx, by in
            let l = CALayer()
            l.contents = bright[idx % bright.count]
            l.contentsScale = scale
            l.frame = CGRect(x: bx - 13 * S, y: H - (by + bh), width: bw, height: bh)
            l.actions = ["opacity": NSNull()]
            bulbLayers.append((l, 1.3 + Double(idx * 37 % 10) * 0.12, Double(idx) * 1.7))
            lightsLayer.addSublayer(l)
        }
    }

    private func renderLights(_ g: CGContext) {
        let span = 230 * S, sag = 22 * S, top = lightsTop + 1
        // Autumn's form is a garland: a brown vine with leaves hanging from it, and small lanterns where the
        // bulbs are (their lit panes are the twinkling layers, see buildBulbs).
        let autumn = c.theme == .efteraar
        let wire = autumn ? C(104, 68, 34, 235) : C(25, 60, 35, 220), socket = C(30, 70, 40)
        var x0 = -span * 0.3
        while x0 < W {
            g.setStrokeColor(wire); g.setLineWidth(2 * S); g.setLineCap(.round)
            g.beginPath()
            for k in 0...24 {
                let u = F(k) / 24
                let p = CGPoint(x: x0 + u * span, y: top + sag * (1 - (2 * u - 1) * (2 * u - 1)))
                if k == 0 { g.move(to: p) } else { g.addLine(to: p) }
            }
            g.strokePath()
            x0 += span
        }
        if autumn {
            // leaves along the vine, each hanging by its stalk at its own angle (none where a lantern hangs)
            var n = 0
            var lx0 = -span * 0.3
            while lx0 < W {
                for k in 0..<12 where k % 3 != 1 {
                    let u = (F(k) + 0.5) / 12
                    let size = (15 + F((n * 7) % 5) * 1.5) * S
                    g.saveGState()
                    g.translateBy(x: lx0 + u * span, y: top + sag * (1 - (2 * u - 1) * (2 * u - 1)))
                    g.rotate(by: .pi / 2 + sin(F(n) * 2.3) * 0.8)
                    g.draw(images.leaves[(n * 3) % images.leaves.count], in: CGRect(x: -1 * S, y: -size / 2, width: size, height: size))
                    g.restoreGState()
                    n += 1
                }
                lx0 += span
            }
            let frame = C(52, 40, 30), dim = C(120, 72, 22)
            forEachBulb { _, bx, by in
                g.line(frame, 1.2 * S, bx, by, bx, by + 2.5 * S)
                g.fillRect(frame, bx - 4.5 * S, by + 2 * S, 9 * S, 2.5 * S)
                g.fillRect(dim, bx - 3.5 * S, by + 4.5 * S, 7 * S, 9 * S)
                g.fillRect(frame, bx - 4.5 * S, by + 13.5 * S, 9 * S, 2 * S)
            }
            return
        }
        let w = 7 * S, h = 11 * S
        forEachBulb { idx, bx, by in
            let comps = Self.bulbColors[idx % Self.bulbColors.count].components!
            g.fillRect(socket, bx - 2.5 * S, by, 5 * S, 4 * S)
            g.fillEllipse(CGColor(srgbRed: comps[0] * 0.5, green: comps[1] * 0.5, blue: comps[2] * 0.5, alpha: 1), bx - w / 2, by + 3 * S, w, h)
        }
    }
}
