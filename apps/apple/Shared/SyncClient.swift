import Foundation

struct SyncEnvelope: Encodable {
  let deviceId: String
  let tasks: [TaskItem]
  let pomodoro: PomodoroState?
}

struct SyncResponse: Decodable {
  let tasks: [TaskItem]
  let pomodoro: PomodoroState?
  let serverTime: Date
  let revision: UInt64?
}

struct SyncChange: Decodable {
  let revision: UInt64
  let changed: Bool
}

enum SyncClientError: LocalizedError {
  case invalidConfiguration(String)
  case invalidResponse
  case server(Int, String)

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration(let message): message
    case .invalidResponse: "服务器返回了无法识别的数据"
    case .server(let code, let message): "\(message)（HTTP \(code)）"
    }
  }
}

struct SyncClient {
  private let session: URLSession

  init() {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 35
    configuration.timeoutIntervalForResource = 40
    configuration.waitsForConnectivity = true
    configuration.httpMaximumConnectionsPerHost = 2
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    session = URLSession(configuration: configuration)
  }

  func testConnection(settings: SyncSettings) async throws {
    try requireConfigured(settings)
    _ = try await request(path: "/health", settings: settings, authenticated: false)
    _ = try await request(path: "/v1/ping", settings: settings, authenticated: true)
  }

  func sync(
    settings: SyncSettings,
    tasks: [TaskItem],
    pomodoro: PomodoroState?
  ) async throws -> SyncResponse {
    try requireConfigured(settings)
    var request = try makeRequest(path: "/v1/sync", settings: settings, authenticated: true)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try QingxuCoding.encoder.encode(
      SyncEnvelope(deviceId: settings.deviceName, tasks: tasks, pomodoro: pomodoro)
    )
    let data = try await perform(request)
    do {
      return try QingxuCoding.decoder.decode(SyncResponse.self, from: data)
    } catch {
      throw SyncClientError.invalidResponse
    }
  }

  func waitForChanges(
    settings: SyncSettings,
    since: UInt64
  ) async throws -> SyncChange {
    try requireConfigured(settings)
    let request = try makeRequest(
      path: "/v1/changes",
      settings: settings,
      authenticated: true,
      queryItems: [URLQueryItem(name: "since", value: String(since))]
    )
    let data = try await perform(request)
    do {
      return try QingxuCoding.decoder.decode(SyncChange.self, from: data)
    } catch {
      throw SyncClientError.invalidResponse
    }
  }

  private func request(
    path: String,
    settings: SyncSettings,
    authenticated: Bool
  ) async throws -> Data {
    try await perform(makeRequest(path: path, settings: settings, authenticated: authenticated))
  }

  private func makeRequest(
    path: String,
    settings: SyncSettings,
    authenticated: Bool,
    queryItems: [URLQueryItem] = []
  ) throws -> URLRequest {
    guard var components = URLComponents(string: settings.normalizedServerURL) else {
      throw SyncClientError.invalidConfiguration("服务器地址格式不正确")
    }
    components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    components.path = "/" + [components.path, path].map {
      $0.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }.filter { !$0.isEmpty }.joined(separator: "/")
    components.queryItems = queryItems.isEmpty ? nil : queryItems
    guard let url = components.url else {
      throw SyncClientError.invalidConfiguration("服务器地址格式不正确")
    }
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if authenticated {
      request.setValue("Bearer \(settings.token)", forHTTPHeaderField: "Authorization")
    }
    return request
  }

  private func perform(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw SyncClientError.invalidResponse
    }
    guard 200..<300 ~= response.statusCode else {
      if response.statusCode == 401 || response.statusCode == 403 {
        throw SyncClientError.server(response.statusCode, "同步密钥无效或无权限")
      }
      let body = String(data: data, encoding: .utf8)?.prefix(160) ?? ""
      let message = body.isEmpty ? "服务器请求失败" : String(body)
      throw SyncClientError.server(response.statusCode, message)
    }
    return data
  }

  private func requireConfigured(_ settings: SyncSettings) throws {
    if let message = settings.validationMessage {
      throw SyncClientError.invalidConfiguration(message)
    }
  }
}
