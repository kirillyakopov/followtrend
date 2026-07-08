//
//  BubbleInfoSheet.swift
//  followtrend
//
//  Bubble legend sheet — opaque cards, single mint accent,
//  dashed-circle glyph for ghost (watchlist) bubbles.
//

import SwiftUI

struct BubbleInfoSheet: View {
    @EnvironmentObject private var lm: AppLanguageManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header: title 22/800 + close
            HStack(alignment: .top) {
                Text(lm.t("bubbleInfo.title"))
                    .font(AppTypography.sheetTitle)
                    .tracking(-0.4)
                    .foregroundStyle(Color.textPrimary)

                Spacer(minLength: 12)

                Button {
                    haptic(.light)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.labelSecondary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 156), spacing: 10, alignment: .top)], alignment: .center, spacing: 10) {
                    ForEach(infoItems) { item in
                        infoCard(item)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var infoItems: [BubbleInfoItem] {
        [
            BubbleInfoItem(icon: "circle.grid.cross", title: lm.t("bubbleInfo.size.title"), body: lm.t("bubbleInfo.size.body"), color: Color.mintAccent),
            BubbleInfoItem(icon: "paintpalette.fill", title: lm.t("bubbleInfo.color.title"), body: lm.t("bubbleInfo.color.body"), color: Color.mintAccent),
            BubbleInfoItem(icon: "eye", title: lm.t("bubbleInfo.ghost.title"), body: lm.t("bubbleInfo.ghost.body"), color: Color.labelSecondary, isGhost: true),
            BubbleInfoItem(icon: "banknote.fill", title: lm.t("bubbleInfo.stablecoins.title"), body: lm.t("bubbleInfo.stablecoins.body"), color: Color.neutralFlat),
            BubbleInfoItem(icon: "circle.hexagongrid.fill", title: lm.t("bubbles.mergedBubblesTitle"), body: lm.t("bubbles.mergedBubblesText"), color: Color.mintAccent)
        ]
    }

    private func infoCard(_ item: BubbleInfoItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    if item.isGhost {
                        // Ghost-bubble glyph: dashed circle, no fill, no glow
                        Circle()
                            .fill(Color.white.opacity(0.025))
                        Circle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(Color.labelTertiary)
                    } else {
                        Circle()
                            .fill(item.color.opacity(0.14))
                        Circle()
                            .strokeBorder(item.color.opacity(0.26), lineWidth: 0.5)
                        Image(systemName: item.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(item.color)
                    }
                }
                .frame(width: 34, height: 34)

                Text(item.title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(item.body)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(4)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132, alignment: .topLeading)
        .background {
            // Opaque surface — cheap to scroll, no blur/shadow on repeating cards
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.surface)
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color.white.opacity(0.05), Color.clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
    }
}

private struct BubbleInfoItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let body: String
    let color: Color
    var isGhost: Bool = false
}
