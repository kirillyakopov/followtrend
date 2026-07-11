//
//  APIConfig.swift
//  followtrend
//
//  Centralised endpoint + secret configuration.
//
//  Live data sources actually in use:
//  - Stocks/ETFs: Yahoo Finance chart API (see MarketDataService) — no key.
//  - Crypto:      Render proxy (prices/candles/FX) + CoinGecko (search/resolve).
//
//  The proxy secret is NOT committed. It is read at runtime from the
//  `PROXY_SECRET` environment variable (tests/CI) or the `ProxySecret`
//  Info.plist key, which is populated from the gitignored
//  `followtrend/Config/Secrets.xcconfig` (see `Secrets.example.xcconfig`).
//  When unset, `proxySecret` is empty and the app degrades to mock data.
//

import Foundation

enum APIConfig {
    // MARK: - Proxy Server (crypto prices/candles + FX)
    static let proxyBaseURL = "https://crypto-proxy-221x.onrender.com"

    /// Bearer token for the proxy. Resolved from the environment first (so tests
    /// and CI can inject it) then the app's Info.plist. Never hard-coded here.
    static let proxySecret: String = {
        if let env = ProcessInfo.processInfo.environment["PROXY_SECRET"],
           !env.isEmpty {
            return env
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "ProxySecret") as? String,
           !plist.isEmpty, !plist.hasPrefix("$(") {
            return plist
        }
        return ""
    }()

    // MARK: - CoinGecko  (crypto search/resolve — no key needed for /v3 free endpoints)
    static let coinGeckoBaseURL = "https://api.coingecko.com/api/v3"
}
