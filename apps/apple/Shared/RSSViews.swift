#if os(iOS)
import SafariServices
import SwiftUI
import UniformTypeIdentifiers
#if canImport(Translation)
import Translation
#endif

private enum RSSPresentation: String, Identifiable {
  case addSubscription
  case manageSubscriptions
  case manageFolders
  case preferences

  var id: String { rawValue }
}

private struct RSSWebsiteRoute: Identifiable {
  let id = UUID()
  let url: URL
}

private struct OPMLOutlineDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.xml, .data] }
  static var writableContentTypes: [UTType] { [.xml] }

  var text: String

  init(text: String = "") {
    self.text = text
  }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents,
          let text = String(data: data, encoding: .utf8)
    else { throw CocoaError(.fileReadCorruptFile) }
    self.text = text
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: Data(text.utf8))
  }
}

struct RSSScreen: View {
  @ObservedObject var store: RSSStore
  @State private var presentation: RSSPresentation?
  @State private var websiteRoute: RSSWebsiteRoute?
  @State private var selectedFeedID: String?
  @State private var selectedFolderID: String?
  @State private var filter = RSSArticleFilter.unread
  @State private var searchText = ""
  @State private var isImporting = false
  @State private var isExporting = false
  @State private var importMessage: String?

  init(store: RSSStore) {
    self.store = store
  }

  private var visibleArticles: [RSSArticle] {
    store.filteredArticles(
      filter: filter,
      query: searchText,
      feedID: selectedFeedID,
      folderID: selectedFolderID
    )
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          RSSReadingControls(
            filter: $filter,
            scopeTitle: selectedScopeTitle,
            folders: store.folders,
            subscriptions: store.subscriptions,
            selectedFolderID: selectedFolderID,
            selectedFeedID: selectedFeedID,
            selectAll: {
              selectedFolderID = nil
              selectedFeedID = nil
            },
            selectFolder: { folderID in
              selectedFolderID = folderID
              selectedFeedID = nil
            },
            selectFeed: { feedID in
              selectedFeedID = feedID
              selectedFolderID = nil
            }
          )
            .padding(.horizontal, 18)
            .padding(.bottom, 14)

          RSSContentState(
            hasSubscriptions: !store.subscriptions.isEmpty,
            isRefreshing: store.phase == .refreshing,
            articles: visibleArticles,
            searchText: searchText,
            filter: filter,
            addSubscription: { presentation = .addSubscription },
            openArticle: openArticle,
            toggleRead: store.toggleRead,
            toggleStarred: store.toggleStarred,
            setReadingProgress: store.setReadingProgress
          )
        }
        .padding(.bottom, 110)
      }
      .scrollIndicators(.visible)
      .qingxuScreen()
      .navigationTitle("阅读")
      .navigationBarTitleDisplayMode(.large)
      .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "搜索文章、来源或作者")
      .refreshable { await store.refresh() }
      .task { await store.refreshIfNeeded() }
      .toolbar { toolbarContent }
      .sheet(item: $presentation) { presentation in
        switch presentation {
        case .addSubscription:
          RSSAddSheet(store: store)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        case .manageSubscriptions:
          NavigationStack { RSSSubscriptionManager(store: store) }
        case .manageFolders:
          NavigationStack { RSSFolderManager(store: store) }
        case .preferences:
          NavigationStack { RSSPreferencesView(store: store) }
        }
      }
      .sheet(item: $websiteRoute) { route in
        RSSWebsiteView(url: route.url).ignoresSafeArea()
      }
      .fileImporter(
        isPresented: $isImporting,
        allowedContentTypes: [.xml, .data],
        allowsMultipleSelection: false,
        onCompletion: importOPML
      )
      .fileExporter(
        isPresented: $isExporting,
        document: OPMLOutlineDocument(text: store.exportOPML()),
        contentType: .xml,
        defaultFilename: "qingxu-rss.opml"
      ) { _ in }
      .alert("RSS", isPresented: Binding(
        get: { importMessage != nil },
        set: { if !$0 { importMessage = nil } }
      )) {
        Button("好", role: .cancel) { importMessage = nil }
      } message: {
        Text(importMessage ?? "")
      }
    }
  }

  private var subscriptionsForSelectedFolder: [RSSSubscription] {
    guard let selectedFolderID else { return store.subscriptions }
    return store.subscriptions.filter { $0.folderID == selectedFolderID }
  }

  private var selectedScopeTitle: String {
    if let selectedFeedID,
       let feed = store.subscriptions.first(where: { $0.id == selectedFeedID }) {
      return feed.title
    }
    if let selectedFolderID,
       let folder = store.folders.first(where: { $0.id == selectedFolderID }) {
      return folder.title
    }
    return "全部来源"
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .navigationBarTrailing) {
      Menu {
        Button { presentation = .addSubscription } label: {
          Label("添加订阅", systemImage: "plus")
        }
        Button { Task { await store.refresh() } } label: {
          Label("刷新", systemImage: "arrow.clockwise")
        }
        .disabled(store.subscriptions.isEmpty || store.phase == .refreshing)
        Divider()
        Button { presentation = .manageSubscriptions } label: {
          Label("管理订阅", systemImage: "dot.radiowaves.left.and.right")
        }
        Button { presentation = .manageFolders } label: {
          Label("管理分类", systemImage: "folder")
        }
        Button { presentation = .preferences } label: {
          Label("阅读与缓存", systemImage: "textformat.size")
        }
        Divider()
        Button { isImporting = true } label: {
          Label("导入 OPML", systemImage: "square.and.arrow.down")
        }
        Button { isExporting = true } label: {
          Label("导出 OPML", systemImage: "square.and.arrow.up")
        }
      } label: {
        if case .refreshing = store.phase {
          ProgressView().controlSize(.small)
        } else {
          Image(systemName: "ellipsis")
        }
      }
      .accessibilityLabel("RSS 管理")
    }
  }

  private func openArticle(_ article: RSSArticle) {
    store.markRead(article)
  }

  private func importOPML(_ result: Result<[URL], Error>) {
    Task { @MainActor in
      do {
        guard let url = try result.get().first else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let imported = await store.importOPML(try Data(contentsOf: url))
        importMessage = imported == 0 ? "没有发现新的订阅地址。" : "已导入 \(imported) 个订阅。"
      } catch {
        importMessage = "导入失败：\(error.localizedDescription)"
      }
    }
  }
}

private struct RSSReadingControls: View {
  @Binding var filter: RSSArticleFilter
  let scopeTitle: String
  let folders: [RSSFolder]
  let subscriptions: [RSSSubscription]
  let selectedFolderID: String?
  let selectedFeedID: String?
  let selectAll: () -> Void
  let selectFolder: (String) -> Void
  let selectFeed: (String) -> Void

  var body: some View {
    HStack(spacing: 10) {
      HStack(spacing: 2) {
        ForEach(RSSArticleFilter.allCases) { item in
          Button {
            withAnimation(.easeInOut(duration: 0.16)) { filter = item }
            UISelectionFeedbackGenerator().selectionChanged()
          } label: {
            Text(item.title)
              .font(.caption.weight(filter == item ? .semibold : .medium))
              .foregroundStyle(filter == item ? QingxuPalette.ink : QingxuPalette.quiet)
              .padding(.horizontal, 10)
              .frame(height: 34)
              .background(filter == item ? QingxuPalette.surface : Color.clear, in: Capsule())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(3)
      .background(QingxuPalette.secondaryBackground, in: Capsule())

      Menu {
        Button(action: selectAll) {
          Label("全部来源", systemImage: selectedFolderID == nil && selectedFeedID == nil ? "checkmark" : "square.grid.2x2")
        }
        if !folders.isEmpty {
          Section("分类") {
            ForEach(folders) { folder in
              Button { selectFolder(folder.id) } label: {
                Label(folder.title, systemImage: selectedFolderID == folder.id ? "checkmark" : "folder")
              }
            }
          }
        }
        if !subscriptions.isEmpty {
          Section("订阅") {
            ForEach(subscriptions) { subscription in
              Button { selectFeed(subscription.id) } label: {
                Label(subscription.title, systemImage: selectedFeedID == subscription.id ? "checkmark" : "dot.radiowaves.left.and.right")
              }
            }
          }
        }
      } label: {
        HStack(spacing: 6) {
          Text(scopeTitle).lineLimit(1)
          Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(QingxuPalette.ink)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(QingxuPalette.secondaryBackground, in: Capsule())
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
  }
}

private struct RSSFolderStrip: View {
  let folders: [RSSFolder]
  @Binding var selection: String?
  let onSelect: () -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        pill("全部分类", id: nil)
        ForEach(folders) { folder in pill(folder.title, id: folder.id) }
      }
      .padding(.horizontal, 18)
    }
  }

  private func pill(_ title: String, id: String?) -> some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) { selection = id }
      onSelect()
    } label: {
      Label(title, systemImage: id == nil ? "square.grid.2x2" : "folder.fill")
        .font(.caption.weight(.semibold))
        .foregroundStyle(selection == id ? QingxuPalette.accent : QingxuPalette.quiet)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(selection == id ? QingxuPalette.selected : QingxuPalette.surface, in: Capsule())
    }
    .buttonStyle(.plain)
  }
}

private struct RSSFeedStrip: View {
  let subscriptions: [RSSSubscription]
  let articles: [RSSArticle]
  @Binding var selection: String?

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        source(title: "所有来源", iconURL: nil, id: nil)
        ForEach(subscriptions) { subscription in
          source(
            title: subscription.title,
            iconURL: subscription.iconURL,
            id: subscription.id
          )
        }
      }
      .padding(.horizontal, 18)
    }
  }

  private func source(title: String, iconURL: String?, id: String?) -> some View {
    let unread = articles.lazy.filter { !$0.isRead && (id == nil || $0.feedID == id) }.count
    let selected = selection == id
    return Button {
      withAnimation(.easeInOut(duration: 0.2)) { selection = id }
    } label: {
      HStack(spacing: 7) {
        RSSSourceIcon(urlString: iconURL, size: 22)
        Text(title).lineLimit(1)
        if unread > 0 {
          Text("\(unread)")
            .font(.caption2.bold())
            .foregroundStyle(selected ? QingxuPalette.onAccent : QingxuPalette.accent)
        }
      }
      .font(.subheadline.weight(selected ? .semibold : .medium))
      .foregroundStyle(selected ? QingxuPalette.onAccent : QingxuPalette.ink)
      .padding(.horizontal, 12)
      .frame(height: 40)
      .background(selected ? QingxuPalette.accent : QingxuPalette.surface, in: Capsule())
    }
    .buttonStyle(.plain)
  }
}

private struct RSSSourceIcon: View {
  let urlString: String?
  let size: CGFloat

  var body: some View {
    Group {
      if let urlString, let url = URL(string: urlString) {
        AsyncImage(url: url) { image in
          image.resizable().scaledToFit()
        } placeholder: {
          Image(systemName: "dot.radiowaves.left.and.right")
        }
      } else {
        Image(systemName: "dot.radiowaves.left.and.right")
      }
    }
    .font(.caption)
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
  }
}

private struct RSSContentState: View {
  let hasSubscriptions: Bool
  let isRefreshing: Bool
  let articles: [RSSArticle]
  let searchText: String
  let filter: RSSArticleFilter
  let addSubscription: () -> Void
  let openArticle: (RSSArticle) -> Void
  let toggleRead: (RSSArticle) -> Void
  let toggleStarred: (RSSArticle) -> Void
  let setReadingProgress: (Double, String) -> Void

  var body: some View {
    if !hasSubscriptions {
      RSSWelcome(add: addSubscription)
    } else if articles.isEmpty {
      RSSEmptyArticles(isRefreshing: isRefreshing, searchText: searchText, filter: filter)
    } else {
      LazyVStack(spacing: 0) {
        ForEach(articles) { article in
          NavigationLink {
            RSSReaderView(
              article: article,
              openArticle: openArticle,
              toggleStarred: toggleStarred,
              setReadingProgress: setReadingProgress
            )
          } label: {
            RSSArticleLine(article: article)
          }
          .buttonStyle(.plain)
          .simultaneousGesture(TapGesture().onEnded { openArticle(article) })
          .contextMenu {
            Button { toggleRead(article) } label: {
              Label(article.isRead ? "标为未读" : "标为已读", systemImage: article.isRead ? "envelope.badge" : "checkmark")
            }
            Button { toggleStarred(article) } label: {
              Label(article.isStarred ? "取消收藏" : "收藏", systemImage: article.isStarred ? "star.slash" : "star")
            }
          }
          .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { toggleStarred(article) } label: {
              Label(article.isStarred ? "取消收藏" : "收藏", systemImage: article.isStarred ? "star.slash" : "star")
            }
            .tint(QingxuPalette.warning)
          }
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { toggleRead(article) } label: {
              Label(article.isRead ? "标为未读" : "标为已读", systemImage: article.isRead ? "envelope.badge" : "checkmark")
            }
            .tint(QingxuPalette.accent)
          }

          Divider()
            .overlay(QingxuPalette.separator)
            .padding(.leading, 50)
        }
      }
      .padding(.horizontal, 16)
      .background(
        QingxuPalette.surface,
        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .stroke(QingxuPalette.separator.opacity(0.55), lineWidth: 0.5)
      }
      .padding(.horizontal, 16)
    }
  }
}

private struct RSSArticleLine: View {
  let article: RSSArticle

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      RSSSourceIcon(urlString: nil, size: 28)
        .foregroundStyle(article.isRead ? QingxuPalette.faint : QingxuPalette.ink)
        .overlay(alignment: .topTrailing) {
          if !article.isRead {
            Circle()
              .fill(QingxuPalette.accent)
              .frame(width: 7, height: 7)
              .overlay(Circle().stroke(QingxuPalette.surface, lineWidth: 1.5))
              .offset(x: 2, y: -2)
          }
        }

      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(article.title)
            .font(article.isRead ? QingxuType.body : QingxuType.body.weight(.semibold))
            .foregroundStyle(QingxuPalette.ink)
            .lineLimit(3)
          Spacer(minLength: 4)
          if article.isStarred {
            Image(systemName: "star.fill")
              .font(.caption)
              .foregroundStyle(QingxuPalette.warning)
          }
        }
        if !article.summary.isEmpty {
          Text(article.summary)
            .font(.subheadline)
            .foregroundStyle(QingxuPalette.quiet)
            .lineLimit(2)
        }
        HStack(spacing: 6) {
          Text(article.feedTitle).lineLimit(1)
          if let author = article.author, !author.isEmpty {
            Text("·")
            Text(author).lineLimit(1)
          }
          if let date = article.publishedAt {
            Text("·")
            Text(date, style: .relative)
          }
        }
        .font(.caption)
        .foregroundStyle(QingxuPalette.faint)
      }
    }
    .padding(.vertical, 15)
    .contentShape(Rectangle())
  }
}

private struct RSSWelcome: View {
  let add: () -> Void

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "newspaper")
        .font(.system(size: 48, weight: .light))
        .foregroundStyle(QingxuPalette.accent)
      Text("建立自己的阅读流")
        .font(.title3.weight(.semibold))
      Text("添加 RSS、Atom 地址或网站首页，清序会自动寻找订阅源。")
        .font(.subheadline)
        .foregroundStyle(QingxuPalette.quiet)
        .multilineTextAlignment(.center)
      Button("添加第一个订阅", action: add)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(QingxuPalette.onAccent)
        .padding(.horizontal, 18)
        .frame(height: 42)
        .background(QingxuPalette.accent, in: Capsule())
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 32)
    .padding(.top, 110)
  }
}

private struct RSSEmptyArticles: View {
  let isRefreshing: Bool
  let searchText: String
  let filter: RSSArticleFilter

  var body: some View {
    VStack(spacing: 11) {
      if isRefreshing {
        ProgressView()
      } else {
        Image(systemName: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass")
          .font(.system(size: 38, weight: .light))
          .foregroundStyle(QingxuPalette.accent)
      }
      Text(title).font(.headline)
      Text(detail)
        .font(.subheadline)
        .foregroundStyle(QingxuPalette.quiet)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 110)
  }

  private var title: String {
    if isRefreshing { return "正在获取文章" }
    if !searchText.isEmpty { return "没有匹配的文章" }
    return filter == .starred ? "还没有收藏" : "已经读完了"
  }

  private var detail: String {
    if isRefreshing { return "稍等一下，新内容马上出现。" }
    if !searchText.isEmpty { return "换个关键词再试试。" }
    return filter == .starred ? "收藏的文章会保留在这里。" : "下拉刷新，或者去读点别的。"
  }
}

private struct RSSReaderView: View {
  @EnvironmentObject private var appStore: AppStore
  let article: RSSArticle
  let openArticle: (RSSArticle) -> Void
  let toggleStarred: (RSSArticle) -> Void
  let setReadingProgress: (Double, String) -> Void
  @State private var isStarred: Bool
  @State private var websiteRoute: RSSWebsiteRoute?
  @State private var resolvedText = ""
  @State private var isLoadingFullText = false
  @State private var isTranslating = false
  @State private var translatedTitle: String?
  @State private var translatedBody: String?
  @State private var showsOriginal = false
  @State private var translationUnavailable = false
  @State private var aiSummary: String?
  @State private var isSummarizing = false
  @State private var aiError: String?
  @AppStorage("qingxu.rss.reader.fontScale") private var fontScale = 1.0
  @AppStorage("qingxu.rss.reader.lineSpacing") private var readerLineSpacing = 7.0

  init(
    article: RSSArticle,
    openArticle: @escaping (RSSArticle) -> Void,
    toggleStarred: @escaping (RSSArticle) -> Void,
    setReadingProgress: @escaping (Double, String) -> Void
  ) {
    self.article = article
    self.openArticle = openArticle
    self.toggleStarred = toggleStarred
    self.setReadingProgress = setReadingProgress
    _isStarred = State(initialValue: article.isStarred)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text(article.feedTitle)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(QingxuPalette.accent)
        Text(displayedTitle)
          .font(.largeTitle.bold())
          .foregroundStyle(QingxuPalette.ink)
        HStack(spacing: 7) {
          if let author = article.author { Text(author) }
          if let date = article.publishedAt {
            if article.author != nil { Text("·") }
            Text(date.formatted(date: .abbreviated, time: .shortened))
          }
        }
        .font(.subheadline)
        .foregroundStyle(QingxuPalette.quiet)

        if let aiSummary {
          VStack(alignment: .leading, spacing: 9) {
            Label("AI 摘要", systemImage: "sparkles")
              .font(.subheadline.weight(.semibold))
            Text(aiSummary)
              .font(QingxuType.body)
              .foregroundStyle(QingxuPalette.ink)
              .lineSpacing(4)
          }
          .padding(.vertical, 4)
        }

        Divider().overlay(QingxuPalette.separator)

        if isLoadingFullText {
          HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("正在补全原文")
          }
          .font(.caption)
          .foregroundStyle(QingxuPalette.quiet)
        }

        Text(displayedBody)
          .font(.system(size: 17 * fontScale, weight: .regular))
          .foregroundStyle(QingxuPalette.ink)
          .lineSpacing(readerLineSpacing)
          .textSelection(.enabled)

        if translatedBody != nil, !showsOriginal {
          Label("译文已覆盖原文", systemImage: "character.bubble")
            .font(.caption)
            .foregroundStyle(QingxuPalette.quiet)
        }

        Color.clear
          .frame(height: 1)
          .onAppear { setReadingProgress(1, article.id) }

        if let url = URL(string: article.link), !article.link.isEmpty {
          Button {
            websiteRoute = RSSWebsiteRoute(url: url)
          } label: {
            Label("查看原网页", systemImage: "safari")
              .font(.subheadline.weight(.semibold))
              .frame(maxWidth: .infinity)
              .frame(height: 46)
              .background(QingxuPalette.selected, in: Capsule())
          }
          .buttonStyle(.plain)
          .padding(.top, 10)
        }
      }
      .frame(maxWidth: 720, alignment: .leading)
      .padding(22)
      .padding(.bottom, 80)
    }
    .qingxuScreen()
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { openArticle(article) }
    .task(id: article.id) { await loadFullTextIfNeeded() }
    .overlay {
      if isTranslating {
        translationWorker
      }
    }
    .toolbar {
      ToolbarItemGroup(placement: .navigationBarTrailing) {
        Button {
          Task { await summarize() }
        } label: {
          if isSummarizing {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: "sparkles")
          }
        }
        .disabled(isSummarizing)
        .accessibilityLabel("AI 总结")
        Button {
          if translatedBody != nil {
            withAnimation(.easeInOut(duration: 0.16)) { showsOriginal.toggle() }
          } else if #available(iOS 18.0, *) {
            isTranslating = true
          } else {
            translationUnavailable = true
          }
        } label: {
          if isTranslating {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: translatedBody != nil && !showsOriginal ? "textformat" : "character.bubble")
          }
        }
        .accessibilityLabel("翻译文章")
        Button {
          toggleStarred(article)
          isStarred.toggle()
        } label: {
          Image(systemName: isStarred ? "star.fill" : "star")
        }
        if let url = URL(string: article.link), !article.link.isEmpty {
          ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
        }
      }
    }
    .sheet(item: $websiteRoute) { route in
      RSSWebsiteView(url: route.url).ignoresSafeArea()
    }
    .alert("系统翻译不可用", isPresented: $translationUnavailable) {
      Button("好", role: .cancel) {}
    } message: {
      Text("原生中英互译需要 iOS 18 或更高版本。")
    }
    .alert("AI 暂时不可用", isPresented: Binding(
      get: { aiError != nil },
      set: { if !$0 { aiError = nil } }
    )) {
      Button("好", role: .cancel) { aiError = nil }
    } message: {
      Text(aiError ?? "")
    }
  }

  private var readerText: String {
    if !resolvedText.isEmpty { return resolvedText }
    let content = article.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return content.isEmpty ? article.summary : content
  }

  private var displayedTitle: String {
    if !showsOriginal, let translatedTitle, !translatedTitle.isEmpty { return translatedTitle }
    return article.title
  }

  private var displayedBody: String {
    if !showsOriginal, let translatedBody, !translatedBody.isEmpty { return translatedBody }
    return readerText
  }

  @ViewBuilder
  private var translationWorker: some View {
    #if canImport(Translation)
    if #available(iOS 18.0, *) {
      RSSInlineTranslationWorker(title: article.title, text: readerText) { title, body in
        translatedTitle = title
        translatedBody = body
        showsOriginal = false
        isTranslating = false
      } onFailure: {
        isTranslating = false
        translationUnavailable = true
      }
      .frame(width: 1, height: 1)
      .opacity(0.001)
    }
    #endif
  }

  private func loadFullTextIfNeeded() async {
    guard readerText.count < 1_200,
          let url = URL(string: article.link),
          !article.link.isEmpty
    else { return }
    await MainActor.run { isLoadingFullText = true }
    let fullText = await RSSArticleExtractor.fullText(from: url)
    await MainActor.run {
      if let fullText, fullText.count > readerText.count + 180 {
        resolvedText = fullText
        translatedBody = nil
      }
      isLoadingFullText = false
    }
  }

  @MainActor
  private func summarize() async {
    guard !isSummarizing else { return }
    isSummarizing = true
    defer { isSummarizing = false }
    do {
      aiSummary = try await QingxuAIClient().summarize(
        title: article.title,
        content: readerText,
        settings: appStore.syncSettings
      )
    } catch {
      aiError = error.localizedDescription
    }
  }
}

#if canImport(Translation)
@available(iOS 18.0, *)
private struct RSSInlineTranslationWorker: View {
  let title: String
  let text: String
  let onComplete: (String, String) -> Void
  let onFailure: () -> Void

  var body: some View {
    Color.clear
      .translationTask(source: nil, target: Locale.Language(identifier: "zh-Hans")) { session in
        do {
          let translatedTitle = try await session.translate(title).targetText
          var parts: [String] = []
          for chunk in text.translationChunks(maximumLength: 1_800) {
            parts.append(try await session.translate(chunk).targetText)
          }
          await MainActor.run { onComplete(translatedTitle, parts.joined(separator: "\n\n")) }
        } catch {
          await MainActor.run { onFailure() }
        }
      }
  }
}
#endif

private enum RSSArticleExtractor {
  static func fullText(from url: URL) async -> String? {
    do {
      var request = URLRequest(url: url)
      request.timeoutInterval = 18
      request.setValue(
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile Safari/604.1",
        forHTTPHeaderField: "User-Agent"
      )
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse,
            200..<400 ~= http.statusCode,
            data.count < 8_000_000,
            let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
      else { return nil }
      return extractReadableText(html)
    } catch {
      return nil
    }
  }

  private static func extractReadableText(_ html: String) -> String? {
    var cleaned = html
    for tag in ["script", "style", "svg", "nav", "header", "footer", "form", "aside"] {
      cleaned = cleaned.replacingOccurrences(
        of: "(?is)<\(tag)\\b[^>]*>.*?</\(tag)>",
        with: " ",
        options: .regularExpression
      )
    }
    let candidates = ["article", "main"]
    for tag in candidates {
      if let range = cleaned.range(of: "(?is)<\(tag)\\b[^>]*>(.*?)</\(tag)>", options: .regularExpression) {
        let candidate = readableText(String(cleaned[range]))
        if candidate.count > 500 { return candidate }
      }
    }
    let fallback = readableText(cleaned)
    return fallback.count > 500 ? fallback : nil
  }

  private static func readableText(_ html: String) -> String {
    var text = html
      .replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
      .replacingOccurrences(of: "(?i)</(p|div|h[1-6]|li|blockquote|section)>", with: "\n\n", options: .regularExpression)
      .replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
    let entities = [
      "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
      "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&mdash;": "—", "&ndash;": "–"
    ]
    for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
    text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
    text = text.replacingOccurrences(of: "\\n[ \\t]+", with: "\n", options: .regularExpression)
    text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private extension String {
  func translationChunks(maximumLength: Int) -> [String] {
    guard count > maximumLength else { return [self] }
    var result: [String] = []
    var buffer = ""
    for paragraph in components(separatedBy: "\n\n") {
      if buffer.count + paragraph.count + 2 > maximumLength, !buffer.isEmpty {
        result.append(buffer)
        buffer = ""
      }
      if paragraph.count > maximumLength {
        var start = paragraph.startIndex
        while start < paragraph.endIndex {
          let end = paragraph.index(start, offsetBy: maximumLength, limitedBy: paragraph.endIndex) ?? paragraph.endIndex
          result.append(String(paragraph[start..<end]))
          start = end
        }
      } else {
        buffer += buffer.isEmpty ? paragraph : "\n\n\(paragraph)"
      }
    }
    if !buffer.isEmpty { result.append(buffer) }
    return result
  }
}

private struct RSSWebsiteView: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> SFSafariViewController {
    let configuration = SFSafariViewController.Configuration()
    configuration.entersReaderIfAvailable = true
    configuration.barCollapsingEnabled = true
    let controller = SFSafariViewController(url: url, configuration: configuration)
    controller.dismissButtonStyle = .close
    controller.preferredControlTintColor = UIColor(QingxuPalette.accent)
    return controller
  }

  func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

private struct RSSAddSheet: View {
  @ObservedObject var store: RSSStore
  @Environment(\.dismiss) private var dismiss
  @State private var address = ""
  @State private var isAdding = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("订阅地址") {
          TextField("https://example.com/feed.xml", text: $address)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
        }
        Section {
          Text("可以填写 RSS、Atom 地址，也可以直接填写网站首页。")
            .font(.footnote)
            .foregroundStyle(QingxuPalette.quiet)
        }
        if let errorMessage {
          Section { Text(errorMessage).foregroundStyle(QingxuPalette.danger) }
        }
      }
      .qingxuScreen()
      .navigationTitle("添加 RSS")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button(isAdding ? "添加中…" : "添加") { Task { await add() } }
            .disabled(isAdding || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .fontWeight(.semibold)
        }
      }
    }
  }

  @MainActor
  private func add() async {
    isAdding = true
    defer { isAdding = false }
    do {
      try await store.addSubscription(address)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct RSSSubscriptionManager: View {
  @ObservedObject var store: RSSStore

  var body: some View {
    List {
      ForEach(store.subscriptions) { subscription in
        NavigationLink {
          RSSSubscriptionSettings(store: store, subscriptionID: subscription.id)
        } label: {
          HStack(spacing: 12) {
            RSSSourceIcon(urlString: subscription.iconURL, size: 32)
            VStack(alignment: .leading, spacing: 4) {
              Text(subscription.title).font(.body.weight(.medium))
              if let folder = store.folders.first(where: { $0.id == subscription.folderID }) {
                Text(folder.title).font(.caption).foregroundStyle(QingxuPalette.accent)
              } else {
                Text(subscription.feedURL).font(.caption).foregroundStyle(QingxuPalette.quiet).lineLimit(1)
              }
            }
            Spacer()
            if subscription.lastError != nil {
              Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(QingxuPalette.warning)
            }
          }
        }
        .swipeActions {
          Button(role: .destructive) { store.delete(subscription) } label: {
            Label("删除", systemImage: "trash")
          }
        }
      }
    }
    .qingxuScreen()
    .navigationTitle("管理订阅")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct RSSSubscriptionSettings: View {
  @ObservedObject var store: RSSStore
  let subscriptionID: String
  @State private var keywords = ""
  @State private var notificationMessage: String?

  private var subscription: RSSSubscription? {
    store.subscriptions.first { $0.id == subscriptionID }
  }

  var body: some View {
    Form {
      if let subscription {
        Section("分类") {
          Picker("所在分类", selection: Binding(
            get: { subscription.folderID ?? "" },
            set: { store.move(subscription, to: $0.isEmpty ? nil : $0) }
          )) {
            Text("未分类").tag("")
            ForEach(store.folders) { folder in Text(folder.title).tag(folder.id) }
          }
        }

        Section("新文章通知") {
          Toggle("允许此来源通知", isOn: Binding(
            get: { subscription.notificationsEnabled ?? false },
            set: { enabled in
              Task {
                let success = await store.updateNotificationSettings(
                  for: subscription,
                  enabled: enabled,
                  keywords: keywordList
                )
                if enabled, !success { notificationMessage = "请先在系统设置中允许通知。" }
              }
            }
          ))
          TextField("关键词，用逗号分隔；留空表示全部", text: $keywords)
            .onSubmit {
              Task {
                _ = await store.updateNotificationSettings(
                  for: subscription,
                  enabled: subscription.notificationsEnabled ?? false,
                  keywords: keywordList
                )
              }
            }
        }

        Section("订阅状态") {
          LabeledContent("地址", value: subscription.feedURL)
          LabeledContent("上次更新") {
            Text(subscription.lastFetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "尚未更新")
          }
          if let error = subscription.lastError {
            Text(error).foregroundStyle(QingxuPalette.danger)
          }
        }
      }
    }
    .qingxuScreen()
    .navigationTitle(subscription?.title ?? "订阅设置")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      keywords = subscription?.notificationKeywords?.joined(separator: "，") ?? ""
    }
    .alert("通知", isPresented: Binding(
      get: { notificationMessage != nil },
      set: { if !$0 { notificationMessage = nil } }
    )) {
      Button("好", role: .cancel) { notificationMessage = nil }
    } message: { Text(notificationMessage ?? "") }
  }

  private var keywordList: [String] {
    keywords
      .replacingOccurrences(of: "，", with: ",")
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}

private struct RSSFolderManager: View {
  @ObservedObject var store: RSSStore
  @State private var title = ""

  var body: some View {
    List {
      Section("新建分类") {
        HStack {
          TextField("例如：科技", text: $title)
          Button("添加") {
            store.createFolder(title: title)
            title = ""
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      Section("已有分类") {
        ForEach(store.folders) { folder in
          HStack {
            Label(folder.title, systemImage: "folder.fill")
            Spacer()
            Text("\(store.subscriptions.lazy.filter { $0.folderID == folder.id }.count)")
              .foregroundStyle(QingxuPalette.quiet)
          }
          .swipeActions {
            Button(role: .destructive) { store.deleteFolder(folder) } label: {
              Label("删除", systemImage: "trash")
            }
          }
        }
      }
    }
    .qingxuScreen()
    .navigationTitle("来源分类")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct RSSPreferencesView: View {
  @ObservedObject var store: RSSStore
  @AppStorage("qingxu.rss.reader.fontScale") private var fontScale = 1.0
  @AppStorage("qingxu.rss.reader.lineSpacing") private var lineSpacing = 7.0
  @State private var syncing = false
  @State private var syncMessage = ""

  var body: some View {
    Form {
      Section("原生阅读器") {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("字号")
            Spacer()
            Text("\(Int(fontScale * 100))%")
              .foregroundStyle(QingxuPalette.quiet)
          }
          Slider(value: $fontScale, in: 0.88...1.28, step: 0.04)
        }
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("行距")
            Spacer()
            Text("\(Int(lineSpacing))")
              .foregroundStyle(QingxuPalette.quiet)
          }
          Slider(value: $lineSpacing, in: 3...12, step: 1)
        }
      }

      Section("离线缓存") {
        LabeledContent("已缓存文章", value: "\(store.articles.count) 篇")
        LabeledContent(
          "占用空间",
          value: ByteCountFormatter.string(fromByteCount: Int64(store.cacheSizeBytes), countStyle: .file)
        )
        Button("清理已读且未收藏的文章", role: .destructive) {
          store.clearReadCache()
        }
      }

      Section("自托管同步") {
        Button(syncing ? "正在同步…" : "立即同步 RSS 状态") {
          Task { await sync() }
        }
        .disabled(syncing)
        if !syncMessage.isEmpty {
          Text(syncMessage).font(.footnote).foregroundStyle(QingxuPalette.quiet)
        }
        Text("同步订阅、分类、已读、收藏和阅读进度；文章正文只保存在本机。")
          .font(.footnote)
          .foregroundStyle(QingxuPalette.quiet)
      }
    }
    .qingxuScreen()
    .navigationTitle("阅读与缓存")
    .navigationBarTitleDisplayMode(.inline)
  }

  @MainActor
  private func sync() async {
    syncing = true
    syncMessage = await store.syncNow() ? "同步完成" : "未配置自动同步，或服务器暂时不可用"
    syncing = false
  }
}
#endif
