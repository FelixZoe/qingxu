import SwiftUI

@main
struct QingxumacOSApp: App {
  @StateObject private var store = AppStore()
  @AppStorage("qingxu.appearance") private var appearance = AppearanceMode.system.rawValue

  var body: some Scene {
    WindowGroup {
      MacRootView()
        .environmentObject(store)
        .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
        .frame(minWidth: 860, minHeight: 600)
    }
    .windowStyle(.titleBar)

    Settings {
      MacPreferencesView()
        .environmentObject(store)
        .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
        .frame(width: 520, height: 420)
    }
  }
}

private struct MacRootView: View {
  @State private var selection: AppTab? = .inbox

  private var sidebarTabs: [AppTab] {
    AppTab.allCases.filter { $0 != .rss }
  }

  var body: some View {
    NavigationSplitView {
      List(sidebarTabs, selection: $selection) { tab in
        Label(tab.title, systemImage: tab.symbol).tag(tab)
      }
      .navigationTitle("清序")
      .listStyle(.sidebar)
      .frame(minWidth: 190)
    } detail: {
      switch selection ?? .inbox {
      case .inbox: TaskListScreen(scope: .inbox)
      case .today: TaskListScreen(scope: .today)
      case .pomodoro: PomodoroScreen()
      case .rss: EmptyView()
      case .settings: SettingsScreen()
      }
    }
    .tint(QingxuPalette.accent)
  }
}

private struct MacPreferencesView: View {
  var body: some View {
    TabView {
      AppearanceSettingsView()
        .tabItem { Label("外观", systemImage: "circle.lefthalf.filled") }
      SyncSettingsView()
        .tabItem { Label("同步", systemImage: "arrow.triangle.2.circlepath") }
    }
    .padding(16)
  }
}
