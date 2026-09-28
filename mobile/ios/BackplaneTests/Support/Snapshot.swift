import Foundation
import SnapshotTesting
import SwiftUI
import Testing
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// Snapshots of the app's screens, drawn from the mock hub's scenes. The
// images under __Snapshots__ double as a picture of the app on every device.
//
// Recording: missing images are recorded and the test fails once, so a new
// one is looked at before it is kept. SNAPSHOT_RECORD=all (as
// TEST_RUNNER_SNAPSHOT_RECORD=all for xcodebuild) records every image again.
//
// The Mac tests run inside the sandboxed app, which can neither read nor
// write the source tree (pointfreeco/swift-snapshot-testing#277). There the
// reference images come from the test bundle (they are its resources),
// are compared in the app's temporary directory, and what is recorded
// there is brought back by the Backplane scheme's test post-action.

enum Device: String {
    case iPhone = "iphone"
    case iPad = "ipad"
    case mac = "mac"

    // a device's screen in points: iPhone 17 Pro, iPad Pro 11" in landscape,
    // and a Mac window
    var size: CGSize {
        switch self {
        case .iPhone: CGSize(width: 402, height: 874)
        case .iPad: CGSize(width: 1210, height: 834)
        case .mac: CGSize(width: 1200, height: 800)
        }
    }

    // the device this simulator draws: each is drawn in its own device's
    // window (an iPad drawn in an iPhone's would take the iPhone's safe
    // area, the Dynamic Island's 62 pt at the top)
    @MainActor
    static var here: [Device] {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? [.iPad] : [.iPhone]
        #else
        [.mac]
        #endif
    }
}

// how long a screen is left to draw once laid out
private let settle: TimeInterval = 0.5

#if os(macOS)
// every view in the tree, by its kind and where it sits
private func layout(_ v: NSView, into h: inout Hasher) {
    h.combine(ObjectIdentifier(type(of: v)))
    h.combine(v.frame.origin.x); h.combine(v.frame.origin.y)
    h.combine(v.frame.size.width); h.combine(v.frame.size.height)
    h.combine(v.isHidden)
    for s in v.subviews { layout(s, into: &h) }
}

// A screen lays itself out over several turns of the run loop (a lazy list
// adds its rows, a split view places its columns): wait until its view tree
// is the same for five turns running, and fail rather than draw one still
// moving. (On iOS the library puts the screen in the key window itself and
// waits `settle` there.)
@MainActor
private func settled(_ v: NSView) {
    let limit = Date().addingTimeInterval(3)
    var last = 0, same = 0
    while same < 5 {
        guard Date() < limit else {
            Issue.record("the screen was still laying itself out after 3 s")
            return
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        v.layoutSubtreeIfNeeded()
        var h = Hasher()
        layout(v, into: &h)
        let now = h.finalize()
        same = now == last ? same + 1 : 0
        last = now
    }
}
#endif

private var recording: SnapshotTestingConfiguration.Record {
    switch ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] {
    case "all": .all
    case "never": .never
    case "failed": .failed
    default: .missing
    }
}

// the name SnapshotTesting gives a test's images ("settingsSheet(device:)"
// becomes "settingsSheet-device")
private func sanitized(_ s: String) -> String {
    s.replacingOccurrences(of: "\\W+", with: "-", options: .regularExpression)
        .replacingOccurrences(of: "^-|-$", with: "", options: .regularExpression)
}

@MainActor
func assertSnapshot<V: View>(_ view: V, device: Device, size: CGSize? = nil, named name: String? = nil,
                             fileID: StaticString = #fileID, file: StaticString = #filePath, testName: String = #function,
                             line: UInt = #line, column: UInt = #column) {
    let size = size ?? device.size
    let id = [device.rawValue, name].compactMap { $0 }.joined(separator: "-")
    let root = view.environment(\.colorScheme, .dark)
    #if os(iOS)
    let traits = UITraitCollection(mutations: {
        $0.userInterfaceStyle = .dark
        $0.displayScale = 2
        $0.userInterfaceIdiom = device == .iPad ? .pad : .phone
        $0.horizontalSizeClass = device == .iPad ? .regular : .compact
        $0.verticalSizeClass = .regular
    })
    let host = UIHostingController(rootView: root)
    host.overrideUserInterfaceStyle = .dark
    // every animation held at its first frame (a running thread's spinner
    // would otherwise be caught wherever it had turned to)
    host.view.layer.speed = 0
    // drawn as the screen draws it (a layer render leaves out a thread's
    // list and resolves some colours in the light), after a moment for the
    // lazy list and the navigation title to lay themselves out
    let failure = verifySnapshot(of: host, as: .wait(for: settle, on: .image(drawHierarchyInKeyWindow: true, perceptualPrecision: 0.98, size: size, traits: traits)),
                                 named: id, record: recording, file: file, testName: testName, line: line)
    #else
    // drawn as in the key window (an offscreen window never is one)
    let host = NSHostingView(rootView: root.environment(\.controlActiveState, .key)
        .frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
    host.frame = CGRect(origin: .zero, size: size)
    // in a window, as the app draws it: a view in none has no appearance or
    // sidebar to lay out
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    // A sidebar's vibrancy and (macOS 26) Liquid Glass blend with what is
    // behind the window, which an offscreen image does not have: they come
    // out white. Draw the sidebar as it looks over a plain dark desktop: its
    // content lifted out of the glass, on the window's own background.
    func plain(_ v: NSView) {
        v.subviews.forEach(plain)
        if let e = v as? NSVisualEffectView {
            e.blendingMode = .withinWindow
            e.state = .active
        }
        if #available(macOS 26.0, *), let g = v as? NSGlassEffectView, let content = g.contentView, let parent = g.superview {
            g.contentView = nil
            content.frame = g.frame
            parent.addSubview(content, positioned: .above, relativeTo: g)
            g.isHidden = true
        }
        // the blur behind a floating sidebar
        if String(describing: type(of: v)) == "BackdropView" { v.isHidden = true }
    }
    settled(host)
    plain(host)
    host.layoutSubtreeIfNeeded()
    let suite = URL(fileURLWithPath: "\(file)").deletingPathExtension().lastPathComponent
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("BackplaneSnapshots/\(suite)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let image = "\(sanitized(testName)).\(id)"
    if let kept = Bundle(for: Token.self).url(forResource: image, withExtension: "png") {
        let into = dir.appendingPathComponent(image + ".png")
        try? FileManager.default.removeItem(at: into)
        try? FileManager.default.copyItem(at: kept, to: into)
    }
    let failure = verifySnapshot(of: host, as: .wait(for: settle, on: .image(perceptualPrecision: 0.98, size: size)), named: id, record: recording,
                                 snapshotDirectory: dir.path, file: file, testName: testName, line: line)
    #endif
    if let failure {
        Issue.record(Comment(rawValue: failure), sourceLocation: SourceLocation(fileID: "\(fileID)", filePath: "\(file)", line: Int(line), column: Int(column)))
    }
}
