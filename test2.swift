import SwiftUI
import Combine

@MainActor
final class AppLanguageManager: ObservableObject {
    static let shared = AppLanguageManager()
    @Published var currentLanguage: String = "en"
    private init() {}
}

struct TestApp: App {
    @StateObject private var lm = AppLanguageManager.shared
    var body: some Scene {
        WindowGroup { Text("Hello") }
    }
}
