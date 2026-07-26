import Foundation
import Testing
@testable import PhoenixValleyCore

@Test func projectV8DefaultsInterchangesAndCurrentFormatRoundTripsThem() throws {
    let fixture = interchangeFixture()
    let project = RoadProject(
        id: interchangeUUID(1),
        name: "立交项目",
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 20),
        terrain: TerrainLayout(seed: 7, shoreline: []),
        roads: fixture.roads,
        interchanges: [fixture.interchange]
    )
    let encoded = try JSONEncoder().encode(project)
    let decoded = try JSONDecoder().decode(RoadProject.self, from: encoded)
    let encodedObject = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )

    #expect(decoded.formatVersion == RoadProject.currentFormatVersion)
    #expect(decoded.interchanges == [fixture.interchange])
    #expect(encodedObject["interchanges"] != nil)

    var version8Object = encodedObject
    version8Object["formatVersion"] = 8
    version8Object.removeValue(forKey: "interchanges")
    let version8Data = try JSONSerialization.data(withJSONObject: version8Object)
    let version8 = try JSONDecoder().decode(RoadProject.self, from: version8Data)

    #expect(version8.formatVersion == 8)
    #expect(version8.interchanges.isEmpty)
}

@Test func legacyRoadRelationDefaultsInterchangeMetadata() throws {
    let fixture = interchangeFixture()
    let relation = try #require(
        RoadNetwork.rebuilding(from: fixture.roads).network.relations.first
    )
    let encoded = try JSONEncoder().encode(relation)
    var object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "interchangeID")
    object.removeValue(forKey: "rampSourceRoadID")
    object.removeValue(forKey: "rampTerminalRole")

    let decoded = try JSONDecoder().decode(
        RoadRelation.self,
        from: JSONSerialization.data(withJSONObject: object)
    )

    #expect(decoded.interchangeID == nil)
    #expect(decoded.rampSourceRoadID == nil)
    #expect(decoded.rampTerminalRole == nil)
}

@Test func declaredElevatedRampConnectionsAreExplicitAndConflictFree() {
    let fixture = interchangeFixture()
    let network = RoadNetwork.rebuilding(
        from: fixture.roads,
        interchanges: [fixture.interchange]
    ).network
    let rampRelations = network.relations.filter {
        $0.kind == .interchangeRampConnection
    }

    #expect(rampRelations.count == 2)
    #expect(rampRelations.allSatisfy {
        $0.interchangeID == fixture.interchange.id
            && $0.rampSourceRoadID == fixture.interchange.ramps[0].id
            && $0.rampTerminalRole != nil
    })
    #expect(network.layerConflicts.isEmpty)
    #expect(
        RoadInterchangeValidator.evaluate(
            interchanges: [fixture.interchange],
            in: network
        ).isEmpty
    )
}

@Test func undeclaredElevatedTJunctionStillConflicts() {
    let fixture = interchangeFixture()
    let network = RoadNetwork.rebuilding(from: fixture.roads).network

    #expect(
        network.relations.filter { $0.kind == .interchangeRampConnection }.isEmpty
    )
    #expect(
        network.layerConflicts.contains {
            $0.kind == .unsupportedNonGroundJunction
        }
    )
}

@Test func multipleRampsRemainIndependentlyDeclared() {
    let fixture = interchangeFixture(rampCount: 2)
    let network = RoadNetwork.rebuilding(
        from: fixture.roads,
        interchanges: [fixture.interchange]
    ).network
    let connections = network.relations.filter {
        $0.kind == .interchangeRampConnection
    }

    #expect(connections.count == 4)
    #expect(Set(connections.compactMap(\.rampSourceRoadID)).count == 2)
    #expect(network.layerConflicts.isEmpty)
    #expect(
        RoadInterchangeValidator.evaluate(
            interchanges: [fixture.interchange],
            in: network
        ).isEmpty
    )
}

@Test func missingAndDetachedTerminalsProduceSpecificDiagnostics() {
    let fixture = interchangeFixture()
    let missingHostID = interchangeUUID(900)
    var broken = fixture.interchange
    broken.ramps[0].start.hostSourceRoadID = missingHostID
    broken.ramps[0].end.lastKnownPoint = RoadPoint(x: 90, y: 30)
    let network = RoadNetwork.rebuilding(
        from: fixture.roads,
        interchanges: [broken]
    ).network
    let issues = RoadInterchangeValidator.evaluate(
        interchanges: [broken],
        in: network
    )

    #expect(issues.contains {
        $0.kind == .missingHostSource
            && $0.terminalRole == .start
            && $0.relatedSourceRoadIDs.contains(missingHostID)
    })
    #expect(issues.contains {
        $0.kind == .terminalDetached && $0.terminalRole == .end
    })
}

@Test func missingRampAndGeometricIdentifierMismatchAreDiagnosed() {
    let fixture = interchangeFixture()
    let actualRampID = fixture.interchange.ramps[0].sourceRoadID
    let declaredRampID = interchangeUUID(901)
    var broken = fixture.interchange
    broken.ramps[0] = RoadRamp(
        id: declaredRampID,
        start: broken.ramps[0].start,
        end: broken.ramps[0].end,
        direction: broken.ramps[0].direction
    )
    let network = RoadNetwork.rebuilding(
        from: fixture.roads,
        interchanges: [broken]
    ).network
    let issues = RoadInterchangeValidator.evaluate(
        interchanges: [broken],
        in: network
    )

    #expect(issues.contains {
        $0.kind == .missingRampSource
            && $0.rampSourceRoadID == declaredRampID
    })
    #expect(issues.contains {
        $0.kind == .rampIdentifierMismatch
            && $0.relatedSourceRoadIDs == [declaredRampID, actualRampID]
    })
}

@Test func terminalLevelMismatchAlsoInvalidatesMissingTransition() {
    let fixture = interchangeFixture()
    var broken = fixture.interchange
    broken.ramps[0].start.level = .ground
    let network = RoadNetwork.rebuilding(
        from: fixture.roads,
        interchanges: [broken]
    ).network
    let issues = RoadInterchangeValidator.evaluate(
        interchanges: [broken],
        in: network
    )

    #expect(issues.contains {
        $0.kind == .terminalLevelMismatch && $0.terminalRole == .start
    })
    #expect(issues.contains { $0.kind == .invalidTransition })
}

@Test func undeclaredRampInteriorJunctionIsDiagnosed() {
    let fixture = interchangeFixture()
    let crossing = RoadSegment(
        id: interchangeUUID(300),
        kind: .arterial,
        level: .elevated,
        points: [RoadPoint(x: 30, y: -10), RoadPoint(x: 30, y: 30)]
    )
    let network = RoadNetwork.rebuilding(
        from: fixture.roads + [crossing],
        interchanges: [fixture.interchange]
    ).network
    let issues = RoadInterchangeValidator.evaluate(
        interchanges: [fixture.interchange],
        in: network
    )

    #expect(issues.contains {
        $0.kind == .unmodeledJunction
            && $0.relatedSourceRoadIDs.contains(crossing.id)
    })
    #expect(network.layerConflicts.contains {
        $0.kind == .unsupportedNonGroundJunction
    })
}

@Test func validatorDetectsBranchedAndDisconnectedRampGeometry() {
    let hostID = interchangeUUID(400)
    let lowerID = interchangeUUID(401)
    let rampID = interchangeUUID(402)
    let roads = [
        RoadSegment(
            id: hostID,
            kind: .motorway,
            points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 100, y: 0)]
        ),
        RoadSegment(
            id: lowerID,
            kind: .arterial,
            points: [RoadPoint(x: 50, y: -50), RoadPoint(x: 50, y: 50)]
        ),
        RoadSegment(
            id: interchangeUUID(403),
            kind: .street,
            points: [RoadPoint(x: 20, y: 0), RoadPoint(x: 30, y: 10)],
            sourceRoadID: rampID
        ),
        RoadSegment(
            id: interchangeUUID(404),
            kind: .street,
            points: [RoadPoint(x: 30, y: 10), RoadPoint(x: 40, y: 0)],
            sourceRoadID: rampID
        ),
        RoadSegment(
            id: interchangeUUID(405),
            kind: .street,
            points: [RoadPoint(x: 30, y: 10), RoadPoint(x: 30, y: 25)],
            sourceRoadID: rampID
        ),
        RoadSegment(
            id: interchangeUUID(406),
            kind: .street,
            points: [RoadPoint(x: 70, y: 20), RoadPoint(x: 80, y: 20)],
            sourceRoadID: rampID
        ),
    ]
    let interchange = RoadInterchange(
        id: interchangeUUID(407),
        name: "损坏立交",
        anchor: InterchangeCrossingAnchor(
            upperSourceRoadID: hostID,
            lowerSourceRoadID: lowerID,
            lastKnownPoint: RoadPoint(x: 50, y: 0)
        ),
        ramps: [
            RoadRamp(
                id: rampID,
                start: RoadRampTerminal(
                    hostSourceRoadID: hostID,
                    normalizedChainage: 0.2,
                    lastKnownPoint: RoadPoint(x: 20, y: 0),
                    level: .ground
                ),
                end: RoadRampTerminal(
                    hostSourceRoadID: hostID,
                    normalizedChainage: 0.4,
                    lastKnownPoint: RoadPoint(x: 40, y: 0),
                    level: .ground
                )
            ),
        ]
    )
    let network = RoadNetwork.rebuilding(
        from: roads,
        interchanges: [interchange]
    ).network
    let issues = RoadInterchangeValidator.evaluate(
        interchanges: [interchange],
        in: network
    )

    #expect(issues.contains { $0.kind == .branchedRamp })
    #expect(issues.contains { $0.kind == .disconnectedRamp })
}

@Test func rampDirectionUsesRealDirectedEdges() {
    let fixture = interchangeFixture(
        rampDirection: .reverse,
        sourceDirection: .forward
    )
    let network = RoadNetwork.rebuilding(
        from: fixture.roads,
        interchanges: [fixture.interchange]
    ).network
    let issues = RoadInterchangeValidator.evaluate(
        interchanges: [fixture.interchange],
        in: network
    )

    #expect(issues.contains { $0.kind == .unreachableRampDirection })
}

@Test func forwardRampRequiresHostArrivalAtStartAndDepartureAtEnd() {
    let valid = directionalTerminalFixture(
        entryDirection: .reverse,
        exitDirection: .reverse,
        rampDirection: .forward
    )
    #expect(!hasUnreachableDirectionIssue(valid))

    let blockedEntry = directionalTerminalFixture(
        entryDirection: .forward,
        exitDirection: .reverse,
        rampDirection: .forward
    )
    #expect(hasUnreachableDirectionIssue(blockedEntry))

    let blockedExit = directionalTerminalFixture(
        entryDirection: .reverse,
        exitDirection: .forward,
        rampDirection: .forward
    )
    #expect(hasUnreachableDirectionIssue(blockedExit))
}

@Test func reverseRampChecksOppositeHostArrivalAndDeparture() {
    let valid = directionalTerminalFixture(
        entryDirection: .forward,
        exitDirection: .forward,
        rampDirection: .reverse
    )
    #expect(!hasUnreachableDirectionIssue(valid))

    let blockedAtDeclaredStart = directionalTerminalFixture(
        entryDirection: .reverse,
        exitDirection: .forward,
        rampDirection: .reverse
    )
    #expect(hasUnreachableDirectionIssue(blockedAtDeclaredStart))
}

@Test func bidirectionalRampRequiresBothDirectionsAcrossBothHosts() {
    let valid = directionalTerminalFixture(
        entryDirection: .bidirectional,
        exitDirection: .bidirectional,
        rampDirection: .bidirectional
    )
    #expect(!hasUnreachableDirectionIssue(valid))

    let oneWayEntry = directionalTerminalFixture(
        entryDirection: .forward,
        exitDirection: .bidirectional,
        rampDirection: .bidirectional
    )
    #expect(hasUnreachableDirectionIssue(oneWayEntry))

    let oneWayExit = directionalTerminalFixture(
        entryDirection: .bidirectional,
        exitDirection: .reverse,
        rampDirection: .bidirectional
    )
    #expect(hasUnreachableDirectionIssue(oneWayExit))
}

@Test func directedRampTraversesDeclaredStructureTransition() {
    let upperID = interchangeUUID(500)
    let lowerID = interchangeUUID(501)
    let rampID = interchangeUUID(502)
    let transitionPoint = RoadPoint(x: 40, y: 50)
    let upper = RoadSegment(
        id: upperID,
        kind: .motorway,
        level: .elevated,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 100, y: 0)]
    )
    let lower = RoadSegment(
        id: lowerID,
        kind: .arterial,
        level: .ground,
        points: [RoadPoint(x: 50, y: -50), RoadPoint(x: 50, y: 150)]
    )
    let elevatedRamp = RoadSegment(
        id: interchangeUUID(503),
        kind: .street,
        level: .elevated,
        points: [RoadPoint(x: 20, y: 0), transitionPoint],
        direction: .forward,
        sourceRoadID: rampID
    )
    let groundRamp = RoadSegment(
        id: interchangeUUID(504),
        kind: .street,
        level: .ground,
        points: [transitionPoint, RoadPoint(x: 50, y: 100)],
        direction: .forward,
        sourceRoadID: rampID
    )
    let firstLength = elevatedRamp.points[0].distance(to: transitionPoint)
    let secondLength = transitionPoint.distance(to: groundRamp.points[1])
    let transitionFraction = firstLength / (firstLength + secondLength)
    let interchange = RoadInterchange(
        id: interchangeUUID(505),
        name: "跨层匝道",
        anchor: InterchangeCrossingAnchor(
            upperSourceRoadID: upperID,
            lowerSourceRoadID: lowerID,
            lastKnownPoint: RoadPoint(x: 50, y: 0)
        ),
        ramps: [
            RoadRamp(
                id: rampID,
                start: RoadRampTerminal(
                    hostSourceRoadID: upperID,
                    normalizedChainage: 0.2,
                    lastKnownPoint: RoadPoint(x: 20, y: 0),
                    level: .elevated
                ),
                end: RoadRampTerminal(
                    hostSourceRoadID: lowerID,
                    normalizedChainage: 0.75,
                    lastKnownPoint: RoadPoint(x: 50, y: 100),
                    level: .ground
                ),
                direction: .forward,
                transition: RoadRampTransition(
                    fromLevel: .elevated,
                    toLevel: .ground,
                    chainageFraction: transitionFraction
                )
            ),
        ]
    )
    let network = RoadNetwork.rebuilding(
        from: [upper, lower, elevatedRamp, groundRamp],
        interchanges: [interchange]
    ).network
    let issues = RoadInterchangeValidator.evaluate(
        interchanges: [interchange],
        in: network
    )

    #expect(network.relations.contains { $0.kind == .structureTransition })
    #expect(network.relations.filter {
        $0.kind == .interchangeRampConnection
    }.count == 2)
    #expect(!issues.contains { $0.kind == .invalidTransition })
    #expect(!issues.contains { $0.kind == .unreachableRampDirection })
}

@Test func railwayAndTunnelHostsHaveExplicitDiagnostics() {
    let railwayID = interchangeUUID(600)
    let lowerID = interchangeUUID(601)
    let rampID = interchangeUUID(602)
    let railway = RoadSegment(
        id: railwayID,
        kind: .railway,
        level: .tunnel,
        points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 100, y: 0)]
    )
    let lower = RoadSegment(
        id: lowerID,
        kind: .street,
        level: .ground,
        points: [RoadPoint(x: 50, y: -50), RoadPoint(x: 50, y: 50)]
    )
    let ramp = RoadSegment(
        id: rampID,
        kind: .street,
        level: .tunnel,
        points: [RoadPoint(x: 20, y: 0), RoadPoint(x: 40, y: 0)]
    )
    let interchange = RoadInterchange(
        id: interchangeUUID(603),
        name: "不支持的宿主",
        anchor: InterchangeCrossingAnchor(
            upperSourceRoadID: railwayID,
            lowerSourceRoadID: lowerID,
            lastKnownPoint: RoadPoint(x: 50, y: 0)
        ),
        ramps: [
            RoadRamp(
                id: rampID,
                start: RoadRampTerminal(
                    hostSourceRoadID: railwayID,
                    normalizedChainage: 0.2,
                    lastKnownPoint: RoadPoint(x: 20, y: 0),
                    level: .tunnel
                ),
                end: RoadRampTerminal(
                    hostSourceRoadID: railwayID,
                    normalizedChainage: 0.4,
                    lastKnownPoint: RoadPoint(x: 40, y: 0),
                    level: .tunnel
                )
            ),
        ]
    )
    let network = RoadNetwork.rebuilding(
        from: [railway, lower, ramp],
        interchanges: [interchange]
    ).network
    let issues = RoadInterchangeValidator.evaluate(
        interchanges: [interchange],
        in: network
    )

    #expect(issues.contains { $0.kind == .unsupportedRailwayHost })
    #expect(issues.contains { $0.kind == .unsupportedTunnelHost })
}

@Test func validatorRejectsRailwayRampSource() {
    let fixture = interchangeFixture()
    let rampSourceRoadID = fixture.interchange.ramps[0].sourceRoadID
    var roads = fixture.roads
    for index in roads.indices
    where roads[index].sourceRoadID == rampSourceRoadID {
        roads[index].kind = .railway
    }
    let network = RoadNetwork.rebuilding(
        from: roads,
        interchanges: [fixture.interchange]
    ).network
    let issues = RoadInterchangeValidator.evaluate(
        interchanges: [fixture.interchange],
        in: network
    )

    #expect(issues.contains {
        $0.kind == .unsupportedRailwayRamp
            && $0.rampSourceRoadID == rampSourceRoadID
    })
}

private func interchangeFixture(
    rampCount: Int = 1,
    rampDirection: RoadDirection = .bidirectional,
    sourceDirection: RoadDirection? = nil
) -> (roads: [RoadSegment], interchange: RoadInterchange) {
    let upperID = interchangeUUID(100)
    let lowerID = interchangeUUID(101)
    var roads = [
        RoadSegment(
            id: upperID,
            kind: .motorway,
            level: .elevated,
            points: [RoadPoint(x: 0, y: 0), RoadPoint(x: 100, y: 0)]
        ),
        RoadSegment(
            id: lowerID,
            kind: .arterial,
            level: .ground,
            points: [RoadPoint(x: 50, y: -50), RoadPoint(x: 50, y: 50)]
        ),
    ]
    var ramps: [RoadRamp] = []
    let ranges: [(Double, Double, Double)] = rampCount == 1
        ? [(20, 30, 40)]
        : [(10, 20, 30), (70, 80, 90)]
    for (index, range) in ranges.enumerated() {
        let rampID = interchangeUUID(110 + index)
        let sourceRoad = RoadSegment(
            id: rampID,
            kind: .street,
            level: .elevated,
            points: [
                RoadPoint(x: range.0, y: 0),
                RoadPoint(x: range.1, y: index.isMultiple(of: 2) ? 20 : -20),
                RoadPoint(x: range.2, y: 0),
            ],
            direction: sourceDirection ?? rampDirection
        )
        roads.append(sourceRoad)
        ramps.append(
            RoadRamp(
                id: rampID,
                start: RoadRampTerminal(
                    hostSourceRoadID: upperID,
                    normalizedChainage: range.0 / 100,
                    lastKnownPoint: RoadPoint(x: range.0, y: 0),
                    level: .elevated
                ),
                end: RoadRampTerminal(
                    hostSourceRoadID: upperID,
                    normalizedChainage: range.2 / 100,
                    lastKnownPoint: RoadPoint(x: range.2, y: 0),
                    level: .elevated
                ),
                direction: rampDirection
            )
        )
    }
    return (
        roads,
        RoadInterchange(
            id: interchangeUUID(120),
            name: "测试立交",
            anchor: InterchangeCrossingAnchor(
                upperSourceRoadID: upperID,
                lowerSourceRoadID: lowerID,
                lastKnownPoint: RoadPoint(x: 50, y: 0)
            ),
            ramps: ramps
        )
    )
}

private func directionalTerminalFixture(
    entryDirection: RoadDirection,
    exitDirection: RoadDirection,
    rampDirection: RoadDirection
) -> (roads: [RoadSegment], interchange: RoadInterchange) {
    let entryID = interchangeUUID(700)
    let exitID = interchangeUUID(701)
    let rampID = interchangeUUID(702)
    let roads = [
        RoadSegment(
            id: entryID,
            kind: .arterial,
            points: [
                RoadPoint(x: 0, y: 0),
                RoadPoint(x: 100, y: 0),
            ],
            direction: entryDirection
        ),
        RoadSegment(
            id: exitID,
            kind: .arterial,
            points: [
                RoadPoint(x: 0, y: 40),
                RoadPoint(x: 100, y: 40),
            ],
            direction: exitDirection
        ),
        RoadSegment(
            id: rampID,
            kind: .street,
            points: [
                RoadPoint(x: 0, y: 0),
                RoadPoint(x: 50, y: 20),
                RoadPoint(x: 100, y: 40),
            ],
            direction: rampDirection
        ),
    ]
    let interchange = RoadInterchange(
        id: interchangeUUID(703),
        name: "方向测试立交",
        anchor: InterchangeCrossingAnchor(
            upperSourceRoadID: entryID,
            lowerSourceRoadID: exitID,
            lastKnownPoint: RoadPoint(x: 50, y: 20)
        ),
        ramps: [
            RoadRamp(
                id: rampID,
                start: RoadRampTerminal(
                    hostSourceRoadID: entryID,
                    normalizedChainage: 0,
                    lastKnownPoint: RoadPoint(x: 0, y: 0),
                    level: .ground
                ),
                end: RoadRampTerminal(
                    hostSourceRoadID: exitID,
                    normalizedChainage: 1,
                    lastKnownPoint: RoadPoint(x: 100, y: 40),
                    level: .ground
                ),
                direction: rampDirection
            ),
        ]
    )
    return (roads, interchange)
}

private func hasUnreachableDirectionIssue(
    _ fixture: (roads: [RoadSegment], interchange: RoadInterchange)
) -> Bool {
    let network = RoadNetwork.rebuilding(
        from: fixture.roads,
        interchanges: [fixture.interchange]
    ).network
    return RoadInterchangeValidator.evaluate(
        interchanges: [fixture.interchange],
        in: network
    ).contains { $0.kind == .unreachableRampDirection }
}

private func interchangeUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
}
