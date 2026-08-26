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
  /// 温润纸墨：只依靠明度、留白和字重建立重点，不使用彩色装饰。
  static let background = Color.adaptive(
    lightHex: 0xF5F4F0,
    darkHex: 0x0D0E0F
  )
  static let secondaryBackground = Color.adaptive(
    lightHex: 0xECEAE5,
    darkHex: 0x141517
  )
  static let surface = Color.adaptive(
    lightHex: 0xFEFDFC,
    darkHex: 0x191A1C
  )
  static let elevatedSurface = Color.adaptive(
    lightHex: 0xFAF9F6,
    darkHex: 0x202124
  )
  static let accent = Color.adaptive(
    lightHex: 0x252629,
    darkHex: 0xF2F1ED
  )
  static let onAccent = Color.adaptive(
    lightHex: 0xFFFFFF,
    darkHex: 0x101011
  )
  static let selected = Color.adaptive(
    lightHex: 0xE5E3DE,
    darkHex: 0x2A2B2E
  )
  static let ink = Color.adaptive(
    lightHex: 0x1E1F22,
    darkHex: 0xF4F4F2
  )
  static let quiet = Color.adaptive(
    lightHex: 0x696B70,
    darkHex: 0xB6B6B2
  )
  static let faint = Color.adaptive(
    lightHex: 0x96989C,
    darkHex: 0x7C7D80
  )
  static let separator = Color.adaptive(
    lightHex: 0xDCDAD5,
    darkHex: 0x303135
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
    colors: [background, background],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  static let actionGradient = LinearGradient(
    colors: [accent, accent],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )
}

enum QingxuType {
  static let screenTitle = Font.system(size: 34, weight: .bold)
  static let sectionTitle = Font.system(size: 20, weight: .semibold)
  static let rowTitle = Font.system(size: 18, weight: .medium)
  static let rowTitleCompleted = Font.system(size: 18, weight: .regular)
  static let body = Font.system(size: 16, weight: .regular)
  static let metadata = Font.system(size: 13, weight: .regular)
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
