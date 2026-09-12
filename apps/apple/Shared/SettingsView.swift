import SwiftUI
#if os(iOS)
import UIKit
#endif

private extension View {
  @ViewBuilder
  func qingxuSettingsDestination() -> some View {
    #if os(iOS)
    background {
      SettingsTabBarTransitionBridge()
        .allowsHitTesting(false)
    }
    #else
    self
    #endif
  }
}

#if os(iOS)
/// Keeps the native tab bar transition attached to the navigation controller's
/// own animator. Interactive back gestures therefore scrub the tab bar opacity
/// and position instead of abruptly toggling it at either end of the gesture.
private struct SettingsTabBarTransitionBridge: UIViewControllerRepresentable {
  func makeUIViewController(context: Context) -> Controller {
    Controller()
  }

  func updateUIViewController(_ controller: Controller, context: Context) {}

  final class Controller: UIViewController {
    private weak var tabBar: UITabBar?

    override func loadView() {
      view = UIView(frame: .zero)
      view.isUserInteractionEnabled = false
      view.backgroundColor = .clear
    }

    override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
      guard let tabBar = resolveTabBar() else { return }
      self.tabBar = tabBar
      animate(tabBar: tabBar, hidden: true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      apply(tabBar: resolveTabBar(), hidden: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
      super.viewWillDisappear(animated)
      guard isLeavingSettingsDestination,
            let tabBar = resolveTabBar() ?? tabBar else { return }
      animate(tabBar: tabBar, hidden: false, animated: animated)
    }

    private var isLeavingSettingsDestination: Bool {
      var candidate = parent
      while let controller = candidate {
        if controller.isMovingFromParent || controller.navigationController?.isBeingDismissed == true {
          return true
        }
        if controller is UINavigationController { break }
        candidate = controller.parent
      }
      return navigationController?.transitionCoordinator?.isInteractive == true
    }

    private func resolveTabBar() -> UITabBar? {
      var candidate: UIViewController? = self
      while let controller = candidate {
        if let tabController = controller as? UITabBarController {
          return tabController.tabBar
        }
        if let tabController = controller.tabBarController {
          return tabController.tabBar
        }
        candidate = controller.parent
      }
      return view.window?.rootViewController?.findTabBarController()?.tabBar
    }

    private func animate(tabBar: UITabBar, hidden: Bool, animated: Bool) {
      tabBar.isUserInteractionEnabled = !hidden
      let changes: () -> Void = { [weak self, weak tabBar] in
        guard let self else { return }
        self.apply(tabBar: tabBar, hidden: hidden)
      }
      let completion: (UIViewControllerTransitionCoordinatorContext) -> Void = { [weak self, weak tabBar] context in
        guard context.isCancelled else { return }
        self?.apply(tabBar: tabBar, hidden: !hidden)
        tabBar?.isUserInteractionEnabled = hidden
      }

      if animated, let coordinator = transitionCoordinator ?? navigationController?.transitionCoordinator {
        coordinator.animate(alongsideTransition: { _ in changes() }, completion: completion)
      } else if animated {
        UIView.animate(
          withDuration: 0.3,
          delay: 0,
          options: [.beginFromCurrentState, .curveEaseInOut, .allowUserInteraction],
          animations: changes
        )
      } else {
        changes()
      }
    }

    private func apply(tabBar: UITabBar?, hidden: Bool) {
      guard let tabBar else { return }
      tabBar.alpha = hidden ? 0 : 1
      tabBar.transform = hidden
        ? CGAffineTransform(translationX: 0, y: min(14, tabBar.bounds.height * 0.12))
        : .identity
    }
  }
}

private extension UIViewController {
  func findTabBarController() -> UITabBarController? {
    if let tabController = self as? UITabBarController { return tabController }
    for child in children {
      if let tabController = child.findTabBarController() { return tabController }
    }
    if let presentedViewController {
      return presentedViewController.findTabBarController()
    }
    return nil
  }
}
#endif

struct SettingsScreen: View {
  @EnvironmentObject private var store: AppStore
  #if os(iOS)
  @EnvironmentObject private var updateChecker: AppUpdateChecker
  #endif
  @AppStorage("qingxu.appearance") private var appearance = AppearanceMode.system.rawValue

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 22) {
          SettingsGroup(title: "效率与界面") {
            NavigationLink { FeatureModulesSettingsView().qingxuSettingsDestination() } label: {
              SettingsDestinationRow(
                symbol: "square.grid.2x2.fill",
                title: "功能模块",
                detail: "管理底部导航",
                tint: QingxuPalette.warning
              )
            }
            SettingsDivider()
            AppearanceInlineRow(appearance: $appearance)
            #if os(iOS)
            SettingsDivider()
            NavigationLink { NotificationAndFeedbackSettingsView().qingxuSettingsDestination() } label: {
              SettingsDestinationRow(
                symbol: "bell.badge.fill",
                title: "声音、提醒与触感",
                detail: "每日提醒与完成反馈",
                tint: QingxuPalette.danger
              )
            }
            #endif
            SettingsDivider()
            NavigationLink { CalendarPreferencesView().qingxuSettingsDestination() } label: {
              SettingsDestinationRow(
                symbol: "calendar",
                title: "日期与日历",
                detail: "周起始日与显示内容",
                tint: QingxuPalette.success
              )
            }
          }

          SettingsGroup(title: "数据与系统") {
            NavigationLink { SyncSettingsView().environmentObject(store).qingxuSettingsDestination() } label: {
              SettingsDestinationRow(
                symbol: "arrow.clockwise",
                title: "自托管同步",
                detail: store.syncSettings.isConfigured ? store.syncPhase.title : "未配置",
                tint: QingxuPalette.success
              )
            }
            SettingsDivider()
            NavigationLink { AmbientSettingsView().qingxuSettingsDestination() } label: {
              SettingsDestinationRow(
                symbol: "cloud.sun.fill",
                title: "天气与每日一句",
                detail: ambientDetail,
                tint: QingxuPalette.accent
              )
            }
            SettingsDivider()
            NavigationLink { AISettingsView().environmentObject(store).qingxuSettingsDestination() } label: {
              SettingsDestinationRow(
                symbol: "sparkles",
                title: "AI 助手",
                detail: aiDetail,
                tint: QingxuPalette.ink
              )
            }
            #if os(iOS)
            SettingsDivider()
            NavigationLink { AppUpdateSettingsView().environmentObject(updateChecker).qingxuSettingsDestination() } label: {
              SettingsDestinationRow(
                symbol: "arrow.down.circle.fill",
                title: "软件更新",
                detail: updateDetail,
                tint: QingxuPalette.warning
              )
            }
            #endif
          }

          SettingsGroup(title: "关于") {
            Link(destination: URL(string: "https://github.com/FelixZoe/qingxu")!) {
              SettingsDestinationRow(
                symbol: "chevron.left.forwardslash.chevron.right",
                title: "项目与下载",
                detail: "GitHub",
                tint: QingxuPalette.ink
              )
            }
          }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 120)
      }
      .qingxuScreen()
      .navigationTitle("设置")
      #if os(iOS)
      .task { await updateChecker.check() }
      #endif
    }
  }

  #if os(iOS)
  private var updateDetail: String {
    switch updateChecker.state {
    case .checking: return "正在检查"
    case .available(let release): return "v\(release.version)"
    case .current: return "已是最新"
    case .failed: return "检查失败"
    case .idle: return "检查更新"
    }
  }
  #endif

  private var aiDetail: String {
    guard store.aiSettings.isConfigured(syncSettings: store.syncSettings) else {
      return "未配置"
    }
    switch store.aiSettings.mode {
    case .selfHosted, .openAI, .deepSeek: return store.aiSettings.mode.title
    case .compatible: return "自定义服务"
    }
  }

  private var ambientDetail: String {
    let preferences = QingxuAmbientPreferencesStore.load()
    if preferences.weatherConfigured { return preferences.cityName.isEmpty ? "已配置" : preferences.cityName }
    return preferences.quoteEnabled ? "每日一句已开启" : "未配置"
  }
}

#if os(iOS)
private struct AppUpdateSettingsView: View {
  @EnvironmentObject private var updateChecker: AppUpdateChecker
  @Environment(\.openURL) private var openURL

  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        VStack(alignment: .leading, spacing: 16) {
          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
              Text("清序").font(.title2.weight(.semibold))
              Text("v\(updateChecker.currentVersion) · 构建 \(updateChecker.currentBuild)")
                .font(.subheadline).foregroundStyle(QingxuPalette.quiet)
            }
            Spacer()
            Image(systemName: "checkmark.seal")
              .font(.title2).foregroundStyle(QingxuPalette.accent)
          }
          updateStatus
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QingxuPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

        if let release = updateChecker.availableRelease {
          VStack(alignment: .leading, spacing: 12) {
            Text("v\(release.version) 更新内容").font(.headline)
            if !release.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              Text(release.body)
                .font(.subheadline).foregroundStyle(QingxuPalette.quiet)
                .textSelection(.enabled)
            }
          }
          .padding(20)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(QingxuPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }

        Button { Task { await checkAndOpenIfNeeded() } } label: {
          HStack(spacing: 10) {
            if isChecking { ProgressView().tint(QingxuPalette.onAccent) }
            Text(updateChecker.availableRelease == nil ? "检查更新" : "下载并覆盖安装")
              .font(.body.weight(.semibold))
          }
          .foregroundStyle(QingxuPalette.onAccent)
          .frame(maxWidth: .infinity).frame(height: 52)
          .background(QingxuPalette.accent, in: Capsule())
        }
        .buttonStyle(.plain).disabled(isChecking)

        Text("覆盖安装需保持应用标识与签名身份一致。下载后直接用同一 Apple ID 或证书重新签名安装，任务和本机设置会保留。")
          .font(.footnote).foregroundStyle(QingxuPalette.quiet)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(18).padding(.bottom, 80)
    }
    .qingxuScreen()
    .navigationTitle("软件更新")
    .navigationBarTitleDisplayMode(.inline)
    .task { await updateChecker.check() }
  }

  @ViewBuilder
  private var updateStatus: some View {
    switch updateChecker.state {
    case .idle:
      Label("尚未检查", systemImage: "clock")
    case .checking:
      Label("正在连接 GitHub", systemImage: "network")
    case .current:
      Label("当前已经是最新版本", systemImage: "checkmark.circle.fill")
        .foregroundStyle(QingxuPalette.success)
    case .available(let release):
      Label("发现新版本 v\(release.version)", systemImage: "arrow.down.circle.fill")
        .foregroundStyle(QingxuPalette.accent)
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(QingxuPalette.danger)
    }
  }

  private var isChecking: Bool {
    if case .checking = updateChecker.state { return true }
    return false
  }

  @MainActor
  private func checkAndOpenIfNeeded() async {
    let release: QingxuRelease?
    if let available = updateChecker.availableRelease {
      release = available
    } else {
      release = await updateChecker.check(force: true)
    }
    guard let release else { return }
    openURL(release.iOSAsset?.browserDownloadURL ?? release.htmlURL)
  }
}
#endif

private struct SettingsGroup<Content: View>: View {
  let title: String
  let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(QingxuPalette.quiet)
        .padding(.leading, 7)

      VStack(spacing: 0) { content }
        .background(QingxuPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(QingxuPalette.separator.opacity(0.65), lineWidth: 0.6)
        }
    }
  }
}

private struct SettingsDivider: View {
  var body: some View {
    Divider().overlay(QingxuPalette.separator).padding(.leading, 64)
  }
}

private struct SettingsDestinationRow: View {
  let symbol: String
  let title: String
  let detail: String
  let tint: Color

  var body: some View {
    HStack(spacing: 14) {
      SettingsRowGlyph(symbol: symbol)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.body.weight(.medium))
          .foregroundStyle(QingxuPalette.ink)
        if !detail.isEmpty {
          Text(detail)
            .font(.caption)
            .foregroundStyle(QingxuPalette.quiet)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 8)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(QingxuPalette.faint)
    }
    .padding(.horizontal, 16)
    .frame(minHeight: 68)
    .contentShape(Rectangle())
  }
}

private struct SettingsValueRow: View {
  let title: String
  let value: String

  var body: some View {
    HStack {
      Text(title).foregroundStyle(QingxuPalette.ink)
      Spacer()
      Text(value).foregroundStyle(QingxuPalette.quiet).monospacedDigit()
    }
    .padding(.horizontal, 18)
    .frame(minHeight: 54)
  }
}

private struct AppearanceInlineRow: View {
  @Binding var appearance: String

  var body: some View {
    HStack(spacing: 14) {
      SettingsRowGlyph(symbol: "circle.lefthalf.filled")
      Text("外观")
        .font(.body.weight(.medium))
        .foregroundStyle(QingxuPalette.ink)
      Spacer(minLength: 12)
      Menu {
        ForEach(AppearanceMode.allCases) { mode in
          Button {
            appearance = mode.rawValue
          } label: {
            if appearance == mode.rawValue {
              Label(mode.title, systemImage: "checkmark")
            } else {
              Text(mode.title)
            }
          }
        }
      } label: {
        HStack(spacing: 5) {
          Text(selectedAppearanceTitle)
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption2.weight(.semibold))
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(QingxuPalette.quiet)
      }
    }
    .padding(.horizontal, 16)
    .frame(minHeight: 68)
  }

  private var selectedAppearanceTitle: String {
    AppearanceMode(rawValue: appearance)?.title ?? AppearanceMode.system.title
  }
}

private struct PreferenceToggleRow: View {
  let symbol: String
  let title: String
  let detail: String
  let tint: Color
  @Binding var isOn: Bool

  var body: some View {
    HStack(spacing: 14) {
      SettingsRowGlyph(symbol: symbol)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.body.weight(.medium)).foregroundStyle(QingxuPalette.ink)
        Text(detail).font(.caption).foregroundStyle(QingxuPalette.quiet)
      }
      Spacer(minLength: 8)
      Toggle("", isOn: $isOn).labelsHidden().tint(QingxuPalette.accent)
    }
    .padding(.horizontal, 16)
    .frame(minHeight: 72)
  }
}

private struct SettingsRowGlyph: View {
  let symbol: String

  var body: some View {
    Image(systemName: symbol)
      .resizable()
      .scaledToFit()
    .foregroundStyle(QingxuPalette.ink)
    .frame(width: 22, height: 22)
    .frame(width: 36, height: 36)
  }
}

private struct FeatureModulesSettingsView: View {
  @AppStorage(QingxuPreferenceKey.inboxModule) private var inboxEnabled = false
  @AppStorage(QingxuPreferenceKey.pomodoroModule) private var pomodoroEnabled = true
  @AppStorage(QingxuPreferenceKey.rssModule) private var rssEnabled = true
  @AppStorage(QingxuPreferenceKey.remoteAccessModule) private var remoteAccessEnabled = true
  @AppStorage(QingxuPreferenceKey.moduleOrder) private var moduleOrder = QingxuModuleOrder.defaultValue
  @State private var orderedTabs = AppTab.allCases
  @State private var pendingEnable: AppTab?
  #if os(iOS)
  @State private var editMode = EditMode.active
  #endif

  var body: some View {
    List {
      Section {
        ForEach(orderedTabs) { tab in
          HStack(spacing: 14) {
            SettingsRowGlyph(symbol: tab.symbol)
            VStack(alignment: .leading, spacing: 3) {
              Text(tab.title).font(.body.weight(.medium))
              Text(moduleDetail(tab)).font(.caption).foregroundStyle(QingxuPalette.quiet)
            }
            Spacer()
            if isOptional(tab) {
              Toggle("", isOn: moduleBinding(for: tab)).labelsHidden().tint(QingxuPalette.accent)
            } else {
              Text("固定")
                .font(.caption.weight(.medium))
                .foregroundStyle(QingxuPalette.quiet)
            }
          }
          .padding(.vertical, 5)
        }
        .onMove(perform: move)
      } header: {
        Text("按住右侧拖动调整底部导航顺序")
      } footer: {
        Text("底部导航始终只有 5 个独立入口。今天与设置固定保留；达到上限后启用其他模块，需要替换一个当前入口。")
      }
    }
    .qingxuScreen()
    .navigationTitle("功能模块")
    .onAppear {
      reloadOrder()
      normalizeEnabledModules()
    }
    .onDisappear(perform: persistOrder)
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    .environment(\.editMode, $editMode)
    #endif
    .confirmationDialog(
      "替换一个导航入口",
      isPresented: Binding(
        get: { pendingEnable != nil },
        set: { if !$0 { pendingEnable = nil } }
      ),
      titleVisibility: .visible
    ) {
      ForEach(enabledOptionalTabs) { current in
        Button("用\(pendingEnable?.title ?? "新模块")替换\(current.title)") {
          guard let pendingEnable else { return }
          setEnabled(false, for: current)
          setEnabled(true, for: pendingEnable)
          self.pendingEnable = nil
        }
      }
      Button("取消", role: .cancel) { pendingEnable = nil }
    } message: {
      Text("不会合并页面，也不会生成系统的“更多”页。")
    }
  }

  private func move(from source: IndexSet, to destination: Int) {
    orderedTabs.move(fromOffsets: source, toOffset: destination)
  }

  private func reloadOrder() {
    orderedTabs = QingxuModuleOrder.decode(moduleOrder)
  }

  private func persistOrder() {
    let normalizedValue = QingxuModuleOrder.encode(orderedTabs)
    if moduleOrder != normalizedValue {
      moduleOrder = normalizedValue
    }
  }

  private var enabledOptionalTabs: [AppTab] {
    QingxuNavigationPolicy.optionalTabs.filter(isEnabled)
  }

  private func isOptional(_ tab: AppTab) -> Bool {
    !QingxuNavigationPolicy.fixedTabs.contains(tab)
  }

  private func moduleBinding(for tab: AppTab) -> Binding<Bool> {
    Binding(
      get: { isEnabled(tab) },
      set: { requested in
        if !requested {
          setEnabled(false, for: tab)
        } else if enabledOptionalTabs.count < QingxuNavigationPolicy.maximumEnabledOptionalTabs {
          setEnabled(true, for: tab)
        } else {
          pendingEnable = tab
        }
      }
    )
  }

  private func isEnabled(_ tab: AppTab) -> Bool {
    switch tab {
    case .inbox: inboxEnabled
    case .pomodoro: pomodoroEnabled
    case .rss: rssEnabled
    case .remoteAccess: remoteAccessEnabled
    case .today, .settings: true
    }
  }

  private func setEnabled(_ enabled: Bool, for tab: AppTab) {
    switch tab {
    case .inbox: inboxEnabled = enabled
    case .pomodoro: pomodoroEnabled = enabled
    case .rss: rssEnabled = enabled
    case .remoteAccess: remoteAccessEnabled = enabled
    case .today, .settings: break
    }
  }

  private func normalizeEnabledModules() {
    let normalized = QingxuNavigationPolicy.normalizedEnabledTabs(
      inbox: inboxEnabled,
      pomodoro: pomodoroEnabled,
      rss: rssEnabled,
      remoteAccess: remoteAccessEnabled
    )
    for tab in QingxuNavigationPolicy.optionalTabs {
      setEnabled(normalized.contains(tab), for: tab)
    }
  }

  private func moduleDetail(_ tab: AppTab) -> String {
    switch tab {
    case .inbox: "快速收集暂未安排的任务"
    case .today: "日历与当天任务"
    case .pomodoro: "专注计时与统计"
    case .rss: "按来源阅读订阅内容"
    case .remoteAccess: "查看状态、使用终端和管理文件"
    case .settings: "账户、同步和偏好"
    }
  }
}

#if os(iOS)
private struct NotificationAndFeedbackSettingsView: View {
  @AppStorage(QingxuPreferenceKey.haptics) private var hapticsEnabled = true
  @AppStorage(QingxuPreferenceKey.completionSound) private var completionSoundEnabled = false
  @AppStorage(QingxuPreferenceKey.dailyReminder) private var dailyReminderEnabled = false
  @AppStorage(QingxuPreferenceKey.dailyReminderMinutes) private var reminderMinutes = 9 * 60
  @State private var reminderMessage = ""

  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        SettingsGroup(title: "完成反馈") {
          PreferenceToggleRow(
            symbol: "hand.tap.fill", title: "完成任务时触感", detail: "勾选任务时给出轻柔反馈",
            tint: QingxuPalette.accent, isOn: $hapticsEnabled
          )
          SettingsDivider()
          PreferenceToggleRow(
            symbol: "speaker.wave.2.fill", title: "完成提示音", detail: "完成任务时播放简短声音",
            tint: QingxuPalette.success, isOn: $completionSoundEnabled
          )

          Button {
            QingxuFeedback.taskCompletion(haptics: hapticsEnabled, sound: completionSoundEnabled)
          } label: {
            Text("测试完成反馈")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(QingxuPalette.accent)
              .frame(maxWidth: .infinity)
              .frame(height: 48)
          }
          .buttonStyle(.plain)
        }

        SettingsGroup(title: "每日提醒") {
          PreferenceToggleRow(
            symbol: "bell.badge.fill", title: "提醒查看今日任务", detail: "每天一次，不会持续打扰",
            tint: QingxuPalette.warning,
            isOn: Binding(
              get: { dailyReminderEnabled },
              set: { value in
                dailyReminderEnabled = value
                updateReminder()
              }
            )
          )
          SettingsDivider()
          DatePicker("提醒时间", selection: reminderDate, displayedComponents: .hourAndMinute)
            .disabled(!dailyReminderEnabled)
            .padding(.horizontal, 18)
            .frame(minHeight: 56)
            .onChange(of: reminderMinutes) { _ in
              if dailyReminderEnabled { updateReminder() }
            }
        }

        if !reminderMessage.isEmpty {
          Text(reminderMessage)
            .font(.footnote)
            .foregroundStyle(QingxuPalette.quiet)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
        }
      }
      .padding(18)
      .padding(.bottom, 80)
    }
    .qingxuScreen()
    .navigationTitle("声音、提醒与触感")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var reminderDate: Binding<Date> {
    Binding(
      get: {
        Calendar.current.date(
          bySettingHour: reminderMinutes / 60,
          minute: reminderMinutes % 60,
          second: 0,
          of: .now
        ) ?? .now
      },
      set: { date in
        let values = Calendar.current.dateComponents([.hour, .minute], from: date)
        reminderMinutes = (values.hour ?? 9) * 60 + (values.minute ?? 0)
      }
    )
  }

  private func updateReminder() {
    Task {
      do {
        let enabled = try await QingxuDailyReminder.update(
          enabled: dailyReminderEnabled,
          minutesAfterMidnight: reminderMinutes
        )
        if dailyReminderEnabled, !enabled {
          dailyReminderEnabled = false
          reminderMessage = "通知权限未开启，请先在系统设置中允许清序发送通知。"
        } else {
          reminderMessage = dailyReminderEnabled ? "每日提醒已保存。" : "每日提醒已关闭。"
        }
      } catch {
        dailyReminderEnabled = false
        reminderMessage = "保存提醒失败：\(error.localizedDescription)"
      }
    }
  }
}
#endif

private struct CalendarPreferencesView: View {
  @AppStorage(QingxuPreferenceKey.weekStartsMonday) private var weekStartsMonday = true
  @AppStorage(QingxuPreferenceKey.showFestivals) private var showFestivals = true
  @AppStorage(QingxuPreferenceKey.showTaskIndicators) private var showTaskIndicators = true

  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        SettingsGroup(title: "星期") {
          PreferenceToggleRow(
            symbol: "calendar", title: "星期一作为一周开始", detail: weekStartsMonday ? "当前从星期一开始" : "当前从星期日开始",
            tint: QingxuPalette.accent, isOn: $weekStartsMonday
          )
        }
        SettingsGroup(title: "日历内容") {
          PreferenceToggleRow(
            symbol: "sparkles", title: "显示节日", detail: "在日期下方显示常用节日",
            tint: QingxuPalette.success, isOn: $showFestivals
          )
          SettingsDivider()
          PreferenceToggleRow(
            symbol: "circle.fill", title: "显示任务标记", detail: "有任务的日期显示小圆点",
            tint: QingxuPalette.warning, isOn: $showTaskIndicators
          )
        }
        Text("节日数据随应用提供，不需要连接第三方接口，也不会读取你的系统日历。")
          .font(.footnote)
          .foregroundStyle(QingxuPalette.quiet)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 7)
      }
      .padding(18)
      .padding(.bottom, 80)
    }
    .qingxuScreen()
    .navigationTitle("日期与日历")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
  }
}

struct SyncSettingsView: View {
  @EnvironmentObject private var store: AppStore
  @State private var draft = SyncSettings()
  @State private var testing = false
  @State private var message: String?

  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Label(store.syncSettings.isConfigured ? "已连接个人服务器" : "连接个人服务器", systemImage: "server.rack")
              .font(.headline)
            Spacer()
            Circle()
              .fill(statusColor).frame(width: 9, height: 9)
          }
          Text("保存后会立即拉取远端数据，并持续监听其他设备的变化。")
            .font(.subheadline).foregroundStyle(QingxuPalette.quiet)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(QingxuPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

        SettingsGroup(title: "连接信息") {
          AmbientFieldRow(title: "服务器") {
            TextField("https://todo.darker.one", text: $draft.serverURL)
              #if os(iOS)
              .textInputAutocapitalization(.never).keyboardType(.URL)
              #endif
              .autocorrectionDisabled().multilineTextAlignment(.trailing)
          }
          SettingsDivider()
          AmbientFieldRow(title: "同步密钥") {
            SecureField("64 位十六进制密钥", text: $draft.token)
              #if os(iOS)
              .textInputAutocapitalization(.never)
              #endif
              .multilineTextAlignment(.trailing)
          }
          SettingsDivider()
          AmbientFieldRow(title: "设备名称") {
            TextField("我的 iPhone", text: $draft.deviceName).multilineTextAlignment(.trailing)
          }
          SettingsDivider()
          PreferenceToggleRow(
            symbol: "bolt.horizontal.circle", title: "实时同步",
            detail: "保持长连接，并在网络恢复后自动补传", tint: QingxuPalette.accent,
            isOn: $draft.autoSync
          )
        }

        Button { Task { await connectSaveAndSync() } } label: {
          HStack(spacing: 10) {
            if testing { ProgressView().tint(QingxuPalette.onAccent) }
            Text(testing ? "正在验证并同步…" : "验证、保存并立即同步")
              .font(.body.weight(.semibold))
          }
          .foregroundStyle(QingxuPalette.onAccent)
          .frame(maxWidth: .infinity).frame(height: 52)
          .background(QingxuPalette.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(testing || draft.validationMessage != nil)

        if let message {
          Text(message).font(.footnote).foregroundStyle(message.contains("成功") ? QingxuPalette.success : QingxuPalette.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if case .failed(let error) = store.syncPhase {
          Text(error).font(.footnote).foregroundStyle(QingxuPalette.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        Text("只填写服务器根地址，不要添加 /v1/sync。密钥仅存放在系统钥匙串；重装后重新填写同一地址和密钥，即会从服务器恢复任务与番茄钟状态。")
          .font(.footnote).foregroundStyle(QingxuPalette.quiet)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(18).padding(.bottom, 80)
    }
    .qingxuScreen()
    .navigationTitle("自托管同步")
    .onAppear { draft = store.syncSettings }
  }

  @MainActor
  private func connectSaveAndSync() async {
    testing = true
    message = nil
    defer { testing = false }
    do {
      try await store.testConnection(draft)
      try store.saveSyncSettings(draft)
      let succeeded = await store.syncNow()
      message = succeeded ? "连接成功，远端数据已同步。" : "连接已保存，但首次同步失败，请检查网络后重试。"
    } catch {
      message = error.localizedDescription
    }
  }

  private var statusColor: Color {
    switch store.syncPhase {
    case .synced: QingxuPalette.success
    case .syncing: QingxuPalette.accent
    case .failed: QingxuPalette.danger
    case .localOnly: QingxuPalette.faint
    }
  }
}

private struct AmbientSettingsView: View {
  @State private var preferences = QingxuAmbientPreferencesStore.load()
  @State private var apiKey = SecureWeatherAPIKey.read()
  @State private var testing = false
  @State private var message = ""
  @State private var preview: QingxuWeatherSnapshot?
  @State private var quotePreview: QingxuQuoteSnapshot?

  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        SettingsGroup(title: "收集箱顶部") {
          PreferenceToggleRow(
            symbol: "quote.opening", title: "每日一句", detail: "每天更新一次，轻点收集箱顶部可手动刷新",
            tint: QingxuPalette.accent, isOn: $preferences.quoteEnabled
          )
          SettingsDivider()
          PreferenceToggleRow(
            symbol: "cloud.sun.fill", title: "天气", detail: "使用自己的和风天气开发凭据",
            tint: QingxuPalette.accent, isOn: $preferences.weatherEnabled
          )
        }

        if preferences.weatherEnabled {
          SettingsGroup(title: "和风天气") {
            AmbientFieldRow(title: "API Host") {
              TextField("abc123.re.qweatherapi.com", text: $preferences.weatherHost)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
            }
            SettingsDivider()
            AmbientFieldRow(title: "API Key") {
              SecureField("必填", text: $apiKey)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
            }
            SettingsDivider()
            AmbientFieldRow(title: "Location ID") {
              TextField("101010100", text: $preferences.locationID)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .multilineTextAlignment(.trailing)
            }
            SettingsDivider()
            AmbientFieldRow(title: "城市名称") {
              TextField("北京", text: $preferences.cityName)
                .multilineTextAlignment(.trailing)
            }
          }

          Button {
            Task { await testWeather() }
          } label: {
            HStack(spacing: 10) {
              if testing { ProgressView().tint(QingxuPalette.onAccent) }
              Text(testing ? "正在连接…" : "测试天气连接")
                .font(.body.weight(.semibold))
            }
            .foregroundStyle(QingxuPalette.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(QingxuPalette.actionGradient, in: Capsule())
          }
          .buttonStyle(.plain)
          .disabled(testing)
        }

        if let preview {
          AmbientPreviewCard(weather: preview, quote: quotePreview)
        } else if let quotePreview {
          AmbientPreviewCard(weather: nil, quote: quotePreview)
        }

        if !message.isEmpty {
          Text(message)
            .font(.footnote)
            .foregroundStyle(QingxuPalette.quiet)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
        }

        Text("和风天气需要在控制台创建项目并填写专属 API Host 与 Key。Location ID 默认是北京；每日一句由 Hitokoto 提供，不需要密钥。密钥只保存在系统钥匙串中。")
          .font(.footnote)
          .foregroundStyle(QingxuPalette.quiet)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 7)
      }
      .padding(18)
      .padding(.bottom, 80)
    }
    .qingxuScreen()
    .navigationTitle("天气与每日一句")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("保存") { save() }.fontWeight(.semibold)
      }
    }
    .task {
      if preferences.quoteEnabled {
        quotePreview = try? await QingxuQuoteClient().fetch()
      }
    }
  }

  private func save() {
    do {
      try SecureWeatherAPIKey.write(apiKey)
      try QingxuAmbientPreferencesStore.save(preferences)
      message = "设置已保存，今日首页会自动刷新。"
    } catch {
      message = "保存失败：\(error.localizedDescription)"
    }
  }

  @MainActor
  private func testWeather() async {
    testing = true
    defer { testing = false }
    do {
      preview = try await QingxuWeatherClient().fetch(preferences: preferences, apiKey: apiKey)
      message = "连接成功：\(preview?.cityName ?? "") \(preview?.temperature ?? "")° \(preview?.text ?? "")"
    } catch {
      message = error.localizedDescription
    }
  }
}

private struct AmbientFieldRow<Content: View>: View {
  let title: String
  let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    HStack(spacing: 16) {
      Text(title).foregroundStyle(QingxuPalette.ink)
      Spacer(minLength: 12)
      content
        .foregroundStyle(QingxuPalette.quiet)
        .frame(maxWidth: 210)
    }
    .padding(.horizontal, 18)
    .frame(minHeight: 58)
  }
}

private struct AmbientPreviewCard: View {
  let weather: QingxuWeatherSnapshot?
  let quote: QingxuQuoteSnapshot?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("首页预览").font(.headline)
        Spacer()
        if let weather {
          Text("\(weather.cityName)  \(weather.temperature)°  \(weather.text)")
            .font(.subheadline.weight(.medium))
        }
      }
      if let quote {
        Text("“\(quote.text)”")
          .font(.subheadline)
          .foregroundStyle(QingxuPalette.ink)
        Text("— \(quote.source)")
          .font(.caption)
          .foregroundStyle(QingxuPalette.quiet)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(QingxuPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(QingxuPalette.separator.opacity(0.65), lineWidth: 0.6)
    }
  }
}

struct AISettingsView: View {
  @EnvironmentObject private var store: AppStore
  @State private var draft = AISettings()
  @State private var testing = false
  @State private var message: String?

  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        SettingsGroup(title: "服务") {
          AmbientFieldRow(title: "AI 服务") {
            Picker("AI 服务", selection: $draft.mode) {
              ForEach(AIConnectionMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.menu)
          }
        }

        SettingsGroup(title: draft.mode.title) {
          configurationRows
        }

        Button { Task { await testAndSave() } } label: {
          HStack(spacing: 10) {
            if testing { ProgressView().tint(QingxuPalette.onAccent) }
            Text(testing ? "正在测试…" : "测试并保存")
              .font(.body.weight(.semibold))
          }
          .foregroundStyle(QingxuPalette.onAccent)
          .frame(maxWidth: .infinity).frame(height: 52)
          .background(QingxuPalette.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(testing || draft.validationMessage(syncSettings: store.syncSettings) != nil)

        if let message {
          Text(message)
            .font(.footnote)
            .foregroundStyle(message.hasPrefix("连接成功") ? QingxuPalette.success : QingxuPalette.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let validation = draft.validationMessage(syncSettings: store.syncSettings) {
          Text(validation).font(.footnote).foregroundStyle(QingxuPalette.quiet)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        Text("服务商地址、模型和 RSS 摘要提示词均已内置。通常只需选择服务并填写 API 密钥；只有自定义兼容服务需要额外填写接口和模型。密钥只保存在本机钥匙串。")
          .font(.footnote).foregroundStyle(QingxuPalette.quiet)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(18).padding(.bottom, 80)
    }
    .qingxuScreen()
    .navigationTitle("AI 助手")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .onAppear { draft = store.aiSettings }
    .onChange(of: draft.mode) { mode in
      applyPreset(for: mode)
    }
  }

  @ViewBuilder
  private var configurationRows: some View {
    switch draft.mode {
    case .selfHosted:
      SettingsValueRow(title: "服务器", value: store.syncSettings.isConfigured ? store.syncSettings.normalizedServerURL : "未配置")
      SettingsDivider()
      NavigationLink { SyncSettingsView().environmentObject(store) } label: {
        SettingsDestinationRow(symbol: "arrow.clockwise", title: "同步服务器", detail: "AI 请求由自托管服务处理", tint: QingxuPalette.accent)
      }
    case .openAI, .deepSeek:
      AmbientFieldRow(title: "API 密钥") {
        SecureField("必填", text: $draft.apiKey)
          #if os(iOS)
          .textInputAutocapitalization(.never)
          #endif
          .multilineTextAlignment(.trailing)
      }
      SettingsDivider()
      SettingsValueRow(title: "内置模型", value: draft.model)
    case .compatible:
      AmbientFieldRow(title: "接口地址") {
        TextField("https://…/chat/completions", text: $draft.baseURL)
          #if os(iOS)
          .textInputAutocapitalization(.never).keyboardType(.URL)
          #endif
          .multilineTextAlignment(.trailing)
      }
      SettingsDivider()
      AmbientFieldRow(title: "模型") {
        TextField("模型名称", text: $draft.model).multilineTextAlignment(.trailing)
      }
      SettingsDivider()
      AmbientFieldRow(title: "API 密钥") {
        SecureField("必填", text: $draft.apiKey).multilineTextAlignment(.trailing)
      }
    }
  }

  @MainActor
  private func testAndSave() async {
    testing = true
    message = nil
    defer { testing = false }
    do {
      try await store.testAIConnection(draft)
      draft.summaryPrompt = ""
      try store.saveAISettings(draft)
      message = "连接成功，设置已保存。"
    } catch {
      message = error.localizedDescription
    }
  }

  private func applyPreset(for mode: AIConnectionMode) {
    guard let baseURL = mode.presetBaseURL,
          let model = mode.presetModel
    else { return }
    draft.baseURL = baseURL
    draft.model = model
    draft.summaryPrompt = ""
    message = nil
  }
}
