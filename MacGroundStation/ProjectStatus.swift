import SwiftUI

enum ProjectStatus: String {
    case offline = "Offline"
    case pairing = "Pairing"
    case waiting = "Waiting for telemetry"
    case stale = "Telemetry stale"
    case demo = "Simulated telemetry"
    case simulator = "DJI Simulator"
    case bridge = "Bridge online"
    case aircraft = "Aircraft online"

    @MainActor
    init(client: BridgeClient, now: Date) {
        if client.connecting { self = .pairing }
        else if !client.connected { self = .offline }
        else if let received = client.lastTelemetryAt, let p = client.latestStatus?.payload {
            if now.timeIntervalSince(received) > 3 { self = .stale }
            else if p.simulated == true { self = .demo }
            else if p.validAircraft && p.aircraftSampledAt == nil { self = .waiting }
            else if p.validAircraft && (client.aircraftDataAge(at: now) ?? .infinity) > 3 { self = .stale }
            else if p.djiSimulatorActive == true { self = .simulator }
            else if p.validAircraft { self = .aircraft }
            else { self = .bridge }
        } else { self = .waiting }
    }

    var tint: Color {
        switch self {
        case .aircraft, .bridge: return GSPalette.green
        case .demo, .simulator: return GSPalette.cyan
        case .waiting, .pairing, .stale: return GSPalette.amber
        case .offline: return GSPalette.muted
        }
    }

    var hasAircraftData: Bool { self == .aircraft || self == .simulator }
}

struct ProjectIconButton: View {
    let label: String
    let symbol: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 34)
                .foregroundStyle(selected ? GSPalette.cyan : .white)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}
