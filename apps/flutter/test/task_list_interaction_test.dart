import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingxu/state/task_controller.dart';
import 'package:qingxu/ui/task_list.dart';

void main() {
  testWidgets('quick add stays in the list and offers explicit editing', (
    tester,
  ) async {
    final controller = TaskController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskListPane(
            controller: controller,
            quickAddFocus: FocusNode(),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('quick-add-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('quick-add-field')),
      '连续新增不会跳走',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('连续新增不会跳走'), findsOneWidget);
    expect(find.text('已添加到今天'), findsOneWidget);
    expect(controller.selectedTaskId, isNull);
  });
}
