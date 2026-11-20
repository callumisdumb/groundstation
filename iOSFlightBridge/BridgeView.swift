import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BridgeView: View {
    @StateObject private var server = BridgeServer()
    @Environment(\.scenePhase) private var phase
    @State private var listeningRequested = true
    @State private var showFlightSetup = false
    @State private var revealFlightKey = false
    @State private var confirmRotation = false
    @State private var copyNotice: String?
    @State private var copyTime = Date.distantPast
    private let blue = Color(red: 0.17, green: 0.42, blue: 0.94)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "square.grid.2x2.fill")
                Text("GroundStation").font(.headline)
                Spacer()
                Label(server.running ? "Listening" : "Stopped",
                      systemImage: server.running ? "antenna.radiowaves.left.and.right" : "pause.circle")
                    .font(.subheadline)
            }.padding().background(Color(red: 0.116, green: 0.215, blue: 0.688))
            List {
                Section {
                    LabeledContent("Device", value: "iPhone bridge")
                    LabeledContent("Wi-Fi address", value: server.running ? (server.localAddress ?? "Wi-Fi unavailable") : "—")
                    if phase == .active, server.running {
                        LabeledContent("Session code") {
                            Text(server.pairingCode).font(.title2.bold().monospacedDigit()).privacySensitive()
                        }
                    }
                    Button { copy(server.bridgeKey, name: "Bridge key") } label: {
                        Label("Copy bridge key for Mac", systemImage: "doc.on.doc")
                    }.disabled(server.bridgeKey.isEmpty || !server.running)
                } header: {
                    Text("Ground Station")
                } footer: {
                    Text("On the Mac, open Connect bridge. Enter the Wi-Fi address, session code and bridge key.")
                }
                Section("Aircraft") {
                    Label(server.djiStatus, systemImage: "airplane").font(.subheadline)
                    DJIFramePreviewSurface().frame(height: 140)
                        .listRowInsets(EdgeInsets())
                        .accessibilityLabel("Aircraft camera decoder")
                }
                Section("Connection") {
                    Text(server.lastEvent).font(.callout).foregroundStyle(.secondary)
                    Button(server.running ? "Stop bridge" : "Start bridge") {
                        if server.running {
                            listeningRequested = false
                            server.stop()
                        } else {
                            listeningRequested = true
                            server.start()
                        }
                    }
                }
                Section {
                    DisclosureGroup("Flight-control pairing", isExpanded: $showFlightSetup) {
                        Text("The flight key is a separate credential for the Mac cockpit. Share it only with the operator.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Copy flight key for Mac") { copy(server.flightAccessKey, name: "Flight key") }
                            .disabled(server.flightAccessKey.isEmpty)
                        Button(revealFlightKey ? "Hide flight key" : "Reveal flight key") { revealFlightKey.toggle() }
                        if revealFlightKey && phase == .active {
                            Text(server.flightAccessKey).font(.caption.monospaced())
                                .textSelection(.enabled).privacySensitive()
                        }
                        Button("Reset paired keys", role: .destructive) { confirmRotation = true }
                    }
                } footer: {
                    Text("Copy for Mac uses the system clipboard, including Universal Clipboard when enabled. Copied keys expire after 60 seconds.")
                }
                if let copyNotice, phase == .active {
                    TimelineView(.periodic(from: .now, by: 1)) { clock in
                        if clock.date.timeIntervalSince(copyTime) < 60 {
                            Text(copyNotice).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .confirmationDialog("Reset paired keys?", isPresented: $confirmRotation, titleVisibility: .visible) {
                Button("Disconnect and reset keys", role: .destructive) {
                    revealFlightKey = false
                    copyNotice = nil
                    server.resetPairing(restart: listeningRequested)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This disconnects the Mac and invalidates both saved keys. Pair each Mac again.")
            }
        }
        .preferredColorScheme(.dark).tint(blue)
        .onAppear { if listeningRequested { server.start() } }
        .onDisappear { server.stop() }
        .onChange(of: phase) { next in
            if next != .active { revealFlightKey = false; showFlightSetup = false }
            if next == .background { server.stop() }
            if next == .active && listeningRequested { server.start() }
        }
    }

    private func copy(_ key: String, name: String) {
        guard !key.isEmpty else { return }
        copyTime = Date()
        UIPasteboard.general.setItems([[UTType.plainText.identifier: key]],
                                     options: [.expirationDate: copyTime.addingTimeInterval(60)])
        copyNotice = "\(name) copied for 60 seconds."
    }
}
