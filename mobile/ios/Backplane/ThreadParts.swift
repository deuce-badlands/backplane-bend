import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// The pieces of a thread and the sheets over it. Every label, value and
// choice comes from the screen (src/mobile/screen.bend); these only draw
// them and send back the action each names.

// the hub's palette for a thread's phase (src/web/style.css, src/app/theme.bend)
enum PhaseColor {
    static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
    static let accent = rgb(0x5fb3ff), ok = rgb(0x58c28a), warn = rgb(0xe3b341), bad = rgb(0xf06a6a)
    static let input = rgb(0xb48cff), queued = rgb(0x4fc1c9), waiting = rgb(0xe07bd0), faint = rgb(0x5c6473)
}

// a thread's dot: its phase (row.status, src/core/model.bend's Phase.name),
// in the same colors as the desktop and web; else its turn
struct StatusDot: View {
    let state: String
    let status: String?

    private func dot(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 7, height: 7)
    }

    var body: some View {
        switch status ?? "" {
        case "approval": Image(systemName: "hand.raised.fill").foregroundStyle(PhaseColor.warn).font(.caption)
        case "input": Image(systemName: "questionmark.bubble.fill").foregroundStyle(PhaseColor.input).font(.caption)
        case "working": ProgressView().controlSize(.mini).tint(PhaseColor.accent)
        // the turn is over, its subagents still at work ("waiting" from an older hub)
        case "monitoring", "waiting": Image(systemName: "arrow.triangle.branch").foregroundStyle(PhaseColor.waiting).font(.caption)
                .symbolEffect(.pulse)
        case "failed": Image(systemName: "exclamationmark.circle.fill").foregroundStyle(PhaseColor.bad)
        case "queued": Image(systemName: "clock").foregroundStyle(PhaseColor.queued).font(.caption)
        case "complete": dot(PhaseColor.ok)
        case "stopped", "idle", "ready": dot(PhaseColor.faint)
        default:
            switch state {
            case "run": ProgressView().controlSize(.mini).tint(PhaseColor.accent)
            case "fail": Image(systemName: "exclamationmark.circle.fill").foregroundStyle(PhaseColor.bad)
            case "stop": Image(systemName: "stop.circle").foregroundStyle(PhaseColor.warn)
            default: dot(PhaseColor.faint)
            }
        }
    }
}

// an image the lightbox shows
struct Shown: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// an image from the hub, as a thumbnail; a tap opens it full screen
struct Thumb: View {
    let model: AppModel
    let url: String
    let show: (Shown) -> Void

    var body: some View {
        if let u = model.web(url) {
            AsyncImage(url: u) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFit()
                case .failure: Image(systemName: "photo").foregroundStyle(.tertiary).frame(width: 80, height: 60)
                default: ProgressView().frame(width: 80, height: 60)
                }
            }
            .frame(maxWidth: 260, maxHeight: 200, alignment: .leading)
            .clipShape(.rect(cornerRadius: 6))
            .onTapGesture { show(Shown(url: u)) }
            .accessibilityAddTraits(.isButton)
        }
    }
}

// pinch to zoom, drag to pan, double-tap to zoom in or back, tap Done to close
struct Lightbox: View {
    let shown: Shown
    let close: () -> Void
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var moved: CGSize = .zero

    var body: some View {
        NavigationStack {
            AsyncImage(url: shown.url) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFit()
                } else if phase.error != nil {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .gesture(MagnifyGesture()
                .onChanged { scale = min(max(base * $0.magnification, 1), 8) }
                .onEnded { _ in base = scale; if scale == 1 { offset = .zero; moved = .zero } })
            .simultaneousGesture(DragGesture()
                .onChanged { offset = CGSize(width: moved.width + $0.translation.width, height: moved.height + $0.translation.height) }
                .onEnded { _ in moved = offset })
            .onTapGesture(count: 2) {
                withAnimation {
                    scale = scale > 1 ? 1 : 2.5
                    base = scale
                    if scale == 1 { offset = .zero; moved = .zero }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) }
                ToolbarItem(placement: .leadingBar) { ShareLink(item: shown.url) }
            }
            .barStyle(.black, scheme: .dark)
        }
    }
}

// an attachment chip; an image shows as a thumbnail
struct ChipView: View {
    let model: AppModel
    let chip: Chip
    let show: (Shown) -> Void

    var body: some View {
        if chip.image {
            Thumb(model: model, url: chip.url, show: show)
        } else {
            Label(chip.label, systemImage: "doc")
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 6))
        }
    }
}

struct EntryRow: View {
    let model: AppModel
    let entry: Entry
    let show: (Shown) -> Void

    var body: some View {
        switch entry.kind {
        case "user":
            VStack(alignment: .trailing, spacing: 6) {
                if !entry.text.isEmpty {
                    Text(entry.text)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 18))
                        .contextMenu { Button("Copy", systemImage: "doc.on.doc") { model.act("copy", entry.text) } }
                }
                ForEach(entry.attachments ?? [], id: \.self) { ChipView(model: model, chip: $0, show: show) }
            }
            .padding(.leading, 48)
            .frame(maxWidth: .infinity, alignment: .trailing)
        case "assistant":
            VStack(alignment: .leading, spacing: 8) {
                MarkdownView(blocks: entry.blocks ?? [])
                ForEach(entry.images ?? [], id: \.self) { Thumb(model: model, url: $0.url, show: show) }
            }
            .contextMenu { Button("Copy", systemImage: "doc.on.doc") { model.act("copy", entry.text) } }
        case "fold":
            Button { model.act("fold", entry.value ?? "") } label: {
                HStack(spacing: 6) {
                    Image(systemName: entry.open == true ? "chevron.down" : "chevron.right").font(.caption2)
                    Text(entry.text).lineLimit(1)
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel((entry.open == true ? "Hide " : "Show ") + entry.text)
        case "link":
            Button { model.act("select", entry.value ?? "") } label: {
                Text(entry.text).lineLimit(1).font(.callout)
            }
            .buttonStyle(.borderless)
        default:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.label ?? "").foregroundStyle(.tertiary)
                Text(entry.text).lineLimit(2)
            }
            .font(.caption.monospaced())
            .foregroundStyle(entry.tone == "error" ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// the threads this one delegated to
struct TasksView: View {
    let model: AppModel
    let tasks: [TaskRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subagents").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(tasks) { t in
                Button { model.act("select", t.id) } label: {
                    HStack(spacing: 8) {
                        StatusDot(state: t.state == "running" ? "run" : t.state == "failed" ? "fail" : "", status: nil).frame(width: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title).lineLimit(1)
                            Text(t.who + " · " + t.state).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.secondaryBackground, in: .rect(cornerRadius: 10))
    }
}

// an approval, question or plan waiting on the user
struct AskCard: View {
    let model: AppModel
    let ask: Ask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(ask.head, systemImage: ask.kind == "plan" ? "list.bullet.clipboard" : ask.kind == "input" ? "questionmark.bubble" : "hand.raised")
                .font(.subheadline.bold())
            if !ask.blocks.isEmpty {
                ScrollView { MarkdownView(blocks: ask.blocks).font(.callout) }.frame(maxHeight: 220)
            } else if !ask.detail.isEmpty {
                Text(ask.detail).font(.caption.monospaced()).lineLimit(8).textSelection(.enabled)
            }
            FlowButtons(buttons: ask.buttons) { model.act("answer", $0.value) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12))
    }
}

// buttons that wrap onto more lines when they do not fit
struct FlowButtons: View {
    let buttons: [AskButton]
    let tap: (AskButton) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { items }
            VStack(alignment: .leading, spacing: 6) { items }
        }
    }

    @ViewBuilder private var items: some View {
        ForEach(buttons, id: \.self) { b in
            if b.primary {
                Button(b.label) { tap(b) }.buttonStyle(.borderedProminent)
            } else {
                Button(b.label) { tap(b) }.buttonStyle(.bordered)
            }
        }
    }
}

// what the next message attaches (× takes one off), what is uploading,
// and what the word being typed completes to: a `$` skill, an `@` bot,
// a `>` thread, a `%` project or a `#` room, each with its summary
struct ComposerExtras: View {
    let model: AppModel
    let thread: ThreadView

    var body: some View {
        let atts = thread.attaching ?? []
        let up = thread.uploading ?? ""
        let skills = thread.skills ?? []
        if let b = thread.btw {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("btw · " + b.q).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button { model.act("btw-close") } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                ScrollView { Text(b.a).font(.callout).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 200)
            }
            .padding(10)
            .background(Color.secondaryBackground)
            .padding(.horizontal).padding(.top, 8)
        }
        if !skills.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(skills.enumerated()), id: \.element) { i, k in
                    Button { model.act("skill", k.name) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(k.name).font(.subheadline.bold()).lineLimit(1)
                            if !k.desc.isEmpty {
                                Text(k.desc).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(k.on ?? (i == 0) ? Color.secondary.opacity(0.15) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        if !atts.isEmpty || !up.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(atts, id: \.self) { c in
                        Button { model.act("detach", c.path) } label: {
                            Label(c.label, systemImage: c.image ? "photo" : "doc").lineLimit(1)
                            Image(systemName: "xmark").font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Remove " + c.label)
                    }
                    if !up.isEmpty {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text(up).lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .padding(.horizontal)
            }
            .padding(.top, 8)
        }
    }
}

// the paperclip: photos or files, each sent up in pieces
struct AttachButton: View {
    let model: AppModel
    @State private var photos: [PhotosPickerItem] = []
    @State private var picking = false
    @State private var importing = false

    var body: some View {
        Menu {
            Button("Photos", systemImage: "photo.on.rectangle") { picking = true }
            Button("Files", systemImage: "folder") { importing = true }
        } label: {
            Image(systemName: "paperclip").font(.system(size: 17)).foregroundStyle(.secondary)
        }
        .plainMenu()
        .accessibilityLabel("Attach")
        .photosPicker(isPresented: $picking, selection: $photos, maxSelectionCount: 10, matching: .images)
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            photos = []
            Task {
                for (i, it) in items.enumerated() {
                    guard let data = try? await it.loadTransferable(type: Data.self) else { continue }
                    let ext = it.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    // HEIC becomes JPEG, which every agent reads
                    if ext == "heic", let jpg = Platform.jpeg(data, quality: 0.85) {
                        model.attach(jpg, name: "photo-\(i + 1).jpg")
                    } else {
                        model.attach(data, name: "photo-\(i + 1).\(ext)")
                    }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            guard case .success(let urls) = r else { return }
            for u in urls {
                let ok = u.startAccessingSecurityScopedResource()
                defer { if ok { u.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: u) { model.attach(data, name: u.lastPathComponent) }
            }
        }
    }
}

// what the thread changed, with the git actions
struct DiffSheet: View {
    let model: AppModel
    let diff: Diff
    @State private var reverting = false

    var body: some View {
        NavigationStack {
            List {
                Section { Text(diff.summary).font(.footnote).foregroundStyle(.secondary) }
                ForEach(diff.files) { f in
                    Section {
                        ForEach(Array(f.lines.enumerated()), id: \.offset) { _, l in line(l) }
                            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    } header: {
                        HStack {
                            Text(f.name).textCase(nil).lineLimit(1).truncationMode(.head)
                            Spacer()
                            Text(f.status).textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 14)
            .navigationTitle("Diff")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { model.act("panel") } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Commit & push", systemImage: "arrow.up.circle") { model.act("git", "commit_push") }
                        Button("Open PR", systemImage: "arrow.triangle.pull") { model.act("git", "commit_push_pr") }
                        Button("Revert thread", systemImage: "arrow.uturn.backward", role: .destructive) { reverting = true }
                    } label: {
                        Text("Git")
                    }
                }
            }
            .confirmationDialog("Put the files back as they were when this thread began?", isPresented: $reverting, titleVisibility: .visible) {
                Button("Revert thread", role: .destructive) { model.act("revert", "0") }
            }
        }
    }

    private func line(_ l: DiffLine) -> some View {
        let sign = l.k == 1 ? "+" : l.k == 2 ? "-" : " "
        let bg: Color = l.k == 1 ? .green.opacity(0.14) : l.k == 2 ? .red.opacity(0.14) : .clear
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            if l.k == 4 {
                Text(l.t).foregroundStyle(.blue)
            } else {
                Text(l.k == 2 ? l.o : l.n).foregroundStyle(.tertiary).frame(width: 30, alignment: .trailing)
                Text(sign + l.t).foregroundStyle(l.k == 3 ? .secondary : .primary)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.vertical, 1)
        .listRowBackground(bg)
        .listRowSeparator(.hidden)
    }
}

// the thread's shell: the screen the hub's emulator keeps, keys typed in a
// hidden field, and a row of keys a phone keyboard lacks
struct TermSheet: View {
    let model: AppModel
    let term: Term
    @State private var buf = " "
    @FocusState private var typing: Bool

    static let metrics = Platform.monoFont(size: 11)
    static let cw = metrics.width
    static let lh = ceil(metrics.line)

    // the size a terminal has room for on this phone, as "<cols>x<rows>"
    static func size() -> String {
        let b = Platform.terminalArea
        return "\(max(Int((b.width - 16) / cw), 20))x\(max(Int(b.height / lh), 8))"
    }

    private static func color(_ c: UInt32) -> Color {
        Color(red: Double((c >> 16) & 255) / 255, green: Double((c >> 8) & 255) / 255, blue: Double(c & 255) / 255)
    }

    private func row(_ runs: [TermRun]) -> AttributedString {
        var out = AttributedString()
        for r in runs {
            var a = AttributedString(r.t)
            a.foregroundColor = Self.color(r.fg)
            if r.bg != term.bg { a.backgroundColor = Self.color(r.bg) }
            if r.b { a.font = .system(size: 11, weight: .bold, design: .monospaced) }
            if r.u { a.underlineStyle = .single }
            out += a
        }
        return out
    }

    private func key(_ k: String, _ mods: Int = 0) { model.act("term-key", "\(k)\t\(mods)") }

    // a Mac keyboard straight to the pty: named keys by name, ctrl+letter as
    // a key with ctrl held (4), anything else typed as text
    private func press(_ p: KeyPress) -> KeyPress.Result {
        let named: [KeyEquivalent: String] = [.return: "Enter", .delete: "Backspace", .escape: "Escape", .tab: "Tab",
                                              .leftArrow: "ArrowLeft", .rightArrow: "ArrowRight", .upArrow: "ArrowUp", .downArrow: "ArrowDown",
                                              .home: "Home", .end: "End", .pageUp: "PageUp", .pageDown: "PageDown", .deleteForward: "Delete"]
        if let n = named[p.key] { key(n); return .handled }
        if p.modifiers.contains(.command) { return .ignored }
        if p.modifiers.contains(.control), let c = p.key.character.lowercased().first, c.isLetter {
            key(String(c), 4)
            return .handled
        }
        guard !p.characters.isEmpty else { return .ignored }
        model.act("term-paste", p.characters)
        return .handled
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(term.lines.enumerated()), id: \.offset) { _, l in
                                Text(row(l)).frame(height: Self.lh, alignment: .leading).fixedSize()
                            }
                        }
                        if term.cursor.on {
                            Rectangle().fill(Self.color(term.fg).opacity(0.6))
                                .frame(width: Self.cw, height: Self.lh)
                                .offset(x: CGFloat(term.cursor.x) * Self.cw, y: CGFloat(term.cursor.y) * Self.lh)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Self.color(term.fg))
                    .padding(8)
                }
                .defaultScrollAnchor(.bottomLeading)
                .background(Self.color(term.bg))
                .onTapGesture { typing = true }
                .terminalKeys($typing) { press($0) }
                #if os(iOS)
                TextField("", text: $buf)
                    .focused($typing)
                    .plainTextInput()
                    .autocorrectionDisabled()
                    .asciiKeyboard()
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .onChange(of: buf) { old, new in
                        // the field keeps one space, so a backspace always has something to take
                        if new == " " { return }
                        if new.count < old.count || new.isEmpty {
                            key("Backspace")
                        } else if new.hasPrefix(" ") {
                            let typed = String(new.dropFirst())
                            if !typed.isEmpty { model.act("term-paste", typed) }
                        }
                        if buf != " " { buf = " " }
                    }
                    .onSubmit { key("Enter"); typing = true }
                #endif
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button("esc") { key("Escape") }
                        Button("tab") { key("Tab") }
                        Button("^C") { key("c", 4) }
                        Button("^D") { key("d", 4) }
                        Button("^Z") { key("z", 4) }
                        Button("^L") { key("l", 4) }
                        Button { key("ArrowLeft") } label: { Image(systemName: "arrow.left") }
                        Button { key("ArrowUp") } label: { Image(systemName: "arrow.up") }
                        Button { key("ArrowDown") } label: { Image(systemName: "arrow.down") }
                        Button { key("ArrowRight") } label: { Image(systemName: "arrow.right") }
                        Button { typing.toggle() } label: { Image(systemName: typing ? "keyboard.chevron.compact.down" : "keyboard") }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.monospaced())
                    .padding(.horizontal).padding(.vertical, 6)
                }
                .background(.bar)
            }
            .navigationTitle(term.title.isEmpty ? "Terminal" : term.title)
            .inlineTitle()
            .barStyle(Self.color(term.bg), scheme: .dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { model.act("term-toggle") } }
            }
            .onAppear { typing = true }
        }
    }
}

// thread search or the file picker: a field over the rows; a row sends its
// action with its value, then the sheet closes
struct FindSheet: View {
    let model: AppModel
    let find: Find
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(find.rows, id: \.self) { r in
                    Button {
                        model.act(r.action, r.value)
                        model.act("find-close")
                    } label: {
                        Label(r.label, systemImage: r.kind == "file" ? "doc" : r.kind == "thread" ? "bubble.left" : "bolt")
                            .lineLimit(2)
                    }
                    .tint(.primary)
                }
            }
            .overlay {
                if find.rows.isEmpty {
                    ContentUnavailableView(find.query.isEmpty ? (find.mode == "files" ? "Type to find a file" : "Type to search threads") : "Nothing found",
                                           systemImage: "magnifyingglass")
                }
            }
            .safeAreaInset(edge: .top) {
                TextField(find.mode == "files" ? "File name" : "Titles and messages", text: $text)
                    .plainTextInput()
                    .autocorrectionDisabled()
                    .focused($focused)
                    .padding(10)
                    .background(Color.secondaryBackground, in: .rect(cornerRadius: 10))
                    .padding(.horizontal).padding(.vertical, 8)
                    .background(.bar)
                    .onChange(of: text) { _, t in model.act("find-q", t) }
            }
            .navigationTitle(find.mode == "files" ? "Find file" : "Search threads")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.act("find-close") } }
            }
            .onAppear { text = find.query; focused = true }
        }
    }
}

// the hub's settings, as the desktop has them
// The hub's settings as a sheet (on a Mac also from the app menu's
// Settings…, cmd+comma). A wide sheet (a Mac, an iPad) lists the sections
// beside the chosen one, like System Settings; a phone lists them with
// what each has set, and pushes into one.
struct SettingsSheet: View {
    let model: AppModel
    let settings: Settings
    let version: String
    // sections beside the chosen one (a Mac, an iPad), or a list that pushes
    let wide: Bool
    @AppStorage("settings.section") private var picked = ""

    private var sections: [SetSection] {
        if let s = settings.sections, !s.isEmpty { return s }
        var seen: [String] = []
        for r in settings.rows where !seen.contains(r.section ?? "") { seen.append(r.section ?? "") }
        return seen.map { SetSection(title: $0, summary: "", attention: false) }
    }

    private var current: SetSection? { sections.first { $0.title == picked } ?? sections.first }

    var body: some View {
        // the rows lay their controls out by the same width
        Group { if wide { split } else { stack } }
            .environment(\.splitLayout, wide)
    }

    private var split: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                List(selection: Binding(get: { current?.title }, set: { if let t = $0 { picked = t } })) {
                    ForEach(sections, id: \.title) { s in
                        HStack(spacing: 8) {
                            SectionIcon(title: s.title)
                            Text(s.title)
                            Spacer(minLength: 4)
                            if s.attention { Circle().fill(.orange).frame(width: 7, height: 7).accessibilityLabel("Needs attention") }
                        }
                        .tag(s.title)
                    }
                }
                .listStyle(.sidebar)
                .frame(width: Platform.settingsSidebar)
                Divider()
                if let c = current {
                    SettingsPane(model: model, section: c, rows: settings.rows.filter { ($0.section ?? "") == c.title }, header: true)
                        .frame(maxWidth: .infinity)
                }
            }
            Divider()
            HStack {
                #if os(macOS)
                Text("⌘1–\(min(9, sections.count)) switch sections").font(.caption).foregroundStyle(.secondary)
                #endif
                Spacer()
                Button("Done") { model.act("flag", "settings") }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background { keys }
        .macSheet(width: 700, height: 520)
        .pageSheet()
    }

    // cmd+1…9 picks a section
    private var keys: some View {
        ForEach(Array(sections.prefix(9).enumerated()), id: \.offset) { i, s in
            Button("") { picked = s.title }
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private var stack: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sections, id: \.title) { s in
                        NavigationLink(value: s.title) {
                            HStack(spacing: 10) {
                                SectionIcon(title: s.title)
                                Text(s.title)
                                Spacer(minLength: 8)
                                Text(s.summary).font(.subheadline).lineLimit(1)
                                    .foregroundStyle(s.attention ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                            }
                        }
                    }
                } footer: {
                    if !version.isEmpty { Text("Backplane \(version)") }
                }
            }
            .navigationTitle("Settings")
            .inlineTitle()
            .navigationDestination(for: String.self) { t in
                if let s = sections.first(where: { $0.title == t }) {
                    SettingsPane(model: model, section: s, rows: settings.rows.filter { ($0.section ?? "") == t }, header: false)
                        .navigationTitle(t)
                        .inlineTitle()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { model.act("flag", "settings") } }
            }
        }
    }
}

// a section's icon: a tinted rounded square, as System Settings draws them
private struct SectionIcon: View {
    let title: String

    private var look: (String, Color) {
        switch title {
        case "Threads": ("text.bubble.fill", .gray)
        case "Agents": ("cpu.fill", .indigo)
        case "Writing": ("pencil.line", .orange)
        case "KiCad": ("memorychip.fill", .teal)
        case "Appearance": ("circle.lefthalf.filled", Color(white: 0.4))
        case "Network": ("network", .blue)
        case "Voice": ("mic.fill", .pink)
        default: ("gearshape.fill", .gray)
        }
    }

    var body: some View {
        Image(systemName: look.0)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(look.1.gradient, in: .rect(cornerRadius: 6))
    }
}

// one section's rows, under their headings ("Installed")
private struct SettingsPane: View {
    let model: AppModel
    let section: SetSection
    let rows: [SetRow]
    let header: Bool

    private var groups: [(title: String, rows: [SetRow])] {
        var out: [(title: String, rows: [SetRow])] = []
        for r in rows {
            let t = r.group ?? ""
            if let last = out.last, last.title == t { out[out.count - 1].rows.append(r) } else { out.append((t, [r])) }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if header {
                HStack(spacing: 10) {
                    SectionIcon(title: section.title)
                    Text(section.title).font(.title3.weight(.semibold))
                }
                .padding(.horizontal, 20).padding(.top, 16)
            }
            Form {
                ForEach(groups, id: \.title) { g in
                    Section {
                        ForEach(g.rows, id: \.label) { SettingRowView(model: model, row: $0) }
                    } header: {
                        if !g.title.isEmpty { Text(g.title) }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

// one setting: its label and note, and the control its kind names
private struct SettingRowView: View {
    let model: AppModel
    let row: SetRow
    @State private var text = ""
    @Environment(\.splitLayout) private var wide

    private var kind: String { row.kind ?? "" }

    // a phone puts a wide control (segments, a field) under its label
    private var below: Bool {
        #if os(macOS)
        false
        #else
        !wide && (kind == "choice" || kind == "field" || (kind == "status" && !row.buttons.isEmpty) || kind == "")
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if below {
                label
                control
            } else {
                HStack(alignment: .center, spacing: 12) {
                    label.frame(maxWidth: .infinity, alignment: .leading)
                    control.fixedSize()
                }
            }
            if let cs = row.chips, !cs.isEmpty {
                ChipFlow(spacing: 6) {
                    ForEach(cs, id: \.self) { c in
                        Button { model.act(c.action, c.value) } label: {
                            HStack(spacing: 4) { Text(c.label); Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Remove \(c.label)")
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
        .onAppear { text = row.field?.text ?? "" }
        // the hub clears a field once it has taken it (a saved key, an added term)
        .onChange(of: row.field?.text) { _, t in text = t ?? "" }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.label)
            if !row.note.isEmpty {
                Text(row.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
    }

    private var chosen: Int? { row.buttons.firstIndex { $0.on } }

    @ViewBuilder private var control: some View {
        switch kind {
        case "choice":
            Picker(row.label, selection: Binding(get: { chosen ?? -1 }, set: { if $0 >= 0, $0 < row.buttons.count { press(row.buttons[$0]) } })) {
                ForEach(Array(row.buttons.enumerated()), id: \.offset) { i, b in Text(b.label).tag(i) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        case "menu":
            Picker(row.label, selection: Binding(get: { chosen ?? -1 }, set: { if $0 >= 0, $0 < row.buttons.count { press(row.buttons[$0]) } })) {
                ForEach(Array(row.buttons.enumerated()), id: \.offset) { i, b in Text(b.label).tag(i) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        case "stepper":
            HStack(spacing: 8) {
                Text(row.value ?? "").monospacedDigit()
                if row.buttons.count == 2 {
                    Stepper(row.label, onIncrement: { press(row.buttons[1]) }, onDecrement: { press(row.buttons[0]) }).labelsHidden()
                }
            }
        case "switch":
            Toggle(row.label, isOn: Binding(get: { row.buttons.first?.on ?? false }, set: { on in
                if let b = row.buttons.first(where: { $0.label.lowercased() == (on ? "on" : "off") }) { press(b) }
            }))
            .toggleStyle(.switch)
            .labelsHidden()
        case "status":
            HStack(spacing: 8) {
                if let v = row.value, !v.isEmpty {
                    Text(v).foregroundStyle(tone).lineLimit(1)
                }
                buttons
            }
        case "field":
            HStack(spacing: 8) {
                if let f = row.field { field(f) }
                buttons
            }
        default:
            ChipFlow(spacing: 6) { buttons }.controlSize(.small)
        }
    }

    private var tone: AnyShapeStyle {
        switch row.tone {
        case "ok": AnyShapeStyle(.green)
        case "warn": AnyShapeStyle(.orange)
        default: AnyShapeStyle(.secondary)
        }
    }

    @ViewBuilder private var buttons: some View {
        ForEach(row.buttons, id: \.self) { b in
            if b.on {
                Button(b.label) { press(b) }.buttonStyle(.borderedProminent)
            } else {
                Button(b.label) { press(b) }.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder private func field(_ f: SetField) -> some View {
        Group {
            if f.secret {
                SecureField("", text: $text, prompt: Text(f.hint))
            } else {
                TextField("", text: $text, prompt: Text(f.hint))
            }
        }
        // the hint is the prompt inside the field, not a label beside it
        .labelsHidden()
        .plainTextInput()
        .autocorrectionDisabled()
        .macFieldStyle()
        .frame(minWidth: 160, idealWidth: 220, maxWidth: below ? .infinity : 240)
        .onChange(of: text) { _, t in model.field(f.name, t) }
        // return does the row's first button (Save, Add)
        .onSubmit { if let b = row.buttons.first { press(b) } }
    }

    // a row with a field sends what was typed first, so the action reads it
    private func press(_ b: SetButton) {
        if let f = row.field { model.submit(f.name, text, b.action, b.value) } else { model.act(b.action, b.value) }
    }
}

// buttons laid out in rows, wrapping at the width they have (a Mac's list
// of microphones, a long dictionary)
private struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let w = rows.map { $0.width }.max() ?? 0
        let h = rows.map { $0.height }.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for r in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for i in r.items {
                let sz = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
                x += sz.width + spacing
            }
            y += r.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let sz = subviews[i].sizeThatFits(.unspecified)
            let add = rows[rows.count - 1].items.isEmpty ? sz.width : rows[rows.count - 1].width + spacing + sz.width
            if add > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row(items: [i], width: sz.width, height: sz.height))
            } else {
                rows[rows.count - 1].items.append(i)
                rows[rows.count - 1].width = add
                rows[rows.count - 1].height = max(rows[rows.count - 1].height, sz.height)
            }
        }
        return rows
    }
}
