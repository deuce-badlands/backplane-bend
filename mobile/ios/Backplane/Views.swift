import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @State private var pairing = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var width
    #endif
    // the delete (or remove) just answered: its dialog stays down until the screen drops it
    @State private var answered = ""
    @State private var removed = ""

    var body: some View {
        if model.links.isEmpty {
            NavigationStack { PairView(link: "") { model.pair($0) } }
        } else if let s = model.screen {
            navigation(s)
            .alert(s.error, isPresented: Binding(get: { !s.error.isEmpty }, set: { if !$0 { model.act("dismiss") } })) {
                Button("OK") { model.act("dismiss") }
            }
            .alert(s.deleting?.title ?? "", isPresented: Binding(get: { s.deleting.map { $0.id != answered } ?? false }, set: { _ in }),
                   presenting: s.deleting) { d in
                Button(d.yes, role: .destructive) { answered = d.id; model.act("row-delete", d.id) }
                Button(d.no, role: .cancel) { answered = d.id; model.act("delete-no") }
            } message: { d in
                Text(d.body)
            }
            .onChange(of: s.deleting?.id) { answered = "" }
            .alert(s.removing?.title ?? "", isPresented: Binding(get: { s.removing.map { $0.id != removed } ?? false }, set: { _ in }),
                   presenting: s.removing) { d in
                Button(d.yes, role: .destructive) { removed = d.id; model.act("proj-remove", d.id) }
                Button(d.no, role: .cancel) { removed = d.id; model.act("proj-keep") }
            } message: { d in
                Text(d.body)
            }
            .onChange(of: s.removing?.id) { removed = "" }
            .sheet(isPresented: Binding(get: { model.screen?.settings != nil }, set: { if !$0, model.screen?.settings != nil { model.act("flag", "settings") } })) {
                if let st = model.screen?.settings { SettingsSheet(model: model, settings: st, version: model.screen?.version ?? "").macSheet(width: 620, height: 640) }
            }
            .sheet(isPresented: Binding(get: { model.screen?.find != nil }, set: { if !$0, model.screen?.find != nil { model.act("find-close") } })) {
                if let f = model.screen?.find { FindSheet(model: model, find: f).macSheet(width: 620, height: 560) }
            }
            .sheet(isPresented: $pairing) {
                NavigationStack {
                    HubsView(model: model, screen: model.screen ?? s)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { pairing = false } } }
                }
                .macSheet(width: 560, height: 520)
            }
        } else {
            ProgressView()
        }
    }
}

extension RootView {
    // a Mac, or an iPad with the room, keeps the projects, threads and bots
    // in a sidebar with the selected one beside it; a phone pushes
    private var split: Bool {
        #if os(macOS)
        true
        #else
        width == .regular
        #endif
    }

    @ViewBuilder
    private func navigation(_ s: Screen) -> some View {
        if split {
        NavigationSplitView {
            ProjectsView(model: model, screen: s, pairing: $pairing)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 400)
        } detail: {
            // the selection (a thread, or a bot's page) fills the column:
            // nothing to go back to, the sidebar is the way elsewhere
            if let id = model.path.last {
                NavigationStack { ThreadDestination(model: model, id: id) }.id(id)
            } else {
                ContentUnavailableView("No thread selected", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Pick a thread or a bot in the sidebar."))
            }
        }
        .environment(\.splitLayout, true)
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 560)
        #endif
        } else {
        NavigationStack(path: Binding(get: { model.path }, set: { model.navigate($0) })) {
            ProjectsView(model: model, screen: s, pairing: $pairing)
                .navigationDestination(for: String.self) { id in
                    ThreadDestination(model: model, id: id)
                }
        }
        }
    }
}

// The first screen: connect to a hub. On a Mac the hub on this machine is
// one click (loopback needs no token) once it answers; any other hub
// pairs by the link its Settings shows.
struct PairView: View {
    @State var link: String
    let done: (String) -> Void
    #if os(macOS)
    // nil while asking, then whether 127.0.0.1:3787 answered /hello
    @State private var local: Bool?
    private static let localURL = "http://127.0.0.1:3787/"
    #endif

    private var typed: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(.tint)
                        .frame(width: 64, height: 64)
                        .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 16))
                    Text("Connect to a hub").font(.title2.bold())
                    Text("Your threads, bots and boards live on a Backplane hub. Pair once; the app remembers it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                #if os(macOS)
                card {
                    HStack(spacing: 12) {
                        Image(systemName: "desktopcomputer").font(.title2).foregroundStyle(.secondary).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("This Mac").font(.headline)
                            HStack(spacing: 6) {
                                Circle().fill(local == true ? Color.green : local == false ? Color.orange : Color.secondary)
                                    .frame(width: 7, height: 7)
                                Text(local == true ? "Hub running at 127.0.0.1:3787" : local == false ? "No hub answering at 127.0.0.1:3787" : "Looking for a hub…")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        if local == false {
                            Button("Retry") { Task { await probe() } }
                        }
                        Button("Connect") { done(Self.localURL) }
                            .buttonStyle(.borderedProminent)
                            .disabled(local != true)
                            .keyboardShortcut(local == true && typed.isEmpty ? .defaultAction : nil)
                    }
                }
                #endif
                card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(anotherTitle).font(.headline)
                        Text("Paste the pairing link from that hub's Settings (Pairing link).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            TextField("Pairing link", text: $link, prompt: Text(verbatim: "http://host:3787/#token=…"))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .plainTextInput()
                                .autocorrectionDisabled()
                                .urlKeyboard()
                                .onSubmit { if !typed.isEmpty { done(typed) } }
                            Button("Connect") { done(typed) }
                                .disabled(typed.isEmpty)
                        }
                    }
                }
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Backplane")
        .inlineTitle()
        #if os(macOS)
        .task { await probe() }
        .frame(minWidth: 560, minHeight: 480)
        #endif
    }

    private var anotherTitle: String {
        #if os(macOS)
        "Another hub"
        #else
        "Pair with a hub"
        #endif
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondaryBackground, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.2)).allowsHitTesting(false))
    }

    #if os(macOS)
    // GET /hello answers without a token (server.bend, Hello.answer)
    private func probe() async {
        local = nil
        var r = URLRequest(url: URL(string: Self.localURL + "hello")!)
        r.timeoutInterval = 2
        let ok = (try? await URLSession.shared.data(for: r)).map { ($0.1 as? HTTPURLResponse)?.statusCode == 200 } ?? false
        local = ok
    }
    #endif
}

// the hubs this phone is paired with (swipe to unpair), the owner's other
// machines they know of (one tap pairs), and a field for a new link
struct HubsView: View {
    let model: AppModel
    let screen: Screen
    @State private var link = ""

    var body: some View {
        Form {
            Section("Paired") {
                ForEach(screen.hubs, id: \.key) { h in
                    let c = model.conn[h.key] ?? HubConn()
                    HStack(alignment: .firstTextBaseline) {
                        HubDot(phase: c.phase).font(.caption)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(h.name)
                                Spacer()
                                Text(HubDot.word(c.phase)).font(.caption).foregroundStyle(HubDot.tint(c.phase))
                            }
                            Text(HubsView.detail(h, c)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .swipeActions { Button("Unpair", role: .destructive) { model.unpair(h.key) } }
                    .macMenu { Button("Unpair", role: .destructive) { model.unpair(h.key) } }
                }
            }
            if !screen.found.isEmpty {
                Section("On your tailnet") {
                    ForEach(screen.found, id: \.url) { f in
                        Button { model.pair(f.url) } label: {
                            HStack {
                                Text(f.name)
                                Spacer()
                                Image(systemName: "plus.circle")
                            }
                        }
                    }
                }
            }
            Section {
                TextField("Pairing link", text: $link, prompt: Text(verbatim: "http://host:3787/#token=…"))
                    .plainTextInput()
                    .autocorrectionDisabled()
                    .urlKeyboard()
                Button("Add hub") { model.pair(link); link = "" }.disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Pair another")
            } footer: {
                Text("Paste the tailnet link Backplane shows in Settings (Pairing link).")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Hubs")
    }

    // host:port · version · changes held · when it last said anything
    static func detail(_ h: HubRow, _ c: HubConn) -> String {
        var parts = [h.key]
        if let v = h.version, !v.isEmpty { parts.append(v) }
        if c.phase == .syncing, c.bytes > 0 {
            parts.append("catching up, " + ByteCountFormatter.string(fromByteCount: Int64(c.bytes), countStyle: .file))
        } else if let n = h.changes, n > 0 {
            parts.append("\(n.formatted()) changes")
        }
        if let t = c.heard { parts.append("heard " + t.formatted(.relative(presentation: .named))) }
        return parts.joined(separator: " · ")
    }
}

// a hub's socket as a dot: green online, orange catching up, grey otherwise
struct HubDot: View {
    let phase: HubConn.Phase

    var body: some View {
        Image(systemName: phase == .online ? "circle.fill" : phase == .syncing ? "circle.lefthalf.filled" : "circle.dotted")
            .foregroundStyle(Self.tint(phase))
    }

    static func tint(_ p: HubConn.Phase) -> Color {
        switch p {
        case .online: .green
        case .syncing: .orange
        case .offline: .red
        case .connecting: .secondary
        }
    }

    static func word(_ p: HubConn.Phase) -> String {
        switch p {
        case .online: "Connected"
        case .syncing: "Catching up"
        case .offline: "Offline, retrying"
        case .connecting: "Connecting"
        }
    }
}

// every paired hub at a glance, in the list's toolbar: one dot each (up to
// four), and a tap opens the hubs
struct HubsPill: View {
    let model: AppModel
    let hubs: [HubRow]
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 3) {
                ForEach(hubs.prefix(4), id: \.key) { h in HubDot(phase: model.conn[h.key]?.phase ?? .connecting) }
                if hubs.count > 4 { Text("+\(hubs.count - 4)") }
            }
            .font(.system(size: 9))
        }
        .accessibilityLabel(hubs.map { $0.name + ": " + HubDot.word(model.conn[$0.key]?.phase ?? .connecting) }.joined(separator: ", "))
    }
}

#if os(macOS)
// the hubs' state along the foot of the Mac's sidebar; a click opens Hubs
struct HubsFooter: View {
    let model: AppModel
    let hubs: [HubRow]
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(hubs.prefix(4), id: \.key) { h in HubDot(phase: model.conn[h.key]?.phase ?? .connecting) }
                }
                .font(.system(size: 8))
                Text(summary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .help("Hubs")
    }

    private var summary: String {
        guard let h = hubs.first else { return "No hub" }
        let word = HubDot.word(model.conn[h.key]?.phase ?? .connecting)
        return hubs.count == 1 ? h.name + " · " + word : "\(hubs.count) hubs · " + h.name + " " + word
    }
}
#endif

private struct SwipeButton: View {
    let model: AppModel
    let swipe: Swipe
    let choose: (Swipe) -> Void

    private var icon: String {
        switch swipe.action {
        case "row-delete": "trash"
        case "row-settle": "checkmark.circle"
        case "row-unsettle": "arrow.uturn.backward"
        default: swipe.options.isEmpty ? "sun.max" : "moon.zzz"
        }
    }

    private var tint: Color {
        switch swipe.tone {
        case "danger": .red
        case "settle": .green
        default: .indigo
        }
    }

    var body: some View {
        Button {
            if swipe.options.isEmpty { model.act(swipe.action, swipe.value) } else { choose(swipe) }
        } label: {
            Label(swipe.label, systemImage: icon)
        }
        .tint(tint)
    }
}

private struct ThreadRow: View {
    let model: AppModel
    let row: Row
    let choose: (Swipe) -> Void

    var body: some View {
        NavigationLink(value: row.id) {
            HStack(spacing: 10) {
                StatusDot(state: row.state, status: row.status).frame(width: 18)
                Text(row.title).lineLimit(1)
                Spacer()
                if row.pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
                Text(row.ago).font(.caption).foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .leading) {
            ForEach(row.lead, id: \.self) { SwipeButton(model: model, swipe: $0, choose: choose) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            ForEach(row.trail, id: \.self) { SwipeButton(model: model, swipe: $0, choose: choose) }
        }
        .macMenu {
            ForEach(row.lead + row.trail, id: \.self) { SwipeButton(model: model, swipe: $0, choose: choose) }
        }
    }
}

struct ProjectsView: View {
    let model: AppModel
    let screen: Screen
    @Binding var pairing: Bool
    // a swipe whose choices are up (a snooze)
    @State private var choosing: Swipe?

    @Environment(\.splitLayout) private var split
    // projects the sidebar has folded shut
    @State private var folded: Set<String> = []

    // a sidebar selects with the list's own selection (its rows' links
    // cannot push into the column beside it); a phone pushes
    private var selection: Binding<String?>? {
        guard split else { return nil }
        return Binding(get: { model.path.last }, set: { model.navigate($0.map { [$0] } ?? []) })
    }

    var body: some View {
        List(selection: selection) {
            if let f = screen.search, f.open {
                Section { SearchField(model: model, search: f, first: screen.projects.first?.id) }
            }
            ForEach(screen.projects) { p in
                Section(isExpanded: Binding(get: { !folded.contains(p.id) }, set: { if $0 { folded.remove(p.id) } else { folded.insert(p.id) } })) {
                    ForEach(p.threads) { ThreadRow(model: model, row: $0) { choosing = $0 } }
                    if !p.snoozed.isEmpty {
                        Text(p.snoozedShelf).font(.subheadline).foregroundStyle(.secondary)
                        ForEach(p.snoozed) { ThreadRow(model: model, row: $0) { choosing = $0 } }
                    }
                    if !p.settled.isEmpty {
                        Button { model.act("toggle-settled", p.id) } label: {
                            HStack {
                                Text(p.shelf).font(.subheadline)
                                Spacer()
                                Image(systemName: p.open ? "chevron.down" : "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.secondary)
                        if p.open { ForEach(p.settled) { ThreadRow(model: model, row: $0) { choosing = $0 } } }
                    }
                    if let arch = p.archived, !arch.isEmpty, let v = p.value {
                        Button { model.act("toggle-settled", v) } label: {
                            HStack {
                                Text("Archived \(arch.count)").font(.subheadline)
                                Spacer()
                                Image(systemName: p.archOpen == true ? "chevron.down" : "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.secondary)
                        if p.archOpen == true { ForEach(arch) { ThreadRow(model: model, row: $0) { choosing = $0 } } }
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text(p.title).textCase(nil)
                        if !p.machine.isEmpty { Text(p.machine).font(.caption2).foregroundStyle(.secondary).textCase(nil) }
                        Spacer()
                        Button { model.act("new-thread", p.id) } label: { Image(systemName: "plus") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("New thread")
                    }
                    .help(p.machine.isEmpty ? p.root : p.machine + ": " + p.root)
                    .contextMenu {
                        Button("Remove project", systemImage: "trash", role: .destructive) { model.act("proj-remove", p.id) }
                    }
                }
            }
            if !screen.hubs.isEmpty { BotsSection(model: model, screen: screen) }
        }
        .projectsListStyle(sidebar: split)
        #if os(macOS)
        .safeAreaInset(edge: .bottom, spacing: 0) { HubsFooter(model: model, hubs: screen.hubs) { pairing = true } }
        #endif
        .overlay {
            if screen.projects.isEmpty && screen.bots.isEmpty && screen.rooms.isEmpty {
                // a hub still catching up has not said what there is yet
                if let h = screen.hubs.first(where: { (model.conn[$0.key]?.phase ?? .connecting) != .online }), !screen.online {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(HubDot.word(model.conn[h.key]?.phase ?? .connecting) + " to " + h.name).foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView(screen.empty, systemImage: "folder")
                }
            }
        }
        .navigationTitle("Backplane")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .leadingBar) {
                HubsPill(model: model, hubs: screen.hubs) { pairing = true }
            }
            #endif
            ToolbarItemGroup(placement: .trailingBar) {
                // with several hubs, the picker opens on the one chosen
                if screen.hubs.count > 1 {
                    Menu {
                        ForEach(screen.hubs, id: \.key) { h in Button(h.name) { model.act("picker-open", h.key + "|") } }
                    } label: { Image(systemName: "folder.badge.plus") }
                    .menuIndicator(.hidden)
                    .accessibilityLabel("Add project")
                } else {
                    Button { model.act("picker-open") } label: { Image(systemName: "folder.badge.plus") }.accessibilityLabel("Add project")
                }
                Menu {
                    Button("Find a project", systemImage: "folder.badge.questionmark") { model.act("proj-find", screen.search?.open == true ? "off" : "on") }
                    Button("Search threads", systemImage: "magnifyingglass") { model.act("find-open", "search") }
                    Divider()
                    Button("Hubs", systemImage: "link") { pairing = true }
                    Button("Settings", systemImage: "gear") { model.act("flag", "settings") }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuIndicator(.hidden)
                .accessibilityLabel("More")
            }
        }
        .confirmationDialog(choosing?.label ?? "", isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }),
                            titleVisibility: .visible, presenting: choosing) { s in
            ForEach(s.options, id: \.self) { o in Button(o.label) { model.act(s.action, o.value) } }
        }
        .sheet(isPresented: Binding(get: { screen.folders != nil }, set: { if !$0 { model.act("proj-close") } })) {
            if let f = screen.folders { FoldersSheet(model: model, folders: f).macSheet(width: 560, height: 520) }
        }
        .sheet(isPresented: Binding(get: { screen.newBot != nil }, set: { if !$0 { model.act("form-close", "@bnew") } })) {
            if let f = model.screen?.newBot { NewBotSheet(model: model, form: f).macSheet(width: 520, height: 480) }
        }
        .sheet(isPresented: Binding(get: { screen.newRoom != nil }, set: { if !$0 { model.act("form-close", "@rnew") } })) {
            if let f = model.screen?.newRoom { NewRoomSheet(model: model, form: f).macSheet(width: 520, height: 480) }
        }
    }
}

// the project search's field: typing filters the list ("proj-find-q"),
// return goes to the first project shown ("proj-go"), the x shuts it
private struct SearchField: View {
    let model: AppModel
    let search: Search
    let first: String?
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(search.hint, text: $text)
                .plainTextInput()
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.go)
                .onChange(of: text) { _, t in if t != search.query { model.act("proj-find-q", t) } }
                .onSubmit { if let f = first { model.act("proj-go", f) } }
            Button { model.act("proj-find", "off") } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .accessibilityLabel("Close search")
        }
        .onAppear { text = search.query; focused = true }
    }
}

// the project picker: a path field over the listed folder's rows
private struct FoldersSheet: View {
    let model: AppModel
    let folders: Folders
    @State private var text = ""
    // what was typed here: a screen still echoing it never overwrites the field
    @State private var typed: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(folders.hint, text: $text)
                        .font(.body.monospaced())
                        .plainTextInput()
                        .autocorrectionDisabled()
                        .onChange(of: text) { _, t in
                            guard t != folders.text else { return }
                            typed.insert(t)
                            model.act("picker-type", t)
                        }
                    if !folders.error.isEmpty { Text(folders.error).font(.footnote).foregroundStyle(.red) }
                }
                Section {
                    ForEach(folders.items, id: \.self) { r in
                        Button { model.act(r.action, r.value) } label: {
                            Label(r.label, systemImage: Self.icon(r.kind)).lineLimit(1).truncationMode(.head)
                        }
                        .disabled(r.action.isEmpty)
                        .tint(r.kind == "dir" || r.kind == "up" ? .primary : .accentColor)
                    }
                }
            }
            .navigationTitle("Add project")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.act("proj-close") } }
            }
        }
        .onAppear { text = folders.text }
        .onChange(of: folders.text) { _, t in
            if !typed.contains(t) { typed = []; text = t }
        }
    }

    static func icon(_ kind: String) -> String {
        switch kind {
        case "up": "arrow.turn.left.up"
        case "add": "plus.circle"
        case "new": "folder.badge.plus"
        case "mkdir": "folder.badge.plus"
        case "off": "checkmark.circle"
        default: "folder"
        }
    }
}

// What a pushed id shows. The screen's own thread (or bot) once the client
// has selected it; until then the same thread as it was last shown, or its
// title from the list. Never another thread: the screen may still hold the
// one before for a moment after a tap.
struct ThreadDestination: View {
    let model: AppModel
    let id: String

    private var selected: Bool { model.screen.map { AppModel.nav($0) == id } ?? false }

    var body: some View {
        if selected, let b = model.screen?.bot {
            BotDestination(model: model, bot: b)
        } else if let t = selected ? model.screen?.thread : model.seen[id] {
            ThreadScreen(model: model, thread: t, live: selected).id(id)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(title)
                .inlineTitle()
        }
    }

    // the row's title in the list, while nothing of the thread is known
    private var title: String {
        for p in model.screen?.projects ?? [] {
            for r in p.threads + p.snoozed + p.settled + (p.archived ?? []) where r.id == id { return r.title }
        }
        return ""
    }
}

// a message on its way: at once when sent, until the hub has it
private struct SendingBubble: View {
    let text: String
    let note: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(text)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 18))
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(note)
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .opacity(0.7)
    }
}

struct ThreadScreen: View {
    @Bindable var model: AppModel
    let thread: ThreadView
    // the client has this thread selected (else it shows as last seen,
    // for the moment the select takes, and takes no input)
    var live = true
    @FocusState private var focused: Bool
    // the image open in the lightbox
    @State private var shown: Shown?
    // the entry that was first when earlier ones were asked for
    @State private var keepAt: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // not lazy: a page is at most a few dozen entries, and with
                // every height known on the first frame the view opens at the
                // bottom and stays there (a lazy stack measured rows as they
                // came and the text jumped)
                VStack(alignment: .leading, spacing: 14) {
                    if let p = thread.parent { EntryRow(model: model, entry: p) { shown = $0 } }
                    if let ts = thread.tasks, !ts.isEmpty { TasksView(model: model, tasks: ts) }
                    // scrolled up to the top while earlier entries are left
                    // out: they are shown, no button, and the view stays on
                    // the entry that was first
                    if let n = thread.earlier, n > 0 {
                        Color.clear.frame(height: 1).background(GeometryReader { g in
                            Color.clear.onChange(of: g.frame(in: .named("timeline")).minY) { _, y in
                                if y > -400 && keepAt == nil {
                                    keepAt = thread.entries.first?.id
                                    model.act("earlier", "")
                                }
                            }
                        })
                    }
                    ForEach(thread.entries) { EntryRow(model: model, entry: $0) { shown = $0 }.id($0.id) }
                    // the client's sending rows, then those tapped here it has
                    // not answered yet, by place: one handed over keeps its place
                    ForEach(Array(sending.enumerated()), id: \.offset) { _, text in
                        SendingBubble(text: text, note: sendNote)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    }
                    if !thread.live.isEmpty {
                        MarkdownView(blocks: thread.live)
                    } else if !thread.working.isEmpty {
                        HStack(spacing: 8) {
                            if thread.state == "run" { ProgressView().controlSize(.small).tint(PhaseColor.accent) }
                            else { StatusDot(state: thread.state, status: thread.phase) }
                            Text(thread.working).foregroundStyle(.secondary)
                        }
                        .font(thread.state == "run" ? .body : .caption)
                    }
                    if let ag = thread.agents, !ag.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(ag.enumerated()), id: \.offset) { _, a in
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.mini)
                                    Text(a.isEmpty ? "Subagent" : a).lineLimit(2)
                                }
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding()
                .animation(.spring(duration: 0.3), value: sending)
            }
            .coordinateSpace(name: "timeline")
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.scrolls) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: mine.count) { old, new in
                if new > old { withAnimation(.spring(duration: 0.3)) { proxy.scrollTo("end", anchor: .bottom) } }
            }
            // held at the bottom with no animation: a scroll animated from
            // wherever the old content left it read as the text snapping
            .onChange(of: thread.entries.last?.id) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: thread.entries.first?.id) {
                if let k = keepAt { proxy.scrollTo(k, anchor: .top); keepAt = nil }
            }
        }
        .safeAreaInset(edge: .bottom) {
          VStack(spacing: 0) {
            ForEach(thread.asks ?? []) { a in
                AskCard(model: model, ask: a).padding(.horizontal).padding(.top, 8)
            }
            if let td = thread.todos {
                VStack(alignment: .leading, spacing: 2) {
                    Text(td.head).bold()
                    ForEach(Array(td.lines.enumerated()), id: \.offset) { _, l in
                        Text(l.text).lineLimit(1).foregroundStyle(l.status == "completed" ? .secondary : .primary)
                    }
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal).padding(.top, 8)
            }
            ForEach(thread.queue ?? [], id: \.msg) { q in
                HStack(spacing: 6) {
                    Text(q.tag).bold()
                    Text(q.text).lineLimit(1)
                    Spacer(minLength: 0)
                    ForEach(q.buttons, id: \.label) { b in
                        Button(b.label) { model.act(b.action, b.value) }.buttonStyle(.borderless)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal).padding(.top, 8)
            }
            ComposerExtras(model: model, thread: thread)
            // one card: the text, then attach, the model and send along its foot
            VStack(alignment: .leading, spacing: 10) {
                TextField("Ask the agent", text: Binding(get: { model.composer }, set: { model.draft($0) }), axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($focused)
                    .sendKeys(send: { if !model.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.send() } },
                              alt: { if !model.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.send("send-alt") } })
                HStack(spacing: 10) {
                    AttachButton(model: model)
                    Menu {
                        Section("Model") {
                            ForEach(thread.picker.models, id: \.value) { c in
                                Button { model.act("model", c.value) } label: {
                                    if c.on { Label(c.label, systemImage: "checkmark") } else { Text(c.label) }
                                }
                            }
                        }
                        if !thread.picker.efforts.isEmpty {
                            Section("Effort") {
                                ForEach(thread.picker.efforts, id: \.value) { c in
                                    Button { model.act("effort", c.value) } label: {
                                        if c.on { Label(c.label, systemImage: "checkmark") } else { Text(c.label) }
                                    }
                                }
                            }
                        }
                        if let ps = thread.picker.providers, !ps.isEmpty {
                            Section("Provider") {
                                ForEach(ps, id: \.value) { c in
                                    Button { model.act("effort", c.value) } label: {
                                        if c.on { Label(c.label, systemImage: "checkmark") } else { Text(c.label) }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(thread.picker.label).lineLimit(1)
                            Image(systemName: "chevron.down")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: .capsule)
                    }
                    .plainMenu()
                    .accessibilityLabel("Model and effort: " + thread.picker.label)
                    Spacer(minLength: 0)
                    // a long press sends with the other follow-up mode (queue or steer);
                    // while a turn runs with nothing typed the button stops it
                    let blank = model.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let stop = thread.sendAct == "interrupt" && blank
                    Image(systemName: stop ? "stop.circle.fill" : "arrow.up.circle.fill").font(.system(size: 26))
                        .foregroundStyle(stop ? Color.red : blank ? Color.secondary : Color.accentColor)
                        .onTapGesture {
                            if stop { model.act("interrupt") } else if !blank { model.send() }
                        }
                        .onLongPressGesture {
                            if !model.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.send("send-alt") }
                        }
                        .accessibilityLabel(thread.send)
                        .accessibilityAddTraits(.isButton)
                }
            }
            .padding(12)
            // a click anywhere on the card (not only on the text's line) types
            .background { Color.secondaryBackground.clipShape(.rect(cornerRadius: 14)).onTapGesture { focused = true } }
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.2)).allowsHitTesting(false))
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 12)
          }
          .disabled(!live)
          .background(.bar)
        }
        .navigationTitle(thread.title)
        .windowSubtitle(thread.branch)
        .inlineTitle()
        .boardViewer(model: model, open: !thread.viewer.open.isEmpty)
        .fullScreen(item: $shown) { s in Lightbox(shown: s) { shown = nil } }
        .sheet(isPresented: Binding(get: { thread.diff != nil }, set: { if !$0, model.screen?.thread?.diff != nil { model.act("panel") } })) {
            if let d = model.screen?.thread?.diff { DiffSheet(model: model, diff: d).macSheet(width: 900, height: 640) }
        }
        .sheet(isPresented: Binding(get: { thread.term != nil }, set: { if !$0, model.screen?.thread?.term != nil { model.act("term-toggle") } })) {
            if let t = model.screen?.thread?.term { TermSheet(model: model, term: t).presentationDetents([.large]).macTerminalSheet() }
        }
        .toolbar {
            #if os(iOS)
            if !thread.branch.isEmpty {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(thread.title).font(.headline).lineLimit(1)
                        Text(thread.branch).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            #endif
            ToolbarItemGroup(placement: .trailingBar) {
                if !thread.viewer.choices.isEmpty {
                    Menu {
                        ForEach(thread.viewer.choices, id: \.value) { c in
                            Button(c.label) { model.act("view", c.value) }
                        }
                    } label: {
                        Image(systemName: "cpu")
                    }
                    .menuIndicator(.hidden)
                    .accessibilityLabel("Board viewer")
                }
                ForEach(thread.tools.filter { $0.action == "interrupt" }, id: \.self) { t in
                    Button(t.label, systemImage: "stop.fill") { model.act(t.action) }
                }
                Menu {
                    ForEach(thread.tools.filter { $0.action != "interrupt" }, id: \.self) { t in
                        Button { model.act(t.action, t.value ?? "") } label: {
                            if t.on { Label(t.label, systemImage: "checkmark") } else { Text(t.label) }
                        }
                    }
                    Divider()
                    ForEach(thread.menu ?? [], id: \.self) { t in
                        if let os = t.options, !os.isEmpty {
                            Menu(t.label) {
                                ForEach(os, id: \.self) { o in Button(o.label) { model.act(t.action, o.value) } }
                            }
                        } else {
                            Button(role: t.danger == true ? .destructive : nil) {
                                // the terminal opens at the size this phone has room for
                                model.act(t.action, t.action == "term-toggle" ? TermSheet.size() : t.value ?? "")
                            } label: {
                                if t.on { Label(t.label, systemImage: "checkmark") } else { Label(t.label, systemImage: Self.icon(t.action)) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
            }
        }
    }

    // this thread's messages tapped here and not yet answered
    private var mine: [Outgoing] { model.outgoing.filter { $0.thread == thread.id } }

    private var sending: [String] { thread.sending + mine.map(\.text) }

    // what a message on its way waits for
    private var sendNote: String {
        guard let s = model.screen else { return "Sending…" }
        let c = model.conn[s.hub]?.phase ?? .connecting
        return c == .online || c == .syncing ? "Sending…" : "Waiting for " + (s.hubs.first { $0.key == s.hub }?.name ?? "the hub") + "…"
    }

    static func icon(_ action: String) -> String {
        switch action {
        case "diff": "plusminus"
        case "term-toggle": "terminal"
        case "find-open": "doc.text.magnifyingglass"
        case "snooze": "moon.zzz"
        case "row-delete": "trash"
        default: "circle"
        }
    }
}
