import Foundation
import RealityKit
import ARKit
import UIKit
import simd

enum CharacterEntityFactory {
    /// Transparent black-line face decal — features only; object surface is the "skin".
    /// No opaque face disc. Root transform is owned by `LivingObjectSystem`.
    static func makeCharacter(label: String, bboxFraction: Float) -> Entity {
        let root = Entity()
        root.name = "living-\(label)"
        root.scale = SIMD3<Float>(repeating: scale(for: bboxFraction, depthMeters: 0.6))

        let body = Entity()
        body.name = "body"
        root.addChild(body)

        let ink = UIColor(white: 0.1, alpha: 1.0)
        let inkMaterial = UnlitMaterial(color: ink)

        // Solid black circle eyes (mug-style decal), facing +Z after plane rotation.
        let eyeMesh = MeshResource.generatePlane(width: 0.28, height: 0.28, cornerRadius: 0.14)
        let leftEye = ModelEntity(mesh: eyeMesh, materials: [inkMaterial])
        leftEye.name = "eyeL"
        leftEye.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        leftEye.position = SIMD3(-0.22, 0.08, 0.02)
        let rightEye = ModelEntity(mesh: eyeMesh, materials: [inkMaterial])
        rightEye.name = "eyeR"
        rightEye.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        rightEye.position = SIMD3(0.22, 0.08, 0.02)
        body.addChild(leftEye)
        body.addChild(rightEye)

        // Simple mouth bar (opens slightly via idle pulse on the whole body).
        let mouthMesh = MeshResource.generatePlane(width: 0.32, height: 0.09, cornerRadius: 0.045)
        let mouth = ModelEntity(mesh: mouthMesh, materials: [inkMaterial])
        mouth.name = "mouth"
        mouth.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        mouth.position = SIMD3(0, -0.2, 0.02)
        body.addChild(mouth)

        attachIdlePulse(to: body)

        return root
    }

    /// World scale so the ~1m-wide feature layout sits inside the object's shorter side.
    static func scale(for bboxFraction: Float, depthMeters: Float) -> Float {
        let depth = max(0.2, min(depthMeters, 4.0))
        let objectExtent = depth * max(0.04, bboxFraction)
        let target = objectExtent * 0.38
        return max(0.03, min(0.12, target))
    }

    static func updateScale(of character: Entity, bboxFraction: Float, depthMeters: Float) {
        let target = scale(for: bboxFraction, depthMeters: depthMeters)
        let current = character.scale.x
        let blended = current * 0.65 + target * 0.35
        character.scale = SIMD3<Float>(repeating: blended)
    }

    /// Full billboard: sticker always faces the camera (+Z toward camera).
    static func billboard(_ character: Entity, toward camera: ARCamera) {
        let camPos = SIMD3<Float>(
            camera.transform.columns.3.x,
            camera.transform.columns.3.y,
            camera.transform.columns.3.z
        )
        let worldPos = character.position(relativeTo: nil)
        var toCam = camPos - worldPos
        guard simd_length(toCam) > 1e-4 else { return }
        toCam = simd_normalize(toCam)
        let upHint = SIMD3<Float>(0, 1, 0)
        let z = toCam
        var x = simd_normalize(simd_cross(upHint, z))
        if simd_length(x) < 1e-4 {
            x = SIMD3(1, 0, 0)
        }
        let y = simd_normalize(simd_cross(z, x))
        let rot = simd_float3x3(columns: (x, y, z))
        character.orientation = simd_quatf(rot)
    }

    private static func attachIdlePulse(to body: Entity) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            loopPulse(body: body)
        }
    }

    private static func loopPulse(body: Entity) {
        guard body.parent != nil || body.scene != nil else { return }
        var big = body.transform
        big.scale = SIMD3<Float>(repeating: 1.04)
        var small = body.transform
        small.scale = SIMD3<Float>(repeating: 0.98)

        body.move(to: big, relativeTo: body.parent, duration: 0.7, timingFunction: .easeInOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            body.move(to: small, relativeTo: body.parent, duration: 0.7, timingFunction: .easeInOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                loopPulse(body: body)
            }
        }
    }
}
