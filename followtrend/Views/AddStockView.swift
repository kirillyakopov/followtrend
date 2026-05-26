//
//  AddStockView.swift
//  followtrend
//
//  Add Position sheet with:
//  - Live market search (stocks, ETFs, crypto)
//  - Auto-fetched current price on selection
//  - Liquid Glass UI throughout
//

import SwiftUI

struct AddStockView: View {
    @ObservedObject var vm: PortfolioViewModel
    @EnvironmentObject private var lm: AppLanguageManager
    @ObservedObject private var cs = CurrencyService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isSearching) private var isSearching
    @Environment(\.dismissSearch) private var dismissSearch

    @StateObject private var marketSearch = MarketSearchViewModel()

    @State private var sharesText   = ""
    @State private var priceText    = ""
    @State private var buyDate      = Date()
    @State private var shakeTrigger = false
    @State private var isWatchlist  = false
    @State private var showBrokerIntegration = false
    @State private var brokerPlatform = "Trade Republic"
    @State private var brokerPriceText = ""
    @State private var brokerCurrency: AppCurrency = .eur

    // Once user selects a result, these are set
    private var selectedSymbol: String? { marketSearch.selectedResult?.symbol }
    private var selectedName:   String? { marketSearch.selectedResult?.name }
    private var selectedKind:   AssetKind? { marketSearch.selectedResult?.kind }
    private var selectedCoinId: String? { marketSearch.selectedResult?.coinId }

    private var isSymbolChosen: Bool { marketSearch.selectedResult != nil }
    private let brokerPlatforms = ["Trade Republic", "Scalable", "IBKR", "Other", "Manual"]

    private var isValid: Bool {
        guard isSymbolChosen else { return false }
        if isWatchlist { return true }
        let s = Double(sharesText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let p = Double(priceText.replacingOccurrences(of: ",", with: "."))  ?? 0
        return s > 0 && p > 0
    }

    private var parsedBrokerPrice: Double {
        Double(brokerPriceText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var brokerAdjustmentFactor: Double? {
        guard let apiPrice = marketSearch.fetchedPrice, parsedBrokerPrice > 0 else { return nil }
        return Investment.adjustmentFactor(
            apiPrice: apiPrice,
            apiCurrency: .usd,
            brokerPrice: parsedBrokerPrice,
            brokerCurrency: brokerCurrency,
            displayCurrency: cs.selectedCurrency
        )
    }

    private var shouldShowBrokerWarning: Bool {
        guard let factor = brokerAdjustmentFactor else { return false }
        return factor < 0.95 || factor > 1.05
    }

    private var brokerAdjustmentDraft: BrokerAdjustmentDraft? {
        guard !isWatchlist, let apiPrice = marketSearch.fetchedPrice, parsedBrokerPrice > 0 else { return nil }
        return BrokerAdjustmentDraft(
            brokerName: brokerPlatform,
            currentBrokerPrice: parsedBrokerPrice,
            brokerCurrency: brokerCurrency,
            currentApiPrice: apiPrice
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgDeep.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        if !marketSearch.query.trimmingCharacters(in: .whitespaces).isEmpty && marketSearch.selectedResult == nil {
                            // Search Mode
                            if marketSearch.isSearching {
                                VStack(spacing: 12) {
                                    Spacer(minLength: 40)
                                    ProgressView()
                                        .tint(Color.jade)
                                    Text(lm.t("search.loading"))
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.textSecondary)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            } else if marketSearch.results.isEmpty {
                                VStack(spacing: 12) {
                                    Spacer(minLength: 40)
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 32))
                                        .foregroundStyle(Color.textMuted)
                                    Text(lm.t("search.noResults"))
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(Color.textPrimary)
                                    Text(lm.t("portfolio.keine_ergebnisse").replacingOccurrences(of: "'%@'", with: "\"\(marketSearch.query)\""))
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.textSecondary)
                                        .multilineTextAlignment(.center)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            } else {
                                // Search results list
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(lm.t("portfolio.ergebnisse"))
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.textMuted)
                                        .tracking(1.1)
                                        .padding(.horizontal, 4)

                                    ForEach(marketSearch.results) { result in
                                        Button {
                                            haptic()
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                marketSearch.select(result)
                                                dismissSearch()
                                            }
                                        } label: {
                                            HStack(spacing: 12) {
                                                Text(result.kind.rawValue)
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(kindColor(result.kind))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(kindColor(result.kind).opacity(0.12))
                                                    .clipShape(Capsule())

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(result.symbol)
                                                        .font(.system(size: 14, weight: .bold))
                                                        .foregroundStyle(Color.textPrimary)
                                                    Text(result.name)
                                                        .font(.system(size: 12))
                                                        .foregroundStyle(Color.textSecondary)
                                                        .lineLimit(1)
                                                }
                                                Spacer()
                                                Image(systemName: "plus.circle")
                                                    .font(.system(size: 16))
                                                    .foregroundStyle(Color.jade.opacity(0.7))
                                            }
                                            .padding(12)
                                            .background(Color.white.opacity(0.04))
                                            .cornerRadius(12)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        } else {
                            // Form Mode
                            if let result = marketSearch.selectedResult {
                                selectedAssetCard(result)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                
                                Picker("Position Type", selection: $isWatchlist) {
                                    Text(lm.t("add.portfolio")).tag(false)
                                    Text(lm.t("add.watchlist")).tag(true)
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal, 4)
                               .onChange(of: isWatchlist) { _, newValue in
                                    if newValue {
                                        sharesText = "1.0"
                                        if let price = marketSearch.fetchedPrice {
                                            priceText = String(format: "%.2f", price)
                                        } else {
                                            priceText = "1.0"
                                        }
                                    } else {
                                        sharesText = ""
                                        priceText = ""
                                    }
                                }
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                
                                if !isWatchlist {
                                    sectionCard(title: lm.t("add.kauf_informationen")) {
                                        numberRow(label: lm.t("add.stueckzahl"), placeholder: "0.0000", text: $sharesText)
                                        Divider().background(Color.borderHair)
                                        priceRow
                                        Divider().background(Color.borderHair)
                                        DatePicker(lm.t("detail.kaufdatum"),
                                                   selection: $buyDate,
                                                   in: ...Date(),
                                                   displayedComponents: .date)
                                            .datePickerStyle(.compact)
                                            .tint(.jade)
                                            .foregroundStyle(Color.textPrimary)
                                    }
                                    .transition(.move(edge: .bottom).combined(with: .opacity))

                                    brokerIntegrationSection
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                                
                                if isValid && !isWatchlist {
                                    let shares = Double(sharesText.replacingOccurrences(of: ",", with: "."))!
                                    let price  = Double(priceText.replacingOccurrences(of: ",", with: "."))!
                                    summaryCard(shares: shares, price: price)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            } else {
                                // Initial empty placeholder instructions
                                VStack(spacing: 16) {
                                    Spacer(minLength: 40)
                                    ZStack {
                                        Circle()
                                            .fill(Color.jade.opacity(0.12))
                                            .frame(width: 80, height: 80)
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 32, weight: .bold))
                                            .foregroundStyle(Color.jade)
                                    }
                                    Text(lm.t("search.market"))
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(Color.textPrimary)
                                    Text(lm.t("add.aktien_etfs_krypto_suchen"))
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.textSecondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 60)
                            }
                        }

                        Spacer(minLength: 120)
                    }
                    .padding(.horizontal, AppLayout.contentHorizontalPadding)
                    .padding(.top, 16)
                    .animation(.spring(response: 0.38, dampingFraction: 0.75), value: isSymbolChosen)
                    .animation(.spring(response: 0.38, dampingFraction: 0.75), value: isValid)
                    .animation(.easeInOut(duration: 0.2), value: marketSearch.results.isEmpty)
                }

                // ── CTA ───────────────────────────────────────────────────
                VStack {
                    Spacer()
                    addButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                }
            }
            .navigationTitle(lm.t("add.uebernehmen").replacingOccurrences(of: "Position ", with: "").replacingOccurrences(of: " posición", with: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lm.t("add.abbrechen")) { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .searchable(
                text: $marketSearch.query,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: lm.t("search.market")
            )
            .searchScopes($marketSearch.selectedScope) {
                Text(lm.t("search.stocks")).tag(MarketScope.stocks)
                Text(lm.t("search.etfs")).tag(MarketScope.etfs)
                Text(lm.t("search.crypto")).tag(MarketScope.crypto)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: marketSearch.fetchedPrice) { _, newPrice in
            if isWatchlist, let price = newPrice {
                priceText = String(format: "%.2f", price)
            }
        }
        .onChange(of: marketSearch.query) { _, newValue in
            if marketSearch.selectedResult != nil {
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && trimmed != marketSearch.selectedResult?.symbol {
                    marketSearch.selectedResult = nil
                    marketSearch.fetchedPrice   = nil
                }
            }
        }
    }

    // MARK: - Selected Asset Card

    private func selectedAssetCard(_ result: MarketSearchResult) -> some View {
        HStack(spacing: 14) {
            // Icon
            let sfSymbolName: String? = {
                switch result.symbol.uppercased() {
                case "AAPL": return "apple.logo"
                case "BTC": return "bitcoinsign.circle.fill"
                default: return nil
                }
            }()
            
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(kindColor(result.kind).opacity(0.15))
                    .frame(width: 32, height: 32)
                if let sfSymbolName {
                    Image(systemName: sfSymbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(kindColor(result.kind))
                } else {
                    Text(String(result.symbol.prefix(2)))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(kindColor(result.kind))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(result.symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(result.kind.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(kindColor(result.kind))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(kindColor(result.kind).opacity(0.12))
                        .clipShape(Capsule())
                }
                Text(result.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Live price
            if marketSearch.isFetchingPrice {
                ProgressView().tint(.jade).scaleEffect(0.8)
            } else if let price = marketSearch.fetchedPrice {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(lm.t("einzel.live"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.jade)
                    Text(CurrencyService.shared.formatConverted(price))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                    if !isWatchlist {
                        Button(lm.t("add.uebernehmen")) {
                            priceText = String(format: "%.2f", price)
                            haptic()
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.jade)
                    }
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.jade.opacity(0.25), lineWidth: 0.8)
                )
        }
    }

    // MARK: - Price Row

    private var priceRow: some View {
        HStack {
            Text(lm.t("add.kaufpreis_eur"))
                .font(.system(size: 15))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            TextField("0.00", text: $priceText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.jade)
                .frame(maxWidth: 140)
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func sectionCard<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .textCase(.uppercase)
                .tracking(1.2)
            content()
        }
        .cardStyle()
    }

    @ViewBuilder
    private func numberRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.jade)
                .frame(maxWidth: 140)
        }
    }

    @ViewBuilder
    private func summaryCard(shares: Double, price: Double) -> some View {
        let total = shares * price
        VStack(alignment: .leading, spacing: 10) {
            Text(lm.t("add.zusammenfassung"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .textCase(.uppercase)
                .tracking(1.2)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lm.t("add.investitionssumme"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                    Text(CurrencyService.shared.formatConverted(total))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(lm.t("add.stueck_preis"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                    Text("\(String(format: "%.4g", shares)) × \(CurrencyService.shared.formatConverted(price).replacingOccurrences(of: "€", with: "").replacingOccurrences(of: "$", with: ""))")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .cardStyle()
    }

    private var brokerIntegrationSection: some View {
        sectionCard(title: "Broker Integration") {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showBrokerIntegration.toggle()
                }
                haptic()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.jade)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Align with broker")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Optional: If your broker currently shows a different price than market APIs, followtrend can align values more closely.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textMuted)
                        .rotationEffect(.degrees(showBrokerIntegration ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if showBrokerIntegration {
                Divider().background(Color.borderHair)

                Picker("Broker Platform", selection: $brokerPlatform) {
                    ForEach(brokerPlatforms, id: \.self) { platform in
                        Text(platform).tag(platform)
                    }
                }
                .pickerStyle(.menu)

                Divider().background(Color.borderHair)

                numberRow(label: "Current Broker Price", placeholder: "0.00", text: $brokerPriceText)

                Divider().background(Color.borderHair)

                Picker("Broker Currency", selection: $brokerCurrency) {
                    ForEach(AppCurrency.allCases) { currency in
                        Text(currency.rawValue).tag(currency)
                    }
                }
                .pickerStyle(.segmented)

                if let factor = brokerAdjustmentFactor {
                    HStack {
                        Text("Adjustment factor")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textMuted)
                        Spacer()
                        Text(String(format: "%.4f", factor))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.textSecondary)
                    }
                } else if parsedBrokerPrice > 0 {
                    Text("A current market API price is required before an adjustment factor can be saved.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
                }

                if shouldShowBrokerWarning {
                    brokerWarningView
                }
            }
        }
    }

    private var brokerWarningView: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "#f59e0b"))
            Text("The broker price differs significantly from market data. Please verify currency, exchange, or symbol.")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color(hex: "#f59e0b").opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - CTA Button

    private var addButton: some View {
        let glowColor = isValid ? (isWatchlist ? Color(hex: "#6366f1") : Color.jade) : Color(white: 0.3)
        return LiquidGlassButton(glowColor: glowColor) {
            guard isValid, let sym = selectedSymbol else {
                shakeTrigger.toggle()
                haptic(.rigid)
                return
            }
            let shares = Double(sharesText.replacingOccurrences(of: ",", with: ".")) ?? 1.0
            let price  = Double(priceText.replacingOccurrences(of: ",", with: ".")) ?? 1.0
            let fmt    = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            vm.addInvestment(
                symbol:   sym,
                shares:   shares,
                buyPrice: price,
                buyDate:  fmt.string(from: buyDate),
                name:     selectedName ?? sym,
                coinId:   selectedCoinId,
                isWatchlist: isWatchlist,
                brokerAdjustment: brokerAdjustmentDraft
            )
            haptic(.medium)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isWatchlist ? "eye.fill" : "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text(isWatchlist ? lm.t("add.zu_watchlist_hinzufuegen") : lm.t("add.uebernehmen"))
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(isValid ? Color.textPrimary : Color.textMuted)
        }
        .disabled(!isValid)
        .opacity(isValid ? 1 : 0.45)
        .modifier(ShakeModifier(trigger: shakeTrigger))
    }

    // MARK: - Helpers

    private func kindColor(_ kind: AssetKind) -> Color {
        switch kind {
        case .stock:  return .jade
        case .etf:    return Color(hex: "#5eead4")
        case .crypto: return Color(hex: "#2dd4bf")
        }
    }

}

// MARK: - Shake Modifier

struct ShakeModifier: ViewModifier {
    var trigger: Bool
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onChange(of: trigger) { _, _ in
                withAnimation(.spring(response: 0.1, dampingFraction: 0.2).repeatCount(4, autoreverses: true)) {
                    offset = 10
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation { offset = 0 }
                }
            }
    }
}
