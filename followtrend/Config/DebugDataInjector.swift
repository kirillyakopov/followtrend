//
//  DebugDataInjector.swift
//  followtrend
//
//  Utility for injecting random assets to test UI limits and performance.
//

import Foundation

class DebugDataInjector {
    /// Toggle this to `true` to inject 20 random assets on app launch.
    /// Toggle to `false` and run `removeDummyAssets` if you want to clean up.
    static let isEnabled = false
    
    static let debugTag = "DEBUG_RANDOM_ASSET"
    
    static func injectDummyAssets(into viewModel: PortfolioViewModel) {
        guard isEnabled else { return }
        
        // Prevent double injection if they already exist
        let existingDebugAssets = viewModel.investments.filter { $0.tags.contains(debugTag) }
        guard existingDebugAssets.isEmpty else { return }
        
        let dummySymbols = [
            "MSFT", "GOOGL", "AMZN", "META", "NFLX", 
            "AMD", "INTC", "QCOM", "TXN", "AVGO",
            "JPM", "BAC", "WFC", "C", "GS",
            "JNJ", "PFE", "MRK", "ABBV", "TMO"
        ]
        
        var newAssets: [Investment] = []
        
        for symbol in dummySymbols {
            let shares = Double.random(in: 1...100)
            let buyPrice = Double.random(in: 10...500)
            
            let inv = Investment(
                id: UUID().uuidString,
                symbol: symbol,
                name: "Debug \(symbol)",
                shares: shares,
                buyPrice: buyPrice,
                buyDate: "2024-01-01",
                nativeCurrency: "USD",
                isWatchlist: false,
                notes: "Random debug asset for testing UI limits",
                tags: debugTag
            )
            newAssets.append(inv)
        }
        
        viewModel.investments.append(contentsOf: newAssets)
        PortfolioStorageService.shared.saveInvestments(viewModel.investments)
        print("🛠️ Injected 20 random assets for debugging.")
    }
    
    static func removeDummyAssets(from viewModel: PortfolioViewModel) {
        let initialCount = viewModel.investments.count
        viewModel.investments.removeAll { $0.tags.contains(debugTag) }
        
        if viewModel.investments.count < initialCount {
            PortfolioStorageService.shared.saveInvestments(viewModel.investments)
            print("🧹 Removed all random debug assets.")
        }
    }
}
