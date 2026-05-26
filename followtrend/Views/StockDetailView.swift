//
//  StockDetailView.swift
//  followtrend
//
//  Full-screen detail sheet opened by tapping a position row or bubble.
//

import SwiftUI
import Combine

// MARK: - Detail ViewModel

@MainActor
final class StockDetailViewModel: ObservableObject {
    let investment: Investment
    let coinId: String?

    @Published var livePrice:   Double = 0
    @Published var priceChange: Double = 0  // % vs prev close
    @Published var isRefreshing = false

    private let marketService = MarketDataService.shared
    private let cryptoService = CryptoDataService.shared
    private var refreshTimer: AnyCancellable?

    init(investment: Investment, coinId: String? = nil) {
        self.investment = investment
        self.coinId     = coinId
        let initialPrice = StockMarketService.shared.getCurrentPrice(for: investment.symbol)
        self.livePrice  = initialPrice
        let prevClose   = StockMarketService.shared.getStockInfo(for: investment.symbol)?.prevPrice ?? initialPrice
        self.priceChange = prevClose > 0 ? ((initialPrice - prevClose) / prevClose) * 100 : 0
        startAutoRefresh()
    }

    var currentValue: Double { investment.shares * livePrice }
    var gainLoss:     Double { currentValue - investment.totalCost }
    var gainPercent:  Double {
        investment.totalCost > 0 ? (gainLoss / investment.totalCost) * 100 : 0
    }

    func refresh() {
        isRefreshing = true
        Task {
            do {
                if let id = coinId {
                    livePrice = try await cryptoService.currentPrice(coinId: id)
                } else {
                    // Fetch live quote from Finnhub
                    let price = try await marketService.fetchQuote(symbol: investment.symbol)
                    if price > 0 { livePrice = price }
                }
                let prevClose = StockMarketService.shared.getStockInfo(for: investment.symbol)?.prevPrice ?? livePrice
                priceChange = prevClose > 0 ? ((livePrice - prevClose) / prevClose) * 100 : 0
            } catch {}
            isRefreshing = false
        }
    }

    private func startAutoRefresh() {
        refresh()
        refreshTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }
}

// MARK: - Stock Detail View

struct StockDetailView: View {
    @StateObject private var detailVM: StockDetailViewModel
    @EnvironmentObject private var lm: AppLanguageManager
    @ObservedObject private var cs = CurrencyService.shared
    @ObservedObject private var alertStore = PriceAlertStore.shared
    @Environment(\.dismiss) private var dismiss

    /// Called when user taps the delete button in the list context
    private var onDelete: (() -> Void)?
    /// Called when user taps "Pop Bubble" — only passed from BubblePhysicsView
    private var onPop: (() -> Void)?
    private var onBuy: ((Double, Double, String) -> Void)?
    private var onEdit: ((Double, Double, String, String, String) -> Void)?

    @State private var showBuyInputs = false
    @State private var buySharesText = "1"
    @State private var buyPriceText = ""
    @State private var buyDate = Date()
    @State private var showEditSheet = false
    @State private var showAlertSheet = false

    init(
        investment: Investment,
        coinId:     String? = nil,
        onDelete:   (() -> Void)? = nil,
        onPop:      (() -> Void)? = nil,
        onBuy:      ((Double, Double, String) -> Void)? = nil,
        onEdit:     ((Double, Double, String, String, String) -> Void)? = nil
    ) {
        _detailVM = StateObject(wrappedValue: StockDetailViewModel(investment: investment, coinId: coinId))
        self.onDelete = onDelete
        self.onPop    = onPop
        self.onBuy    = onBuy
        self.onEdit   = onEdit
    }

    private var inv: Investment { detailVM.investment }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgDeep.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {

                        // Price header
                        priceHeader

                        // Real chart
                        ChartView(
                            symbol:     inv.symbol,
                            coinId:     detailVM.coinId,
                            isPositive: inv.isWatchlist ? (detailVM.priceChange >= 0) : (detailVM.gainLoss >= 0)
                        )
                        .cardStyle()

                        // Position summary
                        positionCard

                        // Market info
                        marketInfoCard

                        // Delete / Pop actions
                        if onDelete != nil || onPop != nil {
                            actionSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 60)
                }
            }
            .navigationTitle(inv.symbol)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.textMuted)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if detailVM.isRefreshing {
                        ProgressView()
                            .tint(Color.jade)
                            .scaleEffect(0.8)
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                EditPositionView(investment: inv) { shares, price, date, notes, tags in
                    onEdit?(shares, price, date, notes, tags)
                    showEditSheet = false
                }
            }
            .sheet(isPresented: $showAlertSheet) {
                PriceAlertSheet(
                    investment: inv,
                    livePrice: detailVM.livePrice,
                    existingAlert: alertStore.alert(for: inv.id)
                ) { alert in
                    alertStore.upsert(alert)
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .environmentObject(lm)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Price header

    private var priceHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(inv.name)
                .font(.system(size: 14))
                .foregroundStyle(Color.textSecondary)

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(CurrencyService.shared.format(value: detailVM.livePrice, from: inv.nativeCurrency))
                    .font(.system(size: 38, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: detailVM.livePrice)

                dayChangeBadge
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var dayChangeBadge: some View {
        let pct = inv.isWatchlist ? detailVM.priceChange : detailVM.gainPercent
        HStack(spacing: 3) {
            Image(systemName: pct >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 9))
            Text(String(format: "%@%.2f%%", pct >= 0 ? "+" : "", pct))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(pct.gainColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(pct.gainColor.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Position card

    private var positionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if inv.isWatchlist {
                // Watchlist Item Status
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lm.t("detail.watchlist_item"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "#6366f1"))
                            .tracking(1.1)
                        Text(inv.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "eye.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: "#6366f1"))
                }

                if let alert = alertStore.alert(for: inv.id), alert.isEnabled {
                    HStack(spacing: 7) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "#818cf8"))
                        Text(alertSummary(alert))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(hex: "#6366f1").opacity(0.10))
                    .clipShape(Capsule())
                }
                
                Divider().background(Color.borderHair)
                
                if !showBuyInputs {
                    // "Buy (Move to Portfolio)" Button
                    Button {
                        // Prefill price if available
                        if buyPriceText.isEmpty && detailVM.livePrice > 0 {
                            buyPriceText = String(format: "%.2f", detailVM.livePrice)
                        }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showBuyInputs = true
                        }
                        haptic()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text(lm.t("actions.convert"))
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(Color.textPrimary)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.jade.opacity(0.15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.jade.opacity(0.35), lineWidth: 0.8)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    // Inline buy fields: Shares, Price, Date
                    VStack(spacing: 12) {
                        // Shares
                        HStack {
                            Text(lm.t("add.stueckzahl"))
                                .font(.system(size: 14))
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            TextField("1.0", text: $buySharesText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.jade)
                                .frame(maxWidth: 120)
                        }
                        
                        Divider().background(Color.borderHair)
                        
                        // Price
                        HStack {
                            Text(lm.t("add.kaufpreis_eur").replacingOccurrences(of: " (€)", with: "").replacingOccurrences(of: " ($)", with: ""))
                                .font(.system(size: 14))
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            TextField("0.00", text: $buyPriceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.jade)
                                .frame(maxWidth: 120)
                        }
                        
                        Divider().background(Color.borderHair)
                        
                        // Date Picker
                        DatePicker(lm.t("detail.kaufdatum"),
                                   selection: $buyDate,
                                   in: ...Date(),
                                   displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .tint(.jade)
                            .foregroundStyle(Color.textSecondary)
                            .font(.system(size: 14))
                        
                        Divider().background(Color.borderHair)
                        
                        // Cancel / Confirm buttons
                        HStack(spacing: 12) {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    showBuyInputs = false
                                }
                                haptic()
                            } label: {
                                Text(lm.t("add.abbrechen"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.textMuted)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity)
                                    .background {
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                                    }
                            }
                            .buttonStyle(.plain)
                            
                            let valShares = Double(buySharesText.replacingOccurrences(of: ",", with: ".")) ?? 0.0
                            let valPrice = Double(buyPriceText.replacingOccurrences(of: ",", with: ".")) ?? 0.0
                            let canConfirm = valShares > 0 && valPrice > 0
                            
                            Button {
                                guard canConfirm else { return }
                                let fmt = DateFormatter()
                                fmt.dateFormat = "yyyy-MM-dd"
                                onBuy?(valShares, valPrice, fmt.string(from: buyDate))
                                haptic(.rigid)
                                dismiss()
                            } label: {
                                Text(lm.t("common.fertig"))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(canConfirm ? Color.textPrimary : Color.textMuted)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity)
                                    .background {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(canConfirm ? Color.jade.opacity(0.2) : Color.white.opacity(0.04))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .strokeBorder(canConfirm ? Color.jade.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 0.8)
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                            .disabled(!canConfirm)
                        }
                        .padding(.top, 6)
                    }
                }
            } else {
                Text(lm.t("detail.meine_position"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.textMuted)
                    .tracking(1.1)

                HStack {
                    infoCell(lm.t("detail.stueck"),      value: String(format: "%.4g", inv.shares))
                    Spacer()
                    infoCell(lm.t("detail.kaufpreis"), value: CurrencyService.shared.format(value: inv.buyPrice, from: inv.nativeCurrency))
                    Spacer()
                    infoCell(lm.t("detail.kaufdatum"),  value: inv.buyDate)
                }

                Divider().background(Color.borderHair)

                HStack {
                    infoCell(lm.t("detail.aktuelle_wert"),
                             value: CurrencyService.shared.format(value: detailVM.currentValue, from: inv.nativeCurrency),
                             color: .textPrimary)
                    Spacer()
                    infoCell(lm.t("detail.gewinn_verlust"),
                             value: String(format: "%@%@ (%@%.1f%%)",
                                           detailVM.gainLoss >= 0 ? "+" : "",
                                           CurrencyService.shared.format(value: abs(detailVM.gainLoss), from: inv.nativeCurrency),
                                           detailVM.gainPercent >= 0 ? "+" : "",
                                           detailVM.gainPercent),
                             color: detailVM.gainLoss.gainColor)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Market info

    private var marketInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lm.t("detail.marktdaten"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.textMuted)
                .tracking(1.1)

            HStack {
                infoCell(lm.t("detail.symbol"),   value: inv.symbol)
                Spacer()
                infoCell(lm.t("detail.typ"),      value: detailVM.coinId != nil ? lm.t("detail.crypto") : lm.t("detail.aktie"))
                Spacer()
                infoCell(lm.t("detail.quelle"),   value: detailVM.coinId != nil ? "CoinGecko" : "Finnhub")
            }
        }
        .cardStyle()
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            // Edit Position Button (only for active investments)
            if !inv.isWatchlist && onEdit != nil {
                Button {
                    showEditSheet = true
                    haptic()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "pencil")
                            .font(.system(size: 15, weight: .semibold))
                        Text(lm.t("actions.edit"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Color.jade)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.jade.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.jade.opacity(0.25), lineWidth: 0.7)
                            )
                    }
                }
                .buttonStyle(.plain)
            }

            if inv.isWatchlist {
                Button {
                    showAlertSheet = true
                    haptic()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 15, weight: .semibold))
                        Text(lm.t("alerts.setAlert"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "#818cf8"))
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(hex: "#6366f1").opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color(hex: "#818cf8").opacity(0.28), lineWidth: 0.7)
                            )
                    }
                }
                .buttonStyle(.plain)
            }

            // Pop Bubble (or fallback to Remove if Pop is missing)
            if let action = inv.isWatchlist ? onDelete : (onPop ?? onDelete) {
                let isPop = !inv.isWatchlist && onPop != nil
                Button {
                    haptic(.rigid)
                    action()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isPop ? "circle.dotted.and.circle" : "trash.fill")
                            .font(.system(size: 17, weight: .semibold))
                        Text(isPop ? lm.t("actions.popBubble") : lm.t("actions.remove"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(isPop ? Color.orange : Color.crimson)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill((isPop ? Color.orange : Color.crimson).opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder((isPop ? Color.orange : Color.crimson).opacity(0.25), lineWidth: 0.7)
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Info cell

    @ViewBuilder
    private func infoCell(_ title: String, value: String, color: Color = .textSecondary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Color.textMuted)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func alertSummary(_ alert: PriceAlert) -> String {
        let title = lm.t(alert.kind.localizationKey)
        guard alert.kind.requiresThreshold else { return title }

        if alert.kind == .dailyChangeAbove {
            return "\(title) \(String(format: "%.1f%%", alert.targetPriceBase))"
        }

        return "\(title) \(CurrencyService.shared.format(value: alert.targetPriceBase, from: alert.baseCurrency))"
    }
}
