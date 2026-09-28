import SwiftUI
#if os(iOS)
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    var model: AppModel?

    func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        MainActor.assumeIsolated { model?.registered(token) }
    }

    func application(_ app: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("push: %@", error.localizedDescription)
    }
}
#else
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func application(_ app: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        MainActor.assumeIsolated { model?.registered(token) }
    }

    func application(_ app: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("push: %@", error.localizedDescription)
    }
}
#endif

@main
struct BackplaneApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var grace: UIBackgroundTaskIdentifier = .invalid
    #else
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    #endif
    @Environment(\.scenePhase) private var phase
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                // the hub's theme, or the phone's own when it has none
                .preferredColorScheme(model.screen?.theme == "light" ? .light : model.screen?.theme == "dark" ? .dark : nil)
                // backplane://pair?url=... pairs; backplane://open?thread=... shows a thread
                .onOpenURL { model.open($0) }
                .onAppear { delegate.model = model }
        }
        .onChange(of: phase) {
            model.foreground(phase == .active)
            #if os(iOS)
            // a little time after leaving, so a turn ending now still alerts
            if phase == .background, grace == .invalid {
                grace = UIApplication.shared.beginBackgroundTask {
                    UIApplication.shared.endBackgroundTask(grace)
                    grace = .invalid
                }
            } else if phase == .active, grace != .invalid {
                UIApplication.shared.endBackgroundTask(grace)
                grace = .invalid
            }
            #endif
        }
        #if os(macOS)
        SwiftUI.Settings {
            MacSettings(model: model)
                .preferredColorScheme(model.screen?.theme == "light" ? .light : model.screen?.theme == "dark" ? .dark : nil)
        }
        #endif
    }
}

#if os(macOS)
// The app's Settings window (⌘, or the sidebar's More menu): the hub in
// focus's settings, open ("flag settings") while the window is
private struct MacSettings: View {
    let model: AppModel

    var body: some View {
        Group {
            if let st = model.screen?.settings {
                SettingsSheet(model: model, settings: st, version: model.screen?.version ?? "", window: true)
            } else if model.screen == nil {
                ContentUnavailableView("No hub", systemImage: "link", description: Text("Pair with a hub to change its settings."))
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 480, idealHeight: 680)
        .onAppear { if model.screen != nil, model.screen?.settings == nil { model.act("flag", "settings") } }
        // a window opened before the hub answered opens them once it has
        .onChange(of: model.screen == nil) { _, none in if !none, model.screen?.settings == nil { model.act("flag", "settings") } }
        .onDisappear { if model.screen?.settings != nil { model.act("flag", "settings") } }
    }
}
#endif
