import SwiftUI
import UIKit

/// Screen-space state for the transparent face decal glued onto the pinned object.
struct LivingCreature: Equatable {
    /// Track id — SwiftUI identity for one decal instance per pin.
    var id: UUID
    var screenPoint: CGPoint
    var sizePoints: CGFloat
    /// Picked once at pin time (1...7). Never changes for this pin — no refresh.
    var expressionIndex: Int
    var visible: Bool
}

/// Transparent static face sticker. Expression is chosen once when pinned and stays fixed.
/// Host fills the screen so `.position` matches `ARView.project` (full-bleed) coords.
struct CreatureOverlayView: View {
    let creature: LivingCreature

    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if let image = DecalLibrary.image(expressionIndex: creature.expressionIndex) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: creature.sizePoints, height: creature.sizePoints)
                        .position(x: creature.screenPoint.x, y: creature.screenPoint.y)
                        .opacity(creature.visible ? 1 : 0)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Bundled static expression PNGs: `decal_expr_01.png` … `decal_expr_07.png` (alpha).
enum DecalLibrary {
    private static var cache: [Int: UIImage] = [:]

    static var isBundled: Bool {
        image(expressionIndex: 1) != nil
    }

    static var expressionCount: Int { 7 }

    /// Uniform random expression index in `1...expressionCount`.
    static func randomExpressionIndex() -> Int {
        Int.random(in: 1...expressionCount)
    }

    static func image(expressionIndex: Int) -> UIImage? {
        let idx = max(1, min(expressionCount, expressionIndex))
        if let hit = cache[idx] { return hit }
        let name = String(format: "decal_expr_%02d", idx)
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        cache[idx] = image
        return image
    }
}
