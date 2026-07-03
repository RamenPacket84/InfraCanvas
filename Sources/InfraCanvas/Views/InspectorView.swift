import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var boardStore: BoardStore

    var body: some View {
        Form {
            if let group = boardStore.selectedGroup {
                Section("Group") {
                    TextField(
                        "Name",
                        text: Binding(
                            get: { group.name },
                            set: { boardStore.updateSelectedGroup(name: $0) }
                        )
                    )

                    LabeledContent("Components", value: group.nodeIDs.count.formatted())
                }

                Section("Arrange") {
                    arrangeControls
                }

                Section {
                    Button("Ungroup") {
                        boardStore.ungroupSelection()
                    }
                }
            } else if let node = boardStore.selectedNode {
                Section("Component") {
                    TextField(
                        "Title",
                        text: Binding(
                            get: { node.title },
                            set: { boardStore.updateSelectedNode(title: $0) }
                        )
                    )

                    TextField(
                        "Subtitle",
                        text: Binding(
                            get: { node.subtitle },
                            set: { boardStore.updateSelectedNode(subtitle: $0) }
                        )
                    )

                    TextField(
                        "SF Symbol",
                        text: Binding(
                            get: { node.symbolName },
                            set: { boardStore.updateSelectedNode(symbolName: $0) }
                        )
                    )
                }

                Section("Notes") {
                    TextEditor(
                        text: Binding(
                            get: { node.notes },
                            set: { boardStore.updateSelectedNode(notes: $0) }
                        )
                    )
                    .font(.body)
                    .frame(minHeight: 110)
                }

                Section("Color") {
                    Picker("Tint", selection: Binding(get: { node.tint }, set: { boardStore.updateSelectedNode(tint: $0) })) {
                        ForEach(NodeTint.allCases) { tint in
                            Label(tint.rawValue.capitalized, systemImage: "circle.fill")
                                .foregroundStyle(tint.color)
                                .tag(tint)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Position") {
                    LabeledContent("X", value: node.x, format: .number.precision(.fractionLength(0)))
                    LabeledContent("Y", value: node.y, format: .number.precision(.fractionLength(0)))
                }
            } else if boardStore.hasMultipleSelectedNodes {
                Section("Selection") {
                    LabeledContent("Components", value: boardStore.selectedNodeIDs.count.formatted())
                }

                Section("Arrange") {
                    arrangeControls
                }

                Section {
                    Button("Group Selection") {
                        boardStore.groupSelectedNodes()
                    }
                    .disabled(!boardStore.canGroupSelectedNodes)
                }
            } else if let edge = boardStore.selectedEdge {
                Section("Connector") {
                    TextField(
                        "Label",
                        text: Binding(
                            get: { edge.label },
                            set: { boardStore.updateSelectedEdge(label: $0) }
                        )
                    )

                    Toggle(
                        "Show Label",
                        isOn: Binding(
                            get: { edge.showsLabel },
                            set: { boardStore.updateSelectedEdge(showsLabel: $0) }
                        )
                    )

                    Toggle(
                        "Arrow",
                        isOn: Binding(
                            get: { edge.hasArrow },
                            set: { boardStore.updateSelectedEdge(hasArrow: $0) }
                        )
                    )

                }

                Section("Routing") {
                    Picker(
                        "Type",
                        selection: Binding(
                            get: { edge.kind },
                            set: { boardStore.updateSelectedEdge(kind: $0) }
                        )
                    ) {
                        ForEach(ConnectorKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbolName)
                                .tag(kind)
                        }
                    }

                    Picker(
                        "Style",
                        selection: Binding(
                            get: { edge.style },
                            set: { boardStore.updateSelectedEdge(style: $0) }
                        )
                    ) {
                        ForEach(ConnectorStyle.allCases) { style in
                            Label(style.title, systemImage: style.symbolName)
                                .tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Endpoints") {
                    LabeledContent("From", value: nodeTitle(for: edge.sourceNodeID))
                    LabeledContent("To", value: nodeTitle(for: edge.targetNodeID))
                }
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: boardStore.activeTool == .connect ? "point.3.connected.trianglepath.dotted" : "cursorarrow",
                    description: Text(emptyStateDescription)
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Inspector")
    }

    private var emptyStateDescription: String {
        if boardStore.activeTool == .connect {
            "Click a source component, then click a target component."
        } else {
            "Select a component or connector on the canvas to edit it."
        }
    }

    private var arrangeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Button {
                        boardStore.alignSelectedNodes(.left)
                    } label: {
                        Image(systemName: "align.horizontal.left")
                    }
                    .help("Align Left")

                    Button {
                        boardStore.alignSelectedNodes(.horizontalCenter)
                    } label: {
                        Image(systemName: "align.horizontal.center")
                    }
                    .help("Align Center")

                    Button {
                        boardStore.alignSelectedNodes(.right)
                    } label: {
                        Image(systemName: "align.horizontal.right")
                    }
                    .help("Align Right")
                }

                GridRow {
                    Button {
                        boardStore.alignSelectedNodes(.top)
                    } label: {
                        Image(systemName: "align.vertical.top")
                    }
                    .help("Align Top")

                    Button {
                        boardStore.alignSelectedNodes(.verticalMiddle)
                    } label: {
                        Image(systemName: "align.vertical.center")
                    }
                    .help("Align Middle")

                    Button {
                        boardStore.alignSelectedNodes(.bottom)
                    } label: {
                        Image(systemName: "align.vertical.bottom")
                    }
                    .help("Align Bottom")
                }
            }

            HStack {
                Button {
                    boardStore.distributeSelectedNodes(.horizontal)
                } label: {
                    Image(systemName: "arrow.left.and.right")
                }
                .help("Distribute Horizontally")
                .disabled(!boardStore.canDistributeSelectedNodes)

                Button {
                    boardStore.distributeSelectedNodes(.vertical)
                } label: {
                    Image(systemName: "arrow.up.and.down")
                }
                .help("Distribute Vertically")
                .disabled(!boardStore.canDistributeSelectedNodes)
            }
        }
    }

    private func nodeTitle(for id: DiagramNode.ID) -> String {
        boardStore.board.nodes.first { $0.id == id }?.title ?? "Missing component"
    }
}
