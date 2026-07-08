//
//  PortfolioAdviceCardsView.swift
//  followtrend
//
//  Insight cards carousel (README §1.6) — horizontal paging,
//  fixed 294×164 Liquid Glass cards, view-aligned snapping.
//

import SwiftUI

struct PortfolioAdviceCardsView: View {
    let snapshot: AdviceCardsSnapshot
    var onCorrelationTap: (() -> Void)? = nil

    @EnvironmentObject private var lm: AppLanguageManager

    private static let cardSize = CGSize(width: 294, height: 164)
    private static let cardPadding: CGFloat = 16

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                insightCard { allocationCard }
                insightCard { rebalancingCard }
                insightCard { diversificationCard }
                    .onTapGesture { onCorrelationTap?() }
                insightCard { concentrationCard }
                insightCard { stablecoinCard }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        // The parent stack applies the 20pt screen margin; bleed out of it so
        // the carousel scrolls edge-to-edge with its own 16pt content margins.
        .padding(.horizontal, -AppLayout.contentHorizontalPadding)
    }

    // MARK: - Card chrome (the one place true glass belongs)

    private func insightCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(
                width: Self.cardSize.width - Self.cardPadding * 2,
                height: Self.cardSize.height - Self.cardPadding * 2,
                alignment: .topLeading
            )
            .glassCard(padding: Self.cardPadding, cornerRadius: 26)
    }

    // MARK: - PORTFOLIO ALLOCATION

    private var rankedSlices: [AssetAllocationSlice] {
        snapshot.assetAllocation.sorted { $0.percentage > $1.percentage }
    }

    private var allocationCard: some View {
        let ranked = Array(rankedSlices.prefix(5))

        return VStack(alignment: .leading, spacing: 10) {
            OverlineLabel(lm.t("advice.allocation.title"))

            if ranked.isEmpty {
                Text(lm.t("allocation.empty"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.labelSecondary)
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    AllocationDonut(slices: ranked, diameter: 92)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(ranked.prefix(4).enumerated()), id: \.element.id) { index, slice in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(AllocationPalette.color(index))
                                    .frame(width: 8, height: 8)
                                Text(lm.t(slice.category.localizationKey))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(String(format: "%.0f%%", slice.percentage))
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.labelSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - REBALANCING

    private var rebalancingCard: some View {
        let suggestion = snapshot.rebalancingSuggestions.first

        return VStack(alignment: .leading, spacing: 8) {
            OverlineLabel(lm.t("rebalancing.title"))

            Text(rebalancingHeadline(suggestion))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(rebalancingMessage(suggestion))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(2)

            Spacer(minLength: 0)

            // Decorative chip — no action wired in the existing card.
            Text(lm.t("advice.rebalancing.reviewChip"))
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(Color.mintAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(Color.mintAccent.opacity(0.14)))
        }
    }

    // MARK: - DIVERSIFICATION (strongest correlated pair)

    private var diversificationCard: some View {
        let symbolA = snapshot.strongestPairSymbolA
        let symbolB = snapshot.strongestPairSymbolB
        let pairValue = snapshot.strongestPairValue
        let hasPair = symbolA != nil && symbolB != nil

        return VStack(alignment: .leading, spacing: 8) {
            OverlineLabel(lm.t("advice.diversification.title"))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(hasPair ? "\(symbolA!) / \(symbolB!)" : lm.t("advice.correlation.noneTitle"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)

                Text(pairValue.map { String(format: "%+.2f r", $0) } ?? "--")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(pairColor(hasPair: hasPair, value: pairValue))
            }

            Text(correlationMessage(symbolA: symbolA, symbolB: symbolB, value: pairValue))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(3)

            Spacer(minLength: 0)
        }
    }

    private func pairColor(hasPair: Bool, value: Double?) -> Color {
        guard hasPair, let value else { return Color.labelTertiary }
        // Positive correlation reduces diversification → muted loss tint.
        return value >= 0 ? Color.lossText : Color.gainText
    }

    // MARK: - CONCENTRATION

    private var concentrationCard: some View {
        let largestSymbol = snapshot.largestSymbol
        let weight = snapshot.largestWeight
        let isHeavy = weight > 35

        return VStack(alignment: .leading, spacing: 8) {
            OverlineLabel(lm.t("advice.concentration.title"))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(largestSymbol ?? lm.t("advice.noActivePositions"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(largestSymbol != nil ? String(format: "%.1f%%", weight) : "--")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(largestSymbol == nil ? Color.labelTertiary : (isHeavy ? Color.lossText : Color.gainText))
            }

            Text(largestMessage(symbol: largestSymbol, weight: weight))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(2)

            Spacer(minLength: 0)

            // 4pt weight meter: white 8% track, mint (ok) / loss (heavy) fill.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    Capsule(style: .continuous)
                        .fill(isHeavy ? Color.lossBase : Color.mintAccent)
                        .frame(width: geo.size.width * CGFloat(min(max(weight, 0), 100)) / 100)
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - STABLECOINS

    private var stablecoinCard: some View {
        let percentage = snapshot.stablecoinPercentage
        let hasStablecoins = snapshot.hasStablecoins

        return VStack(alignment: .leading, spacing: 8) {
            OverlineLabel(lm.t("advice.stablecoin.title"))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(!hasStablecoins ? lm.t("advice.stablecoin.noneTitle") : lm.t("allocation.stablecoins"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(!hasStablecoins ? "--" : String(format: "%.0f%%", percentage))
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(hasStablecoins ? Color.gainText : Color.labelTertiary)
            }

            Text(stablecoinMessage(percentage: percentage, hasStablecoins: hasStablecoins))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(3)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Copy helpers (unchanged logic)

    private func rebalancingHeadline(_ suggestion: RebalancingSuggestion?) -> String {
        guard let suggestion else { return lm.t("advice.rebalancing.emptyTitle") }
        switch suggestion.severity {
        case .critical:
            return lm.t("advice.rebalancing.criticalTitle")
        case .warning:
            return lm.t("advice.rebalancing.warningTitle")
        case .info:
            return lm.t("advice.rebalancing.infoTitle")
        }
    }

    private func rebalancingMessage(_ suggestion: RebalancingSuggestion?) -> String {
        guard let suggestion else { return lm.t("rebalancing.empty") }
        let format = lm.t(suggestion.localizationKey)
        let args = suggestion.arguments.map { $0 as CVarArg }
        return String(format: format, arguments: args)
    }

    private func largestMessage(symbol: String?, weight: Double) -> String {
        guard let symbol else { return lm.t("advice.noActivePositionsBody") }
        if weight > 35 {
            return String(format: lm.t("advice.largest.warning"), symbol, String(format: "%.0f", weight))
        }
        return String(format: lm.t("advice.largest.healthy"), symbol)
    }

    private func correlationMessage(symbolA: String?, symbolB: String?, value: Double?) -> String {
        guard let symbolA, let symbolB, let value else { return lm.t("advice.correlation.none") }
        if value > 0 {
            return String(format: lm.t("advice.correlation.positive"), symbolA, symbolB)
        }
        return String(format: lm.t("advice.correlation.negative"), symbolA, symbolB)
    }

    private func stablecoinMessage(percentage: Double, hasStablecoins: Bool) -> String {
        guard hasStablecoins else { return lm.t("advice.stablecoin.none") }
        return String(format: lm.t("advice.stablecoin.body"), String(format: "%.0f", percentage))
    }
}
