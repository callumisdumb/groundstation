import SwiftUI

@main
struct MacGroundStationApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1080, minHeight: 760)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
    }
}
