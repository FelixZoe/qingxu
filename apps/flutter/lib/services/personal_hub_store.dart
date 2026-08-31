import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../models/sync_settings.dart';
import '../models/task_item.dart';

enum PersonalAIProvider { selfHosted, deepSeek, openAI }

extension PersonalAIProviderLabel on PersonalAIProvider {
  String get label => switch (this) {
    PersonalAIProvider.selfHosted => '自托管服务器',
    PersonalAIProvider.deepSeek => 'DeepSeek',
    PersonalAIProvider.openAI => 'OpenAI',
  };

  String get defaultEndpoint => switch (this) {
    PersonalAIProvider.selfHosted => '',
    PersonalAIProvider.deepSeek =>
      'https://api.deepseek.com/v1/chat/completions',
    PersonalAIProvider.openAI =>
      'https://api.openai.com/v1/chat/completions',
  };

  String get defaultModel => switch (this) {
    PersonalAIProvider.selfHosted => '',
    PersonalAIProvider.deepSeek => 'deepseek-chat',
    PersonalAIProvider.openAI => 'gpt-4.1-mini',
  };
}

class PersonalAISettings {
  const PersonalAISettings({
    this.provider = PersonalAIProvider.selfHosted,
    this.endpoint = '',
    this.model = '',
  });

  final PersonalAIProvider provider;
  final String endpoint;
  final String model;

  PersonalAISettings copyWith({
    PersonalAIProvider? provider,
    String? endpoint,
    String? model,
  }) => PersonalAISettings(
    provider: provider ?? this.provider,
    endpoint: endpoint ?? this.endpoint,
    model: model ?? this.model,
  );

  Map<String, Object?> toJson() => {
    'provider': provider.name,
    'endpoint': endpoint,
    'model': model,
  };

  factory PersonalAISettings.fromJson(Map<String, Object?> json) {
    final raw = json['provider'] as String?;
    return PersonalAISettings(
      provider: PersonalAIProvider.values
          .where((value) => value.name == raw)
          .firstOrNull ??
          PersonalAIProvider.selfHosted,
      endpoint: json['endpoint'] as String? ?? '',
      model: json['model'] as String? ?? '',
    );
  }
}

class DailyQuote {
  const DailyQuote(this.content, this.source);

  final String content;
  final String source;

  Map<String, Object?> toJson() => {'content': content, 'source': source};

  factory DailyQuote.fromJson(Map<String, Object?> json) => DailyQuote(
    json['content'] as String? ?? '把复杂留给系统，把注意力留给今天。',
    json['source'] as String? ?? '清序',
  );
}

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.city,
    required this.temperature,
    required this.description,
    required this.iconCode,
  });

  final String city;
  final String temperature;
  final String description;
  final String iconCode;

  Map<String, Object?> toJson() => {
    'city': city,
    'temperature': temperature,
    'description': description,
    'iconCode': iconCode,
  };

  factory WeatherSnapshot.fromJson(Map<String, Object?> json) =>
      WeatherSnapshot(
        city: json['city'] as String? ?? '',
        temperature: json['temperature'] as String? ?? '--',
        description: json['description'] as String? ?? '',
        iconCode: json['iconCode'] as String? ?? '999',
      );
}

class PersonalRSSSubscription {
  const PersonalRSSSubscription({
    required this.id,
    required this.title,
    required this.feedUrl,
    required this.siteUrl,
    required this.folder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String feedUrl;
  final String? siteUrl;
  final String folder;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'feedURL': feedUrl,
    'siteURL': siteUrl,
    'folder': folder,
    'folderID': folder == '未分类' ? null : _stableDocumentId(folder),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory PersonalRSSSubscription.fromJson(
    Map<String, Object?> json, {
    Map<String, String> folderTitles = const {},
  }) {
    final now = DateTime.now().toUtc();
    final folderId = json['folderID'] as String? ?? json['folderId'] as String?;
    return PersonalRSSSubscription(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '未命名订阅',
      feedUrl: json['feedURL'] as String? ?? json['feedUrl'] as String? ?? '',
      siteUrl: json['siteURL'] as String? ?? json['siteUrl'] as String?,
      folder:
          json['folder'] as String? ?? folderTitles[folderId] ?? '未分类',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }
}

class PersonalRSSArticle {
  const PersonalRSSArticle({
    required this.id,
    required this.feedId,
    required this.feedTitle,
    required this.title,
    required this.summary,
    required this.content,
    required this.link,
    required this.author,
    required this.publishedAt,
    required this.fetchedAt,
    required this.isRead,
    required this.isStarred,
  });

  final String id;
  final String feedId;
  final String feedTitle;
  final String title;
  final String summary;
  final String content;
  final String link;
  final String? author;
  final DateTime? publishedAt;
  final DateTime fetchedAt;
  final bool isRead;
  final bool isStarred;

  PersonalRSSArticle copyWith({bool? isRead, bool? isStarred}) =>
      PersonalRSSArticle(
        id: id,
        feedId: feedId,
        feedTitle: feedTitle,
        title: title,
        summary: summary,
        content: content,
        link: link,
        author: author,
        publishedAt: publishedAt,
        fetchedAt: fetchedAt,
        isRead: isRead ?? this.isRead,
        isStarred: isStarred ?? this.isStarred,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'feedId': feedId,
    'feedTitle': feedTitle,
    'title': title,
    'summary': summary,
    'content': content,
    'link': link,
    'author': author,
    'publishedAt': publishedAt?.toUtc().toIso8601String(),
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'isRead': isRead,
    'isStarred': isStarred,
  };

  factory PersonalRSSArticle.fromJson(Map<String, Object?> json) {
    final now = DateTime.now().toUtc();
    return PersonalRSSArticle(
      id: json['id'] as String? ?? '',
      feedId: json['feedId'] as String? ?? '',
      feedTitle: json['feedTitle'] as String? ?? '',
      title: json['title'] as String? ?? '无标题',
      summary: json['summary'] as String? ?? '',
      content: json['content'] as String? ?? '',
      link: json['link'] as String? ?? '',
      author: json['author'] as String?,
      publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? ''),
      fetchedAt: DateTime.tryParse(json['fetchedAt'] as String? ?? '') ?? now,
      isRead: json['isRead'] == true,
      isStarred: json['isStarred'] == true,
    );
  }
}

class PersonalHubStore extends ChangeNotifier {
  PersonalHubStore({http.Client? client}) : _client = client ?? http.Client();

  static const _secure = FlutterSecureStorage();
  static const _aiKeyName = 'qingxu_android_ai_key';
  static const _weatherKeyName = 'qingxu_android_weather_key';
  static const _documentKey = 'qingxu_android_personal_hub_v1';

  final http.Client _client;
  final List<PersonalRSSSubscription> _subscriptions = [];
  final List<PersonalRSSArticle> _articles = [];

  DailyQuote quote = const DailyQuote(
    '把复杂留给系统，把注意力留给今天。',
    '清序',
  );
  WeatherSnapshot? weather;
  PersonalAISettings aiSettings = const PersonalAISettings();
  String weatherHost = '';
  String weatherLocationId = '101010100';
  String weatherCity = '北京';
  bool loadingOverview = false;
  bool refreshingRSS = false;
  String? lastError;
  DateTime _rssUpdatedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  List<PersonalRSSSubscription> get subscriptions =>
      List.unmodifiable(_subscriptions);
  List<PersonalRSSArticle> get articles {
    final copy = [..._articles];
    copy.sort(
      (left, right) => (right.publishedAt ?? right.fetchedAt).compareTo(
        left.publishedAt ?? left.fetchedAt,
      ),
    );
    return List.unmodifiable(copy);
  }

  Set<String> get folders => {
    '全部',
    ..._subscriptions.map((item) => item.folder),
  };

  Future<void> initialize({SyncSettings? syncSettings}) async {
    await _load();
    notifyListeners();
    unawaited(refreshOverview());
    if (_subscriptions.isNotEmpty) unawaited(refreshFeeds());
    if (syncSettings?.isConfigured == true) {
      unawaited(syncRSS(syncSettings!));
    }
  }

  Future<void> refreshOverview() async {
    if (loadingOverview) return;
    loadingOverview = true;
    notifyListeners();
    try {
      await Future.wait([_refreshQuote(), _refreshWeather()]);
      await _save();
    } finally {
      loadingOverview = false;
      notifyListeners();
    }
  }

  Future<void> saveAISettings(
    PersonalAISettings value, {
    required String apiKey,
  }) async {
    aiSettings = value;
    if (apiKey.trim().isEmpty) {
      await _secure.delete(key: _aiKeyName);
    } else {
      await _secure.write(key: _aiKeyName, value: apiKey.trim());
    }
    await _save();
    notifyListeners();
  }

  Future<String> readAIKey() async =>
      (await _secure.read(key: _aiKeyName)) ?? '';

  Future<void> saveWeatherSettings({
    required String host,
    required String apiKey,
    required String locationId,
    required String city,
  }) async {
    weatherHost = host
        .trim()
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'/+$'), '');
    weatherLocationId = locationId.trim().isEmpty
        ? '101010100'
        : locationId.trim();
    weatherCity = city.trim().isEmpty ? '北京' : city.trim();
    if (apiKey.trim().isEmpty) {
      await _secure.delete(key: _weatherKeyName);
    } else {
      await _secure.write(key: _weatherKeyName, value: apiKey.trim());
    }
    await _save();
    await refreshOverview();
  }

  Future<String> readWeatherKey() async =>
      (await _secure.read(key: _weatherKeyName)) ?? '';

  Future<String> askAI({
    required SyncSettings syncSettings,
    required String prompt,
    List<TaskItem> tasks = const [],
  }) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) throw StateError('请先写下你想让 AI 帮忙的内容');
    if (aiSettings.provider == PersonalAIProvider.selfHosted) {
      if (!syncSettings.isConfigured) {
        throw StateError('请先在设置中配置自托管服务器');
      }
      final endpoint = _endpoint(syncSettings.serverUrl, '/v1/ai');
      final response = await _client
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${syncSettings.token}',
            },
            body: jsonEncode({
              'mode': 'task_plan',
              'goal': cleanPrompt,
              'tasks': tasks
                  .where((task) => task.deletedAt == null && task.isOpen)
                  .take(80)
                  .map(
                    (task) => {
                      'title': task.title,
                      if (task.startAt != null)
                        'scheduledAt': task.startAt!.toUtc().toIso8601String(),
                    },
                  )
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 50));
      return _decodeAIResponse(response);
    }

    final key = await readAIKey();
    if (key.isEmpty) throw StateError('请先在设置中填写 AI API 密钥');
    final endpoint = aiSettings.endpoint.trim().isEmpty
        ? aiSettings.provider.defaultEndpoint
        : aiSettings.endpoint.trim();
    final model = aiSettings.model.trim().isEmpty
        ? aiSettings.provider.defaultModel
        : aiSettings.model.trim();
    final taskContext = tasks
        .where((task) => task.deletedAt == null && task.isOpen)
        .take(80)
        .map((task) => '• ${task.title}')
        .join('\n');
    final response = await _client
        .post(
          Uri.parse(endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $key',
          },
          body: jsonEncode({
            'model': model,
            'temperature': 0.25,
            'messages': [
              {
                'role': 'system',
                'content':
                    '你是清序的个人效率助手。回答简短、具体、可执行，不制造冗余事项。需要安排任务时，优先使用用户已有任务。',
              },
              {
                'role': 'user',
                'content': '$cleanPrompt\n\n当前任务：\n$taskContext',
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 50));
    return _decodeCompatibleAIResponse(response);
  }

  Future<String> summarizeArticle({
    required SyncSettings syncSettings,
    required PersonalRSSArticle article,
  }) async {
    final source = article.content.trim().isEmpty
        ? article.summary
        : article.content;
    if (aiSettings.provider == PersonalAIProvider.selfHosted) {
      if (!syncSettings.isConfigured) {
        throw StateError('请先在设置中配置自托管服务器');
      }
      final response = await _client
          .post(
            _endpoint(syncSettings.serverUrl, '/v1/ai'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${syncSettings.token}',
            },
            body: jsonEncode({
              'mode': 'rss_summary',
              'title': article.title,
              'content': source,
            }),
          )
          .timeout(const Duration(seconds: 50));
      return _decodeAIResponse(response);
    }
    return askAI(
      syncSettings: syncSettings,
      prompt: '请总结这篇文章，只给一句结论、三个关键点和一个行动建议：\n\n${article.title}\n\n$source',
    );
  }

  Future<String> translateArticle({
    required SyncSettings syncSettings,
    required PersonalRSSArticle article,
  }) async {
    final source = article.content.trim().isEmpty
        ? article.summary.trim()
        : article.content.trim();
    if (source.isEmpty) throw StateError('这篇文章没有可翻译的正文');
    if (aiSettings.provider == PersonalAIProvider.selfHosted) {
      if (!syncSettings.isConfigured) {
        throw StateError('请先在设置中配置自托管服务器');
      }
      final response = await _client
          .post(
            _endpoint(syncSettings.serverUrl, '/v1/ai'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${syncSettings.token}',
            },
            body: jsonEncode({
              'mode': 'rss_translation',
              'content': jsonEncode([source]),
            }),
          )
          .timeout(const Duration(seconds: 80));
      final raw = _decodeAIResponse(response)
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final decoded = jsonDecode(raw);
      if (decoded is List && decoded.isNotEmpty && decoded.first is String) {
        return decoded.first as String;
      }
      throw StateError('AI 返回的翻译无法识别');
    }

    final key = await readAIKey();
    if (key.isEmpty) throw StateError('请先在设置中填写 AI API 密钥');
    final endpoint = aiSettings.endpoint.trim().isEmpty
        ? aiSettings.provider.defaultEndpoint
        : aiSettings.endpoint.trim();
    final model = aiSettings.model.trim().isEmpty
        ? aiSettings.provider.defaultModel
        : aiSettings.model.trim();
    final response = await _client
        .post(
          Uri.parse(endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $key',
          },
          body: jsonEncode({
            'model': model,
            'temperature': 0.1,
            'messages': [
              {
                'role': 'system',
                'content':
                    '把用户提供的文章完整翻译为自然、准确的简体中文。保留段落，不总结、不删减、不增加说明。',
              },
              {'role': 'user', 'content': source},
            ],
          }),
        )
        .timeout(const Duration(seconds: 80));
    return _decodeCompatibleAIResponse(response);
  }

  Future<void> addFeed(String rawUrl, {String folder = '未分类'}) async {
    final uri = _safeHttpUri(rawUrl);
    if (_subscriptions.any((item) => item.feedUrl == uri.toString())) {
      throw StateError('这个订阅已经添加过了');
    }
    final response = await _client
        .get(uri, headers: const {'Accept': 'application/rss+xml, application/atom+xml, application/xml, text/xml'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('订阅地址无法访问（HTTP ${response.statusCode}）');
    }
    final parsed = _parseFeed(response.bodyBytes, uri);
    final now = DateTime.now().toUtc();
    final subscription = PersonalRSSSubscription(
      id: _stableId(uri.toString()),
      title: parsed.title,
      feedUrl: uri.toString(),
      siteUrl: parsed.siteUrl,
      folder: folder.trim().isEmpty ? '未分类' : folder.trim(),
      createdAt: now,
      updatedAt: now,
    );
    _subscriptions.add(subscription);
    _mergeArticles(subscription, parsed.items);
    _rssUpdatedAt = now;
    await _save();
    notifyListeners();
  }

  Future<void> removeFeed(PersonalRSSSubscription subscription) async {
    _subscriptions.removeWhere((item) => item.id == subscription.id);
    _articles.removeWhere((item) => item.feedId == subscription.id);
    _rssUpdatedAt = DateTime.now().toUtc();
    await _save();
    notifyListeners();
  }

  Future<void> refreshFeeds() async {
    if (refreshingRSS || _subscriptions.isEmpty) return;
    refreshingRSS = true;
    lastError = null;
    notifyListeners();
    try {
      for (final subscription in [..._subscriptions]) {
        try {
          final response = await _client
              .get(
                Uri.parse(subscription.feedUrl),
                headers: const {
                  'Accept':
                      'application/rss+xml, application/atom+xml, application/xml, text/xml',
                },
              )
              .timeout(const Duration(seconds: 15));
          if (response.statusCode < 200 || response.statusCode >= 300) continue;
          final parsed = _parseFeed(
            response.bodyBytes,
            Uri.parse(subscription.feedUrl),
          );
          _mergeArticles(subscription, parsed.items);
        } on Object catch (error) {
          lastError = '部分订阅刷新失败：$error';
        }
      }
      await _save();
    } finally {
      refreshingRSS = false;
      notifyListeners();
    }
  }

  void markRead(PersonalRSSArticle article, {bool read = true}) {
    final index = _articles.indexWhere((item) => item.id == article.id);
    if (index < 0) return;
    _articles[index] = _articles[index].copyWith(isRead: read);
    _rssUpdatedAt = DateTime.now().toUtc();
    unawaited(_save());
    notifyListeners();
  }

  void toggleStarred(PersonalRSSArticle article) {
    final index = _articles.indexWhere((item) => item.id == article.id);
    if (index < 0) return;
    _articles[index] = _articles[index].copyWith(
      isStarred: !_articles[index].isStarred,
    );
    _rssUpdatedAt = DateTime.now().toUtc();
    unawaited(_save());
    notifyListeners();
  }

  Future<void> syncRSS(SyncSettings settings) async {
    if (!settings.isConfigured) return;
    final response = await _client
        .post(
          _endpoint(settings.serverUrl, '/v1/sync'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${settings.token}',
          },
          body: jsonEncode({
            'deviceId': settings.deviceName,
            'tasks': const <Object>[],
            'rss': _rssSyncDocument(),
          }),
        )
        .timeout(const Duration(seconds: 35));
    if (response.statusCode < 200 || response.statusCode >= 300) return;
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['rss'] is! Map) return;
    final remote = Map<String, Object?>.from(decoded['rss'] as Map);
    final remoteUpdated = DateTime.tryParse(remote['updatedAt'] as String? ?? '');
    if (remoteUpdated == null || remoteUpdated.isBefore(_rssUpdatedAt)) return;
    final rawSubscriptions = remote['subscriptions'];
    final folderTitles = <String, String>{};
    final rawFolders = remote['folders'];
    if (rawFolders is List) {
      for (final raw in rawFolders.whereType<Map>()) {
        final folder = Map<String, Object?>.from(raw);
        final id = folder['id'] as String?;
        final title = folder['title'] as String?;
        if (id != null && title != null && title.trim().isNotEmpty) {
          folderTitles[id] = title.trim();
        }
      }
    }
    if (rawSubscriptions is List) {
      _subscriptions
        ..clear()
        ..addAll(
          rawSubscriptions.whereType<Map>().map(
            (value) => PersonalRSSSubscription.fromJson(
              Map<String, Object?>.from(value),
              folderTitles: folderTitles,
            ),
          ),
        );
    }
    final states = remote['articleStates'];
    if (states is List) {
      for (final raw in states.whereType<Map>()) {
        final state = Map<String, Object?>.from(raw);
        final index = _articles.indexWhere((item) => item.id == state['id']);
        if (index < 0) continue;
        _articles[index] = _articles[index].copyWith(
          isRead: state['isRead'] == true,
          isStarred: state['starredAt'] != null,
        );
      }
    }
    _rssUpdatedAt = remoteUpdated.toUtc();
    await _save();
    notifyListeners();
  }

  Map<String, Object?> _rssSyncDocument() => {
    'subscriptions': _subscriptions.map((item) => item.toJson()).toList(),
    'folders': folders
        .where((folder) => folder != '全部' && folder != '未分类')
        .map(
          (folder) => {
            'id': _stableId(folder),
            'title': folder,
            'createdAt': _rssUpdatedAt.toIso8601String(),
            'updatedAt': _rssUpdatedAt.toIso8601String(),
          },
        )
        .toList(),
    'articleStates': _articles
        .where((item) => item.isRead || item.isStarred)
        .map(
          (item) => {
            'id': item.id,
            'isRead': item.isRead,
            'starredAt': item.isStarred
                ? _rssUpdatedAt.toIso8601String()
                : null,
            'readAt': item.isRead ? _rssUpdatedAt.toIso8601String() : null,
            'readingProgress': item.isRead ? 1.0 : 0.0,
            'updatedAt': _rssUpdatedAt.toIso8601String(),
          },
        )
        .toList(),
    'updatedAt': _rssUpdatedAt.toIso8601String(),
  };

  Future<void> _refreshQuote() async {
    try {
      final response = await _client
          .get(
            Uri.parse('https://v1.hitokoto.cn/?c=d&c=i&c=k'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map) return;
      final content = (data['hitokoto'] as String? ?? '').trim();
      if (content.isEmpty || content.length > 80) return;
      quote = DailyQuote(content, (data['from'] as String? ?? '一言').trim());
    } on Object {
      // Keep the locally cached quote when offline.
    }
  }

  Future<void> _refreshWeather() async {
    final key = await readWeatherKey();
    if (key.isEmpty || weatherHost.isEmpty) return;
    try {
      final uri = Uri.https(weatherHost, '/v7/weather/now', {
        'location': weatherLocationId,
        'key': key,
      });
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map || data['code']?.toString() != '200') return;
      final now = data['now'];
      if (now is! Map) return;
      weather = WeatherSnapshot(
        city: weatherCity,
        temperature: now['temp']?.toString() ?? '--',
        description: now['text']?.toString() ?? '',
        iconCode: now['icon']?.toString() ?? '999',
      );
    } on Object {
      // Keep cached weather data.
    }
  }

  String _decodeAIResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('AI 请求失败（HTTP ${response.statusCode}）');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['text'] is! String) {
      throw StateError('AI 返回了无法识别的数据');
    }
    return decoded['text'] as String;
  }

  String _decodeCompatibleAIResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('AI 请求失败（HTTP ${response.statusCode}）');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['choices'] is! List) {
      throw StateError('AI 返回了无法识别的数据');
    }
    final choices = decoded['choices'] as List;
    if (choices.isEmpty || choices.first is! Map) {
      throw StateError('AI 没有返回内容');
    }
    final message = (choices.first as Map)['message'];
    if (message is! Map || message['content'] is! String) {
      throw StateError('AI 没有返回内容');
    }
    return message['content'] as String;
  }

  void _mergeArticles(
    PersonalRSSSubscription subscription,
    List<_ParsedRSSItem> incoming,
  ) {
    final existing = {for (final item in _articles) item.id: item};
    for (final item in incoming.take(120)) {
      final id = _stableId('${subscription.id}|${item.id}|${item.link}');
      final old = existing[id];
      final next = PersonalRSSArticle(
        id: id,
        feedId: subscription.id,
        feedTitle: subscription.title,
        title: item.title,
        summary: _plainText(item.summary),
        content: _plainText(item.content),
        link: item.link,
        author: item.author,
        publishedAt: item.publishedAt,
        fetchedAt: DateTime.now().toUtc(),
        isRead: old?.isRead ?? false,
        isStarred: old?.isStarred ?? false,
      );
      final index = _articles.indexWhere((article) => article.id == id);
      if (index < 0) {
        _articles.add(next);
      } else {
        _articles[index] = next;
      }
    }
    if (_articles.length > 1000) {
      final sorted = articles.take(1000).toSet();
      _articles.removeWhere((item) => !sorted.contains(item));
    }
  }

  _ParsedRSSDocument _parseFeed(List<int> bytes, Uri feedUri) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final document = XmlDocument.parse(text);
    final channel = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'channel')
        .firstOrNull;
    final root = channel ?? document.rootElement;
    final title = _childText(root, 'title').trim();
    final atom = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'entry')
        .toList();
    final rss = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'item')
        .toList();
    final entries = rss.isNotEmpty ? rss : atom;
    if (entries.isEmpty) throw StateError('没有识别到 RSS 或 Atom 内容');
    final items = entries.map((element) {
      final linkElement = _child(element, 'link');
      final link = (linkElement?.getAttribute('href') ?? linkElement?.innerText ?? '')
          .trim();
      final guid = _childText(element, 'guid').trim();
      final content = _childText(element, 'encoded').trim().isNotEmpty
          ? _childText(element, 'encoded')
          : _childText(element, 'content');
      final summary = _childText(element, 'description').trim().isNotEmpty
          ? _childText(element, 'description')
          : _childText(element, 'summary');
      final date = _childText(element, 'pubDate').trim().isNotEmpty
          ? _childText(element, 'pubDate')
          : _childText(element, 'updated');
      return _ParsedRSSItem(
        id: guid.isEmpty ? link : guid,
        title: _plainText(_childText(element, 'title')).trim().isEmpty
            ? '无标题'
            : _plainText(_childText(element, 'title')).trim(),
        summary: summary,
        content: content,
        link: link,
        author: _childText(element, 'author').trim().isEmpty
            ? null
            : _childText(element, 'author').trim(),
        publishedAt: DateTime.tryParse(date)?.toUtc(),
      );
    }).toList();
    final siteLink = _child(root, 'link');
    return _ParsedRSSDocument(
      title: title.isEmpty ? feedUri.host : title,
      siteUrl: (siteLink?.getAttribute('href') ?? siteLink?.innerText)?.trim(),
      items: items,
    );
  }

  XmlElement? _child(XmlElement parent, String name) => parent.children
      .whereType<XmlElement>()
      .where((element) => element.name.local == name)
      .firstOrNull;

  String _childText(XmlElement parent, String name) =>
      _child(parent, name)?.innerText ?? '';

  String _plainText(String html) => html
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_documentKey);
    if (encoded == null || encoded.isEmpty) return;
    try {
      final data = Map<String, Object?>.from(jsonDecode(encoded) as Map);
      final rawQuote = data['quote'];
      if (rawQuote is Map) {
        quote = DailyQuote.fromJson(Map<String, Object?>.from(rawQuote));
      }
      final rawWeather = data['weather'];
      if (rawWeather is Map) {
        weather = WeatherSnapshot.fromJson(
          Map<String, Object?>.from(rawWeather),
        );
      }
      final rawAI = data['ai'];
      if (rawAI is Map) {
        aiSettings = PersonalAISettings.fromJson(
          Map<String, Object?>.from(rawAI),
        );
      }
      weatherHost = data['weatherHost'] as String? ?? '';
      weatherLocationId = data['weatherLocationId'] as String? ?? '101010100';
      weatherCity = data['weatherCity'] as String? ?? '北京';
      _rssUpdatedAt =
          DateTime.tryParse(data['rssUpdatedAt'] as String? ?? '')?.toUtc() ??
          _rssUpdatedAt;
      final rawSubscriptions = data['subscriptions'];
      if (rawSubscriptions is List) {
        _subscriptions.addAll(
          rawSubscriptions.whereType<Map>().map(
            (value) => PersonalRSSSubscription.fromJson(
              Map<String, Object?>.from(value),
            ),
          ),
        );
      }
      final rawArticles = data['articles'];
      if (rawArticles is List) {
        _articles.addAll(
          rawArticles.whereType<Map>().map(
            (value) => PersonalRSSArticle.fromJson(
              Map<String, Object?>.from(value),
            ),
          ),
        );
      }
    } on Object {
      // Ignore a damaged optional cache. Core task data lives elsewhere.
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _documentKey,
      jsonEncode({
        'quote': quote.toJson(),
        'weather': weather?.toJson(),
        'ai': aiSettings.toJson(),
        'weatherHost': weatherHost,
        'weatherLocationId': weatherLocationId,
        'weatherCity': weatherCity,
        'rssUpdatedAt': _rssUpdatedAt.toUtc().toIso8601String(),
        'subscriptions': _subscriptions.map((item) => item.toJson()).toList(),
        'articles': _articles.map((item) => item.toJson()).toList(),
      }),
    );
  }

  Uri _safeHttpUri(String value) {
    final normalized = value.trim().contains('://')
        ? value.trim()
        : 'https://${value.trim()}';
    final uri = Uri.parse(normalized);
    if (!{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      throw StateError('请输入有效的 RSS 地址');
    }
    return uri;
  }

  Uri _endpoint(String base, String path) {
    final normalized = base.trim().contains('://')
        ? base.trim()
        : 'https://${base.trim()}';
    final uri = Uri.parse(normalized);
    return uri.replace(
      path: '${uri.path.replaceFirst(RegExp(r'/+$'), '')}$path',
      query: null,
      fragment: null,
    );
  }

  String _stableId(String value) {
    return _stableDocumentId(value);
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

String _stableDocumentId(String value) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

class _ParsedRSSDocument {
  const _ParsedRSSDocument({
    required this.title,
    required this.siteUrl,
    required this.items,
  });

  final String title;
  final String? siteUrl;
  final List<_ParsedRSSItem> items;
}

class _ParsedRSSItem {
  const _ParsedRSSItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.content,
    required this.link,
    required this.author,
    required this.publishedAt,
  });

  final String id;
  final String title;
  final String summary;
  final String content;
  final String link;
  final String? author;
  final DateTime? publishedAt;
}
