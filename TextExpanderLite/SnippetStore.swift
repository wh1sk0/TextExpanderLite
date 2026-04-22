import Foundation

struct Snippet: Codable, Identifiable, Equatable {
    let id: UUID
    var label: String
    var abbreviation: String
    var content: String
    var enabled: Bool
    var group: String

    init(id: UUID = UUID(), label: String, abbreviation: String, content: String, enabled: Bool, group: String = "General") {
        self.id = id
        self.label = label
        self.abbreviation = abbreviation
        self.content = content
        self.enabled = enabled
        self.group = group
    }

    enum CodingKeys: String, CodingKey {
        case id, label, abbreviation, content, enabled, group
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        self.abbreviation = try container.decodeIfPresent(String.self, forKey: .abbreviation) ?? ""
        self.content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.group = try container.decodeIfPresent(String.self, forKey: .group) ?? "General"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(abbreviation, forKey: .abbreviation)
        try container.encode(content, forKey: .content)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(group, forKey: .group)
    }
}

final class SnippetStore {
    static let shared = SnippetStore()

    private(set) var snippets: [Snippet] = []
    private let fileURL: URL

    var maxAbbreviationLength: Int {
        snippets.map { $0.abbreviation.count }.max() ?? 0
    }

    var abbreviationPrefixes: Set<String> {
        var prefixes: Set<String> = []
        for snippet in snippets where snippet.enabled {
            var current = ""
            for character in snippet.abbreviation {
                current.append(character)
                prefixes.insert(current)
            }
        }
        return prefixes
    }

    private init() {
        self.fileURL = SnippetStore.defaultFileURL()
        ensureFileExists()
        reload()
    }

    func expansion(for abbreviation: String) -> String? {
        snippets.first { $0.enabled && $0.abbreviation == abbreviation }?.content
    }

    func reload() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            snippets = try decoder.decode([Snippet].self, from: data)
        } catch {
            snippets = SnippetStore.defaultSnippets()
        }
    }

    func updateSnippets(_ newSnippets: [Snippet]) {
        snippets = newSnippets
        _ = save()
    }

    func loadRawJSON() throws -> String {
        ensureFileExists()
        let data = try Data(contentsOf: fileURL)
        return String(decoding: data, as: UTF8.self)
    }

    func loadFolderURL() -> URL {
        fileURL.deletingLastPathComponent()
    }

    func writeRawJSON(_ raw: String) throws {
        let data = Data(raw.utf8)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode([Snippet].self, from: data)
        snippets = decoded
        _ = save()
    }

    @discardableResult
    func save() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snippets)
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private func ensureFileExists() {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return
        }

        snippets = SnippetStore.defaultSnippets()
        _ = save()
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TextExpanderLite", isDirectory: true)
            .appendingPathComponent("snippets.json")
    }

    private static func defaultSnippets() -> [Snippet] {
        [
            Snippet(label: "Signature", abbreviation: ";sig", content: "Best,\nNick", enabled: true, group: "General"),
            Snippet(label: "Email", abbreviation: ";email", content: "nick@example.com", enabled: true, group: "General"),
            Snippet(label: "Address", abbreviation: ";addr", content: "123 Main St, Springfield", enabled: true, group: "General")
        ]
    }
}
