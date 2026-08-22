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
}

enum SecureSyncToken {
  private static let account = "qingxu.sync.token.v1"

  static func read() -> String {
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

  static func write(_ token: String) throws {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(base as CFDictionary)
    let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return }
    var item = base
    item[kSecValueData as String] = Data(normalized.utf8)
    #if os(iOS)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    #endif
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
  }
}
