import Foundation

public struct RoadInterchange: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var anchor: InterchangeCrossingAnchor
    public var ramps: [RoadRamp]

    public init(
        id: UUID = UUID(),
        name: String,
        anchor: InterchangeCrossingAnchor,
        ramps: [RoadRamp] = []
    ) {
        self.id = id
        self.name = name
        self.anchor = anchor
        self.ramps = ramps
    }
}

public struct InterchangeCrossingAnchor: Codable, Hashable, Sendable {
    public var upperSourceRoadID: UUID
    public var lowerSourceRoadID: UUID
    public var lastKnownPoint: RoadPoint

    public init(
        upperSourceRoadID: UUID,
        lowerSourceRoadID: UUID,
        lastKnownPoint: RoadPoint
    ) {
        self.upperSourceRoadID = upperSourceRoadID
        self.lowerSourceRoadID = lowerSourceRoadID
        self.lastKnownPoint = lastKnownPoint
    }
}

public struct RoadRamp: Identifiable, Codable, Hashable, Sendable {
    /// A ramp is a logical source road, so its model identifier is also its
    /// `RoadSegment.sourceRoadID`.
    public let id: UUID
    public var start: RoadRampTerminal
    public var end: RoadRampTerminal
    public var direction: RoadDirection
    public var transition: RoadRampTransition?

    public init(
        id: UUID = UUID(),
        start: RoadRampTerminal,
        end: RoadRampTerminal,
        direction: RoadDirection = .bidirectional,
        transition: RoadRampTransition? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.direction = direction
        self.transition = transition
    }

    public var sourceRoadID: UUID { id }
}

public struct RoadRampTerminal: Codable, Hashable, Sendable {
    public var hostSourceRoadID: UUID
    public var normalizedChainage: Double
    public var lastKnownPoint: RoadPoint
    public var level: RoadLevel

    public init(
        hostSourceRoadID: UUID,
        normalizedChainage: Double,
        lastKnownPoint: RoadPoint,
        level: RoadLevel
    ) {
        self.hostSourceRoadID = hostSourceRoadID
        self.normalizedChainage = normalizedChainage
        self.lastKnownPoint = lastKnownPoint
        self.level = level
    }
}

public struct RoadRampTransition: Codable, Hashable, Sendable {
    public var fromLevel: RoadLevel
    public var toLevel: RoadLevel
    public var chainageFraction: Double

    public init(
        fromLevel: RoadLevel,
        toLevel: RoadLevel,
        chainageFraction: Double
    ) {
        self.fromLevel = fromLevel
        self.toLevel = toLevel
        self.chainageFraction = chainageFraction
    }
}

public enum RoadRampTerminalRole: String, Codable, CaseIterable, Hashable, Sendable {
    case start
    case end
}

public enum RoadInterchangeDiagnosticKind: String, Codable, CaseIterable, Sendable {
    case missingAnchorRoad
    case missingRampSource
    case rampIdentifierMismatch
    case missingHostSource
    case terminalDetached
    case terminalLevelMismatch
    case branchedRamp
    case disconnectedRamp
    case unmodeledJunction
    case invalidTransition
    case unsupportedRailwayRamp
    case unsupportedRailwayHost
    case unsupportedTunnelHost
    case unreachableRampDirection
}

public struct RoadInterchangeIssue: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var kind: RoadInterchangeDiagnosticKind
    public var interchangeID: UUID
    public var rampSourceRoadID: UUID?
    public var terminalRole: RoadRampTerminalRole?
    public var relatedSourceRoadIDs: Set<UUID>
    public var point: RoadPoint?
    public var message: String

    public init(
        id: UUID = UUID(),
        kind: RoadInterchangeDiagnosticKind,
        interchangeID: UUID,
        rampSourceRoadID: UUID? = nil,
        terminalRole: RoadRampTerminalRole? = nil,
        relatedSourceRoadIDs: Set<UUID> = [],
        point: RoadPoint? = nil,
        message: String
    ) {
        self.id = id
        self.kind = kind
        self.interchangeID = interchangeID
        self.rampSourceRoadID = rampSourceRoadID
        self.terminalRole = terminalRole
        self.relatedSourceRoadIDs = relatedSourceRoadIDs
        self.point = point
        self.message = message
    }
}

public enum RoadInterchangeValidator {
    public static func evaluate(
        interchanges: [RoadInterchange],
        in network: RoadNetwork
    ) -> [RoadInterchangeIssue] {
        let sourceEdges = Dictionary(grouping: network.edges, by: \.sourceRoadID)
        var issues: [RoadInterchangeIssue] = []

        for interchange in interchanges.sorted(by: {
            $0.id.uuidString < $1.id.uuidString
        }) {
            let anchorIDs = [
                interchange.anchor.upperSourceRoadID,
                interchange.anchor.lowerSourceRoadID,
            ]
            for sourceRoadID in anchorIDs where sourceEdges[sourceRoadID, default: []].isEmpty {
                issues.append(
                    issue(
                        kind: .missingAnchorRoad,
                        interchange: interchange,
                        relatedSourceRoadIDs: [sourceRoadID],
                        point: interchange.anchor.lastKnownPoint,
                        message: "立交锚点道路不存在。"
                    )
                )
            }

            let allowedHostIDs = Set(anchorIDs + interchange.ramps.map(\.sourceRoadID))
            for ramp in interchange.ramps.sorted(by: {
                $0.id.uuidString < $1.id.uuidString
            }) {
                let rampEdges = sourceEdges[ramp.sourceRoadID, default: []]
                if rampEdges.isEmpty {
                    issues.append(
                        issue(
                            kind: .missingRampSource,
                            interchange: interchange,
                            ramp: ramp,
                            relatedSourceRoadIDs: [ramp.sourceRoadID],
                            message: "匝道对应的源道路不存在。"
                        )
                    )
                }

                if let inferredSourceID = inferredRampSourceID(
                    for: ramp,
                    in: network,
                    excluding: allowedHostIDs
                ), inferredSourceID != ramp.sourceRoadID {
                    issues.append(
                        issue(
                            kind: .rampIdentifierMismatch,
                            interchange: interchange,
                            ramp: ramp,
                            relatedSourceRoadIDs: [ramp.sourceRoadID, inferredSourceID],
                            message: "匝道标识与实际连接两端的源道路不一致。"
                        )
                    )
                }

                if !rampEdges.isEmpty {
                    if rampEdges.contains(where: { $0.kind == .railway }) {
                        issues.append(
                            issue(
                                kind: .unsupportedRailwayRamp,
                                interchange: interchange,
                                ramp: ramp,
                                relatedSourceRoadIDs: [ramp.sourceRoadID],
                                message: "铁路不能作为公路立交匝道。"
                            )
                        )
                    }
                    let graph = sourceGraph(
                        sourceRoadID: ramp.sourceRoadID,
                        edges: rampEdges,
                        network: network
                    )
                    if graph.hasBranch {
                        issues.append(
                            issue(
                                kind: .branchedRamp,
                                interchange: interchange,
                                ramp: ramp,
                                relatedSourceRoadIDs: [ramp.sourceRoadID],
                                message: "一条匝道源道路形成了分支。"
                            )
                        )
                    }
                    if graph.componentCount > 1 {
                        issues.append(
                            issue(
                                kind: .disconnectedRamp,
                                interchange: interchange,
                                ramp: ramp,
                                relatedSourceRoadIDs: [ramp.sourceRoadID],
                                message: "一条匝道源道路包含互不连通的片段。"
                            )
                        )
                    }
                }

                let startRelation = validate(
                    terminal: ramp.start,
                    role: .start,
                    ramp: ramp,
                    interchange: interchange,
                    allowedHostIDs: allowedHostIDs,
                    sourceEdges: sourceEdges,
                    network: network,
                    issues: &issues
                )
                let endRelation = validate(
                    terminal: ramp.end,
                    role: .end,
                    ramp: ramp,
                    interchange: interchange,
                    allowedHostIDs: allowedHostIDs,
                    sourceEdges: sourceEdges,
                    network: network,
                    issues: &issues
                )

                validateTransition(
                    ramp,
                    interchange: interchange,
                    network: network,
                    issues: &issues
                )
                validateUnmodeledJunctions(
                    ramp,
                    interchange: interchange,
                    network: network,
                    issues: &issues
                )
                validateDirectionReachability(
                    ramp,
                    interchange: interchange,
                    startRelation: startRelation,
                    endRelation: endRelation,
                    network: network,
                    issues: &issues
                )
            }
        }

        return issues.sorted {
            (
                $0.interchangeID.uuidString,
                $0.rampSourceRoadID?.uuidString ?? "",
                $0.terminalRole?.rawValue ?? "",
                $0.kind.rawValue,
                $0.id.uuidString
            ) < (
                $1.interchangeID.uuidString,
                $1.rampSourceRoadID?.uuidString ?? "",
                $1.terminalRole?.rawValue ?? "",
                $1.kind.rawValue,
                $1.id.uuidString
            )
        }
    }

    private static let attachmentTolerance = 1.0

    @discardableResult
    private static func validate(
        terminal: RoadRampTerminal,
        role: RoadRampTerminalRole,
        ramp: RoadRamp,
        interchange: RoadInterchange,
        allowedHostIDs: Set<UUID>,
        sourceEdges: [UUID: [RoadEdge]],
        network: RoadNetwork,
        issues: inout [RoadInterchangeIssue]
    ) -> RoadRelation? {
        let hostEdges = sourceEdges[terminal.hostSourceRoadID, default: []]
        if hostEdges.isEmpty {
            issues.append(
                issue(
                    kind: .missingHostSource,
                    interchange: interchange,
                    ramp: ramp,
                    role: role,
                    relatedSourceRoadIDs: [terminal.hostSourceRoadID],
                    point: terminal.lastKnownPoint,
                    message: "匝道端点的宿主道路不存在。"
                )
            )
        }

        if !allowedHostIDs.contains(terminal.hostSourceRoadID)
            || terminal.hostSourceRoadID == ramp.sourceRoadID {
            issues.append(
                issue(
                    kind: .unmodeledJunction,
                    interchange: interchange,
                    ramp: ramp,
                    role: role,
                    relatedSourceRoadIDs: [
                        ramp.sourceRoadID,
                        terminal.hostSourceRoadID,
                    ],
                    point: terminal.lastKnownPoint,
                    message: "匝道端点只能连接锚点道路或同一立交中的另一条匝道。"
                )
            )
        }

        if hostEdges.contains(where: { $0.kind == .railway }) {
            issues.append(
                issue(
                    kind: .unsupportedRailwayHost,
                    interchange: interchange,
                    ramp: ramp,
                    role: role,
                    relatedSourceRoadIDs: [terminal.hostSourceRoadID],
                    point: terminal.lastKnownPoint,
                    message: "铁路暂不能作为匝道宿主道路。"
                )
            )
        }
        if terminal.level == .tunnel
            || hostEdges.contains(where: {
                $0.structure == .tunnel
                    && polylineDistance(
                        from: terminal.lastKnownPoint,
                        to: $0.points
                    ) <= attachmentTolerance
            }) {
            issues.append(
                issue(
                    kind: .unsupportedTunnelHost,
                    interchange: interchange,
                    ramp: ramp,
                    role: role,
                    relatedSourceRoadIDs: [terminal.hostSourceRoadID],
                    point: terminal.lastKnownPoint,
                    message: "隧道暂不能作为匝道端点宿主。"
                )
            )
        }

        let relatedRelations = network.relations.filter { relation in
            Set([relation.firstRoadID, relation.secondRoadID])
                == Set([ramp.sourceRoadID, terminal.hostSourceRoadID])
                && relation.point.distance(to: terminal.lastKnownPoint)
                    <= attachmentTolerance
        }
        let explicit = relatedRelations.first { relation in
            relation.kind == .interchangeRampConnection
                && relation.interchangeID == interchange.id
                && relation.rampSourceRoadID == ramp.sourceRoadID
                && relation.rampTerminalRole == role
        }

        var geometryMatches = terminal.normalizedChainage >= 0
            && terminal.normalizedChainage <= 1
        if let hostPolyline = stitchedPolyline(
            edges: hostEdges,
            network: network
        ), let expectedHostPoint = point(
            on: hostPolyline,
            atNormalizedChainage: terminal.normalizedChainage
        ) {
            geometryMatches = geometryMatches
                && expectedHostPoint.distance(to: terminal.lastKnownPoint)
                    <= attachmentTolerance
        } else if !hostEdges.isEmpty {
            geometryMatches = false
        }
        let rampEdges = sourceEdges[ramp.sourceRoadID, default: []]
        if let rampPolyline = stitchedPolyline(edges: rampEdges, network: network) {
            let expectedRampPoint = role == .start
                ? rampPolyline.first
                : rampPolyline.last
            geometryMatches = geometryMatches
                && (expectedRampPoint?.distance(to: terminal.lastKnownPoint)
                    ?? .infinity) <= attachmentTolerance
        } else if !rampEdges.isEmpty {
            geometryMatches = false
        }

        if let explicit, geometryMatches {
            return explicit
        }

        let hasLevelMismatch = relatedRelations.contains { relation in
            level(
                for: ramp.sourceRoadID,
                in: relation
            ) != terminal.level
                || level(
                    for: terminal.hostSourceRoadID,
                    in: relation
                ) != terminal.level
                || relation.kind == .gradeSeparatedCrossing
        }
        if hasLevelMismatch {
            issues.append(
                issue(
                    kind: .terminalLevelMismatch,
                    interchange: interchange,
                    ramp: ramp,
                    role: role,
                    relatedSourceRoadIDs: [
                        ramp.sourceRoadID,
                        terminal.hostSourceRoadID,
                    ],
                    point: terminal.lastKnownPoint,
                    message: "匝道端点与宿主道路不在声明的道路层级。"
                )
            )
        } else {
            issues.append(
                issue(
                    kind: .terminalDetached,
                    interchange: interchange,
                    ramp: ramp,
                    role: role,
                    relatedSourceRoadIDs: [
                        ramp.sourceRoadID,
                        terminal.hostSourceRoadID,
                    ],
                    point: terminal.lastKnownPoint,
                    message: "匝道端点未在声明里程处连接宿主道路。"
                )
            )
        }
        return nil
    }

    private static func validateTransition(
        _ ramp: RoadRamp,
        interchange: RoadInterchange,
        network: RoadNetwork,
        issues: inout [RoadInterchangeIssue]
    ) {
        let transitionRelations = network.relations.filter {
            $0.kind == .structureTransition
                && $0.firstRoadID == ramp.sourceRoadID
                && $0.secondRoadID == ramp.sourceRoadID
        }
        let isValid: Bool
        if let transition = ramp.transition {
            let levelsMatch = transition.fromLevel == ramp.start.level
                && transition.toLevel == ramp.end.level
                && transition.fromLevel != transition.toLevel
            let fractionIsValid = transition.chainageFraction > 0
                && transition.chainageFraction < 1
            let expectedPoint = stitchedPolyline(
                edges: network.edges.filter {
                    $0.sourceRoadID == ramp.sourceRoadID
                },
                network: network
            ).flatMap {
                point(
                    on: $0,
                    atNormalizedChainage: transition.chainageFraction
                )
            }
            let relationMatches = expectedPoint.map { expectedPoint in
                transitionRelations.contains { relation in
                    Set([relation.firstLevel, relation.secondLevel])
                        == Set([transition.fromLevel, transition.toLevel])
                        && relation.point.distance(to: expectedPoint)
                            <= attachmentTolerance
                }
            } ?? false
            isValid = levelsMatch && fractionIsValid && relationMatches
        } else {
            isValid = ramp.start.level == ramp.end.level
                && transitionRelations.isEmpty
        }
        guard !isValid else { return }
        issues.append(
            issue(
                kind: .invalidTransition,
                interchange: interchange,
                ramp: ramp,
                relatedSourceRoadIDs: [ramp.sourceRoadID],
                point: ramp.transition.flatMap { transition in
                    stitchedPolyline(
                        edges: network.edges.filter {
                            $0.sourceRoadID == ramp.sourceRoadID
                        },
                        network: network
                    ).flatMap {
                        point(
                            on: $0,
                            atNormalizedChainage: transition.chainageFraction
                        )
                    }
                },
                message: "匝道层级转换与端点层级或实际结构转换不一致。"
            )
        )
    }

    private static func validateUnmodeledJunctions(
        _ ramp: RoadRamp,
        interchange: RoadInterchange,
        network: RoadNetwork,
        issues: inout [RoadInterchangeIssue]
    ) {
        let terminals: [(RoadRampTerminalRole, RoadRampTerminal)] = [
            (.start, ramp.start),
            (.end, ramp.end),
        ]
        for relation in network.relations where
            relation.firstRoadID == ramp.sourceRoadID
                || relation.secondRoadID == ramp.sourceRoadID {
            guard relation.kind == .atGradeJunction
                || relation.kind == .interchangeRampConnection
                || relation.kind == .sameLevelOverlap
            else { continue }

            let otherRoadID = relation.firstRoadID == ramp.sourceRoadID
                ? relation.secondRoadID
                : relation.firstRoadID
            let isDeclared = terminals.contains { role, terminal in
                terminal.hostSourceRoadID == otherRoadID
                    && terminal.lastKnownPoint.distance(to: relation.point)
                        <= attachmentTolerance
                    && relation.kind == .interchangeRampConnection
                    && relation.interchangeID == interchange.id
                    && relation.rampSourceRoadID == ramp.sourceRoadID
                    && relation.rampTerminalRole == role
            }
            guard !isDeclared else { continue }
            issues.append(
                issue(
                    kind: .unmodeledJunction,
                    interchange: interchange,
                    ramp: ramp,
                    relatedSourceRoadIDs: [ramp.sourceRoadID, otherRoadID],
                    point: relation.point,
                    message: "匝道存在未在立交模型中声明的平面连接。"
                )
            )
        }
    }

    private static func validateDirectionReachability(
        _ ramp: RoadRamp,
        interchange: RoadInterchange,
        startRelation: RoadRelation?,
        endRelation: RoadRelation?,
        network: RoadNetwork,
        issues: inout [RoadInterchangeIssue]
    ) {
        guard let startNodeID = terminalNodeID(
            relation: startRelation,
            rampSourceRoadID: ramp.sourceRoadID,
            network: network
        ), let endNodeID = terminalNodeID(
            relation: endRelation,
            rampSourceRoadID: ramp.sourceRoadID,
            network: network
        ) else {
            return
        }
        let adjacency = directedRampAdjacency(
            sourceRoadID: ramp.sourceRoadID,
            network: network
        )
        let startHostCanArrive = hostPermitsArrival(
            sourceRoadID: ramp.start.hostSourceRoadID,
            at: startNodeID,
            relation: startRelation,
            network: network
        )
        let startHostCanDepart = hostPermitsDeparture(
            sourceRoadID: ramp.start.hostSourceRoadID,
            from: startNodeID,
            relation: startRelation,
            network: network
        )
        let endHostCanArrive = hostPermitsArrival(
            sourceRoadID: ramp.end.hostSourceRoadID,
            at: endNodeID,
            relation: endRelation,
            network: network
        )
        let endHostCanDepart = hostPermitsDeparture(
            sourceRoadID: ramp.end.hostSourceRoadID,
            from: endNodeID,
            relation: endRelation,
            network: network
        )
        let forwardIsReachable = startHostCanArrive
            && reachable(
                from: startNodeID,
                to: endNodeID,
                adjacency: adjacency
            )
            && endHostCanDepart
        let reverseIsReachable = endHostCanArrive
            && reachable(
                from: endNodeID,
                to: startNodeID,
                adjacency: adjacency
            )
            && startHostCanDepart
        let isReachable: Bool
        switch ramp.direction {
        case .forward:
            isReachable = forwardIsReachable
        case .reverse:
            isReachable = reverseIsReachable
        case .bidirectional:
            isReachable = forwardIsReachable && reverseIsReachable
        }
        guard !isReachable else { return }
        issues.append(
            issue(
                kind: .unreachableRampDirection,
                interchange: interchange,
                ramp: ramp,
                relatedSourceRoadIDs: [
                    ramp.sourceRoadID,
                    ramp.start.hostSourceRoadID,
                    ramp.end.hostSourceRoadID,
                ],
                message: "宿主道路与匝道的真实边方向无法形成声明的完整行驶路径。"
            )
        )
    }

    private static func hostPermitsArrival(
        sourceRoadID: UUID,
        at nodeID: UUID,
        relation: RoadRelation?,
        network: RoadNetwork
    ) -> Bool {
        incidentEdges(
            sourceRoadID: sourceRoadID,
            nodeID: nodeID,
            relation: relation,
            network: network
        ).contains { $0.permitsArrival(at: nodeID) }
    }

    private static func hostPermitsDeparture(
        sourceRoadID: UUID,
        from nodeID: UUID,
        relation: RoadRelation?,
        network: RoadNetwork
    ) -> Bool {
        incidentEdges(
            sourceRoadID: sourceRoadID,
            nodeID: nodeID,
            relation: relation,
            network: network
        ).contains { $0.permitsDeparture(from: nodeID) }
    }

    private static func incidentEdges(
        sourceRoadID: UUID,
        nodeID: UUID,
        relation: RoadRelation?,
        network: RoadNetwork
    ) -> [RoadEdge] {
        guard let relation else { return [] }
        var relevantEdgeIDs: Set<UUID> = []
        if relation.firstRoadID == sourceRoadID {
            relevantEdgeIDs.formUnion(relation.firstEdgeIDs)
        }
        if relation.secondRoadID == sourceRoadID {
            relevantEdgeIDs.formUnion(relation.secondEdgeIDs)
        }
        return network.edges.filter {
            relevantEdgeIDs.contains($0.id)
                && $0.sourceRoadID == sourceRoadID
                && ($0.startNodeID == nodeID || $0.endNodeID == nodeID)
        }
    }

    private static func directedRampAdjacency(
        sourceRoadID: UUID,
        network: RoadNetwork
    ) -> [UUID: Set<UUID>] {
        let rampEdges = network.edges.filter { $0.sourceRoadID == sourceRoadID }
        var result: [UUID: Set<UUID>] = [:]
        for edge in rampEdges {
            if edge.permitsDeparture(from: edge.startNodeID) {
                result[edge.startNodeID, default: []].insert(edge.endNodeID)
            }
            if edge.permitsDeparture(from: edge.endNodeID) {
                result[edge.endNodeID, default: []].insert(edge.startNodeID)
            }
        }
        let edgeIDs = Set(rampEdges.map(\.id))
        for relation in network.relations where relation.kind == .structureTransition {
            let transitionEdgeIDs = Set(relation.firstEdgeIDs + relation.secondEdgeIDs)
                .intersection(edgeIDs)
            guard !transitionEdgeIDs.isEmpty else { continue }
            for sourceNodeID in relation.junctionNodeIDs {
                let canArrive = rampEdges.contains {
                    transitionEdgeIDs.contains($0.id)
                        && ($0.startNodeID == sourceNodeID
                            || $0.endNodeID == sourceNodeID)
                        && $0.permitsArrival(at: sourceNodeID)
                }
                guard canArrive else { continue }
                for destinationNodeID in relation.junctionNodeIDs
                where destinationNodeID != sourceNodeID {
                    let canDepart = rampEdges.contains {
                        transitionEdgeIDs.contains($0.id)
                            && ($0.startNodeID == destinationNodeID
                                || $0.endNodeID == destinationNodeID)
                            && $0.permitsDeparture(from: destinationNodeID)
                    }
                    if canDepart {
                        result[sourceNodeID, default: []].insert(destinationNodeID)
                    }
                }
            }
        }
        return result
    }

    private static func reachable(
        from start: UUID,
        to end: UUID,
        adjacency: [UUID: Set<UUID>]
    ) -> Bool {
        if start == end { return true }
        var visited: Set<UUID> = [start]
        var queue = [start]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            for next in adjacency[current, default: []] where visited.insert(next).inserted {
                if next == end { return true }
                queue.append(next)
            }
        }
        return false
    }

    private static func terminalNodeID(
        relation: RoadRelation?,
        rampSourceRoadID: UUID,
        network: RoadNetwork
    ) -> UUID? {
        guard let relation else { return nil }
        let relevantEdgeIDs: Set<UUID>
        if relation.firstRoadID == rampSourceRoadID {
            relevantEdgeIDs = Set(relation.firstEdgeIDs)
        } else {
            relevantEdgeIDs = Set(relation.secondEdgeIDs)
        }
        return relation.junctionNodeIDs.first { nodeID in
            network.edges.contains {
                relevantEdgeIDs.contains($0.id)
                    && ($0.startNodeID == nodeID || $0.endNodeID == nodeID)
            }
        }
    }

    private static func sourceGraph(
        sourceRoadID: UUID,
        edges: [RoadEdge],
        network: RoadNetwork
    ) -> (componentCount: Int, hasBranch: Bool) {
        var adjacency: [UUID: Set<UUID>] = [:]
        for edge in edges {
            adjacency[edge.startNodeID, default: []].insert(edge.endNodeID)
            adjacency[edge.endNodeID, default: []].insert(edge.startNodeID)
        }
        let edgeIDs = Set(edges.map(\.id))
        for relation in network.relations where
            relation.kind == .structureTransition
                && relation.firstRoadID == sourceRoadID
                && relation.secondRoadID == sourceRoadID
                && !Set(relation.firstEdgeIDs + relation.secondEdgeIDs)
                    .intersection(edgeIDs).isEmpty {
            for first in relation.junctionNodeIDs {
                for second in relation.junctionNodeIDs where first != second {
                    adjacency[first, default: []].insert(second)
                }
            }
        }
        let hasBranch = adjacency.values.contains { $0.count > 2 }
        var remaining = Set(adjacency.keys)
        var componentCount = 0
        while let start = remaining.first {
            componentCount += 1
            var queue = [start]
            remaining.remove(start)
            while !queue.isEmpty {
                let current = queue.removeFirst()
                for next in adjacency[current, default: []]
                where remaining.remove(next) != nil {
                    queue.append(next)
                }
            }
        }
        return (componentCount, hasBranch)
    }

    private static func stitchedPolyline(
        edges: [RoadEdge],
        network: RoadNetwork
    ) -> [RoadPoint]? {
        guard !edges.isEmpty else { return nil }
        if edges.count == 1 { return edges[0].points }
        var remaining = edges.sorted { $0.id.uuidString < $1.id.uuidString }
        let startIndex = remaining.indices.first { candidateIndex in
            let candidate = remaining[candidateIndex]
            return !remaining.indices.contains { otherIndex in
                otherIndex != candidateIndex
                    && canFollow(
                        remaining[otherIndex],
                        with: candidate,
                        network: network
                    )
            }
        } ?? remaining.startIndex
        var ordered = [remaining.remove(at: startIndex)]
        while !remaining.isEmpty {
            guard let current = ordered.last else { return nil }
            let candidates = remaining.indices.filter {
                canFollow(current, with: remaining[$0], network: network)
            }
            guard let nextIndex = candidates.min(by: {
                remaining[$0].id.uuidString < remaining[$1].id.uuidString
            }) else { return nil }
            ordered.append(remaining.remove(at: nextIndex))
        }
        var result = ordered[0].points
        for edge in ordered.dropFirst() {
            result.append(contentsOf: edge.points.dropFirst())
        }
        return removingConsecutiveDuplicates(result)
    }

    private static func canFollow(
        _ first: RoadEdge,
        with second: RoadEdge,
        network: RoadNetwork
    ) -> Bool {
        if first.endNodeID == second.startNodeID { return true }
        guard (
            first.points.last?.distance(
                to: second.points.first ?? RoadPoint(x: 0, y: 0)
            ) ?? .infinity
        ) <= attachmentTolerance
        else { return false }
        return network.relations.contains {
            $0.kind == .structureTransition
                && $0.junctionNodeIDs.contains(first.endNodeID)
                && $0.junctionNodeIDs.contains(second.startNodeID)
                && $0.firstRoadID == first.sourceRoadID
                && $0.secondRoadID == first.sourceRoadID
        }
    }

    private static func point(
        on polyline: [RoadPoint],
        atNormalizedChainage normalizedChainage: Double
    ) -> RoadPoint? {
        guard normalizedChainage.isFinite,
              let first = polyline.first,
              polyline.count >= 2
        else { return polyline.first }
        let lengths = zip(polyline, polyline.dropFirst()).map { $0.distance(to: $1) }
        let totalLength = lengths.reduce(0, +)
        guard totalLength > 1e-12 else { return first }
        let target = min(1, max(0, normalizedChainage)) * totalLength
        var traversed = 0.0
        for (index, length) in lengths.enumerated() {
            if target <= traversed + length || index == lengths.count - 1 {
                guard length > 1e-12 else { return polyline[index] }
                let fraction = min(1, max(0, (target - traversed) / length))
                return polyline[index] + (polyline[index + 1] - polyline[index]) * fraction
            }
            traversed += length
        }
        return polyline.last
    }

    private static func removingConsecutiveDuplicates(
        _ points: [RoadPoint]
    ) -> [RoadPoint] {
        var result: [RoadPoint] = []
        for point in points {
            if result.last?.distance(to: point) ?? .infinity > 1e-9 {
                result.append(point)
            }
        }
        return result
    }

    private static func polylineDistance(
        from point: RoadPoint,
        to polyline: [RoadPoint]
    ) -> Double {
        guard polyline.count >= 2 else {
            return polyline.first?.distance(to: point) ?? .infinity
        }
        return zip(polyline, polyline.dropFirst()).reduce(.infinity) { best, pair in
            let delta = pair.1 - pair.0
            let squaredLength = delta.x * delta.x + delta.y * delta.y
            let fraction: Double
            if squaredLength <= 1e-12 {
                fraction = 0
            } else {
                let offset = point - pair.0
                fraction = min(
                    1,
                    max(0, (offset.x * delta.x + offset.y * delta.y) / squaredLength)
                )
            }
            return min(best, point.distance(to: pair.0 + delta * fraction))
        }
    }

    private static func level(
        for sourceRoadID: UUID,
        in relation: RoadRelation
    ) -> RoadLevel? {
        if relation.firstRoadID == sourceRoadID { return relation.firstLevel }
        if relation.secondRoadID == sourceRoadID { return relation.secondLevel }
        return nil
    }

    private static func inferredRampSourceID(
        for ramp: RoadRamp,
        in network: RoadNetwork,
        excluding excludedSourceIDs: Set<UUID>
    ) -> UUID? {
        func candidates(at terminal: RoadRampTerminal) -> Set<UUID> {
            Set(network.relations.flatMap { relation -> [UUID] in
                guard relation.point.distance(to: terminal.lastKnownPoint)
                    <= attachmentTolerance else { return [] }
                let roadIDs = [relation.firstRoadID, relation.secondRoadID]
                guard roadIDs.contains(terminal.hostSourceRoadID) else { return [] }
                return roadIDs.filter {
                    $0 != terminal.hostSourceRoadID
                        && !excludedSourceIDs.contains($0)
                }
            })
        }
        return candidates(at: ramp.start)
            .intersection(candidates(at: ramp.end))
            .sorted { $0.uuidString < $1.uuidString }
            .first
    }

    private static func issue(
        kind: RoadInterchangeDiagnosticKind,
        interchange: RoadInterchange,
        ramp: RoadRamp? = nil,
        role: RoadRampTerminalRole? = nil,
        relatedSourceRoadIDs: Set<UUID> = [],
        point: RoadPoint? = nil,
        message: String
    ) -> RoadInterchangeIssue {
        let related = relatedSourceRoadIDs.sorted { $0.uuidString < $1.uuidString }
        return RoadInterchangeIssue(
            id: stableIssueID(
                [
                    kind.rawValue,
                    interchange.id.uuidString,
                    ramp?.sourceRoadID.uuidString ?? "",
                    role?.rawValue ?? "",
                    related.map(\.uuidString).joined(separator: ","),
                    point.map { String(format: "%.6f,%.6f", $0.x, $0.y) } ?? "",
                ]
            ),
            kind: kind,
            interchangeID: interchange.id,
            rampSourceRoadID: ramp?.sourceRoadID,
            terminalRole: role,
            relatedSourceRoadIDs: relatedSourceRoadIDs,
            point: point,
            message: message
        )
    }

    private static func stableIssueID(_ components: [String]) -> UUID {
        let bytes = components.joined(separator: "\u{1F}").utf8
        var first: UInt64 = 0xcbf29ce484222325
        var second: UInt64 = 0x84222325cbf29ce4
        for byte in bytes {
            first ^= UInt64(byte)
            first = first &* 0x100000001b3
            second ^= UInt64(byte) &+ (first >> 32)
            second = second &* 0x100000001b3
        }
        var values = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            values[index] = UInt8(truncatingIfNeeded: first >> UInt64((7 - index) * 8))
            values[index + 8] = UInt8(
                truncatingIfNeeded: second >> UInt64((7 - index) * 8)
            )
        }
        values[6] = (values[6] & 0x0F) | 0x50
        values[8] = (values[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                values[0], values[1], values[2], values[3],
                values[4], values[5], values[6], values[7],
                values[8], values[9], values[10], values[11],
                values[12], values[13], values[14], values[15]
            )
        )
    }
}
