import SwiftUI

enum TaskScope {
  case inbox
  case today

  var title: String { self == .inbox ? "收集箱" : "今天" }
  var emptyTitle: String { self == .inbox ? "收集箱已清空" : "今天没有任务" }
  var emptyDetail: String { self == .inbox ? "随时记录任务和想法" : "留一点时间给自己" }
  var symbol: String { self == .inbox ? "tray" : "sun.max" }
}

private struct TaskEditorRoute: Identifiable {
  let id = UUID()
  let task: TaskItem?
  let scope: TaskScope
}

struct TaskListScreen: View {
  @EnvironmentObject private var store: AppStore
  let scope: TaskScope

  @State private var searchText = ""
  @State private var editor: TaskEditorRoute?
  @State private var pendingDelete: TaskItem?
  @State private var recentlyDeleted: TaskItem?

  private var tasks: [TaskItem] {
    let values = scope == .inbox ? store.inboxTasks : store.todayTasks
    guard !searchText.isEmpty else { return values }
    return values.filter {
      $0.title.localizedStandardContains(searchText) ||
      $0.notes.localizedStandardContains(searchText)
    }
  }

  var body: some View {
    NavigationStack {
      ZStack {
        List {
          ForEach(tasks) { task in
            TaskRow(task: task) {
              withAnimation(.easeInOut(duration: 0.2)) { store.toggleTask(task) }
            }
            .contentShape(Rectangle())
            .onTapGesture { editor = TaskEditorRoute(task: task, scope: scope) }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button(role: .destructive) { pendingDelete = task } label: {
                Label("删除", systemImage: "trash")
              }
            }
            .listRowBackground(QingxuPalette.surface)
            .listRowSeparatorTint(QingxuPalette.separator)
          }
        }
        .listStyle(.plain)

        if tasks.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: scope.symbol)
              .font(.system(size: 42, weight: .light))
            Text(scope.emptyTitle)
              .font(.title3.weight(.semibold))
              .foregroundStyle(.primary)
            Text(scope.emptyDetail)
              .font(.subheadline)
          }
          .foregroundStyle(QingxuPalette.quiet)
        }
      }
      .qingxuScreen()
      .navigationTitle(scope.title)
      .searchable(text: $searchText, prompt: "搜索任务")
      .toolbar {
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) { addButton }
        #endif
      }
      #if os(iOS)
      .overlay(alignment: .bottomTrailing) {
        addButton
          .padding(.trailing, 20)
          .padding(.bottom, 18)
      }
      #endif
      .overlay(alignment: .bottom) {
        if let recentlyDeleted {
          undoBanner(for: recentlyDeleted)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .sheet(item: $editor) { route in
        TaskEditorSheet(task: route.task, scope: route.scope)
          .environmentObject(store)
      }
      .confirmationDialog(
        "删除“\(pendingDelete?.title ?? "任务")”？",
        isPresented: Binding(
          get: { pendingDelete != nil },
          set: { if !$0 { pendingDelete = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("删除", role: .destructive) {
          guard let task = pendingDelete else { return }
          withAnimation(.easeInOut(duration: 0.2)) {
            store.deleteTask(task)
            recentlyDeleted = task
          }
          pendingDelete = nil
        }
        Button("取消", role: .cancel) { pendingDelete = nil }
      }
    }
  }

  private var addButton: some View {
    Button {
      editor = TaskEditorRoute(task: nil, scope: scope)
    } label: {
      Image(systemName: "plus")
        .font(.system(size: 20, weight: .semibold))
        .frame(width: 54, height: 54)
        .foregroundStyle(.white)
        .background(QingxuPalette.accent, in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("新增任务")
    .qingxuFloatingSurface()
  }

  private func undoBanner(for task: TaskItem) -> some View {
    HStack {
      Text("任务已删除").font(.subheadline)
      Spacer()
      Button("撤销") {
        withAnimation(.easeInOut(duration: 0.2)) {
          store.restoreTask(task)
          recentlyDeleted = nil
        }
      }
      .fontWeight(.semibold)
    }
    .padding(.horizontal, 16)
    .frame(height: 48)
    .background(.regularMaterial, in: Capsule())
  }
}

private struct TaskRow: View {
  let task: TaskItem
  let toggle: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 13) {
      Button(action: toggle) {
        Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(task.status == .completed ? QingxuPalette.accent : QingxuPalette.quiet)
      }
      .buttonStyle(.plain)

      VStack(alignment: .leading, spacing: 4) {
        Text(task.title)
          .font(.body.weight(.medium))
          .strikethrough(task.status == .completed)
        if !task.notes.isEmpty {
          Text(task.notes)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
      Spacer(minLength: 8)
      if let deadline = task.deadlineAt {
        Text(deadline, format: .dateTime.month().day())
          .font(.caption)
          .foregroundStyle(QingxuPalette.quiet)
      }
    }
    .padding(.vertical, 8)
  }
}

private struct TaskEditorSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss

  let task: TaskItem?
  let scope: TaskScope

  @State private var title: String
  @State private var notes: String
  @State private var scheduledToday: Bool
  @State private var hasDeadline: Bool
  @State private var deadline: Date

  init(task: TaskItem?, scope: TaskScope) {
    self.task = task
    self.scope = scope
    _title = State(initialValue: task?.title ?? "")
    _notes = State(initialValue: task?.notes ?? "")
    _scheduledToday = State(initialValue: task?.startAt != nil || scope == .today)
    _hasDeadline = State(initialValue: task?.deadlineAt != nil)
    _deadline = State(initialValue: task?.deadlineAt ?? .now)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("任务") {
          TextField("要做什么？", text: $title)
          TextField("备注（可选）", text: $notes, axis: .vertical)
            .lineLimit(3...7)
        }
        Section("时间") {
          Toggle("安排到今天", isOn: $scheduledToday)
          Toggle("设置截止时间", isOn: $hasDeadline)
          if hasDeadline {
            DatePicker("截止", selection: $deadline)
          }
        }
      }
      .qingxuScreen()
      .navigationTitle(task == nil ? "新增任务" : "编辑任务")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .frame(minWidth: 360, minHeight: 360)
  }

  private func save() {
    let today = Calendar.autoupdatingCurrent.startOfDay(for: .now)
    if var task {
      task.title = title
      task.notes = notes
      task.startAt = scheduledToday ? today : nil
      task.deadlineAt = hasDeadline ? deadline : nil
      store.updateTask(task)
    } else {
      guard let created = store.addTask(title: title, notes: notes, forToday: scheduledToday) else { return }
      if hasDeadline {
        var updated = created
        updated.deadlineAt = deadline
        store.updateTask(updated)
      }
    }
    dismiss()
  }
}
