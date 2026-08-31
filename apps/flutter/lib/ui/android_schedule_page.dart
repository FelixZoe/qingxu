import 'package:flutter/material.dart';
import 'package:lunar/calendar/Lunar.dart';
import 'package:lunar/calendar/util/HolidayUtil.dart';

import '../models/task_item.dart';
import '../services/personal_hub_store.dart';
import '../state/task_controller.dart';
import 'design_system.dart';

class AndroidSchedulePage extends StatefulWidget {
  const AndroidSchedulePage({
    required this.controller,
    required this.store,
    required this.onOpenAI,
    super.key,
  });

  final TaskController controller;
  final PersonalHubStore store;
  final VoidCallback onOpenAI;

  @override
  State<AndroidSchedulePage> createState() => _AndroidSchedulePageState();
}

class _AndroidSchedulePageState extends State<AndroidSchedulePage> {
  DateTime _selectedDate = _day(DateTime.now());
  bool _monthExpanded = false;
  bool _adding = false;

  List<TaskItem> get _tasks {
    final result = widget.controller.tasks.where((task) {
      if (task.deletedAt != null || task.startAt == null) return false;
      return _sameDay(task.startAt!.toLocal(), _selectedDate);
    }).toList();
    result.sort((left, right) {
      final completedOrder = (left.status == TaskStatus.completed ? 1 : 0)
          .compareTo(right.status == TaskStatus.completed ? 1 : 0);
      return completedOrder != 0
          ? completedOrder
          : left.order.compareTo(right.order);
    });
    return result;
  }

  Future<void> _addTask() async {
    if (_adding) return;
    _adding = true;
    try {
      final title = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _ScheduleQuickAddSheet(),
      );
      if (!mounted || title == null || title.trim().isEmpty) return;
      final previous = widget.controller.activeView;
      widget.controller.selectView('today');
      final task = widget.controller.addTask(title);
      if (previous != 'today') widget.controller.selectView(previous);
      if (task == null) return;
      final scheduled = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        9,
      ).toUtc();
      widget.controller.updateTask(task.copyWith(startAt: scheduled));
    } finally {
      _adding = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, widget.store]),
      builder: (context, _) => ColoredBox(
        color: palette.canvas,
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: widget.store.refreshOverview,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    sliver: SliverToBoxAdapter(child: _buildHeader(palette)),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                    sliver: SliverToBoxAdapter(child: _buildCalendar(palette)),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    sliver: SliverToBoxAdapter(child: _DailyBrief(store: widget.store)),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedTitle,
                              style: TextStyle(
                                color: palette.ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                          Text(
                            '${_tasks.where((task) => task.status != TaskStatus.completed).length} 项待办',
                            style: TextStyle(color: palette.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_tasks.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: const _ScheduleEmptyState(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 132),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ScheduleTaskRow(
                              controller: widget.controller,
                              task: _tasks[index],
                            ),
                          ),
                          childCount: _tasks.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              right: 20,
              bottom: 22,
              child: FloatingActionButton(
                heroTag: 'android-schedule-add',
                onPressed: _addTask,
                child: const Icon(Icons.add_rounded, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(QingxuPalette palette) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '日程',
              style: TextStyle(
                color: palette.ink,
                fontSize: 34,
                height: 1.05,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '${_selectedDate.month}月${_selectedDate.day}日 · ${_lunarLabel(_selectedDate)}',
              style: TextStyle(color: palette.muted, fontSize: 14),
            ),
          ],
        ),
      ),
      IconButton.filledTonal(
        tooltip: 'AI 帮我安排',
        onPressed: widget.onOpenAI,
        icon: const Icon(Icons.auto_awesome_outlined),
      ),
    ],
  );

  Widget _buildCalendar(QingxuPalette palette) {
    final dates = _monthExpanded ? _monthDates(_selectedDate) : _weekDates(_selectedDate);
    return Material(
      color: palette.surfaceRaised,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _monthExpanded = !_monthExpanded),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_selectedDate.year}年${_selectedDate.month}月',
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _monthExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: Icon(Icons.expand_more_rounded, color: palette.muted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AnimatedSize(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: GridView.builder(
                  key: ValueKey(_monthExpanded),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: 54,
                  ),
                  itemCount: dates.length,
                  itemBuilder: (context, index) => _CalendarDay(
                    date: dates[index],
                    selected: _sameDay(dates[index], _selectedDate),
                    muted: dates[index].month != _selectedDate.month,
                    onTap: () => setState(() => _selectedDate = dates[index]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _selectedTitle {
    final now = _day(DateTime.now());
    final difference = _selectedDate.difference(now).inDays;
    return switch (difference) {
      0 => '今天',
      1 => '明天',
      -1 => '昨天',
      _ => '${_selectedDate.month}月${_selectedDate.day}日',
    };
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.selected,
    required this.muted,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final lunar = _lunarLabel(date);
    return InkResponse(
      onTap: onTap,
      radius: 27,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: selected ? palette.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : muted
                    ? palette.faint
                    : palette.ink,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              lunar,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: selected ? Colors.white70 : palette.muted,
                fontSize: 8.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyBrief extends StatelessWidget {
  const _DailyBrief({required this.store});

  final PersonalHubStore store;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final weather = store.weather;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            weather == null ? Icons.format_quote_rounded : Icons.cloud_outlined,
            color: palette.accent,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  store.quote.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.ink,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  weather == null
                      ? '— ${store.quote.source}'
                      : '${weather.city}  ${weather.temperature}°  ${weather.description}',
                  style: TextStyle(color: palette.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleTaskRow extends StatelessWidget {
  const _ScheduleTaskRow({required this.controller, required this.task});

  final TaskController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final completed = task.status == TaskStatus.completed;
    return Dismissible(
      key: ValueKey('android-schedule-${task.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: palette.danger,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) {
        controller.deleteTask(task);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: const Text('已删除任务'),
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: '撤销',
                onPressed: () => controller.restoreTask(task),
              ),
            ),
          );
      },
      child: Material(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => controller.selectTask(task.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              children: [
                InkResponse(
                  onTap: () => controller.toggleTask(task),
                  radius: 22,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 25,
                    height: 25,
                    decoration: BoxDecoration(
                      color: completed ? palette.accent : Colors.transparent,
                      border: Border.all(
                        color: completed ? palette.accent : palette.faint,
                        width: 1.7,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: completed
                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 17)
                        : null,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: completed ? palette.muted : palette.ink,
                      fontSize: 16,
                      height: 1.3,
                      fontWeight: completed ? FontWeight.w400 : FontWeight.w600,
                      decoration: completed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: palette.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScheduleEmptyState extends StatelessWidget {
  const _ScheduleEmptyState();

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 130),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_available_outlined, size: 40, color: palette.faint),
          const SizedBox(height: 18),
          Text(
            '这一天还没有安排',
            style: TextStyle(color: palette.ink, fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Text('留一点空间，也是一种计划', style: TextStyle(color: palette.muted)),
        ],
      ),
    );
  }
}

class _ScheduleQuickAddSheet extends StatefulWidget {
  const _ScheduleQuickAddSheet();

  @override
  State<_ScheduleQuickAddSheet> createState() => _ScheduleQuickAddSheetState();
}

class _ScheduleQuickAddSheetState extends State<_ScheduleQuickAddSheet> {
  final _title = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, MediaQuery.viewInsetsOf(context).bottom + 12),
      child: Material(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('新增日程', style: TextStyle(color: palette.ink, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (value) => Navigator.pop(context, value.trim()),
                decoration: const InputDecoration(hintText: '要做什么？'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _title.text.trim()),
                  child: const Text('添加'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year && left.month == right.month && left.day == right.day;

List<DateTime> _weekDates(DateTime selected) {
  final start = _day(selected).subtract(Duration(days: selected.weekday - 1));
  return List.generate(7, (index) => start.add(Duration(days: index)));
}

List<DateTime> _monthDates(DateTime selected) {
  final first = DateTime(selected.year, selected.month);
  final start = first.subtract(Duration(days: first.weekday - 1));
  final last = DateTime(selected.year, selected.month + 1, 0);
  final tail = 7 - last.weekday;
  final count = first.weekday - 1 + last.day + tail;
  return List.generate(count, (index) => start.add(Duration(days: index)));
}

String _lunarLabel(DateTime date) {
  final holiday = HolidayUtil.getHolidayByYmd(date.year, date.month, date.day);
  if (holiday != null) return holiday.isWork() ? '${holiday.getName()}调休' : holiday.getName();
  final lunar = Lunar.fromDate(date);
  if (lunar.getFestivals().isNotEmpty) return lunar.getFestivals().first;
  if (lunar.getJieQi().isNotEmpty) return lunar.getJieQi();
  return lunar.getDayInChinese();
}
