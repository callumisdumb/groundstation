import Foundation
import CoreLocation

#if canImport(DJISDK)
import DJISDK
#endif

/// DJI Mobile SDK v4 read-only telemetry adapter.
///
/// With the DJI framework NOT installed, the original simulated bridge still works.
/// With DJI-SDK-iOS 4.16.2 linked, the adapter registers and observes the aircraft.
/// No Virtual Stick, waypoint execution, takeoff, landing, or camera commands exist.
///
/// Before relying on this path, prove DJI's official iOS Swift sample works on
/// the exact iPhone 15, Mavic Pro, controller, firmware and Xcode combination.
final class DJIAdapter: NSObject {
    /// Invoked on the main queue with the latest read-only aircraft state.
    var onUpdate: ((GroundStationMessage.Payload) -> Void)?

    private var snapshot = GroundStationMessage.Payload()

    func start() {
        #if canImport(DJISDK)
        let appKey = (Bundle.main.object(forInfoDictionaryKey: "DJISDKAppKey") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !appKey.isEmpty, appKey != "NOT_CONFIGURED",
              !appKey.contains("PASTE_YOUR") else {
            publish { data in
                data.connectionState = "DJI App Key not configured; see Documentation/DJIAppSetup.md"
                data.simulated = false
            }
            return
        }

        publish { data in
            data.connectionState = "Registering with DJI SDK…"
            data.simulated = false
        }
        DJISDKManager.registerApp(with: self)
        #else
        // Intentionally no SDK registration. BridgeServer retains its simulator.
        #endif
    }

    private func publish(_ update: @escaping (inout GroundStationMessage.Payload) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            update(&self.snapshot)
            self.onUpdate?(self.snapshot)
        }
    }
}

#if canImport(DJISDK)
extension DJIAdapter: DJISDKManagerDelegate {
    func appRegisteredWithError(_ error: Error?) {
        if let error {
            publish { data in
                data.connectionState = "DJI registration failed: \(error.localizedDescription)"
                data.simulated = false
            }
            return
        }
        publish { data in
            data.connectionState = "DJI SDK registered. Waiting for aircraft…"
            data.simulated = false
        }
        // This is a connection request only, not a flight-control command.
        DJISDKManager.startConnectionToProduct()
    }

    func productConnected(_ product: DJIBaseProduct?) {
        guard let aircraft = product as? DJIAircraft else {
            publish { data in
                data.connectionState = "DJI product detected; not an aircraft"
                data.simulated = false
            }
            return
        }

        publish { data in
            data.connectionState = "DJI aircraft connected (read-only)"
            data.aircraftModel = aircraft.model
            data.simulated = false
            data.batteryPercent = nil
            data.altitudeMeters = nil
            data.speedMetersPerSecond = nil
            data.latitude = nil
            data.longitude = nil
        }

        aircraft.flightController?.delegate = self
        subscribeToBattery()
    }

    func productDisconnected() {
        DJISDKManager.keyManager()?.stopAllListening(ofListeners: self)
        publish { data in
            data.connectionState = "DJI aircraft disconnected"
            data.aircraftModel = nil
            data.batteryPercent = nil
            data.latitude = nil
            data.longitude = nil
            data.altitudeMeters = nil
            data.speedMetersPerSecond = nil
            data.simulated = false
        }
    }

    func componentConnected(withKey key: String?, andIndex index: Int) {}
    func componentDisconnected(withKey key: String?, andIndex index: Int) {}
    func didUpdateDatabaseDownloadProgress(_ progress: Progress) {}

    private func subscribeToBattery() {
        guard let key = DJIBatteryKey(param: DJIBatteryParamChargeRemainingInPercent) else {
            return
        }
        DJISDKManager.keyManager()?.startListeningForChanges(
            on: key,
            withListener: self,
            andUpdate: { [weak self] _, value in
                guard let self, let value else { return }
                let percent = Int(value.unsignedIntegerValue)
                self.publish { data in
                    data.batteryPercent = (0...100).contains(percent) ? percent : nil
                }
            }
        )
    }
}

extension DJIAdapter: DJIFlightControllerDelegate {
    func flightController(_ fc: DJIFlightController, didUpdate state: DJIFlightControllerState) {
        let altitude = Double(state.altitude)
        let speed = hypot(Double(state.velocityX), Double(state.velocityY))
        let location = state.aircraftLocation?.coordinate
        publish { data in
            data.altitudeMeters = altitude.isFinite ? altitude : nil
            data.speedMetersPerSecond = speed.isFinite ? speed : nil
            if let location, CLLocationCoordinate2DIsValid(location) {
                data.latitude = location.latitude
                data.longitude = location.longitude
            } else {
                data.latitude = nil
                data.longitude = nil
            }
            data.simulated = false
        }
    }
}
#endif
