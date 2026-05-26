
//
//  followtrendApp.swift
//  followtrend
//

import SwiftUI
import Combine
import SwiftData

@main
struct followtrendApp: App {
    @StateObject private var languageManager = AppLanguageManager.shared

    var body: some Scene {
        WindowGroup {
            PortfolioView()
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.currentLanguage.locale)
                .preferredColorScheme(.dark)
                .modelContainer(for: InvestmentModel.self)
        }
    }
}
