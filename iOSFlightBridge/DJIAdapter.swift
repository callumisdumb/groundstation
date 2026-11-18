import Foundation
import Combine

/// Integration boundary for the legacy DJI Mobile SDK.
/// The SDK is deliberately NOT imported into this initial prototype.
///
/// First validate DJI's own Swift sample with the iPhone 15, original Mavic Pro
/// and standard RC: https://github.com/dji-sdk/Mobile-SDK-iOS
///
/// Only then transfer verified registration/product/state callback patterns
/// into this file and translate them into GroundStationMessage payloads.
/// Never send live flight commands from this read-only milestone.
@MainActor
final class DJIAdapter: ObservableObject {
    @Published private(set) var sdkAvailable = false
    @Published private(set) var aircraftConnected = false
    @Published private(set) var statusText = "DJI SDK not integrated"

    func start() {
        statusText = "Pending official DJI SDK sample validation"
    }
}
