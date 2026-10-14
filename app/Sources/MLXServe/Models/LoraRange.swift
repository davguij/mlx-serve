import Foundation

/// What one adapter's strength control offers. The server takes any finite
/// scale; this is only the slider's span and the field's sign, so a "regular"
/// LoRA cannot be pushed negative by accident and a slider LoRA gets the span
/// its author trained it for.
struct LoraRange: Codable, Equatable {
    var signed: Bool
    /// Slider half-range of a signed adapter (-bound...bound). A regular one always spans 0...2.
    var bound: Double

    /// Far past any published slider adapter (±20); only keeps a typo from overflowing bf16.
    static let limit = 100.0
    static let regularTop = 2.0
    static let defaultSignedBound = 2.0

    static let regular = LoraRange(signed: false, bound: regularTop)

    static func negatable(_ bound: Double = defaultSignedBound) -> LoraRange {
        LoraRange(signed: true, bound: bound)
    }

    /// A stored bound can be garbage (hand-edited defaults): fall back rather than build an empty slider.
    private var half: Double {
        guard signed else { return Self.regularTop }
        return bound.isFinite && bound > 0 ? min(Self.limit, bound) : Self.defaultSignedBound
    }

    var sliderRange: ClosedRange<Double> { signed ? -half...half : 0...half }

    var sliderStep: Double { half <= 5 ? 0.05 : 0.5 }

    /// The field takes far more than the slider shows, but a regular adapter never goes negative.
    func clamped(_ value: Double) -> Double {
        value.isNaN ? 0 : min(Self.limit, max(signed ? -Self.limit : 0, value))
    }
}

/// Picks a starting range for a LoRA nobody has set yet. A guess: a file carries
/// no strength range, so it reads the three places an author may have said so.
enum LoraRangeGuess {
    /// Signed when a name or the training metadata says "slider", or the description states a `-A to A` / `±A` range.
    static func guess(names: [String], description: String?) -> LoraRange {
        if let bound = description.flatMap(statedBound) { return .negatable(bound) }
        let isSlider = names.contains { $0.localizedCaseInsensitiveContains("slider") }
        return isSlider ? .negatable() : .regular
    }

    /// `-3 to 3`, `-1 and 1`, `±20`. The minus must not trail a digit or letter, so "0.6-1 to 1.2" is not a range.
    static func statedBound(_ description: String) -> Double? {
        let pattern = #"(?<![\w.])[-−–]\s*(\d+(?:\.\d+)?)\s*(?:to|and|or|~|–|—)\s*\+?(\d+(?:\.\d+)?)|±\s*(\d+(?:\.\d+)?)"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let text = description as NSString
        for m in re.matches(in: description, range: NSRange(location: 0, length: text.length)) {
            let numbers = (1...3).compactMap { i -> Double? in
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : Double(text.substring(with: r))
            }
            if let top = numbers.max(), top > 0 { return min(LoraRange.limit, top) }
        }
        return nil
    }

    /// Reads the adapter's own metadata and the Civitai / Stability Matrix sidecar beside it.
    static func detect(path: String) -> LoraRange {
        let url = URL(fileURLWithPath: path)
        var names = [url.deletingPathExtension().lastPathComponent]
        let metadata = safetensorsMetadata(path: path)
        for key in ["trainer", "concept_name", "modelspec.title", "title", "name", "ss_output_name"] {
            if let v = metadata[key] { names.append(v) }
        }
        var description: String?
        let sidecar = url.deletingPathExtension().appendingPathExtension("cm-info.json")
        if let data = try? Data(contentsOf: sidecar),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let n = json["ModelName"] as? String { names.append(n) }
            description = ["ModelDescription", "VersionDescription"]
                .compactMap { json[$0] as? String }
                .joined(separator: " ")
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        }
        return guess(names: names, description: description)
    }

    /// The header's `__metadata__` map: an 8-byte little-endian length, then JSON.
    static func safetensorsMetadata(path: String) -> [String: String] {
        guard let f = FileHandle(forReadingAtPath: path) else { return [:] }
        defer { try? f.close() }
        guard let lenData = try? f.read(upToCount: 8), lenData.count == 8 else { return [:] }
        let length = lenData.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian
        guard length > 0, length <= 64 << 20,
              let body = try? f.read(upToCount: Int(length)), body.count == Int(length),
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let meta = json["__metadata__"] as? [String: Any] else { return [:] }
        return meta.compactMapValues { $0 as? String }
    }
}

/// Ranges the user set by hand, keyed by adapter path, so a LoRA added again
/// (or in the other pane) comes back with the range that was chosen for it.
enum LoraRangeMemory {
    private static let key = "loraRangeOverrides"

    static func remembered(path: String, defaults: UserDefaults = .standard) -> LoraRange? {
        load(defaults)[path]
    }

    static func remember(_ range: LoraRange, path: String, defaults: UserDefaults = .standard) {
        var all = load(defaults)
        all[path] = range
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: key) }
    }

    /// What a newly attached adapter starts with: the user's choice, else the guess.
    static func resolve(path: String, defaults: UserDefaults = .standard) -> LoraRange {
        remembered(path: path, defaults: defaults) ?? LoraRangeGuess.detect(path: path)
    }

    private static func load(_ defaults: UserDefaults) -> [String: LoraRange] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: LoraRange].self, from: $0) } ?? [:]
    }
}
