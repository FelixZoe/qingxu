import SwiftUI

struct SettingsScreen: View {
  @EnvironmentObject private var store: AppStore
  #if os(iOS)
  @EnvironmentObject private var updateChecker: AppUpdateChecker
  #endif
  @AppStorage("qingxu.appearance") private var appearance = AppearanceMode.system.rawValue

  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack(spacing: 14) {
            Image(systemName: "checkmark")
              .font(.title2.weight(.bold))
              .foregroundStyle(.white)
              .frame(width: 48, height: 48)
              .background(QingxuPalette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
              Text("清序").font(.headline)
              Text("版本 \(appVersion)")
                .font(.caption)
                .foregroundStyle(QingxuPalette.quiet)
            }
            Spacer()
            #if os(iOS)
            if updateChecker.availableRelease != nil {
              Text("可更新")
                .font(.caption.weight(.semibold))
                .foregroundStyle(QingxuPalette.accent)
            }
            #endif
            Image(systemName: store.syncSettings.isConfigured ? "cloud.fill" : "iphone")
              .foregroundStyle(store.syncSettings.isConfigured ? QingxuPalette.success : QingxuPalette.quiet)
          }
          .padding(.vertical, 5)
        }

        Section("偏好") {
          NavigationLink {
            AppearanceSettingsView()
          } label: {
            SettingsRow(
              symbol: "circle.lefthalf.filled",
              title: "外观",
              detail: AppearanceMode(rawValue: appearance)?.title ?? "跟随系统",
              tint: QingxuPalette.accent
            )
          }
          NavigationLink {
            SyncSettingsView()
              .environmentObject(store)
          } label: {
            SettingsRow(
              symbol: "arrow.triangle.2.circlepath",
              title: "自托管同步",
              detail: store.syncSettings.isConfigured ? store.syncPhase.title : "未配置",
              tint: QingxuPalette.success
            )
          }
          #if os(iOS)
          NavigationLink {
            AppUpdateSettingsView()
              .environmentObject(updateChecker)
          } label: {
            SettingsRow(
              symbol: "arrow.down.circle.fill",
              title: "软件更新",
              detail: updateDetail,
              tint: QingxuPalette.accent
            )
          }
          #endif
        }

        Section("数据") {
          LabeledContent("待办任务", value: "\(store.inboxTasks.count)")
          LabeledContent("已完成", value: "\(store.completedTasks.count)")
        }

        Section("关于") {
          LabeledContent("清序", value: appVersion)
          Link("项目与下载", destination: URL(string: "https://github.com/FelixZoe/qingxu")!)
        }
      }
      .qingxuScreen()
      .navigationTitle("设置")
      #if os(iOS)
      .task { await updateChecker.check() }
      #endif
    }
  }

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
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
          Task { await updateChecker.check(force: true) }
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

private struct SettingsRow: View {
  let symbol: String
  let title: String
  let detail: String
  let tint: Color

  var body: some View {
    Label {
      HStack {
        Text(title)
        Spacer()
        Text(detail).font(.subheadline).foregroundStyle(QingxuPalette.quiet)
      }
    } icon: {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 30, height: 30)
        .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }
}

struct AppearanceSettingsView: View {
  @AppStorage("qingxu.appearance") private var appearance = AppearanceMode.system.rawValue

  var body: some View {
    Form {
      Section {
        ForEach(AppearanceMode.allCases) { mode in
          Button {
            appearance = mode.rawValue
          } label: {
            HStack {
              Text(mode.title).foregroundStyle(QingxuPalette.ink)
              Spacer()
              if appearance == mode.rawValue {
                Image(systemName: "checkmark").foregroundStyle(QingxuPalette.accent)
              }
            }
          }
          .buttonStyle(.plain)
        }
      } header: {
        Text("配色")
      } footer: {
        Text("日间使用冷瓷白与雾蓝；暗色使用深蓝石墨与柔和蓝光，所有页面共用同一套语义色。")
      }
    }
    .qingxuScreen()
    .navigationTitle("外观")
  }
}

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
