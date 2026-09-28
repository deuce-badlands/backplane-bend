import Foundation
import Testing
@testable import Backplane

// A pairing link, as a desktop shows it or a QR code carries it, becomes
// the hub's socket, key and web addresses.
@Suite("Pairing links")
struct PairingTests {
    @Test("links to the hub's socket", arguments: [
        ("http://100.64.0.7:3787/#token=7f3a9c", "ws://100.64.0.7:3787/ws?token=7f3a9c"),
        ("https://workbench.tail2f3e.ts.net/#token=ab12", "wss://workbench.tail2f3e.ts.net/ws?token=ab12"),
        ("127.0.0.1:3787", "ws://127.0.0.1:3787/ws"),
        ("  192.168.1.20:3787  ", "ws://192.168.1.20:3787/ws"),
        ("http://host:3787/?token=beef", "ws://host:3787/ws?token=beef"),
        ("backplane://pair?url=http%3A%2F%2F100.64.0.7%3A3787%2F%23token%3Dc0ffee", "ws://100.64.0.7:3787/ws?token=c0ffee"),
    ])
    func socket(_ link: String, _ want: String) {
        #expect(Pairing.socket(link)?.absoluteString == want)
    }

    @Test("what is not a link", arguments: ["", "   ", "backplane://pair"])
    func invalid(_ link: String) {
        #expect(Pairing.socket(link) == nil)
        #expect(Pairing.key(link) == nil)
    }

    @Test("a token that is not hex is not a token")
    func token() {
        #expect(Pairing.socket("http://h:1/#token=not-hex")?.absoluteString == "ws://h:1/ws")
    }

    @Test("every link to one hub has one key")
    func key() {
        #expect(Pairing.key("http://100.64.0.7:3787/#token=7f3a9c") == "100.64.0.7:3787")
        #expect(Pairing.key("100.64.0.7:3787") == "100.64.0.7:3787")
        #expect(Pairing.key("https://workbench.tail2f3e.ts.net/#token=ab") == "workbench.tail2f3e.ts.net")
    }

    @Test("a resumed socket asks for what came since, in CBOR")
    func resume() throws {
        let u = try #require(Pairing.socket("http://h:3787/#token=ab", since: "42", origin: "o1"))
        let q = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(q.map(\.name) == ["token", "since", "origin", "enc"])
        #expect(q.map { $0.value ?? "" } == ["ab", "42", "o1", "cbor"])
    }

    @Test("web and http addresses on the hub")
    func web() {
        #expect(Pairing.web("https://h/#token=ab", "/img?path=a.png")?.absoluteString == "https://h/img?path=a.png&token=ab")
        #expect(Pairing.web("h:3787", "/plot")?.absoluteString == "http://h:3787/plot")
        #expect(Pairing.http("http://h:3787/#token=ab", path: "/hook", query: [URLQueryItem(name: "id", value: "1")])?.absoluteString == "http://h:3787/hook?token=ab&id=1")
        #expect(Pairing.http("http://h:3787/#token=ab", path: "/hook", token: false)?.absoluteString == "http://h:3787/hook")
    }

    #if os(macOS)
    @Test("only a hub's hello offers this Mac")
    func hello() {
        // a hub's answer: {"backplane": "0.10.0"} (Hello.answer)
        let hub = CBOR.encode(["backplane": "0.10.0"])
        #expect(PairView.isHub(hub, 200))
        #expect(!PairView.isHub(hub, 404))
        #expect(!PairView.isHub(Data("<html>ok</html>".utf8), 200))
        #expect(!PairView.isHub(CBOR.encode(["other": "1"]), 200))
        #expect(!PairView.isHub(Data(), 200))
    }
    #endif
}
