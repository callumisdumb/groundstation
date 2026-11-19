import SwiftUI

enum GSPalette {
    static let background = Color(red: 0.052, green: 0.068, blue: 0.087)
    static let side = Color(red: 0.075, green: 0.091, blue: 0.116)
    static let panel = Color(red: 0.092, green: 0.112, blue: 0.140)
    static let raised = Color(red: 0.125, green: 0.150, blue: 0.181)
    static let border = Color.white.opacity(0.10)
    static let highlight = Color(red: 0.18, green: 0.65, blue: 0.77)
    static let slate = Color(red: 0.16, green: 0.20, blue: 0.25)
    static let cyan = Color(red: 0.24, green: 0.82, blue: 0.94)
    static let green = Color(red: 0.29, green: 0.85, blue: 0.60)
    static let amber = Color(red: 1.0, green: 0.70, blue: 0.32)
    static let muted = Color(red: 0.58, green: 0.65, blue: 0.74)
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
                    Text(title.uppercased())
                        .tracking(0.8)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 0)
                }
            }
            content
        }
        .padding(15)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(LinearGradient(colors: [
                    Color(red: 0.12, green: 0.15, blue: 0.19),
                    GSPalette.panel
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.13)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(LinearGradient(colors: [
                    .white.opacity(0.13),
                    .white.opacity(0.025)
                ], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
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
        .clipShape(Capsule())
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
