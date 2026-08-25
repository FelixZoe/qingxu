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
  /// 单色纸墨：只依靠明度、留白和层级建立重点，不使用彩色装饰。
  static let background = Color.adaptive(
    lightHex: 0xF7F7F5,
    darkHex: 0x0B0B0C
  )
  static let secondaryBackground = Color.adaptive(
    lightHex: 0xF0F0EE,
    darkHex: 0x141416
  )
  static let surface = Color.adaptive(
    lightHex: 0xFFFFFF,
    darkHex: 0x1A1A1D
  )
  static let elevatedSurface = Color.adaptive(
    lightHex: 0xFBFBFA,
    darkHex: 0x222226
  )
  static let accent = Color.adaptive(
    lightHex: 0x202124,
    darkHex: 0xF1F1EE
  )
  static let onAccent = Color.adaptive(
    lightHex: 0xFFFFFF,
    darkHex: 0x101011
  )
  static let selected = Color.adaptive(
    lightHex: 0xE9E9E6,
    darkHex: 0x2B2B30
  )
  static let ink = Color.adaptive(
    lightHex: 0x1E1F22,
    darkHex: 0xF4F4F2
  )
  static let quiet = Color.adaptive(
    lightHex: 0x6F7175,
    darkHex: 0xB0B0B3
  )
  static let faint = Color.adaptive(
    lightHex: 0xA0A1A4,
    darkHex: 0x747478
  )
  static let separator = Color.adaptive(
    lightHex: 0xE3E3E0,
    darkHex: 0x303034
  )
  static let success = Color.adaptive(
    lightHex: 0x3F4247,
    darkHex: 0xD7D7D3
  )
  static let warning = Color.adaptive(
    lightHex: 0x5A5B60,
    darkHex: 0xC8C8C4
  )
  static let danger = Color.adaptive(
    lightHex: 0x333438,
    darkHex: 0xE0E0DC
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
    colors: [accent, accent],
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
