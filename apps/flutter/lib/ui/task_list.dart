import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../models/task_item.dart';
import '../state/task_controller.dart';
import 'design_system.dart';

class TaskListPane extends StatefulWidget {
  const TaskListPane({
    required this.controller,
    required this.quickAddFocus,
    this.onMenu,
    super.key,
  });

  final TaskController controller;
  final FocusNode quickAddFocus;
  final VoidCallback? onMenu;

  @override
  State<TaskListPane> createState() => _TaskListPaneState();
}

class _TaskListPaneState extends State<TaskListPane> {
  final addController = TextEditingController();

  @override
  void dispose() {
    addController.dispose();
    super.dispose();
  }

  void submit() {
    widget.controller.addTask(addController.text);
    addController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.controller.visibleTasks;
    final palette = QingxuPalette.of(context);
    final useCupertinoNavigation = defaultTargetPlatform == TargetPlatform.iOS;
    return ColoredBox(
      color: palette.surface,
      child: Column(
        children: [
          if (useCupertinoNavigation)
            CupertinoNavigationBar(
              backgroundColor: palette.surface.withValues(alpha: 0.97),
              border: Border(
                bottom: BorderSide(color: palette.border, width: 0.5),
              ),
              leading: widget.onMenu == null
                  ? null
                  : CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: widget.onMenu,
                      child: const Icon(CupertinoIcons.sidebar_left, size: 22),
                    ),
              middle: Text(widget.controller.currentTitle),
              trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: widget.quickAddFocus.requestFocus,
                child: const Icon(CupertinoIcons.add, size: 23),
              ),
            )
          else
            Container(
              height: 122,
              padding: const EdgeInsets.fromLTRB(42, 27, 32, 18),
              alignment: Alignment.bottomLeft,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: palette.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.onMenu != null) ...[
                    IconButton(
                      onPressed: widget.onMenu,
                      icon: const Icon(Icons.menu_rounded),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _taskViewDescription(widget.controller.activeView),
                        style: TextStyle(
                          fontSize: 11,
                          color: palette.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.controller.currentTitle,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.2,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.accentSoft,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      child: Text(
                        '${tasks.length} 项待办',
                        style: TextStyle(
                          color: palette.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(42, 22, 42, 14),
                  sliver: SliverToBoxAdapter(
                    child: FTextField(
                      control: FTextFieldControl.managed(
                        controller: addController,
                      ),
                      focusNode: widget.quickAddFocus,
                      hint: '新增任务，按 Enter 保存',
                      textInputAction: TextInputAction.done,
                      onSubmit: (_) => submit(),
                      clearable: (value) => value.text.isNotEmpty,
                      prefixBuilder: (context, style, states) =>
                          const Icon(FLucideIcons.plus, size: 18),
                      suffixBuilder: (context, style, states) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          'Enter',
                          style: TextStyle(fontSize: 10, color: palette.faint),
                        ),
                      ),
                    ),
                  ),
                ),
                if (tasks.isEmpty)
                  SliverToBoxAdapter(
                    child: _EmptyState(view: widget.controller.activeView),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(42, 0, 42, 60),
                    sliver: SliverList.builder(
                      itemCount: tasks.length,
                      itemBuilder: (context, index) => _TaskRow(
                        controller: widget.controller,
                        task: tasks[index],
                        showTopBorder: index == 0,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.controller,
    required this.task,
    required this.showTopBorder,
  });

  final TaskController controller;
  final TaskItem task;
  final bool showTopBorder;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final selected = controller.selectedTaskId == task.id;
    final project = task.projectId == null
        ? null
        : TaskController.projects
              .where((value) => value.id == task.projectId)
              .firstOrNull;
    final scheduledAt = task.startAt?.toLocal();
    final showTime = scheduledAt != null && controller.activeView == 'today';
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: showTopBorder
              ? BorderSide(color: palette.border)
              : BorderSide.none,
          bottom: BorderSide(color: palette.border),
        ),
      ),
      child: FItem(
        selected: selected,
        onPress: () => controller.selectTask(task.id),
        prefix: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => controller.toggleTask(task),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 21,
            height: 21,
            decoration: BoxDecoration(
              color: task.status == TaskStatus.completed
                  ? palette.accent
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: task.status == TaskStatus.completed
                    ? palette.accent
                    : palette.faint,
                width: 1.4,
              ),
            ),
            child: task.status == TaskStatus.completed
                ? const Icon(FLucideIcons.check, size: 13, color: Colors.white)
                : null,
          ),
        ),
        title: Text(
          task.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            color: task.status == TaskStatus.completed
                ? palette.faint
                : palette.ink,
            decoration: task.status == TaskStatus.completed
                ? TextDecoration.lineThrough
                : null,
          ),
        ),
        subtitle: project == null && task.notes.isEmpty && !showTime
            ? null
            : Row(
                children: [
                  if (showTime) ...[
                    Icon(
                      Icons.schedule_rounded,
                      size: 12,
                      color: palette.faint,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _formatTime(scheduledAt),
                      style: TextStyle(fontSize: 11, color: palette.faint),
                    ),
                  ],
                  if (project != null) ...[
                    if (showTime) const SizedBox(width: 10),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Color(project.color),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      project.title,
                      style: TextStyle(fontSize: 11, color: palette.faint),
                    ),
                  ],
                  if (task.notes.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Icon(
                      FLucideIcons.notebookPen,
                      size: 12,
                      color: palette.faint,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '备注',
                      style: TextStyle(fontSize: 11, color: palette.faint),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  static String _formatTime(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.view});

  final String view;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final (icon, title, message) = switch (view) {
      'inbox' => (Icons.inbox_outlined, '收集箱是空的', '想到什么就记下来，不必现在分类。'),
      _ => (Icons.check_circle_outline_rounded, '今天已经清空', '把注意力留给真正重要的事情。'),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Icon(icon, size: 30, color: palette.accent),
            ),
          ),
          const SizedBox(height: 15),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 5),
          Text(message, style: TextStyle(fontSize: 12, color: palette.faint)),
        ],
      ),
    );
  }
}

String _taskViewDescription(String view) => switch (view) {
  'inbox' => '随手记录，稍后整理',
  'today' => '专注今天真正重要的事',
  _ => '我的任务',
};
