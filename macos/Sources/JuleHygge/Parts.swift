import CoreImage
import CoreML
import CoreVideo
import Foundation

/// Tells a person's clothes from skin and hair in the camera picture, with a trained model: MediaPipe's
/// multiclass selfie segmenter (Apache 2.0, see assets/model/KILDER.md). For every point it gives how likely it
/// is background, hair, body skin, face skin, clothes or something else (glasses).
///
/// The suit used to find the clothes by colour and contrast. That cannot be made sure: skin in shade and cloth
/// in warm light have the same colours, and a jacket in several colours has edges everywhere (live 2026-11-18
/// and 19: holes and flicker on a grey sweater, shoulders and hood of a blue jacket left uncoloured, and the
/// neck and the hair coloured when the rule was loosened). The model knows the parts by what they are.
///
/// The model needs macOS 15. Before that, and until it has loaded, `clothes` gives nil and the suit falls back
/// on the colour rule.
final class PersonParts {
    /// Tests set this: load the model at once instead of in the background, so the first picture has it.
    nonisolated(unsafe) static var loadNow = false
    /// How long the last picture took (ms), for the tests.
    private(set) var lastMs: Double = 0

    private let lock = NSLock()
    private var model: MLModel?
    private var asked = false
    private var buffer: CVPixelBuffer?
    private var history: [Float]?
    private var tick = 0
    private var last: CIImage?, lastFace: CIImage?
    private static let side = 256, clothesClass = 4, faceClass = 3, classCount = 6

    /// The face's skin in `cam` (white = face skin), from the same run of the model as `clothes`; nil without the
    /// model. The Day of the Dead's make-up is painted only there, so it stays off hair, beard and neck.
    func faceSkin(cam: CIImage) -> CIImage? {
        _ = clothes(cam: cam)
        guard let lastFace, lastFace.extent == cam.extent else { return nil }
        return lastFace
    }

    private func loaded() -> MLModel? {
        lock.lock(); defer { lock.unlock() }
        if let model { return model }
        guard !asked else { return nil }
        asked = true
        // HUE_INGEN_MODEL=1 leaves the model out (the colour rule instead): for measuring what it costs
        guard ProcessInfo.processInfo.environment["HUE_INGEN_MODEL"] == nil else { return nil }
        guard #available(macOS 15, *), let url = Bundle.main.url(forResource: "selfie_multiclass_256x256", withExtension: "mlmodelc") else { return nil }
        let load: @Sendable () -> MLModel? = {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all
            return try? MLModel(contentsOf: url, configuration: cfg)
        }
        if Self.loadNow { model = load(); return model }
        // (loading takes a moment the first time: the camera picture must not wait for it)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let m = load()
            guard let self else { return }
            self.lock.lock(); self.model = m; self.lock.unlock()
        }
        return nil
    }

    /// The clothes in `cam` as a mask in its coordinates (white = clothes), or nil without the model.
    func clothes(cam: CIImage) -> CIImage? {
        guard let model = loaded() else { return nil }
        let extent = cam.extent, n = Self.side
        guard extent.width > 32, extent.height > 32 else { return nil }
        if buffer == nil {
            CVPixelBufferCreate(nil, n, n, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        }
        guard let buffer else { return nil }
        // The model takes about 20 ms a picture (measured 2026-11-19), most of a frame at 30 a second. Clothes
        // move little in a thirtieth of a second, so live it runs for every other picture and the mask is kept
        // for the one between. (The tests' pictures are seconds apart: there it runs for each.)
        tick += 1
        if !Self.loadNow, tick % 2 == 0, let last, last.extent == extent { return last }
        let t0 = CFAbsoluteTimeGetCurrent()
        // the whole picture squeezed into the model's square (as MediaPipe does), and stretched back afterwards
        let shrink = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
            .concatenating(CGAffineTransform(scaleX: CGFloat(n) / extent.width, y: CGFloat(n) / extent.height))
        GPU.ciContext.render(cam.transformed(by: shrink), to: buffer, bounds: CGRect(x: 0, y: 0, width: n, height: n), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        guard let input = try? MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: buffer)]),
              let out = try? model.prediction(from: input),
              let arr = out.featureValue(for: "classes")?.multiArrayValue,
              arr.dataType == .float32, arr.count == Self.classCount * n * n else { return nil }
        var v = [Float](repeating: 0, count: n * n), face = v
        arr.withUnsafeBufferPointer(ofType: Float32.self) { p in
            let fb = Self.faceClass * n * n
            for i in 0..<(n * n) { face[i] = max(0, min(1, (p[fb + i] - 0.4) * 4 + 0.5)) }
            let base = Self.clothesClass * n * n
            // Steep round one half: where the model is only fairly sure (a sleeve seen from an odd angle, 0.6–0.8)
            // the costume must still cover, or the clothes' own colour shines through it.
            for i in 0..<(n * n) { v[i] = max(0, min(1, (p[base + i] - 0.5) * 5 + 0.5)) }
            // The model's picture is coarser than the person's cut-out, so toward the background the clothes
            // faded out before the cut-out's edge and left a rim of their own colour (live 2026-11-19). The
            // clothes are carried a few cells on into what the model takes for background (outside the cut-out
            // it is cut away anyway), never into skin, hair or glasses.
            var open = [Bool](repeating: false, count: n * n)
            for i in 0..<(n * n) { open[i] = p[i] > 0.3 && p[n * n + i] + p[2 * n * n + i] + p[3 * n * n + i] + p[5 * n * n + i] < 0.2 }
            for _ in 0..<4 {
                let before = v
                for y in 1..<(n - 1) { for x in 1..<(n - 1) {
                    let i = y * n + x
                    guard open[i], before[i] < 1 else { continue }
                    v[i] = max(before[i], before[i - 1], before[i + 1], max(before[i - n], before[i + n]))
                } }
            }
        }
        // Averaged with the last picture where the two nearly agree, so the edge does not shimmer. Where they do
        // not, something has moved, and the new picture is right: a plain average left an arm that had just moved
        // half coloured, and a hand where the sleeve had just been half yellow.
        if let old = history, old.count == v.count { for i in 0..<v.count where abs(old[i] - v[i]) < 0.5 { v[i] = (old[i] + v[i]) * 0.5 } }
        history = v
        let bytes = Data(v.map { UInt8($0 * 255) })
        lastMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        let image = CIImage(bitmapData: bytes, bytesPerRow: n, size: CGSize(width: n, height: n), format: .L8, colorSpace: nil)
            .applyingGaussianBlur(sigma: 0.6)
            .transformed(by: shrink.inverted())
            .cropped(to: extent)
        last = image
        lastFace = CIImage(bitmapData: Data(face.map { UInt8($0 * 255) }), bytesPerRow: n, size: CGSize(width: n, height: n), format: .L8, colorSpace: nil)
            .applyingGaussianBlur(sigma: 0.8)
            .transformed(by: shrink.inverted())
            .cropped(to: extent)
        return image
    }
}
