import Foundation
import Testing
@testable import PhoenixValleyCore

@Test func roadSourceEditingNearestSourceSupportsCanvasAndMeterGeometry() throws {
    let first = editingRoad(
        id: editingUUID(1),
        points: [
            RoadPoint(x: 0, y: 10),
            RoadPoint(x: 100, y: 10),
        ]
    )
    let second = editingRoad(
        id: editingUUID(2),
        points: [
            RoadPoint(x: 0, y: 40),
            RoadPoint(x: 100, y: 40),
        ]
    )
    let mapScale = MapScale(metersPerPoint: 2)

    let canvasHit = try #require(
        RoadSourceGeometry.nearestSource(
            toCanvasPoint: RoadPoint(x: 50, y: 15),
            maximumDistanceMeters: 10,
            mapScale: mapScale,
            in: [second, first]
        )
    )
    let meterHit = try #require(
        RoadSourceGeometry.nearestSource(
            toMeterPoint: RoadPoint(x: 100, y: 30),
            maximumDistanceMeters: 10,
            mapScale: mapScale,
            in: [first, second]
        )
    )

    #expect(canvasHit.sourceRoadID == first.id)
    #expect(canvasHit.nearestCanvasPoint == RoadPoint(x: 50, y: 10))
    #expect(canvasHit.distanceCanvasPoints.isClose(to: 5))
    #expect(canvasHit.distanceMeters.isClose(to: 10))
    #expect(meterHit == canvasHit)
    #expect(
        RoadSourceGeometry.nearestSource(
            toCanvasPoint: RoadPoint(x: 50, y: 15),
            maximumDistanceMeters: 9.9,
            mapScale: mapScale,
            in: [first, second]
        ) == nil
    )
}

@Test func roadSourceEditingMarqueeSelectionIncludesCrossingPolylinesAndReturnsSourceIDs() {
    let selectedSourceID = editingUUID(10)
    let crossing = RoadSegment(
        id: selectedSourceID,
        kind: .street,
        points: [
            RoadPoint(x: 0, y: 50),
            RoadPoint(x: 100, y: 50),
        ],
        sourceRoadID: selectedSourceID
    )
    let sameSourceSibling = RoadSegment(
        id: editingUUID(11),
        kind: .street,
        points: [
            RoadPoint(x: 500, y: 500),
            RoadPoint(x: 600, y: 500),
        ],
        sourceRoadID: selectedSourceID
    )
    let outside = editingRoad(
        id: editingUUID(12),
        points: [
            RoadPoint(x: 200, y: 200),
            RoadPoint(x: 300, y: 200),
        ]
    )
    let roads = [outside, sameSourceSibling, crossing]
    let canvasRectangle = RoadSourceSelectionRectangle(
        canvasCornerA: RoadPoint(x: 60, y: 60),
        canvasCornerB: RoadPoint(x: 40, y: 40)
    )
    let meterRectangle = RoadSourceSelectionRectangle(
        meterCornerA: RoadPoint(x: 120, y: 120),
        meterCornerB: RoadPoint(x: 80, y: 80),
        mapScale: MapScale(metersPerPoint: 2)
    )

    #expect(
        RoadSourceGeometry.sourceRoadIDs(
            intersecting: canvasRectangle,
            in: roads
        ) == [selectedSourceID]
    )
    #expect(
        RoadSourceGeometry.sourceRoadIDs(
            intersecting: meterRectangle,
            in: roads
        ) == [selectedSourceID]
    )
}

@Test func roadSourceEditingMovingMultipleSourcesUsesOneClampedGroupTranslation() {
    let left = RoadSegment(
        id: editingUUID(20),
        kind: .street,
        points: [
            RoadPoint(x: 10, y: 100),
            RoadPoint(x: 20, y: 100),
        ],
        direction: .reverse,
        priority: .collector
    )
    let right = RoadSegment(
        id: editingUUID(21),
        kind: .arterial,
        structure: .bridge,
        points: [
            RoadPoint(x: 1_580, y: 200),
            RoadPoint(x: 1_590, y: 200),
        ],
        direction: .forward,
        priority: .motorway
    )

    let result = RoadNetwork.movingSources(
        RoadSourceTranslation(
            sourceRoadIDs: [left.id, right.id],
            meterOffset: RoadPoint(x: 200, y: -400),
            mapScale: MapScale(metersPerPoint: 2)
        ),
        in: [left, right]
    )
    let movedLeft = result.network.edges.first {
        $0.sourceRoadID == left.id
    }
    let movedRight = result.network.edges.first {
        $0.sourceRoadID == right.id
    }

    #expect(result.affectedSourceRoadIDs == [left.id, right.id])
    #expect(movedLeft?.points == [
        RoadPoint(x: 20, y: 0),
        RoadPoint(x: 30, y: 0),
    ])
    #expect(movedRight?.points == [
        RoadPoint(x: 1_590, y: 100),
        RoadPoint(x: 1_600, y: 100),
    ])
    #expect(movedLeft?.direction == .reverse)
    #expect(movedLeft?.priority == .collector)
    #expect(movedLeft?.structure == .ground)
    #expect(movedRight?.direction == .forward)
    #expect(movedRight?.priority == .motorway)
    #expect(movedRight?.structure == .bridge)
}

@Test func roadSourceEditingMovingSplitSourceChangesEverySiblingAndKeepsUnrelatedEdgeIDs() {
    let fixture = splitSourceFixture()
    let originalUnrelatedEdgeIDs = Set(
        fixture.network.edges
            .filter { $0.sourceRoadID == fixture.unrelatedSourceID }
            .map(\.id)
    )

    let result = RoadNetwork.movingSources(
        RoadSourceTranslation(
            sourceRoadIDs: [fixture.editedSourceID],
            canvasOffset: RoadPoint(x: 25, y: -150)
        ),
        in: fixture.network.roadSegments
    )
    let editedEdges = result.network.edges.filter {
        $0.sourceRoadID == fixture.editedSourceID
    }
    let unrelatedEdges = result.network.edges.filter {
        $0.sourceRoadID == fixture.unrelatedSourceID
    }

    #expect(result.affectedSourceRoadIDs == [fixture.editedSourceID])
    #expect(editedEdges.count == 2)
    #expect(editedEdges.flatMap(\.points).allSatisfy { $0.y == 50 })
    #expect(editedEdges.flatMap(\.points).map(\.x).min() == 125)
    #expect(editedEdges.flatMap(\.points).map(\.x).max() == 525)
    #expect(editedEdges.allSatisfy { $0.direction == .forward })
    #expect(editedEdges.allSatisfy { $0.priority == .collector })
    #expect(editedEdges.allSatisfy { $0.structure == .bridge })
    #expect(editedEdges.allSatisfy { $0.level == .elevated })
    #expect(unrelatedEdges.flatMap(\.points).allSatisfy { $0.x == 300 })
    #expect(Set(unrelatedEdges.map(\.id)) == originalUnrelatedEdgeIDs)
}

@Test func roadSourceEditingMovingNearestSplitVertexReshapesEveryMatchingSiblingEndpoint() throws {
    let fixture = splitSourceFixture()
    let hit = try #require(
        RoadSourceGeometry.nearestControlPoint(
            toCanvasPoint: RoadPoint(x: 302, y: 198),
            on: fixture.editedSourceID,
            maximumDistanceMeters: 5,
            mapScale: .standard,
            in: fixture.network.roadSegments
        )
    )
    #expect(hit.canvasPoint == RoadPoint(x: 300, y: 200))

    let destination = RoadPoint(x: 350, y: 400)
    let result = RoadNetwork.movingControlPoint(
        RoadSourceControlPointMove(
            sourceRoadID: fixture.editedSourceID,
            probeCanvasPoint: RoadPoint(x: 302, y: 198),
            destinationCanvasPoint: destination,
            maximumDistanceMeters: 5,
            mapScale: .standard
        ),
        in: fixture.network.roadSegments
    )
    let editedEdges = result.network.edges.filter {
        $0.sourceRoadID == fixture.editedSourceID
    }
    let editedPoints = editedEdges.flatMap(\.points)

    #expect(result.affectedSourceRoadIDs == [fixture.editedSourceID])
    #expect(editedEdges.count == 2)
    #expect(editedPoints.filter { $0 == destination }.count == 2)
    #expect(!editedPoints.contains(RoadPoint(x: 300, y: 200)))
    #expect(editedEdges.allSatisfy { $0.direction == .forward })
    #expect(editedEdges.allSatisfy { $0.priority == .collector })
    #expect(editedEdges.allSatisfy { $0.structure == .bridge })
}

@Test func roadSourceEditingMovingInteriorControlPointClampsDestinationToCanvas() {
    let road = RoadSegment(
        id: editingUUID(30),
        kind: .street,
        points: [
            RoadPoint(x: 100, y: 100),
            RoadPoint(x: 200, y: 150),
            RoadPoint(x: 300, y: 100),
        ]
    )

    let result = RoadNetwork.movingControlPoint(
        RoadSourceControlPointMove(
            sourceRoadID: road.id,
            probeCanvasPoint: RoadPoint(x: 199, y: 151),
            destinationCanvasPoint: RoadPoint(x: -50, y: 1_250),
            maximumDistanceMeters: 5,
            mapScale: .standard
        ),
        in: [road]
    )
    let points = result.network.edges.first?.points

    #expect(result.affectedSourceRoadIDs == [road.id])
    #expect(points == [
        RoadPoint(x: 100, y: 100),
        RoadPoint(x: 0, y: 1_200),
        RoadPoint(x: 300, y: 100),
    ])
}

@Test func roadSourceEditingChangingKindUpdatesAllSplitSiblingsWithoutResettingSemantics() {
    let fixture = splitSourceFixture()
    let originalUnrelatedEdgeIDs = Set(
        fixture.network.edges
            .filter { $0.sourceRoadID == fixture.unrelatedSourceID }
            .map(\.id)
    )

    let result = RoadNetwork.changingSourceKinds(
        RoadSourceKindChange(
            sourceRoadIDs: [fixture.editedSourceID],
            kind: .railway
        ),
        in: fixture.network.roadSegments
    )
    let editedEdges = result.network.edges.filter {
        $0.sourceRoadID == fixture.editedSourceID
    }
    let unrelatedEdges = result.network.edges.filter {
        $0.sourceRoadID == fixture.unrelatedSourceID
    }

    #expect(result.affectedSourceRoadIDs == [fixture.editedSourceID])
    #expect(editedEdges.count == 2)
    #expect(editedEdges.allSatisfy { $0.kind == .railway })
    #expect(editedEdges.allSatisfy { $0.direction == .forward })
    #expect(editedEdges.allSatisfy { $0.priority == .collector })
    #expect(editedEdges.allSatisfy { $0.structure == .bridge })
    #expect(unrelatedEdges.allSatisfy { $0.kind == .street })
    #expect(Set(unrelatedEdges.map(\.id)) == originalUnrelatedEdgeIDs)
}

@Test func roadSourceEditingTransactionUnionsOnlyActuallyChangedSources() {
    let first = editingRoad(
        id: editingUUID(40),
        points: [
            RoadPoint(x: 100, y: 100),
            RoadPoint(x: 200, y: 100),
        ]
    )
    let second = editingRoad(
        id: editingUUID(41),
        points: [
            RoadPoint(x: 300, y: 300),
            RoadPoint(x: 400, y: 300),
        ]
    )
    let missing = editingUUID(42)

    let result = RoadNetwork.editingSources(
        RoadSourceEditTransaction(
            operations: [
                .translate(
                    RoadSourceTranslation(
                        sourceRoadIDs: [first.id, second.id],
                        canvasOffset: RoadPoint(x: 10, y: 20)
                    )
                ),
                .changeKind(
                    RoadSourceKindChange(
                        sourceRoadIDs: [first.id, missing],
                        kind: .arterial
                    )
                ),
            ]
        ),
        in: [first, second]
    )

    #expect(result.affectedSourceRoadIDs == [first.id, second.id])
    #expect(
        result.network.edges.first { $0.sourceRoadID == first.id }?.kind
            == .arterial
    )
    #expect(
        result.network.edges.first { $0.sourceRoadID == second.id }?.kind
            == .street
    )
}

@Test func roadSourceEditingHitTestsRejectNonFiniteGeometry() {
    let road = editingRoad(
        id: editingUUID(50),
        points: [
            RoadPoint(x: 100, y: 100),
            RoadPoint(x: 300, y: 100),
        ]
    )
    let invalidRoad = editingRoad(
        id: editingUUID(51),
        points: [
            RoadPoint(x: .nan, y: 100),
            RoadPoint(x: 200, y: 100),
        ]
    )

    #expect(
        RoadSourceGeometry.nearestSource(
            toCanvasPoint: RoadPoint(x: .nan, y: 100),
            maximumDistanceMeters: 20,
            mapScale: .standard,
            in: [road]
        ) == nil
    )
    #expect(
        RoadSourceGeometry.nearestControlPoint(
            toCanvasPoint: RoadPoint(x: 100, y: .infinity),
            on: road.id,
            maximumDistanceMeters: 20,
            mapScale: .standard,
            in: [road]
        ) == nil
    )
    #expect(
        RoadSourceGeometry.nearestSource(
            toCanvasPoint: RoadPoint(x: 150, y: 100),
            maximumDistanceMeters: 20,
            mapScale: .standard,
            in: [invalidRoad]
        ) == nil
    )
}

@Test func roadSourceEditingMarqueeRejectsNonFiniteRectangleAndSegments() {
    let validRoad = editingRoad(
        id: editingUUID(52),
        points: [
            RoadPoint(x: 0, y: 50),
            RoadPoint(x: 100, y: 50),
        ]
    )
    let invalidRoad = editingRoad(
        id: editingUUID(53),
        points: [
            RoadPoint(x: .nan, y: 50),
            RoadPoint(x: 100, y: 50),
        ]
    )
    let invalidRectangle = RoadSourceSelectionRectangle(
        canvasCornerA: RoadPoint(x: .nan, y: 40),
        canvasCornerB: RoadPoint(x: 60, y: 60)
    )
    let validRectangle = RoadSourceSelectionRectangle(
        canvasCornerA: RoadPoint(x: 40, y: 40),
        canvasCornerB: RoadPoint(x: 60, y: 60)
    )

    #expect(
        RoadSourceGeometry.sourceRoadIDs(
            intersecting: invalidRectangle,
            in: [validRoad]
        ).isEmpty
    )
    #expect(
        RoadSourceGeometry.sourceRoadIDs(
            intersecting: validRectangle,
            in: [invalidRoad]
        ).isEmpty
    )
}

@Test func roadSourceEditingNonFiniteMovesAreNoOps() {
    let road = editingRoad(
        id: editingUUID(54),
        points: [
            RoadPoint(x: 100, y: 100),
            RoadPoint(x: 300, y: 100),
        ]
    )
    let translationResult = RoadNetwork.movingSources(
        RoadSourceTranslation(
            sourceRoadIDs: [road.id],
            canvasOffset: RoadPoint(x: .infinity, y: 20)
        ),
        in: [road]
    )
    let controlPointResult = RoadNetwork.movingControlPoint(
        RoadSourceControlPointMove(
            sourceRoadID: road.id,
            probeCanvasPoint: RoadPoint(x: 100, y: 100),
            destinationCanvasPoint: RoadPoint(x: .nan, y: 200),
            maximumDistanceMeters: 20,
            mapScale: .standard
        ),
        in: [road]
    )

    #expect(translationResult.affectedSourceRoadIDs.isEmpty)
    #expect(translationResult.network.edges.first?.points == road.points)
    #expect(controlPointResult.affectedSourceRoadIDs.isEmpty)
    #expect(controlPointResult.network.edges.first?.points == road.points)
}

@Test func roadSourceEditingFinalSemanticNoOpDoesNotCreateAffectedSources() {
    let road = editingRoad(
        id: editingUUID(55),
        points: [
            RoadPoint(x: 100, y: 100),
            RoadPoint(x: 300, y: 100),
        ]
    )

    let result = RoadNetwork.editingSources(
        RoadSourceEditTransaction(
            operations: [
                .translate(
                    RoadSourceTranslation(
                        sourceRoadIDs: [road.id],
                        canvasOffset: RoadPoint(x: 25, y: 40)
                    )
                ),
                .translate(
                    RoadSourceTranslation(
                        sourceRoadIDs: [road.id],
                        canvasOffset: RoadPoint(x: -25, y: -40)
                    )
                ),
                .changeKind(
                    RoadSourceKindChange(
                        sourceRoadIDs: [road.id],
                        kind: .arterial
                    )
                ),
                .changeKind(
                    RoadSourceKindChange(
                        sourceRoadIDs: [road.id],
                        kind: .street
                    )
                ),
            ]
        ),
        in: [road]
    )

    #expect(result.affectedSourceRoadIDs.isEmpty)
    #expect(result.network.edges.first?.points == road.points)
    #expect(result.network.edges.first?.kind == road.kind)
}

@Test func roadSourceEditingRejectsControlPointMoveThatWouldDeleteWholeSource() {
    let road = editingRoad(
        id: editingUUID(56),
        points: [
            RoadPoint(x: 100, y: 100),
            RoadPoint(x: 300, y: 100),
        ]
    )

    let result = RoadNetwork.movingControlPoint(
        RoadSourceControlPointMove(
            sourceRoadID: road.id,
            probeCanvasPoint: road.points[0],
            destinationCanvasPoint: road.points[1],
            maximumDistanceMeters: 5,
            mapScale: .standard
        ),
        in: [road]
    )

    #expect(result.affectedSourceRoadIDs.isEmpty)
    #expect(result.network.edges.count == 1)
    #expect(result.network.edges.first?.sourceRoadID == road.id)
    #expect(result.network.edges.first?.points == road.points)
}

private func splitSourceFixture() -> (
    network: RoadNetwork,
    editedSourceID: UUID,
    unrelatedSourceID: UUID
) {
    let editedSourceID = editingUUID(100)
    let unrelatedSourceID = editingUUID(101)
    let edited = RoadSegment(
        id: editedSourceID,
        kind: .arterial,
        structure: .bridge,
        points: [
            RoadPoint(x: 100, y: 200),
            RoadPoint(x: 500, y: 200),
        ],
        direction: .forward,
        priority: .collector,
        sourceRoadID: editedSourceID
    )
    let unrelated = RoadSegment(
        id: unrelatedSourceID,
        kind: .street,
        structure: .bridge,
        points: [
            RoadPoint(x: 300, y: 100),
            RoadPoint(x: 300, y: 300),
        ],
        direction: .reverse,
        priority: .local,
        sourceRoadID: unrelatedSourceID
    )
    return (
        network: RoadNetwork.rebuilding(from: [edited, unrelated]).network,
        editedSourceID: editedSourceID,
        unrelatedSourceID: unrelatedSourceID
    )
}

private func editingRoad(
    id: UUID,
    points: [RoadPoint]
) -> RoadSegment {
    RoadSegment(id: id, kind: .street, points: points)
}

private func editingUUID(_ value: UInt64) -> UUID {
    UUID(
        uuid: (
            0xED, 0, 0, 0,
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
    func isClose(to other: Double, tolerance: Double = 1e-9) -> Bool {
        abs(self - other) <= tolerance
    }
}
