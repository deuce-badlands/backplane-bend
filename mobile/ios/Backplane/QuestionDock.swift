import SwiftUI

// The agent's questions, where the composer was (src/mobile/dock.bend
// decides what they are, what is picked and what is sent; this draws the
// screen's dock and sends its actions). One question at a time: its header,
// the question, the options (their descriptions, the recommended one
// badged), an answer in your own words, and "Discuss this" to talk it
// through first; Back and Next go between them, Send answers them all.
// With a keyboard: 1-9 picks an option, return goes on (or sends),
// cmd+return sends from the words, escape goes back to typing a message.
struct QuestionDock: View {
    let model: AppModel
    let dock: Dock
    // switch to the ordinary composer (the questions wait, as they are)
    let typeInstead: () -> Void

    @Environment(\.splitLayout) private var split
    // the words being typed, and what was typed here: a screen still
    // echoing them never overwrites the field
    @State private var text = ""
    @State private var typed: Set<String> = []
    // Send pressed: nothing more is sent until the screen says it went
    @State private var sending = false
    @FocusState private var focused: Bool
    @FocusState private var writing: Bool

    private var at: Int { min(max(dock.at, 0), dock.questions.count - 1) }
    private var q: DockQuestion { dock.questions[at] }
    private var last: Bool { at >= dock.questions.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(.tint).accessibilityHidden(true)
                Text(dock.questions.count > 1 ? "The agent asks \(dock.questions.count) questions" : "The agent asks").font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if dock.questions.count > 1 { progress }
            }
            VStack(alignment: .leading, spacing: 10) {
                if !q.header.isEmpty {
                    Text(q.header.uppercased())
                        .font(.caption2.weight(.bold)).tracking(0.4)
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: .capsule)
                }
                Text(q.question).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in optionRow(i, o) }
                        ownRow
                        discussRow
                    }
                }
                // a phone keeps room for the thread above
                .frame(maxHeight: split ? 340 : 200)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(q.question)
            HStack(spacing: 10) {
                Button("Type a message instead", action: typeInstead)
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if at > 0 { Button("Back") { model.act("q-go", "\(dock.id)|\(at - 1)") }.buttonStyle(.bordered) }
                Button(last ? "Send answers" : "Next") { next() }
                    .buttonStyle(.borderedProminent)
                    .disabled(last ? !dock.ready || dock.sent || sending : !q.answered)
            }
            #if os(macOS)
            Text(hint).font(.caption2).foregroundStyle(.secondary)
            #endif
        }
        .padding(14)
        .background(.bar)
        .overlay(alignment: .top) { Rectangle().fill(Color.accentColor.opacity(0.5)).frame(height: 1).allowsHitTesting(false) }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { key($0) }
        .onAppear { load(); focused = true }
        .onChange(of: at) { load() }
        .onChange(of: q.own) { _, t in if !typed.contains(t) { text = t }; typed = [] }
        .onChange(of: dock.id) { sending = false; load() }
        .onChange(of: dock.sent) { _, s in if !s { sending = false } }
    }

    private var hint: String {
        let n = min(9, q.options.count)
        let go = "return \(last ? "sends" : "goes on") · esc types a message"
        return n > 0 ? "1–\(n) pick · " + go : go
    }

    private func load() {
        text = q.own
        typed = []
    }

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(Array(dock.questions.enumerated()), id: \.offset) { i, d in
                Circle().fill(i == at ? Color.accentColor : d.answered ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
            Text("\(at + 1) of \(dock.questions.count)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Question \(at + 1) of \(dock.questions.count), \(dock.questions.filter(\.answered).count) answered")
    }

    private func optionRow(_ i: Int, _ o: DockOption) -> some View {
        Button { model.act("q-pick", "\(dock.id)|\(at)|\(i)") } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: q.multi ? (o.on ? "checkmark.square.fill" : "square") : (o.on ? "largecircle.fill.circle" : "circle"))
                    .foregroundStyle(o.on ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(o.label).font(.callout.weight(.semibold))
                        if o.recommended {
                            Text("Recommended").font(.caption2.weight(.bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.green.opacity(0.18), in: .rect(cornerRadius: 4))
                                .foregroundStyle(.green)
                        }
                    }
                    if !o.description.isEmpty {
                        Text(o.description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                #if os(macOS)
                if i < 9 { Text("\(i + 1)").font(.caption2.monospaced()).foregroundStyle(.tertiary).accessibilityHidden(true) }
                #endif
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(o.on ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(o.on ? Color.accentColor : Color.secondary.opacity(0.2)).allowsHitTesting(false))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(o.on ? .isSelected : [])
        .accessibilityHint(q.multi ? "Select any" : "Select one")
    }

    // an answer in the person's own words: each change goes to Bend, which
    // makes it the answer (and, emptied, goes back to the options picked)
    private var ownRow: some View {
        let on = q.mode == "own"
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "pencil").foregroundStyle(on ? Color.accentColor : .secondary).frame(width: 16).accessibilityHidden(true)
            TextField("Answer in your own words…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($writing)
                .onChange(of: text) { _, t in
                    guard t != q.own else { return }
                    typed.insert(t)
                    model.act("q-own", "\(dock.id)|\(at)|\(t)")
                }
                // cmd+return sends from here (return writes a new line)
                .onKeyPress(.return, phases: .down) { k in
                    guard k.modifiers.contains(.command) else { return .ignored }
                    next()
                    return .handled
                }
                .onKeyPress(.escape) { typeInstead(); return .handled }
        }
        .padding(10)
        .background(on ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Color.accentColor : Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: on ? [] : [4, 3])).allowsHitTesting(false))
        .contentShape(.rect)
        .onTapGesture { writing = true }
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // talk it through first: the agent explains the trade-offs and waits
    private var discussRow: some View {
        let on = q.mode == "discuss"
        return Button { model.act("q-discuss", "\(dock.id)|\(at)") } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(on ? Color.accentColor : .secondary).frame(width: 16).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dock.discuss).font(.callout.weight(.semibold))
                    Text(dock.discussNote).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Color.accentColor : Color.secondary.opacity(0.2)).allowsHitTesting(false))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func next() {
        if !last {
            if q.answered { model.act("q-go", "\(dock.id)|\(at + 1)") }
            return
        }
        guard dock.ready, !dock.sent, !sending else { return }
        sending = true
        model.act("q-send", dock.id)
    }

    private func key(_ p: KeyPress) -> KeyPress.Result {
        if writing { return .ignored }
        if p.key == .escape { typeInstead(); return .handled }
        if p.key == .return { next(); return .handled }
        if let c = p.characters.first, let n = c.wholeNumberValue, n >= 1, n <= min(9, q.options.count) {
            model.act("q-pick", "\(dock.id)|\(at)|\(n - 1)")
            return .handled
        }
        return .ignored
    }
}
