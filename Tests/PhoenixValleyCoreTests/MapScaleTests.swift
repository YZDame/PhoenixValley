import Foundation
import Testing
@testable import PhoenixValleyCore

@Test func mapScaleConvertsCanvasDistancesAndReportsPhysicalExtent() {
    let scale = MapScale(metersPerPoint: 2)

    #expect(scale.widthMeters == 3_200)
    #expect(scale.heightMeters == 2_400)
    #expect(scale.meters(forCanvasDistance: 125) == 250)
    #expect(scale.canvasDistance(forMeters: 250) == 125)
}

@Test func mapScaleClampsUnsupportedValues() {
    #expect(MapScale(metersPerPoint: 0).metersPerPoint == 0.1)
    #expect(MapScale(metersPerPoint: 100).metersPerPoint == 100)
}

@Test func versionSixProjectWithoutMapScaleUsesStandardScale() throws {
    let project = RoadProject(name: "旧比例项目")
    var object = try #require(
        JSONSerialization.jsonObject(
            with: JSONEncoder().encode(project)
        ) as? [String: Any]
    )
    object["formatVersion"] = 6
    object.removeValue(forKey: "mapScale")

    let decoded = try JSONDecoder().decode(
        RoadProject.self,
        from: JSONSerialization.data(withJSONObject: object)
    )

    #expect(decoded.mapScale == .standard)
}

@Test func plannerConfigurationConvertsPhysicalThresholdsToCanvasUnits() {
    let standard = AutoStructurePlannerConfiguration.standard
    let scaled = standard.scaledForCanvas(metersPerPoint: 2)

    #expect(scaled.sampleSpacing == standard.sampleSpacing / 2)
    #expect(scaled.elevationScale == standard.elevationScale / 2)
    #expect(
        scaled.crossSectionProbeDistance
            == standard.crossSectionProbeDistance / 2
    )
    #expect(
        scaled.crossingEndpointExclusionDistance
            == standard.crossingEndpointExclusionDistance / 2
    )
    #expect(scaled.steepGradeThreshold == standard.steepGradeThreshold)
    #expect(scaled.crossingMinimumAngle == standard.crossingMinimumAngle)
    #expect(scaled.motorwayRule == standard.motorwayRule)
}
