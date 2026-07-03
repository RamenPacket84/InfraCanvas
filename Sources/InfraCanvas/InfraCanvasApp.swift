import AppKit
import SwiftUI

@main
struct InfraCanvasApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @StateObject private var boardStore = BoardStore()

    init() {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "missing bundle identifier"
        NSLog("InfraCanvas launched with bundle identifier: %@", bundleIdentifier)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(boardStore)
                .frame(minWidth: 1080, minHeight: 720)
                .onAppear {
                    appDelegate.boardStore = boardStore
                }
                .onOpenURL { url in
                    boardStore.openBoard(from: url)
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Board") {
                    boardStore.newBoard()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    boardStore.undo()
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!boardStore.canUndo)

                Button("Redo") {
                    boardStore.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!boardStore.canRedo)
            }

            CommandGroup(after: .newItem) {
                Button("Open...") {
                    boardStore.openBoard()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    boardStore.save()
                }
                .keyboardShortcut("s", modifiers: [.command])

                Button("Save As...") {
                    boardStore.saveAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            CommandGroup(after: .saveItem) {
                Button("Export as PNG...") {
                    boardStore.exportPNG()
                }
                .keyboardShortcut("e", modifiers: [.command])

                Button("Export as PDF...") {
                    boardStore.exportPDF()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    boardStore.cutSelection()
                }
                .keyboardShortcut("x", modifiers: [.command])
                .disabled(!boardStore.canCopySelection)

                Button("Copy") {
                    boardStore.copySelection()
                }
                .keyboardShortcut("c", modifiers: [.command])
                .disabled(!boardStore.canCopySelection)

                Button("Paste") {
                    boardStore.pasteSelection()
                }
                .keyboardShortcut("v", modifiers: [.command])
                .disabled(!boardStore.canPasteSelection)

                Button("Duplicate") {
                    boardStore.duplicateSelection()
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(!boardStore.canCopySelection)
            }

            CommandMenu("Canvas") {
                Button("Add Component") {
                    boardStore.addNode(from: ComponentTemplate.defaultTemplate)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Connect Selected Components") {
                    boardStore.connectSelectedNodes()
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(!boardStore.canConnectSelectedNodes)

                Menu("Default Connector Type") {
                    Picker("Default Connector Type", selection: $boardStore.activeConnectorKind) {
                        ForEach(ConnectorKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbolName)
                                .tag(kind)
                        }
                    }
                }

                Button("Zoom In") {
                    boardStore.zoomIn()
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button("Zoom Out") {
                    boardStore.zoomOut()
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button("Reset View") {
                    boardStore.resetViewport()
                }
                .keyboardShortcut("0", modifiers: [.command])

                Button(boardStore.snapToGrid ? "Disable Snap to Grid" : "Enable Snap to Grid") {
                    boardStore.snapToGrid.toggle()
                }
                .keyboardShortcut("'", modifiers: [.command])

                Button(boardStore.board.backgroundStyle == .grid ? "Use Solid Background" : "Use Grid Background") {
                    boardStore.toggleBackgroundStyle()
                }
            }

            CommandMenu("Arrange") {
                Button("Align Left") {
                    boardStore.alignSelectedNodes(.left)
                }
                .disabled(!boardStore.canAlignSelectedNodes)

                Button("Align Center") {
                    boardStore.alignSelectedNodes(.horizontalCenter)
                }
                .disabled(!boardStore.canAlignSelectedNodes)

                Button("Align Right") {
                    boardStore.alignSelectedNodes(.right)
                }
                .disabled(!boardStore.canAlignSelectedNodes)

                Divider()

                Button("Align Top") {
                    boardStore.alignSelectedNodes(.top)
                }
                .disabled(!boardStore.canAlignSelectedNodes)

                Button("Align Middle") {
                    boardStore.alignSelectedNodes(.verticalMiddle)
                }
                .disabled(!boardStore.canAlignSelectedNodes)

                Button("Align Bottom") {
                    boardStore.alignSelectedNodes(.bottom)
                }
                .disabled(!boardStore.canAlignSelectedNodes)

                Divider()

                Button("Distribute Horizontally") {
                    boardStore.distributeSelectedNodes(.horizontal)
                }
                .disabled(!boardStore.canDistributeSelectedNodes)

                Button("Distribute Vertically") {
                    boardStore.distributeSelectedNodes(.vertical)
                }
                .disabled(!boardStore.canDistributeSelectedNodes)

                Divider()

                Button("Group Selection") {
                    boardStore.groupSelectedNodes()
                }
                .keyboardShortcut("g", modifiers: [.command])
                .disabled(!boardStore.canGroupSelectedNodes)

                Button("Ungroup") {
                    boardStore.ungroupSelection()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!boardStore.canUngroupSelection)

                Divider()

                Button("Bring Forward") {
                    boardStore.bringSelectionForward()
                }
                .keyboardShortcut("]", modifiers: [.command])
                .disabled(!boardStore.canReorderSelection)

                Button("Send Backward") {
                    boardStore.sendSelectionBackward()
                }
                .keyboardShortcut("[", modifiers: [.command])
                .disabled(!boardStore.canReorderSelection)

                Button("Bring to Front") {
                    boardStore.bringSelectionToFront()
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(!boardStore.canReorderSelection)

                Button("Send to Back") {
                    boardStore.sendSelectionToBack()
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(!boardStore.canReorderSelection)
            }
        }
    }
}

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    weak var boardStore: BoardStore?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard boardStore?.confirmDiscardingUnsavedChangesIfNeeded() ?? true else {
            return .terminateCancel
        }

        return .terminateNow
    }
}
