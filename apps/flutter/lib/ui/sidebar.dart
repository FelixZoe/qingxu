import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../state/task_controller.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({
    required this.controller,
    required this.searchFocus,
    required this.onOpenSyncSettings,
    super.key,
  });

  final TaskController controller;
  final FocusNode searchFocus;
  final VoidCallback onOpenSyncSettings;

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
        footer: _SyncFooter(controller: controller),
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
          if (controller.syncSupported)
            FSidebarGroup(
              label: const Text('设置'),
              children: [
                FSidebarItem(
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('多端同步'),
                  onPress: () {
                    final drawerOpen =
                        Scaffold.maybeOf(context)?.isDrawerOpen ?? false;
                    if (drawerOpen) {
                      Navigator.of(context).pop();
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => onOpenSyncSettings(),
                      );
                    } else {
                      onOpenSyncSettings();
                    }
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SyncFooter extends StatelessWidget {
  const _SyncFooter({required this.controller});

  final TaskController controller;

  @override
  Widget build(BuildContext context) {
    final (color, label) = controller.syncSupported
        ? switch (controller.syncActivity) {
            SyncActivity.syncing || SyncActivity.testing => (
              const Color(0xFF6687AD),
              controller.syncMessage,
            ),
            SyncActivity.success => (
              const Color(0xFF75AA78),
              controller.syncMessage,
            ),
            SyncActivity.error => (
              const Color(0xFFBD6A5C),
              controller.syncMessage,
            ),
            SyncActivity.idle => (
              const Color(0xFF75AA78),
              controller.syncMessage,
            ),
            SyncActivity.unconfigured => (const Color(0xFFAAA69D), '仅保存在本地'),
          }
        : (const Color(0xFF75AA78), '本地数据已保存');
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: const SizedBox(width: 7, height: 7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFF969289)),
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
