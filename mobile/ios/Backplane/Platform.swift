import ImageIO
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// The app runs on iPhone, iPad and natively on the Mac. What differs is kept
// here, so a view says what it wants once (`.inlineTitle()`) and each
// platform does its own thing: the Mac has no navigation-bar title modes,
// software keyboards or auto-capitalisation.

extension View {
    // a small title, the way a pushed screen shows it on a phone
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    // a field for names, paths and commands: no auto-capitalisation
    func plainTextInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    func urlKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.URL)
        #else
        self
        #endif
    }

    func asciiKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.asciiCapable)
        #else
        self
        #endif
    }

    // a view over everything: the whole screen on a phone, a sheet on a Mac
    func fullScreen<Item: Identifiable, Content: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item) { content($0).frame(minWidth: 800, minHeight: 600) }
        #endif
    }

    // a row's swipe actions again as a right-click menu on the Mac, where a
    // swipe needs a trackpad and is easy to miss
    func macMenu<C: View>(@ViewBuilder _ items: () -> C) -> some View {
        #if os(macOS)
        contextMenu(menuItems: items)
        #else
        self
        #endif
    }

    // the composer on a Mac: cmd+return sends, opt+cmd+return sends with the
    // other follow-up mode (the phone's long press)
    func sendKeys(send: @escaping () -> Void, alt: @escaping () -> Void) -> some View {
        #if os(macOS)
        onKeyPress(.return, phases: .down) { k in
            guard k.modifiers.contains(.command) else { return .ignored }
            if k.modifiers.contains(.option) { alt() } else { send() }
            return .handled
        }
        #else
        self
        #endif
    }

    // the terminal takes a Mac's keys itself; a phone types into a hidden field
    func terminalKeys(_ focus: FocusState<Bool>.Binding, _ press: @escaping (KeyPress) -> KeyPress.Result) -> some View {
        #if os(macOS)
        focusable()
            .focused(focus)
            .focusEffectDisabled()
            .onKeyPress(phases: [.down, .repeat], action: press)
        #else
        self
        #endif
    }

    // a menu that stays open while several items are toggled in a row (a
    // Mac menu closes on each pick)
    func keepsMenuOpen() -> some View {
        #if os(iOS)
        menuActionDismissBehavior(.disabled)
        #else
        self
        #endif
    }

    // the viewer's own light or dark ground: the whole screen it covers on a
    // phone, only its pane on a Mac (the thread beside it keeps the app's)
    func viewerScheme(_ scheme: ColorScheme) -> some View {
        #if os(iOS)
        preferredColorScheme(scheme)
        #else
        environment(\.colorScheme, scheme)
        #endif
    }

    // the viewer takes the whole phone screen; a Mac window has no status bar
    func hiddenStatusBar() -> some View {
        #if os(iOS)
        statusBarHidden()
        #else
        self
        #endif
    }

    // the navigation bar's background and scheme; the Mac's window toolbar
    // keeps the system look
    func barStyle<S: ShapeStyle>(_ background: S, scheme: ColorScheme) -> some View {
        #if os(iOS)
        toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(background, for: .navigationBar)
            .toolbarColorScheme(scheme, for: .navigationBar)
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    static var leadingBar: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    static var trailingBar: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

extension Color {
    // a raised surface: a card, a bubble, a field's well
    static var secondaryBackground: Color {
        #if os(iOS)
        Color(.secondarySystemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

#if os(iOS)
typealias PlatformImage = UIImage

extension Image {
    init(platformImage: PlatformImage) { self.init(uiImage: platformImage) }
}
#else
typealias PlatformImage = NSImage

extension Image {
    init(platformImage: PlatformImage) { self.init(nsImage: platformImage) }
}
#endif

// Wide windows (a Mac, an iPad in regular width) show the projects in a
// sidebar with the selection beside it; a phone (or an iPad in Slide Over)
// pushes. Views read this instead of asking which device they are on.
private struct SplitLayoutKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var splitLayout: Bool {
        get { self[SplitLayoutKey.self] }
        set { self[SplitLayoutKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func projectsListStyle(sidebar: Bool) -> some View {
        if sidebar { listStyle(.sidebar) } else { listStyle(.automatic) }
    }

    // A Mac sheet takes its content's size, and a List or Form has none of
    // its own, so a sheet collapsed to its title bar. Each sheet names the
    // size it wants on a Mac; a phone's sheets fill the screen as before.
    func macSheet(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        frame(minWidth: width, idealWidth: width, minHeight: height, idealHeight: height)
        #else
        self
        #endif
    }

    func macTerminalSheet() -> some View {
        #if os(macOS)
        macSheet(width: Platform.terminalSheet.width, height: Platform.terminalSheet.height)
        #else
        self
        #endif
    }

    // a Mac text field in a list draws as bare text on a line; give it the
    // bordered box that says "type here"
    func macFieldStyle() -> some View {
        #if os(macOS)
        textFieldStyle(.roundedBorder)
        #else
        self
        #endif
    }

    // a button that is a list row: on a Mac, the row itself, not a pill in it
    func macRowButton() -> some View {
        #if os(macOS)
        buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
        #else
        self
        #endif
    }

    // a menu drawn as its label alone: no border, no indicator
    func plainMenu() -> some View {
        menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
    }

    // the thread's branch under its title in a Mac window's toolbar
    func windowSubtitle(_ text: String) -> some View {
        #if os(macOS)
        navigationSubtitle(text)
        #else
        self
        #endif
    }

    // an iPad sheet the size of a page, room for a sidebar beside its pane
    @ViewBuilder
    func pageSheet() -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) { presentationSizing(.page) } else { self }
        #else
        self
        #endif
    }

    // a divider that can be dragged shows the resize cursor on a Mac
    func resizeCursor(horizontal: Bool) -> some View {
        #if os(macOS)
        onHover { inside in
            if inside { (horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() }
        }
        #else
        self
        #endif
    }
}

enum Platform {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    // a link out of the app, in the system's browser
    static func open(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }

    static func registerForRemoteNotifications() {
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #else
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    // A phone app in the background is suspended, so the hub's push carries
    // the alert. A Mac app keeps running behind other windows and has no
    // push without an APNs entitlement, so it posts its own alerts; the
    // notifier still drops the one for the thread on show.
    static var postsAlertsInBackground: Bool {
        #if os(iOS)
        false
        #else
        true
        #endif
    }

    // image data as JPEG (a HEIC photo, attached as something every hub reads)
    static func jpeg(_ data: Data, quality: Double) -> Data? {
        #if os(iOS)
        UIImage(data: data)?.jpegData(compressionQuality: quality)
        #else
        guard let rep = NSImage(data: data).flatMap({ $0.tiffRepresentation }).flatMap(NSBitmapImageRep.init(data:)) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #endif
    }

    // the terminal's monospaced font and its line height
    static func monoFont(size: CGFloat) -> (width: CGFloat, line: CGFloat) {
        #if os(iOS)
        let f = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return (("M" as NSString).size(withAttributes: [.font: f]).width, f.lineHeight)
        #else
        let f = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return (("M" as NSString).size(withAttributes: [.font: f]).width, NSLayoutManager().defaultLineHeight(for: f))
        #endif
    }

    // debug checks: a noisy PNG big enough to go up in several pieces
    static func noisePNG(side: Int) -> Data? {
        guard let c = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for y in stride(from: 0, to: side, by: 2) {
            for x in stride(from: 0, to: side, by: 2) {
                c.setFillColor(red: .random(in: 0 ... 1), green: .random(in: 0 ... 1), blue: .random(in: 0 ... 1), alpha: 1)
                c.fill(CGRect(x: x, y: y, width: 2, height: 2))
            }
        }
        guard let img = c.makeImage() else { return nil }
        let out = NSMutableData()
        guard let d = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(d, img, nil)
        return CGImageDestinationFinalize(d) ? out as Data : nil
    }

    // the room the terminal has: the phone's screen (half of it, above the
    // keyboard), or the Mac's terminal sheet (its full height, no keyboard)
    static var terminalArea: CGSize {
        #if os(iOS)
        let b = UIScreen.main.bounds.size
        return CGSize(width: b.width, height: b.height * 0.5)
        #else
        CGSize(width: terminalSheet.width, height: terminalSheet.height - 120)
        #endif
    }

    // the Settings sheet's list of sections (an iPad's inset rows need more)
    static var settingsSidebar: CGFloat {
        #if os(macOS)
        190
        #else
        230
        #endif
    }

    #if os(macOS)
    static let terminalSheet = CGSize(width: 820, height: 560)
    #endif
}
