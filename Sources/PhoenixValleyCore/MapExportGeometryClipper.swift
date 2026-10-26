import Foundation

/// Clips geographic features in camera space, then restores their original CRS.
enum MapExportGeometryClipper {
    static func clip(_ data: Data, to viewport: MapExportViewport, project: RoadProject) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let scale = project.mapScale.metersPerPoint
        func screen(_ pair: [Double]) -> RoadPoint {
            let world: RoadPoint
            if let map = project.realWorldMap {
                world = map.bounds.canvasPoint(latitude: pair[1], longitude: pair[0])
            } else { world = RoadPoint(x: pair[0]/scale, y: pair[1]/scale) }
            return viewport.camera.screenPoint(for: world)
        }
        func coordinate(_ point: RoadPoint) -> [Double] {
            let world = viewport.camera.worldPoint(for: point)
            if let map = project.realWorldMap {
                let lat = (map.bounds.minLatitude+map.bounds.maxLatitude)/2
                return [(map.bounds.minLongitude+map.bounds.maxLongitude)/2 + (world.x-800)*map.bounds.metersPerPoint/(111_195*cos(lat * .pi/180)),
                        lat+(600-world.y)*map.bounds.metersPerPoint/111_195]
            }
            return [world.x*scale, world.y*scale]
        }
        func inside(_ point: RoadPoint) -> Bool {
            point.x >= 0 && point.y >= 0 && point.x <= viewport.width && point.y <= viewport.height
        }
        func clippedSegment(_ a: RoadPoint, _ b: RoadPoint) -> (RoadPoint, RoadPoint)? {
            let dx = b.x-a.x, dy = b.y-a.y
            var lower = 0.0, upper = 1.0
            for (p,q) in [(-dx,a.x),(dx,viewport.width-a.x),(-dy,a.y),(dy,viewport.height-a.y)] {
                if abs(p) < 1e-12 { if q < 0 { return nil }; continue }
                let ratio = q/p
                if p < 0 { lower = max(lower, ratio) } else { upper = min(upper, ratio) }
                if lower > upper { return nil }
            }
            return (.init(x: a.x+lower*dx,y: a.y+lower*dy), .init(x: a.x+upper*dx,y: a.y+upper*dy))
        }
        func lines(_ coordinates: [[Double]]) -> [[[Double]]] {
            let points = coordinates.map(screen)
            var result: [[RoadPoint]] = []
            for (a,b) in zip(points,points.dropFirst()) {
                guard let (start,end) = clippedSegment(a,b), start.distance(to:end) > 1e-9 else { continue }
                if let last = result.last?.last, last.distance(to:start) < 1e-7 {
                    result[result.count-1].append(end)
                } else { result.append([start,end]) }
            }
            return result.map { $0.map(coordinate) }
        }
        func polygon(_ coordinates: [[Double]]) -> [[Double]] {
            var points = coordinates.map(screen)
            if points.first == points.last { points.removeLast() }
            for edge in 0..<4 {
                guard var previous = points.last else { return [] }
                func distance(_ p: RoadPoint) -> Double {
                    switch edge { case 0: p.x; case 1: viewport.width-p.x; case 2: p.y; default: viewport.height-p.y }
                }
                var output: [RoadPoint] = []
                for current in points {
                    let a = distance(previous), b = distance(current)
                    if (a >= 0) != (b >= 0) {
                        let t = a/(a-b)
                        output.append(.init(x:previous.x+t*(current.x-previous.x),y:previous.y+t*(current.y-previous.y)))
                    }
                    if b >= 0 { output.append(current) }
                    previous = current
                }
                points = output
            }
            guard points.count >= 3 else { return [] }
            points.append(points[0])
            return points.map(coordinate)
        }
        var kept: [[String: Any]] = []
        for var feature in object["features"] as? [[String: Any]] ?? [] {
            guard var geometry = feature["geometry"] as? [String: Any], let type = geometry["type"] as? String else {
                if feature["geometry"] is NSNull || feature["geometry"] == nil {
                    if var properties = feature["properties"] as? [String: Any] {
                        properties["scope"] = "fullProject"
                        feature["properties"] = properties
                    }
                    kept.append(feature)
                }
                continue
            }
            switch type {
            case "Point":
                guard let point = geometry["coordinates"] as? [Double], point.count >= 2, inside(screen(point)) else { continue }
            case "LineString":
                let parts = lines(geometry["coordinates"] as? [[Double]] ?? [])
                guard !parts.isEmpty else { continue }
                geometry["type"] = parts.count == 1 ? "LineString" : "MultiLineString"
                geometry["coordinates"] = parts.count == 1 ? parts[0] as Any : parts as Any
            case "Polygon":
                let rings = (geometry["coordinates"] as? [[[Double]]] ?? []).map(polygon).filter { !$0.isEmpty }
                guard !rings.isEmpty else { continue }
                geometry["coordinates"] = rings
            default: continue
            }
            feature["geometry"] = geometry; kept.append(feature)
        }
        object["features"] = kept
        let corners = [RoadPoint(x:0,y:0), .init(x:viewport.width,y:0), .init(x:0,y:viewport.height), .init(x:viewport.width,y:viewport.height)].map(coordinate)
        object["bbox"] = [corners.map{$0[0]}.min()!,corners.map{$0[1]}.min()!,corners.map{$0[0]}.max()!,corners.map{$0[1]}.max()!]
        object["exportExtent"] = "currentViewport"
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted,.sortedKeys])
    }
}
