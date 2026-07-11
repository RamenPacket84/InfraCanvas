import XCTest
import AppKit
@testable import InfraCanvas

@MainActor
final class BoardStoreTests: XCTestCase {
    func testDefaultBoardStoreStartsBlank() {
        let store = BoardStore()

        XCTAssertEqual(store.board.name, "Untitled Board")
        XCTAssertTrue(store.board.nodes.isEmpty)
        XCTAssertTrue(store.board.edges.isEmpty)
        XCTAssertTrue(store.board.groups.isEmpty)
        XCTAssertEqual(store.board.backgroundStyle, .grid)
        XCTAssertFalse(store.isDirty)
    }

    func testAddingNodeSelectsIt() {
        let store = BoardStore(board: Board(name: "Test", nodes: [], edges: []))

        store.addNode(from: ComponentTemplate.defaultTemplate)

        XCTAssertEqual(store.board.nodes.count, 1)
        XCTAssertEqual(store.selectedNodeID, store.board.nodes.first?.id)
        XCTAssertEqual(store.selectedNodeIDs, Set(store.board.nodes.map(\.id)))
    }

    func testMovingNodeScalesScreenDeltaByZoom() {
        let node = DiagramNode(
            title: "Node",
            subtitle: "Subtitle",
            symbolName: "square",
            x: 10,
            y: 20,
            width: 100,
            height: 80,
            tint: .blue,
            category: .service
        )
        let store = BoardStore(board: Board(name: "Test", nodes: [node], edges: []))
        store.zoom = 2

        store.moveNode(node.id, byScreenDelta: CGSize(width: 20, height: 10))

        XCTAssertEqual(store.board.nodes[0].x, 20)
        XCTAssertEqual(store.board.nodes[0].y, 25)
    }

    func testMovingSelectedNodeMovesWholeSelection() {
        let first = testNode(title: "First", x: 10, y: 20)
        let second = testNode(title: "Second", x: 110, y: 120)
        let third = testNode(title: "Third", x: 300, y: 320)
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second, third], edges: []))

        store.selectNodes([first.id, second.id])
        store.moveNode(first.id, byScreenDelta: CGSize(width: 40, height: 20))

        XCTAssertEqual(store.board.nodes[0].x, 50)
        XCTAssertEqual(store.board.nodes[0].y, 40)
        XCTAssertEqual(store.board.nodes[1].x, 150)
        XCTAssertEqual(store.board.nodes[1].y, 140)
        XCTAssertEqual(store.board.nodes[2].x, 300)
        XCTAssertEqual(store.board.nodes[2].y, 320)
    }

    func testDraggingWithSnapUsesOriginalPositionsAndSnapsPrimaryNode() {
        let first = testNode(title: "First", x: 10, y: 20)
        let second = testNode(title: "Second", x: 110, y: 120)
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second], edges: []))
        let selectedIDs: Set<DiagramNode.ID> = [first.id, second.id]
        let originalPositions = store.positions(for: selectedIDs)

        store.moveNodes(selectedIDs, from: originalPositions, byScreenDelta: CGSize(width: 20, height: 20), snapToGrid: true)

        XCTAssertEqual(store.board.nodes[0].x, 32)
        XCTAssertEqual(store.board.nodes[0].y, 32)
        XCTAssertEqual(store.board.nodes[1].x, 132)
        XCTAssertEqual(store.board.nodes[1].y, 132)
    }

    func testDraggingCanBypassSnap() {
        let node = testNode(title: "Node", x: 10, y: 20)
        let store = BoardStore(board: Board(name: "Test", nodes: [node], edges: []))
        let selectedIDs: Set<DiagramNode.ID> = [node.id]
        let originalPositions = store.positions(for: selectedIDs)

        store.moveNodes(selectedIDs, from: originalPositions, byScreenDelta: CGSize(width: 20, height: 20), snapToGrid: false)

        XCTAssertEqual(store.board.nodes[0].x, 30)
        XCTAssertEqual(store.board.nodes[0].y, 40)
    }

    func testPanningUpdatesViewportOffsetWithoutDirtyingBoard() {
        let store = BoardStore(board: .blank)
        let originalOffset = store.viewportOffset

        store.pan(by: CGSize(width: 24, height: -12))

        XCTAssertEqual(store.viewportOffset.width, originalOffset.width + 24)
        XCTAssertEqual(store.viewportOffset.height, originalOffset.height - 12)
        XCTAssertFalse(store.isDirty)
    }

    func testZoomAnchoredAtPointKeepsWorldPointUnderPointer() {
        let store = BoardStore(board: .blank)
        store.viewportOffset = CGSize(width: 40, height: 40)
        let anchor = CGPoint(x: 240, y: 160)
        let worldPointBeforeZoom = CGPoint(
            x: (anchor.x - store.viewportOffset.width) / store.zoom,
            y: (anchor.y - store.viewportOffset.height) / store.zoom
        )

        store.setZoom(1.5, anchoredAt: anchor)

        let worldPointAfterZoom = CGPoint(
            x: (anchor.x - store.viewportOffset.width) / store.zoom,
            y: (anchor.y - store.viewportOffset.height) / store.zoom
        )
        XCTAssertEqual(worldPointAfterZoom.x, worldPointBeforeZoom.x, accuracy: 0.0001)
        XCTAssertEqual(worldPointAfterZoom.y, worldPointBeforeZoom.y, accuracy: 0.0001)
        XCTAssertFalse(store.isDirty)
    }

    func testResizingNodeScalesScreenDeltaByZoom() {
        let node = testNode(title: "Node", width: 180, height: 92)
        let store = BoardStore(board: Board(name: "Test", nodes: [node], edges: []))
        store.zoom = 2

        store.resizeNode(node.id, from: node.size, byScreenDelta: CGSize(width: 80, height: 56), snapToGrid: false)

        XCTAssertEqual(store.board.nodes[0].width, 220)
        XCTAssertEqual(store.board.nodes[0].height, 120)
        XCTAssertTrue(store.isDirty)
    }

    func testResizingNodeClampsToMinimumSize() {
        let node = testNode(title: "Node", width: 180, height: 92)
        let store = BoardStore(board: Board(name: "Test", nodes: [node], edges: []))

        store.resizeNode(node.id, to: CGSize(width: 40, height: 30), snapToGrid: false)

        XCTAssertEqual(store.board.nodes[0].width, store.minimumNodeWidth)
        XCTAssertEqual(store.board.nodes[0].height, store.minimumNodeHeight)
    }

    func testResizingNodeCanSnapToGrid() {
        let node = testNode(title: "Node", width: 180, height: 92)
        let store = BoardStore(board: Board(name: "Test", nodes: [node], edges: []))

        store.resizeNode(node.id, to: CGSize(width: 205, height: 136), snapToGrid: true)

        XCTAssertEqual(store.board.nodes[0].width, 192)
        XCTAssertEqual(store.board.nodes[0].height, 128)
    }

    func testResizingNodeCanPreserveAspectRatio() {
        let node = testNode(title: "Node", width: 180, height: 90)
        let store = BoardStore(board: Board(name: "Test", nodes: [node], edges: []))

        store.resizeNode(node.id, to: CGSize(width: 260, height: 100), from: node.size, preserveAspectRatio: true, snapToGrid: false)

        XCTAssertEqual(store.board.nodes[0].width, 260)
        XCTAssertEqual(store.board.nodes[0].height, 130)
    }

    func testUndoRedoResizingNodeTreatsDragAsOneAction() {
        let node = testNode(title: "Node", width: 180, height: 92)
        let store = BoardStore(board: Board(name: "Test", nodes: [node], edges: []))

        store.selectNode(node.id)
        store.beginUndoableAction()
        store.resizeNode(node.id, from: node.size, byScreenDelta: CGSize(width: 20, height: 20), snapToGrid: false, registerUndo: false)
        store.resizeNode(node.id, from: node.size, byScreenDelta: CGSize(width: 60, height: 52), snapToGrid: false, registerUndo: false)

        XCTAssertEqual(store.board.nodes[0].width, 240)
        XCTAssertEqual(store.board.nodes[0].height, 144)

        store.undo()

        XCTAssertEqual(store.board.nodes[0].width, 180)
        XCTAssertEqual(store.board.nodes[0].height, 92)
        XCTAssertEqual(store.selectedNodeIDs, [node.id])

        store.redo()

        XCTAssertEqual(store.board.nodes[0].width, 240)
        XCTAssertEqual(store.board.nodes[0].height, 144)
    }

    func testUndoRedoBackgroundStyleChange() {
        let store = BoardStore(board: .blank)

        store.setBackgroundStyle(.solid)

        XCTAssertEqual(store.board.backgroundStyle, .solid)

        store.undo()

        XCTAssertEqual(store.board.backgroundStyle, .grid)

        store.redo()

        XCTAssertEqual(store.board.backgroundStyle, .solid)
    }

    func testNudgingSelectionSupportsFineAndGridSteps() {
        let node = testNode(title: "Node", x: 10, y: 20)
        let store = BoardStore(board: Board(name: "Test", nodes: [node], edges: []))

        store.selectNode(node.id)
        store.nudgeSelection(.right, fine: true)
        store.nudgeSelection(.down)

        XCTAssertEqual(store.board.nodes[0].x, 11)
        XCTAssertEqual(store.board.nodes[0].y, 52)
    }

    func testLayerOrderingMovesSelectedNodes() {
        let first = testNode(title: "First")
        let second = testNode(title: "Second")
        let third = testNode(title: "Third")
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second, third], edges: []))

        store.selectNode(first.id)
        store.bringSelectionForward()
        XCTAssertEqual(store.board.nodes.map(\.id), [second.id, first.id, third.id])

        store.bringSelectionToFront()
        XCTAssertEqual(store.board.nodes.map(\.id), [second.id, third.id, first.id])

        store.sendSelectionBackward()
        XCTAssertEqual(store.board.nodes.map(\.id), [second.id, first.id, third.id])

        store.sendSelectionToBack()
        XCTAssertEqual(store.board.nodes.map(\.id), [first.id, second.id, third.id])
    }

    func testBoardIdentifiesConnectorEndpointNodesForRedraw() {
        let boundary = testNode(title: "Network", width: 420, height: 260)
        let source = testNode(title: "Source", x: 80, y: 80)
        let target = testNode(title: "Target", x: 280, y: 80)
        let edge = DiagramEdge(sourceNodeID: source.id, targetNodeID: target.id, label: "routes")
        let board = Board(name: "Test", nodes: [boundary, source, target], edges: [edge])

        XCTAssertEqual(board.connectorEndpointNodeIDs, [source.id, target.id])
        XCTAssertFalse(board.connectorEndpointNodeIDs.contains(boundary.id))
    }

    func testTogglingNodeSelection() {
        let first = testNode(title: "First")
        let second = testNode(title: "Second")
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second], edges: []))

        store.toggleNodeSelection(first.id)
        store.toggleNodeSelection(second.id)

        XCTAssertEqual(store.selectedNodeIDs, [first.id, second.id])
        XCTAssertTrue(store.hasMultipleSelectedNodes)

        store.toggleNodeSelection(first.id)

        XCTAssertEqual(store.selectedNodeIDs, [second.id])
    }

    func testDeletingMultipleSelectedNodesRemovesRelatedEdges() {
        let first = testNode(title: "First")
        let second = testNode(title: "Second")
        let third = testNode(title: "Third")
        let firstEdge = DiagramEdge(sourceNodeID: first.id, targetNodeID: third.id, label: "first")
        let secondEdge = DiagramEdge(sourceNodeID: second.id, targetNodeID: third.id, label: "second")
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second, third], edges: [firstEdge, secondEdge]))

        store.selectNodes([first.id, second.id])
        store.deleteSelection()

        XCTAssertEqual(store.board.nodes.map(\.id), [third.id])
        XCTAssertTrue(store.board.edges.isEmpty)
        XCTAssertTrue(store.selectedNodeIDs.isEmpty)
    }

    func testAligningSelectedNodesLeft() {
        let first = testNode(title: "First", x: 30)
        let second = testNode(title: "Second", x: 120)
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second], edges: []))

        store.selectNodes([first.id, second.id])
        store.alignSelectedNodes(.left)

        XCTAssertEqual(store.board.nodes[0].x, 30)
        XCTAssertEqual(store.board.nodes[1].x, 30)
        XCTAssertTrue(store.isDirty)
    }

    func testDistributingSelectedNodesHorizontally() {
        let first = testNode(title: "First", x: 10)
        let second = testNode(title: "Second", x: 90)
        let third = testNode(title: "Third", x: 210)
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second, third], edges: []))

        store.selectNodes([first.id, second.id, third.id])
        store.distributeSelectedNodes(.horizontal)

        XCTAssertEqual(store.board.nodes[0].x, 10)
        XCTAssertEqual(store.board.nodes[1].x, 110)
        XCTAssertEqual(store.board.nodes[2].x, 210)
    }

    func testComponentCatalogHasTemplatesForEveryCategory() {
        for category in ComponentCategory.allCases {
            XCTAssertFalse(
                ComponentTemplate.library.filter { $0.category == category }.isEmpty,
                "\(category.rawValue) should have at least one template"
            )
        }
    }

    func testComponentCatalogTitlesAreUniqueWithinEachCategory() {
        for category in ComponentCategory.allCases {
            let titles = ComponentTemplate.library
                .filter { $0.category == category }
                .map(\.title)
            XCTAssertEqual(Set(titles).count, titles.count, "\(category.rawValue) has duplicate template titles")
        }
    }

    func testComponentCatalogSymbolsAreAvailable() {
        for template in ComponentTemplate.library {
            XCTAssertNotNil(
                NSImage(systemSymbolName: template.symbolName, accessibilityDescription: nil),
                "\(template.title) uses missing symbol \(template.symbolName)"
            )
        }
    }

    func testSymbolCatalogFallsBackForUnavailableSymbols() {
        let unavailableSymbol = "not.a.real.sf.symbol.\(UUID().uuidString)"

        XCTAssertEqual(SymbolCatalog.resolvedName(unavailableSymbol), SymbolCatalog.fallbackSymbolName)
        XCTAssertNotNil(SymbolCatalog.image(named: unavailableSymbol))
    }

    func testStarterSolutionMapIsComprehensiveAndGrouped() {
        let board = Board.starterSolutionMap

        XCTAssertGreaterThanOrEqual(board.nodes.count, 12)
        XCTAssertGreaterThanOrEqual(board.edges.count, 12)
        XCTAssertGreaterThanOrEqual(board.groups.count, 4)
        XCTAssertTrue(board.groups.allSatisfy { $0.nodeIDs.count >= 2 })
    }

    func testGroupingSelectedNodesCreatesPersistentGroup() {
        let first = testNode(title: "First")
        let second = testNode(title: "Second")
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second], edges: []))

        store.selectNodes([first.id, second.id])
        store.groupSelectedNodes()

        XCTAssertEqual(store.board.groups.count, 1)
        XCTAssertEqual(store.board.groups[0].nodeIDs, [first.id, second.id])
        XCTAssertEqual(store.selectedGroupID, store.board.groups[0].id)
        XCTAssertTrue(store.isDirty)
    }

    func testSelectingGroupedNodeSelectsWholeGroup() {
        let first = testNode(title: "First")
        let second = testNode(title: "Second")
        let group = DiagramGroup(name: "Group", nodeIDs: [first.id, second.id])
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second], edges: [], groups: [group]))

        store.selectNode(first.id)

        XCTAssertEqual(store.selectedGroupID, group.id)
        XCTAssertEqual(store.selectedNodeIDs, [first.id, second.id])
    }

    func testMovingGroupedNodeMovesWholeGroup() {
        let first = testNode(title: "First", x: 10, y: 20)
        let second = testNode(title: "Second", x: 100, y: 120)
        let group = DiagramGroup(name: "Group", nodeIDs: [first.id, second.id])
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second], edges: [], groups: [group]))

        store.moveNode(first.id, byScreenDelta: CGSize(width: 20, height: 30))

        XCTAssertEqual(store.board.nodes[0].x, 30)
        XCTAssertEqual(store.board.nodes[0].y, 50)
        XCTAssertEqual(store.board.nodes[1].x, 120)
        XCTAssertEqual(store.board.nodes[1].y, 150)
    }

    func testMovingGroupedNodeInMixedSelectionMovesAllSelectedNodes() {
        let first = testNode(title: "First", x: 10, y: 20)
        let second = testNode(title: "Second", x: 100, y: 120)
        let third = testNode(title: "Third", x: 300, y: 320)
        let group = DiagramGroup(name: "Group", nodeIDs: [first.id, second.id])
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second, third], edges: [], groups: [group]))

        store.selectNodes([first.id, second.id, third.id])
        store.moveNode(first.id, byScreenDelta: CGSize(width: 20, height: 30))

        XCTAssertEqual(store.board.nodes[0].x, 30)
        XCTAssertEqual(store.board.nodes[1].x, 120)
        XCTAssertEqual(store.board.nodes[2].x, 320)
    }


    func testUngroupSelectionKeepsNodesSelected() {
        let first = testNode(title: "First")
        let second = testNode(title: "Second")
        let group = DiagramGroup(name: "Group", nodeIDs: [first.id, second.id])
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second], edges: [], groups: [group]))

        store.selectGroup(group.id)
        store.ungroupSelection()

        XCTAssertTrue(store.board.groups.isEmpty)
        XCTAssertNil(store.selectedGroupID)
        XCTAssertEqual(store.selectedNodeIDs, [first.id, second.id])
    }

    func testDuplicatingGroupPreservesInternalEdgesAndCreatesNewGroup() {
        let first = testNode(title: "First")
        let second = testNode(title: "Second", x: 140)
        let edge = DiagramEdge(sourceNodeID: first.id, targetNodeID: second.id, label: "inside")
        let group = DiagramGroup(name: "Group", nodeIDs: [first.id, second.id])
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second], edges: [edge], groups: [group]))

        store.selectGroup(group.id)
        store.duplicateSelection()

        XCTAssertEqual(store.board.nodes.count, 4)
        XCTAssertEqual(store.board.edges.count, 2)
        XCTAssertEqual(store.board.groups.count, 2)
        XCTAssertEqual(store.board.groups[1].nodeIDs.count, 2)
        XCTAssertEqual(store.selectedGroupID, store.board.groups[1].id)
    }

    func testCopyPasteSelectionPreservesInternalConnectors() {
        let first = testNode(title: "First")
        let second = testNode(title: "Second", x: 140)
        let outside = testNode(title: "Outside", x: 320)
        let internalEdge = DiagramEdge(sourceNodeID: first.id, targetNodeID: second.id, label: "inside")
        let externalEdge = DiagramEdge(sourceNodeID: second.id, targetNodeID: outside.id, label: "outside")
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second, outside], edges: [internalEdge, externalEdge]))
        let pasteboard = NSPasteboard.withUniqueName()

        store.selectNodes([first.id, second.id])
        store.copySelection(to: pasteboard)
        store.pasteSelection(from: pasteboard)

        XCTAssertEqual(store.board.nodes.count, 5)
        XCTAssertEqual(store.board.edges.count, 3)
        XCTAssertEqual(store.selectedNodeIDs.count, 2)

        let pastedEdge = store.board.edges.last
        XCTAssertEqual(pastedEdge?.label, "inside")
        XCTAssertTrue(store.selectedNodeIDs.contains(pastedEdge?.sourceNodeID ?? UUID()))
        XCTAssertTrue(store.selectedNodeIDs.contains(pastedEdge?.targetNodeID ?? UUID()))
    }

    func testCopyPasteGroupPreservesGroupSelection() {
        let first = testNode(title: "First")
        let second = testNode(title: "Second", x: 140)
        let group = DiagramGroup(name: "Grouped Pattern", nodeIDs: [first.id, second.id])
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second], edges: [], groups: [group]))
        let pasteboard = NSPasteboard.withUniqueName()

        store.selectGroup(group.id)
        store.copySelection(to: pasteboard)
        store.pasteSelection(from: pasteboard)

        XCTAssertEqual(store.board.nodes.count, 4)
        XCTAssertEqual(store.board.groups.count, 2)
        XCTAssertEqual(store.board.groups[1].name, "Grouped Pattern")
        XCTAssertEqual(store.selectedGroupID, store.board.groups[1].id)
        XCTAssertEqual(store.selectedNodeIDs, store.board.groups[1].nodeIDs)
    }

    func testCutSelectionCopiesAndDeletesOriginalNodes() {
        let first = testNode(title: "First")
        let second = testNode(title: "Second", x: 140)
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second], edges: []))
        let pasteboard = NSPasteboard.withUniqueName()

        store.selectNode(first.id)
        store.cutSelection(to: pasteboard)

        XCTAssertEqual(store.board.nodes.map(\.id), [second.id])
        XCTAssertTrue(store.selectedNodeIDs.isEmpty)
        XCTAssertTrue(store.canPasteSelection(from: pasteboard))
    }

    func testPasteSelectionAtWorldPointPlacesPayloadOriginThere() {
        let first = testNode(title: "First", x: 50, y: 60)
        let second = testNode(title: "Second", x: 180, y: 220)
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second], edges: []))
        let pasteboard = NSPasteboard.withUniqueName()

        store.selectNodes([first.id, second.id])
        store.copySelection(to: pasteboard)
        store.pasteSelection(from: pasteboard, atWorldPoint: CGPoint(x: 300, y: 400))

        let pastedNodes = store.board.nodes.suffix(2)
        XCTAssertEqual(pastedNodes.first?.x, 300)
        XCTAssertEqual(pastedNodes.first?.y, 400)
        XCTAssertEqual(pastedNodes.last?.x, 430)
        XCTAssertEqual(pastedNodes.last?.y, 560)
    }

    func testConnectClickCreatesEdgeAndSelectsIt() {
        let source = testNode(title: "Source")
        let target = testNode(title: "Target", x: 220)
        let store = BoardStore(board: Board(name: "Test", nodes: [source, target], edges: []))

        store.handleConnectClick(on: source.id)
        store.handleConnectClick(on: target.id)

        XCTAssertEqual(store.board.edges.count, 1)
        XCTAssertEqual(store.board.edges[0].sourceNodeID, source.id)
        XCTAssertEqual(store.board.edges[0].targetNodeID, target.id)
        XCTAssertEqual(store.board.edges[0].style, .orthogonal)
        XCTAssertEqual(store.selectedEdgeID, store.board.edges[0].id)
        XCTAssertNil(store.connectionSourceNodeID)
        XCTAssertEqual(store.activeTool, .select)
    }

    func testConnectClickUsesActiveConnectorKind() {
        let source = testNode(title: "Source")
        let target = testNode(title: "Target", x: 220)
        let store = BoardStore(board: Board(name: "Test", nodes: [source, target], edges: []))
        store.activeConnectorKind = .ethernet

        store.handleConnectClick(on: source.id)
        store.handleConnectClick(on: target.id)

        XCTAssertEqual(store.board.edges.count, 1)
        XCTAssertEqual(store.board.edges[0].kind, .ethernet)
    }

    func testConnectClickSelectsExistingEdgeInsteadOfDuplicatingIt() {
        let source = testNode(title: "Source")
        let target = testNode(title: "Target", x: 220)
        let edge = DiagramEdge(sourceNodeID: source.id, targetNodeID: target.id, label: "existing")
        let store = BoardStore(board: Board(name: "Test", nodes: [source, target], edges: [edge]))

        store.handleConnectClick(on: source.id)
        store.handleConnectClick(on: target.id)

        XCTAssertEqual(store.board.edges.count, 1)
        XCTAssertEqual(store.selectedEdgeID, edge.id)
        XCTAssertEqual(store.activeTool, .select)
    }

    func testConnectingSelectedNodesCreatesEdgeBetweenAnyComponents() {
        let firstNote = DiagramNode(title: "Note", subtitle: "First idea", symbolName: "note.text", x: 10, y: 20, width: 180, height: 92, tint: .gray, category: .general)
        let secondNote = DiagramNode(title: "Note", subtitle: "Second idea", symbolName: "note.text", x: 240, y: 20, width: 180, height: 92, tint: .gray, category: .general)
        let store = BoardStore(board: Board(name: "Test", nodes: [firstNote, secondNote], edges: []))
        store.activeConnectorKind = .fiber

        store.selectNodes([firstNote.id, secondNote.id])
        store.connectSelectedNodes()

        XCTAssertEqual(store.board.edges.count, 1)
        XCTAssertEqual(store.board.edges[0].sourceNodeID, firstNote.id)
        XCTAssertEqual(store.board.edges[0].targetNodeID, secondNote.id)
        XCTAssertEqual(store.board.edges[0].style, .orthogonal)
        XCTAssertEqual(store.board.edges[0].kind, .fiber)
        XCTAssertEqual(store.selectedEdgeID, store.board.edges[0].id)
        XCTAssertEqual(store.activeTool, .select)
        XCTAssertTrue(store.isDirty)
    }

    func testConnectingSelectedNodesCanCreateStraightConnectorWhenRequested() {
        let first = testNode(title: "First")
        let second = testNode(title: "Second", x: 220)
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second], edges: []))

        store.selectNodes([first.id, second.id])
        store.connectSelectedNodes(style: .straight)

        XCTAssertEqual(store.board.edges.count, 1)
        XCTAssertEqual(store.board.edges[0].style, .straight)
    }

    func testConnectingSelectedNodesCanCreateTypedConnectorWhenRequested() {
        let first = testNode(title: "First")
        let second = testNode(title: "Second", x: 220)
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second], edges: []))
        store.activeConnectorKind = .fiber

        store.selectNodes([first.id, second.id])
        store.connectSelectedNodes(kind: .wifi)

        XCTAssertEqual(store.board.edges.count, 1)
        XCTAssertEqual(store.board.edges[0].kind, .wifi)
    }

    func testChangingActiveConnectorKindDoesNotDirtyBoard() {
        let store = BoardStore(board: Board(name: "Test", nodes: [], edges: []))

        store.activeConnectorKind = .vpn

        XCTAssertEqual(store.activeConnectorKind, .vpn)
        XCTAssertFalse(store.isDirty)
    }

    func testConnectingSelectedNodesSelectsExistingEdgeInsteadOfDuplicatingIt() {
        let first = testNode(title: "First")
        let second = testNode(title: "Second", x: 220)
        let edge = DiagramEdge(sourceNodeID: first.id, targetNodeID: second.id, label: "existing")
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second], edges: [edge]))

        store.selectNodes([first.id, second.id])
        store.connectSelectedNodes()

        XCTAssertEqual(store.board.edges, [edge])
        XCTAssertEqual(store.selectedEdgeID, edge.id)
    }

    func testUpdatingConnectorStyleMarksBoardDirty() {
        let source = testNode(title: "Source")
        let target = testNode(title: "Target", x: 220)
        let edge = DiagramEdge(sourceNodeID: source.id, targetNodeID: target.id, label: "relates to")
        let store = BoardStore(board: Board(name: "Test", nodes: [source, target], edges: [edge]))

        store.updateEdge(edge.id, style: .orthogonal)

        XCTAssertEqual(store.board.edges[0].style, .orthogonal)
        XCTAssertTrue(store.isDirty)
    }

    func testUpdatingConnectorKindMarksBoardDirty() {
        let source = testNode(title: "Source")
        let target = testNode(title: "Target", x: 220)
        let edge = DiagramEdge(sourceNodeID: source.id, targetNodeID: target.id, label: "relates to")
        let store = BoardStore(board: Board(name: "Test", nodes: [source, target], edges: [edge]))

        store.updateEdge(edge.id, kind: .ethernet)

        XCTAssertEqual(store.board.edges[0].kind, .ethernet)
        XCTAssertTrue(store.isDirty)
    }

    func testUpdatingConnectorLabelVisibilityMarksBoardDirty() {
        let source = testNode(title: "Source")
        let target = testNode(title: "Target", x: 220)
        let edge = DiagramEdge(sourceNodeID: source.id, targetNodeID: target.id, label: "relates to")
        let store = BoardStore(board: Board(name: "Test", nodes: [source, target], edges: [edge]))

        store.updateEdge(edge.id, showsLabel: false)

        XCTAssertFalse(store.board.edges[0].showsLabel)
        XCTAssertTrue(store.isDirty)
    }

    func testMovingManualConnectorWaypointSupportsUndo() {
        let source = testNode(title: "Source")
        let target = testNode(title: "Target", x: 220)
        let route = ManualConnectorRoute(
            sourceSide: .right,
            targetSide: .left,
            waypoints: [DiagramPoint(CGPoint(x: 160, y: 160))]
        )
        let edge = DiagramEdge(sourceNodeID: source.id, targetNodeID: target.id, label: "routes", style: .orthogonal, manualRoute: route)
        let store = BoardStore(board: Board(name: "Test", nodes: [source, target], edges: [edge]))

        store.moveManualWaypoint(for: edge.id, at: 0, to: CGPoint(x: 208, y: 190), snapToGrid: true)

        XCTAssertEqual(store.board.edges[0].manualRoute?.waypoints[0].point, CGPoint(x: 224, y: 192))
        XCTAssertTrue(store.isDirty)

        store.undo()

        XCTAssertEqual(store.board.edges[0].manualRoute, route)
    }

    func testStartConnectionFromNodeArmsConnectTool() {
        let node = testNode(title: "Source")
        let store = BoardStore(board: Board(name: "Test", nodes: [node], edges: []))

        store.startConnection(from: node.id)

        XCTAssertEqual(store.activeTool, .connect)
        XCTAssertEqual(store.connectionSourceNodeID, node.id)
        XCTAssertEqual(store.selectedNodeIDs, [node.id])
        XCTAssertEqual(store.selectedNodeID, node.id)
    }

    func testDeletingSelectedEdgeKeepsNodes() {
        let source = testNode(title: "Source")
        let target = testNode(title: "Target", x: 220)
        let edge = DiagramEdge(sourceNodeID: source.id, targetNodeID: target.id, label: "depends on")
        let store = BoardStore(board: Board(name: "Test", nodes: [source, target], edges: [edge]))

        store.selectEdge(edge.id)
        store.deleteSelection()

        XCTAssertEqual(store.board.nodes.count, 2)
        XCTAssertTrue(store.board.edges.isEmpty)
        XCTAssertNil(store.selectedEdgeID)
    }

    func testEditingMarksBoardDirty() {
        let node = testNode(title: "Original")
        let store = BoardStore(board: Board(name: "Test", nodes: [node], edges: []))

        store.selectNode(node.id)
        store.updateSelectedNode(title: "Updated")

        XCTAssertTrue(store.isDirty)
    }

    func testEditingNodeNotesStoresParagraphAndMarksBoardDirty() {
        let node = testNode(title: "Note")
        let store = BoardStore(board: Board(name: "Test", nodes: [node], edges: []))
        let notes = "This is a longer paragraph explaining why this note exists.\nIt can include multiple lines of context."

        store.selectNode(node.id)
        store.updateSelectedNode(notes: notes)

        XCTAssertEqual(store.board.nodes[0].notes, notes)
        XCTAssertTrue(store.isDirty)
    }

    func testChangingBackgroundStyleMarksBoardDirty() {
        let store = BoardStore(board: .blank)

        store.setBackgroundStyle(.solid)

        XCTAssertEqual(store.board.backgroundStyle, .solid)
        XCTAssertTrue(store.isDirty)
    }

    func testUndoRedoAddingNodeRestoresBoardAndSelection() {
        let store = BoardStore(board: Board(name: "Test", nodes: [], edges: []))
        let initialBoard = store.board

        store.addNode(from: ComponentTemplate.defaultTemplate)

        XCTAssertTrue(store.canUndo)
        XCTAssertFalse(store.canRedo)
        XCTAssertEqual(store.board.nodes.count, 1)

        store.undo()

        XCTAssertEqual(store.board, initialBoard)
        XCTAssertTrue(store.board.nodes.isEmpty)
        XCTAssertFalse(store.isDirty)
        XCTAssertFalse(store.canUndo)
        XCTAssertTrue(store.canRedo)

        store.redo()

        XCTAssertEqual(store.board.nodes.count, 1)
        XCTAssertEqual(store.selectedNodeIDs, Set(store.board.nodes.map(\.id)))
        XCTAssertTrue(store.isDirty)
        XCTAssertTrue(store.canUndo)
        XCTAssertFalse(store.canRedo)
    }

    func testUndoRedoMovingSelectionTreatsDragAsOneAction() {
        let first = testNode(title: "First", x: 10, y: 20)
        let second = testNode(title: "Second", x: 110, y: 120)
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second], edges: []))
        let selectedIDs: Set<DiagramNode.ID> = [first.id, second.id]
        let originalPositions = store.positions(for: selectedIDs)

        store.selectNodes(selectedIDs)
        store.beginUndoableAction()
        store.moveNodes(selectedIDs, from: originalPositions, byScreenDelta: CGSize(width: 20, height: 20), snapToGrid: false, registerUndo: false)
        store.moveNodes(selectedIDs, from: originalPositions, byScreenDelta: CGSize(width: 60, height: 40), snapToGrid: false, registerUndo: false)

        XCTAssertEqual(store.board.nodes[0].x, 70)
        XCTAssertEqual(store.board.nodes[0].y, 60)
        XCTAssertEqual(store.board.nodes[1].x, 170)
        XCTAssertEqual(store.board.nodes[1].y, 160)

        store.undo()

        XCTAssertEqual(store.board.nodes[0].x, 10)
        XCTAssertEqual(store.board.nodes[0].y, 20)
        XCTAssertEqual(store.board.nodes[1].x, 110)
        XCTAssertEqual(store.board.nodes[1].y, 120)
        XCTAssertEqual(store.selectedNodeIDs, selectedIDs)

        store.redo()

        XCTAssertEqual(store.board.nodes[0].x, 70)
        XCTAssertEqual(store.board.nodes[0].y, 60)
        XCTAssertEqual(store.board.nodes[1].x, 170)
        XCTAssertEqual(store.board.nodes[1].y, 160)
    }

    func testUndoRedoDeletingSelectionRestoresRelatedEdges() {
        let source = testNode(title: "Source")
        let target = testNode(title: "Target", x: 220)
        let edge = DiagramEdge(sourceNodeID: source.id, targetNodeID: target.id, label: "depends on")
        let store = BoardStore(board: Board(name: "Test", nodes: [source, target], edges: [edge]))

        store.selectNode(source.id)
        store.deleteSelection()

        XCTAssertEqual(store.board.nodes.map(\.id), [target.id])
        XCTAssertTrue(store.board.edges.isEmpty)

        store.undo()

        XCTAssertEqual(store.board.nodes.map(\.id), [source.id, target.id])
        XCTAssertEqual(store.board.edges, [edge])
        XCTAssertEqual(store.selectedNodeIDs, [source.id])

        store.redo()

        XCTAssertEqual(store.board.nodes.map(\.id), [target.id])
        XCTAssertTrue(store.board.edges.isEmpty)
    }

    func testUndoRedoGroupingRestoresGroupState() {
        let first = testNode(title: "First")
        let second = testNode(title: "Second", x: 140)
        let store = BoardStore(board: Board(name: "Test", nodes: [first, second], edges: []))

        store.selectNodes([first.id, second.id])
        store.groupSelectedNodes()

        XCTAssertEqual(store.board.groups.count, 1)
        XCTAssertNotNil(store.selectedGroupID)

        store.undo()

        XCTAssertTrue(store.board.groups.isEmpty)
        XCTAssertEqual(store.selectedNodeIDs, [first.id, second.id])
        XCTAssertNil(store.selectedGroupID)

        store.redo()

        XCTAssertEqual(store.board.groups.count, 1)
        XCTAssertEqual(store.selectedGroupID, store.board.groups[0].id)
    }

    func testNewEditClearsRedoHistory() {
        let store = BoardStore(board: Board(name: "Test", nodes: [], edges: []))

        store.addNode(from: ComponentTemplate.defaultTemplate)
        store.undo()

        XCTAssertTrue(store.canRedo)

        store.addNode(from: ComponentTemplate.defaultTemplate)

        XCTAssertFalse(store.canRedo)
        XCTAssertTrue(store.canUndo)
    }

    func testSavingAndLoadingBoardFile() throws {
        let source = testNode(title: "Source")
        let target = testNode(title: "Target", x: 220)
        let edge = DiagramEdge(sourceNodeID: source.id, targetNodeID: target.id, label: "sends to")
        let board = Board(name: "Saved Board", nodes: [source, target], edges: [edge])
        let store = BoardStore(board: board)
        let url = temporaryBoardURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try store.save(to: url)

        let loadedStore = BoardStore(board: .blank)
        try loadedStore.load(from: url)

        XCTAssertFalse(store.isDirty)
        XCTAssertEqual(loadedStore.board, board)
        XCTAssertEqual(loadedStore.fileURL, url)
        XCTAssertFalse(loadedStore.isDirty)
    }

    func testSaveAsUpdatesBoardNameFromFilename() throws {
        let store = BoardStore(board: Board(name: "Untitled Board", nodes: [], edges: []))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Home Network")
            .appendingPathExtension("infracanvas")
        defer { try? FileManager.default.removeItem(at: url) }

        try store.save(to: url, updatingBoardNameFromURL: true)

        let loadedStore = BoardStore(board: .blank)
        try loadedStore.load(from: url)

        XCTAssertEqual(store.board.name, "Home Network")
        XCTAssertEqual(loadedStore.board.name, "Home Network")
        XCTAssertEqual(store.documentTitle, "Home Network")
    }

    func testOpeningBoardFromDocumentURLLoadsFile() throws {
        let board = Board(name: "Finder Board", nodes: [testNode(title: "Opened")], edges: [])
        let savedStore = BoardStore(board: board)
        let url = temporaryBoardURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try savedStore.save(to: url)

        let openedStore = BoardStore(board: .blank)
        openedStore.openBoard(from: url)

        XCTAssertEqual(openedStore.board, board)
        XCTAssertEqual(openedStore.fileURL, url)
        XCTAssertFalse(openedStore.isDirty)
    }

    func testSavingAndLoadingBoardBackgroundStyle() throws {
        let board = Board(name: "Solid Board", nodes: [], edges: [], backgroundStyle: .solid)
        let store = BoardStore(board: board)
        let url = temporaryBoardURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try store.save(to: url)

        let loadedStore = BoardStore(board: .blank)
        try loadedStore.load(from: url)

        XCTAssertEqual(loadedStore.board.backgroundStyle, .solid)
        XCTAssertEqual(loadedStore.board, board)
    }

    func testSavingAndLoadingConnectorStyle() throws {
        let source = testNode(title: "Source")
        let target = testNode(title: "Target", x: 220)
        let edge = DiagramEdge(sourceNodeID: source.id, targetNodeID: target.id, label: "routes", style: .orthogonal)
        let board = Board(name: "Saved Connector Style", nodes: [source, target], edges: [edge])
        let store = BoardStore(board: board)
        let url = temporaryBoardURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try store.save(to: url)

        let loadedStore = BoardStore(board: .blank)
        try loadedStore.load(from: url)

        XCTAssertEqual(loadedStore.board.edges.first?.style, .orthogonal)
        XCTAssertEqual(loadedStore.board, board)
    }

    func testSavingAndLoadingConnectorKind() throws {
        let source = testNode(title: "Source")
        let target = testNode(title: "Target", x: 220)
        let edge = DiagramEdge(sourceNodeID: source.id, targetNodeID: target.id, label: "routes", kind: .vpn)
        let board = Board(name: "Saved Connector Kind", nodes: [source, target], edges: [edge])
        let store = BoardStore(board: board)
        let url = temporaryBoardURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try store.save(to: url)

        let loadedStore = BoardStore(board: .blank)
        try loadedStore.load(from: url)

        XCTAssertEqual(loadedStore.board.edges.first?.kind, .vpn)
        XCTAssertEqual(loadedStore.board, board)
    }

    func testSavingAndLoadingConnectorLabelVisibility() throws {
        let source = testNode(title: "Source")
        let target = testNode(title: "Target", x: 220)
        let edge = DiagramEdge(sourceNodeID: source.id, targetNodeID: target.id, label: "routes", showsLabel: false)
        let board = Board(name: "Saved Connector Label Visibility", nodes: [source, target], edges: [edge])
        let store = BoardStore(board: board)
        let url = temporaryBoardURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try store.save(to: url)

        let loadedStore = BoardStore(board: .blank)
        try loadedStore.load(from: url)

        XCTAssertEqual(loadedStore.board.edges.first?.showsLabel, false)
        XCTAssertEqual(loadedStore.board, board)
    }

    func testSavingAndLoadingManualConnectorRoute() throws {
        let source = testNode(title: "Source")
        let target = testNode(title: "Target", x: 220)
        let route = ManualConnectorRoute(
            sourceSide: .right,
            targetSide: .left,
            waypoints: [DiagramPoint(CGPoint(x: 160, y: 160))]
        )
        let edge = DiagramEdge(sourceNodeID: source.id, targetNodeID: target.id, label: "routes", style: .orthogonal, manualRoute: route)
        let board = Board(name: "Saved Manual Route", nodes: [source, target], edges: [edge])
        let store = BoardStore(board: board)
        let url = temporaryBoardURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try store.save(to: url)

        let loadedStore = BoardStore(board: .blank)
        try loadedStore.load(from: url)

        XCTAssertEqual(loadedStore.board.edges.first?.manualRoute, route)
        XCTAssertEqual(loadedStore.board, board)
    }

    func testSavingAndLoadingNodeNotes() throws {
        let node = DiagramNode(
            title: "Note",
            subtitle: "Context",
            notes: "A short paragraph that should survive saving and loading.",
            symbolName: "note.text",
            x: 10,
            y: 20,
            width: 180,
            height: 92,
            tint: .gray,
            category: .general
        )
        let board = Board(name: "Saved Notes", nodes: [node], edges: [])
        let store = BoardStore(board: board)
        let url = temporaryBoardURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try store.save(to: url)

        let loadedStore = BoardStore(board: .blank)
        try loadedStore.load(from: url)

        XCTAssertEqual(loadedStore.board.nodes.first?.notes, node.notes)
        XCTAssertEqual(loadedStore.board, board)
    }

    func testLoadingOlderBoardWithoutGroupsDefaultsToEmptyGroups() throws {
        let json = """
        {
          "schemaVersion" : 1,
          "board" : {
            "id" : "\(UUID().uuidString)",
            "name" : "Old Board",
            "nodes" : [],
            "edges" : []
          }
        }
        """
        let url = temporaryBoardURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try json.data(using: .utf8)?.write(to: url)

        let store = BoardStore(board: .blank)
        try store.load(from: url)

        XCTAssertEqual(store.board.name, "Old Board")
        XCTAssertTrue(store.board.groups.isEmpty)
        XCTAssertEqual(store.board.backgroundStyle, .grid)
    }

    func testLoadingOlderConnectorWithoutStyleDefaultsToStraight() throws {
        let sourceID = UUID()
        let targetID = UUID()
        let edgeID = UUID()
        let json = """
        {
          "schemaVersion" : 4,
          "board" : {
            "id" : "\(UUID().uuidString)",
            "name" : "Old Connector Board",
            "nodes" : [
              {
                "id" : "\(sourceID.uuidString)",
                "title" : "Source",
                "subtitle" : "Older node",
                "notes" : "",
                "symbolName" : "square",
                "x" : 10,
                "y" : 20,
                "width" : 180,
                "height" : 92,
                "tint" : "blue",
                "category" : "Services"
              },
              {
                "id" : "\(targetID.uuidString)",
                "title" : "Target",
                "subtitle" : "Older node",
                "notes" : "",
                "symbolName" : "square",
                "x" : 240,
                "y" : 20,
                "width" : 180,
                "height" : 92,
                "tint" : "green",
                "category" : "Services"
              }
            ],
            "edges" : [
              {
                "id" : "\(edgeID.uuidString)",
                "sourceNodeID" : "\(sourceID.uuidString)",
                "targetNodeID" : "\(targetID.uuidString)",
                "label" : "older",
                "hasArrow" : true
              }
            ],
            "groups" : [],
            "backgroundStyle" : "grid"
          }
        }
        """
        let url = temporaryBoardURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try json.data(using: .utf8)?.write(to: url)

        let store = BoardStore(board: .blank)
        try store.load(from: url)

        XCTAssertEqual(store.board.edges.first?.style, .straight)
        XCTAssertEqual(store.board.edges.first?.showsLabel, true)
    }

    func testLoadingOlderNodeWithoutNotesDefaultsToEmptyString() throws {
        let nodeID = UUID()
        let json = """
        {
          "schemaVersion" : 2,
          "board" : {
            "id" : "\(UUID().uuidString)",
            "name" : "Old Notes Board",
            "nodes" : [
              {
                "id" : "\(nodeID.uuidString)",
                "title" : "Older Note",
                "subtitle" : "No notes field",
                "symbolName" : "note.text",
                "x" : 10,
                "y" : 20,
                "width" : 180,
                "height" : 92,
                "tint" : "gray",
                "category" : "General"
              }
            ],
            "edges" : [],
            "groups" : []
          }
        }
        """
        let url = temporaryBoardURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try json.data(using: .utf8)?.write(to: url)

        let store = BoardStore(board: .blank)
        try store.load(from: url)

        XCTAssertEqual(store.board.nodes.first?.id, nodeID)
        XCTAssertEqual(store.board.nodes.first?.notes, "")
    }

    func testExportRendererFramesBoardContent() {
        let first = testNode(title: "First", x: -20, y: 10)
        let second = testNode(title: "Second", x: 180, y: 220)
        let renderer = BoardExportRenderer(board: Board(name: "Test", nodes: [first, second], edges: []))

        XCTAssertEqual(renderer.contentBounds.minX, -20)
        XCTAssertEqual(renderer.contentBounds.minY, 10)
        XCTAssertEqual(renderer.contentBounds.maxX, 280)
        XCTAssertEqual(renderer.contentBounds.maxY, 300)
    }

    func testExportPNGCreatesFile() throws {
        let store = BoardStore(board: Board(name: "Export", nodes: [testNode(title: "Node")], edges: []))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("InfraCanvas-\(UUID().uuidString)")
            .appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: url) }

        try store.exportPNG(to: url)

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 8)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    func testExportPDFCreatesFile() throws {
        let store = BoardStore(board: Board(name: "Export", nodes: [testNode(title: "Node")], edges: []))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("InfraCanvas-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        try store.exportPDF(to: url)

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 4)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF")
    }

    func testSavingAddsInfraCanvasExtensionWhenMissing() throws {
        let store = BoardStore(board: Board(name: "Test", nodes: [], edges: []))
        let urlWithoutExtension = FileManager.default.temporaryDirectory
            .appendingPathComponent("InfraCanvas-\(UUID().uuidString)")
        let expectedURL = urlWithoutExtension.appendingPathExtension("infracanvas")
        defer { try? FileManager.default.removeItem(at: expectedURL) }

        try store.save(to: urlWithoutExtension)

        XCTAssertEqual(store.fileURL, expectedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))
    }

    func testLoadingBoardClearsUndoRedoHistory() throws {
        let node = testNode(title: "Loaded")
        let savedBoard = Board(name: "Saved", nodes: [node], edges: [])
        let url = temporaryBoardURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try BoardStore(board: savedBoard).save(to: url)

        let store = BoardStore(board: Board(name: "Working", nodes: [], edges: []))
        store.addNode(from: ComponentTemplate.defaultTemplate)
        store.undo()

        XCTAssertTrue(store.canRedo)

        try store.load(from: url)

        XCTAssertEqual(store.board, savedBoard)
        XCTAssertFalse(store.canUndo)
        XCTAssertFalse(store.canRedo)
    }

    private func testNode(
        title: String,
        x: Double = 10,
        y: Double = 20,
        width: Double = 100,
        height: Double = 80,
        notes: String = ""
    ) -> DiagramNode {
        DiagramNode(
            title: title,
            subtitle: "Subtitle",
            notes: notes,
            symbolName: "square",
            x: x,
            y: y,
            width: width,
            height: height,
            tint: .blue,
            category: .service
        )
    }

    private func temporaryBoardURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("InfraCanvas-\(UUID().uuidString)")
            .appendingPathExtension("infracanvas")
    }
}
