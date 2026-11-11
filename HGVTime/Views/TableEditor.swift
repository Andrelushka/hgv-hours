import SwiftUI

/// Look of a notebook table: header and frozen rows/columns, colours and column widths.
struct TableStyle: Codable, Equatable {
    var headerRows = 1
    var headerCols = 0
    var frozenRows = 1
    var frozenCols = 0
    var rowColors: [String] = []
    var colColors: [String] = []
    var cellColors: [[String]] = []
    var colWidths: [Double] = []
}

/// Colours offered for rows, columns and cells.
enum TableColor: String, CaseIterable, Identifiable {
    case none = "", red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, gray
    var id: String { rawValue }
    var title: String { self == .none ? "No colour" : rawValue.capitalized }
    var color: Color? {
        switch self {
        case .none: nil
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }
}

/// Table cells plus style, with operations that keep everything lined up when rows or columns move.
struct TableDoc: Equatable {
    var cells: [[String]]
    var style: TableStyle

    static let defaultWidth = 110.0
    static let rowHeight: CGFloat = 40

    var rows: Int { cells.count }
    var cols: Int { cells.map(\.count).max() ?? 0 }

    init(cells: [[String]], style: TableStyle) {
        self.cells = cells.isEmpty ? [["", ""], ["", ""]] : cells
        self.style = style
        normalize()
    }

    mutating func normalize() {
        let c = max(1, cols)
        for i in cells.indices where cells[i].count < c { cells[i] += Array(repeating: "", count: c - cells[i].count) }
        if style.rowColors.count < rows { style.rowColors += Array(repeating: "", count: rows - style.rowColors.count) }
        if style.rowColors.count > rows { style.rowColors.removeLast(style.rowColors.count - rows) }
        if style.colColors.count < c { style.colColors += Array(repeating: "", count: c - style.colColors.count) }
        if style.colColors.count > c { style.colColors.removeLast(style.colColors.count - c) }
        if style.colWidths.count < c { style.colWidths += Array(repeating: Self.defaultWidth, count: c - style.colWidths.count) }
        if style.colWidths.count > c { style.colWidths.removeLast(style.colWidths.count - c) }
        if style.cellColors.count < rows { style.cellColors += Array(repeating: [], count: rows - style.cellColors.count) }
        if style.cellColors.count > rows { style.cellColors.removeLast(style.cellColors.count - rows) }
        for i in style.cellColors.indices {
            if style.cellColors[i].count < c { style.cellColors[i] += Array(repeating: "", count: c - style.cellColors[i].count) }
            if style.cellColors[i].count > c { style.cellColors[i].removeLast(style.cellColors[i].count - c) }
        }
        style.headerRows = min(max(0, style.headerRows), rows)
        style.frozenRows = min(max(0, style.frozenRows), rows)
        style.headerCols = min(max(0, style.headerCols), c)
        style.frozenCols = min(max(0, style.frozenCols), c)
    }

    func width(_ c: Int) -> CGFloat { CGFloat(style.colWidths.indices.contains(c) ? style.colWidths[c] : Self.defaultWidth) }

    func isHeader(row r: Int, col c: Int) -> Bool { r < style.headerRows || c < style.headerCols }

    /// Cell colour wins over column colour, which wins over row colour.
    func color(row r: Int, col c: Int) -> Color? {
        let cell = style.cellColors.indices.contains(r) && style.cellColors[r].indices.contains(c) ? style.cellColors[r][c] : ""
        if let x = TableColor(rawValue: cell)?.color { return x }
        if style.colColors.indices.contains(c), let x = TableColor(rawValue: style.colColors[c])?.color { return x }
        if style.rowColors.indices.contains(r), let x = TableColor(rawValue: style.rowColors[r])?.color { return x }
        return nil
    }

    // MARK: Rows

    mutating func insertRow(at r: Int) {
        let i = min(max(0, r), rows)
        cells.insert(Array(repeating: "", count: cols), at: i)
        style.rowColors.insert("", at: min(i, style.rowColors.count))
        style.cellColors.insert(Array(repeating: "", count: cols), at: min(i, style.cellColors.count))
        if i < style.headerRows { style.headerRows += 1 }
        if i < style.frozenRows { style.frozenRows += 1 }
        normalize()
    }

    mutating func deleteRow(_ r: Int) {
        guard rows > 1, cells.indices.contains(r) else { return }
        cells.remove(at: r)
        if style.rowColors.indices.contains(r) { style.rowColors.remove(at: r) }
        if style.cellColors.indices.contains(r) { style.cellColors.remove(at: r) }
        if r < style.headerRows { style.headerRows -= 1 }
        if r < style.frozenRows { style.frozenRows -= 1 }
        normalize()
    }

    mutating func moveRows(from: IndexSet, to: Int) {
        cells.move(fromOffsets: from, toOffset: to)
        style.rowColors.move(fromOffsets: from, toOffset: to)
        style.cellColors.move(fromOffsets: from, toOffset: to)
    }

    // MARK: Columns

    mutating func insertColumn(at c: Int) {
        let i = min(max(0, c), cols)
        for r in cells.indices { cells[r].insert(r == 0 && style.headerRows > 0 ? "Column \(cols + 1)" : "", at: min(i, cells[r].count)) }
        style.colColors.insert("", at: min(i, style.colColors.count))
        style.colWidths.insert(Self.defaultWidth, at: min(i, style.colWidths.count))
        for r in style.cellColors.indices { style.cellColors[r].insert("", at: min(i, style.cellColors[r].count)) }
        if i < style.headerCols { style.headerCols += 1 }
        if i < style.frozenCols { style.frozenCols += 1 }
        normalize()
    }

    mutating func deleteColumn(_ c: Int) {
        guard cols > 1 else { return }
        for r in cells.indices where cells[r].indices.contains(c) { cells[r].remove(at: c) }
        if style.colColors.indices.contains(c) { style.colColors.remove(at: c) }
        if style.colWidths.indices.contains(c) { style.colWidths.remove(at: c) }
        for r in style.cellColors.indices where style.cellColors[r].indices.contains(c) { style.cellColors[r].remove(at: c) }
        if c < style.headerCols { style.headerCols -= 1 }
        if c < style.frozenCols { style.frozenCols -= 1 }
        normalize()
    }

    mutating func moveColumns(from: IndexSet, to: Int) {
        for r in cells.indices { cells[r].move(fromOffsets: from, toOffset: to) }
        style.colColors.move(fromOffsets: from, toOffset: to)
        style.colWidths.move(fromOffsets: from, toOffset: to)
        for r in style.cellColors.indices { style.cellColors[r].move(fromOffsets: from, toOffset: to) }
    }

    static func columnName(_ c: Int) -> String {
        var n = c
        var s = ""
        repeat {
            s = String(UnicodeScalar(65 + n % 26)!) + s
            n = n / 26 - 1
        } while n >= 0
        return s
    }
}

/// Spreadsheet-style table with frozen rows/columns (they stay put while the rest scrolls).
struct TableGridEditor: View {
    @Binding var doc: TableDoc
    @Binding var selection: TableSelection?

    private let gutterW: CGFloat = 34
    private let gutterH: CGFloat = 26
    @State private var offset: CGPoint = .zero
    @FocusState private var focused: CellID?

    struct CellID: Hashable { var r: Int; var c: Int }

    var body: some View {
        let frozenW = (0..<doc.style.frozenCols).reduce(CGFloat(0)) { $0 + doc.width($1) }
        let frozenH = CGFloat(doc.style.frozenRows) * TableDoc.rowHeight
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Everything, scrolling both ways (frozen cells are drawn by the layers on top).
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(width: 1, height: gutterH)
                        ForEach(0..<doc.rows, id: \.self) { r in
                            HStack(spacing: 0) {
                                Color.clear.frame(width: gutterW, height: TableDoc.rowHeight)
                                ForEach(0..<doc.cols, id: \.self) { c in
                                    cell(r, c, live: r >= doc.style.frozenRows && c >= doc.style.frozenCols)
                                }
                            }
                        }
                    }
                    .padding(.trailing, 40)
                    .padding(.bottom, 80)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: TableOffsetKey.self, value: g.frame(in: .named("table")).origin)
                    })
                }
                .coordinateSpace(name: "table")
                .onPreferenceChange(TableOffsetKey.self) { offset = $0 }

                // Frozen rows: move sideways only.
                if doc.style.frozenRows > 0 {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<doc.style.frozenRows, id: \.self) { r in
                            HStack(spacing: 0) {
                                ForEach(0..<doc.cols, id: \.self) { c in cell(r, c, live: c >= doc.style.frozenCols) }
                            }
                        }
                    }
                    .offset(x: offset.x)
                    .frame(width: max(0, geo.size.width - gutterW), height: frozenH, alignment: .topLeading)
                    .clipped()
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 2)
                    .offset(x: gutterW, y: gutterH)
                    .zIndex(2)
                }
                // Frozen columns: move up and down only.
                if doc.style.frozenCols > 0 {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<doc.rows, id: \.self) { r in
                            HStack(spacing: 0) {
                                ForEach(0..<doc.style.frozenCols, id: \.self) { c in cell(r, c, live: r >= doc.style.frozenRows) }
                            }
                        }
                    }
                    .offset(y: offset.y)
                    .frame(width: frozenW, height: max(0, geo.size.height - gutterH), alignment: .topLeading)
                    .clipped()
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 2)
                    .offset(x: gutterW, y: gutterH)
                    .zIndex(3)
                }
                // Corner where frozen rows and columns meet.
                if doc.style.frozenRows > 0 && doc.style.frozenCols > 0 {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<doc.style.frozenRows, id: \.self) { r in
                            HStack(spacing: 0) { ForEach(0..<doc.style.frozenCols, id: \.self) { c in cell(r, c, live: true) } }
                        }
                    }
                    .offset(x: gutterW, y: gutterH)
                    .zIndex(4)
                }
                // Column letters (always visible).
                HStack(spacing: 0) {
                    ForEach(0..<doc.cols, id: \.self) { c in
                        let frozen = c < doc.style.frozenCols
                        columnHeader(c)
                            .offset(x: frozen ? -offset.x : 0)
                            .zIndex(frozen ? 1 : 0)
                    }
                }
                .offset(x: offset.x)
                .frame(width: max(0, geo.size.width - gutterW), height: gutterH, alignment: .topLeading)
                .clipped()
                .background(Color(.secondarySystemBackground))
                .offset(x: gutterW)
                .zIndex(5)
                // Row numbers (always visible).
                VStack(spacing: 0) {
                    ForEach(0..<doc.rows, id: \.self) { r in
                        let frozen = r < doc.style.frozenRows
                        rowHeader(r)
                            .offset(y: frozen ? -offset.y : 0)
                            .zIndex(frozen ? 1 : 0)
                    }
                }
                .offset(y: offset.y)
                .frame(width: gutterW, height: max(0, geo.size.height - gutterH), alignment: .topLeading)
                .clipped()
                .background(Color(.secondarySystemBackground))
                .offset(y: gutterH)
                .zIndex(5)
                Image(systemName: "tablecells")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(width: gutterW, height: gutterH)
                    .background(Color(.secondarySystemBackground))
                    .zIndex(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator)))
        .onChange(of: focused) { _, id in if let id { selection = .cell(id.r, id.c) } }
    }

    private func isSelected(_ r: Int, _ c: Int) -> Bool {
        switch selection {
        case .row(let x): x == r
        case .column(let x): x == c
        case .cell(let a, let b): a == r && b == c
        case nil: false
        }
    }

    /// One cell. `live` = editable here; otherwise a coloured placeholder (the editable copy is in a frozen layer).
    @ViewBuilder
    private func cell(_ r: Int, _ c: Int, live: Bool) -> some View {
        if live { liveCell(r, c) } else { Color(.systemBackground).frame(width: doc.width(c), height: TableDoc.rowHeight) }
    }

    @ViewBuilder
    private func liveCell(_ r: Int, _ c: Int) -> some View {
        let header = doc.isHeader(row: r, col: c)
        let tint = doc.color(row: r, col: c)
        TextField("", text: Binding(
            get: { doc.cells.indices.contains(r) && doc.cells[r].indices.contains(c) ? doc.cells[r][c] : "" },
            set: { if doc.cells.indices.contains(r) && doc.cells[r].indices.contains(c) { doc.cells[r][c] = $0 } }))
            .font(header ? .caption.weight(.bold) : .caption)
            .focused($focused, equals: CellID(r: r, c: c))
            .padding(.horizontal, 6)
            .frame(width: doc.width(c), height: TableDoc.rowHeight)
            .background {
                ZStack {
                    Color(.systemBackground)
                    if let tint { tint.opacity(header ? 0.35 : 0.2) } else if header { Color.accentColor.opacity(0.14) }
                }
            }
            .overlay(Rectangle().stroke(Color(.separator).opacity(0.6), lineWidth: 0.5))
            .overlay(Rectangle().stroke(isSelected(r, c) ? Color.accentColor : .clear, lineWidth: 2))
    }

    private func columnHeader(_ c: Int) -> some View {
        Button { selection = selection == .column(c) ? nil : .column(c); focused = nil } label: {
            HStack(spacing: 2) {
                if c < doc.style.frozenCols { Image(systemName: "pin.fill").font(.system(size: 7)) }
                Text(TableDoc.columnName(c))
            }
            .font(.caption2.weight(.semibold))
            .frame(width: doc.width(c), height: gutterH)
            .foregroundStyle(selection == .column(c) ? .white : .secondary)
            .background(selection == .column(c) ? Color.accentColor : Color(.secondarySystemBackground))
            .overlay(Rectangle().stroke(Color(.separator).opacity(0.6), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func rowHeader(_ r: Int) -> some View {
        Button { selection = selection == .row(r) ? nil : .row(r); focused = nil } label: {
            VStack(spacing: 0) {
                if r < doc.style.frozenRows { Image(systemName: "pin.fill").font(.system(size: 7)) }
                Text("\(r + 1)")
            }
            .font(.caption2.weight(.semibold))
            .frame(width: gutterW, height: TableDoc.rowHeight)
            .foregroundStyle(selection == .row(r) ? .white : .secondary)
            .background(selection == .row(r) ? Color.accentColor : Color(.secondarySystemBackground))
            .overlay(Rectangle().stroke(Color(.separator).opacity(0.6), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

enum TableSelection: Equatable {
    case row(Int), column(Int), cell(Int, Int)
}

private struct TableOffsetKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { value = nextValue() }
}

/// Actions for the selected row, column or cell.
struct TableActionBar: View {
    @Binding var doc: TableDoc
    @Binding var selection: TableSelection?
    @Binding var arranging: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                switch selection {
                case .row(let r): rowActions(r)
                case .column(let c): columnActions(c)
                case .cell(let r, let c): cellActions(r, c)
                case nil:
                    Text("Tap a row number or column letter to change it").font(.caption).foregroundStyle(.secondary)
                    chip("Add row", "plus") { doc.insertRow(at: doc.rows) }
                    chip("Add column", "plus") { doc.insertColumn(at: doc.cols) }
                }
                chip("Rearrange", "arrow.up.arrow.down") { arranging = true }
            }
            .padding(.horizontal, 2)
        }
        .buttonStyle(.bordered)
        .font(.caption.weight(.semibold))
    }

    private func chip(_ title: String, _ symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) { Label(title, systemImage: symbol) }
    }

    private func colourMenu(_ title: String, set: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(TableColor.allCases) { col in
                Button { set(col.rawValue) } label: {
                    Label(col.title, systemImage: col == .none ? "circle.slash" : "circle.fill")
                }
                .tint(col.color)
            }
        } label: { Label(title, systemImage: "paintpalette") }
    }

    @ViewBuilder
    private func rowActions(_ r: Int) -> some View {
        Text("Row \(r + 1)").font(.caption.weight(.bold))
        chip("Above", "arrow.up.to.line") { doc.insertRow(at: r); selection = .row(r + 1) }
        chip("Below", "arrow.down.to.line") { doc.insertRow(at: r + 1) }
        chip("Up", "arrow.up") { guard r > 0 else { return }; doc.moveRows(from: [r], to: r - 1); selection = .row(r - 1) }
            .disabled(r == 0)
        chip("Down", "arrow.down") { guard r < doc.rows - 1 else { return }; doc.moveRows(from: [r], to: r + 2); selection = .row(r + 1) }
            .disabled(r >= doc.rows - 1)
        colourMenu("Colour") { doc.style.rowColors[r] = $0; for c in 0..<doc.cols { doc.style.cellColors[r][c] = "" } }
        chip(r < doc.style.headerRows ? "Not header" : "Header to here", "textformat") {
            doc.style.headerRows = r < doc.style.headerRows ? r : r + 1
        }
        chip(r < doc.style.frozenRows ? "Unfreeze" : "Freeze to here", r < doc.style.frozenRows ? "pin.slash" : "pin") {
            doc.style.frozenRows = r < doc.style.frozenRows ? r : r + 1
        }
        chip("Delete", "trash", role: .destructive) { doc.deleteRow(r); selection = nil }.disabled(doc.rows <= 1)
    }

    @ViewBuilder
    private func columnActions(_ c: Int) -> some View {
        Text("Column \(TableDoc.columnName(c))").font(.caption.weight(.bold))
        chip("Left", "arrow.left.to.line") { doc.insertColumn(at: c); selection = .column(c + 1) }
        chip("Right", "arrow.right.to.line") { doc.insertColumn(at: c + 1) }
        chip("Move", "arrow.left") { guard c > 0 else { return }; doc.moveColumns(from: [c], to: c - 1); selection = .column(c - 1) }
            .disabled(c == 0)
        chip("Move", "arrow.right") { guard c < doc.cols - 1 else { return }; doc.moveColumns(from: [c], to: c + 2); selection = .column(c + 1) }
            .disabled(c >= doc.cols - 1)
        Menu {
            Button("Narrow") { doc.style.colWidths[c] = 70 }
            Button("Normal") { doc.style.colWidths[c] = TableDoc.defaultWidth }
            Button("Wide") { doc.style.colWidths[c] = 170 }
            Button("Extra wide") { doc.style.colWidths[c] = 240 }
        } label: { Label("Width", systemImage: "arrow.left.and.right") }
        colourMenu("Colour") { doc.style.colColors[c] = $0; for r in 0..<doc.rows { doc.style.cellColors[r][c] = "" } }
        chip(c < doc.style.headerCols ? "Not header" : "Header to here", "textformat") {
            doc.style.headerCols = c < doc.style.headerCols ? c : c + 1
        }
        chip(c < doc.style.frozenCols ? "Unfreeze" : "Freeze to here", c < doc.style.frozenCols ? "pin.slash" : "pin") {
            doc.style.frozenCols = c < doc.style.frozenCols ? c : c + 1
        }
        chip("Delete", "trash", role: .destructive) { doc.deleteColumn(c); selection = nil }.disabled(doc.cols <= 1)
    }

    @ViewBuilder
    private func cellActions(_ r: Int, _ c: Int) -> some View {
        Text("\(TableDoc.columnName(c))\(r + 1)").font(.caption.weight(.bold))
        colourMenu("Cell colour") { doc.style.cellColors[r][c] = $0 }
        chip("Clear", "eraser") { doc.cells[r][c] = "" }
        chip("Row", "arrow.left.and.right") { selection = .row(r) }
        chip("Column", "arrow.up.and.down") { selection = .column(c) }
    }
}

/// Drag rows and columns into a new order.
struct TableArrangeView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var doc: TableDoc
    @State private var showing = 0

    var body: some View {
        NavigationStack {
            List {
                if showing == 0 {
                    Section {
                        ForEach(Array(doc.cells.enumerated()), id: \.offset) { r, row in
                            HStack {
                                Text("\(r + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 26)
                                if let tint = TableColor(rawValue: doc.style.rowColors[safe: r] ?? "")?.color {
                                    Circle().fill(tint).frame(width: 8, height: 8)
                                }
                                Text(row.filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty("Empty row"))
                                    .font(r < doc.style.headerRows ? .subheadline.weight(.bold) : .subheadline)
                                    .lineLimit(1)
                            }
                        }
                        .onMove { doc.moveRows(from: $0, to: $1) }
                        .onDelete { set in for r in set.sorted(by: >) { doc.deleteRow(r) } }
                    } footer: {
                        Text("Drag the ≡ handles to move rows. Header and frozen rows stay at the top positions.")
                    }
                } else {
                    Section {
                        ForEach(0..<doc.cols, id: \.self) { c in
                            HStack {
                                Text(TableDoc.columnName(c)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 26)
                                if let tint = TableColor(rawValue: doc.style.colColors[safe: c] ?? "")?.color {
                                    Circle().fill(tint).frame(width: 8, height: 8)
                                }
                                Text((doc.cells.first?[safe: c] ?? "").ifEmpty("Column \(TableDoc.columnName(c))")).lineLimit(1)
                            }
                        }
                        .onMove { doc.moveColumns(from: $0, to: $1) }
                        .onDelete { set in for c in set.sorted(by: >) { doc.deleteColumn(c) } }
                    } footer: {
                        Text("Drag the ≡ handles to move columns.")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .safeAreaInset(edge: .top) {
                Picker("Arrange", selection: $showing) {
                    Text("Rows").tag(0)
                    Text("Columns").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                .background(.bar)
            }
            .navigationTitle("Rearrange")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}
