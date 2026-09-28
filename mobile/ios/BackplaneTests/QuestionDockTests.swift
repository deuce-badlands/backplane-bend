import Foundation
import Testing
@testable import Backplane

// The question dock's answers: what each choice sends, as AskUserQuestion's
// answers map (question text -> answer).
@Suite("Question dock")
struct QuestionDockTests {
    private let regulator = AskQuestion(question: "Which regulator?", header: "Regulator", multiSelect: false, options: [
        AskOption(label: "TPS62840 (Recommended)", description: "Lowest quiescent current."),
        AskOption(label: "TPS62162", description: nil),
    ])
    private let rails = AskQuestion(question: "Which rails?", header: nil, multiSelect: true, options: [
        AskOption(label: "3V3", description: nil), AskOption(label: "1V8", description: nil), AskOption(label: "5V", description: nil),
    ])

    @Test("the Recommended marker is a badge, not part of the answer")
    func marker() {
        #expect(QuestionDock.split("TPS62840 (Recommended)") == ("TPS62840", true))
        #expect(QuestionDock.split("TPS62162") == ("TPS62162", false))
        #expect(QuestionDock.split("(Recommended) First") == ("First", true))
    }

    @Test("the recommended option is picked to start with")
    func recommended() {
        #expect(QuestionDock.recommended(regulator) == .options([0]))
        #expect(QuestionDock.recommended(rails) == nil)
    }

    @Test("an answer: the options' labels, in their order")
    func options() {
        #expect(QuestionDock.answer(regulator, .options([0]), own: nil) == "TPS62840")
        #expect(QuestionDock.answer(rails, .options([2, 0]), own: nil) == "3V3, 5V")
        // an index past the options (a stale choice) is left out
        #expect(QuestionDock.answer(rails, .options([1, 9]), own: nil) == "1V8")
    }

    @Test("own words, trimmed; discuss; nothing")
    func others() {
        #expect(QuestionDock.answer(regulator, .own, own: "  the one we stock \n") == "the one we stock")
        #expect(QuestionDock.answer(regulator, .discuss, own: nil) == QuestionDock.discussAnswer)
        #expect(QuestionDock.answer(regulator, nil, own: nil) == "")
    }

    @Test("what counts as answered")
    func answered() {
        #expect(QuestionDock.answered(.options([1]), own: nil))
        #expect(!QuestionDock.answered(.options([]), own: nil))
        #expect(!QuestionDock.answered(.own, own: "   "))
        #expect(QuestionDock.answered(.own, own: "x"))
        #expect(QuestionDock.answered(.discuss, own: nil))
        #expect(!QuestionDock.answered(nil, own: "typed but not chosen"))
    }

    @Test("the answer action: the ask, then every answer as JSON")
    func reply() throws {
        let ask = Ask(id: "k1", kind: "input", head: "", detail: "", blocks: [], buttons: [], questions: [regulator, rails])
        let v = try #require(QuestionDock.reply(ask, choices: [0: .own, 1: .options([0, 1])], own: [0: "TPS62840 or better"]))
        #expect(v.hasPrefix("k1|"))
        let json = try #require(try JSONSerialization.jsonObject(with: Data(v.dropFirst(3).utf8)) as? [String: String])
        #expect(json == ["Which regulator?": "TPS62840 or better", "Which rails?": "3V3, 1V8"])
    }
}
