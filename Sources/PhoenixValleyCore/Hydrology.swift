import Foundation

public enum HydrologySurface: UInt8, Codable, CaseIterable, Hashable, Sendable {
    case land = 0
    case river = 1
    case lake = 2
    case wetland = 3
    case ocean = 4
}

public struct WatershedOutlet: Codable, Hashable, Sendable {
    public var id: UInt16
    public var point: RoadPoint
    public var drainageCellCount: Int

    public init(id: UInt16, point: RoadPoint, drainageCellCount: Int) {
        self.id = id
        self.point = point
        self.drainageCellCount = drainageCellCount
    }
}

public struct HydrologyLayout: Codable, Hashable, Sendable {
    public var gridWidth: Int
    public var gridHeight: Int
    public var surfaceCodes: [UInt8]
    public var watershedIDs: [UInt16]
    public var outlets: [WatershedOutlet]

    public init(
        gridWidth: Int = 0,
        gridHeight: Int = 0,
        surfaceCodes: [UInt8] = [],
        watershedIDs: [UInt16] = [],
        outlets: [WatershedOutlet] = []
    ) {
        self.gridWidth = gridWidth
        self.gridHeight = gridHeight
        self.surfaceCodes = surfaceCodes
        self.watershedIDs = watershedIDs
        self.outlets = outlets
    }

    public var hasData: Bool {
        gridWidth >= 2
            && gridHeight >= 2
            && surfaceCodes.count == gridWidth * gridHeight
            && watershedIDs.count == gridWidth * gridHeight
    }

    public func surface(column: Int, row: Int) -> HydrologySurface {
        guard hasData,
              column >= 0, column < gridWidth,
              row >= 0, row < gridHeight
        else { return .land }
        return HydrologySurface(rawValue: surfaceCodes[row * gridWidth + column]) ?? .land
    }

    public func watershedID(column: Int, row: Int) -> UInt16? {
        guard hasData,
              column >= 0, column < gridWidth,
              row >= 0, row < gridHeight
        else { return nil }
        let value = watershedIDs[row * gridWidth + column]
        return value == 0 ? nil : value
    }

    public func surface(at point: RoadPoint) -> HydrologySurface {
        guard hasData else { return .land }
        let column = Int(
            min(
                Double(gridWidth - 1),
                max(0, point.x / MapScale.canvasWidth * Double(gridWidth - 1))
            ).rounded()
        )
        let row = Int(
            min(
                Double(gridHeight - 1),
                max(0, point.y / MapScale.canvasHeight * Double(gridHeight - 1))
            ).rounded()
        )
        return surface(column: column, row: row)
    }

    public func watershedID(at point: RoadPoint) -> UInt16? {
        guard hasData else { return nil }
        let column = Int(
            min(
                Double(gridWidth - 1),
                max(0, point.x / MapScale.canvasWidth * Double(gridWidth - 1))
            ).rounded()
        )
        let row = Int(
            min(
                Double(gridHeight - 1),
                max(0, point.y / MapScale.canvasHeight * Double(gridHeight - 1))
            ).rounded()
        )
        return watershedID(column: column, row: row)
    }

    public func cellCount(for surface: HydrologySurface) -> Int {
        surfaceCodes.lazy.filter { $0 == surface.rawValue }.count
    }
}
