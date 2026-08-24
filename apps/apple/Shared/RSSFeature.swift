import Combine
import Foundation
import SwiftUI
#if os(iOS)
import SafariServices
#endif

struct RSSSubscription: Codable, Identifiable, Hashable {
  var id: String
  var title: String
  var feedURL: String
  var siteURL: String?
  var createdAt: Date
  var lastFetchedAt: Date?
}

struct RSSArticle: Codable, Identifiable, Hashable {
  var id: String
  var feedID: String
  var feedTitle: String
  var title: String
  var summary: String
  var link: String
  var author: String?
  var publishedAt: Date?
  var fetchedAt: Date
  var isRead: Bool
}

private struct RSSDocument {
  var title: String
  var siteURL: String?
  var feedURL: URL
  var items: [RSSParsedItem]
}

private struct RSSParsedItem {
  var id: String
  var title: String
  var summary: String
  var link: String
  var author: String?
  var publishedAt: Date?
}

enum RSSStorePhase: Equatable {
  case idle
  case refreshing
  case failed(String)
}

enum RSSFeatureError: LocalizedError {
  case invalidURL
  case invalidResponse
  case unsupportedFeed
  case duplicateFeed

  var errorDescription: String? {
    switch self {
    case .invalidURL: "订阅地址格式不正确"
    case .invalidResponse: "服务器返回了无效响应"
    case .unsupportedFeed: "没有识别到 RSS 或 Atom 内容"
    case .duplicateFeed: "这个订阅已经添加过了"
    }
  }
}

@MainActor
final class RSSStore: ObservableObject {
  @Published private(set) var subscriptions: [RSSSubscription]
  @Published private(set) var articles: [RSSArticle]
  @Published private(set) var phase: RSSStorePhase = .idle

  private let client = RSSClient()

  init() {
    subscriptions = QingxuFiles.load(
      [RSSSubscription].self,
      name: "rss-subscriptions.json"
    ) ?? []
    articles = QingxuFiles.load([RSSArticle].self, name: "rss-articles.json") ?? []
  }

  var unreadCount: Int { articles.lazy.filter { !$0.isRead }.count }

  func refreshIfNeeded() async {
    guard !subscriptions.isEmpty else { return }
    let newestFetch = subscriptions.compactMap(\.lastFetchedAt).max() ?? .distantPast
    guard Date().timeIntervalSince(newestFetch) > 10 * 60 else { return }
    await refresh()
  }

  func addSubscription(_ rawAddress: String) async throws {
    let address = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !address.isEmpty else { throw RSSFeatureError.invalidURL }
    let normalized = address.contains("://") ? address : "https://\(address)"
    guard let url = URL(string: normalized), url.host != nil else {
      throw RSSFeatureError.invalidURL
    }

    phase = .refreshing
    do {
      let document = try await client.loadFeed(from: url)
      guard !subscriptions.contains(where: { $0.feedURL == document.feedURL.absoluteString }) else {
        throw RSSFeatureError.duplicateFeed
      }
      let now = Date()
      let subscription = RSSSubscription(
        id: UUID().uuidString,
        title: document.title,
        feedURL: document.feedURL.absoluteString,
        siteURL: document.siteURL,
        createdAt: now,
        lastFetchedAt: now
      )
      subscriptions.append(subscription)
      subscriptions.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
      merge(document.items, into: subscription, fetchedAt: now)
      persist()
      phase = .idle
    } catch {
      phase = .failed(error.localizedDescription)
      throw error
    }
  }

  func refresh() async {
    guard phase != .refreshing, !subscriptions.isEmpty else { return }
    phase = .refreshing
    var failures = 0

    for subscription in subscriptions {
      guard !Task.isCancelled, let url = URL(string: subscription.feedURL) else { continue }
      do {
        let document = try await client.loadFeed(from: url)
        let now = Date()
        merge(document.items, into: subscription, fetchedAt: now)
        if let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) {
          subscriptions[index].title = document.title
          subscriptions[index].siteURL = document.siteURL
          subscriptions[index].feedURL = document.feedURL.absoluteString
          subscriptions[index].lastFetchedAt = now
        }
      } catch is CancellationError {
        phase = .idle
        return
      } catch {
        failures += 1
      }
    }

    sortAndTrimArticles()
    persist()
    phase = failures == 0 ? .idle : .failed("有 \(failures) 个订阅刷新失败")
  }

  func markRead(_ article: RSSArticle) {
    guard let index = articles.firstIndex(where: { $0.id == article.id }) else { return }
    articles[index].isRead = true
    persist()
  }

  func markAllRead() {
    for index in articles.indices { articles[index].isRead = true }
    persist()
  }

  func delete(_ subscription: RSSSubscription) {
    subscriptions.removeAll { $0.id == subscription.id }
    articles.removeAll { $0.feedID == subscription.id }
    persist()
  }

  private func merge(
    _ incoming: [RSSParsedItem],
    into subscription: RSSSubscription,
    fetchedAt: Date
  ) {
    var existing = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })
    for item in incoming {
      let stableID = "\(subscription.id):\(item.id)"
      let old = existing[stableID]
      existing[stableID] = RSSArticle(
        id: stableID,
        feedID: subscription.id,
        feedTitle: subscription.title,
        title: item.title,
        summary: item.summary,
        link: item.link,
        author: item.author,
        publishedAt: item.publishedAt,
        fetchedAt: old?.fetchedAt ?? fetchedAt,
        isRead: old?.isRead ?? false
      )
    }
    articles = Array(existing.values)
    sortAndTrimArticles()
  }

  private func sortAndTrimArticles() {
    articles.sort {
      ($0.publishedAt ?? $0.fetchedAt) > ($1.publishedAt ?? $1.fetchedAt)
    }
    if articles.count > 500 { articles.removeLast(articles.count - 500) }
  }

  private func persist() {
    try? QingxuFiles.save(subscriptions, name: "rss-subscriptions.json")
    try? QingxuFiles.save(articles, name: "rss-articles.json")
  }
}

private struct RSSClient {
  func loadFeed(from requestedURL: URL) async throws -> RSSDocument {
    let (data, response) = try await fetch(requestedURL)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw RSSFeatureError.invalidResponse
    }

    if let document = RSSXMLFeedParser.parse(
      data: data,
      sourceURL: response.url ?? requestedURL
    ) {
      return document
    }
    if let discoveredURL = discoverFeedURL(in: data, baseURL: response.url ?? requestedURL) {
      let (feedData, feedResponse) = try await fetch(discoveredURL)
      guard let http = feedResponse as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            let document = RSSXMLFeedParser.parse(
              data: feedData,
              sourceURL: feedResponse.url ?? discoveredURL
            )
      else { throw RSSFeatureError.unsupportedFeed }
      return document
    }
    throw RSSFeatureError.unsupportedFeed
  }

  private func fetch(_ url: URL) async throws -> (Data, URLResponse) {
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.setValue(
      "application/rss+xml, application/atom+xml, application/xml, text/xml, text/html;q=0.8",
      forHTTPHeaderField: "Accept"
    )
    request.setValue("QingxuRSS/1.0", forHTTPHeaderField: "User-Agent")
    let result = try await URLSession.shared.data(for: request)
    guard result.0.count <= 10 * 1024 * 1024 else { throw RSSFeatureError.invalidResponse }
    return result
  }

  private func discoverFeedURL(in data: Data, baseURL: URL) -> URL? {
    guard let html = String(data: data, encoding: .utf8) else { return nil }
    let tagPattern = #"<link\b[^>]*>"#
    guard let tagRegex = try? NSRegularExpression(pattern: tagPattern, options: [.caseInsensitive]) else {
      return nil
    }
    let range = NSRange(html.startIndex..., in: html)
    for match in tagRegex.matches(in: html, range: range) {
      guard let tagRange = Range(match.range, in: html) else { continue }
      let tag = String(html[tagRange])
      let lower = tag.lowercased()
      guard lower.contains("application/rss+xml") || lower.contains("application/atom+xml") else {
        continue
      }
      guard let hrefRegex = try? NSRegularExpression(
        pattern: #"href\s*=\s*["']([^"']+)["']"#,
        options: [.caseInsensitive]
      ) else { continue }
      let hrefRange = NSRange(tag.startIndex..., in: tag)
      guard let hrefMatch = hrefRegex.firstMatch(in: tag, range: hrefRange),
            let valueRange = Range(hrefMatch.range(at: 1), in: tag)
      else { continue }
      return URL(string: String(tag[valueRange]), relativeTo: baseURL)?.absoluteURL
    }
    return nil
  }
}

private final class RSSXMLFeedParser: NSObject, XMLParserDelegate {
  private struct Draft {
    var id = ""
    var title = ""
    var summary = ""
    var link = ""
    var author = ""
    var date = ""
  }

  private let sourceURL: URL
  private var recognizedFeed = false
  private var feedTitle = ""
  private var siteURL: String?
  private var currentText = ""
  private var currentItem: Draft?
  private var items: [RSSParsedItem] = []

  private init(sourceURL: URL) {
    self.sourceURL = sourceURL
  }

  static func parse(data: Data, sourceURL: URL) -> RSSDocument? {
    let delegate = RSSXMLFeedParser(sourceURL: sourceURL)
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldProcessNamespaces = false
    guard parser.parse(), delegate.recognizedFeed else { return nil }
    let title = delegate.feedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return RSSDocument(
      title: title.isEmpty ? (sourceURL.host ?? "RSS 订阅") : title,
      siteURL: delegate.siteURL,
      feedURL: sourceURL,
      items: delegate.items
    )
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    let name = elementName.lowercased()
    currentText = ""
    if name == "rss" || name == "feed" || name.hasSuffix(":rdf") {
      recognizedFeed = true
    }
    if name == "item" || name == "entry" {
      currentItem = Draft()
    }
    if name == "link", currentItem != nil, let href = attributeDict["href"] {
      currentItem?.link = href
    } else if name == "link", currentItem == nil, let href = attributeDict["href"] {
      let relation = attributeDict["rel"]?.lowercased() ?? "alternate"
      let type = attributeDict["type"]?.lowercased() ?? "text/html"
      if relation == "alternate", type.contains("html") {
        siteURL = URL(string: href, relativeTo: sourceURL)?.absoluteURL.absoluteString
      }
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    currentText += string
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    let name = elementName.lowercased()
    let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

    if name == "item" || name == "entry" {
      if let item = currentItem { append(item) }
      currentItem = nil
      currentText = ""
      return
    }

    if currentItem != nil {
      switch name {
      case "title": currentItem?.title = value
      case "link": if currentItem?.link.isEmpty == true { currentItem?.link = value }
      case "guid", "id": currentItem?.id = value
      case "description", "summary", "content", "content:encoded":
        if !value.isEmpty { currentItem?.summary = value }
      case "author", "dc:creator", "name":
        if !value.isEmpty { currentItem?.author = value }
      case "pubdate", "published", "updated", "dc:date":
        if !value.isEmpty { currentItem?.date = value }
      default: break
      }
    } else {
      if name == "title", feedTitle.isEmpty { feedTitle = value }
      if name == "link", siteURL == nil, !value.isEmpty {
        siteURL = URL(string: value, relativeTo: sourceURL)?.absoluteURL.absoluteString
      }
    }
    currentText = ""
  }

  private func append(_ draft: Draft) {
    let title = cleanText(draft.title)
    guard !title.isEmpty else { return }
    let resolvedLink = URL(string: draft.link, relativeTo: sourceURL)?.absoluteURL.absoluteString
      ?? draft.link
    let identity = [draft.id, resolvedLink, title].first { !$0.isEmpty } ?? UUID().uuidString
    items.append(RSSParsedItem(
      id: identity,
      title: title,
      summary: cleanText(draft.summary),
      link: resolvedLink,
      author: draft.author.isEmpty ? nil : cleanText(draft.author),
      publishedAt: RSSDateParser.parse(draft.date)
    ))
  }

  private func cleanText(_ value: String) -> String {
    let withoutTags = value.replacingOccurrences(
      of: "<[^>]+>",
      with: " ",
      options: .regularExpression
    )
    return withoutTags
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private enum RSSDateParser {
  private static let iso = ISO8601DateFormatter()
  private static let formats = [
    "EEE, dd MMM yyyy HH:mm:ss Z",
    "EEE, d MMM yyyy HH:mm:ss Z",
    "dd MMM yyyy HH:mm:ss Z",
    "yyyy-MM-dd'T'HH:mm:ssZ"
  ]

  static func parse(_ value: String) -> Date? {
    guard !value.isEmpty else { return nil }
    if let date = iso.date(from: value) { return date }
    for format in formats {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = format
      if let date = formatter.date(from: value) { return date }
    }
    return nil
  }
}

#if os(iOS)
private enum RSSRoute: String, Identifiable {
  case addSubscription

  var id: String { rawValue }
}

private struct RSSBrowserRoute: Identifiable {
  let id = UUID()
  let url: URL
}

struct RSSScreen: View {
  @StateObject private var store = RSSStore()
  @State private var route: RSSRoute?
  @State private var browserRoute: RSSBrowserRoute?

  var body: some View {
    NavigationStack {
      List {
        if store.subscriptions.isEmpty {
          RSSEmptyState { route = .addSubscription }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if store.articles.isEmpty, store.phase == .refreshing {
          HStack {
            Spacer()
            ProgressView("正在获取文章…").padding(.top, 120)
            Spacer()
          }
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
        } else {
          ForEach(store.articles) { article in
            Button {
              store.markRead(article)
              if let url = URL(string: article.link), !article.link.isEmpty {
                browserRoute = RSSBrowserRoute(url: url)
              }
            } label: {
              RSSArticleRow(article: article)
            }
            .buttonStyle(.plain)
            .listRowInsets(.init(top: 7, leading: 20, bottom: 7, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
          }
        }
      }
      .listStyle(.plain)
      .environment(\.defaultMinListRowHeight, 1)
      .qingxuScreen()
      .navigationTitle("RSS")
      .navigationBarTitleDisplayMode(.large)
      .refreshable { await store.refresh() }
      .task { await store.refreshIfNeeded() }
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          NavigationLink {
            RSSSubscriptionsView(store: store)
          } label: {
            Image(systemName: "line.3.horizontal.decrease")
          }
          .accessibilityLabel("管理订阅")
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
          if case .refreshing = store.phase {
            ProgressView().controlSize(.small)
          } else {
            Button { Task { await store.refresh() } } label: {
              Image(systemName: "arrow.clockwise")
            }
            .disabled(store.subscriptions.isEmpty)
            .accessibilityLabel("刷新订阅")
          }
          Button { route = .addSubscription } label: {
            Image(systemName: "plus")
          }
          .accessibilityLabel("添加订阅")
        }
      }
      .safeAreaInset(edge: .bottom) {
        if case .failed(let message) = store.phase {
          Text(message)
            .font(.footnote)
            .foregroundStyle(QingxuPalette.danger)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 6)
        }
      }
      .sheet(item: $route) { _ in
        RSSAddSubscriptionSheet(store: store)
          .presentationDetents([.medium])
          .presentationDragIndicator(.visible)
      }
      .sheet(item: $browserRoute) { route in
        RSSInAppBrowser(url: route.url)
          .ignoresSafeArea()
      }
    }
  }
}

private struct RSSInAppBrowser: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> SFSafariViewController {
    let configuration = SFSafariViewController.Configuration()
    configuration.entersReaderIfAvailable = false
    configuration.barCollapsingEnabled = true
    let controller = SFSafariViewController(url: url, configuration: configuration)
    controller.dismissButtonStyle = .close
    controller.preferredControlTintColor = UIColor(QingxuPalette.accent)
    return controller
  }

  func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

private struct RSSArticleRow: View {
  let article: RSSArticle

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Circle()
        .fill(article.isRead ? Color.clear : QingxuPalette.accent)
        .frame(width: 7, height: 7)
        .padding(.top, 8)

      VStack(alignment: .leading, spacing: 7) {
        Text(article.title)
          .font(.body.weight(article.isRead ? .regular : .semibold))
          .foregroundStyle(QingxuPalette.ink)
          .lineLimit(3)

        if !article.summary.isEmpty {
          Text(article.summary)
            .font(.subheadline)
            .foregroundStyle(QingxuPalette.quiet)
            .lineLimit(2)
        }

        HStack(spacing: 6) {
          Text(article.feedTitle).lineLimit(1)
          if let publishedAt = article.publishedAt {
            Text("·")
            Text(publishedAt, style: .relative)
          }
        }
        .font(.caption)
        .foregroundStyle(QingxuPalette.quiet)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(QingxuPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

private struct RSSEmptyState: View {
  let add: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "dot.radiowaves.left.and.right")
        .font(.system(size: 52, weight: .light))
        .foregroundStyle(QingxuPalette.accent)
      Text("还没有 RSS 订阅")
        .font(.title3.weight(.semibold))
        .foregroundStyle(QingxuPalette.ink)
      Text("添加 RSS、Atom 地址或包含订阅链接的网站")
        .font(.subheadline)
        .foregroundStyle(QingxuPalette.quiet)
        .multilineTextAlignment(.center)
      Button("添加第一个订阅", action: add)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(height: 42)
        .background(QingxuPalette.accent, in: Capsule())
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 28)
    .padding(.top, 120)
  }
}

private struct RSSAddSubscriptionSheet: View {
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
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif
        }
        Section {
          Text("可以填写 RSS、Atom 地址，也可以填写包含订阅链接的网站首页。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        if let errorMessage {
          Section { Text(errorMessage).foregroundStyle(QingxuPalette.danger) }
        }
      }
      .qingxuScreen()
      .navigationTitle("添加 RSS")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(isAdding ? "添加中…" : "添加") {
            Task { await addSubscription() }
          }
          .disabled(isAdding || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .fontWeight(.semibold)
        }
      }
    }
  }

  @MainActor
  private func addSubscription() async {
    isAdding = true
    errorMessage = nil
    defer { isAdding = false }
    do {
      try await store.addSubscription(address)
      dismiss()
    } catch is CancellationError {
      return
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct RSSSubscriptionsView: View {
  @ObservedObject var store: RSSStore

  var body: some View {
    List {
      if store.subscriptions.isEmpty {
        Text("还没有订阅").foregroundStyle(QingxuPalette.quiet)
      } else {
        ForEach(store.subscriptions) { subscription in
          VStack(alignment: .leading, spacing: 4) {
            Text(subscription.title).font(.body.weight(.medium))
            Text(subscription.feedURL)
              .font(.caption)
              .foregroundStyle(QingxuPalette.quiet)
              .lineLimit(1)
          }
          .swipeActions {
            Button(role: .destructive) { store.delete(subscription) } label: {
              Label("删除", systemImage: "trash")
            }
          }
        }
      }
    }
    .qingxuScreen()
    .navigationTitle("订阅管理")
    .toolbar {
      if store.unreadCount > 0 {
        ToolbarItem(placement: .primaryAction) {
          Button("全部已读") { store.markAllRead() }
        }
      }
    }
  }
}
#endif
