import Combine
import Foundation

enum SyncPhase: Equatable {
  case localOnly
  case syncing
  case synced(Date)
  case failed(String)

  var title: String {
    switch self {
    case .localOnly: "仅保存在本地"
    case .syncing: "正在同步…"
    case .synced: "已同步"
    case .failed: "同步失败"
    }
  }
}

@MainActor
final class AppStore: ObservableObject {
  @Published private(set) var tasks: [TaskItem] = []
  @Published private(set) var pomodoro = PomodoroState.initial()
  @Published var syncSettings = SyncSettings()
  @Published private(set) var syncPhase: SyncPhase = .localOnly
  @Published private(set) var displayedRemainingSeconds = 25 * 60

  private let client = SyncClient()
  private var clockTask: Task<Void, Never>?
  private var pendingSync: Task<Void, Never>?
  private var serverOffset: TimeInterval = 0
  private var lastAutomaticSync = Date.distantPast
  private var isSyncing = false

  init() {
    tasks = QingxuFiles.load([TaskItem].self, name: "tasks.json") ?? []
    pomodoro = QingxuFiles.load(PomodoroState.self, name: "pomodoro.json") ?? .initial()
    syncSettings = QingxuFiles.load(SyncSettings.self, name: "sync.json") ?? SyncSettings()
    syncSettings.token = SecureSyncToken.read()
    if syncSettings.deviceName.isEmpty {
      syncSettings.deviceName = ProcessInfo.processInfo.hostName
    }
    displayedRemainingSeconds = pomodoro.remaining(at: estimatedNow)
    refreshSystemSurfaces()
    startClock()
    if syncSettings.autoSync && syncSettings.isConfigured {
      scheduleSync(delay: .milliseconds(350))
    }
  }

  deinit {
    clockTask?.cancel()
    pendingSync?.cancel()
  }

  var inboxTasks: [TaskItem] {
    visibleTasks.filter { $0.status == .open }.sorted(by: taskOrder)
  }

  var todayTasks: [TaskItem] {
    let calendar = Calendar.autoupdatingCurrent
    return visibleTasks.filter { task in
      guard task.status == .open else { return false }
      return [task.startAt, task.deadlineAt]
        .compactMap { $0 }
        .contains { calendar.isDateInToday($0) }
    }.sorted(by: taskOrder)
  }

  var completedTasks: [TaskItem] {
    visibleTasks.filter { $0.status == .completed }.sorted {
      ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt)
    }
  }

  var estimatedNow: Date { Date().addingTimeInterval(serverOffset) }

  @discardableResult
  func addTask(title: String, notes: String = "", forToday: Bool = false) -> TaskItem? {
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTitle.isEmpty else { return nil }
    let now = estimatedNow
    let task = TaskItem(
      id: UUID().uuidString,
      title: cleanTitle,
      notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
      status: .open,
      projectId: nil,
      startAt: forToday ? Calendar.autoupdatingCurrent.startOfDay(for: now) : nil,
      deadlineAt: nil,
      completedAt: nil,
      order: Int64(now.timeIntervalSince1970 * 1_000),
      createdAt: now,
      updatedAt: now,
      deletedAt: nil
    )
    tasks.append(task)
    changed()
    return task
  }

  func updateTask(_ task: TaskItem) {
    guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
    var updated = task
    updated.title = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
    updated.updatedAt = estimatedNow
    tasks[index] = updated
    changed()
  }

  func toggleTask(_ task: TaskItem) {
    guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
    let now = estimatedNow
    tasks[index].status = tasks[index].status == .completed ? .open : .completed
    tasks[index].completedAt = tasks[index].status == .completed ? now : nil
    tasks[index].updatedAt = now
    changed()
  }

  func deleteTask(_ task: TaskItem) {
    guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
    let now = estimatedNow
    tasks[index].deletedAt = now
    tasks[index].updatedAt = now
    changed()
  }

  func restoreTask(_ task: TaskItem) {
    guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
    tasks[index].deletedAt = nil
    tasks[index].updatedAt = estimatedNow
    changed()
  }

  func setPomodoroMode(_ mode: PomodoroMode) {
    pomodoro.mode = mode
    pomodoro.status = .idle
    pomodoro.endsAt = nil
    pomodoro.remainingSeconds = pomodoro.duration(for: mode)
    pomodoro.updatedAt = estimatedNow
    pomodoroChanged()
  }

  func togglePomodoro() {
    let now = estimatedNow
    if pomodoro.status == .running {
      pomodoro.remainingSeconds = pomodoro.remaining(at: now)
      pomodoro.endsAt = nil
      pomodoro.status = .paused
    } else {
      let remaining = max(1, pomodoro.remainingSeconds)
      pomodoro.endsAt = now.addingTimeInterval(TimeInterval(remaining))
      pomodoro.status = .running
    }
    pomodoro.updatedAt = now
    pomodoroChanged()
  }

  func resetPomodoro() {
    pomodoro.status = .idle
    pomodoro.endsAt = nil
    pomodoro.remainingSeconds = pomodoro.duration(for: pomodoro.mode)
    pomodoro.updatedAt = estimatedNow
    pomodoroChanged()
  }

  func updateDurations(focus: Int, shortBreak: Int, longBreak: Int) {
    pomodoro.focusMinutes = min(180, max(1, focus))
    pomodoro.shortBreakMinutes = min(60, max(1, shortBreak))
    pomodoro.longBreakMinutes = min(120, max(1, longBreak))
    if pomodoro.status != .running {
      pomodoro.remainingSeconds = pomodoro.duration(for: pomodoro.mode)
    }
    pomodoro.updatedAt = estimatedNow
    pomodoroChanged()
  }

  func saveSyncSettings(_ settings: SyncSettings) throws {
    syncSettings = settings
    try SecureSyncToken.write(settings.token)
    try QingxuFiles.save(settings, name: "sync.json")
    syncPhase = settings.autoSync ? .syncing : .localOnly
    if settings.autoSync { scheduleSync(delay: .milliseconds(100)) }
  }

  func testConnection(_ settings: SyncSettings) async throws {
    try await client.testConnection(settings: settings)
  }

  func syncNow() async {
    guard syncSettings.isConfigured else {
      syncPhase = .localOnly
      return
    }
    guard !isSyncing else { return }
    isSyncing = true
    defer { isSyncing = false }
    syncPhase = .syncing
    do {
      let response = try await client.sync(
        settings: syncSettings,
        tasks: tasks,
        pomodoro: pomodoro
      )
      serverOffset = response.serverTime.timeIntervalSinceNow
      tasks = response.tasks
      if let remote = response.pomodoro, remote.updatedAt >= pomodoro.updatedAt {
        pomodoro = remote
      }
      try persistAll()
      displayedRemainingSeconds = pomodoro.remaining(at: estimatedNow)
      syncPhase = .synced(.now)
      lastAutomaticSync = .now
      refreshSystemSurfaces()
    } catch {
      syncPhase = .failed(error.localizedDescription)
    }
  }

  private var visibleTasks: [TaskItem] { tasks.filter { $0.deletedAt == nil } }

  private func taskOrder(_ left: TaskItem, _ right: TaskItem) -> Bool {
    if left.order == right.order { return left.createdAt < right.createdAt }
    return left.order < right.order
  }

  private func changed() {
    try? QingxuFiles.save(tasks, name: "tasks.json")
    refreshSystemSurfaces()
    scheduleSync()
  }

  private func pomodoroChanged() {
    displayedRemainingSeconds = pomodoro.remaining(at: estimatedNow)
    try? QingxuFiles.save(pomodoro, name: "pomodoro.json")
    refreshSystemSurfaces()
    scheduleSync(delay: .milliseconds(250))
  }

  private func persistAll() throws {
    try QingxuFiles.save(tasks, name: "tasks.json")
    try QingxuFiles.save(pomodoro, name: "pomodoro.json")
  }

  private func scheduleSync(delay: Duration = .milliseconds(700)) {
    guard syncSettings.autoSync && syncSettings.isConfigured else { return }
    pendingSync?.cancel()
    pendingSync = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      await self?.syncNow()
    }
  }

  private func startClock() {
    clockTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard let self else { return }
        self.tick()
      }
    }
  }

  private func tick() {
    displayedRemainingSeconds = pomodoro.remaining(at: estimatedNow)
    if pomodoro.status == .running && displayedRemainingSeconds == 0 {
      advancePomodoro()
    }
    let interval: TimeInterval = pomodoro.status == .running ? 3 : 30
    if syncSettings.autoSync,
       syncSettings.isConfigured,
       !isSyncing,
       Date().timeIntervalSince(lastAutomaticSync) >= interval {
      lastAutomaticSync = .now
      Task { await syncNow() }
    }
  }

  private func advancePomodoro() {
    if pomodoro.mode == .focus {
      pomodoro.completedFocusSessions += 1
      pomodoro.mode = pomodoro.completedFocusSessions.isMultiple(of: 4) ? .longBreak : .shortBreak
    } else {
      pomodoro.mode = .focus
    }
    pomodoro.status = .idle
    pomodoro.endsAt = nil
    pomodoro.remainingSeconds = pomodoro.duration(for: pomodoro.mode)
    pomodoro.updatedAt = estimatedNow
    pomodoroChanged()
  }

  private func refreshSystemSurfaces() {
    SystemFeatures.refresh(
      pomodoro: pomodoro,
      todayTaskCount: todayTasks.count
    )
  }
}
