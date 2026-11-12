import Foundation
import Security

/// Stores the Anthropic API key in the iPhone Keychain (never in settings, backups or logs).
enum KeychainKey {
    private static let service = "com.andreikotlyarenko.hgvhours.anthropic"
    private static let account = "api-key"

    static func save(_ key: String) {
        delete()
        guard !key.isEmpty else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecValueData as String: Data(key.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }

    static var hasKey: Bool { load()?.isEmpty == false }
}

/// Stores the optional DVLA Vehicle Enquiry API key in the Keychain.
enum DVLAKey {
    private static let service = "com.andreikotlyarenko.hgvhours.dvla"

    static func save(_ key: String) {
        delete()
        guard !key.isEmpty else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: "api-key", kSecValueData as String: Data(key.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: "api-key", kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }

    static var hasKey: Bool { load()?.isEmpty == false }
}

/// Everything the assistant knows about your day, as plain facts.
struct AssistantFacts {
    var now: Date
    var region: RuleRegion
    var dash: Dashboard
    var status: ComplianceStatus
    var world: WorldStatus?
    var weekPay: Double
    var currency: String
    var nextPlan: WorkPlan?
    var vehicleHeight: Double
    var recentDays: [(day: Date, drive: TimeInterval, work: TimeInterval)]

    /// Compact summary sent to Claude (and handy for debugging).
    var summary: String {
        var lines: [String] = []
        lines.append("Now: \(now.formatted(date: .complete, time: .shortened))")
        lines.append("Rules: \(region.title)")
        lines.append("Status: \(dash.statusTitle) since \(Fmt.time(dash.since)); on shift: \(dash.onShift ? "yes" : "no"); driver card: \(dash.cardInserted ? "inserted" : "not inserted")")
        if dash.onShift {
            lines.append("Driving left: \(Fmt.hm(dash.driveLeft)) (\(dash.driveLeftReason)). Working time left: \(Fmt.hm(dash.workLeft)) (\(dash.workLeftReason)).")
            if let by = dash.breakBy { lines.append("Next break: \(Fmt.hm(dash.breakLength)) by \(Fmt.time(by)) (\(dash.breakReason) rule).") }
            if let r = dash.dailyRestRegularBy { lines.append("Start 11h daily rest by \(Fmt.time(r)); latest (9h reduced) by \(dash.restBy.map(Fmt.time) ?? "—").") }
        } else if dash.hasData {
            lines.append("Resting for \(Fmt.hm(dash.restLength)).")
        }
        if let n = dash.nextStart { lines.append("Earliest next shift start: \(Fmt.dayTime(n)).") }
        if region.isEuropean {
            lines.append("Today driven: \(Fmt.hm(status.stats.euDriving)) of \(Fmt.hm(status.dailyDrivingLimit)). 10h driving days left this week: \(dash.tenHourDaysLeft) of 2. Reduced 9h rests (15h days) left: \(dash.reducedRestsLeft) of 3.")
            lines.append("This week: driving \(Fmt.hm(status.weeklyDriving)) of 56h; fortnight \(Fmt.hm(status.weeklyDriving + status.previousWeekDriving)) of 90h; working \(Fmt.hm(status.weeklyWorkingTime)) of 60h; \(status.averageWeeks)-week average \(Fmt.hm(status.averageWeeklyWorkingTime)) of 48h.")
            if let w = status.weeklyRestDueBy { lines.append("Weekly rest due by \(Fmt.dayTime(w))\(status.nextWeeklyMustBeRegular ? " (must be regular 45h)" : "").") }
            if status.compensationOwed > 0 { lines.append("Weekly rest compensation owed: \(Fmt.hm(status.compensationOwed)).") }
        }
        if let world {
            for l in world.limits { lines.append("\(l.title): \(Fmt.hm(l.used)) used of \(Fmt.hm(l.limit)).") }
        }
        if !status.warnings.isEmpty { lines.append("Warnings: " + status.warnings.map(\.title).joined(separator: "; ")) }
        if !status.recentInfringements.isEmpty { lines.append("Infringements last 28 days: " + status.recentInfringements.prefix(5).map(\.title).joined(separator: "; ")) }
        lines.append("Earned today: \(Fmt.money(dash.earnedShift, symbol: currency)); this week: \(Fmt.money(weekPay, symbol: currency)).")
        if vehicleHeight > 0 { lines.append("Vehicle height: \(Fmt.length(vehicleHeight, feet: true)).") }
        if let p = nextPlan {
            lines.append("Next planned shift: \(Fmt.dayTime(p.plannedStart))–\(Fmt.time(p.plannedEnd)) \(p.company)\(p.stops.isEmpty ? "" : ", stops: " + p.stops.map(\.place).joined(separator: " → ")).")
        }
        if !recentDays.isEmpty {
            lines.append("Last 7 days (drive/work): " + recentDays.map { "\($0.day.formatted(.dateTime.weekday(.abbreviated))) \(Fmt.hm($0.drive))/\(Fmt.hm($0.work))" }.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}

/// Answers common questions from your live data, offline and free.
enum OfflineAssistant {
    static let suggestions = [
        "How long can I drive?", "When is my next break?", "When must I start my rest?",
        "When can I start tomorrow?", "Can I do a 15-hour day?", "How much have I earned this week?",
        "When is my weekly rest due?", "What's my vehicle height?"
    ]

    /// nil when the question isn't one it knows.
    static func answer(_ question: String, _ f: AssistantFacts) -> String? {
        let q = question.lowercased()
        let d = f.dash
        func has(_ words: String...) -> Bool { words.contains { q.contains($0) } }

        if has("height", "how high", "bridge") {
            return f.vehicleHeight > 0 ? "Your vehicle is \(Fmt.length(f.vehicleHeight, feet: true)) high (highest of your current vehicle and trailer)."
                : "No height saved for your current vehicle. Add it in Settings → Vehicles & trailers."
        }
        if has("earn", "pay", "money", "wage", "£") {
            return "Earned today: \(Fmt.money(d.earnedShift, symbol: f.currency)). This week so far: \(Fmt.money(f.weekPay, symbol: f.currency)). Tap the pay card on Today for the full breakdown and an estimate for the week."
        }
        if has("weekly rest") {
            guard f.region.isEuropean, let due = f.status.weeklyRestDueBy else { return "No weekly rest deadline yet — it starts counting after your first weekly rest is recorded." }
            return "Your weekly rest must start by \(Fmt.dayTime(due)).\(f.status.nextWeeklyMustBeRegular ? " It must be a regular 45-hour rest." : " It can be a reduced 24h rest or a regular 45h rest.")"
        }
        if has("15", "fifteen", "extend", "10 hour", "10h", "ten hour", "reduced") {
            guard f.region.isEuropean else { return "10h driving days and 15h days are European rules; your rules (\(f.region.title)) work differently — see the Hours tab." }
            return "15-hour days (using a 9h reduced rest) left before your weekly rest: \(d.reducedRestsLeft) of 3. 10-hour driving days left this week: \(d.tenHourDaysLeft) of 2."
        }
        if has("tomorrow", "next shift", "start again", "can i start") {
            guard let n = d.nextStart else { return "Start a shift or rest first and I'll work out when you can start again." }
            return d.onShift ? "If you stop now, the earliest you can start your next shift is \(Fmt.dayTime(n))." : "You can start your next shift from \(Fmt.dayTime(n))."
        }
        if has("rest", "finish", "stop work", "end my shift") {
            if let r = d.dailyRestRegularBy {
                return "Start your 11h daily rest by \(Fmt.time(r))\(d.restBy.map { r != $0 ? ", or a 9h reduced rest by \(Fmt.time($0)) at the latest" : "" } ?? "")."
            }
            return d.onShift ? "No rest deadline yet." : "You're resting now — \(Fmt.hm(d.restLength)) so far."
        }
        if has("break") {
            guard d.onShift else { return "You're not on a shift." }
            if let by = d.breakBy { return "Take \(Fmt.hm(d.breakLength)) by \(Fmt.time(by)) (the \(d.breakReason) rule)." }
            return "Your next break is due in \(Fmt.hm(d.breakDueIn))."
        }
        if has("drive", "driving") {
            guard d.onShift else { return d.hasData ? "You're off duty. Start a shift and I'll count down your driving." : "Start a shift and I'll count down your driving." }
            return "You can drive \(Fmt.hm(d.driveLeft)) before your next break (\(d.driveLeftReason)). Driving left today: \(Fmt.hm(f.status.drivingLeftToday))."
        }
        if has("work", "working time") {
            return d.onShift ? "Working time left: \(Fmt.hm(d.workLeft)) (\(d.workLeftReason))." : "You're not on a shift."
        }
        if has("infringe", "fine", "broke", "violation") {
            let list = f.status.recentInfringements
            return list.isEmpty ? "No infringements in the last 28 days. 👍" : "\(list.count) in the last 28 days: " + list.prefix(5).map { "\($0.title) (\($0.date.map(Fmt.day) ?? ""))" }.joined(separator: "; ") + "."
        }
        if has("poa", "availability") {
            return "POA (period of availability) is waiting time you know about in advance — e.g. waiting to be tipped, or riding as the second driver. It isn't driving, a break or working time, but it does count towards your shift length."
        }
        if has("card") {
            return d.cardInserted ? "Your driver card is marked as inserted." : "Your driver card is marked as not inserted — tap the red card button on Today when you put it in."
        }
        return nil
    }
}

/// Calls Claude (Anthropic API) with your question and a summary of your data.
enum ClaudeAssistant {
    struct Reply { var text: String; var rawContent: Any }

    enum Failure: LocalizedError {
        case noKey, http(Int, String), refused, empty
        var errorDescription: String? {
            switch self {
            case .noKey: "Add your Anthropic API key in Assistant settings."
            case .http(let code, let msg): code == 401 ? "The API key was rejected. Check it in Assistant settings." : "Claude request failed (\(code)). \(msg)"
            case .refused: "Claude declined to answer that question."
            case .empty: "No answer came back. Try again."
            }
        }
    }

    static let model = "claude-opus-5-5"

    static let system = """
    You are the assistant inside HGV Hours, an app professional lorry (HGV/truck) drivers use to track driving hours, breaks, rest, working time, pay and jobs.
    Answer the driver's question using the data provided with each question, which comes from their own records. Be short and practical: a few sentences, plain language, times as clock times. Use the driver's country rules shown in the data. If the data doesn't contain what's needed, say what's missing instead of guessing. You are a planning aid, not legal advice: when something is close to a legal limit, say so plainly and remind them the tachograph and their operator's instructions are what count.
    """

    /// Agent mode: Claude can call the app's tools (jobs, notes, activities, vehicles…) until it has an answer.
    /// `history` is updated with the whole exchange.
    static func agent(_ text: String, history: inout [[String: Any]],
                      run: (String, [String: String]) async -> String) async throws -> String {
        guard let key = KeychainKey.load(), !key.isEmpty else { throw Failure.noKey }
        var messages = history
        messages.append(["role": "user", "content": text])
        let tools = AgentTools.all.map(\.claudeSchema)
        for _ in 0..<8 {
            let body: [String: Any] = [
                "model": model, "max_tokens": 4000, "system": AgentTools.instructions + "\nToday is \(Date.now.formatted(date: .complete, time: .shortened)).",
                "messages": messages, "tools": tools, "fallbacks": "default"
            ]
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.httpMethod = "POST"
            req.timeoutInterval = 120
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
            req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard code == 200 else { throw Failure.http(code, (json["error"] as? [String: Any])?["message"] as? String ?? "") }
            let stop = json["stop_reason"] as? String
            if stop == "refusal" { throw Failure.refused }
            let content = json["content"] as? [[String: Any]] ?? []
            messages.append(["role": "assistant", "content": content])
            let calls = content.filter { $0["type"] as? String == "tool_use" }
            if stop == "tool_use", !calls.isEmpty {
                var results: [[String: Any]] = []
                for call in calls {
                    let name = call["name"] as? String ?? ""
                    let input = call["input"] as? [String: Any] ?? [:]
                    var args: [String: String] = [:]
                    for (k, v) in input { args[k] = (v as? String) ?? "\(v)" }
                    let out = await run(name, args)
                    results.append(["type": "tool_result", "tool_use_id": call["id"] as? String ?? "", "content": out])
                }
                messages.append(["role": "user", "content": results])
                continue
            }
            history = messages
            let answer = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
            guard !answer.isEmpty else { throw Failure.empty }
            return answer
        }
        history = messages
        return "Done."
    }

    /// `history` is the earlier conversation as API messages (assistant turns keep their full content unchanged).
    static func ask(_ question: String, facts: AssistantFacts, history: [[String: Any]]) async throws -> Reply {
        guard let key = KeychainKey.load(), !key.isEmpty else { throw Failure.noKey }
        var messages = history
        messages.append(["role": "user", "content": "My data right now:\n\(facts.summary)\n\nQuestion: \(question)"])
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "messages": messages,
            // If the request is declined by a safety classifier, let the API retry on a suitable model.
            "fallbacks": "default"
        ]
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard code == 200 else {
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? ""
            throw Failure.http(code, msg)
        }
        if json["stop_reason"] as? String == "refusal" { throw Failure.refused }
        let content = json["content"] as? [[String: Any]] ?? []
        let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        guard !text.isEmpty else { throw Failure.empty }
        return Reply(text: text, rawContent: content)
    }
}
