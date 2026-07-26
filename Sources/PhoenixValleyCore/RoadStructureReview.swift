import Foundation

public extension RoadStructureType {
    init(defaultFor level: RoadLevel) {
        switch level {
        case .ground:
            self = .ground
        case .tunnel:
            self = .tunnel
        case .elevated:
            self = .elevated
        }
    }

    var renderLevel: RoadLevel {
        switch self {
        case .ground:
            .ground
        case .bridge, .elevated:
            .elevated
        case .tunnel:
            .tunnel
        }
    }

    var displayName: String {
        switch self {
        case .ground:
            "地面"
        case .bridge:
            "桥梁"
        case .tunnel:
            "隧道"
        case .elevated:
            "高架"
        }
    }
}

public enum RoadStructureReviewStatus: String, Codable, Hashable, Sendable {
    case pending
    case applied
    case rejected
}

public struct RoadStructureReviewRecord: Identifiable, Codable, Hashable, Sendable {
    public var plan: AutoStructurePlan
    public var decisions: [AutoStructureDecision]
    public var status: RoadStructureReviewStatus
    public var createdAt: Date
    public var reviewedAt: Date?

    public var id: UUID { plan.sourceRoadID }

    public init(
        plan: AutoStructurePlan,
        decisions: [AutoStructureDecision]? = nil,
        status: RoadStructureReviewStatus = .pending,
        createdAt: Date = .now,
        reviewedAt: Date? = nil
    ) {
        self.plan = plan
        self.decisions = decisions ?? plan.candidates.map {
            AutoStructureDecision(candidateID: $0.id, resolution: .accept)
        }
        self.status = status
        self.createdAt = createdAt
        self.reviewedAt = reviewedAt
    }

    public var resolvedSpans: [ResolvedRoadStructureSpan] {
        plan.resolving(decisions)
    }
}
