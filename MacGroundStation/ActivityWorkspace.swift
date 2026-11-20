import SwiftUI

struct ActivityWorkspace: View {
    @ObservedObject var client: BridgeClient
    @State private var query = ""
    @State private var confirmingClear = false

    private var events: [GroundStationLogEntry] {
        client.logs.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Label("Session activity", systemImage: "list.bullet.rectangle")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                TextField("Search activity", text: $query).textFieldStyle(.roundedBorder).frame(width: 180)
                Button("Clear display") { confirmingClear = true }.disabled(client.logs.isEmpty)
            }
            .padding(.horizontal, 12).frame(height: 43).background(GSPalette.side)
            Divider()
            HStack {
                Text("Time").frame(width: 90, alignment: .leading)
                Text("Event")
                Spacer()
                Text("\(events.count)").monospacedDigit()
            }
            .padding(.horizontal, 14).frame(height: 30)
            .font(.system(size: 12, weight: .medium)).background(GSPalette.raised)
            if events.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock").font(.title2)
                    Text(query.isEmpty ? "No events in this session" : "No matching events")
                        .font(.callout)
                }.foregroundStyle(GSPalette.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(events) { event in
                            HStack(alignment: .top) {
                                Text(event.time.formatted(date: .omitted, time: .standard))
                                    .monospacedDigit().foregroundStyle(GSPalette.muted)
                                    .frame(width: 90, alignment: .leading)
                                Text(event.text).textSelection(.enabled)
                                Spacer()
                            }
                            .font(.system(size: 12)).padding(.horizontal, 14).padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
            }
        }
        .background(GSPalette.panel)
        .confirmationDialog("Clear this session’s activity?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear display", role: .destructive) { client.logs.removeAll() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
