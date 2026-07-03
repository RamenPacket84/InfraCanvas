import SwiftUI

struct CanvasWorkspaceView: View {
    @EnvironmentObject private var boardStore: BoardStore

    var body: some View {
        CanvasRepresentable(boardStore: boardStore)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(alignment: .topLeading) {
                ViewportBadge()
                    .padding(14)
            }
            .navigationTitle(boardStore.documentTitle)
    }
}

private struct ViewportBadge: View {
    @EnvironmentObject private var boardStore: BoardStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: boardStore.activeTool.symbolName)
            Text(statusText)
            Divider()
                .frame(height: 14)
            Text(boardStore.zoom, format: .percent.precision(.fractionLength(0)))
        }
        .font(.system(.caption, design: .rounded).weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusText: String {
        if boardStore.activeTool == .connect, boardStore.connectionSourceNodeID != nil {
            return "\(boardStore.activeConnectorKind.title): Choose Target"
        }

        if boardStore.activeTool == .connect {
            return "Connect: \(boardStore.activeConnectorKind.title)"
        }

        return boardStore.activeTool.title
    }
}

struct CanvasRepresentable: NSViewRepresentable {
    @ObservedObject var boardStore: BoardStore

    func makeNSView(context: Context) -> InfraCanvasNSView {
        let view = InfraCanvasNSView(boardStore: boardStore)
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: InfraCanvasNSView, context: Context) {
        nsView.boardStore = boardStore
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(boardStore: boardStore)
    }

    final class Coordinator {
        var boardStore: BoardStore

        init(boardStore: BoardStore) {
            self.boardStore = boardStore
        }
    }
}

final class InfraCanvasNSView: NSView {
    weak var coordinator: CanvasRepresentable.Coordinator?
    var boardStore: BoardStore {
        didSet {
            coordinator?.boardStore = boardStore
        }
    }

    private var dragState: DragState?
    private var trackingAreaReference: NSTrackingArea?
    private var contextNodeID: DiagramNode.ID?
    private var contextEdgeID: DiagramEdge.ID?
    private var contextCanvasPoint: CGPoint?

    init(boardStore: BoardStore) {
        self.boardStore = boardStore
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        if boardStore.board.backgroundStyle == .grid {
            drawGrid(in: bounds)
        }
        drawNodes()
        drawEdges()
        drawConnectorEndpointNodes()
        drawSelectedGroupBounds()
        drawMarqueeSelection()
        drawMinimap()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)

        let location = convert(event.locationInWindow, from: nil)
        contextNodeID = nil
        contextEdgeID = nil
        contextCanvasPoint = location

        if let hitNode = node(at: location) {
            contextNodeID = hitNode.id
            if !boardStore.selectedNodeIDs.contains(hitNode.id) {
                boardStore.selectNode(hitNode.id)
            }
            needsDisplay = true
            return componentMenu(for: hitNode)
        }

        if let hitEdge = edge(at: location) {
            contextEdgeID = hitEdge.id
            boardStore.selectEdge(hitEdge.id)
            needsDisplay = true
            return connectorMenu()
        }

        return canvasMenu()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        let location = convert(event.locationInWindow, from: nil)
        let hitNode = node(at: location)
        let isExtendingSelection = event.modifierFlags.contains(.shift)

        if boardStore.activeTool == .connect {
            if let hitNode {
                boardStore.handleConnectClick(on: hitNode.id)
            } else {
                boardStore.cancelPendingConnection()
                boardStore.selectNode(nil, activateSelectTool: false)
            }
            dragState = nil
            needsDisplay = true
            return
        }

        if boardStore.activeTool == .select,
           let resizeNode = resizeHandleNode(at: location),
           let originalSize = boardStore.size(for: resizeNode.id) {
            boardStore.selectNode(resizeNode.id)
            dragState = .resize(
                id: resizeNode.id,
                startPoint: location,
                originalSize: originalSize,
                hasRegisteredUndo: false
            )
            needsDisplay = true
            return
        }

        if let hitNode, boardStore.activeTool == .select {
            if isExtendingSelection {
                boardStore.toggleNodeSelection(hitNode.id)
                dragState = nil
                needsDisplay = true
                return
            }

            if !boardStore.selectedNodeIDs.contains(hitNode.id) {
                boardStore.selectNode(hitNode.id)
            }
            let movingIDs = boardStore.nodeIDsMovedByDraggingNode(hitNode.id)
            dragState = .node(
                id: hitNode.id,
                startPoint: location,
                movingIDs: movingIDs,
                originalPositions: boardStore.positions(for: movingIDs),
                hasRegisteredUndo: false
            )
        } else if boardStore.activeTool == .select, let hitEdge = edge(at: location) {
            boardStore.selectEdge(hitEdge.id)
            dragState = nil
        } else if boardStore.activeTool == .select {
            if isExtendingSelection {
                dragState = .marquee(origin: location, current: location, initialSelection: boardStore.selectedNodeIDs)
                needsDisplay = true
            } else {
                boardStore.selectNode(nil)
                dragState = .canvas(lastPoint: location)
            }
        } else if boardStore.activeTool == .pan {
            boardStore.selectNode(nil)
            dragState = .canvas(lastPoint: location)
        } else {
            boardStore.selectNode(nil)
            dragState = .canvas(lastPoint: location)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        switch dragState {
        case .node(let id, let startPoint, let movingIDs, let originalPositions, let hasRegisteredUndo):
            let delta = CGSize(width: location.x - startPoint.x, height: location.y - startPoint.y)
            if !hasRegisteredUndo, delta != .zero {
                boardStore.beginUndoableAction()
                dragState = .node(
                    id: id,
                    startPoint: startPoint,
                    movingIDs: movingIDs,
                    originalPositions: originalPositions,
                    hasRegisteredUndo: true
                )
            }
            let shouldSnap = boardStore.snapToGrid && !event.modifierFlags.contains(.option)
            boardStore.moveNodes(movingIDs, from: originalPositions, byScreenDelta: delta, snapToGrid: shouldSnap, registerUndo: false)
            needsDisplay = true
        case .resize(let id, let startPoint, let originalSize, let hasRegisteredUndo):
            let delta = CGSize(width: location.x - startPoint.x, height: location.y - startPoint.y)
            if !hasRegisteredUndo, delta != .zero {
                boardStore.beginUndoableAction()
                dragState = .resize(
                    id: id,
                    startPoint: startPoint,
                    originalSize: originalSize,
                    hasRegisteredUndo: true
                )
            }
            let shouldSnap = boardStore.snapToGrid && !event.modifierFlags.contains(.option)
            let preserveAspectRatio = event.modifierFlags.contains(.shift)
            boardStore.resizeNode(
                id,
                from: originalSize,
                byScreenDelta: delta,
                preserveAspectRatio: preserveAspectRatio,
                snapToGrid: shouldSnap,
                registerUndo: false
            )
            needsDisplay = true
        case .canvas(let lastPoint):
            let delta = CGSize(width: location.x - lastPoint.x, height: location.y - lastPoint.y)
            boardStore.pan(by: delta)
            dragState = .canvas(lastPoint: location)
            needsDisplay = true
        case .marquee(let origin, _, let initialSelection):
            dragState = .marquee(origin: origin, current: location, initialSelection: initialSelection)
            needsDisplay = true
        case nil:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if case .marquee(let origin, let current, let initialSelection) = dragState {
            let selectionRect = normalizedRect(from: origin, to: current)
            let selectedIDs = nodeIDs(in: selectionRect).union(initialSelection)
            boardStore.selectNodes(selectedIDs)
            needsDisplay = true
        }

        dragState = nil
    }

    override func scrollWheel(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        if shouldZoom(with: event) {
            let zoomFactor = scrollZoomFactor(for: event)
            boardStore.setZoom(boardStore.zoom * zoomFactor, anchoredAt: location)
        } else {
            boardStore.pan(by: CGSize(width: -event.scrollingDeltaX, height: -event.scrollingDeltaY))
        }

        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        boardStore.setZoom(boardStore.zoom * (1 + event.magnification), anchoredAt: location)
        needsDisplay = true
    }

    private func shouldZoom(with event: NSEvent) -> Bool {
        event.modifierFlags.contains(.option) || !event.hasPreciseScrollingDeltas
    }

    private func scrollZoomFactor(for event: NSEvent) -> CGFloat {
        let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.01 : 0.08
        let scaledDelta = event.scrollingDeltaY * sensitivity
        return 1 + max(min(scaledDelta, 0.18), -0.18)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            boardStore.deleteSelection()
            needsDisplay = true
        } else if handleArrowKey(event) {
            needsDisplay = true
        } else {
            super.keyDown(with: event)
        }
    }

    private func handleArrowKey(_ event: NSEvent) -> Bool {
        guard boardStore.canCopySelection else { return false }
        guard !event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.control),
              !event.modifierFlags.contains(.option) else {
            return false
        }

        let fine = !event.modifierFlags.contains(.shift)

        switch event.keyCode {
        case 123:
            boardStore.nudgeSelection(.left, fine: fine)
        case 124:
            boardStore.nudgeSelection(.right, fine: fine)
        case 125:
            boardStore.nudgeSelection(.down, fine: fine)
        case 126:
            boardStore.nudgeSelection(.up, fine: fine)
        default:
            return false
        }

        return true
    }

    private func drawGrid(in rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        defer { context.restoreGState() }

        let spacing = 32 * boardStore.zoom
        guard spacing >= 8 else { return }

        let offsetX = boardStore.viewportOffset.width.truncatingRemainder(dividingBy: spacing)
        let offsetY = boardStore.viewportOffset.height.truncatingRemainder(dividingBy: spacing)

        context.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.42).cgColor)
        context.setLineWidth(1)

        var x = offsetX
        while x < rect.maxX {
            context.move(to: CGPoint(x: x, y: rect.minY))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }

        var y = offsetY
        while y < rect.maxY {
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }

        context.strokePath()
    }

    private func drawMarqueeSelection() {
        guard case .marquee(let origin, let current, _) = dragState else { return }

        let rect = normalizedRect(from: origin, to: current)
        guard rect.width > 2 || rect.height > 2 else { return }

        let path = NSBezierPath(rect: rect)
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        path.fill()

        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawMinimap() {
        guard !boardStore.board.nodes.isEmpty, bounds.width >= 520, bounds.height >= 360 else { return }
        guard let worldBounds = minimapWorldBounds() else { return }

        let size = CGSize(width: min(184, bounds.width * 0.22), height: min(128, bounds.height * 0.22))
        let rect = CGRect(x: bounds.maxX - size.width - 16, y: bounds.minY + 16, width: size.width, height: size.height)
        let innerRect = rect.insetBy(dx: 10, dy: 10)
        let scale = min(innerRect.width / worldBounds.width, innerRect.height / worldBounds.height)
        guard scale.isFinite, scale > 0 else { return }

        let contentSize = CGSize(width: worldBounds.width * scale, height: worldBounds.height * scale)
        let contentOrigin = CGPoint(
            x: innerRect.midX - contentSize.width / 2,
            y: innerRect.midY - contentSize.height / 2
        )

        func mapPoint(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: contentOrigin.x + (point.x - worldBounds.minX) * scale,
                y: contentOrigin.y + (point.y - worldBounds.minY) * scale
            )
        }

        func mapRect(_ worldRect: CGRect) -> CGRect {
            let origin = mapPoint(worldRect.origin)
            return CGRect(x: origin.x, y: origin.y, width: worldRect.width * scale, height: worldRect.height * scale)
        }

        let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.textBackgroundColor.withAlphaComponent(0.92).setFill()
        backgroundPath.fill()
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }

        for node in boardStore.board.nodes {
            let nodeRect = mapRect(worldRect(for: node))
            let visibleRect = CGRect(
                x: nodeRect.minX,
                y: nodeRect.minY,
                width: max(nodeRect.width, 3),
                height: max(nodeRect.height, 3)
            )
            let path = NSBezierPath(roundedRect: visibleRect, xRadius: 2, yRadius: 2)
            nsColor(for: node.tint).withAlphaComponent(boardStore.selectedNodeIDs.contains(node.id) ? 0.95 : 0.58).setFill()
            path.fill()
        }

        context.setStrokeColor(NSColor.secondaryLabelColor.withAlphaComponent(0.36).cgColor)
        context.setLineWidth(1)
        for edge in boardStore.board.edges {
            guard let source = boardStore.board.nodes.first(where: { $0.id == edge.sourceNodeID }),
                  let target = boardStore.board.nodes.first(where: { $0.id == edge.targetNodeID }) else {
                continue
            }
            context.move(to: mapPoint(worldRect(for: source).center))
            context.addLine(to: mapPoint(worldRect(for: target).center))
        }
        context.strokePath()

        let endpointIDs = boardStore.board.connectorEndpointNodeIDs
        for node in boardStore.board.nodes where endpointIDs.contains(node.id) {
            let nodeRect = mapRect(worldRect(for: node))
            let visibleRect = CGRect(
                x: nodeRect.minX,
                y: nodeRect.minY,
                width: max(nodeRect.width, 3),
                height: max(nodeRect.height, 3)
            )
            let path = NSBezierPath(roundedRect: visibleRect, xRadius: 2, yRadius: 2)
            nsColor(for: node.tint).withAlphaComponent(boardStore.selectedNodeIDs.contains(node.id) ? 0.95 : 0.58).setFill()
            path.fill()
        }

        let viewportPath = NSBezierPath(rect: mapRect(visibleWorldRect()))
        NSColor.controlAccentColor.withAlphaComponent(0.88).setStroke()
        viewportPath.lineWidth = 1.5
        viewportPath.stroke()
    }

    private func drawEdges() {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        defer { context.restoreGState() }

        let nodeRects = screenRectsByNodeID()
        let labelObstacleRects = Array(nodeRects.values)
        for edge in boardStore.board.edges {
            draw(edge, nodeRects: nodeRects, labelObstacleRects: labelObstacleRects, in: context)
        }
    }

    private func drawSelectedGroupBounds() {
        guard let group = boardStore.selectedGroup,
              let rect = screenBounds(for: group.nodeIDs) else {
            return
        }

        let expandedRect = rect.insetBy(dx: -14 * boardStore.zoom, dy: -14 * boardStore.zoom)
        let path = NSBezierPath(roundedRect: expandedRect, xRadius: 14 * boardStore.zoom, yRadius: 14 * boardStore.zoom)
        let dashPattern: [CGFloat] = [6 * boardStore.zoom, 4 * boardStore.zoom]
        path.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        NSColor.controlAccentColor.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        drawGroupLabel(group.name, at: CGPoint(x: expandedRect.minX + 10 * boardStore.zoom, y: expandedRect.maxY + 8 * boardStore.zoom))
    }

    private func drawGroupLabel(_ text: String, at origin: CGPoint) {
        let font = NSFont.systemFont(ofSize: max(11 * boardStore.zoom, 9), weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.controlAccentColor
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let padding = CGSize(width: 7 * boardStore.zoom, height: 4 * boardStore.zoom)
        let labelRect = CGRect(
            x: origin.x,
            y: origin.y - textSize.height / 2 - padding.height,
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )

        let backgroundPath = NSBezierPath(roundedRect: labelRect, xRadius: 6 * boardStore.zoom, yRadius: 6 * boardStore.zoom)
        NSColor.textBackgroundColor.withAlphaComponent(0.96).setFill()
        backgroundPath.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.35).setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()

        text.draw(in: labelRect.insetBy(dx: padding.width, dy: padding.height), withAttributes: attributes)
    }

    private func draw(
        _ edge: DiagramEdge,
        nodeRects: [DiagramNode.ID: CGRect],
        labelObstacleRects: [CGRect],
        in context: CGContext
    ) {
        guard let connectorPath = connectorPath(for: edge, nodeRects: nodeRects) else { return }

        let selected = boardStore.selectedEdgeID == edge.id
        let strokeColor = selected ? NSColor.controlAccentColor : nsColor(for: edge.kind)

        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(selected ? edge.kind.lineWidth + 1 : edge.kind.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let dashPattern = edge.kind.dashPattern(scale: max(boardStore.zoom, 0.5))
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
                avoiding: labelObstacleRects,
                gap: max(8 * boardStore.zoom, 6)
            )
            drawLabel(edge.label, centeredAt: labelCenter, selected: selected)
        }
    }

    private func drawArrowhead(from start: CGPoint, to end: CGPoint, color: NSColor, in context: CGContext) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(10 * boardStore.zoom, 8)
        let spread = CGFloat.pi / 7

        let first = CGPoint(
            x: end.x - length * cos(angle - spread),
            y: end.y - length * sin(angle - spread)
        )
        let second = CGPoint(
            x: end.x - length * cos(angle + spread),
            y: end.y - length * sin(angle + spread)
        )

        context.setFillColor(color.cgColor)
        context.beginPath()
        context.move(to: end)
        context.addLine(to: first)
        context.addLine(to: second)
        context.closePath()
        context.fillPath()
    }

    private func connectorLabelSize(for text: String) -> CGSize {
        let font = NSFont.systemFont(ofSize: max(11 * boardStore.zoom, 9), weight: .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]

        let maxTextWidth = max(150 * boardStore.zoom, 80)
        let textSize = (text as NSString).boundingRect(
            with: CGSize(width: maxTextWidth, height: 24 * boardStore.zoom),
            options: [.usesLineFragmentOrigin],
            attributes: attributes
        ).size

        let horizontalPadding = 8 * boardStore.zoom
        let verticalPadding = 4 * boardStore.zoom
        return CGSize(width: textSize.width + horizontalPadding * 2, height: textSize.height + verticalPadding * 2)
    }

    private func drawLabel(_ text: String, centeredAt midpoint: CGPoint, selected: Bool) {
        let font = NSFont.systemFont(ofSize: max(11 * boardStore.zoom, 9), weight: .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: selected ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]

        let maxTextWidth = max(150 * boardStore.zoom, 80)
        let textSize = (text as NSString).boundingRect(
            with: CGSize(width: maxTextWidth, height: 24 * boardStore.zoom),
            options: [.usesLineFragmentOrigin],
            attributes: attributes
        ).size

        let horizontalPadding = 8 * boardStore.zoom
        let verticalPadding = 4 * boardStore.zoom
        let labelRect = CGRect(
            x: midpoint.x - (textSize.width + horizontalPadding * 2) / 2,
            y: midpoint.y - (textSize.height + verticalPadding * 2) / 2,
            width: textSize.width + horizontalPadding * 2,
            height: textSize.height + verticalPadding * 2
        )

        let backgroundPath = NSBezierPath(roundedRect: labelRect, xRadius: 7 * boardStore.zoom, yRadius: 7 * boardStore.zoom)
        NSColor.textBackgroundColor.withAlphaComponent(0.94).setFill()
        backgroundPath.fill()

        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.5) : NSColor.separatorColor.withAlphaComponent(0.45)).setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()

        text.draw(
            in: labelRect.insetBy(dx: horizontalPadding, dy: verticalPadding),
            withAttributes: attributes
        )
    }

    private func drawNodes() {
        for node in boardStore.board.nodes {
            draw(node)
        }
    }

    private func drawConnectorEndpointNodes() {
        let endpointIDs = boardStore.board.connectorEndpointNodeIDs
        guard !endpointIDs.isEmpty else { return }

        for node in boardStore.board.nodes where endpointIDs.contains(node.id) {
            draw(node)
        }
    }

    private func draw(_ node: DiagramNode) {
        let rect = screenRect(for: node)
        let selected = boardStore.selectedNodeIDs.contains(node.id)
        let pendingConnection = boardStore.connectionSourceNodeID == node.id
        let cornerRadius = 10 * boardStore.zoom
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

        NSColor.windowBackgroundColor.setFill()
        path.fill()

        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1
        path.stroke()

        if selected || pendingConnection {
            let selectionPath = NSBezierPath(roundedRect: rect.insetBy(dx: -4, dy: -4), xRadius: cornerRadius + 4, yRadius: cornerRadius + 4)
            (pendingConnection ? NSColor.systemGreen : NSColor.controlAccentColor).setStroke()
            selectionPath.lineWidth = 2
            selectionPath.stroke()
        }

        drawNodeContent(node, in: rect)

        if selected, boardStore.selectedNode?.id == node.id {
            drawResizeHandle(for: rect)
        }
    }

    private func drawNodeContent(_ node: DiagramNode, in rect: CGRect) {
        let compactHeight = 120 * boardStore.zoom
        let iconRect: CGRect
        let titleRect: CGRect
        let subtitleRect: CGRect
        let textX = rect.minX + 66 * boardStore.zoom
        let textWidth = max(rect.width - 82 * boardStore.zoom, 10)

        if rect.height > compactHeight {
            let topTextY = rect.maxY - 38 * boardStore.zoom
            iconRect = CGRect(
                x: rect.minX + 14 * boardStore.zoom,
                y: topTextY - 18 * boardStore.zoom,
                width: 40 * boardStore.zoom,
                height: 40 * boardStore.zoom
            )
            titleRect = CGRect(x: textX, y: topTextY, width: textWidth, height: 22 * boardStore.zoom)
            subtitleRect = CGRect(x: textX, y: topTextY - 24 * boardStore.zoom, width: textWidth, height: 18 * boardStore.zoom)
        } else {
            iconRect = CGRect(
                x: rect.minX + 14 * boardStore.zoom,
                y: rect.midY - 20 * boardStore.zoom,
                width: 40 * boardStore.zoom,
                height: 40 * boardStore.zoom
            )
            titleRect = CGRect(x: textX, y: rect.midY + 2 * boardStore.zoom, width: textWidth, height: 22 * boardStore.zoom)
            subtitleRect = CGRect(x: textX, y: rect.midY - 22 * boardStore.zoom, width: textWidth, height: 18 * boardStore.zoom)
        }

        drawSymbol(node.symbolName, tint: nsColor(for: node.tint), in: iconRect)
        drawText(
            node.title,
            in: titleRect,
            font: .systemFont(ofSize: 14 * boardStore.zoom, weight: .semibold),
            color: .labelColor
        )
        drawText(
            node.subtitle,
            in: subtitleRect,
            font: .systemFont(ofSize: 11 * boardStore.zoom, weight: .regular),
            color: .secondaryLabelColor
        )

        let trimmedNotes = node.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNotes.isEmpty, rect.height > compactHeight else { return }

        let notesRect = CGRect(
            x: rect.minX + 14 * boardStore.zoom,
            y: rect.minY + 16 * boardStore.zoom,
            width: max(rect.width - 28 * boardStore.zoom, 10),
            height: max(subtitleRect.minY - rect.minY - 24 * boardStore.zoom, 0)
        )
        guard notesRect.height >= 28 * boardStore.zoom else { return }

        drawMultilineText(
            trimmedNotes,
            in: notesRect,
            font: .systemFont(ofSize: 11 * boardStore.zoom, weight: .regular),
            color: .secondaryLabelColor
        )
    }

    private func drawResizeHandle(for rect: CGRect) {
        let handleRect = resizeHandleRect(for: rect)
        let path = NSBezierPath(roundedRect: handleRect, xRadius: 4 * boardStore.zoom, yRadius: 4 * boardStore.zoom)

        NSColor.textBackgroundColor.setFill()
        path.fill()

        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        let insetRect = handleRect.insetBy(dx: 4 * boardStore.zoom, dy: 4 * boardStore.zoom)
        let gripPath = NSBezierPath()
        gripPath.move(to: CGPoint(x: insetRect.minX, y: insetRect.maxY))
        gripPath.line(to: CGPoint(x: insetRect.maxX, y: insetRect.minY))
        gripPath.move(to: CGPoint(x: insetRect.midX, y: insetRect.maxY))
        gripPath.line(to: CGPoint(x: insetRect.maxX, y: insetRect.midY))
        NSColor.controlAccentColor.withAlphaComponent(0.72).setStroke()
        gripPath.lineWidth = 1
        gripPath.stroke()
    }

    private func drawSymbol(_ name: String, tint: NSColor, in rect: CGRect) {
        guard let image = SymbolCatalog.image(named: name) else {
            drawText("?", in: rect, font: .systemFont(ofSize: 22 * boardStore.zoom, weight: .bold), color: tint)
            return
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 24 * boardStore.zoom, weight: .semibold)
        let configuredImage = image.withSymbolConfiguration(configuration) ?? image
        let imageRect = CGRect(x: rect.midX - rect.width / 2, y: rect.midY - rect.height / 2, width: rect.width, height: rect.height)

        guard let context = NSGraphicsContext.current?.cgContext,
              let cgImage = configuredImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            tint.set()
            configuredImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
            return
        }

        context.saveGState()
        context.clip(to: imageRect, mask: cgImage)
        context.setFillColor(tint.cgColor)
        context.fill(imageRect)
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
        paragraphStyle.alignment = .left

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

    private func node(at screenPoint: CGPoint) -> DiagramNode? {
        boardStore.board.nodes.reversed().first { node in
            screenRect(for: node).contains(screenPoint)
        }
    }

    private func resizeHandleNode(at screenPoint: CGPoint) -> DiagramNode? {
        guard let selectedNode = boardStore.selectedNode else { return nil }
        let rect = screenRect(for: selectedNode)
        return resizeHandleRect(for: rect).contains(screenPoint) ? selectedNode : nil
    }

    private func resizeHandleRect(for nodeRect: CGRect) -> CGRect {
        let size = max(12 * boardStore.zoom, 10)
        return CGRect(
            x: nodeRect.maxX - size / 2,
            y: nodeRect.maxY - size / 2,
            width: size,
            height: size
        )
    }

    private func edge(at screenPoint: CGPoint) -> DiagramEdge? {
        boardStore.board.edges.reversed().first { edge in
            guard let connectorPath = connectorPath(for: edge) else { return false }
            return connectorPath.segments.contains { segment in
                distance(from: screenPoint, toSegmentStart: segment.start, end: segment.end) <= max(8, 6 * boardStore.zoom)
            }
        }
    }

    private func nodeIDs(in screenRect: CGRect) -> Set<DiagramNode.ID> {
        Set(boardStore.board.nodes.compactMap { node in
            screenRect.intersects(self.screenRect(for: node)) ? node.id : nil
        })
    }

    private func screenBounds(for nodeIDs: Set<DiagramNode.ID>) -> CGRect? {
        let rects = boardStore.board.nodes
            .filter { nodeIDs.contains($0.id) }
            .map(screenRect(for:))

        guard var bounds = rects.first else { return nil }
        for rect in rects.dropFirst() {
            bounds = bounds.union(rect)
        }
        return bounds
    }

    private func minimapWorldBounds() -> CGRect? {
        let nodeRects = boardStore.board.nodes.map(worldRect(for:))
        guard var bounds = nodeRects.first else { return nil }

        for rect in nodeRects.dropFirst() {
            bounds = bounds.union(rect)
        }

        bounds = bounds.union(visibleWorldRect())
        return bounds.insetBy(dx: -80, dy: -80)
    }

    private func visibleWorldRect() -> CGRect {
        CGRect(
            x: (bounds.minX - boardStore.viewportOffset.width) / boardStore.zoom,
            y: (bounds.minY - boardStore.viewportOffset.height) / boardStore.zoom,
            width: bounds.width / boardStore.zoom,
            height: bounds.height / boardStore.zoom
        )
    }

    private func worldRect(for node: DiagramNode) -> CGRect {
        CGRect(x: node.x, y: node.y, width: node.width, height: node.height)
    }

    private func screenRect(for node: DiagramNode) -> CGRect {
        CGRect(
            x: node.x * Double(boardStore.zoom) + Double(boardStore.viewportOffset.width),
            y: node.y * Double(boardStore.zoom) + Double(boardStore.viewportOffset.height),
            width: node.width * Double(boardStore.zoom),
            height: node.height * Double(boardStore.zoom)
        )
    }

    private func connectorPath(for edge: DiagramEdge) -> ConnectorRoute? {
        connectorPath(for: edge, nodeRects: screenRectsByNodeID())
    }

    private func connectorPath(for edge: DiagramEdge, nodeRects: [DiagramNode.ID: CGRect]) -> ConnectorRoute? {
        guard let source = boardStore.board.nodes.first(where: { $0.id == edge.sourceNodeID }),
              let target = boardStore.board.nodes.first(where: { $0.id == edge.targetNodeID }) else {
            return nil
        }

        guard let sourceRect = nodeRects[source.id],
              let targetRect = nodeRects[target.id] else {
            return nil
        }

        let obstacleRects = connectorRouteObstacleRects(from: nodeRects, excluding: [source.id, target.id])
        let options = ConnectorRoutingOptions(
            obstaclePadding: max(10 * boardStore.zoom, 8),
            channelPadding: max(18 * boardStore.zoom, 14),
            endpointLead: max(18 * boardStore.zoom, 12),
            bendPenalty: max(90 * boardStore.zoom, 60),
            backwardAnchorPenalty: max(180 * boardStore.zoom, 120),
            routingBoundsPadding: max(180 * boardStore.zoom, 120),
            maximumObstacleCount: 10
        )

        return ConnectorRouter.route(
            style: edge.style,
            sourceRect: sourceRect,
            targetRect: targetRect,
            obstacleRects: obstacleRects,
            options: options
        )
    }

    private func screenRectsByNodeID() -> [DiagramNode.ID: CGRect] {
        Dictionary(uniqueKeysWithValues: boardStore.board.nodes.map { node in
            (node.id, screenRect(for: node))
        })
    }

    private func connectorRouteObstacleRects(from nodeRects: [DiagramNode.ID: CGRect], excluding nodeIDs: Set<DiagramNode.ID>) -> [CGRect] {
        nodeRects.compactMap { id, rect in
            nodeIDs.contains(id) ? nil : rect
        }
    }

    private func distance(from point: CGPoint, toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y

        guard dx != 0 || dy != 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private func normalizedRect(from firstPoint: CGPoint, to secondPoint: CGPoint) -> CGRect {
        CGRect(
            x: min(firstPoint.x, secondPoint.x),
            y: min(firstPoint.y, secondPoint.y),
            width: abs(secondPoint.x - firstPoint.x),
            height: abs(secondPoint.y - firstPoint.y)
        )
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
            NSColor.secondaryLabelColor.withAlphaComponent(0.64)
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

    private func worldPoint(from screenPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (screenPoint.x - boardStore.viewportOffset.width) / boardStore.zoom,
            y: (screenPoint.y - boardStore.viewportOffset.height) / boardStore.zoom
        )
    }

    private func componentMenu(for node: DiagramNode) -> NSMenu {
        let menu = NSMenu()

        if boardStore.selectedGroup != nil {
            menu.addItem(actionItem("Rename Group...", action: #selector(renameGroupFromMenu), imageName: "pencil"))
        } else if boardStore.hasMultipleSelectedNodes {
            menu.addItem(actionItem("Group Selection", action: #selector(groupSelectionFromMenu), imageName: "rectangle.3.group", enabled: boardStore.canGroupSelectedNodes))
        } else {
            menu.addItem(actionItem("Rename...", action: #selector(renameComponentFromMenu), imageName: "pencil"))
        }
        menu.addItem(actionItem("Edit Notes...", action: #selector(editNotesFromMenu), imageName: "note.text"))

        menu.addItem(.separator())
        if boardStore.canConnectSelectedNodes {
            menu.addItem(actionItem("Connect Selection", action: #selector(connectSelectionFromMenu), imageName: "point.3.connected.trianglepath.dotted"))
        }
        menu.addItem(actionItem("Start Connector", action: #selector(startConnectorFromMenu), imageName: "arrow.right"))

        menu.addItem(.separator())
        menu.addItem(actionItem(boardStore.hasMultipleSelectedNodes ? "Duplicate Selection" : "Duplicate", action: #selector(duplicateFromMenu), imageName: "plus.square.on.square"))
        menu.addItem(actionItem(boardStore.hasMultipleSelectedNodes ? "Copy Selection" : "Copy", action: #selector(copyFromMenu), imageName: "doc.on.doc", enabled: boardStore.canCopySelection))
        menu.addItem(actionItem(boardStore.hasMultipleSelectedNodes ? "Cut Selection" : "Cut", action: #selector(cutFromMenu), imageName: "scissors", enabled: boardStore.canCopySelection))
        menu.addItem(actionItem("Paste", action: #selector(pasteFromMenu), imageName: "doc.on.clipboard", enabled: boardStore.canPasteSelection))

        if boardStore.hasMultipleSelectedNodes {
            addArrangeItems(to: menu)
            menu.addItem(.separator())
        }

        addLayerItems(to: menu)
        menu.addItem(.separator())

        addColorItems(to: menu)
        addSymbolItems(to: menu, node: node)
        menu.addItem(.separator())

        if boardStore.canUngroupSelection {
            menu.addItem(actionItem("Ungroup", action: #selector(ungroupFromMenu), imageName: "rectangle.3.group.bubble.left"))
        } else if boardStore.canGroupSelectedNodes {
            menu.addItem(actionItem("Group Selection", action: #selector(groupSelectionFromMenu), imageName: "rectangle.3.group"))
        }

        menu.addItem(actionItem(boardStore.hasMultipleSelectedNodes ? "Delete Selection" : "Delete", action: #selector(deleteFromMenu), imageName: "trash", destructive: true))

        return menu
    }

    private func connectorMenu() -> NSMenu {
        let menu = NSMenu()
        let edge = contextEdgeID.flatMap { id in
            boardStore.board.edges.first { $0.id == id }
        }
        menu.addItem(actionItem("Rename Label...", action: #selector(renameConnectorFromMenu), imageName: "tag"))
        menu.addItem(actionItem(
            edge?.showsLabel == false ? "Show Label" : "Hide Label",
            action: #selector(toggleConnectorLabelFromMenu),
            imageName: edge?.showsLabel == false ? "text.badge.plus" : "text.badge.minus"
        ))
        menu.addItem(actionItem("Toggle Arrow", action: #selector(toggleArrowFromMenu), imageName: "arrow.right"))
        menu.addItem(actionItem(
            edge?.style == .orthogonal ? "Use Straight Connector" : "Use Elbow Connector",
            action: #selector(toggleConnectorStyleFromMenu),
            imageName: edge?.style == .orthogonal ? ConnectorStyle.straight.symbolName : ConnectorStyle.orthogonal.symbolName
        ))
        addConnectorKindItems(to: menu, edge: edge)
        menu.addItem(.separator())
        menu.addItem(actionItem("Delete Connector", action: #selector(deleteFromMenu), imageName: "trash", destructive: true))
        return menu
    }

    private func canvasMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(actionItem("Add Component Here", action: #selector(addComponentHereFromMenu), imageName: "plus.square.on.square"))
        menu.addItem(actionItem("Paste", action: #selector(pasteFromMenu), imageName: "doc.on.clipboard", enabled: boardStore.canPasteSelection))

        if boardStore.hasSelection {
            menu.addItem(.separator())
            menu.addItem(actionItem("Copy Selection", action: #selector(copyFromMenu), imageName: "doc.on.doc", enabled: boardStore.canCopySelection))
            menu.addItem(actionItem("Cut Selection", action: #selector(cutFromMenu), imageName: "scissors", enabled: boardStore.canCopySelection))
            menu.addItem(actionItem("Delete Selection", action: #selector(deleteFromMenu), imageName: "trash", destructive: true))
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(
            boardStore.board.backgroundStyle == .grid ? "Use Solid Background" : "Use Grid Background",
            action: #selector(toggleBackgroundFromMenu),
            imageName: boardStore.board.backgroundStyle == .grid ? "square" : "square.grid.3x3"
        ))
        menu.addItem(actionItem("Reset View", action: #selector(resetViewFromMenu), imageName: "arrow.up.left.and.down.right.magnifyingglass"))
        return menu
    }

    private func addArrangeItems(to menu: NSMenu) {
        let alignMenu = NSMenu()
        alignMenu.addItem(actionItem("Left", action: #selector(alignLeftFromMenu), imageName: "align.horizontal.left", enabled: boardStore.canAlignSelectedNodes))
        alignMenu.addItem(actionItem("Center", action: #selector(alignCenterFromMenu), imageName: "align.horizontal.center", enabled: boardStore.canAlignSelectedNodes))
        alignMenu.addItem(actionItem("Right", action: #selector(alignRightFromMenu), imageName: "align.horizontal.right", enabled: boardStore.canAlignSelectedNodes))
        alignMenu.addItem(.separator())
        alignMenu.addItem(actionItem("Top", action: #selector(alignTopFromMenu), imageName: "align.vertical.top", enabled: boardStore.canAlignSelectedNodes))
        alignMenu.addItem(actionItem("Middle", action: #selector(alignMiddleFromMenu), imageName: "align.vertical.center", enabled: boardStore.canAlignSelectedNodes))
        alignMenu.addItem(actionItem("Bottom", action: #selector(alignBottomFromMenu), imageName: "align.vertical.bottom", enabled: boardStore.canAlignSelectedNodes))

        let alignItem = NSMenuItem(title: "Align", action: nil, keyEquivalent: "")
        alignItem.image = SymbolCatalog.image(named: "rectangle.alignleft")
        menu.addItem(alignItem)
        menu.setSubmenu(alignMenu, for: alignItem)

        let distributeMenu = NSMenu()
        distributeMenu.addItem(actionItem("Horizontally", action: #selector(distributeHorizontallyFromMenu), imageName: "arrow.left.and.right", enabled: boardStore.canDistributeSelectedNodes))
        distributeMenu.addItem(actionItem("Vertically", action: #selector(distributeVerticallyFromMenu), imageName: "arrow.up.and.down", enabled: boardStore.canDistributeSelectedNodes))

        let distributeItem = NSMenuItem(title: "Distribute", action: nil, keyEquivalent: "")
        distributeItem.image = SymbolCatalog.image(named: "square.grid.3x1.below.line.grid.1x2")
        menu.addItem(distributeItem)
        menu.setSubmenu(distributeMenu, for: distributeItem)
    }

    private func addLayerItems(to menu: NSMenu) {
        let layerMenu = NSMenu()
        layerMenu.addItem(actionItem("Bring Forward", action: #selector(bringForwardFromMenu), imageName: "square.2.layers.3d.top.filled", enabled: boardStore.canReorderSelection))
        layerMenu.addItem(actionItem("Send Backward", action: #selector(sendBackwardFromMenu), imageName: "square.2.layers.3d.bottom.filled", enabled: boardStore.canReorderSelection))
        layerMenu.addItem(.separator())
        layerMenu.addItem(actionItem("Bring to Front", action: #selector(bringToFrontFromMenu), imageName: "rectangle.on.rectangle", enabled: boardStore.canReorderSelection))
        layerMenu.addItem(actionItem("Send to Back", action: #selector(sendToBackFromMenu), imageName: "rectangle.on.rectangle.slash", enabled: boardStore.canReorderSelection))

        let layerItem = NSMenuItem(title: "Layer", action: nil, keyEquivalent: "")
        layerItem.image = SymbolCatalog.image(named: "square.3.layers.3d")
        menu.addItem(layerItem)
        menu.setSubmenu(layerMenu, for: layerItem)
    }

    private func addColorItems(to menu: NSMenu) {
        let colorMenu = NSMenu()
        for tint in NodeTint.allCases {
            let item = actionItem(tint.rawValue.capitalized, action: #selector(setTintFromMenu), imageName: "circle.fill")
            item.representedObject = tint.rawValue
            colorMenu.addItem(item)
        }

        let colorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        colorItem.image = SymbolCatalog.image(named: "paintpalette")
        menu.addItem(colorItem)
        menu.setSubmenu(colorMenu, for: colorItem)
    }

    private func addSymbolItems(to menu: NSMenu, node: DiagramNode) {
        let symbolMenu = NSMenu()
        let templates = ComponentTemplate.library.filter { $0.category == node.category }.prefix(8)
        for template in templates {
            let item = actionItem(template.title, action: #selector(setSymbolFromMenu), imageName: template.symbolName)
            item.representedObject = template.symbolName
            symbolMenu.addItem(item)
        }

        if !symbolMenu.items.isEmpty {
            symbolMenu.addItem(.separator())
        }
        symbolMenu.addItem(actionItem("Custom Symbol...", action: #selector(customSymbolFromMenu), imageName: "square.text.square"))

        let symbolItem = NSMenuItem(title: "Symbol", action: nil, keyEquivalent: "")
        symbolItem.image = SymbolCatalog.image(named: "sparkles.rectangle.stack")
        menu.addItem(symbolItem)
        menu.setSubmenu(symbolMenu, for: symbolItem)
    }

    private func addConnectorKindItems(to menu: NSMenu, edge: DiagramEdge?) {
        let kindMenu = NSMenu()
        for kind in ConnectorKind.allCases {
            let item = actionItem(kind.title, action: #selector(setConnectorKindFromMenu), imageName: kind.symbolName)
            item.representedObject = kind.rawValue
            item.state = edge?.kind == kind ? .on : .off
            kindMenu.addItem(item)
        }

        let kindItem = NSMenuItem(title: "Type", action: nil, keyEquivalent: "")
        kindItem.image = SymbolCatalog.image(named: edge?.kind.symbolName ?? ConnectorKind.generic.symbolName)
        menu.addItem(kindItem)
        menu.setSubmenu(kindMenu, for: kindItem)
    }

    private func actionItem(_ title: String, action: Selector, imageName: String, enabled: Bool = true, destructive: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        item.image = SymbolCatalog.image(named: imageName)
        if destructive {
            item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemRed])
        }
        return item
    }

    @objc private func renameComponentFromMenu() {
        guard let contextNodeID,
              let node = boardStore.board.nodes.first(where: { $0.id == contextNodeID }),
              let name = prompt(title: "Rename Component", message: "Enter a new component title.", value: node.title) else {
            return
        }
        boardStore.updateNode(contextNodeID, title: name)
        needsDisplay = true
    }

    @objc private func editNotesFromMenu() {
        guard let contextNodeID,
              let node = boardStore.board.nodes.first(where: { $0.id == contextNodeID }),
              let notes = promptMultiline(title: "Edit Notes", message: node.title, value: node.notes) else {
            return
        }
        boardStore.updateNode(contextNodeID, notes: notes)
        needsDisplay = true
    }

    @objc private func renameGroupFromMenu() {
        guard let group = boardStore.selectedGroup,
              let name = prompt(title: "Rename Group", message: "Enter a new group name.", value: group.name) else {
            return
        }
        boardStore.updateGroup(group.id, name: name)
        needsDisplay = true
    }

    @objc private func renameConnectorFromMenu() {
        guard let contextEdgeID,
              let edge = boardStore.board.edges.first(where: { $0.id == contextEdgeID }),
              let label = prompt(title: "Rename Connector", message: "Enter a connector label.", value: edge.label) else {
            return
        }
        boardStore.updateEdge(contextEdgeID, label: label)
        needsDisplay = true
    }

    @objc private func customSymbolFromMenu() {
        let currentSymbol = contextNodeID.flatMap { id in
            boardStore.board.nodes.first { $0.id == id }?.symbolName
        } ?? "square.stack.3d.up"

        guard let symbolName = prompt(title: "Change Symbol", message: "Enter an SF Symbol name.", value: currentSymbol) else {
            return
        }
        updateContextNodes(symbolName: symbolName)
        needsDisplay = true
    }

    @objc private func duplicateFromMenu() {
        if let contextNodeID {
            boardStore.duplicateNode(contextNodeID)
        } else {
            boardStore.duplicateSelection()
        }
        needsDisplay = true
    }

    @objc private func connectSelectionFromMenu() {
        boardStore.connectSelectedNodes()
        needsDisplay = true
    }

    @objc private func startConnectorFromMenu() {
        guard let contextNodeID else { return }
        boardStore.startConnection(from: contextNodeID)
        needsDisplay = true
    }

    @objc private func copyFromMenu() {
        boardStore.copySelection()
        needsDisplay = true
    }

    @objc private func cutFromMenu() {
        boardStore.cutSelection()
        needsDisplay = true
    }

    @objc private func pasteFromMenu() {
        let point = contextCanvasPoint.map(worldPoint(from:))
        boardStore.pasteSelection(atWorldPoint: point)
        needsDisplay = true
    }

    @objc private func deleteFromMenu() {
        boardStore.deleteSelection()
        needsDisplay = true
    }

    @objc private func addComponentHereFromMenu() {
        let point = worldPoint(from: contextCanvasPoint ?? CGPoint(x: bounds.midX, y: bounds.midY))
        boardStore.addNode(from: .defaultTemplate, atWorldPoint: point)
        needsDisplay = true
    }

    @objc private func resetViewFromMenu() {
        boardStore.resetViewport()
        needsDisplay = true
    }

    @objc private func toggleBackgroundFromMenu() {
        boardStore.toggleBackgroundStyle()
        needsDisplay = true
    }

    @objc private func setTintFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let tint = NodeTint(rawValue: rawValue) else {
            return
        }
        updateContextNodes(tint: tint)
        needsDisplay = true
    }

    @objc private func setSymbolFromMenu(_ sender: NSMenuItem) {
        guard let symbolName = sender.representedObject as? String else { return }
        updateContextNodes(symbolName: symbolName)
        needsDisplay = true
    }

    @objc private func setConnectorKindFromMenu(_ sender: NSMenuItem) {
        guard let contextEdgeID,
              let rawValue = sender.representedObject as? String,
              let kind = ConnectorKind(rawValue: rawValue) else {
            return
        }
        boardStore.updateEdge(contextEdgeID, kind: kind)
        needsDisplay = true
    }

    @objc private func toggleArrowFromMenu() {
        guard let contextEdgeID,
              let edge = boardStore.board.edges.first(where: { $0.id == contextEdgeID }) else {
            return
        }
        boardStore.updateEdge(contextEdgeID, hasArrow: !edge.hasArrow)
        needsDisplay = true
    }

    @objc private func toggleConnectorLabelFromMenu() {
        guard let contextEdgeID,
              let edge = boardStore.board.edges.first(where: { $0.id == contextEdgeID }) else {
            return
        }
        boardStore.updateEdge(contextEdgeID, showsLabel: !edge.showsLabel)
        needsDisplay = true
    }

    @objc private func toggleConnectorStyleFromMenu() {
        guard let contextEdgeID,
              let edge = boardStore.board.edges.first(where: { $0.id == contextEdgeID }) else {
            return
        }

        boardStore.updateEdge(contextEdgeID, style: edge.style == .orthogonal ? .straight : .orthogonal)
        needsDisplay = true
    }

    @objc private func groupSelectionFromMenu() {
        boardStore.groupSelectedNodes()
        needsDisplay = true
    }

    @objc private func ungroupFromMenu() {
        boardStore.ungroupSelection()
        needsDisplay = true
    }

    @objc private func alignLeftFromMenu() {
        boardStore.alignSelectedNodes(.left)
        needsDisplay = true
    }

    @objc private func alignCenterFromMenu() {
        boardStore.alignSelectedNodes(.horizontalCenter)
        needsDisplay = true
    }

    @objc private func alignRightFromMenu() {
        boardStore.alignSelectedNodes(.right)
        needsDisplay = true
    }

    @objc private func alignTopFromMenu() {
        boardStore.alignSelectedNodes(.top)
        needsDisplay = true
    }

    @objc private func alignMiddleFromMenu() {
        boardStore.alignSelectedNodes(.verticalMiddle)
        needsDisplay = true
    }

    @objc private func alignBottomFromMenu() {
        boardStore.alignSelectedNodes(.bottom)
        needsDisplay = true
    }

    @objc private func distributeHorizontallyFromMenu() {
        boardStore.distributeSelectedNodes(.horizontal)
        needsDisplay = true
    }

    @objc private func distributeVerticallyFromMenu() {
        boardStore.distributeSelectedNodes(.vertical)
        needsDisplay = true
    }

    @objc private func bringForwardFromMenu() {
        boardStore.bringSelectionForward()
        needsDisplay = true
    }

    @objc private func sendBackwardFromMenu() {
        boardStore.sendSelectionBackward()
        needsDisplay = true
    }

    @objc private func bringToFrontFromMenu() {
        boardStore.bringSelectionToFront()
        needsDisplay = true
    }

    @objc private func sendToBackFromMenu() {
        boardStore.sendSelectionToBack()
        needsDisplay = true
    }

    private func prompt(title: String, message: String, value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: CGRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = value
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let trimmedValue = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func promptMultiline(title: String, message: String, value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 360, height: 160))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.autoresizingMask = [.width]
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.string = value
        textView.isRichText = false
        textView.textContainerInset = CGSize(width: 6, height: 6)

        scrollView.documentView = textView
        alert.accessoryView = scrollView

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateContextNodes(tint: NodeTint? = nil, symbolName: String? = nil) {
        if boardStore.hasMultipleSelectedNodes || boardStore.selectedGroup != nil {
            boardStore.updateSelectedNodes(tint: tint, symbolName: symbolName)
        } else if let contextNodeID {
            boardStore.updateNode(contextNodeID, symbolName: symbolName, tint: tint)
        } else {
            boardStore.updateSelectedNodes(tint: tint, symbolName: symbolName)
        }
    }
}

private enum DragState {
    case node(id: DiagramNode.ID, startPoint: CGPoint, movingIDs: Set<DiagramNode.ID>, originalPositions: [DiagramNode.ID: CGPoint], hasRegisteredUndo: Bool)
    case resize(id: DiagramNode.ID, startPoint: CGPoint, originalSize: CGSize, hasRegisteredUndo: Bool)
    case canvas(lastPoint: CGPoint)
    case marquee(origin: CGPoint, current: CGPoint, initialSelection: Set<DiagramNode.ID>)
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
