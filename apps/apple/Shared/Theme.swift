import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: "跟随系统"
    case .light: "明亮"
    case .dark: "深色"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

enum QingxuPalette {
  /// 暖瓷白与深海墨：大面积保持安静，只让矿物蓝承担交互强调。
  static let background = Color.adaptive(
    lightHex: 0xF7F6F2,
    darkHex: 0x0D1117
  )
  static let secondaryBackground = Color.adaptive(
    lightHex: 0xEFEFEA,
    darkHex: 0x131A20
  )
  static let surface = Color.adaptive(
    lightHex: 0xFCFCF9,
    darkHex: 0x182129
  )
  static let elevatedSurface = Color.adaptive(
    lightHex: 0xFFFFFF,
    darkHex: 0x1E2932
  )
  static let accent = Color.adaptive(
    lightHex: 0x456F8E,
    darkHex: 0x7FA9C4
  )
  static let selected = Color.adaptive(
    lightHex: 0xDDE9F0,
    darkHex: 0x203846
  )
  static let ink = Color.adaptive(
    lightHex: 0x172026,
    darkHex: 0xEDF3F4
  )
  static let quiet = Color.adaptive(
    lightHex: 0x667078,
    darkHex: 0x9CAAAF
  )
  static let faint = Color.adaptive(
    lightHex: 0x8C9499,
    darkHex: 0x748289
  )
  static let separator = Color.adaptive(
    lightHex: 0xDEE1DE,
    darkHex: 0x29363E
  )
  static let success = Color.adaptive(
    lightHex: 0x47715D,
    darkHex: 0x7CB394
  )
  static let warning = Color.adaptive(
    lightHex: 0xA56B32,
    darkHex: 0xD2A067
  )
  static let danger = Color.adaptive(
    lightHex: 0xAF5458,
    darkHex: 0xD67C80
  )
  static let scrim = Color.adaptive(
    lightHex: 0x172026,
    darkHex: 0x000000
  )
}

extension Color {
  static func adaptive(
    lightHex: UInt32,
    darkHex: UInt32
  ) -> Color {
    #if os(iOS)
    Color(UIColor { traits in
      UIColor(hex: traits.userInterfaceStyle == .dark ? darkHex : lightHex)
    })
    #else
    Color(NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return NSColor(hex: isDark ? darkHex : lightHex)
    })
    #endif
  }
}

#if os(iOS)
private extension UIColor {
  convenience init(hex: UInt32) {
    self.init(
      red: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}
#else
private extension NSColor {
  convenience init(hex: UInt32) {
    self.init(
      red: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}
#endif

private struct QingxuScreenBackground: ViewModifier {
  func body(content: Content) -> some View {
    content
      .scrollContentBackground(.hidden)
      .background(QingxuPalette.background.ignoresSafeArea())
      .tint(QingxuPalette.accent)
  }
}

extension View {
  func qingxuScreen() -> some View { modifier(QingxuScreenBackground()) }

  @ViewBuilder
  func qingxuFloatingSurface() -> some View {
    #if os(iOS)
    if #available(iOS 26.0, *) {
      self.glassEffect(.regular.interactive(), in: .circle)
    } else {
      self.background(.ultraThinMaterial, in: Circle())
    }
    #else
    self.background(.ultraThinMaterial, in: Circle())
    #endif
  }
}
