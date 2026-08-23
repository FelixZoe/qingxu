import 'package:flutter/material.dart';

import '../models/task_item.dart';
import '../state/task_controller.dart';
import 'design_system.dart';
import 'task_actions.dart';

class TaskEditor extends StatefulWidget {
  const TaskEditor({required this.controller, required this.task, super.key});

  final TaskController controller;
  final TaskItem task;

  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  late final TextEditingController titleController;
  late final TextEditingController notesController;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.task.title);
    notesController = TextEditingController(text: widget.task.notes);
  }

  @override
  void dispose() {
    titleController.dispose();
    notesController.dispose();
    super.dispose();
  }

  void saveText() {
    final title = titleController.text.trim();
    widget.controller.updateTask(
      widget.task.copyWith(
        title: title.isEmpty ? widget.task.title : title,
        notes: notesController.text,
      ),
    );
  }

  Future<void> pickStartDate() async {
    await _pickDate(isDeadline: false);
  }

  Future<void> pickDeadlineDate() async {
    await _pickDate(isDeadline: true);
  }

  Future<void> deleteTask() async {
    if (!await confirmTaskDeletion(context, widget.task) || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    widget.controller.deleteTask(widget.task);
    showTaskDeletionUndo(messenger, widget.controller, widget.task);
  }

  Future<void> _pickDate({required bool isDeadline}) async {
    final current = isDeadline ? widget.task.deadlineAt : widget.task.startAt;
    final selected = await showDatePicker(
      context: context,
      initialDate: current?.toLocal() ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('zh', 'CN'),
    );
    if (selected != null) {
      final value = DateTime(
        selected.year,
        selected.month,
        selected.day,
        isDeadline ? 23 : 9,
        isDeadline ? 59 : 0,
      ).toUtc();
      widget.controller.updateTask(
        isDeadline
            ? widget.task.copyWith(deadlineAt: value)
            : widget.task.copyWith(startAt: value),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return ColoredBox(
      color: palette.surfaceRaised,
      child: Column(
        children: [
          Container(
            height: 68,
            padding: const EdgeInsets.fromLTRB(24, 0, 14, 0),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '任务详情',
                        style: TextStyle(
                          fontSize: 14,
                          color: palette.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '修改后自动保存',
                        style: TextStyle(fontSize: 10.5, color: palette.faint),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭详情',
                  onPressed: () {
                    saveText();
                    widget.controller.selectTask(null);
                  },
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _EditorLabel(label: '任务'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleController,
                    onSubmitted: (_) => saveText(),
                    onTapOutside: (_) => saveText(),
                    minLines: 1,
                    maxLines: 3,
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 21,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _EditorLabel(label: '备注'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesController,
                    onTapOutside: (_) => saveText(),
                    minLines: 5,
                    maxLines: 10,
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 13,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: '补充背景、步骤或想法…',
                      filled: true,
                      fillColor: palette.canvas,
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: palette.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: palette.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  _EditorLabel(label: '安排'),
                  const SizedBox(height: 8),
                  Divider(height: 1, color: palette.border),
                  _EditorField(
                    icon: Icons.calendar_today_outlined,
                    label: '开始日期',
                    value: _dateLabel(widget.task.startAt),
                    onTap: pickStartDate,
                  ),
                  _EditorField(
                    icon: Icons.flag_outlined,
                    label: '截止日期',
                    value: _dateLabel(widget.task.deadlineAt),
                    onTap: pickDeadlineDate,
                  ),
                  _ProjectField(
                    controller: widget.controller,
                    task: widget.task,
                  ),
                  Divider(height: 1, color: palette.border),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: palette.danger),
                onPressed: deleteTask,
                icon: const Icon(Icons.delete_outline_rounded, size: 17),
                label: const Text('删除任务'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _dateLabel(DateTime? value) {
    if (value == null) return '未设置';
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

class _EditorLabel extends StatelessWidget {
  const _EditorLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Text(
      label,
      style: TextStyle(
        color: palette.faint,
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.7,
      ),
    );
  }
}

class _EditorField extends StatelessWidget {
  const _EditorField({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: palette.muted),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(fontSize: 13, color: palette.muted)),
              const Spacer(),
              Text(value, style: TextStyle(fontSize: 12, color: palette.ink)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 18, color: palette.faint),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectField extends StatelessWidget {
  const _ProjectField({required this.controller, required this.task});

  final TaskController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return SizedBox(
      height: 49,
      child: Row(
        children: [
          Icon(
            Icons.format_list_bulleted_rounded,
            size: 18,
            color: palette.muted,
          ),
          const SizedBox(width: 10),
          Text('项目', style: TextStyle(fontSize: 12, color: palette.muted)),
          const Spacer(),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: task.projectId ?? '',
              style: TextStyle(fontSize: 12, color: palette.ink),
              items: [
                const DropdownMenuItem(value: '', child: Text('无项目')),
                for (final project in TaskController.projects)
                  DropdownMenuItem(
                    value: project.id,
                    child: Text(project.title),
                  ),
              ],
              onChanged: (value) => controller.updateTask(
                task.copyWith(
                  projectId: value,
                  clearProject: value == null || value.isEmpty,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
