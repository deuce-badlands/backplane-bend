import Foundation

// CBOR for the tests: the mock hub's JSON frames written as a hub writes
// them (plain text keys, no dictionary), and the frames the app sends read
// back. A hub's dictionary words (tag 6) and keys (small ints) come back as
// Word and "#n": the tests look for the text values they carry.
enum CBOR {
    struct Word: Equatable { let index: Int }

    static func encode(_ value: Any) -> Data {
        var out = Data()
        write(value, into: &out)
        return out
    }

    private static func head(_ major: UInt8, _ n: UInt64, into out: inout Data) {
        let m = major << 5
        switch n {
        case 0..<24: out.append(m | UInt8(n))
        case 24..<0x100: out.append(m | 24); out.append(UInt8(n))
        case 0x100..<0x10000: out.append(m | 25); out.append(contentsOf: [UInt8(n >> 8), UInt8(n & 0xff)])
        case 0x10000..<0x1_0000_0000: out.append(m | 26); out.append(contentsOf: (0..<4).reversed().map { UInt8((n >> (8 * UInt64($0))) & 0xff) })
        default: out.append(m | 27); out.append(contentsOf: (0..<8).reversed().map { UInt8((n >> (8 * UInt64($0))) & 0xff) })
        }
    }

    private static func write(_ v: Any, into out: inout Data) {
        switch v {
        case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID():
            out.append(n.boolValue ? 0xf5 : 0xf4)
        case let n as NSNumber:
            let i = n.int64Value
            precondition(Double(i) == n.doubleValue, "the mock hub sends whole numbers only")
            i >= 0 ? head(0, UInt64(i), into: &out) : head(1, UInt64(-1 - i), into: &out)
        case let s as String:
            let b = Data(s.utf8)
            head(3, UInt64(b.count), into: &out)
            out.append(b)
        case let a as [Any]:
            head(4, UInt64(a.count), into: &out)
            for x in a { write(x, into: &out) }
        case let o as [String: Any]:
            head(5, UInt64(o.count), into: &out)
            // in a stable order, as a hub's frames are
            for k in o.keys.sorted() {
                write(k, into: &out)
                write(o[k]!, into: &out)
            }
        case is NSNull:
            out.append(0xf6)
        default:
            preconditionFailure("not JSON: \(type(of: v))")
        }
    }

    static func decode(_ d: Data) -> Any? {
        let b = [UInt8](d)
        var i = 0
        func arg(_ ai: UInt8) -> UInt64? {
            func take(_ n: Int) -> UInt64? {
                guard i + n <= b.count else { return nil }
                defer { i += n }
                return b[i..<(i + n)].reduce(0) { $0 << 8 | UInt64($1) }
            }
            switch ai {
            case 0..<24: return UInt64(ai)
            case 24: return take(1)
            case 25: return take(2)
            case 26: return take(4)
            case 27: return take(8)
            default: return nil
            }
        }
        func item() -> Any? {
            guard i < b.count else { return nil }
            let h = b[i]
            i += 1
            if h == 0xf4 { return false }
            if h == 0xf5 { return true }
            if h == 0xf6 { return NSNull() }
            guard let n = arg(h & 31) else { return nil }
            switch h >> 5 {
            case 0: return Int(n)
            case 1: return -1 - Int(n)
            case 2, 3:
                guard i + Int(n) <= b.count else { return nil }
                defer { i += Int(n) }
                let bytes = Data(b[i..<(i + Int(n))])
                return h >> 5 == 2 ? bytes : String(decoding: bytes, as: UTF8.self)
            case 4:
                var a: [Any] = []
                for _ in 0..<n { guard let x = item() else { return nil }; a.append(x) }
                return a
            case 5:
                var o: [String: Any] = [:]
                for _ in 0..<n {
                    guard let k = item(), let v = item() else { return nil }
                    o[(k as? String) ?? "#\(k)"] = v
                }
                return o
            case 6:
                // tag 6: a dictionary word; tag 7: a number's text
                guard let x = item() else { return nil }
                return n == 6 ? Word(index: x as? Int ?? -1) : x
            default: return nil
            }
        }
        let v = item()
        return i == b.count ? v : nil
    }

    // every text value in a decoded frame, however deep
    static func strings(_ v: Any) -> [String] {
        switch v {
        case let s as String: [s]
        case let a as [Any]: a.flatMap(strings)
        case let o as [String: Any]: o.keys.sorted().flatMap { strings(o[$0]!) }
        default: []
        }
    }
}
