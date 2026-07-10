//
//  PortfolioAdviceCardsView.swift
//  followtrend
//
//  Insight cards carousel (README §1.6) — one full-width card at a time,
//  native Liquid Glass, paged with swipe + page dots.
//
//  Cards: Portfolio Allocation · Rebalancing · Diversification Score ·
//         Risk Overview · Stablecoins (only when the portfolio holds any).
//

import SwiftUI

struct PortfolioAdviceCardsView: View {
    let snapshot: AdviceCardsSnapshot
    var onCorrelationTap: (() -> Void)? = nil

    @EnvironmentObject private var lm: AppLanguageManager
    @State private var currentCardID: Int?

    private static let cardHeight: CGFloat = 190
    private static let cardRadius: CGFloat = 28

    private enum CardKind: Int, Identifiable, CaseIterable {
        case allocation, rebalancing, score, risk, stablecoin
        var id: Int { rawValue }
    }

    /// Stablecoin card only earns a swipe when there is something to say.
    private var visibleCards: [CardKind] {
        var cards: [CardKind] = [.allocation, .rebalancing, .score, .risk]
        if snapshot.hasStablecoins { cards.append(.stablecoin) }
        return cards
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(visibleCards) { kind in
                        insightCard { card(for: kind) }
                            .containerRelativeFrame(.horizontal)
                            .id(kind.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $currentCardID)

            pageDots
        }
        .onAppear {
            if currentCardID == nil { currentCardID = visibleCards.first?.id }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(visibleCards) { kind in
                Circle()
                    .fill(kind.id == (currentCardID ?? 0) ? Color.mintAccent : Color.white.opacity(0.18))
                    .frame(width: 6, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: currentCardID)
            }
        }
    }

    // MARK: - Card chrome (native Liquid Glass)

    private func insightCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: Self.cardHeight, alignment: .topLeading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private func card(for kind: CardKind) -> some View {
        switch kind {
        case .allocation:  allocationCard
        case .rebalancing: rebalancingCard
        case .score:
            diversificationScoreCard
                .contentShape(Rectangle())
                .onTapGesture { onCorrelationTap?() }
        case .risk:        riskOverviewCard
        case .stablecoin:  stablecoinCard
        }
    }

    // MARK: - PORTFOLIO ALLOCATION

    private var rankedSlices: [AssetAllocationSlice] {
        snapshot.assetAllocation.sorted { $0.percentage > $1.percentage }
    }

    private var allocationCard: some View {
        let ranked = Array(rankedSlices.prefix(5))

        return VStack(alignment: .leading, spacing: 12) {
            OverlineLabel(lm.t("advice.allocation.title"))

            if ranked.isEmpty {
                Text(lm.t("allocation.empty"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.labelSecondary)
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .center, spacing: 20) {
                    AllocationDonut(slices: ranked, diameter: 100)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(ranked.prefix(4).enumerated()), id: \.element.id) { index, slice in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(AllocationPalette.color(index))
                                    .frame(width: 8, height: 8)
                                Text(lm.t(slice.category.localizationKey))
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(String(format: "%.0f%%", slice.percentage))
                                    .font(.system(size: 12.5, weight: .semibold))
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
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Text(rebalancingMessage(suggestion))
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(3)

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

    // MARK: - DIVERSIFICATION SCORE (gauge)

    private var diversificationScoreCard: some View {
        let score = snapshot.diversificationScore

        return VStack(alignment: .leading, spacing: 12) {
            OverlineLabel(lm.t("advice.score.title"))

            HStack(alignment: .center, spacing: 18) {
                DiversificationGauge(score: score, diameter: 92)

                VStack(alignment: .leading, spacing: 4) {
                    Text(score.map(gradeLabel) ?? lm.t("advice.score.unavailable"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(score == nil ? Color.labelTertiary : Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(correlationMessage(
                        symbolA: snapshot.strongestPairSymbolA,
                        symbolB: snapshot.strongestPairSymbolB,
                        value:   snapshot.strongestPairValue
                    ))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
    }

    private func gradeLabel(_ score: Int) -> String {
        switch score {
        case 80...:    return lm.t("advice.score.excellent")
        case 65..<80:  return lm.t("advice.score.good")
        case 50..<65:  return lm.t("advice.score.moderate")
        case 35..<50:  return lm.t("advice.score.weak")
        default:       return lm.t("advice.score.poor")
        }
    }

    // MARK: - RISK OVERVIEW

    private var riskOverviewCard: some View {
        let vol = snapshot.volatility30D
        let drawdown = snapshot.maxDrawdown
        let weight = snapshot.largestWeight
        let topSymbol = snapshot.largestSymbol

        return VStack(alignment: .leading, spacing: 12) {
            OverlineLabel(lm.t("advice.risk.title"))

            riskRow(
                label: lm.t("advice.risk.volatility"),
                value: vol.map { String(format: "%.1f%%", $0) },
                fraction: (vol ?? 0) / 40.0,
                tint: (vol ?? 0) > 25 ? Color.lossBase : Color.mintAccent
            )
            riskRow(
                label: lm.t("advice.risk.drawdown"),
                value: drawdown.map { String(format: "%.1f%%", $0) },
                fraction: abs(drawdown ?? 0) / 50.0,
                tint: abs(drawdown ?? 0) > 20 ? Color.lossBase : Color.mintAccent
            )
            riskRow(
                label: lm.t("advice.risk.topHolding"),
                value: topSymbol.map { "\($0)  \(String(format: "%.0f%%", weight))" },
                fraction: weight / 100.0,
                tint: weight > 35 ? Color.lossBase : Color.mintAccent
            )

            Spacer(minLength: 0)
        }
    }

    private func riskRow(label: String, value: String?, fraction: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.labelTertiary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(value ?? lm.t("advice.risk.unavailable"))
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(value == nil ? Color.labelTertiary : Color.textPrimary)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    Capsule(style: .continuous)
                        .fill(value == nil ? Color.white.opacity(0.10) : tint)
                        .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - STABLECOINS

    private var stablecoinCard: some View {
        let percentage = snapshot.stablecoinPercentage

        return VStack(alignment: .leading, spacing: 8) {
            OverlineLabel(lm.t("advice.stablecoin.title"))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(lm.t("allocation.stablecoins"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(String(format: "%.0f%%", percentage))
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.gainText)
            }

            Text(stablecoinMessage(percentage: percentage, hasStablecoins: true))
                .font(.system(size: 13.5, weight: .medium))
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

// MARK: - Diversification gauge (84–92pt ring, 245° mint arc, gap at the bottom)

struct DiversificationGauge: View {
    let score: Int?
    var diameter: CGFloat = 92

    /// 245° of 360° — the remaining 115° gap is centred at the bottom.
    private let sweep: Double = 245.0 / 360.0
    private var startRotation: Double { 90.0 + (360.0 - 245.0) / 2.0 }

    var body: some View {
        let fraction = Double(score ?? 0) / 100.0
        let lineWidth = diameter * 0.10

        ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(Color.white.opacity(0.08),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(startRotation))

            Circle()
                .trim(from: 0, to: sweep * min(max(fraction, 0), 1))
                .stroke(Color.mintAccent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(startRotation))
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: score)

            Text(score.map(String.init) ?? "—")
                .font(.system(size: diameter * 0.26, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(score == nil ? Color.labelTertiary : Color.textPrimary)
        }
        .frame(width: diameter, height: diameter)
    }
}
