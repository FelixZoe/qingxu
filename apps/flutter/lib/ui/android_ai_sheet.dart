import 'package:flutter/material.dart';

import '../services/personal_hub_store.dart';
import '../state/task_controller.dart';
import 'design_system.dart';

Future<void> showAndroidAISheet(
  BuildContext context, {
  required PersonalHubStore store,
  required TaskController controller,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _AndroidAISheet(store: store, controller: controller),
);

Future<void> showAndroidAISettingsSheet(
  BuildContext context, {
  required PersonalHubStore store,
  required TaskController controller,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _AISettingsSheet(store: store, controller: controller),
);

Future<void> showAndroidWeatherSettingsSheet(
  BuildContext context, {
  required PersonalHubStore store,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _WeatherSettingsSheet(store: store),
);

class _AndroidAISheet extends StatefulWidget {
  const _AndroidAISheet({required this.store, required this.controller});

  final PersonalHubStore store;
  final TaskController controller;

  @override
  State<_AndroidAISheet> createState() => _AndroidAISheetState();
}

class _AndroidAISheetState extends State<_AndroidAISheet> {
  final _prompt = TextEditingController();
  String? _answer;
  bool _loading = false;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _ask([String? preset]) async {
    final prompt = preset ?? _prompt.text;
    if (prompt.trim().isEmpty || _loading) return;
    setState(() => _loading = true);
    try {
      final answer = await widget.store.askAI(
        syncSettings: widget.controller.syncSettings,
        prompt: prompt,
        tasks: widget.controller.tasks,
      );
      if (mounted) setState(() => _answer = answer);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cleanError(error))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return _SheetFrame(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          8,
          22,
          MediaQuery.viewInsetsOf(context).bottom + 22,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '帮我安排',
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'AI 会结合当前任务给出简短、可执行的安排。',
                style: TextStyle(color: palette.muted, height: 1.45),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: const Text('整理今天'),
                    onPressed: () => _ask('根据我的现有任务，给出今天最值得完成的三件事和顺序。'),
                  ),
                  ActionChip(
                    label: const Text('拆分任务'),
                    onPressed: () => _ask('找出最模糊或最难开始的任务，并拆成可以立刻执行的小步骤。'),
                  ),
                  ActionChip(
                    label: const Text('安排专注'),
                    onPressed: () => _ask('结合现有任务，安排一个不过度拥挤的番茄专注计划。'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _prompt,
                minLines: 2,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(hintText: '例如：今晚两小时该先做什么？'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _ask,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_upward_rounded),
                  label: Text(_loading ? '正在思考…' : '发送'),
                ),
              ),
              if (_answer != null) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: SelectableText(
                    _answer!,
                    style: TextStyle(color: palette.ink, height: 1.65),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AISettingsSheet extends StatefulWidget {
  const _AISettingsSheet({required this.store, required this.controller});

  final PersonalHubStore store;
  final TaskController controller;

  @override
  State<_AISettingsSheet> createState() => _AISettingsSheetState();
}

class _AISettingsSheetState extends State<_AISettingsSheet> {
  late PersonalAIProvider _provider;
  final _apiKey = TextEditingController();
  bool _saving = false;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _provider = widget.store.aiSettings.provider;
    widget.store.readAIKey().then((value) {
      if (mounted) _apiKey.text = value;
    });
  }

  @override
  void dispose() {
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await widget.store.saveAISettings(
      PersonalAISettings(provider: _provider),
      apiKey: _apiKey.text,
    );
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _test() async {
    if (_testing) return;
    await _save();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final result = await widget.store.askAI(
        syncSettings: widget.controller.syncSettings,
        prompt: '只回复：连接成功',
      );
      if (mounted) setState(() => _testResult = result.trim());
    } on Object catch (error) {
      if (mounted) setState(() => _testResult = _cleanError(error));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return _SheetFrame(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          8,
          22,
          MediaQuery.viewInsetsOf(context).bottom + 22,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AI 服务', style: TextStyle(color: palette.ink, fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 7),
              Text('选择服务，填写自己的密钥，然后测试。模型和提示词由清序内置。', style: TextStyle(color: palette.muted, height: 1.45)),
              const SizedBox(height: 20),
              DropdownButtonFormField<PersonalAIProvider>(
                initialValue: _provider,
                decoration: const InputDecoration(labelText: '服务商'),
                items: PersonalAIProvider.values
                    .map((value) => DropdownMenuItem(value: value, child: Text(value.label)))
                    .toList(),
                onChanged: (value) => setState(() => _provider = value ?? _provider),
              ),
              if (_provider != PersonalAIProvider.selfHosted) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKey,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: 'API 密钥'),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _testing ? null : _test,
                      child: Text(_testing ? '测试中…' : '测试连接'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : () async {
                        await _save();
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Text(_saving ? '保存中…' : '保存'),
                    ),
                  ),
                ],
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 12),
                Text(_testResult!, style: TextStyle(color: palette.muted, height: 1.45)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WeatherSettingsSheet extends StatefulWidget {
  const _WeatherSettingsSheet({required this.store});

  final PersonalHubStore store;

  @override
  State<_WeatherSettingsSheet> createState() => _WeatherSettingsSheetState();
}

class _WeatherSettingsSheetState extends State<_WeatherSettingsSheet> {
  late final TextEditingController _host;
  late final TextEditingController _city;
  late final TextEditingController _location;
  final _key = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: widget.store.weatherHost);
    _city = TextEditingController(text: widget.store.weatherCity);
    _location = TextEditingController(text: widget.store.weatherLocationId);
    widget.store.readWeatherKey().then((value) {
      if (mounted) _key.text = value;
    });
  }

  @override
  void dispose() {
    _host.dispose();
    _city.dispose();
    _location.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return _SheetFrame(
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, 8, 22, MediaQuery.viewInsetsOf(context).bottom + 22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('每日一句与天气', style: TextStyle(color: palette.ink, fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 7),
              Text('每日一句开箱即用；天气使用你自己的和风天气凭据并保存在本机。', style: TextStyle(color: palette.muted, height: 1.45)),
              const SizedBox(height: 18),
              TextField(controller: _host, decoration: const InputDecoration(labelText: 'API Host', hintText: '你的 QWeather API Host')),
              const SizedBox(height: 10),
              TextField(controller: _key, obscureText: true, decoration: const InputDecoration(labelText: 'API 密钥')),
              const SizedBox(height: 10),
              TextField(controller: _city, decoration: const InputDecoration(labelText: '城市名称')),
              const SizedBox(height: 10),
              TextField(controller: _location, decoration: const InputDecoration(labelText: 'Location ID')),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : () async {
                    setState(() => _saving = true);
                    await widget.store.saveWeatherSettings(
                      host: _host.text,
                      apiKey: _key.text,
                      locationId: _location.text,
                      city: _city.text,
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(_saving ? '保存中…' : '保存并刷新'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Material(
      color: palette.surfaceRaised,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

String _cleanError(Object error) => error
    .toString()
    .replaceFirst('Bad state: ', '')
    .replaceFirst('StateError: ', '');
