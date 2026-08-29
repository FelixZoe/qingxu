import 'package:flutter_test/flutter_test.dart';
import 'package:qingxu/models/pomodoro_state.dart';

void main() {
  test('fresh state uses an old timestamp so remote state wins first sync', () {
    expect(
      PomodoroState.initial().updatedAt,
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  });

  test('running pomodoro derives the same remaining time from endsAt', () {
    final state = PomodoroState(
      mode: PomodoroMode.focus,
      status: PomodoroStatus.running,
      remainingSeconds: 1500,
      completedFocusSessions: 2,
      phaseId: 'focus-20260822-1025',
      endsAt: DateTime.utc(2026, 8, 22, 10, 25),
      updatedAt: DateTime.utc(2026, 8, 22, 10),
    );

    expect(state.remainingAt(DateTime.utc(2026, 8, 22, 10, 10)), 900);
    expect(state.remainingAt(DateTime.utc(2026, 8, 22, 10, 30)), 0);
    expect(PomodoroState.fromJson(state.toJson()).toJson(), state.toJson());
  });

  test('custom durations round-trip and legacy data keeps defaults', () {
    final customized = PomodoroState.initial(DateTime.utc(2026, 8, 23))
        .copyWith(
          focusMinutes: 45,
          shortBreakMinutes: 8,
          longBreakMinutes: 24,
          dailyFocusGoal: 6,
          phaseId: 'focus-20260823',
        );

    final restored = PomodoroState.fromJson(customized.toJson());
    expect(restored.focusMinutes, 45);
    expect(restored.shortBreakMinutes, 8);
    expect(restored.longBreakMinutes, 24);
    expect(restored.dailyFocusGoal, 6);
    expect(restored.phaseId, 'focus-20260823');
    expect(
      restored.configuredDurationFor(PomodoroMode.longBreak),
      const Duration(minutes: 24),
    );

    final legacy = PomodoroState.fromJson({
      'mode': 'shortBreak',
      'status': 'idle',
      'updatedAt': '2026-08-23T00:00:00.000Z',
    });
    expect(legacy.focusMinutes, PomodoroState.defaultFocusMinutes);
    expect(legacy.shortBreakMinutes, PomodoroState.defaultShortBreakMinutes);
    expect(legacy.dailyFocusGoal, 4);
    expect(legacy.remainingSeconds, 5 * 60);
  });
}
