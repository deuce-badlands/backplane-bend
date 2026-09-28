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
        // test/apple_fixtures.bend writes seven
        #expect(Fixture.names.count == 7, "\(Fixture.names)")
    }

    @Test("every answer decodes", arguments: Fixture.names)
    func everyAnswer(_ name: String) throws {
        let f = try Fixture.load(name)
        let b = Bridge()
        let outs = b.play(f)
        #expect(b.errors.isEmpty, "bridge.js threw: \(b.errors)")
        for (i, text) in outs.enumerated() {
            let out = try JSONDecoder().decode(Out.self, from: Data(text.utf8))
            #expect(out.screen != nil, "answer \(i) of \(name) has no screen")
        }
    }
}
