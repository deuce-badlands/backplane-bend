import Foundation
import JavaScriptCore

// bridge.js on its own, as the app's Engine runs it (one thread with a deep
// stack, JavaScriptCore) but answering the raw text of each call, so a test
// can decode it with a throwing decoder and see which key broke.
final class Bridge: @unchecked Sendable {
    private final class Worker: Thread, @unchecked Sendable {
        private let cond = NSCondition()
        private var jobs: [() -> Void] = []
        private var done = false

        override init() {
            super.init()
            stackSize = 64 << 20
            start()
        }

        func sync<T>(_ f: @escaping () -> T) -> T {
            var out: T?
            let done = DispatchSemaphore(value: 0)
            cond.lock()
            jobs.append { out = f(); done.signal() }
            cond.signal()
            cond.unlock()
            done.wait()
            return out!
        }

        // the thread ends once the jobs already given are run
        func finish() {
            cond.lock()
            done = true
            cond.signal()
            cond.unlock()
        }

        override func main() {
            while true {
                cond.lock()
                while jobs.isEmpty, !done { cond.wait() }
                if jobs.isEmpty {
                    cond.unlock()
                    return
                }
                let f = jobs.removeFirst()
                cond.unlock()
                f()
            }
        }
    }

    private let worker = Worker()
    private var ctx: JSContext!
    private(set) var errors: [String] = []

    struct NoBridge: Error, CustomStringConvertible {
        let why: String
        // the scheme builds bridge.js before each build, but a file missing when
        // the build starts is only bundled by the next one
        var description: String { "bridge.js: \(why) (scripts/test-apple.sh builds it; in Xcode, build again)" }
    }

    init() throws {
        guard let url = Bundle.main.url(forResource: "bridge", withExtension: "js") else { throw NoBridge(why: "not in the app") }
        let src = try String(contentsOf: url, encoding: .utf8)
        let ok: Bool = worker.sync {
            guard let c = JSContext() else { return false }
            c.exceptionHandler = { [weak self] _, e in self?.errors.append(e?.toString() ?? "?") }
            c.evaluateScript(src, withSourceURL: url)
            self.ctx = c
            return c.objectForKeyedSubscript("Backplane")?.isObject == true
        }
        if !ok { worker.finish(); throw NoBridge(why: "defines no Backplane" + (errors.first.map { ": " + $0 } ?? "")) }
    }

    deinit { worker.finish() }

    func call(_ name: String, _ args: [Any]) -> String {
        worker.sync {
            self.ctx.objectForKeyedSubscript("Backplane").invokeMethod(name, withArguments: args)?.toString() ?? ""
        }
    }

    func recv(_ hub: String, _ frame: [String: Any]) -> String {
        call("recv", [hub, CBOR.encode(frame).base64EncodedString()])
    }

    // a plot frame: a map whose first key is 1 ("t") and value "plot"
    // (PlotStore.isPlot, without the main actor)
    static func isPlot(_ d: Data) -> Bool {
        let b = [UInt8](d.prefix(7))
        return b.count == 7 && (0xA0 ... 0xB7).contains(b[0]) && b[1] == 1 && Array(b[2...]) == [0x64, 0x70, 0x6C, 0x6F, 0x74]
    }

    // a scene, as AppModel.replay feeds it: every answer's text, in order
    func play(_ f: Fixture) -> [String] {
        var out = [call("start", ["tests", "{}"]), call("hubs", [[f.hub]]), call("tick", [f.now]), call("online", [f.hub, true])]
        for s in f.steps {
            switch s {
            case .recv(let frame): out.append(recv(f.hub, frame))
            case .wire(let d): out.append(call("recv", [f.hub, d.base64EncodedString()]))
            case .act(let a, let v): out.append(call("act", [a, v]))
            // plots go to the viewer, never through bridge.js
            case .capture(let k):
                for d in (try? Fixture.captured(k)) ?? [] where !Self.isPlot(d) {
                    out.append(call("recv", [f.hub, d.base64EncodedString()]))
                }
            }
        }
        return out
    }
}
