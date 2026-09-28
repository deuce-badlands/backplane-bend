import SwiftUI

// The agent's questions, where the composer was. One question at a time:
// its header, the question, the options (with their descriptions, the
// recommended one badged and picked to start with), an answer in your own
// words, and "Discuss this" to talk it through first. Every question gets
// an answer, and they go back together as one JSON object (question text ->
// answer), which bend hands to Claude as AskUserQuestion's answers.
// With a keyboard: 1-9 picks an option, return goes on (or sends).
struct QuestionDock: View {
    let model: AppModel
    let ask: Ask
    // switch to the ordinary composer (the questions wait)
    let typeInstead: () -> Void

    // what a question is answered with: options picked, words of one's own,
    // or a talk first
    enum Choice: Equatable { case options(Set<Int>), own, discuss }

    @State private var at = 0
    @State private var choices: [Int: Choice] = [:]
    @State private var own: [Int: String] = [:]
    @FocusState private var focused: Bool
    @FocusState private var writing: Bool

    private var questions: [AskQuestion] { ask.questions ?? [] }
    private var q: AskQuestion { questions[min(at, questions.count - 1)] }
    private var last: Bool { at >= questions.count - 1 }

    static let discussAnswer = "Let's discuss this before deciding. Explain the trade-offs between the options and wait for my reply."

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(.tint)
                Text(questions.count > 1 ? "The agent asks \(questions.count) questions" : "The agent asks").font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if questions.count > 1 { progress }
            }
            if let h = q.header, !h.isEmpty {
                Text(h.uppercased())
                    .font(.caption2.weight(.bold)).tracking(0.4)
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: .capsule)
            }
            Text(q.question).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array((q.options ?? []).enumerated()), id: \.offset) { i, o in
                        optionRow(i, o)
                    }
                    ownRow
                    discussRow
                }
            }
            .frame(maxHeight: 340)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Type a message instead", action: typeInstead)
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if at > 0 { Button("Back") { at -= 1 }.buttonStyle(.bordered) }
                Button(last ? "Send answers" : "Next") { next() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!answered(at))
            }
            #if os(macOS)
            Text("1–\(min(9, (q.options ?? []).count)) pick · return \(last ? "sends" : "goes on")")
                .font(.caption2).foregroundStyle(.tertiary)
            #endif
        }
        .padding(14)
        .background(.bar)
        .overlay(alignment: .top) { Rectangle().fill(Color.accentColor.opacity(0.5)).frame(height: 1) }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { key($0) }
        .onAppear { start() }
        .onChange(of: ask.id) { at = 0; choices = [:]; own = [:]; start() }
        .onChange(of: at) { if choices[at] == nil { choices[at] = recommended(at) } }
    }

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< questions.count, id: \.self) { i in
                Circle().fill(i == at ? Color.accentColor : answered(i) ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
            Text("\(at + 1) of \(questions.count)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    // an option's label without Claude's "(Recommended)" marker, and whether it had one
    static func split(_ label: String) -> (String, Bool) {
        let marker = "(Recommended)"
        guard label.contains(marker) else { return (label, false) }
        return (label.replacingOccurrences(of: marker, with: "").trimmingCharacters(in: .whitespaces), true)
    }

    private func optionRow(_ i: Int, _ o: AskOption) -> some View {
        let (label, rec) = Self.split(o.label)
        let on = { if case .options(let s) = choices[at] { return s.contains(i) }; return false }()
        let multi = q.multiSelect == true
        return Button { pick(i) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: multi ? (on ? "checkmark.square.fill" : "square") : (on ? "largecircle.fill.circle" : "circle"))
                    .foregroundStyle(on ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(label).font(.callout.weight(.semibold))
                        if rec {
                            Text("Recommended").font(.caption2.weight(.bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.green.opacity(0.18), in: .rect(cornerRadius: 4))
                                .foregroundStyle(.green)
                        }
                    }
                    if let d = o.description, !d.isEmpty {
                        Text(d).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                #if os(macOS)
                if i < 9 { Text("\(i + 1)").font(.caption2.monospaced()).foregroundStyle(.tertiary) }
                #endif
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Color.accentColor : Color.secondary.opacity(0.2)).allowsHitTesting(false))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // an answer in the person's own words
    private var ownRow: some View {
        let on = choices[at] == .own
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "pencil").foregroundStyle(on ? Color.accentColor : .secondary).frame(width: 16)
            TextField("Answer in your own words…", text: Binding(get: { own[at] ?? "" }, set: { own[at] = $0; choices[at] = $0.isEmpty ? recommended(at) : .own }), axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($writing)
                .onSubmit { next() }
        }
        .padding(10)
        .background(on ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Color.accentColor : Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: on ? [] : [4, 3])).allowsHitTesting(false))
        .contentShape(.rect)
        .onTapGesture { writing = true }
    }

    // talk it through first: the agent explains the trade-offs and waits
    private var discussRow: some View {
        let on = choices[at] == .discuss
        return Button { choices[at] = on ? recommended(at) : .discuss } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(on ? Color.accentColor : .secondary).frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Discuss this").font(.callout.weight(.semibold))
                    Text("The agent explains the trade-offs and waits for your reply before deciding.").font(.caption).foregroundStyle(.secondary)
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
    }

    private func start() {
        for i in questions.indices where choices[i] == nil { choices[i] = recommended(i) }
        focused = true
    }

    // the recommended option picked to start with (nothing when none is)
    private func recommended(_ i: Int) -> Choice? {
        i < questions.count ? Self.recommended(questions[i]) : nil
    }

    static func recommended(_ q: AskQuestion) -> Choice? {
        (q.options ?? []).firstIndex { split($0.label).1 }.map { .options([$0]) }
    }

    private func pick(_ i: Int) {
        if q.multiSelect == true {
            var s: Set<Int> = { if case .options(let s) = choices[at] { return s }; return [] }()
            if s.contains(i) { s.remove(i) } else { s.insert(i) }
            choices[at] = s.isEmpty ? nil : .options(s)
        } else {
            choices[at] = .options([i])
        }
    }

    private func answered(_ i: Int) -> Bool {
        Self.answered(choices[i], own: own[i])
    }

    static func answered(_ c: Choice?, own: String?) -> Bool {
        switch c {
        case .options(let s)?: !s.isEmpty
        case .own?: !(own ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .discuss?: true
        case nil: false
        }
    }

    // a question's answer as Claude reads it: the options' labels (without
    // the marker, in their order), the words typed, or the ask to discuss
    static func answer(_ q: AskQuestion, _ c: Choice?, own: String?) -> String {
        let opts = q.options ?? []
        switch c {
        case .options(let s)?: return s.sorted().compactMap { $0 < opts.count ? split(opts[$0].label).0 : nil }.joined(separator: ", ")
        case .own?: return (own ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        case .discuss?: return discussAnswer
        case nil: return ""
        }
    }

    // the "answer" action's value: the ask, then every question's answer
    // as JSON (question text -> answer)
    static func reply(_ ask: Ask, choices: [Int: Choice], own: [Int: String]) -> String? {
        let qs = ask.questions ?? []
        var m: [String: String] = [:]
        for i in qs.indices { m[qs[i].question] = answer(qs[i], choices[i], own: own[i]) }
        guard let d = try? JSONSerialization.data(withJSONObject: m, options: [.sortedKeys]), let json = String(data: d, encoding: .utf8) else { return nil }
        return ask.id + "|" + json
    }

    private func next() {
        guard answered(at) else { return }
        if !last { at += 1; return }
        if let v = Self.reply(ask, choices: choices, own: own) { model.act("answer", v) }
    }

    private func key(_ p: KeyPress) -> KeyPress.Result {
        if writing { return .ignored }
        if p.key == .return { next(); return .handled }
        if let c = p.characters.first, let n = c.wholeNumberValue, n >= 1, n <= min(9, (q.options ?? []).count) {
            pick(n - 1)
            return .handled
        }
        return .ignored
    }
}
