//
//  AssetAllocationChartView.swift
//  followtrend
//

import SwiftUI

struct AssetAllocationChartView: View {
    let slices: [AssetAllocationSlice]

    @EnvironmentObject private var lm: AppLanguageManager
    @State private var expandedCategory: AssetCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(lm.t("allocation.title"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.textMuted)
                    .tracking(1.1)
                Spacer()
                Text(lm.t("allocation.excludesWatchlist"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textMuted)
            }

            if slices.isEmpty {
                Text(lm.t("allocation.empty"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(alignment: .center, spacing: 14) {
                    stackedCapsuleBar
                        .frame(maxWidth: .infinity, alignment: .center)

                    VStack(spacing: 10) {
                        ForEach(slices) { slice in
                            allocationRow(slice)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if let expandedCategory,
                   let slice = slices.first(where: { $0.category == expandedCategory }) {
                    expandedAssets(slice)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .cardStyle()
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: expandedCategory)
        .animation(.easeInOut(duration: 0.35), value: slices)
    }

    private var stackedCapsuleBar: some View {
        GeometryReader { geo in
            HStack(spacing: 4) {
                ForEach(slices) { slice in
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: gradientColors(for: slice.category),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, geo.size.width * slice.percentage / 100))
                }
            }
            .padding(5)
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .glassEffect(.regular.tint(Color.jade.opacity(0.035)), in: .capsule)
            }
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7)
            )
        }
        .frame(height: 28)
    }

    private func allocationRow(_ slice: AssetAllocationSlice) -> some View {
        Button {
            haptic(.light)
            expandedCategory = expandedCategory == slice.category ? nil : slice.category
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(LinearGradient(colors: gradientColors(for: slice.category), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 9, height: 9)

                VStack(alignment: .leading, spacing: 2) {
                    Text(lm.t(slice.category.localizationKey))
                        .font(AppTypography.label)
                        .foregroundStyle(AppColorPalette.primaryText)
                    Text(CurrencyService.shared.formatConverted(slice.value))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppColorPalette.mutedText)
                }

                Spacer()

                Text(String(format: "%.1f%%", slice.percentage))
                    .font(AppTypography.number)
                    .foregroundStyle(AppColorPalette.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }

    private func expandedAssets(_ slice: AssetAllocationSlice) -> some View {
        VStack(spacing: 8) {
            ForEach(slice.assets) { asset in
                HStack {
                    Text(asset.symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(asset.name)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, 4)
    }

    private func gradientColors(for category: AssetCategory) -> [Color] {
        switch category {
        case .stocks:
            return [Color.jade, Color(hex: "#5eead4")]
        case .etfs:
            return [Color(hex: "#34d399"), Color(hex: "#86efac")]
        case .crypto:
            return [Color(hex: "#2dd4bf"), Color(hex: "#0f766e")]
        case .stablecoins:
            return [Color(hex: "#86a69a"), Color(hex: "#9ccfbe")]
        }
    }
}
