import Foundation
import SwiftData
import UIKit
import Vision

/// What the assistant can do inside the app. The same tools are used by the on-device model and by Claude.
struct AgentToolDef {
    struct Param { var name: String; var type = "string"; var description: String; var required = false }
    var name: String
    var description: String
    var params: [Param] = []
    /// Asks the driver before running (deletes, ending a shift…).
    var needsConfirm = false

    /// JSON schema for the Claude Messages API.
    var claudeSchema: [String: Any] {
        var props: [String: Any] = [:]
        for p in params { props[p.name] = ["type": p.type, "description": p.description] }
        return ["name": name, "description": description,
                "input_schema": ["type": "object", "properties": props, "required": params.filter(\.required).map(\.name)]]
    }
}

@MainActor
enum AgentTools {
    static let instructions = """
    You are the assistant inside HGV Hours, an app lorry (HGV) drivers use for driving hours, breaks, rest, jobs, pay, vehicles and notes.
    You can read and change the driver's data with the tools. Use a tool whenever the driver asks you to do, add, change, find, cancel or delete something. \
    Call get_status before answering questions about hours, breaks, rest or pay. Dates are yyyy-MM-dd and times HH:mm (24h); "today" and "tomorrow" also work. \
    Jobs have short ids (6 characters) shown by list_jobs. If a photo's text is given, use it (delivery notes, booking sheets, receipts). \
    Keep answers short and practical, times as clock times. You're a planning aid, not legal advice — the tachograph and the operator's instructions are what count.
    """

    static let all: [AgentToolDef] = [
        .init(name: "get_status", description: "Current activity, driving/working time left, next break, rest deadlines, weekly limits, pay, vehicle and next job."),
        .init(name: "change_activity", description: "Record a new activity now, like the tacho mode switch.",
              params: [.init(name: "activity", description: "One of: start_shift, drive, other_work, poa, break, end_shift_daily_rest, end_shift_weekly_rest", required: true)]),
        .init(name: "set_task", description: "Label the current work, e.g. loading or waiting to unload.",
              params: [.init(name: "task", description: "One of: " + ActivitySubtype.allCases.map(\.rawValue).joined(separator: ", ") + ", none", required: true)]),
        .init(name: "list_jobs", description: "Planned jobs with their ids, times, stops and status.",
              params: [.init(name: "from_date", description: "First day (default today)"),
                       .init(name: "days", type: "integer", description: "How many days (default 7)")]),
        .init(name: "create_job", description: "Plan a job (shift) with optional stops.",
              params: [.init(name: "date", description: "Day of the job", required: true),
                       .init(name: "start", description: "Start time HH:mm", required: true),
                       .init(name: "end", description: "Planned finish HH:mm (default start + 10h)"),
                       .init(name: "company", description: "Customer or company"),
                       .init(name: "reference", description: "Job / run reference"),
                       .init(name: "notes", description: "Notes"),
                       .init(name: "stops", description: "Stops separated by ';', each like 'delivery: Tesco Daventry NN11 8XX at 08:30'. Kinds: collection, delivery, depot, fuel, parking, trailer, service, other")]),
        .init(name: "update_job", description: "Change a job's times or details.",
              params: [.init(name: "job_id", description: "Job id from list_jobs", required: true),
                       .init(name: "date", description: "New day"), .init(name: "start", description: "New start HH:mm"),
                       .init(name: "end", description: "New finish HH:mm"), .init(name: "company", description: "Company"),
                       .init(name: "reference", description: "Reference"), .init(name: "notes", description: "Notes (replaces)")]),
        .init(name: "add_stop", description: "Add a stop to a job.",
              params: [.init(name: "job_id", description: "Job id", required: true),
                       .init(name: "stop", description: "Like 'collection: DHL Northampton NN4 7PB at 06:00 ref 12345'", required: true)]),
        .init(name: "cancel_job", description: "Mark a job as cancelled (kept for the record).",
              params: [.init(name: "job_id", description: "Job id", required: true), .init(name: "reason", description: "Why")], needsConfirm: true),
        .init(name: "delete_job", description: "Delete a job permanently.",
              params: [.init(name: "job_id", description: "Job id", required: true)], needsConfirm: true),
        .init(name: "list_notes", description: "Titles of the driver's notes."),
        .init(name: "read_note", description: "Read a note.", params: [.init(name: "title", description: "Note title", required: true)]),
        .init(name: "create_note", description: "Write a new note.",
              params: [.init(name: "title", description: "Title", required: true), .init(name: "text", description: "Body", required: true)]),
        .init(name: "update_note", description: "Replace or add to a note's text.",
              params: [.init(name: "title", description: "Note title", required: true), .init(name: "text", description: "Text", required: true),
                       .init(name: "append", type: "boolean", description: "true = add to the end")]),
        .init(name: "delete_note", description: "Delete a note.", params: [.init(name: "title", description: "Note title", required: true)], needsConfirm: true),
        .init(name: "log_fuel", description: "Record fuel, AdBlue or other supplies.",
              params: [.init(name: "kind", description: "diesel, petrol, adblue, gas, electricity, tachoRoll, oil or other", required: true),
                       .init(name: "quantity", type: "number", description: "Litres (or kWh / rolls)"),
                       .init(name: "cost", type: "number", description: "Total cost"),
                       .init(name: "location", description: "Where")]),
        .init(name: "add_reminder", description: "Set a reminder at a time.",
              params: [.init(name: "title", description: "What to remind", required: true),
                       .init(name: "date", description: "Day (default today)"), .init(name: "time", description: "HH:mm", required: true),
                       .init(name: "repeat", description: "once (default), daily, weekdays or weekly")]),
        .init(name: "list_vehicles", description: "Vehicles and trailers with registrations, heights and which is in use."),
        .init(name: "choose_vehicle", description: "Set the vehicle (unit) being driven.",
              params: [.init(name: "registration", description: "Registration or fleet number; empty for none", required: true)]),
        .init(name: "choose_trailer", description: "Set or change the trailer.",
              params: [.init(name: "registration", description: "Trailer registration or number; empty to drop it", required: true)]),
        .init(name: "card", description: "Mark the driver card inserted or withdrawn.",
              params: [.init(name: "inserted", type: "boolean", description: "true = inserted", required: true)]),
    ]

    static func def(_ name: String) -> AgentToolDef? { all.first { $0.name == name } }

    /// Runs a tool and returns a short result for the model. `confirm` asks the driver (true = go ahead).
    static func run(_ name: String, _ a: [String: String], context: ModelContext, store: SettingsStore,
                    status: () -> String, confirm: (String) async -> Bool) async -> String {
        let settings = store.settings
        switch name {
        case "get_status":
            return status()

        case "change_activity":
            let act = (a["activity"] ?? "").lowercased()
            let command: VoiceCommand? = switch act {
            case "start_shift": .startShift
            case "drive", "driving": .activity(.drive)
            case "other_work", "work": .activity(.otherWork)
            case "poa", "availability": .activity(.availability)
            case "break", "rest": .activity(.rest)
            case "end_shift_daily_rest", "end_shift": .endShift(.daily)
            case "end_shift_weekly_rest": .endShift(.weekly)
            default: nil
            }
            guard let command else { return "Unknown activity \(act)." }
            if case .endShift = command, !(await confirm("End your shift now and start \(act.contains("weekly") ? "weekly" : "daily") rest?")) {
                return "The driver chose not to end the shift."
            }
            ActivityController.perform(command, context: context, store: store)
            return command.confirmation

        case "set_task":
            let t = a["task"] ?? ""
            let sub = ActivitySubtype.allCases.first { $0.rawValue.lowercased() == t.lowercased() || $0.title.lowercased() == t.lowercased() }
            guard ActivityController.isOnShift(context: context) else { return "Not on a shift — start a shift first." }
            ActivityController.setSubtype(sub, context: context, settings: settings)
            return sub.map { "\($0.title) started." } ?? "Task label cleared."

        case "list_jobs":
            let from = day(a["from_date"]) ?? Calendar.hgv.startOfDay(for: .now)
            let days = Int(a["days"] ?? "") ?? 7
            let to = from.addingTimeInterval(Double(max(1, days)) * 86_400)
            let plans = fetch(WorkPlan.self, context).filter { $0.plannedStart >= from && $0.plannedStart < to }.sorted { $0.plannedStart < $1.plannedStart }
            if plans.isEmpty { return "No jobs planned from \(Fmt.day(from)) for \(days) days." }
            return plans.map(describe).joined(separator: "\n")

        case "create_job":
            guard let d = day(a["date"]), let start = time(a["start"], on: d) else { return "Need a date and a start time (HH:mm)." }
            var end = time(a["end"], on: d) ?? start.addingTimeInterval(10 * 3600)
            if end <= start { end = end.addingTimeInterval(86_400) }
            let plan = WorkPlan(start: start, end: end)
            plan.company = a["company"] ?? ""
            plan.reference = a["reference"] ?? ""
            plan.notes = a["notes"] ?? ""
            plan.vehicleID = settings.currentVehicleID
            plan.trailerID = settings.currentTrailerID
            plan.stops = (a["stops"] ?? "").split(separator: ";").map { parseStop(String($0)) }.filter { !$0.place.isEmpty }
            context.insert(plan)
            try? context.save()
            return "Job created: " + describe(plan)

        case "update_job":
            guard let plan = job(a["job_id"], context) else { return "No job with id \(a["job_id"] ?? "")." }
            let d = day(a["date"]) ?? Calendar.hgv.startOfDay(for: plan.plannedStart)
            let length = plan.plannedEnd.timeIntervalSince(plan.plannedStart)
            if let s = time(a["start"], on: d) ?? (a["date"] != nil ? time(Fmt.time(plan.plannedStart), on: d) : nil) {
                plan.plannedStart = s
                plan.plannedEnd = s.addingTimeInterval(length)
            }
            if var e = time(a["end"], on: d) {
                if e <= plan.plannedStart { e = e.addingTimeInterval(86_400) }
                plan.plannedEnd = e
            }
            if let v = a["company"] { plan.company = v }
            if let v = a["reference"] { plan.reference = v }
            if let v = a["notes"] { plan.notes = v }
            try? context.save()
            return "Updated: " + describe(plan)

        case "add_stop":
            guard let plan = job(a["job_id"], context) else { return "No job with id \(a["job_id"] ?? "")." }
            let stop = parseStop(a["stop"] ?? "")
            guard !stop.place.isEmpty else { return "Say where the stop is." }
            plan.stops = plan.stops + [stop]
            try? context.save()
            return "Stop added. " + describe(plan)

        case "cancel_job":
            guard let plan = job(a["job_id"], context) else { return "No job with id \(a["job_id"] ?? "")." }
            guard await confirm("Mark this job as cancelled?\n\(describe(plan))") else { return "The driver kept the job." }
            plan.cancelled = true
            plan.cancelledAt = .now
            plan.cancelReason = a["reason"] ?? ""
            try? context.save()
            EventRecorder.log(.note, title: "Job cancelled", detail: plan.company, context: context, settings: settings)
            return "Job cancelled."

        case "delete_job":
            guard let plan = job(a["job_id"], context) else { return "No job with id \(a["job_id"] ?? "")." }
            guard await confirm("Delete this job permanently?\n\(describe(plan))") else { return "The driver kept the job." }
            context.delete(plan)
            try? context.save()
            return "Job deleted."

        case "list_notes":
            let notes = fetch(NoteItem.self, context).filter { !$0.isTemplate }.sorted { $0.updatedAt > $1.updatedAt }
            return notes.isEmpty ? "No notes." : notes.prefix(40).map { "- \($0.title.isEmpty ? "(untitled)" : $0.title)\($0.isTable ? " [table]" : "")" }.joined(separator: "\n")

        case "read_note":
            guard let n = note(a["title"], context) else { return "No note called \(a["title"] ?? "")." }
            if n.isTable { return n.table.map { $0.joined(separator: " | ") }.joined(separator: "\n") }
            return String(n.body.prefix(3000))

        case "create_note":
            let n = NoteItem(title: a["title"] ?? "Note")
            n.body = a["text"] ?? ""
            context.insert(n)
            try? context.save()
            return "Note \"\(n.title)\" saved."

        case "update_note":
            guard let n = note(a["title"], context), !n.isTable else { return "No text note called \(a["title"] ?? "")." }
            let text = a["text"] ?? ""
            n.body = (a["append"] ?? "").lowercased() == "true" ? n.body + (n.body.isEmpty ? "" : "\n") + text : text
            n.updatedAt = .now
            try? context.save()
            return "Note updated."

        case "delete_note":
            guard let n = note(a["title"], context) else { return "No note called \(a["title"] ?? "")." }
            guard await confirm("Delete the note \"\(n.title)\"?") else { return "The driver kept the note." }
            context.delete(n)
            try? context.save()
            return "Note deleted."

        case "log_fuel":
            let kind = ResourceKind.allCases.first { $0.rawValue.lowercased() == (a["kind"] ?? "").lowercased() } ?? .diesel
            let log = ResourceLog(kind: kind)
            log.quantity = Double(a["quantity"] ?? "") ?? 0
            log.cost = Double(a["cost"] ?? "") ?? 0
            log.location = a["location"] ?? ""
            log.vehicleID = settings.currentVehicleID
            context.insert(log)
            try? context.save()
            EventRecorder.log(.fuel, title: kind.title, detail: log.quantity > 0 ? "\(Int(log.quantity))" : "", context: context, settings: settings)
            return "\(kind.title) logged."

        case "add_reminder":
            let d = day(a["date"]) ?? Calendar.hgv.startOfDay(for: .now)
            guard let t = time(a["time"], on: d) else { return "Need a time HH:mm." }
            let r = Reminder(title: a["title"] ?? "Reminder", trigger: .time)
            r.time = t
            r.repeatRule = ReminderRepeat(rawValue: (a["repeat"] ?? "once").lowercased()) ?? .once
            context.insert(r)
            try? context.save()
            ActivityController.refreshSideEffects(context: context, settings: settings)
            return "Reminder set for \(Fmt.dayTime(t))."

        case "list_vehicles":
            let vs = fetch(Vehicle.self, context)
            if vs.isEmpty { return "No vehicles saved." }
            return vs.map { v in
                let inUse = v.id.uuidString == settings.currentVehicleID || v.id.uuidString == settings.currentTrailerID
                return "- \(v.kind.title): \(v.displayName)\(v.height > 0 ? String(format: ", %.2f m high", v.height) : "")\(inUse ? " (in use)" : "")"
            }.joined(separator: "\n")

        case "choose_vehicle", "choose_trailer":
            let reg = (a["registration"] ?? "").uppercased().replacingOccurrences(of: " ", with: "")
            let trailer = name == "choose_trailer"
            let match = fetch(Vehicle.self, context).first {
                ($0.kind == .trailer) == trailer && !reg.isEmpty &&
                    ($0.registration.uppercased().replacingOccurrences(of: " ", with: "") == reg || $0.fleetNumber.uppercased() == reg)
            }
            if !reg.isEmpty && match == nil { return "No \(trailer ? "trailer" : "vehicle") \(reg) saved. Add it under Vehicles first." }
            let id = match?.id.uuidString ?? ""
            if trailer { VehicleLog.selectTrailer(id, context: context, store: store) } else { VehicleLog.select(id, context: context, store: store) }
            AutoDriveDetector.shared.update(settings: store.settings)
            return match.map { "\(trailer ? "Trailer" : "Vehicle") set to \($0.displayName)." } ?? "\(trailer ? "Trailer" : "Vehicle") cleared."

        case "card":
            let on = (a["inserted"] ?? "").lowercased() == "true"
            ActivityController.perform(on ? .cardIn : .cardOut, context: context, store: store)
            return on ? "Card marked inserted." : "Card marked withdrawn."

        default:
            return "Unknown tool \(name)."
        }
    }

    // MARK: Helpers

    private static func fetch<T: PersistentModel>(_ t: T.Type, _ context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    static func shortID(_ id: UUID) -> String { String(id.uuidString.prefix(6)).lowercased() }

    private static func job(_ id: String?, _ context: ModelContext) -> WorkPlan? {
        guard let id = id?.lowercased().trimmingCharacters(in: .whitespaces), !id.isEmpty else { return nil }
        return fetch(WorkPlan.self, context).first { shortID($0.id) == id || $0.id.uuidString.lowercased().hasPrefix(id) }
    }

    private static func note(_ title: String?, _ context: ModelContext) -> NoteItem? {
        let t = (title ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        let notes = fetch(NoteItem.self, context).filter { !$0.isTemplate }
        return notes.first { $0.title.lowercased() == t } ?? notes.first { !t.isEmpty && $0.title.lowercased().contains(t) }
    }

    static func describe(_ p: WorkPlan) -> String {
        var s = "[\(shortID(p.id))] \(Fmt.day(p.plannedStart)) \(Fmt.time(p.plannedStart))–\(Fmt.time(p.plannedEnd))"
        if !p.company.isEmpty { s += " \(p.company)" }
        if !p.reference.isEmpty { s += " ref \(p.reference)" }
        if p.cancelled { s += " (CANCELLED)" } else if p.completed { s += " (done)" }
        if !p.stops.isEmpty {
            s += "; stops: " + p.stops.map { "\($0.kind.rawValue) \($0.displayName)\($0.postcode.map { " \($0)" } ?? "")\($0.time.isEmpty ? "" : " at \($0.time)")" }
                .joined(separator: " → ")
        }
        return s
    }

    /// "delivery: Tesco Daventry NN11 8XX at 08:30 ref 123"
    static func parseStop(_ text: String) -> PlanStop {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var stop = PlanStop(kind: .delivery)
        if let colon = t.firstIndex(of: ":"), let k = PlanStop.Kind(rawValue: t[..<colon].trimmingCharacters(in: .whitespaces).lowercased()) {
            stop.kind = k
            t = String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        if let r = t.range(of: #"\s+ref(erence)?\s+(\S+)"#, options: [.regularExpression, .caseInsensitive]) {
            stop.reference = String(t[r]).components(separatedBy: .whitespaces).last ?? ""
            t.removeSubrange(r)
        }
        if let r = t.range(of: #"\s+at\s+(\d{1,2}[:.]\d{2}|\d{1,2}\s*(am|pm)|am|pm)\s*$"#, options: [.regularExpression, .caseInsensitive]) {
            stop.time = String(t[r]).replacingOccurrences(of: "at", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
            t.removeSubrange(r)
        }
        // UK postcode at the end.
        if let r = t.range(of: #"\s*,?\s*([A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2})\s*$"#, options: [.regularExpression, .caseInsensitive]) {
            stop.postcode = String(t[r]).trimmingCharacters(in: CharacterSet(charactersIn: " ,")).uppercased()
            t.removeSubrange(r)
        }
        stop.place = t.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        return stop
    }

    static func day(_ s: String?) -> Date? {
        guard let s = s?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else { return nil }
        let cal = Calendar.hgv
        let today = cal.startOfDay(for: .now)
        if s == "today" { return today }
        if s == "tomorrow" { return cal.date(byAdding: .day, value: 1, to: today) }
        if s == "yesterday" { return cal.date(byAdding: .day, value: -1, to: today) }
        for f in ["yyyy-MM-dd", "dd/MM/yyyy", "d/M/yyyy", "dd/MM/yy", "d MMM yyyy", "d MMMM yyyy"] {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_GB")
            df.timeZone = cal.timeZone
            df.dateFormat = f
            if let d = df.date(from: s) { return cal.startOfDay(for: d) }
        }
        return nil
    }

    static func time(_ s: String?, on day: Date) -> Date? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let parts = s.replacingOccurrences(of: ".", with: ":").split(separator: ":").compactMap { Int($0) }
        guard let h = parts.first, (0...23).contains(h) else { return nil }
        let m = parts.count > 1 ? parts[1] : 0
        return Calendar.hgv.date(bySettingHour: h, minute: min(59, max(0, m)), second: 0, of: day)
    }

    // MARK: Photos

    /// Reads printed text from a photo on the phone (Apple Vision, no network).
    nonisolated static func readText(from image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation)
            try? handler.perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
