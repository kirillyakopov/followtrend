
//
//  StockMarketService.swift
//  followtrend
//

import Foundation
import Combine

// MARK: - Market Service (singleton)

final class StockMarketService: ObservableObject {

    static let shared = StockMarketService()

    @Published private(set) var liveStocks: [String: StockAsset]

    private init() {
        liveStocks = Self.buildDefaultStocks()
    }

    // MARK: Accessors

    func getCurrentPrice(for symbol: String) -> Double {
        liveStocks[symbol.uppercased()]?.currentPrice ?? 0
    }

    func getStockInfo(for symbol: String) -> StockAsset? {
        liveStocks[symbol.uppercased()]
    }

    var availableSymbols: [String] {
        liveStocks.keys.sorted()
    }

    // MARK: Update with real price from Finnhub / CoinGecko

    func updatePrice(symbol: String, price: Double) {
        let key = symbol.uppercased()
        guard price > 0 else { return }

        if var existing = liveStocks[key] {
            existing = StockAsset(
                symbol:      existing.symbol,
                name:        existing.name,
                currentPrice: price,
                prevPrice:   existing.currentPrice   // old current becomes prev
            )
            liveStocks[key] = existing
        } else {
            // Unknown symbol — register it with synthetic history
            registerSymbol(symbol: key, name: key, price: price)
        }
    }

    /// Register a symbol not in the default catalogue (e.g. user-added stock)
    func registerSymbol(symbol: String, name: String, price: Double) {
        let key = symbol.uppercased()
        guard liveStocks[key] == nil, price > 0 else { return }

        liveStocks[key] = StockAsset(
            symbol:       key,
            name:         name,
            currentPrice: price,
            prevPrice:    price * 0.99
        )
    }

    // MARK: Default stock catalogue

    private static func buildDefaultStocks() -> [String: StockAsset] {
        return [
            "AAPL": StockAsset(
                symbol: "AAPL", name: "Apple Inc.",
                currentPrice: 175.50, prevPrice: 173.20
            ),
            "NVDA": StockAsset(
                symbol: "NVDA", name: "NVIDIA Corp.",
                currentPrice: 102.50, prevPrice: 99.80
            ),
            "TSLA": StockAsset(
                symbol: "TSLA", name: "Tesla Inc.",
                currentPrice: 113.44, prevPrice: 115.10
            ),
            "MSFT": StockAsset(
                symbol: "MSFT", name: "Microsoft Corp.",
                currentPrice: 415.20, prevPrice: 412.50
            ),
            "AMZN": StockAsset(
                symbol: "AMZN", name: "Amazon.com Inc.",
                currentPrice: 178.40, prevPrice: 179.10
            ),
            "SAP": StockAsset(
                symbol: "SAP", name: "SAP SE",
                currentPrice: 168.10, prevPrice: 165.40
            )
        ]
    }
}
