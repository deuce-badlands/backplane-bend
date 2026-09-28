import Foundation
import Testing
@testable import Backplane

// What the app asks the hub for: the send commands bridge.js answers an
// action with, their CBOR frames read back.
@Suite("Requests to the hub", .serialized)
struct BridgeRequestTests {
    // the text values of every frame an answer sends to the hub
    private func sent(_ text: String, to hub: String) throws -> [[String]] {
        let out = try JSONDecoder().decode(Out.self, from: Data(text.utf8))
        return try out.cmds.filter { $0.type == "send" }.map { c in
            #expect(c.hub == hub)
            let d = try #require(Data(base64Encoded: c.data ?? ""), "a send's data is not base64")
            let frame = try #require(CBOR.decode(d), "a send's frame is not CBOR")
            return CBOR.strings(frame)
        }
    }

    private func scene(_ name: String) throws -> (Bridge, Fixture) {
        let f = try Fixture.load(name)
        let b = Bridge()
        _ = b.play(f)
        return (b, f)
    }

    @Test("opening Settings asks for the voice status")
    func voiceStatus() throws {
        let (b, f) = try scene("projects")
        let frames = try sent(b.call("act", ["flag", "settings"]), to: f.hub)
        #expect(frames.count == 1)
        #expect(frames.first?.contains("status") == true)
    }

    @Test("a setting is asked of the hub, not set here")
    func setting() throws {
        let (b, f) = try scene("settings")
        let text = b.call("act", ["setting", "text.model=sonnet"])
        let frames = try sent(text, to: f.hub)
        #expect(frames.count == 1)
        #expect(frames.first?.contains("text.model") == true)
        #expect(frames.first?.contains("sonnet") == true)
        // the row changes only when the hub confirms it
        let out = try JSONDecoder().decode(Out.self, from: Data(text.utf8))
        let model = out.screen?.settings?.rows.first { $0.section == "Writing" && $0.label == "Model" }
        #expect(model?.buttons.first { $0.on }?.label == "Haiku 4.5")
    }

    @Test("a typed key goes up with Save")
    func voiceKey() throws {
        let (b, f) = try scene("settings")
        _ = b.call("quiet", ["bfield", "vkey\u{1f}sk-proj-new"])
        let frames = try sent(b.call("act", ["voice-key", ""]), to: f.hub)
        #expect(frames.contains { $0.contains("sk-proj-new") })
    }
}
