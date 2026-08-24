import SwiftUI
import UIKit

@main
struct QingxuiOSApp: App {
  @StateObject private var store = AppStore()
  @StateObject private var rssStore = RSSStore()
  @StateObject private var updateChecker = AppUpdateChecker()
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
        .environmentObject(rssStore)
        .environmentObject(updateChecker)
        .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
    }
    .backgroundTask(.appRefresh(RSSBackgroundRefresh.identifier)) {
      await rssStore.refresh()
      RSSBackgroundRefresh.schedule()
    }
  }
}

private struct iOSRootView: View {
  @EnvironmentObject private var store: AppStore
  @EnvironmentObject private var updateChecker: AppUpdateChecker
  @EnvironmentObject private var rssStore: RSSStore
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @State private var selection = AppTab.inbox
  @State private var showingLaunchExperience = true
  @State private var availableUpdate: QingxuRelease?
  @AppStorage(QingxuPreferenceKey.inboxModule) private var inboxEnabled = true
  @AppStorage(QingxuPreferenceKey.pomodoroModule) private var pomodoroEnabled = true
  @AppStorage(QingxuPreferenceKey.rssModule) private var rssEnabled = true

  var body: some View {
    ZStack {
      QingxuPalette.background.ignoresSafeArea()

      TabView(selection: $selection) {
        if inboxEnabled {
          TaskListScreen(scope: .inbox)
            .tabItem { Label(AppTab.inbox.title, systemImage: AppTab.inbox.symbol) }
            .tag(AppTab.inbox)
        }
        TaskListScreen(scope: .today)
          .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.symbol) }
          .tag(AppTab.today)
        if pomodoroEnabled {
          PomodoroScreen()
            .tabItem { Label(AppTab.pomodoro.title, systemImage: AppTab.pomodoro.symbol) }
            .tag(AppTab.pomodoro)
        }
        if rssEnabled {
          RSSScreen(store: rssStore)
            .tabItem { Label(AppTab.rss.title, systemImage: AppTab.rss.symbol) }
            .tag(AppTab.rss)
        }
        SettingsScreen()
          .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.symbol) }
          .tag(AppTab.settings)
      }
      .tint(QingxuPalette.accent)
      .disabled(showingLaunchExperience)

      if showingLaunchExperience {
        QingxuLaunchExperience {
          showingLaunchExperience = false
          checkForUpdates()
        }
        .zIndex(10)
      }
    }
    .onChange(of: selection) { _ in
      guard !showingLaunchExperience else { return }
      UISelectionFeedbackGenerator().selectionChanged()
    }
    .onChange(of: pomodoroEnabled) { enabled in
      if !enabled, selection == .pomodoro { selection = .today }
    }
    .onChange(of: inboxEnabled) { enabled in
      if !enabled, selection == .inbox { selection = .today }
    }
    .onChange(of: rssEnabled) { enabled in
      if !enabled, selection == .rss { selection = inboxEnabled ? .inbox : .today }
    }
    .onChange(of: scenePhase) { phase in
      if phase == .active {
        Task {
          await store.syncNow()
          await rssStore.syncNow()
          await rssStore.refreshIfNeeded()
        }
      } else if phase == .background {
        RSSBackgroundRefresh.schedule()
      }
    }
    .onOpenURL { url in
      switch url.host {
      case "today": selection = .today
      case "inbox": selection = inboxEnabled ? .inbox : .today
      case "pomodoro": selection = pomodoroEnabled ? .pomodoro : (inboxEnabled ? .inbox : .today)
      case "rss": selection = rssEnabled ? .rss : (inboxEnabled ? .inbox : .today)
      case "settings": selection = .settings
      default: selection = inboxEnabled ? .inbox : .today
      }
    }
    .alert(item: $availableUpdate) { release in
      Alert(
        title: Text("发现新版本 v\(release.version)"),
        message: Text(updateMessage(release)),
        primaryButton: .default(Text("直接下载")) {
          openURL(release.iOSAsset?.browserDownloadURL ?? release.htmlURL)
        },
        secondaryButton: .cancel(Text("稍后"))
      )
    }
    .onAppear {
      if !inboxEnabled, selection == .inbox { selection = .today }
      RSSBackgroundRefresh.schedule()
    }
  }

  private func checkForUpdates() {
    Task {
      if let release = await updateChecker.check() {
        availableUpdate = release
      }
    }
  }

  private func updateMessage(_ release: QingxuRelease) -> String {
    let notes = release.body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !notes.isEmpty else { return "新版本已经发布，可前往 GitHub 下载 IPA。" }
    return String(notes.prefix(240))
  }
}
