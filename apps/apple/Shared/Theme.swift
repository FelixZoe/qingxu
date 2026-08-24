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
  /// 雾紫与杏桃：日间轻盈、夜间柔和，行动色清楚但不过度刺激。
  static let background = Color.adaptive(
    lightHex: 0xF7F7FB,
    darkHex: 0x0B0D12
  )
  static let secondaryBackground = Color.adaptive(
    lightHex: 0xEEEFF6,
    darkHex: 0x131720
  )
  static let surface = Color.adaptive(
    lightHex: 0xFFFFFF,
    darkHex: 0x191D27
  )
  static let elevatedSurface = Color.adaptive(
    lightHex: 0xFBFBFE,
    darkHex: 0x222735
  )
  static let accent = Color.adaptive(
    lightHex: 0x655FD1,
    darkHex: 0xA89FFF
  )
  static let onAccent = Color.adaptive(
    lightHex: 0xFFFFFF,
    darkHex: 0x11121A
  )
  static let selected = Color.adaptive(
    lightHex: 0xEBE9FA,
    darkHex: 0x2C2A49
  )
  static let ink = Color.adaptive(
    lightHex: 0x242536,
    darkHex: 0xF4F3FA
  )
  static let quiet = Color.adaptive(
    lightHex: 0x6B6E82,
    darkHex: 0xAFB2C4
  )
  static let faint = Color.adaptive(
    lightHex: 0x9B9EAF,
    darkHex: 0x777C91
  )
  static let separator = Color.adaptive(
    lightHex: 0xE4E4EC,
    darkHex: 0x2B3040
  )
  static let success = Color.adaptive(
    lightHex: 0x399576,
    darkHex: 0x70CEAA
  )
  static let warning = Color.adaptive(
    lightHex: 0xED8B67,
    darkHex: 0xFFAE8A
  )
  static let danger = Color.adaptive(
    lightHex: 0xD95F73,
    darkHex: 0xF08A99
  )
  static let scrim = Color.adaptive(
    lightHex: 0x242536,
    darkHex: 0x000000
  )

  static let canvasGradient = LinearGradient(
    colors: [background, background, selected.opacity(0.22)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  static let actionGradient = LinearGradient(
    colors: [accent, warning],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
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
      .background(QingxuPalette.canvasGradient.ignoresSafeArea())
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
