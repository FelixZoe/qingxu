enum PomodoroMode { focus, shortBreak, longBreak }

enum PomodoroStatus { idle, running, paused }

enum PomodoroTimerDirection { countdown, countUp }

class FocusSessionRecord {
  const FocusSessionRecord({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    required this.completed,
  });

  factory FocusSessionRecord.fromJson(Map<String, Object?> json) {
    final endedAt = DateTime.tryParse(json['endedAt'] as String? ?? '')?.toUtc();
    final duration = (json['durationSeconds'] as num?)?.toInt().clamp(0, 24 * 3600) ?? 0;
    return FocusSessionRecord(
      id: json['id'] as String? ?? '',
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '')?.toUtc() ??
          (endedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
              .subtract(Duration(seconds: duration)),
      endedAt: endedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      durationSeconds: duration,
      completed: json['completed'] as bool? ?? false,
    );
  }

  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSeconds;
  final bool completed;

  Map<String, Object?> toJson() => {
    'id': id,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt.toUtc().toIso8601String(),
    'durationSeconds': durationSeconds,
    'completed': completed,
  };
}

class PomodoroState {
  const PomodoroState({
    required this.mode,
    required this.status,
    required this.remainingSeconds,
    required this.completedFocusSessions,
    required this.updatedAt,
    this.focusMinutes = defaultFocusMinutes,
    this.shortBreakMinutes = defaultShortBreakMinutes,
    this.longBreakMinutes = defaultLongBreakMinutes,
    this.longBreakEvery = 4,
    this.timerDirection = PomodoroTimerDirection.countdown,
    this.endsAt,
    this.startedAt,
    this.focusHistory = const [],
  });

  static const defaultFocusMinutes = 25;
  static const defaultShortBreakMinutes = 5;
  static const defaultLongBreakMinutes = 15;

  factory PomodoroState.initial([DateTime? now]) => PomodoroState(
    mode: PomodoroMode.focus,
    status: PomodoroStatus.idle,
    remainingSeconds: durationFor(PomodoroMode.focus).inSeconds,
    completedFocusSessions: 0,
    updatedAt: (now ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
        .toUtc(),
  );

  factory PomodoroState.fromJson(Map<String, Object?> json) {
    final mode = PomodoroMode.values.firstWhere(
      (value) => value.name == json['mode'],
      orElse: () => PomodoroMode.focus,
    );
    final status = PomodoroStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => PomodoroStatus.idle,
    );
    final focusMinutes = _readMinutes(
      json['focusMinutes'],
      defaultValue: defaultFocusMinutes,
      max: 180,
    );
    final shortBreakMinutes = _readMinutes(
      json['shortBreakMinutes'],
      defaultValue: defaultShortBreakMinutes,
      max: 60,
    );
    final longBreakMinutes = _readMinutes(
      json['longBreakMinutes'],
      defaultValue: defaultLongBreakMinutes,
      max: 120,
    );
    final timerDirection = PomodoroTimerDirection.values.firstWhere(
      (value) => value.name == json['timerDirection'],
      orElse: () => PomodoroTimerDirection.countdown,
    );
    return PomodoroState(
      mode: mode,
      status: status,
      focusMinutes: focusMinutes,
      shortBreakMinutes: shortBreakMinutes,
      longBreakMinutes: longBreakMinutes,
      longBreakEvery: (json['longBreakEvery'] as num?)?.toInt().clamp(2, 12) ?? 4,
      timerDirection: timerDirection,
      remainingSeconds:
          (json['remainingSeconds'] as num?)?.toInt().clamp(0, 24 * 3600) ??
          _durationFor(
            mode,
            focusMinutes,
            shortBreakMinutes,
            longBreakMinutes,
          ).inSeconds,
      completedFocusSessions:
          (json['completedFocusSessions'] as num?)?.toInt().clamp(0, 1000000) ??
          0,
      endsAt: json['endsAt'] is String
          ? DateTime.tryParse(json['endsAt']! as String)?.toUtc()
          : null,
      startedAt: json['startedAt'] is String
          ? DateTime.tryParse(json['startedAt']! as String)?.toUtc()
          : null,
      focusHistory: (json['focusHistory'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(FocusSessionRecord.fromJson)
          .toList(growable: false),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final PomodoroMode mode;
  final PomodoroStatus status;
  final int remainingSeconds;
  final int completedFocusSessions;
  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;
  final int longBreakEvery;
  final PomodoroTimerDirection timerDirection;
  final DateTime? endsAt;
  final DateTime? startedAt;
  final List<FocusSessionRecord> focusHistory;
  final DateTime updatedAt;

  static Duration durationFor(PomodoroMode mode) => switch (mode) {
    PomodoroMode.focus => const Duration(minutes: defaultFocusMinutes),
    PomodoroMode.shortBreak => const Duration(
      minutes: defaultShortBreakMinutes,
    ),
    PomodoroMode.longBreak => const Duration(minutes: defaultLongBreakMinutes),
  };

  Duration configuredDurationFor(PomodoroMode mode) =>
      _durationFor(mode, focusMinutes, shortBreakMinutes, longBreakMinutes);

  static Duration _durationFor(
    PomodoroMode mode,
    int focusMinutes,
    int shortBreakMinutes,
    int longBreakMinutes,
  ) => switch (mode) {
    PomodoroMode.focus => Duration(minutes: focusMinutes),
    PomodoroMode.shortBreak => Duration(minutes: shortBreakMinutes),
    PomodoroMode.longBreak => Duration(minutes: longBreakMinutes),
  };

  static int _readMinutes(
    Object? value, {
    required int defaultValue,
    required int max,
  }) => (value as num?)?.toInt().clamp(1, max) ?? defaultValue;

  int remainingAt(DateTime serverNow) {
    if (timerDirection == PomodoroTimerDirection.countUp) {
      if (status != PomodoroStatus.running || startedAt == null) {
        return remainingSeconds;
      }
      return (remainingSeconds + serverNow.toUtc().difference(startedAt!).inSeconds)
          .clamp(0, 24 * 3600);
    }
    if (status != PomodoroStatus.running || endsAt == null) {
      return remainingSeconds;
    }
    return (endsAt!.difference(serverNow.toUtc()).inMilliseconds / 1000)
        .ceil()
        .clamp(0, 24 * 3600);
  }

  PomodoroState copyWith({
    PomodoroMode? mode,
    PomodoroStatus? status,
    int? remainingSeconds,
    int? completedFocusSessions,
    int? focusMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? longBreakEvery,
    PomodoroTimerDirection? timerDirection,
    DateTime? endsAt,
    bool clearEndsAt = false,
    DateTime? startedAt,
    bool clearStartedAt = false,
    List<FocusSessionRecord>? focusHistory,
    DateTime? updatedAt,
  }) => PomodoroState(
    mode: mode ?? this.mode,
    status: status ?? this.status,
    remainingSeconds: remainingSeconds ?? this.remainingSeconds,
    completedFocusSessions:
        completedFocusSessions ?? this.completedFocusSessions,
    focusMinutes: focusMinutes ?? this.focusMinutes,
    shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
    longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
    longBreakEvery: longBreakEvery ?? this.longBreakEvery,
    timerDirection: timerDirection ?? this.timerDirection,
    endsAt: clearEndsAt ? null : endsAt ?? this.endsAt,
    startedAt: clearStartedAt ? null : startedAt ?? this.startedAt,
    focusHistory: focusHistory ?? this.focusHistory,
    updatedAt: (updatedAt ?? this.updatedAt).toUtc(),
  );

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'status': status.name,
    'remainingSeconds': remainingSeconds,
    'completedFocusSessions': completedFocusSessions,
    'focusMinutes': focusMinutes,
    'shortBreakMinutes': shortBreakMinutes,
    'longBreakMinutes': longBreakMinutes,
    'longBreakEvery': longBreakEvery,
    'timerDirection': timerDirection.name,
    'endsAt': endsAt?.toUtc().toIso8601String(),
    'startedAt': startedAt?.toUtc().toIso8601String(),
    'focusHistory': focusHistory.map((record) => record.toJson()).toList(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}
