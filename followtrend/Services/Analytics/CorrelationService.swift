//
//  CorrelationService.swift
//  followtrend
//
//  Dedicated actor for calculating Pearson correlation coefficient between the
//  daily returns of the portfolio and a benchmark index (e.g. S&P 500 "^GSPC").
//

import Foundation

actor CorrelationService {
    static let shared = CorrelationService()

    private init() {}

    // MARK: - Pearson Math

    /// Calculates Pearson correlation coefficient between two raw arrays of Doubles.
    func pearson(x: [Double], y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 2 else {
            print("CorrelationService [Warning]: Aligned datasets have mismatched or insufficient lengths (x: \(x.count), y: \(y.count)).")
            return nil
        }

        let n = Double(x.count)
        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n

        let varX = x.map { pow($0 - meanX, 2) }.reduce(0, +)
        let varY = y.map { pow($0 - meanY, 2) }.reduce(0, +)

        let stdDevX = (varX / n).squareRoot()
        let stdDevY = (varY / n).squareRoot()

        // Guard against zero variance / division by zero
        guard stdDevX > 0 && stdDevY > 0 else {
            print("CorrelationService [Warning]: Standard deviation of returns is zero (X stddev: \(stdDevX), Y stddev: \(stdDevY)).")
            return nil
        }

        // Covariance = E[(X - μX)(Y - μY)]
        var covariance: Double = 0
        for i in 0..<x.count {
            covariance += (x[i] - meanX) * (y[i] - meanY)
        }
        covariance = covariance / n

        let r = covariance / (stdDevX * stdDevY)

        // Detailed Logging
        print("--- CorrelationService Calculation Debug Details ---")
        print("Aligned observations count (N): \(x.count)")
        print("Aligned array X (Portfolio Returns): \(x.map { String(format: "%.5f", $0) })")
        print("Aligned array Y (Benchmark Returns): \(y.map { String(format: "%.5f", $0) })")
        print("Mean X: \(meanX), Mean Y: \(meanY)")
        print("StdDev X: \(stdDevX), StdDev Y: \(stdDevY)")
        print("Calculated Covariance: \(covariance)")
        print("Calculated Pearson r: \(r)")
        print("-----------------------------------------------------")

        // Range Validation: -1.0 <= r <= 1.0 (with slight threshold for float precision)
        if r < -1.0001 || r > 1.0001 {
            print("CorrelationService [Error]: Pearson coefficient is out of bounds: \(r)")
            return nil
        }

        return min(1.0, max(-1.0, r))
    }

    // MARK: - Self Test Suite

    /// Verifies the correctness of the Pearson correlation formula against known test cases.
    func runSelfTests() -> Bool {
        print("CorrelationService [Self-Test]: Running validation suite...")

        // Test Case 1: Perfect Positive Correlation
        let x1 = [1.0, 2.0, 3.0, 4.0]
        let y1 = [2.0, 4.0, 6.0, 8.0] // y = 2x
        guard let r1 = pearson(x: x1, y: y1), abs(r1 - 1.0) < 0.0001 else {
            print("CorrelationService [Self-Test Failed]: Perfect positive correlation test failed.")
            return false
        }

        // Test Case 2: Perfect Negative Correlation
        let x2 = [1.0, 2.0, 3.0, 4.0]
        let y2 = [8.0, 6.0, 4.0, 2.0] // y = -2x + 10
        guard let r2 = pearson(x: x2, y: y2), abs(r2 - (-1.0)) < 0.0001 else {
            print("CorrelationService [Self-Test Failed]: Perfect negative correlation test failed.")
            return false
        }

        // Test Case 3: Zero Correlation (Orthogonal variation)
        let x3 = [1.0, 2.0, 3.0, 4.0]
        let y3 = [1.0, -1.0, 1.0, -1.0]
        let r3 = pearson(x: x3, y: y3)
        guard let r3Value = r3, abs(r3Value) < 0.1 else {
            print("CorrelationService [Self-Test Failed]: Zero correlation test failed (got \(String(describing: r3))).")
            return false
        }

        print("CorrelationService [Self-Test Passed]: All calculations validated successfully.")
        return true
    }

    // MARK: - Public API

    /// Computes the Pearson correlation coefficient between portfolio returns and benchmark returns.
    func computePortfolioCorrelation(
        for investments: [Investment],
        cashBalance: Double,
        benchmarkSymbol: String = "^GSPC"
    ) async -> Double? {
        // Run self tests to ensure math safety
        _ = runSelfTests()

        let active = investments.filter { !$0.isWatchlist }
        guard !active.isEmpty else {
            print("CorrelationService [Info]: No active investments in portfolio.")
            return nil
        }

        // 1. Fetch price histories for active assets and the benchmark index
        var assetCandles: [String: [Date: Double]] = [:]

        await withTaskGroup(of: (String, [Date: Double]).self) { group in
            // Active assets
            for inv in active {
                group.addTask {
                    let series = await Self.fetchDailyClosePrices(for: inv)
                    return (inv.symbol, series)
                }
            }
            // Benchmark index
            group.addTask {
                let series = await Self.fetchDailyClosePricesForSymbol(benchmarkSymbol)
                return (benchmarkSymbol, series)
            }

            for await (symbol, series) in group {
                if !series.isEmpty {
                    assetCandles[symbol] = series
                }
            }
        }

        // Ensure benchmark index prices are fetched
        guard let benchmarkPrices = assetCandles[benchmarkSymbol] else {
            print("CorrelationService [Warning]: Failed to fetch benchmark prices for \(benchmarkSymbol).")
            return nil
        }

        // Data Alignment Check: Ensure sufficient timestamps
        let sortedDates = benchmarkPrices.keys.sorted()
        guard sortedDates.count >= 5 else {
            print("CorrelationService [Warning]: Insufficient benchmark data points (\(sortedDates.count) < 5).")
            return nil
        }

        // 2. Compute daily portfolio total value aligning with index dates
        var portfolioValues: [Date: Double] = [:]
        for date in sortedDates {
            var totalValue = cashBalance
            for inv in active {
                guard let prices = assetCandles[inv.symbol] else { continue }

                // Forward filling: Find closest price on or before the trading date
                if let closest = prices.filter({ $0.key <= date }).max(by: { $0.key < $1.key }) {
                    totalValue += closest.value * inv.shares
                } else if let first = prices.keys.min(), let firstVal = prices[first] {
                    totalValue += firstVal * inv.shares
                }
            }
            portfolioValues[date] = totalValue
        }

        // 3. Compute daily log returns: ln(P_t / P_t-1)
        var portReturns: [Date: Double] = [:]
        var benchReturns: [Date: Double] = [:]

        for i in 1 ..< sortedDates.count {
            let prevDate = sortedDates[i - 1]
            let currDate = sortedDates[i]

            let prevPortVal = portfolioValues[prevDate] ?? 0
            let currPortVal = portfolioValues[currDate] ?? 0
            let prevBenchVal = benchmarkPrices[prevDate] ?? 0
            let currBenchVal = benchmarkPrices[currDate] ?? 0

            if prevPortVal > 0 && currPortVal > 0 {
                portReturns[currDate] = log(currPortVal / prevPortVal)
            }
            if prevBenchVal > 0 && currBenchVal > 0 {
                benchReturns[currDate] = log(currBenchVal / prevBenchVal)
            }
        }

        // 4. Align return series on matching dates
        let commonDates = Set(portReturns.keys).intersection(benchReturns.keys).sorted()
        guard commonDates.count >= 5 else {
            print("CorrelationService [Warning]: Insufficient aligned return points (\(commonDates.count) < 5).")
            return nil
        }

        let xs = commonDates.map { portReturns[$0]! }
        let ys = commonDates.map { benchReturns[$0]! }

        return pearson(x: xs, y: ys)
    }

    // MARK: - Price Fetching Helpers

    private static func fetchDailyClosePrices(for inv: Investment) async -> [Date: Double] {
        do {
            let points: [ChartPoint]
            if let coinId = inv.coinId {
                points = try await CryptoDataService.shared.fetchCandles(
                    coinId: coinId,
                    timeframe: .oneMonth
                )
            } else {
                points = try await MarketDataService.shared.fetchCandles(
                    symbol: inv.symbol,
                    timeframe: .oneMonth
                )
            }
            return normalisePrices(from: points)
        } catch {
            return [:]
        }
    }

    private static func fetchDailyClosePricesForSymbol(_ symbol: String) async -> [Date: Double] {
        do {
            let points = try await MarketDataService.shared.fetchCandles(
                symbol: symbol,
                timeframe: .oneMonth
            )
            return normalisePrices(from: points)
        } catch {
            return [:]
        }
    }

    private static func normalisePrices(from points: [ChartPoint]) -> [Date: Double] {
        let calendar = Calendar(identifier: .iso8601)
        var result: [Date: Double] = [:]
        for pt in points {
            let day = calendar.startOfDay(for: pt.timestamp)
            result[day] = pt.close
        }
        return result
    }
}
