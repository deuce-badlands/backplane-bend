import Foundation
@testable import Backplane

// A scene of the mock hub (test/apple_fixtures.bend, written by
// scripts/apple-fixtures.sh): the hub's frames and the user's actions that
// reach it, and the clock they happen at.
struct Fixture {
    enum Step {
        case recv([String: Any])
        case act(String, String)
    }

    let name, about, hub: String
    let now: Int
    let steps: [Step]

    // every scene, so a new one is replayed, decoded and checked with the rest
    static let names = ["projects", "thread-review", "thread-question", "thread-done", "thread-failed", "settings", "settings-attention"]

    static func load(_ name: String) throws -> Fixture {
        guard let url = Bundle(for: Token.self).url(forResource: name, withExtension: "json") else { throw Missing(name: name) }
        let o = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        let steps: [Step] = (o["steps"] as? [[String: Any]] ?? []).compactMap { s in
            if let f = s["recv"] as? [String: Any] { return .recv(f) }
            if let a = s["act"] as? [String], a.count == 2 { return .act(a[0], a[1]) }
            return nil
        }
        return Fixture(name: name, about: o["about"] as? String ?? "", hub: o["hub"] as? String ?? "", now: o["now"] as? Int ?? 0, steps: steps)
    }

    struct Missing: Error, CustomStringConvertible {
        let name: String
        var description: String { "no fixture \(name).json in the test bundle: run scripts/apple-fixtures.sh" }
    }

    // the app's model, fed this scene with no hub and no kept state
    @MainActor
    func model() async -> AppModel {
        let m = AppModel(live: false)
        await m.replay(hub: hub, now: now, steps: steps.map {
            switch $0 {
            case .recv(let f): .recv(CBOR.encode(f))
            case .act(let a, let v): .act(a, v)
            }
        })
        return m
    }
}

// the test bundle, for its resources
final class Token {}
