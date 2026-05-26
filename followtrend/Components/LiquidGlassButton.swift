//
//  LiquidGlassButton.swift
//  followtrend
//
//  iOS 26 Liquid Glass style button component.
//  Ultra-transparent glass with soft ambient glow — premium Apple aesthetic.
//

import SwiftUI

// MARK: - Liquid Glass Button

struct LiquidGlassButton<Label: View>: View {
    let action: () -> Void
    let glowColor: Color
    @ViewBuilder let label: () -> Label

    @State private var isPressed = false

    init(
        glowColor: Color = .jade,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.glowColor = glowColor
        self.action    = action
        self.label     = label
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isPressed = true
            }
            haptic(.medium)
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
            }
        } label: {
            label()
                .padding(.vertical, 16)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
                .background {
                    ZStack {
                        // Ultra-thin base — almost fully transparent
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(0.6)

                        // Very subtle top specular — soft radial, not harsh stripe
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [.white.opacity(0.10), .clear],
                                    center: .init(x: 0.5, y: 0.0),
                                    startRadius: 0,
                                    endRadius: 60
                                )
                            )

                        // Specular border: bright top edge, fades to near-invisible
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.28),
                                        .white.opacity(0.06),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.7
                            )
                    }
                }
                .glassEffect(.regular.tint(glowColor.opacity(0.08)), in: .capsule)
                // Soft diffused ambient glow — large radius, low opacity
                .shadow(color: glowColor.opacity(isPressed ? 0.30 : 0.18),
                        radius: isPressed ? 14 : 32, y: isPressed ? 4 : 12)
                // Second shadow layer for depth
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                .scaleEffect(isPressed ? 0.96 : 1.0)
                .brightness(isPressed ? 0.04 : 0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
    }
}

// MARK: - Liquid Glass Icon Button (compact, circular)

struct LiquidGlassIconButton: View {
    let systemName: String
    let glowColor:  Color
    let action:     () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { isPressed = true }
            haptic()
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isPressed = false }
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(glowColor)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial)
                .glassEffect(.regular.tint(glowColor.opacity(0.08)), in: .circle)
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.6))
                .shadow(color: glowColor.opacity(0.25), radius: 14, y: 3)
                .scaleEffect(isPressed ? 0.88 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: isPressed)
    }
}
