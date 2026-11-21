# GroundStation verification

## Automated review

Generate the Xcode project and run the GroundStationReview scheme on macOS. It includes bridge and route regressions plus a UI workflow through Team, Route Library, waypoint editing, cockpit, Activity and connection settings. Xcode records the actual Mac windows as test attachments. The no-DJI workflow also builds the Mac app, iPhone simulator app and optional Core ML resource.

## Physical integration

Record the Xcode, iOS, app revision, controller and aircraft firmware versions for each run. The hardware integration requires a DJI developer app key and the pinned CocoaPods. The no-SDK simulator reports demo status and has no camera feed. [DJI app setup](DJIAppSetup.md)

For a stationary bench test, verify the original controller, iPhone 15 data cable and official DJI sample detect the aircraft. Check that the Mac distinguishes controller-only, real aircraft, DJI simulator, demo and stale states. Compare displayed telemetry with the device, verify disconnection clears live readings and check foreground/background transitions on the phone. Record latency and recovery separately for the camera and telemetry.

Verify two-device pairing, wrong credentials, key rotation, clipboard expiry and reconnecting with the new code. Validate VoiceOver navigation and readability at the operator’s display settings. Flight behaviour and physical RC takeover need separate hardware evidence. [Security and usability review](WorkspaceReview.md) · [Hardware limitations](LiveFlight.md)
