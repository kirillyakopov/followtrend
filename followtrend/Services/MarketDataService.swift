//
//  MarketDataService.swift
//  followtrend
//
//  Fetches stock candles and live quotes from Finnhub.
//  Falls back to mock data when APIConfig.finnhubKey is empty.
//
//  Correct timeframe → Finnhub resolution mapping:
//  1D  → 1 min  (intraday candles for last trading session)
//  1W  → 15 min
//  1M  → 60 min (1 hour)
//  1Y  → D      (daily)
//  Max → W      (weekly)
//

import Foundation

// MARK: - Finnhub response shapes

private struct FinnhubCandleResponse: Decodable {
    let s: String        // "ok" or "no_data"
    let c: [Double]?     // close prices
    let o: [Double]?     // open
    let h: [Double]?     // high
    let l: [Double]?     // low
    let v: [Double]?     // volume
    let t: [Int]?        // unix timestamps
}

private struct FinnhubQuoteResponse: Decodable {
    let c:  Double    // current price
    let d:  Double?   // change
    let dp: Double?   // percent change
    let h:  Double?   // high
    let l:  Double?   // low
    let o:  Double?   // open
    let pc: Double?   // prev close
}

private struct FinnhubSearchResponse: Decodable {
    let count: Int
    let result: [FinnhubMatch]
}

private struct FinnhubMatch: Decodable {
    let description:   String
    let displaySymbol: String
    let symbol:        String
    let type:          String
}

// MARK: - Cache entry

private struct CacheEntry {
    let points:    [ChartPoint]
    let expiresAt: Date
}

// MARK: - Market Data Service

@MainActor
final class MarketDataService {
    static let shared = MarketDataService()

    private let net = NetworkService.shared
    private var cache: [String: CacheEntry] = [:]

    private init() {}

    private func getProxyURL(path: String, params: [String: String]) -> URL? {
        var components = URLComponents(string: APIConfig.proxyBaseURL + path)
        components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components?.url
    }

    // MARK: - Live quote (current price)

    func fetchQuote(symbol: String) async throws -> Double {
        guard let url = getProxyURL(path: "/api/stock/quote", params: ["symbol": symbol.uppercased()]) else {
            return StockMarketService.shared.getCurrentPrice(for: symbol)
        }

        do {
            let response: FinnhubQuoteResponse = try await net.fetch(url)
            return response.c > 0 ? response.c : StockMarketService.shared.getCurrentPrice(for: symbol)
        } catch {
            return StockMarketService.shared.getCurrentPrice(for: symbol)
        }
    }

    // MARK: - Candles (OHLC)

    func fetchCandles(symbol: String, timeframe: Timeframe) async throws -> [ChartPoint] {
        let cacheKey = "\(symbol)_\(timeframe.rawValue)"

        if let entry = cache[cacheKey], entry.expiresAt > Date() {
            return entry.points
        }

        let range: String
        let interval: String
        
        switch timeframe {
        case .oneDay:
            range = "5d"
            interval = "5m"
        case .oneWeek:
            range = "1mo"
            interval = "15m"
        case .oneMonth:
            range = "3mo"
            interval = "1d"
        case .oneYear:
            range = "1y"
            interval = "1d"
        case .max:
            range = "max"
            interval = "1wk"
        }

        guard let url = getProxyURL(
            path: "/api/stock/candles",
            params: [
                "symbol": symbol.uppercased(),
                "range": range,
                "interval": interval
            ]
        ) else { return [] }

        do {
            let response: FinnhubCandleResponse = try await net.fetch(url)

            guard response.s == "ok",
                  let closes = response.c,
                  let times  = response.t,
                  !closes.isEmpty else {
                return [] // Market closed or no data
            }

            let points: [ChartPoint] = zip(times, closes).enumerated().map { (i, pair) in
                let (ts, close) = pair
                return ChartPoint(
                    timestamp: Date(timeIntervalSince1970: Double(ts)),
                    close: close,
                    open:   response.o?[safe: i],
                    high:   response.h?[safe: i],
                    low:    response.l?[safe: i],
                    volume: response.v?[safe: i]
                )
            }

            // Cache TTL: 1 min for intraday, 5 min for longer frames
            let ttl: TimeInterval = (timeframe == .oneDay || timeframe == .oneWeek) ? 60 : 300
            cache[cacheKey] = CacheEntry(points: points, expiresAt: Date().addingTimeInterval(ttl))
            return points
        } catch {
            print("Proxy error for \(symbol): \(error)")
            return []
        }
    }

    // MARK: - Symbol search

    func searchSymbols(query: String) async throws -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        // Fall back to pure local search since yfinance symbol search isn't implemented
        return localSearch(query)
    }

    // MARK: - Local catalogue fallback

    private func localSearch(_ query: String) -> [SearchResult] {
        let q = query.lowercased()
        var results = localCatalogue.filter {
            $0.symbol.lowercased().hasPrefix(q) || $0.name.lowercased().contains(q)
        }
        
        // If the exact symbol isn't in our results, allow them to add it directly.
        if !results.contains(where: { $0.symbol.lowercased() == q }) {
            results.insert(SearchResult(symbol: query.uppercased(), name: "Custom Ticker (\(query.uppercased()))", kind: .stock, coinId: nil), at: 0)
        }
        
        return results
    }

    private let localCatalogue: [SearchResult] = [
        SearchResult(symbol: "AAPL",  name: "Apple Inc.",           kind: .stock,  coinId: nil),
        SearchResult(symbol: "NVDA",  name: "NVIDIA Corp.",         kind: .stock,  coinId: nil),
        SearchResult(symbol: "MSFT",  name: "Microsoft Corp.",      kind: .stock,  coinId: nil),
        SearchResult(symbol: "TSLA",  name: "Tesla Inc.",           kind: .stock,  coinId: nil),
        SearchResult(symbol: "AMZN",  name: "Amazon.com Inc.",      kind: .stock,  coinId: nil),
        SearchResult(symbol: "GOOGL", name: "Alphabet Inc.",        kind: .stock,  coinId: nil),
        SearchResult(symbol: "META",  name: "Meta Platforms",       kind: .stock,  coinId: nil),
        SearchResult(symbol: "SAP",   name: "SAP SE",               kind: .stock,  coinId: nil),
        SearchResult(symbol: "NFLX",  name: "Netflix Inc.",         kind: .stock,  coinId: nil),
        SearchResult(symbol: "SPY",   name: "S&P 500 ETF (SPY)",    kind: .etf,    coinId: nil),
        SearchResult(symbol: "QQQ",   name: "Nasdaq-100 ETF (QQQ)", kind: .etf,    coinId: nil),
        SearchResult(symbol: "VUSA",  name: "Vanguard S&P 500 ETF", kind: .etf,    coinId: nil),
        SearchResult(symbol: "IWDA",  name: "iShares Core MSCI World", kind: .etf, coinId: nil),
        SearchResult(symbol: "BTC",   name: "Bitcoin",              kind: .crypto, coinId: "bitcoin"),
        SearchResult(symbol: "ETH",   name: "Ethereum",             kind: .crypto, coinId: "ethereum"),
        SearchResult(symbol: "SOL",   name: "Solana",               kind: .crypto, coinId: "solana"),
        SearchResult(symbol: "BNB",   name: "BNB",                  kind: .crypto, coinId: "binancecoin"),
        SearchResult(symbol: "XRP",   name: "XRP",                  kind: .crypto, coinId: "ripple"),
    ]
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
