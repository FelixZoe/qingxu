import Citadel
import CryptoKit
import Foundation
import NIOCore
import NIOSSH
import Security
@preconcurrency import SwiftTerm
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct RemoteServerProfile: Codable, Identifiable, Hashable {
  var id = UUID()
  var name = ""
  var host = ""
  var port = 22
  var username = ""

  var displayName: String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? host : trimmed
  }
}

@MainActor
final class RemoteServerStore: ObservableObject {
  @Published private(set) var servers: [RemoteServerProfile] = []

  private let defaultsKey = "qingxu.remote.servers.v1"
  private let keychain = RemoteSecretStore()

  init() {
    reload()
  }

  func password(for server: RemoteServerProfile) -> String {
    keychain.read(account: server.id.uuidString) ?? ""
  }

  func save(_ server: RemoteServerProfile, password: String) {
    if let index = servers.firstIndex(where: { $0.id == server.id }) {
      servers[index] = server
    } else {
      servers.append(server)
    }
    servers.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    persist()
    if !password.isEmpty {
      keychain.write(password, account: server.id.uuidString)
    }
  }

  func remove(_ offsets: IndexSet) {
    let removed = offsets.compactMap { servers.indices.contains($0) ? servers[$0] : nil }
    servers.remove(atOffsets: offsets)
    removed.forEach { keychain.delete(account: $0.id.uuidString) }
    persist()
  }

  private func reload() {
    guard let data = UserDefaults.standard.data(forKey: defaultsKey),
          let decoded = try? JSONDecoder().decode([RemoteServerProfile].self, from: data)
    else { return }
    servers = decoded
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(servers) else { return }
    UserDefaults.standard.set(data, forKey: defaultsKey)
  }
}

private struct RemoteSecretStore {
  private let service = "one.darker.qingxu.remote"

  func read(account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  func write(_ value: String, account: String) {
    delete(account: account)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecValueData as String: Data(value.utf8)
    ]
    SecItemAdd(query as CFDictionary, nil)
  }

  func delete(account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    SecItemDelete(query as CFDictionary)
  }
}

private struct RemoteKnownHost: Codable, Sendable {
  let host: String
  let port: Int
  let fingerprint: String
  let publicKey: String
  let firstSeenAt: Date
  var lastSeenAt: Date
}

private enum RemoteHostKeyError: LocalizedError, Sendable {
  case invalidKey
  case changed(expected: String, presented: String)

  var errorDescription: String? {
    switch self {
    case .invalidKey:
      "服务器返回了无法识别的 SSH 主机密钥。"
    case .changed(let expected, let presented):
      "SSH 主机密钥已变化。为防止中间人攻击，连接已停止。原指纹：\(expected)，当前指纹：\(presented)。"
    }
  }
}

private final class RemoteKnownHostsStore: @unchecked Sendable {
  static let shared = RemoteKnownHostsStore()

  private let storageKey = "qingxu.remote.known-hosts.v1"
  private let lock = NSLock()

  func validate(hostKey: NIOSSHPublicKey, host: String, port: Int) throws -> RemoteKnownHost {
    let publicKey = String(openSSHPublicKey: hostKey)
    let components = publicKey.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
    guard components.count >= 2, let keyData = Data(base64Encoded: String(components[1])) else {
      throw RemoteHostKeyError.invalidKey
    }

    let digest = SHA256.hash(data: keyData)
    let fingerprint = "SHA256:" + Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
    let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let key = "\(normalizedHost):\(port)"

    lock.lock()
    defer { lock.unlock() }
    var entries = loadAll()
    if var existing = entries[key] {
      guard existing.fingerprint == fingerprint else {
        throw RemoteHostKeyError.changed(expected: existing.fingerprint, presented: fingerprint)
      }
      existing.lastSeenAt = Date()
      entries[key] = existing
      saveAll(entries)
      return existing
    }

    let entry = RemoteKnownHost(
      host: normalizedHost,
      port: port,
      fingerprint: fingerprint,
      publicKey: publicKey,
      firstSeenAt: Date(),
      lastSeenAt: Date()
    )
    entries[key] = entry
    saveAll(entries)
    return entry
  }

  func entry(host: String, port: Int) -> RemoteKnownHost? {
    let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    lock.lock()
    defer { lock.unlock() }
    return loadAll()["\(normalizedHost):\(port)"]
  }

  private func loadAll() -> [String: RemoteKnownHost] {
    guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [:] }
    return (try? JSONDecoder().decode([String: RemoteKnownHost].self, from: data)) ?? [:]
  }

  private func saveAll(_ entries: [String: RemoteKnownHost]) {
    guard let data = try? JSONEncoder().encode(entries) else { return }
    UserDefaults.standard.set(data, forKey: storageKey)
  }
}

private final class RemoteHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
  private let host: String
  private let port: Int

  init(host: String, port: Int) {
    self.host = host
    self.port = port
  }

  func validateHostKey(
    hostKey: NIOSSHPublicKey,
    validationCompletePromise: EventLoopPromise<Void>
  ) {
    do {
      _ = try RemoteKnownHostsStore.shared.validate(hostKey: hostKey, host: host, port: port)
      validationCompletePromise.succeed(())
    } catch {
      validationCompletePromise.fail(error)
    }
  }
}

struct RemoteMachineStatus: Equatable {
  var hostname = "—"
  var system = "—"
  var uptime = "—"
  var load = "—"
  var memory = "—"
  var disk = "—"

  init() {}

  init(output: String) {
    var values: [String: String] = [:]
    output.split(whereSeparator: \.isNewline).forEach { line in
      let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else { return }
      values[String(parts[0])] = String(parts[1])
    }
    hostname = values["hostname"] ?? "—"
    system = values["system"] ?? "—"
    uptime = values["uptime"] ?? "—"
    load = values["load"] ?? "—"
    memory = values["memory"] ?? "—"
    disk = values["disk"] ?? "—"
  }
}

struct RemoteFileItem: Identifiable, Hashable {
  let name: String
  let path: String
  let isDirectory: Bool
  let size: UInt64?
  let modifiedAt: Date?

  var id: String { path }
}

@MainActor
final class RemoteWorkspace: ObservableObject {
  enum ConnectionPhase: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)

    var title: String {
      switch self {
      case .idle: "未连接"
      case .connecting: "正在连接"
      case .connected: "已连接"
      case .failed: "连接失败"
      }
    }
  }

  @Published private(set) var phase: ConnectionPhase = .idle
  @Published private(set) var machineStatus = RemoteMachineStatus()
  @Published private(set) var currentPath = "."
  @Published private(set) var files: [RemoteFileItem] = []
  @Published private(set) var isLoadingFiles = false
  @Published private(set) var hostFingerprint = "首次连接后显示"
  @Published var filePreview: RemoteFilePreview?

  let server: RemoteServerProfile
  private let password: String
  private var client: SSHClient?
  private var sftp: SFTPClient?
  private var terminalWriter: TTYStdinWriter?
  private weak var terminalView: TerminalView?
  private var terminalTask: Task<Void, Never>?

  init(server: RemoteServerProfile, password: String) {
    self.server = server
    self.password = password
  }

  deinit {
    terminalTask?.cancel()
  }

  func connect() async {
    guard client == nil, phase != .connecting else { return }
    phase = .connecting
    do {
      let connectedClient = try await SSHClient.connect(
        host: server.host,
        port: server.port,
        authenticationMethod: .passwordBased(username: server.username, password: password),
        hostKeyValidator: .custom(RemoteHostKeyValidator(host: server.host, port: server.port)),
        reconnect: .never
      )
      client = connectedClient
      hostFingerprint = RemoteKnownHostsStore.shared.entry(host: server.host, port: server.port)?.fingerprint
        ?? "无法读取"
      phase = .connected
      async let status: Void = refreshStatus()
      async let directory: Void = loadDirectory(".")
      _ = await (status, directory)
      startTerminalIfNeeded()
    } catch {
      phase = .failed(Self.message(for: error))
    }
  }

  func disconnect() {
    terminalTask?.cancel()
    terminalTask = nil
    terminalWriter = nil
    sftp = nil
    let closingClient = client
    client = nil
    phase = .idle
    Task { try? await closingClient?.close() }
  }

  func reconnect() async {
    disconnect()
    await connect()
  }

  func refreshStatus() async {
    guard let client else { return }
    let command = #"""
    LC_ALL=C
    printf 'hostname=%s\n' "$(hostname 2>/dev/null || printf unknown)"
    printf 'system=%s\n' "$(uname -srm 2>/dev/null || printf unknown)"
    printf 'uptime=%s\n' "$(uptime -p 2>/dev/null || uptime 2>/dev/null || printf unknown)"
    printf 'load=%s\n' "$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null || sysctl -n vm.loadavg 2>/dev/null || printf unknown)"
    printf 'memory=%s\n' "$(free -h 2>/dev/null | awk '/^Mem:/ {print $3" / "$2}' || vm_stat 2>/dev/null | head -1 || printf unknown)"
    printf 'disk=%s\n' "$(df -h / 2>/dev/null | awk 'NR==2 {print $3" / "$2" · "$5}' || printf unknown)"
    """#
    do {
      var response = try await client.executeCommand(command, maxResponseSize: 65_536)
      let output = response.readString(length: response.readableBytes) ?? ""
      machineStatus = RemoteMachineStatus(output: output)
    } catch {
      phase = .failed(Self.message(for: error))
    }
  }

  func loadDirectory(_ path: String) async {
    guard let client else { return }
    isLoadingFiles = true
    defer { isLoadingFiles = false }
    do {
      let activeSFTP: SFTPClient
      if let sftp {
        activeSFTP = sftp
      } else {
        activeSFTP = try await client.openSFTP()
        sftp = activeSFTP
      }
      let canonical = try await activeSFTP.getRealPath(atPath: path)
      let batches = try await activeSFTP.listDirectory(atPath: canonical)
      currentPath = canonical
      files = batches
        .flatMap(\.components)
        .filter { $0.filename != "." && $0.filename != ".." }
        .map { component in
          let joined = canonical == "/" ? "/\(component.filename)" : "\(canonical)/\(component.filename)"
          let mode = component.attributes.permissions ?? 0
          return RemoteFileItem(
            name: component.filename,
            path: joined,
            isDirectory: mode & 0o170000 == 0o040000,
            size: component.attributes.size,
            modifiedAt: component.attributes.accessModificationTime?.modificationTime
          )
        }
        .sorted {
          if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
          return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    } catch {
      phase = .failed(Self.message(for: error))
    }
  }

  func goToParentDirectory() async {
    guard currentPath != "/" else { return }
    let parent = (currentPath as NSString).deletingLastPathComponent
    await loadDirectory(parent.isEmpty ? "/" : parent)
  }

  func open(_ file: RemoteFileItem) async {
    if file.isDirectory {
      await loadDirectory(file.path)
      return
    }
    guard let sftp else { return }
    do {
      let handle = try await sftp.openFile(filePath: file.path, flags: .read)
      let requested = UInt32(min(file.size ?? 1_048_576, 1_048_576))
      var buffer = try await handle.read(from: 0, length: requested)
      try await handle.close()
      guard let text = buffer.readString(length: buffer.readableBytes) else {
        filePreview = RemoteFilePreview(name: file.name, text: "这个文件不是可预览的文本格式。")
        return
      }
      let suffix = (file.size ?? 0) > UInt64(requested) ? "\n\n— 仅预览前 1 MB —" : ""
      filePreview = RemoteFilePreview(name: file.name, text: text + suffix)
    } catch {
      filePreview = RemoteFilePreview(name: file.name, text: "读取失败：\(Self.message(for: error))")
    }
  }

  func attachTerminal(_ view: TerminalView) {
    terminalView = view
    startTerminalIfNeeded()
  }

  func sendToTerminal(_ bytes: ArraySlice<UInt8>) {
    guard let writer = terminalWriter else { return }
    Task {
      do {
        try await writer.write(ByteBuffer(bytes: bytes))
      } catch {
        await MainActor.run { self.phase = .failed(Self.message(for: error)) }
      }
    }
  }

  func resizeTerminal(columns: Int, rows: Int) {
    guard let writer = terminalWriter, columns > 0, rows > 0 else { return }
    Task {
      try? await writer.changeSize(cols: columns, rows: rows, pixelWidth: 0, pixelHeight: 0)
    }
  }

  private func startTerminalIfNeeded() {
    guard terminalTask == nil, let client, terminalView != nil else { return }
    terminalTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await client.withTTY { inbound, outbound in
          await MainActor.run { self.terminalWriter = outbound }
          for try await event in inbound {
            guard !Task.isCancelled else { return }
            let bytes: [UInt8]
            switch event {
            case .stdout(let buffer), .stderr(let buffer):
              bytes = Array(buffer.readableBytesView)
            }
            await MainActor.run {
              self.terminalView?.feed(byteArray: bytes[...])
            }
          }
        }
      } catch {
        guard !Task.isCancelled else { return }
        await MainActor.run { self.phase = .failed(Self.message(for: error)) }
      }
    }
  }

  private static func message(for error: Error) -> String {
    let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? String(describing: error) : text
  }
}

struct RemoteFilePreview: Identifiable {
  let id = UUID()
  let name: String
  let text: String
}

struct RemoteAccessScreen: View {
  @StateObject private var store = RemoteServerStore()
  @State private var editingServer: RemoteServerProfile?
  @State private var showingNewServer = false

  var body: some View {
    NavigationStack {
      Group {
        if store.servers.isEmpty {
          ContentUnavailableView {
            Label("还没有服务器", systemImage: "terminal")
          } description: {
            Text("添加一次连接信息，就能查看状态、打开终端和管理文件。")
          } actions: {
            Button("添加服务器") { showingNewServer = true }
              .buttonStyle(.borderedProminent)
          }
        } else {
          List {
            Section {
              ForEach(store.servers) { server in
                NavigationLink {
                  RemoteServerDetailView(server: server, password: store.password(for: server))
                } label: {
                  HStack(spacing: 14) {
                    Image(systemName: "server.rack")
                      .font(.title3)
                      .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 3) {
                      Text(server.displayName).font(.body.weight(.semibold))
                      Text("\(server.username)@\(server.host):\(server.port)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    }
                  }
                  .contextMenu {
                    Button("编辑") { editingServer = server }
                  }
                }
              }
              .onDelete(perform: store.remove)
            } footer: {
              Text("密码只保存在这台设备的系统钥匙串中，不会进入同步数据或 Git 仓库。")
            }
          }
        }
      }
      .navigationTitle("服务器")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button { showingNewServer = true } label: { Image(systemName: "plus") }
        }
      }
      .sheet(isPresented: $showingNewServer) {
        RemoteServerEditor(store: store, server: RemoteServerProfile())
      }
      .sheet(item: $editingServer) { server in
        RemoteServerEditor(store: store, server: server)
      }
    }
  }
}

private struct RemoteServerEditor: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var store: RemoteServerStore
  @State private var server: RemoteServerProfile
  @State private var password: String

  init(store: RemoteServerStore, server: RemoteServerProfile) {
    self.store = store
    _server = State(initialValue: server)
    _password = State(initialValue: store.password(for: server))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("连接") {
          TextField("名称（可选）", text: $server.name)
          #if os(iOS)
          TextField("主机或 IP", text: $server.host)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          #else
          TextField("主机或 IP", text: $server.host)
          #endif
          TextField("端口", value: $server.port, format: .number)
          #if os(iOS)
          TextField("用户名", text: $server.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          #else
          TextField("用户名", text: $server.username)
          #endif
        }
        Section {
          #if os(iOS)
          SecureField("密码", text: $password).textContentType(.password)
          #else
          SecureField("密码", text: $password)
          #endif
        } header: {
          Text("认证")
        } footer: {
          Text("当前版本先提供密码认证；私钥认证会作为下一步单独加入，不会把私钥写入普通配置。")
        }
      }
      .navigationTitle(server.host.isEmpty ? "添加服务器" : "编辑服务器")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            store.save(server, password: password)
            dismiss()
          }
          .disabled(server.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || server.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || password.isEmpty)
        }
      }
    }
  }
}

private enum RemoteSection: String, CaseIterable, Identifiable {
  case status = "状态"
  case terminal = "终端"
  case files = "文件"
  var id: String { rawValue }
}

private struct RemoteServerDetailView: View {
  @StateObject private var workspace: RemoteWorkspace
  @State private var section = RemoteSection.status

  init(server: RemoteServerProfile, password: String) {
    _workspace = StateObject(wrappedValue: RemoteWorkspace(server: server, password: password))
  }

  var body: some View {
    VStack(spacing: 0) {
      Picker("功能", selection: $section) {
        ForEach(RemoteSection.allCases) { item in Text(item.rawValue).tag(item) }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, 18)
      .padding(.vertical, 12)

      Group {
        switch section {
        case .status: RemoteStatusPane(workspace: workspace)
        case .terminal: RemoteTerminalPane(workspace: workspace)
        case .files: RemoteFilesPane(workspace: workspace)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .navigationTitle(workspace.server.displayName)
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task { await workspace.reconnect() }
        } label: {
          Image(systemName: workspace.phase == .connected ? "bolt.horizontal.circle.fill" : "arrow.clockwise")
        }
        .disabled(workspace.phase == .connecting)
      }
    }
    .task { await workspace.connect() }
    .onDisappear { workspace.disconnect() }
    .sheet(item: $workspace.filePreview) { preview in
      NavigationStack {
        ScrollView {
          Text(preview.text)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle(preview.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("完成") { workspace.filePreview = nil }
          }
        }
      }
    }
  }
}

private struct RemoteStatusPane: View {
  @ObservedObject var workspace: RemoteWorkspace

  private let columns = [GridItem(.adaptive(minimum: 145), spacing: 12)]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 10) {
          Circle()
            .fill(workspace.phase == .connected ? Color.green : Color.secondary)
            .frame(width: 9, height: 9)
          Text(workspace.phase.title).font(.subheadline.weight(.semibold))
          Spacer()
          if case .failed(let message) = workspace.phase {
            Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
        }

        LazyVGrid(columns: columns, spacing: 12) {
          RemoteMetricCard(title: "主机", value: workspace.machineStatus.hostname, symbol: "server.rack")
          RemoteMetricCard(title: "运行时间", value: workspace.machineStatus.uptime, symbol: "clock")
          RemoteMetricCard(title: "系统", value: workspace.machineStatus.system, symbol: "cpu")
          RemoteMetricCard(title: "负载", value: workspace.machineStatus.load, symbol: "waveform.path.ecg")
          RemoteMetricCard(title: "内存", value: workspace.machineStatus.memory, symbol: "memorychip")
          RemoteMetricCard(title: "系统盘", value: workspace.machineStatus.disk, symbol: "internaldrive")
        }

        VStack(alignment: .leading, spacing: 7) {
          Label("SSH 主机指纹", systemImage: "checkmark.shield")
            .font(.subheadline.weight(.semibold))
          Text(workspace.hostFingerprint)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
          Text("首次连接时信任当前主机密钥；以后密钥发生变化会立即拒绝连接。")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      }
      .padding(18)
    }
    .refreshable { await workspace.refreshStatus() }
  }
}

private struct RemoteMetricCard: View {
  let title: String
  let value: String
  let symbol: String

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Image(systemName: symbol).font(.headline)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.caption).foregroundStyle(.secondary)
        Text(value).font(.subheadline.weight(.semibold)).lineLimit(3)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
    .padding(16)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }
}

private struct RemoteTerminalPane: View {
  @ObservedObject var workspace: RemoteWorkspace

  var body: some View {
    ZStack {
      Color.black
      QingxuTerminalView(workspace: workspace)
      if workspace.phase != .connected {
        VStack(spacing: 10) {
          ProgressView().tint(.white)
          Text(workspace.phase.title).font(.caption).foregroundStyle(.white.opacity(0.65))
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .padding(.horizontal, 12)
    .padding(.bottom, 12)
  }
}

private struct RemoteFilesPane: View {
  @ObservedObject var workspace: RemoteWorkspace

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Button { Task { await workspace.goToParentDirectory() } } label: {
          Image(systemName: "chevron.up")
        }
        .disabled(workspace.currentPath == "/")
        Text(workspace.currentPath)
          .font(.caption.monospaced())
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer()
        if workspace.isLoadingFiles { ProgressView().controlSize(.small) }
        Button { Task { await workspace.loadDirectory(workspace.currentPath) } } label: {
          Image(systemName: "arrow.clockwise")
        }
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 10)

      List(workspace.files) { item in
        Button {
          Task { await workspace.open(item) }
        } label: {
          HStack(spacing: 13) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc")
              .foregroundStyle(item.isDirectory ? QingxuPalette.accent : .secondary)
              .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
              Text(item.name).foregroundStyle(.primary).lineLimit(1)
              HStack(spacing: 8) {
                if let size = item.size, !item.isDirectory {
                  Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                }
                if let date = item.modifiedAt {
                  Text(date, style: .date)
                }
              }
              .font(.caption2)
              .foregroundStyle(.secondary)
            }
            Spacer()
            if item.isDirectory { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .listStyle(.plain)
      .overlay {
        if workspace.files.isEmpty, !workspace.isLoadingFiles {
          ContentUnavailableView("文件夹为空", systemImage: "folder")
        }
      }
    }
  }
}

@MainActor
private final class QingxuTerminalCoordinator: NSObject, TerminalViewDelegate {
  weak var workspace: RemoteWorkspace?

  init(workspace: RemoteWorkspace) {
    self.workspace = workspace
  }

  func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
    workspace?.resizeTerminal(columns: newCols, rows: newRows)
  }

  func setTerminalTitle(source: TerminalView, title: String) {}
  func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
  func send(source: TerminalView, data: ArraySlice<UInt8>) { workspace?.sendToTerminal(data) }
  func scrolled(source: TerminalView, position: Double) {}
  func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

  func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
    guard let url = URL(string: link) else { return }
    #if os(iOS)
    UIApplication.shared.open(url)
    #elseif os(macOS)
    NSWorkspace.shared.open(url)
    #endif
  }
}

#if os(iOS)
private struct QingxuTerminalView: UIViewRepresentable {
  @ObservedObject var workspace: RemoteWorkspace

  func makeCoordinator() -> QingxuTerminalCoordinator {
    QingxuTerminalCoordinator(workspace: workspace)
  }

  func makeUIView(context: Context) -> TerminalView {
    let view = TerminalView(frame: .zero, font: .monospacedSystemFont(ofSize: 13, weight: .regular))
    view.terminalDelegate = context.coordinator
    view.nativeBackgroundColor = .black
    view.nativeForegroundColor = .white
    workspace.attachTerminal(view)
    return view
  }

  func updateUIView(_ view: TerminalView, context: Context) {
    context.coordinator.workspace = workspace
    workspace.attachTerminal(view)
  }
}
#elseif os(macOS)
private struct QingxuTerminalView: NSViewRepresentable {
  @ObservedObject var workspace: RemoteWorkspace

  func makeCoordinator() -> QingxuTerminalCoordinator {
    QingxuTerminalCoordinator(workspace: workspace)
  }

  func makeNSView(context: Context) -> TerminalView {
    let view = TerminalView(frame: .zero)
    view.terminalDelegate = context.coordinator
    view.configureNativeColors()
    workspace.attachTerminal(view)
    return view
  }

  func updateNSView(_ view: TerminalView, context: Context) {
    context.coordinator.workspace = workspace
    workspace.attachTerminal(view)
  }
}
#endif
