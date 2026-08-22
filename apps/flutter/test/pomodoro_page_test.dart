import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingxu/ui/pomodoro_page.dart';

void main() {
  testWidgets('pomodoro timer starts, pauses, and resets', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PomodoroPage()));

    expect(find.text('25:00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pomodoro-toggle')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('24:59'), findsOneWidget);
    expect(find.text('暂停'), findsOneWidget);

    await tester.tap(find.text('暂停'));
    await tester.tap(find.text('重置'));
    await tester.pump();
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('开始'), findsOneWidget);
  });
}
