import Foundation
import Vision
import CoreML
import CoreVideo
import UIKit
import ARKit

struct DetectedObject: Identifiable, Equatable {
    let id: UUID
    let label: String
    let confidence: Float
    /// Normalized bounding box in Vision coordinates (origin bottom-left, [0,1]).
    let boundingBox: CGRect

    init(label: String, confidence: Float, boundingBox: CGRect, id: UUID = UUID()) {
        self.id = id
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
    }

    var uiKitNormalizedBox: CGRect {
        CGRect(
            x: boundingBox.origin.x,
            y: 1.0 - boundingBox.origin.y - boundingBox.height,
            width: boundingBox.width,
            height: boundingBox.height
        )
    }

    /// Vision boxes are normalized in the *oriented* image space (we feed Vision the interface
    /// orientation). Map that straight to normalized view coords with ARView's aspect-fill (cover,
    /// centered). This is the SINGLE source of truth — do NOT also apply `displayTransform`, which
    /// expects native sensor coords and caused cup boxes to be misplaced (pinned to the table).
    func viewNormalizedBox(
        imagePixelSize: CGSize,
        orientation: UIInterfaceOrientation,
        viewSize: CGSize
    ) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else { return uiKitNormalizedBox }

        // Oriented (upright) image size: portrait swaps the native landscape sensor dims.
        let orientedW: CGFloat
        let orientedH: CGFloat
        switch orientation {
        case .portrait, .portraitUpsideDown:
            orientedW = imagePixelSize.height
            orientedH = imagePixelSize.width
        default:
            orientedW = imagePixelSize.width
            orientedH = imagePixelSize.height
        }
        guard orientedW > 0, orientedH > 0 else { return uiKitNormalizedBox }

        // Vision box → top-left-origin normalized in oriented space.
        let ox = boundingBox.origin.x
        let oyTop = 1.0 - boundingBox.origin.y - boundingBox.height
        let ow = boundingBox.width
        let oh = boundingBox.height

        // Aspect-fill: scale so the oriented image covers the view, centered (matches ARView).
        let scale = max(viewSize.width / orientedW, viewSize.height / orientedH)
        let dispW = orientedW * scale
        let dispH = orientedH * scale
        let offX = (viewSize.width - dispW) / 2
        let offY = (viewSize.height - dispH) / 2

        let vx = ox * dispW + offX
        let vy = oyTop * dispH + offY
        let vw = ow * dispW
        let vh = oh * dispH

        return CGRect(
            x: vx / viewSize.width,
            y: vy / viewSize.height,
            width: vw / viewSize.width,
            height: vh / viewSize.height
        )
    }

    var area: CGFloat {
        boundingBox.width * boundingBox.height
    }
}

/// Ultralytics YOLO11s (COCO + NMS) via Vision on AR camera frames.
final class ObjectDetector {
    static let modelResourceName = "yolo11s"

    private let visionModel: VNCoreMLModel
    private let confidenceThreshold: Float
    private let excludePerson: Bool

    init(confidenceThreshold: Float = 0.20, excludePerson: Bool = true) throws {
        self.confidenceThreshold = confidenceThreshold
        self.excludePerson = excludePerson

        let config = MLModelConfiguration()
        config.computeUnits = .all

        let mlModel = try Self.loadModel(configuration: config)
        visionModel = try VNCoreMLModel(for: mlModel)
    }

    private static func loadModel(configuration: MLModelConfiguration) throws -> MLModel {
        if let url = Bundle.main.url(forResource: modelResourceName, withExtension: "mlmodelc") {
            return try MLModel(contentsOf: url, configuration: configuration)
        }
        if let url = Bundle.main.url(forResource: modelResourceName, withExtension: "mlpackage") {
            return try MLModel(contentsOf: url, configuration: configuration)
        }
        if let url = Bundle.main.url(forResource: modelResourceName, withExtension: nil) {
            return try MLModel(contentsOf: url, configuration: configuration)
        }
        throw DetectorError.modelMissing
    }

    /// Detect objects in an AR frame. Orientation must match how the buffer is fed to Vision.
    func detect(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) throws -> [DetectedObject] {
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFit

        // Guardrail: ARKit capturedImage is sensor-oriented; without this, portrait cups vanish.
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )
        try handler.perform([request])

        guard let results = request.results else { return [] }

        var detections: [DetectedObject] = []
        var rawRecognized = 0

        for observation in results {
            guard let obj = observation as? VNRecognizedObjectObservation else { continue }
            rawRecognized += 1
            guard let top = obj.labels.first, top.confidence >= confidenceThreshold else { continue }
            let label = COCOClasses.label(forIdentifier: top.identifier)
            if excludePerson && COCOClasses.isExcluded(label) { continue }
            detections.append(
                DetectedObject(
                    label: label,
                    confidence: top.confidence,
                    boundingBox: obj.boundingBox
                )
            )
        }

        #if DEBUG
        if rawRecognized > 0 || !detections.isEmpty {
            let summary = detections.prefix(5).map {
                String(format: "%@:%.2f", $0.label, $0.confidence)
            }.joined(separator: ",")
            print("[OmniAR][det] orient=\(orientation.rawValue) raw=\(rawRecognized) kept=\(detections.count) [\(summary)]")
        }
        #endif

        return detections.sorted { $0.confidence > $1.confidence }
    }

    /// Map interface orientation → Vision orientation for the *back* camera buffer.
    static func visionOrientation(for interfaceOrientation: UIInterfaceOrientation) -> CGImagePropertyOrientation {
        switch interfaceOrientation {
        case .landscapeLeft:
            return .up
        case .landscapeRight:
            return .down
        case .portraitUpsideDown:
            return .left
        case .portrait, .unknown:
            fallthrough
        @unknown default:
            return .right
        }
    }

    /// Rank candidates under the finger only.
    /// Nested case (cup on dining table): prefer the **smallest** containing box — completeness
    /// ranking wrongly picks the full-frame table (see runtime: pin label=dining table bbox=1.00).
    /// Tap outside every box → nil (do not invent a global best).
    static func pickTapped(
        detections: [DetectedObject],
        normalizedTap: CGPoint,
        imagePixelSize: CGSize,
        orientation: UIInterfaceOrientation,
        viewSize: CGSize,
        depthMeters: (DetectedObject) -> Float?
    ) -> DetectedObject? {
        guard !detections.isEmpty else { return nil }

        let containing = detections.filter { det in
            det.viewNormalizedBox(
                imagePixelSize: imagePixelSize,
                orientation: orientation,
                viewSize: viewSize
            ).contains(normalizedTap)
        }
        // Guardrail: empty tap must not fall back to whole-frame ranking.
        guard !containing.isEmpty else { return nil }

        // Drop support surfaces when a tighter object also contains the tap.
        let foreground = containing.filter { !COCOClasses.isSupportSurface($0.label) }
        let pool = foreground.isEmpty ? containing : foreground
        return mostSpecific(
            in: pool,
            imagePixelSize: imagePixelSize,
            orientation: orientation,
            viewSize: viewSize,
            depthMeters: depthMeters
        )
    }

    /// Completeness ∈ [0,1]: fraction of the view-normalized box that stays inside the screen.
    static func completeness(
        of det: DetectedObject,
        imagePixelSize: CGSize,
        orientation: UIInterfaceOrientation,
        viewSize: CGSize
    ) -> CGFloat {
        let box = det.viewNormalizedBox(
            imagePixelSize: imagePixelSize,
            orientation: orientation,
            viewSize: viewSize
        )
        let screen = CGRect(x: 0, y: 0, width: 1, height: 1)
        let visible = box.intersection(screen)
        guard !visible.isNull, !visible.isEmpty else { return 0 }
        let area = max(box.width * box.height, 1e-6)
        return min(1, (visible.width * visible.height) / area)
    }

    private static func viewArea(
        of det: DetectedObject,
        imagePixelSize: CGSize,
        orientation: UIInterfaceOrientation,
        viewSize: CGSize
    ) -> CGFloat {
        let box = det.viewNormalizedBox(
            imagePixelSize: imagePixelSize,
            orientation: orientation,
            viewSize: viewSize
        )
        return max(box.width * box.height, 1e-6)
    }

    /// Smallest view-area under the finger = most specific object (cup beats table).
    private static func mostSpecific(
        in pool: [DetectedObject],
        imagePixelSize: CGSize,
        orientation: UIInterfaceOrientation,
        viewSize: CGSize,
        depthMeters: (DetectedObject) -> Float?
    ) -> DetectedObject? {
        // Primary: smaller box. Secondary: nearer. Tertiary: higher confidence.
        return pool.min { a, b in
            let aa = viewArea(of: a, imagePixelSize: imagePixelSize, orientation: orientation, viewSize: viewSize)
            let ab = viewArea(of: b, imagePixelSize: imagePixelSize, orientation: orientation, viewSize: viewSize)
            if abs(aa - ab) / max(aa, ab) > 0.08 {
                return aa < ab
            }
            let da = depthMeters(a) ?? Float.greatestFiniteMagnitude
            let db = depthMeters(b) ?? Float.greatestFiniteMagnitude
            if abs(da - db) > 0.03 {
                return da < db
            }
            return a.confidence > b.confidence
        }
    }

    enum DetectorError: LocalizedError {
        case modelMissing

        var errorDescription: String? {
            switch self {
            case .modelMissing:
                return "\(ObjectDetector.modelResourceName) Core ML model not found in app bundle."
            }
        }
    }
}
