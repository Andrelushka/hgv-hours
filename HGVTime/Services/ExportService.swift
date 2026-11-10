import UIKit

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdfTimesheet = "PDF timesheet"
    case csvShifts = "CSV – shifts"
    case csvActivities = "CSV – activities"
    var id: String { rawValue }
}

enum ExportService {

    static func export(format: ExportFormat, from: Date, to: Date, entries: [EntrySnapshot],
                       nightOuts: [Date], settings: AppSettings, includePay: Bool,
                       payItems: [PayItemSnapshot] = []) throws -> URL {
        let now = Date()
        let analysis = RulesEngine.analyze(entries, now: now, config: settings.ruleConfig)
        let cal = Calendar.hgv
        let rangeStart = cal.startOfDay(for: from)
        let rangeEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: to)) ?? to
        let shifts = analysis.shifts.filter { $0.period.start >= rangeStart && $0.period.start < rangeEnd }
        let stamp = "\(Fmt.isoDate(rangeStart))_to_\(Fmt.isoDate(to))"
        let directory = FileManager.default.temporaryDirectory

        switch format {
        case .csvShifts:
            let url = directory.appendingPathComponent("HGV-shifts_\(stamp).csv")
            try shiftsCSV(shifts).write(to: url, atomically: true, encoding: .utf8)
            return url
        case .csvActivities:
            let url = directory.appendingPathComponent("HGV-activities_\(stamp).csv")
            let segments = analysis.segments.filter { $0.end > rangeStart && $0.start < rangeEnd }
            try activitiesCSV(segments).write(to: url, atomically: true, encoding: .utf8)
            return url
        case .pdfTimesheet:
            let url = directory.appendingPathComponent("HGV-timesheet_\(stamp).pdf")
            let weeks = analysis.weeks.filter { week in
                guard let end = cal.date(byAdding: .day, value: 7, to: week.weekStart) else { return false }
                return end > rangeStart && week.weekStart < rangeEnd
            }
            let data = pdf(weeks: weeks, shiftsInRange: shifts, allShifts: analysis.shifts, nightOuts: nightOuts, payItems: payItems, settings: settings,
                           includePay: includePay, rangeStart: rangeStart, rangeEnd: rangeEnd)
            try data.write(to: url)
            return url
        }
    }

    // MARK: CSV

    private static func csvField(_ value: String) -> String {
        value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
            ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : value
    }

    static func shiftsCSV(_ shifts: [ShiftSummary]) -> String {
        var rows = ["Date,Start,Finish,Driving (h),Other work (h),POA (h),Breaks (h),Working time (h),Rest after,Rest after (h),Multi-manned,Infringements"]
        for shift in shifts {
            let st = shift.stats
            let fields = [
                Fmt.isoDate(shift.period.start),
                Fmt.time(shift.period.start),
                shift.period.isOpen ? "open" : Fmt.time(shift.period.end),
                Fmt.decimalHours(st.allDriving),
                Fmt.decimalHours(st.otherWork),
                Fmt.decimalHours(st.availability),
                Fmt.decimalHours(st.breaks),
                Fmt.decimalHours(st.workingTime),
                shift.restKind?.rawValue ?? "",
                shift.period.restAfter.map { Fmt.decimalHours($0.duration) } ?? "",
                shift.period.multiManned ? "yes" : "no",
                shift.issues.map(\.title).joined(separator: "; ")
            ]
            rows.append(fields.map(csvField).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    static func activitiesCSV(_ segments: [Segment]) -> String {
        var rows = ["Start,End,Activity,Rules,Duration (h:mm),Duration (h),Multi-manned"]
        for seg in segments {
            let fields = [
                seg.start.formatted(.iso8601),
                seg.end.formatted(.iso8601),
                seg.kind.title,
                seg.regime.shortTitle,
                Fmt.hmCompact(seg.duration),
                Fmt.decimalHours(seg.duration),
                seg.multiManned ? "yes" : "no"
            ]
            rows.append(fields.map(csvField).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    // MARK: PDF

    private struct Column { let title: String; let width: CGFloat }

    private static func pdf(weeks: [WeekSummary], shiftsInRange: [ShiftSummary], allShifts: [ShiftSummary], nightOuts: [Date], payItems: [PayItemSnapshot], settings: AppSettings,
                            includePay: Bool, rangeStart: Date, rangeEnd: Date) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4
        let margin: CGFloat = 36
        let renderer = UIGraphicsPDFRenderer(bounds: page)

        let titleFont = UIFont.boldSystemFont(ofSize: 18)
        let headFont = UIFont.boldSystemFont(ofSize: 10)
        let bodyFont = UIFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .regular)
        let smallFont = UIFont.systemFont(ofSize: 7.5)
        let columns = [
            Column(title: "Date", width: 70), Column(title: "Start", width: 38), Column(title: "Finish", width: 38),
            Column(title: "Drive", width: 38), Column(title: "Other", width: 38), Column(title: "POA", width: 38),
            Column(title: "Breaks", width: 38), Column(title: "Work", width: 38), Column(title: "Rest after", width: 92),
            Column(title: "Issues", width: 75)
        ]

        return renderer.pdfData { ctx in
            var y: CGFloat = 0
            var pageNumber = 0

            func attrs(_ font: UIFont, _ color: UIColor = .black) -> [NSAttributedString.Key: Any] {
                [.font: font, .foregroundColor: color]
            }
            func footer() {
                let text = "Page \(pageNumber) · Generated \(Fmt.dayTime(Date())) by HGV Hours · Planning aid only — your tachograph and employer records are the legal record."
                (text as NSString).draw(at: CGPoint(x: margin, y: page.height - margin + 10), withAttributes: attrs(smallFont, .darkGray))
            }
            func newPage() {
                if pageNumber > 0 { footer() }
                ctx.beginPage()
                pageNumber += 1
                y = margin
            }
            func ensure(_ height: CGFloat) {
                if y + height > page.height - margin - 10 { newPage() }
            }
            func line(_ text: String, font: UIFont, color: UIColor = .black, height: CGFloat = 14) {
                ensure(height)
                (text as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: attrs(font, color))
                y += height
            }
            func row(_ values: [String], font: UIFont, fill: UIColor? = nil, color: UIColor = .black) {
                ensure(14)
                if let fill {
                    fill.setFill()
                    UIRectFill(CGRect(x: margin - 2, y: y - 1, width: page.width - margin * 2 + 4, height: 13))
                }
                var x = margin
                for (index, column) in columns.enumerated() where index < values.count {
                    let rect = CGRect(x: x, y: y, width: column.width - 3, height: 12)
                    (values[index] as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                                     attributes: attrs(font, color), context: nil)
                    x += column.width
                }
                y += 14
            }

            newPage()
            line("Driver timesheet", font: titleFont, height: 24)
            var who = [String]()
            if !settings.driverName.isEmpty { who.append("Driver: \(settings.driverName)") }
            if !settings.employer.isEmpty { who.append("Employer: \(settings.employer)") }
            if !settings.vehicleReg.isEmpty { who.append("Vehicle: \(settings.vehicleReg)") }
            if !who.isEmpty { line(who.joined(separator: "   "), font: headFont) }
            let lastDay = Calendar.hgv.date(byAdding: .day, value: -1, to: rangeEnd) ?? rangeEnd
            line("Period: \(Fmt.day(rangeStart)) – \(Fmt.day(lastDay)) \(Calendar.hgv.component(.year, from: lastDay))", font: headFont)
            line("Rules: \(settings.primaryRegime.title)\(settings.applyWorkingTime ? " + Road Transport (Working Time) Regulations" : "")", font: smallFont, color: .darkGray)
            y += 6

            for week in weeks {
                let shifts = week.shifts.filter { s in shiftsInRange.contains { $0.id == s.id } }
                ensure(60)
                y += 4
                line("Week commencing \(Fmt.day(week.weekStart))", font: headFont, height: 14)
                line("Driving \(Fmt.hm(week.allDriving))  ·  Fortnight (tacho) \(Fmt.hm(week.fortnightDriving)) / 90h  ·  Working time \(Fmt.hm(week.workingTime)) / 60h  ·  POA \(Fmt.hm(week.availability))",
                     font: smallFont, color: .darkGray, height: 12)
                row(columns.map(\.title), font: headFont, fill: UIColor(white: 0.9, alpha: 1))
                for shift in shifts {
                    let st = shift.stats
                    let rest: String
                    if let after = shift.period.restAfter, let kind = shift.restKind {
                        rest = "\(Fmt.hmCompact(after.duration)) \(kind.rawValue.replacingOccurrences(of: " rest", with: ""))"
                    } else {
                        rest = "—"
                    }
                    let flagged = !shift.issues.isEmpty
                    row([
                        Fmt.day(shift.period.start),
                        Fmt.time(shift.period.start),
                        shift.period.isOpen ? "open" : Fmt.time(shift.period.end),
                        Fmt.hmCompact(st.allDriving),
                        Fmt.hmCompact(st.otherWork),
                        Fmt.hmCompact(st.availability),
                        Fmt.hmCompact(st.breaks),
                        Fmt.hmCompact(st.workingTime),
                        rest,
                        flagged ? "\(shift.issues.count) issue\(shift.issues.count == 1 ? "" : "s")" : "OK"
                    ], font: bodyFont, color: flagged ? .systemRed : .black)
                }
                let totals = shifts.reduce(into: PeriodStats()) { acc, s in
                    acc.euDriving += s.stats.euDriving; acc.gbDriving += s.stats.gbDriving
                    acc.otherWork += s.stats.otherWork; acc.availability += s.stats.availability
                    acc.breaks += s.stats.breaks
                }
                row(["Total", "", "", Fmt.hmCompact(totals.allDriving), Fmt.hmCompact(totals.otherWork),
                     Fmt.hmCompact(totals.availability), Fmt.hmCompact(totals.breaks), Fmt.hmCompact(totals.workingTime), "", ""],
                    font: headFont, fill: UIColor(white: 0.95, alpha: 1))

                let issues = shifts.flatMap(\.issues) + week.issues
                for issue in issues {
                    line("• \(issue.date.map(Fmt.day) ?? "") — \(issue.title): \(issue.detail)", font: smallFont, color: .systemRed, height: 11)
                }

                if includePay {
                    let weekEnd = Calendar.hgv.date(byAdding: .day, value: 7, to: week.weekStart) ?? week.weekStart
                    let nights = nightOuts.filter { $0 >= week.weekStart && $0 < weekEnd }.count
                    let items = payItems.filter { $0.date >= week.weekStart && $0.date < weekEnd }
                    let pay = PayCalculator.calculate(shifts: shifts, nightOuts: nights, settings: settings.pay, items: items,
                                                      holidayDayValue: PayCalculator.averageDayPay(shifts: allShifts, before: week.weekStart, settings: settings.pay))
                    let symbol = settings.pay.currencySymbol
                    let parts: [String] = pay.lines.filter { !$0.isInfo }.map { l in
                        let hours = l.hours.map { String(format: " %.2fh", $0) } ?? ""
                        return l.label + hours + ": " + Fmt.money(l.amount, symbol: symbol)
                    }
                    line("Estimated gross pay \(Fmt.money(pay.total, symbol: symbol))  (\(parts.joined(separator: " · ")))",
                         font: smallFont, color: .darkGray, height: 12)
                }
            }

            y += 16
            line("Driver signature: ______________________     Date: ____________", font: headFont, height: 20)
            footer()
        }
    }
}
