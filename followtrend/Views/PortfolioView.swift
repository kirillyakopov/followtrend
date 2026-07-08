//
//  PortfolioView.swift
//  followtrend
//

import SwiftUI
import Combine

// PositionSortMode is defined in Models/RowModels.swift

private let largeRemovalWeightThreshold: Double = 35

// README §1.7 search-field fill: rgba(118,118,128,0.16)
private let searchFieldFill = Color(red: 118.0/255.0, green: 118.0/255.0, blue: 128.0/255.0).opacity(0.16)
// README §5 ghost/watchlist dashed border: 1px dashed rgba(235,235,245,0.16)
private let ghostDashBorder = Color(red: 235.0/255.0, green: 235.0/255.0, blue: 245.0/255.0).opacity(0.16)
private let ghostDashStyle  = StrokeStyle(lineWidth: 1, dash: [4, 4])

// MARK: - Root Portfolio View

struct PortfolioView: View {

    @StateObject private var vm     = PortfolioViewModel()
    @EnvironmentObject private var lm: AppLanguageManager
    @ObservedObject private var cs = CurrencyService.shared
    @Namespace   private var navNamespace

    @State private var showPearsonInfo:    Bool = false
    @State private var showBubbleInfo:     Bool = false

    @State private var showRestoreConfirm: Bool = false
    @State private var showRemovePositionConfirm: Bool = false
    @State private var currentTab:         AppTab = .gesamt
    @State private var portfolioSearchText: String = ""
    @State private var selectedInvestment:  Investment? = nil
    @State private var editingInvestment:   Investment? = nil
    @State private var convertingInvestment: Investment? = nil
    @State private var pendingRemovePosition: Investment? = nil
    // Sort mode lives in vm.positionSortMode (persisted in PortfolioViewModel)

    enum AppTab: String, CaseIterable {
        case gesamt  = "Total"
        case bubbles = "Bubbles"
        case profile = "Profile"
        case add     = "Add"      // pseudo-tab → detached "+" circle next to the tab bar (never stays selected)

        var icon: String {
            switch self {
            case .gesamt:  return "chart.pie.fill"
            case .bubbles: return "circle.hexagongrid.fill"
            case .profile: return "person.crop.circle"
            case .add:     return "plus"
            }
        }
    }

    private var filteredActiveRows: [PositionRowModel] {
        let q = portfolioSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return vm.sortedActivePositions }
        return vm.sortedActivePositions.filter {
            $0.symbol.lowercased().hasPrefix(q) || $0.name.lowercased().contains(q)
        }
    }

    @State private var bubbleSearchText: String = ""
    
    private var filteredWatchlistRows: [WatchlistRowModel] {
        let q = portfolioSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return vm.watchlistRows }
        return vm.watchlistRows.filter {
            $0.symbol.lowercased().hasPrefix(q) || $0.name.lowercased().contains(q)
        }
    }

    @State private var previousTab: AppTab = .gesamt
    
    @State private var showAddSheet = false
    @State private var addIsWatchlist = false

    var body: some View {
        TabView(selection: $currentTab) {
            Tab(lm.t("tabs.gesamt"), systemImage: AppTab.gesamt.icon, value: .gesamt) {
                mainTabContent(for: .gesamt)
            }

            Tab(lm.t("tabs.bubbles"), systemImage: AppTab.bubbles.icon, value: .bubbles) {
                mainTabContent(for: .bubbles)
            }

            Tab(lm.t("tabs.profile"), systemImage: AppTab.profile.icon, value: .profile) {
                ProfileView(vm: vm)
            }

            // Native detached action circle beside the tab bar (iOS 26 Liquid Glass).
            // `role: .search` renders it separated from the main tab capsule; we
            // intercept selection below and treat it as a button, never a real tab.
            Tab(lm.t("portfolio.add_position_title"), systemImage: AppTab.add.icon, value: .add, role: .search) {
                Color.clear
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Color.mintAccent)
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: currentTab) { oldTab, newTab in
            guard newTab == .add else { return }
            currentTab = oldTab          // never actually switch — the "+" acts as a button
            haptic(.light)
            addIsWatchlist = false       // sheet opens in Portfolio mode; a segment inside switches to Watchlist
            showAddSheet = true
        }
        .sheet(isPresented: $showAddSheet) {
            AddStockView(vm: vm, isWatchlist: addIsWatchlist)
        }
        .sheet(isPresented: $showPearsonInfo) {
            PearsonInfoSheet()
                .presentationDetents([.medium, .large])
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
            case .gesamt:
                gesamtTab
            case .bubbles:
                einzelTab
            case .profile, .add:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PremiumDarkBackground())
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        let isPositive = vm.percentageGain >= 0
        let changeText = String(format: "%@%@ (%@%.2f%%)",
                                vm.absoluteGain >= 0 ? "+" : "-",
                                CurrencyService.shared.formatConverted(abs(vm.absoluteGain)),
                                isPositive ? "+" : "",
                                vm.percentageGain)
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                OverlineLabel(lm.t("einzel.depot"))
                Text(CurrencyService.shared.formatConverted(vm.totalValue))
                    .font(AppTypography.largeNumber)
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                Text(changeText)
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isPositive ? Color.gainText : Color.lossText)
                    .contentTransition(.numericText())
            }

            Spacer()

            // Live price indicator
            if vm.isPriceFetching {
                HStack(spacing: 4) {
                    ProgressView().tint(Color.mintAccent).scaleEffect(0.6)
                    Text(lm.t("portfolio.live"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.mintAccent.opacity(0.7))
                }
            }

            // Info button
            Button {
                showBubbleInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(LiquidGlassButtonStyle(isActive: showBubbleInfo, isCircle: true))

            // Restore popped bubbles (34pt glass circle + mint count badge)
            restoreBubbleButton
        }
        .padding(.horizontal, AppLayout.contentHorizontalPadding)
        .padding(.vertical, 14)
    }



    // MARK: - Gesamt Tab

    private var gesamtTabHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                // Date overline — "TUESDAY, JUL 8" (13pt/600 secondary)
                Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .textCase(.uppercase)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Color.labelSecondary)

                Text(lm.t("add.portfolio"))
                    .font(AppTypography.screenTitle)
                    .tracking(-0.7)
                    .foregroundStyle(Color.textPrimary)
            }
            Spacer()

            if vm.isPriceFetching {
                HStack(spacing: 4) {
                    ProgressView().tint(Color.mintAccent).scaleEffect(0.6)
                    Text(lm.t("portfolio.live"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.mintAccent.opacity(0.7))
                }
                .padding(.bottom, 6)
            }
        }
        .padding(.horizontal, AppLayout.contentHorizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var gesamtTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                gesamtTabHeader
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                    balanceCard
                    chartCard

                    // Portfolio insight / advice cards (allocation, rebalancing, correlation, etc.)
                    if !vm.sortedActivePositions.isEmpty {
                        PortfolioAdviceCardsView(snapshot: vm.adviceSnapshot, onCorrelationTap: { showPearsonInfo = true })
                    }
                    
                    positionsList
                }
                .padding(.horizontal, AppLayout.contentHorizontalPadding)
                .padding(.bottom, 40)
                }
            }
            .background(PremiumDarkBackground().ignoresSafeArea())
        }
    }

    // MARK: - Balance Card

    private var balanceCard: some View {
        let isPositive = vm.percentageGain >= 0
        let changeText = String(format: "%@%@ (%@%.2f%%)",
                                vm.absoluteGain >= 0 ? "+" : "-",
                                CurrencyService.shared.formatConverted(abs(vm.absoluteGain)),
                                isPositive ? "+" : "",
                                vm.percentageGain)
        return VStack(alignment: .leading, spacing: 10) {
            OverlineLabel(lm.t("portfolio.net_worth"))

            Text(CurrencyService.shared.formatConverted(vm.totalValue))
                .font(AppTypography.hugeNumber)
                .tracking(-1.4)
                .foregroundStyle(Color.textPrimary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.4), value: vm.totalValue)

            ChangePill(text: changeText, isPositive: isPositive, trailing: lm.t("portfolio.seit_kauf"))
                .animation(.easeInOut(duration: 0.4), value: vm.percentageGain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(lm.t("portfolio.all_time_return"))
                .font(AppTypography.cardTitle)
                .foregroundStyle(Color.textMuted)
                .tracking(1.2)
            
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "%@%@", vm.absoluteGain >= 0 ? "+" : "-", CurrencyService.shared.formatConverted(abs(vm.absoluteGain))))
                        .font(AppTypography.largeNumber)
                        .foregroundStyle(vm.absoluteGain.gainColor)
                        .contentTransition(.numericText())
                    
                    Text(String(format: "%@%.2f%%", vm.percentageGain >= 0 ? "+" : "", vm.percentageGain))
                        .font(AppTypography.number)
                        .foregroundStyle(vm.percentageGain.gainColor)
                        .contentTransition(.numericText())
                }
                Spacer()
            }
            
            // Full width chart
            PortfolioChartView(
                chartTrigger: vm.chartTrigger,
                isPositive: vm.absoluteGain >= 0,
                fetchCandles: { tf in try await vm.fetchPortfolioCandles(timeframe: tf) }
            )
        }
        .cardStyle()
    }


    // MARK: - Positions List (with swipe-to-delete)

    private var positionsList: some View {
        VStack(alignment: .leading, spacing: 20) {
            // ── Portfolio Search (§1.7) ──
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textPrimary.opacity(0.45))
                TextField(lm.t("search.portfolio"), text: $portfolioSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundColor(Color.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                if !portfolioSearchText.isEmpty {
                    Button { portfolioSearchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color.labelTertiary)
                            .font(.system(size: 14))
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(searchFieldFill)
            )

            // No-match banner when search returns nothing
            if !portfolioSearchText.isEmpty && filteredActiveRows.isEmpty && filteredWatchlistRows.isEmpty {
                Text(lm.t("search.noResults"))
                    .font(.system(size: 14))
                    .foregroundColor(Color.labelTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }

            // ── Positions Section (§1.8 header + §1.9 list) ──
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(lm.t("portfolio.positionen"))
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(Color.textPrimary)
                        Text("\(filteredActiveRows.count)")
                            .font(.system(size: 15, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.labelTertiary)
                    }
                    Spacer()
                    sortButton
                }

                if filteredActiveRows.isEmpty && portfolioSearchText.isEmpty {
                    Text(lm.t("portfolio.keine_positionen"))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.labelTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else if !filteredActiveRows.isEmpty {
                    activePositionsList(filteredActiveRows)
                }
            }

            // ── Watchlist Section (§5) ──
            if !vm.watchlistRows.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    OverlineLabel("\(lm.t("portfolio.watchlist")) (\(filteredWatchlistRows.count))")

                    // Ghost info strip — dashed border, dashed-circle glyph
                    HStack(spacing: 10) {
                        Image(systemName: "circle.dashed")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.labelSecondary)
                        Text(lm.t("watchlist.ghost_hint"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.labelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.035))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(ghostDashBorder, style: ghostDashStyle)
                    )

                    if filteredWatchlistRows.isEmpty && portfolioSearchText.isEmpty {
                        Text(lm.t("portfolio.keine_positionen"))
                            .font(.system(size: 14))
                            .foregroundStyle(Color.labelTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    } else if !filteredWatchlistRows.isEmpty {
                        watchlistPositionsList(filteredWatchlistRows)
                    }
                }
            }

            // ── Footer hint (§1.10) ──
            Text(lm.t("portfolio.row_hint"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.labelQuaternary)
                .frame(maxWidth: .infinity)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: vm.sortedActivePositions.map(\.id))
    }

    private func activePositionsList(_ rows: [PositionRowModel]) -> some View {
        nativeSwipeList(rows: rows) { row in
            Button {
                haptic(.medium)
                if let inv = vm.investments.first(where: { $0.id == row.investmentID }) {
                    selectedInvestment = inv
                }
            } label: {
                positionRow(row)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    if let inv = vm.investments.first(where: { $0.id == row.investmentID }) {
                        editingInvestment = inv
                    }
                } label: {
                    Label(lm.t("actions.edit"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    if let inv = vm.investments.first(where: { $0.id == row.investmentID }) {
                        deletePosition(inv)
                    }
                } label: {
                    Label(lm.t("actions.remove"), systemImage: "trash")
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    haptic(.light)
                    if let inv = vm.investments.first(where: { $0.id == row.investmentID }) {
                        editingInvestment = inv
                    }
                } label: {
                    Label(lm.t("actions.edit"), systemImage: "pencil")
                }
                .tint(Color(white: 0.35))

                Button(role: .destructive) {
                    if let inv = vm.investments.first(where: { $0.id == row.investmentID }) {
                        deletePosition(inv)
                    }
                } label: {
                    Label(lm.t("actions.remove"), systemImage: "trash")
                }
                .tint(Color.destructive)
            }
        }
    }

    private func watchlistPositionsList(_ rows: [WatchlistRowModel]) -> some View {
        nativeSwipeList(rows: rows, rowHeight: 72, container: false) { row in
            Button {
                haptic(.medium)
                if let inv = vm.investments.first(where: { $0.id == row.investmentID }) {
                    selectedInvestment = inv
                }
            } label: {
                watchlistRow(row)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    haptic(.light)
                    if let inv = vm.investments.first(where: { $0.id == row.investmentID }) {
                        convertingInvestment = inv
                    }
                } label: {
                    Label(lm.t("actions.convert"), systemImage: "arrow.triangle.2.circlepath")
                }
                .tint(Color(hex: "#1E7A54"))

                Button(role: .destructive) {
                    if let inv = vm.investments.first(where: { $0.id == row.investmentID }) {
                        removeWatchlistItem(inv)
                    }
                } label: {
                    Label(lm.t("actions.remove"), systemImage: "trash")
                }
                .tint(Color.destructive)
            }
        }
    }

    /// Native `List` wrapper that keeps `.swipeActions` working.
    /// `container == true` → §1.9: one opaque #101013 container, radius 24,
    /// 0.5px border, hairline inset separators. `container == false` → §5:
    /// transparent rows (each row draws its own dashed watch card) with 10pt gaps.
    @ViewBuilder
    private func nativeSwipeList<T: Identifiable>(rows: [T],
                                 rowHeight: CGFloat = 68,
                                 container: Bool = true,
                                 @ViewBuilder row: @escaping (T) -> some View) -> some View {
        let list = List {
            ForEach(rows) { item in
                row(item)
                    .listRowInsets(container
                                   ? EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
                                   : EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                    .listRowBackground(container ? Color.surface : Color.clear)
                    .listRowSeparator((container && item.id != rows.last?.id) ? .visible : .hidden)
                    .listRowSeparatorTint(Color.separatorHair)
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 52 }
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
        .frame(height: max(1, CGFloat(rows.count)) * rowHeight)
        .background(Color.clear)
        .environment(\.defaultMinListRowHeight, rowHeight)

        if container {
            list
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        } else {
            list
        }
    }

    private func deletePosition(_ inv: Investment) {
        let rowModel = vm.sortedActivePositions.first { $0.investmentID == inv.id }
        let weight = rowModel.map { r in
            let total = vm.sortedActivePositions.reduce(0.0) { $0 + $1.totalValue }
            return total > 0 ? r.totalValue / total * 100 : 0.0
        } ?? 0.0
        if weight >= largeRemovalWeightThreshold {
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
                        vm.positionSortMode = mode
                    }
                    haptic(.light)
                } label: {
                    Label {
                        Text(lm.t(mode.localizationKey))
                    } icon: {
                        Image(systemName: mode == vm.positionSortMode ? "checkmark" : mode.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                Text(lm.t(vm.positionSortMode.localizationKey))
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .buttonStyle(LiquidGlassButtonStyle(isActive: false, isCircle: false))
        .tint(Color.mintAccent)
    }

    // MARK: - Row helpers (reads pre-formatted strings from model — no calculation)


    /// §5 — separate dashed "ghost" card per watchlist row.
    @ViewBuilder
    private func watchlistRow(_ row: WatchlistRowModel) -> some View {
        HStack(spacing: 12) {
            MonogramTile(symbol: row.symbol, size: 38)
                .grayscale(0.7)
                .opacity(0.6)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.labelTertiary)
                    Text(row.symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.textPrimary.opacity(0.85))
                }
                Text(row.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color(red: 235.0/255.0, green: 235.0/255.0, blue: 245.0/255.0).opacity(0.42))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(row.priceText)
                    .font(AppTypography.number)
                    .foregroundStyle(Color.textPrimary.opacity(0.85))
                    .contentTransition(.numericText())
                Text(row.dayChangeText)
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle((row.dayChangePositive ? Color.gainText : Color.lossText).opacity(0.7))
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.surfaceWatch)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ghostDashBorder, style: ghostDashStyle)
        )
    }

    /// §1.9 — ~68pt position row inside the opaque list container.
    @ViewBuilder
    private func positionRow(_ row: PositionRowModel) -> some View {
        HStack(spacing: 12) {
            MonogramTile(symbol: row.symbol, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Text(row.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(row.sharesSubtitle)
                    let weight = vm.totalValue > 0 ? (row.totalValue / vm.totalValue) * 100 : 0
                    Text(String(format: "· %.1f%%", weight))
                        .monospacedDigit()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.labelTertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(row.valueText)
                    .font(AppTypography.number)
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                Text(row.gainPercentText)
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(row.isPositive ? Color.gainText : Color.lossText)
                    .contentTransition(.numericText())
            }
        }
    }

    // MARK: - Einzel Tab (bubbles + floating glass pill)

    private var einzelTab: some View {
        ZStack {
            Color.bgDeep.ignoresSafeArea()

            BubblePhysicsView(vm: vm, searchText: bubbleSearchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environmentObject(lm)

            // ── Floating overlay row — top-left ───────────────────────────
            VStack(spacing: 12) {
                // Search Bar (§1.7 recipe: 38pt, radius 13, gray 16% fill)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textPrimary.opacity(0.45))
                    TextField(lm.t("add.aktien_etfs_krypto_suchen"), text: $bubbleSearchText)
                        .foregroundColor(Color.textPrimary)
                        .font(.system(size: 14))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    if !bubbleSearchText.isEmpty {
                        Button { bubbleSearchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color.labelTertiary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(searchFieldFill)
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)

                HStack(alignment: .center) {
                    bubblesLegend
                    Spacer()
                }
                .padding(.horizontal, 16)

                Spacer()
                // Minimal bottom hint (§2)
                Text(lm.t("bubbles.interactionHint"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.30))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 14)
            }
        }
    }

    // MARK: - Bubbles Legend (floating horizontal pill, left side)

    private var bubblesLegend: some View {
        let active = vm.sortedActivePositions
        let gaining = active.filter { $0.gainPercent > 0 }.count
        let losing = active.filter { $0.gainPercent < 0 }.count

        return HStack(spacing: 12) {
            legendPillDot(color: Color.mintAccent, count: gaining, label: lm.t("bubbles.gaining"))
            legendPillDot(color: Color.lossBase, count: losing, label: lm.t("bubbles.losing"))
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .glassEffect(.regular.tint(Color.white.opacity(0.02)), in: .capsule)
        }
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    private func legendPillDot(color: Color, count: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textMuted)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
    }

    // MARK: - Restore Bubble Button (§2 — 34pt glass circle + mint count badge)

    private var restoreBubbleButton: some View {
        let enabled = vm.canUnpop
        let poppedCount = vm.poppedBubbles.count
        return Button {
            showRestoreConfirm = true
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 15, weight: .semibold))
                .opacity(enabled ? 1.0 : 0.4)
        }
        .buttonStyle(LiquidGlassButtonStyle(isActive: enabled, isCircle: true))
        .overlay(alignment: .topTrailing) {
            if poppedCount > 0 {
                Text("\(poppedCount)")
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.mintInk)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 16)
                    .frame(height: 16)
                    .background(Capsule().fill(Color.mintAccent))
                    .offset(x: 4, y: -4)
            }
        }
        .disabled(!enabled)
        .accessibilityLabel(lm.t("actions.restoreBubble"))
    }
}


// MARK: - Shared Logo Component

struct AppLogoView: View {
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.mintAccent.opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.mintAccent)
            }
            Text("followtrend")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.textPrimary)
        }
    }
}

// MARK: - Preview

#Preview {
    PortfolioView()
}
