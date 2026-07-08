//
//  DesignSystem.swift
//  followtrend
//
//  Single source of truth for colors, fonts, and shared modifiers.
//
//  iOS 26 redesign — dark monochrome surfaces, one mint-green accent,
//  Liquid Glass materials, SF Pro with tabular numerals.
//  Token *names* are preserved from the previous palette so the whole
//  app re-tints from this one file; new semantic tokens are added below.
//  NB: the accent is `mintAccent` (SwiftUI already ships a `Color.mint`).
//

import SwiftUI

// MARK: - Colors

extension Color {

    // Base label ramp (Apple's "labelColor on dark" family, rgba 235/235/245)
    private static let labelBase = Color(red: 235.0/255.0, green: 235.0/255.0, blue: 245.0/255.0)

    // ── Backgrounds / surfaces ─────────────────────────────────────────
    static let bgDeep        = Color(hex: "#020202")   // app background base
    static let bgWash        = Color(hex: "#0A0A0B")   // top-of-screen wash
    static let bgCard        = Color(hex: "#101013")   // elevated list/card surface
    static let bgElevated    = Color(hex: "#17181A")
    static let surface       = Color(hex: "#101013")
    static let surfaceWatch  = Color(hex: "#0B0B0D")   // watchlist rows
    static let borderHair    = Color.white.opacity(0.07)
    static let separatorHair = Color.white.opacity(0.07)

    // ── Accent (single mint accent) ────────────────────────────────────
    static let mintAccent    = Color(hex: "#7BE0AE")   // gains, active, primary
    static let mintInk       = Color(hex: "#04140C")   // dark ink on mint fill
    static let mintInkSoft   = Color(hex: "#0A2A1B")
    static let mintDeep      = Color(hex: "#5EB89A")
    static let gainText      = Color(hex: "#8FE8BD")   // gain text tint
    static let gainTextBright = Color(hex: "#DCF8EA")  // gain text inside bubbles

    // ── Loss (muted, never bright red) ─────────────────────────────────
    static let lossBase      = Color(hex: "#E37B72")
    static let lossText      = Color(hex: "#F0A198")
    static let lossPill      = Color(hex: "#C0665E")
    static let destructive   = Color(hex: "#C0453D")   // destructive swipe
    static let neutralFlat   = Color(hex: "#8E8E93")   // neutral / flat

    // ── Legacy accent aliases → mint (keeps old call-sites working) ─────
    static let jade          = Color.mintAccent        // gain / accent
    static let crimson       = Color.lossBase          // loss
    static let accentGold    = Color.mintAccent
    static let accentOrange  = Color.mintAccent

    // ── Labels ─────────────────────────────────────────────────────────
    static let textPrimary   = Color(hex: "#F2F2F4")
    static let labelPrimary  = Color(hex: "#F2F2F4")
    static let labelSecondary  = labelBase.opacity(0.55)
    static let labelTertiary   = labelBase.opacity(0.32)
    static let labelQuaternary = labelBase.opacity(0.24)
    static let textSecondary = labelBase.opacity(0.55)
    static let textMuted     = labelBase.opacity(0.32)

    init(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str = String(str.dropFirst()) }
        var rgb: UInt64 = 0
        Scanner(string: str).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xff) / 255
        let g = Double((rgb >>  8) & 0xff) / 255
        let b = Double( rgb        & 0xff) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Deterministic muted per-ticker hue for monogram tiles
    /// (HSB ≈ 28% saturation, low brightness bg / high brightness fg).
    static func monogramHue(for symbol: String) -> (bg: Color, fg: Color) {
        let seed = symbol.uppercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
        let hue = Double(seed % 360) / 360.0
        let bg = Color(hue: hue, saturation: 0.28, brightness: 0.26)
        let fg = Color(hue: hue, saturation: 0.42, brightness: 0.92)
        return (bg, fg)
    }
}

enum AppColorPalette {
    static let primaryText   = Color.textPrimary
    static let secondaryText = Color.textSecondary
    static let mutedText     = Color.textMuted
    static let accent        = Color.mintAccent
    static let accentSoft    = Color.gainText
    static let accentDeep    = Color.mintDeep
    static let glassBase     = Color.surface
    static let glassBorder   = Color.white.opacity(0.09)
    static let glassHighlight = Color.white.opacity(0.08)
}

// MARK: - Typography (SF Pro system font; tabular numerals for money/percent)

enum AppTypography {
    static let screenTitle  = Font.system(size: 33, weight: .heavy)                 // large title (−0.7 tracking at call-site)
    static let sectionTitle = Font.system(size: 20, weight: .heavy)                 // section header
    static let sheetTitle   = Font.system(size: 22, weight: .heavy)
    static let cardTitle    = Font.system(size: 11, weight: .bold)                  // overline
    static let cardSubtitle = Font.system(size: 13, weight: .medium)
    static let cardHeadline  = Font.system(size: 24, weight: .heavy)
    static let body         = Font.system(size: 14, weight: .regular)
    static let label        = Font.system(size: 12, weight: .semibold)
    static let number       = Font.system(size: 15, weight: .bold).monospacedDigit()      // row price 15/700 tabular
    static let largeNumber  = Font.system(size: 25, weight: .heavy).monospacedDigit()      // 25/800 tabular
    static let hugeNumber   = Font.system(size: 41, weight: .bold).monospacedDigit()       // hero value 41/700 tabular
    static let heroValue    = Font.system(size: 41, weight: .bold).monospacedDigit()
}

enum AppLayout {
    static let contentHorizontalPadding: CGFloat = 20
    static let cardHorizontalPadding: CGFloat = 16
    static let cardRadius: CGFloat = 22
    static let listRadius: CGFloat = 24
    static let sheetRadius: CGFloat = 28
}

// MARK: - Gain/Loss colour helper

extension Double {
    var gainColor: Color { self >= 0 ? .mintAccent : .lossBase }
    var gainTextColor: Color { self >= 0 ? .gainText : .lossText }
    var gainPrefix: String { self >= 0 ? "+" : "" }
}

// MARK: - Overline label (11pt bold, tracked, uppercase, tertiary)

struct OverlineLabel: View {
    private let text: String
    private var color: Color

    init(_ text: String, color: Color = .labelTertiary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(color)
    }
}

// MARK: - Change pill (capsule, mint / loss tinted)

struct ChangePill: View {
    let text: String
    var isPositive: Bool
    var trailing: String? = nil

    var body: some View {
        let accent = isPositive ? Color.mintAccent : Color.lossBase
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isPositive ? Color.mintAccent : Color.lossText)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.labelSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(accent.opacity(0.13)))
        .overlay(Capsule().strokeBorder(accent.opacity(0.16), lineWidth: 0.5))
        .contentTransition(.numericText())
    }
}

// MARK: - Monogram tile (per-ticker muted hue, radius 12 @ 40pt)

struct MonogramTile: View {
    let symbol: String
    var size: CGFloat = 40

    var body: some View {
        let hue = Color.monogramHue(for: symbol)
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(hue.bg)
            .frame(width: size, height: size)
            .overlay(
                Text(symbol.prefix(2).uppercased())
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(hue.fg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
    }
}

// MARK: - Card modifier (Liquid Glass recipe)

struct LiquidGlassCardStyle: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.surface)                                  // opaque #101013 → cheap to scroll (no blur/shadow)
                    .overlay(alignment: .top) {
                        // faint top highlight only — keeps scrolling smooth
                        LinearGradient(
                            colors: [Color.white.opacity(0.05), Color.clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: cornerRadius * 2)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    }
            }
    }
}

// MARK: - Glass Card (true Liquid Glass — for insight cards only, used sparingly)

struct GlassCardStyle: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 26

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.white.opacity(0.035)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                    }
            }
            .shadow(color: Color.black.opacity(0.30), radius: 12, x: 0, y: 8)
    }
}

extension View {
    func glassCard(padding: CGFloat = 16, cornerRadius: CGFloat = 26) -> some View {
        modifier(GlassCardStyle(padding: padding, cornerRadius: cornerRadius))
    }
}

typealias CardStyle = LiquidGlassCardStyle

extension View {
    func cardStyle(padding: CGFloat = 16, cornerRadius: CGFloat = 20) -> some View {
        modifier(LiquidGlassCardStyle(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Global Background

struct PremiumDarkBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.bgWash, Color.bgDeep, Color.bgDeep],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - Haptic

func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

func hapticSuccess() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
}

// MARK: - Liquid Glass Button Style

// Wraps the label in the system Liquid Glass material (`glassEffect`) so
// chips/circle buttons get the authentic iOS 26 look — including the
// interactive press shimmer — while keeping this style's existing API.
struct LiquidGlassButtonStyle: ButtonStyle {
    var isActive: Bool = false
    var isCircle: Bool = false
    var customAccent: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let accent = customAccent ?? Color.mintAccent
        let label = configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isActive ? accent : Color.labelSecondary)
            .frame(width: isCircle ? 34 : nil, height: isCircle ? 34 : nil)
            .padding(.horizontal, isCircle ? 0 : 14)
            .padding(.vertical, isCircle ? 0 : 8)

        return Group {
            if isCircle {
                label.glassEffect(
                    isActive ? .regular.tint(accent.opacity(0.22)).interactive() : .regular.interactive(),
                    in: .circle
                )
            } else {
                label.glassEffect(
                    isActive ? .regular.tint(accent.opacity(0.22)).interactive() : .regular.interactive(),
                    in: .capsule
                )
            }
        }
        .onChange(of: configuration.isPressed) { _, isPressed in
            if isPressed {
                haptic(.light)
            }
        }
    }
}
