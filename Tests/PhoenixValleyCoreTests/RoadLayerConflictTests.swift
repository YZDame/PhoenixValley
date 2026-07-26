import Testing
@testable import PhoenixValleyCore

@Test func elevatedInteriorCrossingRequiresExplicitInterchange() {
    let horizontal = conflictRoad(
        level: .elevated,
        points: [RoadPoint(x: 0, y: 5), RoadPoint(x: 10, y: 5)]
    )
    let vertical = conflictRoad(
        level: .elevated,
        points: [RoadPoint(x: 5, y: 0), RoadPoint(x: 5, y: 10)]
    )

    let network = RoadNetwork.rebuilding(from: [horizontal, vertical]).network

    #expect(network.layerConflicts.count == 1)
    #expect(network.layerConflicts[0].kind == .unsupportedNonGroundJunction)
}

@Test func matchingElevatedStructuresMayContinueAtEndpoints() {
    let first = conflictRoad(
        level: .elevated,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 5, y: 0)]
    )
    let second = conflictRoad(
        level: .elevated,
        points: [RoadPoint(x: 5, y: 0), RoadPoint(x: 10, y: 0)]
    )

    let network = RoadNetwork.rebuilding(from: [first, second]).network

    #expect(network.layerConflicts.isEmpty)
}

@Test func differentElevatedStructuresConflictAtUnmodeledEndpointTransition() {
    let bridge = conflictRoad(
        structure: .bridge,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 5, y: 0)]
    )
    let viaduct = conflictRoad(
        structure: .elevated,
        points: [RoadPoint(x: 5, y: 0), RoadPoint(x: 10, y: 0)]
    )

    let network = RoadNetwork.rebuilding(from: [bridge, viaduct]).network

    #expect(network.layerConflicts.count == 1)
    #expect(network.layerConflicts[0].kind == .unsupportedNonGroundJunction)
}

@Test func groundAndElevatedCrossingIsGradeSeparatedWithoutConflict() {
    let ground = conflictRoad(
        level: .ground,
        points: [RoadPoint(x: 0, y: 5), RoadPoint(x: 10, y: 5)]
    )
    let elevated = conflictRoad(
        level: .elevated,
        points: [RoadPoint(x: 5, y: 0), RoadPoint(x: 5, y: 10)]
    )

    let network = RoadNetwork.rebuilding(from: [ground, elevated]).network

    #expect(network.layerConflicts.isEmpty)
    #expect(network.relations.first?.kind == .gradeSeparatedCrossing)
}

@Test func overlappingTunnelsAreReportedAsStructuralConflict() {
    let first = conflictRoad(
        level: .tunnel,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 10, y: 0)]
    )
    let second = conflictRoad(
        level: .tunnel,
        points: [RoadPoint(x: 3, y: 0), RoadPoint(x: 8, y: 0)]
    )

    let network = RoadNetwork.rebuilding(from: [first, second]).network

    #expect(network.layerConflicts.count == 1)
    #expect(network.layerConflicts[0].kind == .nonGroundStructureOverlap)
}

private func conflictRoad(
    level: RoadLevel = .ground,
    structure: RoadStructureType? = nil,
    points: [RoadPoint]
) -> RoadSegment {
    RoadSegment(
        kind: .arterial,
        level: level,
        structure: structure,
        points: points
    )
}
