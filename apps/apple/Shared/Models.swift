import Foundation

enum TaskStatus: String, Codable, CaseIterable {
  case open
  case completed
  case cancelled
}

enum TaskPriority: String, Codable, CaseIterable, Hashable, Identifiable {
  case high
  case medium
  case low

  var id: String { rawValue }

  var title: String {
    switch self {
    case .high: "高优先级"
    case .medium: "中优先级"
    case .low: "低优先级"
    }
  }

  var symbol: String { "flag.fill" }
}

struct TaskItem: Codable, Identifiable, Hashable {
  var id: String
  var title: String
  var notes: String
  var status: TaskStatus
  var projectId: String?
  var priority: TaskPriority? = nil
  var startAt: Date?
  var deadlineAt: Date?
  var completedAt: Date?
  var order: Int64
  var createdAt: Date
  var updatedAt: Date
  var deletedAt: Date?

  var isOpen: Bool { status == .open && deletedAt == nil }
}

enum PomodoroMode: String, Codable, CaseIterable {
  case focus
  case shortBreak
  case longBreak

  var title: String {
    switch self {
    case .focus: "专注"
    case .shortBreak: "短休息"
    case .longBreak: "长休息"
    }
  }
}

enum PomodoroStatus: String, Codable {
  case idle
  case running
  case paused
}

enum PomodoroTimerDirection: String, Codable, CaseIterable, Identifiable {
  case countdown
  case countUp

  var id: String { rawValue }
  var title: String { self == .countdown ? "番茄计时" : "正计时" }
}

struct FocusSessionRecord: Codable, Equatable, Identifiable {
  var id: String
  var startedAt: Date
  var endedAt: Date
  var durationSeconds: Int
  var completed: Bool

  init(
    id: String = UUID().uuidString,
    startedAt: Date,
    endedAt: Date,
    durationSeconds: Int,
    completed: Bool
  ) {
    self.id = id
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.durationSeconds = max(0, durationSeconds)
    self.completed = completed
  }
}

struct PomodoroState: Codable, Equatable {
  var mode: PomodoroMode
  var status: PomodoroStatus
  var remainingSeconds: Int
  var completedFocusSessions: Int
  var focusMinutes: Int
  var shortBreakMinutes: Int
  var longBreakMinutes: Int
  var longBreakEvery: Int
  var dailyFocusGoal: Int
  var phaseID: String
  var timerDirection: PomodoroTimerDirection
  var endsAt: Date?
  var startedAt: Date?
  var focusHistory: [FocusSessionRecord]
  var updatedAt: Date

  static func initial(now: Date = .distantPast) -> PomodoroState {
    PomodoroState(
      mode: .focus,
      status: .idle,
      remainingSeconds: 25 * 60,
      completedFocusSessions: 0,
      focusMinutes: 25,
      shortBreakMinutes: 5,
      longBreakMinutes: 15,
      longBreakEvery: 4,
      dailyFocusGoal: 4,
      phaseID: UUID().uuidString,
      timerDirection: .countdown,
      endsAt: nil,
      startedAt: nil,
      focusHistory: [],
      updatedAt: now
    )
  }

  func duration(for mode: PomodoroMode) -> Int {
    let minutes = switch mode {
    case .focus: focusMinutes
    case .shortBreak: shortBreakMinutes
    case .longBreak: longBreakMinutes
    }
    return minutes * 60
  }

  func remaining(at now: Date) -> Int {
    if timerDirection == .countUp {
      guard status == .running, let startedAt else { return max(0, remainingSeconds) }
      return max(0, remainingSeconds + Int(now.timeIntervalSince(startedAt)))
    }
    guard status == .running, let endsAt else { return remainingSeconds }
    return max(0, Int(ceil(endsAt.timeIntervalSince(now))))
  }

  func completedFocusCount(on date: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> Int {
    focusHistory.filter { $0.completed && calendar.isDate($0.endedAt, inSameDayAs: date) }.count
  }

  enum CodingKeys: String, CodingKey {
    case mode, status, remainingSeconds, completedFocusSessions
    case focusMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery
    case dailyFocusGoal, phaseID
    case timerDirection, endsAt, startedAt, focusHistory, updatedAt
  }

  init(
    mode: PomodoroMode,
    status: PomodoroStatus,
    remainingSeconds: Int,
    completedFocusSessions: Int,
    focusMinutes: Int,
    shortBreakMinutes: Int,
    longBreakMinutes: Int,
    longBreakEvery: Int = 4,
    dailyFocusGoal: Int = 4,
    phaseID: String = UUID().uuidString,
    timerDirection: PomodoroTimerDirection = .countdown,
    endsAt: Date?,
    startedAt: Date? = nil,
    focusHistory: [FocusSessionRecord] = [],
    updatedAt: Date
  ) {
    self.mode = mode
    self.status = status
    self.remainingSeconds = remainingSeconds
    self.completedFocusSessions = completedFocusSessions
    self.focusMinutes = focusMinutes
    self.shortBreakMinutes = shortBreakMinutes
    self.longBreakMinutes = longBreakMinutes
    self.longBreakEvery = longBreakEvery
    self.dailyFocusGoal = dailyFocusGoal
    self.phaseID = phaseID
    self.timerDirection = timerDirection
    self.endsAt = endsAt
    self.startedAt = startedAt
    self.focusHistory = focusHistory
    self.updatedAt = updatedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mode = try container.decodeIfPresent(PomodoroMode.self, forKey: .mode) ?? .focus
    status = try container.decodeIfPresent(PomodoroStatus.self, forKey: .status) ?? .idle
    completedFocusSessions = try container.decodeIfPresent(
      Int.self,
      forKey: .completedFocusSessions
    ) ?? 0
    focusMinutes = min(180, max(1, try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 25))
    shortBreakMinutes = min(
      60,
      max(1, try container.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? 5)
    )
    longBreakMinutes = min(
      120,
      max(1, try container.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? 15)
    )
    longBreakEvery = min(12, max(2, try container.decodeIfPresent(Int.self, forKey: .longBreakEvery) ?? 4))
    dailyFocusGoal = min(24, max(1, try container.decodeIfPresent(Int.self, forKey: .dailyFocusGoal) ?? 4))
    phaseID = try container.decodeIfPresent(String.self, forKey: .phaseID) ?? UUID().uuidString
    timerDirection = try container.decodeIfPresent(
      PomodoroTimerDirection.self,
      forKey: .timerDirection
    ) ?? .countdown
    endsAt = try container.decodeIfPresent(Date.self, forKey: .endsAt)
    startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
    focusHistory = try container.decodeIfPresent(
      [FocusSessionRecord].self,
      forKey: .focusHistory
    ) ?? []
    updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    let fallback = switch mode {
    case .focus: focusMinutes * 60
    case .shortBreak: shortBreakMinutes * 60
    case .longBreak: longBreakMinutes * 60
    }
    remainingSeconds = try container.decodeIfPresent(Int.self, forKey: .remainingSeconds) ?? fallback
  }
}

struct SyncSettings: Codable, Equatable {
  var serverURL = ""
  var token = ""
  var deviceName = ""
  var autoSync = false

  var normalizedServerURL: String {
    var value = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
    while value.hasSuffix("/") { value.removeLast() }
    if !value.contains("://") { value = "https://\(value)" }
    return value
  }

  var validationMessage: String? {
    guard let url = URL(string: normalizedServerURL), url.host != nil else {
      return "服务器地址格式不正确"
    }
    guard token.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else {
      return "同步密钥必须是 64 位十六进制字符"
    }
    guard !deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return "请填写设备名称"
    }
    return nil
  }

  var isConfigured: Bool { validationMessage == nil }

  enum CodingKeys: String, CodingKey {
    case serverURL = "serverUrl"
    case deviceName, autoSync
  }
}

enum AIConnectionMode: String, Codable, CaseIterable, Identifiable {
  case selfHosted
  case openAI
  case deepSeek
  case compatible

  var id: String { rawValue }

  var title: String {
    switch self {
    case .selfHosted: "清序自托管"
    case .openAI: "OpenAI"
    case .deepSeek: "DeepSeek"
    case .compatible: "自定义服务"
    }
  }

  var presetBaseURL: String? {
    switch self {
    case .openAI: "https://api.openai.com/v1/chat/completions"
    case .deepSeek: "https://api.deepseek.com/chat/completions"
    case .selfHosted, .compatible: nil
    }
  }

  var presetModel: String? {
    switch self {
    case .openAI: "gpt-4.1-mini"
    case .deepSeek: "deepseek-chat"
    case .selfHosted, .compatible: nil
    }
  }
}

struct AISettings: Codable, Equatable {
  var mode: AIConnectionMode = .selfHosted
  var baseURL = "https://api.openai.com/v1/chat/completions"
  var model = "gpt-4.1-mini"
  var summaryPrompt = ""
  var apiKey = ""

  var normalizedBaseURL: String {
    var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    while value.hasSuffix("/") { value.removeLast() }
    if !value.contains("://") { value = "https://\(value)" }
    if let url = URL(string: value), url.path.isEmpty || url.path == "/" {
      return value + "/v1/chat/completions"
    }
    if value.hasSuffix("/v1") { return value + "/chat/completions" }
    return value
  }

  func validationMessage(syncSettings: SyncSettings) -> String? {
    switch mode {
    case .selfHosted:
      return syncSettings.validationMessage == nil
        ? nil
        : "请先配置可用的自托管同步服务器"
    case .openAI, .deepSeek, .compatible:
      guard let url = URL(string: normalizedBaseURL), url.host != nil else {
        return "AI 接口地址格式不正确"
      }
      guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return "请填写模型名称"
      }
      guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return "请填写 API 密钥"
      }
      return nil
    }
  }

  func isConfigured(syncSettings: SyncSettings) -> Bool {
    validationMessage(syncSettings: syncSettings) == nil
  }

  enum CodingKeys: String, CodingKey {
    case mode, baseURL, model, summaryPrompt
  }
}

enum AppTab: String, CaseIterable, Identifiable, Hashable {
  case inbox
  case today
  case pomodoro
  case rss
  case settings

  var id: String { rawValue }

  var title: String {
    switch self {
    case .inbox: "收集箱"
    case .today: "今天"
    case .pomodoro: "番茄钟"
    case .rss: "RSS"
    case .settings: "设置"
    }
  }

  var symbol: String {
    switch self {
    case .inbox: "tray"
    case .today: "sun.horizon"
    case .pomodoro: "timer"
    case .rss: "dot.radiowaves.left.and.right"
    case .settings: "gearshape"
    }
  }
}

enum QingxuCoding {
  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(iso8601.string(from: date))
    }
    return encoder
  }()

  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      guard let date = iso8601.date(from: value) ?? ISO8601DateFormatter().date(from: value) else {
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Invalid ISO-8601 date: \(value)"
        )
      }
      return date
    }
    return decoder
  }()

  private static let iso8601: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}
