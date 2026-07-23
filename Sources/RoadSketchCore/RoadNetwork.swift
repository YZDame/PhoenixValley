import Foundation

public enum RoadKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case motorway
    case arterial
    case street
    case railway

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .motorway: "高速"
        case .arterial: "主干道"
        case .street: "街道"
        case .railway: "铁路"
        }
    }
}

public enum RoadLevel: Int, Codable, CaseIterable, Sendable {
    case tunnel = -1
    case ground = 0
    case elevated = 1
}

public enum MapTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case topographic
    case planning
    case ink

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .topographic: "地形图"
        case .planning: "规划图"
        case .ink: "墨线图"
        }
    }
}

public struct RoadSegment: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var kind: RoadKind
    public var level: RoadLevel
    public var points: [RoadPoint]

    public init(
        id: UUID = UUID(),
        kind: RoadKind,
        level: RoadLevel = .ground,
        points: [RoadPoint]
    ) {
        self.id = id
        self.kind = kind
        self.level = level
        self.points = points
    }
}

public struct TerrainLayout: Codable, Hashable, Sendable {
    public static let currentGenerationVersion = 3

    public var seed: UInt64
    public var shoreline: [RoadPoint]
    public var generationVersion: Int
    public var gridWidth: Int
    public var gridHeight: Int
    public var elevations: [UInt16]
    public var waterLevel: Double

    public init(
        seed: UInt64,
        shoreline: [RoadPoint],
        generationVersion: Int = Self.currentGenerationVersion,
        gridWidth: Int = 0,
        gridHeight: Int = 0,
        elevations: [UInt16] = [],
        waterLevel: Double = 0.2
    ) {
        self.seed = seed
        self.shoreline = shoreline
        self.generationVersion = generationVersion
        self.gridWidth = gridWidth
        self.gridHeight = gridHeight
        self.elevations = elevations
        self.waterLevel = waterLevel
    }

    public var hasElevationData: Bool {
        gridWidth >= 2 && gridHeight >= 2 && elevations.count == gridWidth * gridHeight
    }

    public func normalizedElevation(at point: RoadPoint) -> Double {
        guard hasElevationData else { return 0.35 }

        let gridX = min(Double(gridWidth - 1), max(0, point.x / 1600 * Double(gridWidth - 1)))
        let gridY = min(Double(gridHeight - 1), max(0, point.y / 1200 * Double(gridHeight - 1)))
        let x0 = Int(gridX.rounded(.down))
        let y0 = Int(gridY.rounded(.down))
        let x1 = min(gridWidth - 1, x0 + 1)
        let y1 = min(gridHeight - 1, y0 + 1)
        let fx = gridX - Double(x0)
        let fy = gridY - Double(y0)

        func value(_ x: Int, _ y: Int) -> Double {
            Double(elevations[y * gridWidth + x]) / Double(UInt16.max)
        }

        let top = value(x0, y0) * (1 - fx) + value(x1, y0) * fx
        let bottom = value(x0, y1) * (1 - fx) + value(x1, y1) * fx
        return top * (1 - fy) + bottom * fy
    }

    private enum CodingKeys: String, CodingKey {
        case seed, shoreline, generationVersion, gridWidth, gridHeight, elevations, waterLevel
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        seed = try values.decode(UInt64.self, forKey: .seed)
        shoreline = try values.decode([RoadPoint].self, forKey: .shoreline)
        generationVersion = try values.decodeIfPresent(Int.self, forKey: .generationVersion) ?? 1
        gridWidth = try values.decodeIfPresent(Int.self, forKey: .gridWidth) ?? 0
        gridHeight = try values.decodeIfPresent(Int.self, forKey: .gridHeight) ?? 0
        elevations = try values.decodeIfPresent([UInt16].self, forKey: .elevations) ?? []
        waterLevel = try values.decodeIfPresent(Double.self, forKey: .waterLevel) ?? 0.2
    }
}

public struct RoadProject: Identifiable, Codable, Hashable, Sendable {
    public static let currentFormatVersion = 3

    public let id: UUID
    public var formatVersion: Int
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var terrain: TerrainLayout
    public var roads: [RoadSegment]
    public var theme: MapTheme
    public var showsContours: Bool
    public var showsGrid: Bool
    public var groupID: UUID?

    public init(
        id: UUID = UUID(),
        name: String = "未命名地图",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        terrain: TerrainLayout = TerrainGenerator.generate(seed: 1),
        roads: [RoadSegment] = [],
        theme: MapTheme = .planning,
        showsContours: Bool = true,
        showsGrid: Bool = true,
        groupID: UUID? = nil
    ) {
        self.id = id
        self.formatVersion = Self.currentFormatVersion
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.terrain = terrain
        self.roads = roads
        self.theme = theme
        self.showsContours = showsContours
        self.showsGrid = showsGrid
        self.groupID = groupID
    }

    private enum CodingKeys: String, CodingKey {
        case id, formatVersion, name, createdAt, updatedAt, terrain, roads
        case theme, showsContours, showsGrid, groupID
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        formatVersion = try values.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        name = try values.decode(String.self, forKey: .name)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        terrain = try values.decode(TerrainLayout.self, forKey: .terrain)
        roads = try values.decodeIfPresent([RoadSegment].self, forKey: .roads) ?? []
        theme = try values.decodeIfPresent(MapTheme.self, forKey: .theme) ?? .planning
        showsContours = try values.decodeIfPresent(Bool.self, forKey: .showsContours) ?? true
        showsGrid = try values.decodeIfPresent(Bool.self, forKey: .showsGrid) ?? true
        groupID = try values.decodeIfPresent(UUID.self, forKey: .groupID)
    }
}
