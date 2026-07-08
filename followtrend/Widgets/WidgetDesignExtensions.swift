//
//  WidgetDesignExtensions.swift
//  followtrend
//
//  UI design extensions utilized exclusively by the PortfolioWidget target.
//  This prevents duplicate declarations in the main target which defines its own DesignSystem.
//
//  iOS 26 redesign — dark monochrome tile, single mint accent, tabular numerals.
//  Token names mirror the main target's DesignSystem so shared views compile in both.
//

import SwiftUI

extension Color {

    // Base label ramp (Apple's "labelColor on dark" family, rgba 235/235/245)
    private static let labelBase = Color(red: 235.0/255.0, green: 235.0/255.0, blue: 245.0/255.0)

    // ── Backgrounds / surfaces ─────────────────────────────────────────
    public static let bgDeep        = Color(hex: "#020202")
    public static let bgCard        = Color(hex: "#101013")
    public static let bgElevated    = Color(hex: "#151517")
    public static let surfaceWatch  = Color(hex: "#0B0B0D")
    public static let borderHair    = Color.white.opacity(0.07)
    public static let separatorHair = Color.white.opacity(0.07)

    // ── Accent (single mint accent) ────────────────────────────────────
    public static let mintAccent    = Color(hex: "#7BE0AE")
    public static let mintInk       = Color(hex: "#04140C")
    public static let gainText      = Color(hex: "#8FE8BD")

    // ── Loss (muted, never bright red) ─────────────────────────────────
    public static let lossBase      = Color(hex: "#E37B72")
    public static let lossText      = Color(hex: "#F0A198")
    public static let lossPill      = Color(hex: "#C0665E")
    public static let neutralFlat   = Color(hex: "#8E8E93")

    // ── Legacy aliases → mint / muted loss (keep old call-sites working)
    public static let jade          = Color.mintAccent
    public static let crimson       = Color.lossBase

    // ── Labels ─────────────────────────────────────────────────────────
    public static let textPrimary   = Color(hex: "#F2F2F4")
    public static let labelSecondary  = labelBase.opacity(0.55)
    public static let labelTertiary   = labelBase.opacity(0.32)
    public static let labelQuaternary = labelBase.opacity(0.24)
    public static let textSecondary = labelBase.opacity(0.55)
    public static let textMuted     = labelBase.opacity(0.32)

    public init(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str = String(str.dropFirst()) }
        var rgb: UInt64 = 0
        Scanner(string: str).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xff) / 255
        let g = Double((rgb >>  8) & 0xff) / 255
        let b = Double( rgb        & 0xff) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Deterministic muted per-ticker hue for monogram tiles.
    public static func monogramHue(for symbol: String) -> (bg: Color, fg: Color) {
        let seed = symbol.uppercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
        let hue = Double(seed % 360) / 360.0
        let bg = Color(hue: hue, saturation: 0.28, brightness: 0.26)
        let fg = Color(hue: hue, saturation: 0.42, brightness: 0.92)
        return (bg, fg)
    }
}

extension Double {
    public var gainColor: Color { self >= 0 ? .mintAccent : .lossBase }
    public var gainTextColor: Color { self >= 0 ? .gainText : .lossText }
    public var gainPrefix: String { self >= 0 ? "+" : "" }
}

// MARK: - Widget tile background (linear-gradient 160° #151517 → #0B0B0D)

extension LinearGradient {
    /// Home-screen widget tile background per design spec.
    public static let widgetTile = LinearGradient(
        colors: [Color(hex: "#151517"), Color(hex: "#0B0B0D")],
        startPoint: UnitPoint(x: 0.33, y: 0.03),
        endPoint: UnitPoint(x: 0.67, y: 0.97)
    )
}

// MARK: - Overline label (11pt bold, tracked, uppercase, tertiary)

struct WidgetOverline: View {
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

// MARK: - Segmented allocation mini-bar (2pt gaps, monochrome + mint palette)

struct WidgetAllocationBar: View {
    var height: CGFloat = 6

    private let segments: [(Color, CGFloat)] = [
        (Color.mintAccent, 0.34),
        (Color.mintAccent.opacity(0.55), 0.24),
        (Color.white.opacity(0.66), 0.18),
        (Color.white.opacity(0.34), 0.14),
        (Color.white.opacity(0.16), 0.10)
    ]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0..<segments.count, id: \.self) { i in
                    Capsule()
                        .fill(segments[i].0)
                        .frame(width: max(0, (geo.size.width - CGFloat(segments.count - 1) * 2) * segments[i].1))
                }
            }
        }
        .frame(height: height)
    }
}
