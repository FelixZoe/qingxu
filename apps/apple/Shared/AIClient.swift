import Foundation

struct QingxuAISuggestion: Codable, Identifiable, Hashable {
  var title: String
  var dayOffset: Int
  var id: String { "\(title)-\(dayOffset)" }
}

struct QingxuAITaskPlan: Codable, Hashable {
  var summary: String
  var suggestions: [QingxuAISuggestion]
}

enum QingxuAIError: LocalizedError {
  case unavailable
  case invalidResponse
  case server(String)

  var errorDescription: String? {
    switch self {
    case .unavailable: "请先配置同步服务器，并在服务器设置 AI_API_KEY。"
    case .invalidResponse: "AI 返回的内容无法识别。"
    case .server(let message): message
    }
  }
}

struct QingxuAIClient {
  func summarize(title: String, content: String, settings: SyncSettings) async throws -> String {
    let body = AIRequest(mode: "rss_summary", title: title, content: content, goal: nil, tasks: nil)
    return try await perform(body, settings: settings).text
  }

  func plan(
    goal: String,
    tasks: [TaskItem],
    settings: SyncSettings
  ) async throws -> QingxuAITaskPlan {
    let inputs = tasks.prefix(200).map {
      AITaskInput(title: $0.title, scheduledAt: $0.startAt?.ISO8601Format())
    }
    let body = AIRequest(mode: "task_plan", title: nil, content: nil, goal: goal, tasks: inputs)
    let raw = try await perform(body, settings: settings).text
      .replacingOccurrences(of: "```json", with: "")
      .replacingOccurrences(of: "```", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = raw.data(using: .utf8),
          let plan = try? JSONDecoder().decode(QingxuAITaskPlan.self, from: data)
    else { throw QingxuAIError.invalidResponse }
    return plan
  }

  private func perform(_ body: AIRequest, settings: SyncSettings) async throws -> AIResponse {
    guard settings.isConfigured,
          var components = URLComponents(string: settings.normalizedServerURL)
    else { throw QingxuAIError.unavailable }
    components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    components.path = "/" + [components.path, "/v1/ai"].map {
      $0.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }.filter { !$0.isEmpty }.joined(separator: "/")
    guard let url = components.url else { throw QingxuAIError.unavailable }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(settings.token)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw QingxuAIError.invalidResponse }
    guard 200..<300 ~= http.statusCode else {
      if http.statusCode == 503 { throw QingxuAIError.unavailable }
      let message = String(data: data, encoding: .utf8) ?? "AI 请求失败"
      throw QingxuAIError.server(String(message.prefix(180)))
    }
    guard let result = try? JSONDecoder().decode(AIResponse.self, from: data) else {
      throw QingxuAIError.invalidResponse
    }
    return result
  }
}

private struct AIRequest: Encodable {
  var mode: String
  var title: String?
  var content: String?
  var goal: String?
  var tasks: [AITaskInput]?
}

private struct AITaskInput: Encodable {
  var title: String
  var scheduledAt: String?
}

private struct AIResponse: Decodable {
  var text: String
}
