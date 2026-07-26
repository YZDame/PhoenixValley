import Foundation
import Testing
@testable import PhoenixValleyCore

@Test func legacyRoadAndEdgeInferStructureFromLevel() throws {
    let segment = RoadSegment(
        kind: .arterial,
        level: .elevated,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 10, y: 0)]
    )
    var segmentObject = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(segment)) as? [String: Any]
    )
    segmentObject.removeValue(forKey: "structure")
    let decodedSegment = try JSONDecoder().decode(
        RoadSegment.self,
        from: JSONSerialization.data(withJSONObject: segmentObject)
    )
    #expect(decodedSegment.structure == .elevated)

    let network = RoadNetwork.rebuilding(from: [segment]).network
    let edge = try #require(network.edges.first)
    var edgeObject = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(edge)) as? [String: Any]
    )
    edgeObject.removeValue(forKey: "structure")
    let decodedEdge = try JSONDecoder().decode(
        RoadEdge.self,
        from: JSONSerialization.data(withJSONObject: edgeObject)
    )
    #expect(decodedEdge.structure == .elevated)
}

@Test func structureIsTheAuthorityForRenderedTopologyLevel() {
    var bridge = RoadSegment(
        kind: .arterial,
        level: .ground,
        structure: .bridge,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 10, y: 0)]
    )
    #expect(bridge.level == .elevated)
    bridge.setStructure(.tunnel)
    #expect(bridge.structure == .tunnel)
    #expect(bridge.level == .tunnel)

    let edge = RoadEdge(
        id: UUID(),
        sourceRoadID: UUID(),
        startNodeID: UUID(),
        endNodeID: UUID(),
        kind: .arterial,
        level: .ground,
        structure: .bridge,
        direction: .bidirectional,
        priority: .arterial,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 10, y: 0)]
    )
    #expect(edge.level == .elevated)
}

@Test func structureTransitionConnectsDifferentLevelsOfOneRoad() throws {
    let sourceRoadID = UUID()
    let ground = RoadSegment(
        id: sourceRoadID,
        kind: .arterial,
        level: .ground,
        structure: .ground,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 50, y: 0)],
        sourceRoadID: sourceRoadID
    )
    let bridge = RoadSegment(
        kind: .arterial,
        level: .elevated,
        structure: .bridge,
        points: [RoadPoint(x: 50, y: 0), RoadPoint(x: 100, y: 0)],
        sourceRoadID: sourceRoadID
    )

    let network = RoadNetwork.rebuilding(from: [ground, bridge]).network
    let relation = try #require(
        network.relations.first { $0.kind == .structureTransition }
    )
    #expect(relation.junctionNodeIDs.count == 2)
    let firstNodeID = relation.junctionNodeIDs[0]
    let secondNodeID = relation.junctionNodeIDs[1]
    #expect(network.adjacentNodeIDs(to: firstNodeID).contains(secondNodeID))
    #expect(network.adjacentNodeIDs(to: secondNodeID).contains(firstNodeID))
}

@Test func structureReviewSurvivesProjectRoundTrip() throws {
    let sourceRoadID = UUID()
    let plan = AutoStructurePlan(
        sourceRoadID: sourceRoadID,
        sourceEdgeID: sourceRoadID,
        roadKind: .arterial,
        sourceLevel: .ground,
        sourcePoints: [RoadPoint(x: 0, y: 0), RoadPoint(x: 10, y: 0)],
        totalLength: 10,
        samples: [],
        candidates: [],
        crossingSuggestions: []
    )
    let project = RoadProject(
        name: "结构审核",
        structureReviews: [RoadStructureReviewRecord(plan: plan)]
    )

    let decoded = try JSONDecoder().decode(
        RoadProject.self,
        from: JSONEncoder().encode(project)
    )
    #expect(decoded.structureReviews == project.structureReviews)
    #expect(decoded.formatVersion == RoadProject.currentFormatVersion)
}

@Test func currentAndFutureProjectsCannotLoseRequiredNetwork() throws {
    let project = RoadProject(name: "版本保护")
    var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any]
    )
    object.removeValue(forKey: "roadNetwork")
    object["formatVersion"] = 4

    var rejectedMissingNetwork = false
    do {
        _ = try JSONDecoder().decode(
            RoadProject.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    } catch {
        rejectedMissingNetwork = true
    }
    #expect(rejectedMissingNetwork)

    object["formatVersion"] = RoadProject.currentFormatVersion + 1
    var rejectedFutureVersion = false
    do {
        _ = try JSONDecoder().decode(
            RoadProject.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    } catch {
        rejectedFutureVersion = true
    }
    #expect(rejectedFutureVersion)
}
