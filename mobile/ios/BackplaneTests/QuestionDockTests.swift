import Foundation
import Testing
@testable import Backplane

// The question dock as the app gets it: the dock bridge.js puts on the
// thread's screen (src/mobile/dock.bend decides it; test/mdock_test.bend
// and the dock laws check what it decides), and what its actions ask the
// hub for, read back from their CBOR.
@Suite("Question dock", .serialized)
struct QuestionDockTests {
    private func scene() throws -> (Bridge, Fixture) {
        let f = try Fixture.load("thread-question")
        let b = try Bridge()
        _ = b.play(f)
        return (b, f)
    }

    private func dock(_ text: String) throws -> Dock {
        let out = try JSONDecoder().decode(Out.self, from: Data(text.utf8))
        return try #require(out.screen?.thread?.dock, "no dock on the thread's screen")
    }

    @Test("the dock: its questions, the recommended option picked")
    func shown() throws {
        let (b, _) = try scene()
        let d = try dock(b.call("screen", []))
        #expect(d.id == "k1")
        #expect(d.at == 0)
        #expect(d.questions.map(\.header) == ["Regulator", "Power good", "Placement"])
        #expect(d.questions[0].options.map(\.label) == ["TPS62840", "TPS62162", "AP62300"])
        #expect(d.questions[0].options.map(\.recommended) == [true, false, false])
        #expect(d.questions[0].options.map(\.on) == [true, false, false])
        #expect(d.questions[1].multi)
        #expect(!d.questions[1].answered)
        #expect(!d.ready && !d.sent)
    }

    @Test("picks, words and discuss come back on the screen")
    func actions() throws {
        let (b, _) = try scene()
        #expect(try dock(b.call("act", ["q-pick", "k1|1|2"])).questions[1].options.map(\.on) == [false, false, true])
        let own = try dock(b.call("act", ["q-own", "k1|0|the one we stock"])).questions[0]
        #expect(own.mode == "own" && own.own == "the one we stock")
        #expect(try dock(b.call("act", ["q-own", "k1|0|"])).questions[0].options.map(\.on) == [true, false, false])
        #expect(try dock(b.call("act", ["q-discuss", "k1|2"])).questions[2].mode == "discuss")
        #expect(try dock(b.call("act", ["q-go", "k1|2"])).at == 2)
        #expect(try dock(b.call("screen", [])).ready)
    }

    @Test("Send asks the hub once, with every answer")
    func send() throws {
        let (b, f) = try scene()
        _ = b.call("act", ["q-pick", "k1|1|0"])
        _ = b.call("act", ["q-pick", "k1|1|1"])
        let out = try JSONDecoder().decode(Out.self, from: Data(b.call("act", ["q-send", "k1"]).utf8))
        let sends = out.cmds.filter { $0.type == "send" }
        #expect(sends.count == 1)
        #expect(sends.first?.hub == f.hub)
        let frame = try #require(sends.first.flatMap { Data(base64Encoded: $0.data ?? "") }.flatMap(CBOR.decode))
        let texts = CBOR.strings(frame)
        #expect(texts.contains("k1"))
        #expect(texts.contains("TPS62840"))
        #expect(texts.contains("3V3, 1V8"))
        #expect(texts.contains("Top, beside U7"))
        #expect(try dock(b.call("screen", [])).sent)
        let again = try JSONDecoder().decode(Out.self, from: Data(b.call("act", ["q-send", "k1"]).utf8))
        #expect(again.cmds.filter { $0.type == "send" }.isEmpty)
    }
}
