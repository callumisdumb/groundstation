# Continuous H.264 video: iPhone → Mac

## What changed

Previously the Mac displayed an occasional JPEG extracted from DJIWidget's
preview (~1 image every 2 seconds). The new code relays the **original continuous
H.264 byte stream** from DJI's iOS Mobile SDK v4 directly to the Mac.

| Link | Direction | Port | Payload |
| --- | --- | --- | --- |
| Telemetry and commands | bidirectional | 8765/TLS over TCP | newline-delimited JSON |
| Camera video | iPhone → Mac | 8766/TLS over TCP | 4-byte big-endian length, then arbitrary H.264 byte chunk |

The video endpoint authenticates the bridge key and session code during its TLS handshake. Both apps must run the paired-transport revision. [Pair the bridge](../README.md#pair-the-bridge)

After authentication, each received compressed chunk gets a 4-byte network-order
length prefix. A chunk is **not necessarily a complete frame or a NAL unit**.
The Mac reassembles Annex-B NAL start codes, SPS and PPS parameter sets, and
slices into H.264 access units. The Mac uses CoreMedia and
\`AVSampleBufferDisplayLayer\` (native macOS hardware-backed video decode)
for display. No FFmpeg or extra Mac video dependencies are required.

The iPhone continues using DJIWidget for its own diagnostic camera surface,
but **does not create JPEG snapshots for the Mac**.

## Run the new video version

Stay on the currently checked-out branch, \`feature/dji-v4-readonly\`:

\`\`\`bash
cd /path/to/groundstation
xcodegen generate
pod install
open MavicGroundStation.xcworkspace
\`\`\`

Build and run **iOSFlightBridge** on the real iPhone 15.
Then build and run **MacGroundStation** on the Mac.

1. Remove the Mavic Pro's **propellers** for bench testing.
2. Power on the controller and drone; verify they are actually linked.
3. Connect the iPhone to the controller with the compatible USB-C cable.
4. Keep the Flight Bridge app active on the iPhone and both devices on the same trusted Wi-Fi.
5. In the Mac app, enter the iPhone’s address, bridge key and current six-digit code, and click **Connect**.
6. The Mac establishes **two** separate sockets (8765 and 8766).
7. The camera panel should change to **LIVE H.264**, with an FPS counter after decoded frames arrive.

## Troubleshooting

**Still waiting for H.264 parameter sets**
- Ensure the iPhone's DJI camera preview displays live imagery.
- Check the controller and aircraft are fully linked; \`Only RemoteController\`
  cannot supply flight-controller telemetry or camera video.
- Close DJI GO 4 while using the Flight Bridge app.
- Confirm that port 8766 is reachable on the iPhone, that the pairing code
  matches, and that both apps were rebuilt from this commit.
- DJI H.264 feed can require waiting for SPS/PPS and the next IDR (keyframe).
  Restart the app if the stream decoder never acquires a keyframe.
- The original Mavic Pro's firmware/link mode affects the DJI video decoder.
  Compare against DJI's official Swift FPV example.

**Video stutters / freezes**
- A shared Wi-Fi network or network changes may create jitter.
- macOS drops frames when the display layer cannot enqueue more samples.
- The iPhone relay drops encoded chunks during excessive network backlog
  (over 768 KiB) to keep telemetry unaffected. H.264 recovers at a later IDR.
- Check the Mac's H.264 FPS indicator and the DJI preview on the iPhone.

**TCP connection reset**
- Most often a stopped/restarted iPhone app or Wi-Fi link switch. The Mac
  clears stale video state and requires reconnecting; this is intentional.
- There is no automatic reconnection loop in this prototype.

**Green/black frames, wrong aspect ratio**
- Native H.264 decoding still needs real Mavic hardware testing, especially
  for multiple slices, parameter-set changes, and firmware-specific metadata.
  Report the exact stream status and Xcode logs; don't fly until resolved.

## Limitations and security

- The video port requires paired TLS. Keep the bridge on the local network. [Transport and remaining risks](WorkspaceReview.md#trust-boundary)
- Continuous video does not by itself guarantee a safe control-to-photon
  latency or enough frame reliability for remote piloting.
- Flight and motor commands remain **locked by default**, independent of video.
- No audio, video recording to disk, application-level retransmit logic, or
  latency instrumentation is provided yet.
- Keep the RC available, maintain visual line of sight and follow applicable CAA rules.

Sources:
- DJI iOS FPV tutorials:
  https://developer.dji.com/mobile-sdk/documentation/ios-tutorials/index.html
- Apple: AVSampleBufferDisplayLayer
  https://developer.apple.com/documentation/avfoundation/avsamplebufferdisplaylayer
