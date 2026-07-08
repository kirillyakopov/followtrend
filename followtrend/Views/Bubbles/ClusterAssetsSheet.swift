//
//  ClusterAssetsSheet.swift
//  followtrend
//
//  Cluster members sheet — overline header with combined value/return,
//  member rows with monogram tiles, key-value stats, Break Up / Done actions.
//

import SwiftUI

struct ClusterAssetsSheet: View {
    let particle: BubbleParticle
    @ObservedObject var vm: PortfolioViewModel
    @ObservedObject var engine: BubblePhysicsEngine
    @EnvironmentObject private var lm: AppLanguageManager
    @Environment(\.dismiss) private var dismiss

    @State private var isRenaming = false
    @State private var newName = ""
    @State private var showCorrelationInfo = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    membersCard
                    statsCard
                    correlationInfoLink
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .safeAreaInset(edge: .bottom) {
            actionButtons
        }
        .alert(lm.t("bubbles.renameCluster"), isPresented: $isRenaming) {
            TextField(lm.t("bubbles.clusterName"), text: $newName)
            Button(lm.t("common.abbrechen"), role: .cancel) { }
            Button(lm.t("common.speichern")) {
                if let clusterId = UUID(uuidString: particle.id), !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    vm.renameCluster(id: clusterId, newName: newName.trimmingCharacters(in: .whitespaces))
                }
            }
        } message: {
            Text(lm.t("bubbles.renameClusterDesc"))
        }
        .sheet(isPresented: $showCorrelationInfo) {
            PearsonInfoSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .environmentObject(lm)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header (overline name · combined value · combined return)

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    OverlineLabel(currentCluster?.name ?? particle.symbol)

                    Button {
                        haptic(.light)
                        newName = particle.symbol
                        isRenaming = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .buttonStyle(.plain)
                }

                Text(CurrencyService.shared.formatConverted(combinedValue))
                    .font(Font.system(size: 26, weight: .heavy))
                    .monospacedDigit()
                    .tracking(-0.5)
                    .foregroundStyle(Color.textPrimary)

                Text(combinedReturnLine)
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(combinedGainPercent.gainTextColor)
            }

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
        .padding(.bottom, 16)
    }

    // MARK: - Members

    @ViewBuilder
    private var membersCard: some View {
        let investments = clusterInvestments
        if !investments.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(investments.enumerated()), id: \.element.id) { index, inv in
                    ClusterAssetRow(investment: inv, vm: vm, engine: engine, particle: particle) {
                        dismiss()
                    }
                    if index < investments.count - 1 {
                        Rectangle()
                            .fill(Color.separatorHair)
                            .frame(height: 0.5)
                            .padding(.leading, 54)
                    }
                }
            }
            .cardStyle(padding: 8, cornerRadius: 20)
        }
    }

    // MARK: - Stats (key-value hairline rows)

    @ViewBuilder
    private var statsCard: some View {
        let investments = clusterInvestments
        if !investments.isEmpty {
            VStack(spacing: 0) {
                statRow(label: lm.t("cluster.stats_combined_value"),
                        value: CurrencyService.shared.formatConverted(combinedValue),
                        tint: Color.textPrimary)
                hairline
                statRow(label: lm.t("cluster.stats_combined_return"),
                        value: String(format: "%@%.1f%%", combinedGainPercent >= 0 ? "+" : "", combinedGainPercent),
                        tint: combinedGainPercent.gainTextColor)

                if let largest = investments.max(by: { value(of: $0) < value(of: $1) }), combinedValue > 0 {
                    hairline
                    statRow(label: lm.t("cluster.stats_largest_holding"),
                            value: String(format: "%@ · %.0f%%", largest.symbol, value(of: largest) / combinedValue * 100),
                            tint: Color.textPrimary)
                }

                if let top = investments.max(by: { gainPercent(of: $0) < gainPercent(of: $1) }) {
                    let topGain = gainPercent(of: top)
                    hairline
                    statRow(label: lm.t("cluster.stats_top_performer"),
                            value: String(format: "%@ · %@%.1f%%", top.symbol, topGain >= 0 ? "+" : "", topGain),
                            tint: topGain.gainTextColor)
                }
            }
            .cardStyle(padding: 8, cornerRadius: 20)
        }
    }

    private var correlationInfoLink: some View {
        Button {
            haptic(.light)
            showCorrelationInfo = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .semibold))
                Text(lm.t("cluster.correlation_link"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.mintAccent)
        }
        .buttonStyle(.plain)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.separatorHair)
            .frame(height: 0.5)
            .padding(.horizontal, 8)
    }

    private func statRow(label: String, value: String, tint: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.labelSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 8)
    }

    // MARK: - Actions (Break Up · Done)

    private var actionButtons: some View {
        HStack(spacing: 10) {
            if let clusterId = UUID(uuidString: particle.id) {
                Button {
                    haptic(.rigid)
                    vm.dissolveCluster(id: clusterId)
                    dismiss()
                } label: {
                    Text(lm.t("bubbles.dissolveCluster"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.lossText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .tint(Color.lossBase)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
            }

            Button {
                haptic(.light)
                dismiss()
            } label: {
                Text(lm.t("common.fertig"))
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Data

    private var currentCluster: BubbleCluster? {
        guard let clusterId = UUID(uuidString: particle.id) else { return nil }
        return vm.bubbleClusters.first { $0.id == clusterId }
    }

    private var clusterInvestments: [Investment] {
        guard let cluster = currentCluster else { return [] }
        return vm.investments.filter { cluster.symbols.contains($0.symbol) && !$0.isWatchlist }
    }

    private func value(of inv: Investment) -> Double {
        vm.selectedCurrencyValue(for: inv)
    }

    private func gainPercent(of inv: Investment) -> Double {
        let cost = vm.selectedCurrencyCost(for: inv)
        guard cost > 0 else { return 0 }
        return ((value(of: inv) - cost) / cost) * 100
    }

    private var combinedValue: Double {
        clusterInvestments.reduce(0) { $0 + value(of: $1) }
    }

    private var combinedCost: Double {
        clusterInvestments.reduce(0) { $0 + vm.selectedCurrencyCost(for: $1) }
    }

    private var combinedGainPercent: Double {
        guard combinedCost > 0 else { return 0 }
        return ((combinedValue - combinedCost) / combinedCost) * 100
    }

    private var combinedReturnLine: String {
        let delta = combinedValue - combinedCost
        let formatted = CurrencyService.shared.formatConverted(abs(delta))
        return String(format: "%@%@ (%@%.2f%%)",
                      delta >= 0 ? "+" : "-",
                      formatted,
                      combinedGainPercent >= 0 ? "+" : "",
                      combinedGainPercent)
    }
}

private struct ClusterAssetRow: View {
    let investment: Investment
    @ObservedObject var vm: PortfolioViewModel
    @ObservedObject var engine: BubblePhysicsEngine
    let particle: BubbleParticle
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MonogramTile(symbol: investment.symbol, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(investment.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text(investment.name)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyService.shared.formatConverted(value))
                    .font(AppTypography.number)
                    .foregroundStyle(Color.textPrimary)
                Text(String(format: "%@%.1f%%", gainPercent >= 0 ? "+" : "", gainPercent))
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(gainPercent.gainTextColor)
            }

            Button {
                haptic(.light)
                if let clusterId = UUID(uuidString: particle.id) {
                    engine.prepareForExpansion(clusterId: particle.id, position: particle.position, velocity: particle.velocity, symbols: [investment.symbol])
                    vm.removeSymbolFromCluster(id: clusterId, symbol: investment.symbol)
                    if !vm.bubbleClusters.contains(where: { $0.id == clusterId }) {
                        onDismiss()
                    }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.labelTertiary)
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
    }

    private var value: Double {
        vm.selectedCurrencyValue(for: investment)
    }

    private var cost: Double {
        vm.selectedCurrencyCost(for: investment)
    }

    private var gainPercent: Double {
        guard cost > 0 else { return 0 }
        return ((value - cost) / cost) * 100
    }
}
