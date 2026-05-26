import SwiftUI
import Combine

@MainActor
final class AppLanguageManager: ObservableObject {
    @Published var test: String = ""
}

struct TestView: View {
    @StateObject var lm = AppLanguageManager()
    var body: some View { Text("hi") }
}
