import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingxu/state/task_controller.dart';
import 'package:qingxu/ui/pomodoro_page.dart';

void main() {
  testWidgets('pomodoro timer starts, pauses, and resets', (tester) async {
    final controller = TaskController();
    await tester.pumpWidget(
      MaterialApp(home: PomodoroPage(controller: controller)),
    );

    expect(find.text('25:00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pomodoro-toggle')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('暂停'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pomodoro-toggle')));
    await tester.pump();
    expect(find.text('开始专注'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('pomodoro durations can be customized', (tester) async {
    final controller = TaskController();
    await tester.pumpWidget(
      MaterialApp(home: PomodoroPage(controller: controller)),
    );

    await tester.tap(find.byKey(const ValueKey('pomodoro-duration-settings')));
    await tester.pumpAndSettle();
    expect(find.text('计时时长'), findsOneWidget);

    for (var index = 0; index < 5; index++) {
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('save-pomodoro-durations')));
    await tester.pumpAndSettle();

    expect(find.text('30:00'), findsOneWidget);
    expect(find.text('专注 30'), findsOneWidget);
    expect(controller.pomodoro.focusMinutes, 30);
    controller.dispose();
  });
}
