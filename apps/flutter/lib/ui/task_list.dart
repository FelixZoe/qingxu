import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/task_item.dart';
import '../state/task_controller.dart';

class TaskListPane extends StatefulWidget {
  const TaskListPane({required this.controller, required this.quickAddFocus, this.onMenu, super.key});

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
    final useCupertinoNavigation = defaultTargetPlatform == TargetPlatform.iOS;
    return ColoredBox(
      color: const Color(0xFFFBFAF7),
      child: Column(
        children: [
          if (useCupertinoNavigation)
            CupertinoNavigationBar(
              backgroundColor: const Color(0xF7FBFAF7),
              border: const Border(bottom: BorderSide(color: Color(0xFFEAE7E0), width: 0.5)),
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
                onPressed: () => widget.controller.addTask('新任务'),
                child: const Icon(CupertinoIcons.add, size: 23),
              ),
            )
          else
            Container(
            height: 122,
            padding: const EdgeInsets.fromLTRB(42, 27, 32, 18),
            alignment: Alignment.bottomLeft,
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEAE7E0)))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (widget.onMenu != null) ...[
                  IconButton(onPressed: widget.onMenu, icon: const Icon(Icons.menu_rounded)),
                  const SizedBox(width: 8),
                ],
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('我的任务', style: TextStyle(fontSize: 11, color: Color(0xFF85827A), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(widget.controller.currentTitle, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -1.2)),
                  ],
                ),
                const Spacer(),
                IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF8C887F))),
              ],
            ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(42, 22, 42, 60),
              children: [
                TextField(
                  focusNode: widget.quickAddFocus,
                  controller: addController,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    hintText: '新增任务',
                    hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF918D84)),
                    prefixIcon: const Icon(Icons.add_rounded, size: 21),
                    suffixText: 'Enter',
                    suffixStyle: const TextStyle(fontSize: 10, color: Color(0xFFA7A39A)),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFDEDBD3)), borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFD5B55D)), borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
                if (tasks.isEmpty)
                  const _EmptyState()
                else
                  DecoratedBox(
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEAE7E0)))),
                    child: Column(
                      children: [for (final task in tasks) _TaskRow(controller: widget.controller, task: task)],
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
  const _TaskRow({required this.controller, required this.task});

  final TaskController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedTaskId == task.id;
    final project = task.projectId == null
        ? null
        : TaskController.projects.where((value) => value.id == task.projectId).firstOrNull;
    return Material(
      color: selected ? const Color(0xFFF2F0EA) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => controller.selectTask(task.id),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 63),
          padding: const EdgeInsets.fromLTRB(8, 11, 10, 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEAE7E0)))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkResponse(
                onTap: () => controller.toggleTask(task),
                radius: 18,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: task.status == TaskStatus.completed ? const Color(0xFFE7B83F) : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: task.status == TaskStatus.completed ? const Color(0xFFE7B83F) : const Color(0xFFB9B5AB), width: 1.4),
                  ),
                  child: task.status == TaskStatus.completed ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: task.status == TaskStatus.completed ? const Color(0xFF99958C) : const Color(0xFF36342F),
                        decoration: task.status == TaskStatus.completed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (project != null || task.notes.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (project != null) ...[
                            Container(width: 6, height: 6, decoration: BoxDecoration(color: Color(project.color), shape: BoxShape.circle)),
                            const SizedBox(width: 4),
                            Text(project.title, style: const TextStyle(fontSize: 11, color: Color(0xFF99958C))),
                          ],
                          if (task.notes.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            const Icon(Icons.notes_rounded, size: 13, color: Color(0xFF99958C)),
                            const SizedBox(width: 3),
                            const Text('备注', style: TextStyle(fontSize: 11, color: Color(0xFF99958C))),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Column(
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 40, color: Color(0xFFAAA69D)),
            SizedBox(height: 15),
            Text('这里已经清空', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF66625B))),
            SizedBox(height: 5),
            Text('把注意力留给真正重要的事情。', style: TextStyle(fontSize: 12, color: Color(0xFFAAA69D))),
          ],
        ),
      );
}
