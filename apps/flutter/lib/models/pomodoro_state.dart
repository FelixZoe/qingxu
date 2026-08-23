enum PomodoroMode { focus, shortBreak, longBreak }

enum PomodoroStatus { idle, running, paused }

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
    this.endsAt,
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
    return PomodoroState(
      mode: mode,
      status: status,
      focusMinutes: focusMinutes,
      shortBreakMinutes: shortBreakMinutes,
      longBreakMinutes: longBreakMinutes,
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
  final DateTime? endsAt;
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
    DateTime? endsAt,
    bool clearEndsAt = false,
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
    endsAt: clearEndsAt ? null : endsAt ?? this.endsAt,
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
    'endsAt': endsAt?.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}
