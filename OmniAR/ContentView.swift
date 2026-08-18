import SwiftUI

struct ContentView: View {
    @StateObject private var livingSystem = LivingObjectSystem()

    var body: some View {
        // Full-bleed ZStack so ARView.project points and overlay `.position` share
        // the same coordinate space (avoids Safe Area clipping the decal in half).
        ZStack {
            ARLivingView(system: livingSystem)
                .ignoresSafeArea()

            if let creature = livingSystem.creature {
                CreatureOverlayView(creature: creature)
                    .id(creature.id)
            }

            // Thinking "…" + line bubble (decal expression is static — bubble carries wait/talk).
            if let speech = livingSystem.speech {
                SpeechBubbleView(speech: speech)
                    .animation(.easeInOut(duration: 0.2), value: speech.isThinking)
            }

            StatusHUD(
                detectionCount: livingSystem.detectionCount,
                statusText: livingSystem.statusText,
                livingCount: livingSystem.livingCount,
                isLocked: livingSystem.isLocked
            )
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
