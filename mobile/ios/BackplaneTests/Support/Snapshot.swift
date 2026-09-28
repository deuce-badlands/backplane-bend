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

    // the devices this platform draws
    static var here: [Device] {
        #if os(iOS)
        [.iPhone, .iPad]
        #else
        [.mac]
        #endif
    }
}

// how long a screen is left to lay itself out before it is drawn
private let settle: TimeInterval = 0.5

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
