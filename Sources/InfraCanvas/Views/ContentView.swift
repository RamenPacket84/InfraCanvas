import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var boardStore: BoardStore

    var body: some View {
        NavigationSplitView {
            ComponentPaletteView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 320)
        } content: {
            CanvasWorkspaceView()
                .navigationSplitViewColumnWidth(min: 620, ideal: 820)
        } detail: {
            InspectorView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        }
        .toolbar {
            InfraToolbar()
        }
        .background {
            WindowCloseGuard {
                boardStore.confirmDiscardingUnsavedChangesIfNeeded()
            }
            .frame(width: 0, height: 0)
        }
        .onAppear {
            boardStore.validateSymbolAvailabilityIfNeeded()
        }
    }
}
