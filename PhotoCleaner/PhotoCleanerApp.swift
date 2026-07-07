import SwiftUI

@main
struct PhotoCleanerApp: App {
    init() {
        TemporaryCacheManager.cleanIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
