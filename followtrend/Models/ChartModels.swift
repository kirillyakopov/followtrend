//
//  ChartModels.swift
//  followtrend
//

import Foundation

// MARK: - Single OHLC/Close data point

struct ChartPoint: Identifiable, Equatable {
    let id      = UUID()
    let timestamp: Date
    let close:     Double
    var open:      Double?
    var high:      Double?
    var low:       Double?
    var volume:    Double?
}

// MARK: - Chart data with loading state

enum ChartLoadState: Equatable {
    case idle
    case loading
    case loaded([ChartPoint])
    case error(String)

    var points: [ChartPoint]? {
        if case .loaded(let pts) = self { return pts }
        return nil
    }
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

// MARK: - Timeframe

enum Timeframe: String, CaseIterable, Identifiable {
    case oneDay   = "1D"
    case oneWeek  = "1W"
    case oneMonth = "1M"
    case oneYear  = "1Y"
    case max      = "Max"

    var id: String { rawValue }

    /// How many days back to fetch
    var daysBack: Int {
        switch self {
        case .oneDay:   return 1
        case .oneWeek:  return 7
        case .oneMonth: return 30
        case .oneYear:  return 365
        case .max:      return 365 * 5
        }
    }

    /// CoinGecko `days` parameter
    var coinGeckoDays: String {
        switch self {
        case .oneDay:   return "1"
        case .oneWeek:  return "7"
        case .oneMonth: return "30"
        case .oneYear:  return "365"
        case .max:      return "max"
        }
    }
}

// MARK: - Search result

enum AssetKind: String {
    case stock  = "Stock"
    case etf    = "ETF"
    case crypto = "Crypto"
}

struct SearchResult: Identifiable, Hashable {
    let id          = UUID()
    let symbol:      String
    let name:        String
    let kind:        AssetKind
    let coinId:      String?   // CoinGecko id (crypto only)

    func hash(into hasher: inout Hasher) { hasher.combine(symbol) }
    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool { lhs.symbol == rhs.symbol }
}
