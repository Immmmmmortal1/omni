import Foundation

/// Builds the DeepSeek prompt (object first-person, playful) and provides a local
/// fallback line so the feature never blocks or crashes when the network / key is missing.
enum SceneLine {

    static func isChinese(_ languageCode: String) -> Bool {
        languageCode.lowercased().hasPrefix("zh")
    }

    private static func languageName(for code: String) -> String {
        let lower = code.lowercased()
        if lower.hasPrefix("zh") { return "Simplified Chinese (简体中文)" }
        if lower.hasPrefix("ja") { return "Japanese" }
        if lower.hasPrefix("ko") { return "Korean" }
        if lower.hasPrefix("fr") { return "French" }
        if lower.hasPrefix("de") { return "German" }
        if lower.hasPrefix("es") { return "Spanish" }
        return "English"
    }

    static func systemPrompt(languageCode: String) -> String {
        let lang = languageName(for: languageCode)
        return """
        You are a playful cartoon face that has just been stuck onto a real-world object. \
        Speak exactly ONE short line in \(lang), in the FIRST PERSON as if you ARE that object — \
        witty, anthropomorphic, with an everyday-life vibe. \
        Output only that single line: no quotes, no explanation, no label, keep it under ~14 words.
        """
    }

    static func userPrompt(selected: String, others: [String]) -> String {
        let sel = COCOClasses.displayName(for: selected)
        let context = others
            .filter { $0 != selected }
            .map { COCOClasses.displayName(for: $0) }
        if context.isEmpty {
            return "You are this object: \(sel). Nothing else notable is around you."
        }
        return "You are this object: \(sel). Also visible in the same scene: \(context.joined(separator: ", "))."
    }

    /// Trim model output down to a single clean line without wrapping quotes.
    static func sanitize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine = text.split(whereSeparator: \.isNewline).first {
            text = String(firstLine).trimmingCharacters(in: .whitespaces)
        }
        let quotePairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'"), ("「", "」"), ("『", "』")]
        for (open, close) in quotePairs where text.count >= 2 && text.first == open && text.last == close {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    // MARK: - Local fallback

    static func fallback(selected: String, languageCode: String) -> String {
        let name = COCOClasses.displayName(for: selected)
        let pool = isChinese(languageCode) ? chinesePool(name: name) : englishPool(name: name)
        // Deterministic-ish pick so the same object doesn't feel random on retry.
        let index = abs(name.hashValue) % pool.count
        return pool[index]
    }

    private static func chinesePool(name: String) -> [String] {
        [
            "嘿，我可是这里最有个性的\(name)。",
            "别只顾着拍，快夸夸我这个\(name)。",
            "作为一个\(name)，我今天状态在线。",
            "我在这儿等你很久啦，看我一眼嘛。",
            "叮咚——你的专属\(name)已上线。"
        ]
    }

    private static func englishPool(name: String) -> [String] {
        [
            "Hey, I'm the coolest \(name) in the room.",
            "Don't just stare — say hi to your \(name)!",
            "As a \(name), I'm feeling pretty photogenic today.",
            "I've been waiting all day for you to notice me.",
            "Ding! Your friendly \(name) is now online."
        ]
    }
}
