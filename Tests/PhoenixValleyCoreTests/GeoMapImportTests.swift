import Foundation
import Testing
@testable import PhoenixValleyCore

private func osm(_ body: String) -> Data { Data("<osm version=\"0.6\">\(body)</osm>".utf8) }
private let squareNodes = """
<node id="1" lat="25" lon="121"/><node id="2" lat="25" lon="121.002"/>
<node id="3" lat="25" lon="121.004"/><node id="4" lat="25.002" lon="121.002"/>
"""

@Test func geoSharedJunctionSurvivesSimplificationAndProjectReload() throws {
    let data = osm(squareNodes + """
    <way id="10"><nd ref="1"/><nd ref="2"/><nd ref="3"/><tag k="highway" v="primary"/><tag k="oneway" v="-1"/></way>
    <way id="11"><nd ref="2"/><nd ref="4"/><tag k="highway" v="residential"/></way>
    """)
    let result = try GeoMapImporter.importMap(data:data, format:.osmXML, options:.init(simplificationMeters:100))
    #expect(result.project.roads.count == 3)
    #expect(result.project.roads.filter { $0.direction == .reverse }.count == 2)
    let junctions = result.project.roadNetwork.nodes.filter { result.project.roadNetwork.edges(at:$0.id).count == 3 }
    #expect(junctions.count == 1)
    let decoded = try JSONDecoder().decode(RoadProject.self,from:JSONEncoder().encode(result.project))
    #expect(decoded == result.project)
    #expect(decoded.realWorldMap?.attribution.contains("ODbL") == true)
    #expect(!decoded.terrain.hasElevationData)
}

@Test func geoNonSharedCrossingDoesNotInventIntersectionAndLevelsPreserved() throws {
    let data = osm("""
    <node id="1" lat="25" lon="121"/><node id="2" lat="25.004" lon="121.004"/>
    <node id="3" lat="25.004" lon="121"/><node id="4" lat="25" lon="121.004"/>
    <node id="5" lat="25.002" lon="121"/><node id="6" lat="25.002" lon="121.004"/>
    <way id="1"><nd ref="1"/><nd ref="2"/><tag k="highway" v="residential"/></way>
    <way id="2"><nd ref="3"/><nd ref="4"/><tag k="highway" v="residential"/></way>
    <way id="3"><nd ref="5"/><nd ref="6"/><tag k="railway" v="rail"/><tag k="bridge" v="yes"/></way>
    """)
    let p = try GeoMapImporter.importMap(data:data,format:.osmXML).project
    #expect(p.roadNetwork.nodes.count == 6)
    #expect(p.roads.count == 3)
    #expect(p.roads.contains { $0.kind == .railway && $0.level == .elevated })
    let reloaded = try JSONDecoder().decode(RoadProject.self,from:JSONEncoder().encode(p))
    #expect(reloaded.roadNetwork == p.roadNetwork)
}

@Test func geoCropClipsRoadAndPolygonToRequestedRegionWithoutDistortion() throws {
    let bounds = try GeoBounds.around(latitude:25,longitude:121,widthMeters:1000,heightMeters:1000)
    let data = osm("""
    <node id="1" lat="25" lon="120.99"/><node id="2" lat="25" lon="121.01"/>
    <node id="3" lat="24.99" lon="120.99"/><node id="4" lat="24.99" lon="121.01"/>
    <node id="5" lat="25.01" lon="121.01"/><node id="6" lat="25.01" lon="120.99"/>
    <way id="1"><nd ref="1"/><nd ref="2"/><tag k="highway" v="residential"/></way>
    <way id="2"><nd ref="3"/><nd ref="4"/><nd ref="5"/><nd ref="6"/><nd ref="3"/><tag k="natural" v="water"/></way>
    """)
    let result = try GeoMapImporter.importMap(data:data,format:.osmXML,options:.init(bounds:bounds))
    let road = try #require(result.project.roads.first)
    #expect(abs(road.points.first!.x-200) < 0.01)
    #expect(abs(road.points.last!.x-1400) < 0.01)
    #expect(result.project.realWorldMap?.features.first?.kind == .water)
    #expect(result.project.realWorldMap!.features[0].points.allSatisfy { $0.x >= 199.99 && $0.x <= 1400.01 && $0.y >= -0.01 && $0.y <= 1200.01 })
    #expect(abs(result.project.mapScale.metersPerPoint-1000/1200) < 0.001)
}

@Test func geoRejectsMissingNodesInvalidXMLUnsafeEntitiesAndLimits() throws {
    let bad: [Data] = [
        osm("<way id=\"1\"><nd ref=\"8\"/><nd ref=\"9\"/><tag k=\"highway\" v=\"road\"/></way>"),
        Data("<osm><node".utf8),
        Data("<!DOCTYPE osm [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><osm/>".utf8),
        Data(repeating:32,count:GeoMapImporter.maximumBytes+1),
        osm("<node id=\"1\" lat=\"nan\" lon=\"121\"/>")
    ]
    for data in bad { #expect(throws:GeoImportError.self) { try GeoMapImporter.importMap(data:data,format:.osmXML) } }
    #expect(throws:GeoImportError.self) { try GeoBounds.around(latitude:25,longitude:121,widthMeters:20_000,heightMeters:2000) }
    let big = osm("<node id=\"1\" lat=\"25\" lon=\"121\"/><node id=\"2\" lat=\"26\" lon=\"121\"/><way id=\"1\"><nd ref=\"1\"/><nd ref=\"2\"/><tag k=\"highway\" v=\"road\"/></way>")
    #expect(throws:GeoImportError.self) { try GeoMapImporter.importMap(data:big,format:.osmXML) }
}

@Test func geoKMLUsesLongitudeLatitudeAndDoesNotInventDEMsOrCrossings() throws {
    let data = Data("""
    <kml xmlns="http://www.opengis.net/kml/2.2"><Document>
    <Placemark><name>路径</name><LineString><altitudeMode>absolute</altitudeMode><coordinates>121,25,600 121.001,25.001,800</coordinates></LineString></Placemark>
    <Placemark><LineString><coordinates>121,25.001 121.001,25</coordinates></LineString></Placemark>
    <Placemark><Polygon><outerBoundaryIs><LinearRing><coordinates>121,25 121.001,25 121.001,25.001 121,25</coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark>
    </Document></kml>
    """.utf8)
    let p = try GeoMapImporter.importMap(data:data,format:.kml).project
    #expect(p.roads.count == 2)
    #expect(p.roadNetwork.nodes.count == 4)
    #expect(p.realWorldMap?.features.count == 1)
    #expect(p.realWorldMap?.elevation == nil)
    #expect(!p.terrain.hasElevationData)
    #expect(p.roads[0].points[0].x < p.roads[0].points[1].x)
    #expect(p.roads[0].points[0].y > p.roads[0].points[1].y)
}

@Test func geoASCKeepsTrueMetersNorthFirstMissingCellsAndRequiresCRS() throws {
    let data = Data("""
    ncols 3
    nrows 3
    xllcenter 121
    yllcenter 25
    cellsize 0.001
    NODATA_value -9999
    100 200 -9999
    50 60 70
    -20 0 10
    """.utf8)
    #expect(throws:GeoImportError.self) { try GeoMapImporter.importMap(data:data,format:.esriASCII) }
    let p = try GeoMapImporter.importMap(data:data,format:.esriASCII,options:.init(demCoordinateSystem:.wgs84)).project
    let dem = try #require(p.realWorldMap?.elevation)
    #expect(dem.minimumMeters == -20)
    #expect(dem.maximumMeters == 200)
    #expect(dem.meters.contains(nil))
    #expect(dem.meters.contains(100))
    #expect(dem.width == 129 && dem.height == 97)
    #expect(!p.terrain.hasElevationData)
    #expect(try JSONDecoder().decode(RoadProject.self,from:JSONEncoder().encode(p)) == p)
}

@Test func geoOldVersionTenProjectHasNoImportedMetadata() throws {
    let project = RoadProject(name:"旧图")
    var json = try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(project)) as? [String:Any])
    json["formatVersion"] = 10; json.removeValue(forKey:"realWorldMap")
    let old = try JSONDecoder().decode(RoadProject.self,from:JSONSerialization.data(withJSONObject:json))
    #expect(old.realWorldMap == nil)
}

@Test func geoNodeAndRoadBudgetsRejectDenseRegionsBeforeNetworkRebuild() throws {
    let nodes = (0...GeoMapImporter.maximumInputPoints).map { "<node id=\"\($0)\" lat=\"25\" lon=\"121\"/>" }.joined()
    #expect(throws:GeoImportError.self) { try GeoMapImporter.importMap(data:osm(nodes),format:.osmXML) }
    let roads = (0...GeoMapImporter.maximumRoadEdges).map { "<way id=\"\($0)\"><nd ref=\"1\"/><nd ref=\"2\"/><tag k=\"highway\" v=\"road\"/></way>" }.joined()
    #expect(throws:GeoImportError.self) { try GeoMapImporter.importMap(data:osm(squareNodes+roads),format:.osmXML) }
}

@Test func geoKMLHolesAreOmittedAndExternalLinksAreNeverFetched() throws {
    let data = Data("""
    <kml><Document><NetworkLink><Link><href>https://invalid.example/never-fetch</href></Link></NetworkLink>
    <Placemark><Polygon><outerBoundaryIs><LinearRing><coordinates>121,25 121.001,25 121.001,25.001 121,25</coordinates></LinearRing></outerBoundaryIs>
    <innerBoundaryIs><LinearRing><coordinates>121.0001,25.0001 121.0002,25.0001 121.0001,25.0002 121.0001,25.0001</coordinates></LinearRing></innerBoundaryIs></Polygon></Placemark>
    <Placemark><LineString><coordinates>121,25 121.001,25.001</coordinates></LineString></Placemark></Document></kml>
    """.utf8)
    let result = try GeoMapImporter.importMap(data:data,format:.kml)
    #expect(result.project.realWorldMap?.features.isEmpty == true)
    #expect(result.project.roads.count == 1)
    #expect(result.summary.warnings.contains { $0.contains("内环") })
}

@Test func geoOptionalLocalOSMSampleExportsReviewableProject() throws {
    guard let path = ProcessInfo.processInfo.environment["PHOENIX_GEO_SAMPLE"] else { return }
    let bounds = try GeoBounds(minLatitude:25.03130,minLongitude:121.56053,maxLatitude:25.03670,maxLongitude:121.56847)
    let result = try GeoMapImporter.importMap(data:Data(contentsOf:URL(fileURLWithPath:path)),format:.osmXML,options:.init(name:"台北真实地图",bounds:bounds))
    if let output = ProcessInfo.processInfo.environment["PHOENIX_GEO_OUTPUT"] {
        try JSONEncoder().encode(result.project).write(to:URL(fileURLWithPath:output))
    }
    print("REAL OSM SAMPLE: \(result.summary.description)")
    #expect(result.project.realWorldMap != nil)
}

@Test func geoSharedOSMBridgeApproachHasExplicitTraversableTransition() throws {
    let data = osm(squareNodes + """
    <way id="10"><nd ref="1"/><nd ref="2"/><tag k="highway" v="primary"/><tag k="oneway" v="yes"/></way>
    <way id="11"><nd ref="2"/><nd ref="3"/><tag k="highway" v="primary"/><tag k="bridge" v="yes"/><tag k="oneway" v="yes"/></way>
    """)
    let network = try GeoMapImporter.importMap(data:data,format:.osmXML).project.roadNetwork
    let relation = try #require(network.relations.first)
    #expect(relation.kind == .structureTransition)
    let ground = try #require(network.edges.first { $0.level == .ground })
    let bridge = try #require(network.edges.first { $0.level == .elevated })
    #expect(network.adjacentNodeIDs(to:ground.endNodeID).contains(bridge.startNodeID))
    #expect(!network.adjacentNodeIDs(to:bridge.startNodeID).contains(ground.endNodeID))
}

@Test func geoTinyASCGridDoesNotOverflowIntegerSampling() throws {
    let data = Data("""
    ncols 2
    nrows 2
    xllcorner 0
    yllcorner 0
    cellsize 1e-25
    1 2 3 4
    """.utf8)
    let result = try GeoMapImporter.importMap(data: data, format: .esriASCII,
        options: .init(demCoordinateSystem: .wgs84))
    #expect(result.project.realWorldMap?.elevation?.meters.contains(nil) == true)
}
