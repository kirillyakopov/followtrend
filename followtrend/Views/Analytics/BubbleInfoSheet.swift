//
//  BubbleInfoSheet.swift
//  followtrend
//

import SwiftUI

struct BubbleInfoSheet: View {
    @EnvironmentObject private var lm: AppLanguageManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgDeep.ignoresSafeArea()
                RadialGradient(
                    colors: [Color.jade.opacity(0.18), Color.clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 360
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 156), spacing: 12, alignment: .top)], alignment: .center, spacing: 12) {
                        ForEach(infoItems) { item in
                            infoCard(item)
                        }
                    }
                    .padding(20)
                    .padding(.top, 4)
                }
            }
            .navigationTitle(lm.t("bubbleInfo.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.textMuted)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var infoItems: [BubbleInfoItem] {
        [
            BubbleInfoItem(icon: "circle.grid.cross", title: lm.t("bubbleInfo.size.title"), body: lm.t("bubbleInfo.size.body"), color: Color.jade),
            BubbleInfoItem(icon: "paintpalette.fill", title: lm.t("bubbleInfo.color.title"), body: lm.t("bubbleInfo.color.body"), color: Color(hex: "#5eead4")),
            BubbleInfoItem(icon: "eye.fill", title: lm.t("bubbleInfo.ghost.title"), body: lm.t("bubbleInfo.ghost.body"), color: Color(hex: "#818cf8")),
            BubbleInfoItem(icon: "banknote.fill", title: lm.t("bubbleInfo.stablecoins.title"), body: lm.t("bubbleInfo.stablecoins.body"), color: Color(hex: "#86a69a")),
            BubbleInfoItem(icon: "circle.hexagongrid.fill", title: lm.t("bubbles.mergedBubblesTitle"), body: lm.t("bubbles.mergedBubblesText"), color: Color.jade)
        ]
    }

    private func infoCard(_ item: BubbleInfoItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(item.color.opacity(0.16))
                    Circle()
                        .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.7)
                    Image(systemName: item.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(item.color)
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
                .foregroundStyle(Color.textSecondary)
                .lineLimit(4)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Color.bgCard.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [item.color.opacity(0.09), Color.white.opacity(0.035), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
                )
                .shadow(color: item.color.opacity(0.10), radius: 14, x: 0, y: 8)
                .shadow(color: Color.black.opacity(0.20), radius: 12, x: 0, y: 8)
        }
    }
}

private struct BubbleInfoItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let body: String
    let color: Color
}
