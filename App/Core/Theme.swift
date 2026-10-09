import BalancePhysics
import SpriteKit
import SwiftUI
import UIKit

/// Design-system tokens (Asset Catalog colour sets with Any / Dark appearances).
/// One accent (brass). Red only for collapse and critical stress. Jade for success and valid placement.
enum Palette {
    static let background = Color("BackgroundPrimary")
    static let background2 = Color("BackgroundSecondary")
    static let sheet = Color("BackgroundSheet")
    static let surface = Color("FillSurface")
    static let surface2 = Color("FillSurfaceSecondary")
    static let text = Color("LabelPrimary")
    static let text2 = Color("LabelSecondary")
    static let text3 = Color("LabelTertiary")
    static let line = Color("Separator")
    static let line2 = Color("SeparatorStrong")
    static let accent = Color("AccentBrass")
    static let onAccent = Color("LabelOnAccent")
    static let accentSoft = Color("AccentSoft")
    static let danger = Color("StateCollapse")
    static let dangerSoft = Color("StateCollapseSoft")
    static let jade = Color("StateSuccess")
    static let jadeSoft = Color("StateSuccessSoft")
    static let hud = Color("HudMaterial")
    static let scrim = Color("Scrim")
    static let grid = Color("BlueprintGrid")
    static let gridStrong = Color("BlueprintGridStrong")
    static let ground = Color("GroundLine")
    static let keystone = Color("MaterialKeystone")

    /// SpriteKit colours resolved for an appearance.
    static func scene(dark: Bool) -> ScenePalette {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        func c(_ name: String) -> SKColor {
            (UIColor(named: name) ?? .gray).resolvedColor(with: traits)
        }
        return ScenePalette(
            wood: c("MaterialWood"), woodDark: c("MaterialWoodDark"), woodLight: c("MaterialWoodLight"),
            stone: c("MaterialStone"), stoneDark: c("MaterialStoneDark"), stoneLight: c("MaterialStoneLight"),
            steel: c("MaterialSteel"), steelDark: c("MaterialSteelDark"), steelLight: c("MaterialSteelLight"),
            rope: c("MaterialRope"), ropeDark: c("MaterialRopeDark"),
            key: c("MaterialKeystone"), keyDark: c("MaterialKeystoneDark"), keyLight: c("MaterialKeystoneLight"),
            outline: c("PieceOutline"), ground: c("GroundLine"), crack: c("Crack"),
            accent: c("AccentBrass"), accentSoft: c("AccentSoft"), danger: c("StateCollapse"),
            jade: c("StateSuccess"), jadeSoft: c("StateSuccessSoft"),
            text: c("LabelPrimary"), text3: c("LabelTertiary"), surface: c("FillSurface"), line2: c("SeparatorStrong"),
            isDark: dark)
    }
}

/// Type ramp. Display ≥ 20 pt, Text below; counters rounded + monospaced digits; mono captions.
enum Typo {
    static let largeTitle = Font.largeTitle.bold()
    static let title1 = Font.title.bold()
    static let title2 = Font.title2.weight(.semibold)
    static let body = Font.body
    static let subhead = Font.subheadline.weight(.semibold)
    static let caption = Font.footnote
    /// Monospaced, fixed size: game HUD only (exempt from Dynamic Type, see docs). Elsewhere use
    /// `.scaledFont(_, design: .monospaced, relativeTo:)`, which follows the player's text size.
    static func mono(_ size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// HUD counter: fixed size (HUD is exempt from Dynamic Type, see docs).
    static func counter(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .heavy, design: .rounded).monospacedDigit()
    }
}

/// A system font at a design size that still follows Dynamic Type, scaled like `relativeTo`
/// (the size is exact at the default text size).
struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default,
                    relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, relativeTo: style))
    }
}

/// Lays content out to fill the height when it fits, and scrolls it only when it does not
/// (accessibility text sizes on small phones), so nothing is clipped off-screen.
struct ScrollIfNeeded<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// A row that puts its parts side by side, or under each other at accessibility text sizes
/// (like iOS Settings), so neither side has to truncate.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var spacing: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) { content }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: spacing) { content }
        }
    }
}

// MARK: - Buttons

/// Scale 0.97 on press, spring 0.15 / 0.9.
struct PressScale: ViewModifier {
    let pressed: Bool
    func body(content: Content) -> some View {
        content.scaleEffect(pressed ? 0.97 : 1).animation(.spring(response: 0.15, dampingFraction: 0.9), value: pressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 12)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(Palette.onAccent)
            .modifier(PressScale(pressed: configuration.isPressed))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 12)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(Palette.text)
            .modifier(PressScale(pressed: configuration.isPressed))
    }
}

/// Rewarded buttons always look the same: ▶ ring, plain verb, "AD" tag. Secondary weight.
struct RewardedButton: View {
    let title: LocalizedStringKey
    var tag: LocalizedStringKey = "ad.tag"
    var dimmed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(Palette.accent, lineWidth: 1.5))
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                AdTag(text: tag)
            }
            .padding(.leading, 9)
            .padding(.trailing, 14)
            .frame(minHeight: 54)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line2, lineWidth: 1))
            .opacity(dimmed ? 0.45 : 1)
        }
        .buttonStyle(PressPlain())
    }
}

struct AdTag: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text)
            .scaledFont(10, design: .monospaced, relativeTo: .caption2)
            .tracking(1)
            .foregroundStyle(Palette.text2)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.line2, lineWidth: 1))
            .fixedSize()
    }
}

struct PressPlain: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(PressScale(pressed: configuration.isPressed))
    }
}

/// 44 × 44 round HUD button with material background.
struct HUDCircleButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    var dimmed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.text)
                .frame(width: 44, height: 44)
                .background(Palette.hud, in: Circle())
                .overlay(Circle().strokeBorder(Palette.line, lineWidth: 1))
                .opacity(dimmed ? 0.4 : 1)
        }
        .buttonStyle(PressPlain())
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Backgrounds

/// Blueprint grid: 22 pt minor, 110 pt major.
struct BlueprintGrid: View {
    var body: some View {
        Canvas { ctx, size in
            func lines(step: CGFloat, color: Color) {
                var p = Path()
                var x: CGFloat = -1
                while x < size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                var y: CGFloat = -1
                while y < size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                ctx.stroke(p, with: .color(color), lineWidth: 1)
            }
            lines(step: 22, color: Palette.grid)
            lines(step: 110, color: Palette.gridStrong)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct ScreenBackground: View {
    var grid = true
    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if grid { BlueprintGrid() }
        }
    }
}

// MARK: - Toast

struct ToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.background)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Palette.text, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
            .frame(maxWidth: 360)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// Mono kicker label: "COLLAPSE REPLAY", "LEVEL 12 CLEARED".
struct Kicker: View {
    let text: Text
    var color: Color = Palette.text3
    var body: some View {
        text.scaledFont(11, design: .monospaced, relativeTo: .caption2).tracking(1.5).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.8)
    }
}

extension View {
    /// Sheet chrome shared by Pause / Hint / Daily: sheet background, grabber.
    func keystoneSheet(height: CGFloat? = nil) -> some View {
        self
            .presentationBackground(Palette.sheet)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(38)
            .modifier(OptionalDetent(height: height))
    }
}

private struct OptionalDetent: ViewModifier {
    let height: CGFloat?
    func body(content: Content) -> some View {
        if let height {
            content.presentationDetents([.height(height)])
        } else {
            content.presentationDetents([.large])
        }
    }
}
