import SwiftUI

struct ContentView: View {
    @StateObject private var client = BridgeClient()
    @State private var host = "192.168.1.100"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Mavic Ground Station").font(.largeTitle.bold())
                    Text("Prototype • telemetry link only").foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(client.connected ? .green : .red)
                    .frame(width: 10, height: 10)
                Text(client.connected ? "Bridge connected" : "Disconnected")
                    .font(.headline)
            }

            GroupBox("iPhone bridge connection") {
                HStack {
                    TextField("iPhone IP address", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    Button("Connect") { client.connect(host: host, port: 8765) }
                    Button("Disconnect") { client.disconnect() }
                }
                .padding(.vertical, 6)
            }

            GroupBox("Aircraft telemetry") {
                if let status = client.latestStatus {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                        GridRow {
                            metric("Connection", status.payload.connectionState ?? "—")
                            metric("Aircraft", status.payload.aircraftModel ?? "—")
                        }
                        GridRow {
                            metric("Battery", status.payload.batteryPercent.map { "\($0)%" } ?? "—")
                            metric("Altitude", status.payload.altitudeMeters.map { String(format: "%.1f m", $0) } ?? "—")
                        }
                        GridRow {
                            metric("Latitude", status.payload.latitude.map { String(format: "%.6f", $0) } ?? "—")
                            metric("Longitude", status.payload.longitude.map { String(format: "%.6f", $0) } ?? "—")
                        }
                        GridRow {
                            metric("Speed", status.payload.speedMetersPerSecond.map { String(format: "%.1f m/s", $0) } ?? "—")
                            metric("Source", status.payload.simulated == true ? "SIMULATED" : "DJI")
                        }
                    }
                    .padding(.vertical, 8)
                } else {
                    Text("Waiting for telemetry…").foregroundStyle(.secondary).padding()
                }
            }

            GroupBox("System log") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(client.logs, id: \.self) { line in
                            Text(line).font(.system(.caption, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 130)
            }

            Spacer()
            Text("Prototype only. Aircraft values are simulated until the DJI adapter is implemented.")
                .font(.footnote).foregroundStyle(.orange)
        }
        .padding(22)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
