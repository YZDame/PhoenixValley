import Foundation
import Testing
@testable import PhoenixValleyCore

@Test func mapLayerVisibilityDefaultsToShowingEveryLayer() {
    let visibility = MapLayerVisibility()

    #expect(visibility.showsTerrain)
    #expect(RoadKind.allCases.allSatisfy { visibility.isVisible($0) })
}

@Test func mapLayerVisibilityRoundTripsWithProject() throws {
    var visibility = MapLayerVisibility(showsTerrain: false)
    visibility.setVisible(false, for: .motorway)
    visibility.setVisible(false, for: .railway)
    let project = RoadProject(
        terrain: layerTestTerrain(),
        layerVisibility: visibility
    )

    let decoded = try JSONDecoder().decode(
        RoadProject.self,
        from: JSONEncoder().encode(project)
    )

    #expect(!decoded.layerVisibility.showsTerrain)
    #expect(!decoded.layerVisibility.isVisible(.motorway))
    #expect(decoded.layerVisibility.isVisible(.arterial))
    #expect(!decoded.layerVisibility.isVisible(.railway))
}

@Test func versionFiveProjectWithoutLayerSettingsUsesVisibleDefaults() throws {
    let project = RoadProject(terrain: layerTestTerrain())
    let data = try JSONEncoder().encode(project)
    var object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    object["formatVersion"] = 5
    object.removeValue(forKey: "layerVisibility")

    let decoded = try JSONDecoder().decode(
        RoadProject.self,
        from: JSONSerialization.data(withJSONObject: object)
    )

    #expect(decoded.layerVisibility.showsTerrain)
    #expect(RoadKind.allCases.allSatisfy {
        decoded.layerVisibility.isVisible($0)
    })
}

private func layerTestTerrain() -> TerrainLayout {
    TerrainLayout(
        seed: 1,
        shoreline: [
            RoadPoint(x: 0, y: 0),
            RoadPoint(x: 1_600, y: 0),
            RoadPoint(x: 800, y: 1_200),
        ]
    )
}
