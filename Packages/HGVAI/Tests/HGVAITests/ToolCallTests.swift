import Foundation
import HGVAI
import Testing

/// Loads the real model (downloads once) and checks it calls a tool with sensible arguments.
/// Opt-in: set HGVAI_LIVE=1 and HGVAI_CACHE to a folder.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["HGVAI_LIVE"] == "1"))
func modelCallsCreateJobTool() async throws {
    let env = ProcessInfo.processInfo.environment
    LocalModel.cacheOverride = URL(fileURLWithPath: env["HGVAI_CACHE"]!)
    let id = env["HGVAI_MODEL"] ?? "mlx-community/Qwen3.5-2B-4bit"
    let start = Date()
    try await LocalModel.shared.load(id) { _ in }
    print("Loaded \(id) in \(Int(Date().timeIntervalSince(start))) s")
    final class Box: @unchecked Sendable { var calls: [(String, [String: String])] = [] }
    let box = Box()
    let tools = [
        AgentTool(name: "get_status", description: "Driving time left, breaks and rest deadlines."),
        AgentTool(name: "create_job", description: "Plan a job (shift) with optional stops.", parameters: [
            (name: "date", type: "string", description: "Day yyyy-MM-dd, or today/tomorrow", required: true),
            (name: "start", type: "string", description: "Start time HH:mm", required: true),
            (name: "company", type: "string", description: "Customer", required: false),
            (name: "stops", type: "string", description: "Stops separated by ';', like 'delivery: Tesco Daventry NN11 8XX at 08:30'", required: false),
        ]),
    ]
    let chat = try LocalModel.shared.makeChat(
        instructions: "You are the assistant in an app for lorry drivers. Use the tools to change the driver's data. Today is Wednesday 11 November 2026.",
        tools: tools) { name, args in
            box.calls.append((name, args))
            return name == "create_job" ? "Job created [a1b2c3] 12 Nov 06:00 Tesco." : "Driving left 4h10, break due by 13:20."
        }
    let t0 = Date()
    let answer = try await chat.send("Add a job tomorrow at 6am for Tesco, delivering to Tesco Daventry NN11 8XX at 8:30.")
    print("Answer in \(Int(Date().timeIntervalSince(t0))) s: \(answer)")
    print("Calls: \(box.calls)")
    let job = box.calls.first { $0.0 == "create_job" }
    #expect(job != nil)
    #expect(job?.1["start"]?.hasPrefix("06") == true || job?.1["start"]?.hasPrefix("6") == true)
    #expect((job?.1["stops"] ?? "").localizedCaseInsensitiveContains("daventry"))
    let a2 = try await chat.send("How long can I drive?")
    print("Answer 2: \(a2) calls: \(box.calls.map(\.0))")
    #expect(box.calls.contains { $0.0 == "get_status" })
}
