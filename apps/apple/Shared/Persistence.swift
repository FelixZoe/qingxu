import Foundation
import Security

enum QingxuFiles {
  private static var root: URL {
    #if os(iOS)
    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    #else
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    #endif
    return base.appendingPathComponent("Qingxu", isDirectory: true)
  }

  static func load<T: Decodable>(_ type: T.Type, name: String) -> T? {
    let url = root.appendingPathComponent(name)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? QingxuCoding.decoder.decode(type, from: data)
  }

  static func save<T: Encodable>(_ value: T, name: String) throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let data = try QingxuCoding.encoder.encode(value)
    try data.write(to: root.appendingPathComponent(name), options: .atomic)
  }

  static var hasPersistedInstallState: Bool {
    FileManager.default.fileExists(atPath: root.path)
  }
}

enum SecureSyncToken {
  private static let account = "qingxu.sync.token.v1"

  static func read() -> String {
    KeychainSecret.read(account: account)
  }

  static func write(_ token: String) throws {
    try KeychainSecret.write(token, account: account)
  }


  static func clear() {
    KeychainSecret.clear(account: account)
  }
}

enum SecureAIAPIKey {
  private static let account = "qingxu.ai.api-key.v1"

  static func read() -> String {
    KeychainSecret.read(account: account)
  }

  static func write(_ apiKey: String) throws {
    try KeychainSecret.write(apiKey, account: account)
  }


  static func clear() {
    KeychainSecret.clear(account: account)
  }
}

enum SecureWeatherAPIKey {
  private static let account = "qingxu.weather.api-key.v1"

  static func read() -> String {
    KeychainSecret.read(account: account)
  }

  static func write(_ apiKey: String) throws {
    try KeychainSecret.write(apiKey, account: account)
  }

  static func clear() {
    KeychainSecret.clear(account: account)
  }
}

private enum KeychainSecret {
  static func read(account: String) -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data,
          let value = String(data: data, encoding: .utf8)
    else { return "" }
    return value
  }

  static func write(_ value: String, account: String) throws {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      clear(account: account)
      return
    }

    let lookup: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: account,
    ]
    var update: [String: Any] = [kSecValueData as String: Data(normalized.utf8)]
    #if os(iOS)
    update[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    #endif
    let updateStatus = SecItemUpdate(lookup as CFDictionary, update as CFDictionary)
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
    }

    var item = lookup
    item.merge(update) { _, new in new }
    let addStatus = SecItemAdd(item as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
    }
  }

  static func clear(account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
  }
}


enum QingxuInstallPrivacy {
  private static let launchMarker = "qingxu.install.didLaunch.v1"

  /// Keychain values survive uninstall on iOS. Clear them only when the app has
  /// no local container state, which identifies a real reinstall. An in-place
  /// update keeps both the local state and the user's secrets.
  static func prepareForLaunch() {
    #if os(iOS)
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: launchMarker) else { return }
    if !QingxuFiles.hasPersistedInstallState {
      SecureSyncToken.clear()
      SecureAIAPIKey.clear()
      SecureWeatherAPIKey.clear()
    }
    defaults.set(true, forKey: launchMarker)
    #endif
  }
}
