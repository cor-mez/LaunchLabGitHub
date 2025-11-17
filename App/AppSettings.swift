import Foundation

@MainActor
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private init() {}

    // Add your properties here, example:
    @Published var showDebug: Bool = true
}
