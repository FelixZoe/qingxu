import 'package:flutter/material.dart';

import '../state/task_controller.dart';
import 'design_system.dart';

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
    final palette = QingxuPalette.of(context);
    return ColoredBox(
      color: palette.sidebar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: palette.accentStrong,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.check_rounded, size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: 11),
                  Text(
                    '清序',
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                focusNode: searchFocus,
                onChanged: (value) {
                  if (value.trim().isNotEmpty &&
                      (controller.activeView == 'pomodoro' ||
                          controller.activeView == 'settings')) {
                    controller.selectView('inbox');
                  }
                  controller.setSearch(value);
                },
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '搜索任务',
                  hintStyle: TextStyle(fontSize: 13, color: palette.muted),
                  prefixIcon: const Icon(Icons.search_rounded, size: 19),
                  suffixText: '⌘K',
                  suffixStyle: TextStyle(fontSize: 10, color: palette.faint),
                  filled: true,
                  fillColor: palette.surface.withValues(alpha: 0.72),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
              child: Text(
                '任务',
                style: TextStyle(
                  color: palette.faint,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            _NavItem(
              controller: controller,
              id: 'inbox',
              label: '收集箱',
              icon: Icons.inbox_outlined,
              selectedIcon: Icons.inbox_rounded,
            ),
            _NavItem(
              controller: controller,
              id: 'today',
              label: '今天',
              icon: Icons.wb_sunny_outlined,
              selectedIcon: Icons.wb_sunny_rounded,
            ),
            _NavItem(
              controller: controller,
              id: 'pomodoro',
              label: '番茄钟',
              icon: Icons.timer_outlined,
              selectedIcon: Icons.timer_rounded,
            ),
            const SizedBox(height: 10),
            Divider(height: 1, indent: 20, endIndent: 20, color: palette.border),
            const SizedBox(height: 10),
            _NavItem(
              controller: controller,
              id: 'settings',
              label: '设置',
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_rounded,
            ),
            const Spacer(),
            _SyncFooter(controller: controller),
          ],
        ),
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
    required this.selectedIcon,
  });

  final TaskController controller;
  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final selected = controller.activeView == id && controller.search.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected ? palette.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            controller.selectView(id);
            if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
              Navigator.of(context).pop();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 20,
                  color: selected ? palette.accentStrong : palette.muted,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? palette.ink : palette.muted,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncFooter extends StatelessWidget {
  const _SyncFooter({required this.controller});

  final TaskController controller;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final (color, label) = controller.syncSupported
        ? switch (controller.syncActivity) {
            SyncActivity.syncing || SyncActivity.testing =>
              (palette.info, controller.syncMessage),
            SyncActivity.success || SyncActivity.idle =>
              (palette.success, controller.syncMessage),
            SyncActivity.error => (palette.danger, controller.syncMessage),
            SyncActivity.unconfigured => (palette.faint, '仅保存在本地'),
          }
        : (palette.success, '本地数据已保存');
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: palette.faint),
            ),
          ),
        ],
      ),
    );
  }
}
