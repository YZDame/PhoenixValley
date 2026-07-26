import Foundation
import Testing
@testable import PhoenixValleyCore

@Test func localEraseSplitsRoadAndPreservesSemantics() {
    let sourceID = eraseUUID(1)
    let road = RoadSegment(
        id: sourceID,
        kind: .arterial,
        structure: .bridge,
        points: [
            RoadPoint(x: 0, y: 50),
            RoadPoint(x: 100, y: 50),
        ],
        direction: .forward,
        priority: .collector
    )

    let result = RoadNetwork.erasing(
        RoadEraseRequest(
            points: [
                RoadPoint(x: 50, y: 35),
                RoadPoint(x: 50, y: 65),
            ],
            radius: 10,
            eligibleRoadIDs: [sourceID]
        ),
        from: [road]
    )
    let fragments = result.network.edges.sorted {
        $0.points[0].x < $1.points[0].x
    }

    #expect(result.affectedSourceRoadIDs == [sourceID])
    #expect(fragments.count == 2)
    #expect(fragments[0].points.last!.x.isApproximatelyEqual(to: 40))
    #expect(fragments[1].points.first!.x.isApproximatelyEqual(to: 60))
    #expect(fragments.allSatisfy { $0.sourceRoadID == sourceID })
    #expect(fragments.allSatisfy { $0.kind == .arterial })
    #expect(fragments.allSatisfy { $0.structure == .bridge })
    #expect(fragments.allSatisfy { $0.level == .elevated })
    #expect(fragments.allSatisfy { $0.direction == .forward })
    #expect(fragments.allSatisfy { $0.priority == .collector })
}

@Test func localEraseAtEndpointKeepsRemainingRoad() {
    let road = eraseRoad(
        id: eraseUUID(2),
        points: [
            RoadPoint(x: 0, y: 0),
            RoadPoint(x: 100, y: 0),
        ]
    )

    let result = RoadNetwork.erasing(
        RoadEraseRequest(
            points: [RoadPoint(x: 0, y: 0)],
            radius: 12,
            eligibleRoadIDs: [road.id]
        ),
        from: [road]
    )
    let remaining = result.network.edges.first

    #expect(result.network.edges.count == 1)
    #expect(remaining?.points.first?.x.isApproximatelyEqual(to: 12) == true)
    #expect(remaining?.points.last == RoadPoint(x: 100, y: 0))
}

@Test func localEraseHonorsEligibleRoads() {
    let editable = eraseRoad(
        id: eraseUUID(3),
        points: [
            RoadPoint(x: 0, y: 40),
            RoadPoint(x: 100, y: 40),
        ]
    )
    let protected = eraseRoad(
        id: eraseUUID(4),
        points: [
            RoadPoint(x: 0, y: 60),
            RoadPoint(x: 100, y: 60),
        ]
    )

    let result = RoadNetwork.erasing(
        RoadEraseRequest(
            points: [
                RoadPoint(x: 50, y: 20),
                RoadPoint(x: 50, y: 80),
            ],
            radius: 8,
            eligibleRoadIDs: [editable.id]
        ),
        from: [editable, protected]
    )

    #expect(result.affectedSourceRoadIDs == [editable.id])
    #expect(
        result.network.edges.filter {
            $0.sourceRoadID == editable.sourceRoadID
        }.count == 2
    )
    #expect(
        result.network.edges.filter {
            $0.sourceRoadID == protected.sourceRoadID
        }.count == 1
    )
    #expect(
        result.network.edges.first {
            $0.sourceRoadID == protected.sourceRoadID
        }?.points == protected.points
    )
}

@Test func localEraseAtIntersectionRemovesCentralConnection() {
    let horizontal = eraseRoad(
        id: eraseUUID(5),
        points: [
            RoadPoint(x: 0, y: 50),
            RoadPoint(x: 100, y: 50),
        ]
    )
    let vertical = eraseRoad(
        id: eraseUUID(6),
        points: [
            RoadPoint(x: 50, y: 0),
            RoadPoint(x: 50, y: 100),
        ]
    )
    let initial = RoadNetwork.rebuilding(from: [horizontal, vertical]).network

    let result = RoadNetwork.erasing(
        RoadEraseRequest(
            points: [RoadPoint(x: 50, y: 50)],
            radius: 10,
            eligibleRoadIDs: Set(initial.edges.map(\.id))
        ),
        from: initial.roadSegments
    )

    #expect(result.affectedSourceRoadIDs == [horizontal.id, vertical.id])
    #expect(result.network.edges.count == 4)
    #expect(
        !result.network.nodes.contains {
            $0.point.distance(to: RoadPoint(x: 50, y: 50)) < 9.9
        }
    )
    #expect(result.network.relations.isEmpty)
}

@Test func localEraseMissLeavesTopologyUnchanged() {
    let road = eraseRoad(
        id: eraseUUID(7),
        points: [
            RoadPoint(x: 0, y: 0),
            RoadPoint(x: 100, y: 0),
        ]
    )
    let original = RoadNetwork.rebuilding(from: [road]).network

    let result = RoadNetwork.erasing(
        RoadEraseRequest(
            points: [RoadPoint(x: 50, y: 50)],
            radius: 5,
            eligibleRoadIDs: [road.id]
        ),
        from: original.roadSegments
    )

    #expect(result.affectedSourceRoadIDs.isEmpty)
    #expect(result.network == original)
}

@Test func localEraseRemovesShortRoadFullyInsideBrush() {
    let road = eraseRoad(
        id: eraseUUID(8),
        points: [
            RoadPoint(x: 48, y: 50),
            RoadPoint(x: 52, y: 50),
        ]
    )

    let result = RoadNetwork.erasing(
        RoadEraseRequest(
            points: [RoadPoint(x: 50, y: 50)],
            radius: 18,
            eligibleRoadIDs: [road.id]
        ),
        from: [road]
    )

    #expect(result.affectedSourceRoadIDs == [road.id])
    #expect(result.network.edges.isEmpty)
    #expect(result.network.nodes.isEmpty)
}

private func eraseRoad(id: UUID, points: [RoadPoint]) -> RoadSegment {
    RoadSegment(id: id, kind: .street, points: points)
}

private func eraseUUID(_ value: UInt64) -> UUID {
    UUID(
        uuid: (
            0xEE, 0, 0, 0,
            0, 0,
            0x50, 0,
            0x80, 0,
            0, 0, 0, 0,
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value)
        )
    )
}

private extension Double {
    func isApproximatelyEqual(
        to other: Double,
        tolerance: Double = 0.02
    ) -> Bool {
        abs(self - other) <= tolerance
    }
}
