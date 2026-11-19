import SwiftUI
import UIKit

@main
struct iOSFlightBridgeApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            BridgeView()
                .onAppear {
                    // Prevent auto-lock while the iPhone bridge is in the foreground.
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                .onChange(of: scenePhase) { phase in
                    // Restore normal auto-lock whenever the app isn't active.
                    UIApplication.shared.isIdleTimerDisabled = (phase == .active)
                }
                .onDisappear {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
        }
    }
}
