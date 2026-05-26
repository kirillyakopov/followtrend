//
//  RiskAnalyticsService.swift
//  followtrend
//
//  Computes pairwise Pearson correlation coefficients from 90-day daily log
//  returns for every active (non-watchlist) portfolio asset.
//
//  All heavy computation is offloaded to a background task via a dedicated
//  actor so the main thread is never blocked.
//

import Foundation

// MARK: - Asset Pair (hashable, order-independent key)

nonisolated struct AssetPair: Hashable, Equatable, Sendable {
    let symbolA: String
    let symbolB: String

    init(_ a: String, _ b: String) {
        // Canonical order so (A,B) == (B,A)
        if a <= b { symbolA = a; symbolB = b }
        else       { symbolA = b; symbolB = a }
    }
}

// MARK: - Risk Analytics Actor (runs entirely off the main thread)

actor RiskAnalyticsService {

    static let shared = RiskAnalyticsService()

    // 90-day window fetched as daily data via yfinance proxy (3mo/1d)
    private let correlationTimeframe: Timeframe = .oneMonth   // closest supported: "3mo"/"1d"

    // MARK: - Public entry point

    /// Fetch 90-day daily candles for every active asset, align the return
    /// series by calendar date, and return a fully-populated correlation matrix.
    func computeCorrelations(
        for investments: [Investment]
    ) async -> [AssetPair: Double] {

        let active = investments.filter {
            !$0.isWatchlist && !StablecoinClassifier.isStablecoin(symbol: $0.symbol, name: $0.name)
        }
        guard active.count >= 2 else { return [:] }

        // ── 1. Fetch price histories concurrently ────────────────────────────
        var returnSeries: [String: [Date: Double]] = [:]

        await withTaskGroup(of: (String, [Date: Double]).self) { group in
            for inv in active {
                group.addTask {
                    let series = await Self.fetchLogReturns(for: inv)
                    return (inv.symbol, series)
                }
            }
            for await (symbol, series) in group {
                if !series.isEmpty {
                    returnSeries[symbol] = series
                }
            }
        }

        guard returnSeries.count >= 2 else { return [:] }

        // ── 2. Compute pairwise Pearson r ────────────────────────────────────
        let symbols = Array(returnSeries.keys)
        var matrix: [AssetPair: Double] = [:]

        for i in 0 ..< symbols.count {
            for j in (i + 1) ..< symbols.count {
                let symA = symbols[i]
                let symB = symbols[j]
                guard
                    let seriesA = returnSeries[symA],
                    let seriesB = returnSeries[symB]
                else { continue }

                let r = pearson(seriesA, seriesB)
                matrix[AssetPair(symA, symB)] = r
            }
        }

        return matrix
    }

    /// Computes per-symbol daily-return volatility for active portfolio assets.
    /// Watchlist assets are intentionally excluded from this risk signal.
    func computeVolatility(
        for investments: [Investment]
    ) async -> [String: Double] {
        let active = investments.filter {
            !$0.isWatchlist && !StablecoinClassifier.isStablecoin(symbol: $0.symbol, name: $0.name)
        }
        guard !active.isEmpty else { return [:] }

        var volatilityBySymbol: [String: Double] = [:]

        await withTaskGroup(of: (String, Double?).self) { group in
            for inv in active {
                group.addTask {
                    let series = await Self.fetchLogReturns(for: inv)
                    let values = Array(series.values)
                    return (inv.symbol, Self.standardDeviation(values))
                }
            }

            for await (symbol, volatility) in group {
                if let volatility {
                    volatilityBySymbol[symbol] = volatility
                }
            }
        }

        return volatilityBySymbol
    }

    // MARK: - Log-return fetcher

    /// Returns a date-keyed dictionary of daily log returns for one asset.
    /// Dates are normalised to midnight UTC to allow cross-asset intersection.
    private static func fetchLogReturns(for inv: Investment) async -> [Date: Double] {
        do {
            let points: [ChartPoint]
            if let coinId = inv.coinId {
                points = try await CryptoDataService.shared.fetchCandles(
                    coinId: coinId,
                    timeframe: .oneMonth          // yfinance backend returns 3mo/1d
                )
            } else {
                points = try await MarketDataService.shared.fetchCandles(
                    symbol: inv.symbol,
                    timeframe: .oneMonth
                )
            }
            return logReturns(from: points)
        } catch {
            return [:]
        }
    }

    // MARK: - Log-return computation

    /// Converts a chronologically ordered array of ChartPoints into date-keyed
    /// daily log returns:  R_t = ln(P_t / P_{t-1})
    private static func logReturns(from points: [ChartPoint]) -> [Date: Double] {
        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else { return [:] }

        let calendar = Calendar(identifier: .iso8601)
        var result: [Date: Double] = [:]
        result.reserveCapacity(sorted.count)

        for i in 1 ..< sorted.count {
            let prev = sorted[i - 1].close
            let curr = sorted[i].close
            guard prev > 0, curr > 0 else { continue }

            // Normalise timestamp to start of day (UTC) for date-intersection
            let day = calendar.startOfDay(for: sorted[i].timestamp)
            result[day] = log(curr / prev)
        }
        return result
    }

    private static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2 else { return nil }

        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values
            .map { pow($0 - mean, 2) }
            .reduce(0, +) / Double(values.count)

        return variance.squareRoot()
    }

    // MARK: - Pearson r

    /// Intersects two date-keyed return series and computes the Pearson
    /// correlation coefficient over the aligned observations.
    private func pearson(
        _ a: [Date: Double],
        _ b: [Date: Double]
    ) -> Double {
        // Intersection of dates present in both series
        let commonDates = Set(a.keys).intersection(b.keys).sorted()
        let n = commonDates.count
        guard n >= 5 else { return 0 }   // too few points → undefined

        let xs: [Double] = commonDates.map { a[$0]! }
        let ys: [Double] = commonDates.map { b[$0]! }

        let meanX = xs.reduce(0, +) / Double(n)
        let meanY = ys.reduce(0, +) / Double(n)

        var sumCov:  Double = 0
        var sumVarX: Double = 0
        var sumVarY: Double = 0

        for i in 0 ..< n {
            let dx = xs[i] - meanX
            let dy = ys[i] - meanY
            sumCov  += dx * dy
            sumVarX += dx * dx
            sumVarY += dy * dy
        }

        let denom = (sumVarX * sumVarY).squareRoot()
        guard denom > 0 else { return 0 }

        // Clamp to [-1, 1] to guard against floating-point drift
        return min(1.0, max(-1.0, sumCov / denom))
    }

}
