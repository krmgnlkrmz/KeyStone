import GoogleMobileAds
import SwiftUI
import UIKit

/// Bottom banner slot for Menu, Map and Settings only. The adaptive height is reserved up front,
/// so an unfilled (or offline) banner shows a hatched placeholder and nothing moves. After Remove
/// Ads the slot is removed and content extends to the 40 pt bottom margin with a 0.25 s spring.
struct BannerSlot: View {
    @Environment(AdsCoordinator.self) private var ads
    @State private var loaded = false

    var body: some View {
        if !ads.adsRemoved {
            GeometryReader { geo in
                let width = max(geo.size.width - 32, 1)
                let height = currentOrientationAnchoredAdaptiveBanner(width: width).size.height
                VStack(spacing: 0) {
                    Rectangle().fill(Palette.line).frame(height: 1)
                    ZStack {
                        if !loaded { BannerPlaceholder(offline: !ads.isOnline) }
                        if ads.started {
                            BannerViewRepresentable(width: width, loaded: $loaded)
                                .frame(width: width, height: height)
                                .opacity(loaded ? 1 : 0)
                        }
                    }
                    .frame(height: height)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(Palette.background)
            }
            .frame(height: Self.slotHeight)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// 50 pt banner (adaptive on phones: ~50–60) + 16 pt padding + hairline.
    static var slotHeight: CGFloat {
        let w = (UIApplication.topViewController?.view.bounds.width ?? 390) - 32
        return currentOrientationAnchoredAdaptiveBanner(width: w).size.height + 17
    }
}

private struct BannerPlaceholder: View {
    let offline: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Palette.line2, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .background(
                Canvas { ctx, size in
                    var p = Path()
                    var x: CGFloat = -size.height
                    while x < size.width { p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0)); x += 7 }
                    ctx.stroke(p, with: .color(Palette.line2), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            )
            .overlay(
                Text(offline ? "ad.slot.offline" : "ad.slot")
                    .font(Typo.mono(10)).tracking(1.2)
                    .foregroundStyle(Palette.text3)
            )
            .accessibilityHidden(true)
    }
}

private struct BannerViewRepresentable: UIViewRepresentable {
    let width: CGFloat
    @Binding var loaded: Bool

    func makeCoordinator() -> Coordinator { Coordinator(loaded: $loaded) }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: currentOrientationAnchoredAdaptiveBanner(width: width))
        banner.adUnitID = AppConfig.AdUnit.banner
        banner.delegate = context.coordinator
        banner.rootViewController = UIApplication.topViewController
        banner.load(Request())
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        let size = currentOrientationAnchoredAdaptiveBanner(width: width)
        if !isAdSizeEqualToSize(size1: banner.adSize, size2: size) {
            banner.adSize = size
            banner.load(Request())
        }
    }

    @MainActor
    final class Coordinator: NSObject, BannerViewDelegate {
        @Binding var loaded: Bool
        init(loaded: Binding<Bool>) { _loaded = loaded }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) { loaded = true }
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) { loaded = false }
    }
}
