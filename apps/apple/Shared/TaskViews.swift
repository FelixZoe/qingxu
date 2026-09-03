import SwiftUI

enum TaskScope {
  case inbox
  case today

  var title: String { self == .inbox ? "收集箱" : "今天" }
  var emptyTitle: String { self == .inbox ? "收集箱已清空" : "今天没有任务" }
  var emptyDetail: String { self == .inbox ? "随时记录任务和想法" : "留一点时间给自己" }
  var symbol: String { self == .inbox ? "tray" : "calendar" }
}

private struct TaskEditorRoute: Identifiable {
  let id = UUID()
  let task: TaskItem?
  let scope: TaskScope
}

private struct TaskCaptureRoute: Identifiable {
  let id = UUID()
  let scope: TaskScope
  let scheduledAt: Date?
}

private struct TaskMoveRoute: Identifiable {
  let task: TaskItem
  var id: String { task.id }
}

struct TaskListScreen: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.openURL) private var openURL
  let scope: TaskScope
  @StateObject private var ambientStore = TodayAmbientStore()

  @State private var searchText = ""
  @State private var editor: TaskEditorRoute?
  @State private var capture: TaskCaptureRoute?
  @State private var moveRoute: TaskMoveRoute?
  @State private var recentlyDeleted: TaskItem?
  @State private var undoDismissTask: Task<Void, Never>?
  @State private var showingAIPlanner = false
  @State private var selectedDate = Date.now
  @AppStorage(QingxuPreferenceKey.showFestivals) private var showFestivalLabels = true
  @AppStorage(QingxuPreferenceKey.showTaskIndicators) private var showTaskIndicators = true
  @AppStorage(QingxuPreferenceKey.weekStartsMonday) private var weekStartsMonday = true
  #if os(iOS)
  @AppStorage(QingxuPreferenceKey.haptics) private var hapticsEnabled = true
  @AppStorage(QingxuPreferenceKey.completionSound) private var completionSoundEnabled = false
  #endif
  #if os(iOS)
  @State private var calendarExpansion: CGFloat = 0
  @State private var calendarDragStart: CGFloat?
  #endif

  private var tasks: [TaskItem] {
    let values = scope == .inbox
      ? store.displayedInboxTasks
      : store.displayedTasks(on: selectedDate)
    guard scope == .inbox, !searchText.isEmpty else { return values }
    return values.filter {
      $0.title.localizedStandardContains(searchText) ||
      $0.notes.localizedStandardContains(searchText)
    }
  }

  var body: some View {
    NavigationStack {
      ZStack {
        #if os(iOS)
        if scope == .today {
          todayFixedLayout
        } else {
          standardTaskList
        }
        #else
        standardTaskList
        #endif
      }
      .qingxuScreen()
      #if os(iOS)
      .navigationTitle(scope == .today ? "" : navigationTitle)
      .navigationBarTitleDisplayMode(scope == .today ? .inline : .large)
      .qingxuInboxSearch(enabled: scope == .inbox, text: $searchText)
      #else
      .navigationTitle(navigationTitle)
      .searchable(text: $searchText, prompt: "搜索任务")
      #endif
      .toolbar {
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) { addButton }
        #else
        if scope == .today {
          ToolbarItem(placement: .principal) {
            TodayNavigationTitle(date: selectedDate, expansion: calendarExpansion)
          }
          ToolbarItem(placement: .navigationBarTrailing) {
            todayMoreMenu
          }
        }
        #endif
      }
      #if os(iOS)
      .overlay(alignment: .bottomTrailing) {
        if capture == nil {
          addButton
            .padding(.trailing, 20)
            .padding(.bottom, 18)
            .transition(.scale.combined(with: .opacity))
        }
      }
      #endif
      .overlay(alignment: .bottomLeading) {
        if let recentlyDeleted {
          undoButton(for: recentlyDeleted)
            .padding(.leading, 20)
            .padding(.bottom, 18)
            .transition(.scale(scale: 0.86, anchor: .bottomLeading).combined(with: .opacity))
        }
      }
      .sheet(item: $editor) { route in
        TaskEditorSheet(task: route.task, scope: route.scope)
          .environmentObject(store)
      }
      #if os(iOS)
      .sheet(item: $moveRoute) { route in
        TaskMoveSheet(task: route.task) { date in
          moveTask(route.task, to: date)
        }
        .presentationDetents([.height(350)])
        .presentationDragIndicator(.visible)
      }
      .sheet(isPresented: $showingAIPlanner) {
        AITaskPlannerSheet(tasks: store.displayedInboxTasks) { suggestions in
          addAISuggestions(suggestions)
        }
        .environmentObject(store)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
      #endif
      #if os(iOS)
      .overlay {
        if capture != nil {
          QingxuPalette.scrim.opacity(0.18)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { dismissCapture() }
            .transition(.opacity)
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if let capture {
          TaskQuickCaptureBar(
            scope: capture.scope,
            initialSchedule: capture.scheduledAt,
            onDismiss: dismissCapture
          )
          .environmentObject(store)
          .padding(.horizontal, 8)
          .padding(.bottom, 6)
          .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .animation(.easeOut(duration: 0.22), value: capture?.id)
      #endif
      .onDisappear { undoDismissTask?.cancel() }
      .task {
        if scope == .today { await ambientStore.load() }
      }
      .onReceive(NotificationCenter.default.publisher(for: QingxuAmbientPreferencesStore.didChange)) { _ in
        guard scope == .today else { return }
        Task { await ambientStore.load(force: true) }
      }
    }
  }

  private var navigationTitle: String {
    guard scope == .today else { return scope.title }
    if Calendar.autoupdatingCurrent.isDateInToday(selectedDate) { return "今天" }
    return chineseDateLabel(selectedDate, includesWeekday: true)
  }

  private var defaultEmptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: scope.symbol)
        .font(.system(size: 42, weight: .light))
      Text(scope.emptyTitle)
        .font(.title3.weight(.semibold))
        .foregroundStyle(QingxuPalette.ink)
      Text(scope.emptyDetail)
        .font(.subheadline)
    }
    .foregroundStyle(QingxuPalette.quiet)
  }

  private var standardTaskList: some View {
    List {
      taskRows

      if tasks.isEmpty {
        defaultEmptyState
          .frame(maxWidth: .infinity)
          .padding(.top, 120)
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
      }

      Color.clear
        .frame(height: 92)
        .listRowInsets(.init())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
    .listStyle(.plain)
    .environment(\.defaultMinListRowHeight, 1)
  }

  @ViewBuilder
  private var taskRows: some View {
    ForEach(tasks) { task in
      TaskRow(
        task: task,
        style: scope == .today ? .todayPanel : .card,
        scheduleLabel: scope == .today ? selectedDateLabel : nil
      ) {
        let completing = task.status != .completed
        withAnimation(.easeInOut(duration: 0.2)) { store.toggleTask(task) }
        #if os(iOS)
        if completing {
          QingxuFeedback.taskCompletion(
            haptics: hapticsEnabled,
            sound: completionSoundEnabled
          )
        } else {
          QingxuFeedback.selection(enabled: hapticsEnabled)
        }
        #endif
      }
      .contentShape(Rectangle())
      .onTapGesture { editor = TaskEditorRoute(task: task, scope: scope) }
      .swipeActions(edge: .trailing, allowsFullSwipe: false) {
        Button(role: .destructive) { deleteImmediately(task) } label: {
          Label("删除", systemImage: "trash")
        }
        Button { moveRoute = TaskMoveRoute(task: task) } label: {
          Label("迁移", systemImage: "calendar")
        }
        .tint(QingxuPalette.quiet)
      }
      .listRowInsets(.init(top: 5, leading: 20, bottom: 5, trailing: 20))
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
    }
  }

  #if os(iOS)
  @ViewBuilder
  private var todayTaskRows: some View {
    ForEach(tasks) { task in
      TaskSwipeContainer(
        move: { moveRoute = TaskMoveRoute(task: task) },
        delete: { deleteImmediately(task) }
      ) {
        TaskRow(task: task, style: .todayPanel, scheduleLabel: nil) {
          let completing = task.status != .completed
          withAnimation(.easeInOut(duration: 0.2)) { store.toggleTask(task) }
          if completing {
            QingxuFeedback.taskCompletion(
              haptics: hapticsEnabled,
              sound: completionSoundEnabled
            )
          } else {
            QingxuFeedback.selection(enabled: hapticsEnabled)
          }
        }
        .contentShape(Rectangle())
        .onTapGesture { editor = TaskEditorRoute(task: task, scope: scope) }
        .contextMenu {
          Button { store.toggleTask(task) } label: {
            Label(task.status == .completed ? "恢复任务" : "完成任务", systemImage: "checkmark.circle")
          }
          Button { moveRoute = TaskMoveRoute(task: task) } label: {
            Label("迁移任务", systemImage: "calendar")
          }
          Button(role: .destructive) { deleteImmediately(task) } label: {
            Label("删除", systemImage: "trash")
          }
        }
      }

      if task.id != tasks.last?.id {
        Divider()
          .overlay(QingxuPalette.separator.opacity(0.68))
          .padding(.leading, 36)
      }
    }
  }
  #endif

  #if os(iOS)
  private var todayFixedLayout: some View {
    GeometryReader { geometry in
      ZStack(alignment: .top) {
        TodayExpandableCalendar(
          selection: $selectedDate,
          expansion: $calendarExpansion,
          showsFestivals: showFestivalLabels,
          showsTaskIndicators: showTaskIndicators,
          weekStartsMonday: weekStartsMonday
        )
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .padding(.top, TodayCalendarMetrics.topPadding)
        .background(QingxuPalette.background)
        .contentShape(Rectangle())
        .gesture(todayCalendarDrag)
        .zIndex(1)

        ScrollView {
          LazyVStack(spacing: 0) {
            if ambientStore.quote != nil || ambientStore.weather != nil || ambientStore.isLoading {
              TodayAmbientStrip(
                weather: ambientStore.weather,
                quote: ambientStore.quote,
                isLoading: ambientStore.isLoading,
                refresh: { Task { await ambientStore.load(force: true) } }
              )
              .padding(.horizontal, 24)
              .padding(.bottom, 14)
            }

            if tasks.isEmpty {
              TodayEmptyState()
                .frame(maxWidth: .infinity)
                .padding(.top, 64)
            } else {
              VStack(alignment: .leading, spacing: 0) {
                TodayTaskPanelHeader(title: selectedDateLabel)
                todayTaskRows
              }
              .padding(.horizontal, 20)
              .padding(.top, 12)
              .padding(.bottom, 8)
              .background(
                QingxuPalette.surface,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
              )
              .padding(.horizontal, 20)
            }

            Color.clear.frame(height: tasks.isEmpty ? 360 : 118)
          }
          .frame(width: geometry.size.width)
          .background(TodayTaskScrollConfigurator(expansion: $calendarExpansion))
        }
        .scrollIndicators(.visible)
        // The scroll view spans the screen so its indicator stays on the
        // outside edge; only the task surface itself is inset.
        .frame(
          height: max(1, geometry.size.height - TodayCalendarMetrics.collapsedHeight),
          alignment: .top
        )
        .offset(y: TodayCalendarMetrics.collapsedHeight
          + TodayCalendarMetrics.expansionDistance * calendarExpansion)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .clipped()
    }
  }
  #endif

  private var selectedDateLabel: String {
    let calendar = Calendar.autoupdatingCurrent
    if calendar.isDateInToday(selectedDate) { return "今天" }
    if calendar.isDateInTomorrow(selectedDate) { return "明天" }
    return chineseDateLabel(selectedDate)
  }

  private func chineseDateLabel(_ date: Date, includesWeekday: Bool = false) -> String {
    let calendar = Calendar.autoupdatingCurrent
    let month = calendar.component(.month, from: date)
    let day = calendar.component(.day, from: date)
    guard includesWeekday else { return "\(month)月\(day)日" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "EEEE"
    return "\(month)月\(day)日 \(formatter.string(from: date))"
  }

  private var addButton: some View {
    Button {
      #if os(iOS)
      capture = TaskCaptureRoute(
        scope: scope,
        scheduledAt: scope == .today ? selectedDate : nil
      )
      #else
      editor = TaskEditorRoute(task: nil, scope: scope)
      #endif
    } label: {
      Image(systemName: "plus")
        .font(.system(size: 20, weight: .semibold))
        .frame(width: 54, height: 54)
        .foregroundStyle(QingxuPalette.onAccent)
        .background(QingxuPalette.actionGradient, in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("新增任务")
  }

  #if os(iOS)
  private var todayMoreMenu: some View {
    Menu {
      Menu {
        Button { setCalendarExpanded(false) } label: {
          Label("当前周", systemImage: calendarExpansion < 0.5 ? "checkmark" : "calendar")
        }
        Button { setCalendarExpanded(true) } label: {
          Label("整月", systemImage: calendarExpansion >= 0.5 ? "checkmark" : "calendar")
        }
      } label: {
        Label("显示范围", systemImage: "line.3.horizontal.decrease")
      }

      Menu {
        Toggle(isOn: $showFestivalLabels) {
          Label("节日", systemImage: "leaf")
        }
        Toggle(isOn: $showTaskIndicators) {
          Label("任务标记", systemImage: "circlebadge")
        }
      } label: {
        Label("显示设置", systemImage: "slider.horizontal.3")
      }

      Button {
        capture = TaskCaptureRoute(scope: .today, scheduledAt: selectedDate)
      } label: {
        Label("安排任务", systemImage: "calendar.badge.plus")
      }
      Button { showingAIPlanner = true } label: {
        Label("AI 智能安排", systemImage: "sparkles")
      }
      Button { openAppTab("rss") } label: {
        Label("RSS 订阅", systemImage: "dot.radiowaves.left.and.right")
      }

      Divider()

      Button {
        withAnimation(.easeInOut(duration: 0.28)) { selectedDate = .now }
      } label: {
        Label("回到今天", systemImage: "calendar.badge.clock")
      }
    } label: {
      Image(systemName: "ellipsis")
    }
    .foregroundStyle(QingxuPalette.ink)
    .accessibilityLabel("更多日历操作")
  }

  private func setCalendarExpanded(_ expanded: Bool) {
    withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24)) {
      calendarExpansion = expanded ? 1 : 0
    }
    UISelectionFeedbackGenerator().selectionChanged()
  }

  private func openAppTab(_ host: String) {
    guard let url = URL(string: "qingxu://\(host)") else { return }
    openURL(url)
  }
  #endif

  private func dismissCapture() {
    withAnimation(.easeOut(duration: 0.2)) { capture = nil }
  }

  #if os(iOS)
  private var todayCalendarDrag: some Gesture {
    DragGesture(minimumDistance: 3)
      .onChanged { value in
        guard scope == .today,
              capture == nil,
              abs(value.translation.height) > abs(value.translation.width)
        else { return }
        if calendarDragStart == nil { calendarDragStart = calendarExpansion }
        let start = calendarDragStart ?? calendarExpansion
        calendarExpansion = min(
          1,
          max(0, start + value.translation.height / TodayCalendarMetrics.expansionDistance)
        )
      }
      .onEnded { value in
        guard scope == .today, let start = calendarDragStart else { return }
        let projected = min(
          1,
          max(0, start + value.predictedEndTranslation.height / TodayCalendarMetrics.expansionDistance)
        )
        let target: CGFloat = projected >= 0.5 ? 1 : 0
        calendarDragStart = nil
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24)) {
          calendarExpansion = target
        }
        if (start < 0.5 && target == 1) || (start >= 0.5 && target == 0) {
          UISelectionFeedbackGenerator().selectionChanged()
        }
      }
  }

  #endif

  private func undoButton(for task: TaskItem) -> some View {
    Button {
      undoDismissTask?.cancel()
      withAnimation(.easeInOut(duration: 0.2)) {
        store.restoreTask(task)
        recentlyDeleted = nil
      }
    } label: {
      Image(systemName: "arrow.uturn.backward")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(QingxuPalette.onAccent)
        .frame(width: 54, height: 54)
        .background(QingxuPalette.actionGradient, in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("撤销删除")
  }

  private func deleteImmediately(_ task: TaskItem) {
    undoDismissTask?.cancel()
    withAnimation(.easeInOut(duration: 0.18)) {
      store.deleteTask(task)
      recentlyDeleted = task
    }
    undoDismissTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(4))
      guard !Task.isCancelled, recentlyDeleted?.id == task.id else { return }
      withAnimation(.easeOut(duration: 0.18)) { recentlyDeleted = nil }
    }
  }

  private func moveTask(_ task: TaskItem, to date: Date?) {
    var updated = task
    updated.startAt = date.map { Calendar.autoupdatingCurrent.startOfDay(for: $0) }
    store.updateTask(updated)
    moveRoute = nil
  }

  private func addAISuggestions(_ suggestions: [QingxuAISuggestion]) {
    let calendar = Calendar.autoupdatingCurrent
    for suggestion in suggestions {
      guard var task = store.addTask(title: suggestion.title, forToday: false) else { continue }
      task.startAt = calendar.date(
        byAdding: .day,
        value: max(0, min(14, suggestion.dayOffset)),
        to: calendar.startOfDay(for: .now)
      )
      store.updateTask(task)
    }
  }
}

private enum TaskRowStyle {
  case card
  case todayPanel
}

private struct TaskRow: View {
  let task: TaskItem
  let style: TaskRowStyle
  let scheduleLabel: String?
  let toggle: () -> Void

  var body: some View {
    HStack(alignment: task.notes.isEmpty ? .center : .top, spacing: 13) {
      Button(action: toggle) {
        if style == .todayPanel {
          ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
              .stroke(
                task.status == .completed ? QingxuPalette.success : QingxuPalette.quiet.opacity(0.55),
                lineWidth: 1.6
              )
              .frame(width: 23, height: 23)
            if task.status == .completed {
              Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(QingxuPalette.success)
            }
          }
        } else {
          Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(task.status == .completed ? QingxuPalette.success : QingxuPalette.quiet)
        }
      }
      .buttonStyle(.plain)

      VStack(alignment: .leading, spacing: 4) {
        Text(task.title)
          .font(task.status == .completed ? QingxuType.rowTitleCompleted : QingxuType.rowTitle)
          .strikethrough(task.status == .completed, color: QingxuPalette.quiet)
          .foregroundStyle(task.status == .completed ? QingxuPalette.quiet : QingxuPalette.ink)
        if !task.notes.isEmpty {
          Text(task.notes)
            .font(.subheadline)
            .foregroundStyle(QingxuPalette.quiet)
            .lineLimit(2)
        }
      }
      Spacer(minLength: 8)
      if let priority = task.priority {
        Image(systemName: priority.symbol)
          .font(.caption.weight(.semibold))
          .foregroundStyle(priority.color)
          .accessibilityLabel(priority.title)
      }
      if let deadline = task.deadlineAt {
        Text(numericChineseDate(deadline))
          .font(.caption)
          .foregroundStyle(QingxuPalette.quiet)
      } else if let scheduleLabel {
        Text(scheduleLabel)
          .font(QingxuType.metadata.weight(.medium))
          .foregroundStyle(QingxuPalette.quiet)
      }
    }
    .padding(.horizontal, style == .todayPanel ? 0 : 16)
    .padding(.vertical, 13)
    .opacity(task.status == .completed ? 0.72 : 1)
    .background {
      if style == .card {
        QingxuPalette.surface
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      }
    }
  }

  private func numericChineseDate(_ date: Date) -> String {
    let calendar = Calendar.autoupdatingCurrent
    return "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
  }
}

#if os(iOS)
private struct TaskSwipeContainer<Content: View>: View {
  let move: () -> Void
  let delete: () -> Void
  @ViewBuilder let content: () -> Content

  @State private var offset: CGFloat = 0
  @State private var dragStartOffset: CGFloat?
  private let actionWidth: CGFloat = 142

  private var actionProgress: CGFloat {
    min(1, max(0, -offset / actionWidth))
  }

  var body: some View {
    ZStack(alignment: .trailing) {
      HStack(spacing: 8) {
        actionButton(title: "迁移", symbol: "calendar", prominent: false) {
          close()
          move()
        }
        actionButton(title: "删除", symbol: "trash", prominent: true) {
          close()
          delete()
        }
      }
      .padding(.horizontal, 6)
      .frame(width: actionWidth, alignment: .trailing)
      .opacity(actionProgress)
      .allowsHitTesting(actionProgress > 0.96)

      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QingxuPalette.surface)
        .offset(x: offset)
    }
    .background(QingxuPalette.surface)
    .contentShape(Rectangle())
    .clipShape(Rectangle())
    .simultaneousGesture(
      DragGesture(minimumDistance: 12)
        .onChanged { value in
          guard abs(value.translation.width) > abs(value.translation.height) else { return }
          if dragStartOffset == nil { dragStartOffset = offset }
          let start = dragStartOffset ?? offset
          offset = min(0, max(-actionWidth, start + value.translation.width))
        }
        .onEnded { value in
          guard abs(value.translation.width) > abs(value.translation.height) else {
            dragStartOffset = nil
            return
          }
          let start = dragStartOffset ?? offset
          let projected = min(0, max(-actionWidth, start + value.predictedEndTranslation.width))
          dragStartOffset = nil
          withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
            offset = projected < -actionWidth * 0.42 ? -actionWidth : 0
          }
        }
    )
  }

  private func actionButton(
    title: String,
    symbol: String,
    prominent: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
        Text(title).font(.caption2.weight(.medium))
      }
      .foregroundStyle(prominent ? QingxuPalette.onAccent : QingxuPalette.ink)
      .frame(width: 61, height: 56)
      .background(
        prominent ? QingxuPalette.accent : QingxuPalette.secondaryBackground,
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
    }
    .buttonStyle(.plain)
  }

  private func close() {
    dragStartOffset = nil
    withAnimation(.easeOut(duration: 0.16)) { offset = 0 }
  }
}

private struct TaskMoveSheet: View {
  @Environment(\.dismiss) private var dismiss
  let task: TaskItem
  let onMove: (Date?) -> Void
  @State private var customDate = Date.now

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 5) {
        Text("迁移任务")
          .font(.title2.weight(.semibold))
        Text(task.title)
          .font(.subheadline)
          .foregroundStyle(QingxuPalette.quiet)
          .lineLimit(1)
      }

      HStack(spacing: 10) {
        choice("今天", symbol: "calendar", date: .now)
        choice("明天", symbol: "sunrise", date: tomorrow)
        choice("下周一", symbol: "calendar.badge.clock", date: nextMonday)
      }

      HStack(spacing: 12) {
        Label("选择日期", systemImage: "calendar.badge.plus")
          .font(.subheadline.weight(.medium))
        Spacer()
        DatePicker("选择日期", selection: $customDate, displayedComponents: .date)
          .labelsHidden()
          .onChange(of: customDate) { date in onMove(date); dismiss() }
      }
      .padding(.horizontal, 14)
      .frame(height: 52)
      .background(QingxuPalette.secondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

      Button {
        onMove(nil)
        dismiss()
      } label: {
        Label("清除日期，移回收集箱", systemImage: "tray")
          .font(.subheadline.weight(.medium))
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(height: 46)
      }
      .buttonStyle(.plain)
      .foregroundStyle(QingxuPalette.quiet)
    }
    .padding(22)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(QingxuPalette.surface)
  }

  private func choice(_ title: String, symbol: String, date: Date) -> some View {
    Button {
      onMove(date)
      dismiss()
    } label: {
      VStack(spacing: 7) {
        Image(systemName: symbol).font(.system(size: 20, weight: .medium))
        Text(title).font(.caption.weight(.medium))
      }
      .foregroundStyle(QingxuPalette.ink)
      .frame(maxWidth: .infinity)
      .frame(height: 74)
      .background(QingxuPalette.secondaryBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private var tomorrow: Date {
    Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: .now) ?? .now
  }

  private var nextMonday: Date {
    Calendar.autoupdatingCurrent.nextDate(
      after: .now,
      matching: DateComponents(weekday: 2),
      matchingPolicy: .nextTime
    ) ?? tomorrow
  }
}

private struct AITaskPlannerSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let tasks: [TaskItem]
  let onApply: ([QingxuAISuggestion]) -> Void

  @State private var goal = ""
  @State private var plan: QingxuAITaskPlan?
  @State private var selected = Set<String>()
  @State private var isLoading = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          VStack(alignment: .leading, spacing: 8) {
            Text("你接下来想完成什么？")
              .font(QingxuType.sectionTitle)
            TextField("例如：本周完成课程项目", text: $goal, axis: .vertical)
              .font(QingxuType.body)
              .padding(14)
              .background(
                QingxuPalette.secondaryBackground,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
              )
          }

          Button {
            Task { await generate() }
          } label: {
            HStack(spacing: 8) {
              if isLoading { ProgressView().tint(QingxuPalette.onAccent) }
              Image(systemName: "sparkles")
              Text(isLoading ? "正在整理" : "生成轻量计划")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(QingxuPalette.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(QingxuPalette.accent, in: Capsule())
          }
          .buttonStyle(.plain)
          .disabled(isLoading || (goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && tasks.isEmpty))

          if let plan {
            VStack(alignment: .leading, spacing: 14) {
              Text(plan.summary)
                .font(QingxuType.body)
                .foregroundStyle(QingxuPalette.quiet)

              ForEach(plan.suggestions) { suggestion in
                Button {
                  if selected.contains(suggestion.id) {
                    selected.remove(suggestion.id)
                  } else {
                    selected.insert(suggestion.id)
                  }
                } label: {
                  HStack(spacing: 12) {
                    Image(systemName: selected.contains(suggestion.id) ? "checkmark.circle.fill" : "circle")
                    VStack(alignment: .leading, spacing: 3) {
                      Text(suggestion.title)
                        .font(QingxuType.rowTitle)
                        .foregroundStyle(QingxuPalette.ink)
                      Text(suggestion.dayOffset == 0 ? "今天" : "\(suggestion.dayOffset) 天后")
                        .font(QingxuType.metadata)
                        .foregroundStyle(QingxuPalette.quiet)
                    }
                    Spacer()
                  }
                  .padding(.vertical, 9)
                }
                .buttonStyle(.plain)

                if suggestion.id != plan.suggestions.last?.id {
                  Divider().overlay(QingxuPalette.separator)
                }
              }
            }
            .padding(18)
            .background(QingxuPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
          }
        }
        .padding(20)
      }
      .qingxuScreen()
      .navigationTitle("智能安排")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("添加") {
            let choices = plan?.suggestions.filter { selected.contains($0.id) } ?? []
            onApply(choices)
            dismiss()
          }
          .disabled(selected.isEmpty)
          .fontWeight(.semibold)
        }
      }
      .alert("AI 暂时不可用", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("好", role: .cancel) { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
    }
  }

  @MainActor
  private func generate() async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let result = try await QingxuAIClient().plan(
        goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
        tasks: tasks,
        settings: store.syncSettings,
        aiSettings: store.aiSettings
      )
      plan = result
      selected = Set(result.suggestions.map(\.id))
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
#endif

#if os(iOS)
private extension View {
  @ViewBuilder
  func qingxuInboxSearch(enabled: Bool, text: Binding<String>) -> some View {
    if enabled {
      searchable(
        text: text,
        placement: .navigationBarDrawer(displayMode: .automatic),
        prompt: "搜索任务"
      )
    } else {
      self
    }
  }
}

private enum CaptureModal: String, Identifiable {
  case schedule

  var id: String { rawValue }
}

private struct TaskQuickCaptureBar: View {
  @EnvironmentObject private var store: AppStore

  let onDismiss: () -> Void

  @FocusState private var titleFocused: Bool
  @State private var title = ""
  @State private var notes = ""
  @State private var presentedModal: CaptureModal?
  @State private var hasSchedule: Bool
  @State private var scheduledAt: Date
  @State private var includesTime = false
  @State private var priority: TaskPriority?

  init(scope: TaskScope, initialSchedule: Date?, onDismiss: @escaping () -> Void) {
    self.onDismiss = onDismiss
    let date = initialSchedule ?? Calendar.autoupdatingCurrent.startOfDay(for: .now)
    _hasSchedule = State(initialValue: initialSchedule != nil || scope == .today)
    _scheduledAt = State(initialValue: date)
  }

  var body: some View {
    composer
      .frame(height: 172)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
          .stroke(QingxuPalette.separator.opacity(0.7), lineWidth: 0.7)
      }
      .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
      .sheet(item: $presentedModal) { _ in
        schedulePicker
          .presentationDetents([.fraction(0.82)])
          .presentationDragIndicator(.visible)
      }
  }

  private var composer: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 9) {
        TextField("例如：每月 9 号还信用卡", text: $title)
          .font(.system(size: 18, weight: .medium))
          .focused($titleFocused)
          .submitLabel(.done)
          .onSubmit(save)
          .accessibilityIdentifier("quickCaptureTitle")

        TextField("描述", text: $notes, axis: .vertical)
          .font(.subheadline)
          .foregroundStyle(QingxuPalette.quiet)
          .lineLimit(1...2)
          .accessibilityIdentifier("quickCaptureNotes")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.top, 20)

      Spacer(minLength: 12)

      HStack(spacing: 8) {
        captureButton(
          symbol: hasSchedule ? "calendar.badge.checkmark" : "calendar",
          label: hasSchedule ? scheduleLabel : "安排"
        ) {
          titleFocused = false
          presentedModal = .schedule
        }

        Menu {
          ForEach(TaskPriority.allCases) { value in
            Button {
              priority = value
            } label: {
              Label(value.title, systemImage: value.symbol)
            }
          }
          if priority != nil {
            Divider()
            Button("清除优先级", role: .destructive) { priority = nil }
          }
        } label: {
          Image(systemName: priority?.symbol ?? "flag")
            .foregroundStyle(priority?.color ?? QingxuPalette.quiet)
            .frame(width: 38, height: 38)
            .background(QingxuPalette.secondaryBackground, in: Circle())
        }
        .accessibilityLabel(priority?.title ?? "设置优先级")

        Button {
          hasSchedule.toggle()
          if hasSchedule {
            scheduledAt = Calendar.autoupdatingCurrent.startOfDay(for: .now)
          }
        } label: {
          Image(systemName: hasSchedule ? "sun.max.fill" : "tray")
            .frame(width: 38, height: 38)
            .background(QingxuPalette.secondaryBackground, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hasSchedule ? QingxuPalette.accent : QingxuPalette.quiet)
        .accessibilityLabel(hasSchedule ? "已安排到今天" : "保存在收集箱")

        Spacer()

        Button(action: save) {
          Image(systemName: "checkmark")
            .font(.system(size: 17, weight: .bold))
            .frame(width: 42, height: 42)
            .foregroundStyle(QingxuPalette.onAccent)
            .background(QingxuPalette.actionGradient, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        .accessibilityLabel("保存任务")
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 14)
    }
    .onAppear {
      DispatchQueue.main.async { titleFocused = true }
    }
  }

  private var schedulePicker: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 22) {
          HStack(spacing: 10) {
            scheduleShortcut("今天", symbol: "calendar", date: .now)
            scheduleShortcut(
              "明天",
              symbol: "sunrise",
              date: Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: .now) ?? .now
            )
            scheduleShortcut("下周一", symbol: "calendar.badge.clock", date: nextMonday)
          }

          DatePicker(
            "日期",
            selection: $scheduledAt,
            displayedComponents: .date
          )
          .datePickerStyle(.graphical)
          .tint(QingxuPalette.accent)

          VStack(spacing: 0) {
            Toggle("指定时间", isOn: $includesTime)
              .padding(.horizontal, 16)
              .frame(height: 54)
            if includesTime {
              Divider().padding(.leading, 16)
              DatePicker(
                "时间",
                selection: $scheduledAt,
                displayedComponents: .hourAndMinute
              )
              .padding(.horizontal, 16)
              .frame(height: 54)
            }
          }
          .background(QingxuPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
      }
      .navigationTitle("安排")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("返回") {
            presentedModal = nil
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("完成") {
            hasSchedule = true
            presentedModal = nil
          }
          .fontWeight(.semibold)
        }
      }
    }
  }

  private func captureButton(
    symbol: String,
    label: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: symbol)
        Text(label).lineLimit(1)
      }
      .font(.subheadline.weight(.medium))
      .foregroundStyle(hasSchedule ? QingxuPalette.accent : QingxuPalette.quiet)
      .padding(.horizontal, 12)
      .frame(height: 38)
      .background(QingxuPalette.secondaryBackground, in: Capsule())
    }
    .buttonStyle(.plain)
  }

  private func scheduleShortcut(_ title: String, symbol: String, date: Date) -> some View {
    Button {
      scheduledAt = Calendar.autoupdatingCurrent.startOfDay(for: date)
      hasSchedule = true
    } label: {
      VStack(spacing: 8) {
        Image(systemName: symbol).font(.title3)
        Text(title).font(.caption)
      }
      .foregroundStyle(QingxuPalette.accent)
      .frame(maxWidth: .infinity)
      .frame(height: 72)
      .background(QingxuPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private var nextMonday: Date {
    let calendar = Calendar.autoupdatingCurrent
    return calendar.nextDate(
      after: .now,
      matching: DateComponents(weekday: 2),
      matchingPolicy: .nextTime
    ) ?? .now
  }

  private var scheduleLabel: String {
    if Calendar.autoupdatingCurrent.isDateInToday(scheduledAt) { return "今天" }
    if Calendar.autoupdatingCurrent.isDateInTomorrow(scheduledAt) { return "明天" }
    let calendar = Calendar.autoupdatingCurrent
    return "\(calendar.component(.month, from: scheduledAt))月\(calendar.component(.day, from: scheduledAt))日"
  }

  private func save() {
    guard let created = store.addTask(title: title, notes: notes) else { return }
    var updated = created
    updated.priority = priority
    if hasSchedule {
      updated.startAt = includesTime
        ? scheduledAt
        : Calendar.autoupdatingCurrent.startOfDay(for: scheduledAt)
    }
    store.updateTask(updated)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    onDismiss()
  }
}

private enum TodayCalendarMetrics {
  static let rowHeight: CGFloat = 52
  static let weekdayHeight: CGFloat = 24
  static let gridSpacing: CGFloat = 5
  static let topPadding: CGFloat = 4
  static let collapsedHeight = topPadding + weekdayHeight + gridSpacing + rowHeight
  static let expansionDistance = rowHeight * 5
}

private enum TodayCalendarDragDirection: Equatable {
  case expand
  case collapse
}

/// Observe the List's existing UIKit pan recognizer instead of adding a second
/// SwiftUI drag recognizer. This gives the calendar one continuous progress
/// source and prevents List scrolling, scroll disabling and layout updates
/// from fighting over the same gesture.
private struct TodayTaskScrollConfigurator: UIViewRepresentable {
  @Binding var expansion: CGFloat

  func makeCoordinator() -> Coordinator {
    Coordinator(expansion: $expansion)
  }

  func makeUIView(context: Context) -> UIView {
    let marker = UIView(frame: .zero)
    marker.isUserInteractionEnabled = false
    configureEnclosingScrollView(from: marker, coordinator: context.coordinator)
    return marker
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.expansion = $expansion
    configureEnclosingScrollView(from: uiView, coordinator: context.coordinator)
  }

  private func configureEnclosingScrollView(from marker: UIView, coordinator: Coordinator) {
    DispatchQueue.main.async { [weak marker, weak coordinator] in
      var ancestor = marker?.superview
      while let view = ancestor {
        if let scrollView = view as? UIScrollView {
          // A short task list is smaller than the viewport. It still needs a
          // vertical pan recognizer so a pull can expand the calendar.
          scrollView.bounces = true
          scrollView.alwaysBounceVertical = true
          scrollView.showsVerticalScrollIndicator = true
          scrollView.isDirectionalLockEnabled = true
          coordinator?.attach(to: scrollView)
          return
        }
        ancestor = view.superview
      }
    }
  }

  final class Coordinator: NSObject {
    var expansion: Binding<CGFloat>
    private weak var scrollView: UIScrollView?
    private var direction: TodayCalendarDragDirection?
    private var startExpansion: CGFloat = 0
    private var lastTranslation: CGFloat = 0

    init(expansion: Binding<CGFloat>) {
      self.expansion = expansion
    }

    deinit {
      scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
    }

    func attach(to scrollView: UIScrollView) {
      guard self.scrollView !== scrollView else { return }
      self.scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
      self.scrollView = scrollView
      scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
      guard let scrollView else { return }
      let translation = recognizer.translation(in: scrollView).y

      switch recognizer.state {
      case .began:
        direction = nil
        startExpansion = expansion.wrappedValue
        lastTranslation = 0
        let top = -scrollView.adjustedContentInset.top
        let atTop = scrollView.contentOffset.y <= top + 6
        let velocity = recognizer.velocity(in: scrollView).y
        if velocity > 0, atTop, expansion.wrappedValue < 0.999 {
          direction = .expand
          keepListAtTop(scrollView)
        } else if velocity < 0, expansion.wrappedValue > 0.001 {
          direction = .collapse
          keepListAtTop(scrollView)
        }

      case .changed:
        if direction == nil {
          let top = -scrollView.adjustedContentInset.top
          let atTop = scrollView.contentOffset.y <= top + 6
          if translation > 1, atTop, expansion.wrappedValue < 0.999 {
            direction = .expand
            startExpansion = expansion.wrappedValue
          } else if translation < -1, expansion.wrappedValue > 0.001 {
            direction = .collapse
            startExpansion = expansion.wrappedValue
          }
        }
        guard let direction else { return }
        keepListAtTop(scrollView)
        expansion.wrappedValue = min(
          1,
          max(0, startExpansion + translation / TodayCalendarMetrics.expansionDistance)
        )
        if direction == .collapse, expansion.wrappedValue <= 0.001 {
          // Once the calendar is fully collapsed, release the rest of this
          // same upward gesture to the task list instead of requiring a
          // second swipe.
          self.direction = nil
          recognizer.setTranslation(.zero, in: scrollView)
        }

      case .ended, .cancelled, .failed:
        guard let direction else { return }
        keepListAtTop(scrollView)
        let velocity = recognizer.velocity(in: scrollView).y
        let projected = expansion.wrappedValue
          + velocity * 0.12 / TodayCalendarMetrics.expansionDistance
        let threshold: CGFloat = direction == .expand ? 0.42 : 0.58
        let target: CGFloat = projected >= threshold ? 1 : 0
        let crossedState = (startExpansion < 0.5 && target == 1)
          || (startExpansion >= 0.5 && target == 0)
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24)) {
          expansion.wrappedValue = target
        }
        if crossedState { UISelectionFeedbackGenerator().selectionChanged() }
        self.direction = nil

      default:
        break
      }
    }

    private func keepListAtTop(_ scrollView: UIScrollView) {
      let top = -scrollView.adjustedContentInset.top
      guard abs(scrollView.contentOffset.y - top) > 0.5 else { return }
      scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: top), animated: false)
    }
  }
}

private struct TodayAmbientStrip: View {
  let weather: QingxuWeatherSnapshot?
  let quote: QingxuQuoteSnapshot?
  let isLoading: Bool
  let refresh: () -> Void

  var body: some View {
    Button(action: refresh) {
      HStack(spacing: 14) {
        VStack(alignment: .leading, spacing: 5) {
          if let quote {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Image(systemName: "quote.opening")
                .font(.caption.weight(.semibold))
                .foregroundStyle(QingxuPalette.accent)
              Text(quote.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(QingxuPalette.ink)
                .lineLimit(2)
            }
            Text("— \(quote.source)")
              .font(.caption2)
              .foregroundStyle(QingxuPalette.quiet)
              .padding(.leading, 21)
          } else if isLoading {
            HStack(spacing: 9) {
              ProgressView().controlSize(.small)
              Text("正在准备今天的一句话")
                .font(.subheadline)
                .foregroundStyle(QingxuPalette.quiet)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let weather {
          HStack(spacing: 8) {
            Image(systemName: weatherSymbol(weather.icon, text: weather.text))
              .font(.system(size: 18, weight: .medium))
            VStack(alignment: .trailing, spacing: 1) {
              Text("\(weather.temperature)°")
                .font(.headline.monospacedDigit())
              Text(weather.text)
                .font(.caption2)
                .foregroundStyle(QingxuPalette.quiet)
            }
          }
          .foregroundStyle(QingxuPalette.ink)
          .padding(.leading, 12)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 13)
      .frame(maxWidth: .infinity, minHeight: 64)
      .background(QingxuPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .stroke(QingxuPalette.separator.opacity(0.72), lineWidth: 0.6)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("刷新天气和每日一句")
  }

  private func weatherSymbol(_ icon: String, text: String) -> String {
    if text.contains("雷") { return "cloud.bolt.rain.fill" }
    if text.contains("雨") { return "cloud.rain.fill" }
    if text.contains("雪") { return "cloud.snow.fill" }
    if text.contains("雾") || text.contains("霾") { return "cloud.fog.fill" }
    if text.contains("阴") { return "cloud.fill" }
    if text.contains("云") { return "cloud.sun.fill" }
    if ["150", "151", "152", "153"].contains(icon) { return "moon.stars.fill" }
    return "sun.max.fill"
  }
}

private struct TodayTaskPanelHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.system(size: 21, weight: .semibold, design: .rounded))
      .foregroundStyle(QingxuPalette.quiet)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.bottom, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct TodayNavigationTitle: View {
  let date: Date
  let expansion: CGFloat

  private let calendar = Calendar.autoupdatingCurrent
  var body: some View {
    ZStack {
      Text(monthTitle)
        .font(.caption.weight(.semibold))
        .foregroundStyle(QingxuPalette.quiet.opacity(0.72 + 0.28 * Double(expansion)))
        .offset(y: -7 * (1 - expansion))
      Text(dayTitle)
        .font(.headline)
        .foregroundStyle(QingxuPalette.ink)
        .opacity(1 - expansion)
        .offset(y: 8 * (1 - expansion))
    }
    .frame(width: 132, height: 44)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  private var monthTitle: String {
    let names = ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"]
    let month = calendar.component(.month, from: date)
    return names.indices.contains(month - 1) ? names[month - 1] : "\(month)月"
  }

  private var dayTitle: String {
    if calendar.isDateInToday(date) { return "今天" }
    if calendar.isDateInYesterday(date) { return "昨天" }
    if calendar.isDateInTomorrow(date) { return "明天" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "EEE"
    return formatter.string(from: date)
  }
}

private struct TodayExpandableCalendar: View {
  @Binding var selection: Date
  @Binding var expansion: CGFloat
  let showsFestivals: Bool
  let showsTaskIndicators: Bool
  let weekStartsMonday: Bool

  private let rowHeight = TodayCalendarMetrics.rowHeight
  private var weekdays: [String] {
    weekStartsMonday
      ? ["一", "二", "三", "四", "五", "六", "日"]
      : ["日", "一", "二", "三", "四", "五", "六"]
  }

  private var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.locale = Locale(identifier: "zh_CN")
    value.firstWeekday = weekStartsMonday ? 2 : 1
    return value
  }

  private var progress: CGFloat {
    min(1, max(0, expansion))
  }

  private var monthStart: Date {
    calendar.dateInterval(of: .month, for: selection)?.start
      ?? calendar.startOfDay(for: selection)
  }

  private var gridDays: [Date] {
    let weekday = calendar.component(.weekday, from: monthStart)
    let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
    let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart) ?? monthStart
    return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
  }

  var body: some View {
    let days = gridDays
    let selectedRow = (days.firstIndex {
      calendar.isDate($0, inSameDayAs: selection)
    } ?? 0) / 7
    let revealedRows = 5 * progress
    let leadingCapacity = CGFloat(selectedRow)
    let trailingCapacity = CGFloat(5 - selectedRow)
    let baseLeadingRows = min(leadingCapacity, revealedRows / 2)
    let revealedTrailingRows = min(trailingCapacity, revealedRows / 2)
    let revealedLeadingRows = baseLeadingRows + min(
      leadingCapacity - baseLeadingRows,
      revealedRows - baseLeadingRows - revealedTrailingRows
    )
    let gridOffset = -(CGFloat(selectedRow) - revealedLeadingRows) * rowHeight
    let visibleGridHeight = rowHeight * (1 + revealedRows)

    VStack(spacing: 5) {
      HStack(spacing: 0) {
        ForEach(weekdays, id: \.self) { value in
          Text(value)
            .font(.caption)
            .foregroundStyle(QingxuPalette.quiet.opacity(0.8))
            .frame(maxWidth: .infinity)
        }
      }
      .frame(height: TodayCalendarMetrics.weekdayHeight)

      ZStack(alignment: .top) {
        TodayCalendarGrid(
          days: days,
          selection: $selection,
          showsFestivals: showsFestivals,
          showsTaskIndicators: showsTaskIndicators
        )
        .equatable()
        .offset(y: gridOffset)
      }
      .frame(height: visibleGridHeight, alignment: .top)
      .clipped()
    }
    .contentShape(Rectangle())
  }
}

private struct TodayCalendarGrid: View, Equatable {
  @EnvironmentObject private var store: AppStore
  let days: [Date]
  @Binding var selection: Date
  let showsFestivals: Bool
  let showsTaskIndicators: Bool

  private let rowHeight = TodayCalendarMetrics.rowHeight

  private var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.locale = Locale(identifier: "zh_CN")
    value.firstWeekday = 2
    return value
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.days == rhs.days
      && lhs.selection == rhs.selection
      && lhs.showsFestivals == rhs.showsFestivals
      && lhs.showsTaskIndicators == rhs.showsTaskIndicators
  }

  var body: some View {
    let markedDays = taskDays

    LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
      spacing: 0
    ) {
      ForEach(days, id: \.self) { day in
        dayCell(
          day,
          hasTasks: markedDays.contains(calendar.startOfDay(for: day))
        )
      }
    }
    .animation(.easeOut(duration: 0.16), value: selection)
  }

  private var taskDays: Set<Date> {
    guard showsTaskIndicators else { return [] }
    return Set(store.tasks.lazy
      .filter(\.isOpen)
      .flatMap { [$0.startAt, $0.deadlineAt].compactMap { $0 } }
      .map { calendar.startOfDay(for: $0) })
  }

  private func dayCell(_ day: Date, hasTasks: Bool) -> some View {
    let isSelected = calendar.isDate(day, inSameDayAs: selection)
    let isToday = calendar.isDateInToday(day)
    let isCurrentMonth = calendar.isDate(day, equalTo: selection, toGranularity: .month)
    let festival = showsFestivals ? QingxuFestivalCalendar.title(for: day) : nil

    return Button {
      withAnimation(.easeInOut(duration: 0.18)) { selection = day }
    } label: {
      VStack(spacing: 0) {
        Text("\(calendar.component(.day, from: day))")
          .font(.system(size: 16, weight: isSelected ? .semibold : .medium, design: .rounded))
          .frame(width: 38, height: 38)
          .foregroundStyle(dayForeground(
            selected: isSelected,
            today: isToday,
            currentMonth: isCurrentMonth
          ))
          .background(isSelected ? QingxuPalette.accent : Color.clear, in: Circle())

        ZStack {
          if let festival {
            Text(festival)
              .font(.system(size: 9, weight: .medium))
              .lineLimit(1)
              .minimumScaleFactor(0.72)
              .foregroundStyle(isSelected ? QingxuPalette.onAccent.opacity(0.92) : QingxuPalette.success)
          } else if hasTasks {
            Circle()
              .fill(isSelected ? QingxuPalette.onAccent.opacity(0.9) : QingxuPalette.accent)
              .frame(width: 3.5, height: 3.5)
          }
        }
        .frame(height: 11)
      }
      .frame(maxWidth: .infinity)
      .frame(height: rowHeight)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
  }

  private func dayForeground(selected: Bool, today: Bool, currentMonth: Bool) -> Color {
    if selected { return QingxuPalette.onAccent }
    if today { return QingxuPalette.accent }
    return currentMonth ? QingxuPalette.ink : QingxuPalette.quiet.opacity(0.38)
  }
}

private struct TodayEmptyState: View {
  var body: some View {
    VStack(spacing: 16) {
      ZStack {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
          .fill(QingxuPalette.selected.opacity(0.52))
          .frame(width: 156, height: 106)
          .rotationEffect(.degrees(-8))

        Image(systemName: "sparkle")
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(QingxuPalette.accent.opacity(0.62))
          .offset(x: -69, y: -42)
        Image(systemName: "sparkle")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(QingxuPalette.quiet.opacity(0.7))
          .offset(x: 72, y: 35)

        Image(systemName: "calendar")
          .font(.system(size: 68, weight: .light))
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(QingxuPalette.accent)
          .rotationEffect(.degrees(4))
      }
      .frame(height: 126)

      VStack(spacing: 7) {
        Text("你这一天没有任务")
          .font(.title3.weight(.medium))
          .foregroundStyle(QingxuPalette.ink)
        Text("放松一下吧")
          .font(.subheadline)
          .foregroundStyle(QingxuPalette.quiet)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

private extension TaskPriority {
  var color: Color {
    switch self {
    case .high: QingxuPalette.danger
    case .medium: QingxuPalette.warning
    case .low: QingxuPalette.accent
    }
  }
}
#else
private extension TaskPriority {
  var color: Color { QingxuPalette.accent }
}
#endif

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
