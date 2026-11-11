import SwiftUI

/// A basic calculator plus km ↔ miles and feet ↔ metres converters.
struct CalculatorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case calculator = "Calculator", distance = "km ↔ mi", height = "ft ↔ m"
        var id: String { rawValue }
    }

    @AppStorage("calculatorMode") private var modeRaw = Mode.calculator.rawValue

    var body: some View {
        let mode = Mode(rawValue: modeRaw) ?? .calculator
        VStack(spacing: 0) {
            Picker("Mode", selection: $modeRaw) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding()
            switch mode {
            case .calculator: CalculatorPad()
            case .distance:
                UnitConverterView(a: .init(name: "Kilometres", symbol: "km"), b: .init(name: "Miles", symbol: "mi"),
                                  factor: UnitConversion.milesPerKm, showFeetInches: false)
            case .height:
                UnitConverterView(a: .init(name: "Feet", symbol: "ft"), b: .init(name: "Metres", symbol: "m"),
                                  factor: UnitConversion.metresPerFoot, showFeetInches: true)
            }
        }
        .navigationTitle("Calculator")
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum UnitConversion {
    static let milesPerKm = 0.621_371_192
    static let metresPerFoot = 0.3048

    /// 4.88 → "16 ft 0 in" (rounded to the nearest inch).
    static func feetInches(_ feet: Double) -> String {
        guard feet.isFinite else { return "" }
        var totalInches = (abs(feet) * 12).rounded()
        let ft = Int(totalInches / 12)
        totalInches -= Double(ft * 12)
        return "\(feet < 0 ? "-" : "")\(ft) ft \(Int(totalInches)) in"
    }

    static func format(_ v: Double, digits: Int = 4) -> String {
        guard v.isFinite else { return "Error" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = digits
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    /// Accepts "1,234.5", "16'6", "16 6" (feet and inches) and plain numbers.
    static func parse(_ text: String, feetInches: Bool = false) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        if let v = Double(t) { return v }
        guard feetInches else { return nil }
        let parts = t.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "in", with: "")
            .replacingOccurrences(of: "ft", with: "'")
            .split(whereSeparator: { $0 == "'" || $0 == " " }).map(String.init)
        guard parts.count == 2, let ft = Double(parts[0]), let inch = Double(parts[1]) else { return nil }
        return ft + inch / 12
    }
}

// MARK: - Converter

struct UnitConverterView: View {
    struct Side { var name: String; var symbol: String }
    var a: Side
    var b: Side
    /// b = a × factor
    var factor: Double
    var showFeetInches: Bool

    @State private var aText = ""
    @State private var bText = ""
    @FocusState private var focus: Int?

    var body: some View {
        Form {
            Section {
                field(a, text: $aText, tag: 0)
                field(b, text: $bText, tag: 1)
            } footer: {
                Text(footer)
            }
            if showFeetInches, let ft = UnitConversion.parse(aText, feetInches: true) {
                Section("Feet and inches") {
                    LabeledContent("Height", value: UnitConversion.feetInches(ft))
                }
            }
            Section("Quick values") {
                ForEach(presets, id: \.self) { v in
                    Button {
                        aText = UnitConversion.format(v, digits: 2).replacingOccurrences(of: ",", with: "")
                        convert(from: 0)
                    } label: {
                        HStack {
                            Text("\(UnitConversion.format(v, digits: 2)) \(a.symbol)")
                            Spacer()
                            Text("\(UnitConversion.format(v * factor, digits: 2)) \(b.symbol)").foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("Clear") { aText = ""; bText = "" }
                Spacer()
                Button("Done") { focus = nil }
            }
        }
    }

    private var footer: String {
        showFeetInches
            ? "1 ft = 0.3048 m. You can type feet and inches like 16'6 or 16 6."
            : "1 km = 0.6214 mi · 1 mi = 1.6093 km"
    }

    private var presets: [Double] {
        showFeetInches ? [13, 14, 14.5, 15, 16, 16.5] : [1, 5, 10, 50, 100, 500]
    }

    private func field(_ side: Side, text: Binding<String>, tag: Int) -> some View {
        HStack {
            Text(side.name)
            Spacer()
            TextField("0", text: text)
                .keyboardType(tag == 0 && showFeetInches ? .numbersAndPunctuation : .decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.title3.monospacedDigit())
                .focused($focus, equals: tag)
                .onChange(of: text.wrappedValue) { _, _ in if focus == tag { convert(from: tag) } }
            Text(side.symbol).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
        }
    }

    private func convert(from tag: Int) {
        if tag == 0 {
            guard let v = UnitConversion.parse(aText, feetInches: showFeetInches) else { bText = ""; return }
            bText = UnitConversion.format(v * factor).replacingOccurrences(of: ",", with: "")
        } else {
            guard let v = UnitConversion.parse(bText) else { aText = ""; return }
            aText = UnitConversion.format(v / factor).replacingOccurrences(of: ",", with: "")
        }
    }
}

// MARK: - Calculator

/// Calculator state: a typed expression evaluated with normal operator precedence (× ÷ before + −).
struct CalcEngine: Equatable {
    enum Op: String { case add = "+", sub = "−", mul = "×", div = "÷" }
    enum Token: Equatable { case number(String), op(Op) }

    private(set) var tokens: [Token] = []
    /// Shown after "=" until the next key.
    private(set) var result: Double?

    var expression: String {
        tokens.map { t in
            switch t {
            case .number(let s): s
            case .op(let o): " \(o.rawValue) "
            }
        }.joined()
    }

    /// Live result of what's typed so far (ignores a trailing operator).
    var preview: Double? {
        var t = tokens
        if case .op = t.last { t.removeLast() }
        return Self.evaluate(t)
    }

    mutating func digit(_ d: String) {
        if result != nil { tokens = []; result = nil }
        if case .number(var s) = tokens.last {
            if d == "." && s.contains(".") { return }
            if s == "0" && d != "." { s = d } else if s == "-0" && d != "." { s = "-" + d } else { s += d }
            tokens[tokens.count - 1] = .number(s)
        } else {
            tokens.append(.number(d == "." ? "0." : d))
        }
    }

    mutating func op(_ o: Op) {
        if let r = result { tokens = [.number(Self.plain(r))]; result = nil }
        switch tokens.last {
        case .none: tokens = [.number("0"), .op(o)]
        case .op: tokens[tokens.count - 1] = .op(o)
        case .number: tokens.append(.op(o))
        }
    }

    mutating func equals() {
        guard let v = preview else { return }
        result = v
        tokens = [.number(Self.plain(v))]
    }

    mutating func toggleSign() {
        if let r = result { tokens = [.number(Self.plain(r))]; result = nil }
        guard case .number(let s) = tokens.last else { return }
        tokens[tokens.count - 1] = .number(s.hasPrefix("-") ? String(s.dropFirst()) : "-" + s)
    }

    /// Turns the last number into a percentage (of the number before it for + and −, like a pocket calculator).
    mutating func percent() {
        if let r = result { tokens = [.number(Self.plain(r))]; result = nil }
        guard case .number(let s) = tokens.last, let v = Double(s) else { return }
        var pct = v / 100
        if tokens.count >= 3, case .op(let o) = tokens[tokens.count - 2], o == .add || o == .sub,
           let base = Self.evaluate(Array(tokens.dropLast(2))) {
            pct = base * v / 100
        }
        tokens[tokens.count - 1] = .number(Self.plain(pct))
    }

    mutating func backspace() {
        if result != nil { clear(); return }
        guard let last = tokens.last else { return }
        switch last {
        case .op: tokens.removeLast()
        case .number(var s):
            s.removeLast()
            if s.isEmpty || s == "-" { tokens.removeLast() } else { tokens[tokens.count - 1] = .number(s) }
        }
    }

    mutating func clear() { tokens = []; result = nil }

    static func evaluate(_ tokens: [Token]) -> Double? {
        guard !tokens.isEmpty else { return nil }
        // First pass: × and ÷.
        var terms: [Double] = []
        var addOps: [Op] = []
        var pending: Op?
        for t in tokens {
            switch t {
            case .number(let s):
                guard let v = Double(s) else { return nil }
                if let p = pending, p == .mul || p == .div, let prev = terms.popLast() {
                    terms.append(p == .mul ? prev * v : prev / v)
                } else {
                    if let p = pending { addOps.append(p) }
                    terms.append(v)
                }
                pending = nil
            case .op(let o):
                pending = o
            }
        }
        guard var total = terms.first else { return nil }
        for (i, o) in addOps.enumerated() where i + 1 < terms.count {
            total = o == .add ? total + terms[i + 1] : total - terms[i + 1]
        }
        return total
    }

    /// A number as typed text, without a trailing ".0" and without float noise.
    static func plain(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        let rounded = (v * 1e10).rounded() / 1e10
        if rounded == rounded.rounded(), abs(rounded) < 1e15 { return String(Int64(rounded)) }
        return String(rounded)
    }

    static func display(_ v: Double?) -> String {
        guard let v else { return "0" }
        guard v.isFinite else { return "Error" }
        return UnitConversion.format((v * 1e10).rounded() / 1e10, digits: 8)
    }
}

struct CalculatorPad: View {
    @State private var engine = CalcEngine()

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(engine.result == nil ? engine.expression : "")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                Text(CalcEngine.display(engine.result ?? engine.preview))
                    .font(.system(size: 60, weight: .light, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .contentTransition(.numericText())
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal)
            .animation(.snappy, value: engine)

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    key(engine.tokens.isEmpty && engine.result == nil ? "AC" : "C", .gray) { engine.clear() }
                    key("±", .gray) { engine.toggleSign() }
                    key("%", .gray) { engine.percent() }
                    key("÷", .orange) { engine.op(.div) }
                }
                GridRow {
                    key("7") { engine.digit("7") }; key("8") { engine.digit("8") }; key("9") { engine.digit("9") }
                    key("×", .orange) { engine.op(.mul) }
                }
                GridRow {
                    key("4") { engine.digit("4") }; key("5") { engine.digit("5") }; key("6") { engine.digit("6") }
                    key("−", .orange) { engine.op(.sub) }
                }
                GridRow {
                    key("1") { engine.digit("1") }; key("2") { engine.digit("2") }; key("3") { engine.digit("3") }
                    key("+", .orange) { engine.op(.add) }
                }
                GridRow {
                    key("⌫", .secondary) { engine.backspace() }
                    key("0") { engine.digit("0") }
                    key(".") { engine.digit(".") }
                    key("=", .orange) { engine.equals() }
                }
            }
            .padding([.horizontal, .bottom])
        }
    }

    private func key(_ label: String, _ style: Color = Color(.secondarySystemFill), action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text(label)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(style == .gray ? Color(.systemGray4) : style == .secondary ? Color(.systemGray5) : style,
                            in: RoundedRectangle(cornerRadius: 18))
                .foregroundStyle(style == .orange ? .white : .primary)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: engine)
        .accessibilityLabel(label == "⌫" ? "Delete" : label)
    }
}

#Preview {
    NavigationStack { CalculatorView() }
}
