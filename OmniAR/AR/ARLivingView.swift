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
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            // Keep disabled by default for broader device support / performance.
        }
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        arView.session.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)
        context.coordinator.arView = arView

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
        private let minDetectInterval: TimeInterval = 0.12 // ~8 fps detection

        init(system: LivingObjectSystem) {
            self.system = system
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let t = frame.timestamp
            guard t - lastDetectTime >= minDetectInterval else { return }
            lastDetectTime = t
            Task { @MainActor in
                system.updateDetections(from: frame)
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
