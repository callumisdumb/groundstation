import SwiftUI

private struct WorkspaceFocusKey: FocusedValueKey {
    typealias Value = Binding<GSWorkspace>
}

extension FocusedValues {
    var groundStationWorkspace: Binding<GSWorkspace>? {
        get { self[WorkspaceFocusKey.self] }
        set { self[WorkspaceFocusKey.self] = newValue }
    }
}

private struct WorkspaceCommands: Commands {
    @FocusedBinding(\.groundStationWorkspace) var workspace

    var body: some Commands {
        CommandMenu("Workspace") {
            ForEach(GSWorkspace.allCases) { item in
                Button(item.rawValue) { workspace = item }
                    .keyboardShortcut(item.shortcut, modifiers: .command)
                    .disabled(workspace == nil)
            }
        }
    }
}

@main
struct MacGroundStationApp: App {
    var body: some Scene {
        Window("GroundStation", id: "project") {
            ContentView()
                .frame(minWidth: 960, minHeight: 580)
        }
        .defaultSize(width: 1320, height: 800)
        .windowStyle(.titleBar)
        .commands { WorkspaceCommands() }
    }
}
