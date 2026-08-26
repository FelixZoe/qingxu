import SwiftUI

private enum PomodoroSheet: String, Identifiable {
  case durations
  case task

  var id: String { rawValue }
}

struct PomodoroScreen: View {
  @EnvironmentObject private var store: AppStore
  @State private var presentedSheet: PomodoroSheet?
  @State private var selectedTaskID: String?

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

        Spacer(minLength: 64)

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
        .padding(.bottom, 44)

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
            .font(.system(size: 54, weight: .light, design: .rounded).monospacedDigit())
        }
        .frame(width: 268, height: 268)
        .accessibilityElement(children: .combine)

        Spacer(minLength: 48)

        #if os(iOS)
        Button(action: store.togglePomodoro) {
          Text(store.pomodoro.status == .running ? "暂停" : "开始")
            .font(.headline)
            .frame(width: 148, height: 52)
            .foregroundStyle(QingxuPalette.onAccent)
            .background(QingxuPalette.actionGradient, in: Capsule())
        }
        .buttonStyle(.plain)
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

        Spacer(minLength: 38)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(QingxuPalette.canvasGradient.ignoresSafeArea())
      .tint(QingxuPalette.accent)
      #if os(iOS)
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      #else
      .navigationTitle("番茄钟")
      #endif
      .toolbar {
        #if os(iOS)
        ToolbarItem(placement: .navigationBarLeading) {
          Button { presentedSheet = .durations } label: {
            Image(systemName: "clock")
              .font(.system(size: 18, weight: .medium))
              .frame(width: 40, height: 40)
          }
          .accessibilityLabel("自定义时长")
        }
        ToolbarItem(placement: .principal) {
          Picker("计时方向", selection: Binding(
            get: { store.pomodoro.timerDirection },
            set: store.setPomodoroTimerDirection
          )) {
            ForEach(PomodoroTimerDirection.allCases) { direction in
              Text(direction.title).tag(direction)
            }
          }
          .pickerStyle(.segmented)
          .frame(width: 210)
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
              .frame(width: 40, height: 40)
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

  init() {
    _focus = State(initialValue: 25)
    _shortBreak = State(initialValue: 5)
    _longBreak = State(initialValue: 15)
    _longBreakEvery = State(initialValue: 4)
  }

  var body: some View {
    NavigationStack {
      Form {
        Stepper("专注：\(focus) 分钟", value: $focus, in: 1...180)
        Stepper("短休息：\(shortBreak) 分钟", value: $shortBreak, in: 1...60)
        Stepper("长休息：\(longBreak) 分钟", value: $longBreak, in: 1...120)
        Stepper("每 \(longBreakEvery) 次专注后长休息", value: $longBreakEvery, in: 2...12)
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
              longBreakEvery: longBreakEvery
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
    }
  }
}
