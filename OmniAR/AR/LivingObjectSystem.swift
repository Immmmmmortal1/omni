import Foundation
import Combine
import RealityKit
import ARKit
import UIKit
import simd

@MainActor
final class LivingObjectSystem: ObservableObject {
    @Published private(set) var detectionCount: Int = 0
    @Published private(set) var livingCount: Int = 0
    @Published private(set) var statusText: String = "Point at everyday objects"

    private(set) var latestDetections: [DetectedObject] = []
    private var detector: ObjectDetector?
    private weak var arView: ARView?
    private var isDetecting = false
    private let maxLiving = 6

    func attach(arView: ARView) {
        self.arView = arView
        do {
            detector = try ObjectDetector()
            statusText = "tap an object to bring it alive"
        } catch {
            statusText = "Detector failed: \(error.localizedDescription)"
        }
    }

    func updateDetections(from frame: ARFrame) {
        guard let detector, !isDetecting else { return }
        isDetecting = true
        let buffer = frame.capturedImage

        Task { [weak self] in
            let results: [DetectedObject]
            do {
                results = try detector.detect(pixelBuffer: buffer)
            } catch {
                results = []
            }
            await MainActor.run {
                guard let self else { return }
                self.latestDetections = results
                self.detectionCount = results.count
                self.isDetecting = false
                if self.livingCount == 0 {
                    self.statusText = results.isEmpty
                        ? "Looking for objects…"
                        : "tap an object to bring it alive"
                }
            }
        }
    }

    func handleTap(at viewPoint: CGPoint) {
        guard let arView else { return }
        let size = arView.bounds.size
        guard size.width > 0, size.height > 0 else { return }

        let normalized = CGPoint(x: viewPoint.x / size.width, y: viewPoint.y / size.height)

        guard let picked = ObjectDetector.pickTapped(
            detections: latestDetections,
            normalizedTap: normalized
        ) else {
            statusText = "No object under tap — try again"
            return
        }

        let results = arView.raycast(from: viewPoint, allowing: .estimatedPlane, alignment: .any)
        let worldTransform: simd_float4x4
        if let first = results.first {
            worldTransform = first.worldTransform
        } else if let ray = arView.ray(through: viewPoint) {
            let position = ray.origin + simd_normalize(ray.direction) * 0.6
            worldTransform = Transform(translation: position).matrix
        } else if let cam = arView.session.currentFrame?.camera {
            var t = cam.transform
            // Place along camera forward (-Z in camera space)
            let forward = SIMD3<Float>(-t.columns.2.x, -t.columns.2.y, -t.columns.2.z)
            let origin = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            let position = origin + simd_normalize(forward) * 0.6
            worldTransform = Transform(translation: position).matrix
        } else {
            statusText = "No surface — move around and retry"
            return
        }

        if livingCount >= maxLiving {
            if let oldest = arView.scene.anchors.first(where: { ($0.name ?? "").hasPrefix("living-anchor") }) {
                arView.scene.removeAnchor(oldest)
                livingCount = max(0, livingCount - 1)
            }
        }

        let bboxFrac = Float(max(picked.boundingBox.width, picked.boundingBox.height))
        let character = CharacterEntityFactory.makeCharacter(label: picked.label, bboxFraction: bboxFrac)

        let anchor = AnchorEntity(world: worldTransform)
        anchor.name = "living-anchor-\(picked.label)-\(UUID().uuidString.prefix(6))"
        character.position = SIMD3(0, 0.12, 0)
        anchor.addChild(character)
        arView.scene.addAnchor(anchor)

        livingCount += 1
        statusText = "Alive: \(COCOClasses.displayName(for: picked.label))"
    }
}
