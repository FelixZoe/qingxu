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
          RSSFilterBar(selection: $filter)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

          if !store.folders.isEmpty {
            RSSFolderStrip(
              folders: store.folders,
              selection: $selectedFolderID,
              onSelect: { selectedFeedID = nil }
            )
            .padding(.bottom, 10)
          }

          if !store.subscriptions.isEmpty {
            RSSFeedStrip(
              subscriptions: subscriptionsForSelectedFolder,
              articles: store.articles,
              selection: $selectedFeedID
            )
            .padding(.bottom, 14)
          }

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
      .navigationTitle("RSS")
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

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .navigationBarLeading) {
      Menu {
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
        Image(systemName: "line.3.horizontal.decrease")
      }
      .accessibilityLabel("RSS 管理")
    }

    ToolbarItemGroup(placement: .navigationBarTrailing) {
      if case .refreshing = store.phase {
        ProgressView().controlSize(.small)
      } else {
        Button { Task { await store.refresh() } } label: {
          Image(systemName: "arrow.clockwise")
        }
        .disabled(store.subscriptions.isEmpty)
      }
      Button { presentation = .addSubscription } label: {
        Image(systemName: "plus")
      }
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

private struct RSSFilterBar: View {
  @Binding var selection: RSSArticleFilter

  var body: some View {
    HStack(spacing: 7) {
      ForEach(RSSArticleFilter.allCases) { filter in
        Button {
          withAnimation(.easeInOut(duration: 0.2)) { selection = filter }
          UISelectionFeedbackGenerator().selectionChanged()
        } label: {
          Text(filter.title)
            .font(.subheadline.weight(selection == filter ? .semibold : .medium))
            .foregroundStyle(selection == filter ? QingxuPalette.onAccent : QingxuPalette.quiet)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(selection == filter ? QingxuPalette.accent : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(4)
    .background(QingxuPalette.secondaryBackground, in: Capsule())
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
            .overlay(QingxuPalette.separator.opacity(0.7))
            .padding(.leading, 56)
        }
      }
      .padding(.horizontal, 18)
    }
  }
}

private struct RSSArticleLine: View {
  let article: RSSArticle

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Circle()
        .fill(article.isRead ? Color.clear : QingxuPalette.accent)
        .frame(width: 7, height: 7)
        .overlay(Circle().stroke(QingxuPalette.separator, lineWidth: article.isRead ? 0.7 : 0))
        .padding(.top, 8)

      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(article.title)
            .font(.body.weight(article.isRead ? .regular : .semibold))
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
    .padding(.vertical, 13)
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
  let article: RSSArticle
  let openArticle: (RSSArticle) -> Void
  let toggleStarred: (RSSArticle) -> Void
  let setReadingProgress: (Double, String) -> Void
  @State private var isStarred: Bool
  @State private var websiteRoute: RSSWebsiteRoute?
  @State private var showTranslation = false
  @State private var translationUnavailable = false
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
        Text(article.title)
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

        Divider().overlay(QingxuPalette.separator)

        Text(readerText)
          .font(.system(size: 17 * fontScale, weight: .regular, design: .rounded))
          .foregroundStyle(QingxuPalette.ink)
          .lineSpacing(readerLineSpacing)
          .textSelection(.enabled)

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
    .rssTranslationPresentation(isPresented: $showTranslation, text: translationText)
    .toolbar {
      ToolbarItemGroup(placement: .navigationBarTrailing) {
        Button {
          if #available(iOS 18.0, *) {
            showTranslation = true
          } else {
            translationUnavailable = true
          }
        } label: {
          Image(systemName: "character.bubble")
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
  }

  private var readerText: String {
    let content = article.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return content.isEmpty ? article.summary : content
  }

  private var translationText: String {
    [article.title, readerText].filter { !$0.isEmpty }.joined(separator: "\n\n")
  }
}

private extension View {
  @ViewBuilder
  func rssTranslationPresentation(isPresented: Binding<Bool>, text: String) -> some View {
    #if canImport(Translation)
    if #available(iOS 18.0, *) {
      translationPresentation(isPresented: isPresented, text: text)
    } else {
      self
    }
    #else
    self
    #endif
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
