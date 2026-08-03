import Foundation
import RealityKit
import UIKit
import simd

enum CharacterEntityFactory {
    /// Builds a simple pink "living" character: face + 4 limb capsules.
    /// `bboxFraction` is the larger side of the 2D detection in normalized screen space (rough scale cue).
    static func makeCharacter(label: String, bboxFraction: Float) -> Entity {
        let root = Entity()
        root.name = "living-\(label)"

        let scale = max(0.08, min(0.35, bboxFraction * 0.9))
        root.scale = SIMD3<Float>(repeating: scale)

        let pink = UIColor(red: 1.0, green: 0.55, blue: 0.72, alpha: 1.0)
        let deepPink = UIColor(red: 0.95, green: 0.35, blue: 0.55, alpha: 1.0)
        let limbColor = UIColor(red: 1.0, green: 0.70, blue: 0.82, alpha: 1.0)

        // Face (sphere) — billboard-ish focal point
        let faceMesh = MeshResource.generateSphere(radius: 0.5)
        var faceMaterial = SimpleMaterial(color: pink, isMetallic: false)
        faceMaterial.roughness = 0.4
        let face = ModelEntity(mesh: faceMesh, materials: [faceMaterial])
        face.name = "face"
        face.position = .zero
        root.addChild(face)

        // Soft face plane accent (2D-ish billboard feel)
        let planeMesh = MeshResource.generatePlane(width: 0.85, height: 0.55)
        let planeMaterial = UnlitMaterial(color: deepPink.withAlphaComponent(0.85))
        let plane = ModelEntity(mesh: planeMesh, materials: [planeMaterial])
        plane.name = "facePlane"
        plane.position = SIMD3(0, 0.05, 0.48)
        root.addChild(plane)

        // Eyes
        let eyeMesh = MeshResource.generateSphere(radius: 0.08)
        let eyeMaterial = UnlitMaterial(color: .white)
        let leftEye = ModelEntity(mesh: eyeMesh, materials: [eyeMaterial])
        leftEye.position = SIMD3(-0.16, 0.12, 0.42)
        let rightEye = ModelEntity(mesh: eyeMesh, materials: [eyeMaterial])
        rightEye.position = SIMD3(0.16, 0.12, 0.42)
        root.addChild(leftEye)
        root.addChild(rightEye)

        let pupilMaterial = UnlitMaterial(color: .black)
        let pupilMesh = MeshResource.generateSphere(radius: 0.04)
        let lp = ModelEntity(mesh: pupilMesh, materials: [pupilMaterial])
        lp.position = SIMD3(-0.16, 0.12, 0.48)
        let rp = ModelEntity(mesh: pupilMesh, materials: [pupilMaterial])
        rp.position = SIMD3(0.16, 0.12, 0.48)
        root.addChild(lp)
        root.addChild(rp)

        // Limbs as capsules (arms / legs)
        let limbMesh = MeshResource.generateBox(size: SIMD3(0.12, 0.55, 0.12), cornerRadius: 0.06)
        let limbMaterial = SimpleMaterial(color: limbColor, isMetallic: false)

        func limb(at position: SIMD3<Float>, name: String) -> ModelEntity {
            let e = ModelEntity(mesh: limbMesh, materials: [limbMaterial])
            e.name = name
            e.position = position
            return e
        }

        let leftArm = limb(at: SIMD3(-0.55, 0.05, 0), name: "leftArm")
        leftArm.orientation = simd_quatf(angle: .pi / 8, axis: SIMD3(0, 0, 1))
        let rightArm = limb(at: SIMD3(0.55, 0.05, 0), name: "rightArm")
        rightArm.orientation = simd_quatf(angle: -.pi / 8, axis: SIMD3(0, 0, 1))
        let leftLeg = limb(at: SIMD3(-0.22, -0.7, 0), name: "leftLeg")
        let rightLeg = limb(at: SIMD3(0.22, -0.7, 0), name: "rightLeg")

        root.addChild(leftArm)
        root.addChild(rightArm)
        root.addChild(leftLeg)
        root.addChild(rightLeg)

        attachIdleAnimation(to: root, arms: (leftArm, rightArm), legs: (leftLeg, rightLeg))

        return root
    }

    private static func attachIdleAnimation(
        to root: Entity,
        arms: (Entity, Entity),
        legs: (Entity, Entity)
    ) {
        // Gentle bob
        let up = root.transform
        var bob = up
        bob.translation.y += 0.06
        root.move(to: bob, relativeTo: root.parent, duration: 0.9, timingFunction: .easeInOut)

        // Orbit / sway limbs with delayed moves (loop approximated by recurring transforms)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            loopSway(entity: arms.0, axis: SIMD3(0, 0, 1), angle: 0.35, firstDelay: 0)
            loopSway(entity: arms.1, axis: SIMD3(0, 0, 1), angle: -0.35, firstDelay: 0.15)
            loopSway(entity: legs.0, axis: SIMD3(1, 0, 0), angle: 0.2, firstDelay: 0.1)
            loopSway(entity: legs.1, axis: SIMD3(1, 0, 0), angle: -0.2, firstDelay: 0.25)
            loopBob(root: root)
        }
    }

    private static func loopBob(root: Entity) {
        guard root.parent != nil || root.scene != nil else { return }
        let baseY = root.position.y
        var high = root.transform
        high.translation.y = baseY + 0.05
        var low = root.transform
        low.translation.y = baseY - 0.02

        root.move(to: high, relativeTo: root.parent, duration: 0.85, timingFunction: .easeInOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            root.move(to: low, relativeTo: root.parent, duration: 0.85, timingFunction: .easeInOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                loopBob(root: root)
            }
        }
    }

    private static func loopSway(entity: Entity, axis: SIMD3<Float>, angle: Float, firstDelay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + firstDelay) {
            swayOnce(entity: entity, axis: axis, angle: angle)
        }
    }

    private static func swayOnce(entity: Entity, axis: SIMD3<Float>, angle: Float) {
        guard entity.parent != nil || entity.scene != nil else { return }
        let base = entity.orientation
        let tipped = simd_mul(base, simd_quatf(angle: angle, axis: axis))
        entity.move(
            to: Transform(scale: entity.scale, rotation: tipped, translation: entity.position),
            relativeTo: entity.parent,
            duration: 0.55,
            timingFunction: .easeInOut
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            entity.move(
                to: Transform(scale: entity.scale, rotation: base, translation: entity.position),
                relativeTo: entity.parent,
                duration: 0.55,
                timingFunction: .easeInOut
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                swayOnce(entity: entity, axis: axis, angle: angle)
            }
        }
    }
}
