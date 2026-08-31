import Foundation

struct QingxuAmbientPreferences: Codable, Equatable {
  var quoteEnabled = true
  var weatherEnabled = true
  var weatherHost = ""
  var locationID = "101010100"
  var cityName = "北京"

  var weatherConfigured: Bool {
    weatherEnabled
      && !weatherHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !SecureWeatherAPIKey.read().isEmpty
      && !locationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

struct QingxuWeatherSnapshot: Codable, Equatable {
  var cityName: String
  var temperature: String
  var text: String
  var icon: String
  var windDirection: String
  var humidity: String
  var updatedAt: Date
}

struct QingxuQuoteSnapshot: Codable, Equatable {
  var text: String
  var source: String
  var updatedAt: Date
}

enum QingxuAmbientPreferencesStore {
  static let didChange = Notification.Name("qingxu.ambient-preferences.changed")
  private static let preferencesKey = "qingxu.ambient.preferences.v1"

  static func load() -> QingxuAmbientPreferences {
    guard let data = UserDefaults.standard.data(forKey: preferencesKey),
          let value = try? JSONDecoder().decode(QingxuAmbientPreferences.self, from: data)
    else { return QingxuAmbientPreferences() }
    return value
  }

  static func save(_ value: QingxuAmbientPreferences) throws {
    UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: preferencesKey)
    NotificationCenter.default.post(name: didChange, object: nil)
  }
}

enum QingxuAmbientServiceError: LocalizedError {
  case invalidHost
  case notConfigured
  case server(String)
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .invalidHost: "API Host 格式不正确"
    case .notConfigured: "请先填写和风天气 Host、Key 与 Location ID"
    case .server(let message): message
    case .invalidResponse: "服务返回了无法识别的数据"
    }
  }
}

struct QingxuWeatherClient {
  private struct Response: Decodable {
    struct Now: Decodable {
      let temp: String
      let text: String
      let icon: String
      let windDir: String
      let humidity: String
    }
    let code: String
    let now: Now?
  }

  func fetch(
    preferences: QingxuAmbientPreferences,
    apiKey: String = SecureWeatherAPIKey.read()
  ) async throws -> QingxuWeatherSnapshot {
    let host = try normalizedHost(preferences.weatherHost)
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let location = preferences.locationID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty, !location.isEmpty else { throw QingxuAmbientServiceError.notConfigured }

    var components = URLComponents()
    components.scheme = "https"
    components.host = host
    components.path = "/v7/weather/now"
    components.queryItems = [
      URLQueryItem(name: "location", value: location),
      URLQueryItem(name: "key", value: key),
    ]
    guard let url = components.url else { throw QingxuAmbientServiceError.invalidHost }
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw QingxuAmbientServiceError.server("天气服务连接失败")
    }
    let decoded = try JSONDecoder().decode(Response.self, from: data)
    guard decoded.code == "200", let now = decoded.now else {
      throw QingxuAmbientServiceError.server(qweatherMessage(decoded.code))
    }
    return QingxuWeatherSnapshot(
      cityName: preferences.cityName.trimmingCharacters(in: .whitespacesAndNewlines),
      temperature: now.temp,
      text: now.text,
      icon: now.icon,
      windDirection: now.windDir,
      humidity: now.humidity,
      updatedAt: .now
    )
  }

  private func normalizedHost(_ value: String) throws -> String {
    var text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    text = text.replacingOccurrences(of: "https://", with: "")
    text = text.replacingOccurrences(of: "http://", with: "")
    text = text.split(separator: "/").first.map(String.init) ?? ""
    guard !text.isEmpty, text.contains("."), !text.contains(" ") else {
      throw QingxuAmbientServiceError.invalidHost
    }
    return text
  }

  private func qweatherMessage(_ code: String) -> String {
    switch code {
    case "401": "和风天气 Key 无效或权限不足"
    case "402": "和风天气额度已用尽"
    case "404": "没有找到这个 Location ID"
    case "429": "天气请求过于频繁，请稍后再试"
    default: "和风天气返回错误（\(code)）"
    }
  }
}

struct QingxuQuoteClient {
  private struct Response: Decodable {
    let hitokoto: String
    let from: String
  }

  private let rejectedWords = ["死亡", "自杀", "绝望", "痛苦", "孤独", "悲伤", "遗憾"]

  func fetch() async throws -> QingxuQuoteSnapshot {
    guard let url = URL(string: "https://v1.hitokoto.cn/?encode=json") else {
      throw QingxuAmbientServiceError.invalidResponse
    }
    for _ in 0..<3 {
      let (data, response) = try await URLSession.shared.data(from: url)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw QingxuAmbientServiceError.server("每日一句暂时不可用")
      }
      let value = try JSONDecoder().decode(Response.self, from: data)
      let text = value.hitokoto.trimmingCharacters(in: .whitespacesAndNewlines)
      if !text.isEmpty, !rejectedWords.contains(where: text.contains) {
        return QingxuQuoteSnapshot(text: text, source: value.from, updatedAt: .now)
      }
    }
    return QingxuQuoteSnapshot(text: "向着光亮那方", source: "清序", updatedAt: .now)
  }
}

@MainActor
final class TodayAmbientStore: ObservableObject {
  @Published private(set) var weather: QingxuWeatherSnapshot?
  @Published private(set) var quote: QingxuQuoteSnapshot?
  @Published private(set) var isLoading = false
  @Published private(set) var message: String?

  private let weatherCacheKey = "qingxu.ambient.weather-cache.v1"
  private let quoteCacheKey = "qingxu.ambient.quote-cache.v1"

  init() {
    weather = cached(QingxuWeatherSnapshot.self, key: weatherCacheKey)
    quote = cached(QingxuQuoteSnapshot.self, key: quoteCacheKey)
  }

  func load(force: Bool = false) async {
    let preferences = QingxuAmbientPreferencesStore.load()
    isLoading = true
    message = nil
    defer { isLoading = false }

    if preferences.quoteEnabled, force || quoteNeedsRefresh {
      do {
        let value = try await QingxuQuoteClient().fetch()
        quote = value
        cache(value, key: quoteCacheKey)
      } catch {
        message = error.localizedDescription
      }
    } else if !preferences.quoteEnabled {
      quote = nil
    }

    if preferences.weatherConfigured, force || weatherNeedsRefresh {
      do {
        let value = try await QingxuWeatherClient().fetch(preferences: preferences)
        weather = value
        cache(value, key: weatherCacheKey)
      } catch {
        message = error.localizedDescription
      }
    } else if !preferences.weatherEnabled {
      weather = nil
    }
  }

  private var weatherNeedsRefresh: Bool {
    guard let weather else { return true }
    return Date().timeIntervalSince(weather.updatedAt) > 30 * 60
  }

  private var quoteNeedsRefresh: Bool {
    guard let quote else { return true }
    return !Calendar.autoupdatingCurrent.isDateInToday(quote.updatedAt)
  }

  private func cached<T: Decodable>(_ type: T.Type, key: String) -> T? {
    guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  private func cache<T: Encodable>(_ value: T, key: String) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    UserDefaults.standard.set(data, forKey: key)
  }
}
