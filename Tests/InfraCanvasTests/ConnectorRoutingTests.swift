import CoreGraphics
import Foundation
import XCTest
@testable import InfraCanvas

final class ConnectorRoutingTests: XCTestCase {
    func testOrthogonalRouteChoosesFacingAnchorsForHorizontalNodes() {
        let source = CGRect(x: 0, y: 0, width: 100, height: 80)
        let target = CGRect(x: 300, y: 0, width: 100, height: 80)

        let route = ConnectorRouter.route(
            style: .orthogonal,
            sourceRect: source,
            targetRect: target,
            obstacleRects: [],
            options: testOptions
        )

        XCTAssertEqual(route.start.x, source.maxX, accuracy: 0.001)
        XCTAssertEqual(route.start.y, source.midY, accuracy: 0.001)
        XCTAssertEqual(route.end.x, target.minX, accuracy: 0.001)
        XCTAssertEqual(route.end.y, target.midY, accuracy: 0.001)
    }

    func testOrthogonalRouteChoosesFacingAnchorsForVerticalNodes() {
        let source = CGRect(x: 0, y: 0, width: 100, height: 80)
        let target = CGRect(x: 0, y: 260, width: 100, height: 80)

        let route = ConnectorRouter.route(
            style: .orthogonal,
            sourceRect: source,
            targetRect: target,
            obstacleRects: [],
            options: testOptions
        )

        XCTAssertEqual(route.start.x, source.midX, accuracy: 0.001)
        XCTAssertEqual(route.start.y, source.maxY, accuracy: 0.001)
        XCTAssertEqual(route.end.x, target.midX, accuracy: 0.001)
        XCTAssertEqual(route.end.y, target.minY, accuracy: 0.001)
    }

    func testOrthogonalRouteAvoidsMiddleNodeWhenChannelExists() {
        let source = CGRect(x: 0, y: 0, width: 100, height: 80)
        let middle = CGRect(x: 150, y: -20, width: 100, height: 120)
        let target = CGRect(x: 300, y: 0, width: 100, height: 80)
        let paddedMiddle = middle.insetBy(dx: -testOptions.obstaclePadding, dy: -testOptions.obstaclePadding)

        let route = ConnectorRouter.route(
            style: .orthogonal,
            sourceRect: source,
            targetRect: target,
            obstacleRects: [middle],
            options: testOptions
        )

        XCTAssertFalse(route.segments.contains { segmentIntersects($0, paddedMiddle) })
        XCTAssertTrue(route.points.contains { $0.y < paddedMiddle.minY || $0.y > paddedMiddle.maxY })
    }

    func testLabelCenterAvoidsObstacleNearRouteMidpoint() {
        let route = ConnectorRoute(points: [
            CGPoint(x: 100, y: 40),
            CGPoint(x: 300, y: 40)
        ])
        let labelSize = CGSize(width: 90, height: 28)
        let obstacle = CGRect(x: 155, y: 25, width: 90, height: 40)

        let labelCenter = ConnectorRouter.labelCenter(
            for: route,
            labelSize: labelSize,
            avoiding: [obstacle],
            gap: 8
        )
        let labelRect = CGRect(
            x: labelCenter.x - labelSize.width / 2,
            y: labelCenter.y - labelSize.height / 2,
            width: labelSize.width,
            height: labelSize.height
        )

        XCTAssertFalse(labelRect.intersects(obstacle.insetBy(dx: -4, dy: -4)))
        XCTAssertNotEqual(labelCenter.y, route.midpoint.y)
    }

    func testDenseUnrelatedObstaclesDoNotMakeDragRoutingExpensive() {
        let obstacles = denseBoardObstacles()
        let startedAt = Date()

        for step in 0..<80 {
            let offset = CGFloat(step) * 2
            let source = CGRect(x: offset, y: 0, width: 100, height: 80)
            let target = CGRect(x: 420 + offset, y: 0, width: 100, height: 80)

            let route = ConnectorRouter.route(
                style: .orthogonal,
                sourceRect: source,
                targetRect: target,
                obstacleRects: obstacles,
                options: testOptions
            )

            XCTAssertEqual(route.start.x, source.maxX, accuracy: 0.001)
            XCTAssertEqual(route.end.x, target.minX, accuracy: 0.001)
        }

        let elapsedSeconds = Date().timeIntervalSince(startedAt)
        XCTAssertLessThan(
            elapsedSeconds,
            1.0,
            "Dense boards should not rebuild a large obstacle graph for every drag redraw."
        )
    }

    private var testOptions: ConnectorRoutingOptions {
        ConnectorRoutingOptions(
            obstaclePadding: 8,
            channelPadding: 16,
            endpointLead: 20,
            bendPenalty: 90,
            backwardAnchorPenalty: 180,
            routingBoundsPadding: 160,
            maximumObstacleCount: 10
        )
    }

    private func denseBoardObstacles() -> [CGRect] {
        var obstacles: [CGRect] = []

        for row in 0..<12 {
            for column in 0..<14 {
                obstacles.append(
                    CGRect(
                        x: CGFloat(column) * 135,
                        y: 280 + CGFloat(row) * 110,
                        width: 96,
                        height: 72
                    )
                )
            }
        }

        return obstacles
    }

    private func segmentIntersects(_ segment: ConnectorSegment, _ rect: CGRect) -> Bool {
        let bounds = CGRect(
            x: min(segment.start.x, segment.end.x),
            y: min(segment.start.y, segment.end.y),
            width: abs(segment.end.x - segment.start.x),
            height: abs(segment.end.y - segment.start.y)
        )

        if segment.axis == .vertical {
            return bounds.insetBy(dx: -0.5, dy: 0).intersects(rect)
        }

        if segment.axis == .horizontal {
            return bounds.insetBy(dx: 0, dy: -0.5).intersects(rect)
        }

        return bounds.insetBy(dx: -0.5, dy: -0.5).intersects(rect)
    }
}
