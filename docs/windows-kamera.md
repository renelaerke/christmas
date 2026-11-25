# JuleHygge Kamera on Windows: research (2026-11-25)

> **Status:** research only, nothing built. Written on a Mac from the macOS code, Microsoft's documentation and
> public projects. Nothing here has been run on Windows. Each claim says where it comes from; the section
> "Not verified" lists what must be tried on a real Windows 11 PC before any of it is relied on.

## Short answer

It can be ported, on **Windows 11 only**, and in three parts of very different risk:

1. **The virtual camera** needs one small native DLL (a Media Foundation media source) that Windows loads into its
   camera service, registered once with administrator rights. It cannot be written in the app's C# 5. It only
   passes pictures on, like the macOS extension does.
2. **The measurements** (person cutout, face, clothes) have a good replacement: Google's MediaPipe models, run as
   ONNX. The clothes model is the one macOS already uses. The face model gives 478 points in three dimensions,
   which is more than Apple's Vision gives.
3. **The costume logic** (`Hat.swift`, `Costume.swift`, `Makeup.swift`, about 2,700 lines) is geometry and
   drawing and ports line for line, as the themes did. What has to be rewritten by hand is the part that uses
   Apple's Core Image (about 100 call sites, 11 different filters).

The largest open question is not technical feasibility but one compatibility report: a public sample of this kind
of camera shows in Teams' own preview but is said not to reach the other side of the call. That can be settled in
ten minutes on a Windows 11 PC, before anything is written (see "First experiment").

## What the macOS version does (what has to be matched)

From `VirtualCamera.swift`, `Hat.swift`, `Costume.swift`, `Parts.swift`, `Makeup.swift` and `CameraExtension/`:

| Step | macOS | Framework |
|---|---|---|
| Read the real camera | `AVCaptureSession`, only while some app reads JuleHygge Kamera | AVFoundation |
| Cut the person out | `VNGeneratePersonSegmentationRequest`, balanced quality, a 512×384 mask for every frame | Vision |
| Find faces and head angles | `VNDetectFaceRectanglesRequest` revision 3: roll, yaw, pitch | Vision |
| Face points | `VNDetectFaceLandmarksRequest`: eyes, eyebrows, face contour, nose crest, nose, outer lips | Vision |
| Clothes, skin, hair | MediaPipe "Multiclass Selfie Segmentation" 256×256, every second frame | Core ML |
| The scene behind and in front | the overlay's own drawing on a virtual 1280×720 screen | AppKit, Core Animation |
| Hat, beard, suit, make-up, witch, pumpkin | geometry on the measured head, drawn and blended | AppKit, Core Image |
| Hand the picture to other apps | a camera extension with a sink stream in and a source stream out, 1280×720 at 30 fps; it also tells the app when someone reads the camera | CoreMediaIO |

The app does the work and the extension only forwards. The same split fits Windows.

## 1. The virtual camera

### The options

| Route | Windows | Needs | Verdict |
|---|---|---|---|
| **Media Foundation virtual camera** (`MFCreateVirtualCamera`) | 11 (build 22000) and later | a COM DLL registered machine-wide (administrator, once) | **Recommended.** No kernel driver. The modern route. |
| DirectShow source filter (how OBS's virtual camera and the MIT library *softcam* work) | 10 and 11 | a 64-bit and a 32-bit DLL, registered with administrator rights | Fallback if Teams does not take the route above. Apps that only use Media Foundation (Windows' Camera app) do not see it. |
| Kernel camera driver (AVStream) | all | driver signing through Microsoft | Out of reach for this project. |
| A Teams video filter app (TeamsJS `videoEffects`) | any | a Teams app installed in the tenant, written in JavaScript | Not a port: Teams only, another language, and Microsoft marks the API as beta, not for production. |

Windows 10 left support in October 2025 and the paid extension for private users ended in October 2026, so a
Windows 11-only feature is defensible. On Windows 10 the menu item would simply be absent.

### How the recommended route works

From Microsoft's reference for `MFCreateVirtualCamera` and three public projects (two MIT samples by smourier,
and `VL.Video.VirtualCamera`, MIT, which is the closest match to what JuleHygge needs):

- The app calls `MFCreateVirtualCamera(type, lifetime, access, friendlyName, sourceId, ...)`, where `sourceId` is
  the CLSID of the media source DLL, then `Start()`. With lifetime *Session* the camera disappears when the app
  exits; with *System* it stays. Windows appends "Windows Virtual Camera" to the name.
- The DLL is loaded by Windows' **Frame Server** service (and by the camera monitor service and the reading
  apps). Frame Server runs as Local Service in session 0, so:
  - the DLL must be registered under **HKLM** (`Software\Classes\CLSID\{...}\InprocServer32`). Both samples state
    that HKCU does not work;
  - the DLL file must lie where that service can read it: Program Files or ProgramData, not the user's folder.
    This is the cause of the samples' most reported error ("Access denied" on `Start`).
- Frames get from the app to the DLL through **shared memory**. `VL.Video.VirtualCamera` documents a working
  design: the DLL creates a `Global\` memory section inside the service (where that needs no privilege) with an
  access list that lets the user's app write it; a ring of frame slots with a sequence counter per slot, so no
  locks cross processes; a heartbeat, so the DLL shows a fallback picture when the app is gone. Its DLL delivers
  frames on its own steady clock.
- The DLL offers NV12 as well as RGB32, because most readers ask for NV12.
- Frame Server keeps the DLL loaded while the camera exists, so a new version needs a new file name (or a restart
  of the service).

Mapped to JuleHygge:

| macOS | Windows |
|---|---|
| `CameraExtension/Provider.swift` (266 lines) | a media source DLL, C++ on the pattern of the MIT samples |
| the sink stream | the shared memory ring |
| the property `jhsr` ("someone is reading") | a flag or event the DLL sets when streaming starts and stops |
| the calm snowflake when no frames come | the DLL's fallback picture |
| "Installér JuleHygge Kamera" and the approval in System Settings | a menu item that restarts the app elevated once, copies the DLL to Program Files and writes the HKLM key |
| `CMIOSink` in the app | `MFCreateVirtualCamera` and the ring writer in `JuleHygge.exe` |

### What this costs the project

- **A second toolchain.** The DLL cannot be C# 5 on .NET Framework in any sensible way (it would load the .NET
  runtime into Windows' camera service and every reading app). It is C++ (or Rust, or C# with NativeAOT, as
  `VL.Video.VirtualCamera` does). The development PC has no SDK, so it would be **built only in CI**, as the Linux
  version is. GitHub's Windows runner has the compiler.
- **Shipping.** To keep one exe and the self-update, the CI-built DLL can be built into `JuleHygge.exe` as a
  resource (as the language files and the goose recording are) and written out when the camera is installed. A
  locally built exe would then have no camera, as a locally built macOS app without Xcode has none.
- **Administrator rights once.** Today the app needs none.
- **The Microsoft Store version** (branch `microsoft-store`) most likely cannot carry the camera: a package
  cannot write HKLM, and Microsoft's own sample installs the media source with a separate MSI beside the packaged
  app. This is inferred from the sample's structure, not from a statement in the documentation.
- **Signing.** None of the samples sign their DLL, and plain Windows 11 loads it. One developer's notes say Smart
  App Control (on by default on some clean installs) blocks unsigned DLLs; Microsoft's support page says the same
  in general terms. The exe is unsigned today, so those PCs are already a problem.
- **ARM64** PCs need an ARM64 build of the DLL too.

## 2. The measurements

Windows has nothing built in that matches Vision. `Windows.Media.FaceAnalysis` gives face boxes only, without
points or angles. Windows Studio Effects blurs backgrounds on PCs with an NPU but gives apps no mask. So the
models must come with the app.

### The models

| Need | Model | Notes |
|---|---|---|
| Clothes, skin, hair | MediaPipe Multiclass Selfie Segmentation 256×256 | The same model as on macOS (16 MB there). An ONNX conversion under Apache 2.0 exists; the Core ML file macOS uses was itself made by way of ONNX. |
| Person cutout | the same model: class 0 is background, so person = everything else | One model run then gives both the cutout and the clothes. But it is 256×256, coarser than Vision's 512×384, and the hat is built on the head's outline in this mask. See risks. |
| Finding faces | MediaPipe BlazeFace short-range, 128×128 | Its output is 896 candidate boxes that must be decoded and merged in our code. |
| Face points and head angles | MediaPipe Face Mesh V2, 256×256 on the cropped face | 478 points with x, y and z. Angles are not an output; they are computed from the points. |

All four are Apache 2.0 (code and weights), the licence the project already ships for the clothes model. Existing
ONNX conversions of the two face models are published with a conversion script and a comparison against Google's
original. We should convert from Google's files ourselves, or at least check the sums, as `assets/model/KILDER.md`
does for the Core ML file. Some MediaPipe files have failed in the usual converter (tf2onnx) on one operator, so
the conversion is a task with its own check, not a formality.

### Mapping to what the code expects

`Hat.face(...)` reduces Vision's result to: eye centre, brow, chin, roll, yaw, pitch, and for the witch's nose the
top and tip of the crest, the point under the nose and the nose's breadth. Costume and make-up also use the eyes,
eyebrows, face contour, nose and outer lips. Every one of these is a fixed set of points in the 478-point mesh.

Two things get easier:

- **The witch's nose.** On macOS the nose tip had to be rebuilt in three dimensions from flat points, with a ratio
  learned per person (`AGENTS.md`, "Halloween"). The mesh has depth for every point, so the nose's own protrusion
  can be read instead of learned.
- **The angles.** They can be computed from the mesh as a rotation and written in Vision's order
  (R = Rz(roll)·Rx(pitch)·Ry(yaw)), so the hat's code stays as it is.

One thing gets harder: Vision does detection, tracking and smoothing for us. With MediaPipe's models as bare ONNX
files the app must itself crop the face (rotated, 1.5 times the box), run the mesh, map the points back, and
follow each face from frame to frame. That is a few hundred lines that exist nowhere in the macOS code.

### Running the models from the app

| Way | Fits "no NuGet, C# 5, the compiler in Windows" | Notes |
|---|---|---|
| **Windows' built-in machine learning** (`Windows.AI.MachineLearning`, in Windows since 2018) | Yes, if the compiler accepts the metadata files that ship in `System32\WinMetadata` | Nothing to ship. Uses the GPU through DirectML. Windows 11's version reads ONNX up to opset 12, so the models must be converted to that. Microsoft calls the API superseded by a newer one in the Windows App SDK, but it is still in Windows. |
| **ONNX Runtime's own DLL**, called through its C interface | Yes (P/Invoke; about 25 functions to declare) | MIT. One more native DLL to carry, in the tens of MB with its GPU part. Any opset. |
| The new Windows ML (Windows App SDK) | No: NuGet packages and a runtime to install | Not for this project as it is built today. |

The same question applies to reading the real camera: the simple API is `Windows.Media.Capture` (WinRT), the
other is Media Foundation's source reader through hand-written COM declarations. Both the built-in machine
learning and the camera API are WinRT, so **one small test decides both**: can the Windows compiler build a C# 5
file that references the `.winmd` files in `System32\WinMetadata` and `System.Runtime.WindowsRuntime.dll`. I
found no source that confirms or denies it. If it works, capture and inference need no extra files at all. Note
that mono on the Mac will not compile such a file, so the camera's Windows-only part would fall outside today's
compile check and should sit in its own files behind a thin interface.

## 3. The costume code

| File | Lines | Core Image call sites | What porting it means |
|---|---|---|---|
| `Hat.swift` | 1416 | 6 | Almost all geometry and filtering of measurements. Ports like the themes. |
| `Costume.swift` | 1050 | 65 | The suit, beard, witch's skin and clothes are colour operations on the picture. |
| `Makeup.swift` | 271 | 14 | Drawn shapes blended onto skin. |
| `Parts.swift` | 142 | 7 | Becomes the ONNX call for the clothes model. |
| `VirtualCamera.swift` | 443 | 15 | The frame loop; rewritten around the Windows capture and the ring. |

The Core Image filters in use are few: colour matrix, blend with mask, multiply, clamp, invert, colour controls,
minimum, addition, one radial gradient, one colour cube and one area average. On Windows these become loops over
a 1280×720 pixel buffer in unsafe C#, the way `BlendDot` and `BlendLeaf` already draw. The shapes (hat, beard,
pumpkin) are drawn with GDI+ into a bitmap, as the theme figures are. The scene behind the person is the existing
`Layer` drawing into a 1280×720 buffer without a window, as `ScreenOverlay(virtualFor:)` does on macOS.

Speed is unknown. macOS measures about 32 ms per frame for the cutout alone and about 50 % of a core in total,
with the GPU doing the blending. On Windows the blending would be on the CPU unless more is built. It should be
measured on the first working frame, and rows can be split across cores.

## Risks, in the order they should be removed

1. **Teams.** smourier's C++ sample says in its README that Teams shows the camera in its own preview but does
   not send it to the other party, cause unknown. The same author's .NET sample shows a Teams screenshot, and
   other projects list Teams as working; none of those is a documented test of the far end. If Teams fails, the
   fallback is a DirectShow filter on the pattern of softcam (MIT), which is how OBS's camera reaches Teams.
2. **The cutout's quality.** The hat stands on the head's outline in the mask. A 256×256 mask is coarser than
   Vision's, and may need its edge sharpened against the camera picture.
3. **The Windows compiler and WinRT** (above). Decides how much extra has to be shipped.
4. **Model conversion** to opset 12, if the built-in machine learning is used.
5. **Nobody on this side can see it run.** The Mac can only compile the C#. The DLL and the camera need a
   Windows 11 PC; GitHub's runners are Windows Server, where the camera service may not exist, so CI can build
   the DLL and can run the costume code on still pictures, but probably not the camera itself.

## Suggested order of work

**First experiment (on a Windows 11 PC, about ten minutes, no code):** download the two prebuilt files from the
releases of `smourier/VCamNetSample`, register the DLL as administrator from a folder outside the user profile,
start the app, choose the camera in Teams and make a call to a second account or device. Does the other side see
the picture? Try the Camera app and a browser too. This decides Media Foundation or DirectShow.

**Second experiment (on Windows, an hour):** a 30-line C# 5 file compiled with the Windows compiler that
references the `.winmd` files and loads a small ONNX model with `Windows.AI.MachineLearning`. This decides how
models are run and how the camera is read.

**On the Mac, before any Windows code:** make macOS the test bench for the new inputs. The project already has 56
raw camera frames (`build-test/`, outside git) and `--kamera-replay`.
- Feed the hat the person mask from the multiclass model (already in the app) instead of Vision's, and look at
  the same frames. That answers risk 2 without Windows.
- Run BlazeFace and Face Mesh on the frames (as Core ML or with ONNX Runtime in Python), map the mesh to `Face`,
  and replay. That fixes the point numbers and the angle conversion where the result can be seen.

Then, in this order: the DLL and the shared memory with a test pattern; reading the real camera; the models; the
cutout over the scene (already a usable Teams background); hat; suit and beard; the themes' costumes.

## Not verified

- That Teams sends a Media Foundation virtual camera to the other party (risk 1).
- That `MFCreateVirtualCamera` works without elevation for a per-user, session-lifetime camera. Microsoft's
  reference says administrator rights are needed for all-users access; one project says elevation is always
  needed.
- That the Windows compiler can reference `System32\WinMetadata\*.winmd`.
- That the three models convert to opset 12 and run in Windows' built-in machine learning, and how fast.
- That a 256×256 cutout is good enough for the hat.
- CPU use of the blending on Windows.
- Smart App Control's treatment of an unsigned DLL loaded by the camera service.
- Whether the camera service exists on GitHub's Windows runners.
- Sizes of ONNX Runtime's DLLs today (the download page could not be read from here).

## Sources

Microsoft:
- [MFCreateVirtualCamera](https://learn.microsoft.com/en-us/windows/win32/api/mfvirtualcamera/nf-mfvirtualcamera-mfcreatevirtualcamera) and [IMFVirtualCamera](https://learn.microsoft.com/en-us/windows/win32/api/mfvirtualcamera/nn-mfvirtualcamera-imfvirtualcamera)
- [Frame Server custom media source](https://learn.microsoft.com/en-us/windows-hardware/drivers/stream/frame-server-custom-media-source)
- [Virtual camera sample](https://github.com/microsoft/Windows-Camera/tree/master/Samples/VirtualCamera) (MIT; installs the media source with an MSI)
- [ONNX versions and Windows builds](https://learn.microsoft.com/en-us/windows/ai/windows-ml/onnx-versions) and [Windows.AI.MachineLearning](https://learn.microsoft.com/en-us/windows/ai/windows-ml/api-reference)
- [What is Windows ML](https://learn.microsoft.com/en-us/windows/ai/new-windows-ml/overview) (the newer one, in the Windows App SDK)
- [Call Windows Runtime APIs in desktop apps](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/winrt-apis-desktop-apps)
- [TeamsJS videoEffects](https://learn.microsoft.com/en-us/javascript/api/@microsoft/teams-js/videoeffects) (beta)
- [Smart App Control has blocked part of this app](https://support.microsoft.com/en-US/Windows/Security/Threat-Malware-Protection/smart-app-control-has-blocked-part-of-this-app)

Projects:
- [smourier/VCamSample](https://github.com/smourier/VCamSample) (C++, MIT; the Teams note and the HKLM and folder rules)
- [smourier/VCamNetSample](https://github.com/smourier/VCamNetSample) (.NET and NativeAOT, MIT; prebuilt files for the first experiment)
- [bj-rn/VL.Video.VirtualCamera](https://github.com/bj-rn/VL.Video.VirtualCamera) (MIT; the shared memory design)
- [tshino/softcam](https://github.com/tshino/softcam) (MIT; DirectShow, the fallback)
- [matumi-software/skakel issue 19](https://github.com/matumi-software/skakel/issues/19) (a developer's plan for the same thing; the Smart App Control and Chrome notes)
- [OneLimeStudio/BestCam](https://github.com/OneLimeStudio/BestCam) (GPL 2.0: read for its claims only, take no code)

Models:
- [MediaPipe Face Landmarker](https://ai.google.dev/mediapipe/solutions/vision/face_landmarker) and [Image Segmenter](https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter)
- [Face Mesh V2 as ONNX](https://huggingface.co/fernandotonon/QtMeshEditor-facemesh-onnx) and [BlazeFace as ONNX](https://huggingface.co/fernandotonon/QtMeshEditor-blazeface-onnx) (Apache 2.0, with conversion script)
- [tf2onnx](https://github.com/onnx/tensorflow-onnx)
- [OBS forum: new Teams and the virtual camera](https://obsproject.com/forum/threads/new-teams-cant-capture-the-virtual-camera.171102/) (user reports, 2023 to 2024)
