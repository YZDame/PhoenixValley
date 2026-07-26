import Foundation
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
