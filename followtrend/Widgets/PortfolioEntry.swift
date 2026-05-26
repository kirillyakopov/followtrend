//
//  PortfolioEntry.swift
//  followtrend
//
//  Timeline entry carrying portfolio and watchlist data for widget views.
//

import WidgetKit
import Foundation

struct PortfolioEntry: TimelineEntry {
    let date: Date
    let totalValue: Double
    let percentageGain: Double
    let currency: String
    let topWatchlistItem: WidgetWatchlistItem?
    let allWatchlist: [WidgetWatchlistItem]
    let isPlaceholder: Bool
}
