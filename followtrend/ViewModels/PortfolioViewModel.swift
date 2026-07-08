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
    @Published var bubbleRenderSnapshot = BubbleRenderSnapshot()
    @Published var expandedClusterID: UUID? = nil

    // Multi-Select Mode state
    @Published var isBubbleSelectionModeActive: Bool = false
    @Published var selectedBubbleSymbols: Set<String> = []

    // MARK: Cached derived state (pre-formatted for views)

    /// Pre-sorted, pre-formatted active positions. Views read this directly — zero sorting/formatting in body.
    @Published private(set) var sortedActivePositions: [PositionRowModel] = []

    /// Pre-formatted watchlist rows.
    @Published private(set) var watchlistRows: [WatchlistRowModel] = []

    /// Snapshot for advice cards — only rebuilt when analytics change, not on every price tick.
    @Published private(set) var adviceSnapshot: AdviceCardsSnapshot = AdviceCardsSnapshot(
        assetAllocation: [], rebalancingSuggestions: [], correlationMatrix: [:],
        activeInvestmentIDs: [], strongestPairSymbolA: nil, strongestPairSymbolB: nil,
        strongestPairValue: nil, largestSymbol: nil, largestWeight: 0,
        stablecoinPercentage: 0, hasStablecoins: false
    )

    /// Incremented only when investments are added/removed — used by chart to avoid reloading on price ticks.
    @Published private(set) var chartTrigger: Int = 0

    /// Sort mode lives in ViewModel so the sorted array is always ready.
    @Published var positionSortMode: PositionSortMode = .sinceBuy {
        didSet {
            UserDefaults.standard.set(positionSortMode.rawValue, forKey: "portfolio.positionSortMode")
            rebuildRowModels()
        }
    }

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
        // Restore persisted sort mode
        if let stored = UserDefaults.standard.string(forKey: "portfolio.positionSortMode"),
           let mode = PositionSortMode(rawValue: stored) {
            positionSortMode = mode
        }

        loadDefaultInvestments()
        loadPriceSourceMode()

        // Re-calculate after price updates — DEBOUNCED so that a full batch refresh
        // (N symbols) triggers recalculate only once after all prices land.
        marketService.$liveStocks
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
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
        
        // Debug injection hook (toggle isEnabled in DebugDataInjector.swift)
        DebugDataInjector.injectDummyAssets(into: self)
        
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
        return CurrencyService.shared.convertToSelected(value: nativeValue, from: inv.priceCurrency)
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
            displayCurrency: displayCurrency,
            currencyService: CurrencyService.shared
        )
        inv.brokerName = draft.brokerName
        inv.apiBaseCurrency = apiCurrency.rawValue
        inv.brokerCurrency = draft.brokerCurrency.rawValue
        inv.displayCurrency = displayCurrency.rawValue
        inv.fxRateAtCreation = Investment.fxRate(from: draft.brokerCurrency, to: displayCurrency, currencyService: CurrencyService.shared)
    }

    // MARK: Live price refresh (Finnhub quotes + CoinGecko)

    func refreshLivePrices() async {
        isPriceFetching = true
        let invSnapshot = investments   // capture value-type copy for safe concurrent access

        // Fetch all prices concurrently, collect into a local dict
        var collectedPrices: [String: Double] = [:]
        await withTaskGroup(of: (String, Double?).self) { group in
            for inv in invSnapshot {
                let sym    = inv.symbol
                let coinId = inv.coinId
                group.addTask {
                    do {
                        let price: Double
                        if let cid = coinId {
                            price = try await CryptoDataService.shared.currentPrice(coinId: cid)
                        } else {
                            price = try await MarketDataService.shared.fetchQuote(symbol: sym)
                        }
                        return (sym, price)
                    } catch {
                        return (sym, nil)
                    }
                }
            }
            for await (sym, price) in group {
                if let p = price { collectedPrices[sym] = p }
            }
        }

        // Apply ALL prices in one shot → ONE Combine publish → ONE debounced recalculate
        marketService.applyBatchUpdate(collectedPrices)

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
        }
    }

    // MARK: Performance calculation

    func recalculate() {
        var value = cashBalance
        var cost  = cashBalance

        let cs = CurrencyService.shared

        for inv in investments {
            guard !inv.isWatchlist else { continue }
            let price = displayPrice(for: inv)
            let convertedPrice = cs.convertToSelected(value: price, from: inv.priceCurrency)
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
        rebuildBubbleSnapshot()

        // Rebuild cached row models for list views
        rebuildRowModels()
    }

    private func refreshCachedPortfolioAnalytics() {
        let active = investments.filter { !$0.isWatchlist }
        let cs = CurrencyService.shared

        let valuesByID: [String: Double] = Dictionary(uniqueKeysWithValues: active.map { inv in
            let price = displayPrice(for: inv)
            let convertedPrice = cs.convertToSelected(value: price, from: inv.priceCurrency)
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
        // Watchlist ghosts legitimately have no purchase price (0) — only real
        // positions require a positive buy price. (This is why imported ghost
        // bubbles used to silently vanish.)
        guard !sym.isEmpty, shares > 0 else { return }
        if !isWatchlist, buyPrice <= 0 { return }

        let assetName = name ?? marketService.getStockInfo(for: sym)?.name ?? sym

        if let idx = investments.firstIndex(where: { $0.symbol == sym && $0.isWatchlist == isWatchlist }) {
            let existing      = investments[idx]
            if isWatchlist {
                if buyPrice > 0 { investments[idx].buyPrice = buyPrice }
            } else {
                let totalShares   = existing.shares + shares
                let weightedPrice = (existing.shares * existing.buyPrice + shares * buyPrice) / totalShares
                investments[idx].shares   = totalShares
                investments[idx].buyPrice = weightedPrice
                if brokerAdjustment != nil {
                    applyBrokerAdjustment(brokerAdjustment, to: &investments[idx])
                }
                chartTrigger += 1   // signal chart to reload (position merged)
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
            chartTrigger += 1   // signal chart to reload (new symbol added)
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
        chartTrigger += 1   // signal chart to reload (watchlist item became active position)

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
        chartTrigger += 1   // signal chart to reload (position removed)
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
        chartTrigger += 1   // signal chart to reload (position restored)

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
        chartTrigger += 1   // signal chart to reload (position edited)

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

    // MARK: - Bubble Merge Operations

    @MainActor
    func createClusterFromSelectedSymbols(_ selected: Set<String>) {
        let validSymbols = selected.filter { symbol in
            !StablecoinClassifier.isStablecoin(symbol: symbol, name: "")
        }

        guard validSymbols.count >= 2 else { return }
        hapticSuccess()

        var updatedClusters = bubbleClusters.map { cluster in
            let newSymbols = cluster.symbols.filter { !validSymbols.contains($0) }
            return BubbleCluster(
                id: cluster.id,
                name: cluster.name,
                symbols: newSymbols,
                averageCorrelation: cluster.averageCorrelation,
                combinedWeight: cluster.combinedWeight,
                type: cluster.type,
                isExpanded: cluster.isExpanded
            )
        }

        updatedClusters.removeAll { $0.symbols.count < 2 }

        let newCluster = BubbleCluster(
            id: UUID(),
            name: AppLanguageManager.shared.t("bubbles.customCluster"),
            symbols: Array(validSymbols).sorted(),
            averageCorrelation: nil,
            combinedWeight: 0,
            type: .correlation,
            isExpanded: false
        )

        updatedClusters.append(newCluster)

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            bubbleClusters = updatedClusters
            selectedBubbleSymbols.removeAll()
            isBubbleSelectionModeActive = false
            expandedClusterID = nil
        }

        saveBubbleClusters()
        rebuildBubbleSnapshot()
    }

    func dissolveCluster(id: UUID) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            var updated = bubbleClusters
            if let idx = updated.firstIndex(where: { $0.id == id }) {
                updated.remove(at: idx)
                bubbleClusters = updated
            }
            if expandedClusterID == id {
                expandedClusterID = nil
            }
        }
        saveBubbleClusters()
        rebuildBubbleSnapshot()
    }

    func renameCluster(id: UUID, newName: String) {
        if let idx = bubbleClusters.firstIndex(where: { $0.id == id }) {
            let old = bubbleClusters[idx]
            bubbleClusters[idx] = BubbleCluster(
                id: old.id,
                name: newName,
                symbols: old.symbols,
                averageCorrelation: old.averageCorrelation,
                combinedWeight: old.combinedWeight,
                type: old.type,
                isExpanded: old.isExpanded
            )
            saveBubbleClusters()
            rebuildBubbleSnapshot()
        }
    }

    func removeSymbolFromCluster(id: UUID, symbol: String) {
        if let idx = bubbleClusters.firstIndex(where: { $0.id == id }) {
            var updatedSymbols = bubbleClusters[idx].symbols
            updatedSymbols.removeAll { $0 == symbol }
            
            if updatedSymbols.count < 2 {
                dissolveCluster(id: id)
            } else {
                let old = bubbleClusters[idx]
                bubbleClusters[idx] = BubbleCluster(
                    id: old.id,
                    name: old.name,
                    symbols: updatedSymbols,
                    averageCorrelation: old.averageCorrelation,
                    combinedWeight: old.combinedWeight,
                    type: old.type,
                    isExpanded: old.isExpanded
                )
                saveBubbleClusters()
                rebuildBubbleSnapshot()
            }
        }
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
        haptic(.rigid)
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
        chartTrigger += 1   // signal chart to reload (positions removed)
        recalculate()
        PortfolioStorageService.shared.saveInvestments(investments)
        Task { await triggerCorrelationUpdate() }
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
        rebuildBubbleSnapshot()
    }

    private func buildBaseParticles() -> [BubbleParticle] {
        let size = lastCanvasSize.width > 100 && lastCanvasSize.height > 100 ? lastCanvasSize : CGSize(width: 393, height: 852)
        let activeInvestments = investments.filter { !$0.isWatchlist }
        let totalVal = activeInvestments.reduce(0.0) {
            $0 + selectedCurrencyValue(for: $1)
        }

        var baseList: [BubbleParticle] = []

        for inv in investments {
            if inv.isWatchlist {
                // Ghost bubbles: small fixed size (design spec r = 21)
                let r = 21.0
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
                    isWatchlist: true,
                    name: inv.name
                )
                baseList.append(particle)
            } else {
                let val = selectedCurrencyValue(for: inv)
                let weight = totalVal > 0 ? (val / totalVal) : 0.0
                // Design spec: radius = 15 + sqrt(allocation) × 76 (≈29–49 typical)
                let r = 15.0 + sqrt(max(0, weight)) * 76.0
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
                    isWatchlist: false,
                    name: inv.name
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

            // Design spec: cluster radius = min(78, sqrt(Σ memberR²) × 1.05)
            let sumR2 = clusterInvestments.reduce(0.0) { acc, inv in
                let w = totalVal > 0 ? (selectedCurrencyValue(for: inv) / totalVal) : 0.0
                let memberR = 15.0 + sqrt(max(0, w)) * 76.0
                return acc + memberR * memberR
            }
            let r = CGFloat(min(78.0, sqrt(sumR2) * 1.05))
            
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
            visible = base
        }
        
        var connections: [BubbleConnection] = []
        if let expId = expandedClusterID, let cluster = validClusters.first(where: { $0.id == expId }) {
            for sym in cluster.symbols {
                connections.append(BubbleConnection(id: "\(cluster.id.uuidString)-\(sym)", fromSymbol: cluster.name, toSymbol: sym))
            }
        }
        
        self.bubbleRenderSnapshot = BubbleRenderSnapshot(
            particles: visible,
            connections: connections,
            clusters: validClusters,
            baseParticles: base
        )
    }



    // MARK: - Cached Row Model Rebuilding

    func rebuildRowModels() {
        let cs = CurrencyService.shared
        let active = investments.filter { !$0.isWatchlist }
        let watchlist = investments.filter { $0.isWatchlist }

        // --- Active positions ---
        let totalActiveValue = active.reduce(0.0) { $0 + selectedCurrencyValue(for: $1) }

        let built: [PositionRowModel] = active.map { inv in
            let val  = selectedCurrencyValue(for: inv)
            let cost = selectedCurrencyCost(for: inv)
            let gain = val - cost
            let gainPct = cost > 0 ? (gain / cost) * 100 : 0.0
            let dayChangePct = marketService.getStockInfo(for: inv.symbol)?.dayChangePercent ?? 0.0
            let returnSinceBuy = val - cost

            let sharesText = String(format: "%.4g", inv.shares)
            let avgPriceText = cs.format(value: inv.buyPrice, from: inv.nativeCurrency)
            let sharesSubtitle = "\(sharesText) \(AppLanguageManager.shared.t("portfolio.stueck"))  ·  Ø \(avgPriceText)"
            let valueText = cs.formatConverted(val)
            let gainText = String(format: "%@%.1f%%", gainPct >= 0 ? "+" : "", gainPct)

            return PositionRowModel(
                id:             inv.id,
                investmentID:   inv.id,
                symbol:         inv.symbol,
                name:           inv.name,
                sharesSubtitle: sharesSubtitle,
                valueText:      valueText,
                gainPercentText: gainText,
                isPositive:     gainPct >= 0,
                badgeColorIndex: abs(inv.symbol.hashValue) % 6,
                gainPercent:    gainPct,
                totalValue:     val,
                returnSinceBuy: returnSinceBuy,
                dayChangePercent: dayChangePct,
                coinId:         inv.coinId
            )
        }

        sortedActivePositions = sortRows(built)

        // --- Watchlist ---
        watchlistRows = watchlist.map { inv in
            let price    = marketService.getCurrentPrice(for: inv.symbol)
            let gainPct  = marketService.getStockInfo(for: inv.symbol)?.dayChangePercent ?? 0.0
            let priceText = cs.format(value: price, from: inv.priceCurrency)
            let changeText = String(format: "%@%.1f%%", gainPct >= 0 ? "+" : "", gainPct)

            return WatchlistRowModel(
                id:                inv.id,
                investmentID:      inv.id,
                symbol:            inv.symbol,
                name:              inv.name,
                nativeCurrency:    inv.nativeCurrency,
                priceText:         priceText,
                dayChangeText:     changeText,
                dayChangePositive: gainPct >= 0,
                badgeColorIndex:   abs(inv.symbol.hashValue) % 6,
                coinId:            inv.coinId
            )
        }

        // --- Advice snapshot (rebuilt on analytics + price changes) ---
        let strongestPair = correlationMatrix
            .filter { abs($0.value) > 0.4 }
            .max { abs($0.value) < abs($1.value) }

        let largest = active
            .map { ($0, selectedCurrencyValue(for: $0)) }
            .max { $0.1 < $1.1 }
        let largestWeight = totalActiveValue > 0 ? ((largest?.1 ?? 0) / totalActiveValue * 100) : 0

        let stablecoinSlice = assetAllocation.first { $0.category == .stablecoins }

        let newSnapshot = AdviceCardsSnapshot(
            assetAllocation:       assetAllocation,
            rebalancingSuggestions: rebalancingSuggestions,
            correlationMatrix:     correlationMatrix,
            activeInvestmentIDs:   active.map(\.id),
            strongestPairSymbolA:  strongestPair?.key.symbolA,
            strongestPairSymbolB:  strongestPair?.key.symbolB,
            strongestPairValue:    strongestPair?.value,
            largestSymbol:         largest?.0.symbol,
            largestWeight:         largestWeight,
            stablecoinPercentage:  stablecoinSlice?.percentage ?? 0,
            hasStablecoins:        stablecoinSlice != nil
        )
        // Only publish if something actually changed — prevents advice cards from re-rendering
        // on every price tick when the analytics values haven't changed.
        if newSnapshot != adviceSnapshot {
            adviceSnapshot = newSnapshot
        }
    }

    private func sortRows(_ rows: [PositionRowModel]) -> [PositionRowModel] {
        rows.sorted { lhs, rhs in
            switch positionSortMode {
            case .sinceBuy:
                let l = lhs.returnSinceBuy, r = rhs.returnSinceBuy
                return l == r ? lhs.symbol < rhs.symbol : l > r
            case .bestPerformer:
                return lhs.gainPercent == rhs.gainPercent
                    ? lhs.symbol < rhs.symbol : lhs.gainPercent > rhs.gainPercent
            case .worstPerformer:
                return lhs.gainPercent == rhs.gainPercent
                    ? lhs.symbol < rhs.symbol : lhs.gainPercent < rhs.gainPercent
            case .today:
                return lhs.dayChangePercent == rhs.dayChangePercent
                    ? lhs.symbol < rhs.symbol : lhs.dayChangePercent > rhs.dayChangePercent
            case .totalValue:
                return lhs.totalValue == rhs.totalValue
                    ? lhs.symbol < rhs.symbol : lhs.totalValue > rhs.totalValue
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
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
