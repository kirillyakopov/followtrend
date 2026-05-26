//
//  PortfolioStore.swift
//  followtrend
//
//  Shared data synchronization layer between the main iOS application
//  and the Widget extension using App Groups (UserDefaults suite).
//

import Foundation
import SwiftUI

// MARK: - Watchlist Data Transfer Object
public struct WidgetWatchlistItem: Codable, Identifiable {
    public var id: String { symbol }
    public let symbol: String
    public let name: String
    public let price: Double
    public let changePercent: Double
    
    public init(symbol: String, name: String, price: Double, changePercent: Double) {
        self.symbol = symbol
        self.name = name
        self.price = price
        self.changePercent = changePercent
    }
}

// MARK: - Portfolio Shared Store
public final class PortfolioStore {
    public static let shared = PortfolioStore()
    
    private let appGroupSuiteName = "group.com.yourapp.finance"
    private let userDefaults: UserDefaults?
    
    private init() {
        self.userDefaults = UserDefaults(suiteName: appGroupSuiteName)
    }
    
    private let totalValueKey = "totalPortfolioValue"
    private let percentageGainKey = "percentageGain"
    private let currencyKey = "currency"
    private let watchlistKey = "watchlist"
    
    /// Writes the processed portfolio status to the App Group UserDefaults suite.
    public func writeData(totalValue: Double, percentageGain: Double, currency: String, watchlist: [WidgetWatchlistItem]) {
        guard let userDefaults = userDefaults else {
            print("Widget Error: App Group suite '\(appGroupSuiteName)' could not be loaded.")
            return
        }
        userDefaults.set(totalValue, forKey: totalValueKey)
        userDefaults.set(percentageGain, forKey: percentageGainKey)
        userDefaults.set(currency, forKey: currencyKey)
        
        if let encoded = try? JSONEncoder().encode(watchlist) {
            userDefaults.set(encoded, forKey: watchlistKey)
        }
        userDefaults.synchronize()
    }
    
    /// Reads the cached portfolio status from the App Group.
    public func readData() -> (totalValue: Double, percentageGain: Double, currency: String, watchlist: [WidgetWatchlistItem]) {
        guard let userDefaults = userDefaults else {
            return (0.0, 0.0, "USD", [])
        }
        let totalValue = userDefaults.double(forKey: totalValueKey)
        let percentageGain = userDefaults.double(forKey: percentageGainKey)
        let currency = userDefaults.string(forKey: currencyKey) ?? "USD"
        
        var watchlist: [WidgetWatchlistItem] = []
        if let data = userDefaults.data(forKey: watchlistKey),
           let decoded = try? JSONDecoder().decode([WidgetWatchlistItem].self, from: data) {
            watchlist = decoded
        }
        
        return (totalValue, percentageGain, currency, watchlist)
    }
}

// Note: UI Design Extensions (Color and Double) are defined in DesignSystem.swift which is shared with the widget target.

