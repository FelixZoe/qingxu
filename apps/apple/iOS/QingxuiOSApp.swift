import SwiftUI
import UIKit

@main
struct QingxuiOSApp: App {
  @StateObject private var store = AppStore()
  @AppStorage("qingxu.appearance") private var appearance = AppearanceMode.system.rawValue

  init() {
    if #unavailable(iOS 26.0) {
      let appearance = UITabBarAppearance()
      appearance.configureWithOpaqueBackground()
      appearance.backgroundColor = UIColor(QingxuPalette.background)
      UITabBar.appearance().standardAppearance = appearance
      UITabBar.appearance().scrollEdgeAppearance = appearance
    }
  }

  var body: some Scene {
    WindowGroup {
      iOSRootView()
        .environmentObject(store)
        .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
    }
  }
}

private struct iOSRootView: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var selection = AppTab.inbox
  @State private var showingLaunchExperience = true

  var body: some View {
    ZStack {
      QingxuPalette.background.ignoresSafeArea()

      TabView(selection: $selection) {
        TaskListScreen(scope: .inbox)
          .tabItem { Label(AppTab.inbox.title, systemImage: AppTab.inbox.symbol) }
          .tag(AppTab.inbox)
        TaskListScreen(scope: .today)
          .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.symbol) }
          .tag(AppTab.today)
        PomodoroScreen()
          .tabItem { Label(AppTab.pomodoro.title, systemImage: AppTab.pomodoro.symbol) }
          .tag(AppTab.pomodoro)
        RSSScreen()
          .tabItem { Label(AppTab.rss.title, systemImage: AppTab.rss.symbol) }
          .tag(AppTab.rss)
        SettingsScreen()
          .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.symbol) }
          .tag(AppTab.settings)
      }
      .tint(QingxuPalette.accent)
      .disabled(showingLaunchExperience)

      if showingLaunchExperience {
        QingxuLaunchExperience {
          showingLaunchExperience = false
        }
        .zIndex(10)
      }
    }
    .onChange(of: selection) { _ in
      guard !showingLaunchExperience else { return }
      UISelectionFeedbackGenerator().selectionChanged()
    }
    .onChange(of: scenePhase) { phase in
      guard phase == .active else { return }
      Task { await store.syncNow() }
    }
    .onOpenURL { url in
      switch url.host {
      case "today": selection = .today
      case "pomodoro": selection = .pomodoro
      case "rss": selection = .rss
      case "settings": selection = .settings
      default: selection = .inbox
      }
    }
  }
}
