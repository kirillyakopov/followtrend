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

// MARK: - Yahoo Finance response shapes

private struct YahooChartResponse: Decodable {
    let chart: YahooChart
}

private struct YahooChart: Decodable {
    let result: [YahooResult]?
}

private struct YahooResult: Decodable {
    let meta: YahooMeta
    let timestamp: [Int]?
    let indicators: YahooIndicators?
}

private struct YahooMeta: Decodable {
    let regularMarketPrice: Double?
}

private struct YahooIndicators: Decodable {
    let quote: [YahooQuote]?
}

private struct YahooQuote: Decodable {
    let close: [Double?]?
    let open: [Double?]?
    let high: [Double?]?
    let low: [Double?]?
    let volume: [Double?]?
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

    /// Symbols we remap to Yahoo's "-USD" crypto pair.
    static let cryptoPairSymbols: Set<String> = ["BTC", "ETH", "SOL", "ADA", "XRP", "DOGE", "BNB", "AVAX", "DOT", "MATIC"]

    /// Existence checks are memoised for the app session (symbols don't stop existing).
    private var existenceCache: [String: Bool] = [:]

    private init() {}

    private func getProxyURL(path: String, params: [String: String]) -> URL? {
        var components = URLComponents(string: APIConfig.proxyBaseURL + path)
        components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components?.url
    }

    // MARK: - Live quote (current price)

    func fetchQuote(symbol: String) async throws -> Double {
        let yfSymbol = ["BTC", "ETH", "SOL", "ADA", "XRP", "DOGE", "BNB", "AVAX", "DOT", "MATIC"].contains(symbol.uppercased()) ? "\(symbol.uppercased())-USD" : symbol.uppercased()
        
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(yfSymbol)?range=1d&interval=1d") else {
            return StockMarketService.shared.getCurrentPrice(for: symbol)
        }

        do {
            let response: YahooChartResponse = try await net.fetch(url)
            if let price = response.chart.result?.first?.meta.regularMarketPrice, price > 0 {
                return price
            }
            return StockMarketService.shared.getCurrentPrice(for: symbol)
        } catch {
            return StockMarketService.shared.getCurrentPrice(for: symbol)
        }
    }

    // MARK: - Symbol existence (portfolio import validation)

    /// Definitive existence check used by portfolio import.
    /// - Returns `true` if a real quote exists, `false` if the provider says the
    ///   symbol is unknown, and `nil` if it can't be determined (offline / rate
    ///   limited) so callers can treat it as *unverified* rather than *not found*.
    func symbolExists(symbol: String, coinId: String?) async -> Bool? {
        let sym = symbol.uppercased()
        if coinId != nil { return true }                 // already resolved to a known crypto id
        if let cached = existenceCache[sym] { return cached }

        let yfSymbol = Self.cryptoPairSymbols.contains(sym) ? "\(sym)-USD" : sym
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(yfSymbol)?range=5d&interval=1d") else { return nil }

        do {
            let response: YahooChartResponse = try await net.fetch(url)
            let exists = (response.chart.result?.first?.meta.regularMarketPrice ?? 0) > 0
            existenceCache[sym] = exists
            return exists
        } catch {
            if case NetworkError.httpError(let code) = error, code == 404 {
                existenceCache[sym] = false
                return false
            }
            return nil   // network / rate-limit / decode → unverified, don't accuse
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

        let yfSymbol = ["BTC", "ETH", "SOL", "ADA", "XRP", "DOGE", "BNB", "AVAX", "DOT", "MATIC"].contains(symbol.uppercased()) ? "\(symbol.uppercased())-USD" : symbol.uppercased()

        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(yfSymbol)?range=\(range)&interval=\(interval)") else { return [] }

        do {
            let response: YahooChartResponse = try await net.fetch(url)
            
            guard let result = response.chart.result?.first,
                  let timestamps = result.timestamp,
                  let quote = result.indicators?.quote?.first else {
                return []
            }
            
            let closes = quote.close ?? []
            let opens = quote.open ?? []
            let highs = quote.high ?? []
            let lows = quote.low ?? []
            let volumes = quote.volume ?? []

            var points: [ChartPoint] = []
            
            for i in 0..<min(timestamps.count, closes.count) {
                guard let close = closes[i] else { continue }
                
                let pt = ChartPoint(
                    timestamp: Date(timeIntervalSince1970: Double(timestamps[i])),
                    close: close,
                    open: opens[safe: i] ?? nil,
                    high: highs[safe: i] ?? nil,
                    low: lows[safe: i] ?? nil,
                    volume: volumes[safe: i] ?? nil
                )
                points.append(pt)
            }

            let ttl: TimeInterval = (timeframe == .oneDay || timeframe == .oneWeek) ? 60 : 300
            cache[cacheKey] = CacheEntry(points: points, expiresAt: Date().addingTimeInterval(ttl))
            return points
        } catch {
            print("Yahoo error for \(symbol): \(error)")
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
