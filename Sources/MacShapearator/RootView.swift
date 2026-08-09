import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var viewModel = ExtractionViewModel()
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            WorkspaceView(viewModel: viewModel)
                .tabItem { Text("Workspace") }
                .tag(0)
            SettingsView()
                .tabItem { Text("Settings") }
                .tag(1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
