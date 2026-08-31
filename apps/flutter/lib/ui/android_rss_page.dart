import 'package:flutter/material.dart';

import '../services/personal_hub_store.dart';
import '../state/task_controller.dart';
import 'design_system.dart';

enum _RSSFilter { unread, all, starred }

class AndroidRSSPage extends StatefulWidget {
  const AndroidRSSPage({
    required this.store,
    required this.controller,
    super.key,
  });

  final PersonalHubStore store;
  final TaskController controller;

  @override
  State<AndroidRSSPage> createState() => _AndroidRSSPageState();
}

class _AndroidRSSPageState extends State<AndroidRSSPage> {
  _RSSFilter _filter = _RSSFilter.unread;
  String _folder = '全部';

  List<PersonalRSSArticle> get _visibleArticles {
    final feedIds = _folder == '全部'
        ? null
        : widget.store.subscriptions
              .where((subscription) => subscription.folder == _folder)
              .map((subscription) => subscription.id)
              .toSet();
    return widget.store.articles.where((article) {
      if (feedIds != null && !feedIds.contains(article.feedId)) return false;
      return switch (_filter) {
        _RSSFilter.unread => !article.isRead,
        _RSSFilter.all => true,
        _RSSFilter.starred => article.isStarred,
      };
    }).toList();
  }

  Future<void> _addFeed() async {
    final result = await showModalBottomSheet<_NewFeed>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddFeedSheet(),
    );
    if (result == null || !mounted) return;
    try {
      await widget.store.addFeed(result.url, folder: result.folder);
      await widget.store.syncRSS(widget.controller.syncSettings);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final articles = _visibleArticles;
        return ColoredBox(
          color: palette.canvas,
          child: Stack(
            children: [
              RefreshIndicator(
                onRefresh: () async {
                  await widget.store.refreshFeeds();
                  await widget.store.syncRSS(widget.controller.syncSettings);
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                      sliver: SliverToBoxAdapter(child: _header(palette)),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    if (widget.store.subscriptions.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyRSS(onAdd: _addFeed),
                      )
                    else if (articles.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: const _NoRSSResults(),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 126),
                        sliver: SliverList.builder(
                          itemCount: articles.length,
                          itemBuilder: (context, index) => _ArticleLine(
                            article: articles[index],
                            onOpen: () => _openArticle(articles[index]),
                            onStar: () {
                              widget.store.toggleStarred(articles[index]);
                              widget.store.syncRSS(
                                widget.controller.syncSettings,
                              );
                            },
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
                  heroTag: 'android-rss-add',
                  onPressed: _addFeed,
                  elevation: 0,
                  highlightElevation: 0,
                  child: const Icon(Icons.add_rounded, size: 28),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(QingxuPalette palette) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RSS',
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 32,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '把来源收在一处，安静地读完',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: '刷新订阅',
            onPressed: widget.store.refreshingRSS
                ? null
                : () async {
                    await widget.store.refreshFeeds();
                    await widget.store.syncRSS(widget.controller.syncSettings);
                  },
            icon: widget.store.refreshingRSS
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 1.8),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      const SizedBox(height: 22),
      Row(
        children: [
          Expanded(
            child: SegmentedButton<_RSSFilter>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _RSSFilter.unread, label: Text('未读')),
                ButtonSegment(value: _RSSFilter.all, label: Text('全部')),
                ButtonSegment(value: _RSSFilter.starred, label: Text('收藏')),
              ],
              selected: {_filter},
              onSelectionChanged: (value) =>
                  setState(() => _filter = value.first),
            ),
          ),
          const SizedBox(width: 10),
          PopupMenuButton<String>(
            tooltip: '按来源分类',
            initialValue: _folder,
            onSelected: (value) => setState(() => _folder = value),
            itemBuilder: (_) => widget.store.folders
                .map(
                  (folder) => PopupMenuItem(
                    value: folder,
                    child: Text(folder),
                  ),
                )
                .toList(),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.tune_rounded, size: 18),
                  const SizedBox(width: 7),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 72),
                    child: Text(
                      _folder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ],
  );

  Future<void> _openArticle(PersonalRSSArticle article) async {
    widget.store.markRead(article);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: QingxuPalette.of(context).canvas,
      builder: (_) => _RSSReader(
        article: article.copyWith(isRead: true),
        store: widget.store,
        controller: widget.controller,
      ),
    );
    await widget.store.syncRSS(widget.controller.syncSettings);
  }
}

class _ArticleLine extends StatelessWidget {
  const _ArticleLine({
    required this.article,
    required this.onOpen,
    required this.onStar,
  });

  final PersonalRSSArticle article;
  final VoidCallback onOpen;
  final VoidCallback onStar;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final published = article.publishedAt?.toLocal();
    final date = published == null
        ? ''
        : '${published.month}月${published.day}日';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      article.feedTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(date, style: TextStyle(color: palette.faint, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      article.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: article.isRead ? palette.muted : palette.ink,
                        fontSize: 17,
                        height: 1.38,
                        fontWeight: article.isRead
                            ? FontWeight.w500
                            : FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: article.isStarred ? '取消收藏' : '收藏',
                    onPressed: onStar,
                    icon: Icon(
                      article.isStarred
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: article.isStarred ? palette.accent : palette.faint,
                    ),
                  ),
                ],
              ),
              if (article.summary.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  article.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 17),
              Divider(height: 1, color: palette.border),
            ],
          ),
        ),
      ),
    );
  }
}

class _RSSReader extends StatefulWidget {
  const _RSSReader({
    required this.article,
    required this.store,
    required this.controller,
  });

  final PersonalRSSArticle article;
  final PersonalHubStore store;
  final TaskController controller;

  @override
  State<_RSSReader> createState() => _RSSReaderState();
}

class _RSSReaderState extends State<_RSSReader> {
  String? _summary;
  String? _translation;
  bool _summarizing = false;
  bool _translating = false;

  Future<void> _summarize() async {
    if (_summarizing) return;
    setState(() => _summarizing = true);
    try {
      final value = await widget.store.summarizeArticle(
        syncSettings: widget.controller.syncSettings,
        article: widget.article,
      );
      if (mounted) setState(() => _summary = value);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _summarizing = false);
    }
  }

  Future<void> _translate() async {
    if (_translation != null) {
      setState(() => _translation = null);
      return;
    }
    if (_translating) return;
    setState(() => _translating = true);
    try {
      final value = await widget.store.translateArticle(
        syncSettings: widget.controller.syncSettings,
        article: widget.article,
      );
      if (mounted) setState(() => _translation = value);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    final originalBody = widget.article.content.trim().isEmpty
        ? widget.article.summary
        : widget.article.content;
    final body = _translation ?? originalBody;
    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(widget.article.feedTitle),
        actions: [
          TextButton(
            onPressed: _translating ? null : _translate,
            child: Text(
              _translating
                  ? '翻译中…'
                  : _translation == null
                  ? '翻译'
                  : '原文',
            ),
          ),
          IconButton(
            tooltip: 'AI 总结',
            onPressed: _summarizing ? null : _summarize,
            icon: _summarizing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 1.8),
                  )
                : const Icon(Icons.auto_awesome_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
        children: [
          Text(
            widget.article.title,
            style: TextStyle(
              color: palette.ink,
              fontSize: 28,
              height: 1.22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            [widget.article.feedTitle, widget.article.author]
                .whereType<String>()
                .where((value) => value.trim().isNotEmpty)
                .join(' · '),
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
          if (_summary != null) ...[
            const SizedBox(height: 24),
            QingxuSurface(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('AI 摘要', style: TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(_summary!, style: const TextStyle(height: 1.65)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          Text(
            body.isEmpty ? '这个订阅没有提供正文。' : body,
            style: TextStyle(
              color: palette.ink,
              fontSize: 17,
              height: 1.75,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRSS extends StatelessWidget {
  const _EmptyRSS({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 48, 28, 130),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.rss_feed_rounded, size: 42, color: palette.faint),
          const SizedBox(height: 22),
          Text(
            '还没有订阅',
            style: TextStyle(
              color: palette.ink,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '添加 RSS 或 Atom 地址，按来源分类阅读',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, fontSize: 14),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加订阅'),
          ),
        ],
      ),
    );
  }
}

class _NoRSSResults extends StatelessWidget {
  const _NoRSSResults();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.only(bottom: 100),
      child: Text('这里暂时没有文章'),
    ),
  );
}

class _NewFeed {
  const _NewFeed(this.url, this.folder);

  final String url;
  final String folder;
}

class _AddFeedSheet extends StatefulWidget {
  const _AddFeedSheet();

  @override
  State<_AddFeedSheet> createState() => _AddFeedSheetState();
}

class _AddFeedSheetState extends State<_AddFeedSheet> {
  final _url = TextEditingController();
  final _folder = TextEditingController(text: '未分类');

  @override
  void dispose() {
    _url.dispose();
    _folder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = QingxuPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: Material(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '添加订阅',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _url,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'RSS 或 Atom 地址'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _folder,
                decoration: const InputDecoration(labelText: '分类'),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final value = _url.text.trim();
                    if (value.isEmpty) return;
                    Navigator.pop(
                      context,
                      _NewFeed(value, _folder.text.trim()),
                    );
                  },
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
