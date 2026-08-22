import SwiftUI

struct PomodoroScreen: View {
  @EnvironmentObject private var store: AppStore
  @State private var showingDurations = false

  private var progress: Double {
    let total = max(1, store.pomodoro.duration(for: store.pomodoro.mode))
    return 1 - Double(store.displayedRemainingSeconds) / Double(total)
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Picker("计时模式", selection: Binding(
          get: { store.pomodoro.mode },
          set: store.setPomodoroMode
        )) {
          ForEach(PomodoroMode.allCases, id: \.self) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 430)
        .padding(.horizontal, 24)
        .padding(.top, 12)

        Spacer(minLength: 24)

        ZStack {
          Circle()
            .stroke(QingxuPalette.separator, lineWidth: 10)
          Circle()
            .trim(from: 0, to: min(1, max(0, progress)))
            .stroke(
              QingxuPalette.accent,
              style: StrokeStyle(lineWidth: 10, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .animation(.linear(duration: 0.25), value: progress)
          VStack(spacing: 10) {
            Text(store.pomodoro.mode.title)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(QingxuPalette.quiet)
            Text(format(store.displayedRemainingSeconds))
              .font(.system(size: 60, weight: .light, design: .rounded).monospacedDigit())
            Text("已完成 \(store.pomodoro.completedFocusSessions) 次专注")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .frame(width: 300, height: 300)
        .accessibilityElement(children: .combine)

        Spacer(minLength: 28)

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
              .foregroundStyle(.white)
              .background(QingxuPalette.accent, in: Capsule())
          }
          .buttonStyle(.plain)

          Button { showingDurations = true } label: {
            Image(systemName: "slider.horizontal.3")
              .frame(width: 48, height: 48)
              .background(QingxuPalette.surface, in: Circle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("自定义时长")
        }

        Spacer(minLength: 34)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(QingxuPalette.background.ignoresSafeArea())
      .tint(QingxuPalette.accent)
      .navigationTitle("番茄钟")
      .sheet(isPresented: $showingDurations) {
        DurationSettingsSheet()
          .environmentObject(store)
      }
    }
  }

  private func format(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }
}

private struct DurationSettingsSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @State private var focus: Int
  @State private var shortBreak: Int
  @State private var longBreak: Int

  init() {
    _focus = State(initialValue: 25)
    _shortBreak = State(initialValue: 5)
    _longBreak = State(initialValue: 15)
  }

  var body: some View {
    NavigationStack {
      Form {
        Stepper("专注：\(focus) 分钟", value: $focus, in: 1...180)
        Stepper("短休息：\(shortBreak) 分钟", value: $shortBreak, in: 1...60)
        Stepper("长休息：\(longBreak) 分钟", value: $longBreak, in: 1...120)
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
            store.updateDurations(focus: focus, shortBreak: shortBreak, longBreak: longBreak)
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
    }
  }
}
