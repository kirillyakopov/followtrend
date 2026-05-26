//
//  MarketSearchViewModel.swift
//  followtrend
//
//  Dedicated VM for the Add Position market search.
//  Searches stocks (Finnhub) + ETFs + crypto (CoinGecko) in parallel.
//  Fetches live current price when a result is selected.
//

import SwiftUI
import Combine

// MARK: - Market Search Result with live price

struct MarketSearchResult: Identifiable, Hashable {
    let id       = UUID()
    let symbol:  String
    let name:    String
    let kind:    AssetKind
    let coinId:  String?     // CoinGecko id for crypto
    var livePrice: Double?   // fetched on selection

    func hash(into hasher: inout Hasher) { hasher.combine(symbol) }
    static func == (lhs: MarketSearchResult, rhs: MarketSearchResult) -> Bool { lhs.symbol == rhs.symbol }
}

// MARK: - Market Scope Enum

enum MarketScope: Hashable {
    case stocks
    case etfs
    case crypto
}

// MARK: - Market Search ViewModel

@MainActor
final class MarketSearchViewModel: ObservableObject {

    @Published var query:          String = ""
    @Published var selectedScope:  MarketScope = .stocks
    @Published var results:        [MarketSearchResult] = []
    @Published var isSearching:    Bool = false
    @Published var isFetchingPrice: Bool = false
    @Published var selectedResult: MarketSearchResult?
    @Published var fetchedPrice:   Double?

    private let stockService  = MarketDataService.shared
    private let cryptoService = CryptoDataService.shared
    private var cancellables  = Set<AnyCancellable>()
    private var searchTask:   Task<Void, Never>?
    private var priceTask:    Task<Void, Never>?

    init() {
        Publishers.CombineLatest($query, $selectedScope)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1
            }
            .sink { [weak self] q, scope in
                self?.performSearch(q, scope: scope)
            }
            .store(in: &cancellables)
    }

    // MARK: - Search

    private func performSearch(_ q: String, scope: MarketScope) {
        searchTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true

        searchTask = Task {
            let stocks: [SearchResult]
            let cryptos: [SearchResult]

            switch scope {
            case .stocks, .etfs:
                stocks = (try? await stockService.searchSymbols(query: trimmed)) ?? []
                cryptos = []
            case .crypto:
                stocks = []
                cryptos = (try? await cryptoService.searchCoins(query: trimmed)) ?? []
            }

            guard !Task.isCancelled else { return }

            // Convert SearchResult → MarketSearchResult, filter & deduplicate
            var seen = Set<String>()
            var merged: [MarketSearchResult] = []
            for r in (stocks + cryptos) where !seen.contains(r.symbol) {
                let kindMatches: Bool
                switch scope {
                case .stocks:
                    kindMatches = (r.kind == .stock)
                case .etfs:
                    kindMatches = (r.kind == .etf)
                case .crypto:
                    kindMatches = (r.kind == .crypto)
                }

                if kindMatches {
                    merged.append(MarketSearchResult(
                        symbol: r.symbol,
                        name:   r.name,
                        kind:   r.kind,
                        coinId: r.coinId
                    ))
                    seen.insert(r.symbol)
                }
            }

            self.results    = merged
            self.isSearching = false
        }
    }

    // MARK: - Select result + fetch live price

    func select(_ result: MarketSearchResult) {
        priceTask?.cancel()
        selectedResult = result
        fetchedPrice   = nil
        isFetchingPrice = true

        priceTask = Task {
            do {
                let price: Double
                if let coinId = result.coinId {
                    price = try await cryptoService.currentPrice(coinId: coinId)
                } else {
                    // Fetch live quote from Finnhub
                    price = try await stockService.fetchQuote(symbol: result.symbol)
                }
                guard !Task.isCancelled else { return }
                self.fetchedPrice    = price > 0 ? price : nil
                self.isFetchingPrice = false
            } catch {
                self.isFetchingPrice = false
            }
        }
    }

    // MARK: - Clear

    func clear() {
        query          = ""
        results        = []
        selectedResult = nil
        fetchedPrice   = nil
        isSearching    = false
        isFetchingPrice = false
    }
}
