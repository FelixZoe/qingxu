import 'package:flutter/material.dart';

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
    if (addController.text.trim().isEmpty) return;
    widget.controller.addTask(addController.text);
    addController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.controller.visibleTasks;
    final palette = QingxuPalette.of(context);
    final isToday = widget.controller.activeView == 'today';
    return ColoredBox(
      color: palette.canvas,
      child: Column(
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
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final gutter = QingxuLayout.gutterFor(
                      constraints.crossAxisExtent,
                    );
                    return SliverPadding(
                      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 14),
                      sliver: SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: QingxuLayout.contentMaxWidth,
                            ),
                            child: _QuickAdd(
                              controller: addController,
                              focusNode: widget.quickAddFocus,
                              onSubmit: submit,
                              isToday: isToday,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (tasks.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(view: widget.controller.activeView),
                  )
                else
                  SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final gutter = QingxuLayout.gutterFor(
                        constraints.crossAxisExtent,
                      );
                      return SliverPadding(
                        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 48),
                        sliver: SliverToBoxAdapter(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: QingxuLayout.contentMaxWidth,
                              ),
                              child: QingxuSurface(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    QingxuLayout.sectionRadius,
                                  ),
                                  child: Column(
                                    children: [
                                      for (var index = 0;
                                          index < tasks.length;
                                          index++)
                                        _TaskRow(
                                          controller: widget.controller,
                                          task: tasks[index],
                                          showDivider: index != tasks.length - 1,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
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

class _QuickAdd extends StatelessWidget {
  const _QuickAdd({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.isToday,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return QingxuSurface(
      radius: 16,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => onSubmit(),
        style: TextStyle(color: palette.ink, fontSize: 15),
        decoration: InputDecoration(
          hintText: isToday ? '添加今天要完成的事' : '快速记录一个想法或任务',
          hintStyle: TextStyle(color: palette.faint, fontSize: 15),
          prefixIcon: Icon(Icons.add_rounded, color: palette.accent, size: 22),
          suffixIcon: IconButton(
            tooltip: '添加任务',
            onPressed: onSubmit,
            icon: Icon(Icons.arrow_upward_rounded, color: palette.accent),
          ),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
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
    final completed = task.status == TaskStatus.completed;
    final selected = controller.selectedTaskId == task.id;
    final project = task.projectId == null
        ? null
        : TaskController.projects
              .where((value) => value.id == task.projectId)
              .firstOrNull;
    final scheduledAt = task.startAt?.toLocal();
    final showTime = scheduledAt != null && controller.activeView == 'today';

    return Material(
      color: selected ? palette.accentSoft.withValues(alpha: 0.46) : Colors.transparent,
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
                        ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
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
                        decoration: completed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (project != null || task.notes.isNotEmpty || showTime) ...[
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
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, size: 20, color: palette.faint),
            ],
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
        Text(project.title, style: TextStyle(fontSize: 11.5, color: palette.muted)),
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
