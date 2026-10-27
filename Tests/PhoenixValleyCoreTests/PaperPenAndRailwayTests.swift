import Foundation
import Testing
@testable import PhoenixValleyCore

@Suite("纸笔绘制体验与铁路车站测试")
struct PaperPenAndRailwayTests {

    @Test("工程规划比例尺支持 100km 大地图 (62.5 m/pt)")
    func scaledForCanvasSupportsLargeScaleMaps() {
        let base = AutoStructurePlannerConfiguration.standard
        let config62_5 = base.scaledForCanvas(metersPerPoint: 62.5)

        // Verify that 62.5 is used without being clamped to 10
        #expect(abs(config62_5.sampleSpacing - base.sampleSpacing / 62.5) < 0.000_1)
        #expect(abs(config62_5.minimumBridgeLength - base.minimumBridgeLength / 62.5) < 0.000_1)
        #expect(abs(config62_5.minimumTunnelLength - base.minimumTunnelLength / 62.5) < 0.000_1)
        #expect(abs(config62_5.tunnelPortalSearchDistance - base.tunnelPortalSearchDistance / 62.5) < 0.000_1)

        // Scale 100 (160km map)
        let config100 = base.scaledForCanvas(metersPerPoint: 100.0)
        #expect(abs(config100.sampleSpacing - base.sampleSpacing / 100.0) < 0.000_1)
    }

    @Test("立交预设模组全部可用且包含 6 种经典模组")
    func interchangeTemplatesInstantiation() {
        let templates = InterchangeTemplate.allTemplates
        #expect(templates.count == 6)

        let expectedIDs = ["t_junction", "cross_junction", "roundabout", "diamond", "trumpet", "cloverleaf"]
        #expect(templates.map(\.id) == expectedIDs)

        for template in templates {
            let instance = template.instantiate(center: RoadPoint(x: 800, y: 600), sizeScale: 1.0)
            #expect(!instance.roads.isEmpty, "Template \(template.id) should produce roads")
            #expect(!instance.roads.first!.points.isEmpty)
        }
    }

    @Test("铁路车站可创建、重命名并在 RoadProject 中正确序列化")
    func railwayStationProjectSerialization() throws {
        var project = RoadProject(name: "铁路网络测试")
        #expect(project.railwayStations.isEmpty)

        let station1 = RailwayStation(
            id: UUID(),
            name: "凤凰城中央站",
            point: RoadPoint(x: 500, y: 400),
            sourceRoadID: nil
        )
        let station2 = RailwayStation(
            id: UUID(),
            name: "山谷北站",
            point: RoadPoint(x: 800, y: 300),
            sourceRoadID: UUID()
        )
        project.railwayStations.append(contentsOf: [station1, station2])
        #expect(project.railwayStations.count == 2)

        // Codable roundtrip test
        let encoder = JSONEncoder()
        let data = try encoder.encode(project)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RoadProject.self, from: data)

        #expect(decoded.railwayStations.count == 2)
        #expect(decoded.railwayStations[0].name == "凤凰城中央站")
        #expect(decoded.railwayStations[0].point == RoadPoint(x: 500, y: 400))
        #expect(decoded.railwayStations[1].name == "山谷北站")
        #expect(decoded.railwayStations[1].sourceRoadID == station2.sourceRoadID)
        #expect(decoded.formatVersion == RoadProject.currentFormatVersion)
    }

    @Test("地形生成版本已升级到 10 且湖泊筛选使用原始未雕刻高程")
    func terrainGenerationVersionAndLakeFiltering() async throws {
        #expect(TerrainLayout.currentGenerationVersion == 10)

        let request = TerrainGenerationRequest(
            seed: 42,
            vertexCount: 32,
            gridWidth: 65,
            gridHeight: 49,
            scenario: .mountains
        )
        let terrain = try await TerrainGenerator.generate(request: request, progress: { _ in })
        #expect(terrain.gridWidth == 65)
        #expect(terrain.gridHeight == 49)
        #expect(terrain.waterLevel > 0)
        #expect(!terrain.elevations.isEmpty)
    }
}
