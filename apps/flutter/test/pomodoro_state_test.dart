import 'package:flutter_test/flutter_test.dart';
import 'package:qingxu/models/pomodoro_state.dart';

void main() {
  test('running pomodoro derives the same remaining time from endsAt', () {
    final state = PomodoroState(
      mode: PomodoroMode.focus,
      status: PomodoroStatus.running,
      remainingSeconds: 1500,
      completedFocusSessions: 2,
      endsAt: DateTime.utc(2026, 8, 22, 10, 25),
      updatedAt: DateTime.utc(2026, 8, 22, 10),
    );

    expect(state.remainingAt(DateTime.utc(2026, 8, 22, 10, 10)), 900);
    expect(state.remainingAt(DateTime.utc(2026, 8, 22, 10, 30)), 0);
    expect(PomodoroState.fromJson(state.toJson()).toJson(), state.toJson());
  });
}
