import CoreGraphics
import Foundation

struct ConnectorRoutingOptions: Equatable {
    var obstaclePadding: CGFloat = 10
    var channelPadding: CGFloat = 18
    var endpointLead: CGFloat = 18
    var bendPenalty: CGFloat = 90
    var backwardAnchorPenalty: CGFloat = 180
    var routingBoundsPadding: CGFloat = 180
    var maximumObstacleCount: Int = 10
}

struct ConnectorRoute: Equatable {
    var points: [CGPoint]

    var start: CGPoint {
        points.first ?? .zero
    }

    var end: CGPoint {
        points.last ?? .zero
    }

    var arrowStart: CGPoint {
        points.dropLast().last ?? start
    }

    var midpoint: CGPoint {
        point(atDistanceFraction: 0.5)
    }

    var segments: [ConnectorSegment] {
        guard points.count >= 2 else { return [] }
        return zip(points, points.dropFirst()).map { ConnectorSegment(start: $0, end: $1) }
    }

    var length: CGFloat {
        segments.reduce(CGFloat(0)) { $0 + $1.length }
    }

    var bendCount: Int {
        let axes = segments.compactMap(\.axis)
        guard axes.count >= 2 else { return 0 }

        return zip(axes, axes.dropFirst()).reduce(0) { count, pair in
            count + (pair.0 == pair.1 ? 0 : 1)
        }
    }

    func point(atDistanceFraction fraction: CGFloat) -> CGPoint {
        guard !segments.isEmpty else { return start }

        let clampedFraction = min(max(fraction, 0), 1)
        let targetDistance = length * clampedFraction
        var traveled: CGFloat = 0

        for segment in segments {
            let nextDistance = traveled + segment.length
            if nextDistance >= targetDistance {
                let progress = segment.length == 0 ? 0 : (targetDistance - traveled) / segment.length
                return CGPoint(
                    x: segment.start.x + (segment.end.x - segment.start.x) * progress,
                    y: segment.start.y + (segment.end.y - segment.start.y) * progress
                )
            }
            traveled = nextDistance
        }

        return end
    }
}

struct ConnectorSegment: Equatable {
    var start: CGPoint
    var end: CGPoint

    var length: CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    var axis: ConnectorAxis? {
        if abs(end.x - start.x) < 0.0001 {
            return .vertical
        }

        if abs(end.y - start.y) < 0.0001 {
            return .horizontal
        }

        return nil
    }
}

enum ConnectorRouter {
    static func route(
        style: ConnectorStyle,
        sourceRect: CGRect,
        targetRect: CGRect,
        obstacleRects: [CGRect],
        manualRoute: ManualConnectorRoute? = nil,
        options: ConnectorRoutingOptions = ConnectorRoutingOptions()
    ) -> ConnectorRoute {
        if style == .orthogonal, let manualRoute, !manualRoute.waypoints.isEmpty {
            return manualOrthogonalRoute(
                from: sourceRect,
                to: targetRect,
                manualRoute: manualRoute,
                options: options
            )
        }

        let obstacles = inflatedObstacles(from: obstacleRects, options: options)

        switch style {
        case .straight:
            return straightRoute(from: sourceRect, to: targetRect)
        case .orthogonal:
            let nearbyObstacles = relevantObstacles(from: obstacles, sourceRect: sourceRect, targetRect: targetRect, options: options)
            let simpleRoute = fallbackOrthogonalRoute(from: sourceRect, to: targetRect)
            if routeIsClear(simpleRoute, avoiding: nearbyObstacles) {
                return simpleRoute
            }

            return orthogonalRoute(from: sourceRect, to: targetRect, avoiding: nearbyObstacles, options: options)
        }
    }

    static func labelCenter(
        for route: ConnectorRoute,
        labelSize: CGSize,
        avoiding obstacleRects: [CGRect],
        gap: CGFloat
    ) -> CGPoint {
        guard !route.segments.isEmpty else { return route.start }

        let paddedObstacles = obstacleRects.map { $0.insetBy(dx: -4, dy: -4) }
        let pathMidpoint = route.midpoint
        var candidates: [LabelCandidate] = [
            LabelCandidate(center: pathMidpoint, priority: 0)
        ]

        for fraction in [CGFloat(0.35), CGFloat(0.65), CGFloat(0.2), CGFloat(0.8)] {
            candidates.append(LabelCandidate(center: route.point(atDistanceFraction: fraction), priority: 18))
        }

        let sortedSegments = route.segments.sorted { $0.length > $1.length }
        for segment in sortedSegments {
            guard segment.length > 0 else { continue }

            let midpoint = CGPoint(
                x: (segment.start.x + segment.end.x) / 2,
                y: (segment.start.y + segment.end.y) / 2
            )
            let offsets = labelOffsets(for: segment, labelSize: labelSize, gap: gap)

            for (index, offset) in offsets.enumerated() {
                candidates.append(
                    LabelCandidate(
                        center: CGPoint(x: midpoint.x + offset.width, y: midpoint.y + offset.height),
                        priority: CGFloat(index) * 10
                    )
                )
            }
        }

        return candidates.min { lhs, rhs in
            labelScore(lhs, labelSize: labelSize, obstacles: paddedObstacles, pathMidpoint: pathMidpoint)
                < labelScore(rhs, labelSize: labelSize, obstacles: paddedObstacles, pathMidpoint: pathMidpoint)
        }?.center ?? pathMidpoint
    }

    private static func straightRoute(from sourceRect: CGRect, to targetRect: CGRect) -> ConnectorRoute {
        let sourceCenter = sourceRect.icCenter
        let targetCenter = targetRect.icCenter
        let start = pointOnRect(sourceRect, from: sourceCenter, toward: targetCenter)
        let end = pointOnRect(targetRect, from: targetCenter, toward: sourceCenter)
        return ConnectorRoute(points: [start, end])
    }

    private static func orthogonalRoute(
        from sourceRect: CGRect,
        to targetRect: CGRect,
        avoiding obstacles: [CGRect],
        options: ConnectorRoutingOptions
    ) -> ConnectorRoute {
        var bestRoute: ConnectorRoute?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for sourceSide in ConnectorSide.allCases {
            for targetSide in ConnectorSide.allCases {
                guard let points = gridRoute(
                    from: sourceRect,
                    sourceSide: sourceSide,
                    to: targetRect,
                    targetSide: targetSide,
                    avoiding: obstacles,
                    options: options
                ) else {
                    continue
                }

                let route = ConnectorRoute(points: compacted(points))
                let score = routeScore(
                    route,
                    sourceRect: sourceRect,
                    sourceSide: sourceSide,
                    targetRect: targetRect,
                    targetSide: targetSide,
                    options: options
                )

                if score < bestScore {
                    bestRoute = route
                    bestScore = score
                }
            }
        }

        if let bestRoute {
            return bestRoute
        }

        return fallbackOrthogonalRoute(from: sourceRect, to: targetRect)
    }

    private static func manualOrthogonalRoute(
        from sourceRect: CGRect,
        to targetRect: CGRect,
        manualRoute: ManualConnectorRoute,
        options: ConnectorRoutingOptions
    ) -> ConnectorRoute {
        let sourceSide = ConnectorSide(manualRoute.sourceSide)
        let targetSide = ConnectorSide(manualRoute.targetSide)
        let start = sourceSide.anchor(in: sourceRect)
        let end = targetSide.anchor(in: targetRect)
        let startPort = start.offset(by: sourceSide.direction, distance: options.endpointLead)
        let endPort = end.offset(by: targetSide.direction, distance: options.endpointLead)
        let waypoints = manualRoute.waypoints.map(\.point)

        var points: [CGPoint] = [start, startPort]
        appendBridge(
            from: startPort,
            to: waypoints[0],
            leavingAlong: sourceSide.axis,
            into: &points
        )

        for waypoint in waypoints.dropFirst() {
            appendBridge(from: points.last ?? startPort, to: waypoint, into: &points)
        }

        appendBridge(
            from: points.last ?? startPort,
            to: endPort,
            arrivingAlong: targetSide.axis,
            into: &points
        )
        points.append(end)

        return ConnectorRoute(points: compacted(points))
    }

    private static func appendBridge(
        from origin: CGPoint,
        to destination: CGPoint,
        leavingAlong axis: ConnectorAxis? = nil,
        arrivingAlong arrivingAxis: ConnectorAxis? = nil,
        into points: inout [CGPoint]
    ) {
        guard origin != destination else { return }

        if let axis {
            let isAlreadyAligned = axis == .horizontal
                ? origin.y == destination.y
                : origin.x == destination.x
            if isAlreadyAligned {
                points.append(destination)
                return
            }

            let corner = axis == .horizontal
                ? CGPoint(x: destination.x, y: origin.y)
                : CGPoint(x: origin.x, y: destination.y)
            points.append(corner)
            points.append(destination)
            return
        }

        if let arrivingAxis {
            let isAlreadyAligned = arrivingAxis == .horizontal
                ? origin.y == destination.y
                : origin.x == destination.x
            if isAlreadyAligned {
                points.append(destination)
                return
            }

            switch arrivingAxis {
            case .horizontal:
                let channelX = (origin.x + destination.x) / 2
                points.append(CGPoint(x: channelX, y: origin.y))
                points.append(CGPoint(x: channelX, y: destination.y))
            case .vertical:
                let channelY = (origin.y + destination.y) / 2
                points.append(CGPoint(x: origin.x, y: channelY))
                points.append(CGPoint(x: destination.x, y: channelY))
            case .none:
                break
            }
            points.append(destination)
            return
        }

        if origin.x == destination.x || origin.y == destination.y {
            points.append(destination)
            return
        }

        let corner: CGPoint
        let horizontalFirst = abs(destination.x - origin.x) >= abs(destination.y - origin.y)
        corner = horizontalFirst
            ? CGPoint(x: destination.x, y: origin.y)
            : CGPoint(x: origin.x, y: destination.y)

        points.append(corner)
        points.append(destination)
    }

    private static func gridRoute(
        from sourceRect: CGRect,
        sourceSide: ConnectorSide,
        to targetRect: CGRect,
        targetSide: ConnectorSide,
        avoiding obstacles: [CGRect],
        options: ConnectorRoutingOptions
    ) -> [CGPoint]? {
        let start = sourceSide.anchor(in: sourceRect)
        let end = targetSide.anchor(in: targetRect)
        let startPort = start.offset(by: sourceSide.direction, distance: options.endpointLead)
        let endPort = end.offset(by: targetSide.direction, distance: options.endpointLead)

        guard segmentIsClear(from: start, to: startPort, avoiding: obstacles),
              segmentIsClear(from: endPort, to: end, avoiding: obstacles) else {
            return nil
        }

        let graphPoints = gridPoints(
            start: startPort,
            end: endPort,
            obstacles: obstacles,
            options: options
        )

        guard let routedPorts = shortestOrthogonalPath(from: startPort, to: endPort, points: graphPoints, avoiding: obstacles, options: options) else {
            return nil
        }

        return [start] + routedPorts + [end]
    }

    private static func gridPoints(
        start: CGPoint,
        end: CGPoint,
        obstacles: [CGRect],
        options: ConnectorRoutingOptions
    ) -> [CGPoint] {
        var xValues: Set<CGFloat> = [start.x, end.x]
        var yValues: Set<CGFloat> = [start.y, end.y]

        for obstacle in obstacles {
            xValues.insert(obstacle.minX - options.channelPadding)
            xValues.insert(obstacle.maxX + options.channelPadding)
            yValues.insert(obstacle.minY - options.channelPadding)
            yValues.insert(obstacle.maxY + options.channelPadding)
        }

        var points: [CGPoint] = []
        for xValue in xValues {
            for yValue in yValues {
                let point = CGPoint(x: xValue, y: yValue)
                if point == start || point == end || !obstacles.contains(where: { $0.contains(point) }) {
                    points.append(point)
                }
            }
        }

        return uniqued(points + [start, end])
    }

    private static func shortestOrthogonalPath(
        from start: CGPoint,
        to end: CGPoint,
        points: [CGPoint],
        avoiding obstacles: [CGRect],
        options: ConnectorRoutingOptions
    ) -> [CGPoint]? {
        guard let startIndex = points.firstIndex(of: start),
              let endIndex = points.firstIndex(of: end) else {
            return nil
        }

        let stateCount = points.count * ConnectorAxis.stateCount
        var distances = Array(repeating: CGFloat.greatestFiniteMagnitude, count: stateCount)
        var visited = Array(repeating: false, count: stateCount)
        var previous = Array<RoutingState?>(repeating: nil, count: stateCount)
        let startState = RoutingState(pointIndex: startIndex, axis: .none)
        distances[startState.index] = 0

        while true {
            guard let currentIndex = distances.indices
                .filter({ !visited[$0] })
                .min(by: { distances[$0] < distances[$1] }),
                  distances[currentIndex].isFinite else {
                break
            }

            visited[currentIndex] = true
            let current = RoutingState(index: currentIndex)

            if current.pointIndex == endIndex {
                return reconstructPath(endingAt: current, previous: previous, points: points)
            }

            for neighborIndex in points.indices where neighborIndex != current.pointIndex {
                guard let segmentAxis = axis(from: points[current.pointIndex], to: points[neighborIndex]),
                      segmentIsClear(from: points[current.pointIndex], to: points[neighborIndex], avoiding: obstacles) else {
                    continue
                }

                let neighbor = RoutingState(pointIndex: neighborIndex, axis: segmentAxis)
                let turnPenalty = current.axis != .none && current.axis != segmentAxis ? options.bendPenalty : 0
                let candidateDistance = distances[currentIndex] + ConnectorSegment(start: points[current.pointIndex], end: points[neighborIndex]).length + turnPenalty

                if candidateDistance < distances[neighbor.index] {
                    distances[neighbor.index] = candidateDistance
                    previous[neighbor.index] = current
                }
            }
        }

        return nil
    }

    private static func reconstructPath(
        endingAt endState: RoutingState,
        previous: [RoutingState?],
        points: [CGPoint]
    ) -> [CGPoint] {
        var path: [CGPoint] = []
        var state: RoutingState? = endState

        while let current = state {
            path.append(points[current.pointIndex])
            state = previous[current.index]
        }

        return path.reversed()
    }

    private static func routeScore(
        _ route: ConnectorRoute,
        sourceRect: CGRect,
        sourceSide: ConnectorSide,
        targetRect: CGRect,
        targetSide: ConnectorSide,
        options: ConnectorRoutingOptions
    ) -> CGFloat {
        route.length
            + CGFloat(route.bendCount) * options.bendPenalty
            + anchorPenalty(side: sourceSide, from: sourceRect.icCenter, toward: targetRect.icCenter, options: options)
            + anchorPenalty(side: targetSide, from: targetRect.icCenter, toward: sourceRect.icCenter, options: options)
    }

    private static func anchorPenalty(
        side: ConnectorSide,
        from origin: CGPoint,
        toward target: CGPoint,
        options: ConnectorRoutingOptions
    ) -> CGFloat {
        let vector = CGVector(dx: target.x - origin.x, dy: target.y - origin.y)
        let distance = max(hypot(vector.dx, vector.dy), 1)
        let alignment = (side.direction.dx * vector.dx + side.direction.dy * vector.dy) / distance

        if alignment < 0 {
            return options.backwardAnchorPenalty + abs(alignment)
        }

        return (1 - alignment) * 40
    }

    private static func fallbackOrthogonalRoute(from sourceRect: CGRect, to targetRect: CGRect) -> ConnectorRoute {
        let sourceCenter = sourceRect.icCenter
        let targetCenter = targetRect.icCenter
        let dx = targetCenter.x - sourceCenter.x
        let dy = targetCenter.y - sourceCenter.y

        if abs(dx) >= abs(dy) {
            let start = CGPoint(x: dx >= 0 ? sourceRect.maxX : sourceRect.minX, y: sourceRect.midY)
            let end = CGPoint(x: dx >= 0 ? targetRect.minX : targetRect.maxX, y: targetRect.midY)
            let midX = (start.x + end.x) / 2
            return ConnectorRoute(points: compacted([start, CGPoint(x: midX, y: start.y), CGPoint(x: midX, y: end.y), end]))
        }

        let start = CGPoint(x: sourceRect.midX, y: dy >= 0 ? sourceRect.maxY : sourceRect.minY)
        let end = CGPoint(x: targetRect.midX, y: dy >= 0 ? targetRect.minY : targetRect.maxY)
        let midY = (start.y + end.y) / 2
        return ConnectorRoute(points: compacted([start, CGPoint(x: start.x, y: midY), CGPoint(x: end.x, y: midY), end]))
    }

    private static func inflatedObstacles(from rects: [CGRect], options: ConnectorRoutingOptions) -> [CGRect] {
        rects
            .map { $0.insetBy(dx: -options.obstaclePadding, dy: -options.obstaclePadding) }
            .filter { !$0.isNull && !$0.isEmpty }
    }

    private static func relevantObstacles(
        from obstacles: [CGRect],
        sourceRect: CGRect,
        targetRect: CGRect,
        options: ConnectorRoutingOptions
    ) -> [CGRect] {
        guard !obstacles.isEmpty else { return [] }

        let routeBounds = sourceRect
            .union(targetRect)
            .insetBy(dx: -options.routingBoundsPadding, dy: -options.routingBoundsPadding)
        let midpoint = CGPoint(
            x: (sourceRect.icCenter.x + targetRect.icCenter.x) / 2,
            y: (sourceRect.icCenter.y + targetRect.icCenter.y) / 2
        )
        let nearbyObstacles = obstacles.filter { $0.intersects(routeBounds) }

        guard nearbyObstacles.count > options.maximumObstacleCount else {
            return nearbyObstacles
        }

        return nearbyObstacles
            .sorted { lhs, rhs in
                distance(from: lhs.icCenter, to: midpoint) < distance(from: rhs.icCenter, to: midpoint)
            }
            .prefix(options.maximumObstacleCount)
            .map { $0 }
    }

    private static func routeIsClear(_ route: ConnectorRoute, avoiding obstacles: [CGRect]) -> Bool {
        route.segments.allSatisfy { segment in
            segmentIsClear(from: segment.start, to: segment.end, avoiding: obstacles)
        }
    }

    private static func labelOffsets(for segment: ConnectorSegment, labelSize: CGSize, gap: CGFloat) -> [CGSize] {
        switch segment.axis {
        case .some(.horizontal):
            let offset = labelSize.height / 2 + gap
            let wideOffset = labelSize.height + gap * 2
            return [
                CGSize(width: 0, height: offset),
                CGSize(width: 0, height: -offset),
                CGSize(width: 0, height: wideOffset),
                CGSize(width: 0, height: -wideOffset),
                .zero
            ]
        case .some(.vertical):
            let offset = labelSize.width / 2 + gap
            let wideOffset = labelSize.width + gap * 2
            return [
                CGSize(width: offset, height: 0),
                CGSize(width: -offset, height: 0),
                CGSize(width: wideOffset, height: 0),
                CGSize(width: -wideOffset, height: 0),
                .zero
            ]
        case .some(.none):
            return [.zero]
        case nil:
            let dx = segment.end.x - segment.start.x
            let dy = segment.end.y - segment.start.y
            let length = max(hypot(dx, dy), 1)
            let offset = max(labelSize.width, labelSize.height) / 2 + gap
            let perpendicular = CGSize(width: -dy / length * offset, height: dx / length * offset)
            let wideOffset = max(labelSize.width, labelSize.height) + gap * 2
            let widePerpendicular = CGSize(width: -dy / length * wideOffset, height: dx / length * wideOffset)
            return [
                perpendicular,
                CGSize(width: -perpendicular.width, height: -perpendicular.height),
                widePerpendicular,
                CGSize(width: -widePerpendicular.width, height: -widePerpendicular.height),
                .zero
            ]
        }
    }

    private static func labelScore(
        _ candidate: LabelCandidate,
        labelSize: CGSize,
        obstacles: [CGRect],
        pathMidpoint: CGPoint
    ) -> CGFloat {
        let rect = CGRect(
            x: candidate.center.x - labelSize.width / 2,
            y: candidate.center.y - labelSize.height / 2,
            width: labelSize.width,
            height: labelSize.height
        )
        let overlapArea = obstacles.reduce(CGFloat(0)) { total, obstacle in
            total + rect.intersection(obstacle).area
        }
        let distanceFromMidpoint = hypot(candidate.center.x - pathMidpoint.x, candidate.center.y - pathMidpoint.y)

        return overlapArea * 10_000 + distanceFromMidpoint + candidate.priority
    }

    private static func segmentIsClear(from start: CGPoint, to end: CGPoint, avoiding obstacles: [CGRect]) -> Bool {
        let segmentBounds = segmentBounds(from: start, to: end)
        return !obstacles.contains { obstacle in
            segmentBounds.intersects(obstacle)
        }
    }

    private static func segmentBounds(from start: CGPoint, to end: CGPoint) -> CGRect {
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        if abs(start.x - end.x) < 0.0001 {
            return rect.insetBy(dx: -0.5, dy: 0)
        }

        if abs(start.y - end.y) < 0.0001 {
            return rect.insetBy(dx: 0, dy: -0.5)
        }

        return rect.insetBy(dx: -0.5, dy: -0.5)
    }

    private static func axis(from start: CGPoint, to end: CGPoint) -> ConnectorAxis? {
        if abs(start.x - end.x) < 0.0001 {
            return .vertical
        }

        if abs(start.y - end.y) < 0.0001 {
            return .horizontal
        }

        return nil
    }

    private static func pointOnRect(_ rect: CGRect, from center: CGPoint, toward target: CGPoint) -> CGPoint {
        let dx = target.x - center.x
        let dy = target.y - center.y

        guard dx != 0 || dy != 0 else { return center }

        let halfWidth = rect.width / 2
        let halfHeight = rect.height / 2
        let scaleX = dx == 0 ? CGFloat.greatestFiniteMagnitude : halfWidth / abs(dx)
        let scaleY = dy == 0 ? CGFloat.greatestFiniteMagnitude : halfHeight / abs(dy)
        let scale = min(scaleX, scaleY)

        return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }

    private static func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private static func compacted(_ points: [CGPoint]) -> [CGPoint] {
        let uniquePoints = points.reduce(into: [CGPoint]()) { result, point in
            if result.last != point {
                result.append(point)
            }
        }

        guard uniquePoints.count >= 3 else { return uniquePoints }

        return uniquePoints.reduce(into: [CGPoint]()) { result, point in
            guard let previous = result.last else {
                result.append(point)
                return
            }

            if result.count >= 2 {
                let beforePrevious = result[result.count - 2]
                let firstSegment = CGVector(dx: previous.x - beforePrevious.x, dy: previous.y - beforePrevious.y)
                let secondSegment = CGVector(dx: point.x - previous.x, dy: point.y - previous.y)
                let continuesInSameDirection = firstSegment.dx * secondSegment.dx + firstSegment.dy * secondSegment.dy > 0
                if axis(from: beforePrevious, to: previous) == axis(from: previous, to: point), continuesInSameDirection {
                    result[result.count - 1] = point
                    return
                }
            }

            result.append(point)
        }
    }

    private static func uniqued(_ points: [CGPoint]) -> [CGPoint] {
        points.reduce(into: [CGPoint]()) { result, point in
            if !result.contains(point) {
                result.append(point)
            }
        }
    }
}

private struct LabelCandidate {
    var center: CGPoint
    var priority: CGFloat
}

private struct RoutingState: Equatable {
    var pointIndex: Int
    var axis: ConnectorAxis

    var index: Int {
        pointIndex * ConnectorAxis.stateCount + axis.stateIndex
    }

    init(pointIndex: Int, axis: ConnectorAxis) {
        self.pointIndex = pointIndex
        self.axis = axis
    }

    init(index: Int) {
        pointIndex = index / ConnectorAxis.stateCount
        axis = ConnectorAxis(stateIndex: index % ConnectorAxis.stateCount)
    }
}

private enum ConnectorSide: CaseIterable {
    case left
    case right
    case top
    case bottom

    init(_ side: ConnectorAnchorSide) {
        switch side {
        case .left: self = .left
        case .right: self = .right
        case .top: self = .top
        case .bottom: self = .bottom
        }
    }

    var axis: ConnectorAxis {
        switch self {
        case .left, .right: .horizontal
        case .top, .bottom: .vertical
        }
    }

    var direction: CGVector {
        switch self {
        case .left:
            CGVector(dx: -1, dy: 0)
        case .right:
            CGVector(dx: 1, dy: 0)
        case .top:
            CGVector(dx: 0, dy: 1)
        case .bottom:
            CGVector(dx: 0, dy: -1)
        }
    }

    func anchor(in rect: CGRect) -> CGPoint {
        switch self {
        case .left:
            CGPoint(x: rect.minX, y: rect.midY)
        case .right:
            CGPoint(x: rect.maxX, y: rect.midY)
        case .top:
            CGPoint(x: rect.midX, y: rect.maxY)
        case .bottom:
            CGPoint(x: rect.midX, y: rect.minY)
        }
    }
}

enum ConnectorAxis {
    case horizontal
    case vertical
    case none

    static let stateCount = 3

    var stateIndex: Int {
        switch self {
        case .horizontal:
            0
        case .vertical:
            1
        case .none:
            2
        }
    }

    init(stateIndex: Int) {
        switch stateIndex {
        case 0:
            self = .horizontal
        case 1:
            self = .vertical
        default:
            self = .none
        }
    }
}

private extension CGPoint {
    func offset(by vector: CGVector, distance: CGFloat) -> CGPoint {
        CGPoint(x: x + vector.dx * distance, y: y + vector.dy * distance)
    }
}

private extension CGRect {
    var icCenter: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
