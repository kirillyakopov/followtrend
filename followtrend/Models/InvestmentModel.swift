//
//  InvestmentModel.swift
//  followtrend
//
//  Created for SwiftData persistence.
//

import Foundation
import SwiftData

@Model
final class InvestmentModel {
    @Attribute(.unique) var id: String
    var symbol: String
    var name: String
    var shares: Double
    var buyPrice: Double
    var buyDate: String
    var coinId: String?
    var nativeCurrency: String
    var isWatchlist: Bool = false
    var notes: String = ""
    var tags: String = ""
    var currentApiPriceAtEntry: Double?
    var currentBrokerPriceAtEntry: Double?
    var priceAdjustmentFactor: Double?
    var brokerName: String?
    var apiBaseCurrency: String?
    var brokerCurrency: String?
    var displayCurrency: String?
    var fxRateAtCreation: Double?
    
    init(
        id: String,
        symbol: String,
        name: String,
        shares: Double,
        buyPrice: Double,
        buyDate: String,
        coinId: String? = nil,
        nativeCurrency: String = "USD",
        isWatchlist: Bool = false,
        notes: String = "",
        tags: String = "",
        currentApiPriceAtEntry: Double? = nil,
        currentBrokerPriceAtEntry: Double? = nil,
        priceAdjustmentFactor: Double? = nil,
        brokerName: String? = nil,
        apiBaseCurrency: String? = nil,
        brokerCurrency: String? = nil,
        displayCurrency: String? = nil,
        fxRateAtCreation: Double? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.shares = shares
        self.buyPrice = buyPrice
        self.buyDate = buyDate
        self.coinId = coinId
        self.nativeCurrency = nativeCurrency
        self.isWatchlist = isWatchlist
        self.notes = notes
        self.tags = tags
        self.currentApiPriceAtEntry = currentApiPriceAtEntry
        self.currentBrokerPriceAtEntry = currentBrokerPriceAtEntry
        self.priceAdjustmentFactor = priceAdjustmentFactor
        self.brokerName = brokerName
        self.apiBaseCurrency = apiBaseCurrency
        self.brokerCurrency = brokerCurrency
        self.displayCurrency = displayCurrency
        self.fxRateAtCreation = fxRateAtCreation
    }
}
