//
//  ImportTickerResolver.swift
//  followtrend
//
//  Resolves a pasted ticker against the real market APIs (Yahoo for stocks,
//  CoinGecko for coins). Lives apart from PortfolioImportParser so the parser
//  stays pure Foundation logic — no network, directly testable.
//

import Foundation

// MARK: - Ticker resolution (stock vs. crypto, with disambiguation)

/// One concrete asset a pasted ticker could refer to. `coinId == nil` means a
/// stock/ETF (validated via Yahoo); a non-nil `coinId` is a CoinGecko coin.
struct ImportCandidate: Identifiable, Equatable {
    let id: String          // stable, unique: coinId for crypto, "stock:SYM" for stocks
    let symbol: String
    let name: String
    let coinId: String?
}

/// The verdict for a single symbol. `.crypto`/`.stock` auto-resolve; `.ambiguous`
/// needs the user to pick; `.unverified` means the lookup couldn't be completed.
enum ImportResolution: Equatable {
    case stock
    case crypto(ImportCandidate)
    case ambiguous([ImportCandidate])
    case notFound
    case unverified
}

/// Resolves pasted tickers against the real stock + crypto APIs, returning the
/// list of plausible matches so the UI can disambiguate. Memoised per symbol
/// for the app session so re-parsing / typing doesn't hammer CoinGecko.
@MainActor
enum ImportTickerResolver {
    /// Definitive verdicts only (`.unverified` is never cached so a retry can
    /// succeed once connectivity / rate limits recover).
    private static var memo: [String: ImportResolution] = [:]

    static func resolve(symbol: String) async -> ImportResolution {
        let sym = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        guard !sym.isEmpty else { return .notFound }
        if let cached = memo[sym] { return cached }

        // a. Hardcoded known crypto → resolve with no network calls.
        if let coinId = PortfolioImportParser.knownCrypto[sym] {
            let res = ImportResolution.crypto(
                ImportCandidate(id: coinId, symbol: sym, name: sym, coinId: coinId))
            memo[sym] = res
            return res
        }

        // b. Concurrent stock existence + crypto search.
        async let stockLookup = MarketDataService.shared.symbolExists(symbol: sym, coinId: nil)
        async let coinLookup  = CryptoDataService.shared.resolveCoins(query: sym)
        let (stockExists, coins) = await (stockLookup, coinLookup)

        // c. Crypto candidates: exact symbol matches (cap 5), else fuzzy top 3.
        var cryptoCandidates: [ImportCandidate] = []
        let cryptoErrored = (coins == nil)
        if let coins {
            let exact = coins.filter { $0.symbol.uppercased() == sym }
            let chosen: [SearchResult]
            if !exact.isEmpty {
                chosen = Array(exact.prefix(5))
            } else if !coins.isEmpty {
                chosen = Array(coins.prefix(3))          // "did you mean?"
            } else {
                chosen = []
            }
            cryptoCandidates = chosen.map {
                ImportCandidate(
                    id: $0.coinId ?? "coin:\($0.symbol)",
                    symbol: $0.symbol.uppercased(),
                    name: $0.name,
                    coinId: $0.coinId)
            }
        }

        // d. Assemble candidates: stock (if Yahoo said yes) + crypto matches.
        var candidates: [ImportCandidate] = []
        if stockExists == true {
            candidates.append(ImportCandidate(id: "stock:\(sym)", symbol: sym, name: sym, coinId: nil))
        }
        candidates.append(contentsOf: cryptoCandidates)

        let stockErrored = (stockExists == nil)

        let res: ImportResolution
        if candidates.isEmpty {
            res = (stockErrored || cryptoErrored) ? .unverified : .notFound
        } else if candidates.count == 1, candidates[0].symbol == sym {
            // Auto-resolve ONLY on an exact ticker match. A lone *fuzzy* suggestion
            // (symbol != typed ticker) must never silently become the imported
            // asset — the user has to pick it deliberately.
            let only = candidates[0]
            res = only.coinId == nil ? .stock : .crypto(only)
        } else {
            res = .ambiguous(candidates)
        }

        if res != .unverified { memo[sym] = res }   // don't cache transient failures
        return res
    }
}
