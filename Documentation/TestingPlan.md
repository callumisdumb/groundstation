# Test Plan

## A: Local bridge (current prototype)

- Install and run the Mac application.
- Install and run the iPhone application on a physical iPhone 15.
- Confirm Local Network permission is granted on iPhone.
- Confirm both devices are on the same Wi-Fi LAN.
- Enter the iPhone IPv4 address shown on-screen into the Mac app, port 8765.
- Confirm the Mac displays a SIMULATED status every second.
- Verify disconnect/reconnect, and that no take-off, landing or movement controls exist.
- Do not test the prototype on a public network.

## B: DJI read-only integration (not implemented)

- Build and run the *official* DJI Mobile SDK iOS Swift sample.
- Connect the original Mavic Pro controller to iPhone 15 with compatible USB-C data cable.
- Confirm SDK registration and product connection.
- Confirm read-only aircraft state, GPS and battery callbacks.
- Replace only the simulated status provider, preserving the \`simulated\` marker distinction.
- Re-test network disconnects and unexpected aircraft disconnects.

## C: Video (not implemented)

- Render SDK video locally on iPhone using the documented sample.
- Transport encoded video to Mac only after measuring latency and dropped frames.

## D: Flight control (not implemented)

Separate flight-safety engineering review required: operator arming, bounded command set, command sequence numbers/freshness, link-loss watchdog, RTH configuration, simulator testing, controlled ground testing, physical controller fallback and UK CAA compliance.
