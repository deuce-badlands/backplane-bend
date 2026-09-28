import Foundation
import Testing
@testable import Backplane

// The board viewer's decoding: CBOR as plots use it, varints and zigzag,
// chunks of capsules and fills, and 3D meshes.
@Suite("Plot decoding")
struct PlotDecodingTests {
    @Test("CBOR: ints, strings, bytes, arrays, maps and the plot keys")
    @MainActor
    func cbor() throws {
        // {1: "plot", 31: "k", "n": [0, 23, 24, 256, -1, -300], "d": h'0102'}
        let d = Data([0xA4, 0x01, 0x64, 0x70, 0x6C, 0x6F, 0x74, 0x18, 0x1F, 0x61, 0x6B, 0x61, 0x6E,
                      0x86, 0x00, 0x17, 0x18, 0x18, 0x19, 0x01, 0x00, 0x20, 0x39, 0x01, 0x2B, 0x61, 0x64, 0x42, 0x01, 0x02])
        let o = try #require(Cbor.decode(d) as? [String: Any])
        #expect(o["t"] as? String == "plot")
        #expect(o["key"] as? String == "k")
        #expect(o["n"] as? [Int] == [0, 23, 24, 256, -1, -300])
        #expect(o["d"] as? Data == Data([1, 2]))
        #expect(PlotStore.isPlot(d))
    }

    @Test("CBOR that is cut short is nothing", arguments: [Data([0x82, 0x01]), Data([0x63, 0x61]), Data([0x19, 0x01]), Data()])
    func truncated(_ d: Data) {
        #expect(Cbor.decode(d) == nil)
    }

    @Test("a frame that is not a plot")
    @MainActor
    func notPlot() {
        #expect(!PlotStore.isPlot(CBOR.encode(["t": "log"])))
        #expect(!PlotStore.isPlot(Data([0xA1, 0x01, 0x64, 0x76, 0x69, 0x65, 0x77, 0x00])))
    }

    @Test("varints and zigzag")
    func varints() {
        var v = Varints(Data([0x05, 0xAC, 0x02, 0x03, 0x04, 0x01]))
        #expect(v.next() == 5)
        #expect(v.next() == 300)
        #expect(v.signed() == -2)
        #expect(v.signed() == 2)
        #expect(v.signed() == -1)
        #expect(!v.more)
    }

    @Test("a chunk of tracks: capsules from a path, a piece per path, boxes padded by the radius")
    func tracks() {
        // mode 1 (paths), width 200: one piece (info 7) of 3 points (0,0) (10,0) (10,10)
        let d = Data([0x07, 0x03, 0x00, 0x00, 0x14, 0x00, 0x00, 0x14])
        let c = PlotChunk.decode(["l": 3, "c": 0xFF8800, "a": 128, "m": 1, "w": 200, "d": d])
        #expect(c.layer == 3)
        #expect(c.color == 0xFF8800)
        #expect(abs(c.alpha - 128.0 / 255) < 1e-6)
        #expect(c.caps == [0, 0, 10, 0, 100, 10, 0, 10, 10, 100])
        #expect(c.pieces.count == 1)
        #expect(c.pieces[0].info == 7)
        #expect(c.pieces[0].box == SIMD4(-100, -100, 110, 110))
        #expect(c.distance(c.pieces[0], 5, 0) == -100)
    }

    @Test("a chunk of pads (dots) and a chunk of fills (a fan)")
    func padsAndFills() {
        let pads = PlotChunk.decode(["m": 2, "w": 60, "d": Data([0x01, 0x14, 0x14, 0x02, 0x14, 0x00])])
        #expect(pads.caps == [10, 10, 10, 10, 30, 20, 10, 20, 10, 30])
        #expect(pads.pieces.map(\.info) == [1, 2])
        // a clockwise square is turned counter-clockwise: two triangles
        let fill = PlotChunk.decode(["m": 0, "d": Data([0x09, 0x04, 0x00, 0x00, 0x00, 0x14, 0x14, 0x00, 0x00, 0x13])])
        #expect(fill.tris.count == 12)
        #expect(fill.pieces.first?.info == 9)
        #expect(fill.distance(fill.pieces[0], 5, 5) == 0)
        #expect(fill.distance(fill.pieces[0], 50, 50) == .infinity)
    }

    @Test("a mesh: triangles with normals, colours and a box in micrometres")
    func mesh() {
        // one triangle (0,0,0) (1,0,0) (0,1,0), colour 0x00FF00, box 0..1 in 10 µm units
        let d = Data([0x80, 0xFE, 0x03, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x01, 0x02, 0x00])
        let m = PlotMesh.decode(["n": 1, "mesh": d, "box3": [0, 0, 0, 1, 1, 1]])
        #expect(m.colors == [0x00FF00, 0x00FF00, 0x00FF00])
        #expect(m.verts.count == 18)
        #expect(Array(m.verts[0..<6]) == [0, 0, 0, 0, 0, 1])
        #expect(Array(m.verts[6..<9]) == [10, 0, 0])
        #expect(m.box == [0, 0, 0, 10, 10, 10])
        #expect(PlotMesh.decode(["n": 0]).verts.isEmpty)
    }
}
