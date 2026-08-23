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
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: palette.sidebar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      dark
                          ? 'assets/branding/qingxu-icon-master-white.png'
                          : 'assets/branding/qingxu-icon-master-black.png',
                      width: 30,
                      height: 30,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '清序',
                          style: TextStyle(
                            color: palette.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '让事情回到秩序',
                          style: TextStyle(
                            color: palette.faint,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                height: 38,
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
                  style: TextStyle(fontSize: 12.5, color: palette.ink),
                  decoration: InputDecoration(
                    hintText: '搜索任务',
                    hintStyle: TextStyle(fontSize: 12.5, color: palette.muted),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: palette.muted,
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 38),
                    suffix: Text(
                      'Ctrl K',
                      style: TextStyle(fontSize: 9.5, color: palette.faint),
                    ),
                    filled: true,
                    fillColor: palette.surface.withValues(alpha: 0.82),
                    isDense: true,
                    contentPadding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: palette.border),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: palette.border),
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
              ),
            ),
            _SectionLabel(label: '任务'),
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
            _SectionLabel(label: '专注', top: 22),
            _NavItem(
              controller: controller,
              id: 'pomodoro',
              label: '番茄钟',
              icon: Icons.timer_outlined,
              selectedIcon: Icons.timer_rounded,
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Divider(height: 1, color: palette.border),
            ),
            const SizedBox(height: 10),
            _NavItem(
              controller: controller,
              id: 'settings',
              label: '设置',
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_rounded,
            ),
            _SyncFooter(controller: controller),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.top = 28});

  final String label;
  final double top;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(24, top, 24, 8),
      child: Text(
        label,
        style: TextStyle(
          color: palette.faint,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.7,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: palette.surface.withValues(alpha: 0.72),
          onTap: () {
            controller.selectView(id);
            if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
              Navigator.of(context).pop();
            }
          },
          child: AnimatedContainer(
            duration: QingxuMotion.quick,
            height: 40,
            decoration: BoxDecoration(
              color: selected
                  ? palette.surfaceRaised.withValues(alpha: 0.86)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(
                  color: selected ? palette.accent : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(11, 0, 12, 0),
            child: Row(
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 18,
                  color: selected ? palette.accentStrong : palette.muted,
                ),
                const SizedBox(width: 11),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? palette.ink : palette.muted,
                    fontSize: 13,
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
            SyncActivity.syncing ||
            SyncActivity.testing => (palette.info, controller.syncMessage),
            SyncActivity.success ||
            SyncActivity.idle => (palette.success, controller.syncMessage),
            SyncActivity.error => (palette.danger, controller.syncMessage),
            SyncActivity.unconfigured => (palette.faint, '仅保存在本地'),
          }
        : (palette.success, '本地数据已保存');
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 15, 22, 19),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: palette.faint),
            ),
          ),
        ],
      ),
    );
  }
}
