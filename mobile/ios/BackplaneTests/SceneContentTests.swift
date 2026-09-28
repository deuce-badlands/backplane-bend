import Foundation
import Testing
@testable import Backplane

// What the app shows for each scene, through the app's own model: the
// fixture's frames and actions go through AppModel.replay, the real
// bridge.js answers, and AppModel applies the answers as it would a hub's.
@MainActor
@Suite("Scene content", .serialized)
struct SceneContentTests {
    private func screen(_ name: String) async throws -> (AppModel, Screen) {
        let m = try await Fixture.load(name).model()
        let s = try #require(m.screen, "\(name) left no screen")
        return (m, s)
    }

    private func find(_ tag: String, in blocks: [Block]) -> Block? {
        for b in blocks {
            if b.tag == tag { return b }
            if let k = find(tag, in: b.kids ?? []) { return k }
        }
        return nil
    }

    @Test("the projects, and every thread's state")
    func projects() async throws {
        let (m, s) = try await screen("projects")
        #expect(m.links == ["http://workbench.local:3787"])
        #expect(s.hub == "workbench.local:3787")
        #expect(s.version == "0.10.0")
        #expect(s.projects.map(\.title) == ["sensor-hub", "usb-pd-sink", "bench-tools"])
        let rows = s.projects.flatMap(\.threads)
        #expect(rows.map(\.title) == ["Route the IMU's SPI bus", "Pick a buck converter for 3V3", "Review the PD negotiation schematic",
                                      "Export the JLCPCB order", "Add a --json flag to the bench report"])
        #expect(rows.map(\.status) == ["working", "input", "complete", "failed", "complete"])
        // a settled thread leaves the list for its shelf
        #expect(s.projects[0].settled.map(\.title) == ["Fix silkscreen over pads"])
        #expect(s.bots.map(\.name) == ["Librarian"])
        #expect(s.thread == nil)
        #expect(m.path.isEmpty)
    }

    @Test("a running thread: its review, tool calls, todos")
    func review() async throws {
        let (m, s) = try await screen("thread-review")
        let t = try #require(s.thread)
        #expect(t.title == "Route the IMU's SPI bus")
        #expect(t.state == "run")
        #expect(t.working == "Working…")
        // the selection pushes the thread (a phone) or selects it (a sidebar)
        #expect(m.path == [s.sel])
        #expect(t.entries.map(\.kind) == ["user", "fold", "assistant", "user", "fold", "fold", "act"])
        let reply = try #require(t.entries.first { $0.kind == "assistant" }?.blocks)
        // a table and a code block each come in a div (the code's with Copy)
        #expect(reply.map { $0.tag ?? "" } == ["p", "h4", "div", "p", "div", "p", "ul"])
        let table = try #require(find("table", in: reply))
        #expect(table.kids?.count == 5)
        #expect(table.plain.contains("IMU_MOSI47.9 mm45 mmover"))
        #expect(find("pre", in: reply)?.plain.contains("BUDGET_MM = 45.0") == true)
        #expect(find("ul", in: reply)?.kids?.count == 2)
        #expect(t.entries.last?.label == "Edit")
        #expect(t.entries.last?.text == "sensor-hub_v2.kicad_pcb")
        #expect(t.todos?.head == "Todo 1/3")
        #expect(t.todos?.lines.map(\.status) == ["completed", "in_progress", "pending"])
        #expect(t.tools.first?.action == "interrupt")
    }

    @Test("the agent's three questions")
    func question() async throws {
        let (_, s) = try await screen("thread-question")
        let ask = try #require(s.thread?.asks?.first)
        #expect(ask.id == "k1")
        #expect(ask.kind == "input")
        let qs = try #require(ask.questions)
        #expect(qs.map { $0.header ?? "" } == ["Regulator", "Power good", "Placement"])
        #expect(qs.map { $0.multiSelect ?? false } == [false, true, false])
        #expect(qs[0].options?.map(\.label) == ["TPS62840 (Recommended)", "TPS62162", "AP62300"])
        #expect(qs[0].options?.first?.description == "60 nA quiescent, 750 mA. Best for the sleep budget.")
    }

    @Test("a finished turn and a failed one")
    func endings() async throws {
        let (_, done) = try await screen("thread-done")
        #expect(done.thread?.title == "Review the PD negotiation schematic")
        #expect(done.thread?.entries.last?.blocks?.first?.plain == "The PDO table asks for 20 V at 3 A, but R12 sets the current limit to 2.25 A. Change R12 to 6.04 kΩ.")
        let (_, failed) = try await screen("thread-failed")
        #expect(failed.thread?.title == "Export the JLCPCB order")
        #expect(failed.projects[1].threads.first { $0.id.hasSuffix("|t5") }?.status == "failed")
    }

    @Test("Settings set up well")
    func settings() async throws {
        let (_, s) = try await screen("settings")
        let st = try #require(s.settings)
        #expect(st.sections?.map(\.title) == ["Threads", "Agents", "Writing", "CAD", "Appearance", "Network", "Voice"])
        #expect(st.sections?.contains { $0.attention } == false)
        let key = try #require(st.rows.first { $0.label == "OpenAI API key" })
        #expect(key.kind == "field")
        #expect(key.field?.secret == true)
        #expect(key.value == "sk-…9f2c")
        #expect(st.rows.first { $0.label == "Microphone" }?.buttons.map(\.label) == ["Default", "Blue Yeti", "Built-in Audio"])
        #expect(st.rows.first { $0.label == "Dictionary" }?.chips?.map(\.label) == ["TPS62840", "KiCad", "JLCPCB"])
    }

    @Test("Settings that need you")
    func attention() async throws {
        let (_, s) = try await screen("settings-attention")
        let st = try #require(s.settings)
        #expect(st.sections?.filter(\.attention).map(\.title) == ["CAD", "Network", "Voice"])
        #expect(st.rows.first { $0.label == "KiCad CLI" }?.tone == "warn")
        #expect(st.rows.first { $0.label == "KiCad IPC" }?.buttons.map(\.action) == ["kicad-install"])
        #expect(st.rows.first { $0.label.hasPrefix("Backplane ") }?.buttons.map(\.action) == ["update"])
    }

    // The viewer on the sample board (KiCad's RoyalBlue54L Feather demo):
    // the frames a real hub sent, applied as the socket hands them over.
    @Test("the viewer draws what the hub sent", arguments: ["board", "schematic", "3d"])
    func viewer(_ kind: String) async throws {
        let (m, s) = try await screen("viewer-" + kind)
        let v = try #require(s.thread?.viewer)
        #expect(v.open == kind)
        #expect(v.choices.map(\.value) == ["board", "schematic", "3d", "mech"])
        // the layers' plot, for the source on screen (3D draws the board's layers on its faces)
        let f = try #require(m.plots.frame, "no plot arrived")
        #expect(f.key == v.layers)
        #expect(f.none.isEmpty, "the hub could not plot it: \(f.none)")
        #expect(f.chunks.count > 10)
        #expect(f.box.count == 4)
        // every layer the sample draws: the board's eight copper layers with
        // its mask, silk and edges; the schematic's one sheet
        let layers = Set(f.chunks.map(\.layer)).count
        #expect(layers >= (kind == "schematic" ? 1 : 8), "\(kind) drew \(layers) layers")
        if kind == "3d" {
            let mesh = try #require(m.plots.mesh, "no model arrived")
            #expect(mesh.key == v.key)
            #expect(mesh.none.isEmpty, "the hub could not make the model: \(mesh.none)")
            #expect((mesh.mesh?.verts.count ?? 0) > 10_000)
        } else {
            #expect(m.plots.mesh == nil)
        }
    }

    // what each capture came from: the hub's commit (never one with changes
    // under src/) and the design's pinned commit
    @Test("each viewer capture names where it came from", arguments: ["board", "schematic", "3d"])
    func provenance(_ kind: String) throws {
        let url = try #require(Bundle(for: Token.self).url(forResource: kind, withExtension: "capture"))
        let o = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let hub = o["hub"] as? String ?? ""
        #expect(hub.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil, "hub commit: \(hub)")
        #expect(o["kicad"] as? String == "7f2d789cd59318048e3419f0628777197a287464")
        #expect(o["kind"] as? String == kind)
        #expect(try Fixture.captured(kind).contains(where: Bridge.isPlot))
    }
}
