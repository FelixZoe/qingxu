import SwiftUI
import UIKit

struct QingxuLaunchExperience: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let onFinished: () -> Void

  @State private var hasStarted = false
  @State private var markVisible = false
  @State private var sealVisible = false
  @State private var panelsOpen = false
  @State private var overlayOpacity = 1.0

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        launchPanels(size: proxy.size)

        brandMark
          .scaleEffect(markVisible ? 1 : 0.94)
          .opacity(markVisible && !panelsOpen ? 1 : 0)
          .blur(radius: markVisible ? 0 : 3)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .opacity(overlayOpacity)
    .ignoresSafeArea()
    .accessibilityHidden(true)
    .task { await playOnce() }
  }

  private var brandMark: some View {
    ZStack(alignment: .bottomTrailing) {
      Text("清")
        .font(.system(size: 92, weight: .black, design: .rounded))
        .foregroundStyle(.white)
        .tracking(-5)

      Circle()
        .fill(QingxuPalette.accent)
        .frame(width: 9, height: 9)
        .scaleEffect(sealVisible ? 1 : 1.9)
        .opacity(sealVisible ? 1 : 0)
        .offset(x: 2, y: 1)
    }
    .frame(width: 128, height: 128)
  }

  private func launchPanels(size: CGSize) -> some View {
    let leftWidth = ceil(size.width / 2)
    let rightWidth = size.width - leftWidth

    return HStack(spacing: 0) {
      launchPanel(edge: .trailing)
        .frame(width: leftWidth)
        .offset(x: panelsOpen ? -leftWidth - 2 : 0)

      launchPanel(edge: .leading)
        .frame(width: rightWidth)
        .offset(x: panelsOpen ? rightWidth + 2 : 0)
    }
  }

  private func launchPanel(edge: HorizontalEdge) -> some View {
    ZStack(alignment: edge == .leading ? .leading : .trailing) {
      Color.black

      LinearGradient(
        colors: [Color.white.opacity(0.08), Color.clear],
        startPoint: edge == .leading ? .leading : .trailing,
        endPoint: edge == .leading ? .trailing : .leading
      )
      .frame(width: 2)
      .opacity(panelsOpen ? 1 : 0)
    }
    .clipped()
  }

  @MainActor
  private func playOnce() async {
    guard !hasStarted else { return }
    hasStarted = true

    if reduceMotion {
      markVisible = true
      try? await Task.sleep(nanoseconds: 180_000_000)
      withAnimation(.easeOut(duration: 0.18)) { overlayOpacity = 0 }
      try? await Task.sleep(nanoseconds: 190_000_000)
      onFinished()
      return
    }

    withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.42)) {
      markVisible = true
    }
    try? await Task.sleep(nanoseconds: 330_000_000)

    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
      sealVisible = true
    }
    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.42)
    try? await Task.sleep(nanoseconds: 350_000_000)

    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.62)) {
      panelsOpen = true
    }
    try? await Task.sleep(nanoseconds: 640_000_000)
    onFinished()
  }
}
