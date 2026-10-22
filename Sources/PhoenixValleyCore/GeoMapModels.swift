import Foundation

public enum GeoImportFormat: String, Codable, Sendable { case osmXML, kml, esriASCII }

public enum GeoImportError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

public struct GeoBounds: Codable, Hashable, Sendable {
    public let minLatitude: Double
    public let minLongitude: Double
    public let maxLatitude: Double
    public let maxLongitude: Double
    public init(minLatitude: Double, minLongitude: Double, maxLatitude: Double, maxLongitude: Double) throws {
        guard [minLatitude,minLongitude,maxLatitude,maxLongitude].allSatisfy(\.isFinite),
              minLatitude >= -80, maxLatitude <= 80, minLatitude < maxLatitude,
              minLongitude >= -180, maxLongitude <= 180, minLongitude < maxLongitude else {
            throw GeoImportError.invalid("地理范围无效；支持南北纬 80° 内、不跨日期变更线的区域。")
        }
        self.minLatitude = minLatitude; self.minLongitude = minLongitude
        self.maxLatitude = maxLatitude; self.maxLongitude = maxLongitude
    }
    public static func around(latitude: Double, longitude: Double, widthMeters: Double, heightMeters: Double) throws -> Self {
        guard latitude.isFinite, longitude.isFinite, widthMeters.isFinite, heightMeters.isFinite,
              widthMeters >= 100, heightMeters >= 100, widthMeters <= 16_000, heightMeters <= 12_000 else {
            throw GeoImportError.invalid("区域宽度须为 100–16000 米，高度须为 100–12000 米。")
        }
        let dy = heightMeters / 2 / 111_195
        let dx = widthMeters / 2 / (111_195 * cos(latitude * .pi / 180))
        return try .init(minLatitude: latitude-dy, minLongitude: longitude-dx, maxLatitude: latitude+dy, maxLongitude: longitude+dx)
    }
    public var bboxQuery: String { "\(minLongitude),\(minLatitude),\(maxLongitude),\(maxLatitude)" }
    public var widthMeters: Double { (maxLongitude-minLongitude) * 111_195 * cos((maxLatitude+minLatitude)/2 * .pi/180) }
    public var heightMeters: Double { (maxLatitude-minLatitude) * 111_195 }
    public var metersPerPoint: Double { max(0.1, max(widthMeters/1600, heightMeters/1200)) }
    public func canvasPoint(latitude: Double, longitude: Double) -> RoadPoint {
        .init(x: 800 + (longitude-(maxLongitude+minLongitude)/2) * 111_195 * cos((maxLatitude+minLatitude)/2 * .pi/180)/metersPerPoint,
              y: 600 - (latitude-(maxLatitude+minLatitude)/2) * 111_195/metersPerPoint)
    }
}

public enum GeoCoordinateSystem: String, Sendable { case wgs84 }
public struct GeoImportOptions: Sendable {
    public var demCoordinateSystem: GeoCoordinateSystem?
    public var name: String
    public var bounds: GeoBounds?
    public var simplificationMeters: Double
    public init(name: String = "真实地图", bounds: GeoBounds? = nil, simplificationMeters: Double = 8, demCoordinateSystem: GeoCoordinateSystem? = nil) {
        self.demCoordinateSystem = demCoordinateSystem
        self.name = name; self.bounds = bounds; self.simplificationMeters = simplificationMeters
    }
}
public enum GeoMapFeatureKind: String, Codable, Hashable, Sendable { case water, forest, park, building }
public struct GeoMapFeature: Codable, Hashable, Sendable {
    public var kind: GeoMapFeatureKind
    public var points: [RoadPoint]
    public var name: String?
    public init(kind: GeoMapFeatureKind, points: [RoadPoint], name: String? = nil) { self.kind = kind; self.points = points; self.name = name }
}
public struct GeoElevationGrid: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    public var meters: [Double?]
    public var minimumMeters: Double
    public var maximumMeters: Double
}
public struct GeoImportSummary: Codable, Hashable, Sendable {
    public var inputPointCount: Int
    public var retainedPointCount: Int
    public var roadCount: Int
    public var featureCount: Int
    public var simplificationMeters: Double
    public var warnings: [String]
    public var description: String { "\(roadCount) 段可编辑道路 · \(featureCount) 个地物 · \(inputPointCount) → \(retainedPointCount) 个点" }
}
public struct RealWorldMap: Codable, Hashable, Sendable {
    public var bounds: GeoBounds
    public var source: GeoImportFormat
    public var attribution: String
    public var features: [GeoMapFeature]
    public var elevation: GeoElevationGrid?
    public var summary: GeoImportSummary
}
public struct GeoImportResult: Sendable {
    public var project: RoadProject
    public var summary: GeoImportSummary
}
