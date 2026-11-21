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
- DJIWidget iOS preview and a separate H.264 relay to the Mac (experimental)
- Unique system log IDs (fixes SwiftUI ForEach duplicate-ID warnings)
- Clear error reporting and reconnect workflow after iPhone TCP reset
- Cockpit pilot station with hold-to-move directions, key practice and confirmed handoff
- Authenticated telemetry and video sessions using the bridge key and a current six-digit code

### Experimental LIVE mode — explicit authorization required

- Simulator controls remain separate from real flight.
- LIVE takeoff, landing, RTH and Virtual Sticks are now wired through explicit short-lived preflight authorization and separate takeoff confirmation.
- Actual Mavic Pro flight has NOT been validated by CI; the physical RC must be ready for manual override.
- The live camera is not a certified low-latency piloting link.
- Read [LiveFlight.md](LiveFlight.md) for current operating conditions.

## How to test locally

On your Mac, from the \`groundstation\` repository:

\`\`\`bash
xcodegen generate
pod install
open MavicGroundStation.xcworkspace
\`\`\`

Rebuild **both** Xcode schemes (MacGroundStation and iOSFlightBridge).
Use the iPhone address, current code and bridge key. [Pair the bridge](../README.md#pair-the-bridge)
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
The iPhone also forwards compressed H.264 to the Mac on the paired video channel. First confirm the iPhone has a camera image.

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


## iPhone screen-awake mode

The iOS Flight Bridge app sets \`UIApplication.shared.isIdleTimerDisabled = true\`
while its SwiftUI scene is in the active foreground. The screen stays awake
without relying on the iPhone Auto-Lock setting.

Normal iOS Auto-Lock is restored if the app becomes inactive/backgrounded
or its main view disappears. The power button will still lock the phone,
and iOS can still suspend a backgrounded app. Keep the iPhone connected to
external power if running for an extended time.

## DJI Simulator and encrypted Mac keyboard testing

The phone stores a separate 256-bit flight credential in Keychain. Use **Copy flight key for Mac** and enter it in **Flight-control pairing** on the Mac. On a paired connection choose **Verify flight key**.

1. Remove the Mavic Pro’s propellers and link the physical remote and aircraft.
2. Run the iPhone bridge in the foreground and connect the Mac using the phone address, code and bridge key.
3. Open **⌘3 → Flight setup → DJI simulator**. Choose **Start DJI simulator…**, confirm and wait for the displayed mode to change.
4. Arm and confirm simulated takeoff. Once airborne, choose **Fly with keyboard** and wait for the iPhone’s grant.
5. Check every direction against the displayed simulator position and heading. Test releasing Space, holding opposing directions, changing windows, pressing Esc and interrupting the connection. Confirm handoff on the physical controller. [Keyboard map](VirtualCockpit.md#virtual-cockpit)
6. Land in the simulator, then choose **Stop DJI simulator…**.

DJI documents Virtual Stick control-data frequency 5–25 Hz. The Mac emits
bounded control data at 10 Hz while enabled, including neutral commands
when SPACE is released; the iPhone also enforces a 0.8-second watchdog.

The original Mavic Pro's SDK reports flight-controller simulator state
separately from UI simulated telemetry. Simulator output and direct flight
command results must be checked before trusting any control motion.

**LIVE manual flight now has an explicit authorization path**, but real control, RC takeover, video latency and connection-loss behaviour still need supervised hardware validation. **Autonomous ActiveTrack remains locked.** The Mac protocol is a prototype, not a certification.


## Update — live flight authorization (2026-11-19)

The previous blanket compile-time lock has been replaced by a separate,
short-lived **LIVE flight authorization** on the iPhone. Simulator testing
still requires propellers removed. Real takeoff can now be requested only
from the Mac **Control** panel after explicit operator acknowledgments.

This is an experimental integration and does **not** mean the real aircraft
path was tested or certified by CI. Read
[LiveFlight.md](LiveFlight.md) before attempting any real flight.
