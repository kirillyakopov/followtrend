
//
//  DesignSystem.swift
//  followtrend
//
//  Single source of truth for colors, fonts, and shared modifiers.
//

import SwiftUI

// MARK: - Colors

extension Color {
    static let bgDeep        = Color(hex: "#07070a")
    static let bgCard        = Color(hex: "#0e0e15")
    static let bgElevated    = Color(hex: "#13131d")
    static let borderHair    = Color.white.opacity(0.07)
    static let jade          = Color(hex: "#00d17e")
    static let crimson       = Color(hex: "#ff4a6a")
    static let textPrimary   = Color.white
    static let textSecondary = Color(white: 0.55)
    static let textMuted     = Color(white: 0.35)

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
}

enum AppColorPalette {
    static let primaryText = Color.textPrimary
    static let secondaryText = Color.textSecondary
    static let mutedText = Color.textMuted
    static let accent = Color.jade
    static let accentSoft = Color(hex: "#5eead4")
    static let accentDeep = Color(hex: "#0f766e")
    static let glassBase = Color.bgCard
    static let glassBorder = Color.white.opacity(0.09)
    static let glassHighlight = Color.white.opacity(0.12)
}

enum AppTypography {
    static let cardTitle = Font.system(size: 11, weight: .bold)
    static let cardSubtitle = Font.system(size: 13, weight: .medium)
    static let cardHeadline = Font.system(size: 24, weight: .bold)
    static let body = Font.system(size: 14, weight: .regular)
    static let label = Font.system(size: 12, weight: .semibold)
    static let number = Font.system(size: 15, weight: .bold, design: .monospaced)
    static let largeNumber = Font.system(size: 24, weight: .bold, design: .monospaced)
}

enum AppLayout {
    static let contentHorizontalPadding: CGFloat = 20
}

// MARK: - Gain/Loss colour helper

extension Double {
    var gainColor: Color { self >= 0 ? .jade : .crimson }
    var gainPrefix: String { self >= 0 ? "+" : "" }
}

// MARK: - Card modifier

struct LiquidGlassCardStyle: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .glassEffect(.regular.tint(AppColorPalette.accent.opacity(0.035)), in: .rect(cornerRadius: cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(AppColorPalette.glassBase.opacity(0.72))
                    )
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [AppColorPalette.glassHighlight, .clear],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                )
                            )
                            .blendMode(.screen)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(AppColorPalette.glassBorder, lineWidth: 0.8)
                    )
                    .shadow(color: AppColorPalette.accent.opacity(0.08), radius: 20, x: 0, y: 10)
                    .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
            }
    }
}

typealias CardStyle = LiquidGlassCardStyle

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        modifier(LiquidGlassCardStyle(padding: padding))
    }
}

// MARK: - Global Background

struct PremiumDarkBackground: View {
    var body: some View {
        ZStack {
            // Base deep layer
            Color(hex: "#020202").ignoresSafeArea()
            
            // Ambient subtle glow at the top for depth
            RadialGradient(
                colors: [
                    Color(hex: "#181818").opacity(0.85),
                    Color(hex: "#111111").opacity(0.55),
                    Color(hex: "#0d0d0d").opacity(0.25),
                    .clear
                ],
                center: .top,
                startRadius: 0,
                endRadius: 650
            )
            .ignoresSafeArea()
            
            // Subtle vignette effect at the edges to ground the UI
            RadialGradient(
                colors: [
                    .clear,
                    Color(hex: "#090909").opacity(0.65),
                    Color(hex: "#020202").opacity(0.95)
                ],
                center: .center,
                startRadius: 200,
                endRadius: 850
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Haptic

func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

// MARK: - Liquid Glass Button Style

struct LiquidGlassButtonStyle: ButtonStyle {
    var isActive: Bool = false
    var isCircle: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isActive ? Color.jade : Color.white.opacity(0.85))
            .frame(width: isCircle ? 36 : nil, height: isCircle ? 36 : nil)
            .padding(.horizontal, isCircle ? 0 : 16)
            .padding(.vertical, isCircle ? 0 : 8)
            .background {
                if isCircle {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .glassEffect(.regular.tint(isActive ? Color.jade.opacity(0.12) : Color.white.opacity(0.02)), in: .circle)
                        .overlay(
                            Circle()
                                .strokeBorder(isActive ? Color.jade.opacity(0.4) : Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                        .shadow(color: isActive ? Color.jade.opacity(0.2) : Color.black.opacity(0.1), radius: isActive ? 8 : 2)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .glassEffect(.regular.tint(isActive ? Color.jade.opacity(0.12) : Color.white.opacity(0.02)), in: .rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(isActive ? Color.jade.opacity(0.4) : Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                        .shadow(color: isActive ? Color.jade.opacity(0.2) : Color.black.opacity(0.1), radius: isActive ? 8 : 2)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    haptic(.light)
                }
            }
    }
}

