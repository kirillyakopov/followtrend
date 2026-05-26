//
//  CryptoDataService.swift
//  followtrend
//
//  Fetches crypto price history and search from CoinGecko.
//  No API key required for the free /v3 endpoints.
//

import Foundation

// MARK: - CoinGecko response shapes

private struct CoinGeckoMarketChart: Decodable {
    let prices: [[Double]]   // [[timestamp_ms, price], ...]
}

private struct CoinGeckoSearchResponse: Decodable {
    let coins: [CoinGeckoSearchCoin]
}

private struct CoinGeckoSearchCoin: Decodable {
    let id:     String
    let symbol: String
    let name:   String
}

private struct CoinGeckoCoinDetail: Decodable {
    let id:     String
    let symbol: String
    let name:   String
    struct MarketData: Decodable {
        struct PriceMap: Decodable { let eur: Double? }
        let current_price: PriceMap
    }
    let market_data: MarketData
}

// MARK: - Cache entry

private struct CacheEntry {
    let points:    [ChartPoint]
    let expiresAt: Date
}

// MARK: - Crypto Data Service

@MainActor
final class CryptoDataService {
    static let shared = CryptoDataService()

    private let net = NetworkService.shared
    private var cache: [String: CacheEntry] = [:]

    private init() {}

    // MARK: - Market chart

    func fetchCandles(coinId: String, timeframe: Timeframe) async throws -> [ChartPoint] {
        let cacheKey = "crypto_\(coinId)_\(timeframe.rawValue)"

        if let entry = cache[cacheKey], entry.expiresAt > Date() {
            return entry.points
        }

        guard let url = URL(string: "\(APIConfig.proxyBaseURL)/api/candles?coinId=\(coinId)&days=\(timeframe.coinGeckoDays)") else {
            return []
        }

        do {
            let response: CoinGeckoMarketChart = try await net.fetch(url)

            guard !response.prices.isEmpty else {
                return []
            }

            let points: [ChartPoint] = response.prices.compactMap { pair in
                guard pair.count >= 2 else { return nil }
                return ChartPoint(
                    timestamp: Date(timeIntervalSince1970: pair[0] / 1000),
                    close: pair[1]
                )
            }

            let ttl: TimeInterval = timeframe == .oneDay ? 60 : 300
            cache[cacheKey] = CacheEntry(points: points, expiresAt: Date().addingTimeInterval(ttl))
            return points
        } catch {
            print("Crypto proxy chart error: \(error)")
            return []
        }
    }

    // MARK: - Current price

    func currentPrice(coinId: String) async throws -> Double {
        // Use local caching proxy to prevent rate limits
        guard let url = URL(string: "\(APIConfig.proxyBaseURL)/api/prices?ids=\(coinId)") else {
            return 0.0
        }

        do {
            // Response format from proxy: {"bitcoin":{"eur":45000.0, "usd": ...}}
            let raw = try await net.fetch(url) as [String: [String: Double]]
            return raw[coinId]?["eur"] ?? 0.0
        } catch {
            print("Proxy fetch failed: \(error)")
            return 0.0
        }
    }

    // MARK: - Search

    func searchCoins(query: String) async throws -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        guard let url = net.makeURL(
            base: APIConfig.coinGeckoBaseURL,
            path: "/search",
            params: ["query": query]
        ) else { return [] }

        do {
            let response: CoinGeckoSearchResponse = try await net.fetch(url)
            return response.coins.prefix(5).map { coin in
                SearchResult(
                    symbol: coin.symbol.uppercased(),
                    name:   coin.name,
                    kind:   .crypto,
                    coinId: coin.id
                )
            }
        } catch {
            return [] // Fail silently to empty array, allowing other search providers to show results
        }
    }

    // Removed mock fallbacks
}
