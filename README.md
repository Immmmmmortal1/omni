# OmniAR

iOS 17+ sample that combines **ARKit** / **RealityKit** world tracking with **Core ML** + **Vision** object detection (Apple’s `YOLOv3TinyInt8LUT`) so you can tap a detected object and attach a simple pink “living” character in 3D space.

Bundle ID: `com.omni.livingobjects` · Product: **OmniAR**

## Architecture

```
Camera frames (ARSession)
        │
        ▼
 ObjectDetector  ── Vision VNCoreMLRequest ──► yolo11s.mlpackage
        │                                         (Ultralytics YOLO11s + NMS)
        ▼
 VNRecognizedObjectObservation → DetectedObject (label, conf, bbox)
        │
        ▼
 LivingObjectSystem  ←── tap (UIKit coords → normalized)
        │  pick smallest containing box
        │  project box center → surface (scene depth / raycast)
        │  lock track + IoU rematch each detect frame
        ▼
 AnchorEntity glued to object + CharacterEntityFactory (billboard face)
        │
        ▼
 ARLivingView (RealityKit ARView) + StatusHUD (SwiftUI overlay)
```

| Piece | Role |
|--------|------|
| `ObjectDetector` | Loads the bundled YOLO Core ML model, runs Vision each few frames, maps COCO-ish labels, excludes `person`. |
| `COCOClasses` | 80-class label list + exclusion helpers. |
| `DetectionMatch` | IoU + same-class rematching so a locked face follows its object. |
| `SurfaceProjector` | Box-center → world hit via scene depth (LiDAR) or plane raycast / feature-point depth. |
| `ARLivingView` | `UIViewRepresentable` hosting `ARView`, world tracking, tap gesture, session delegate. |
| `LivingObjectSystem` | Locks characters onto detections; continuously reprojects + billboards while the object stays in view. |
| `CharacterEntityFactory` | RealityKit meshes (sphere face, plane accent, limbs) + idle sway on an inner body node. |
| `StatusHUD` | “omni” brand, detection/alive counts, instruction line. |

Detection uses the AR frame’s `capturedImage` (`CVPixelBuffer`). Placement pins to the **detection box center** on a real surface (scene depth when available), then tracks that object until it leaves frame.

## Requirements

- macOS with **Xcode 15+** (project generated against Xcode 16)
- **XcodeGen** (`brew install xcodegen`)
- Physical **iPhone/iPad** with A12+ recommended for ARKit + Core ML (Simulator builds compile, but AR camera/world tracking need a device)

## Open & run

```bash
xcodegen generate   # only needed after editing project.yml
open OmniAR.xcodeproj
```

1. Select the **OmniAR** scheme and your connected device (AR features are limited in Simulator).
2. Set your **Signing Team** in the OmniAR target if needed.
3. Build & Run. Grant camera permission when prompted.
4. Aim at COCO-style objects (cup, chair, bottle, …), wait for the HUD detection count to rise, then **tap** the object to spawn a character.

### Regenerate after editing `project.yml`

```bash
xcodegen generate
```

### CLI build (Simulator, no signing)

```bash
xcodebuild -scheme OmniAR \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  -quiet build
```

## Model

`OmniAR/Models/yolo11s.mlpackage` is **Ultralytics YOLO11s** (COCO, Core ML with embedded NMS) from the official [yolo-ios-app v8.3.0 release](https://github.com/ultralytics/yolo-ios-app/releases/tag/v8.3.0). Xcode compiles it to `.mlmodelc`. `ObjectDetector` loads that bundle with the correct AR frame **Vision orientation** (portrait back camera → `.right`).

Detection scores the full camera frame while hunting. After a successful pin, YOLO **stops** and the face stays on a **world-fixed** `AnchorEntity`. Re-download:

```bash
bash scripts/download-yolo11n.sh yolo11s
```

## Privacy keys

- `NSCameraUsageDescription` — AR + detection  
- `NSMicrophoneUsageDescription` — reserved for future voice interaction  

Defined via `project.yml` / generated `Info.plist`.

## Build notes (CI / this machine)

If `-destination 'generic/platform=iOS Simulator'` fails with “iOS … is not installed” / no destinations (missing Simulator runtime), compile against the SDK directly:

```bash
xcodebuild -project OmniAR.xcodeproj -target OmniAR \
  -sdk iphonesimulator -arch arm64 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" ONLY_ACTIVE_ARCH=YES \
  build
```

`COREML_COMPILER_CONTAINER` must be `bundle-resources` (not `Swift`) on Xcode 16’s `coremlc`.
