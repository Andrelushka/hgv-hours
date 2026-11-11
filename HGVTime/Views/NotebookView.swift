import SwiftUI
import SwiftData

/// Notes and tables, with templates you can reuse.
struct NotebookView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \NoteItem.updatedAt, order: .reverse) private var items: [NoteItem]
    @State private var search = ""
    @State private var opened: NoteItem?
    /// Inside the Jobs tab (no own navigation stack).
    var embedded = false

    var body: some View {
        if embedded { content } else { NavigationStack { content } }
    }

    private var content: some View {
        let notes = items.filter { !$0.isTemplate && matches($0) }
        let templates = items.filter { $0.isTemplate }
        return Group {
            List {
                if notes.isEmpty && search.isEmpty {
                    ContentUnavailableView {
                        Label("No notes yet", systemImage: "note.text")
                    } description: {
                        Text("Write notes, keep tables (e.g. delivery points, fuel log, trailer checks) and save them as templates to reuse.")
                    }
                }
                let pinned = notes.filter(\.pinned)
                if !pinned.isEmpty {
                    Section("Pinned") { ForEach(pinned) { row($0) } }
                }
                Section(pinned.isEmpty ? "" : "Notes") {
                    ForEach(notes.filter { !$0.pinned }) { row($0) }
                }
                Section {
                    ForEach(templates) { t in
                        Button { opened = newFrom(t) } label: {
                            Label(t.title.isEmpty ? "Untitled template" : t.title, systemImage: t.isTable ? "tablecells" : "doc.text")
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(t); try? context.save() }
                            Button("Edit", systemImage: "pencil") { opened = t }.tint(.blue)
                        }
                    }
                    Menu {
                        Button("Fuel log", systemImage: "fuelpump") { addStarter(.fuel) }
                        Button("Delivery sheet", systemImage: "shippingbox") { addStarter(.delivery) }
                        Button("Vehicle defect check", systemImage: "checklist") { addStarter(.defects) }
                    } label: {
                        Label("Add a ready-made template", systemImage: "wand.and.stars")
                    }
                } header: {
                    Text("Templates")
                } footer: {
                    Text("Tap a template to start a new note from it. Save any note as a template from its ⋯ menu.")
                }
            }
            .searchable(text: $search)
            .navigationTitle("Notebook")
            .toolbar {
                Menu {
                    Button("New note", systemImage: "square.and.pencil") { opened = create(kind: "text") }
                    Button("New table", systemImage: "tablecells") { opened = create(kind: "table") }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
            .navigationDestination(item: $opened) { NoteEditor(note: $0) }
        }
    }

    private func matches(_ n: NoteItem) -> Bool {
        guard !search.isEmpty else { return true }
        let q = search.lowercased()
        return n.title.lowercased().contains(q) || n.body.lowercased().contains(q)
            || n.table.joined().joined(separator: " ").lowercased().contains(q)
    }

    private func row(_ n: NoteItem) -> some View {
        Button { opened = n } label: {
            VStack(alignment: .leading, spacing: 3) {
                Label(n.title.isEmpty ? "Untitled" : n.title, systemImage: n.isTable ? "tablecells" : "note.text")
                    .font(.subheadline.weight(.semibold))
                Text(n.isTable ? "\(max(0, n.table.count - 1)) rows · \(n.table.first?.count ?? 0) columns" : String(n.body.prefix(80)))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(n.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(n); try? context.save() }
            Button(n.pinned ? "Unpin" : "Pin", systemImage: "pin") { n.pinned.toggle(); try? context.save() }.tint(.orange)
        }
    }

    private func create(kind: String) -> NoteItem {
        let n = NoteItem(kind: kind)
        if kind == "table" { n.table = [["Column 1", "Column 2", "Column 3"]] + Array(repeating: ["", "", ""], count: 8) }
        context.insert(n)
        try? context.save()
        return n
    }

    private func newFrom(_ template: NoteItem) -> NoteItem {
        let n = template.copy(asTemplate: false)
        n.title = template.title.isEmpty ? "" : "\(template.title) \(Date.now.formatted(date: .abbreviated, time: .omitted))"
        context.insert(n)
        try? context.save()
        return n
    }

    private enum Starter { case fuel, delivery, defects }

    private func addStarter(_ starter: Starter) {
        let t = NoteItem(kind: "table", isTemplate: true)
        switch starter {
        case .fuel:
            t.title = "Fuel log"
            t.table = [["Date", "Location", "Litres", "AdBlue", "Mileage"], ["", "", "", "", ""]]
        case .delivery:
            t.title = "Delivery sheet"
            t.table = [["Time", "Customer", "Postcode", "Ref", "Pallets", "Signed"], ["", "", "", "", "", ""]]
        case .defects:
            t.kindRaw = "text"
            t.title = "Vehicle defect check"
            t.body = "Reg:\nTrailer:\nMileage:\n\n☐ Lights & indicators\n☐ Tyres & wheel nuts\n☐ Mirrors & glass\n☐ Brakes & air lines\n☐ Fluid leaks\n☐ Load security\n☐ Tachograph & card\n☐ Height marker\n\nDefects found:\n"
        }
        context.insert(t)
        try? context.save()
    }
}

/// Edit a note or table.
struct NoteEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var note: NoteItem
    @State private var doc = TableDoc(cells: [], style: TableStyle())
    @State private var loaded = false
    @State private var selection: TableSelection?
    @State private var arranging = false
    @State private var confirmDelete = false
    @State private var savedTemplate = false

    var body: some View {
        Group {
            if note.isTable { tableBody } else { textBody }
        }
        .navigationTitle(note.isTemplate ? "Template" : (note.isTable ? "Table" : "Note"))
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .onAppear {
            doc = TableDoc(cells: note.table, style: note.tableStyle)
            loaded = true
        }
        .onChange(of: doc) { _, value in
            guard loaded else { return }
            note.table = value.cells
            note.tableStyle = value.style
            touch()
        }
        .onChange(of: note.title) { _, _ in touch() }
        .onChange(of: note.body) { _, _ in touch() }
        .onDisappear { try? context.save() }
        .sheet(isPresented: $arranging) { TableArrangeView(doc: $doc) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: exportText) { Image(systemName: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if note.isTable {
                        Button("Rearrange rows & columns", systemImage: "arrow.up.arrow.down") { arranging = true }
                    }
                    if !note.isTemplate {
                        Button("Save as template", systemImage: "doc.badge.plus") {
                            context.insert(note.copy(asTemplate: true))
                            try? context.save()
                            savedTemplate = true
                        }
                        Button(note.pinned ? "Unpin" : "Pin", systemImage: "pin") { note.pinned.toggle() }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Saved as a template", isPresented: $savedTemplate) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Find it under Templates in the Notebook.")
        }
        .confirmationDialog("Delete this \(note.isTemplate ? "template" : "note")?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(note)
                try? context.save()
                dismiss()
            }
        }
    }

    private var textBody: some View {
        Form {
            Section {
                TextField(note.isTemplate ? "Template name" : "Title", text: $note.title).font(.headline)
            }
            Section("Note") {
                TextField("Write here…", text: $note.body, axis: .vertical).lineLimit(12...200)
            }
        }
    }

    private var tableBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(note.isTemplate ? "Template name" : "Title", text: $note.title)
                .font(.headline)
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            TableActionBar(doc: $doc, selection: $selection, arranging: $arranging)
            TableGridEditor(doc: $doc, selection: $selection)
            VStack(alignment: .leading, spacing: 4) {
                Label("Notes", systemImage: "note.text").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField("Write notes about this table…", text: $note.body, axis: .vertical)
                    .lineLimit(2...6)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            Text("Tap a row number or column letter to insert, move, colour, make a header or freeze. Freeze any number of rows (they stay at the top) and columns (they stay on the left) at the same time.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private func touch() { note.updatedAt = .now }

    /// Plain text (tables as CSV-like lines) for sharing.
    private var exportText: String {
        var out = note.title.isEmpty ? "" : note.title + "\n\n"
        if note.isTable {
            out += doc.cells.map { $0.map { $0.contains(",") ? "\"\($0)\"" : $0 }.joined(separator: ", ") }.joined(separator: "\n") + "\n\n"
        }
        return out + note.body
    }
}
