import SwiftUI

struct ContentView: View {
    @StateObject private var livingSystem = LivingObjectSystem()

    var body: some View {
        ZStack {
            ARLivingView(system: livingSystem)
                .ignoresSafeArea()

            StatusHUD(
                detectionCount: livingSystem.detectionCount,
                statusText: livingSystem.statusText,
                livingCount: livingSystem.livingCount
            )
        }
    }
}

#Preview {
    ContentView()
}
