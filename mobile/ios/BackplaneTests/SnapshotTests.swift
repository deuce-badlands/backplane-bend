import Foundation
import SwiftUI
import Testing
@testable import Backplane

// The app's screens on every device, drawn from the mock hub's scenes
// (test/mockhub.bend): the projects, a thread at work, the agent's
// questions, a failed turn, Settings set up well and needing you, and
// pairing (iPhone and iPad). iOS draws the iPhone and iPad images, macOS the Mac's; the
// images are in __Snapshots__/SnapshotTests.
@MainActor
@Suite("Snapshots", .serialized)
struct SnapshotTests {
    private func model(_ name: String) async throws -> AppModel {
        let m = try await Fixture.load(name).model()
        try #require(m.screen != nil, "\(name) left no screen")
        return m
    }

    // Settings remembers the section last shown; each image names its own
    // (and leaves the viewer's choice as it was)
    private func showing<T>(_ section: String, _ body: () throws -> T) rethrows -> T {
        let d = UserDefaults.standard
        let was = d.string(forKey: "settings.section")
        d.set(section, forKey: "settings.section")
        defer { d.set(was, forKey: "settings.section") }
        return try body()
    }

    // the Settings sheet's size: a Mac's sheet, an iPad's page sheet, a
    // phone's whole screen
    private func sheet(_ d: Device) -> CGSize {
        switch d {
        case .mac: CGSize(width: 700, height: 520)
        case .iPad: CGSize(width: 760, height: 700)
        case .iPhone: d.size
        }
    }

    // The app's window. On a Mac, AppKit's offscreen drawing leaves a
    // NavigationSplitView's sidebar out (its Liquid Glass draws only on a
    // screen), so the Mac images lay the same two columns side by side as
    // the split view does: RootView's sidebar at its ideal width, and its
    // detail. A phone and an iPad draw RootView itself.
    @ViewBuilder
    private func window(_ m: AppModel) -> some View {
        #if os(macOS)
        if let s = m.screen {
            HStack(spacing: 0) {
                ProjectsView(model: m, screen: s, pairing: .constant(false))
                    .frame(width: 260)
                Divider()
                Group {
                    if let id = m.path.last {
                        NavigationStack { ThreadDestination(model: m, id: id) }
                    } else {
                        ContentUnavailableView("No thread selected", systemImage: "bubble.left.and.bubble.right",
                                               description: Text("Pick a thread or a bot in the sidebar."))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .environment(\.splitLayout, true)
        }
        #else
        RootView(model: m)
        #endif
    }

    @Test("projects")
    func projects() async throws {
        let m = try await model("projects")
        for d in Device.here { assertSnapshot(window(m), device: d) }
    }

    @Test("a thread at work")
    func threadReview() async throws {
        let m = try await model("thread-review")
        for d in Device.here { assertSnapshot(window(m), device: d) }
    }

    @Test("the agent's questions")
    func threadQuestion() async throws {
        let m = try await model("thread-question")
        for d in Device.here { assertSnapshot(window(m), device: d) }
    }

    @Test("a failed turn")
    func threadFailed() async throws {
        let m = try await model("thread-failed")
        for d in Device.here { assertSnapshot(window(m), device: d) }
    }

    @Test("Settings: Agents")
    func settings() async throws {
        let m = try await model("settings")
        let st = try #require(m.screen?.settings)
        showing("Agents") {
            for d in Device.here {
                assertSnapshot(SettingsSheet(model: m, settings: st, version: "0.10.0", wide: d != .iPhone), device: d, size: sheet(d))
            }
        }
    }

    @Test("Settings: Voice")
    func settingsVoice() async throws {
        let m = try await model("settings")
        let st = try #require(m.screen?.settings)
        let voice = try #require(st.sections?.first { $0.title == "Voice" })
        showing("Voice") {
            for d in Device.here where d != .iPhone {
                assertSnapshot(SettingsSheet(model: m, settings: st, version: "0.10.0", wide: true), device: d, size: sheet(d))
            }
        }
        #if os(iOS)
        // a phone pushes into a section from the list
        let pane = NavigationStack {
            SettingsPane(model: m, section: voice, rows: SettingsSheet.rows(of: st, in: "Voice"), header: false)
                .navigationTitle("Voice")
                .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.splitLayout, false)
        assertSnapshot(pane, device: .iPhone)
        #endif
    }

    @Test("Settings that need you")
    func settingsAttention() async throws {
        let m = try await model("settings-attention")
        let st = try #require(m.screen?.settings)
        showing("KiCad") {
            for d in Device.here {
                assertSnapshot(SettingsSheet(model: m, settings: st, version: "0.10.0", wide: d != .iPhone), device: d, size: sheet(d))
            }
        }
    }

    // The board viewer on a sample board, KiCad's RoyalBlue54L Feather demo
    // (CERN-OHL-P v2, Fixtures/Viewer/NOTICE.md): a phone shows it over the
    // whole screen, an iPad and a Mac as a pane with the thread.
    private func viewer(_ kind: String, testName: String = #function) async throws {
        let m = try await model("viewer-" + kind)
        let v = try #require(m.screen?.thread?.viewer)
        for d in Device.here {
            if d == .iPhone {
                assertSnapshot(PlotScreen(model: m, viewer: v), device: d, testName: testName)
            } else {
                assertSnapshot(window(m), device: d, testName: testName)
            }
        }
    }

    @Test("the board viewer")
    func viewerBoard() async throws { try await viewer("board") }

    @Test("the schematic viewer")
    func viewerSchematic() async throws { try await viewer("schematic") }

    @Test("the 3D viewer")
    func viewer3D() async throws { try await viewer("3d") }

    // (not on a Mac: there PairView asks 127.0.0.1:3787 whether a hub runs
    // on the machine, and draws whichever answer came)
    @Test("pairing")
    func pairing() {
        for d in Device.here where d != .mac { assertSnapshot(NavigationStack { PairView(link: "") { _ in } }, device: d) }
    }
}
