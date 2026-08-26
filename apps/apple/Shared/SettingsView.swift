import SwiftUI

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
            NavigationLink { FeatureModulesSettingsView() } label: {
              SettingsDestinationRow(
                symbol: "square.grid.2x2.fill",
                title: "功能模块",
                detail: "管理底部导航",
                tint: QingxuPalette.warning
              )
            }
            SettingsDivider()
            NavigationLink { AppearanceSettingsView() } label: {
              SettingsDestinationRow(
                symbol: "paintpalette.fill",
                title: "外观",
                detail: AppearanceMode(rawValue: appearance)?.title ?? "跟随系统",
                tint: QingxuPalette.accent
              )
            }
            #if os(iOS)
            SettingsDivider()
            NavigationLink { NotificationAndFeedbackSettingsView() } label: {
              SettingsDestinationRow(
                symbol: "bell.badge.fill",
                title: "声音、提醒与触感",
                detail: "每日提醒与完成反馈",
                tint: QingxuPalette.danger
              )
            }
            #endif
            SettingsDivider()
            NavigationLink { CalendarPreferencesView() } label: {
              SettingsDestinationRow(
                symbol: "calendar",
                title: "日期与日历",
                detail: "周起始日与显示内容",
                tint: QingxuPalette.success
              )
            }
          }

          SettingsGroup(title: "数据与系统") {
            NavigationLink { SyncSettingsView().environmentObject(store) } label: {
              SettingsDestinationRow(
                symbol: "arrow.triangle.2.circlepath",
                title: "自托管同步",
                detail: store.syncSettings.isConfigured ? store.syncPhase.title : "未配置",
                tint: QingxuPalette.success
              )
            }
            #if os(iOS)
            SettingsDivider()
            NavigationLink { WidgetSettingsView() } label: {
              SettingsDestinationRow(
                symbol: "rectangle.3.group.fill",
                title: "小组件与灵动岛",
                detail: "任务和专注状态",
                tint: QingxuPalette.accent
              )
            }
            SettingsDivider()
            NavigationLink { AppUpdateSettingsView().environmentObject(updateChecker) } label: {
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
}

#if os(iOS)
private struct AppUpdateSettingsView: View {
  @EnvironmentObject private var updateChecker: AppUpdateChecker
  @Environment(\.openURL) private var openURL

  var body: some View {
    Form {
      Section("当前版本") {
        LabeledContent("版本", value: "v\(updateChecker.currentVersion)")
        LabeledContent("构建", value: updateChecker.currentBuild)
      }

      Section("更新状态") {
        updateStatus
        Button {
          Task {
            if let release = await updateChecker.check(force: true) {
              openURL(release.iOSAsset?.browserDownloadURL ?? release.htmlURL)
            }
          }
        } label: {
          if case .checking = updateChecker.state {
            HStack(spacing: 10) {
              ProgressView()
              Text("正在检查…")
            }
          } else {
            Label("检查更新", systemImage: "arrow.clockwise")
          }
        }
        .disabled(isChecking)
      }

      if let release = updateChecker.availableRelease {
        Section("v\(release.version)") {
          if !release.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(release.body)
              .font(.subheadline)
              .foregroundStyle(QingxuPalette.quiet)
              .textSelection(.enabled)
          }

          if let asset = release.iOSAsset {
            Button {
              openURL(asset.browserDownloadURL)
            } label: {
              Label("下载新版 IPA", systemImage: "arrow.down.circle.fill")
            }
          }

          Button {
            openURL(release.htmlURL)
          } label: {
            Label("打开 GitHub Release", systemImage: "safari")
          }
        }
      }

      Section {
        Text("覆盖安装必须保持 Bundle ID 为 one.darker.qingxu，并使用与当前安装版本相同的签名身份。满足这两个条件时，重新签名并安装新版 IPA 会保留任务、设置与同步配置。")
          .font(.footnote)
          .foregroundStyle(QingxuPalette.quiet)
      } header: {
        Text("覆盖安装")
      }
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
    Group {
      #if os(iOS)
      if let asset = assetName {
        Image(asset)
          .resizable()
          .renderingMode(.template)
          .scaledToFit()
      } else {
        Image(systemName: symbol)
          .resizable()
          .scaledToFit()
      }
      #else
      Image(systemName: symbol)
        .resizable()
        .scaledToFit()
      #endif
    }
    .foregroundStyle(QingxuPalette.ink)
    .frame(width: 22, height: 22)
    .frame(width: 36, height: 36)
  }

  private var assetName: String? {
    switch symbol {
    case "square.grid.2x2.fill": "SettingsModules"
    case "paintpalette.fill": "SettingsAppearance"
    case "bell.badge.fill": "SettingsNotifications"
    case "calendar": "SettingsCalendar"
    case "arrow.triangle.2.circlepath": "SettingsSync"
    case "rectangle.3.group.fill": "SettingsWidgets"
    case "arrow.down.circle.fill": "SettingsUpdate"
    case "chevron.left.forwardslash.chevron.right": "SettingsCode"
    default: nil
    }
  }
}

private struct FeatureModulesSettingsView: View {
  @AppStorage(QingxuPreferenceKey.inboxModule) private var inboxEnabled = true
  @AppStorage(QingxuPreferenceKey.pomodoroModule) private var pomodoroEnabled = true
  @AppStorage(QingxuPreferenceKey.rssModule) private var rssEnabled = true

  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        SettingsGroup(title: "可选模块") {
          PreferenceToggleRow(
            symbol: "tray.fill", title: "收集箱", detail: "快速记录未安排的任务和想法",
            tint: QingxuPalette.accent, isOn: $inboxEnabled
          )
          SettingsDivider()
          PreferenceToggleRow(
            symbol: "timer", title: "番茄钟", detail: "专注计时与实时同步",
            tint: QingxuPalette.warning, isOn: $pomodoroEnabled
          )
          SettingsDivider()
          PreferenceToggleRow(
            symbol: "dot.radiowaves.left.and.right", title: "RSS 订阅", detail: "按来源阅读订阅内容",
            tint: QingxuPalette.success, isOn: $rssEnabled
          )
        }

        Text("关闭可选模块后，它会从底部导航隐藏，数据不会被删除。")
          .font(.footnote)
          .foregroundStyle(QingxuPalette.quiet)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 7)
      }
      .padding(18)
      .padding(.bottom, 80)
    }
    .qingxuScreen()
    .navigationTitle("功能模块")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
  }

}

struct AppearanceSettingsView: View {
  @AppStorage("qingxu.appearance") private var appearance = AppearanceMode.system.rawValue

  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        SettingsGroup(title: "显示模式") {
          ForEach(Array(AppearanceMode.allCases.enumerated()), id: \.element.id) { index, mode in
            Button {
              withAnimation(.easeInOut(duration: 0.2)) { appearance = mode.rawValue }
            } label: {
              HStack {
                Image(systemName: modeSymbol(mode))
                  .foregroundStyle(QingxuPalette.accent)
                  .frame(width: 32)
                Text(mode.title).foregroundStyle(QingxuPalette.ink)
                Spacer()
                if appearance == mode.rawValue {
                  Image(systemName: "checkmark.circle.fill").foregroundStyle(QingxuPalette.success)
                }
              }
              .padding(.horizontal, 18)
              .frame(minHeight: 58)
            }
            .buttonStyle(.plain)
            if index < AppearanceMode.allCases.count - 1 { SettingsDivider() }
          }
        }

      }
      .padding(18)
      .padding(.bottom, 80)
    }
    .qingxuScreen()
    .navigationTitle("外观")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
  }

  private func modeSymbol(_ mode: AppearanceMode) -> String {
    switch mode {
    case .system: "circle.lefthalf.filled"
    case .light: "sun.max.fill"
    case .dark: "moon.stars.fill"
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

#if os(iOS)
private struct WidgetSettingsView: View {
  @EnvironmentObject private var store: AppStore
  @State private var liveActivityMessage = SystemFeatures.liveActivityStatus
  @State private var testingLiveActivity = false

  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        SettingsGroup(title: "实时活动诊断") {
          Button {
            Task { await testLiveActivity() }
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(testingLiveActivity ? "正在检测…" : "检测并重新启动实时活动")
                  .font(.body.weight(.medium))
                  .foregroundStyle(QingxuPalette.ink)
                Text(liveActivityMessage)
                  .font(.caption)
                  .foregroundStyle(QingxuPalette.quiet)
                  .multilineTextAlignment(.leading)
              }
              Spacer()
              Image(systemName: "arrow.clockwise")
                .foregroundStyle(QingxuPalette.accent)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 72)
          }
          .buttonStyle(.plain)
          .disabled(testingLiveActivity)
        }
        Text("长按主屏幕或锁屏添加“清序”小组件；灵动岛会在番茄钟开始后自动显示。这里仅保留可执行的实时活动检测。")
          .font(.footnote)
          .foregroundStyle(QingxuPalette.quiet)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 7)
      }
      .padding(18)
      .padding(.bottom, 80)
    }
    .qingxuScreen()
    .navigationTitle("小组件与灵动岛")
    .navigationBarTitleDisplayMode(.inline)
  }

  @MainActor
  private func testLiveActivity() async {
    testingLiveActivity = true
    liveActivityMessage = await store.restartLiveActivity()
    testingLiveActivity = false
  }
}
#endif

struct SyncSettingsView: View {
  @EnvironmentObject private var store: AppStore
  @State private var draft = SyncSettings()
  @State private var testing = false
  @State private var message: String?

  var body: some View {
    Form {
      Section("服务器") {
        TextField("https://todo.darker.one", text: $draft.serverURL)
          #if os(iOS)
          .textInputAutocapitalization(.never)
          .keyboardType(.URL)
          #endif
        SecureField("64 位同步密钥", text: $draft.token)
        TextField("设备名称", text: $draft.deviceName)
        Toggle("自动同步", isOn: $draft.autoSync)
      }

      Section {
        Button(testing ? "正在测试…" : "测试连接") {
          Task { await test() }
        }
        .disabled(testing || draft.validationMessage != nil)
        Button("保存设置") { save() }
          .disabled(draft.validationMessage != nil)
        Button("立即同步") { Task { await store.syncNow() } }
          .disabled(!draft.isConfigured)
      }

      if let message {
        Section("状态") { Text(message) }
      } else if case .failed(let error) = store.syncPhase {
        Section("状态") { Text(error).foregroundStyle(QingxuPalette.danger) }
      }

      Section {
        Text("只填写服务器根地址，不需要添加 /v1/sync。同步密钥保存在系统钥匙串中；任务、番茄钟状态与自定义时长会自动同步。")
          .font(.footnote)
          .foregroundStyle(QingxuPalette.quiet)
      }
    }
    .qingxuScreen()
    .navigationTitle("自托管同步")
    .onAppear { draft = store.syncSettings }
  }

  @MainActor
  private func test() async {
    testing = true
    defer { testing = false }
    do {
      try await store.testConnection(draft)
      message = "连接成功，身份验证有效。"
    } catch {
      message = error.localizedDescription
    }
  }

  private func save() {
    do {
      try store.saveSyncSettings(draft)
      message = "设置已保存。"
    } catch {
      message = "保存失败：\(error.localizedDescription)"
    }
  }
}
