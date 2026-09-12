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
    let upperHeight = ceil(size.height / 2)
    let lowerHeight = size.height - upperHeight

    return VStack(spacing: 0) {
      launchPanel(edge: .bottom)
        .frame(height: upperHeight)
        .offset(y: panelsOpen ? -upperHeight - 2 : 0)

      launchPanel(edge: .top)
        .frame(height: lowerHeight)
        .offset(y: panelsOpen ? lowerHeight + 2 : 0)
    }
  }

  private func launchPanel(edge: VerticalEdge) -> some View {
    ZStack(alignment: edge == .top ? .top : .bottom) {
      Color.black

      LinearGradient(
        colors: [Color.white.opacity(0.08), Color.clear],
        startPoint: edge == .top ? .top : .bottom,
        endPoint: edge == .top ? .bottom : .top
      )
      .frame(height: 2)
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
    try? await Task.sleep(nanoseconds: 390_000_000)

    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.56)) {
      panelsOpen = true
    }
    try? await Task.sleep(nanoseconds: 580_000_000)
    onFinished()
  }
}
