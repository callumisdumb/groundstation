import CoreLocation
import SwiftUI

enum GSPalette {
    static let rail = Color(red: 0.116, green: 0.215, blue: 0.688)
    static let background = Color(white: 0.10)
    static let side = Color(white: 0.152)
    static let panel = Color(white: 0.183)
    static let raised = Color(white: 0.246)
    static let border = Color(white: 0.29)
    static let highlight = Color(red: 0.19, green: 0.48, blue: 0.98)
    static let slate = Color(white: 0.22)
    static let cyan = Color(red: 0.39, green: 0.65, blue: 1)
    static let green = Color(red: 0.39, green: 0.85, blue: 0.42)
    static let amber = Color(red: 1.0, green: 0.73, blue: 0.32)
    static let muted = Color(white: 0.74)
}

struct GSPanel<Content: View>: View {
    let title: String?
    let icon: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, icon: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon).foregroundStyle(GSPalette.cyan)
                    }
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 0)
                }
            }
            content
        }
        .padding(12)
        .background(GSPalette.panel)
        .overlay(Rectangle().strokeBorder(GSPalette.border, lineWidth: 1))
    }
}

struct GSStatusChip: View {
    let label: String
    let kind: Kind

    enum Kind { case good, caution, neutral, bad }

    private var tint: Color {
        switch kind {
        case .good: return GSPalette.green
        case .caution: return GSPalette.amber
        case .neutral: return GSPalette.cyan
        case .bad: return .red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

struct GSReadout: View {
    let label: String
    let value: String
    var symbol: String? = nil
    var tint: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.caption2) }
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.7)
            }
            .foregroundStyle(GSPalette.muted)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GSKeyCap: View {
    let text: String
    var active = false
    var wide = false
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(active ? GSPalette.background : .white.opacity(0.8))
            .frame(width: wide ? 94 : 32, height: 29)
            .background(active ? GSPalette.cyan : GSPalette.raised)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(active ? GSPalette.cyan : GSPalette.border))
    }
}

extension GroundStationMessage.Payload {
    var validAircraft: Bool {
        aircraftConnected == true && simulated != true
    }
    var aircraftPoint: CLLocationCoordinate2D? {
        guard validAircraft, let latitude, let longitude else { return nil }
        let point = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(point) ? point : nil
    }
    var homePoint: CLLocationCoordinate2D? {
        guard validAircraft, homeLocationSet == true, let homeLatitude, let homeLongitude else { return nil }
        let point = CLLocationCoordinate2D(latitude: homeLatitude, longitude: homeLongitude)
        return CLLocationCoordinate2DIsValid(point) ? point : nil
    }
    var batteryText: String { batteryPercent.map { "\($0)%" } ?? "—" }
    var altitudeText: String {
        altitudeMeters.map { String(format: "%.1f m", $0) } ?? "—"
    }
    var speedText: String {
        speedMetersPerSecond.map { String(format: "%.1f m/s", $0) } ?? "—"
    }
    var locationText: String {
        guard let latitude, let longitude else { return "Position unavailable" }
        return String(format: "%.5f, %.5f", latitude, longitude)
    }
}
