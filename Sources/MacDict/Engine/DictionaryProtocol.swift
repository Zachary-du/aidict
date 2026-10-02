import Foundation

public enum ResultStatus: Equatable, Sendable {
    case idle
    case loading
    case success
    case failure(String)
}

public struct ExampleItem: Identifiable, Codable, Sendable, Hashable {
    public var id = UUID()
    public var text: String
    public var audioURL: String?

    public init(id: UUID = UUID(), text: String, audioURL: String? = nil) {
        self.id = id
        self.text = text
        self.audioURL = audioURL
    }

    enum CodingKeys: String, CodingKey {
        case text, audioURL
    }
}

public struct DefinitionItem: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var partOfSpeech: String
    public var meaning: String
    public var examples: [String] {
        get { exampleItems.map(\.text) }
        set { exampleItems = newValue.map { ExampleItem(text: $0) } }
    }
    public var exampleItems: [ExampleItem]

    public init(id: UUID = UUID(), partOfSpeech: String, meaning: String, examples: [String] = [], exampleItems: [ExampleItem]? = nil) {
        self.id = id
        self.partOfSpeech = partOfSpeech
        self.meaning = meaning
        if let items = exampleItems {
            self.exampleItems = items
        } else {
            self.exampleItems = examples.map { ExampleItem(text: $0) }
        }
    }

    enum CodingKeys: String, CodingKey {
        case partOfSpeech, meaning, examples, exampleItems
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.partOfSpeech = try container.decode(String.self, forKey: .partOfSpeech)
        self.meaning = try container.decode(String.self, forKey: .meaning)
        if let items = try? container.decode([ExampleItem].self, forKey: .exampleItems) {
            self.exampleItems = items
        } else if let strings = try? container.decode([String].self, forKey: .examples) {
            self.exampleItems = strings.map { ExampleItem(text: $0) }
        } else {
            self.exampleItems = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(partOfSpeech, forKey: .partOfSpeech)
        try container.encode(meaning, forKey: .meaning)
        try container.encode(exampleItems.map(\.text), forKey: .examples)
        try container.encode(exampleItems, forKey: .exampleItems)
    }
}

public struct DictionaryResult: Identifiable, Sendable {
    public var id: String { sourceId }
    public var sourceId: String
    public var sourceName: String
    public var word: String
    public var phonetic: String?       // US IPA
    public var phonetic_uk: String?    // UK IPA
    public var audioURL: String?       // US mp3
    public var audioURL_uk: String?    // UK mp3
    public var definitions: [DefinitionItem]
    public var rawText: String?
    public var aiAnalysis: String?
    public var tags: [String]
    public var status: ResultStatus

    public init(
        sourceId: String,
        sourceName: String,
        word: String,
        phonetic: String? = nil,
        phonetic_uk: String? = nil,
        audioURL: String? = nil,
        audioURL_uk: String? = nil,
        definitions: [DefinitionItem] = [],
        rawText: String? = nil,
        aiAnalysis: String? = nil,
        tags: [String] = [],
        status: ResultStatus = .idle
    ) {
        self.sourceId = sourceId
        self.sourceName = sourceName
        self.word = word
        self.phonetic = phonetic
        self.phonetic_uk = phonetic_uk
        self.audioURL = audioURL
        self.audioURL_uk = audioURL_uk
        self.definitions = definitions
        self.rawText = rawText
        self.aiAnalysis = aiAnalysis
        self.tags = tags
        self.status = status
    }
}

public protocol DictionarySource: Sendable {
    var id: String { get }
    var name: String { get }
    var icon: String { get }
    var priority: Int { get }

    func lookup(word: String, context: String?) async throws -> DictionaryResult
}
