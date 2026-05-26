//
//  PortfolioAdviceCardsView.swift
//  followtrend
//

import SwiftUI

struct PortfolioAdviceCardsView: View {
    @ObservedObject var vm: PortfolioViewModel

    @EnvironmentObject private var lm: AppLanguageManager
    @GestureState private var dragOffset: CGFloat = 0
    @State private var activeIndex = 0

    private let cardCount = 5

    private var activeInvestments: [Investment] {
        vm.investments.filter { !$0.isWatchlist }
    }

    private var totalHoldingsValue: Double {
        activeInvestments.reduce(0) { partial, inv in
            partial + convertedValue(for: inv)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width

            VStack(spacing: 12) {
                ZStack {
                    ForEach(Array((0..<cardCount).reversed()), id: \.self) { index in
                        let relative = index - activeIndex

                        if abs(relative) <= 2 {
                            cardView(for: index)
                                .frame(width: cardWidth, height: 220)
                                .blur(radius: relative == 0 ? 0 : 5.8)
                                .scaleEffect(scale(for: relative))
                                .offset(x: xOffset(for: relative), y: yOffset(for: relative))
                                .opacity(opacity(for: relative))
                                .zIndex(zIndex(for: relative))
                                .allowsHitTesting(index == activeIndex)
                        }
                    }
                }
                .frame(width: geo.size.width, height: 228)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .updating($dragOffset) { value, state, _ in
                            state = value.translation.width
                        }
                        .onEnded { value in
                            let threshold = max(54, cardWidth * 0.18)
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                if value.translation.width < -threshold {
                                    activeIndex = min(cardCount - 1, activeIndex + 1)
                                } else if value.translation.width > threshold {
                                    activeIndex = max(0, activeIndex - 1)
                                }
                            }
                        }
                )

                HStack(spacing: 6) {
                    ForEach(0..<cardCount, id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(index == activeIndex ? Color.jade : Color.white.opacity(0.16))
                            .frame(width: index == activeIndex ? 18 : 6, height: 6)
                    }
                }
                .animation(.spring(response: 0.34, dampingFraction: 0.80), value: activeIndex)
            }
            .frame(width: geo.size.width)
        }
        .frame(height: 252)
        .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.86), value: dragOffset)
    }

    @ViewBuilder
    private func cardView(for index: Int) -> some View {
        switch index {
        case 0:
            allocationCard
        case 1:
            rebalancingCard
        case 2:
            diversificationCard
        case 3:
            concentrationCard
        default:
            stablecoinCard
        }
    }

    private var allocationCard: some View {
        adviceCard(icon: "chart.bar.fill", title: lm.t("advice.allocation.title")) {
            VStack(alignment: .center, spacing: 14) {
                segmentedAllocationBar
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: 8) {
                    ForEach(vm.assetAllocation.prefix(4)) { slice in
                        allocationLegendRow(slice)
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var rebalancingCard: some View {
        let suggestion = vm.rebalancingSuggestions.first

        return adviceCard(icon: suggestion?.icon ?? "checkmark.seal.fill", title: lm.t("advice.rebalancing.title")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(rebalancingHeadline(suggestion))
                    .font(AppTypography.cardHeadline)
                    .foregroundStyle(AppColorPalette.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(rebalancingMessage(suggestion))
                    .font(AppTypography.cardSubtitle)
                    .foregroundStyle(AppColorPalette.secondaryText)
                    .lineLimit(4)
                    .minimumScaleFactor(0.88)

                Spacer(minLength: 0)
            }
        }
    }

    private var diversificationCard: some View {
        let strongestPair = vm.correlationMatrix
            .filter { abs($0.value) > 0.4 }
            .max { abs($0.value) < abs($1.value) }

        return adviceCard(icon: "leaf.circle.fill", title: lm.t("advice.diversification.title")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(strongestPair.map { "\($0.key.symbolA) / \($0.key.symbolB)" } ?? lm.t("advice.correlation.noneTitle"))
                    .font(AppTypography.largeNumber)
                    .foregroundStyle(AppColorPalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)

                Text(strongestPair.map { String(format: "%+.2f r", $0.value) } ?? "0.00 r")
                    .font(AppTypography.number)
                    .foregroundStyle(strongestPair == nil ? AppColorPalette.mutedText : AppColorPalette.accentSoft)

                Text(correlationMessage(strongestPair))
                    .font(AppTypography.cardSubtitle)
                    .foregroundStyle(AppColorPalette.secondaryText)
                    .lineLimit(4)
                    .minimumScaleFactor(0.88)

                Spacer(minLength: 0)
            }
        }
    }

    private var concentrationCard: some View {
        let largest = activeInvestments
            .map { ($0, convertedValue(for: $0)) }
            .max { $0.1 < $1.1 }
        let weight = totalHoldingsValue > 0 ? ((largest?.1 ?? 0) / totalHoldingsValue * 100) : 0

        return adviceCard(icon: weight > 35 ? "exclamationmark.triangle.fill" : "scope", title: lm.t("advice.concentration.title")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(largest?.0.symbol ?? lm.t("advice.noActivePositions"))
                    .font(AppTypography.largeNumber)
                    .foregroundStyle(weight > 35 ? AppColorPalette.accentSoft : AppColorPalette.accent)
                    .lineLimit(1)

                Text(largest.map { _ in String(format: "%.1f%%", weight) } ?? "--")
                    .font(AppTypography.number)
                    .foregroundStyle(AppColorPalette.primaryText)

                Text(largestMessage(symbol: largest?.0.symbol, weight: weight))
                    .font(AppTypography.cardSubtitle)
                    .foregroundStyle(AppColorPalette.secondaryText)
                    .lineLimit(4)
                    .minimumScaleFactor(0.88)

                Spacer(minLength: 0)
            }
        }
    }

    private var stablecoinCard: some View {
        let stablecoinSlice = vm.assetAllocation.first { $0.category == .stablecoins }
        let percentage = stablecoinSlice?.percentage ?? 0

        return adviceCard(icon: "banknote.fill", title: lm.t("advice.stablecoin.title")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(stablecoinSlice == nil ? lm.t("advice.stablecoin.noneTitle") : lm.t("allocation.stablecoins"))
                    .font(AppTypography.cardHeadline)
                    .foregroundStyle(AppColorPalette.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(stablecoinSlice == nil ? "--" : String(format: "%.0f%%", percentage))
                    .font(AppTypography.number)
                    .foregroundStyle(Color(hex: "#9ccfbe"))

                Text(stablecoinMessage(percentage: percentage, hasStablecoins: stablecoinSlice != nil))
                    .font(AppTypography.cardSubtitle)
                    .foregroundStyle(AppColorPalette.secondaryText)
                    .lineLimit(4)
                    .minimumScaleFactor(0.88)

                Spacer(minLength: 0)
            }
        }
    }

    private var segmentedAllocationBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            HStack(spacing: 3) {
                ForEach(vm.assetAllocation) { slice in
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    color(for: slice.category).opacity(0.62),
                                    color(for: slice.category).opacity(0.94)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, width * slice.percentage / 100))
                }
            }
            .frame(height: 18)
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Color.white.opacity(0.045))
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.6)
            )
        }
        .frame(height: 26)
    }

    private func allocationLegendRow(_ slice: AssetAllocationSlice) -> some View {
        HStack(spacing: 8) {
            Capsule(style: .continuous)
                .fill(color(for: slice.category))
                .frame(width: 16, height: 7)
            Text(lm.t(slice.category.localizationKey))
                .font(AppTypography.label)
                .foregroundStyle(AppColorPalette.secondaryText)
                .lineLimit(1)
            Spacer()
            Text(String(format: "%.0f%%", slice.percentage))
                .font(AppTypography.number)
                .foregroundStyle(AppColorPalette.primaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func adviceCard<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColorPalette.accent)
                    .frame(width: 30, height: 30)
                    .background(AppColorPalette.accent.opacity(0.12))
                    .clipShape(Circle())
                Text(title)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColorPalette.mutedText)
                    .tracking(1.1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
            }

            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.bgDeep.opacity(0.78))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.jade.opacity(0.12), Color(hex: "#2dd4bf").opacity(0.05), Color.bgCard.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.7)
                        .padding(1.5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.jade.opacity(0.18), lineWidth: 0.9)
                )
                .shadow(color: Color.jade.opacity(0.16), radius: 26, x: 0, y: 14)
                .shadow(color: Color.black.opacity(0.28), radius: 22, x: 0, y: 12)
        }
    }

    private func xOffset(for relative: Int) -> CGFloat {
        if relative == 0 { return dragOffset }
        let direction: CGFloat = relative > 0 ? 1 : -1
        let peek = relative > 0 ? CGFloat(relative) * 28 : CGFloat(abs(relative)) * 18
        return direction * peek + dragOffset * 0.10
    }

    private func yOffset(for relative: Int) -> CGFloat {
        relative == 0 ? 0 : CGFloat(abs(relative)) * 8
    }

    private func scale(for relative: Int) -> CGFloat {
        max(0.88, 1 - CGFloat(abs(relative)) * 0.055)
    }

    private func opacity(for relative: Int) -> Double {
        relative == 0 ? 1 : max(0.30, 0.58 - Double(abs(relative)) * 0.14)
    }

    private func zIndex(for relative: Int) -> Double {
        Double(10 - abs(relative))
    }

    private func convertedValue(for investment: Investment) -> Double {
        let price = vm.marketService.getCurrentPrice(for: investment.symbol)
        let convertedPrice = CurrencyService.shared.convertToSelected(value: price, from: investment.nativeCurrency)
        return investment.shares * convertedPrice
    }

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

    private func correlationMessage(_ pair: Dictionary<AssetPair, Double>.Element?) -> String {
        guard let pair else { return lm.t("advice.correlation.none") }
        if pair.value > 0 {
            return String(format: lm.t("advice.correlation.positive"), pair.key.symbolA, pair.key.symbolB)
        }
        return String(format: lm.t("advice.correlation.negative"), pair.key.symbolA, pair.key.symbolB)
    }

    private func stablecoinMessage(percentage: Double, hasStablecoins: Bool) -> String {
        guard hasStablecoins else { return lm.t("advice.stablecoin.none") }
        return String(format: lm.t("advice.stablecoin.body"), String(format: "%.0f", percentage))
    }

    private func color(for category: AssetCategory) -> Color {
        switch category {
        case .stocks:
            return Color.jade
        case .etfs:
            return Color(hex: "#5eead4")
        case .crypto:
            return Color(hex: "#2dd4bf")
        case .stablecoins:
            return Color(hex: "#86a69a")
        }
    }
}
