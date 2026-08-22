import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingxu/state/task_controller.dart';
import 'package:qingxu/ui/design_system.dart';
import 'package:qingxu/ui/pomodoro_page.dart';
import 'package:qingxu/ui/sync_settings_page.dart';
import 'package:qingxu/ui/task_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) => MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      extensions: const [QingxuPalette.light],
    ),
    home: Scaffold(body: SafeArea(bottom: false, child: child)),
  );

  Future<void> usePhoneSize(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('task list fits a compact phone without overflow', (tester) async {
    await usePhoneSize(tester);
    final controller = TaskController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        TaskListPane(
          controller: controller,
          quickAddFocus: FocusNode(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('今天'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pomodoro fits a compact phone without overflow', (tester) async {
    await usePhoneSize(tester);
    final controller = TaskController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(PomodoroPage(controller: controller)));
    await tester.pump();
    expect(find.text('25:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings uses readable mobile groups without overflow', (tester) async {
    await usePhoneSize(tester);
    final controller = TaskController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        SyncSettingsPage(
          controller: controller,
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('米白蓝'), findsOneWidget);
    expect(find.text('黑绿'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
