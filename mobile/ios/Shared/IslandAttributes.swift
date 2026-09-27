#if os(iOS)
import ActivityKit
#endif
import Foundation

// The Dynamic Island's content: exactly the "island" object
// src/mobile/notify.bend emits, and the content-state the hub pushes.
struct IslandAttributes {
    struct Line: Codable, Hashable {
        let thread: String
        let title: String
        let doing: String
    }

    struct ContentState: Codable, Hashable {
        let running: Int
        let headline: String
        let lines: [Line]
    }
}

// Live Activities are iOS-only; the Mac app decodes the same content-state
// from the screen but has no Dynamic Island to show it on
#if os(iOS)
extension IslandAttributes: ActivityAttributes {}
#endif
