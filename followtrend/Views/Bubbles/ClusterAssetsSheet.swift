//
//  ClusterAssetsSheet.swift
//  followtrend
//

import SwiftUI

struct ClusterAssetsSheet: View {
    let particle: BubbleParticle
    @ObservedObject var vm: PortfolioViewModel
    @EnvironmentObject private var lm: AppLanguageManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgDeep.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(lm.t("bubbles.mergedBubblesTitle"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.textMuted)
                            .tracking(1.2)
                            .padding(.horizontal, 4)

                        VStack(spacing: 12) {
                            ForEach(clusterInvestments) { inv in
                                ClusterAssetRow(investment: inv, vm: vm)
                            }
                        }
                        .cardStyle()
                    }
                    .padding(20)
                }
            }
            .navigationTitle(particle.symbol)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lm.t("common.fertig")) { dismiss() }
                        .foregroundStyle(Color.jade)
                }
            }
            .safeAreaInset(edge: .bottom) {
                dissolveButton
            }
        }
        .preferredColorScheme(.dark)
    }

    private var clusterInvestments: [Investment] {
        vm.investments.filter { particle.clusterSymbols.contains($0.symbol) && !$0.isWatchlist }
    }

    @ViewBuilder
    private var dissolveButton: some View {
        if let clusterId = UUID(uuidString: particle.id) {
            Button(role: .destructive) {
                haptic(.rigid)
                vm.expandCluster(id: clusterId)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "circle.grid.cross.left.filled")
                    Text(lm.t("bubbles.dissolveCluster"))
                }
                .font(.system(size: 15, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.red.opacity(0.15))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.3), lineWidth: 1))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ClusterAssetRow: View {
    let investment: Investment
    @ObservedObject var vm: PortfolioViewModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(investment.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text(investment.name)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(CurrencyService.shared.formatConverted(value))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                Text(String(format: "%@%.1f%%", gainPercent >= 0 ? "+" : "", gainPercent))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(gainPercent.gainColor)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
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
