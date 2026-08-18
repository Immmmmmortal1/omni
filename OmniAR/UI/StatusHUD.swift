import SwiftUI

struct StatusHUD: View {
    let detectionCount: Int
    let statusText: String
    let livingCount: Int
    var isLocked: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("omni")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.55, blue: 0.75),
                                    Color(red: 1.0, green: 0.75, blue: 0.85),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color.pink.opacity(0.45), radius: 8, y: 2)

                    Text(statusText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    metricChip(title: isLocked ? "locked" : "detect", value: isLocked ? "off" : "\(detectionCount)")
                    metricChip(title: "alive", value: "\(livingCount)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            Text(isLocked ? "tap empty or Esc to clear" : "tap an object to stick a face on it")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                .padding(.bottom, 28)
        }
        .allowsHitTesting(false)
    }

    private func metricChip(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        StatusHUD(detectionCount: 3, statusText: "tap an object to stick a face on it", livingCount: 1, isLocked: false)
    }
}
