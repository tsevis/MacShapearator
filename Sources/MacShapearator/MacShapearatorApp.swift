import SwiftUI

@main
struct MacShapearatorApp: App {
    @StateObject private var settingsStore = SettingsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settingsStore)
                .frame(minWidth: 1280, minHeight: 860)
        }
        .windowResizability(.contentSize)
    }
}
