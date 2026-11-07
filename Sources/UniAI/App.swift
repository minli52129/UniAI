import SwiftUI

@main
struct UniAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settingsStore = SettingsStore.shared

    var body: some Scene {
        WindowGroup("UniAI") {
            ContentView()
                .environmentObject(settingsStore)
                .frame(minWidth: 980, minHeight: 640)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
