import 'package:flutter/material.dart';

import '../state/task_controller.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({required this.controller, required this.searchFocus, super.key});

  final TaskController controller;
  final FocusNode searchFocus;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFEAE8E2),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 29,
                  height: 29,
                  decoration: BoxDecoration(color: const Color(0xFFE7B83F), borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: const Icon(Icons.check_rounded, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Text('清序', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const Spacer(),
                _Badge(text: '雏形'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              focusNode: searchFocus,
              onChanged: controller.setSearch,
              decoration: InputDecoration(
                hintText: '搜索',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF8B887F)),
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                suffixText: '⌘K',
                suffixStyle: const TextStyle(fontSize: 10, color: Color(0xFFA7A39A)),
                filled: true,
                fillColor: const Color(0xAFFFFFFF),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(9)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _NavItem(controller: controller, id: 'inbox', label: '收集箱', icon: Icons.inbox_outlined),
          _NavItem(controller: controller, id: 'today', label: '今天', icon: Icons.wb_sunny_outlined),
          _NavItem(controller: controller, id: 'upcoming', label: '计划', icon: Icons.calendar_month_outlined),
          _NavItem(controller: controller, id: 'anytime', label: '随时', icon: Icons.radio_button_unchecked),
          _NavItem(controller: controller, id: 'logbook', label: '日志', icon: Icons.inventory_2_outlined),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 7),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('项目', style: TextStyle(fontSize: 11, color: Color(0xFF96928A), fontWeight: FontWeight.w600)),
            ),
          ),
          for (final project in TaskController.projects)
            _NavItem(
              controller: controller,
              id: 'project:${project.id}',
              label: project.title,
              icon: Icons.format_list_bulleted_rounded,
              iconColor: Color(project.color),
            ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(color: Color(0xFF75AA78), shape: BoxShape.circle),
                  child: SizedBox(width: 7, height: 7),
                ),
                SizedBox(width: 8),
                Text('本地数据已保存', style: TextStyle(fontSize: 11, color: Color(0xFF969289))),
              ],
            ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1.5),
      child: Material(
        color: selected ? const Color(0xDEFFFFFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () {
            controller.selectView(id);
            if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) Navigator.of(context).pop();
          },
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 37,
            child: Row(
              children: [
                const SizedBox(width: 11),
                Icon(icon, size: 19, color: iconColor ?? const Color(0xFF5F5C55)),
                const SizedBox(width: 11),
                Text(label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD5D1C7)), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: const TextStyle(fontSize: 10, color: Color(0xFF8C887F))),
      );
}

