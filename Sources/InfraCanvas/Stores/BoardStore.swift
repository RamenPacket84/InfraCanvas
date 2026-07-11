import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class BoardStore: ObservableObject {
    @Published var board: Board
    @Published private(set) var fileURL: URL?
    @Published private(set) var isDirty = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var lastFileError: String?
    @Published var selectedNodeID: DiagramNode.ID?
    @Published var selectedNodeIDs: Set<DiagramNode.ID> = []
    @Published var selectedEdgeID: DiagramEdge.ID?
    @Published var selectedGroupID: DiagramGroup.ID?
    @Published var connectionSourceNodeID: DiagramNode.ID?
    @Published var activeTool: CanvasTool = .select {
        didSet {
            if activeTool != .connect {
                connectionSourceNodeID = nil
            }
        }
    }
    @Published var activeConnectorKind: ConnectorKind = .generic
    @Published var viewportOffset = CGSize(width: 40, height: 40)
    @Published var zoom: CGFloat = 1
    @Published var snapToGrid = true

    let minimumZoom: CGFloat = 0.35
    let maximumZoom: CGFloat = 2.5
    let gridSize: Double = 32
    let minimumNodeWidth: Double = 120
    let minimumNodeHeight: Double = 72

    private let maximumHistoryDepth = 100
    private var undoStack: [BoardHistoryState] = []
    private var redoStack: [BoardHistoryState] = []
    private var hasPresentedSymbolAvailabilityWarning = false

    init(board: Board = .blank) {
        self.board = board
    }

    var documentTitle: String {
        "\(board.name)\(isDirty ? " *" : "")"
    }

    var selectedNode: DiagramNode? {
        guard selectedNodeIDs.count == 1 else { return nil }
        guard let selectedNodeID else { return nil }
        return board.nodes.first { $0.id == selectedNodeID }
    }

    var selectedNodes: [DiagramNode] {
        board.nodes.filter { selectedNodeIDs.contains($0.id) }
    }

    var selectedEdge: DiagramEdge? {
        guard let selectedEdgeID else { return nil }
        return board.edges.first { $0.id == selectedEdgeID }
    }

    var selectedGroup: DiagramGroup? {
        guard let selectedGroupID else { return nil }
        return board.groups.first { $0.id == selectedGroupID }
    }

    var hasSelection: Bool {
        !selectedNodeIDs.isEmpty || selectedEdgeID != nil || selectedGroupID != nil
    }

    var hasMultipleSelectedNodes: Bool {
        selectedNodeIDs.count > 1
    }

    var canAlignSelectedNodes: Bool {
        selectedNodeIDs.count >= 2
    }

    var canDistributeSelectedNodes: Bool {
        selectedNodeIDs.count >= 3
    }

    var canGroupSelectedNodes: Bool {
        selectedNodeIDs.count >= 2 && selectedGroupID == nil
    }

    var canUngroupSelection: Bool {
        selectedGroupID != nil
    }

    var canCopySelection: Bool {
        !selectedNodeIDs.isEmpty
    }

    var canPasteSelection: Bool {
        canPasteSelection(from: .general)
    }

    var canReorderSelection: Bool {
        !selectedNodeIDs.isEmpty
    }

    var canConnectSelectedNodes: Bool {
        selectedNodeIDs.count == 2
    }

    func undo() {
        guard let previousState = undoStack.popLast() else { return }
        redoStack.append(historySnapshot())
        trimHistoryStack(&redoStack)
        restore(previousState)
        updateHistoryAvailability()
    }

    func redo() {
        guard let nextState = redoStack.popLast() else { return }
        undoStack.append(historySnapshot())
        trimHistoryStack(&undoStack)
        restore(nextState)
        updateHistoryAvailability()
    }

    func beginUndoableAction() {
        registerUndoSnapshot()
    }

    func toggleBackgroundStyle() {
        setBackgroundStyle(board.backgroundStyle == .grid ? .solid : .grid)
    }

    func setBackgroundStyle(_ backgroundStyle: BoardBackgroundStyle) {
        guard board.backgroundStyle != backgroundStyle else { return }

        registerUndoSnapshot()
        board.backgroundStyle = backgroundStyle
        markDirty()
    }

    func validateSymbolAvailabilityIfNeeded() {
        guard !hasPresentedSymbolAvailabilityWarning else { return }

        let requiredSymbols = Set(
            ComponentTemplate.library.map(\.symbolName)
            + board.nodes.map(\.symbolName)
            + CanvasTool.allCases.map(\.symbolName)
        )
        let unavailableSymbols = SymbolCatalog.unavailableNames(in: requiredSymbols)
        guard !unavailableSymbols.isEmpty else { return }

        hasPresentedSymbolAvailabilityWarning = true

        let displayedSymbols = unavailableSymbols.prefix(8).joined(separator: ", ")
        let remainingCount = max(unavailableSymbols.count - 8, 0)
        let suffix = remainingCount > 0 ? " and \(remainingCount) more" : ""

        let alert = NSAlert()
        alert.messageText = "Some Symbols Are Unavailable"
        alert.informativeText = """
        SF Symbols are provided by macOS at runtime. This Mac does not include \(displayedSymbols)\(suffix). InfraCanvas will use a fallback component icon so boards still render and export correctly.

        Updating macOS can make newer SF Symbols available. You can also choose another symbol name in the inspector.
        """
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        alert.runModal()
    }

    func selectNode(_ id: DiagramNode.ID?, activateSelectTool: Bool = true) {
        if let id {
            if let group = group(containing: id) {
                selectGroup(group.id, activateSelectTool: activateSelectTool)
                return
            }

            selectedNodeIDs = [id]
            selectedNodeID = id
        } else {
            selectedNodeIDs = []
            selectedNodeID = nil
        }
        selectedEdgeID = nil
        selectedGroupID = nil

        if id != nil, activateSelectTool {
            activeTool = .select
        }
    }

    func selectNodes(_ ids: Set<DiagramNode.ID>, activateSelectTool: Bool = true) {
        selectedNodeIDs = ids
        selectedNodeID = primaryNodeID(in: ids)
        selectedEdgeID = nil
        selectedGroupID = group(matching: ids)?.id

        if !ids.isEmpty, activateSelectTool {
            activeTool = .select
        }
    }

    func toggleNodeSelection(_ id: DiagramNode.ID) {
        let toggledIDs = group(containing: id)?.nodeIDs ?? [id]

        if toggledIDs.isSubset(of: selectedNodeIDs) {
            selectedNodeIDs.subtract(toggledIDs)
        } else {
            selectedNodeIDs.formUnion(toggledIDs)
        }

        selectedNodeID = primaryNodeID(in: selectedNodeIDs)
        selectedEdgeID = nil
        selectedGroupID = group(matching: selectedNodeIDs)?.id
        connectionSourceNodeID = nil

        if !selectedNodeIDs.isEmpty {
            activeTool = .select
        }
    }

    func selectGroup(_ id: DiagramGroup.ID?, activateSelectTool: Bool = true) {
        guard let id else {
            selectedGroupID = nil
            selectedNodeIDs = []
            selectedNodeID = nil
            selectedEdgeID = nil
            return
        }

        guard let group = board.groups.first(where: { $0.id == id }) else { return }
        selectedGroupID = id
        selectedNodeIDs = group.nodeIDs
        selectedNodeID = nil
        selectedEdgeID = nil
        connectionSourceNodeID = nil

        if activateSelectTool {
            activeTool = .select
        }
    }

    func selectEdge(_ id: DiagramEdge.ID?) {
        selectedEdgeID = id
        selectedNodeIDs = []
        selectedNodeID = nil
        selectedGroupID = nil
        connectionSourceNodeID = nil

        if id != nil {
            activeTool = .select
        }
    }

    func addNode(from template: ComponentTemplate) {
        registerUndoSnapshot()

        let node = DiagramNode(
            title: template.title,
            subtitle: template.subtitle,
            symbolName: template.symbolName,
            x: Double(160 - viewportOffset.width) / Double(zoom),
            y: Double(130 - viewportOffset.height) / Double(zoom),
            width: 180,
            height: 92,
            tint: template.tint,
            category: template.category
        )

        board.nodes.append(node)
        selectedNodeIDs = [node.id]
        selectedNodeID = node.id
        selectedEdgeID = nil
        selectedGroupID = nil
        connectionSourceNodeID = nil
        activeTool = .select
        markDirty()
    }

    func addNode(from template: ComponentTemplate, atWorldPoint point: CGPoint) {
        registerUndoSnapshot()

        let node = DiagramNode(
            title: template.title,
            subtitle: template.subtitle,
            symbolName: template.symbolName,
            x: Double(point.x),
            y: Double(point.y),
            width: 180,
            height: 92,
            tint: template.tint,
            category: template.category
        )

        board.nodes.append(node)
        selectedNodeIDs = [node.id]
        selectedNodeID = node.id
        selectedEdgeID = nil
        selectedGroupID = nil
        connectionSourceNodeID = nil
        activeTool = .select
        markDirty()
    }

    func moveNode(_ id: DiagramNode.ID, byScreenDelta delta: CGSize, registerUndo: Bool = true) {
        let idsToMove = nodeIDsMovedByDraggingNode(id)

        moveNodes(idsToMove, byScreenDelta: delta, registerUndo: registerUndo)
    }

    func moveNodes(_ ids: Set<DiagramNode.ID>, byScreenDelta delta: CGSize, registerUndo: Bool = true) {
        guard !ids.isEmpty else { return }
        let worldDeltaX = Double(delta.width / zoom)
        let worldDeltaY = Double(delta.height / zoom)

        moveNodes(ids, byWorldDelta: CGSize(width: worldDeltaX, height: worldDeltaY), registerUndo: registerUndo)
    }

    func moveNodes(_ ids: Set<DiagramNode.ID>, from originalPositions: [DiagramNode.ID: CGPoint], byScreenDelta delta: CGSize, snapToGrid shouldSnap: Bool? = nil, registerUndo: Bool = true) {
        guard !ids.isEmpty else { return }
        let worldDelta = CGSize(width: Double(delta.width / zoom), height: Double(delta.height / zoom))
        let snapped = shouldSnap ?? snapToGrid
        let effectiveWorldDelta: CGSize

        if snapped,
           let primaryID = primaryNodeID(in: ids),
           let primaryOrigin = originalPositions[primaryID] {
            let rawPrimaryX = Double(primaryOrigin.x) + Double(worldDelta.width)
            let rawPrimaryY = Double(primaryOrigin.y) + Double(worldDelta.height)
            let snappedPrimaryX = snappedValue(Double(rawPrimaryX))
            let snappedPrimaryY = snappedValue(Double(rawPrimaryY))
            effectiveWorldDelta = CGSize(
                width: snappedPrimaryX - Double(primaryOrigin.x),
                height: snappedPrimaryY - Double(primaryOrigin.y)
            )
        } else {
            effectiveWorldDelta = worldDelta
        }

        if registerUndo {
            registerUndoSnapshot()
        }

        for index in board.nodes.indices where ids.contains(board.nodes[index].id) {
            guard let originalPosition = originalPositions[board.nodes[index].id] else { continue }
            board.nodes[index].x = originalPosition.x + Double(effectiveWorldDelta.width)
            board.nodes[index].y = originalPosition.y + Double(effectiveWorldDelta.height)
        }

        markDirty()
    }

    func nodeIDsMovedByDraggingNode(_ id: DiagramNode.ID) -> Set<DiagramNode.ID> {
        if selectedNodeIDs.contains(id) {
            selectedNodeIDs
        } else if let group = group(containing: id) {
            group.nodeIDs
        } else {
            [id]
        }
    }

    func positions(for ids: Set<DiagramNode.ID>) -> [DiagramNode.ID: CGPoint] {
        Dictionary(uniqueKeysWithValues: board.nodes.compactMap { node in
            ids.contains(node.id) ? (node.id, node.position) : nil
        })
    }

    func size(for id: DiagramNode.ID) -> CGSize? {
        board.nodes.first(where: { $0.id == id })?.size
    }

    func resizeNode(
        _ id: DiagramNode.ID,
        from originalSize: CGSize,
        byScreenDelta delta: CGSize,
        preserveAspectRatio: Bool = false,
        snapToGrid shouldSnap: Bool? = nil,
        registerUndo: Bool = true
    ) {
        let worldDelta = CGSize(width: Double(delta.width / zoom), height: Double(delta.height / zoom))
        resizeNode(
            id,
            to: CGSize(
                width: Double(originalSize.width) + Double(worldDelta.width),
                height: Double(originalSize.height) + Double(worldDelta.height)
            ),
            from: originalSize,
            preserveAspectRatio: preserveAspectRatio,
            snapToGrid: shouldSnap,
            registerUndo: registerUndo
        )
    }

    func resizeNode(
        _ id: DiagramNode.ID,
        to proposedSize: CGSize,
        from originalSize: CGSize? = nil,
        preserveAspectRatio: Bool = false,
        snapToGrid shouldSnap: Bool? = nil,
        registerUndo: Bool = true
    ) {
        guard let index = board.nodes.firstIndex(where: { $0.id == id }) else { return }

        var width = max(Double(proposedSize.width), minimumNodeWidth)
        var height = max(Double(proposedSize.height), minimumNodeHeight)

        if preserveAspectRatio {
            let baselineSize = originalSize ?? board.nodes[index].size
            let aspectRatio = max(Double(baselineSize.width), minimumNodeWidth) / max(Double(baselineSize.height), minimumNodeHeight)

            if width / max(height, minimumNodeHeight) > aspectRatio {
                height = width / aspectRatio
            } else {
                width = height * aspectRatio
            }
        }

        if shouldSnap ?? snapToGrid {
            width = max(snappedValue(width), minimumNodeWidth)
            height = max(snappedValue(height), minimumNodeHeight)
        }

        guard board.nodes[index].width != width || board.nodes[index].height != height else { return }

        if registerUndo {
            registerUndoSnapshot()
        }

        board.nodes[index].width = width
        board.nodes[index].height = height
        markDirty()
    }

    func moveNodes(_ ids: Set<DiagramNode.ID>, byWorldDelta delta: CGSize, registerUndo: Bool = true) {
        guard !ids.isEmpty else { return }

        if registerUndo {
            registerUndoSnapshot()
        }

        for index in board.nodes.indices where ids.contains(board.nodes[index].id) {
            board.nodes[index].x += Double(delta.width)
            board.nodes[index].y += Double(delta.height)
        }

        markDirty()
    }

    func nudgeSelection(_ direction: NudgeDirection, fine: Bool = false) {
        guard !selectedNodeIDs.isEmpty else { return }
        let distance = fine ? 1.0 : gridSize

        switch direction {
        case .left:
            moveNodes(selectedNodeIDs, byWorldDelta: CGSize(width: -distance, height: 0))
        case .right:
            moveNodes(selectedNodeIDs, byWorldDelta: CGSize(width: distance, height: 0))
        case .up:
            moveNodes(selectedNodeIDs, byWorldDelta: CGSize(width: 0, height: -distance))
        case .down:
            moveNodes(selectedNodeIDs, byWorldDelta: CGSize(width: 0, height: distance))
        }
    }

    func bringSelectionForward() {
        guard !selectedNodeIDs.isEmpty else { return }
        registerUndoSnapshot()

        for index in board.nodes.indices.dropLast().reversed() where selectedNodeIDs.contains(board.nodes[index].id) && !selectedNodeIDs.contains(board.nodes[index + 1].id) {
            board.nodes.swapAt(index, index + 1)
        }

        markDirty()
    }

    func sendSelectionBackward() {
        guard !selectedNodeIDs.isEmpty else { return }
        registerUndoSnapshot()

        for index in board.nodes.indices.dropFirst() where selectedNodeIDs.contains(board.nodes[index].id) && !selectedNodeIDs.contains(board.nodes[index - 1].id) {
            board.nodes.swapAt(index, index - 1)
        }

        markDirty()
    }

    func bringSelectionToFront() {
        guard !selectedNodeIDs.isEmpty else { return }
        registerUndoSnapshot()

        let selectedNodes = board.nodes.filter { selectedNodeIDs.contains($0.id) }
        board.nodes.removeAll { selectedNodeIDs.contains($0.id) }
        board.nodes.append(contentsOf: selectedNodes)
        markDirty()
    }

    func sendSelectionToBack() {
        guard !selectedNodeIDs.isEmpty else { return }
        registerUndoSnapshot()

        let selectedNodes = board.nodes.filter { selectedNodeIDs.contains($0.id) }
        board.nodes.removeAll { selectedNodeIDs.contains($0.id) }
        board.nodes.insert(contentsOf: selectedNodes, at: 0)
        markDirty()
    }

    func deleteSelection() {
        if !selectedNodeIDs.isEmpty {
            registerUndoSnapshot()

            let deletedIDs = selectedNodeIDs
            board.nodes.removeAll { deletedIDs.contains($0.id) }
            board.edges.removeAll { deletedIDs.contains($0.sourceNodeID) || deletedIDs.contains($0.targetNodeID) }
            removeDeletedNodesFromGroups(deletedIDs)
            selectedNodeIDs = []
            self.selectedNodeID = nil
            selectedGroupID = nil
            connectionSourceNodeID = nil
            markDirty()
            return
        }

        if let selectedEdgeID {
            registerUndoSnapshot()

            board.edges.removeAll { $0.id == selectedEdgeID }
            self.selectedEdgeID = nil
            markDirty()
        }
    }

    func updateSelectedNode(title: String? = nil, subtitle: String? = nil, notes: String? = nil, symbolName: String? = nil, tint: NodeTint? = nil) {
        guard let selectedNodeID, let index = board.nodes.firstIndex(where: { $0.id == selectedNodeID }) else { return }

        updateNode(at: index, title: title, subtitle: subtitle, notes: notes, symbolName: symbolName, tint: tint, registerUndo: true)
    }

    func updateNode(_ id: DiagramNode.ID, title: String? = nil, subtitle: String? = nil, notes: String? = nil, symbolName: String? = nil, tint: NodeTint? = nil) {
        guard let index = board.nodes.firstIndex(where: { $0.id == id }) else { return }
        updateNode(at: index, title: title, subtitle: subtitle, notes: notes, symbolName: symbolName, tint: tint, registerUndo: true)
    }

    func updateSelectedNodes(tint: NodeTint? = nil, symbolName: String? = nil) {
        guard !selectedNodeIDs.isEmpty else { return }
        guard tint != nil || symbolName != nil else { return }

        registerUndoSnapshot()

        for index in board.nodes.indices where selectedNodeIDs.contains(board.nodes[index].id) {
            updateNode(at: index, symbolName: symbolName, tint: tint, registerUndo: false)
        }
    }

    private func updateNode(at index: Array<DiagramNode>.Index, title: String? = nil, subtitle: String? = nil, notes: String? = nil, symbolName: String? = nil, tint: NodeTint? = nil, registerUndo: Bool = false) {
        guard title != nil || subtitle != nil || notes != nil || symbolName != nil || tint != nil else { return }

        if registerUndo {
            registerUndoSnapshot()
        }

        if let title {
            board.nodes[index].title = title
            markDirty()
        }

        if let subtitle {
            board.nodes[index].subtitle = subtitle
            markDirty()
        }

        if let notes {
            board.nodes[index].notes = notes
            markDirty()
        }

        if let symbolName {
            board.nodes[index].symbolName = symbolName
            markDirty()
        }

        if let tint {
            board.nodes[index].tint = tint
            markDirty()
        }
    }

    func updateSelectedEdge(label: String? = nil, showsLabel: Bool? = nil, hasArrow: Bool? = nil, style: ConnectorStyle? = nil, kind: ConnectorKind? = nil) {
        guard let selectedEdgeID, let index = board.edges.firstIndex(where: { $0.id == selectedEdgeID }) else { return }

        updateEdge(at: index, label: label, showsLabel: showsLabel, hasArrow: hasArrow, style: style, kind: kind, registerUndo: true)
    }

    func updateEdge(_ id: DiagramEdge.ID, label: String? = nil, showsLabel: Bool? = nil, hasArrow: Bool? = nil, style: ConnectorStyle? = nil, kind: ConnectorKind? = nil) {
        guard let index = board.edges.firstIndex(where: { $0.id == id }) else { return }
        updateEdge(at: index, label: label, showsLabel: showsLabel, hasArrow: hasArrow, style: style, kind: kind, registerUndo: true)
    }

    func setManualRoute(_ route: ManualConnectorRoute?, for edgeID: DiagramEdge.ID, registerUndo: Bool = true) {
        guard let index = board.edges.firstIndex(where: { $0.id == edgeID }),
              board.edges[index].manualRoute != route else {
            return
        }

        if registerUndo {
            registerUndoSnapshot()
        }
        board.edges[index].manualRoute = route
        markDirty()
    }

    func moveManualWaypoint(
        for edgeID: DiagramEdge.ID,
        at index: Int,
        to point: CGPoint,
        snapToGrid shouldSnap: Bool,
        registerUndo: Bool = true
    ) {
        guard let edgeIndex = board.edges.firstIndex(where: { $0.id == edgeID }),
              var route = board.edges[edgeIndex].manualRoute,
              route.waypoints.indices.contains(index) else {
            return
        }

        let adjustedPoint: CGPoint
        if shouldSnap {
            adjustedPoint = CGPoint(
                x: (point.x / gridSize).rounded() * gridSize,
                y: (point.y / gridSize).rounded() * gridSize
            )
        } else {
            adjustedPoint = point
        }
        guard route.waypoints[index].point != adjustedPoint else { return }

        if registerUndo {
            registerUndoSnapshot()
        }
        route.waypoints[index] = DiagramPoint(adjustedPoint)
        board.edges[edgeIndex].manualRoute = route
        markDirty()
    }

    func removeManualWaypoint(for edgeID: DiagramEdge.ID, at index: Int) {
        guard let edgeIndex = board.edges.firstIndex(where: { $0.id == edgeID }),
              var route = board.edges[edgeIndex].manualRoute,
              route.waypoints.indices.contains(index) else {
            return
        }

        registerUndoSnapshot()
        route.waypoints.remove(at: index)
        board.edges[edgeIndex].manualRoute = route.waypoints.isEmpty ? nil : route
        markDirty()
    }

    func updateSelectedGroup(name: String) {
        guard let selectedGroupID else { return }
        updateGroup(selectedGroupID, name: name)
    }

    func updateGroup(_ id: DiagramGroup.ID, name: String) {
        guard let index = board.groups.firstIndex(where: { $0.id == id }) else { return }
        guard board.groups[index].name != name else { return }
        registerUndoSnapshot()

        board.groups[index].name = name
        markDirty()
    }

    private func updateEdge(
        at index: Array<DiagramEdge>.Index,
        label: String? = nil,
        showsLabel: Bool? = nil,
        hasArrow: Bool? = nil,
        style: ConnectorStyle? = nil,
        kind: ConnectorKind? = nil,
        registerUndo: Bool = false
    ) {
        guard label != nil || showsLabel != nil || hasArrow != nil || style != nil || kind != nil else { return }

        if registerUndo {
            registerUndoSnapshot()
        }

        if let label {
            board.edges[index].label = label
            markDirty()
        }

        if let showsLabel {
            board.edges[index].showsLabel = showsLabel
            markDirty()
        }

        if let hasArrow {
            board.edges[index].hasArrow = hasArrow
            markDirty()
        }

        if let style {
            board.edges[index].style = style
            markDirty()
        }

        if let kind {
            board.edges[index].kind = kind
            markDirty()
        }
    }

    func handleConnectClick(on nodeID: DiagramNode.ID) {
        selectedEdgeID = nil

        guard let sourceNodeID = connectionSourceNodeID else {
            connectionSourceNodeID = nodeID
            selectedNodeIDs = [nodeID]
            selectedNodeID = nodeID
            return
        }

        if sourceNodeID == nodeID {
            connectionSourceNodeID = nil
            selectedNodeIDs = [nodeID]
            selectedNodeID = nodeID
            selectedGroupID = nil
            return
        }

        connectNodes(sourceID: sourceNodeID, targetID: nodeID, label: "relates to")
        activeTool = .select
    }

    func cancelPendingConnection() {
        connectionSourceNodeID = nil
    }

    func startConnection(from nodeID: DiagramNode.ID) {
        guard board.nodes.contains(where: { $0.id == nodeID }) else { return }

        selectedEdgeID = nil
        selectedGroupID = nil
        selectedNodeIDs = [nodeID]
        selectedNodeID = nodeID
        connectionSourceNodeID = nodeID
        activeTool = .connect
    }

    func connectSelectedNodes(label: String = "relates to", style: ConnectorStyle = .orthogonal, kind: ConnectorKind? = nil) {
        guard canConnectSelectedNodes else { return }

        let selectedNodesInBoardOrder = board.nodes.filter { selectedNodeIDs.contains($0.id) }
        guard selectedNodesInBoardOrder.count == 2 else { return }
        let connectorKind = kind ?? activeConnectorKind

        connectNodes(
            sourceID: selectedNodesInBoardOrder[0].id,
            targetID: selectedNodesInBoardOrder[1].id,
            label: label,
            style: style,
            kind: connectorKind
        )
        activeTool = .select
    }

    @discardableResult
    func connectNodes(
        sourceID: DiagramNode.ID,
        targetID: DiagramNode.ID,
        label: String = "relates to",
        style: ConnectorStyle = .orthogonal,
        kind: ConnectorKind? = nil
    ) -> DiagramEdge.ID? {
        guard sourceID != targetID,
              board.nodes.contains(where: { $0.id == sourceID }),
              board.nodes.contains(where: { $0.id == targetID }) else {
            return nil
        }

        if let existingEdge = board.edges.first(where: { $0.sourceNodeID == sourceID && $0.targetNodeID == targetID }) {
            selectedEdgeID = existingEdge.id
            selectedNodeID = nil
            selectedNodeIDs = []
            selectedGroupID = nil
            connectionSourceNodeID = nil
            return existingEdge.id
        }

        registerUndoSnapshot()

        let edge = DiagramEdge(sourceNodeID: sourceID, targetNodeID: targetID, label: label, style: style, kind: kind ?? activeConnectorKind)
        board.edges.append(edge)
        selectedEdgeID = edge.id
        selectedNodeID = nil
        selectedNodeIDs = []
        selectedGroupID = nil
        connectionSourceNodeID = nil
        markDirty()
        return edge.id
    }

    func pan(by delta: CGSize) {
        viewportOffset.width += delta.width
        viewportOffset.height += delta.height
    }

    func setZoom(_ newZoom: CGFloat, anchoredAt anchor: CGPoint? = nil) {
        let oldZoom = zoom
        let clampedZoom = min(max(newZoom, minimumZoom), maximumZoom)
        guard clampedZoom != oldZoom else { return }

        if let anchor {
            let worldX = (anchor.x - viewportOffset.width) / oldZoom
            let worldY = (anchor.y - viewportOffset.height) / oldZoom

            viewportOffset.width = anchor.x - worldX * clampedZoom
            viewportOffset.height = anchor.y - worldY * clampedZoom
        }

        zoom = clampedZoom
    }

    func zoomIn() {
        setZoom(zoom * 1.12)
    }

    func zoomOut() {
        setZoom(zoom / 1.12)
    }

    func resetViewport() {
        viewportOffset = CGSize(width: 40, height: 40)
        zoom = 1
    }

    func alignSelectedNodes(_ alignment: NodeAlignment) {
        guard selectedNodeIDs.count >= 2 else { return }
        let selectedIndexes = board.nodes.indices.filter { selectedNodeIDs.contains(board.nodes[$0].id) }
        guard !selectedIndexes.isEmpty else { return }
        registerUndoSnapshot()

        switch alignment {
        case .left:
            let target = selectedIndexes.map { board.nodes[$0].x }.min() ?? 0
            for index in selectedIndexes {
                board.nodes[index].x = target
            }
        case .horizontalCenter:
            let target = selectedIndexes.map { board.nodes[$0].x + board.nodes[$0].width / 2 }.reduce(0, +) / Double(selectedIndexes.count)
            for index in selectedIndexes {
                board.nodes[index].x = target - board.nodes[index].width / 2
            }
        case .right:
            let target = selectedIndexes.map { board.nodes[$0].x + board.nodes[$0].width }.max() ?? 0
            for index in selectedIndexes {
                board.nodes[index].x = target - board.nodes[index].width
            }
        case .top:
            let target = selectedIndexes.map { board.nodes[$0].y }.min() ?? 0
            for index in selectedIndexes {
                board.nodes[index].y = target
            }
        case .verticalMiddle:
            let target = selectedIndexes.map { board.nodes[$0].y + board.nodes[$0].height / 2 }.reduce(0, +) / Double(selectedIndexes.count)
            for index in selectedIndexes {
                board.nodes[index].y = target - board.nodes[index].height / 2
            }
        case .bottom:
            let target = selectedIndexes.map { board.nodes[$0].y + board.nodes[$0].height }.max() ?? 0
            for index in selectedIndexes {
                board.nodes[index].y = target - board.nodes[index].height
            }
        }

        markDirty()
    }

    func duplicateSelection() {
        duplicateNodes(selectedNodeIDs)
    }

    func duplicateNode(_ id: DiagramNode.ID) {
        let idsToDuplicate = group(containing: id)?.nodeIDs ?? [id]
        duplicateNodes(idsToDuplicate)
    }

    func copySelection(to pasteboard: NSPasteboard = .general) {
        guard let payload = clipboardPayloadForSelection() else { return }

        do {
            let data = try JSONEncoder().encode(payload)
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .infraCanvasSelection)
        } catch {
            presentFileError(error)
        }
    }

    func cutSelection(to pasteboard: NSPasteboard = .general) {
        guard canCopySelection else { return }
        copySelection(to: pasteboard)
        deleteSelection()
    }

    func pasteSelection(from pasteboard: NSPasteboard = .general, atWorldPoint point: CGPoint? = nil) {
        guard let payload = clipboardPayload(from: pasteboard) else { return }
        paste(payload, atWorldPoint: point)
    }

    func canPasteSelection(from pasteboard: NSPasteboard) -> Bool {
        clipboardPayload(from: pasteboard) != nil
    }

    func groupSelectedNodes() {
        guard canGroupSelectedNodes else { return }

        let existingGroupedIDs = Set(board.groups.flatMap(\.nodeIDs))
        guard selectedNodeIDs.isDisjoint(with: existingGroupedIDs) else { return }
        registerUndoSnapshot()

        let groupNumber = board.groups.count + 1
        let group = DiagramGroup(name: "Group \(groupNumber)", nodeIDs: selectedNodeIDs)
        board.groups.append(group)
        selectGroup(group.id)
        markDirty()
    }

    func ungroupSelection() {
        guard let selectedGroupID else { return }
        registerUndoSnapshot()

        board.groups.removeAll { $0.id == selectedGroupID }
        self.selectedGroupID = nil
        selectedNodeID = primaryNodeID(in: selectedNodeIDs)
        markDirty()
    }

    func distributeSelectedNodes(_ axis: DistributionAxis) {
        guard selectedNodeIDs.count >= 3 else { return }
        let selectedIndexes = board.nodes.indices.filter { selectedNodeIDs.contains(board.nodes[$0].id) }
        guard !selectedIndexes.isEmpty else { return }
        registerUndoSnapshot()

        switch axis {
        case .horizontal:
            let sortedIndexes = selectedIndexes.sorted { board.nodes[$0].x < board.nodes[$1].x }
            guard let firstIndex = sortedIndexes.first, let lastIndex = sortedIndexes.last else { return }
            let firstX = board.nodes[firstIndex].x
            let lastX = board.nodes[lastIndex].x
            let step = (lastX - firstX) / Double(sortedIndexes.count - 1)

            for (offset, index) in sortedIndexes.enumerated() {
                board.nodes[index].x = firstX + Double(offset) * step
            }
        case .vertical:
            let sortedIndexes = selectedIndexes.sorted { board.nodes[$0].y < board.nodes[$1].y }
            guard let firstIndex = sortedIndexes.first, let lastIndex = sortedIndexes.last else { return }
            let firstY = board.nodes[firstIndex].y
            let lastY = board.nodes[lastIndex].y
            let step = (lastY - firstY) / Double(sortedIndexes.count - 1)

            for (offset, index) in sortedIndexes.enumerated() {
                board.nodes[index].y = firstY + Double(offset) * step
            }
        }

        markDirty()
    }

    func newBoard() {
        guard confirmDiscardingUnsavedChangesIfNeeded() else { return }

        board = .blank
        fileURL = nil
        isDirty = false
        clearHistory()
        resetInteractionState()
        resetViewport()
    }

    func save() {
        do {
            if let fileURL {
                try save(to: fileURL)
            } else {
                saveAs()
            }
        } catch {
            presentFileError(error)
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.infraCanvasDocument]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedFileName
        panel.title = "Save Board"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try save(to: normalizedDocumentURL(url), updatingBoardNameFromURL: true)
        } catch {
            presentFileError(error)
        }
    }

    func exportPNG() {
        export(format: .png)
    }

    func exportPDF() {
        export(format: .pdf)
    }

    func exportPNG(to url: URL) throws {
        let targetURL = normalizedExportURL(url, for: .png)
        try withSecurityScopedAccess(to: targetURL) {
            try BoardExportRenderer(board: board).writePNG(to: targetURL)
        }
    }

    func exportPDF(to url: URL) throws {
        let targetURL = normalizedExportURL(url, for: .pdf)
        try withSecurityScopedAccess(to: targetURL) {
            try BoardExportRenderer(board: board).writePDF(to: targetURL)
        }
    }

    func openBoard() {
        guard confirmDiscardingUnsavedChangesIfNeeded() else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.infraCanvasDocument]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Open Board"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try loadUserSelectedBoard(from: url)
        } catch {
            presentFileError(error)
        }
    }

    func openBoard(from url: URL) {
        guard url.isFileURL else { return }
        guard confirmDiscardingUnsavedChangesIfNeeded() else { return }

        do {
            try loadUserSelectedBoard(from: url)
        } catch {
            presentFileError(error)
        }
    }

    func save(to url: URL, updatingBoardNameFromURL: Bool = false) throws {
        let targetURL = normalizedDocumentURL(url)
        if updatingBoardNameFromURL {
            board.name = boardName(from: targetURL)
        }

        let document = BoardDocument(board: board)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(document)
        try withSecurityScopedAccess(to: targetURL) {
            try data.write(to: targetURL, options: .atomic)
        }

        fileURL = targetURL
        isDirty = false
        lastFileError = nil
    }

    func load(from url: URL) throws {
        let data = try withSecurityScopedAccess(to: url) {
            try Data(contentsOf: url)
        }
        let document = try JSONDecoder().decode(BoardDocument.self, from: data)

        board = document.board
        fileURL = url
        isDirty = false
        lastFileError = nil
        clearHistory()
        resetInteractionState()
        resetViewport()
    }

    private func loadUserSelectedBoard(from url: URL) throws {
        try load(from: url)
    }

    private func withSecurityScopedAccess<T>(to url: URL, perform work: () throws -> T) rethrows -> T {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try work()
    }

    private var suggestedFileName: String {
        let trimmedName = board.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(trimmedName.isEmpty ? "Untitled Board" : trimmedName).infracanvas"
    }

    private func boardName(from url: URL) -> String {
        let filename = url.deletingPathExtension().lastPathComponent
        let trimmedName = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Untitled Board" : trimmedName
    }

    private func historySnapshot() -> BoardHistoryState {
        BoardHistoryState(
            board: board,
            isDirty: isDirty,
            selectedNodeID: selectedNodeID,
            selectedNodeIDs: selectedNodeIDs,
            selectedEdgeID: selectedEdgeID,
            selectedGroupID: selectedGroupID,
            connectionSourceNodeID: connectionSourceNodeID,
            activeTool: activeTool
        )
    }

    private func restore(_ state: BoardHistoryState) {
        board = state.board
        isDirty = state.isDirty
        selectedNodeID = state.selectedNodeID
        selectedNodeIDs = state.selectedNodeIDs
        selectedEdgeID = state.selectedEdgeID
        selectedGroupID = state.selectedGroupID
        connectionSourceNodeID = state.connectionSourceNodeID
        activeTool = state.activeTool
    }

    private func registerUndoSnapshot() {
        let snapshot = historySnapshot()
        guard undoStack.last != snapshot else { return }

        undoStack.append(snapshot)
        trimHistoryStack(&undoStack)
        redoStack.removeAll()
        updateHistoryAvailability()
    }

    private func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        updateHistoryAvailability()
    }

    private func trimHistoryStack(_ stack: inout [BoardHistoryState]) {
        if stack.count > maximumHistoryDepth {
            stack.removeFirst(stack.count - maximumHistoryDepth)
        }
    }

    private func updateHistoryAvailability() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func normalizedDocumentURL(_ url: URL) -> URL {
        guard url.pathExtension.isEmpty else { return url }
        return url.appendingPathExtension("infracanvas")
    }

    private func export(format: BoardExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(exportFileBaseName).\(format.fileExtension)"
        panel.title = "Export \(format.title)"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            switch format {
            case .png:
                try exportPNG(to: url)
            case .pdf:
                try exportPDF(to: url)
            }
            lastFileError = nil
        } catch {
            presentFileError(error)
        }
    }

    private var exportFileBaseName: String {
        let trimmedName = board.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Untitled Board" : trimmedName
    }

    private func normalizedExportURL(_ url: URL, for format: BoardExportFormat) -> URL {
        guard url.pathExtension.isEmpty else { return url }
        return url.appendingPathExtension(format.fileExtension)
    }

    private func markDirty() {
        isDirty = true
    }

    private func resetInteractionState() {
        selectedNodeIDs = []
        selectedNodeID = nil
        selectedEdgeID = nil
        selectedGroupID = nil
        connectionSourceNodeID = nil
        activeTool = .select
    }

    private func primaryNodeID(in ids: Set<DiagramNode.ID>) -> DiagramNode.ID? {
        board.nodes.first { ids.contains($0.id) }?.id
    }

    private func snappedValue(_ value: Double) -> Double {
        guard gridSize > 0 else { return value }
        return (value / gridSize).rounded() * gridSize
    }

    private func group(containing nodeID: DiagramNode.ID) -> DiagramGroup? {
        board.groups.first { $0.nodeIDs.contains(nodeID) }
    }

    private func group(matching nodeIDs: Set<DiagramNode.ID>) -> DiagramGroup? {
        board.groups.first { $0.nodeIDs == nodeIDs }
    }

    private func removeDeletedNodesFromGroups(_ deletedIDs: Set<DiagramNode.ID>) {
        for index in board.groups.indices {
            board.groups[index].nodeIDs.subtract(deletedIDs)
        }

        board.groups.removeAll { $0.nodeIDs.count < 2 }
    }

    private func clipboardPayloadForSelection() -> InfraCanvasClipboardPayload? {
        guard !selectedNodeIDs.isEmpty else { return nil }

        let nodes = board.nodes.filter { selectedNodeIDs.contains($0.id) }
        guard !nodes.isEmpty else { return nil }

        let edges = board.edges.filter { edge in
            selectedNodeIDs.contains(edge.sourceNodeID) && selectedNodeIDs.contains(edge.targetNodeID)
        }
        let groups = board.groups.filter { group in
            group.nodeIDs.isSubset(of: selectedNodeIDs)
        }

        return InfraCanvasClipboardPayload(nodes: nodes, edges: edges, groups: groups)
    }

    private func clipboardPayload(from pasteboard: NSPasteboard) -> InfraCanvasClipboardPayload? {
        guard let data = pasteboard.data(forType: .infraCanvasSelection) else { return nil }
        guard let payload = try? JSONDecoder().decode(InfraCanvasClipboardPayload.self, from: data) else { return nil }
        return payload.nodes.isEmpty ? nil : payload
    }

    private func paste(_ payload: InfraCanvasClipboardPayload, atWorldPoint point: CGPoint?) {
        guard !payload.nodes.isEmpty else { return }
        registerUndoSnapshot()

        let payloadBounds = bounds(for: payload.nodes)
        let fallbackOffset = CGSize(width: 28, height: 28)
        let offset: CGSize
        if let point {
            offset = CGSize(width: point.x - payloadBounds.minX, height: point.y - payloadBounds.minY)
        } else {
            offset = fallbackOffset
        }

        var idMap: [DiagramNode.ID: DiagramNode.ID] = [:]
        var pastedNodes: [DiagramNode] = []

        for node in payload.nodes {
            var pastedNode = node
            let newID = UUID()
            pastedNode.id = newID
            pastedNode.x += Double(offset.width)
            pastedNode.y += Double(offset.height)
            idMap[node.id] = newID
            pastedNodes.append(pastedNode)
        }

        let pastedEdges = payload.edges.compactMap { edge -> DiagramEdge? in
            guard let sourceID = idMap[edge.sourceNodeID], let targetID = idMap[edge.targetNodeID] else { return nil }
            return DiagramEdge(
                sourceNodeID: sourceID,
                targetNodeID: targetID,
                label: edge.label,
                showsLabel: edge.showsLabel,
                hasArrow: edge.hasArrow,
                style: edge.style,
                kind: edge.kind,
                manualRoute: translatedManualRoute(edge.manualRoute, by: offset)
            )
        }

        let pastedGroups = payload.groups.compactMap { group -> DiagramGroup? in
            let mappedIDs = Set(group.nodeIDs.compactMap { idMap[$0] })
            guard mappedIDs.count == group.nodeIDs.count, mappedIDs.count >= 2 else { return nil }
            return DiagramGroup(name: group.name, nodeIDs: mappedIDs)
        }

        board.nodes.append(contentsOf: pastedNodes)
        board.edges.append(contentsOf: pastedEdges)
        board.groups.append(contentsOf: pastedGroups)

        let pastedIDs = Set(pastedNodes.map(\.id))
        if let onlyGroup = pastedGroups.first, pastedGroups.count == 1, onlyGroup.nodeIDs == pastedIDs {
            selectGroup(onlyGroup.id)
        } else {
            selectNodes(pastedIDs)
        }

        activeTool = .select
        markDirty()
    }

    private func bounds(for nodes: [DiagramNode]) -> CGRect {
        guard var bounds = nodes.first?.worldRect else { return .zero }

        for node in nodes.dropFirst() {
            bounds = bounds.union(node.worldRect)
        }

        return bounds
    }

    private func duplicateNodes(_ ids: Set<DiagramNode.ID>) {
        guard !ids.isEmpty else { return }

        let shouldPreserveGroup = group(matching: ids) != nil
        let offset = 28.0
        var idMap: [DiagramNode.ID: DiagramNode.ID] = [:]
        var duplicatedNodes: [DiagramNode] = []

        for node in board.nodes where ids.contains(node.id) {
            var duplicate = node
            let newID = UUID()
            duplicate.id = newID
            duplicate.title = nextDuplicateTitle(for: node.title)
            duplicate.x += offset
            duplicate.y += offset
            idMap[node.id] = newID
            duplicatedNodes.append(duplicate)
        }

        guard !duplicatedNodes.isEmpty else { return }
        registerUndoSnapshot()

        let duplicatedEdges = board.edges.compactMap { edge -> DiagramEdge? in
            guard let sourceID = idMap[edge.sourceNodeID], let targetID = idMap[edge.targetNodeID] else { return nil }
            return DiagramEdge(
                sourceNodeID: sourceID,
                targetNodeID: targetID,
                label: edge.label,
                showsLabel: edge.showsLabel,
                hasArrow: edge.hasArrow,
                style: edge.style,
                kind: edge.kind,
                manualRoute: translatedManualRoute(edge.manualRoute, by: CGSize(width: offset, height: offset))
            )
        }

        board.nodes.append(contentsOf: duplicatedNodes)
        board.edges.append(contentsOf: duplicatedEdges)

        let duplicatedIDs = Set(duplicatedNodes.map(\.id))
        if shouldPreserveGroup, duplicatedIDs.count >= 2 {
            let groupNumber = board.groups.count + 1
            let group = DiagramGroup(name: "Group \(groupNumber)", nodeIDs: duplicatedIDs)
            board.groups.append(group)
            selectGroup(group.id)
        } else {
            selectNodes(duplicatedIDs)
        }

        markDirty()
    }

    private func nextDuplicateTitle(for title: String) -> String {
        let candidate = "\(title) Copy"
        let existingTitles = Set(board.nodes.map(\.title))
        guard existingTitles.contains(candidate) else { return candidate }

        var index = 2
        while existingTitles.contains("\(candidate) \(index)") {
            index += 1
        }
        return "\(candidate) \(index)"
    }

    private func translatedManualRoute(_ route: ManualConnectorRoute?, by offset: CGSize) -> ManualConnectorRoute? {
        route.map { route in
            ManualConnectorRoute(
                sourceSide: route.sourceSide,
                targetSide: route.targetSide,
                waypoints: route.waypoints.map { point in
                    DiagramPoint(CGPoint(x: point.x + offset.width, y: point.y + offset.height))
                }
            )
        }
    }

    func confirmDiscardingUnsavedChangesIfNeeded() -> Bool {
        guard isDirty else { return true }

        let alert = NSAlert()
        alert.messageText = "Save changes to \(board.name)?"
        alert.informativeText = "Your changes will be lost if you continue without saving."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save()
            return !isDirty
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func presentFileError(_ error: Error) {
        lastFileError = error.localizedDescription

        let alert = NSAlert(error: error)
        alert.messageText = "InfraCanvas could not complete the file operation."
        alert.runModal()
    }
}

enum NodeAlignment {
    case left
    case horizontalCenter
    case right
    case top
    case verticalMiddle
    case bottom
}

enum DistributionAxis {
    case horizontal
    case vertical
}

enum NudgeDirection {
    case left
    case right
    case up
    case down
}

private struct InfraCanvasClipboardPayload: Codable {
    var nodes: [DiagramNode]
    var edges: [DiagramEdge]
    var groups: [DiagramGroup]
}

private struct BoardHistoryState: Equatable {
    var board: Board
    var isDirty: Bool
    var selectedNodeID: DiagramNode.ID?
    var selectedNodeIDs: Set<DiagramNode.ID>
    var selectedEdgeID: DiagramEdge.ID?
    var selectedGroupID: DiagramGroup.ID?
    var connectionSourceNodeID: DiagramNode.ID?
    var activeTool: CanvasTool
}

private extension NSPasteboard.PasteboardType {
    static let infraCanvasSelection = NSPasteboard.PasteboardType("com.andrewbacon.infracanvas.selection")
}

enum BoardExportFormat {
    case png
    case pdf

    var title: String {
        switch self {
        case .png: "PNG"
        case .pdf: "PDF"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .pdf: "pdf"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: .png
        case .pdf: .pdf
        }
    }
}

struct BoardExportRenderer {
    var board: Board
    var padding: CGFloat = 72
    var scale: CGFloat = 2

    var contentBounds: CGRect {
        guard var bounds = board.nodes.first?.worldRect else {
            return CGRect(x: 0, y: 0, width: 960, height: 640)
        }

        for node in board.nodes.dropFirst() {
            bounds = bounds.union(node.worldRect)
        }

        for route in board.edges.compactMap(\.manualRoute) {
            for waypoint in route.waypoints {
                bounds = bounds.union(CGRect(x: waypoint.x, y: waypoint.y, width: 1, height: 1))
            }
        }

        return bounds
    }

    var exportSize: CGSize {
        let bounds = contentBounds
        return CGSize(width: max(bounds.width + padding * 2, 320), height: max(bounds.height + padding * 2, 240))
    }

    func writePNG(to url: URL) throws {
        let size = exportSize
        let pixelsWide = max(Int(ceil(size.width * scale)), 1)
        let pixelsHigh = max(Int(ceil(size.height * scale)), 1)

        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw BoardExportError.couldNotCreateImage
        }

        representation.size = size

        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: representation) else {
            throw BoardExportError.couldNotCreateImage
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        graphicsContext.cgContext.scaleBy(x: scale, y: scale)
        draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw BoardExportError.couldNotEncodePNG
        }

        try data.write(to: url, options: .atomic)
    }

    func writePDF(to url: URL) throws {
        let size = exportSize
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: size)

        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw BoardExportError.couldNotCreatePDF
        }

        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        draw(in: mediaBox)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()

        try data.write(to: url, options: .atomic)
    }

    private func draw(in rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        NSColor.textBackgroundColor.setFill()
        rect.fill()

        context.saveGState()
        defer { context.restoreGState() }

        let bounds = contentBounds
        let offset = CGSize(width: padding - bounds.minX, height: padding - bounds.minY)

        if board.backgroundStyle == .grid {
            drawGrid(in: rect, offset: offset, contentBounds: bounds, in: context)
        }

        for node in board.nodes {
            draw(node, offset: offset)
        }

        for edge in board.edges {
            draw(edge, offset: offset, in: context)
        }

        let endpointIDs = board.connectorEndpointNodeIDs
        for node in board.nodes where endpointIDs.contains(node.id) {
            draw(node, offset: offset)
        }
    }

    private func draw(_ edge: DiagramEdge, offset: CGSize, in context: CGContext) {
        guard let connectorPath = connectorPath(for: edge, offset: offset) else { return }
        let strokeColor = nsColor(for: edge.kind)

        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(edge.kind.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let dashPattern = edge.kind.dashPattern()
        if !dashPattern.isEmpty {
            context.setLineDash(phase: 0, lengths: dashPattern)
        }
        context.move(to: connectorPath.start)
        for point in connectorPath.points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()

        if edge.hasArrow {
            drawArrowhead(from: connectorPath.arrowStart, to: connectorPath.end, color: strokeColor, in: context)
        }

        if edge.showsLabel, !edge.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let labelSize = connectorLabelSize(for: edge.label)
            let labelCenter = ConnectorRouter.labelCenter(
                for: connectorPath,
                labelSize: labelSize,
                avoiding: connectorLabelObstacleRects(offset: offset),
                gap: 8
            )
            drawLabel(edge.label, centeredAt: labelCenter)
        }
    }

    private func draw(_ node: DiagramNode, offset: CGSize) {
        let rect = exportRect(for: node, offset: offset)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)

        NSColor.windowBackgroundColor.setFill()
        path.fill()

        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1
        path.stroke()

        let expanded = rect.height > 120
        let topTextY = rect.maxY - 38
        let iconRect = expanded
            ? CGRect(x: rect.minX + 14, y: topTextY - 18, width: 40, height: 40)
            : CGRect(x: rect.minX + 14, y: rect.midY - 20, width: 40, height: 40)
        drawSymbol(node.symbolName, tint: nsColor(for: node.tint), in: iconRect, pointSize: 24)

        let textX = rect.minX + 66
        let textWidth = max(rect.width - 82, 10)
        let titleRect = expanded
            ? CGRect(x: textX, y: topTextY, width: textWidth, height: 22)
            : CGRect(x: textX, y: rect.midY + 2, width: textWidth, height: 22)
        let subtitleRect = expanded
            ? CGRect(x: textX, y: topTextY - 24, width: textWidth, height: 18)
            : CGRect(x: textX, y: rect.midY - 22, width: textWidth, height: 18)

        drawText(
            node.title,
            in: titleRect,
            font: .systemFont(ofSize: 14, weight: .semibold),
            color: .labelColor
        )
        drawText(
            node.subtitle,
            in: subtitleRect,
            font: .systemFont(ofSize: 11, weight: .regular),
            color: .secondaryLabelColor
        )

        let trimmedNotes = node.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expanded, !trimmedNotes.isEmpty else { return }

        let notesRect = CGRect(
            x: rect.minX + 14,
            y: rect.minY + 16,
            width: max(rect.width - 28, 10),
            height: max(subtitleRect.minY - rect.minY - 24, 0)
        )
        guard notesRect.height >= 28 else { return }

        drawMultilineText(
            trimmedNotes,
            in: notesRect,
            font: .systemFont(ofSize: 11, weight: .regular),
            color: .secondaryLabelColor
        )
    }

    private func drawGrid(in rect: CGRect, offset: CGSize, contentBounds: CGRect, in context: CGContext) {
        let spacing = CGFloat(32)
        let firstWorldX = floor((contentBounds.minX - padding) / spacing) * spacing
        let lastWorldX = contentBounds.maxX + padding
        let firstWorldY = floor((contentBounds.minY - padding) / spacing) * spacing
        let lastWorldY = contentBounds.maxY + padding

        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.30).cgColor)
        context.setLineWidth(1)

        var worldX = firstWorldX
        while worldX <= lastWorldX {
            let x = worldX + offset.width
            if x >= rect.minX, x <= rect.maxX {
                context.move(to: CGPoint(x: x, y: rect.minY))
                context.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            worldX += spacing
        }

        var worldY = firstWorldY
        while worldY <= lastWorldY {
            let y = worldY + offset.height
            if y >= rect.minY, y <= rect.maxY {
                context.move(to: CGPoint(x: rect.minX, y: y))
                context.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            worldY += spacing
        }

        context.strokePath()
    }

    private func drawArrowhead(from start: CGPoint, to end: CGPoint, color: NSColor, in context: CGContext) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 10
        let spread = CGFloat.pi / 7
        let first = CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread))
        let second = CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))

        context.setFillColor(color.cgColor)
        context.beginPath()
        context.move(to: end)
        context.addLine(to: first)
        context.addLine(to: second)
        context.closePath()
        context.fillPath()
    }

    private func connectorLabelSize(for text: String) -> CGSize {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]

        let textSize = (text as NSString).boundingRect(
            with: CGSize(width: 150, height: 24),
            options: [.usesLineFragmentOrigin],
            attributes: attributes
        ).size
        return CGSize(width: textSize.width + 16, height: textSize.height + 8)
    }

    private func drawLabel(_ text: String, centeredAt midpoint: CGPoint) {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]

        let textSize = (text as NSString).boundingRect(
            with: CGSize(width: 150, height: 24),
            options: [.usesLineFragmentOrigin],
            attributes: attributes
        ).size
        let labelRect = CGRect(
            x: midpoint.x - (textSize.width + 16) / 2,
            y: midpoint.y - (textSize.height + 8) / 2,
            width: textSize.width + 16,
            height: textSize.height + 8
        )

        let path = NSBezierPath(roundedRect: labelRect, xRadius: 7, yRadius: 7)
        NSColor.textBackgroundColor.withAlphaComponent(0.94).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1
        path.stroke()

        text.draw(in: labelRect.insetBy(dx: 8, dy: 4), withAttributes: attributes)
    }

    private func drawSymbol(_ name: String, tint: NSColor, in rect: CGRect, pointSize: CGFloat) {
        guard let image = SymbolCatalog.image(named: name) else {
            drawText("?", in: rect, font: .systemFont(ofSize: pointSize, weight: .bold), color: tint)
            return
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let configuredImage = image.withSymbolConfiguration(configuration) ?? image

        guard let context = NSGraphicsContext.current?.cgContext,
              let cgImage = configuredImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            tint.set()
            configuredImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return
        }

        context.saveGState()
        context.clip(to: rect, mask: cgImage)
        context.setFillColor(tint.cgColor)
        context.fill(rect)
        context.restoreGState()
    }

    private func drawText(_ text: String, in rect: CGRect, font: NSFont, color: NSColor) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        text.draw(in: rect, withAttributes: attributes)
    }

    private func drawMultilineText(_ text: String, in rect: CGRect, font: NSFont, color: NSColor) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        text.draw(in: rect, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func connectorPath(for edge: DiagramEdge, offset: CGSize) -> ConnectorRoute? {
        guard let source = board.nodes.first(where: { $0.id == edge.sourceNodeID }),
              let target = board.nodes.first(where: { $0.id == edge.targetNodeID }) else {
            return nil
        }

        let sourceRect = exportRect(for: source, offset: offset)
        let targetRect = exportRect(for: target, offset: offset)
        let obstacleRects = connectorRouteObstacleRects(offset: offset, excluding: [source.id, target.id])

        return ConnectorRouter.route(
            style: edge.style,
            sourceRect: sourceRect,
            targetRect: targetRect,
            obstacleRects: obstacleRects,
            manualRoute: edge.manualRoute.map { translatedManualRoute($0, by: offset) }
        )
    }

    private func translatedManualRoute(_ route: ManualConnectorRoute, by offset: CGSize) -> ManualConnectorRoute {
        ManualConnectorRoute(
            sourceSide: route.sourceSide,
            targetSide: route.targetSide,
            waypoints: route.waypoints.map { point in
                DiagramPoint(CGPoint(x: point.x + offset.width, y: point.y + offset.height))
            }
        )
    }

    private func exportRect(for node: DiagramNode, offset: CGSize) -> CGRect {
        CGRect(
            x: node.x + Double(offset.width),
            y: node.y + Double(offset.height),
            width: node.width,
            height: node.height
        )
    }

    private func connectorRouteObstacleRects(offset: CGSize, excluding nodeIDs: Set<DiagramNode.ID>) -> [CGRect] {
        board.nodes.compactMap { node in
            nodeIDs.contains(node.id) ? nil : exportRect(for: node, offset: offset)
        }
    }

    private func connectorLabelObstacleRects(offset: CGSize) -> [CGRect] {
        board.nodes.map { exportRect(for: $0, offset: offset) }
    }

    private func nsColor(for tint: NodeTint) -> NSColor {
        switch tint {
        case .blue: .systemBlue
        case .green: .systemGreen
        case .orange: .systemOrange
        case .purple: .systemPurple
        case .red: .systemRed
        case .gray: .systemGray
        }
    }

    private func nsColor(for kind: ConnectorKind) -> NSColor {
        switch kind {
        case .generic:
            NSColor.secondaryLabelColor.withAlphaComponent(0.68)
        case .ethernet:
            NSColor.systemBlue.withAlphaComponent(0.82)
        case .wifi:
            NSColor.systemTeal.withAlphaComponent(0.82)
        case .fiber:
            NSColor.systemPink.withAlphaComponent(0.84)
        case .vpn:
            NSColor.systemPurple.withAlphaComponent(0.82)
        case .power:
            NSColor.systemGreen.withAlphaComponent(0.84)
        case .dependency:
            NSColor.secondaryLabelColor.withAlphaComponent(0.48)
        }
    }
}

enum BoardExportError: LocalizedError {
    case couldNotCreateImage
    case couldNotEncodePNG
    case couldNotCreatePDF

    var errorDescription: String? {
        switch self {
        case .couldNotCreateImage:
            "InfraCanvas could not create the export image."
        case .couldNotEncodePNG:
            "InfraCanvas could not encode the PNG export."
        case .couldNotCreatePDF:
            "InfraCanvas could not create the PDF export."
        }
    }
}

private extension DiagramNode {
    var worldRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

extension Board {
    static var blank: Board {
        Board(name: "Untitled Board", nodes: [], edges: [])
    }

    static let starterSolutionMap: Board = {
        let stakeholders = DiagramNode(title: "Stakeholders", subtitle: "People affected or accountable", symbolName: "person.3", x: 60, y: 80, width: 210, height: 94, tint: .purple, category: .people)
        let needs = DiagramNode(title: "Needs & Outcomes", subtitle: "Goals, pain points, success criteria", symbolName: "target", x: 60, y: 230, width: 210, height: 94, tint: .green, category: .general)
        let experience = DiagramNode(title: "Experience", subtitle: "App, portal, service, or workflow", symbolName: "app.connected.to.app.below.fill", x: 340, y: 80, width: 230, height: 94, tint: .blue, category: .service)
        let process = DiagramNode(title: "Process", subtitle: "Rules, decisions, handoffs", symbolName: "arrow.triangle.branch", x: 340, y: 230, width: 230, height: 94, tint: .green, category: .process)
        let identity = DiagramNode(title: "Identity & Access", subtitle: "Users, roles, auth, permissions", symbolName: "person.badge.shield.checkmark", x: 650, y: 30, width: 230, height: 94, tint: .purple, category: .identity)
        let security = DiagramNode(title: "Security & Policy", subtitle: "Controls, audit, compliance", symbolName: "lock.shield", x: 650, y: 160, width: 230, height: 94, tint: .red, category: .security)
        let network = DiagramNode(title: "Network Boundary", subtitle: "Trust zones and traffic paths", symbolName: "network", x: 650, y: 290, width: 230, height: 94, tint: .green, category: .network)
        let integration = DiagramNode(title: "Integration Layer", subtitle: "APIs, events, automations", symbolName: "curlybraces.square", x: 960, y: 80, width: 230, height: 94, tint: .blue, category: .cloud)
        let data = DiagramNode(title: "Data & State", subtitle: "Records, files, logs, metrics", symbolName: "cylinder.split.1x2", x: 960, y: 230, width: 230, height: 94, tint: .orange, category: .data)
        let operations = DiagramNode(title: "Operations", subtitle: "Monitoring, support, runbooks", symbolName: "waveform.path.ecg", x: 1260, y: 80, width: 220, height: 94, tint: .orange, category: .service)
        let constraints = DiagramNode(title: "Constraints", subtitle: "Cost, time, risk, platform limits", symbolName: "exclamationmark.triangle", x: 1260, y: 230, width: 220, height: 94, tint: .red, category: .general)
        let roadmap = DiagramNode(title: "Roadmap", subtitle: "Milestones, phases, next steps", symbolName: "flag", x: 960, y: 420, width: 230, height: 94, tint: .green, category: .process)

        return Board(
            name: "Solution Map",
            nodes: [
                stakeholders,
                needs,
                experience,
                process,
                identity,
                security,
                network,
                integration,
                data,
                operations,
                constraints,
                roadmap
            ],
            edges: [
                DiagramEdge(sourceNodeID: stakeholders.id, targetNodeID: needs.id, label: "define"),
                DiagramEdge(sourceNodeID: needs.id, targetNodeID: experience.id, label: "shape"),
                DiagramEdge(sourceNodeID: experience.id, targetNodeID: process.id, label: "triggers"),
                DiagramEdge(sourceNodeID: process.id, targetNodeID: integration.id, label: "orchestrates"),
                DiagramEdge(sourceNodeID: integration.id, targetNodeID: data.id, label: "reads/writes"),
                DiagramEdge(sourceNodeID: identity.id, targetNodeID: experience.id, label: "authorizes"),
                DiagramEdge(sourceNodeID: security.id, targetNodeID: identity.id, label: "governs"),
                DiagramEdge(sourceNodeID: security.id, targetNodeID: data.id, label: "protects"),
                DiagramEdge(sourceNodeID: network.id, targetNodeID: integration.id, label: "routes"),
                DiagramEdge(sourceNodeID: data.id, targetNodeID: operations.id, label: "signals"),
                DiagramEdge(sourceNodeID: constraints.id, targetNodeID: roadmap.id, label: "prioritize"),
                DiagramEdge(sourceNodeID: operations.id, targetNodeID: roadmap.id, label: "improves")
            ],
            groups: [
                DiagramGroup(name: "Discovery", nodeIDs: [stakeholders.id, needs.id]),
                DiagramGroup(name: "Solution Core", nodeIDs: [experience.id, process.id, integration.id, data.id]),
                DiagramGroup(name: "Controls", nodeIDs: [identity.id, security.id, network.id]),
                DiagramGroup(name: "Delivery", nodeIDs: [operations.id, constraints.id, roadmap.id])
            ]
        )
    }()
}

extension UTType {
    static var infraCanvasDocument: UTType {
        UTType("com.andrewbacon.infracanvas") ?? .json
    }
}
