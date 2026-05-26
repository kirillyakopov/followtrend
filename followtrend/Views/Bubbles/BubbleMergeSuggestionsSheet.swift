//
//  BubbleMergeSuggestionsSheet.swift
//  followtrend
//
//  Created by Portfolio Manager
//

import SwiftUI

struct BubbleMergeSuggestionsSheet: View {
    @EnvironmentObject private var lm: AppLanguageManager
    @ObservedObject var vm: PortfolioViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAssetClass: AssetCategory = .stocks
    @State private var selectedSymbols: Set<String> = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgDeep.ignoresSafeArea()
                
                // Premium background glow
                RadialGradient(
                    colors: [Color.jade.opacity(0.15), Color.clear],
                    center: .topTrailing,
                    startRadius: 30,
                    endRadius: 400
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        
                        // --- Suggestions Section ---
                        VStack(alignment: .leading, spacing: 12) {
                            Text(lm.t("bubbles.mergeSuggestions"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(1.2)
                                .padding(.horizontal, 4)
                            
                            if vm.mergeSuggestions.isEmpty {
                                Text(lm.t("bubbles.noMergeSuggestions"))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.textMuted)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 32)
                                    .cardStyle()
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(vm.mergeSuggestions) { suggestion in
                                        suggestionCard(suggestion)
                                    }
                                }
                            }
                        }
                        
                        // --- Manual Merge Section ---
                        VStack(alignment: .leading, spacing: 12) {
                            Text(lm.t("bubbles.mergeCluster").uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(1.2)
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 16) {
                                Picker("", selection: $selectedAssetClass) {
                                    Text(lm.t("allocation.stocks")).tag(AssetCategory.stocks)
                                    Text(lm.t("allocation.etfs")).tag(AssetCategory.etfs)
                                    Text(lm.t("allocation.crypto")).tag(AssetCategory.crypto)
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: selectedAssetClass) { _, _ in
                                    selectedSymbols.removeAll()
                                }
                                
                                let eligibleAssets = manualMergeEligibleAssets
                                
                                if eligibleAssets.isEmpty {
                                    Text(lm.t("portfolio.keine_positionen"))
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.textMuted)
                                        .padding(.vertical, 16)
                                } else {
                                    VStack(spacing: 8) {
                                        ForEach(eligibleAssets) { inv in
                                            Button {
                                                haptic(.light)
                                                if selectedSymbols.contains(inv.symbol) {
                                                    selectedSymbols.remove(inv.symbol)
                                                } else {
                                                    selectedSymbols.insert(inv.symbol)
                                                }
                                            } label: {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 3) {
                                                        Text(inv.symbol)
                                                            .font(.system(size: 14, weight: .bold))
                                                            .foregroundStyle(Color.textPrimary)
                                                        Text(inv.name)
                                                            .font(.system(size: 11))
                                                            .foregroundStyle(Color.textMuted)
                                                            .lineLimit(1)
                                                    }
                                                    Spacer()
                                                    
                                                    Image(systemName: selectedSymbols.contains(inv.symbol) ? "checkmark.circle.fill" : "circle")
                                                        .font(.system(size: 20))
                                                        .foregroundStyle(selectedSymbols.contains(inv.symbol) ? Color.jade : Color.textMuted)
                                                }
                                                .padding(.vertical, 8)
                                                .padding(.horizontal, 12)
                                                .background(Color.white.opacity(0.03))
                                                .cornerRadius(8)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                
                                Button {
                                    haptic(.rigid)
                                    let name = manualClusterName
                                    vm.mergeCluster(symbols: Array(selectedSymbols), name: name, type: .assetClass)
                                    selectedSymbols.removeAll()
                                    dismiss()
                                } label: {
                                    Text(lm.t("bubbles.mergeCluster"))
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Color.bgDeep)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 48)
                                        .background(selectedSymbols.count >= 2 ? Color.jade : Color.textMuted.opacity(0.3))
                                        .cornerRadius(12)
                                }
                                .disabled(selectedSymbols.count < 2)
                                .buttonStyle(.plain)
                            }
                            .cardStyle()
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(lm.t("bubbles.mergeSuggestions"))
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

    private var manualMergeEligibleAssets: [Investment] {
        let mergedSymbols = Set(vm.bubbleClusters.flatMap { $0.symbols })
        return vm.investments.filter { inv in
            !inv.isWatchlist &&
            !StablecoinClassifier.isStablecoin(symbol: inv.symbol, name: inv.name) &&
            AssetClassifier.category(for: inv) == selectedAssetClass &&
            !mergedSymbols.contains(inv.symbol)
        }
    }

    private var manualClusterName: String {
        switch selectedAssetClass {
        case .stocks: return lm.t("bubbles.stockCluster")
        case .etfs: return lm.t("bubbles.etfCluster")
        case .crypto: return lm.t("bubbles.cryptoCluster")
        default: return lm.t("bubbles.correlationCluster")
        }
    }

    @ViewBuilder
    private func suggestionCard(_ suggestion: MergeSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    
                    Text(suggestion.symbols.joined(separator: " · "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.jade)
                }
                
                Spacer()
                
                Button {
                    haptic(.rigid)
                    vm.mergeCluster(symbols: suggestion.symbols, name: suggestion.name, type: suggestion.type)
                    dismiss()
                } label: {
                    Text(lm.t("bubbles.merge"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.bgDeep)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.jade)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            
            Divider().background(Color.borderHair)
            
            HStack(spacing: 16) {
                if let corr = suggestion.averageCorrelation {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lm.t("bubbles.averageCorrelation"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.textMuted)
                        Text(String(format: "%.2f", corr))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.textPrimary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(lm.t("bubbles.portfolioWeight"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textMuted)
                    Text(String(format: "%.1f%%", suggestion.combinedWeight * 100))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                }
                
                Spacer()
                
                let badgeText: String = {
                    if let sector = suggestion.sector {
                        let localizedName = lm.t(sector.localizationKey)
                        // Strip out "Cluster" suffix if present
                        return localizedName
                            .replacingOccurrences(of: " Cluster", with: "")
                            .replacingOccurrences(of: "-Cluster", with: "")
                            .replacingOccurrences(of: " Кластер", with: "")
                            .replacingOccurrences(of: " кластер", with: "")
                            .replacingOccurrences(of: " Clúster", with: "")
                            .replacingOccurrences(of: " clúster", with: "")
                    } else if let assetClass = suggestion.assetClass {
                        return lm.t(assetClass.localizationKey)
                    } else {
                        return lm.t("detail.pearson_correlation")
                    }
                }()
                
                Text(badgeText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
            }
        }
        .cardStyle()
    }
}
