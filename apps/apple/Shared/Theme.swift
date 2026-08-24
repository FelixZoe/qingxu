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
  /// 奶油纸与晨光蓝：底色安静，蓝绿承担行动与完成，暖杏只用于轻提醒。
  static let background = Color.adaptive(
    lightHex: 0xFAF9F5,
    darkHex: 0x11181A
  )
  static let secondaryBackground = Color.adaptive(
    lightHex: 0xF1F4EF,
    darkHex: 0x182123
  )
  static let surface = Color.adaptive(
    lightHex: 0xFFFEF9,
    darkHex: 0x1E292B
  )
  static let elevatedSurface = Color.adaptive(
    lightHex: 0xFFFFFF,
    darkHex: 0x253235
  )
  static let accent = Color.adaptive(
    lightHex: 0x4773C9,
    darkHex: 0x82A7F0
  )
  static let onAccent = Color.adaptive(
    lightHex: 0xFFFFFF,
    darkHex: 0x11181A
  )
  static let selected = Color.adaptive(
    lightHex: 0xE8EFFB,
    darkHex: 0x283B4E
  )
  static let ink = Color.adaptive(
    lightHex: 0x25323A,
    darkHex: 0xF0F4EE
  )
  static let quiet = Color.adaptive(
    lightHex: 0x657477,
    darkHex: 0xA7B5B0
  )
  static let faint = Color.adaptive(
    lightHex: 0x97A19F,
    darkHex: 0x788984
  )
  static let separator = Color.adaptive(
    lightHex: 0xE3E7E0,
    darkHex: 0x304043
  )
  static let success = Color.adaptive(
    lightHex: 0x498060,
    darkHex: 0x7CC49A
  )
  static let warning = Color.adaptive(
    lightHex: 0xD99A52,
    darkHex: 0xECB56E
  )
  static let danger = Color.adaptive(
    lightHex: 0xD4676D,
    darkHex: 0xE28589
  )
  static let scrim = Color.adaptive(
    lightHex: 0x25323A,
    darkHex: 0x000000
  )

  static let canvasGradient = LinearGradient(
    colors: [background, background, selected.opacity(0.22)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  static let actionGradient = LinearGradient(
    colors: [accent, success],
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
