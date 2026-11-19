# Modelfiler

## selfie_multiclass_256x256.mlpackage

Deler en person i kamerabilledet op i baggrund (0), hår (1), kropshud (2), ansigtshud (3), tøj (4) og andet (5,
fx briller). Bruges af kamerakostumet (`macos/Sources/JuleHygge/Parts.swift`) til at finde tøjet, som farves
(nissedragt, regnfrakke).

- **Model:** Google MediaPipe "Multiclass Selfie Segmentation", `selfie_multiclass_256x256.tflite` (float32).
  Licens: Apache 2.0 ifølge Googles modelkort.
  <https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter>
- **Core ML-udgaven** er omsat af en tredjepart og hentet 2026-11-19 fra udgivelsen
  `mediapipe-selfie-multiclass-256x256-coreml-1` i `kpgalligan/rasterize-models` på GitHub:
  <https://github.com/kpgalligan/rasterize-models/releases/tag/mediapipe-selfie-multiclass-256x256-coreml-1>
  Udgivelsen oplyser værktøjerne (TensorFlow 2.15.1, tf2onnx 1.16.1, onnx2torch 1.5.15, PyTorch 2.5.1,
  coremltools 8.3.0) og at resultatet stemmer med Googles original (samme klasse i mindst 99 % af punkterne).
  Vi har ikke selv omsat modellen fra originalen.
- **Kontrolsummer (SHA-256)**, som oplyst i udgivelsen og kontrolleret efter hentning:
  - `Manifest.json`: `04735bcd9171e169a68f08879bdb00962d5e27890b44bf6243eee4b4b78a5f05`
  - `Data/com.apple.CoreML/model.mlmodel`: `8c636fc6029188ff19bb313f6918fda0d6ecf642668d925a7cefa2125337ea86`
  - `Data/com.apple.CoreML/weights/weight.bin`: `19be63ebfc121cc84cfdbf9451a791ae473fc1c238d1d6696b07f17f8ab7cd3e`
- **Licensteksten** (Apache 2.0, hentet fra apache.org) ligger i `macos/licenses/Apache-2.0.txt`. Den kopieres ind i
  macOS-appen og vises fra menuen ("Licens for tøjmodellen i kameraet…"). Modellen bruges kun af macOS-udgaven.
- **Krav:** macOS 15 eller nyere. På ældre systemer bruger appen den gamle farveregel.
- `build.sh` og Xcode-projektet kompilerer pakken til `selfie_multiclass_256x256.mlmodelc` i appens Resources.
- Prøv modellen alene: `swift macos/tools/parts-probe.swift MODEL.mlmodelc BILLEDMAPPE UDMAPPE`.
