
//
//  StockModels.swift
//  followtrend
//
//  Created by Portfolio Manager
//

import Foundation

// MARK: - Stock Asset (live market data)

struct StockAsset: Identifiable, Hashable {
    let id = UUID()
    let symbol: String
    let name: String
    var currentPrice: Double
    let prevPrice: Double



    var dayChangePercent: Double {
        guard prevPrice > 0 else { return 0 }
        return ((currentPrice - prevPrice) / prevPrice) * 100
    }
}

enum PriceSourceMode: String, CaseIterable, Identifiable, Codable {
    case market = "market"
    case brokerAdjusted = "brokerAdjusted"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .market: return "Market Price"
        case .brokerAdjusted: return "Broker Adjusted"
        }
    }
}

struct BrokerAdjustmentDraft {
    var brokerName: String
    var currentBrokerPrice: Double
    var brokerCurrency: AppCurrency
    var currentApiPrice: Double
}

// MARK: - Investment (user position)

struct Investment: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    let symbol:   String
    let name:     String
    var shares:   Double
    var buyPrice: Double         // weighted-average cost basis
    var buyDate:  String         // "YYYY-MM-DD"
    var coinId:   String?        // CoinGecko id (crypto only)
    var nativeCurrency: String = "USD"
    var isWatchlist: Bool = false

    var notes: String = ""
    var tags: String = ""

    var currentApiPriceAtEntry: Double?
    var currentBrokerPriceAtEntry: Double?
    var priceAdjustmentFactor: Double?
    var brokerName: String?
    var apiBaseCurrency: String?
    var brokerCurrency: String?
    var displayCurrency: String?
    var fxRateAtCreation: Double?

    var totalCost: Double { shares * buyPrice }

    var hasBrokerAdjustment: Bool {
        guard let factor = priceAdjustmentFactor else { return false }
        return factor.isFinite && factor > 0
    }

    func displayPrice(apiPrice: Double, mode: PriceSourceMode) -> Double {
        guard mode == .brokerAdjusted, hasBrokerAdjustment, let factor = priceAdjustmentFactor else {
            return apiPrice
        }
        return apiPrice * factor
    }

    func positionValue(apiPrice: Double, mode: PriceSourceMode) -> Double {
        shares * displayPrice(apiPrice: apiPrice, mode: mode)
    }

    static func adjustmentFactor(
        apiPrice: Double,
        apiCurrency: AppCurrency,
        brokerPrice: Double,
        brokerCurrency: AppCurrency,
        displayCurrency: AppCurrency,
        currencyService: CurrencyService = .shared
    ) -> Double? {
        guard apiPrice > 0, brokerPrice > 0 else { return nil }
        let apiConverted = currencyService.convert(value: apiPrice, from: apiCurrency, to: displayCurrency)
        let brokerConverted = currencyService.convert(value: brokerPrice, from: brokerCurrency, to: displayCurrency)
        guard apiConverted > 0, brokerConverted.isFinite else { return nil }
        return brokerConverted / apiConverted
    }

    static func fxRate(
        from sourceCurrency: AppCurrency,
        to targetCurrency: AppCurrency,
        currencyService: CurrencyService = .shared
    ) -> Double {
        currencyService.convert(value: 1, from: sourceCurrency, to: targetCurrency)
    }
    
    // Convert from SwiftData model
    init(from model: InvestmentModel) {
        self.id = model.id
        self.symbol = model.symbol
        self.name = model.name
        self.shares = model.shares
        self.buyPrice = model.buyPrice
        self.buyDate = model.buyDate
        self.coinId = model.coinId
        self.nativeCurrency = model.nativeCurrency
        self.isWatchlist = model.isWatchlist
        self.notes = model.notes
        self.tags = model.tags
        self.currentApiPriceAtEntry = model.currentApiPriceAtEntry
        self.currentBrokerPriceAtEntry = model.currentBrokerPriceAtEntry
        self.priceAdjustmentFactor = model.priceAdjustmentFactor
        self.brokerName = model.brokerName
        self.apiBaseCurrency = model.apiBaseCurrency
        self.brokerCurrency = model.brokerCurrency
        self.displayCurrency = model.displayCurrency
        self.fxRateAtCreation = model.fxRateAtCreation
    }
    
    // Default initializer since we added a custom one
    init(
        id: String = UUID().uuidString,
        symbol: String,
        name: String,
        shares: Double,
        buyPrice: Double,
        buyDate: String,
        coinId: String? = nil,
        nativeCurrency: String = "USD",
        isWatchlist: Bool = false,
        notes: String = "",
        tags: String = "",
        currentApiPriceAtEntry: Double? = nil,
        currentBrokerPriceAtEntry: Double? = nil,
        priceAdjustmentFactor: Double? = nil,
        brokerName: String? = nil,
        apiBaseCurrency: String? = nil,
        brokerCurrency: String? = nil,
        displayCurrency: String? = nil,
        fxRateAtCreation: Double? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.shares = shares
        self.buyPrice = buyPrice
        self.buyDate = buyDate
        self.coinId = coinId
        self.nativeCurrency = nativeCurrency
        self.isWatchlist = isWatchlist
        self.notes = notes
        self.tags = tags
        self.currentApiPriceAtEntry = currentApiPriceAtEntry
        self.currentBrokerPriceAtEntry = currentBrokerPriceAtEntry
        self.priceAdjustmentFactor = priceAdjustmentFactor
        self.brokerName = brokerName
        self.apiBaseCurrency = apiBaseCurrency
        self.brokerCurrency = brokerCurrency
        self.displayCurrency = displayCurrency
        self.fxRateAtCreation = fxRateAtCreation
    }
}

// MARK: - Portfolio Performance

struct PortfolioPerformance {
    let totalValue: Double
    let totalCost: Double

    var absoluteGain: Double { totalValue - totalCost }

    var percentageGain: Double {
        guard totalCost > 0 else { return 0 }
        return (absoluteGain / totalCost) * 100
    }
}

// MARK: - Bubble (physics particle)

enum SpawnState: String, Codable {
    case spawning
    case settling
    case active
}

struct BubbleParticle: Identifiable, Equatable {
    let id: String          // matches Investment.id or BubbleCluster.id
    let symbol: String
    var gain: Double
    var radius: CGFloat
    var position: CGPoint
    var velocity: CGVector
    var isWatchlist: Bool
    var spawnState: SpawnState = .active
    var spawnProgress: Double = 1.0
    
    // Bubble Merge additions
    var isCluster: Bool = false
    var clusterSymbols: [String] = []
    var combinedValueText: String = ""
    var assetsCountText: String = ""
}

// MARK: - Bubble Cluster (visual only)

struct BubbleCluster: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let symbols: [String]
    let averageCorrelation: Double?
    let combinedWeight: Double
    let type: BubbleClusterType
    var isExpanded: Bool
}

enum BubbleClusterType: String, Codable {
    case sector
    case assetClass
    case correlation
}

struct BubbleConnection: Identifiable, Equatable {
    let id: String
    let fromSymbol: String
    let toSymbol: String
}

struct BubbleRenderSnapshot: Equatable {
    var particles: [BubbleParticle] = []
    var connections: [BubbleConnection] = []
    var clusters: [BubbleCluster] = []
}
