//
//  StablecoinClassifier.swift
//  followtrend
//

import Foundation

enum StablecoinClassifier {
    nonisolated static func isStablecoin(symbol: String, name: String? = nil) -> Bool {
        let normalizedSymbol = normalize(symbol)
        if exactSymbols.contains(normalizedSymbol) { return true }

        if normalizedSymbol.hasPrefix("AXLUSDC") ||
            normalizedSymbol.contains("USDC.E") ||
            normalizedSymbol.contains("USDT.E") {
            return true
        }

        guard let name else { return false }
        let normalizedName = normalize(name)

        return nameKeywords.contains { normalizedName.contains($0) }
    }

    nonisolated private static func normalize(_ value: String) -> String {
        value
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    nonisolated private static let exactSymbols: Set<String> = [
        "USDT", "USDC", "DAI", "FDUSD", "TUSD", "USDP", "PYUSD", "GUSD",
        "LUSD", "FRAX", "USDD", "USDJ", "EURC", "EURT", "EURS", "XAUT", "PAXG"
    ]

    nonisolated private static let nameKeywords: Set<String> = [
        "BRIDGEDUSDC",
        "WRAPPEDUSDT",
        "AXLUSDC",
        "USDC.E",
        "USDTE",
        "USDCE",
        "STABLECOIN",
        "TETHER",
        "USDCOIN",
        "DAI",
        "PAXGOLD",
        "TETHERGOLD"
    ]
}
