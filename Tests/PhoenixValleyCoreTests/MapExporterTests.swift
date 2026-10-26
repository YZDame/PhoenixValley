import Foundation
import CoreGraphics
import ImageIO
#if canImport(FoundationXML)
import FoundationXML
#endif
import Testing
@testable import PhoenixValleyCore

@Test func pngAndPDFExportsHaveExpectedSignatures() throws {
    let project = exportTestProject()
    let png = try MapExporter.data(for: project, format: .png)
    let pdf = try MapExporter.data(for: project, format: .pdf)

    #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    #expect(String(data: pdf.prefix(4), encoding: .ascii) == "%PDF")
    #expect(png.count > 1_000)
    #expect(pdf.count > 1_000)
}

@Test func SVGExportIsWellFormedAndContainsVisibleRoads() throws {
    let project = exportTestProject()
    let data = try MapExporter.data(for: project, format: .svg)
    let parser = XMLParser(data: data)

    #expect(parser.parse())
    let svg = try #require(String(data: data, encoding: .utf8))
    #expect(svg.contains("<svg"))
    #expect(svg.contains("<title>Export &amp; Test</title>"))
    #expect(svg.contains("stroke-linecap=\"round\""))
    #expect(svg.contains("data-meters-per-point=\"2\""))
    #expect(svg.contains("id=\"map-scale\""))
    #expect(svg.contains(">200 m</text>"))
}

@Test func geoJSONExportCarriesRoadSemanticsAndLocalCoordinates() throws {
    let project = exportTestProject()
    let data = try MapExporter.data(for: project, format: .geoJSON)
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let features = try #require(object["features"] as? [[String: Any]])
    let road = try #require(features.first {
        ($0["properties"] as? [String: Any])?["featureType"] as? String == "road"
    })
    let properties = try #require(road["properties"] as? [String: Any])

    #expect(object["type"] as? String == "FeatureCollection")
    #expect(
        object["coordinateSystem"] as? String
            == "PhoenixValley local Cartesian metres; origin top-left"
    )
    #expect((object["metersPerCanvasPoint"] as? NSNumber)?.doubleValue == 2)
    let bbox = try #require(object["bbox"] as? [NSNumber])
    #expect(bbox.map(\.doubleValue) == [0, 0, 3_200, 2_400])
    #expect(properties["structure"] as? String == RoadStructureType.bridge.rawValue)
    #expect(properties["direction"] as? String == RoadDirection.forward.rawValue)

    let geometry = try #require(road["geometry"] as? [String: Any])
    let coordinates = try #require(geometry["coordinates"] as? [[NSNumber]])
    #expect(coordinates.map { $0.map(\.doubleValue) } == [
        [200, 1_200],
        [3_000, 1_200],
    ])
}

@Test func exportsRespectHiddenTerrainAndRoadKinds() throws {
    var visibility = MapLayerVisibility(showsTerrain: false)
    visibility.setVisible(false, for: .arterial)
    var project = exportTestProject()
    project.layerVisibility = visibility

    let data = try MapExporter.data(for: project, format: .geoJSON)
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let features = try #require(object["features"] as? [[String: Any]])

    #expect(features.isEmpty)
}

@Test func exportsCarryBridgePiersAndTunnelPortals() throws {
    let project = engineeringExportProject()
    let svgData = try MapExporter.data(for: project, format: .svg)
    let svg = try #require(String(data: svgData, encoding: .utf8))

    #expect(svg.contains(#"id="bridge-piers""#))
    #expect(svg.contains(#"id="tunnel-portals""#))
    #expect(svg.contains(#"data-role="entrance""#))
    #expect(svg.contains(#"data-role="exit""#))

    let geoJSON = try MapExporter.data(for: project, format: .geoJSON)
    let object = try #require(
        JSONSerialization.jsonObject(with: geoJSON) as? [String: Any]
    )
    let features = try #require(object["features"] as? [[String: Any]])
    let featureTypes = features.compactMap {
        ($0["properties"] as? [String: Any])?["featureType"] as? String
    }

    #expect(featureTypes.contains("bridgePier"))
    #expect(featureTypes.filter { $0 == "tunnelPortal" }.count == 2)
}

@Test func exportsCarryHydrologyAndWatershedSemantics() throws {
    var project = RoadProject(
        name: "Hydrology",
        terrain: TerrainGenerator.generate(
            seed: 20260808,
            gridWidth: 65,
            gridHeight: 49,
            scenario: .riverAndLakes
        )
    )
    project.layerVisibility.showsWatersheds = true

    let svgData = try MapExporter.data(for: project, format: .svg)
    let svg = try #require(String(data: svgData, encoding: .utf8))
    #expect(svg.contains(#"id="watershed-boundaries""#))

    let data = try MapExporter.data(for: project, format: .geoJSON)
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let features = try #require(object["features"] as? [[String: Any]])
    let featureTypes = features.compactMap {
        ($0["properties"] as? [String: Any])?["featureType"] as? String
    }
    #expect(featureTypes.contains("hydrologySummary"))
    #expect(featureTypes.filter { $0 == "watershedOutlet" }.count == 4)
}

private func exportTestProject() -> RoadProject {
    let terrain = TerrainGenerator.generate(
        seed: 42,
        gridWidth: 33,
        gridHeight: 25
    )
    let road = RoadSegment(
        kind: .arterial,
        structure: .bridge,
        points: [
            RoadPoint(x: 100, y: 600),
            RoadPoint(x: 1_500, y: 600),
        ],
        direction: .forward
    )
    return RoadProject(
        name: "Export & Test",
        terrain: terrain,
        roads: [road],
        theme: .coastal,
        mapScale: MapScale(metersPerPoint: 2)
    )
}

private func engineeringExportProject() -> RoadProject {
    let terrain = TerrainGenerator.generate(
        seed: 42,
        gridWidth: 81,
        gridHeight: 61
    )
    let bridge = RoadSegment(
        kind: .arterial,
        structure: .bridge,
        points: [
            RoadPoint(x: 100, y: 480),
            RoadPoint(x: 700, y: 480),
        ]
    )
    let tunnel = RoadSegment(
        kind: .arterial,
        structure: .tunnel,
        points: [
            RoadPoint(x: 900, y: 780),
            RoadPoint(x: 1_300, y: 780),
        ]
    )
    let mapScale = MapScale.standard
    let structures = [bridge, tunnel].flatMap {
        RoadEngineeringPlanner.evaluate(
            road: $0,
            terrain: terrain,
            mapScale: mapScale
        ).structures
    }
    return RoadProject(
        name: "Engineering Export",
        terrain: terrain,
        roads: [bridge, tunnel],
        engineeringStructures: structures,
        mapScale: mapScale
    )
}


@Test func geographicExportsCarryLanduseAttributionAndWGS84() throws {
    let project = try geographicExportProject()
    let data = try MapExporter.data(for: project, format: .geoJSON)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["coordinateSystem"] as? String == "WGS84 longitude, latitude (EPSG:4326)")
    #expect(object["attribution"] as? String == "© OpenStreetMap contributors")
    let features = try #require(object["features"] as? [[String: Any]])
    let types = features.compactMap { ($0["properties"] as? [String: Any])?["featureType"] as? String }
    #expect(types.contains("water"))
    #expect(types.contains("building"))
    #expect(!types.contains("shoreline"))
    #expect(!types.contains("hydrologySummary"))
    let road = try #require(features.first { ($0["properties"] as? [String: Any])?["featureType"] as? String == "road" })
    let geometry = try #require(road["geometry"] as? [String: Any])
    let coordinates = try #require(geometry["coordinates"] as? [[Double]])
    #expect(abs(coordinates[0][0] - 116.4) < 0.0000001)
    #expect(abs(coordinates[0][1] - 39.9) < 0.0000001)
    let svgData = try MapExporter.data(for: project, format: .svg)
    let svg = try #require(String(data: svgData, encoding: .utf8))
    #expect(XMLParser(data: svgData).parse())
    #expect(svg.contains("© OpenStreetMap contributors"))
    #expect(svg.contains("data-feature-kind=\"building\""))
    #expect(!svg.contains("terrain-smooth"))
}

@Test func geographicRasterAndSVGRespectLayerVisibility() throws {
    var project = try geographicExportProject()
    // Inspect the actual PNG pixel inside the imported water polygon.
    func waterPixel(_ project: RoadProject) throws -> [UInt8] {
        let png = try MapExporter.data(for: project, format: .png)
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try #require(CGContext(data: nil, width: 1600, height: 1200, bitsPerComponent: 8, bytesPerRow: 6400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1600, height: 1200))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        // Read both y orientations at the centre of a vertically symmetric polygon.
        let index = (600 * 1600 + 400) * 4
        return [bytes[index], bytes[index+1], bytes[index+2]]
    }
    let water = try waterPixel(project)
    #expect(water[2] > water[0] + 25)
    project.layerVisibility.showsHydrology = false
    let land = try waterPixel(project)
    #expect(land[0] > land[2])
    let svg = try #require(String(data: MapExporter.data(for: project, format: .svg), encoding: .utf8))
    #expect(!svg.contains("data-feature-kind=\"water\""))
    #expect(svg.contains("data-feature-kind=\"building\""))
    project.layerVisibility.showsTerrain = false
    let hidden = try #require(String(data: MapExporter.data(for: project, format: .svg), encoding: .utf8))
    #expect(!hidden.contains("geographic-features"))
    #expect(hidden.contains("map-attribution"))
}

private func geographicExportProject() throws -> RoadProject {
    var project = RoadProject(name: "Geographic", terrain: TerrainGenerator.generate(seed: 42), roads: [
        RoadSegment(kind: .street, points: [RoadPoint(x: 800, y: 600), RoadPoint(x: 1000, y: 600)])
    ])
    let bounds = try GeoBounds(minLatitude: 39.89, minLongitude: 116.39, maxLatitude: 39.91, maxLongitude: 116.41)
    project.mapScale = MapScale(metersPerPoint: bounds.metersPerPoint)
    project.realWorldMap = RealWorldMap(bounds: bounds, source: .osmXML, attribution: "© OpenStreetMap contributors", features: [
        GeoMapFeature(kind: .water, points: [RoadPoint(x: 300,y: 300),RoadPoint(x: 500,y: 300),RoadPoint(x: 500,y: 900),RoadPoint(x: 300,y: 900)]),
        GeoMapFeature(kind: .building, points: [RoadPoint(x: 1000,y: 300),RoadPoint(x: 1040,y: 300),RoadPoint(x: 1040,y: 350),RoadPoint(x: 1000,y: 350)])
    ], elevation: nil, summary: GeoImportSummary(inputPointCount: 10, retainedPointCount: 10, roadCount: 1, featureCount: 2, simplificationMeters: 8, warnings: []))
    return project
}

@Test func terrainReliefUsesActualSlopeAndLeavesMissingCellsTransparent() throws {
    func shadedPixels(_ meters: [Double?]) throws -> Int {
        let context = try #require(CGContext(data: nil, width: 1600, height: 1200, bitsPerComponent: 8, bytesPerRow: 6400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        CartographicRenderer.drawRelief(width: 3, height: 3, meters: meters, widthMeters: 1600, heightMeters: 1200, in: context)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<(1600 * 1200)).filter { bytes[$0 * 4 + 3] > 0 }.count
    }
    #expect(try shadedPixels(Array(repeating: nil, count: 9)) == 0)
    #expect(try shadedPixels(Array(repeating: 100, count: 9)) == 0)
    #expect(try shadedPixels([0,300,600,0,300,600,0,300,600]) > 0)
}

@Test func viewportExportsPreserveFrameAndClipRoadGeometry() throws {
    let project = exportTestProject()
    let view = MapExportViewport(camera: CanvasViewport(scale: 2, translation: .init(x: -1000, y: -800)), width: 800, height: 600)
    let options = MapExportOptions(viewport: view, showsTitle: false, showsScale: false, showsInformation: false)
    let png = try MapExporter.data(for: project, format: .png, options: options)
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 800)
    #expect(image.height == 600)
    let pdf = try MapExporter.data(for: project, format: .pdf, options: options)
    let provider = try #require(CGDataProvider(data: pdf as CFData))
    let page = try #require(CGPDFDocument(provider)?.page(at: 1))
    #expect(page.getBoxRect(.mediaBox).size == CGSize(width: 800, height: 600))
    let svg = try MapExporter.data(for: project, format: .svg, options: options)
    #expect(XMLParser(data: svg).parse())
    let text = String(decoding: svg, as: UTF8.self)
    #expect(!text.contains("id=\"export-scale\""))
    #expect(!text.contains(">Export &amp; Test</text>"))
    let data = try MapExporter.data(for: project, format: .geoJSON, options: options)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let features = try #require(object["features"] as? [[String: Any]])
    let road = try #require(features.first { ($0["properties"] as? [String: Any])?["featureType"] as? String == "road" })
    let geometry = try #require(road["geometry"] as? [String: Any])
    let coordinates = try #require(geometry["coordinates"] as? [[Double]])
    #expect(coordinates == [[1000, 1200], [1800, 1200]])

    let hydroSummary = features.first { ($0["properties"] as? [String: Any])?["featureType"] as? String == "hydrologySummary" }
    #expect(hydroSummary != nil)
    #expect((hydroSummary?["properties"] as? [String: Any])?["scope"] as? String == "fullProject")

    let viewOptionsWithInfo = MapExportOptions(viewport: view, showsTitle: true, showsScale: false, showsInformation: true)
    let svgWithInfo = String(decoding: try MapExporter.data(for: project, format: .svg, options: viewOptionsWithInfo), as: UTF8.self)
    #expect(svgWithInfo.contains("当前视野"))
}

@Test func exportOptionsControlTextAndRetainRequiredSource() throws {
    let project = try geographicExportProject()
    let options = MapExportOptions(showsTitle: false, showsScale: false, showsInformation: true, showsAttribution: false)
    let svg = String(decoding: try MapExporter.data(for: project, format: .svg, options: options), as: UTF8.self)
    #expect(!svg.contains(">Geographic</text>"))
    #expect(!svg.contains("id=\"export-scale\""))
    #expect(svg.contains("条道路</text>"))
    #expect(svg.contains("© OpenStreetMap contributors"))
    let full = try MapExporter.data(for: project, format: .geoJSON)
    #expect(try MapExporter.data(for: project, format: .geoJSON, options: options) == full)
}
