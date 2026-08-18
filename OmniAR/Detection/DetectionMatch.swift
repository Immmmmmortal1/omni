import Foundation
import CoreGraphics

enum DetectionMatch {
    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard !inter.isNull, !inter.isEmpty else { return 0 }
        let interArea = inter.width * inter.height
        let union = a.width * a.height + b.width * b.height - interArea
        guard union > 0 else { return 0 }
        return interArea / union
    }

    /// Same-class + highest IoU above `minIoU`; otherwise nearest center of same class.
    static func match(
        targetLabel: String,
        targetBox: CGRect,
        in detections: [DetectedObject],
        minIoU: CGFloat = 0.25
    ) -> DetectedObject? {
        let sameClass = detections.filter { $0.label == targetLabel }
        guard !sameClass.isEmpty else { return nil }

        var best: DetectedObject?
        var bestIoU: CGFloat = 0
        for det in sameClass {
            let score = iou(targetBox, det.boundingBox)
            if score > bestIoU {
                bestIoU = score
                best = det
            }
        }
        if let best, bestIoU >= minIoU {
            return best
        }

        let targetCenter = CGPoint(x: targetBox.midX, y: targetBox.midY)
        return sameClass.min { a, b in
            let ca = CGPoint(x: a.boundingBox.midX, y: a.boundingBox.midY)
            let cb = CGPoint(x: b.boundingBox.midX, y: b.boundingBox.midY)
            let da = hypot(ca.x - targetCenter.x, ca.y - targetCenter.y)
            let db = hypot(cb.x - targetCenter.x, cb.y - targetCenter.y)
            return da < db
        }
    }
}
