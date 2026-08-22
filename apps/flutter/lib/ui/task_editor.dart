import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../models/task_item.dart';
import '../state/task_controller.dart';

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
    final selected = await showDatePicker(
      context: context,
      initialDate: widget.task.startAt?.toLocal() ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('zh', 'CN'),
    );
    if (selected != null) {
      widget.controller.updateTask(
        widget.task.copyWith(
          startAt: DateTime(
            selected.year,
            selected.month,
            selected.day,
            9,
          ).toUtc(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF7F6F2),
      child: Column(
        children: [
          Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFDEDBD3))),
            ),
            child: Row(
              children: [
                const Text(
                  '任务详情',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF85827A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
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
              padding: const EdgeInsets.fromLTRB(22, 27, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    onSubmitted: (_) => saveText(),
                    onTapOutside: (_) => saveText(),
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: notesController,
                    onTapOutside: (_) => saveText(),
                    maxLines: 6,
                    decoration: InputDecoration(
                      hintText: '备注',
                      filled: true,
                      fillColor: const Color(0x99FFFFFF),
                      border: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFFE5E1DA)),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFFE5E1DA)),
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
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
                    onTap: () {},
                  ),
                  _ProjectField(
                    controller: widget.controller,
                    task: widget.task,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
            child: FButton(
              variant: FButtonVariant.destructive,
              prefix: const Icon(FLucideIcons.trash2, size: 17),
              onPress: () => widget.controller.deleteTask(widget.task),
              child: const Text('删除任务'),
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
  Widget build(BuildContext context) => FItem(
    prefix: Icon(icon, size: 17, color: const Color(0xFF77736B)),
    title: Text(label),
    details: Text(value),
    suffix: const Icon(FLucideIcons.chevronRight, size: 15),
    onPress: onTap,
  );
}

class _ProjectField extends StatelessWidget {
  const _ProjectField({required this.controller, required this.task});

  final TaskController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) => Container(
    height: 45,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    color: const Color(0x8AFFFFFF),
    child: Row(
      children: [
        const Icon(
          Icons.format_list_bulleted_rounded,
          size: 18,
          color: Color(0xFF77736B),
        ),
        const SizedBox(width: 10),
        const Text(
          '项目',
          style: TextStyle(fontSize: 12, color: Color(0xFF6C6962)),
        ),
        const Spacer(),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: task.projectId ?? '',
            style: const TextStyle(fontSize: 11, color: Color(0xFF77736B)),
            items: [
              const DropdownMenuItem(value: '', child: Text('无项目')),
              for (final project in TaskController.projects)
                DropdownMenuItem(value: project.id, child: Text(project.title)),
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
