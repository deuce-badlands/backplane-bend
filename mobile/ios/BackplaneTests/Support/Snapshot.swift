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
    let failure = verifySnapshot(of: host, as: .image(on: ViewImageConfig(safeArea: .zero, size: size, traits: traits), perceptualPrecision: 0.98),
                                 named: id, record: recording, file: file, testName: testName, line: line)
    #else
    let host = NSHostingView(rootView: root.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .darkAqua)
    host.frame = CGRect(origin: .zero, size: size)
    let suite = URL(fileURLWithPath: "\(file)").deletingPathExtension().lastPathComponent
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("BackplaneSnapshots/\(suite)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let image = "\(sanitized(testName)).\(id)"
    if let kept = Bundle(for: Token.self).url(forResource: image, withExtension: "png") {
        let into = dir.appendingPathComponent(image + ".png")
        try? FileManager.default.removeItem(at: into)
        try? FileManager.default.copyItem(at: kept, to: into)
    }
    let failure = verifySnapshot(of: host, as: .image(perceptualPrecision: 0.98, size: size), named: id, record: recording,
                                 snapshotDirectory: dir.path, file: file, testName: testName, line: line)
    #endif
    if let failure {
        Issue.record(Comment(rawValue: failure), sourceLocation: SourceLocation(fileID: "\(fileID)", filePath: "\(file)", line: Int(line), column: Int(column)))
    }
}
