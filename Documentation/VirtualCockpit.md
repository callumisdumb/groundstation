# GroundStation workspaces

## Project

The Team screen opens on the satellite map. The blue navigation rail opens the project, Flight Route Library, Virtual Cockpit and Activity. Collapse the device panel for more map space. Call signs and the single local member belong to this Mac. Select a linked aircraft to recenter the map on its latest valid position.

**Map layers** switches between satellite and standard imagery and controls the route and track overlays. **Search project map** accepts a saved route name, the current aircraft model or decimal latitude and longitude. Route numbers follow waypoint order. The green line joins draft waypoints and the blue line follows received aircraft positions.

## Route Library

Choose the plus button to make a local draft, or open an existing route. Enter coordinates in the Waypoints tab. Settings contains rename, GeoJSON export and delete. Deleting a route requires confirmation. Route files live in the user’s Application Support directory under `GroundStation/mission-routes.json`. The editor preserves the earlier file format and reports load and write errors.

## Virtual Cockpit

Use **Virtual Cockpit** from Team or the rail. The primary camera is on the right, with its contextual tool column and instrument display. The left column has the auxiliary source state and map. The original bridge supplies a single video stream. The empty auxiliary pane labels that state. **Map focus** gives the map more space. The back arrow returns to Team.

The keyboard button displays the existing key panel. Opening a connection form, leaving the cockpit, disconnecting or losing app focus releases the held inputs. The camera view identifies a stalled feed and the project status identifies stale or simulated telemetry. The hardware-specific authorization and physical validation requirements are described in the [live-flight guide](LiveFlight.md).

[Reference screenshots and comparison](WorkspaceReview.md) · [Video diagnostics](LiveVideo.md)
