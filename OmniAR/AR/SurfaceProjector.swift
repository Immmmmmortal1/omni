import Foundation
import ARKit
import RealityKit
import CoreVideo
import simd
import UIKit

/// Projects a UIKit-normalized screen point onto the object along the camera ray.
/// Placement order follows [CoreML-in-ARKit](https://github.com/hanleyweng/CoreML-in-ARKit):
/// prefer ARKit `.featurePoint` hit tests over estimated planes (planes often hit the table).
enum SurfaceProjector {
    struct Hit {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>?
        /// depth|arkit-feature|feature|raycast|fallback — for Debug diagnostics.
        var path: String
        var depthMeters: Float
    }

    /// 兜底距离（米）：所有 depth/feature/raycast 路径都失败时沿射线放点。
    /// 不动行为，仅提为常量便于诊断与未来调参。
    /// 机制保留原因：无特征区域若直接 fail 体验更差（tap 完全无响应）；
    /// 0.55m 是经验值——近到不至于悬空太远、远到小物体也能命中。
    /// path=fallback 已在 LivingObjectSystem.debugLog 中可见，便于诊断。
    static let kFallbackDistance: Float = 0.55

    static func project(
        normalizedUIKitPoint point: CGPoint,
        in arView: ARView,
        frame: ARFrame
    ) -> Hit? {
        let size = arView.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }

        let viewPoint = CGPoint(x: point.x * size.width, y: point.y * size.height)

        // 1) LiDAR / scene depth — true object surface when available.
        if let depthHit = hitFromSceneDepth(normalizedUIKitPoint: point, frame: frame) {
            return depthHit
        }

        // 2) CoreML-in-ARKit path: ARKit feature-point hit test at the screen point.
        if let arkitFeature = hitFromARKitFeaturePoint(
            normalizedUIKitPoint: point,
            viewPoint: viewPoint,
            in: arView,
            frame: frame
        ) {
            return arkitFeature
        }

        guard let ray = arView.ray(through: viewPoint) else { return nil }
        let dir = simd_normalize(ray.direction)

        // 3) Manual feature-cloud sample along the ray (fallback if ARKit hitTest empty).
        if let distance = estimatedRayDistance(rayOrigin: ray.origin, direction: dir, frame: frame) {
            let position = ray.origin + dir * distance
            return Hit(
                position: position,
                normal: -dir,
                path: "feature",
                depthMeters: distance
            )
        }

        // 4) Estimated plane raycast — last resort (often the supporting table).
        let raycasts = arView.raycast(from: viewPoint, allowing: .estimatedPlane, alignment: .any)
        if let first = raycasts.first {
            let t = first.worldTransform
            let position = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            let normal = SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z)
            let depth = simd_length(position - ray.origin)
            return Hit(
                position: position,
                normal: simd_normalize(normal),
                path: "raycast",
                depthMeters: max(0.15, depth)
            )
        }

        // 5) Fixed mid-range fallback along the view ray.
        let position = ray.origin + dir * Self.kFallbackDistance
        return Hit(position: position, normal: -dir, path: "fallback", depthMeters: Self.kFallbackDistance)
    }

    // MARK: - CoreML-in-ARKit featurePoint hit

    /// Same idea as `sceneView.hitTest(point, types: [.featurePoint])` in CoreML-in-ARKit.
    /// Uses ARFrame hitTest (image-normalized) with a view-space fallback via ray + cloud.
    private static func hitFromARKitFeaturePoint(
        normalizedUIKitPoint point: CGPoint,
        viewPoint: CGPoint,
        in arView: ARView,
        frame: ARFrame
    ) -> Hit? {
        let interfaceOrientation = currentInterfaceOrientation()
        let displayTransform = frame.displayTransform(
            for: interfaceOrientation,
            viewportSize: CGSize(width: 1, height: 1)
        )
        // displayTransform: normalized image → normalized view; invert for ARFrame.hitTest.
        let imagePoint = point.applying(displayTransform.inverted())

        // Deprecated but still the API CoreML-in-ARKit relies on for object-surface pins.
        let results = frame.hitTest(imagePoint, types: [.featurePoint])
        guard let closest = results.first else { return nil }

        let t = closest.worldTransform
        let position = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let camPos = SIMD3<Float>(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z
        )
        let depth = simd_length(position - camPos)
        guard depth.isFinite, depth > 0.08, depth < 6 else { return nil }

        // Keep unused params for call-site parity / future ARView-native hit APIs.
        _ = viewPoint
        _ = arView

        return Hit(
            position: position,
            normal: nil,
            path: "arkit-feature",
            depthMeters: depth
        )
    }

    // MARK: - Scene depth

    private static func hitFromSceneDepth(normalizedUIKitPoint point: CGPoint, frame: ARFrame) -> Hit? {
        let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
        guard let depthMap = depthData?.depthMap else { return nil }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard width > 0, height > 0 else { return nil }

        let interfaceOrientation = currentInterfaceOrientation()
        let displayTransform = frame.displayTransform(
            for: interfaceOrientation,
            viewportSize: CGSize(width: 1, height: 1)
        )
        let imagePoint = point.applying(displayTransform.inverted())

        let ix = clamp(Int(imagePoint.x * CGFloat(width)), 0, width - 1)
        let iy = clamp(Int(imagePoint.y * CGFloat(height)), 0, height - 1)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let row = base.advanced(by: iy * bytesPerRow).assumingMemoryBound(to: Float32.self)
        let depth = row[ix]
        guard depth.isFinite, depth > 0.05, depth < 8 else { return nil }

        let cam = frame.camera
        let intrinsics = cam.intrinsics
        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]
        let cx = intrinsics[2, 0]
        let cy = intrinsics[2, 1]

        let imageWidth = CVPixelBufferGetWidth(frame.capturedImage)
        let imageHeight = CVPixelBufferGetHeight(frame.capturedImage)
        let sx = Float(imageWidth) / Float(width)
        let sy = Float(imageHeight) / Float(height)
        let u = (Float(ix) + 0.5) * sx
        let v = (Float(iy) + 0.5) * sy

        let x = (u - cx) * depth / fx
        let y = (v - cy) * depth / fy
        let camPoint = SIMD4<Float>(x, y, depth, 1)
        let world = cam.transform * camPoint
        let position = SIMD3<Float>(world.x, world.y, world.z)
        return Hit(position: position, normal: nil, path: "depth", depthMeters: depth)
    }

    private static func estimatedRayDistance(
        rayOrigin: SIMD3<Float>,
        direction: SIMD3<Float>,
        frame: ARFrame
    ) -> Float? {
        guard let points = frame.rawFeaturePoints?.points, !points.isEmpty else { return nil }
        let dir = simd_normalize(direction)
        var best: Float?
        var bestScore = Float.greatestFiniteMagnitude
        for p in points {
            let toPoint = p - rayOrigin
            let along = simd_dot(toPoint, dir)
            guard along > 0.15, along < 4 else { continue }
            let lateral = simd_length(toPoint - dir * along)
            let score = lateral + along * 0.015
            if score < bestScore {
                bestScore = score
                best = along
            }
        }
        return bestScore < 0.45 ? best : nil
    }

    private static func currentInterfaceOrientation() -> UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first?.interfaceOrientation ?? .portrait
    }

    private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
        min(max(v, lo), hi)
    }
}
