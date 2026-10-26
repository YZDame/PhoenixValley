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

    public var defaultPriority: RoadPriority {
        switch self {
        case .motorway: .motorway
        case .arterial: .arterial
        case .street: .local
        case .railway: .railway
        }
    }
}

public enum RoadLevel: Int, Codable, CaseIterable, Sendable {
    case tunnel = -1
    case ground = 0
    case elevated = 1
}

public enum RoadDirection: String, Codable, CaseIterable, Sendable {
    case bidirectional
    case forward
    case reverse
}

public enum RoadPriority: Int, Codable, CaseIterable, Comparable, Sendable {
    case local = 100
    case collector = 200
    case arterial = 300
    case motorway = 400
    case railway = 500

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum MapTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case topographic
    case planning
    case ink
    case coastal
    case midnight
    case forest

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .topographic: "雾岚地形"
        case .planning: "绢纸规划"
        case .ink: "石墨线稿"
        case .coastal: "浅湾海岸"
        case .midnight: "深蓝夜色"
        case .forest: "鼠尾草林野"
        }
    }
}

public struct MapLayerVisibility: Codable, Hashable, Sendable {
    public var showsTerrain: Bool
    public var showsHydrology: Bool
    public var showsWatersheds: Bool
    public var hiddenRoadKinds: Set<RoadKind>

    public init(
        showsTerrain: Bool = true,
        showsHydrology: Bool = true,
        showsWatersheds: Bool = false,
        hiddenRoadKinds: Set<RoadKind> = []
    ) {
        self.showsTerrain = showsTerrain
        self.showsHydrology = showsHydrology
        self.showsWatersheds = showsWatersheds
        self.hiddenRoadKinds = hiddenRoadKinds
    }

    public func isVisible(_ kind: RoadKind) -> Bool {
        !hiddenRoadKinds.contains(kind)
    }

    public mutating func setVisible(_ isVisible: Bool, for kind: RoadKind) {
        if isVisible {
            hiddenRoadKinds.remove(kind)
        } else {
            hiddenRoadKinds.insert(kind)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case showsTerrain, showsHydrology, showsWatersheds, hiddenRoadKinds
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            showsTerrain: try values.decodeIfPresent(Bool.self, forKey: .showsTerrain) ?? true,
            showsHydrology: try values.decodeIfPresent(Bool.self, forKey: .showsHydrology) ?? true,
            showsWatersheds: try values.decodeIfPresent(Bool.self, forKey: .showsWatersheds) ?? false,
            hiddenRoadKinds: try values.decodeIfPresent(
                Set<RoadKind>.self,
                forKey: .hiddenRoadKinds
            ) ?? []
        )
    }
}

public struct MapScale: Codable, Hashable, Sendable {
    public static let canvasWidth = 1_600.0
    public static let canvasHeight = 1_200.0
    public static let standard = MapScale(metersPerPoint: 1)

    public var metersPerPoint: Double

    public init(metersPerPoint: Double = 1) {
        self.metersPerPoint = min(100, max(0.1, metersPerPoint))
    }

    public var widthMeters: Double {
        Self.canvasWidth * metersPerPoint
    }

    public var heightMeters: Double {
        Self.canvasHeight * metersPerPoint
    }

    public func meters(forCanvasDistance distance: Double) -> Double {
        distance * metersPerPoint
    }

    public func canvasDistance(forMeters distance: Double) -> Double {
        distance / metersPerPoint
    }

    private enum CodingKeys: String, CodingKey {
        case metersPerPoint
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            metersPerPoint: try values.decodeIfPresent(
                Double.self,
                forKey: .metersPerPoint
            ) ?? 1
        )
    }
}

public struct RoadSegment: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var kind: RoadKind
    public private(set) var level: RoadLevel
    public private(set) var structure: RoadStructureType
    public var points: [RoadPoint]
    public var direction: RoadDirection
    public var priority: RoadPriority
    public var sourceRoadID: UUID
    public var startNodeID: UUID?
    public var endNodeID: UUID?

    public init(
        id: UUID = UUID(),
        kind: RoadKind,
        level: RoadLevel = .ground,
        structure: RoadStructureType? = nil,
        points: [RoadPoint],
        direction: RoadDirection = .bidirectional,
        priority: RoadPriority? = nil,
        sourceRoadID: UUID? = nil,
        startNodeID: UUID? = nil,
        endNodeID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        let normalizedStructure = structure ?? RoadStructureType(defaultFor: level)
        self.level = normalizedStructure.renderLevel
        self.structure = normalizedStructure
        self.points = points
        self.direction = direction
        self.priority = priority ?? kind.defaultPriority
        self.sourceRoadID = sourceRoadID ?? id
        self.startNodeID = startNodeID
        self.endNodeID = endNodeID
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, level, structure, points, direction, priority, sourceRoadID
        case startNodeID, endNodeID
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(RoadKind.self, forKey: .kind)
        let decodedLevel = try values.decodeIfPresent(RoadLevel.self, forKey: .level) ?? .ground
        structure = try values.decodeIfPresent(RoadStructureType.self, forKey: .structure)
            ?? RoadStructureType(defaultFor: decodedLevel)
        level = structure.renderLevel
        points = try values.decode([RoadPoint].self, forKey: .points)
        direction = try values.decodeIfPresent(RoadDirection.self, forKey: .direction)
            ?? .bidirectional
        priority = try values.decodeIfPresent(RoadPriority.self, forKey: .priority)
            ?? kind.defaultPriority
        sourceRoadID = try values.decodeIfPresent(UUID.self, forKey: .sourceRoadID) ?? id
        startNodeID = try values.decodeIfPresent(UUID.self, forKey: .startNodeID)
        endNodeID = try values.decodeIfPresent(UUID.self, forKey: .endNodeID)
    }

    public mutating func setStructure(_ structure: RoadStructureType) {
        self.structure = structure
        level = structure.renderLevel
    }
}

public enum TerrainScenario: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case island
    case continent
    case coastalCity
    case valley
    case basin
    case mountains
    case hills
    case riverAndLakes

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .island: "海岛"
        case .continent: "大陆"
        case .coastalCity: "海滨城市"
        case .valley: "山谷"
        case .basin: "盆地"
        case .mountains: "山地"
        case .hills: "丘陵"
        case .riverAndLakes: "河流与湖泊"
        }
    }

    public var symbol: String {
        switch self {
        case .island: "water.waves"
        case .continent: "map"
        case .coastalCity: "building.2"
        case .valley: "arrow.down.right.and.arrow.up.left"
        case .basin: "circle.dotted"
        case .mountains: "mountain.2"
        case .hills: "mountain.2.circle"
        case .riverAndLakes: "drop"
        }
    }

    /// Whether the editable-region boundary represents an actual coastline.
    public var hasOceanBoundary: Bool {
        self == .island || self == .coastalCity
    }
}

public struct TerrainLayout: Codable, Hashable, Sendable {
    public static let currentGenerationVersion = 8

    public var seed: UInt64
    public var shoreline: [RoadPoint]
    public var generationVersion: Int
    public var gridWidth: Int
    public var gridHeight: Int
    public var elevations: [UInt16]
    public var waterLevel: Double
    public var scenario: TerrainScenario
    public var hydrology: HydrologyLayout

    public init(
        seed: UInt64,
        shoreline: [RoadPoint],
        generationVersion: Int = Self.currentGenerationVersion,
        gridWidth: Int = 0,
        gridHeight: Int = 0,
        elevations: [UInt16] = [],
        waterLevel: Double = 0.2,
        scenario: TerrainScenario = .island,
        hydrology: HydrologyLayout = .init()
    ) {
        self.seed = seed
        self.shoreline = shoreline
        self.generationVersion = generationVersion
        self.gridWidth = gridWidth
        self.gridHeight = gridHeight
        self.elevations = elevations
        self.waterLevel = waterLevel
        self.scenario = scenario
        self.hydrology = hydrology
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
        case scenario, hydrology
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
        scenario = try values.decodeIfPresent(TerrainScenario.self, forKey: .scenario) ?? .island
        hydrology = try values.decodeIfPresent(HydrologyLayout.self, forKey: .hydrology) ?? .init()
    }
}

public struct RoadProject: Identifiable, Codable, Hashable, Sendable {
    public static let currentFormatVersion = 13

    public let id: UUID
    public var formatVersion: Int
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var terrain: TerrainLayout
    public var roadNetwork: RoadNetwork
    public var interchanges: [RoadInterchange]
    public var trafficRules: RoadTrafficRuleSet
    public var structureReviews: [RoadStructureReviewRecord]
    public var engineeringStructures: [RoadEngineeringStructure]
    public var theme: MapTheme
    public var showsContours: Bool
    public var showsGrid: Bool
    public var layerVisibility: MapLayerVisibility
    public var mapScale: MapScale
    public var groupID: UUID?
    public var realWorldMap: RealWorldMap?

    public init(
        id: UUID = UUID(),
        name: String = "未命名地图",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        terrain: TerrainLayout = TerrainGenerator.generate(seed: 1),
        roads: [RoadSegment] = [],
        roadNetwork: RoadNetwork? = nil,
        interchanges: [RoadInterchange] = [],
        trafficRules: RoadTrafficRuleSet = .init(),
        structureReviews: [RoadStructureReviewRecord] = [],
        engineeringStructures: [RoadEngineeringStructure] = [],
        theme: MapTheme = .planning,
        showsContours: Bool = true,
        showsGrid: Bool = true,
        layerVisibility: MapLayerVisibility = .init(),
        mapScale: MapScale = .standard,
        groupID: UUID? = nil,
        realWorldMap: RealWorldMap? = nil
    ) {
        self.id = id
        self.formatVersion = Self.currentFormatVersion
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.terrain = terrain
        self.interchanges = interchanges
        self.trafficRules = trafficRules
        self.roadNetwork = roadNetwork ?? RoadNetwork.rebuilding(
            from: roads,
            interchanges: interchanges
        ).network
        self.structureReviews = structureReviews
        self.engineeringStructures = engineeringStructures
        self.theme = theme
        self.showsContours = showsContours
        self.showsGrid = showsGrid
        self.layerVisibility = layerVisibility
        self.mapScale = mapScale
        self.groupID = groupID
        self.realWorldMap = realWorldMap
    }

    public var roads: [RoadSegment] {
        get { roadNetwork.roadSegments }
        set {
            roadNetwork = RoadNetwork.rebuilding(
                from: newValue,
                interchanges: interchanges
            ).network
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, formatVersion, name, createdAt, updatedAt, terrain, roads
        case roadNetwork, interchanges, trafficRules
        case structureReviews, engineeringStructures
        case theme, showsContours, showsGrid
        case layerVisibility, mapScale, groupID, realWorldMap
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        formatVersion = try values.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        guard formatVersion <= Self.currentFormatVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .formatVersion,
                in: values,
                debugDescription: "Unsupported project format version \(formatVersion)"
            )
        }
        name = try values.decode(String.self, forKey: .name)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        terrain = try values.decode(TerrainLayout.self, forKey: .terrain)
        interchanges = try values.decodeIfPresent(
            [RoadInterchange].self,
            forKey: .interchanges
        ) ?? []
        trafficRules = try values.decodeIfPresent(
            RoadTrafficRuleSet.self,
            forKey: .trafficRules
        ) ?? .init()
        if formatVersion >= 4 {
            roadNetwork = try values.decode(RoadNetwork.self, forKey: .roadNetwork)
        } else if let decodedNetwork = try values.decodeIfPresent(
            RoadNetwork.self,
            forKey: .roadNetwork
        ) {
            roadNetwork = decodedNetwork
        } else {
            let legacyRoads = try values.decodeIfPresent([RoadSegment].self, forKey: .roads) ?? []
            roadNetwork = RoadNetwork.rebuilding(
                from: legacyRoads,
                interchanges: interchanges
            ).network
        }
        structureReviews = try values.decodeIfPresent(
            [RoadStructureReviewRecord].self,
            forKey: .structureReviews
        ) ?? []
        engineeringStructures = try values.decodeIfPresent(
            [RoadEngineeringStructure].self,
            forKey: .engineeringStructures
        ) ?? []
        theme = try values.decodeIfPresent(MapTheme.self, forKey: .theme) ?? .planning
        showsContours = try values.decodeIfPresent(Bool.self, forKey: .showsContours) ?? true
        showsGrid = try values.decodeIfPresent(Bool.self, forKey: .showsGrid) ?? true
        layerVisibility = try values.decodeIfPresent(
            MapLayerVisibility.self,
            forKey: .layerVisibility
        ) ?? .init()
        mapScale = try values.decodeIfPresent(
            MapScale.self,
            forKey: .mapScale
        ) ?? .standard
        groupID = try values.decodeIfPresent(UUID.self, forKey: .groupID)
        realWorldMap = try values.decodeIfPresent(RealWorldMap.self, forKey: .realWorldMap)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(formatVersion, forKey: .formatVersion)
        try values.encode(name, forKey: .name)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encode(terrain, forKey: .terrain)
        try values.encode(roads, forKey: .roads)
        try values.encode(roadNetwork, forKey: .roadNetwork)
        try values.encode(interchanges, forKey: .interchanges)
        try values.encode(trafficRules, forKey: .trafficRules)
        try values.encode(structureReviews, forKey: .structureReviews)
        try values.encode(engineeringStructures, forKey: .engineeringStructures)
        try values.encode(theme, forKey: .theme)
        try values.encode(showsContours, forKey: .showsContours)
        try values.encode(showsGrid, forKey: .showsGrid)
        try values.encode(layerVisibility, forKey: .layerVisibility)
        try values.encode(mapScale, forKey: .mapScale)
        try values.encodeIfPresent(groupID, forKey: .groupID)
        try values.encodeIfPresent(realWorldMap, forKey: .realWorldMap)
    }
}
