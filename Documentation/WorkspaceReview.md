# FlightHub 2 design and GroundStation review

The reference is the English FlightHub 2 desktop manual available on 20 November 2026. The implementation runs natively on macOS 13 and later. GroundStation connects to one foreground iPhone bridge and saves route drafts on the Mac.

## Screen comparison

| Surface | DJI reference | GroundStation implementation |
| --- | --- | --- |
| Project and Team | Blue left rail, project name, call sign, grouped stations, devices and members beside satellite imagery. [DJI Team screenshot](https://fh.dji.com/user-manual/local-image/real-time-project-information/online-project-information/en/dock4-online-info-en.webp) | 46-point rail, 264-point collapsible charcoal panel, editable local call sign, iPhone status and aircraft telemetry. The local member is labelled “This Mac”. |
| Map | Zoom, project recenter, map search, standard/satellite basemaps, green planned route and blue trajectory. [DJI Map Details](https://fh.dji.com/user-manual/en/map/map-details.html) | Native MapKit with searchable local routes, aircraft and coordinates. Layer switches control the selected draft and session track. Numbered pins show waypoint order. |
| Route Library | A light file browser over the map, with a folder column, list toolbar, selected rows and search. [DJI Route Library screenshot](https://fh.dji.com/user-manual/local-image/584.jpg) | A local routes folder, searchable list, sort by update time, creation, contextual deletion and a separate editor. Older drafts use their creation date until edited. |
| Waypoint editor | Map canvas and a dark settings inspector on the right. [DJI editor screenshot](https://fh.dji.com/user-manual/private_images/wayline_editer_en.png) | Waypoint and Settings tabs, numbered positions, altitude, rename and GeoJSON export. The editor identifies the route as a local draft. |
| Virtual Cockpit | Auxiliary view above the lower-left map, main camera to the right, navigation instruments and contextual controls. [DJI cockpit screenshot](https://fh.dji.com/user-manual/local-image/real-time-project-information/virtual-cockpit/en/overview-v2-en.webp) | The primary H.264 feed, heading, telemetry and existing inspectors use this arrangement. The original Mavic Pro bridge supplies one camera. The auxiliary pane identifies the missing source. |
| iPhone companion | DJI’s desktop project screens describe enterprise devices and docks. [Supported devices](https://fh.dji.com/user-manual/en/before-using.html) | The iPhone shows the local bridge address, pairing state, camera diagnostics and key management. GroundStation uses its own identity and native Apple window controls, symbols, map imagery and attribution. |

The native screenshot suite captures the project, populated route browser, waypoint editor and disconnected cockpit. Their contents vary with the window, map tiles, saved routes and actual device state. Exact pixel identity across devices and all FlightHub 2 screens has not been established. Cloud organisations, enterprise docks, scheduled dispatch and multi-camera feeds have no corresponding backend in this repository.

## Security and usability findings

| Finding in the development branch | Change and remaining exposure |
| --- | --- |
| The telemetry server sent aircraft status before verifying the peer. Video, camera requests and command acknowledgements crossed the LAN in cleartext. | Both ports now require a paired TLS session before producing application data. The six-digit code salts a high-entropy credential. Separate channel keys bind the telemetry and video sessions to their intended uses. |
| An incoming socket could take over an active session. The command ID cache could empty while accepted commands were still fresh. | Each listener authenticates bounded, time-limited candidates, preserves an established peer and releases control on disconnect. The command ID cache retains accepted IDs until their timestamp window closes, including across socket replacement. |
| The long-lived flight credential could stay on the general clipboard. | Explicit Copy for Mac uses a 60-second expiry, with Universal Clipboard available when enabled. Key rotation on the phone closes sessions and replaces both credentials. Clipboard expiry cannot recall a copy already taken by another device or app. [Apple pasteboard options](https://developer.apple.com/documentation/uikit/uipasteboard/optionskey) |
| Valid bridge packets could keep old aircraft readings looking current. A frozen camera could continue to show the last reported FPS. | The Mac checks the time of the actual flight-controller sample and the time since reception. The camera labels a stalled stream after three seconds. Missing headings and positions stay empty. |
| Longitude-only motion could disappear from the track. Each UI update rebuilt every map annotation. | Position recording observes each telemetry receipt. The map updates device pins in place, redraws a changed route or track and keeps static callouts intact. |
| The route editor hid file errors, could overwrite an unreadable library and deleted entire routes in one click. | Edits update the in-memory selection after an atomic save. An unreadable library is preserved, the editor reports errors and deletion requests confirmation. |
| Compact icon controls relied on visual recognition. An open pairing form could coexist with keyboard capture. | Navigation and map controls have accessible names and selected-state feedback. Navigation and pairing release cockpit keyboard capture. Search, editor fields and native dialogs remain keyboard accessible. [Apple accessibility and colour](https://developer.apple.com/design/human-interface-guidelines/color) |

## Trust boundary

The iPhone and the Mac use Apple Network.framework with TLS 1.2 PSK and AES-128-GCM. Each endpoint checks the negotiated cipher suite. The bridge key is derived from a random 256-bit Keychain credential with HKDF-SHA256. The bridge key permits observation and camera commands. Protected flight commands still require the separate AES-GCM flight key and the existing phone-side authorization checks. Both app versions must be upgraded together. [Apple peer networking](https://developer.apple.com/documentation/network/building-a-custom-peer-to-peer-protocol) · [Apple PSK API](https://developer.apple.com/documentation/security/sec_protocol_options_add_pre_shared_key(_:_:_:)) · [OWASP MASVS-NETWORK-1](https://mas.owasp.org/MASVS/controls/MASVS-NETWORK-1/)

This static PSK suite lacks forward secrecy. A holder of a bridge credential and current code can authenticate as a bridge peer. Resetting paired keys revokes every paired Mac together. Local network availability, a compromised endpoint and copies of exported routes remain outside this protection. The route JSON is stored under the macOS user account. Activity is a bounded in-memory display, with no durable audit trail. [RFC 5487](https://www.rfc-editor.org/rfc/rfc5487)

The Podfile pins the DJI SDK and DJIWidget. The FlySafe resource uses a compatible-version range, and this repository has no lockfile for the hardware build. The optional model installer retrieves an Apple-hosted file over HTTPS and checks its size. It does not pin a content digest. These external inputs and the physical SDK build remain part of the supply-chain review.

## Verification

The native review scheme tests positive and negative TLS pairing, flight-key separation, replay-window capacity and expiry, legacy route storage, export coordinates and recovery from a damaged file. A UI test exercises the actual Mac application and records window screenshots. CI also compiles both application targets without DJI pods and builds the optional model into the Mac bundle. A separate job installs the bridge pods and builds the DJIWidget static library for iPhone. The screenshot archive is attached to the GitHub Actions run.

Physical iPhone Keychain/Handoff behaviour, DJI SDK v4 and DJIWidget on the original controller, video latency, aircraft behaviour and physical controller takeover require device evidence. A successful scaffold build does not validate flight behaviour.
