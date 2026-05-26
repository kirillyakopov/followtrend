//
//  AnalyticsModels.swift
//  followtrend
//

import Foundation

enum AssetCategory: String, CaseIterable, Codable, Hashable, Identifiable {
    case stocks
    case etfs
    case crypto
    case stablecoins

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .stocks: return "allocation.stocks"
        case .etfs: return "allocation.etfs"
        case .crypto: return "allocation.crypto"
        case .stablecoins: return "allocation.stablecoins"
        }
    }
}

struct AssetAllocationSlice: Identifiable, Equatable {
    var id: AssetCategory { category }
    let category: AssetCategory
    let value: Double
    let percentage: Double
    let assets: [Investment]
}

enum RebalancingSeverity: Int, Codable, Comparable {
    case info
    case warning
    case critical

    static func < (lhs: RebalancingSeverity, rhs: RebalancingSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct RebalancingSuggestion: Identifiable, Equatable {
    let id: String
    let localizationKey: String
    let arguments: [String]
    let severity: RebalancingSeverity
    let icon: String

    init(
        id: String = UUID().uuidString,
        localizationKey: String,
        arguments: [String],
        severity: RebalancingSeverity,
        icon: String
    ) {
        self.id = id
        self.localizationKey = localizationKey
        self.arguments = arguments
        self.severity = severity
        self.icon = icon
    }
}

enum AssetClassifier {
    static func category(for investment: Investment) -> AssetCategory {
        let symbol = investment.symbol.uppercased()

        if StablecoinClassifier.isStablecoin(symbol: investment.symbol, name: investment.name) {
            return .stablecoins
        }

        if investment.coinId != nil || cryptoSymbols.contains(symbol) {
            return .crypto
        }

        if etfSymbols.contains(symbol) || symbol.hasSuffix("ETF") {
            return .etfs
        }

        return .stocks
    }

    static func isTechnology(_ investment: Investment) -> Bool {
        technologySymbols.contains(investment.symbol.uppercased())
    }

    static func sector(for investment: Investment) -> AssetSector? {
        let symbol = investment.symbol.uppercased()
        if technologySymbols.contains(symbol) { return .tech }
        if financeSymbols.contains(symbol) { return .finance }
        if energySymbols.contains(symbol) { return .energy }
        if healthcareSymbols.contains(symbol) { return .healthcare }
        return nil
    }

    private static let cryptoSymbols: Set<String> = [
        "BTC", "ETH", "SOL", "ADA", "XRP", "DOGE", "BNB", "AVAX", "DOT", "MATIC"
    ]

    private static let etfSymbols: Set<String> = [
        "SPY", "VOO", "VTI", "QQQ", "IWM", "DIA", "IVV", "EFA", "VEA", "VWO", "ARKK"
    ]

    private static let technologySymbols: Set<String> = [
        "AAPL", "MSFT", "NVDA", "GOOGL", "GOOG", "META", "AMZN", "TSLA", "AMD", "INTC", "AVGO", "ADBE", "CRM", "SAP"
    ]

    private static let financeSymbols: Set<String> = [
        "JPM", "BAC", "MS", "GS", "WFC", "C"
    ]

    private static let energySymbols: Set<String> = [
        "XOM", "CVX", "COP", "SLB"
    ]

    private static let healthcareSymbols: Set<String> = [
        "JNJ", "LLY", "UNH", "PFE", "ABBV", "MRK"
    ]
}

enum AssetSector: String, CaseIterable, Codable {
    case tech = "tech"
    case finance = "finance"
    case energy = "energy"
    case healthcare = "healthcare"
    
    var localizationKey: String {
        "bubbles.\(rawValue)Cluster"
    }
}

