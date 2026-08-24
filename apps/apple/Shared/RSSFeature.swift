import Combine
import Foundation
import SwiftUI
#if os(iOS)
import SafariServices
import UniformTypeIdentifiers
import UserNotifications
#endif

struct RSSFolder: Codable, Identifiable, Hashable {
  var id: String
  var title: String
  var createdAt: Date
  var updatedAt: Date
}

struct RSSSubscription: Codable, Identifiable, Hashable {
  var id: String
  var title: String
  var feedURL: String
  var siteURL: String?
  var createdAt: Date
  var lastFetchedAt: Date?
  var folderID: String?
  var iconURL: String?
  var notificationsEnabled: Bool?
  var notificationKeywords: [String]?
  var lastError: String?
  var updatedAt: Date?
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
  var content: String?
  var starredAt: Date?
  var readAt: Date?
  var readingProgress: Double?
  var cachedAt: Date?

  var isStarred: Bool { starredAt != nil }
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
  var content: String
}

enum RSSArticleFilter: String, CaseIterable, Identifiable {
  case unread
  case all
  case starred

  var id: String { rawValue }

  var title: String {
    switch self {
    case .unread: "未读"
    case .all: "全部"
    case .starred: "收藏"
    }
  }
}

struct RSSArticleSyncState: Codable, Hashable {
  var id: String
  var isRead: Bool
  var starredAt: Date?
  var readAt: Date?
  var readingProgress: Double?
  var updatedAt: Date
}

struct RSSSyncState: Codable, Equatable {
  var subscriptions: [RSSSubscription]
  var folders: [RSSFolder]
  var articleStates: [RSSArticleSyncState]
  var updatedAt: Date
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
  @Published private(set) var folders: [RSSFolder]
  @Published private(set) var phase: RSSStorePhase = .idle

  private let client = RSSClient()
  private let syncClient = SyncClient()
  private var syncStateUpdatedAt = Date.distantPast
  private var syncedArticleStates: [String: RSSArticleSyncState] = [:]
  private var pendingCloudSync: Task<Void, Never>?

  init() {
    subscriptions = QingxuFiles.load(
      [RSSSubscription].self,
      name: "rss-subscriptions.json"
    ) ?? []
    articles = QingxuFiles.load([RSSArticle].self, name: "rss-articles.json") ?? []
    folders = QingxuFiles.load([RSSFolder].self, name: "rss-folders.json") ?? []
    if let snapshot = QingxuFiles.load(RSSSyncState.self, name: "rss-sync-state.json") {
      syncStateUpdatedAt = snapshot.updatedAt
      syncedArticleStates = Dictionary(uniqueKeysWithValues: snapshot.articleStates.map { ($0.id, $0) })
      if subscriptions.isEmpty { subscriptions = snapshot.subscriptions }
      if folders.isEmpty { folders = snapshot.folders }
      applySyncedArticleStates()
    }
  }

  deinit { pendingCloudSync?.cancel() }

  var unreadCount: Int { articles.lazy.filter { !$0.isRead }.count }

  var cacheSizeBytes: Int {
    (try? QingxuCoding.encoder.encode(articles).count) ?? 0
  }

  func unreadCount(for feedID: String?) -> Int {
    articles.lazy.filter { article in
      !article.isRead && (feedID == nil || article.feedID == feedID)
    }.count
  }

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
        lastFetchedAt: now,
        folderID: nil,
        iconURL: document.siteURL.flatMap { RSSStore.faviconURL(for: $0) },
        notificationsEnabled: false,
        notificationKeywords: [],
        lastError: nil,
        updatedAt: now
      )
      subscriptions.append(subscription)
      subscriptions.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
      _ = merge(document.items, into: subscription, fetchedAt: now)
      persist()
      cloudStateChanged()
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
        let newArticles = merge(document.items, into: subscription, fetchedAt: now)
        #if os(iOS)
        scheduleNewArticleNotification(newArticles, for: subscription)
        #endif
        if let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) {
          subscriptions[index].title = document.title
          subscriptions[index].siteURL = document.siteURL
          subscriptions[index].feedURL = document.feedURL.absoluteString
          subscriptions[index].lastFetchedAt = now
          subscriptions[index].lastError = nil
        }
      } catch is CancellationError {
        phase = .idle
        return
      } catch {
        failures += 1
        if let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) {
          subscriptions[index].lastError = error.localizedDescription
        }
      }
    }

    sortAndTrimArticles()
    persist()
    phase = failures == 0 ? .idle : .failed("有 \(failures) 个订阅刷新失败")
  }

  func markRead(_ article: RSSArticle) {
    guard let index = articles.firstIndex(where: { $0.id == article.id }) else { return }
    guard !articles[index].isRead else { return }
    articles[index].isRead = true
    articles[index].readAt = .now
    persist()
    cloudStateChanged()
  }

  func toggleRead(_ article: RSSArticle) {
    guard let index = articles.firstIndex(where: { $0.id == article.id }) else { return }
    articles[index].isRead.toggle()
    articles[index].readAt = articles[index].isRead ? .now : nil
    persist()
    cloudStateChanged()
  }

  func toggleStarred(_ article: RSSArticle) {
    guard let index = articles.firstIndex(where: { $0.id == article.id }) else { return }
    articles[index].starredAt = articles[index].starredAt == nil ? .now : nil
    persist()
    cloudStateChanged()
  }

  func setReadingProgress(_ progress: Double, articleID: String) {
    guard let index = articles.firstIndex(where: { $0.id == articleID }) else { return }
    articles[index].readingProgress = min(1, max(0, progress))
    persist()
    cloudStateChanged()
  }

  func markAllRead(feedID: String? = nil) {
    for index in articles.indices where feedID == nil || articles[index].feedID == feedID {
      articles[index].isRead = true
      articles[index].readAt = articles[index].readAt ?? .now
    }
    persist()
    cloudStateChanged()
  }

  func delete(_ subscription: RSSSubscription) {
    subscriptions.removeAll { $0.id == subscription.id }
    articles.removeAll { $0.feedID == subscription.id }
    persist()
    cloudStateChanged()
  }

  func clearReadCache() {
    articles.removeAll { $0.isRead && !$0.isStarred }
    persist()
    cloudStateChanged()
  }

  func createFolder(title: String) {
    let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty,
          !folders.contains(where: { $0.title.localizedCaseInsensitiveCompare(clean) == .orderedSame })
    else { return }
    let now = Date()
    folders.append(RSSFolder(id: UUID().uuidString, title: clean, createdAt: now, updatedAt: now))
    folders.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    persist()
    cloudStateChanged()
  }

  func deleteFolder(_ folder: RSSFolder) {
    folders.removeAll { $0.id == folder.id }
    for index in subscriptions.indices where subscriptions[index].folderID == folder.id {
      subscriptions[index].folderID = nil
      subscriptions[index].updatedAt = .now
    }
    persist()
    cloudStateChanged()
  }

  func move(_ subscription: RSSSubscription, to folderID: String?) {
    guard let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) else { return }
    subscriptions[index].folderID = folderID
    subscriptions[index].updatedAt = .now
    persist()
    cloudStateChanged()
  }

  func updateNotificationSettings(
    for subscription: RSSSubscription,
    enabled: Bool,
    keywords: [String]
  ) async -> Bool {
    guard let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) else { return false }
    #if os(iOS)
    if enabled {
      let center = UNUserNotificationCenter.current()
      let settings = await center.notificationSettings()
      var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
      if settings.authorizationStatus == .notDetermined {
        allowed = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
      }
      guard allowed else { return false }
    }
    #else
    guard !enabled else { return false }
    #endif
    subscriptions[index].notificationsEnabled = enabled
    subscriptions[index].notificationKeywords = keywords
    subscriptions[index].updatedAt = .now
    persist()
    cloudStateChanged()
    return true
  }

  func filteredArticles(
    filter: RSSArticleFilter,
    query: String,
    feedID: String?,
    folderID: String?
  ) -> [RSSArticle] {
    let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let folderFeedIDs = folderID.map { id in
      Set(subscriptions.lazy.filter { $0.folderID == id }.map(\.id))
    }
    let matches = articles.filter { article in
      if let feedID, article.feedID != feedID { return false }
      if let folderFeedIDs, !folderFeedIDs.contains(article.feedID) { return false }
      switch filter {
      case .unread where article.isRead: return false
      case .starred where !article.isStarred: return false
      default: break
      }
      guard !cleanQuery.isEmpty else { return true }
      return [article.title, article.summary, article.feedTitle, article.author ?? ""]
        .contains { $0.localizedCaseInsensitiveContains(cleanQuery) }
    }
    var seen = Set<String>()
    return matches.filter { article in
      let key = article.link.isEmpty ? article.title.lowercased() : article.link.lowercased()
      return seen.insert(key).inserted
    }
  }

  func exportOPML() -> String {
    let outlines = subscriptions.map { subscription in
      let title = xmlEscaped(subscription.title)
      let feedURL = xmlEscaped(subscription.feedURL)
      let siteURL = subscription.siteURL.map(xmlEscaped) ?? ""
      return "    <outline type=\"rss\" text=\"\(title)\" title=\"\(title)\" xmlUrl=\"\(feedURL)\" htmlUrl=\"\(siteURL)\"/>"
    }.joined(separator: "\n")
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="2.0">
      <head><title>清序 RSS 订阅</title></head>
      <body>
    \(outlines)
      </body>
    </opml>
    """
  }

  func importOPML(_ data: Data) async -> Int {
    guard let text = String(data: data, encoding: .utf8),
          let regex = try? NSRegularExpression(
            pattern: #"xmlUrl\s*=\s*[\"']([^\"']+)[\"']"#,
            options: [.caseInsensitive]
          )
    else { return 0 }
    let range = NSRange(text.startIndex..., in: text)
    let addresses = regex.matches(in: text, range: range).compactMap { match -> String? in
      guard let valueRange = Range(match.range(at: 1), in: text) else { return nil }
      return String(text[valueRange])
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&quot;", with: "\"")
    }
    var imported = 0
    for address in addresses where !subscriptions.contains(where: { $0.feedURL == address }) {
      do {
        try await addSubscription(address)
        imported += 1
      } catch { continue }
    }
    return imported
  }

  @discardableResult
  func syncNow() async -> Bool {
    var settings = QingxuFiles.load(SyncSettings.self, name: "sync.json") ?? SyncSettings()
    settings.token = SecureSyncToken.read()
    guard settings.autoSync, settings.isConfigured else { return false }
    do {
      let outgoing: RSSSyncState? = syncStateUpdatedAt == .distantPast && subscriptions.isEmpty
        ? nil
        : makeSyncState()
      let response = try await syncClient.sync(
        settings: settings,
        tasks: [],
        pomodoro: nil,
        rss: outgoing
      )
      if let remote = response.rss, remote.updatedAt > syncStateUpdatedAt {
        applyRemoteSyncState(remote)
      }
      return true
    } catch {
      return false
    }
  }

  @discardableResult
  private func merge(
    _ incoming: [RSSParsedItem],
    into subscription: RSSSubscription,
    fetchedAt: Date
  ) -> [RSSArticle] {
    var existing = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })
    var inserted: [RSSArticle] = []
    for item in incoming {
      let stableID = "\(subscription.id):\(item.id)"
      let old = existing[stableID]
      let syncedState = syncedArticleStates[stableID]
      let article = RSSArticle(
        id: stableID,
        feedID: subscription.id,
        feedTitle: subscription.title,
        title: item.title,
        summary: item.summary,
        link: item.link,
        author: item.author,
        publishedAt: item.publishedAt,
        fetchedAt: old?.fetchedAt ?? fetchedAt,
        isRead: syncedState?.isRead ?? old?.isRead ?? false,
        content: item.content,
        starredAt: syncedState?.starredAt ?? old?.starredAt,
        readAt: syncedState?.readAt ?? old?.readAt,
        readingProgress: syncedState?.readingProgress ?? old?.readingProgress,
        cachedAt: fetchedAt
      )
      existing[stableID] = article
      if old == nil { inserted.append(article) }
    }
    articles = Array(existing.values)
    sortAndTrimArticles()
    return inserted
  }

  private func sortAndTrimArticles() {
    articles.sort {
      ($0.publishedAt ?? $0.fetchedAt) > ($1.publishedAt ?? $1.fetchedAt)
    }
    if articles.count > 1_500 {
      let protected = articles.filter { $0.isStarred }
      let recent = articles.filter { !$0.isStarred }.prefix(max(0, 1_500 - protected.count))
      articles = (protected + Array(recent)).sorted {
        ($0.publishedAt ?? $0.fetchedAt) > ($1.publishedAt ?? $1.fetchedAt)
      }
    }
  }

  private func persist() {
    try? QingxuFiles.save(subscriptions, name: "rss-subscriptions.json")
    try? QingxuFiles.save(articles, name: "rss-articles.json")
    try? QingxuFiles.save(folders, name: "rss-folders.json")
  }

  private func cloudStateChanged() {
    syncStateUpdatedAt = .now
    let snapshot = makeSyncState()
    syncedArticleStates = Dictionary(uniqueKeysWithValues: snapshot.articleStates.map { ($0.id, $0) })
    try? QingxuFiles.save(snapshot, name: "rss-sync-state.json")
    pendingCloudSync?.cancel()
    pendingCloudSync = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(180))
      guard !Task.isCancelled else { return }
      await self?.syncNow()
    }
  }

  private func makeSyncState() -> RSSSyncState {
    let now = syncStateUpdatedAt == .distantPast ? Date() : syncStateUpdatedAt
    let states = articles.map { article in
      let previous = syncedArticleStates[article.id]
      let stateChanged = previous?.isRead != article.isRead
        || previous?.starredAt != article.starredAt
        || previous?.readAt != article.readAt
        || previous?.readingProgress != article.readingProgress
      return RSSArticleSyncState(
        id: article.id,
        isRead: article.isRead,
        starredAt: article.starredAt,
        readAt: article.readAt,
        readingProgress: article.readingProgress,
        updatedAt: stateChanged ? now : (previous?.updatedAt ?? now)
      )
    }
    return RSSSyncState(
      subscriptions: subscriptions,
      folders: folders,
      articleStates: states,
      updatedAt: now
    )
  }

  private func applyRemoteSyncState(_ remote: RSSSyncState) {
    subscriptions = remote.subscriptions
    folders = remote.folders
    for state in remote.articleStates {
      if let current = syncedArticleStates[state.id], current.updatedAt > state.updatedAt { continue }
      syncedArticleStates[state.id] = state
    }
    syncStateUpdatedAt = remote.updatedAt
    applySyncedArticleStates()
    persist()
    try? QingxuFiles.save(makeSyncState(), name: "rss-sync-state.json")
  }

  private func applySyncedArticleStates() {
    for index in articles.indices {
      guard let state = syncedArticleStates[articles[index].id] else { continue }
      articles[index].isRead = state.isRead
      articles[index].starredAt = state.starredAt
      articles[index].readAt = state.readAt
      articles[index].readingProgress = state.readingProgress
    }
  }

  private static func faviconURL(for site: String) -> String? {
    guard var components = URLComponents(string: site) else { return nil }
    components.path = "/favicon.ico"
    components.query = nil
    components.fragment = nil
    return components.url?.absoluteString
  }

  private func xmlEscaped(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }

  #if os(iOS)
  private func scheduleNewArticleNotification(
    _ newArticles: [RSSArticle],
    for subscription: RSSSubscription
  ) {
    guard subscription.notificationsEnabled == true, !newArticles.isEmpty else { return }
    let keywords = subscription.notificationKeywords ?? []
    let matching = keywords.isEmpty ? newArticles : newArticles.filter { article in
      keywords.contains { keyword in
        article.title.localizedCaseInsensitiveContains(keyword)
          || article.summary.localizedCaseInsensitiveContains(keyword)
      }
    }
    guard let newest = matching.first else { return }

    let content = UNMutableNotificationContent()
    content.title = subscription.title
    content.body = matching.count == 1 ? newest.title : "有 \(matching.count) 篇新文章，最新：\(newest.title)"
    content.sound = .default
    content.userInfo = ["url": newest.link]
    let request = UNNotificationRequest(
      identifier: "rss.\(subscription.id).\(Int(Date().timeIntervalSince1970))",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
  }
  #endif
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
    var content = ""
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
        if !value.isEmpty {
          currentItem?.summary = value
          if name == "content" || name == "content:encoded" || currentItem?.content.isEmpty == true {
            currentItem?.content = value
          }
        }
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
      publishedAt: RSSDateParser.parse(draft.date),
      content: cleanText(draft.content.isEmpty ? draft.summary : draft.content)
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

#if os(iOS) && QINGXU_LEGACY_RSS_UI
private enum RSSRoute: String, Identifiable {
  case addSubscription

  var id: String { rawValue }
}

private struct RSSBrowserRoute: Identifiable {
  let id = UUID()
  let url: URL
}

private struct RSSArticleGroup: Identifiable {
  let subscription: RSSSubscription
  let articles: [RSSArticle]

  var id: String { subscription.id }
  var unreadCount: Int { articles.lazy.filter { !$0.isRead }.count }
  var latestDate: Date {
    articles.map { $0.publishedAt ?? $0.fetchedAt }.max() ?? .distantPast
  }
}

struct RSSScreen: View {
  @StateObject private var store = RSSStore()
  @State private var route: RSSRoute?
  @State private var browserRoute: RSSBrowserRoute?
  @State private var selectedFeedID: String?

  private var articleGroups: [RSSArticleGroup] {
    store.subscriptions
      .filter { selectedFeedID == nil || $0.id == selectedFeedID }
      .compactMap { subscription in
        let articles = store.articles.filter { $0.feedID == subscription.id }
        guard !articles.isEmpty else { return nil }
        return RSSArticleGroup(subscription: subscription, articles: articles)
      }
      .sorted { $0.latestDate > $1.latestDate }
  }

  var body: some View {
    NavigationStack {
      List {
        if store.subscriptions.isEmpty {
          RSSEmptyState { route = .addSubscription }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
          RSSSourceStrip(
            subscriptions: store.subscriptions,
            articles: store.articles,
            selection: $selectedFeedID
          )
          .listRowInsets(.init(top: 2, leading: 20, bottom: 10, trailing: 20))
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
        }

        if !store.subscriptions.isEmpty,
           store.articles.isEmpty,
           store.phase == .refreshing {
          HStack {
            Spacer()
            ProgressView("正在获取文章…").padding(.top, 120)
            Spacer()
          }
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
        } else if !store.subscriptions.isEmpty, articleGroups.isEmpty {
          RSSNoArticlesState(sourceSelected: selectedFeedID != nil)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
          ForEach(articleGroups) { group in
            Section {
              ForEach(group.articles) { article in
                Button {
                  store.markRead(article)
                  if let url = URL(string: article.link), !article.link.isEmpty {
                    browserRoute = RSSBrowserRoute(url: url)
                  }
                } label: {
                  RSSArticleRow(article: article, showsSource: false)
                }
                .buttonStyle(.plain)
                .listRowInsets(.init(top: 3, leading: 20, bottom: 3, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
              }
            } header: {
              RSSSourceHeader(group: group)
            }
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
      .onChange(of: store.subscriptions.map(\.id)) { sourceIDs in
        if let selectedFeedID, !sourceIDs.contains(selectedFeedID) {
          self.selectedFeedID = nil
        }
      }
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

          if store.unreadCount(for: selectedFeedID) > 0 {
            Menu {
              Button {
                store.markAllRead(feedID: selectedFeedID)
              } label: {
                Label(selectedFeedID == nil ? "全部标为已读" : "此来源全部已读", systemImage: "checkmark.circle")
              }
            } label: {
              Image(systemName: "ellipsis")
            }
            .accessibilityLabel("更多 RSS 操作")
          }
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

private struct RSSSourceStrip: View {
  let subscriptions: [RSSSubscription]
  let articles: [RSSArticle]
  @Binding var selection: String?

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        sourceButton(
          title: "全部",
          feedID: nil,
          unreadCount: articles.lazy.filter { !$0.isRead }.count
        )

        ForEach(subscriptions) { subscription in
          sourceButton(
            title: subscription.title,
            feedID: subscription.id,
            unreadCount: articles.lazy.filter {
              !$0.isRead && $0.feedID == subscription.id
            }.count
          )
        }
      }
      .padding(.vertical, 2)
    }
  }

  private func sourceButton(title: String, feedID: String?, unreadCount: Int) -> some View {
    let isSelected = selection == feedID

    return Button {
      withAnimation(.easeInOut(duration: 0.18)) { selection = feedID }
      UISelectionFeedbackGenerator().selectionChanged()
    } label: {
      HStack(spacing: 6) {
        Text(title)
          .lineLimit(1)
        if unreadCount > 0 {
          Text("\(unreadCount)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .frame(minHeight: 18)
            .background(
              isSelected ? QingxuPalette.onAccent.opacity(0.2) : QingxuPalette.selected,
              in: Capsule()
            )
        }
      }
      .font(.subheadline.weight(isSelected ? .semibold : .medium))
      .foregroundStyle(isSelected ? QingxuPalette.onAccent : QingxuPalette.ink)
      .padding(.horizontal, 13)
      .frame(height: 36)
      .background(isSelected ? QingxuPalette.accent : QingxuPalette.surface, in: Capsule())
      .overlay {
        if !isSelected {
          Capsule().stroke(QingxuPalette.separator.opacity(0.7), lineWidth: 0.5)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(unreadCount == 0 ? title : "\(title)，\(unreadCount) 篇未读")
  }
}

private struct RSSSourceHeader: View {
  let group: RSSArticleGroup

  var body: some View {
    HStack(spacing: 8) {
      Text(group.subscription.title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(QingxuPalette.ink)
        .lineLimit(1)
      Text("\(group.articles.count)")
        .font(.caption.weight(.medium))
        .foregroundStyle(QingxuPalette.quiet)
      Spacer()
      if group.unreadCount > 0 {
        Text("\(group.unreadCount) 未读")
          .font(.caption)
          .foregroundStyle(QingxuPalette.accent)
      }
    }
    .textCase(nil)
    .padding(.top, 8)
  }
}

private struct RSSNoArticlesState: View {
  let sourceSelected: Bool

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "doc.text.magnifyingglass")
        .font(.system(size: 34, weight: .light))
      Text(sourceSelected ? "这个来源还没有文章" : "还没有获取到文章")
        .font(.headline)
      Text("下拉刷新后再看看")
        .font(.subheadline)
    }
    .foregroundStyle(QingxuPalette.quiet)
    .frame(maxWidth: .infinity)
    .padding(.top, 100)
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
  let showsSource: Bool

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
          if showsSource {
            Text(article.feedTitle).lineLimit(1)
          }
          if let publishedAt = article.publishedAt {
            if showsSource { Text("·") }
            Text(publishedAt, style: .relative)
          }
        }
        .font(.caption)
        .foregroundStyle(QingxuPalette.quiet)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 12)
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
        .foregroundStyle(QingxuPalette.onAccent)
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
            .foregroundStyle(QingxuPalette.quiet)
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
