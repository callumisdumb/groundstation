import SwiftUI

struct ActivityWorkspace: View {
    @ObservedObject var client: BridgeClient

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Session activity")
                        .font(.system(size: 19, weight: .bold))
                    Text("Connection lifecycle, telemetry updates, DJI command results")
                        .font(.caption).foregroundStyle(GSPalette.muted)
                }
                Spacer()
                GSStatusChip(label: client.connected ? "BRIDGE LIVE" : "BRIDGE OFFLINE",
                             kind: client.connected ? .good : .caution)
                Button("Clear display") { client.logs.removeAll() }
            }
            GSPanel("System event log", icon: "list.bullet.rectangle") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 9) {
                        ForEach(client.logs) { event in
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: event.text.contains("failed") ||
                                      event.text.contains("error") ?
                                      "exclamationmark.triangle" : "circle.dotted")
                                    .foregroundStyle(event.text.contains("error") ?
                                                     GSPalette.amber : GSPalette.cyan)
                                Text(event.text)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Divider().overlay(GSPalette.border)
                        }
                        if client.logs.isEmpty {
                            Text("No events recorded in this session.")
                                .foregroundStyle(GSPalette.muted)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("Logs shown here are session-only; this prototype does not yet provide persistent flight-log archiving or synchronized video playback.")
                .font(.caption).foregroundStyle(GSPalette.muted)
        }
        .padding(16)
        .background(GSPalette.background)
    }
}
