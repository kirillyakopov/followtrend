//
//  PortfolioProvider.swift
//  followtrend
//
//  WidgetKit TimelineProvider delivering updates to the Home Screen widgets.
//

import WidgetKit
import Foundation

struct PortfolioProvider: TimelineProvider {
    typealias Entry = PortfolioEntry
    
    func placeholder(in context: Context) -> PortfolioEntry {
        PortfolioEntry(
            date: Date(),
            totalValue: 12450.75,
            percentageGain: 8.42,
            currency: "USD",
            topWatchlistItem: WidgetWatchlistItem(symbol: "TSLA", name: "Tesla Inc.", price: 185.30, changePercent: 4.8),
            allWatchlist: [
                WidgetWatchlistItem(symbol: "TSLA", name: "Tesla Inc.", price: 185.30, changePercent: 4.8),
                WidgetWatchlistItem(symbol: "NVDA", name: "NVIDIA Corp.", price: 850.12, changePercent: 2.1)
            ],
            isPlaceholder: true
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (PortfolioEntry) -> Void) {
        let (total, gain, currency, watchlist) = PortfolioStore.shared.readData()
        let topItem = getTopWatchlistItem(from: watchlist)
        
        let entry = PortfolioEntry(
            date: Date(),
            totalValue: total == 0 && watchlist.isEmpty ? 12450.75 : total,
            percentageGain: total == 0 && watchlist.isEmpty ? 8.42 : gain,
            currency: currency,
            topWatchlistItem: watchlist.isEmpty && total == 0 ? WidgetWatchlistItem(symbol: "TSLA", name: "Tesla Inc.", price: 185.30, changePercent: 4.8) : topItem,
            allWatchlist: watchlist,
            isPlaceholder: context.isPreview
        )
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<PortfolioEntry>) -> Void) {
        let (total, gain, currency, watchlist) = PortfolioStore.shared.readData()
        let topItem = getTopWatchlistItem(from: watchlist)
        
        let entry = PortfolioEntry(
            date: Date(),
            totalValue: total,
            percentageGain: gain,
            currency: currency,
            topWatchlistItem: topItem,
            allWatchlist: watchlist,
            isPlaceholder: false
        )
        
        // Timeline refresh scheduled in 15 minutes as a fallback;
        // main app forces reloading on modifications.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func getTopWatchlistItem(from watchlist: [WidgetWatchlistItem]) -> WidgetWatchlistItem? {
        // Sorts by daily price change percentage descending (highest gain first)
        return watchlist.sorted { $0.changePercent > $1.changePercent }.first
    }
}
