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

    func displayPrice(mode: PriceSourceMode) -> Double {
        investment.displayPrice(apiPrice: livePrice, mode: mode)
    }

    func currentValue(mode: PriceSourceMode) -> Double {
        investment.shares * displayPrice(mode: mode)
    }

    func gainLoss(mode: PriceSourceMode) -> Double {
        currentValue(mode: mode) - investment.totalCost
    }

    func gainPercent(mode: PriceSourceMode) -> Double {
        investment.totalCost > 0 ? (gainLoss(mode: mode) / investment.totalCost) * 100 : 0
    }

    func refresh() {
        isRefreshing = true
        Task {
            do {
                if let id = coinId {
                    livePrice = try await cryptoService.currentPrice(coinId: id)
                } else {
                    // Fetch live quote
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
    private var onEdit: ((Double, Double, String, String, String, BrokerAdjustmentDraft?, Bool) -> Void)?
    private let priceSourceMode: PriceSourceMode

    @State private var showBuyInputs = false
    @State private var buySharesText = "1"
    @State private var buyPriceText = ""
    @State private var buyDate = Date()
    @State private var showEditSheet = false
    @State private var showAlertSheet = false

    init(
        investment: Investment,
        coinId:     String? = nil,
        priceSourceMode: PriceSourceMode = .market,
        onDelete:   (() -> Void)? = nil,
        onPop:      (() -> Void)? = nil,
        onBuy:      ((Double, Double, String) -> Void)? = nil,
        onEdit:     ((Double, Double, String, String, String, BrokerAdjustmentDraft?, Bool) -> Void)? = nil
    ) {
        _detailVM = StateObject(wrappedValue: StockDetailViewModel(investment: investment, coinId: coinId))
        self.onDelete = onDelete
        self.onPop    = onPop
        self.onBuy    = onBuy
        self.onEdit   = onEdit
        self.priceSourceMode = priceSourceMode
    }

    private var inv: Investment { detailVM.investment }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgDeep.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // Header: 52pt tile · ticker + company · price + day change
                        priceHeader

                        // Real chart (component restyled separately) + period footer
                        chartCard

                        // Statistics grid
                        statisticsCard

                        // Context-dependent position / watchlist section
                        positionCard

                        // Context actions (edit / alert / pop / remove)
                        if onDelete != nil || onPop != nil {
                            actionSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 60)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.labelSecondary)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if detailVM.isRefreshing {
                        ProgressView()
                            .tint(Color.mintAccent)
                            .scaleEffect(0.8)
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                EditPositionView(investment: inv, currentApiPrice: detailVM.livePrice) { shares, price, date, notes, tags, brokerDraft, clearsBrokerAdjustment in
                    onEdit?(shares, price, date, notes, tags, brokerDraft, clearsBrokerAdjustment)
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

    // MARK: - Header

    private var priceHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            MonogramTile(symbol: inv.symbol, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(inv.symbol)
                    .font(AppTypography.sheetTitle)
                    .foregroundStyle(Color.textPrimary)
                Text(inv.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(CurrencyService.shared.format(value: inv.isWatchlist ? detailVM.livePrice : detailVM.displayPrice(mode: priceSourceMode), from: inv.nativeCurrency))
                    .font(.system(size: 21, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: detailVM.livePrice)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(String(format: "%@%.2f%% %@", detailVM.priceChange >= 0 ? "+" : "", detailVM.priceChange, lm.t("detail.today_suffix")))
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(detailVM.priceChange.gainTextColor)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Chart card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChartView(
                symbol:     inv.symbol,
                coinId:     detailVM.coinId,
                isPositive: inv.isWatchlist ? (detailVM.priceChange >= 0) : (detailVM.gainLoss(mode: priceSourceMode) >= 0),
                priceAdjustmentFactor: inv.priceAdjustmentFactor,
                displayBrokerAdjustedChart: priceSourceMode == .brokerAdjusted
            )

            HStack {
                OverlineLabel(lm.t("sort.today"))
                Spacer()
                Text(String(format: "%@%.2f%%", detailVM.priceChange >= 0 ? "+" : "", detailVM.priceChange))
                    .font(.system(size: 10.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(detailVM.priceChange.gainTextColor)
            }
        }
        .cardStyle()
    }

    // MARK: - Position / Watchlist context

    @ViewBuilder
    private var positionCard: some View {
        if inv.isWatchlist {
            watchlistSection
        } else {
            ownedPositionCard
        }
    }

    /// "YOUR POSITION" card — mint 7% fill, mint 14% border, radius 18.
    private var ownedPositionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            OverlineLabel(lm.t("detail.meine_position"), color: Color.mintAccent.opacity(0.7))

            HStack(alignment: .top) {
                statColumn(lm.t("detail.stueck"), value: String(format: "%.4g", inv.shares))
                Spacer(minLength: 10)
                statColumn(lm.t("detail.kaufpreis"), value: CurrencyService.shared.format(value: inv.buyPrice, from: inv.nativeCurrency))
                Spacer(minLength: 10)
                statColumn(lm.t("detail.gewinn_verlust"),
                           value: String(format: "%@%.1f%%",
                                         detailVM.gainPercent(mode: priceSourceMode) >= 0 ? "+" : "",
                                         detailVM.gainPercent(mode: priceSourceMode)),
                           color: detailVM.gainLoss(mode: priceSourceMode).gainTextColor,
                           alignment: .trailing)
            }

            Rectangle()
                .fill(Color.separatorHair)
                .frame(height: 0.5)

            HStack(alignment: .top) {
                statColumn(lm.t("detail.aktuelle_wert"),
                           value: CurrencyService.shared.format(value: detailVM.currentValue(mode: priceSourceMode), from: inv.nativeCurrency))
                Spacer(minLength: 10)
                statColumn(lm.t("detail.gewinn_verlust"),
                           value: String(format: "%@%@",
                                         detailVM.gainLoss(mode: priceSourceMode) >= 0 ? "+" : "−",
                                         CurrencyService.shared.format(value: abs(detailVM.gainLoss(mode: priceSourceMode)), from: inv.nativeCurrency)),
                           color: detailVM.gainLoss(mode: priceSourceMode).gainTextColor)
                Spacer(minLength: 10)
                statColumn(lm.t("detail.kaufdatum"), value: inv.buyDate, alignment: .trailing)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.mintAccent.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.mintAccent.opacity(0.14), lineWidth: 1)
                )
        }
    }

    /// Watchlist context: dashed ghost info strip + convert flow.
    private var watchlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Dashed info strip
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.labelSecondary)
                    Text(lm.t("detail.watchlist_ghost_info"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let alert = alertStore.alert(for: inv.id), alert.isEnabled {
                    HStack(spacing: 7) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.mintAccent)
                        Text(alertSummary(alert))
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.labelSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                Color(hex: "#EBEBF5").opacity(0.16),
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                    )
            }

            if !showBuyInputs {
                // Convert to Position — prominent mint glass, dark ink
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
                    Text(lm.t("detail.convert_to_position"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.mintInk)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.mintAccent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
            } else {
                buyInputsCard
            }
        }
    }

    /// Inline convert form — inset grouped rows on opaque surface.
    private var buyInputsCard: some View {
        let valShares = Double(buySharesText.replacingOccurrences(of: ",", with: ".")) ?? 0.0
        let valPrice = Double(buyPriceText.replacingOccurrences(of: ",", with: ".")) ?? 0.0
        let canConfirm = valShares > 0 && valPrice > 0

        return VStack(spacing: 12) {
            VStack(spacing: 0) {
                formNumberRow(label: lm.t("add.stueckzahl"), placeholder: "0.00", text: $buySharesText)

                Rectangle().fill(Color.separatorHair).frame(height: 0.5)

                formNumberRow(
                    label: lm.t("add.kaufpreis_eur").replacingOccurrences(of: " (€)", with: "").replacingOccurrences(of: " ($)", with: ""),
                    placeholder: "0.00",
                    text: $buyPriceText
                )

                Rectangle().fill(Color.separatorHair).frame(height: 0.5)

                DatePicker(lm.t("detail.kaufdatum"),
                           selection: $buyDate,
                           in: ...Date(),
                           displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(.mintAccent)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.labelSecondary)
                    .padding(.vertical, 8)

                if canConfirm {
                    HStack {
                        Spacer()
                        Text("≈ \(CurrencyService.shared.format(value: valShares * valPrice, from: inv.nativeCurrency))")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .padding(.bottom, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            }

            // Cancel / Confirm buttons
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showBuyInputs = false
                    }
                    haptic()
                } label: {
                    Text(lm.t("add.abbrechen"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .buttonBorderShape(.capsule)

                Button {
                    guard canConfirm else { return }
                    let fmt = DateFormatter()
                    fmt.dateFormat = "yyyy-MM-dd"
                    onBuy?(valShares, valPrice, fmt.string(from: buyDate))
                    haptic(.rigid)
                    dismiss()
                } label: {
                    Text(lm.t("common.fertig"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.mintInk)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.mintAccent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .disabled(!canConfirm)
            }
        }
    }

    // MARK: - Statistics grid

    private var statisticsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            OverlineLabel(lm.t("detail.marktdaten"))

            statRow(
                leftKey: lm.t("detail.symbol"), leftValue: inv.symbol,
                rightKey: lm.t("detail.typ"), rightValue: detailVM.coinId != nil ? lm.t("detail.crypto") : lm.t("detail.aktie")
            )

            Rectangle()
                .fill(Color.separatorHair)
                .frame(height: 0.5)

            statRow(
                leftKey: lm.t("detail.quelle"), leftValue: detailVM.coinId != nil ? "CoinGecko" : "Yahoo Finance",
                rightKey: inv.isWatchlist ? nil : lm.t("detail.kaufdatum"),
                rightValue: inv.isWatchlist ? nil : inv.buyDate
            )
        }
        .cardStyle(cornerRadius: 20)
    }

    @ViewBuilder
    private func statRow(leftKey: String, leftValue: String, rightKey: String?, rightValue: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            statColumn(leftKey, value: leftValue)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let rightKey, let rightValue {
                statColumn(rightKey, value: rightValue)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: 1)
            }
        }
    }

    // MARK: - Actions

    private var actionSection: some View {
        VStack(spacing: 12) {
            // Edit Position (only for active investments) — neutral glass
            if !inv.isWatchlist && onEdit != nil {
                Button {
                    showEditSheet = true
                    haptic()
                } label: {
                    Text(lm.t("detail.edit_position"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
            }

            // Set Price Alert (watchlist) — neutral glass
            if inv.isWatchlist {
                Button {
                    showAlertSheet = true
                    haptic()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 14, weight: .semibold))
                        Text(lm.t("alerts.setAlert"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
            }

            // Pop Bubble / Remove — destructive loss-tinted glass
            if let action = inv.isWatchlist ? onDelete : (onPop ?? onDelete) {
                let isPop = !inv.isWatchlist && onPop != nil
                Button {
                    haptic(.rigid)
                    action()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isPop ? "circle.dotted.and.circle" : "trash")
                            .font(.system(size: 14, weight: .semibold))
                        Text(isPop ? lm.t("actions.popBubble") : lm.t("actions.remove"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Color.lossText)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .tint(Color.lossBase)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
            }
        }
    }

    // MARK: - Cells & rows

    @ViewBuilder
    private func statColumn(_ title: String, value: String, color: Color = .textPrimary, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.labelTertiary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 14.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    @ViewBuilder
    private func formNumberRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.labelSecondary)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.mintAccent)
                .frame(maxWidth: 140)
        }
        .padding(.vertical, 12)
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
