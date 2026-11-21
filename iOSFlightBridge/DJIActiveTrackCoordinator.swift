import CoreGraphics
import Foundation

#if canImport(DJISDK) && GROUNDSTATION_ACTIVE_TRACK_TESTED
import DJISDK
#endif

/// DJI-native ActiveTrack state machine for original Mavic Pro.
/// Apple Vision runs on the Mac; DJI vision and flight control run *on aircraft*.
/// The Mac's bounding box is forwarded in DJI's top-left normalised coordinates.
///
/// Flight movement is intentionally unavailable in default builds. To permit
/// commissioning a build flag alone is NOT sufficient: the link needs TLS,
/// latency/failsafe tests, VLOS pilot and proven physical RC emergency override.
final class DJIActiveTrackCoordinator: NSObject {
    var onState: ((String, TrackingRectangle?, Bool, String?) -> Void)?

    private var pendingRect: TrackingRectangle?
    private var preparedAt: Date = .distantPast
    private var lastState = "Idle"
    private var aircraftMovementApproved = false

    #if canImport(DJISDK) && GROUNDSTATION_ACTIVE_TRACK_TESTED
    private var activeOperator: DJIActiveTrackMissionOperator? {
        DJISDKManager.missionControl()?.activeTrackMissionOperator
    }

    private var listenerInstalled = false

    func startListening() {
        guard !listenerInstalled, let op = activeOperator else { return }
        listenerInstalled = true
        op.addListener(toEvents: self, with: .main) { [weak self] event in
            guard let self else { return }
            let state = String(describing: event.currentState)
            let rectangle = event.trackingState.map { tracking -> TrackingRectangle in
                TrackingRectangle(x: Double(tracking.targetRect.minX),
                                  y: Double(tracking.targetRect.minY),
                                  width: Double(tracking.targetRect.width),
                                  height: Double(tracking.targetRect.height))
            }
            let error = event.error?.localizedDescription
            let following = state.lowercased().contains("aircraftfollowing")
            if !following { self.aircraftMovementApproved = false }
            self.lastState = state
            self.onState?(state, rectangle?.isValid == true ? rectangle : nil,
                          following, error)
        }
    }

    func connected() {
        startListening()
    }
    #else
    func connected() {}
    #endif

    /// Prepares a DJI mission at a manually confirmed target rectangle.
    /// With DJI's native ActiveTrack this step should track while HOVERING.
    /// The first stage never authorizes aircraft movement.
    func prepare(_ rect: TrackingRectangle, completion: @escaping (Bool, String) -> Void) {
        guard rect.isValid else {
            completion(false, "Target box is invalid or outside the camera")
            return
        }
        pendingRect = rect
        preparedAt = Date()
        aircraftMovementApproved = false

        #if canImport(DJISDK) && GROUNDSTATION_ACTIVE_TRACK_TESTED && GROUNDSTATION_ACTIVE_TRACK_TESTED
        guard let op = activeOperator else {
            completion(false, "DJI ActiveTrack mission operator not supported")
            return
        }
        startListening()
        let mission = DJIActiveTrackMission()
        mission.targetRect = CGRect(x: rect.x, y: rect.y,
                                    width: rect.width, height: rect.height)
        mission.mode = .trace
        if let error = op.canStartMission(mission) {
            completion(false, "DJI cannot prepare ActiveTrack: \(error.localizedDescription)")
            return
        }
        op.startMission(mission, withCompletion: { [weak self] error in
            guard let self else { return }
            self.lastState = error == nil ? "Target prepared — awaiting confirmation" :
                "ActiveTrack preparation rejected"
            self.onState?(self.lastState, rect, false, error?.localizedDescription)
            completion(error == nil, error?.localizedDescription ??
                       "Target prepared; aircraft movement NOT authorised")
        })
        #else
        lastState = "DJI follow LOCKED — local target preview only"
        onState?(lastState, rect, false, nil)
        completion(false, "Native ActiveTrack flight remains locked: secure transport and flight-safety validation required")
        #endif
    }

    /// Explicit DJI confirmation is the point at which the aircraft would
    /// start moving relative to the target. Never bypass that confirmation.
    func confirm(completion: @escaping (Bool, String) -> Void) {
        #if canImport(DJISDK) && GROUNDSTATION_ACTIVE_TRACK_TESTED && GROUNDSTATION_ACTIVE_TRACK_TESTED
        guard pendingRect != nil,
              Date().timeIntervalSince(preparedAt) < 25,
              let op = activeOperator else {
            completion(false, "Target preparation expired or DJI ActiveTrack unavailable")
            return
        }
        op.acceptConfirmation(completion: { [weak self] error in
            self?.aircraftMovementApproved = error == nil
            completion(error == nil, error?.localizedDescription ??
                       "DJI accepted confirmation; ActiveTrack may move the aircraft")
        })
        #else
        completion(false, "Autonomous aircraft-follow confirmation is locked")
        #endif
    }

    /// This stop must be reachable even if the Mac loses its connection.
    func stop(completion: ((Bool, String) -> Void)? = nil) {
        pendingRect = nil
        preparedAt = .distantPast
        aircraftMovementApproved = false
        lastState = "Stop requested"
        onState?(lastState, nil, false, nil)
        #if canImport(DJISDK) && GROUNDSTATION_ACTIVE_TRACK_TESTED
        guard let op = activeOperator else {
            completion?(false, "DJI ActiveTrack operator unavailable")
            return
        }
        op.stopMission(completion: { [weak self] error in
            self?.lastState = error == nil ? "Stopped" : "DJI stop failed"
            self?.onState?(self?.lastState ?? "Stopped", nil, false,
                           error?.localizedDescription)
            completion?(error == nil, error?.localizedDescription ??
                        "DJI ActiveTrack stop acknowledged")
        })
        #else
        completion?(true, "No DJI SDK active; local target cleared")
        #endif
    }

    func lostMacConnection() {
        // If a mission ever became active, request stop independently of
        // the Mac-to-iPhone socket. DJI's flight controller still manages its
        // own independent safety state.
        if pendingRect != nil || aircraftMovementApproved {
            stop()
        }
    }
}
