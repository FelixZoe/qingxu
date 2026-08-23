import SwiftUI

struct SettingsScreen: View {
  @EnvironmentObject private var store: AppStore
  @AppStorage("qingxu.appearance") private var appearance = AppearanceMode.system.rawValue

  var body: some View {
    NavigationStack {
      Form {
        Section {
          NavigationLink {
            AppearanceSettingsView()
          } label: {
            SettingsRow(
              symbol: "circle.lefthalf.filled",
              title: "外观",
              detail: AppearanceMode(rawValue: appearance)?.title ?? "跟随系统"
            )
          }
          NavigationLink {
            SyncSettingsView()
              .environmentObject(store)
          } label: {
            SettingsRow(
              symbol: "arrow.triangle.2.circlepath",
              title: "自托管同步",
              detail: store.syncSettings.isConfigured ? store.syncPhase.title : "未配置"
            )
          }
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
    }
  }

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
  }
}

private struct SettingsRow: View {
  let symbol: String
  let title: String
  let detail: String

  var body: some View {
    Label {
      HStack {
        Text(title)
        Spacer()
        Text(detail).font(.subheadline).foregroundStyle(.secondary)
      }
    } icon: {
      Image(systemName: symbol).foregroundStyle(QingxuPalette.accent)
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
              Text(mode.title).foregroundStyle(.primary)
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
          .foregroundStyle(.secondary)
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
