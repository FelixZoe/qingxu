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
    case .unavailable: "请先在设置中完成 AI 助手配置。"
    case .invalidResponse: "AI 返回的内容无法识别。"
    case .server(let message): message
    }
  }
}

struct QingxuAIClient {
  func summarize(
    title: String,
    content: String,
    settings: SyncSettings,
    aiSettings: AISettings
  ) async throws -> String {
    let body = AIRequest(
      mode: "rss_summary",
      title: title,
      content: content,
      goal: nil,
      tasks: nil,
      prompt: aiSettings.summaryPrompt
    )
    return try await perform(body, settings: settings, aiSettings: aiSettings).text
  }

  func plan(
    goal: String,
    tasks: [TaskItem],
    settings: SyncSettings,
    aiSettings: AISettings
  ) async throws -> QingxuAITaskPlan {
    let inputs = tasks.prefix(200).map {
      AITaskInput(title: $0.title, scheduledAt: $0.startAt?.ISO8601Format())
    }
    let body = AIRequest(
      mode: "task_plan",
      title: nil,
      content: nil,
      goal: goal,
      tasks: inputs,
      prompt: nil
    )
    let raw = try await perform(body, settings: settings, aiSettings: aiSettings).text
      .replacingOccurrences(of: "```json", with: "")
      .replacingOccurrences(of: "```", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = raw.data(using: .utf8),
          let plan = try? JSONDecoder().decode(QingxuAITaskPlan.self, from: data)
    else { throw QingxuAIError.invalidResponse }
    return plan
  }

  func test(settings: SyncSettings, aiSettings: AISettings) async throws {
    guard aiSettings.validationMessage(syncSettings: settings) == nil else {
      throw QingxuAIError.unavailable
    }
    let body = AIRequest(
      mode: "rss_summary",
      title: "连接测试",
      content: "请只回复：连接成功",
      goal: nil,
      tasks: nil,
      prompt: nil
    )
    let response = try await perform(body, settings: settings, aiSettings: aiSettings)
    guard !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw QingxuAIError.invalidResponse
    }
  }

  private func perform(
    _ body: AIRequest,
    settings: SyncSettings,
    aiSettings: AISettings
  ) async throws -> AIResponse {
    guard aiSettings.validationMessage(syncSettings: settings) == nil else {
      throw QingxuAIError.unavailable
    }
    switch aiSettings.mode {
    case .selfHosted:
      return try await performSelfHosted(body, settings: settings)
    case .openAI, .deepSeek, .compatible:
      return try await performCompatible(body, settings: aiSettings)
    }
  }

  private func performSelfHosted(_ body: AIRequest, settings: SyncSettings) async throws -> AIResponse {
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
      throw QingxuAIError.server(serverMessage(from: data))
    }
    guard let result = try? JSONDecoder().decode(AIResponse.self, from: data) else {
      throw QingxuAIError.invalidResponse
    }
    return result
  }

  private func performCompatible(_ body: AIRequest, settings: AISettings) async throws -> AIResponse {
    guard let url = URL(string: settings.normalizedBaseURL) else {
      throw QingxuAIError.unavailable
    }
    let payload = ChatCompletionRequest(
      model: settings.model.trimmingCharacters(in: .whitespacesAndNewlines),
      messages: [
        ChatMessage(role: "system", content: body.systemPrompt),
        ChatMessage(role: "user", content: body.userPrompt),
      ],
      temperature: 0.2
    )
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(
      "Bearer \(settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))",
      forHTTPHeaderField: "Authorization"
    )
    request.httpBody = try JSONEncoder().encode(payload)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw QingxuAIError.invalidResponse }
    guard 200..<300 ~= http.statusCode else {
      throw QingxuAIError.server(serverMessage(from: data))
    }
    guard let result = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
          let content = result.choices.first?.message.content,
          !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw QingxuAIError.invalidResponse }
    return AIResponse(text: content)
  }

  private func serverMessage(from data: Data) -> String {
    if let envelope = try? JSONDecoder().decode(ChatErrorEnvelope.self, from: data),
       !envelope.error.message.isEmpty {
      return String(envelope.error.message.prefix(180))
    }
    return String((String(data: data, encoding: .utf8) ?? "AI 请求失败").prefix(180))
  }
}

private struct AIRequest: Encodable {
  var mode: String
  var title: String?
  var content: String?
  var goal: String?
  var tasks: [AITaskInput]?
  var prompt: String?

  var systemPrompt: String {
    switch mode {
    case "task_plan":
      return "你是简洁的中文任务规划助手。只输出合法 JSON，不要 Markdown。"
    default:
      return "你是简洁准确的中文阅读助手。保留关键事实，不要套话。"
    }
  }

  var userPrompt: String {
    switch mode {
    case "task_plan":
      let existing = (tasks ?? []).map { task in
        task.scheduledAt.map { "- \(task.title)（\($0)）" } ?? "- \(task.title)"
      }.joined(separator: "\n")
      return """
      目标：\(goal ?? "整理近期任务")
      现有任务：
      \(existing.isEmpty ? "无" : existing)

      请给出可执行安排，严格返回：
      {"summary":"一句话建议","suggestions":[{"title":"任务名","dayOffset":0}]}
      dayOffset 从今天起计算，控制在 0 到 30，最多 8 项。
      """
    default:
      let instruction = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
      let summaryInstruction = instruction?.isEmpty == false
        ? instruction!
        : "请用三段输出：一句话结论；3 个关键点；值得采取的一个行动。总计不超过 260 个汉字。"
      return """
      标题：\(title ?? "")
      正文：
      \(String((content ?? "").prefix(18_000)))

      摘要要求：\(summaryInstruction)
      """
    }
  }
}

private struct AITaskInput: Encodable {
  var title: String
  var scheduledAt: String?
}

private struct AIResponse: Decodable {
  var text: String
}

private struct ChatCompletionRequest: Encodable {
  var model: String
  var messages: [ChatMessage]
  var temperature: Double
}

private struct ChatMessage: Codable {
  var role: String
  var content: String
}

private struct ChatCompletionResponse: Decodable {
  struct Choice: Decodable { var message: ChatMessage }
  var choices: [Choice]
}

private struct ChatErrorEnvelope: Decodable {
  struct APIError: Decodable { var message: String }
  var error: APIError
}
