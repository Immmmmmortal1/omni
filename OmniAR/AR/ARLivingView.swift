import SwiftUI
import RealityKit
import ARKit

struct ARLivingView: UIViewRepresentable {
    @ObservedObject var system: LivingObjectSystem

    func makeCoordinator() -> Coordinator {
        Coordinator(system: system)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        }
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        arView.session.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)
        context.coordinator.arView = arView

        // Esc clears locked stickers (hardware keyboard / Stage Manager).
        arView.addSubview(context.coordinator.keyCatcher)
        context.coordinator.keyCatcher.frame = .zero
        DispatchQueue.main.async {
            context.coordinator.keyCatcher.becomeFirstResponder()
        }

        system.attach(arView: arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.system = system
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        var system: LivingObjectSystem
        weak var arView: ARView?
        private var lastDetectTime: TimeInterval = 0
        private let minDetectInterval: TimeInterval = 0.12
        let keyCatcher = EscapeKeyView()

        init(system: LivingObjectSystem) {
            self.system = system
            super.init()
            keyCatcher.onEscape = { [weak self] in
                Task { @MainActor in
                    self?.system.clearAll(reason: "escape")
                }
            }
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let t = frame.timestamp
            Task { @MainActor in
                if system.isLocked {
                    // World-locked: no YOLO — billboard only.
                    system.tickFrame(frame)
                    return
                }
                if t - lastDetectTime >= minDetectInterval {
                    lastDetectTime = t
                    system.updateDetections(from: frame)
                } else {
                    system.tickFrame(frame)
                }
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView else { return }
            let point = gesture.location(in: arView)
            Task { @MainActor in
                system.handleTap(at: point)
            }
        }
    }
}

/// Tiny first-responder view so Escape clears locks when a keyboard is attached.
final class EscapeKeyView: UIView {
    var onEscape: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(
                title: "Clear",
                action: #selector(escapePressed),
                input: UIKeyCommand.inputEscape,
                modifierFlags: []
            )
        ]
    }

    @objc private func escapePressed() {
        onEscape?()
    }
}
