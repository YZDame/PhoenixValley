import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

private struct GeoCoordinate { var latitude: Double; var longitude: Double }
private struct GeoPath {
    var id: String
    var references: [String]
    var tags: [String:String]
    var polygon: Bool
}

/// Parses a bounded, local copy. Never resolves XML entities, links, images or remote KML content.
public enum GeoMapImporter {
    public static let maximumBytes = 8 * 1024 * 1024
    public static let maximumInputPoints = 40_000
    public static let maximumRoadEdges = 1_200
    public static let maximumRetainedPoints = 12_000

    public static func importMap(data: Data, format: GeoImportFormat, options: GeoImportOptions = .init()) throws -> GeoImportResult {
        guard !data.isEmpty, data.count <= maximumBytes else { throw GeoImportError.invalid("文件为空或超过 8 MB；请缩小导入区域。") }
        guard options.simplificationMeters.isFinite, (0...100).contains(options.simplificationMeters) else { throw GeoImportError.invalid("简化距离须为 0–100 米。") }
        if format == .esriASCII { return try importElevation(data: data, options: options) }
        guard let xml = String(data: data, encoding: .utf8),
              !xml.localizedCaseInsensitiveContains("<!DOCTYPE"), !xml.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw GeoImportError.invalid("仅支持 UTF-8 XML，且不允许 DTD 或外部实体。")
        }
        let reader = GeographicXMLReader(format: format)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = true
        parser.delegate = reader
        guard parser.parse(), reader.error == nil else { throw reader.error ?? GeoImportError.invalid("XML 格式错误或文件不完整。") }
        guard reader.root == (format == .osmXML ? "osm" : "kml") else { throw GeoImportError.invalid("文件内容与所选地理格式不符。") }
        return try build(reader: reader, format: format, options: options)
    }

    private static func build(reader: GeographicXMLReader, format: GeoImportFormat, options: GeoImportOptions) throws -> GeoImportResult {
        let selected = reader.paths.filter { roadKind($0.tags) != nil || featureKind($0.tags) != nil }
        guard !selected.isEmpty else { throw GeoImportError.invalid("未找到支持的道路或地物。支持 OSM 道路/封闭地物与 KML 路径/多边形。") }
        let coordinates = selected.flatMap { $0.references.compactMap { reader.coordinates[$0] } }
        guard !coordinates.isEmpty else { throw GeoImportError.invalid("地理文件没有有效坐标。") }
        let bounds = try options.bounds ?? inferredBounds(coordinates)
        try validateSize(bounds)
        var warnings = reader.warnings
        warnings.append("后续编辑按游戏的几何规则重建路口，可能改变源数据连接；不保留完整现实交通规则。")
        if format == .osmXML { warnings.append("仅转换有共享节点的道路连接；转向限制、多边形关系及未支持的地物不参与模拟。") }
        if format == .kml { warnings.append("KML 路径作为街道，多边形作为公园底图；路径高程与样式不作为 DEM，交叉路径不自动连通。") }
        warnings.append("未提供 DEM 时不生成虚构高程。导入结果是简化地图，不用于导航或测绘。")
        let roads = selected.filter { roadKind($0.tags) != nil }
        var uses: [String:Int] = [:]
        for path in roads { for ref in Set(path.references) { uses[ref, default:0] += 1 } }
        var nodes: [RoadNode] = []
        var edges: [RoadEdge] = []
        var nodeIDs: [String:UUID] = [:]
        var sourceNodes: [String:[RoadNode]] = [:]
        var features: [GeoMapFeature] = []
        var retained = 0
        let tolerance = options.simplificationMeters / bounds.metersPerPoint
        let clipRect = (bounds.canvasPoint(latitude: bounds.maxLatitude, longitude: bounds.minLongitude), bounds.canvasPoint(latitude: bounds.minLatitude, longitude: bounds.maxLongitude))
        func node(_ key: String, _ point: RoadPoint, _ level: RoadLevel) -> UUID {
            let scoped = "\(key):\(level.rawValue)"
            if let id = nodeIDs[scoped] { return id }
            let id = UUID(); nodeIDs[scoped] = id
            let created = RoadNode(id: id, point: point, level: level)
            nodes.append(created)
            sourceNodes[key, default: []].append(created)
            return id
        }
        for path in selected {
            guard path.references.allSatisfy({ reader.coordinates[$0] != nil }) else {
                throw GeoImportError.invalid("道路或地物引用了缺失的节点，请导入完整区域数据。")
            }
            let points = path.references.map { ref -> RoadPoint in
                let c = reader.coordinates[ref]!
                return bounds.canvasPoint(latitude: c.latitude, longitude: c.longitude)
            }
            if let kind = roadKind(path.tags) {
                let level: RoadLevel = truthy(path.tags["tunnel"]) ? .tunnel : (truthy(path.tags["bridge"]) ? .elevated : .ground)
                let direction: RoadDirection = path.tags["oneway"] == "-1" ? .reverse : ((truthy(path.tags["oneway"]) || (path.tags["junction"] == "roundabout" && path.tags["oneway"] != "no")) ? .forward : .bidirectional)
                let source = UUID()
                // Shared source nodes are immutable simplification anchors; geometric intersections stay disconnected.
                var anchors = [0]
                if points.count > 2 { anchors += (1..<(points.count-1)).filter { uses[path.references[$0], default:0] > 1 } }
                if points.count > 1 { anchors.append(points.count-1) }
                guard anchors.count > 1 else { continue }
                for pair in zip(anchors, anchors.dropFirst()) {
                    let original = Array(points[pair.0...pair.1])
                    // Clip each original segment before simplifying, retaining boundary contacts.
                    let chunks = clippedPolyline(original, rect: clipRect)
                    for (index, chunk) in chunks.enumerated() {
                        let simplified = simplify(chunk, tolerance: tolerance)
                        guard simplified.count >= 2, simplified.first!.distance(to: simplified.last!) > 0.00001 || simplified.count > 2 else { continue }
                        let startKey = simplified.first! == original.first! ? path.references[pair.0] : "clip:\(path.id):\(pair.0):\(index):a"
                        let endKey = simplified.last! == original.last! ? path.references[pair.1] : "clip:\(path.id):\(pair.1):\(index):b"
                        let a = node(startKey, simplified.first!, level)
                        let b = node(endKey, simplified.last!, level)
                        edges.append(.init(id: UUID(), sourceRoadID: source, startNodeID: a, endNodeID: b, kind: kind, level: level, direction: direction, priority: kind.defaultPriority, points: simplified))
                        retained += simplified.count
                        guard edges.count <= maximumRoadEdges, retained <= maximumRetainedPoints else { throw GeoImportError.invalid("道路过密；请选择更小区域或增加简化距离（最多 1200 段、12000 个点）。") }
                    }
                }
            } else if let kind = featureKind(path.tags), path.polygon, points.count >= 4 {
                let clipped = clippedPolygon(points, rect: clipRect)
                let simplified = simplifyClosed(clipped, tolerance: kind == .building ? min(tolerance, 1) : tolerance)
                if simplified.count >= 3 {
                    retained += simplified.count
                    features.append(.init(kind: kind, points: simplified, name: path.tags["name"]))
                    guard features.count <= 2_000, retained <= maximumRetainedPoints else { throw GeoImportError.invalid("地物过密；请缩小导入区域。") }
                }
            }
        }
        guard !edges.isEmpty || !features.isEmpty else { throw GeoImportError.invalid("所选区域内没有可导入的道路或地物。") }
        // OSM bridge/tunnel approaches share source IDs even when render levels differ.
        // Explicit transitions connect only that declared node, never an incidental crossing.
        var relations: [RoadRelation] = []
        let incident = Dictionary(grouping: edges.flatMap { [($0.startNodeID, $0), ($0.endNodeID, $0)] }, by: { $0.0 })
        for key in sourceNodes.keys.sorted() {
            let endpoints = sourceNodes[key]!.sorted { $0.level.rawValue < $1.level.rawValue }
            guard endpoints.count > 1 else { continue }
            for i in 0..<(endpoints.count-1) {
                for j in (i+1)..<endpoints.count {
                    let a = endpoints[i], b = endpoints[j]
                    let first = incident[a.id, default: []].map { $0.1 }
                    let second = incident[b.id, default: []].map { $0.1 }
                    guard let firstRoad = first.first, let secondRoad = second.first else { continue }
                    relations.append(.init(id: UUID(), kind: .structureTransition, point: a.point,
                        firstRoadID: firstRoad.sourceRoadID, secondRoadID: secondRoad.sourceRoadID,
                        firstLevel: a.level, secondLevel: b.level, firstEdgeIDs: first.map(\.id),
                        secondEdgeIDs: second.map(\.id), junctionNodeIDs: [a.id,b.id]))
                }
            }
        }
        let summary = GeoImportSummary(inputPointCount: coordinates.count, retainedPointCount: retained, roadCount: edges.count, featureCount: features.count, simplificationMeters: options.simplificationMeters, warnings: warnings)
        let metadata = RealWorldMap(bounds: bounds, source: format, attribution: format == .osmXML ? "© OpenStreetMap contributors · ODbL 1.0 · https://www.openstreetmap.org/copyright" : "用户提供的 KML；使用与分享前请确认源数据授权。", features: features, elevation: nil, summary: summary)
        let terrain = TerrainLayout(seed: 0, shoreline: [.init(x:0,y:0),.init(x:1600,y:0),.init(x:1600,y:1200),.init(x:0,y:1200)], scenario: .continent)
        let project = RoadProject(name: options.name, terrain: terrain, roadNetwork: RoadNetwork(nodes: nodes, edges: edges, relations: relations), theme: .topographic, showsContours: false, showsGrid: false, mapScale: .init(metersPerPoint: bounds.metersPerPoint), realWorldMap: metadata)
        return .init(project: project, summary: summary)
    }
    private static func truthy(_ value: String?) -> Bool { value.map { !["no","false","0"].contains($0) } ?? false }
    private static func roadKind(_ tags: [String:String]) -> RoadKind? {
        if ["rail","light_rail","tram","subway","narrow_gauge"].contains(tags["railway"] ?? "") { return .railway }
        switch tags["highway"] {
        case "motorway","motorway_link","trunk","trunk_link": return .motorway
        case "primary","primary_link","secondary","secondary_link","tertiary","tertiary_link": return .arterial
        case "residential","unclassified","living_street","service","road": return .street
        default: return nil
        }
    }
    private static func featureKind(_ tags: [String:String]) -> GeoMapFeatureKind? {
        if let b = tags["building"], b != "no" { return .building }
        if tags["natural"] == "water" || tags["landuse"] == "reservoir" || tags["waterway"] == "riverbank" { return .water }
        if tags["natural"] == "wood" || tags["landuse"] == "forest" { return .forest }
        if ["park","garden","recreation_ground"].contains(tags["leisure"] ?? "") || tags["landuse"] == "grass" { return .park }
        return nil
    }
    private static func inferredBounds(_ points: [GeoCoordinate]) throws -> GeoBounds {
        let minLat = points.map(\.latitude).min()!, maxLat = points.map(\.latitude).max()!
        let minLon = points.map(\.longitude).min()!, maxLon = points.map(\.longitude).max()!
        let centerLat = (minLat+maxLat)/2, centerLon = (minLon+maxLon)/2
        // A single straight path still needs a nonzero map region.
        return try GeoBounds(minLatitude: min(centerLat-0.0005,minLat), minLongitude: min(centerLon-0.0005,minLon), maxLatitude: max(centerLat+0.0005,maxLat), maxLongitude: max(centerLon+0.0005,maxLon))
    }
    private static func validateSize(_ bounds: GeoBounds) throws {
        guard bounds.widthMeters <= 16_000.1, bounds.heightMeters <= 12_000.1 else { throw GeoImportError.invalid("区域过大；请限制在宽 16 千米、高 12 千米内。") }
    }
}

private final class GeographicXMLReader: NSObject, XMLParserDelegate {
    let format: GeoImportFormat
    var coordinates: [String:GeoCoordinate] = [:]
    var paths: [GeoPath] = []
    var warnings: [String] = []
    var error: GeoImportError?
    var root: String?
    private var stack: [String] = []
    private var activeWay: GeoPath?
    private var text = ""
    private var coordinateCount = 0
    private var kmlName = ""
    private var polygonStart: Int?
    private var wayIDs: Set<String> = []
    private var referenceCount = 0
    init(format: GeoImportFormat) { self.format = format }
    func fail(_ parser: XMLParser, _ message: String) { error = .invalid(message); parser.abortParsing() }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String:String]) {
        if root == nil { root = elementName }
        stack.append(elementName)
        guard stack.count <= 64 else { fail(parser,"XML 嵌套层级过深。"); return }
        if format == .osmXML {
            switch elementName {
            case "node":
                guard let id = attributes["id"], let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init), valid(lat,lon), coordinates[id] == nil else { fail(parser,"OSM 节点无效或重复。"); return }
                coordinateCount += 1
                guard coordinateCount <= GeoMapImporter.maximumInputPoints else { fail(parser,"节点超过 40000；请缩小区域。"); return }
                coordinates[id] = .init(latitude: lat, longitude: lon)
            case "way":
                guard let id = attributes["id"], wayIDs.insert(id).inserted else { fail(parser,"OSM 路径编号缺失或重复。"); return }
                activeWay = GeoPath(id: id, references: [], tags: [:], polygon: false)
            case "nd":
                if activeWay != nil {
                    guard let ref = attributes["ref"] else { fail(parser,"OSM 路径节点引用缺失。"); return }
                    referenceCount += 1
                    guard referenceCount <= 160_000 else { fail(parser,"路径引用数量过多；请缩小区域。"); return }
                    activeWay!.references.append(ref)
                    guard activeWay!.references.count <= GeoMapImporter.maximumInputPoints else { fail(parser,"单条路径节点过多。"); return }
                }
            case "tag":
                if let k = attributes["k"], let v = attributes["v"], activeWay != nil { activeWay!.tags[k] = v }
            default: break
            }
        } else {
            if elementName == "Placemark" { kmlName = "" }
            if elementName == "Polygon" { polygonStart = paths.count }
            if elementName == "coordinates" || elementName == "name" { text = "" }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if format == .kml && ["coordinates","name"].contains(stack.last ?? "") { text += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        defer { if !stack.isEmpty { stack.removeLast() } }
        if format == .osmXML && elementName == "way", var way = activeWay {
            way.polygon = way.references.count >= 4 && way.references.first == way.references.last
            paths.append(way); activeWay = nil
        }
        if format == .kml {
            if elementName == "name" { kmlName = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            if elementName == "coordinates" {
                guard stack.contains("LineString") || stack.contains("outerBoundaryIs") else { return }
                if stack.contains("innerBoundaryIs") { return }
                var refs: [String] = []
                for tuple in text.split(whereSeparator: \.isWhitespace) {
                    let parts = tuple.split(separator: ",", omittingEmptySubsequences: false)
                    guard parts.count >= 2, let lon = Double(parts[0]), let lat = Double(parts[1]), valid(lat,lon) else { fail(parser,"KML 坐标须为经度,纬度[,高程]。"); return }
                    coordinateCount += 1
                    guard coordinateCount <= GeoMapImporter.maximumInputPoints else { fail(parser,"节点超过 40000；请缩小区域。"); return }
                    let key = "kml\(coordinateCount)"
                    coordinates[key] = .init(latitude:lat,longitude:lon); refs.append(key)
                }
                let polygon = stack.contains("outerBoundaryIs")
                if polygon, let first = refs.first, let last = refs.last,
                   let a = coordinates[first], let b = coordinates[last], a.latitude != b.latitude || a.longitude != b.longitude { refs.append(first) }
                paths.append(.init(id:"kml-path\(paths.count)", references:refs, tags:polygon ? ["leisure":"park","name":kmlName] : ["highway":"residential","name":kmlName], polygon:polygon))
            }
            if elementName == "innerBoundaryIs" {
                if !warnings.contains("KML 多边形内环暂不支持；带内环的面不导入。") { warnings.append("KML 多边形内环暂不支持；带内环的面不导入。") }
                // Remove the outer ring of this polygon instead of filling an actual hole.
                if let start = polygonStart, start < paths.count { paths.removeSubrange(start..<paths.count) }
            }
            if elementName == "Polygon" { polygonStart = nil }
        }
        if paths.count > 10_000 { fail(parser,"路径数量过多；请缩小导入区域。") }
    }
    private func valid(_ latitude: Double, _ longitude: Double) -> Bool { latitude.isFinite && longitude.isFinite && abs(latitude) <= 80 && abs(longitude) <= 180 }
}

private func simplify(_ points: [RoadPoint], tolerance: Double) -> [RoadPoint] {
    guard points.count > 2, tolerance > 0 else { return points }
    var keep: Set<Int> = [0, points.count-1]
    var pending = [(0,points.count-1)]
    var comparisons = 0
    while let (a,b) = pending.popLast() {
        guard b > a+1 else { continue }
        let v = points[b]-points[a], length = v.x*v.x+v.y*v.y
        var furthest = 0.0, index = a
        for i in (a+1)..<b {
            comparisons += 1
            if comparisons > 1_000_000 { return points }
            let w = points[i]-points[a]
            let t = length > 0 ? max(0,min(1,(w.x*v.x+w.y*v.y)/length)) : 0
            let distance = points[i].distance(to:points[a]+v*t)
            if distance > furthest { furthest = distance; index = i }
        }
        if furthest > tolerance { keep.insert(index); pending.append((a,index)); pending.append((index,b)) }
    }
    return keep.sorted().map { points[$0] }
}
private func simplifyClosed(_ points: [RoadPoint], tolerance: Double) -> [RoadPoint] {
    guard points.count > 3 else { return points }
    var ring = points
    if ring.first == ring.last { ring.removeLast() }
    guard ring.count > 3 else { return ring }
    // Two open halves avoid collapsing a closed ring whose endpoints coincide.
    let split = ring.count/2
    let first = simplify(Array(ring[0...split]),tolerance:tolerance)
    let second = simplify(Array(ring[split...])+[ring[0]],tolerance:tolerance)
    let result = Array(first.dropLast()) + Array(second.dropLast())
    return result.count >= 3 ? result : ring
}
private func clipSegment(_ a: RoadPoint, _ b: RoadPoint, rect: (RoadPoint, RoadPoint)) -> (RoadPoint,RoadPoint)? {
    let dx = b.x-a.x, dy = b.y-a.y
    var lo = 0.0, hi = 1.0
    for (p,q) in [(-dx,a.x-rect.0.x),(dx,rect.1.x-a.x),(-dy,a.y-rect.0.y),(dy,rect.1.y-a.y)] {
        if abs(p) < 1e-12 { if q < 0 { return nil }; continue }
        let t = q/p
        if p < 0 { lo = max(lo,t) } else { hi = min(hi,t) }
        if lo > hi { return nil }
    }
    let delta = b-a
    return (a+delta*lo,a+delta*hi)
}
private func clippedPolyline(_ points: [RoadPoint], rect: (RoadPoint, RoadPoint)) -> [[RoadPoint]] {
    var chunks: [[RoadPoint]] = []
    for (a,b) in zip(points, points.dropFirst()) {
        guard let (start,end) = clipSegment(a,b,rect:rect), start.distance(to:end) > 1e-8 else { continue }
        if let last = chunks.last?.last, last.distance(to:start) < 1e-7 {
            chunks[chunks.count-1].append(end)
        } else { chunks.append([start,end]) }
    }
    return chunks
}
private func clippedPolygon(_ points: [RoadPoint], rect: (RoadPoint, RoadPoint)) -> [RoadPoint] {
    var result = points
    if result.first == result.last { result.removeLast() }
    for boundary in 0..<4 {
        let input = result; result = []
        guard let last = input.last else { break }
        func inside(_ p: RoadPoint) -> Bool {
            switch boundary { case 0: p.x >= rect.0.x; case 1: p.x <= rect.1.x; case 2: p.y >= rect.0.y; default: p.y <= rect.1.y }
        }
        func intersect(_ a: RoadPoint,_ b: RoadPoint) -> RoadPoint {
            if boundary < 2 { let x = boundary == 0 ? rect.0.x : rect.1.x; return .init(x:x,y:a.y+(b.y-a.y)*(x-a.x)/(b.x-a.x)) }
            let y = boundary == 2 ? rect.0.y : rect.1.y
            return .init(x:a.x+(b.x-a.x)*(y-a.y)/(b.y-a.y),y:y)
        }
        var previous = last
        for current in input {
            if inside(current) {
                if !inside(previous) { result.append(intersect(previous,current)) }
                result.append(current)
            } else if inside(previous) { result.append(intersect(previous,current)) }
            previous = current
        }
    }
    return result
}

extension GeoMapImporter {
    private static func importElevation(data: Data, options: GeoImportOptions) throws -> GeoImportResult {
        guard options.demCoordinateSystem == .wgs84 else { throw GeoImportError.invalid("ASC 文件不记录坐标系，请明确确认源数据为 WGS84 经纬度、海拔单位为米。") }
        guard let text = String(data:data,encoding:.utf8) else { throw GeoImportError.invalid("ASC 文件必须是 UTF-8 文本。") }
        let tokens = text.split(whereSeparator: \.isWhitespace)
        var cursor = 0, header: [String:Double] = [:]
        let keys: Set<String> = ["ncols","nrows","xllcorner","yllcorner","xllcenter","yllcenter","cellsize","nodata_value"]
        while cursor+1 < tokens.count, keys.contains(tokens[cursor].lowercased()) {
            let key = tokens[cursor].lowercased()
            guard header[key] == nil, let value = Double(tokens[cursor+1]), value.isFinite else { throw GeoImportError.invalid("ASC 表头无效或重复。") }
            header[key] = value; cursor += 2
        }
        guard let cols = header["ncols"], let rows = header["nrows"], cols >= 2, rows >= 2, cols <= 2048, rows <= 2048,
              cols.rounded() == cols, rows.rounded() == rows, cols*rows <= 1_000_000,
              let cell = header["cellsize"], cell > 0, cell < 1,
              let originX = header["xllcorner"] ?? header["xllcenter"], let originY = header["yllcorner"] ?? header["yllcenter"],
              (header["xllcorner"] != nil) == (header["yllcorner"] != nil),
              (header["xllcenter"] != nil) == (header["yllcenter"] != nil),
              (header["xllcorner"] == nil) != (header["xllcenter"] == nil),
              tokens.count-cursor == Int(cols*rows) else { throw GeoImportError.invalid("ASC 表头/栅格尺寸无效；最多 100 万格，须为 WGS84 经纬度。") }
        let x = originX - (header["xllcenter"] != nil ? cell/2 : 0)
        let y = originY - (header["yllcenter"] != nil ? cell/2 : 0)
        let sourceBounds = try GeoBounds(minLatitude:y,minLongitude:x,maxLatitude:y+rows*cell,maxLongitude:x+cols*cell)
        let bounds = options.bounds ?? sourceBounds
        try validateSize(bounds)
        let missing = header["nodata_value"] ?? -9999
        var source: [Double?] = []; source.reserveCapacity(Int(cols*rows))
        for token in tokens[cursor...] {
            guard let v = Double(token), v.isFinite else { throw GeoImportError.invalid("ASC 存在非数值或无穷高程。") }
            source.append(v == missing ? nil : v)
        }
        let width = 129, height = 97
        var meters: [Double?] = []; meters.reserveCapacity(width*height)
        // Sample in canvas coordinates so letterboxing and optional crop use exactly the same georeference.
        for row in 0..<height { for col in 0..<width {
            let px = Double(col)/Double(width-1)*1600, py = Double(row)/Double(height-1)*1200
            let lat = (bounds.maxLatitude+bounds.minLatitude)/2 + (600-py)*bounds.metersPerPoint/111_195
            let lon = (bounds.maxLongitude+bounds.minLongitude)/2 + (px-800)*bounds.metersPerPoint/(111_195*cos((bounds.maxLatitude+bounds.minLatitude)/2 * .pi/180))
            let sourceX = floor((lon-x)/cell), sourceY = floor((lat-y)/cell)
            guard sourceX >= 0, sourceX < cols, sourceY >= 0, sourceY < rows else {
                meters.append(nil)
                continue
            }
            let sx = Int(sourceX), sy = Int(rows)-1-Int(sourceY)
            meters.append(source[sy*Int(cols)+sx])
        } }
        let valid = meters.compactMap { $0 }
        guard let minimum = valid.min(), let maximum = valid.max() else { throw GeoImportError.invalid("所选区域内没有有效高程。") }
        let grid = GeoElevationGrid(width:width,height:height,meters:meters,minimumMeters:minimum,maximumMeters:maximum)
        let warnings = ["高程为用户确认的 WGS84、米制 DEM；129 × 97 最近邻采样，缺失值保留为空。", "真实高程用于地形底图；现有道路工程坡度计算未标定到此 DEM，不代表现实工程可行性。"]
        let summary = GeoImportSummary(inputPointCount:source.count,retainedPointCount:valid.count,roadCount:0,featureCount:0,simplificationMeters:options.simplificationMeters,warnings:warnings)
        let metadata = RealWorldMap(bounds:bounds,source:.esriASCII,attribution:"用户提供的 DEM；使用与分享前请确认源数据授权。",features:[],elevation:grid,summary:summary)
        let terrain = TerrainLayout(seed:0,shoreline:[.init(x:0,y:0),.init(x:1600,y:0),.init(x:1600,y:1200),.init(x:0,y:1200)],scenario:.continent)
        let project = RoadProject(name:options.name,terrain:terrain,theme:.topographic,showsContours:false,showsGrid:false,mapScale:.init(metersPerPoint:bounds.metersPerPoint),realWorldMap:metadata)
        return .init(project:project,summary:summary)
    }
}
