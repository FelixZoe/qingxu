import 'package:flutter/material.dart';

import '../models/task_item.dart';
import '../state/task_controller.dart';
import 'design_system.dart';
import 'task_actions.dart';

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
  bool _quickAddOpen = false;

  void submit(String title) {
    if (title.trim().isEmpty) return;
    final task = widget.controller.addTask(title);
    if (task == null) return;
    final destination = widget.controller.activeView == 'today' ? '今天' : '收集箱';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已添加到$destination'),
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: '编辑',
            onPressed: () => widget.controller.selectTask(task.id),
          ),
        ),
      );
  }

  Future<void> openQuickAdd() async {
    if (_quickAddOpen) return;
    _quickAddOpen = true;
    try {
      final title = await showDialog<String>(
        context: context,
        builder: (_) => const _QuickAddDialog(),
      );
      if (title != null && mounted) submit(title);
    } finally {
      _quickAddOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.controller.visibleTasks;
    final palette = QingxuPalette.of(context);
    if (qingxuIsDesktop) {
      return _DesktopTaskList(
        controller: widget.controller,
        tasks: tasks,
        quickAddFocus: widget.quickAddFocus,
        onQuickAdd: openQuickAdd,
      );
    }
    return ColoredBox(
      color: palette.canvas,
      child: Stack(
        children: [
          Column(
            children: [
              QingxuPageHeader(
                title: widget.controller.currentTitle,
                subtitle: _taskViewDescription(widget.controller.activeView),
                leading: widget.onMenu == null
                    ? null
                    : IconButton(
                        tooltip: '打开导航',
                        onPressed: widget.onMenu,
                        icon: const Icon(Icons.menu_rounded),
                      ),
                trailing: _TaskCount(count: tasks.length),
              ),
              Expanded(
                child: tasks.isEmpty
                    ? _EmptyState(view: widget.controller.activeView)
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final gutter = QingxuLayout.gutterFor(
                            constraints.maxWidth,
                          );
                          return ListView.separated(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.fromLTRB(
                              gutter,
                              10,
                              gutter,
                              104,
                            ),
                            itemCount: tasks.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              color: palette.border.withValues(alpha: 0.8),
                            ),
                            itemBuilder: (context, index) => Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: QingxuLayout.contentMaxWidth,
                                ),
                                child: _TaskRow(
                                  controller: widget.controller,
                                  task: tasks[index],
                                  showDivider: false,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          Positioned(
            right: QingxuLayout.mobileGutter,
            bottom: 22,
            child: Focus(
              focusNode: widget.quickAddFocus,
              onFocusChange: (focused) {
                if (focused) {
                  widget.quickAddFocus.unfocus();
                  openQuickAdd();
                }
              },
              child: FloatingActionButton(
                key: const ValueKey('quick-add-button'),
                tooltip: '新增任务',
                elevation: 0,
                highlightElevation: 0,
                backgroundColor: palette.accent,
                foregroundColor: Colors.white,
                onPressed: openQuickAdd,
                child: const Icon(Icons.add_rounded, size: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAddDialog extends StatefulWidget {
  const _QuickAddDialog();

  @override
  State<_QuickAddDialog> createState() => _QuickAddDialogState();
}

class _QuickAddDialogState extends State<_QuickAddDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final value = controller.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Dialog(
      backgroundColor: palette.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '新增任务',
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '先写下来，日期和项目可以稍后补充。',
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
              const SizedBox(height: 18),
              TextField(
                key: const ValueKey('quick-add-field'),
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(hintText: '要做什么？'),
                onSubmitted: (_) => submit(),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => FilledButton(
                      onPressed: value.text.trim().isEmpty ? null : submit,
                      child: const Text('添加任务'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopTaskList extends StatelessWidget {
  const _DesktopTaskList({
    required this.controller,
    required this.tasks,
    required this.quickAddFocus,
    required this.onQuickAdd,
  });

  final TaskController controller;
  final List<TaskItem> tasks;
  final FocusNode quickAddFocus;
  final VoidCallback onQuickAdd;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return ColoredBox(
      color: palette.canvas,
      child: Stack(
        children: [
          Column(
            children: [
              QingxuPageHeader(
                title: controller.currentTitle,
                subtitle: _taskViewDescription(controller.activeView),
                trailing: _TaskCount(count: tasks.length),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: QingxuLayout.contentMaxWidth,
                      ),
                      child: tasks.isEmpty
                          ? _EmptyState(view: controller.activeView)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    0,
                                    8,
                                    0,
                                    12,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        controller.activeView == 'today'
                                            ? '今日待办'
                                            : '待整理',
                                        style: TextStyle(
                                          color: palette.muted,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '单击打开详情',
                                        style: TextStyle(
                                          color: palette.faint,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.only(bottom: 92),
                                    itemCount: tasks.length,
                                    itemBuilder: (context, index) =>
                                        _DesktopTaskRow(
                                          controller: controller,
                                          task: tasks[index],
                                          first: index == 0,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            right: 30,
            bottom: 28,
            child: Focus(
              focusNode: quickAddFocus,
              onFocusChange: (focused) {
                if (focused) {
                  quickAddFocus.unfocus();
                  onQuickAdd();
                }
              },
              child: Tooltip(
                message: '新增任务  Ctrl+N',
                child: Material(
                  color: palette.accentStrong,
                  elevation: 5,
                  shadowColor: palette.accent.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(15),
                  child: InkWell(
                    key: const ValueKey('quick-add-button'),
                    borderRadius: BorderRadius.circular(15),
                    onTap: onQuickAdd,
                    child: const SizedBox(
                      width: 52,
                      height: 52,
                      child: Icon(
                        Icons.add_rounded,
                        size: 25,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopTaskRow extends StatefulWidget {
  const _DesktopTaskRow({
    required this.controller,
    required this.task,
    required this.first,
  });

  final TaskController controller;
  final TaskItem task;
  final bool first;

  @override
  State<_DesktopTaskRow> createState() => _DesktopTaskRowState();
}

class _DesktopTaskRowState extends State<_DesktopTaskRow> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final task = widget.task;
    final completed = task.status == TaskStatus.completed;
    final selected = widget.controller.selectedTaskId == task.id;
    final project = task.projectId == null
        ? null
        : TaskController.projects
              .where((value) => value.id == task.projectId)
              .firstOrNull;
    final scheduledAt = task.startAt?.toLocal();
    final showTime =
        scheduledAt != null && widget.controller.activeView == 'today';
    final highlighted = selected || hovered;

    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        duration: QingxuMotion.quick,
        decoration: BoxDecoration(
          color: highlighted
              ? palette.surfaceRaised.withValues(alpha: selected ? 1 : 0.68)
              : Colors.transparent,
          border: Border(
            top: widget.first
                ? BorderSide(color: palette.border)
                : BorderSide.none,
            bottom: BorderSide(color: palette.border),
            left: BorderSide(
              color: selected ? palette.accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => widget.controller.selectTask(task.id),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 68),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(15, 13, 10, 13),
                child: Row(
                  children: [
                    InkResponse(
                      onTap: () => widget.controller.toggleTask(task),
                      radius: 22,
                      child: AnimatedContainer(
                        duration: QingxuMotion.quick,
                        width: 21,
                        height: 21,
                        decoration: BoxDecoration(
                          color: completed
                              ? palette.accent
                              : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: completed ? palette.accent : palette.faint,
                            width: 1.4,
                          ),
                        ),
                        child: completed
                            ? const Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: completed ? palette.faint : palette.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              decoration: completed
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          if (project != null ||
                              task.notes.isNotEmpty ||
                              showTime) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 12,
                              children: [
                                if (showTime)
                                  _TaskMeta(
                                    icon: Icons.schedule_rounded,
                                    label: _TaskRow._formatTime(scheduledAt),
                                  ),
                                if (project != null)
                                  _ProjectMeta(project: project),
                                if (task.notes.isNotEmpty)
                                  const _TaskMeta(
                                    icon: Icons.notes_rounded,
                                    label: '有备注',
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    AnimatedOpacity(
                      duration: QingxuMotion.quick,
                      opacity: highlighted ? 1 : 0,
                      child: IconButton(
                        tooltip: '删除任务',
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          if (!await confirmTaskDeletion(context, task) ||
                              !context.mounted) {
                            return;
                          }
                          final messenger = ScaffoldMessenger.of(context);
                          widget.controller.deleteTask(task);
                          showTaskDeletionUndo(
                            messenger,
                            widget.controller,
                            task,
                          );
                        },
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: palette.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskCount extends StatelessWidget {
  const _TaskCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        child: Text(
          '$count 项',
          style: TextStyle(
            color: palette.accentStrong,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.controller,
    required this.task,
    required this.showDivider,
  });

  final TaskController controller;
  final TaskItem task;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final completed = task.status == TaskStatus.completed;
    final selected = controller.selectedTaskId == task.id;
    final project = task.projectId == null
        ? null
        : TaskController.projects
              .where((value) => value.id == task.projectId)
              .firstOrNull;
    final scheduledAt = task.startAt?.toLocal();
    final showTime = scheduledAt != null && controller.activeView == 'today';

    return Dismissible(
      key: ValueKey('task-${task.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => confirmTaskDeletion(context, task),
      onDismissed: (_) {
        controller.deleteTask(task);
        showTaskDeletionUndo(messenger, controller, task);
      },
      background: ColoredBox(
        color: palette.danger,
        child: const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 22),
            child: Icon(Icons.delete_outline_rounded, color: Colors.white),
          ),
        ),
      ),
      child: Material(
        color: selected
            ? palette.accentSoft.withValues(alpha: 0.46)
            : Colors.transparent,
        child: InkWell(
          onTap: () => controller.selectTask(task.id),
          child: Container(
            constraints: const BoxConstraints(minHeight: 70),
            padding: const EdgeInsets.fromLTRB(18, 13, 16, 13),
            decoration: BoxDecoration(
              border: showDivider
                  ? Border(bottom: BorderSide(color: palette.border))
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  button: true,
                  label: completed ? '标记为未完成' : '标记为已完成',
                  child: InkResponse(
                    onTap: () => controller.toggleTask(task),
                    radius: 24,
                    child: AnimatedContainer(
                      duration: QingxuMotion.quick,
                      width: 23,
                      height: 23,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        color: completed ? palette.accent : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: completed ? palette.accent : palette.faint,
                          width: 1.5,
                        ),
                      ),
                      child: completed
                          ? const Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: completed ? palette.faint : palette.ink,
                          fontSize: 15,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          decoration: completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (project != null ||
                          task.notes.isNotEmpty ||
                          showTime) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          children: [
                            if (showTime)
                              _TaskMeta(
                                icon: Icons.schedule_rounded,
                                label: _formatTime(scheduledAt),
                              ),
                            if (project != null) _ProjectMeta(project: project),
                            if (task.notes.isNotEmpty)
                              const _TaskMeta(
                                icon: Icons.notes_rounded,
                                label: '有备注',
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: palette.faint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
  }
}

class _TaskMeta extends StatelessWidget {
  const _TaskMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: palette.faint),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11.5, color: palette.muted)),
      ],
    );
  }
}

class _ProjectMeta extends StatelessWidget {
  const _ProjectMeta({required this.project});

  final ProjectItem project;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: Color(project.color),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          project.title,
          style: TextStyle(fontSize: 11.5, color: palette.muted),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.view});

  final String view;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final (icon, title, message) = switch (view) {
      'inbox' => (Icons.inbox_outlined, '收集箱空空的', '先把脑海里的事情放下来。'),
      _ => (Icons.check_rounded, '今天没有待办', '留一点空白，也是一种完成。'),
    };
    return Center(
      child: Transform.translate(
        offset: const Offset(0, -28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: palette.accent),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(message, style: TextStyle(fontSize: 13, color: palette.muted)),
          ],
        ),
      ),
    );
  }
}

String _taskViewDescription(String view) => switch (view) {
  'inbox' => '随手收集，稍后再整理',
  'today' => _todayDescription(),
  _ => '专注当前清单',
};

String _todayDescription() {
  const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
  final now = DateTime.now();
  return '${now.month} 月 ${now.day} 日 · ${weekdays[now.weekday - 1]}';
}
