import SwiftUI

@main
struct MacGroundStationApp: App {
    var body: some Scene {
        Window("GroundStation", id: "project") {
            ContentView()
                .frame(minWidth: 960, minHeight: 580)
        }
        .defaultSize(width: 1320, height: 800)
        .windowStyle(.titleBar)
    }
}
