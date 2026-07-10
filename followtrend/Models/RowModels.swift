//
//  RowModels.swift
//  followtrend
//
//  Lightweight value-type snapshots for list rows.
//  All display strings are pre-formatted in the ViewModel so
//  SwiftUI body functions contain zero formatting work.
//

import SwiftUI

// MARK: - Position Sort Mode (shared between VM and views)

enum PositionSortMode: String, CaseIterable, Identifiable {
    case sinceBuy
    case today
    case totalValue
    case name
    case bestPerformer
    case worstPerformer

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .sinceBuy:      return "sort.sinceBuy"
        case .today:         return "sort.today"
        case .totalValue:    return "sort.totalValue"
        case .name:          return "sort.name"
        case .bestPerformer: return "sort.bestPerformer"
        case .worstPerformer: return "sort.worstPerformer"
        }
    }

    var icon: String {
        switch self {
        case .sinceBuy:      return "calendar.badge.clock"
        case .today:         return "sun.max.fill"
        case .totalValue:    return "banknote.fill"
        case .name:          return "textformat.abc"
        case .bestPerformer: return "arrow.up.right.circle.fill"
        case .worstPerformer: return "arrow.down.right.circle.fill"
        }
    }
}

// MARK: - Position Row Model


struct PositionRowModel: Identifiable, Equatable {
    // Identity
    let id: String          // matches Investment.id
    let investmentID: String

    // Display strings (pre-formatted in ViewModel)
    let symbol: String
    let name: String
    let sharesSubtitle: String  // "12 Shares  ·  Ø $175.00"
    let valueText: String       // "$2,100.00"
    let gainPercentText: String // "+3.5%"
    let isPositive: Bool

    // Badge color selection (stable hash, 0–5)
    let badgeColorIndex: Int

    // Raw values (for search / sort in VM — not used in view body)
    let gainPercent: Double
    let totalValue: Double
    let returnSinceBuy: Double
    let dayChangePercent: Double

    // For sheet navigation
    let coinId: String?
}

// MARK: - Watchlist Row Model

struct WatchlistRowModel: Identifiable, Equatable {
    let id: String          // matches Investment.id
    let investmentID: String

    let symbol: String
    let name: String
    let nativeCurrency: String
    let priceText: String       // "$175.50"
    let dayChangeText: String   // "+1.23%"
    let dayChangePositive: Bool

    let badgeColorIndex: Int

    let coinId: String?
}

// MARK: - Advice Cards Snapshot

struct AdviceCardsSnapshot: Equatable {
    let assetAllocation: [AssetAllocationSlice]
    let rebalancingSuggestions: [RebalancingSuggestion]
    let correlationMatrix: [AssetPair: Double]
    let activeInvestmentIDs: [String]   // stable identity for card content

    // Pre-computed for diversification card
    let strongestPairSymbolA: String?
    let strongestPairSymbolB: String?
    let strongestPairValue: Double?

    // Pre-computed for concentration card
    let largestSymbol: String?
    let largestWeight: Double

    // Pre-computed for stablecoin card
    let stablecoinPercentage: Double
    let hasStablecoins: Bool

    // Pre-computed for diversification-score card
    let diversificationScore: Int?      // 0–100, from the average pairwise correlation
    let averageCorrelation: Double?

    // Pre-computed for risk-overview card
    let volatility30D: Double?          // annualised %, from daily log-return σ
    let maxDrawdown: Double?            // negative %, deepest peak-to-trough
}
