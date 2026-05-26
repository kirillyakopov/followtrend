//
//  APIConfig.swift
//  followtrend
//
//  Centralised API key configuration.
//  Paste your keys below — the app gracefully falls back to mock data
//  when keys are empty.
//
//  Providers:
//  - Finnhub (stocks/search): https://finnhub.io  (free tier available)
//  - CoinGecko (crypto):      https://www.coingecko.com  (no key required for free tier)
//  - Alpha Vantage (fallback):https://www.alphavantage.co  (free tier available)
//

import Foundation

enum APIConfig {
    // MARK: - Proxy Server
    // Replace this with your Mac's IP address when running on a physical iPhone
    static let proxyBaseURL    = "http://localhost:3000"

    // MARK: - Finnhub  (stocks, ETFs, search)
    static let finnhubKey      = "d87eoq9r01ql0hslfu60d87eoq9r01ql0hslfu6g"          // e.g. "cxxxxxxxxxxxxxxxxxxxxxx"
    static let finnhubBaseURL  = "https://finnhub.io/api/v1"

    // MARK: - CoinGecko  (crypto — no key needed for /v3 free endpoints)
    static let coinGeckoBaseURL = "https://api.coingecko.com/api/v3"

    // MARK: - Alpha Vantage  (optional fallback)
    static let alphaVantageKey     = ""      // e.g. "DEMO"
    static let alphaVantageBaseURL = "https://www.alphavantage.co/query"

    // MARK: - Feature flags
    static var canFetchLiveStockData: Bool { !finnhubKey.isEmpty }
    static var canFetchLiveCryptoData: Bool { true }   // CoinGecko needs no key
}
