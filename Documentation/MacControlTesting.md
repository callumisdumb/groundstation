# GroundStation — Mac-only operation and test plan

## Current scope

The Mac is intended to provide all operator controls. The iPhone is a foreground
DJI SDK communications relay connected by USB-C to the standard Mavic Pro RC.
The Mac talks to the iPhone over a trusted LAN.

### Included in this branch

- Mac/iPhone connected-state detection, read-only aircraft telemetry and warnings
- Aircraft-only battery (not controller battery): blanked when controller-only
- GPS coordinates, altitude, velocity, motor status, flight mode, pitch/roll/yaw,
  satellites, IMU preheat, flight duration and home point
- Mac gimbal pitch preset controls and photo/video camera commands
- DJIWidget iOS decoding and low-rate JPEG snapshots sent to the Mac (experimental)
- Unique system log IDs (fixes SwiftUI ForEach duplicate-ID warnings)
- Clear error reporting and reconnect workflow after iPhone TCP reset
- Mac-side flight UI scaffolding with hold-to-move directions and safety confirmations
- Six-digit pairing code displayed on iPhone and entered on Mac

### Deliberately unavailable until safety review

- Live takeoff/landing, motor start/stop, RTH and virtual-stick actions are **locked**
  using a \`GROUNDSTATION_FLIGHT_TESTED\` compilation flag NOT set by the project.
- Do not unlock them until an authenticated **encrypted** network protocol is
  implemented, simulator tests and real-device latency/failsafes validated.
- A JPEG every two seconds is NOT flight-grade live video.
- Flight should remain within applicable legal visual-line-of-sight restrictions.
- The physical RC must be available at all times.

## How to test locally (same branch; do not switch)

On your Mac, from the \`groundstation\` repository:

\`\`\`bash
git pull origin feature/dji-v4-readonly
xcodegen generate
pod install
open MavicGroundStation.xcworkspace
\`\`\`

Rebuild **both** Xcode schemes (MacGroundStation and iOSFlightBridge).
Enter the iPhone's Wi-Fi address and the new six-digit pairing code in the Mac app.
The code changes on each iPhone bridge app restart; entering it on the Mac does not
require operating flight controls on the phone.

### Test DJI RC vs aircraft

Before bench testing, **remove propellers**. Power up the RC and Mavic Pro and confirm
the RC screen indicates a connection. Use the DJI GO 4 app separately if you need
to relink the aircraft, then close it before launching Flight Bridge.

- If the Mac says **CONTROLLER ONLY**, SDK sees the RC, **not** a flight controller.
- In controller-only state, drone battery and position are intentionally empty.
- With valid aircraft link, fields should come from DJIFlightControllerState.
- If GPS/home point are blank while indoors, retry outdoors in a safe stationary area
  only after verifying the aircraft link; do not fly while debugging.

### Camera preview troubleshooting

The current preview uses DJIWidget 1.6.8 and DJIVideoPreviewer on the iPhone.
The video feed is decoded there, sampled at a low rate, and sent to the Mac as JPEG
in the existing TCP stream. First confirm the iPhone has a camera image.

If nothing appears:
1. Confirm the Mac reports a **real** aircraft link, not Only RemoteController.
2. Confirm camera status is connected; ensure DJI GO 4 is not competing for USB.
3. Compare the feed with DJI's official Swift sample CameraFPV demo:
   https://github.com/dji-sdk/Mobile-SDK-iOS/tree/master/Sample%20Code/SwiftSampleCode
4. The Mavic Pro's DJIWidget encoder settings may need adapting to firmware/link mode.
5. Do not confuse the sampled preview with safe low-latency flight video.

### Logs

- \`ForEach<Array<String> ID occurs multiple times\`: corrected by UUID-based log entries.
- \`Connection reset by peer\`: usually app restart, network switch or socket closure.
  Connection closure now clears stale telemetry and releases virtual-stick control.
- \`com.apple.linkd.autoShortcut\`: macOS/iOS system Intents service; not by itself
  evidence of a DJI SDK failure.
- \`ViewBridge ... Terminated\`: often UI service teardown; evaluate alongside crashes.

This code hasn't been built on the operator's local Mac/iPhone combination. If Xcode
reports a type error from legacy DJI SDK, capture the exact filename and line to
align Swift imported names with your installed 4.16.2 headers.
