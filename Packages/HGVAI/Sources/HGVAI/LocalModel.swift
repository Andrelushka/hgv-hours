import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// A model the driver can download and run on the phone.
public struct LocalModelOption: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var sizeMB: Int

    public static let all: [LocalModelOption] = [
        .init(id: "mlx-community/Qwen3.5-2B-4bit", title: "Qwen 3.5 2B (recommended)",
              detail: "Best at using the app's tools. Needs about 2 GB free memory.", sizeMB: 1_300),
        .init(id: "mlx-community/Qwen3-1.7B-4bit", title: "Qwen 3 1.7B (lighter)",
              detail: "A little faster on older iPhones.", sizeMB: 980),
        .init(id: "mlx-community/Qwen3-0.6B-4bit", title: "Qwen 3 0.6B (tiny)",
              detail: "Very fast, but makes more mistakes.", sizeMB: 350),
    ]
}

/// A tool the model may call: name, description and JSON-schema parameters, plus the app's handler.
public struct AgentTool: Sendable {
    public var name: String
    public var description: String
    /// JSON-schema "properties": name → (type, description).
    public var parameters: [(name: String, type: String, description: String, required: Bool)]

    public init(name: String, description: String, parameters: [(name: String, type: String, description: String, required: Bool)] = []) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    var spec: ToolSpec {
        var props: [String: any Sendable] = [:]
        for p in parameters { props[p.name] = ["type": p.type, "description": p.description] as [String: any Sendable] }
        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": props,
                    "required": parameters.filter(\.required).map(\.name),
                ] as [String: any Sendable],
            ] as [String: any Sendable],
        ]
    }
}

/// Loads one model and answers with it. All work happens on the phone.
@MainActor
public final class LocalModel {
    public static let shared = LocalModel()

    public private(set) var loadedID: String?
    private var container: ModelContainer?

    public enum Failure: LocalizedError {
        case notLoaded, simulator
        public var errorDescription: String? {
            switch self {
            case .notLoaded: "The on-device model isn't downloaded yet. Open Assistant settings to download it."
            case .simulator: "On-device AI needs a real iPhone (it uses the GPU)."
            }
        }
    }

    /// Set to keep downloads somewhere else (tests).
    nonisolated(unsafe) public static var cacheOverride: URL?

    /// Where downloaded models live (kept out of iCloud backups).
    static var cacheDirectory: URL {
        if let cacheOverride { return cacheOverride }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var url = dir
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return dir
    }

    /// Downloads (first time only) and loads a model. `progress` gets 0…1.
    public func load(_ id: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        #if targetEnvironment(simulator)
        throw Failure.simulator
        #else
        if loadedID == id, container != nil { return }
        container = nil
        loadedID = nil
        MLX.GPU.set(cacheLimit: 64 * 1024 * 1024)
        let hub = HubClient(cache: HubCache(cacheDirectory: Self.cacheDirectory))
        let c = try await loadModelContainer(
            from: #hubDownloader(hub),
            using: #huggingFaceTokenizerLoader(),
            configuration: ModelConfiguration(id: id, extraEOSTokens: ["<|im_end|>"]),
            progressHandler: { p in progress(min(0.99, p.fractionCompleted)) })
        container = c
        loadedID = id
        progress(1)
        #endif
    }

    /// Frees the model's memory (it stays downloaded).
    public func unload() {
        container = nil
        loadedID = nil
        MLX.GPU.clearCache()
    }

    /// Deletes downloaded model files.
    public func deleteDownloads() {
        unload()
        try? FileManager.default.removeItem(at: Self.cacheDirectory)
    }

    /// Megabytes of downloaded models on the phone.
    public static func downloadedMB() -> Int {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in e { total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        return total / 1_048_576
    }

    /// One conversation. Earlier turns are kept so follow-ups work.
    public func makeChat(instructions: String, tools: [AgentTool],
                         dispatch: @escaping @Sendable (_ name: String, _ arguments: [String: String]) async -> String) throws -> LocalChat {
        guard let container else { throw Failure.notLoaded }
        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: 700, temperature: 0.4, topP: 0.9),
            additionalContext: ["enable_thinking": false],
            tools: tools.map(\.spec),
            toolDispatch: { call in
                var args: [String: String] = [:]
                for (k, v) in call.function.arguments {
                    switch v.anyValue {
                    case let s as String: args[k] = s
                    case let n as NSNumber: args[k] = n.stringValue
                    case let other: args[k] = "\(other)"
                    }
                }
                return await dispatch(call.function.name, args)
            })
        return LocalChat(session: session)
    }
}

/// A running conversation with the on-device model.
public final class LocalChat: @unchecked Sendable {
    let session: ChatSession
    init(session: ChatSession) { self.session = session }

    /// Sends a message and returns the model's reply (tools are called along the way).
    public func send(_ text: String) async throws -> String {
        let raw = try await session.respond(to: text)
        return Self.clean(raw)
    }

    /// Removes any leftover reasoning tags.
    static func clean(_ s: String) -> String {
        var out = s
        while let a = out.range(of: "<think>"), let b = out.range(of: "</think>", range: a.upperBound..<out.endIndex) {
            out.removeSubrange(a.lowerBound..<b.upperBound)
        }
        return out.replacingOccurrences(of: "</think>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
