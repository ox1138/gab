import Foundation

/// Resolves where the ggml Whisper model lives and which one is selected.
/// Models are found in two places: the user's Application Support dir (downloaded
/// via fetch-model.sh) and inside the app bundle's Resources (shipped with a
/// release build, so a fresh install works with no download).
enum ModelLocator {
    /// Preferred models, best first — used when the user hasn't picked one.
    static let preferred = ["ggml-large-v3-turbo.bin", "ggml-small.en.bin", "ggml-base.en.bin"]

    private static let selectionKey = "gab.selectedModel"

    struct Model: Equatable {
        let fileName: String
        let path: String
        let label: String
    }

    static func supportDir() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("gab", isDirectory: true).path
    }

    static func bundledDir() -> String? {
        Bundle.main.resourceURL?.path
    }

    /// Directories searched for models, in priority order (user copy wins).
    private static func searchDirs() -> [String] {
        [supportDir(), bundledDir()].compactMap { $0 }
    }

    /// Full path to a model filename if it exists in any search dir, else nil.
    static func find(_ fileName: String) -> String? {
        for dir in searchDirs() {
            let path = (dir as NSString).appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    /// Human label + rough cost for the menu.
    static func label(for fileName: String) -> String {
        switch fileName {
        case "ggml-large-v3-turbo.bin": return "Large v3 Turbo — accurate, ~1.5 GB"
        case "ggml-small.en.bin":       return "Small English — balanced, ~465 MB"
        case "ggml-base.en.bin":        return "Base English — fast, ~150 MB"
        case "ggml-large-v3.bin":       return "Large v3 — slow, ~3 GB"
        case "ggml-tiny.en.bin":        return "Tiny English — fastest, ~75 MB"
        default:
            return fileName
                .replacingOccurrences(of: "ggml-", with: "")
                .replacingOccurrences(of: ".bin", with: "")
        }
    }

    /// All ggml-*.bin models present across search dirs, deduped, best-known first.
    static func available() -> [Model] {
        var seen = Set<String>()
        var found: [String] = []
        for dir in searchDirs() {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for name in names where name.hasPrefix("ggml-") && name.hasSuffix(".bin") {
                if seen.insert(name).inserted { found.append(name) }
            }
        }
        let sorted = found.sorted { a, b in
            let ia = preferred.firstIndex(of: a) ?? Int.max
            let ib = preferred.firstIndex(of: b) ?? Int.max
            return ia != ib ? ia < ib : a < b
        }
        return sorted.compactMap { name in
            guard let path = find(name) else { return nil }
            return Model(fileName: name, path: path, label: label(for: name))
        }
    }

    /// Persisted user choice (filename), if any.
    static var selectedFileName: String? {
        get { UserDefaults.standard.string(forKey: selectionKey) }
        set { UserDefaults.standard.set(newValue, forKey: selectionKey) }
    }

    /// The model gab should load: env override > saved selection > auto-preferred.
    static func modelPath() -> String {
        if let override = ProcessInfo.processInfo.environment["GAB_MODEL"], !override.isEmpty {
            return override
        }
        if let chosen = selectedFileName, let path = find(chosen) {
            return path
        }
        for name in preferred {
            if let path = find(name) { return path }
        }
        // Fall back to the best name in support dir even if missing, for a useful error.
        return (supportDir() as NSString).appendingPathComponent(preferred.first!)
    }
}
