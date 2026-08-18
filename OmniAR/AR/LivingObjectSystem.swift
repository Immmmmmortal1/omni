import Foundation
import Combine
import RealityKit
import ARKit
import UIKit
import simd
import CoreVideo

@MainActor
final class LivingObjectSystem: ObservableObject {
    @Published private(set) var detectionCount: Int = 0
    @Published private(set) var livingCount: Int = 0
    @Published private(set) var statusText: String = "Point at everyday objects"
    /// When true, YOLO is off — stickers stay on fixed world anchors.
    @Published private(set) var isLocked: Bool = false
    /// Line spoken by the pinned face, positioned in screen space. Nil = no bubble.
    @Published private(set) var speech: LivingSpeech?
    /// Transparent face decal glued on the pinned object. Nil = none (asset missing → RealityKit fallback).
    @Published private(set) var creature: LivingCreature?

    /// Decal PNG stickers (alpha) from 包图网; if missing, keep RealityKit face fallback.
    private let decalAvailable = DecalLibrary.isBundled

    private(set) var latestDetections: [DetectedObject] = []
    private var detector: ObjectDetector?
    private weak var arView: ARView?
    private var isDetecting = false
    private let maxLiving = 6

    /// 贴纸直径占物体短边实际尺寸的比例（目标：贴纸 ≈ 物体短边 × 0.5）。
    /// 原 0.32 偏小（贴纸几乎看不到）；集中放成常量便于后续微调。
    private static let kDecalDiameterFraction: Float = 0.5

    /// depth 命中（真正打到物体表面）时的 lift，仅用于防 z-fighting。
    /// 不再沿相机方向大抬，避免贴纸悬空在物体上方（原 liftMeters 0.06~0.32m）。
    private static let kDepthHitLiftMeters: Float = 0.02

    private var tracks: [LivingTrack] = []
    /// The pinned track whose speech bubble is currently tracked on screen.
    private var activeTrack: LivingTrack?

    func attach(arView: ARView) {
        self.arView = arView
        do {
            detector = try ObjectDetector()
            statusText = "tap an object to stick a face on it"
            Self.debugLog("detector ready model=\(ObjectDetector.modelResourceName)")
        } catch {
            statusText = "Detector failed: \(error.localizedDescription)"
            Self.debugLog("detector failed: \(error.localizedDescription)")
        }
    }

    func tickFrame(_ frame: ARFrame) {
        // Locked stickers: only yaw toward camera; do NOT reproject.
        updateBillboards(frame: frame)
    }

    func updateDetections(from frame: ARFrame) {
        updateBillboards(frame: frame)
        // After pin: stop recognizing — world anchors must not be rewritten.
        guard !isLocked else { return }
        guard let detector, !isDetecting else { return }
        isDetecting = true
        let buffer = frame.capturedImage
        let interfaceOrientation = Self.interfaceOrientation()
        let visionOrient = ObjectDetector.visionOrientation(for: interfaceOrientation)

        Task { [weak self] in
            let results: [DetectedObject]
            do {
                results = try detector.detect(pixelBuffer: buffer, orientation: visionOrient)
            } catch {
                results = []
            }
            await MainActor.run {
                guard let self else { return }
                // 防御：异步检测在途时用户可能已 pin（isLocked=true 且清空了 detections）。
                // 此处若再无条件写回，会污染锁定状态——旧帧检测框重新出现、count 跳变。
                // 必须丢弃这次结果并释放 isDetecting，让锁定状态保持干净。
                guard !self.isLocked else {
                    self.isDetecting = false
                    return
                }
                self.latestDetections = results
                self.detectionCount = results.count
                self.isDetecting = false
                if self.livingCount == 0 {
                    self.statusText = results.isEmpty
                        ? "Looking for objects…"
                        : "tap an object to stick a face on it"
                }
            }
        }
    }

    func handleTap(at viewPoint: CGPoint) {
        guard let arView,
              let frame = arView.session.currentFrame
        else { return }

        let size = arView.bounds.size
        guard size.width > 0, size.height > 0 else { return }

        let normalized = CGPoint(x: viewPoint.x / size.width, y: viewPoint.y / size.height)

        // Locked: any tap clears and resumes hunting (blank / Esc product rule).
        if isLocked {
            clearAll(reason: "blank-tap")
            return
        }

        let orientation = Self.interfaceOrientation()

        // ===== 时序对齐：用当前帧 capturedImage 同步跑一次检测 =====
        // 原因：latestDetections 是 0.12s 节流异步结果，与 currentFrame 差 100ms+，
        // 手持时检测框已漂移 → 旧框 + 新帧投影导致贴纸歪。
        // YOLO 单次推理约 20-50ms，同步阻塞主线程可接受。
        // 区分两种情况：
        //   - 同步成功（无异常）：用 syncResults，空就是空（pickTapped 返 nil → 提示无物体）
        //   - 同步抛异常：才回退 latestDetections，标注 sync-detect-fallback
        //   （若空也回退旧框，会重新引入"旧框+新帧投影"的时序错位）
        // 注意：isDetecting 防重入只在异步节流路径用；同步路径直接调用即可。
        var detectionsForPick = latestDetections
        if let detector {
            let visionOrient = ObjectDetector.visionOrientation(for: orientation)
            do {
                let syncResults = try detector.detect(
                    pixelBuffer: frame.capturedImage,
                    orientation: visionOrient
                )
                // 同步成功：无论空否都采用当前帧结果（空 → pickTapped 返 nil 走提示分支）
                detectionsForPick = syncResults
                latestDetections = syncResults
                detectionCount = syncResults.count
            } catch {
                // 仅异常才回退旧框，并标注便于诊断
                Self.debugLog("sync-detect-fallback reason=error \(error.localizedDescription)")
            }
        }

        let imagePixelSize = CGSize(
            width: CVPixelBufferGetWidth(frame.capturedImage),
            height: CVPixelBufferGetHeight(frame.capturedImage)
        )

        guard let picked = ObjectDetector.pickTapped(
            detections: detectionsForPick,
            normalizedTap: normalized,
            imagePixelSize: imagePixelSize,
            orientation: orientation,
            viewSize: size,
            depthMeters: { det in
                let box = det.viewNormalizedBox(
                    imagePixelSize: imagePixelSize,
                    orientation: orientation,
                    viewSize: size
                )
                let center = CGPoint(x: box.midX, y: box.midY)
                return SurfaceProjector.project(
                    normalizedUIKitPoint: center,
                    in: arView,
                    frame: frame
                )?.depthMeters
            }
        ) else {
            statusText = "No object under tap — try again"
            Self.debugLog("tap miss normalized=\(normalized) detections=\(latestDetections.count)")
            return
        }

        let viewBox = picked.viewNormalizedBox(
            imagePixelSize: imagePixelSize,
            orientation: orientation,
            viewSize: size
        )
        // Aim at the true box center so the face sticks to the object's middle.
        let attachPoint = CGPoint(x: viewBox.midX, y: viewBox.midY)
        let completeness = ObjectDetector.completeness(
            of: picked,
            imagePixelSize: imagePixelSize,
            orientation: orientation,
            viewSize: size
        )
        let viewArea = Float(max(viewBox.width * viewBox.height, 1e-6))
        guard let hit = SurfaceProjector.project(
            normalizedUIKitPoint: attachPoint,
            in: arView,
            frame: frame
        ) else {
            statusText = "Can't find surface on that object — move closer"
            Self.debugLog("project fail label=\(picked.label) tapRay=0 boxAim=1")
            return
        }

        let bboxFrac = Float(max(viewBox.width, viewBox.height))
        // Size the face by the object's SHORTER side so a tall/wide box never inflates the face.
        let sizeFrac = Float(max(min(viewBox.width, viewBox.height), 0.02))
        // depth 命中真表面：仅防 z-fighting，不再沿相机方向大抬（避免贴纸悬空在物体上方）。
        // feature/raycast 可能命中支撑面（桌子），保留原 lift 逻辑抬到物体中部。
        let liftMeters: Float
        if hit.path == "depth" {
            liftMeters = Self.kDepthHitLiftMeters
        } else {
            liftMeters = Self.liftMeters(for: hit, bboxFrac: bboxFrac, viewArea: viewArea, label: picked.label)
        }

        if tracks.count >= maxLiving {
            evictOldest()
        }

        let character = CharacterEntityFactory.makeCharacter(
            label: picked.label,
            bboxFraction: sizeFrac
        )
        CharacterEntityFactory.updateScale(
            of: character,
            bboxFraction: sizeFrac,
            depthMeters: hit.depthMeters
        )

        // World-fixed anchor — pose frozen at pin time (ARKit keeps it in world space).
        let lift = surfaceLift(camera: frame.camera, at: hit.position, meters: liftMeters)
        let worldPosition = hit.position + lift
        let anchor = AnchorEntity(world: worldPosition)
        anchor.name = "living-anchor-\(picked.label)-\(UUID().uuidString.prefix(6))"
        character.position = .zero
        anchor.addChild(character)
        arView.scene.addAnchor(anchor)

        Self.debugLog(
            "pin label=\(picked.label) complete=\(String(format: "%.2f", Double(completeness))) area=\(String(format: "%.3f", Double(viewArea))) boxAim=1 path=\(hit.path) depth=\(String(format: "%.2f", hit.depthMeters)) lift=\(String(format: "%.2f", liftMeters)) bbox=\(String(format: "%.2f", bboxFrac))"
        )

        // 贴纸直径 ≈ 物体短边实际尺寸 × kDecalDiameterFraction（目标 0.5，原 0.32 偏小）。
        // worldRadius = 直径 / 2；depthMeters × sizeFrac ≈ 物体短边米数。
        let worldRadius = max(0.015, hit.depthMeters * sizeFrac * Self.kDecalDiameterFraction * 0.5)
        // When the decal overlay is active, hide the RealityKit face to avoid a double image.
        character.isEnabled = !decalAvailable

        let track = LivingTrack(
            id: UUID(),
            label: picked.label,
            anchor: anchor,
            character: character,
            worldPosition: worldPosition,
            worldRadius: worldRadius,
            createdAt: Date()
        )
        tracks.append(track)
        activeTrack = track
        livingCount = tracks.count
        isLocked = true
        detectionCount = 0
        // Capture scene context BEFORE clearing detections so the line stays situational.
        let contextLabels = latestDetections.map(\.label)
        latestDetections = []
        if !decalAvailable {
            CharacterEntityFactory.billboard(character, toward: frame.camera)
        }
        statusText = "Locked on \(COCOClasses.displayName(for: picked.label)) · tap empty / Esc to clear"
        Self.debugLog("locked tracks=\(tracks.count) detection=OFF decal=\(decalAvailable)")

        // Show a thinking bubble immediately, then fill with the generated line.
        let initialPoint = arView.project(worldPosition) ?? attachPoint
        speech = LivingSpeech(text: "", screenPoint: initialPoint, isThinking: true)
        if decalAvailable {
            // One random expression per pin — locked for the lifetime of this track (no pose refresh).
            // sizePoints 临时值 72：立即调用 updateAnchors 用与每帧一致的投影公式覆写，
            // 避免首帧 72pt → 投影尺寸的跳变。72 落在 clamp 48...160 范围内，即使投影失败也合理。
            creature = LivingCreature(
                id: track.id,
                screenPoint: initialPoint,
                sizePoints: 72,
                expressionIndex: DecalLibrary.randomExpressionIndex(),
                visible: true
            )
            updateAnchors(frame: frame)
        }
        generateSpeech(selected: picked.label, others: contextLabels, trackID: track.id)
    }

    private func generateSpeech(selected: String, others: [String], trackID: UUID) {
        let languageCode = Locale.preferredLanguages.first ?? "en"
        Task { [weak self] in
            let line: String
            do {
                line = try await DeepSeekClient.generateLine(
                    selected: selected,
                    others: others,
                    languageCode: languageCode
                )
            } catch {
                line = SceneLine.fallback(selected: selected, languageCode: languageCode)
                Self.debugLog("speech fallback label=\(selected) reason=\(error)")
            }
            await MainActor.run {
                guard let self, self.activeTrack?.id == trackID else { return }
                if var current = self.speech {
                    current.text = line
                    current.isThinking = false
                    self.speech = current
                }
                Self.debugLog("speech ready label=\(selected) line=\(line)")
            }
        }
    }

    /// Reproject the active track's fixed world anchor to screen space every frame so
    /// the speech bubble and Rive creature stay glued to the object and scale with distance.
    private func updateAnchors(frame: ARFrame) {
        guard let arView, let track = activeTrack else { return }
        guard let point = arView.project(track.worldPosition) else {
            // Anchor is off-screen / behind the camera — hide the creature this frame.
            if var creature, creature.visible {
                creature.visible = false
                self.creature = creature
            }
            return
        }

        if var current = speech {
            current.screenPoint = point
            if current != speech { speech = current }
        }

        guard var creature else { return }
        // On-screen size = pixel length of a world-space radius offset along the camera's right axis.
        let cam = frame.camera.transform
        let right = simd_normalize(SIMD3<Float>(cam.columns.0.x, cam.columns.0.y, cam.columns.0.z))
        let edgeWorld = track.worldPosition + right * track.worldRadius
        var diameter: CGFloat = creature.sizePoints
        if let edge = arView.project(edgeWorld) {
            // clamp 收窄 48...160：原 36...220 上限过大（远距离贴纸糊满屏）、下限过小（近距离看不清）。
            // 与 pin 时初始值 72 语义一致（72 落在范围内，投影失败也不会 clamp 越界）。
            diameter = max(48, min(160, 2 * hypot(edge.x - point.x, edge.y - point.y)))
        }
        creature.screenPoint = point
        creature.sizePoints = diameter
        creature.visible = true
        if creature != self.creature { self.creature = creature }
    }

    /// Esc / explicit clear → hunting again.
    func clearAll(reason: String = "clear") {
        guard let arView else {
            tracks.removeAll()
            activeTrack = nil
            speech = nil
            creature = nil
            livingCount = 0
            isLocked = false
            return
        }
        for track in tracks {
            arView.scene.removeAnchor(track.anchor)
        }
        tracks.removeAll()
        activeTrack = nil
        speech = nil
        creature = nil
        livingCount = 0
        isLocked = false
        detectionCount = 0
        latestDetections = []
        statusText = "tap an object to stick a face on it"
        Self.debugLog("cleared reason=\(reason) detection=ON")
    }

    private func updateBillboards(frame: ARFrame) {
        if !decalAvailable {
            for track in tracks {
                CharacterEntityFactory.billboard(track.character, toward: frame.camera)
            }
        }
        updateAnchors(frame: frame)
    }

    /// Support-plane feature hits need a body lift; full-screen furniture less so.
    private static func liftMeters(
        for hit: SurfaceProjector.Hit,
        bboxFrac: Float,
        viewArea: Float,
        label: String
    ) -> Float {
        let extentMeters = hit.depthMeters * bboxFrac * 1.15
        // Small objects (cup/bottle) sitting on tables: featurePoint ≈ table → lift mid-body.
        let isSmall = viewArea < 0.35 && !COCOClasses.isSupportSurface(label)
        let factor: Float
        switch hit.path {
        // 注意：depth path 在 handleTap 调用处已分支为 kDepthHitLiftMeters，不会走到这里。
        // 保留 case 以便未来若调整策略可直接复用本函数。
        case "arkit-feature", "feature", "depth":
            factor = isSmall ? 0.45 : 0.12
        default:
            factor = isSmall ? 0.50 : 0.30
        }
        let lo: Float = isSmall ? 0.06 : 0.02
        let hi: Float = isSmall ? 0.32 : 0.22
        return min(hi, max(lo, extentMeters * factor))
    }

    private func surfaceLift(camera: ARCamera, at position: SIMD3<Float>, meters: Float) -> SIMD3<Float> {
        guard meters > 0 else { return .zero }
        let camPos = SIMD3<Float>(
            camera.transform.columns.3.x,
            camera.transform.columns.3.y,
            camera.transform.columns.3.z
        )
        let towardCamera = simd_normalize(camPos - position)
        return towardCamera * meters
    }

    private func evictOldest() {
        guard let arView, let oldest = tracks.min(by: { $0.createdAt < $1.createdAt }) else { return }
        arView.scene.removeAnchor(oldest.anchor)
        tracks.removeAll { $0.id == oldest.id }
        if activeTrack?.id == oldest.id {
            activeTrack = nil
            speech = nil
            creature = nil
        }
        livingCount = tracks.count
    }

    private static func interfaceOrientation() -> UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first?.interfaceOrientation ?? .portrait
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("[OmniAR][pin] \(message)")
        #endif
    }

}

@MainActor
private final class LivingTrack {
    let id: UUID
    let label: String
    let anchor: AnchorEntity
    let character: Entity
    /// Frozen world anchor (meters) — projected each frame to follow the object on screen.
    let worldPosition: SIMD3<Float>
    /// World-space half-extent (meters) used to depth-scale the 2D overlay.
    let worldRadius: Float
    let createdAt: Date

    init(
        id: UUID,
        label: String,
        anchor: AnchorEntity,
        character: Entity,
        worldPosition: SIMD3<Float>,
        worldRadius: Float,
        createdAt: Date
    ) {
        self.id = id
        self.label = label
        self.anchor = anchor
        self.character = character
        self.worldPosition = worldPosition
        self.worldRadius = worldRadius
        self.createdAt = createdAt
    }
}
