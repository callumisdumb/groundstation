# GroundStation workspaces

## Project

The Team screen opens on the satellite map. The blue navigation rail opens the project, Flight Route Library, Virtual Cockpit and Activity. Collapse the device panel for more map space. Call signs and the single local member belong to this Mac. Select a linked aircraft to recenter the map on its latest valid position.

**Map layers** switches between satellite and standard imagery and controls the route and track overlays. **Search project map** accepts a saved route name, the current aircraft model or decimal latitude and longitude. Route numbers follow waypoint order. The green line joins draft waypoints and the blue line follows received aircraft positions.

## Route Library

Choose the plus button to make a local draft, or open an existing route. Enter coordinates in the Waypoints tab. Settings contains rename, GeoJSON export and delete. Deleting a route requires confirmation. Route files live in the user’s Application Support directory under `GroundStation/mission-routes.json`. The editor preserves the earlier file format and reports load and write errors.

## Virtual Cockpit

Press **⌘3** from any workspace to open the cockpit. The Pilot station sits above the map, with the camera and instruments on the right. Its main button follows the current aircraft state, from pairing to takeoff and keyboard handoff. Open **Flight setup** to see individual preflight readings or select **DJI simulator**. A draft opened with **View in cockpit** appears on the map as a planning overlay.

Press **?** for the key guide. Choose **Practice keys** to check your keyboard locally, even without a bridge. For the connected aircraft or DJI simulator, select **Fly with keyboard** after takeoff and wait for the iPhone to grant control. Press fresh keys after each grant.

| Input | Effect in captured flight or practice |
| --- | --- |
| Hold Space + W / S or ↑ / ↓ | Forward / backward relative to the nose |
| Hold Space + A / D or ← / → | Left / right relative to the nose |
| Hold Space + Q / E | Turn left / right |
| Hold Space + C / Z | Ascend / descend |
| Release Space | Send neutral input and clear held directions |
| X with Space released | Switch between precision and normal speed |
| Esc | End practice or request physical-controller handoff |

DJI’s FlightHub 2 guide informed the letter mappings and **?** guide. GroundStation uses Space as hold-to-move and offers arrow keys for translation. Precision selects 0.35 m/s horizontal speed. Normal selects 0.8 m/s. Diagonal input respects the same horizontal limit. In DJI SDK v4 body velocity mode, right maps to the SDK pitch field and forward maps to roll. [FlightHub 2 shortcuts](https://fh.dji.com/user-manual/en/real-time-project-information/virtual-cockpit.html) · [DJI velocity coordinate table](https://developer.dji.com/mobile-sdk/documentation/introduction/component-guide-flightController.html)

Opening a dialog, editing text, switching workspaces, or losing the key window ends capture. The phone neutralizes movement when input goes stale. **Release to controller** requests a handoff and waits for the SDK response. The phone operator can disconnect the Mac from **Pilot station**. Check physical control on the original hardware before relying on handoff. [Apple key-window notification](https://developer.apple.com/documentation/appkit/nswindow/didresignkeynotification) · [Live-flight verification](LiveFlight.md)

**⌘1** opens Team, **⌘2** the Route Library, and **⌘4** Activity. Use the **Flight control** activity filter to inspect flight-key and aircraft-command results.
