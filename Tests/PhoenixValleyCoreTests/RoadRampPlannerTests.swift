import Foundation
import Testing
@testable import PhoenixValleyCore

@Test func rampPlannerSnapsTerminalsAndBuildsExactGroundToElevatedTransition() throws {
    let fixture = rampFixture()
    let plan = try RoadRampPlanner.plan(
        points: [
            RoadPoint(x: 100, y: 104),
            RoadPoint(x: 170, y: 120),
            RoadPoint(x: 196, y: 220),
        ],
        crossing: fixture.crossing,
        roads: fixture.roads,
        existingInterchanges: [],
        kind: .motorway,
        direction: .forward,
        mapScale: .standard
    )

    #expect(plan.interchange.ramps == [plan.ramp])
    #expect(plan.interchange.anchor.upperSourceRoadID == fixture.elevated.sourceRoadID)
    #expect(plan.interchange.anchor.lowerSourceRoadID == fixture.ground.sourceRoadID)
    #expect(plan.ramp.sourceRoadID == plan.roadSegments[0].sourceRoadID)
    #expect(plan.ramp.start.hostSourceRoadID == fixture.ground.sourceRoadID)
    #expect(plan.ramp.end.hostSourceRoadID == fixture.elevated.sourceRoadID)
    #expect(plan.ramp.start.lastKnownPoint == RoadPoint(x: 100, y: 100))
    #expect(
        plan.ramp.end.lastKnownPoint.distance(to: RoadPoint(x: 200, y: 220))
            < 1e-9
    )
    #expect(abs(plan.ramp.start.normalizedChainage - 0.25) < 1e-9)
    #expect(abs(plan.ramp.end.normalizedChainage - 0.55) < 1e-9)
    #expect(plan.ramp.direction == .forward)
    #expect(plan.ramp.transition?.fromLevel == .ground)
    #expect(plan.ramp.transition?.toLevel == .elevated)
    #expect(plan.roadSegments.count == 2)
    #expect(plan.roadSegments.allSatisfy { $0.sourceRoadID == plan.ramp.id })
    #expect(plan.roadSegments.allSatisfy { $0.kind == .motorway })
    #expect(plan.roadSegments.allSatisfy { $0.direction == .forward })
    #expect(plan.roadSegments.allSatisfy { $0.priority == .arterial })
    #expect(plan.roadSegments[0].structure == .ground)
    #expect(plan.roadSegments[1].structure == .elevated)
    #expect(plan.roadSegments[0].points.last == plan.roadSegments[1].points.first)

    let completeLength = polylineLength(plan.roadSegments[0].points)
        + polylineLength(plan.roadSegments[1].points)
    let expectedFirstLength = completeLength
        * (plan.ramp.transition?.chainageFraction ?? -1)
    #expect(
        abs(polylineLength(plan.roadSegments[0].points) - expectedFirstLength)
            < 1e-8
    )

    let rebuilt = RoadNetwork.rebuilding(
        from: fixture.roads + plan.roadSegments,
        interchanges: [plan.interchange]
    ).network
    #expect(
        RoadInterchangeValidator.evaluate(
            interchanges: [plan.interchange],
            in: rebuilt
        ).isEmpty
    )
}

@Test func rampPlannerUsesStrokeOrderForReverseRamp() throws {
    let fixture = rampFixture()
    let plan = try RoadRampPlanner.plan(
        points: [
            RoadPoint(x: 204, y: 220),
            RoadPoint(x: 170, y: 120),
            RoadPoint(x: 100, y: 96),
        ],
        crossing: fixture.crossing,
        roads: fixture.roads,
        existingInterchanges: [],
        kind: .street,
        direction: .reverse,
        mapScale: .standard
    )

    #expect(plan.ramp.start.hostSourceRoadID == fixture.elevated.sourceRoadID)
    #expect(plan.ramp.end.hostSourceRoadID == fixture.ground.sourceRoadID)
    #expect(
        plan.ramp.start.lastKnownPoint.distance(to: RoadPoint(x: 200, y: 220))
            < 1e-9
    )
    #expect(plan.ramp.end.lastKnownPoint == RoadPoint(x: 100, y: 100))
    #expect(plan.ramp.direction == .reverse)
    #expect(plan.ramp.transition?.fromLevel == .elevated)
    #expect(plan.ramp.transition?.toLevel == .ground)
    #expect(plan.roadSegments.map(\.level) == [.elevated, .ground])
}

@Test func rampPlannerKeepsSameLevelTerminalsInOneSegment() throws {
    let fixture = rampFixture()
    let elevatedApproach = RoadSegment(
        id: fixture.elevated.id,
        kind: fixture.elevated.kind,
        level: .elevated,
        structure: .elevated,
        points: [
            RoadPoint(x: 200, y: 0),
            RoadPoint(x: 200, y: 100),
        ],
        priority: fixture.elevated.priority,
        sourceRoadID: fixture.elevated.sourceRoadID
    )
    let groundApproach = RoadSegment(
        kind: fixture.elevated.kind,
        level: .ground,
        structure: .ground,
        points: [
            RoadPoint(x: 200, y: 100),
            RoadPoint(x: 200, y: 400),
        ],
        priority: fixture.elevated.priority,
        sourceRoadID: fixture.elevated.sourceRoadID
    )

    let plan = try RoadRampPlanner.plan(
        points: [
            RoadPoint(x: 100, y: 104),
            RoadPoint(x: 170, y: 120),
            RoadPoint(x: 196, y: 220),
        ],
        crossing: fixture.crossing,
        roads: [fixture.ground, elevatedApproach, groundApproach],
        existingInterchanges: [],
        kind: .street,
        direction: .bidirectional,
        mapScale: .standard
    )

    #expect(plan.ramp.start.level == .ground)
    #expect(plan.ramp.end.level == .ground)
    #expect(plan.ramp.transition == nil)
    #expect(plan.roadSegments.count == 1)
    #expect(plan.roadSegments[0].level == .ground)
    #expect(plan.roadSegments[0].structure == .ground)
}

@Test func rampPlannerReusesNearbyInterchangeForAdditionalRamp() throws {
    let fixture = rampFixture()
    let first = try RoadRampPlanner.plan(
        points: [
            RoadPoint(x: 100, y: 100),
            RoadPoint(x: 170, y: 120),
            RoadPoint(x: 200, y: 220),
        ],
        crossing: fixture.crossing,
        roads: fixture.roads,
        existingInterchanges: [],
        kind: .street,
        direction: .bidirectional,
        mapScale: .standard
    )
    let second = try RoadRampPlanner.plan(
        points: [
            RoadPoint(x: 300, y: 100),
            RoadPoint(x: 240, y: 150),
            RoadPoint(x: 200, y: 220),
        ],
        crossing: fixture.crossing,
        roads: fixture.roads,
        existingInterchanges: [first.interchange],
        kind: .street,
        direction: .forward,
        mapScale: .standard
    )

    #expect(second.interchange.id == first.interchange.id)
    #expect(second.interchange.name == first.interchange.name)
    #expect(second.interchange.ramps.count == 2)
    #expect(second.interchange.ramps[0] == first.ramp)
    #expect(second.interchange.ramps[1] == second.ramp)
    #expect(second.ramp.id != first.ramp.id)
}

@Test func rampPlannerRejectsDetachedAndShortStrokes() throws {
    let fixture = rampFixture()
    var detached = false
    do {
        _ = try RoadRampPlanner.plan(
            points: [
                RoadPoint(x: 100, y: 60),
                RoadPoint(x: 160, y: 140),
                RoadPoint(x: 240, y: 220),
            ],
            crossing: fixture.crossing,
            roads: fixture.roads,
            existingInterchanges: [],
            kind: .street,
            direction: .bidirectional,
            mapScale: .standard,
            configuration: .init(
                endpointSnapDistanceMeters: 10,
                minimumDistanceFromCrossingMeters: 0,
                minimumRampLengthMeters: 0
            )
        )
    } catch RoadRampPlannerError.endpointsDoNotSnapToDistinctHosts {
        detached = true
    }
    #expect(detached)

    var short = false
    do {
        _ = try RoadRampPlanner.plan(
            points: [
                RoadPoint(x: 170, y: 100),
                RoadPoint(x: 185, y: 115),
                RoadPoint(x: 200, y: 130),
            ],
            crossing: fixture.crossing,
            roads: fixture.roads,
            existingInterchanges: [],
            kind: .street,
            direction: .bidirectional,
            mapScale: .standard,
            configuration: .init(
                endpointSnapDistanceMeters: 5,
                minimumDistanceFromCrossingMeters: 0,
                minimumRampLengthMeters: 100
            )
        )
    } catch RoadRampPlannerError.rampTooShort {
        short = true
    }
    #expect(short)
}

@Test func rampPlannerRejectsTerminalTooNearCrossing() throws {
    let fixture = rampFixture()
    var rejected = false
    do {
        _ = try RoadRampPlanner.plan(
            points: [
                RoadPoint(x: 190, y: 100),
                RoadPoint(x: 195, y: 110),
                RoadPoint(x: 200, y: 120),
            ],
            crossing: fixture.crossing,
            roads: fixture.roads,
            existingInterchanges: [],
            kind: .street,
            direction: .bidirectional,
            mapScale: .standard,
            configuration: .init(
                endpointSnapDistanceMeters: 5,
                minimumDistanceFromCrossingMeters: 25,
                minimumRampLengthMeters: 0
            )
        )
    } catch RoadRampPlannerError.terminalTooCloseToCrossing(
        role: .start,
        distanceMeters: _
    ) {
        rejected = true
    }
    #expect(rejected)
}

@Test func rampPlannerRejectsRailwayAndTunnelHosts() throws {
    let fixture = rampFixture()
    let railway = RoadSegment(
        id: fixture.ground.id,
        kind: .railway,
        points: fixture.ground.points
    )
    var railwayRejected = false
    do {
        _ = try RoadRampPlanner.plan(
            points: rampFixturePoints,
            crossing: fixture.crossing,
            roads: [railway, fixture.elevated],
            existingInterchanges: [],
            kind: .street,
            direction: .bidirectional,
            mapScale: .standard
        )
    } catch RoadRampPlannerError.railwayHostUnsupported(let sourceRoadID) {
        railwayRejected = sourceRoadID == railway.sourceRoadID
    }
    #expect(railwayRejected)

    let tunnel = RoadSegment(
        id: fixture.ground.id,
        kind: .arterial,
        level: .tunnel,
        structure: .tunnel,
        points: fixture.ground.points
    )
    var tunnelRejected = false
    do {
        _ = try RoadRampPlanner.plan(
            points: rampFixturePoints,
            crossing: fixture.crossing,
            roads: [tunnel, fixture.elevated],
            existingInterchanges: [],
            kind: .street,
            direction: .bidirectional,
            mapScale: .standard
        )
    } catch RoadRampPlannerError.tunnelHostUnsupported(let sourceRoadID) {
        tunnelRejected = sourceRoadID == tunnel.sourceRoadID
    }
    #expect(tunnelRejected)
}

@Test func rampPlannerAllowsGroundTerminalWhenRemoteSameSourcePieceIsTunnel() throws {
    let fixture = rampFixture()
    let remoteTunnel = RoadSegment(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
        kind: fixture.ground.kind,
        level: .tunnel,
        structure: .tunnel,
        points: [
            RoadPoint(x: 400, y: 100),
            RoadPoint(x: 600, y: 100),
        ],
        priority: fixture.ground.priority,
        sourceRoadID: fixture.ground.sourceRoadID
    )

    let plan = try RoadRampPlanner.plan(
        points: rampFixturePoints,
        crossing: fixture.crossing,
        roads: fixture.roads + [remoteTunnel],
        existingInterchanges: [],
        kind: .street,
        direction: .bidirectional,
        mapScale: .standard
    )

    #expect(plan.ramp.start.hostSourceRoadID == fixture.ground.sourceRoadID)
    #expect(plan.ramp.start.level == .ground)
    #expect(plan.roadSegments.first?.structure == .ground)
}

@Test func rampPlannerRejectsRailwayRampKind() throws {
    let fixture = rampFixture()
    var rejected = false
    do {
        _ = try RoadRampPlanner.plan(
            points: rampFixturePoints,
            crossing: fixture.crossing,
            roads: fixture.roads,
            existingInterchanges: [],
            kind: .railway,
            direction: .bidirectional,
            mapScale: .standard
        )
    } catch RoadRampPlannerError.railwayRampUnsupported {
        rejected = true
    }

    #expect(rejected)
}

@Test func rampPlannerOutputRebuildsIntoValidatorCleanInterchange() throws {
    let fixture = rampFixture()
    let plan = try RoadRampPlanner.plan(
        points: rampFixturePoints,
        crossing: fixture.crossing,
        roads: fixture.roads,
        existingInterchanges: [],
        kind: .street,
        direction: .forward,
        mapScale: .standard
    )
    let network = RoadNetwork.rebuilding(
        from: fixture.roads + plan.roadSegments,
        interchanges: [plan.interchange]
    ).network
    let issues = RoadInterchangeValidator.evaluate(
        interchanges: [plan.interchange],
        in: network
    )

    #expect(network.relations.filter {
        $0.kind == .interchangeRampConnection
    }.count == 2)
    #expect(issues.isEmpty)
}

@Test func rampPlannerAppliesSnapThresholdInPhysicalMeters() throws {
    let fixture = rampFixture()
    let points = [
        RoadPoint(x: 100, y: 112),
        RoadPoint(x: 170, y: 140),
        RoadPoint(x: 188, y: 220),
    ]
    let configuration = RoadRampPlannerConfiguration(
        endpointSnapDistanceMeters: 20,
        minimumDistanceFromCrossingMeters: 0,
        minimumRampLengthMeters: 0
    )

    let standardScalePlan = try RoadRampPlanner.plan(
        points: points,
        crossing: fixture.crossing,
        roads: fixture.roads,
        existingInterchanges: [],
        kind: .street,
        direction: .bidirectional,
        mapScale: .standard,
        configuration: configuration
    )
    #expect(standardScalePlan.ramp.start.lastKnownPoint == RoadPoint(x: 100, y: 100))

    var rejectedAtDoubleScale = false
    do {
        _ = try RoadRampPlanner.plan(
            points: points,
            crossing: fixture.crossing,
            roads: fixture.roads,
            existingInterchanges: [],
            kind: .street,
            direction: .bidirectional,
            mapScale: MapScale(metersPerPoint: 2),
            configuration: configuration
        )
    } catch RoadRampPlannerError.endpointsDoNotSnapToDistinctHosts {
        rejectedAtDoubleScale = true
    }
    #expect(rejectedAtDoubleScale)
}

private let rampFixturePoints = [
    RoadPoint(x: 100, y: 104),
    RoadPoint(x: 170, y: 120),
    RoadPoint(x: 196, y: 220),
]

private struct RampPlannerFixture {
    var ground: RoadSegment
    var elevated: RoadSegment
    var crossing: RoadRelation

    var roads: [RoadSegment] {
        [ground, elevated]
    }
}

private func rampFixture() -> RampPlannerFixture {
    let groundID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let elevatedID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    let ground = RoadSegment(
        id: groundID,
        kind: .arterial,
        level: .ground,
        structure: .ground,
        points: [
            RoadPoint(x: 0, y: 100),
            RoadPoint(x: 400, y: 100),
        ],
        priority: .arterial
    )
    let elevated = RoadSegment(
        id: elevatedID,
        kind: .motorway,
        level: .elevated,
        structure: .elevated,
        points: [
            RoadPoint(x: 200, y: 0),
            RoadPoint(x: 200, y: 400),
        ],
        priority: .motorway
    )
    let crossing = RoadRelation(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
        kind: .gradeSeparatedCrossing,
        point: RoadPoint(x: 200, y: 100),
        firstRoadID: groundID,
        secondRoadID: elevatedID,
        firstLevel: .ground,
        secondLevel: .elevated,
        firstEdgeIDs: [groundID],
        secondEdgeIDs: [elevatedID]
    )
    return RampPlannerFixture(
        ground: ground,
        elevated: elevated,
        crossing: crossing
    )
}

private func polylineLength(_ points: [RoadPoint]) -> Double {
    zip(points, points.dropFirst()).reduce(0) {
        $0 + $1.0.distance(to: $1.1)
    }
}
