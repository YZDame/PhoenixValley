import Foundation
import Testing
@testable import PhoenixValleyCore

@Test func endpointConnectionCreatesSharedNode() {
    let first = RoadSegment(
        id: topologyUUID(1),
        kind: .street,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 50, y: 0)]
    )
    let second = RoadSegment(
        id: topologyUUID(2),
        kind: .arterial,
        points: [RoadPoint(x: 50, y: 0), RoadPoint(x: 80, y: 30)]
    )

    let result = RoadNetwork.rebuilding(from: [first, second])
    let junction = result.network.nodes.first { $0.point == RoadPoint(x: 50, y: 0) }

    #expect(result.roads.count == 2)
    #expect(junction != nil)
    #expect(result.network.edges(at: junction!.id).count == 2)
    #expect(result.network.relations.count == 1)
    #expect(result.network.relations[0].kind == .atGradeJunction)
    #expect(result.network.relations[0].junctionNodeIDs == [junction!.id])
}

@Test func snappedTJunctionSplitsExistingRoad() {
    let existing = RoadSegment(
        id: topologyUUID(10),
        kind: .arterial,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 100, y: 0)]
    )
    let branch = RoadSegment(
        id: topologyUUID(11),
        kind: .street,
        points: [RoadPoint(x: 50, y: 0.6), RoadPoint(x: 50, y: 60)]
    )

    let result = RoadNetwork.integrating(
        existingRoads: [existing],
        newRoad: branch,
        configuration: .init(snapTolerance: 1)
    )
    let junction = result.network.nodes.first { $0.point == RoadPoint(x: 50, y: 0) }

    #expect(result.roads.count == 3)
    #expect(result.roads.contains { $0.id == existing.id })
    #expect(result.roads.contains { $0.id == branch.id })
    #expect(result.roads.filter { $0.sourceRoadID == existing.id }.count == 2)
    #expect(junction != nil)
    #expect(result.network.edges(at: junction!.id).count == 3)
    #expect(
        result.roads.first { $0.id == branch.id }?.points.first
            == RoadPoint(x: 50, y: 0)
    )
}

@Test func sameLevelCrossingCreatesFourEdges() {
    let horizontal = RoadSegment(
        id: topologyUUID(20),
        kind: .arterial,
        points: [RoadPoint(x: 0, y: 50), RoadPoint(x: 100, y: 50)]
    )
    let vertical = RoadSegment(
        id: topologyUUID(21),
        kind: .street,
        points: [RoadPoint(x: 50, y: 0), RoadPoint(x: 50, y: 100)]
    )

    let result = RoadNetwork.rebuilding(from: [horizontal, vertical])
    let junction = result.network.nodes.first { $0.point == RoadPoint(x: 50, y: 50) }

    #expect(result.network.edges.count == 4)
    #expect(junction != nil)
    #expect(result.network.edges(at: junction!.id).count == 4)
    #expect(result.network.relations.count == 1)
    #expect(result.network.relations[0].kind == .atGradeJunction)
}

@Test func sameLevelOverlapSplitsAtBothBoundaries() {
    let longRoad = RoadSegment(
        id: topologyUUID(30),
        kind: .street,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 100, y: 0)]
    )
    let overlappingRoad = RoadSegment(
        id: topologyUUID(31),
        kind: .street,
        points: [RoadPoint(x: 40, y: 0), RoadPoint(x: 80, y: 0)]
    )

    let result = RoadNetwork.rebuilding(from: [longRoad, overlappingRoad])
    let relation = result.network.relations.first
    let overlapNodePoints = Set(
        relation?.junctionNodeIDs.compactMap { result.network.node(id: $0)?.point } ?? []
    )

    #expect(result.network.edges.filter { $0.sourceRoadID == longRoad.id }.count == 3)
    #expect(result.network.edges.filter { $0.sourceRoadID == overlappingRoad.id }.count == 1)
    #expect(relation?.kind == .sameLevelOverlap)
    #expect(overlapNodePoints == [RoadPoint(x: 40, y: 0), RoadPoint(x: 80, y: 0)])
}

@Test func differentLevelsCreateCrossingRelationWithoutConnection() {
    let ground = RoadSegment(
        id: topologyUUID(40),
        kind: .arterial,
        level: .ground,
        points: [RoadPoint(x: 0, y: 50), RoadPoint(x: 100, y: 50)]
    )
    let elevated = RoadSegment(
        id: topologyUUID(41),
        kind: .motorway,
        level: .elevated,
        points: [RoadPoint(x: 50, y: 0), RoadPoint(x: 50, y: 100)]
    )

    let result = RoadNetwork.rebuilding(from: [ground, elevated])
    let relation = result.network.relations.first

    #expect(result.network.edges.count == 2)
    #expect(result.network.nodes.count == 4)
    #expect(!result.network.nodes.contains { $0.point == RoadPoint(x: 50, y: 50) })
    #expect(relation?.kind == .gradeSeparatedCrossing)
    #expect(relation?.junctionNodeIDs.isEmpty == true)
    #expect(relation?.upperRoadID == elevated.id)
    #expect(relation?.lowerRoadID == ground.id)
}

@Test func splitEdgesRetainDirectionAndPriority() {
    let oneWay = RoadSegment(
        id: topologyUUID(50),
        kind: .street,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 100, y: 0)],
        direction: .forward,
        priority: .collector
    )
    let crossing = RoadSegment(
        id: topologyUUID(51),
        kind: .arterial,
        points: [RoadPoint(x: 50, y: -50), RoadPoint(x: 50, y: 50)]
    )

    let result = RoadNetwork.rebuilding(from: [oneWay, crossing])
    let oneWayEdges = result.network.edges.filter { $0.sourceRoadID == oneWay.id }
        .sorted { $0.points[0].x < $1.points[0].x }
    let startNodeID = oneWayEdges[0].startNodeID
    let endNodeID = oneWayEdges[1].endNodeID

    #expect(oneWayEdges.count == 2)
    #expect(oneWayEdges.allSatisfy { $0.direction == .forward })
    #expect(oneWayEdges.allSatisfy { $0.priority == .collector })
    #expect(result.network.outgoingEdges(from: startNodeID).contains { $0.id == oneWay.id })
    #expect(
        !result.network.outgoingEdges(from: endNodeID)
            .contains { $0.sourceRoadID == oneWay.id }
    )
}

@Test func topologyIdentifiersSurviveRebuildAndCodableRoundTrip() throws {
    let horizontal = RoadSegment(
        id: topologyUUID(60),
        kind: .arterial,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 100, y: 0)]
    )
    let vertical = RoadSegment(
        id: topologyUUID(61),
        kind: .street,
        points: [RoadPoint(x: 50, y: -50), RoadPoint(x: 50, y: 50)]
    )

    let first = RoadNetwork.rebuilding(from: [horizontal, vertical])
    let rebuilt = RoadNetwork.rebuilding(from: first.roads)
    let decoded = try JSONDecoder().decode(
        RoadNetwork.self,
        from: JSONEncoder().encode(first.network)
    )

    #expect(Set(first.network.nodes.map(\.id)) == Set(rebuilt.network.nodes.map(\.id)))
    #expect(Set(first.network.edges.map(\.id)) == Set(rebuilt.network.edges.map(\.id)))
    #expect(Set(first.network.relations.map(\.id)) == Set(rebuilt.network.relations.map(\.id)))
    #expect(decoded == first.network)
}

@Test func unaffectedEdgeIdentifierSurvivesLaterIntegration() {
    let crossed = RoadSegment(
        id: topologyUUID(70),
        kind: .arterial,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 100, y: 0)]
    )
    let unaffected = RoadSegment(
        id: topologyUUID(71),
        kind: .street,
        points: [RoadPoint(x: 0, y: 100), RoadPoint(x: 100, y: 100)]
    )
    let newRoad = RoadSegment(
        id: topologyUUID(72),
        kind: .street,
        points: [RoadPoint(x: 50, y: -50), RoadPoint(x: 50, y: 50)]
    )

    let result = RoadNetwork.integrating(
        existingRoads: [crossed, unaffected],
        newRoad: newRoad
    )

    #expect(result.network.edge(id: unaffected.id) != nil)
    #expect(result.network.edge(id: crossed.id) != nil)
    #expect(result.network.edges.filter { $0.sourceRoadID == crossed.id }.count == 2)
}

@Test func legacyRoadSegmentReceivesTopologyDefaults() throws {
    let id = topologyUUID(80)
    let json = """
    {
      "id": "\(id.uuidString)",
      "kind": "arterial",
      "level": 0,
      "points": [{"x": 0, "y": 0}, {"x": 100, "y": 0}]
    }
    """

    let segment = try JSONDecoder().decode(RoadSegment.self, from: Data(json.utf8))

    #expect(segment.direction == .bidirectional)
    #expect(segment.priority == .arterial)
    #expect(segment.sourceRoadID == id)
    #expect(segment.startNodeID == nil)
    #expect(segment.endNodeID == nil)
}

@Test func legacyProjectBuildsAndPersistsNetwork() throws {
    let project = RoadProject(
        id: topologyUUID(90),
        name: "旧项目",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        terrain: TerrainLayout(seed: 7, shoreline: []),
        roads: [
            RoadSegment(
                id: topologyUUID(91),
                kind: .street,
                points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 100, y: 0)]
            ),
        ]
    )
    let encoded = try JSONEncoder().encode(project)
    var legacyObject = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    legacyObject.removeValue(forKey: "roadNetwork")
    legacyObject["formatVersion"] = 3

    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    let migrated = try JSONDecoder().decode(RoadProject.self, from: legacyData)
    let persistedObject = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(migrated))
            as? [String: Any]
    )

    #expect(migrated.roadNetwork.edges.count == 1)
    #expect(migrated.roads[0].startNodeID != nil)
    #expect(migrated.roads[0].endNodeID != nil)
    #expect(persistedObject["roadNetwork"] != nil)
}

@Test func rebuildingOverlapDoesNotAddBoundaryJunctionRelations() {
    let longRoad = RoadSegment(
        kind: .arterial,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 100, y: 0)]
    )
    let overlap = RoadSegment(
        kind: .street,
        points: [RoadPoint(x: 25, y: 0), RoadPoint(x: 75, y: 0)]
    )

    let first = RoadNetwork.rebuilding(from: [longRoad, overlap]).network
    let rebuilt = RoadNetwork.rebuilding(from: first.roadSegments).network

    #expect(rebuilt.relations.filter { $0.kind == .sameLevelOverlap }.count == 1)
    #expect(rebuilt.relations.allSatisfy { $0.kind != .atGradeJunction })
}

@Test func edgeIDUsesGeometricBoundariesInsteadOfFragmentIndex() throws {
    let base = RoadSegment(
        kind: .arterial,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 100, y: 0)]
    )
    let crossing25 = RoadSegment(
        kind: .street,
        points: [RoadPoint(x: 25, y: -10), RoadPoint(x: 25, y: 10)]
    )
    let crossing75 = RoadSegment(
        kind: .street,
        points: [RoadPoint(x: 75, y: -10), RoadPoint(x: 75, y: 10)]
    )
    let first = RoadNetwork.rebuilding(
        from: [base, crossing25, crossing75]
    ).network
    let originalTail = try #require(first.edges.first {
        $0.sourceRoadID == base.id
            && $0.points.first == RoadPoint(x: 75, y: 0)
            && $0.points.last == RoadPoint(x: 100, y: 0)
    })

    let crossing50 = RoadSegment(
        kind: .street,
        points: [RoadPoint(x: 50, y: -10), RoadPoint(x: 50, y: 10)]
    )
    let second = RoadNetwork.rebuilding(
        from: [base, crossing25, crossing50, crossing75]
    ).network
    let rebuiltTail = try #require(second.edges.first {
        $0.sourceRoadID == base.id
            && $0.points.first == RoadPoint(x: 75, y: 0)
            && $0.points.last == RoadPoint(x: 100, y: 0)
    })

    #expect(rebuiltTail.id == originalTail.id)
}

@Test func continuousOverlapAcrossPolylineVertexCreatesOneRelation() throws {
    let bentOnlyByVertex = RoadSegment(
        id: topologyUUID(100),
        kind: .arterial,
        points: [
            RoadPoint(x: 0, y: 0),
            RoadPoint(x: 50, y: 0),
            RoadPoint(x: 100, y: 0),
        ]
    )
    let overlap = RoadSegment(
        id: topologyUUID(101),
        kind: .street,
        points: [RoadPoint(x: 25, y: 0), RoadPoint(x: 75, y: 0)]
    )

    let network = RoadNetwork.rebuilding(from: [bentOnlyByVertex, overlap]).network
    let relations = network.relations.filter { $0.kind == .sameLevelOverlap }
    let relation = try #require(relations.first)

    #expect(relations.count == 1)
    #expect(relation.point == RoadPoint(x: 25, y: 0))
    #expect(relation.secondaryPoint == RoadPoint(x: 75, y: 0))
}

@Test func selfIntersectingPolylineCreatesJunction() throws {
    let selfIntersecting = RoadSegment(
        id: topologyUUID(110),
        kind: .arterial,
        points: [
            RoadPoint(x: 0, y: 0),
            RoadPoint(x: 100, y: 100),
            RoadPoint(x: 0, y: 100),
            RoadPoint(x: 100, y: 0),
        ]
    )

    let network = RoadNetwork.rebuilding(from: [selfIntersecting]).network
    let junction = try #require(network.nodes.first {
        $0.point == RoadPoint(x: 50, y: 50)
    })

    #expect(network.edges(at: junction.id).count >= 3)
    #expect(network.relations.contains {
        $0.kind == .atGradeJunction
            && $0.point == RoadPoint(x: 50, y: 50)
    })
}

@Test func sameSourceDifferentStructuresCrossWithoutConnecting() throws {
    let sourceRoadID = topologyUUID(120)
    let ground = RoadSegment(
        id: sourceRoadID,
        kind: .arterial,
        structure: .ground,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 100, y: 100)],
        sourceRoadID: sourceRoadID
    )
    let bridge = RoadSegment(
        id: topologyUUID(121),
        kind: .arterial,
        structure: .bridge,
        points: [RoadPoint(x: 0, y: 100), RoadPoint(x: 100, y: 0)],
        sourceRoadID: sourceRoadID
    )

    let network = RoadNetwork.rebuilding(from: [ground, bridge]).network

    #expect(!network.nodes.contains { $0.point == RoadPoint(x: 50, y: 50) })
    #expect(network.relations.contains {
        $0.kind == .gradeSeparatedCrossing
            && $0.point == RoadPoint(x: 50, y: 50)
    })
}

@Test func forwardStructureTransitionPreservesTravelDirection() throws {
    let sourceRoadID = topologyUUID(130)
    let ground = RoadSegment(
        id: sourceRoadID,
        kind: .arterial,
        structure: .ground,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 50, y: 0)],
        direction: .forward,
        sourceRoadID: sourceRoadID
    )
    let bridge = RoadSegment(
        id: topologyUUID(131),
        kind: .arterial,
        structure: .bridge,
        points: [RoadPoint(x: 50, y: 0), RoadPoint(x: 100, y: 0)],
        direction: .forward,
        sourceRoadID: sourceRoadID
    )

    let network = RoadNetwork.rebuilding(from: [ground, bridge]).network
    let transition = try #require(
        network.relations.first { $0.kind == .structureTransition }
    )
    let groundNodeID = try #require(transition.junctionNodeIDs.first {
        network.node(id: $0)?.level == .ground
    })
    let bridgeNodeID = try #require(transition.junctionNodeIDs.first {
        network.node(id: $0)?.level == .elevated
    })

    #expect(network.adjacentNodeIDs(to: groundNodeID).contains(bridgeNodeID))
    #expect(!network.adjacentNodeIDs(to: bridgeNodeID).contains(groundNodeID))
}

private func topologyUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
}
