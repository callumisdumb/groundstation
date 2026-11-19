import Foundation
import CoreLocation

#if canImport(DJISDK)
import DJISDK
#endif

/// DJI v4 adapter. All operator input is received from the Mac over the
/// authenticated-in-session bridge. No independent phone flight UI exists.
/// The remote controller must remain physically available for override.
final class DJIAdapter: NSObject {
    var onUpdate: ((GroundStationMessage.Payload) -> Void)?
    var onResult: ((String, Bool, String) -> Void)?

    private var snapshot = GroundStationMessage.Payload()
    private var lastAircraftStateAt = Date.distantPast
    private var flightArmedUntil = Date.distantPast
    private var lastSticksAt = Date.distantPast
    private var stickTimer: Timer?
    private var sticksEnabled = false
    private var lastAxes = (pitch: 0.0, roll: 0.0, yaw: 0.0, vertical: 0.0)

    #if canImport(DJISDK)
    private weak var controller: DJIFlightController?
    private var lastFlightState: DJIFlightControllerState?
    #endif

    func start() {
        #if canImport(DJISDK)
        let key = (Bundle.main.object(forInfoDictionaryKey: "DJISDKAppKey") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key != "NOT_CONFIGURED", !key.contains("PASTE_YOUR") else {
            publish {
                $0.connectionState = "DJI App Key missing; see Documentation/DJIAppSetup.md"
                $0.simulated = false
            }
            return
        }
        publish { $0.connectionState = "Registering DJI SDK…" ; $0.simulated = false }
        DJISDKManager.registerApp(with: self)
        #endif
    }

    /// Called each second so controller-only states are never labelled as
    /// an aircraft connection, and stale flight readings are cleared.
    func refreshConnection() {
        #if canImport(DJISDK)
        let product = DJISDKManager.product()
        let model = product?.model ?? ""
        let aircraft = product as? DJIAircraft
        let actualController = aircraft?.flightController
        let hasAircraft = !model.lowercased().contains("only remotecontroller") &&
            actualController?.isConnected == true
        if !hasAircraft {
            if sticksEnabled { disableSticks() }
            controller = nil
            lastFlightState = nil
            flightArmedUntil = .distantPast
            publish {
                $0.aircraftConnected = false
                $0.controllerConnected = product != nil
                $0.aircraftModel = nil
                $0.connectionState = product == nil ? "DJI disconnected" :
                    "Controller detected — aircraft NOT linked"
                $0.batteryPercent = nil
                $0.latitude = nil
                $0.longitude = nil
                $0.altitudeMeters = nil
                $0.speedMetersPerSecond = nil
                $0.velocityX = nil
                $0.velocityY = nil
                $0.velocityZ = nil
                $0.pitchDegrees = nil
                $0.rollDegrees = nil
                $0.yawDegrees = nil
                $0.satelliteCount = nil
                $0.flightMode = nil
                $0.motorsOn = nil
                $0.isFlying = nil
                $0.homeLocationSet = nil
                $0.homeLatitude = nil
                $0.homeLongitude = nil
                $0.imuPreheating = nil
                $0.flightTimeSeconds = nil
                $0.simulated = false
            }
            return
        }
        if controller !== actualController {
            controller = actualController
            actualController?.delegate = self
            subscribeToBattery()
        }
        if Date().timeIntervalSince(lastAircraftStateAt) > 4 {
            publish {
                $0.connectionState = "Aircraft linked — flight telemetry pending"
                $0.altitudeMeters = nil
                $0.speedMetersPerSecond = nil
                $0.latitude = nil
                $0.longitude = nil
                $0.aircraftConnected = true
            }
        }
        #endif
    }

    func handle(_ command: GroundStationCommand) {
        #if canImport(DJISDK)
        guard let fc = controller, fc.isConnected, snapshot.aircraftConnected == true else {
            result(command, false, "Aircraft not linked. Check controller ↔ Mavic connection.")
            return
        }
        let flightAction: Bool = [
            .armFlight, .disarmFlight, .takeoff, .land, .returnHome,
            .motorsOn, .motorsOff, .enableSticks, .disableSticks, .sticks
        ].contains(command.action)

        if flightAction && Date().timeIntervalSince(lastAircraftStateAt) > 2.0 {
            result(command, false, "Flight telemetry stale; command rejected")
            return
        }
        let completion: (Error?) -> Void = { [weak self] error in
            self?.result(command, error == nil,
                         error.map { $0.localizedDescription } ?? "DJI accepted \(command.action.rawValue)")
        }

        switch command.action {
        case .gimbalPitch:
            guard let pitch = command.value, pitch.isFinite, (-90...0).contains(pitch),
                  let gimbal = (DJISDKManager.product() as? DJIAircraft)?.gimbal else {
                result(command, false, "Gimbal unavailable or pitch outside -90°…0°")
                return
            }
            // Absolute pitch. Camera's physical travel limits still apply.
            let rotation = DJIGimbalRotation(pitchValue: NSNumber(value: pitch),
                                             rollValue: nil, yawValue: nil,
                                             time: 1, mode: .absoluteAngle, ignore: true)
            gimbal.rotate(with: rotation, completion: completion)

        case .takePhoto:
            guard let camera = (DJISDKManager.product() as? DJIAircraft)?.camera else {
                result(command, false, "No camera connected")
                return
            }
            camera.setMode(.shootPhoto, withCompletion: { error in
                if let error { completion(error); return }
                camera.startShootPhoto(completion: completion)
            })
        case .startRecording:
            guard let camera = (DJISDKManager.product() as? DJIAircraft)?.camera else {
                result(command, false, "No camera connected")
                return
            }
            camera.setMode(.recordVideo, withCompletion: { error in
                if let error { completion(error); return }
                camera.startRecordVideo(completion: completion)
            })
        case .stopRecording:
            guard let camera = (DJISDKManager.product() as? DJIAircraft)?.camera else {
                result(command, false, "No camera connected")
                return
            }
            camera.stopRecordVideo(completion: completion)

        case .armFlight:
            guard snapshot.isFlying == false,
                  (snapshot.batteryPercent ?? 0) >= 30,
                  (snapshot.satelliteCount ?? 0) >= 8,
                  snapshot.homeLocationSet == true,
                  snapshot.imuPreheating == false else {
                result(command, false, "Preflight failed: grounded aircraft, battery ≥30%, GPS ≥8, home point and ready IMU required")
                return
            }
            flightArmedUntil = Date().addingTimeInterval(30)
            result(command, true, "Flight armed for 30 seconds. Confirm takeoff on the Mac.")
        case .disarmFlight:
            flightArmedUntil = .distantPast
            disableSticks()
            result(command, true, "Flight commands disarmed")
        case .takeoff:
            guard Date() < flightArmedUntil, snapshot.isFlying == false else {
                result(command, false, "Arm flight from Mac first (expires after 30 seconds)")
                return
            }
            flightArmedUntil = .distantPast
            fc.startTakeoff(completion: completion)
        case .land:
            guard snapshot.isFlying == true else {
                result(command, false, "Landing requires flight status")
                return
            }
            disableSticks()
            fc.startLanding(completion: completion)
        case .returnHome:
            guard snapshot.isFlying == true, snapshot.homeLocationSet == true else {
                result(command, false, "Return home needs flight status and a valid home point")
                return
            }
            disableSticks()
            fc.startGoHome(completion: completion)
        case .motorsOn:
            guard snapshot.isFlying == false, Date() < flightArmedUntil else {
                result(command, false, "Grounded and explicitly armed required to start motors")
                return
            }
            flightArmedUntil = .distantPast
            fc.turnOnMotors(completion: completion)
        case .motorsOff:
            guard snapshot.isFlying == false else {
                result(command, false, "Motor shutdown while flying is prohibited")
                return
            }
            fc.turnOffMotors(completion: completion)
        case .enableSticks:
            guard snapshot.isFlying == true,
                  (snapshot.batteryPercent ?? 0) >= 20 else {
                result(command, false, "Virtual Sticks require active flight and usable battery")
                return
            }
            fc.rollPitchControlMode = .velocity
            fc.rollPitchCoordinateSystem = .body
            fc.yawControlMode = .angularVelocity
            fc.verticalControlMode = .velocity
            fc.setVirtualStickModeEnabled(true, withCompletion: { [weak self] error in
                if error == nil {
                    self?.sticksEnabled = true
                    self?.lastSticksAt = Date()
                    self?.startStickWatchdog()
                }
                completion(error)
            })
        case .disableSticks:
            disableSticks()
            result(command, true, "Virtual Stick mode released to DJI controller")
        case .sticks:
            guard sticksEnabled, snapshot.isFlying == true else {
                // Avoid filling the logs with rejected held-button messages.
                return
            }
            let pitch = command.pitch ?? 0
            let roll = command.roll ?? 0
            let yaw = command.yaw ?? 0
            let vertical = command.vertical ?? 0
            guard [pitch, roll, yaw, vertical].allSatisfy({ $0.isFinite }),
                  abs(pitch) <= 1.2, abs(roll) <= 1.2,
                  abs(yaw) <= 20.0, abs(vertical) <= 0.8 else { return }
            lastSticksAt = Date()
            lastAxes = (pitch, roll, yaw, vertical)
        }
        #else
        result(command, false, "DJI SDK not installed")
        #endif
    }

    func networkDisconnected() {
        flightArmedUntil = .distantPast
        disableSticks()
    }

    private func result(_ cmd: GroundStationCommand, _ ok: Bool, _ detail: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onResult?(cmd.id, ok, detail)
        }
    }

    private func publish(_ change: @escaping (inout GroundStationMessage.Payload) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            change(&self.snapshot)
            self.onUpdate?(self.snapshot)
        }
    }

    private func startStickWatchdog() {
        stickTimer?.invalidate()
        stickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.stickTick()
        }
    }

    private func stickTick() {
        #if canImport(DJISDK)
        guard sticksEnabled, let fc = controller, fc.isConnected else {
            disableSticks()
            return
        }
        let age = Date().timeIntervalSince(lastSticksAt)
        if age > 0.8 {
            disableSticks()
            return
        }
        let axes = age <= 0.3 ? lastAxes : (pitch: 0.0, roll: 0.0, yaw: 0.0, vertical: 0.0)
        let data = DJIVirtualStickFlightControlData(
            pitch: Float(axes.pitch), roll: Float(axes.roll),
            yaw: Float(axes.yaw), verticalThrottle: Float(axes.vertical))
        fc.send(data, withCompletion: nil)
        #endif
    }

    private func disableSticks() {
        stickTimer?.invalidate()
        stickTimer = nil
        #if canImport(DJISDK)
        guard sticksEnabled else { return }
        sticksEnabled = false
        lastAxes = (0, 0, 0, 0)
        controller?.setVirtualStickModeEnabled(false, withCompletion: nil)
        #endif
    }
}

#if canImport(DJISDK)
extension DJIAdapter: DJISDKManagerDelegate {
    func appRegisteredWithError(_ error: Error?) {
        if let error {
            publish {
                $0.connectionState = "DJI registration failed: \(error.localizedDescription)"
                $0.simulated = false
            }
            return
        }
        publish { $0.connectionState = "DJI registered; seeking controller/aircraft" ; $0.simulated = false }
        DJISDKManager.startConnectionToProduct()
    }

    func productConnected(_ product: DJIBaseProduct?) {
        refreshConnection()
    }

    func productDisconnected() {
        disableSticks()
        refreshConnection()
    }

    func componentConnected(withKey key: String?, andIndex index: Int) { refreshConnection() }
    func componentDisconnected(withKey key: String?, andIndex index: Int) { refreshConnection() }
    func didUpdateDatabaseDownloadProgress(_ progress: Progress) {}

    private func subscribeToBattery() {
        guard let key = DJIBatteryKey(param: DJIBatteryParamChargeRemainingInPercent) else { return }
        DJISDKManager.keyManager()?.stopAllListening(ofListeners: self)
        DJISDKManager.keyManager()?.startListeningForChanges(
            on: key, withListener: self, andUpdate: { [weak self] _, value in
                guard let self, let value else { return }
                let percentage = Int(value.unsignedIntegerValue)
                self.publish {
                    guard $0.aircraftConnected == true else { return }
                    $0.batteryPercent = (0...100).contains(percentage) ? percentage : nil
                }
            })
    }
}

extension DJIAdapter: DJIFlightControllerDelegate {
    func flightController(_ fc: DJIFlightController, didUpdate state: DJIFlightControllerState) {
        lastFlightState = state
        lastAircraftStateAt = Date()
        let speed = hypot(Double(state.velocityX), Double(state.velocityY))
        let position = state.aircraftLocation?.coordinate
        let home = state.homeLocation?.coordinate
        publish {
            $0.aircraftConnected = true
            $0.controllerConnected = true
            $0.connectionState = "DJI aircraft linked (real telemetry)"
            $0.aircraftModel = DJISDKManager.product()?.model
            $0.simulated = false
            $0.altitudeMeters = state.altitude.isFinite ? Double(state.altitude) : nil
            $0.velocityX = Double(state.velocityX)
            $0.velocityY = Double(state.velocityY)
            $0.velocityZ = Double(state.velocityZ)
            $0.speedMetersPerSecond = speed.isFinite ? speed : nil
            $0.satelliteCount = Int(state.satelliteCount)
            $0.flightMode = state.flightModeString
            $0.motorsOn = state.areMotorsOn
            $0.isFlying = state.isFlying
            $0.homeLocationSet = state.isHomeLocationSet
            $0.imuPreheating = state.isIMUPreheating
            $0.flightTimeSeconds = Int(state.flightTimeInSeconds)
            $0.pitchDegrees = Double(state.attitude.pitch)
            $0.rollDegrees = Double(state.attitude.roll)
            $0.yawDegrees = Double(state.attitude.yaw)
            if let position, CLLocationCoordinate2DIsValid(position) {
                $0.latitude = position.latitude
                $0.longitude = position.longitude
            } else {
                $0.latitude = nil
                $0.longitude = nil
            }
            if state.isHomeLocationSet, let home, CLLocationCoordinate2DIsValid(home) {
                $0.homeLatitude = home.latitude
                $0.homeLongitude = home.longitude
            } else {
                $0.homeLatitude = nil
                $0.homeLongitude = nil
            }
        }
    }
}
#endif
