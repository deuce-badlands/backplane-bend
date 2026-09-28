import Foundation
import Testing
@testable import Backplane

// Every answer bridge.js gives for every scene decodes into the app's
// types. Out.decode drops an answer it cannot read (the app then keeps its
// last screen), so a field renamed on one side shows only as a screen that
// never changes; decoding with a throwing decoder here names the field.
@Suite("Scenes decode", .serialized)
struct SceneDecodingTests {
    @Test("the scenes are in the bundle")
    func bundled() {
        // test/apple_fixtures.bend writes eleven
        #expect(Fixture.names.count == 11, "\(Fixture.names)")
    }

    @Test("every answer decodes", arguments: Fixture.names)
    func everyAnswer(_ name: String) throws {
        let f = try Fixture.load(name)
        let b = try Bridge()
        let outs = b.play(f)
        #expect(b.errors.isEmpty, "bridge.js threw: \(b.errors)")
        for (i, text) in outs.enumerated() {
            let out = try JSONDecoder().decode(Out.self, from: Data(text.utf8))
            #expect(out.screen != nil, "answer \(i) of \(name) has no screen")
        }
    }

    // The tests' own encoder writes every key and string out; a hub sends
    // its dictionaries' indexes. The same frame both ways gives the same
    // screens, so the scenes stand for what a hub really sends.
    @Test("the hub's own encoding reads as the tests' does")
    func hubEncoding() throws {
        let plain = try Bridge().play(Fixture.load("projects"))
        let wire = try Bridge().play(Fixture.load("projects-wire"))
        #expect(wire.count == plain.count)
        #expect(wire == plain)
        // and the frame did use the dictionaries: its first key is an index
        let f = try Fixture.load("projects-wire")
        guard case .wire(let d)? = f.steps.first else { Issue.record("projects-wire has no wire step"); return }
        #expect(d.count > 2 && d[d.startIndex + 1] == 0x01, "the frame's first key is not \"t\"'s index")
    }
}
