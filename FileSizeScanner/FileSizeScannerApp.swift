import SwiftUI

@main
struct FileSizeScannerApp: App {
    init() {
        UserDefaults.standard.set(400, forKey: "NSInitialToolTipDelay")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
    }
}
