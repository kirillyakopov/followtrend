//
//  AppLanguageManager.swift
//  followtrend
//
//  Custom localization manager reading from JSON structures.
//  Matches next-intl style namespaces, instantly updates SwiftUI views.
//

import SwiftUI
import Foundation
import Combine

// MARK: - Supported Languages Struct
struct AppLanguage: Codable, Identifiable, Hashable, Equatable {
    let code: String
    let displayName: String
    let flag: String

    var id: String { code }
    var rawValue: String { code }

    var locale: Locale {
        Locale(identifier: code)
    }
}

private struct LanguageFile: Codable {
    struct Meta: Codable {
        let displayName: String
        let flag: String
    }
    let _meta: Meta
}

// MARK: - Language Manager
@MainActor
final class AppLanguageManager: ObservableObject {
    static let shared = AppLanguageManager()

    static let fallbackLanguage = AppLanguage(code: "en", displayName: "English", flag: "🇬🇧")

    @Published private(set) var supportedLanguages: [AppLanguage] = [fallbackLanguage]

    private var storedLanguage: String {
        get { UserDefaults.standard.string(forKey: "selectedLanguage") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedLanguage") }
    }

    @Published var currentLanguage: AppLanguage = fallbackLanguage {
        didSet {
            storedLanguage = currentLanguage.code
        }
    }

    private var translations: [String: Any] = [:]

    private init() {
        loadSupportedLanguages()

        // Resolve current language
        let selected = storedLanguage
        if !selected.isEmpty, let matched = supportedLanguages.first(where: { $0.code == selected }) {
            currentLanguage = matched
        } else {
            // Auto-detect system language
            let sysLang = Locale.current.language.languageCode?.identifier ?? "en"
            if let matched = supportedLanguages.first(where: { $0.code == sysLang }) {
                currentLanguage = matched
            } else {
                currentLanguage = supportedLanguages.first(where: { $0.code == "en" }) ?? AppLanguageManager.fallbackLanguage
            }
        }

        loadTranslations(for: currentLanguage)
    }

    func setLanguage(_ lang: AppLanguage) {
        currentLanguage = lang
        loadTranslations(for: lang)
        haptic(.rigid)
    }

    /// Translation function matching nested keys e.g., "portfolio.brokerage"
    func t(_ keyPath: String) -> String {
        let keys = keyPath.split(separator: ".")
        var current: Any? = translations

        for key in keys {
            if let dict = current as? [String: Any], let val = dict[String(key)] {
                current = val
            } else {
                return String(keyPath.split(separator: ".").last ?? "") // Fallback to key
            }
        }

        if let str = current as? String {
            return str
        }
        return String(keyPath.split(separator: ".").last ?? "")
    }

    // MARK: - Dynamic Discovery & Loading
    private func loadSupportedLanguages() {
        var languages: [AppLanguage] = []

        // Scan main bundle for all JSON files
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        for url in urls {
            if let data = try? Data(contentsOf: url),
               let languageFile = try? JSONDecoder().decode(LanguageFile.self, from: data) {
                let code = url.deletingPathExtension().lastPathComponent
                let lang = AppLanguage(
                    code: code,
                    displayName: languageFile._meta.displayName,
                    flag: languageFile._meta.flag
                )
                languages.append(lang)
            }
        }

        // Sort languages: English first, then others alphabetically by displayName
        languages.sort { (a, b) -> Bool in
            if a.code == "en" { return true }
            if b.code == "en" { return false }
            return a.displayName.localizedCompare(b.displayName) == .orderedAscending
        }

        if languages.isEmpty {
            self.supportedLanguages = [AppLanguageManager.fallbackLanguage]
        } else {
            self.supportedLanguages = languages
        }
    }

    private func loadTranslations(for lang: AppLanguage) {
        // Attempt to load from Bundle
        if let url = Bundle.main.url(forResource: lang.code, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.translations = json
            return
        }

        // Fallback: embedded translations to ensure it works even if bundle loading fails
        let rawJSON = embeddedEnglishJSON()
        if let data = rawJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.translations = json
        }
    }

    private func embeddedEnglishJSON() -> String {
        return """
        {
          "_meta": {
            "displayName": "English",
            "flag": "🇬🇧"
          },
          "tabs": { "gesamt": "Total", "einzel": "Items", "bubbles": "Bubbles", "anlegen": "Add" },
          "portfolio": {
            "brokerage": "Brokerage", "kosten": "Cost", "cash": "Cash",
            "gesamtrendite": "Total Return", "roi": "ROI", "positionen": "Positions",
            "positionen_suchen": "Search positions…", "aktive_positionen": "ACTIVE POSITIONS",
            "ergebnisse": "RESULTS", "seit_kauf": "Since buy",
            "keine_positionen": "No positions. Tap 'Add' to insert.",
            "keine_ergebnisse": "No results for '%@'", "stueck": "Shares", "loeschen": "Delete",
            "watchlist": "Watchlist", "risk_correlation": "RISK & CORRELATION"
          },
          "sort": {
            "title": "SORT POSITIONS",
            "sinceBuy": "Since buy",
            "today": "Today",
            "totalValue": "Total value",
            "name": "Name A-Z",
            "bestPerformer": "Best performer",
            "worstPerformer": "Worst performer"
          },
          "actions": {
            "edit": "Edit",
            "remove": "Remove",
            "convert": "Convert",
            "popBubble": "Pop Bubble",
            "restoreBubble": "Restore Bubble"
          },
          "confirm": {
            "removePosition": {
              "title": "Remove position",
              "message": "Remove this position from your portfolio?"
            },
            "removeWatchlist": {
              "title": "Remove watchlist item",
              "message": "Remove this item from your watchlist?"
            },
            "popBubble": {
              "title": "Pop bubble",
              "message": "Pop this bubble and remove the position?"
            },
            "restoreBubble": {
              "title": "Restore the last popped bubble?"
            }
          },
          "einzel": { "depot": "PORTFOLIO", "rendite": "RETURN", "live": "Live", "tippe_ziehen": "Tap · Drag to move" },
          "detail": {
            "meine_position": "MY POSITION", "stueck": "Shares", "kaufpreis": "Avg Price",
            "kaufdatum": "Buy Date", "aktuelle_wert": "Current Value", "gewinn_verlust": "Profit/Loss",
            "marktdaten": "MARKET DATA", "symbol": "Symbol", "typ": "Type", "quelle": "Source",
            "aktie": "Stock", "crypto": "Crypto", "blase_platzen": "Pop Bubble", "position_loeschen": "Delete Position",
            "watchlist_item": "WATCHLIST ITEM", "watchlist_entfernen": "Remove from Watchlist", "in_portfolio_kaufen": "Buy (Move to Portfolio)",
            "insufficient_correlation_data": "Insufficient historical data for correlation analysis",
            "pearson_correlation": "Pearson Correlation"
          },
          "add": {
            "wertpapier_suchen": "Search assets...", "abbrechen": "Cancel",
            "aktien_etfs_krypto_suchen": "Search Stocks, ETFs, Crypto...", "zusammenfassung": "Summary",
            "investitionssumme": "Investment Amount", "kauf_informationen": "Buy Information",
            "stueckzahl": "Shares", "kaufpreis_eur": "Price (€)", "stueck_preis": "Shares × Price",
            "uebernehmen": "Add Position", "portfolio": "Portfolio", "watchlist": "Watchlist", "zu_watchlist_hinzufuegen": "Add to Watchlist"
          },
          "profile": {
            "profil": "Profile", "abmelden": "Sign Out", "mit_apple_anmelden": "Sign In with Apple",
            "nicht_angemeldet": "Not signed in", "apple_id_verknuepft": "Apple ID Linked",
            "deine_daten_sicher": "Your data is securely stored",
            "daten_apple_verknuepft": "Your data is securely linked to your Apple ID.",
            "sprache": "Language"
          },
          "common": { "fertig": "Done" },
          "pearson": {
            "title": "Pearson Correlation",
            "badges": {
              "diversified": "Diversified",
              "weak": "Low Correlation",
              "moderate": "Moderate Correlation",
              "high": "High Correlation"
            },
            "shortDescription": "Measures how strongly two assets move together.",
            "explanation": "Correlation shows whether two assets tend to move in the same direction, independently, or in opposite directions.",
            "scale": {
              "title": "Correlation Spectrum",
              "perfectPositive": { "title": "+1.0", "description": "Perfect positive correlation. Assets move exactly together." },
              "strongPositive": { "title": "+0.7 to +0.9", "description": "Strong positive correlation. Assets generally move in the same direction." },
              "moderatePositive": { "title": "+0.3 to +0.7", "description": "Moderate positive correlation." },
              "noCorrelation": { "title": "0", "description": "No correlation. Assets move independently." },
              "moderateNegative": { "title": "-0.3 to -0.7", "description": "Moderate negative correlation." },
              "strongNegative": { "title": "-0.7 to -1.0", "description": "Strong negative correlation." },
              "perfectNegative": { "title": "-1.0", "description": "Perfect inverse correlation. When one asset rises, the other falls." }
            },
            "whyItMatters": {
              "title": "Why does it matter?",
              "point1": "Helps diversify your portfolio.",
              "point2": "Can reduce overall risk.",
              "point3": "Shows hidden relationships between investments.",
              "point4": "Helps identify hedging opportunities."
            },
            "disclaimer": {
              "title": "Important",
              "text": "Correlation does not imply causation. Two assets moving similarly does not necessarily mean one causes the movement of the other."
            },
            "errors": {
              "insufficientData": "Insufficient historical data",
              "calculationFailed": "Unable to calculate correlation",
              "loading": "Loading correlation data..."
            }
          },
          "search": {
            "portfolio": "Search positions",
            "market": "Search stocks, ETFs, crypto",
            "stocks": "Stocks",
            "etfs": "ETFs",
            "crypto": "Crypto",
            "watchlist": "Watchlist",
            "positions": "Positions",
            "noResults": "No results",
            "loading": "Searching..."
          },
          "bubbles": {
            "merge": "Merge",
            "mergeSuggestions": "Merge Suggestions",
            "noMergeSuggestions": "No merge suggestions yet",
            "mergeCluster": "Merge Cluster",
            "expandCluster": "Expand Cluster",
            "dissolveCluster": "Dissolve Cluster",
            "viewAssets": "View Assets",
            "mergedBubblesTitle": "Merged Bubbles",
            "mergedBubblesText": "Highly related assets can be grouped into one cluster bubble. Merging is visual only and does not change your portfolio.",
            "averageCorrelation": "Avg correlation",
            "portfolioWeight": "Portfolio weight",
            "assetsCount": "{count} assets",
            "techCluster": "Tech Cluster",
            "financeCluster": "Finance Cluster",
            "energyCluster": "Energy Cluster",
            "healthcareCluster": "Healthcare Cluster",
            "stockCluster": "Stock Cluster",
            "etfCluster": "ETF Cluster",
            "cryptoCluster": "Crypto Cluster",
            "correlationCluster": "Correlation Cluster"
          }
        }
        """
    }
}
