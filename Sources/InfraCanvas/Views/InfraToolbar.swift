import SwiftUI

struct InfraToolbar: ToolbarContent {
    @EnvironmentObject private var boardStore: BoardStore

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Tool", selection: $boardStore.activeTool) {
                ForEach(CanvasTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.symbolName)
                        .labelStyle(.iconOnly)
                        .help(tool.helpText)
                        .accessibilityLabel(tool.title)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 126)
            .help("Canvas Tool: \(boardStore.activeTool.title). \(boardStore.activeTool.helpText)")
            .accessibilityLabel("Canvas Tool")

            Menu {
                Picker("Connector Type", selection: $boardStore.activeConnectorKind) {
                    ForEach(ConnectorKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbolName)
                            .tag(kind)
                    }
                }
            } label: {
                Image(systemName: boardStore.activeConnectorKind.symbolName)
            }
            .help("Connector Type: \(boardStore.activeConnectorKind.title). New connectors use this type.")
            .accessibilityLabel("Connector Type")

            Divider()

            Button {
                boardStore.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom Out. Make the canvas smaller so more of the board is visible.")
            .accessibilityLabel("Zoom Out")

            Text(boardStore.zoom, format: .percent.precision(.fractionLength(0)))
                .font(.system(.callout, design: .rounded).monospacedDigit())
                .frame(width: 54)
                .foregroundStyle(.secondary)
                .help("Current Zoom Level")
                .accessibilityLabel("Current Zoom Level")

            Button {
                boardStore.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom In. Make the canvas larger for more detailed editing.")
            .accessibilityLabel("Zoom In")

            Button {
                boardStore.resetViewport()
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .help("Reset View. Return the canvas to 100 percent zoom and the default position.")
            .accessibilityLabel("Reset View")

            Button {
                boardStore.snapToGrid.toggle()
            } label: {
                Image(systemName: boardStore.snapToGrid ? "square.grid.3x3.fill" : "square.grid.3x3")
            }
            .help(boardStore.snapToGrid ? "Snap to Grid On. Components align to the grid while moving or resizing." : "Snap to Grid Off. Components move and resize freely.")
            .accessibilityLabel(boardStore.snapToGrid ? "Snap to Grid On" : "Snap to Grid Off")

            Button {
                boardStore.toggleBackgroundStyle()
            } label: {
                Image(systemName: boardStore.board.backgroundStyle.symbolName)
            }
            .help(boardStore.board.backgroundStyle == .grid ? "Grid Background On. Click to switch to a solid canvas background." : "Solid Background On. Click to switch to a grid canvas background.")
            .accessibilityLabel(boardStore.board.backgroundStyle == .grid ? "Grid Background" : "Solid Background")

            Divider()

            Button {
                boardStore.addNode(from: ComponentTemplate.defaultTemplate)
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .help("Add Component. Place a new general component on the canvas.")
            .accessibilityLabel("Add Component")

            Menu {
                Button {
                    boardStore.alignSelectedNodes(.left)
                } label: {
                    Label("Align Left", systemImage: "align.horizontal.left")
                }
                .help("Align selected components to the left edge.")

                Button {
                    boardStore.alignSelectedNodes(.horizontalCenter)
                } label: {
                    Label("Align Center", systemImage: "align.horizontal.center")
                }
                .help("Align selected components to a shared horizontal center.")

                Button {
                    boardStore.alignSelectedNodes(.right)
                } label: {
                    Label("Align Right", systemImage: "align.horizontal.right")
                }
                .help("Align selected components to the right edge.")

                Divider()

                Button {
                    boardStore.alignSelectedNodes(.top)
                } label: {
                    Label("Align Top", systemImage: "align.vertical.top")
                }
                .help("Align selected components to the top edge.")

                Button {
                    boardStore.alignSelectedNodes(.verticalMiddle)
                } label: {
                    Label("Align Middle", systemImage: "align.vertical.center")
                }
                .help("Align selected components to a shared vertical middle.")

                Button {
                    boardStore.alignSelectedNodes(.bottom)
                } label: {
                    Label("Align Bottom", systemImage: "align.vertical.bottom")
                }
                .help("Align selected components to the bottom edge.")

                Divider()

                Button {
                    boardStore.distributeSelectedNodes(.horizontal)
                } label: {
                    Label("Distribute Horizontally", systemImage: "arrow.left.and.right")
                }
                .help("Evenly space selected components from left to right.")
                .disabled(!boardStore.canDistributeSelectedNodes)

                Button {
                    boardStore.distributeSelectedNodes(.vertical)
                } label: {
                    Label("Distribute Vertically", systemImage: "arrow.up.and.down")
                }
                .help("Evenly space selected components from top to bottom.")
                .disabled(!boardStore.canDistributeSelectedNodes)

                Divider()

                Button {
                    boardStore.groupSelectedNodes()
                } label: {
                    Label("Group Selection", systemImage: "rectangle.3.group")
                }
                .help("Group selected components so they can be moved together.")
                .disabled(!boardStore.canGroupSelectedNodes)

                Button {
                    boardStore.ungroupSelection()
                } label: {
                    Label("Ungroup", systemImage: "rectangle.3.group.bubble.left")
                }
                .help("Remove the selected group while keeping its components.")
                .disabled(!boardStore.canUngroupSelection)

                Divider()

                Button {
                    boardStore.bringSelectionForward()
                } label: {
                    Label("Bring Forward", systemImage: "square.2.layers.3d.top.filled")
                }
                .help("Move selected components one layer forward.")
                .disabled(!boardStore.canReorderSelection)

                Button {
                    boardStore.sendSelectionBackward()
                } label: {
                    Label("Send Backward", systemImage: "square.2.layers.3d.bottom.filled")
                }
                .help("Move selected components one layer backward.")
                .disabled(!boardStore.canReorderSelection)

                Button {
                    boardStore.bringSelectionToFront()
                } label: {
                    Label("Bring to Front", systemImage: "rectangle.on.rectangle")
                }
                .help("Move selected components in front of all other components.")
                .disabled(!boardStore.canReorderSelection)

                Button {
                    boardStore.sendSelectionToBack()
                } label: {
                    Label("Send to Back", systemImage: "rectangle.on.rectangle.slash")
                }
                .help("Move selected components behind all other components.")
                .disabled(!boardStore.canReorderSelection)
            } label: {
                Image(systemName: "rectangle.3.group")
            }
            .help("Arrange Selected Components. Align, distribute, group, ungroup, or reorder selected components.")
            .accessibilityLabel("Arrange Selected Components")
            .disabled(!boardStore.canAlignSelectedNodes && !boardStore.canUngroupSelection && !boardStore.canReorderSelection)

            Button(role: .destructive) {
                boardStore.deleteSelection()
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete Selection. Remove the selected component, connector, or group.")
            .accessibilityLabel("Delete Selection")
            .disabled(!boardStore.hasSelection)
        }
    }
}

private extension CanvasTool {
    var helpText: String {
        switch self {
        case .select:
            "Select, move, resize, edit, and arrange components."
        case .pan:
            "Drag the canvas without selecting or moving components."
        case .connect:
            "Click one component, then another, to create a connector."
        }
    }
}
