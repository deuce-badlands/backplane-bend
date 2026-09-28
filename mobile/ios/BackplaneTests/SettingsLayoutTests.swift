import Foundation
import Testing
@testable import Backplane

// How the Settings sheet lays the hub's rows out: sections in the hub's
// order, rows by section, and headings within a section.
@Suite("Settings layout")
struct SettingsLayoutTests {
    private func row(_ section: String?, _ label: String, group: String? = nil) -> SetRow {
        SetRow(section: section, group: group, kind: "status", label: label, note: "", value: nil, tone: nil, field: nil, buttons: [], chips: nil)
    }

    @Test("the hub's sections as it sends them")
    func sent() {
        let s = Settings(rows: [row("B", "b"), row("A", "a")], sections: [SetSection(title: "A", summary: "on", attention: true), SetSection(title: "B", summary: "", attention: false)])
        #expect(SettingsSheet.sections(of: s).map(\.title) == ["A", "B"])
    }

    @Test("a hub that sends no sections: the rows' own, in order")
    func derived() {
        let s = Settings(rows: [row("Threads", "a"), row("Agents", "b"), row("Threads", "c"), row(nil, "d")], sections: nil)
        #expect(SettingsSheet.sections(of: s).map(\.title) == ["Threads", "Agents", ""])
        #expect(SettingsSheet.sections(of: Settings(rows: [], sections: [])).isEmpty)
        #expect(SettingsSheet.rows(of: s, in: "Threads").map(\.label) == ["a", "c"])
    }

    @Test("consecutive rows under one heading")
    func groups() {
        let rows = [row("Agents", "Provider"), row("Agents", "Model"), row("Agents", "Claude", group: "Installed"), row("Agents", "Codex", group: "Installed")]
        let g = SettingsPane.groups(rows)
        #expect(g.map(\.title) == ["", "Installed"])
        #expect(g.map { $0.rows.map(\.label) } == [["Provider", "Model"], ["Claude", "Codex"]])
        #expect(SettingsPane.groups([]).isEmpty)
    }
}
