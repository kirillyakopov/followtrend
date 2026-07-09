//
//  AddStockView.swift
//  followtrend
//
//  Add Asset sheet (README §3):
//  - Cancel-left nav row with centered title
//  - Embedded search field + SUGGESTED chips
//  - Opaque results list with monogram tiles
//  - Inset-grouped input form + broker alignment section
//  - Liquid Glass prominent (mint) primary save button
//

import SwiftUI

struct AddStockView: View {
    @ObservedObject var vm: PortfolioViewModel
    @EnvironmentObject private var lm: AppLanguageManager
    @ObservedObject private var cs = CurrencyService.shared

    @StateObject private var marketSearch = MarketSearchViewModel()

    @State private var sharesText   = ""
    @State private var priceText    = ""
    @State private var buyDate      = Date()
    @State private var shakeTrigger = false
    @State var isWatchlist: Bool
    @Environment(\.dismiss) private var dismiss
    // Broker integration
    @State private var showBrokerIntegration = false
    @State private var showImportSheet = false
    @State private var brokerPlatform = "Trade Republic"
    @State private var brokerPriceText = ""
    @State private var brokerCurrency: AppCurrency = .eur

    private var selectedSymbol: String? { marketSearch.selectedResult?.symbol }
    private var selectedName:   String? { marketSearch.selectedResult?.name }
    private var selectedKind:   AssetKind? { marketSearch.selectedResult?.kind }
    private var selectedCoinId: String? { marketSearch.selectedResult?.coinId }

    private var isSymbolChosen: Bool { marketSearch.selectedResult != nil }
    private let brokerPlatforms = ["Trade Republic", "Scalable", "IBKR", "Other", "Manual"]
    private let suggestedSymbols = ["NVDA", "VOO", "SOL", "DIS", "SCHD"]

    /// Search-field fill per spec: rgba(118,118,128,0.16)
    private let fieldFill = Color(red: 118/255, green: 118/255, blue: 128/255).opacity(0.16)

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
            displayCurrency: cs.selectedCurrency,
            currencyService: cs
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

    /// "≈ $4,320.10 at current price" — shares × live price, when computable.
    private var estimatedValueText: String? {
        guard let price = marketSearch.fetchedPrice else { return nil }
        let shares = Double(sharesText.replacingOccurrences(of: ",", with: ".")) ?? 0
        guard shares > 0 else { return nil }
        return cs.format(value: price * shares, from: selectedKind == .crypto ? "EUR" : "USD")
    }

    var body: some View {
        ZStack {
            Color.bgDeep.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                headerView
                    .padding(.bottom, 14)

                modePicker
                    .padding(.horizontal, AppLayout.contentHorizontalPadding)
                    .padding(.bottom, 10)

                // Bulk import — paste a whole portfolio instead of one-by-one entry
                Button {
                    haptic(.light)
                    showImportSheet = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                        Text(lm.t("import.entry_button"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.mintAccent)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .padding(.horizontal, AppLayout.contentHorizontalPadding)
                .padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 24) {
                        searchSection

                        if let result = marketSearch.selectedResult {
                            inputSection(for: result)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        Spacer(minLength: 120)
                    }
                    .padding(.horizontal, AppLayout.contentHorizontalPadding)
                }
            }

            VStack {
                Spacer()
                if isSymbolChosen {
                    addButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
        .onAppear {
            if isWatchlist {
                sharesText = "1.0"
            }
        }
        .sheet(isPresented: $showImportSheet) {
            PortfolioImportView(vm: vm, onImported: { dismiss() })
                .environmentObject(lm)
        }
    }

    // MARK: - Header (Cancel left · centered title)

    private var headerView: some View {
        ZStack {
            Text(isWatchlist ? lm.t("add.watchlist") : lm.t("portfolio.add_position_title"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 70)

            HStack {
                Button {
                    haptic(.light)
                    dismiss()
                } label: {
                    Text(lm.t("add.abbrechen"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.mintAccent)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.horizontal, AppLayout.contentHorizontalPadding)
        .padding(.top, 14)
    }

    // MARK: - Mode Picker (Portfolio / Watchlist)

    private var modePicker: some View {
        Picker("", selection: $isWatchlist.animation(.spring(response: 0.35, dampingFraction: 0.8))) {
            Text(lm.t("add.portfolio")).tag(false)
            Text(lm.t("add.watchlist")).tag(true)
        }
        .pickerStyle(.segmented)
        .onChange(of: isWatchlist) { _, watch in
            haptic(.light)
            if watch {
                if sharesText.isEmpty { sharesText = "1.0" }
                if let price = marketSearch.fetchedPrice {
                    priceText = String(format: "%.2f", price)
                }
            }
        }
    }

    // MARK: - Search Section

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            searchField

            if marketSearch.query.trimmingCharacters(in: .whitespaces).isEmpty
                && marketSearch.selectedResult == nil {
                suggestedChips
            }

            if marketSearch.isSearching {
                HStack {
                    Spacer()
                    ProgressView().tint(Color.mintAccent)
                    Spacer()
                }
                .padding(.top, 20)
            } else if !marketSearch.query.isEmpty && marketSearch.selectedResult == nil {
                if marketSearch.results.isEmpty {
                    HStack {
                        Spacer()
                        Text(lm.t("search.noResults"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.labelTertiary)
                        Spacer()
                    }
                    .padding(.top, 20)
                } else {
                    resultsList
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))

            TextField(lm.t("add.aktien_etfs_krypto_suchen"), text: $marketSearch.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Color.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !marketSearch.query.isEmpty {
                Button {
                    haptic(.light)
                    marketSearch.query = ""
                    marketSearch.selectedResult = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(fieldFill)
        )
    }

    // MARK: - Suggested chips (query empty)

    private var suggestedChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineLabel(lm.t("add.suggested"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestedSymbols, id: \.self) { symbol in
                        Button {
                            haptic(.light)
                            marketSearch.query = symbol
                        } label: {
                            Text(symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Results list (opaque container, hairline separators)

    private var resultsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(marketSearch.results.enumerated()), id: \.element.id) { index, result in
                searchRow(for: result)
                if index < marketSearch.results.count - 1 {
                    Rectangle()
                        .fill(Color.separatorHair)
                        .frame(height: 0.5)
                        .padding(.leading, 62)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func searchRow(for result: MarketSearchResult) -> some View {
        Button {
            haptic(.medium)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                marketSearch.select(result)
            }
        } label: {
            HStack(spacing: 12) {
                MonogramTile(symbol: result.symbol, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(result.symbol)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        if isOwned(result.symbol) {
                            Text(lm.t("add.owned"))
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.6)
                                .foregroundStyle(Color.mintAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Capsule().fill(Color.mintAccent.opacity(0.16)))
                        }
                    }
                    Text(result.name)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // 24h change data is not available on search results; show price
                // when known, otherwise a quiet add affordance.
                if let price = result.livePrice {
                    Text(cs.formatConverted(price))
                        .font(.system(size: 14.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                } else {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.mintAccent.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func isOwned(_ symbol: String) -> Bool {
        vm.investments.contains { !$0.isWatchlist && $0.symbol.uppercased() == symbol.uppercased() }
    }

    // MARK: - Input Section

    @ViewBuilder
    private func inputSection(for result: MarketSearchResult) -> some View {
        VStack(spacing: 20) {
            selectedAssetCard(result)

            if !isWatchlist {
                VStack(alignment: .leading, spacing: 0) {
                    quantityPriceCard

                    if let est = estimatedValueText {
                        Text(String(format: lm.t("add.approx_at_current_price"), est))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(Color.labelSecondary)
                            .padding(.top, 8)
                            .padding(.horizontal, 4)
                    }

                    brokerIntegrationSection
                        .padding(.top, 16)
                }
            }
        }
    }

    private func selectedAssetCard(_ result: MarketSearchResult) -> some View {
        HStack(spacing: 12) {
            MonogramTile(symbol: result.symbol, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text(result.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if marketSearch.isFetchingPrice {
                ProgressView().tint(Color.mintAccent).scaleEffect(0.8)
            } else if let price = marketSearch.fetchedPrice {
                VStack(alignment: .trailing, spacing: 2) {
                    OverlineLabel(lm.t("einzel.live"), color: .mintAccent)
                    Text(cs.formatConverted(price))
                        .font(.system(size: 14.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                    if !isWatchlist {
                        Button {
                            priceText = String(format: "%.2f", price)
                            haptic()
                        } label: {
                            Text(lm.t("add.uebernehmen"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.mintAccent)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.mini)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Inset-grouped Shares / Avg price fields

    private var quantityPriceCard: some View {
        VStack(spacing: 0) {
            fieldRow(label: lm.t("add.stueckzahl"), placeholder: "0.000", text: $sharesText)

            Rectangle()
                .fill(Color.separatorHair)
                .frame(height: 0.5)
                .padding(.leading, 16)

            fieldRow(label: lm.t("detail.kaufpreis"), placeholder: "0.00", text: $priceText)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func fieldRow(label: String, placeholder: String, text: Binding<String>) -> some View {
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Broker Integration

    private var brokerIntegrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showBrokerIntegration.toggle()
                }
                haptic()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mintAccent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Align with broker")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Optional: If your broker currently shows a different price than market APIs, followtrend can align values more closely.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.labelTertiary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.labelTertiary)
                        .rotationEffect(.degrees(showBrokerIntegration ? 90 : 0))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle(radius: 16))

            if showBrokerIntegration {
                VStack(spacing: 0) {
                    Picker("Broker Platform", selection: $brokerPlatform) {
                        ForEach(brokerPlatforms, id: \.self) { platform in
                            Text(platform).tag(platform)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.mintAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Rectangle()
                        .fill(Color.separatorHair)
                        .frame(height: 0.5)
                        .padding(.leading, 16)

                    HStack {
                        Text("Current Broker Price")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.labelSecondary)
                        Spacer()
                        TextField("0.00", text: $brokerPriceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 16, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.mintAccent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)

                    Rectangle()
                        .fill(Color.separatorHair)
                        .frame(height: 0.5)
                        .padding(.leading, 16)

                    Picker("Broker Currency", selection: $brokerCurrency) {
                        ForEach(AppCurrency.allCases) { currency in
                            Text(currency.rawValue).tag(currency)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(16)
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )

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
                .foregroundStyle(Color.lossText)
            Text("The broker price differs significantly from market data. Please verify currency, exchange, or symbol.")
                .font(.system(size: 12))
                .foregroundStyle(Color.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.lossBase.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.lossBase.opacity(0.16), lineWidth: 0.5)
        )
    }

    // MARK: - CTA Button

    private var addButton: some View {
        Button {
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
            hapticSuccess()

            // Reset state instead of dismiss, since it's a tab now
            dismiss()
            sharesText = ""
            priceText = ""
            // Optionally, we could switch tab back to portfolio via vm or binding
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isWatchlist ? "eye.fill" : "plus.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text(isWatchlist ? lm.t("add.zu_watchlist_hinzufuegen") : lm.t("add.uebernehmen"))
                    .font(.system(size: 16, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Color.mintInk)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.mintAccent)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .disabled(!isValid)
        .modifier(ShakeModifier(trigger: shakeTrigger))
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
