import Foundation

/// COCO-ish class labels used by Apple's YOLOv3 Tiny Core ML models (80 classes).
enum COCOClasses {
    static let labels: [String] = [
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
        "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat", "dog",
        "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella",
        "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball", "kite",
        "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket", "bottle",
        "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich",
        "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
        "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse", "remote",
        "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator", "book",
        "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush",
    ]

    /// Class ids to exclude from "bring to life" (people are not inanimate objects).
    static let excludedLabels: Set<String> = ["person"]

    static func label(forIdentifier identifier: String) -> String {
        // Vision may return "label" or "LABEL" depending on model metadata.
        let cleaned = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let match = labels.first(where: { $0 == cleaned }) {
            return match
        }
        return cleaned
    }

    static func isExcluded(_ label: String) -> Bool {
        excludedLabels.contains(label.lowercased())
    }

    static func displayName(for label: String) -> String {
        let name = label.lowercased()
        guard !name.isEmpty else { return "object" }
        return name
    }
}
