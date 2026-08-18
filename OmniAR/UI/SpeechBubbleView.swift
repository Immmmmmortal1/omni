import SwiftUI

/// Screen-space state for the line spoken by the pinned face.
struct LivingSpeech: Equatable {
    var text: String
    var screenPoint: CGPoint
    var isThinking: Bool
}

struct SpeechBubbleView: View {
    let speech: LivingSpeech

    var body: some View {
        content
            .frame(maxWidth: 240)
            .position(
                x: speech.screenPoint.x,
                y: max(56, speech.screenPoint.y - 78)
            )
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var content: some View {
        if speech.isThinking {
            ThinkingDots()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(bubbleBackground)
                .overlay(alignment: .bottom) { tail }
        } else {
            Text(speech.text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(bubbleBackground)
                .overlay(alignment: .bottom) { tail }
        }
    }

    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.55, blue: 0.75),
                                Color(red: 1.0, green: 0.78, blue: 0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    private var tail: some View {
        BubbleTail()
            .fill(.ultraThinMaterial)
            .frame(width: 18, height: 10)
            .offset(y: 9)
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct ThinkingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(phase == i ? 1.0 : 0.4))
                    .frame(width: 7, height: 7)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
    }
}
