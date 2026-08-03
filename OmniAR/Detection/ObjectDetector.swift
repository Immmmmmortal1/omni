import Foundation
import Vision
import CoreML
import CoreVideo
import UIKit

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

    /// Convert Vision bottom-left normalized box to UIKit top-left normalized box.
    var uiKitNormalizedBox: CGRect {
        CGRect(
            x: boundingBox.origin.x,
            y: 1.0 - boundingBox.origin.y - boundingBox.height,
            width: boundingBox.width,
            height: boundingBox.height
        )
    }

    var area: CGFloat {
        boundingBox.width * boundingBox.height
    }
}

/// Runs Apple's bundled YOLOv3TinyInt8LUT Core ML model via Vision.
final class ObjectDetector {
    private let visionModel: VNCoreMLModel
    private let confidenceThreshold: Float
    private let excludePerson: Bool

    init(confidenceThreshold: Float = 0.35, excludePerson: Bool = true) throws {
        self.confidenceThreshold = confidenceThreshold
        self.excludePerson = excludePerson

        let config = MLModelConfiguration()
        config.computeUnits = .all

        let mlModel = try Self.loadModel(configuration: config)
        visionModel = try VNCoreMLModel(for: mlModel)
    }

    private static func loadModel(configuration: MLModelConfiguration) throws -> MLModel {
        // Compiled model in app bundle (Xcode coremlc output).
        if let url = Bundle.main.url(forResource: "YOLOv3TinyInt8LUT", withExtension: "mlmodelc") {
            return try MLModel(contentsOf: url, configuration: configuration)
        }
        // Raw model (less common at runtime).
        if let url = Bundle.main.url(forResource: "YOLOv3TinyInt8LUT", withExtension: "mlmodel") {
            return try MLModel(contentsOf: url, configuration: configuration)
        }
        // Some bundles nest mlmodelc as a directory resource name without extension lookup quirks.
        if let url = Bundle.main.url(forResource: "YOLOv3TinyInt8LUT", withExtension: nil) {
            return try MLModel(contentsOf: url, configuration: configuration)
        }
        throw DetectorError.modelMissing
    }

    func detect(pixelBuffer: CVPixelBuffer) throws -> [DetectedObject] {
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])

        guard let results = request.results else { return [] }

        var detections: [DetectedObject] = []

        for observation in results {
            guard let obj = observation as? VNRecognizedObjectObservation else { continue }
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

        return detections.sorted { $0.confidence > $1.confidence }
    }

    /// Prefer the smallest-area detection whose UIKit-normalized box contains the tap (nested objects).
    static func pickTapped(
        detections: [DetectedObject],
        normalizedTap: CGPoint
    ) -> DetectedObject? {
        let containing = detections.filter { det in
            det.uiKitNormalizedBox.contains(normalizedTap)
        }
        if let smallest = containing.min(by: { $0.area < $1.area }) {
            return smallest
        }

        return detections.min { a, b in
            let ca = CGPoint(x: a.uiKitNormalizedBox.midX, y: a.uiKitNormalizedBox.midY)
            let cb = CGPoint(x: b.uiKitNormalizedBox.midX, y: b.uiKitNormalizedBox.midY)
            let da = hypot(ca.x - normalizedTap.x, ca.y - normalizedTap.y)
            let db = hypot(cb.x - normalizedTap.x, cb.y - normalizedTap.y)
            return da < db
        }
    }

    enum DetectorError: LocalizedError {
        case modelMissing

        var errorDescription: String? {
            switch self {
            case .modelMissing:
                return "YOLOv3TinyInt8LUT model not found in app bundle."
            }
        }
    }
}
