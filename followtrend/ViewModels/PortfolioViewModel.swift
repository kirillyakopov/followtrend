//
//  PortfolioViewModel.swift
//  followtrend
//

import SwiftUI
import Combine
import WidgetKit

// MARK: - PortfolioViewModel

@MainActor
final class PortfolioViewModel: ObservableObject {

    // MARK: Published state

    @Published var investments:      [Investment] = []
    @Published var cashBalance:      Double = 0.00
    @Published var isPriceFetching:  Bool = false

    @Published var totalValue:       Double = 0
    @Published var totalCost:        Double = 0
    @Published var absoluteGain:     Double = 0
    @Published var percentageGain:   Double = 0
    @Published var priceSourceMode:  PriceSourceMode = .market

    /// Pairwise Pearson correlation coefficients — updated after every price refresh.
    @Published var correlationMatrix: [AssetPair: Double] = [:]
    
    @Published var portfolioCorrelation: Double? = nil
    @Published var correlationState: CorrelationState = .loading
    @Published private(set) var assetAllocation: [AssetAllocationSlice] = []
    @Published private(set) var rebalancingSuggestions: [RebalancingSuggestion] = []
    @Published private(set) var volatilityBySymbol: [String: Double] = [:]

    enum CorrelationState: Equatable {
        case loading
        case success(Double)
        case insufficientData
        case error
    }

    /// LIFO stack of recently popped / deleted investments available for undo.
    @Published private(set) var poppedBubbles: [Investment] = []

    /// True when there is at least one popped bubble available to restore.
    var canUnpop: Bool { !poppedBubbles.isEmpty }

    @Published var bubbleClusters: [BubbleCluster] = []
    @Published var mergeSuggestions: [MergeSuggestion] = []
    @Published var bubbleRenderSnapshot = BubbleRenderSnapshot()
    @Published var expandedClusterID: UUID? = nil
    
    // Multi-Select Mode state
    @Published var isBubbleSelectionModeActive: Bool = false
    @Published var selectedBubbleSymbols: Set<String> = []
    
    private var lastCanvasSize: CGSize = .zero

    // MARK: Dependencies

    let marketService = StockMarketService.shared
    private let cryptoService = CryptoDataService.shared
    private var cancellables   = Set<AnyCancellable>()
    private var priceRefreshTimer: AnyCancellable?
    private let priceSourceModeKey = "portfolio.priceSourceMode"
    private let priceSourceModeUserSelectedKey = "portfolio.priceSourceMode.userSelected"

    // MARK: Init

    init() {
        loadDefaultInvestments()
        loadPriceSourceMode()

        // Re-calculate whenever market prices update
        marketService.$liveStocks
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recalculate() }
            .store(in: &cancellables)
            
        // Re-calculate whenever selected currency changes
        CurrencyService.shared.$selectedCurrency
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recalculate() }
            .store(in: &cancellables)

        // First live price fetch
        Task { await refreshLivePrices() }

        // Auto-refresh every 30 seconds
        priceRefreshTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshLivePrices() }
            }
    }

    // MARK: Default portfolio

    private func loadDefaultInvestments() {
        // Fetch saved investments from SwiftData
        var fetched = PortfolioStorageService.shared.fetchInvestments()
        if fetched.isEmpty {
            fetched = [
                Investment(symbol: "AAPL", name: "Apple Inc.", shares: 12.0, buyPrice: 175.0, buyDate: "2024-01-15", nativeCurrency: "USD", isWatchlist: false),
                Investment(symbol: "BTC", name: "Bitcoin", shares: 0.45, buyPrice: 43200.0, buyDate: "2024-02-10", coinId: "bitcoin", nativeCurrency: "USD", isWatchlist: false),
                Investment(symbol: "TSLA", name: "Tesla Inc.", shares: 1.0, buyPrice: 185.0, buyDate: "2024-05-01", nativeCurrency: "USD", isWatchlist: true),
                Investment(symbol: "NVDA", name: "NVIDIA Corp.", shares: 1.0, buyPrice: 850.0, buyDate: "2024-05-05", nativeCurrency: "USD", isWatchlist: true)
            ]
            PortfolioStorageService.shared.saveInvestments(fetched)
        } else if !fetched.contains(where: { $0.isWatchlist }) {
            let defaultWatchlist = [
                Investment(symbol: "TSLA", name: "Tesla Inc.", shares: 1.0, buyPrice: 185.0, buyDate: "2024-05-01", nativeCurrency: "USD", isWatchlist: true),
                Investment(symbol: "NVDA", name: "NVIDIA Corp.", shares: 1.0, buyPrice: 850.0, buyDate: "2024-05-05", nativeCurrency: "USD", isWatchlist: true)
            ]
            fetched.append(contentsOf: defaultWatchlist)
            PortfolioStorageService.shared.saveInvestments(fetched)
        }
        investments = fetched
        loadBubbleClusters()
        recalculate()
    }

    private func loadPriceSourceMode() {
        if let stored = UserDefaults.standard.string(forKey: priceSourceModeKey),
           let mode = PriceSourceMode(rawValue: stored) {
            priceSourceMode = mode
        } else {
            priceSourceMode = investments.contains(where: { $0.hasBrokerAdjustment }) ? .brokerAdjusted : .market
        }
    }

    func setPriceSourceMode(_ mode: PriceSourceMode) {
        priceSourceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: priceSourceModeKey)
        UserDefaults.standard.set(true, forKey: priceSourceModeUserSelectedKey)
        recalculate()
    }

    private func refreshDefaultPriceSourceModeIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: priceSourceModeUserSelectedKey) else { return }
        let defaultMode: PriceSourceMode = investments.contains(where: { $0.hasBrokerAdjustment }) ? .brokerAdjusted : .market
        if priceSourceMode != defaultMode {
            priceSourceMode = defaultMode
        }
    }

    func currentApiPrice(for inv: Investment) -> Double {
        marketService.getCurrentPrice(for: inv.symbol)
    }

    func displayPrice(for inv: Investment) -> Double {
        inv.displayPrice(apiPrice: currentApiPrice(for: inv), mode: priceSourceMode)
    }

    func selectedCurrencyValue(for inv: Investment) -> Double {
        let nativeValue = inv.shares * displayPrice(for: inv)
        return CurrencyService.shared.convertToSelected(value: nativeValue, from: inv.nativeCurrency)
    }

    func selectedCurrencyCost(for inv: Investment) -> Double {
        CurrencyService.shared.convertToSelected(value: inv.totalCost, from: inv.nativeCurrency)
    }

    private func applyBrokerAdjustment(_ draft: BrokerAdjustmentDraft?, to inv: inout Investment) {
        guard let draft else {
            inv.currentApiPriceAtEntry = nil
            inv.currentBrokerPriceAtEntry = nil
            inv.priceAdjustmentFactor = nil
            inv.brokerName = nil
            inv.apiBaseCurrency = nil
            inv.brokerCurrency = nil
            inv.displayCurrency = nil
            inv.fxRateAtCreation = nil
            return
        }

        let apiCurrency = AppCurrency(rawValue: inv.nativeCurrency.uppercased()) ?? .usd
        let displayCurrency = CurrencyService.shared.selectedCurrency
        inv.currentApiPriceAtEntry = draft.currentApiPrice
        inv.currentBrokerPriceAtEntry = draft.currentBrokerPrice
        inv.priceAdjustmentFactor = Investment.adjustmentFactor(
            apiPrice: draft.currentApiPrice,
            apiCurrency: apiCurrency,
            brokerPrice: draft.currentBrokerPrice,
            brokerCurrency: draft.brokerCurrency,
            displayCurrency: displayCurrency
        )
        inv.brokerName = draft.brokerName
        inv.apiBaseCurrency = apiCurrency.rawValue
        inv.brokerCurrency = draft.brokerCurrency.rawValue
        inv.displayCurrency = displayCurrency.rawValue
        inv.fxRateAtCreation = Investment.fxRate(from: draft.brokerCurrency, to: displayCurrency)
    }

    // MARK: Live price refresh (Finnhub quotes + CoinGecko)

    func refreshLivePrices() async {
        isPriceFetching = true
        await withTaskGroup(of: Void.self) { group in
            for inv in investments {
                let sym    = inv.symbol
                let coinId = inv.coinId
                group.addTask { [weak self] in
                    guard let self else { return }
                    do {
                        let price: Double
                        if let cid = coinId {
                            price = try await self.cryptoService.currentPrice(coinId: cid)
                        } else {
                            price = try await MarketDataService.shared.fetchQuote(symbol: sym)
                        }
                        await MainActor.run {
                            self.marketService.updatePrice(symbol: sym, price: price)
                        }
                    } catch {
                        // Silently retain mock price
                    }
                }
            }
        }
        recalculate()
        isPriceFetching = false

        // Kick off correlation computation in background (does not block UI)
        Task { await triggerCorrelationUpdate() }
    }

    // MARK: Correlation matrix

    func triggerCorrelationUpdate() async {
        await MainActor.run { self.correlationState = .loading }
        let snapshot = investments.filter {
            !$0.isWatchlist && !StablecoinClassifier.isStablecoin(symbol: $0.symbol, name: $0.name)
        }  // value-type copy — safe to use off main actor
        let cash = cashBalance
        
        async let matrixTask = RiskAnalyticsService.shared.computeCorrelations(for: snapshot)
        async let volatilityTask = RiskAnalyticsService.shared.computeVolatility(for: snapshot)
        async let portfolioCorrTask = CorrelationService.shared.computePortfolioCorrelation(
            for: snapshot,
            cashBalance: cash
        )
        
        let matrix = await matrixTask
        let volatility = await volatilityTask
        let portfolioCorr = await portfolioCorrTask
        
        await MainActor.run {
            self.correlationMatrix = matrix
            self.volatilityBySymbol = volatility
            if let corr = portfolioCorr {
                self.portfolioCorrelation = corr
                self.correlationState = .success(corr)
            } else {
                self.portfolioCorrelation = nil
                self.correlationState = .insufficientData
            }
            self.refreshCachedPortfolioAnalytics()
            self.recalculateSuggestions()
        }
    }

    // MARK: Performance calculation

    func recalculate() {
        var value = cashBalance
        var cost  = costBalanceHelper() // wait, let's look at the original code

        let cs = CurrencyService.shared

        for inv in investments {
            guard !inv.isWatchlist else { continue }
            let price = displayPrice(for: inv)
            let convertedPrice = cs.convertToSelected(value: price, from: inv.nativeCurrency)
            value += inv.shares * convertedPrice
            
            let convertedCost = cs.convertToSelected(value: inv.totalCost, from: inv.nativeCurrency)
            cost += convertedCost
        }

        totalValue      = value
        totalCost       = cost - cashBalance
        let holdingsVal  = value - cashBalance
        let holdingsCost = cost - cashBalance
        absoluteGain    = holdingsVal - holdingsCost
        percentageGain  = holdingsCost > 0 ? (absoluteGain / holdingsCost) * 100 : 0
        refreshCachedPortfolioAnalytics()
        
        syncToWidget()
        
        validateClusters()
        recalculateSuggestions()
        rebuildBubbleSnapshot()
    }

    private func refreshCachedPortfolioAnalytics() {
        let active = investments.filter { !$0.isWatchlist }
        let cs = CurrencyService.shared

        let valuesByID: [String: Double] = Dictionary(uniqueKeysWithValues: active.map { inv in
            let price = displayPrice(for: inv)
            let convertedPrice = cs.convertToSelected(value: price, from: inv.nativeCurrency)
            return (inv.id, inv.shares * convertedPrice)
        })

        let holdingsValue = valuesByID.values.reduce(0, +)
        guard holdingsValue > 0 else {
            assetAllocation = []
            rebalancingSuggestions = []
            return
        }

        assetAllocation = AssetCategory.allCases.compactMap { category in
            let assets = active.filter { AssetClassifier.category(for: $0) == category }
            let value = assets.reduce(0.0) { partial, inv in
                partial + (valuesByID[inv.id] ?? 0)
            }
            guard value > 0 else { return nil }
            return AssetAllocationSlice(
                category: category,
                value: value,
                percentage: value / holdingsValue * 100,
                assets: assets
            )
        }
        .sorted { $0.value > $1.value }

        var suggestions: [RebalancingSuggestion] = []

        let rebalancingUniverse = active.filter {
            !StablecoinClassifier.isStablecoin(symbol: $0.symbol, name: $0.name)
        }

        for inv in rebalancingUniverse {
            let value = valuesByID[inv.id] ?? 0
            let weight = value / holdingsValue * 100
            if weight > 35 {
                suggestions.append(
                    RebalancingSuggestion(
                        localizationKey: "rebalancing.positionConcentration",
                        arguments: [inv.symbol, String(format: "%.0f", weight)],
                        severity: weight > 50 ? .critical : .warning,
                        icon: "chart.pie.fill"
                    )
                )
            }
        }

        let technologyValue = rebalancingUniverse
            .filter { AssetClassifier.isTechnology($0) }
            .reduce(0.0) { partial, inv in partial + (valuesByID[inv.id] ?? 0) }
        let technologyWeight = technologyValue / holdingsValue * 100
        if technologyWeight > 65 {
            suggestions.append(
                RebalancingSuggestion(
                    localizationKey: "rebalancing.technologyConcentration",
                    arguments: [String(format: "%.0f", technologyWeight)],
                    severity: technologyWeight > 80 ? .critical : .warning,
                    icon: "cpu.fill"
                )
            )
        }

        for slice in assetAllocation where slice.category != .stablecoins && slice.percentage > 70 {
            suggestions.append(
                RebalancingSuggestion(
                    localizationKey: "rebalancing.assetClassImbalance.\(slice.category.rawValue)",
                    arguments: [String(format: "%.0f", slice.percentage)],
                    severity: slice.percentage > 85 ? .critical : .warning,
                    icon: slice.category == .crypto ? "bitcoinsign.circle.fill" : "square.grid.2x2.fill"
                )
            )
        }

        let strongPairs = correlationMatrix
            .filter { $0.value >= 0.75 }
            .sorted { $0.value > $1.value }
            .prefix(2)

        for pair in strongPairs {
            suggestions.append(
                RebalancingSuggestion(
                    localizationKey: "rebalancing.highCorrelation",
                    arguments: [pair.key.symbolA, pair.key.symbolB],
                    severity: pair.value > 0.9 ? .critical : .warning,
                    icon: "link.circle.fill"
                )
            )
        }

        if suggestions.isEmpty && rebalancingUniverse.count >= 2 {
            suggestions.append(
                RebalancingSuggestion(
                    localizationKey: "rebalancing.noMajorIssues",
                    arguments: [],
                    severity: .info,
                    icon: "checkmark.seal.fill"
                )
            )
        }

        rebalancingSuggestions = suggestions.sorted { $0.severity > $1.severity }
    }

    private func costBalanceHelper() -> Double {
        return cashBalance
    }

    private func syncToWidget() {
        let watchlisted = investments.filter { $0.isWatchlist }
        let watchlistItems: [WidgetWatchlistItem] = watchlisted.map { inv in
            let price = marketService.getCurrentPrice(for: inv.symbol)
            let info = marketService.getStockInfo(for: inv.symbol)
            let changePercent = info?.dayChangePercent ?? 0.0
            return WidgetWatchlistItem(
                symbol: inv.symbol,
                name: inv.name,
                price: price,
                changePercent: changePercent
            )
        }
        
        let currencySymbol = CurrencyService.shared.selectedCurrency.rawValue
        
        PortfolioStore.shared.writeData(
            totalValue: totalValue,
            percentageGain: percentageGain,
            currency: currencySymbol,
            watchlist: watchlistItems
        )
        
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Add investment (weighted-average merging)

    func addInvestment(
        symbol:   String,
        shares:   Double,
        buyPrice: Double,
        buyDate:  String,
        name:     String? = nil,
        coinId:   String? = nil,
        nativeCurrency: String = "USD",
        isWatchlist: Bool = false,
        brokerAdjustment: BrokerAdjustmentDraft? = nil
    ) {
        let sym = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sym.isEmpty, shares > 0, buyPrice > 0 else { return }

        let assetName = name ?? marketService.getStockInfo(for: sym)?.name ?? sym

        if let idx = investments.firstIndex(where: { $0.symbol == sym && $0.isWatchlist == isWatchlist }) {
            let existing      = investments[idx]
            if isWatchlist {
                investments[idx].buyPrice = buyPrice
            } else {
                let totalShares   = existing.shares + shares
                let weightedPrice = (existing.shares * existing.buyPrice + shares * buyPrice) / totalShares
                investments[idx].shares   = totalShares
                investments[idx].buyPrice = weightedPrice
                if brokerAdjustment != nil {
                    applyBrokerAdjustment(brokerAdjustment, to: &investments[idx])
                }
            }
        } else {
            var inv = Investment(
                symbol:   sym,
                name:     assetName,
                shares:   shares,
                buyPrice: buyPrice,
                buyDate:  buyDate,
                coinId:   coinId,
                nativeCurrency: nativeCurrency,
                isWatchlist: isWatchlist
            )
            if !isWatchlist {
                applyBrokerAdjustment(brokerAdjustment, to: &inv)
            }
            withAnimation(.easeInOut(duration: 0.35)) {
                investments.append(inv)
            }
        }

        // Register with StockMarketService at buy price (will be overwritten on next price refresh)
        marketService.registerSymbol(symbol: sym, name: assetName, price: buyPrice)
        refreshDefaultPriceSourceModeIfNeeded()
        recalculate()

        // Fetch live price for new position immediately
        Task {
            do {
                let price: Double
                if let cid = coinId {
                    price = try await cryptoService.currentPrice(coinId: cid)
                } else {
                    price = try await MarketDataService.shared.fetchQuote(symbol: sym)
                }
                if price > 0 {
                    marketService.updatePrice(symbol: sym, price: price)
                    recalculate()
                }
            } catch {}
        }
        
        // Auto-save
        PortfolioStorageService.shared.saveInvestments(investments)
        Task { await triggerCorrelationUpdate() }
    }

    // MARK: Convert watchlist item to active portfolio position

    func buyWatchlistItem(id: String, shares: Double, price: Double, date: String) {
        guard let watchListIdx = investments.firstIndex(where: { $0.id == id }) else { return }
        let item = investments[watchListIdx]
        
        if let existingIdx = investments.firstIndex(where: { $0.symbol == item.symbol && !$0.isWatchlist }) {
            withAnimation(.easeInOut(duration: 0.35)) {
                let existing = investments[existingIdx]
                let totalShares = existing.shares + shares
                let weightedPrice = (existing.shares * existing.buyPrice + shares * price) / totalShares
                investments[existingIdx].shares = totalShares
                investments[existingIdx].buyPrice = weightedPrice
                investments.remove(at: watchListIdx)
            }
        } else {
            withAnimation(.easeInOut(duration: 0.35)) {
                investments[watchListIdx].shares = shares
                investments[watchListIdx].buyPrice = price
                investments[watchListIdx].buyDate = date
                investments[watchListIdx].isWatchlist = false
            }
        }
        
        refreshDefaultPriceSourceModeIfNeeded()
        recalculate()
        
        // Auto-save
        PortfolioStorageService.shared.saveInvestments(investments)
        Task { await triggerCorrelationUpdate() }
    }

    // MARK: Delete investment

    func deleteInvestment(id: String, preserveForRestore: Bool = true) {
        // Bubble pops are restorable; ordinary list removals are not.
        if let removed = investments.first(where: { $0.id == id }) {
            if preserveForRestore {
                poppedBubbles.append(removed)
                if poppedBubbles.count > 10 { poppedBubbles.removeFirst() }
            }
            PriceAlertStore.shared.removeAlerts(for: removed.id)
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            investments.removeAll(where: { $0.id == id })
        }
        recalculate()

        // Auto-save
        PortfolioStorageService.shared.saveInvestments(investments)
        Task { await triggerCorrelationUpdate() }
    }

    func removeInvestment(id: String) {
        deleteInvestment(id: id, preserveForRestore: false)
    }

    // MARK: Restore Bubble (undo last pop)

    func unpopBubble() {
        guard var restored = poppedBubbles.popLast() else { return }

        // Guard against duplicate: if the symbol already exists in the active portfolio, skip
        let alreadyActive = investments.contains {
            $0.symbol == restored.symbol && $0.isWatchlist == restored.isWatchlist
        }
        guard !alreadyActive else { return }

        // Assign a fresh ID to avoid SwiftData uniqueness conflicts
        restored.id = UUID().uuidString

        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
            investments.append(restored)
        }

        // Re-register the symbol at the last known buy price
        marketService.registerSymbol(
            symbol: restored.symbol,
            name:   restored.name,
            price:  restored.buyPrice
        )
        haptic(.rigid)
        recalculate()
        PortfolioStorageService.shared.saveInvestments(investments)
        Task { await triggerCorrelationUpdate() }

        // Fetch a live price immediately
        let sym    = restored.symbol
        let coinId = restored.coinId
        Task {
            do {
                let price: Double
                if let cid = coinId {
                    price = try await cryptoService.currentPrice(coinId: cid)
                } else {
                    price = try await MarketDataService.shared.fetchQuote(symbol: sym)
                }
                if price > 0 {
                    marketService.updatePrice(symbol: sym, price: price)
                    recalculate()
                }
            } catch {}
        }
    }

    // MARK: - Update Investment

    func updateInvestment(
        id: String,
        shares: Double,
        buyPrice: Double,
        buyDate: String,
        notes: String = "",
        tags: String = "",
        brokerAdjustment: BrokerAdjustmentDraft? = nil,
        clearsBrokerAdjustment: Bool = false
    ) {
        guard let idx = investments.firstIndex(where: { $0.id == id }) else { return }
        
        withAnimation(.easeInOut(duration: 0.35)) {
            investments[idx].shares = shares
            investments[idx].buyPrice = buyPrice
            investments[idx].buyDate = buyDate
            investments[idx].notes = notes
            investments[idx].tags = tags
            if clearsBrokerAdjustment || brokerAdjustment != nil {
                applyBrokerAdjustment(brokerAdjustment, to: &investments[idx])
            }
        }
        
        recalculate()
        
        // Auto-save
        PortfolioStorageService.shared.saveInvestments(investments)
        
        Task { await triggerCorrelationUpdate() }
    }

    // MARK: - Aggregate Portfolio Chart
    
    func fetchPortfolioCandles(timeframe: Timeframe) async throws -> [ChartPoint] {
        let activeInvestments = investments.filter { !$0.isWatchlist }
        guard !activeInvestments.isEmpty else { return [] }
        
        var chartDataDict = [String: [ChartPoint]]()
        
        try await withThrowingTaskGroup(of: (String, [ChartPoint]).self) { group in
            for inv in activeInvestments {
                group.addTask {
                    let points: [ChartPoint]
                    if let cid = inv.coinId {
                        points = try await CryptoDataService.shared.fetchCandles(coinId: cid, timeframe: timeframe)
                    } else {
                        points = try await MarketDataService.shared.fetchCandles(symbol: inv.symbol, timeframe: timeframe)
                    }
                    return (inv.id, points)
                }
            }
            
            for try await (id, points) in group {
                chartDataDict[id] = points
            }
        }
        
        guard let referencePoints = chartDataDict.values.max(by: { $0.count < $1.count }) else {
            return []
        }
        
        var aggregatedPoints: [ChartPoint] = []
        
        for refPoint in referencePoints {
            let refDate = refPoint.timestamp
            var totalValue: Double = 0
            
            for inv in activeInvestments {
                guard let assetPoints = chartDataDict[inv.id] else { continue }
                
                if let closestPoint = assetPoints.last(where: { $0.timestamp <= refDate }) {
                    totalValue += inv.positionValue(apiPrice: closestPoint.close, mode: priceSourceMode)
                } else if let firstPoint = assetPoints.first {
                    totalValue += inv.positionValue(apiPrice: firstPoint.close, mode: priceSourceMode)
                }
            }
            
            let pointValue = totalValue + cashBalance
            
            aggregatedPoints.append(ChartPoint(
                timestamp: refDate,
                close: pointValue,
                open: pointValue,
                high: pointValue,
                low: pointValue
            ))
        }
        
        return aggregatedPoints
    }

    // MARK: Bubble particles

    func bubbleParticles(in size: CGSize) -> [BubbleParticle] {
        let activeInvestments = investments.filter { !$0.isWatchlist }
        let totalVal = activeInvestments.reduce(0.0) {
            $0 + selectedCurrencyValue(for: $1)
        }

        let maxR: CGFloat = min(size.width, size.height) * 0.22
        let minR: CGFloat = 28

        var particlesList: [BubbleParticle] = []
        var processedSymbols = Set<String>()

        // 1. Process collapsed clusters
        for cluster in bubbleClusters where !cluster.isExpanded {
            let clusterInvestments = investments.filter { !$0.isWatchlist && cluster.symbols.contains($0.symbol) }
            guard !clusterInvestments.isEmpty else { continue }

            let combinedValue = clusterInvestments.reduce(0.0) {
                $0 + selectedCurrencyValue(for: $1)
            }
            let combinedCost = clusterInvestments.reduce(0.0) {
                $0 + selectedCurrencyCost(for: $1)
            }

            let gain: Double
            if combinedCost > 0 {
                gain = ((combinedValue - combinedCost) / combinedCost) * 100
            } else {
                gain = 0.0
            }

            let weight = totalVal > 0 ? (combinedValue / totalVal) : 0.0
            let r = minR + (maxR - minR) * CGFloat(weight)

            let formattedValue = CurrencyService.shared.formatConverted(combinedValue)
            let template = AppLanguageManager.shared.t("bubbles.assetsCount")
            let assetsCountText = template.replacingOccurrences(of: "{count}", with: "\(cluster.symbols.count)")

            let particle = BubbleParticle(
                id: cluster.id.uuidString,
                symbol: cluster.name,
                gain: gain,
                radius: r,
                position: CGPoint(
                    x: CGFloat.random(in: r...(size.width - r)),
                    y: CGFloat.random(in: r...(size.height - r))
                ),
                velocity: CGVector(
                    dx: CGFloat.random(in: -0.3...0.3),
                    dy: CGFloat.random(in: -0.3...0.3)
                ),
                isWatchlist: false,
                isCluster: true,
                clusterSymbols: cluster.symbols,
                combinedValueText: formattedValue,
                assetsCountText: assetsCountText
            )

            particlesList.append(particle)
            for sym in cluster.symbols {
                processedSymbols.insert(sym)
            }
        }

        // 2. Process remaining investments
        for inv in investments {
            if inv.isWatchlist {
                let r = 38.0
                let gain = marketService.getStockInfo(for: inv.symbol)?.dayChangePercent ?? 0.0

                let particle = BubbleParticle(
                    id: inv.id,
                    symbol: inv.symbol,
                    gain: gain,
                    radius: r,
                    position: CGPoint(
                        x: CGFloat.random(in: r...(size.width - r)),
                        y: CGFloat.random(in: r...(size.height - r))
                    ),
                    velocity: CGVector(
                        dx: CGFloat.random(in: -0.3...0.3),
                        dy: CGFloat.random(in: -0.3...0.3)
                    ),
                    isWatchlist: true
                )
                particlesList.append(particle)
            } else {
                guard !processedSymbols.contains(inv.symbol) else { continue }

                let val = selectedCurrencyValue(for: inv)
                let weight = totalVal > 0 ? (val / totalVal) : 0.0
                let r = minR + (maxR - minR) * CGFloat(weight)
                let gain = inv.totalCost > 0 ? ((val - inv.totalCost) / inv.totalCost) * 100 : 0.0

                let particle = BubbleParticle(
                    id: inv.id,
                    symbol: inv.symbol,
                    gain: gain,
                    radius: r,
                    position: CGPoint(
                        x: CGFloat.random(in: r...(size.width - r)),
                        y: CGFloat.random(in: r...(size.height - r))
                    ),
                    velocity: CGVector(
                        dx: CGFloat.random(in: -0.3...0.3),
                        dy: CGFloat.random(in: -0.3...0.3)
                    ),
                    isWatchlist: false
                )
                particlesList.append(particle)
            }
        }

        return particlesList
    }

    // MARK: - Bubble Merge Operations

    func mergeCluster(symbols: [String], name: String, type: BubbleClusterType) {
        var pairCorrelations: [Double] = []
        for i in 0..<symbols.count {
            for j in (i+1)..<symbols.count {
                let pair = AssetPair(symbols[i], symbols[j])
                if let corr = correlationMatrix[pair] {
                    pairCorrelations.append(corr)
                }
            }
        }
        let avgCorr = pairCorrelations.isEmpty ? nil : pairCorrelations.reduce(0, +) / Double(pairCorrelations.count)

        let activeInvestments = investments.filter { !$0.isWatchlist }
        let totalVal = activeInvestments.reduce(0.0) {
            $0 + selectedCurrencyValue(for: $1)
        }
        let clusterInvestments = investments.filter { !$0.isWatchlist && symbols.contains($0.symbol) }
        let combinedValue = clusterInvestments.reduce(0.0) {
            $0 + selectedCurrencyValue(for: $1)
        }
        let combinedWeight = totalVal > 0 ? (combinedValue / totalVal) : 0.0

        let newCluster = BubbleCluster(
            id: UUID(),
            name: name,
            symbols: symbols.sorted(),
            averageCorrelation: avgCorr,
            combinedWeight: combinedWeight,
            type: type,
            isExpanded: false
        )

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            var updated = bubbleClusters
            updated.append(newCluster)
            bubbleClusters = updated
        }

        saveBubbleClusters()
        recalculateSuggestions()
        rebuildBubbleSnapshot()
    }

    func expandCluster(id: UUID) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            var updated = bubbleClusters
            if let idx = updated.firstIndex(where: { $0.id == id }) {
                updated.remove(at: idx)
                bubbleClusters = updated
            }
        }
        if expandedClusterID == id {
            expandedClusterID = nil
        }
        saveBubbleClusters()
        recalculateSuggestions()
        rebuildBubbleSnapshot()
    }

    // MARK: - Bubble Multi-Select Operations

    func toggleBubbleSelectionMode() {
        haptic(.rigid)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isBubbleSelectionModeActive.toggle()
            if !isBubbleSelectionModeActive {
                selectedBubbleSymbols.removeAll()
            }
        }
    }

    func toggleBubbleSelection(for symbol: String) {
        haptic(.light)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedBubbleSymbols.contains(symbol) {
                selectedBubbleSymbols.remove(symbol)
            } else {
                selectedBubbleSymbols.insert(symbol)
            }
        }
    }

    func popSelectedBubbles() {
        haptic(.medium)
        // Find investments matching selected symbols
        let toDelete = investments.filter { selectedBubbleSymbols.contains($0.symbol) && !$0.isWatchlist }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            for inv in toDelete {
                poppedBubbles.append(inv)
                if poppedBubbles.count > 10 { poppedBubbles.removeFirst() }
                PriceAlertStore.shared.removeAlerts(for: inv.id)
                investments.removeAll(where: { $0.id == inv.id })
            }
            isBubbleSelectionModeActive = false
            selectedBubbleSymbols.removeAll()
        }
        recalculate()
        PortfolioStorageService.shared.saveInvestments(investments)
        Task { await triggerCorrelationUpdate() }
    }

    func mergeSelectedBubbles(name: String, type: BubbleClusterType) {
        let symbols = Array(selectedBubbleSymbols)
        guard symbols.count >= 2 else { return }
        mergeCluster(symbols: symbols, name: name, type: type)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isBubbleSelectionModeActive = false
            selectedBubbleSymbols.removeAll()
        }
    }

    func validateClusters() {
        let activeSymbols = Set(investments.filter { !$0.isWatchlist }.map { $0.symbol })
        let originalCount = bubbleClusters.count
        var updated = bubbleClusters
        updated.removeAll { cluster in
            let validSymbols = cluster.symbols.filter { activeSymbols.contains($0) }
            return validSymbols.count < 2 || validSymbols.count != cluster.symbols.count
        }
        if updated.count != originalCount {
            bubbleClusters = updated
            saveBubbleClusters()
            rebuildBubbleSnapshot()
        }
    }

    private func saveBubbleClusters() {
        if let data = try? JSONEncoder().encode(bubbleClusters) {
            UserDefaults.standard.set(data, forKey: "portfolio.bubbleClusters")
        }
    }

    private func loadBubbleClusters() {
        if let data = UserDefaults.standard.data(forKey: "portfolio.bubbleClusters"),
           let decoded = try? JSONDecoder().decode([BubbleCluster].self, from: data) {
            let activeSymbols = Set(investments.filter { !$0.isWatchlist }.map { $0.symbol })
            let filtered = decoded.filter { cluster in
                let validSymbols = cluster.symbols.filter { activeSymbols.contains($0) }
                return validSymbols.count >= 2 && validSymbols.count == cluster.symbols.count
            }
            self.bubbleClusters = filtered
            rebuildBubbleSnapshot()
        }
    }

    func setTempExpandedCluster(id: UUID?) {
        self.expandedClusterID = id
        rebuildBubbleSnapshot()
    }

    func prepareBubblesIfNeeded() {
        validateClusters()
        recalculateSuggestions()
        rebuildBubbleSnapshot()
    }

    private func buildBaseParticles() -> [BubbleParticle] {
        let size = lastCanvasSize.width > 100 && lastCanvasSize.height > 100 ? lastCanvasSize : CGSize(width: 393, height: 852)
        let activeInvestments = investments.filter { !$0.isWatchlist }
        let totalVal = activeInvestments.reduce(0.0) {
            $0 + selectedCurrencyValue(for: $1)
        }

        let maxR: CGFloat = min(size.width, size.height) * 0.22
        let minR: CGFloat = 28

        var baseList: [BubbleParticle] = []

        for inv in investments {
            if inv.isWatchlist {
                let r = 38.0
                let gain = marketService.getStockInfo(for: inv.symbol)?.dayChangePercent ?? 0.0
                let xLimit = size.width - r > r ? CGFloat.random(in: r...(size.width - r)) : size.width / 2
                let yLimit = size.height - r > r ? CGFloat.random(in: r...(size.height - r)) : size.height / 2

                let particle = BubbleParticle(
                    id: inv.id,
                    symbol: inv.symbol,
                    gain: gain,
                    radius: r,
                    position: CGPoint(x: xLimit, y: yLimit),
                    velocity: CGVector(
                        dx: CGFloat.random(in: -0.3...0.3),
                        dy: CGFloat.random(in: -0.3...0.3)
                    ),
                    isWatchlist: true
                )
                baseList.append(particle)
            } else {
                let val = selectedCurrencyValue(for: inv)
                let weight = totalVal > 0 ? (val / totalVal) : 0.0
                let r = minR + (maxR - minR) * CGFloat(weight)
                let gain = inv.totalCost > 0 ? ((val - inv.totalCost) / inv.totalCost) * 100 : 0.0
                let xLimit = size.width - r > r ? CGFloat.random(in: r...(size.width - r)) : size.width / 2
                let yLimit = size.height - r > r ? CGFloat.random(in: r...(size.height - r)) : size.height / 2

                let particle = BubbleParticle(
                    id: inv.id,
                    symbol: inv.symbol,
                    gain: gain,
                    radius: r,
                    position: CGPoint(x: xLimit, y: yLimit),
                    velocity: CGVector(
                        dx: CGFloat.random(in: -0.3...0.3),
                        dy: CGFloat.random(in: -0.3...0.3)
                    ),
                    isWatchlist: false
                )
                baseList.append(particle)
            }
        }
        return baseList
    }

    func rebuildBubbleSnapshot(in size: CGSize? = nil) {
        if let s = size, s.width > 100 && s.height > 100 {
            self.lastCanvasSize = s
        }
        
        let base = buildBaseParticles()
        let sizeToUse = lastCanvasSize.width > 100 && lastCanvasSize.height > 100 ? lastCanvasSize : CGSize(width: 393, height: 852)
        
        let activeInvestments = investments.filter { !$0.isWatchlist }
        let totalVal = activeInvestments.reduce(0.0) {
            $0 + selectedCurrencyValue(for: $1)
        }
        
        let activeSymbols = Set(investments.filter { !$0.isWatchlist }.map { $0.symbol })
        let validClusters = bubbleClusters.filter { cluster in
            let validSymbols = cluster.symbols.filter { activeSymbols.contains($0) }
            return validSymbols.count >= 2 && validSymbols.count == cluster.symbols.count
        }
        
        var visible: [BubbleParticle] = []
        var processedSymbols = Set<String>()
        
        for cluster in validClusters {
            let clusterInvestments = investments.filter { !$0.isWatchlist && cluster.symbols.contains($0.symbol) }
            guard !clusterInvestments.isEmpty else { continue }
            
            let combinedValue = clusterInvestments.reduce(0.0) {
                $0 + selectedCurrencyValue(for: $1)
            }
            let combinedCost = clusterInvestments.reduce(0.0) {
                $0 + selectedCurrencyCost(for: $1)
            }
            
            let gain = combinedCost > 0 ? ((combinedValue - combinedCost) / combinedCost) * 100 : 0.0
            
            let maxR: CGFloat = min(sizeToUse.width, sizeToUse.height) * 0.22
            let minR: CGFloat = 28
            let weight = totalVal > 0 ? (combinedValue / totalVal) : 0.0
            let r = minR + (maxR - minR) * CGFloat(weight)
            
            let formattedValue = CurrencyService.shared.formatConverted(combinedValue)
            let template = AppLanguageManager.shared.t("bubbles.assetsCount")
            let assetsCountText = template.replacingOccurrences(of: "{count}", with: "\(cluster.symbols.count)")
            
            let xLimit = sizeToUse.width - r > r ? CGFloat.random(in: r...(sizeToUse.width - r)) : sizeToUse.width / 2
            let yLimit = sizeToUse.height - r > r ? CGFloat.random(in: r...(sizeToUse.height - r)) : sizeToUse.height / 2
            
            let clusterParticle = BubbleParticle(
                id: cluster.id.uuidString,
                symbol: cluster.name,
                gain: gain,
                radius: r,
                position: CGPoint(x: xLimit, y: yLimit),
                velocity: CGVector(
                    dx: CGFloat.random(in: -0.3...0.3),
                    dy: CGFloat.random(in: -0.3...0.3)
                ),
                isWatchlist: false,
                isCluster: true,
                clusterSymbols: cluster.symbols,
                combinedValueText: formattedValue,
                assetsCountText: assetsCountText
            )
            
            visible.append(clusterParticle)
            
            for sym in cluster.symbols {
                processedSymbols.insert(sym)
            }
        }
        
        for p in base {
            if p.isWatchlist {
                visible.append(p)
            } else {
                if !processedSymbols.contains(p.symbol) {
                    visible.append(p)
                }
            }
        }
        
        // 5. Empty Snapshot Bug Guard
        if visible.isEmpty && !base.isEmpty {
            print("WARNING: visible.isEmpty but base is not. Falling back.")
            visible = base
        }
        
        var connections: [BubbleConnection] = []
        if let expId = expandedClusterID, let cluster = validClusters.first(where: { $0.id == expId }) {
            for sym in cluster.symbols {
                connections.append(BubbleConnection(id: "\(cluster.id.uuidString)-\(sym)", fromSymbol: cluster.name, toSymbol: sym))
            }
        }
        
        print("Investments:", investments.count)
        print("Base particles:", base.count)
        print("Clusters:", bubbleClusters.count)
        print("Expanded cluster:", expandedClusterID?.uuidString ?? "none")
        print("Visible particles:", visible.count)
        
        self.bubbleRenderSnapshot = BubbleRenderSnapshot(
            particles: visible,
            connections: connections,
            clusters: validClusters
        )
    }

    func recalculateSuggestions() {
        let eligible = investments.filter {
            !$0.isWatchlist &&
            !StablecoinClassifier.isStablecoin(symbol: $0.symbol, name: $0.name) &&
            marketService.getCurrentPrice(for: $0.symbol) > 0
        }

        guard eligible.count >= 2 else {
            self.mergeSuggestions = []
            return
        }

        let mergedSymbols = Set(bubbleClusters.flatMap { $0.symbols })
        var suggestions: [MergeSuggestion] = []

        let activeInvestments = investments.filter { !$0.isWatchlist }
        let totalVal = activeInvestments.reduce(0.0) {
            $0 + selectedCurrencyValue(for: $1)
        }

        // Priority 1: Same sector + strong correlation (Pearson correlation >= 0.70)
        let sectors = Dictionary(grouping: eligible) { AssetClassifier.sector(for: $0) }
        for (sectorOpt, sectorAssets) in sectors {
            guard let sector = sectorOpt, sectorAssets.count >= 2 else { continue }

            var pairCorrelations: [Double] = []
            let symbols = sectorAssets.map { $0.symbol }

            for i in 0..<symbols.count {
                for j in (i+1)..<symbols.count {
                    let pair = AssetPair(symbols[i], symbols[j])
                    if let corr = correlationMatrix[pair] {
                        pairCorrelations.append(corr)
                    }
                }
            }

            let avgCorr = pairCorrelations.isEmpty ? 0.0 : pairCorrelations.reduce(0, +) / Double(pairCorrelations.count)
            if avgCorr >= 0.70 {
                let unmergedSymbols = symbols.filter { !mergedSymbols.contains($0) }
                if unmergedSymbols.count >= 2 {
                    let combinedValue = sectorAssets.reduce(0.0) { $0 + selectedCurrencyValue(for: $1) }
                    let combinedWeight = totalVal > 0 ? (combinedValue / totalVal) : 0.0
                    let sectorName = AppLanguageManager.shared.t(sector.localizationKey)

                    suggestions.append(MergeSuggestion(
                        name: sectorName,
                        symbols: unmergedSymbols.sorted(),
                        averageCorrelation: avgCorr,
                        combinedWeight: combinedWeight,
                        type: .sector,
                        sector: sector,
                        assetClass: nil
                    ))
                }
            }
        }

        // Priority 2: Strong correlation only (Pearson correlation >= 0.70, mixed sectors)
        var processedPairs = Set<AssetPair>()
        for i in 0..<eligible.count {
            for j in (i+1)..<eligible.count {
                let assetA = eligible[i]
                let assetB = eligible[j]
                let pair = AssetPair(assetA.symbol, assetB.symbol)
                guard !processedPairs.contains(pair) else { continue }

                if let corr = correlationMatrix[pair], corr >= 0.70 {
                    if !mergedSymbols.contains(assetA.symbol) && !mergedSymbols.contains(assetB.symbol) {
                        processedPairs.insert(pair)

                        let classA = AssetClassifier.category(for: assetA)
                        let classB = AssetClassifier.category(for: assetB)

                        let clusterType: BubbleClusterType
                        let clusterName: String
                        let assetClass: AssetCategory?

                        if classA == classB {
                            clusterType = .assetClass
                            assetClass = classA
                            clusterName = AppLanguageManager.shared.t("bubbles.\(classA.rawValue)Cluster")
                        } else {
                            clusterType = .correlation
                            assetClass = nil
                            clusterName = AppLanguageManager.shared.t("bubbles.correlationCluster")
                        }

                        let valA = selectedCurrencyValue(for: assetA)
                        let valB = selectedCurrencyValue(for: assetB)
                        let combinedWeight = totalVal > 0 ? ((valA + valB) / totalVal) : 0.0

                        suggestions.append(MergeSuggestion(
                            name: clusterName,
                            symbols: [assetA.symbol, assetB.symbol].sorted(),
                            averageCorrelation: corr,
                            combinedWeight: combinedWeight,
                            type: clusterType,
                            sector: nil,
                            assetClass: assetClass
                        ))
                    }
                }
            }
        }

        self.mergeSuggestions = suggestions.filter { sugg in
            !suggestions.contains { other in
                other.type == .sector && sugg.type != .sector && Set(sugg.symbols).isSubset(of: Set(other.symbols))
            }
        }
    }
}

// MARK: - Merge Suggestion Model

struct MergeSuggestion: Identifiable, Hashable {
    var id: String { symbols.sorted().joined(separator: "-") }
    let name: String
    let symbols: [String]
    let averageCorrelation: Double?
    let combinedWeight: Double
    let type: BubbleClusterType
    let sector: AssetSector?
    let assetClass: AssetCategory?
}
