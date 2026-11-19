import SwiftUI

struct BridgeView: View {
    @StateObject private var server = BridgeServer()

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 42))
            Text("Mavic Flight Bridge").font(.largeTitle.bold())
            Text("Milestone B • read-only DJI SDK integration")
                .foregroundStyle(.secondary)

            GroupBox("Network server") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Status", value: server.running ? "Listening" : "Stopped")
                    LabeledContent("Address", value: server.localAddress ?? "Finding Wi-Fi address…")
                    LabeledContent("Port", value: "8765")
                    Button(server.running ? "Stop server" : "Start server") {
                        server.running ? server.stop() : server.start()
                    }
                }
                .padding(.vertical, 5)
            }

            GroupBox("DJI SDK") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(server.djiStatus).font(.headline)
                    Text("Read-only telemetry. No aircraft flight commands are implemented.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            Text(server.lastEvent)
                .font(.caption.monospaced()).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .onAppear { server.start() }
        .onDisappear { server.stop() }
    }
}
