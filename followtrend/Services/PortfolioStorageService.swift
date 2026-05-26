//
//  PortfolioStorageService.swift
//  followtrend
//
//  Created for SwiftData persistence.
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
final class PortfolioStorageService {
    static let shared = PortfolioStorageService()
    
    private var modelContainer: ModelContainer?
    private var context: ModelContext?
    
    private init() {
        do {
            let schema = Schema([InvestmentModel.self])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            if let container = modelContainer {
                context = ModelContext(container)
            }
        } catch {
            print("Failed to initialize SwiftData ModelContainer: \(error.localizedDescription)")
        }
    }
    
    // Get the shared container to inject into SwiftUI if needed
    var sharedContainer: ModelContainer? {
        return modelContainer
    }
    
    func fetchInvestments() -> [Investment] {
        guard let context = context else { return [] }
        
        do {
            let descriptor = FetchDescriptor<InvestmentModel>()
            let models = try context.fetch(descriptor)
            return models.map { Investment(from: $0) }
        } catch {
            print("Failed to fetch investments: \(error.localizedDescription)")
            return []
        }
    }
    
    func saveInvestments(_ investments: [Investment]) {
        guard let context = context else { return }
        
        do {
            // Fetch all existing models to replace them
            let descriptor = FetchDescriptor<InvestmentModel>()
            let existingModels = try context.fetch(descriptor)
            
            for model in existingModels {
                context.delete(model)
            }
            
            // Insert new models
            for inv in investments {
                let newModel = InvestmentModel(
                    id: inv.id,
                    symbol: inv.symbol,
                    name: inv.name,
                    shares: inv.shares,
                    buyPrice: inv.buyPrice,
                    buyDate: inv.buyDate,
                    coinId: inv.coinId,
                    nativeCurrency: inv.nativeCurrency,
                    isWatchlist: inv.isWatchlist,
                    notes: inv.notes,
                    tags: inv.tags,
                    currentApiPriceAtEntry: inv.currentApiPriceAtEntry,
                    currentBrokerPriceAtEntry: inv.currentBrokerPriceAtEntry,
                    priceAdjustmentFactor: inv.priceAdjustmentFactor,
                    brokerName: inv.brokerName,
                    apiBaseCurrency: inv.apiBaseCurrency,
                    brokerCurrency: inv.brokerCurrency,
                    displayCurrency: inv.displayCurrency,
                    fxRateAtCreation: inv.fxRateAtCreation
                )
                context.insert(newModel)
            }
            
            try context.save()
            print("Successfully auto-saved \(investments.count) investments.")
        } catch {
            print("Failed to save investments: \(error.localizedDescription)")
        }
    }
}
