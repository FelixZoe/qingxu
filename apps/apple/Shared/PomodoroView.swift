import SwiftUI

private enum PomodoroSheet: String, Identifiable {
  case durations
  case task
  case statistics

  var id: String { rawValue }
}

struct PomodoroScreen: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.openURL) private var openURL
  @State private var presentedSheet: PomodoroSheet?
  @State private var selectedTaskID: String?
  @AppStorage(QingxuPreferenceKey.completionSound) private var completionSoundEnabled = false

  private var selectedTask: TaskItem? {
    store.todayTasks.first { $0.id == selectedTaskID }
  }

  private var progress: Double {
    let total = max(1, store.pomodoro.duration(for: store.pomodoro.mode))
    if store.pomodoro.timerDirection == .countUp {
      return min(1, Double(store.displayedRemainingSeconds) / Double(total))
    }
    return 1 - Double(store.displayedRemainingSeconds) / Double(total)
  }

  var body: some View {
    NavigationStack {
      GeometryReader { proxy in
        VStack(spacing: 0) {
        #if os(macOS)
        Picker("计时方向", selection: Binding(
          get: { store.pomodoro.timerDirection },
          set: store.setPomodoroTimerDirection
        )) {
          ForEach(PomodoroTimerDirection.allCases) { direction in
            Text(direction.title).tag(direction)
          }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 430)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        #endif

        Spacer(minLength: 24)

        Button { presentedSheet = .task } label: {
          HStack(spacing: 8) {
            Text(timerTitle)
              .font(.headline)
              .lineLimit(1)
            Image(systemName: "chevron.right")
              .font(.caption.weight(.semibold))
              .foregroundStyle(QingxuPalette.quiet)
          }
          .foregroundStyle(QingxuPalette.ink)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 28)

        ZStack {
          Circle()
            .stroke(QingxuPalette.separator.opacity(0.72), lineWidth: 6)
          Circle()
            .trim(from: 0, to: min(1, max(0, progress)))
            .stroke(
              QingxuPalette.actionGradient,
              style: StrokeStyle(lineWidth: 6, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .animation(.linear(duration: 0.25), value: progress)
          Text(format(store.displayedRemainingSeconds))
            .font(.system(size: 58, weight: .light, design: .rounded).monospacedDigit())
          if store.pomodoro.status == .paused {
            Text("已暂停")
              .font(.subheadline)
              .foregroundStyle(QingxuPalette.quiet)
              .offset(y: 48)
          }
        }
        .frame(
          width: min(304, max(264, proxy.size.width - 88)),
          height: min(304, max(264, proxy.size.width - 88))
        )
        .accessibilityElement(children: .combine)

        Color.clear.frame(height: 34)

        #if os(iOS)
        if store.pomodoro.status == .idle {
          Button(action: store.togglePomodoro) {
            Text("开始")
              .font(.headline)
              .frame(width: 148, height: 54)
              .foregroundStyle(QingxuPalette.onAccent)
              .background(QingxuPalette.actionGradient, in: Capsule())
          }
          .buttonStyle(.plain)
        } else {
          HStack(spacing: 42) {
            Button { completionSoundEnabled.toggle() } label: {
              Image(systemName: completionSoundEnabled ? "speaker.wave.2" : "speaker.slash")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(QingxuPalette.quiet)
                .frame(width: 52, height: 52)
                .background(QingxuPalette.surface, in: Circle())
                .overlay(Circle().stroke(QingxuPalette.separator, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(completionSoundEnabled ? "关闭结束提示音" : "开启结束提示音")

            Button(action: store.togglePomodoro) {
              Image(systemName: store.pomodoro.status == .running ? "pause.fill" : "play.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(QingxuPalette.onAccent)
                .frame(width: 72, height: 72)
                .background(QingxuPalette.actionGradient, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.pomodoro.status == .running ? "暂停" : "继续")

            Button(action: store.stopPomodoro) {
              Image(systemName: "stop.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(QingxuPalette.quiet)
                .frame(width: 52, height: 52)
                .background(QingxuPalette.surface, in: Circle())
                .overlay(Circle().stroke(QingxuPalette.separator, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("停止并记录")
          }
        }
        #else
        HStack(spacing: 16) {
          Button(action: store.resetPomodoro) {
            Image(systemName: "arrow.counterclockwise")
              .frame(width: 48, height: 48)
              .background(QingxuPalette.surface, in: Circle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("重置")

          Button(action: store.togglePomodoro) {
            Text(store.pomodoro.status == .running ? "暂停" : "开始")
              .font(.headline)
              .frame(width: 148, height: 52)
              .foregroundStyle(QingxuPalette.onAccent)
              .background(QingxuPalette.actionGradient, in: Capsule())
          }
          .buttonStyle(.plain)

          Button { presentedSheet = .task } label: {
            Image(systemName: selectedTask == nil ? "checklist" : "checkmark.circle.fill")
              .frame(width: 48, height: 48)
              .background(QingxuPalette.surface, in: Circle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("选择专注任务")
        }
        #endif

        Spacer(minLength: 24)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(QingxuPalette.canvasGradient.ignoresSafeArea())
      .tint(QingxuPalette.accent)
      #if os(iOS)
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      #else
      .navigationTitle("番茄钟")
      #endif
      .toolbar {
        #if os(iOS)
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            if store.pomodoro.status == .idle {
              presentedSheet = .statistics
            } else {
              openURL(URL(string: "qingxu://today")!)
            }
          } label: {
            Image(systemName: store.pomodoro.status == .idle ? "clock.arrow.circlepath" : "chevron.down")
              .font(.system(size: 17, weight: .medium))
              .frame(width: 34, height: 34)
          }
          .accessibilityLabel(store.pomodoro.status == .idle ? "专注统计" : "收起计时")
        }
        ToolbarItem(placement: .principal) {
          if store.pomodoro.status == .idle {
            Picker("计时方向", selection: Binding(
              get: { store.pomodoro.timerDirection },
              set: store.setPomodoroTimerDirection
            )) {
              ForEach(PomodoroTimerDirection.allCases) { direction in
                Text(direction.title).tag(direction)
              }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 156)
          }
        }
        #endif
        ToolbarItem(placement: .primaryAction) {
          Menu {
            Button {
              presentedSheet = .task
            } label: {
              Label("选择任务", systemImage: "checklist")
            }
            Button {
              presentedSheet = .durations
            } label: {
              Label("自定义时长", systemImage: "slider.horizontal.3")
            }
            Divider()
            Button(role: .destructive) {
              store.resetPomodoro()
            } label: {
              Label("重置计时", systemImage: "arrow.counterclockwise")
            }
          } label: {
            Image(systemName: "ellipsis")
              .frame(width: 34, height: 34)
          }
          .accessibilityLabel("番茄钟菜单")
        }
      }
      .sheet(item: $presentedSheet) { sheet in
        switch sheet {
        case .durations:
          DurationSettingsSheet()
            .environmentObject(store)
            .presentationDetents([.medium])
        case .task:
          PomodoroTaskPicker(selection: $selectedTaskID)
            .environmentObject(store)
            .presentationDetents([.medium])
        case .statistics:
          FocusStatisticsSheet()
            .environmentObject(store)
            .presentationDetents([.large])
        }
      }
    }
  }

  private func format(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }

  private var timerTitle: String {
    if store.pomodoro.mode != .focus { return store.pomodoro.mode.title }
    return selectedTask?.title ?? (store.pomodoro.timerDirection == .countUp ? "自由专注" : "专注")
  }
}

private enum FocusStatisticsRange: String, CaseIterable, Identifiable {
  case week
  case month
  case year

  var id: String { rawValue }
  var title: String {
    switch self {
    case .week: "周"
    case .month: "月"
    case .year: "年"
    }
  }
}

private struct FocusStatisticsSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @State private var range: FocusStatisticsRange = .week

  private let calendar = Calendar.autoupdatingCurrent

  private var records: [FocusSessionRecord] {
    store.pomodoro.focusHistory.sorted { $0.endedAt > $1.endedAt }
  }

  private var todayRecords: [FocusSessionRecord] {
    records.filter { calendar.isDateInToday($0.endedAt) }
  }

  private var todaySeconds: Int { todayRecords.reduce(0) { $0 + $1.durationSeconds } }
  private var totalSeconds: Int { records.reduce(0) { $0 + $1.durationSeconds } }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 16) {
          summaryGrid
          recentRecords
          trendSection
          heatmapSection
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
      }
      .qingxuScreen()
      .navigationTitle("专注统计")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button { dismiss() } label: { Image(systemName: "xmark") }
            .accessibilityLabel("关闭")
        }
        ToolbarItem(placement: .primaryAction) {
          ShareLink(item: shareSummary) {
            Image(systemName: "square.and.arrow.up")
          }
          .accessibilityLabel("分享统计")
        }
      }
    }
  }

  private var summaryGrid: some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
      FocusMetricCard(
        title: "今日番茄",
        value: "\(todayRecords.filter(\.completed).count)/\(store.pomodoro.dailyFocusGoal)"
      )
      FocusMetricCard(title: "今日专注时长", value: durationText(todaySeconds))
      FocusMetricCard(title: "总番茄", value: "\(records.count)")
      FocusMetricCard(title: "总专注时长", value: durationText(totalSeconds))
    }
    .padding(.top, 10)
  }

  private var recentRecords: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("专注记录").font(QingxuType.sectionTitle)
        Spacer()
        Text("最近 \(min(records.count, 6)) 次")
          .font(QingxuType.metadata)
          .foregroundStyle(QingxuPalette.quiet)
      }
      if records.isEmpty {
        FocusEmptyStat(message: "完成一次专注后，这里会留下记录")
      } else {
        ForEach(Array(records.prefix(6))) { record in
          HStack(spacing: 12) {
            Image(systemName: record.completed ? "checkmark.circle.fill" : "circle.lefthalf.filled")
              .foregroundStyle(QingxuPalette.ink)
            VStack(alignment: .leading, spacing: 3) {
              Text(record.endedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline.weight(.medium))
              Text(record.startedAt.formatted(date: .omitted, time: .shortened) + " – " + record.endedAt.formatted(date: .omitted, time: .shortened))
                .font(QingxuType.metadata)
                .foregroundStyle(QingxuPalette.quiet)
            }
            Spacer()
            Text(durationText(record.durationSeconds))
              .font(.subheadline.monospacedDigit())
              .foregroundStyle(QingxuPalette.quiet)
          }
        }
      }
    }
    .focusStatCard()
  }

  private var trendSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("专注趋势").font(QingxuType.sectionTitle)
      Picker("统计范围", selection: $range) {
        ForEach(FocusStatisticsRange.allCases) { item in
          Text(item.title).tag(item)
        }
      }
      .pickerStyle(.segmented)

      if records.isEmpty {
        FocusEmptyStat(message: "暂无趋势数据")
      } else {
        FocusBarChart(values: trendValues)
          .frame(height: 170)
      }
    }
    .focusStatCard()
  }

  private var heatmapSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("年度专注").font(QingxuType.sectionTitle)
        Spacer()
        Text("过去 52 周")
          .font(QingxuType.metadata)
          .foregroundStyle(QingxuPalette.quiet)
      }
      if records.isEmpty {
        FocusEmptyStat(message: "暂无年度数据")
      } else {
        FocusHeatmap(records: records)
        HStack(spacing: 5) {
          Text("少")
          ForEach(0..<5, id: \.self) { level in
            RoundedRectangle(cornerRadius: 2)
              .fill(FocusHeatmap.legendColor(level: level))
              .frame(width: 11, height: 11)
          }
          Text("多")
        }
        .font(.caption2)
        .foregroundStyle(QingxuPalette.quiet)
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
    .focusStatCard()
  }

  private var trendValues: [Double] {
    let now = Date()
    let dayCount: Int
    switch range {
    case .week: dayCount = 7
    case .month: dayCount = 30
    case .year: dayCount = 365
    }
    if range == .year {
      return (0..<12).map { offset in
        guard let month = calendar.date(byAdding: .month, value: offset - 11, to: now),
              let interval = calendar.dateInterval(of: .month, for: month) else { return 0 }
        return Double(records.filter { interval.contains($0.endedAt) }.reduce(0) { $0 + $1.durationSeconds })
      }
    }
    return (0..<dayCount).map { offset in
      guard let date = calendar.date(byAdding: .day, value: offset - dayCount + 1, to: now) else { return 0 }
      return Double(records.filter { calendar.isDate($0.endedAt, inSameDayAs: date) }.reduce(0) { $0 + $1.durationSeconds })
    }
  }

  private var shareSummary: String {
    "清序专注统计：今天完成 \(todayRecords.count) 次，专注 \(durationText(todaySeconds))；累计专注 \(durationText(totalSeconds))。"
  }

  private func durationText(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    if hours > 0 { return "\(hours)时\(minutes)分" }
    if minutes > 0 { return "\(minutes)分" }
    return "\(seconds)秒"
  }
}

private struct FocusMetricCard: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(title)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(QingxuPalette.quiet)
      Text(value)
        .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(QingxuPalette.ink)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .focusStatCard()
  }
}

private struct FocusEmptyStat: View {
  let message: String
  var body: some View {
    Text(message)
      .font(.subheadline)
      .foregroundStyle(QingxuPalette.quiet)
      .frame(maxWidth: .infinity, minHeight: 72)
  }
}

private struct FocusBarChart: View {
  let values: [Double]

  var body: some View {
    GeometryReader { proxy in
      let peak = max(values.max() ?? 0, 1)
      HStack(alignment: .bottom, spacing: values.count > 40 ? 2 : 7) {
        ForEach(Array(values.enumerated()), id: \.offset) { _, value in
          Capsule()
            .fill(value > 0 ? QingxuPalette.ink : QingxuPalette.separator.opacity(0.5))
            .frame(height: max(4, proxy.size.height * value / peak))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
    .accessibilityLabel("专注时长趋势")
  }
}

private struct FocusHeatmap: View {
  let records: [FocusSessionRecord]
  private let calendar = Calendar.autoupdatingCurrent

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 4) {
        ForEach(0..<52, id: \.self) { weekOffset in
          VStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { dayOffset in
              RoundedRectangle(cornerRadius: 2)
                .fill(color(for: date(weekOffset: weekOffset, dayOffset: dayOffset)))
                .frame(width: 12, height: 12)
            }
          }
        }
      }
    }
    .accessibilityLabel("过去一年的专注热力图")
  }

  private func date(weekOffset: Int, dayOffset: Int) -> Date {
    let daysAgo = (51 - weekOffset) * 7 + (6 - dayOffset)
    return calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
  }

  private func color(for date: Date) -> Color {
    let seconds = records
      .filter { calendar.isDate($0.endedAt, inSameDayAs: date) }
      .reduce(0) { $0 + $1.durationSeconds }
    let level = switch seconds {
    case 1..<(25 * 60): 1
    case (25 * 60)..<(60 * 60): 2
    case (60 * 60)..<(120 * 60): 3
    case (120 * 60)...: 4
    default: 0
    }
    return Self.legendColor(level: level)
  }

  static func legendColor(level: Int) -> Color {
    switch level {
    case 1: QingxuPalette.faint.opacity(0.35)
    case 2: QingxuPalette.quiet.opacity(0.55)
    case 3: QingxuPalette.ink.opacity(0.72)
    case 4: QingxuPalette.ink
    default: QingxuPalette.separator.opacity(0.36)
    }
  }
}

private extension View {
  func focusStatCard() -> some View {
    self
      .padding(18)
      .background(QingxuPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
  }
}

private struct PomodoroTaskPicker: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @Binding var selection: String?

  var body: some View {
    NavigationStack {
      List {
        Button {
          selection = nil
          dismiss()
        } label: {
          HStack {
            Label("不关联任务", systemImage: "circle.dashed")
            Spacer()
            if selection == nil { Image(systemName: "checkmark") }
          }
        }
        .foregroundStyle(QingxuPalette.ink)

        ForEach(store.todayTasks) { task in
          Button {
            selection = task.id
            dismiss()
          } label: {
            HStack {
              Text(task.title).lineLimit(1)
              Spacer()
              if selection == task.id {
                Image(systemName: "checkmark").foregroundStyle(QingxuPalette.accent)
              }
            }
          }
          .foregroundStyle(QingxuPalette.ink)
        }
      }
      .qingxuScreen()
      .navigationTitle("选择任务")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("关闭") { dismiss() }
        }
      }
      .overlay {
        if store.todayTasks.isEmpty {
          VStack(spacing: 10) {
            Image(systemName: "checklist")
              .font(.system(size: 34, weight: .light))
            Text("今天没有任务")
              .font(.subheadline.weight(.medium))
          }
          .foregroundStyle(QingxuPalette.quiet)
            .allowsHitTesting(false)
        }
      }
    }
  }
}

private struct DurationSettingsSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @State private var focus: Int
  @State private var shortBreak: Int
  @State private var longBreak: Int
  @State private var longBreakEvery: Int
  @State private var dailyFocusGoal: Int

  init() {
    _focus = State(initialValue: 25)
    _shortBreak = State(initialValue: 5)
    _longBreak = State(initialValue: 15)
    _longBreakEvery = State(initialValue: 4)
    _dailyFocusGoal = State(initialValue: 4)
  }

  var body: some View {
    NavigationStack {
      Form {
        Stepper("专注：\(focus) 分钟", value: $focus, in: 1...180)
        Stepper("短休息：\(shortBreak) 分钟", value: $shortBreak, in: 1...60)
        Stepper("长休息：\(longBreak) 分钟", value: $longBreak, in: 1...120)
        Stepper("每 \(longBreakEvery) 次专注后长休息", value: $longBreakEvery, in: 2...12)
        Section("今日目标") {
          Stepper("完成 \(dailyFocusGoal) 个番茄", value: $dailyFocusGoal, in: 1...24)
          Text("目标和完成进度会同步到安卓，并显示在灵动岛与专注统计中。")
            .font(.footnote)
            .foregroundStyle(QingxuPalette.quiet)
        }
      }
      .qingxuScreen()
      .navigationTitle("自定义时长")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            store.updateDurations(
              focus: focus,
              shortBreak: shortBreak,
              longBreak: longBreak,
              longBreakEvery: longBreakEvery,
              dailyFocusGoal: dailyFocusGoal
            )
            dismiss()
          }
        }
      }
    }
    .frame(minWidth: 360, minHeight: 280)
    .onAppear {
      focus = store.pomodoro.focusMinutes
      shortBreak = store.pomodoro.shortBreakMinutes
      longBreak = store.pomodoro.longBreakMinutes
      longBreakEvery = store.pomodoro.longBreakEvery
      dailyFocusGoal = store.pomodoro.dailyFocusGoal
    }
  }
}
