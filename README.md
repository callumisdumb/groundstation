# Mavic Ground Station

GroundStation is a native macOS console and iPhone communications bridge for the original DJI Mavic Pro. The Mac opens on a FlightHub 2-style project map. The iPhone connects to the original remote controller and relays telemetry and video over a paired local connection.

| Mac workspace | What you can do |
| --- | --- |
| Team | View bridge and aircraft status, change your call sign, search the map, switch layers and recenter on a device or saved route. |
| Flight Route Library | Create and edit local waypoint drafts, reopen earlier routes and export GeoJSON. |
| Virtual Cockpit | Open the Pilot station with ⌘3, see the next flight step and press ? for keyboard practice or the live control map. |
| Activity | Search session events and filter flight-control replies. |

The no-SDK build supplies simulated bridge data. The hardware integration targets DJI Mobile SDK v4.16.2. Live operation, video latency and controller takeover still require validation on the original Mavic Pro and iPhone. [Design, security and usability review](Documentation/WorkspaceReview.md) · [Hardware validation](Documentation/TestingPlan.md)

## Build

Use Xcode and XcodeGen on a Mac. The deployment targets are macOS 13 and iOS 16. In a checkout of the revision you want to run, generate the project and open it.

```bash
brew install xcodegen
xcodegen generate
open MavicGroundStation.xcodeproj
```

Build the `MacGroundStation` scheme on the Mac. For an iPhone, choose `iOSFlightBridge`, configure your Apple development team and build it from the same revision. Install the pinned DJI CocoaPods and open the generated workspace only for the hardware integration. Keep the DJI app key in the gitignored configuration file. [DJI app setup](Documentation/DJIAppSetup.md) · [Compatibility notes](Documentation/DJIIntegration.md)

## Pair the bridge

1. Open the bridge on the iPhone and keep it in the foreground. Allow local network access. The Mac and phone must be able to reach each other on the local network.
2. In the Mac project, choose **Connect bridge**. Enter the address and current six-digit session code from the phone.
3. On the phone choose **Copy bridge key for Mac**. Paste it into **Bridge key** on the Mac, then choose **Connect**. The Mac saves the key in Keychain. An existing paired flight key can also supply the bridge credential when the bridge-key field is empty.
4. For pilot access, open **Flight-control pairing** on the paired Mac, paste the phone’s flight key and choose **Verify flight key**.

The phone renews the short code when the listeners restart. Copy for Mac uses the system clipboard for 60 seconds and supports Universal Clipboard. On a Mac without Handoff, transfer the key through a trusted channel. **Reset paired keys** on the phone disconnects the current Mac and revokes the old keys. Update both apps together when upgrading from the earlier plaintext protocol.

Telemetry and command traffic use TCP port 8765 and H.264 uses TCP port 8766. Each port has its own authenticated TLS session. Pairing a bridge leaves live flight locked. [Transport review](Documentation/WorkspaceReview.md#trust-boundary) · [Live video](Documentation/LiveVideo.md)

## Keyboard flight

Open **⌘3 → Flight setup** and select the live aircraft or DJI simulator. The Pilot station shows the next available action. After confirmed takeoff, choose **Fly with keyboard** and wait for the iPhone grant. Hold **Space** plus **WASD** or the **arrows** to translate, **Q/E** to turn and **C/Z** to ascend or descend. Release Space for neutral or press **Esc** to hand control back. Open **? → Practice keys** to try the controls entirely on the Mac. [Controls and flight readiness](Documentation/VirtualCockpit.md#virtual-cockpit)

## Hardware and operating guides

The hardware setup uses an Apple Silicon Mac, iPhone 15, original Mavic Pro and its standard remote controller with a compatible USB-C data cable. The controller’s side cable must be disconnected when using its bottom USB port.

- [Project, Route Library and cockpit](Documentation/VirtualCockpit.md)
- [Mac controls and device checks](Documentation/MacControlTesting.md)
- [Experimental live-flight authorization and limitations](Documentation/LiveFlight.md)
- [Local Vision and optional Core ML model](Documentation/AITracking.md)

## Verification

```bash
xcodegen generate
xcodebuild test -project MavicGroundStation.xcodeproj -scheme GroundStationReview \
  -destination 'platform=macOS' -parallel-testing-enabled NO
```

The review scheme uses a temporary route library for UI tests. GitHub Actions builds the Mac and iPhone simulator targets, compiles the complete DJI-enabled iPhone bridge, tests the keyboard and workspace flows, collects native screenshots and verifies optional model packaging.
