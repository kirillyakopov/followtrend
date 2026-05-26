//
//  CurrencyService.swift
//  followtrend
//
//  Manages global currency state, FX rates, and correct locale formatting.
//

import Foundation
import Combine
import SwiftUI

enum AppCurrency: String, CaseIterable, Identifiable {
    case eur = "EUR"
    case usd = "USD"
    var id: String { rawValue }
    
    var symbol: String {
        switch self {
        case .eur: return "€"
        case .usd: return "$"
        }
    }
}

@MainActor
final class CurrencyService: ObservableObject {
    static let shared = CurrencyService()
    
    @AppStorage("selectedCurrency") private var storedCurrencyValue: String = AppCurrency.eur.rawValue
    
    @Published var selectedCurrency: AppCurrency = .eur {
        didSet {
            storedCurrencyValue = selectedCurrency.rawValue
        }
    }
    
    // Fallback rate if proxy fetch fails
    @Published var eurToUsdRate: Double = 1.05
    @Published var usdToEurRate: Double = 0.95
    
    private init() {
        if let currency = AppCurrency(rawValue: storedCurrencyValue) {
            self.selectedCurrency = currency
        }
    }
    
    // MARK: - Fetch FX Rates
    func fetchFXRates() async {
        guard let url = URL(string: "\(APIConfig.proxyBaseURL)/api/fx") else { return }
        do {
            let data = try await NetworkService.shared.fetch(url) as [String: Double]
            if let eurUsd = data["EUR_USD"], let usdEur = data["USD_EUR"] {
                self.eurToUsdRate = eurUsd
                self.usdToEurRate = usdEur
            }
        } catch {
            print("Failed to fetch FX rates: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Conversion
    func convert(value: Double, from sourceCurrency: AppCurrency, to targetCurrency: AppCurrency) -> Double {
        if sourceCurrency == targetCurrency {
            return value
        }
        if sourceCurrency == .usd && targetCurrency == .eur {
            return value * usdToEurRate
        }
        if sourceCurrency == .eur && targetCurrency == .usd {
            return value * eurToUsdRate
        }
        return value
    }
    
    func convertToSelected(value: Double, from sourceCurrency: String) -> Double {
        let source = AppCurrency(rawValue: sourceCurrency.uppercased()) ?? .usd
        return convert(value: value, from: source, to: selectedCurrency)
    }
    
    // MARK: - Formatting
    func format(value: Double, from sourceCurrency: String = "USD") -> String {
        let convertedValue = convertToSelected(value: value, from: sourceCurrency)
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = selectedCurrency.rawValue
        formatter.locale = AppLanguageManager.shared.currentLanguage.locale
        
        return formatter.string(from: NSNumber(value: convertedValue)) ?? "\(selectedCurrency.symbol)\(convertedValue)"
    }
    
    func formatConverted(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = selectedCurrency.rawValue
        formatter.locale = AppLanguageManager.shared.currentLanguage.locale
        
        return formatter.string(from: NSNumber(value: value)) ?? "\(selectedCurrency.symbol)\(value)"
    }
}
