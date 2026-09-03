import SwiftUI
import WidgetKit

private let suiteName = "group.one.darker.qingxu"

private struct MacWidgetWeather: Decodable {
  let cityName: String
  let temperature: String
  let text: String
  let humidity: String
}

private struct MacWidgetQuote: Decodable {
  let text: String
  let source: String
}

private struct QingxuWidgetEntry: TimelineEntry {
  let date: Date
  let taskCount: Int
  let taskTitles: [String]
  let mode: String
  let status: String
  let direction: String
  let remaining: Int
  let endsAt: Date?
  let startedAt: Date?
  let goal: Int
  let completed: Int
  let heatmap: [String: Int]
  let weather: MacWidgetWeather?
  let quote: MacWidgetQuote?
  let snapshotUpdatedAt: Date?
}

private struct QingxuWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> QingxuWidgetEntry { sample }

  func getSnapshot(in context: Context, completion: @escaping (QingxuWidgetEntry) -> Void) {
    completion(context.isPreview ? sample : load())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<QingxuWidgetEntry>) -> Void) {
    let entry = load()
    let interval: TimeInterval = entry.status == "running" ? 60 : 15 * 60
    completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(interval))))
  }

  private var sample: QingxuWidgetEntry {
    QingxuWidgetEntry(
      date: .now,
      taskCount: 3,
      taskTitles: ["完成今日计划", "整理阅读列表", "专注 25 分钟"],
      mode: "focus",
      status: "running",
      direction: "countdown",
      remaining: 21 * 60 + 18,
      endsAt: Date().addingTimeInterval(21 * 60 + 18),
      startedAt: nil,
      goal: 4,
      completed: 2,
      heatmap: [:],
      weather: MacWidgetWeather(cityName: "上海", temperature: "23", text: "晴", humidity: "52"),
      quote: MacWidgetQuote(text: "把今天真正重要的事做好。", source: "清序"),
      snapshotUpdatedAt: .now
    )
  }

  private func load() -> QingxuWidgetEntry {
    let defaults = UserDefaults(suiteName: suiteName)
    let heatmapData = defaults?.data(forKey: "focusHeatmap")
    let heatmap = heatmapData.flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
    return QingxuWidgetEntry(
      date: .now,
      taskCount: defaults?.integer(forKey: "todayTaskCount") ?? 0,
      taskTitles: defaults?.stringArray(forKey: "todayTaskTitles") ?? [],
      mode: defaults?.string(forKey: "pomodoroMode") ?? "focus",
      status: defaults?.string(forKey: "pomodoroStatus") ?? "idle",
      direction: defaults?.string(forKey: "pomodoroDirection") ?? "countdown",
      remaining: defaults?.integer(forKey: "pomodoroRemaining") ?? 25 * 60,
      endsAt: defaults?.object(forKey: "pomodoroEndsAt") as? Date,
      startedAt: defaults?.object(forKey: "pomodoroStartedAt") as? Date,
      goal: max(1, defaults?.integer(forKey: "dailyFocusGoal") ?? 4),
      completed: defaults?.integer(forKey: "dailyFocusCompleted") ?? 0,
      heatmap: heatmap,
      weather: decode(MacWidgetWeather.self, data: defaults?.data(forKey: "qingxu.ambient.weather-cache.v1")),
      quote: decode(MacWidgetQuote.self, data: defaults?.data(forKey: "qingxu.ambient.quote-cache.v1")),
      snapshotUpdatedAt: defaults?.object(forKey: "widgetSnapshotUpdatedAt") as? Date
    )
  }

  private func decode<T: Decodable>(_ type: T.Type, data: Data?) -> T? {
    guard let data else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }
}

private struct WidgetSurface<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    if #available(macOSApplicationExtension 26.0, *) {
      content()
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .containerBackground(Color.clear, for: .widget)
    } else if #available(macOSApplicationExtension 14.0, *) {
      content()
        .containerBackground(.fill.tertiary, for: .widget)
    } else {
      content()
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }
  }
}

private struct MacOverviewWidgetView: View {
  let entry: QingxuWidgetEntry

  var body: some View {
    WidgetSurface {
      HStack(spacing: 18) {
        VStack(alignment: .leading, spacing: 9) {
          Label("今天", systemImage: "calendar")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.blue)
          Text("\(entry.taskCount)")
            .font(.system(size: 40, weight: .semibold, design: .rounded))
            .monospacedDigit()
          Text(entry.taskTitles.first ?? (entry.taskCount == 0 ? "今天已清空" : "项待办"))
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Divider()

        VStack(alignment: .leading, spacing: 9) {
          HStack {
            Label(modeTitle, systemImage: "timer")
              .font(.caption.weight(.semibold))
            Spacer()
            Text("\(entry.completed)/\(entry.goal)")
              .font(.caption2.weight(.semibold).monospacedDigit())
              .foregroundStyle(.secondary)
          }
          timerText
            .font(.system(size: 30, weight: .medium, design: .rounded).monospacedDigit())
            .lineLimit(1)
          Text(entry.status == "running" ? "正在同步计时" : "准备下一次专注")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(16)
    }
    .widgetURL(URL(string: "qingxu://today"))
  }

  private var modeTitle: String {
    switch entry.mode {
    case "shortBreak": return "短暂休息"
    case "longBreak": return "长休息"
    default: return "专注"
    }
  }

  @ViewBuilder
  private var timerText: some View {
    if entry.status == "running", entry.direction == "countdown", let endsAt = entry.endsAt {
      Text(timerInterval: entry.date...endsAt, countsDown: true)
    } else if entry.status == "running", entry.direction == "countUp", let startedAt = entry.startedAt {
      Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
    } else {
      Text(String(format: "%02d:%02d", max(0, entry.remaining) / 60, max(0, entry.remaining) % 60))
    }
  }
}

private struct MacAmbientWidgetView: View {
  let entry: QingxuWidgetEntry

  var body: some View {
    WidgetSurface {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text(entry.weather.map { "\($0.temperature)°" } ?? "--°")
            .font(.system(size: 34, weight: .medium, design: .rounded))
          VStack(alignment: .leading, spacing: 1) {
            Text(entry.weather?.text ?? "天气待刷新").font(.caption.weight(.semibold))
            Text(entry.weather?.cityName ?? "打开清序刷新")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: "quote.opening").foregroundStyle(.blue)
        }
        Spacer(minLength: 0)
        Text(entry.quote?.text ?? "把今天真正重要的事做好。")
          .font(.subheadline.weight(.medium))
          .lineLimit(2)
        Text(entry.quote.map { "— \($0.source)" } ?? "— 清序")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .padding(16)
    }
    .widgetURL(URL(string: "qingxu://today"))
  }
}

private struct TodayTasksWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: QingxuWidgetEntry

  var body: some View {
    WidgetSurface {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Label("今日任务", systemImage: "checkmark.circle")
            .font(.headline)
          Spacer()
          Text("\(entry.taskCount)")
            .font(.title3.weight(.semibold))
            .monospacedDigit()
        }

        if entry.taskTitles.isEmpty {
          Spacer()
          Text("今天没有待办")
            .foregroundStyle(.secondary)
          Spacer()
        } else {
          ForEach(Array(entry.taskTitles.prefix(family == .systemSmall ? 2 : 3).enumerated()), id: \.offset) { _, title in
            HStack(spacing: 8) {
              Circle()
                .strokeBorder(.secondary, lineWidth: 1.2)
                .frame(width: 12, height: 12)
              Text(title)
                .lineLimit(1)
            }
            .font(.subheadline)
          }
          Spacer(minLength: 0)
        }
      }
      .padding(16)
    }
    .widgetURL(URL(string: "qingxu://today"))
  }
}

private struct FocusTimerWidgetView: View {
  let entry: QingxuWidgetEntry

  private var modeTitle: String {
    switch entry.mode {
    case "shortBreak": "短休息"
    case "longBreak": "长休息"
    default: entry.direction == "countUp" ? "正计时" : "专注"
    }
  }

  var body: some View {
    WidgetSurface {
      VStack(alignment: .leading, spacing: 12) {
        Label(modeTitle, systemImage: "timer")
          .font(.headline)
        Spacer()
        timerText
          .font(.system(size: 31, weight: .medium, design: .rounded))
          .monospacedDigit()
          .minimumScaleFactor(0.7)
        Text(entry.status == "running" ? "进行中" : entry.status == "paused" ? "已暂停" : "准备开始")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(16)
    }
    .widgetURL(URL(string: "qingxu://pomodoro"))
  }

  @ViewBuilder
  private var timerText: some View {
    if entry.status == "running", entry.direction == "countdown", let endsAt = entry.endsAt {
      Text(timerInterval: entry.date...endsAt, countsDown: true)
    } else if entry.status == "running", entry.direction == "countUp", let startedAt = entry.startedAt {
      Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
    } else {
      Text(format(entry.remaining))
    }
  }

  private func format(_ seconds: Int) -> String {
    let safe = max(0, seconds)
    return String(format: "%02d:%02d", safe / 60, safe % 60)
  }
}

private struct DailyGoalWidgetView: View {
  let entry: QingxuWidgetEntry

  private var progress: Double {
    min(1, Double(entry.completed) / Double(max(1, entry.goal)))
  }

  var body: some View {
    WidgetSurface {
      VStack(alignment: .leading, spacing: 12) {
        Label("今日目标", systemImage: "scope")
          .font(.headline)
        Spacer()
        ZStack {
          Circle().stroke(.secondary.opacity(0.18), lineWidth: 8)
          Circle()
            .trim(from: 0, to: progress)
            .stroke(.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
            .rotationEffect(.degrees(-90))
          VStack(spacing: 0) {
            Text("\(entry.completed)")
              .font(.title.weight(.semibold))
            Text("/ \(entry.goal)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity)
        Spacer()
      }
      .padding(16)
    }
    .widgetURL(URL(string: "qingxu://pomodoro"))
  }
}

private struct FocusHeatmapWidgetView: View {
  let entry: QingxuWidgetEntry

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

  var body: some View {
    WidgetSurface {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label("专注热力图", systemImage: "square.grid.3x3.fill")
            .font(.headline)
          Spacer()
          Text("最近 5 周")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        LazyVGrid(columns: columns, spacing: 4) {
          ForEach(days, id: \.self) { day in
            RoundedRectangle(cornerRadius: 3, style: .continuous)
              .fill(shade(for: seconds(on: day)))
              .aspectRatio(1, contentMode: .fit)
              .help(day.formatted(date: .abbreviated, time: .omitted))
          }
        }
        HStack(spacing: 5) {
          Text("少")
          ForEach(0..<4, id: \.self) { level in
            RoundedRectangle(cornerRadius: 2)
              .fill(shade(for: level * 30 * 60))
              .frame(width: 12, height: 12)
          }
          Text("多")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
      .padding(16)
    }
    .widgetURL(URL(string: "qingxu://pomodoro"))
  }

  private var days: [Date] {
    let calendar = Calendar.autoupdatingCurrent
    let today = calendar.startOfDay(for: entry.date)
    return (0..<35).compactMap { calendar.date(byAdding: .day, value: $0 - 34, to: today) }
  }

  private func seconds(on date: Date) -> Int {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return entry.heatmap[formatter.string(from: date)] ?? 0
  }

  private func shade(for seconds: Int) -> Color {
    switch seconds {
    case 1..<(25 * 60): .primary.opacity(0.22)
    case (25 * 60)..<(60 * 60): .primary.opacity(0.42)
    case (60 * 60)..<(120 * 60): .primary.opacity(0.66)
    case (120 * 60)...: .primary.opacity(0.9)
    default: .secondary.opacity(0.1)
    }
  }
}

struct MacTodayTasksWidget: Widget {
  let kind = "QingxuMacTodayTasks"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QingxuWidgetProvider()) { entry in
      TodayTasksWidgetView(entry: entry)
    }
    .configurationDisplayName("今日任务")
    .description("在桌面查看今天最重要的任务。")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

struct MacFocusTimerWidget: Widget {
  let kind = "QingxuMacFocusTimer"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QingxuWidgetProvider()) { entry in
      FocusTimerWidgetView(entry: entry)
    }
    .configurationDisplayName("番茄计时")
    .description("查看当前番茄钟或正计时状态。")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct MacDailyGoalWidget: Widget {
  let kind = "QingxuMacDailyGoal"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QingxuWidgetProvider()) { entry in
      DailyGoalWidgetView(entry: entry)
    }
    .configurationDisplayName("今日专注目标")
    .description("查看今天完成了多少次专注。")
    .supportedFamilies([.systemSmall])
  }
}

struct MacFocusHeatmapWidget: Widget {
  let kind = "QingxuMacFocusHeatmap"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QingxuWidgetProvider()) { entry in
      FocusHeatmapWidgetView(entry: entry)
    }
    .configurationDisplayName("专注热力图")
    .description("以 GitHub 风格热力图查看最近五周的专注节奏。")
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}

struct MacOverviewWidget: Widget {
  let kind = "QingxuMacOverview"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QingxuWidgetProvider()) { entry in
      MacOverviewWidgetView(entry: entry)
    }
    .configurationDisplayName("今日总览")
    .description("同时查看任务、实时计时与今日专注目标。")
    .supportedFamilies([.systemMedium])
  }
}

struct MacAmbientWidget: Widget {
  let kind = "QingxuMacAmbient"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QingxuWidgetProvider()) { entry in
      MacAmbientWidgetView(entry: entry)
    }
    .configurationDisplayName("天气与一言")
    .description("在桌面安静地查看天气与每日一句。")
    .supportedFamilies([.systemMedium])
  }
}

@main
struct QingxumacOSWidgetBundle: WidgetBundle {
  var body: some Widget {
    MacTodayTasksWidget()
    MacFocusTimerWidget()
    MacDailyGoalWidget()
    MacFocusHeatmapWidget()
    MacOverviewWidget()
    MacAmbientWidget()
  }
}
