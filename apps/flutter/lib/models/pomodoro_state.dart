enum PomodoroMode { focus, shortBreak, longBreak }

enum PomodoroStatus { idle, running, paused }

class PomodoroState {
  const PomodoroState({
    required this.mode,
    required this.status,
    required this.remainingSeconds,
    required this.completedFocusSessions,
    required this.updatedAt,
    this.endsAt,
  });

  factory PomodoroState.initial([DateTime? now]) => PomodoroState(
    mode: PomodoroMode.focus,
    status: PomodoroStatus.idle,
    remainingSeconds: durationFor(PomodoroMode.focus).inSeconds,
    completedFocusSessions: 0,
    updatedAt: (now ?? DateTime.now()).toUtc(),
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
    return PomodoroState(
      mode: mode,
      status: status,
      remainingSeconds:
          (json['remainingSeconds'] as num?)?.toInt().clamp(0, 24 * 3600) ??
          durationFor(mode).inSeconds,
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
  final DateTime? endsAt;
  final DateTime updatedAt;

  static Duration durationFor(PomodoroMode mode) => switch (mode) {
    PomodoroMode.focus => const Duration(minutes: 25),
    PomodoroMode.shortBreak => const Duration(minutes: 5),
    PomodoroMode.longBreak => const Duration(minutes: 15),
  };

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
    DateTime? endsAt,
    bool clearEndsAt = false,
    DateTime? updatedAt,
  }) => PomodoroState(
    mode: mode ?? this.mode,
    status: status ?? this.status,
    remainingSeconds: remainingSeconds ?? this.remainingSeconds,
    completedFocusSessions:
        completedFocusSessions ?? this.completedFocusSessions,
    endsAt: clearEndsAt ? null : endsAt ?? this.endsAt,
    updatedAt: (updatedAt ?? this.updatedAt).toUtc(),
  );

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'status': status.name,
    'remainingSeconds': remainingSeconds,
    'completedFocusSessions': completedFocusSessions,
    'endsAt': endsAt?.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}
