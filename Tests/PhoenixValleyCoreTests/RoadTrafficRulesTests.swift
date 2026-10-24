import Foundation
import Testing
@testable import PhoenixValleyCore

@Test func projectV9DefaultsTrafficRulesAndCurrentVersionRoundTripsThem() throws {
    let sourceRoadID = trafficUUID(900)
    let rules = RoadTrafficRuleSet(
        sourceRules: [
            RoadSourceTrafficRule(
                sourceRoadID: sourceRoadID,
                speedLimitKilometersPerHour: 35,
                access: .closed
            ),
        ],
        turnRestrictions: [
            RoadTurnRestriction(
                id: trafficUUID(901),
                fromSourceRoadID: sourceRoadID,
                viaNodeID: trafficUUID(902),
                toSourceRoadID: trafficUUID(903)
            ),
        ]
    )
    let project = RoadProject(
        id: trafficUUID(904),
        name: "交通规则项目",
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 20),
        terrain: TerrainLayout(seed: 1, shoreline: []),
        trafficRules: rules
    )
    let encoded = try JSONEncoder().encode(project)
    let decoded = try JSONDecoder().decode(RoadProject.self, from: encoded)
    let object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )

    #expect(decoded.formatVersion == RoadProject.currentFormatVersion)
    #expect(decoded.trafficRules == rules)
    #expect(object["trafficRules"] != nil)

    var version9Object = object
    version9Object["formatVersion"] = 9
    version9Object.removeValue(forKey: "trafficRules")
    let version9 = try JSONDecoder().decode(
        RoadProject.self,
        from: JSONSerialization.data(withJSONObject: version9Object)
    )

    #expect(version9.formatVersion == 9)
    #expect(version9.trafficRules == RoadTrafficRuleSet())
}

@Test func trafficRulesHaveStableDefaultsAndRoundTrip() throws {
    let sourceRoadID = trafficUUID(1)
    let restriction = RoadTurnRestriction(
        id: trafficUUID(2),
        fromSourceRoadID: sourceRoadID,
        viaNodeID: trafficUUID(3),
        toSourceRoadID: trafficUUID(4)
    )
    let rules = RoadTrafficRuleSet(
        sourceRules: [
            RoadSourceTrafficRule(
                sourceRoadID: sourceRoadID,
                speedLimitKilometersPerHour: 35,
                access: .closed
            ),
        ],
        turnRestrictions: [restriction]
    )

    let decoded = try JSONDecoder().decode(
        RoadTrafficRuleSet.self,
        from: JSONEncoder().encode(rules)
    )
    let empty = try JSONDecoder().decode(
        RoadTrafficRuleSet.self,
        from: Data("{}".utf8)
    )

    #expect(decoded == rules)
    #expect(empty == RoadTrafficRuleSet())
    #expect(
        RoadSourceTrafficRule.defaultSpeedLimit(for: .motorway) == 100
    )
    #expect(
        RoadSourceTrafficRule.defaultSpeedLimit(for: .arterial) == 60
    )
    #expect(
        RoadSourceTrafficRule.defaultSpeedLimit(for: .street) == 40
    )
    #expect(
        RoadSourceTrafficRule.defaultSpeedLimit(for: .railway) == 120
    )
}

@Test func trafficRulesUseExplicitSourceRuleWithoutDuplicatingDirectionOrPriority() {
    let sourceRoadID = trafficUUID(10)
    let defaults = RoadTrafficRuleSet()
    let closed = RoadTrafficRuleSet(
        sourceRules: [
            RoadSourceTrafficRule(
                sourceRoadID: sourceRoadID,
                speedLimitKilometersPerHour: 25,
                access: .closed
            ),
        ]
    )

    #expect(
        defaults.effectiveRule(
            for: sourceRoadID,
            kind: .arterial
        ).speedLimitKilometersPerHour == 60
    )
    #expect(defaults.allowsTraversal(of: sourceRoadID, kind: .arterial))
    #expect(!closed.allowsTraversal(of: sourceRoadID, kind: .arterial))
    #expect(
        closed.effectiveRule(
            for: sourceRoadID,
            kind: .arterial
        ).speedLimitKilometersPerHour == 25
    )
}

@Test func prohibitedTurnUsesRealIncomingAndOutgoingDirections() {
    let fixture = trafficNetworkFixture()
    let restriction = RoadTurnRestriction(
        id: trafficUUID(20),
        fromSourceRoadID: fixture.incomingSourceID,
        viaNodeID: fixture.viaNodeID,
        toSourceRoadID: fixture.outgoingSourceID
    )
    let rules = RoadTrafficRuleSet(turnRestrictions: [restriction])

    #expect(
        !rules.allowsTurn(
            from: fixture.incomingSourceID,
            via: fixture.viaNodeID,
            to: fixture.outgoingSourceID,
            in: fixture.network
        )
    )
    #expect(
        rules.allowsTurn(
            from: fixture.incomingSourceID,
            via: fixture.viaNodeID,
            to: fixture.alternateSourceID,
            in: fixture.network
        )
    )
    #expect(
        !rules.allowsTurn(
            from: fixture.outgoingSourceID,
            via: fixture.viaNodeID,
            to: fixture.incomingSourceID,
            in: fixture.network
        )
    )
    #expect(RoadTrafficRuleValidator.evaluate(rules, in: fixture.network).isEmpty)
}

@Test func trafficRuleValidatorReportsStaleAndDirectionallyImpossibleReferences() {
    let fixture = trafficNetworkFixture()
    let missingSourceID = trafficUUID(30)
    let missingNodeID = trafficUUID(31)
    let detachedNodeID = trafficUUID(32)
    var network = fixture.network
    network.nodes.append(
        RoadNode(
            id: detachedNodeID,
            point: RoadPoint(x: 99, y: 99),
            level: .ground
        )
    )
    let rules = RoadTrafficRuleSet(
        sourceRules: [
            RoadSourceTrafficRule(
                sourceRoadID: missingSourceID,
                speedLimitKilometersPerHour: 0
            ),
        ],
        turnRestrictions: [
            RoadTurnRestriction(
                id: trafficUUID(33),
                fromSourceRoadID: missingSourceID,
                viaNodeID: fixture.viaNodeID,
                toSourceRoadID: fixture.outgoingSourceID
            ),
            RoadTurnRestriction(
                id: trafficUUID(34),
                fromSourceRoadID: fixture.incomingSourceID,
                viaNodeID: missingNodeID,
                toSourceRoadID: fixture.outgoingSourceID
            ),
            RoadTurnRestriction(
                id: trafficUUID(35),
                fromSourceRoadID: fixture.incomingSourceID,
                viaNodeID: detachedNodeID,
                toSourceRoadID: fixture.outgoingSourceID
            ),
            RoadTurnRestriction(
                id: trafficUUID(36),
                fromSourceRoadID: fixture.outgoingSourceID,
                viaNodeID: fixture.viaNodeID,
                toSourceRoadID: fixture.incomingSourceID
            ),
        ]
    )
    let issues = RoadTrafficRuleValidator.evaluate(rules, in: network)

    #expect(issues.contains { $0.kind == .staleSourceRule })
    #expect(issues.contains { $0.kind == .invalidSpeedLimit })
    #expect(issues.contains { $0.kind == .staleTurnSource })
    #expect(issues.contains { $0.kind == .staleTurnNode })
    #expect(issues.contains { $0.kind == .sourceNotIncidentToTurnNode })
    #expect(issues.contains { $0.kind == .directionallyImpossibleTurn })

    let cleaned = rules.removingStaleReferences(in: network)
    #expect(cleaned.sourceRules.isEmpty)
    #expect(cleaned.turnRestrictions.count == 1)
    #expect(cleaned.turnRestrictions[0].id == trafficUUID(36))
    #expect(
        RoadTrafficRuleValidator.evaluate(cleaned, in: network)
            .map(\.kind) == [.directionallyImpossibleTurn]
    )
}

@Test func trafficRuleValidatorReportsDuplicatesAndClosedRoadBlocksTurns() {
    let fixture = trafficNetworkFixture()
    let firstRestriction = RoadTurnRestriction(
        id: trafficUUID(40),
        fromSourceRoadID: fixture.incomingSourceID,
        viaNodeID: fixture.viaNodeID,
        toSourceRoadID: fixture.outgoingSourceID
    )
    let secondRestriction = RoadTurnRestriction(
        id: trafficUUID(41),
        fromSourceRoadID: fixture.incomingSourceID,
        viaNodeID: fixture.viaNodeID,
        toSourceRoadID: fixture.outgoingSourceID
    )
    let rules = RoadTrafficRuleSet(
        sourceRules: [
            RoadSourceTrafficRule(
                sourceRoadID: fixture.incomingSourceID,
                access: .open
            ),
            RoadSourceTrafficRule(
                sourceRoadID: fixture.incomingSourceID,
                access: .closed
            ),
            RoadSourceTrafficRule(
                sourceRoadID: fixture.alternateSourceID,
                access: .closed
            ),
        ],
        turnRestrictions: [firstRestriction, secondRestriction]
    )
    let issues = RoadTrafficRuleValidator.evaluate(rules, in: fixture.network)

    #expect(issues.contains { $0.kind == .duplicateSourceRule })
    #expect(
        issues.filter { $0.kind == .duplicateTurnRestriction }.count == 2
    )
    #expect(
        !rules.allowsTurn(
            from: fixture.incomingSourceID,
            via: fixture.viaNodeID,
            to: fixture.alternateSourceID,
            in: fixture.network
        )
    )
}

private struct TrafficNetworkFixture {
    var network: RoadNetwork
    var viaNodeID: UUID
    var incomingSourceID: UUID
    var outgoingSourceID: UUID
    var alternateSourceID: UUID
}

private func trafficNetworkFixture() -> TrafficNetworkFixture {
    let westNodeID = trafficUUID(100)
    let viaNodeID = trafficUUID(101)
    let eastNodeID = trafficUUID(102)
    let northNodeID = trafficUUID(103)
    let incomingSourceID = trafficUUID(110)
    let outgoingSourceID = trafficUUID(111)
    let alternateSourceID = trafficUUID(112)
    let nodes = [
        RoadNode(
            id: westNodeID,
            point: RoadPoint(x: 0, y: 0),
            level: .ground
        ),
        RoadNode(
            id: viaNodeID,
            point: RoadPoint(x: 10, y: 0),
            level: .ground
        ),
        RoadNode(
            id: eastNodeID,
            point: RoadPoint(x: 20, y: 0),
            level: .ground
        ),
        RoadNode(
            id: northNodeID,
            point: RoadPoint(x: 10, y: -10),
            level: .ground
        ),
    ]
    let edges = [
        trafficEdge(
            id: trafficUUID(120),
            sourceRoadID: incomingSourceID,
            startNodeID: westNodeID,
            endNodeID: viaNodeID,
            direction: .forward
        ),
        trafficEdge(
            id: trafficUUID(121),
            sourceRoadID: outgoingSourceID,
            startNodeID: viaNodeID,
            endNodeID: eastNodeID,
            direction: .forward
        ),
        trafficEdge(
            id: trafficUUID(122),
            sourceRoadID: alternateSourceID,
            startNodeID: viaNodeID,
            endNodeID: northNodeID,
            direction: .bidirectional
        ),
    ]
    return TrafficNetworkFixture(
        network: RoadNetwork(nodes: nodes, edges: edges),
        viaNodeID: viaNodeID,
        incomingSourceID: incomingSourceID,
        outgoingSourceID: outgoingSourceID,
        alternateSourceID: alternateSourceID
    )
}

private func trafficEdge(
    id: UUID,
    sourceRoadID: UUID,
    startNodeID: UUID,
    endNodeID: UUID,
    direction: RoadDirection
) -> RoadEdge {
    RoadEdge(
        id: id,
        sourceRoadID: sourceRoadID,
        startNodeID: startNodeID,
        endNodeID: endNodeID,
        kind: .street,
        level: .ground,
        direction: direction,
        priority: .local,
        points: [
            RoadPoint(x: 0, y: 0),
            RoadPoint(x: 10, y: 0),
        ]
    )
}

private func trafficUUID(_ value: Int) -> UUID {
    UUID(
        uuidString: String(
            format: "20000000-0000-0000-0000-%012d",
            value
        )
    )!
}
