import Foundation
@testable import Backplane

// A scene of the mock hub (test/apple_fixtures.bend, written by
// scripts/apple-fixtures.sh): the hub's frames and the user's actions that
// reach it, and the clock they happen at.
struct Fixture {
    enum Step {
        case recv([String: Any])
        // a frame as the hub's own encoder wrote it (its dictionaries' keys and words)
        case wire(Data)
        case act(String, String)
        // what a hub sent a phone watching the viewer's sample (Viewer/<kind>.capture)
        case capture(String)
    }

    let name, about, hub: String
    let now: Int
    let steps: [Step]

    // the frames a hub sent a phone watching the sample's view (kind: board,
    // schematic, 3d), captured by scripts/apple-viewer-fixtures.sh
    static func captured(_ kind: String) throws -> [Data] {
        guard let url = Bundle(for: Token.self).url(forResource: kind, withExtension: "capture") else { throw Missing(name: kind + ".capture") }
        let o = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        return (o["frames"] as? [String] ?? []).compactMap { Data(base64Encoded: $0) }
    }

    // every scene in the bundle, so a new one is replayed and decoded with the rest
    static let names: [String] = (Bundle(for: Token.self).urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
        .map { $0.deletingPathExtension().lastPathComponent }.sorted()

    static func load(_ name: String) throws -> Fixture {
        guard let url = Bundle(for: Token.self).url(forResource: name, withExtension: "json") else { throw Missing(name: name) }
        let o = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        let steps: [Step] = (o["steps"] as? [[String: Any]] ?? []).compactMap { s in
            if let f = s["recv"] as? [String: Any] { return .recv(f) }
            if let w = s["wire"] as? String, let d = Data(base64Encoded: w) { return .wire(d) }
            if let a = s["act"] as? [String], a.count == 2 { return .act(a[0], a[1]) }
            if let k = s["capture"] as? String { return .capture(k) }
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
    func model() async throws -> AppModel {
        let m = AppModel(live: false)
        var app: [AppModel.Step] = []
        for s in steps {
            switch s {
            case .recv(let f): app.append(.recv(CBOR.encode(f)))
            case .wire(let d): app.append(.recv(d))
            case .act(let a, let v): app.append(.act(a, v))
            case .capture(let k): app += try Self.captured(k).map { .frame($0) }
            }
        }
        await m.replay(hub: hub, now: now, steps: app)
        // the bots' cats, which the list asks for once it is on screen
        for b in m.screen?.bots ?? [] { await m.cat(b.cat) }
        // plots are decoded off the main thread: wait for the viewer's (and
        // for 3D, its model too)
        for case .capture(let k) in steps {
            for _ in 0 ..< 400 where m.plots.frame == nil || (k == "3d" && m.plots.mesh == nil) {
                try await Task.sleep(for: .milliseconds(25))
            }
            if m.plots.frame == nil || (k == "3d" && m.plots.mesh == nil) { throw NoPlot(kind: k) }
        }
        return m
    }

    struct NoPlot: Error, CustomStringConvertible {
        let kind: String
        var description: String { "the \(kind) capture gave the viewer no \(kind == "3d" ? "model" : "frame") within 10 s" }
    }
}

// the test bundle, for its resources
final class Token {}
