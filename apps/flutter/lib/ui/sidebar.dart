import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../state/task_controller.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({
    required this.controller,
    required this.searchFocus,
    super.key,
  });

  final TaskController controller;
  final FocusNode searchFocus;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFEAE8E2),
      child: FSidebar(
        header: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 29,
                    height: 29,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7B83F),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      FLucideIcons.check,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    '清序',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  FBadge(
                    variant: FBadgeVariant.outline,
                    child: const Text('雏形'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: TextField(
                focusNode: searchFocus,
                onChanged: controller.setSearch,
                decoration: InputDecoration(
                  hintText: '搜索任务',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8B887F),
                  ),
                  prefixIcon: const Icon(FLucideIcons.search, size: 17),
                  suffixText: '⌘K',
                  suffixStyle: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFA7A39A),
                  ),
                  filled: true,
                  fillColor: const Color(0xCFFFFFFF),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
        footer: const Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFF75AA78),
                  shape: BoxShape.circle,
                ),
                child: SizedBox(width: 7, height: 7),
              ),
              SizedBox(width: 8),
              Text(
                '本地数据已保存',
                style: TextStyle(fontSize: 11, color: Color(0xFF969289)),
              ),
            ],
          ),
        ),
        children: [
          FSidebarGroup(
            label: const Text('任务'),
            children: [
              _NavItem(
                controller: controller,
                id: 'inbox',
                label: '收集箱',
                icon: FLucideIcons.inbox,
              ),
              _NavItem(
                controller: controller,
                id: 'today',
                label: '今天',
                icon: FLucideIcons.sun,
              ),
              _NavItem(
                controller: controller,
                id: 'upcoming',
                label: '计划',
                icon: FLucideIcons.calendarDays,
              ),
              _NavItem(
                controller: controller,
                id: 'anytime',
                label: '随时',
                icon: FLucideIcons.circle,
              ),
              _NavItem(
                controller: controller,
                id: 'logbook',
                label: '日志',
                icon: FLucideIcons.archive,
              ),
            ],
          ),
          FSidebarGroup(
            label: const Text('项目'),
            children: [
              for (final project in TaskController.projects)
                _NavItem(
                  controller: controller,
                  id: 'project:${project.id}',
                  label: project.title,
                  icon: FLucideIcons.listTodo,
                  iconColor: Color(project.color),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.controller,
    required this.id,
    required this.label,
    required this.icon,
    this.iconColor,
  });

  final TaskController controller;
  final String id;
  final String label;
  final IconData icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final selected = controller.activeView == id && controller.search.isEmpty;
    return FSidebarItem(
      selected: selected,
      icon: Icon(icon, size: 18, color: iconColor),
      label: Text(label),
      onPress: () {
        controller.selectView(id);
        if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
          Navigator.of(context).pop();
        }
      },
    );
  }
}
