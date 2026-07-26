import Foundation

/// Operational access layered on top of a road's geometric direction and
/// routing priority.
public enum RoadTrafficAccess: String, Codable, CaseIterable, Sendable {
    case open
    case closed
}

/// Traffic policy attached to one logical source road. Direction and routing
/// priority remain authoritative on `RoadSegment` / `RoadEdge`.
public struct RoadSourceTrafficRule: Identifiable, Codable, Hashable, Sendable {
    public var sourceRoadID: UUID
    public var speedLimitKilometersPerHour: Double
    public var access: RoadTrafficAccess

    public var id: UUID { sourceRoadID }

    public init(
        sourceRoadID: UUID,
        speedLimitKilometersPerHour: Double = 50,
        access: RoadTrafficAccess = .open
    ) {
        self.sourceRoadID = sourceRoadID
        self.speedLimitKilometersPerHour = speedLimitKilometersPerHour
        self.access = access
    }

    public static func defaultRule(
        sourceRoadID: UUID,
        kind: RoadKind
    ) -> RoadSourceTrafficRule {
        RoadSourceTrafficRule(
            sourceRoadID: sourceRoadID,
            speedLimitKilometersPerHour: defaultSpeedLimit(for: kind)
        )
    }

    public static func defaultSpeedLimit(for kind: RoadKind) -> Double {
        switch kind {
        case .motorway: 100
        case .arterial: 60
        case .street: 40
        case .railway: 120
        }
    }
}

/// A node-level movement rule. Source-road identifiers keep the rule stable
/// when topology rebuilds split a logical road into different edge fragments.
public struct RoadTurnRestriction: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var fromSourceRoadID: UUID
    public var viaNodeID: UUID
    public var toSourceRoadID: UUID

    public init(
        id: UUID = UUID(),
        fromSourceRoadID: UUID,
        viaNodeID: UUID,
        toSourceRoadID: UUID
    ) {
        self.id = id
        self.fromSourceRoadID = fromSourceRoadID
        self.viaNodeID = viaNodeID
        self.toSourceRoadID = toSourceRoadID
    }
}

/// Persistable traffic policy independent from `RoadProject` schema version.
/// Empty arrays mean that every source uses its road-kind default and there
/// are no turn restrictions.
public struct RoadTrafficRuleSet: Codable, Hashable, Sendable {
    public var sourceRules: [RoadSourceTrafficRule]
    public var turnRestrictions: [RoadTurnRestriction]

    public init(
        sourceRules: [RoadSourceTrafficRule] = [],
        turnRestrictions: [RoadTurnRestriction] = []
    ) {
        self.sourceRules = sourceRules
        self.turnRestrictions = turnRestrictions
    }

    private enum CodingKeys: String, CodingKey {
        case sourceRules, turnRestrictions
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sourceRules = try values.decodeIfPresent(
            [RoadSourceTrafficRule].self,
            forKey: .sourceRules
        ) ?? []
        turnRestrictions = try values.decodeIfPresent(
            [RoadTurnRestriction].self,
            forKey: .turnRestrictions
        ) ?? []
    }

    public func effectiveRule(
        for sourceRoadID: UUID,
        kind: RoadKind
    ) -> RoadSourceTrafficRule {
        sourceRules.first { $0.sourceRoadID == sourceRoadID }
            ?? .defaultRule(sourceRoadID: sourceRoadID, kind: kind)
    }

    public func allowsTraversal(
        of sourceRoadID: UUID,
        kind: RoadKind
    ) -> Bool {
        switch effectiveRule(for: sourceRoadID, kind: kind).access {
        case .open:
            true
        case .closed:
            false
        }
    }

    /// Evaluates the movement using both persisted restrictions and the
    /// current directed topology. Closed roads never permit a movement.
    public func allowsTurn(
        from fromSourceRoadID: UUID,
        via viaNodeID: UUID,
        to toSourceRoadID: UUID,
        in network: RoadNetwork
    ) -> Bool {
        guard hasArrival(
            sourceRoadID: fromSourceRoadID,
            at: viaNodeID,
            in: network
        ), hasDeparture(
            sourceRoadID: toSourceRoadID,
            from: viaNodeID,
            in: network
        ), access(for: fromSourceRoadID, in: network) != .closed,
           access(for: toSourceRoadID, in: network) != .closed
        else {
            return false
        }

        return !turnRestrictions.contains {
            $0.fromSourceRoadID == fromSourceRoadID
                && $0.viaNodeID == viaNodeID
                && $0.toSourceRoadID == toSourceRoadID
        }
    }

    /// Removes references made stale by deleted roads, deleted nodes, or a
    /// topology rebuild that detached a source from the referenced node.
    /// Directionally impossible rules are retained so validation can surface
    /// them instead of silently deleting user policy.
    public func removingStaleReferences(
        in network: RoadNetwork
    ) -> RoadTrafficRuleSet {
        let availableSourceRoadIDs = Set(network.edges.map(\.sourceRoadID))
        let availableNodeIDs = Set(network.nodes.map(\.id))
        let retainedSourceRules = sourceRules.filter {
            availableSourceRoadIDs.contains($0.sourceRoadID)
        }
        let retainedTurnRestrictions = turnRestrictions.filter { restriction in
            availableSourceRoadIDs.contains(restriction.fromSourceRoadID)
                && availableSourceRoadIDs.contains(restriction.toSourceRoadID)
                && availableNodeIDs.contains(restriction.viaNodeID)
                && isIncident(
                    sourceRoadID: restriction.fromSourceRoadID,
                    at: restriction.viaNodeID,
                    in: network
                )
                && isIncident(
                    sourceRoadID: restriction.toSourceRoadID,
                    at: restriction.viaNodeID,
                    in: network
                )
        }
        return RoadTrafficRuleSet(
            sourceRules: retainedSourceRules,
            turnRestrictions: retainedTurnRestrictions
        )
    }

    private func access(
        for sourceRoadID: UUID,
        in network: RoadNetwork
    ) -> RoadTrafficAccess? {
        guard let edge = network.edges.first(where: {
            $0.sourceRoadID == sourceRoadID
        }) else {
            return nil
        }
        return effectiveRule(for: sourceRoadID, kind: edge.kind).access
    }
}

public enum RoadTrafficRuleDiagnosticKind: String, Codable, CaseIterable, Sendable {
    case staleSourceRule
    case invalidSpeedLimit
    case duplicateSourceRule
    case staleTurnSource
    case staleTurnNode
    case sourceNotIncidentToTurnNode
    case directionallyImpossibleTurn
    case duplicateTurnRestriction
}

public struct RoadTrafficRuleIssue: Identifiable, Codable, Hashable, Sendable {
    public var kind: RoadTrafficRuleDiagnosticKind
    public var sourceRoadIDs: Set<UUID>
    public var nodeID: UUID?
    public var turnRestrictionID: UUID?
    public var message: String

    public var id: String {
        [
            kind.rawValue,
            sourceRoadIDs.map(\.uuidString).sorted().joined(separator: ","),
            nodeID?.uuidString ?? "",
            turnRestrictionID?.uuidString ?? "",
        ].joined(separator: "|")
    }

    public init(
        kind: RoadTrafficRuleDiagnosticKind,
        sourceRoadIDs: Set<UUID> = [],
        nodeID: UUID? = nil,
        turnRestrictionID: UUID? = nil,
        message: String
    ) {
        self.kind = kind
        self.sourceRoadIDs = sourceRoadIDs
        self.nodeID = nodeID
        self.turnRestrictionID = turnRestrictionID
        self.message = message
    }
}

public enum RoadTrafficRuleValidator {
    public static func evaluate(
        _ rules: RoadTrafficRuleSet,
        in network: RoadNetwork
    ) -> [RoadTrafficRuleIssue] {
        let availableSourceRoadIDs = Set(network.edges.map(\.sourceRoadID))
        let availableNodeIDs = Set(network.nodes.map(\.id))
        var issues: [RoadTrafficRuleIssue] = []

        let sourceRuleGroups = Dictionary(
            grouping: rules.sourceRules,
            by: \.sourceRoadID
        )
        for sourceRule in rules.sourceRules {
            if !availableSourceRoadIDs.contains(sourceRule.sourceRoadID) {
                issues.append(
                    RoadTrafficRuleIssue(
                        kind: .staleSourceRule,
                        sourceRoadIDs: [sourceRule.sourceRoadID],
                        message: "道路交通规则引用的源道路不存在。"
                    )
                )
            }
            if !sourceRule.speedLimitKilometersPerHour.isFinite
                || sourceRule.speedLimitKilometersPerHour <= 0
                || sourceRule.speedLimitKilometersPerHour > 300 {
                issues.append(
                    RoadTrafficRuleIssue(
                        kind: .invalidSpeedLimit,
                        sourceRoadIDs: [sourceRule.sourceRoadID],
                        message: "道路限速必须在 0 到 300 km/h 之间。"
                    )
                )
            }
        }
        for (sourceRoadID, group) in sourceRuleGroups where group.count > 1 {
            issues.append(
                RoadTrafficRuleIssue(
                    kind: .duplicateSourceRule,
                    sourceRoadIDs: [sourceRoadID],
                    message: "同一源道路存在重复交通规则。"
                )
            )
        }

        let restrictionGroups = Dictionary(
            grouping: rules.turnRestrictions
        ) {
            TurnRestrictionKey(
                fromSourceRoadID: $0.fromSourceRoadID,
                viaNodeID: $0.viaNodeID,
                toSourceRoadID: $0.toSourceRoadID
            )
        }
        for restriction in rules.turnRestrictions {
            let sourceRoadIDs: Set<UUID> = [
                restriction.fromSourceRoadID,
                restriction.toSourceRoadID,
            ]
            let missingSourceRoadIDs = sourceRoadIDs.subtracting(
                availableSourceRoadIDs
            )
            if !missingSourceRoadIDs.isEmpty {
                issues.append(
                    RoadTrafficRuleIssue(
                        kind: .staleTurnSource,
                        sourceRoadIDs: missingSourceRoadIDs,
                        nodeID: restriction.viaNodeID,
                        turnRestrictionID: restriction.id,
                        message: "转向限制引用的源道路不存在。"
                    )
                )
            }
            guard availableNodeIDs.contains(restriction.viaNodeID) else {
                issues.append(
                    RoadTrafficRuleIssue(
                        kind: .staleTurnNode,
                        sourceRoadIDs: sourceRoadIDs,
                        nodeID: restriction.viaNodeID,
                        turnRestrictionID: restriction.id,
                        message: "转向限制引用的节点不存在。"
                    )
                )
                continue
            }
            guard missingSourceRoadIDs.isEmpty else { continue }

            let fromIsIncident = isIncident(
                sourceRoadID: restriction.fromSourceRoadID,
                at: restriction.viaNodeID,
                in: network
            )
            let toIsIncident = isIncident(
                sourceRoadID: restriction.toSourceRoadID,
                at: restriction.viaNodeID,
                in: network
            )
            if !fromIsIncident || !toIsIncident {
                issues.append(
                    RoadTrafficRuleIssue(
                        kind: .sourceNotIncidentToTurnNode,
                        sourceRoadIDs: sourceRoadIDs,
                        nodeID: restriction.viaNodeID,
                        turnRestrictionID: restriction.id,
                        message: "转向限制中的道路未连接到声明节点。"
                    )
                )
                continue
            }
            if !hasArrival(
                sourceRoadID: restriction.fromSourceRoadID,
                at: restriction.viaNodeID,
                in: network
            ) || !hasDeparture(
                sourceRoadID: restriction.toSourceRoadID,
                from: restriction.viaNodeID,
                in: network
            ) {
                issues.append(
                    RoadTrafficRuleIssue(
                        kind: .directionallyImpossibleTurn,
                        sourceRoadIDs: sourceRoadIDs,
                        nodeID: restriction.viaNodeID,
                        turnRestrictionID: restriction.id,
                        message: "转向限制与道路真实行驶方向不一致。"
                    )
                )
            }
        }

        for (_, group) in restrictionGroups where group.count > 1 {
            for restriction in group {
                issues.append(
                    RoadTrafficRuleIssue(
                        kind: .duplicateTurnRestriction,
                        sourceRoadIDs: [
                            restriction.fromSourceRoadID,
                            restriction.toSourceRoadID,
                        ],
                        nodeID: restriction.viaNodeID,
                        turnRestrictionID: restriction.id,
                        message: "存在重复的转向限制。"
                    )
                )
            }
        }

        return issues.sorted { $0.id < $1.id }
    }
}

private struct TurnRestrictionKey: Hashable {
    var fromSourceRoadID: UUID
    var viaNodeID: UUID
    var toSourceRoadID: UUID
}

private func isIncident(
    sourceRoadID: UUID,
    at nodeID: UUID,
    in network: RoadNetwork
) -> Bool {
    network.edges.contains {
        $0.sourceRoadID == sourceRoadID
            && ($0.startNodeID == nodeID || $0.endNodeID == nodeID)
    }
}

private func hasArrival(
    sourceRoadID: UUID,
    at nodeID: UUID,
    in network: RoadNetwork
) -> Bool {
    network.edges.contains {
        $0.sourceRoadID == sourceRoadID
            && ($0.startNodeID == nodeID || $0.endNodeID == nodeID)
            && $0.permitsArrival(at: nodeID)
    }
}

private func hasDeparture(
    sourceRoadID: UUID,
    from nodeID: UUID,
    in network: RoadNetwork
) -> Bool {
    network.edges.contains {
        $0.sourceRoadID == sourceRoadID
            && ($0.startNodeID == nodeID || $0.endNodeID == nodeID)
            && $0.permitsDeparture(from: nodeID)
    }
}
