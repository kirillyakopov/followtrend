//
//  PriceAlertStore.swift
//  followtrend
//

import Foundation
import Combine

enum PriceAlertKind: String, CaseIterable, Codable, Identifiable {
    case priceAbove
    case priceBelow
    case dailyChangeAbove
    case volumeSpike
    case fiftyTwoWeekHigh
    case fiftyTwoWeekLow

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .priceAbove: return "alerts.kind.priceAbove"
        case .priceBelow: return "alerts.kind.priceBelow"
        case .dailyChangeAbove: return "alerts.kind.dailyChangeAbove"
        case .volumeSpike: return "alerts.kind.volumeSpike"
        case .fiftyTwoWeekHigh: return "alerts.kind.fiftyTwoWeekHigh"
        case .fiftyTwoWeekLow: return "alerts.kind.fiftyTwoWeekLow"
        }
    }

    var requiresThreshold: Bool {
        switch self {
        case .priceAbove, .priceBelow, .dailyChangeAbove:
            return true
        case .volumeSpike, .fiftyTwoWeekHigh, .fiftyTwoWeekLow:
            return false
        }
    }
}

struct PriceAlert: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var investmentID: String
    var symbol: String
    var kind: PriceAlertKind
    var baseCurrency: String
    var targetPriceBase: Double
    var displayCurrencyAtCreation: String
    var originalInputValue: Double
    var isEnabled: Bool
    var createdAt: Date = Date()
}

@MainActor
final class PriceAlertStore: ObservableObject {
    static let shared = PriceAlertStore()

    @Published private(set) var alerts: [PriceAlert] = []

    private let storageKey = "followtrend.priceAlerts.v1"

    private init() {
        load()
    }

    func alert(for investmentID: String) -> PriceAlert? {
        alerts.first { $0.investmentID == investmentID }
    }

    func upsert(_ alert: PriceAlert) {
        if let index = alerts.firstIndex(where: { $0.id == alert.id || $0.investmentID == alert.investmentID }) {
            alerts[index] = alert
        } else {
            alerts.append(alert)
        }
        save()
    }

    func removeAlerts(for investmentID: String) {
        alerts.removeAll { $0.investmentID == investmentID }
        save()
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([PriceAlert].self, from: data)
        else { return }

        alerts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
