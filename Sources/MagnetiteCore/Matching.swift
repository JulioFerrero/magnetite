import Foundation

struct SearchKey: Hashable {
    let text: [Character], wordStarts: [Int]
    init(_ raw: String) {
        let original = Array(raw), folded = Array(normalize(raw)), separators = Set(" -_.(/+")
        text = folded
        wordStarts = folded.indices.filter { i in
            !separators.contains(folded[i]) && (i == 0 || separators.contains(folded[i - 1])
                || (original.count == folded.count && original[i].isUppercase && original[i - 1].isLowercase)
                || folded[i].isNumber != folded[i - 1].isNumber)
        }
    }
    func score(_ query: [Character]) -> Double? {
        guard !query.isEmpty else { return nil }
        if text == query { return 1000 }
        if text.starts(with: query) { return 900 + 50 * Double(query.count) / Double(text.count) }
        if let n = wordStarts.enumerated().first(where: { $0.element > 0 && text[$0.element...].starts(with: query) })?.offset { return 800 - Double(n) }
        if query.count >= 2, wordStarts.map({ text[$0] }).starts(with: query) { return 750 }
        if let offset = text.indices.first(where: { text[$0...].starts(with: query) }) { return 600 - Double(offset) }
        let needle = query.filter { $0 != " " }, starts = Set(wordStarts)
        guard let first = needle.first, var previous = wordStarts.first(where: { text[$0] == first }) else { return nil }
        var score = 300.0
        for ch in needle.dropFirst() {
            guard let i = text[(previous + 1)...].firstIndex(of: ch) else { return nil }
            score += i == previous + 1 ? 12 : starts.contains(i) ? 8 : -2 * Double(min(i - previous, 10))
            previous = i
        }
        return max(score, 100)
    }
}

func normalize(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil) }
