//
//  PortfolioView.swift
//  followtrend
//

import SwiftUI
import Combine

private enum PositionSortMode: String, CaseIterable, Identifiable {
    case sinceBuy
    case today
    case totalValue
    case name
    case bestPerformer
    case worstPerformer

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .sinceBuy: return "sort.sinceBuy"
        case .today: return "sort.today"
        case .totalValue: return "sort.totalValue"
        case .name: return "sort.name"
        case .bestPerformer: return "sort.bestPerformer"
        case .worstPerformer: return "sort.worstPerformer"
        }
    }

    var icon: String {
        switch self {
        case .sinceBuy: return "calendar.badge.clock"
        case .today: return "sun.max.fill"
        case .totalValue: return "banknote.fill"
        case .name: return "textformat.abc"
        case .bestPerformer: return "arrow.up.right.circle.fill"
        case .worstPerformer: return "arrow.down.right.circle.fill"
        }
    }
}

private let largeRemovalWeightThreshold: Double = 35

// MARK: - Root Portfolio View

struct PortfolioView: View {

    @StateObject private var vm     = PortfolioViewModel()
    @EnvironmentObject private var lm: AppLanguageManager
    @ObservedObject private var cs = CurrencyService.shared
    @Namespace   private var navNamespace

    @State private var showAdd:            Bool = false
    @State private var showProfile:        Bool = false
    @State private var showPearsonInfo:    Bool = false
    @State private var showBubbleInfo:     Bool = false
    @State private var showMergeSuggestions: Bool = false
    @State private var showRestoreConfirm: Bool = false
    @State private var showRemovePositionConfirm: Bool = false
    @State private var currentTab:         AppTab = .gesamt
    @State private var portfolioSearchText: String = ""
    @State private var selectedPortfolioScope: PortfolioScope = .positions
    @State private var selectedInvestment: Investment? = nil
    @State private var editingInvestment:  Investment? = nil
    @State private var convertingInvestment: Investment? = nil
    @State private var pendingRemovePosition: Investment? = nil
    @AppStorage("portfolio.positionSortMode") private var storedPositionSortMode: String = PositionSortMode.sinceBuy.rawValue

    enum PortfolioScope: Hashable {
        case positions
        case watchlist
    }

    private var positionSortMode: PositionSortMode {
        PositionSortMode(rawValue: storedPositionSortMode) ?? .sinceBuy
    }

    enum AppTab: String, CaseIterable {
        case gesamt  = "Gesamt"
        case bubbles = "Bubbles"
        case anlegen = "Anlegen"

        var icon: String {
            switch self {
            case .gesamt:  return "waveform.path.ecg"
            case .bubbles: return "bubbles.and.sparkles"
            case .anlegen: return "plus.circle.fill"
            }
        }
    }

    private var filteredInvestments: [Investment] {
        let q = portfolioSearchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return vm.investments }
        let lower = q.lowercased()
        switch selectedPortfolioScope {
        case .positions:
            return vm.investments.filter { !$0.isWatchlist && ($0.symbol.lowercased().hasPrefix(lower) || $0.name.lowercased().contains(lower)) }
        case .watchlist:
            return vm.investments.filter { $0.isWatchlist && ($0.symbol.lowercased().hasPrefix(lower) || $0.name.lowercased().contains(lower)) }
        }
    }

    private var portfolioSuggestions: [Investment] {
        let q = portfolioSearchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let lower = q.lowercased()
        return vm.investments.filter { inv in
            let matchesScope = (selectedPortfolioScope == .positions ? !inv.isWatchlist : inv.isWatchlist)
            let matchesText = inv.symbol.lowercased().contains(lower) || inv.name.lowercased().contains(lower)
            return matchesScope && matchesText
        }
    }

    @State private var previousTab: AppTab = .gesamt

    var body: some View {
        TabView(selection: $currentTab) {
            Tab(lm.t("tabs.gesamt"), systemImage: AppTab.gesamt.icon, value: .gesamt) {
                mainTabContent(for: .gesamt)
            }

            Tab(lm.t("tabs.bubbles"), systemImage: AppTab.bubbles.icon, value: .bubbles) {
                mainTabContent(for: .bubbles)
            }

            Tab(lm.t("tabs.anlegen"), systemImage: AppTab.anlegen.icon, value: .anlegen) {
                Color.clear
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .onChange(of: currentTab) { oldTab, newTab in
            if newTab == .anlegen {
                showAdd = true
                currentTab = oldTab
            }
        }
        .sheet(isPresented: $showAdd) {
            AddStockView(vm: vm)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(vm: vm)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showPearsonInfo) {
            PearsonInfoSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
                .environmentObject(lm)
        }
        .sheet(isPresented: $showBubbleInfo) {
            BubbleInfoSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
                .environmentObject(lm)
        }
        .sheet(isPresented: $showMergeSuggestions) {
            BubbleMergeSuggestionsSheet(vm: vm)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
                .environmentObject(lm)
        }
        .sheet(item: $selectedInvestment) { inv in
            StockDetailView(
                investment: inv,
                coinId:     inv.coinId,
                priceSourceMode: vm.priceSourceMode,
                onDelete: {
                    vm.removeInvestment(id: inv.id)
                    selectedInvestment = nil
                },
                onBuy: { shares, price, date in
                    vm.buyWatchlistItem(id: inv.id, shares: shares, price: price, date: date)
                    selectedInvestment = nil
                },
                onEdit: { shares, price, date, notes, tags, brokerDraft, clearsBrokerAdjustment in
                    vm.updateInvestment(id: inv.id, shares: shares, buyPrice: price, buyDate: date, notes: notes, tags: tags, brokerAdjustment: brokerDraft, clearsBrokerAdjustment: clearsBrokerAdjustment)
                    selectedInvestment = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $editingInvestment) { inv in
            EditPositionView(investment: inv, currentApiPrice: vm.currentApiPrice(for: inv)) { shares, price, date, notes, tags, brokerDraft, clearsBrokerAdjustment in
                vm.updateInvestment(id: inv.id, shares: shares, buyPrice: price, buyDate: date, notes: notes, tags: tags, brokerAdjustment: brokerDraft, clearsBrokerAdjustment: clearsBrokerAdjustment)
            }
        }
        .sheet(item: $convertingInvestment) { inv in
            ConvertWatchlistPositionView(
                investment: inv,
                livePrice: vm.marketService.getCurrentPrice(for: inv.symbol)
            ) { shares, price, date in
                vm.buyWatchlistItem(id: inv.id, shares: shares, price: price, date: date)
                convertingInvestment = nil
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .environmentObject(lm)
        }
        .alert(lm.t("confirm.restoreBubble.title"), isPresented: $showRestoreConfirm) {
            Button(lm.t("actions.restoreBubble")) {
                haptic(.rigid)
                vm.unpopBubble()
            }
            Button(lm.t("add.abbrechen"), role: .cancel) {}
        }
        .alert(lm.t("confirm.removePosition.title"), isPresented: $showRemovePositionConfirm) {
            Button(lm.t("actions.remove"), role: .destructive) {
                if let pendingRemovePosition {
                    removePositionNow(pendingRemovePosition)
                }
                pendingRemovePosition = nil
            }
            Button(lm.t("add.abbrechen"), role: .cancel) {
                pendingRemovePosition = nil
            }
        } message: {
            Text(lm.t("confirm.removePosition.message"))
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func mainTabContent(for tab: AppTab) -> some View {
        VStack(spacing: 0) {
            if tab == .bubbles {
                headerBar
            }

            switch tab {
            case .gesamt, .anlegen:
                gesamtTab
            case .bubbles:
                einzelTab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PremiumDarkBackground())
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.jade.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.jade)
                }
                Text("followtrend")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
            }

            Spacer()

            // Live price indicator
            if vm.isPriceFetching {
                HStack(spacing: 4) {
                    ProgressView().tint(Color.jade).scaleEffect(0.6)
                    Text(lm.t("portfolio.live"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.jade.opacity(0.7))
                }
            }

            // Info and Profile buttons (matched pair)
            HStack(spacing: 10) {
                Button {
                    showMergeSuggestions = true
                } label: {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(LiquidGlassButtonStyle(isActive: showMergeSuggestions, isCircle: true))

                Button {
                    showBubbleInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(LiquidGlassButtonStyle(isActive: showBubbleInfo, isCircle: true))

                Button {
                    showProfile = true
                } label: {
                    Text("K")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(LiquidGlassButtonStyle(isActive: showProfile, isCircle: true))
            }
        }
        .padding(.horizontal, AppLayout.contentHorizontalPadding)
        .padding(.vertical, 14)
    }

    // MARK: - Gesamt Tab

    private var gesamtTab: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    balanceCard
                    chartCard
                    metricStrip
                    PortfolioAdviceCardsView(vm: vm)
                    riskAnalyticsCard
                    
                    inlinePortfolioSearchBar
                    
                    positionsList
                }
                .padding(.horizontal, AppLayout.contentHorizontalPadding)
                .padding(.bottom, 40)
            }
            .background(PremiumDarkBackground().ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.jade.opacity(0.15))
                                .frame(width: 30, height: 30)
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.jade)
                        }
                        Text("followtrend")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if vm.isPriceFetching {
                            HStack(spacing: 4) {
                                ProgressView().tint(Color.jade).scaleEffect(0.6)
                                Text(lm.t("portfolio.live"))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.jade.opacity(0.7))
                            }
                        }
                        
                        Button {
                            showProfile = true
                            haptic()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 36, height: 36)
                                Text("K")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.jade)
                            }
                            .glassEffect(.regular.tint(Color.jade.opacity(0.08)), in: .circle)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
                            .shadow(color: Color.jade.opacity(0.15), radius: 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Balance Card

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(CurrencyService.shared.formatConverted(vm.totalValue))
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.4), value: vm.totalValue)

                gainBadge(vm.absoluteGain, percent: vm.percentageGain)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func gainBadge(_ absGain: Double, percent: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: percent >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 9))
            Text(String(format: "%@%.2f%%", percent >= 0 ? "+" : "", percent))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(percent.gainColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(percent.gainColor.opacity(0.12))
        .clipShape(Capsule())
        .contentTransition(.numericText())
        .animation(.easeInOut(duration: 0.4), value: percent)
    }

    @ViewBuilder
    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            PortfolioChartView(
                vm: vm,
                isPositive: vm.absoluteGain >= 0
            )
            // .frame(height: 150) is inside PortfolioChartView
        }
        .cardStyle()
    }


    // MARK: - Metric Strip

    private var metricStrip: some View {
        HStack(spacing: 12) {
            stripCell(title: lm.t("portfolio.gesamtrendite"),
                      value: String(format: "%@%@", vm.absoluteGain >= 0 ? "+" : "", CurrencyService.shared.formatConverted(abs(vm.absoluteGain))),
                      color: vm.absoluteGain.gainColor)
            Divider().frame(height: 36).background(Color.borderHair)
            stripCell(title: lm.t("portfolio.roi"),
                      value: String(format: "%@%.2f%%", vm.percentageGain >= 0 ? "+" : "", vm.percentageGain),
                      color: vm.percentageGain.gainColor)
            Divider().frame(height: 36).background(Color.borderHair)
            stripCell(title: lm.t("portfolio.positionen"),
                      value: "\(vm.investments.filter { !$0.isWatchlist }.count)")
        }
        .cardStyle(padding: 14)
    }

    private var riskAnalyticsCard: some View {
        Button {
            haptic(.light)
            showPearsonInfo = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(lm.t("portfolio.risk_correlation"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.textMuted)
                        .tracking(1.2)
                    Spacer()
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
                }
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lm.t("detail.pearson_correlation"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        
                        switch vm.correlationState {
                        case .insufficientData:
                            Text(lm.t("detail.insufficient_correlation_data"))
                                .font(.system(size: 11))
                                .foregroundStyle(Color.textMuted)
                                .minimumScaleFactor(0.8)
                        default:
                            Text(lm.t("pearson.shortDescription"))
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textMuted)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    
                    Spacer()
                    
                    switch vm.correlationState {
                    case .loading:
                        ProgressView()
                            .tint(Color.jade)
                            .scaleEffect(0.8)
                    case .insufficientData:
                        Text("—")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.textMuted)
                    case .success(let corr):
                        correlationBadge(corr)
                    case .error:
                        Text(lm.t("pearson.errors.calculationFailed"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.crimson)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle()
    }
    
    private var inlinePortfolioSearchBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color.textMuted)
                    .font(.system(size: 16, weight: .semibold))
                
                TextField(lm.t("search.portfolio"), text: $portfolioSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                
                if !portfolioSearchText.isEmpty {
                    Button {
                        haptic(.light)
                        portfolioSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color.textMuted)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06))
            .cornerRadius(10)
            
            if !portfolioSearchText.isEmpty {
                Picker("", selection: $selectedPortfolioScope) {
                    Text(lm.t("search.positions")).tag(PortfolioScope.positions)
                    Text(lm.t("search.watchlist")).tag(PortfolioScope.watchlist)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func correlationBadge(_ r: Double) -> some View {
        let text: String = String(format: "%@%.2f", r >= 0 ? "+" : "", r)
        let color: Color
        let desc: String
        
        if r < 0 {
            color = Color.jade
            desc = lm.t("pearson.badges.diversified")
        } else if r < 0.3 {
            color = Color.jade
            desc = lm.t("pearson.badges.weak")
        } else if r < 0.7 {
            color = Color.orange
            desc = lm.t("pearson.badges.moderate")
        } else {
            color = Color.crimson
            desc = lm.t("pearson.badges.high")
        }
        
        return VStack(alignment: .trailing, spacing: 2) {
            Text(text)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(desc)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(color.opacity(0.8))
        }
    }

    @ViewBuilder
    private func stripCell(title: String, value: String, color: Color = .textPrimary) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Positions List (with swipe-to-delete)

    private var positionsList: some View {
        let activePos = sortedActivePositions(filteredInvestments.filter { !$0.isWatchlist })
        let watchPos  = filteredInvestments.filter { $0.isWatchlist }
        
        return VStack(alignment: .leading, spacing: 24) {
            // ── Active Positions Section ──
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(portfolioSearchText.isEmpty
                         ? "\(lm.t("portfolio.aktive_positionen")) (\(vm.investments.filter { !$0.isWatchlist }.count))"
                         : "\(lm.t("portfolio.aktive_positionen")) (\(activePos.count))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.textMuted)
                        .tracking(1.1)
                    Spacer()
                    sortButton
                }

                if activePos.isEmpty {
                    Text(lm.t("portfolio.keine_positionen"))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    activePositionsList(activePos)
                }
            }

            // ── Watchlist Section ──
            if !watchPos.isEmpty || (portfolioSearchText.isEmpty && !vm.investments.filter({ $0.isWatchlist }).isEmpty) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("\(lm.t("portfolio.watchlist")) (\(portfolioSearchText.isEmpty ? vm.investments.filter { $0.isWatchlist }.count : watchPos.count))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.textMuted)
                            .tracking(1.1)
                        Spacer()
                        Text(lm.t("einzel.rendite"))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textMuted)
                    }

                    if watchPos.isEmpty {
                        Text(lm.t("portfolio.keine_positionen"))
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    } else {
                        watchlistPositionsList(watchPos)
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: vm.investments.map(\.id))
        .animation(.spring(response: 0.42, dampingFraction: 0.80), value: activePos.map(\.id))
        .animation(.easeInOut(duration: 0.2), value: filteredInvestments.map(\.id))
    }

    private func activePositionsList(_ positions: [Investment]) -> some View {
        nativeSwipeList(positions: positions, rowHeight: 58) { inv in
            Button {
                haptic(.medium)
                selectedInvestment = inv
            } label: {
                positionRow(inv)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    editingInvestment = inv
                } label: {
                    Label(lm.t("actions.edit"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deletePosition(inv)
                } label: {
                    Label(lm.t("actions.remove"), systemImage: "trash")
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    haptic(.light)
                    editingInvestment = inv
                } label: {
                    Label(lm.t("actions.edit"), systemImage: "pencil")
                }
                .tint(Color.jade)

                Button(role: .destructive) {
                    deletePosition(inv)
                } label: {
                    Label(lm.t("actions.remove"), systemImage: "trash")
                }
            }
        }
    }

    private func watchlistPositionsList(_ positions: [Investment]) -> some View {
        nativeSwipeList(positions: positions, rowHeight: 58) { inv in
            Button {
                haptic(.medium)
                selectedInvestment = inv
            } label: {
                watchlistRow(inv)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    haptic(.light)
                    convertingInvestment = inv
                } label: {
                    Label(lm.t("actions.convert"), systemImage: "arrow.triangle.2.circlepath")
                }
                .tint(Color.jade)

                Button(role: .destructive) {
                    removeWatchlistItem(inv)
                } label: {
                    Label(lm.t("actions.remove"), systemImage: "trash")
                }
            }
        }
    }

    private func nativeSwipeList<Row: View>(
        positions: [Investment],
        rowHeight: CGFloat,
        @ViewBuilder row: @escaping (Investment) -> Row
    ) -> some View {
        List {
            ForEach(positions) { inv in
                row(inv)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .frame(height: max(1, CGFloat(positions.count)) * (rowHeight + 8))
        .background(Color.clear)
        .environment(\.defaultMinListRowHeight, rowHeight)
    }

    private func deletePosition(_ inv: Investment) {
        if positionImpactPercent(inv) >= largeRemovalWeightThreshold {
            pendingRemovePosition = inv
            showRemovePositionConfirm = true
            haptic(.light)
            return
        }
        removePositionNow(inv)
    }

    private func removePositionNow(_ inv: Investment) {
        haptic(.rigid)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            vm.removeInvestment(id: inv.id)
        }
    }

    private func positionImpactPercent(_ inv: Investment) -> Double {
        let activePositions = vm.investments.filter { !$0.isWatchlist }
        let total = activePositions.reduce(0) { $0 + positionValue($1) }
        guard total > 0 else { return 0 }
        return positionValue(inv) / total * 100
    }

    private func removeWatchlistItem(_ inv: Investment) {
        haptic(.rigid)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            vm.removeInvestment(id: inv.id)
        }
    }

    private var sortButton: some View {
        Menu {
            ForEach(PositionSortMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.40, dampingFraction: 0.80)) {
                        storedPositionSortMode = mode.rawValue
                    }
                    haptic(.light)
                } label: {
                    Label {
                        Text(lm.t(mode.localizationKey))
                    } icon: {
                        Image(systemName: mode == positionSortMode ? "checkmark" : mode.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(lm.t(positionSortMode.localizationKey))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .buttonStyle(LiquidGlassButtonStyle(isActive: false, isCircle: false))
        .tint(Color.jade)
    }

    private func sortedActivePositions(_ investments: [Investment]) -> [Investment] {
        investments.sorted { lhs, rhs in
            switch positionSortMode {
            case .sinceBuy:
                let left = returnSinceBuyAmount(lhs)
                let right = returnSinceBuyAmount(rhs)
                return left == right ? lhs.symbol < rhs.symbol : left > right
            case .bestPerformer:
                let left = returnSinceBuyPercent(lhs)
                let right = returnSinceBuyPercent(rhs)
                return left == right ? lhs.symbol < rhs.symbol : left > right
            case .today:
                let left = vm.marketService.getStockInfo(for: lhs.symbol)?.dayChangePercent ?? 0
                let right = vm.marketService.getStockInfo(for: rhs.symbol)?.dayChangePercent ?? 0
                return left == right ? lhs.symbol < rhs.symbol : left > right
            case .totalValue:
                let left = positionValue(lhs)
                let right = positionValue(rhs)
                return left == right ? lhs.symbol < rhs.symbol : left > right
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .worstPerformer:
                let left = returnSinceBuyPercent(lhs)
                let right = returnSinceBuyPercent(rhs)
                return left == right ? lhs.symbol < rhs.symbol : left < right
            }
        }
    }

    private func positionValue(_ inv: Investment) -> Double {
        vm.selectedCurrencyValue(for: inv)
    }

    private func costValue(_ inv: Investment) -> Double {
        vm.selectedCurrencyCost(for: inv)
    }

    private func returnSinceBuyAmount(_ inv: Investment) -> Double {
        positionValue(inv) - costValue(inv)
    }

    private func returnSinceBuyPercent(_ inv: Investment) -> Double {
        let value = positionValue(inv)
        let cost = costValue(inv)
        guard cost > 0 else { return 0 }
        return ((value - cost) / cost) * 100
    }

    @ViewBuilder
    private func watchlistRow(_ inv: Investment) -> some View {
        let price   = vm.marketService.getCurrentPrice(for: inv.symbol)
        let gainPct = vm.marketService.getStockInfo(for: inv.symbol)?.dayChangePercent ?? 0.0

        HStack(spacing: 12) {
            symbolBadge(inv.symbol)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "#6366f1"))
                    Text(inv.symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                }
                Text(inv.name)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(CurrencyService.shared.format(value: price, from: inv.nativeCurrency))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                Text(String(format: "%@%.1f%%", gainPct >= 0 ? "+" : "", gainPct))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(gainPct.gainColor)
                    .contentTransition(.numericText())
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Color.textMuted.opacity(0.6))
        }
    }

    @ViewBuilder
    private func positionRow(_ inv: Investment) -> some View {
        let val     = positionValue(inv)
        let cost    = costValue(inv)
        let gain    = val - cost
        let gainPct = cost > 0 ? (gain / cost) * 100 : 0

        HStack(spacing: 12) {
            symbolBadge(inv.symbol)

            VStack(alignment: .leading, spacing: 3) {
                Text(inv.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text("\(String(format: "%.4g", inv.shares)) \(lm.t("portfolio.stueck"))  ·  Ø \(CurrencyService.shared.format(value: inv.buyPrice, from: inv.nativeCurrency))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(CurrencyService.shared.formatConverted(val))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                Text(String(format: "%@%.1f%%", gainPct >= 0 ? "+" : "", gainPct))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(gainPct.gainColor)
                    .contentTransition(.numericText())
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Color.textMuted.opacity(0.6))
        }
    }

    @ViewBuilder
    private func symbolBadge(_ symbol: String) -> some View {
        let colors: [(Color, Color)] = [
            (.jade.opacity(0.12),               .jade),
            (Color(hex: "#5eead4").opacity(0.10), Color(hex: "#5eead4")),
            (Color(hex: "#2dd4bf").opacity(0.10), Color(hex: "#2dd4bf")),
            (Color(hex: "#0f766e").opacity(0.15), Color(hex: "#34d399")),
            (Color(hex: "#ff4a6a").opacity(0.12), Color(hex: "#ff4a6a")),
            (Color(hex: "#86a69a").opacity(0.12), Color(hex: "#9ccfbe")),
        ]
        let pair = colors[abs(symbol.hashValue) % colors.count]

        let sfSymbolName: String? = {
            switch symbol.uppercased() {
            case "AAPL": return "apple.logo"
            case "BTC": return "bitcoinsign.circle.fill"
            default: return nil
            }
        }()

        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(pair.0)
                .frame(width: 32, height: 32)
            
            if let sfSymbolName {
                Image(systemName: sfSymbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(pair.1)
            } else {
                Text(String(symbol.prefix(2)))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(pair.1)
            }
        }
    }

    // MARK: - Einzel Tab (bubbles + floating glass pill)

    private var einzelTab: some View {
        ZStack {
            Color.bgDeep.ignoresSafeArea()

            BubblePhysicsView(vm: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environmentObject(lm)

            // ── Floating overlay row — top-left ───────────────────────────
            VStack {
                HStack(alignment: .center) {
                    portfolioPill
                    Spacer()
                    restoreBubbleButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer()
                // Minimal bottom hint
                Text(lm.t("einzel.tippe_ziehen"))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textMuted.opacity(0.45))
                    .padding(.bottom, 14)
            }
        }
    }

    // MARK: - Portfolio Info Pill (floating horizontal pill, left side)

    private var portfolioPill: some View {
        HStack(spacing: 12) {
            Text(lm.t("einzel.depot"))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.textMuted)
                .tracking(1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(CurrencyService.shared.formatConverted(vm.totalValue))
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.4), value: vm.totalValue)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .glassEffect(.regular.tint(Color.jade.opacity(0.05)), in: .capsule)
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.06), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .shadow(color: Color.jade.opacity(0.14), radius: 18, x: 0, y: 6)
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    // MARK: - Restore Bubble Button (Liquid Glass, green glow)

    private var restoreBubbleButton: some View {
        let enabled = vm.canUnpop
        return Button {
            showRestoreConfirm = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrowshape.turn.up.backward")
                    .font(.system(size: 12, weight: .semibold))
                Text(lm.t("actions.restoreBubble"))
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .buttonStyle(LiquidGlassButtonStyle(isActive: enabled, isCircle: false))
        .disabled(!enabled)
    }
}


// MARK: - Preview

#Preview {
    PortfolioView()
}
