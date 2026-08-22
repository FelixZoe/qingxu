import 'package:flutter/material.dart';

import '../models/task_item.dart';
import '../state/task_controller.dart';
import 'design_system.dart';

Future<bool> confirmTaskDeletion(BuildContext context, TaskItem task) async {
  final palette = QingxuPalette.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除这个任务？'),
          content: Text('“${task.title}”会从所有同步设备中删除。删除后仍可立即撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: palette.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ??
      false;
}

void showTaskDeletionUndo(
  ScaffoldMessengerState messenger,
  TaskController controller,
  TaskItem task,
) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('任务已删除'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => controller.restoreTask(task),
        ),
      ),
    );
}
