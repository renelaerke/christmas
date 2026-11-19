// Probe: runs the MediaPipe multiclass selfie segmenter (Core ML) on recorded camera frames and shows what it
// takes for hair, skin and clothes, and how long one frame takes.
//
//   swift tools/parts-probe.swift MODEL.mlmodelc FRAMES_DIR OUT_DIR
//
// Reads FRAMES_DIR/raa-NNN.jpg, writes OUT_DIR/dele-NNN.png: the frame with the classes laid over it
// (hair blue, body skin green, face skin red, clothes yellow, others magenta; background untouched).
import AppKit
import CoreML
import Vision

let args = CommandLine.arguments
guard args.count == 4 else { print("brug: parts-probe MODEL.mlmodelc BILLEDMAPPE UDMAPPE"); exit(1) }
let cfg = MLModelConfiguration()
cfg.computeUnits = .all
let model = try MLModel(contentsOf: URL(fileURLWithPath: args[1]), configuration: cfg)
let constraint = model.modelDescription.inputDescriptionsByName["image"]!.imageConstraint!
let fm = FileManager.default
try fm.createDirectory(atPath: args[3], withIntermediateDirectories: true)
let names = try fm.contentsOfDirectory(atPath: args[2]).filter { $0.hasPrefix("raa-") && $0.hasSuffix(".jpg") }.sorted()
let colours: [(UInt8, UInt8, UInt8)] = [(0, 0, 0), (40, 90, 255), (40, 220, 60), (255, 50, 50), (255, 220, 0), (255, 0, 255)]
let N = 256

func classes(_ cg: CGImage) throws -> MLMultiArray {
    // the whole frame squeezed into the model's square, as MediaPipe does
    let fv = try MLFeatureValue(cgImage: cg, constraint: constraint, options: [.cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue])
    let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": fv]))
    return out.featureValue(for: "classes")!.multiArrayValue!
}

var times: [Double] = []
for name in names {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[2] + "/" + name) as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil), cg.width > 200 else { continue }
    _ = try classes(cg)   // (the first run loads the model)
    let t0 = CFAbsoluteTimeGetCurrent()
    var arr = try classes(cg)
    for _ in 0..<9 { arr = try classes(cg) }
    let ms = (CFAbsoluteTimeGetCurrent() - t0) / 10 * 1000
    times.append(ms)
    let p = arr.dataPointer.bindMemory(to: Float32.self, capacity: 6 * N * N)
    var px = [UInt8](repeating: 0, count: N * N * 4)
    var count = [Int](repeating: 0, count: 6)
    for i in 0..<(N * N) {
        var best = 0
        for c in 1..<6 where p[c * N * N + i] > p[best * N * N + i] { best = c }
        count[best] += 1
        if best > 0 { let c = colours[best]; px[4 * i] = c.0; px[4 * i + 1] = c.1; px[4 * i + 2] = c.2; px[4 * i + 3] = 255 }
    }
    let space = CGColorSpaceCreateDeviceRGB()
    let overlay = px.withUnsafeMutableBytes { raw -> CGImage? in
        CGContext(data: raw.baseAddress, width: N, height: N, bitsPerComponent: 8, bytesPerRow: N * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }
    let w = 960, h = 960 * cg.height / cg.width
    guard let g = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let overlay else { continue }
    let r = CGRect(x: 0, y: 0, width: w, height: h)
    g.draw(cg, in: r)
    g.setAlpha(0.5)
    g.interpolationQuality = .none
    g.draw(overlay, in: r)
    let rep = NSBitmapImageRep(cgImage: g.makeImage()!)
    let out = args[3] + "/dele-" + name.dropFirst(4).dropLast(4) + ".png"
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    let share = count.map { String(format: "%.0f", Double($0) * 100 / Double(N * N)) }
    print("\(name): \(String(format: "%.1f", ms)) ms | baggrund \(share[0]) % hår \(share[1]) kropshud \(share[2]) ansigtshud \(share[3]) tøj \(share[4]) andet \(share[5])")
}
if !times.isEmpty { print(String(format: "gennemsnit %.1f ms pr. billede over %d billeder", times.reduce(0, +) / Double(times.count), times.count)) }
