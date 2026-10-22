import Foundation
import Testing
@testable import PhoenixValleyCore

private func near(_ lhs: RoadPoint, _ rhs: RoadPoint) -> Bool {
    lhs.distance(to: rhs) < 0.000001
}

@Test func viewportInverseIncludesRotationTranslationAndScale() {
    for angle in [-Double.pi, -1.2, 0, 0.7, Double.pi] {
        let camera = CanvasViewport(scale: 2.7, rotation: angle, translation: RoadPoint(x: -350, y: 200))
        for point in [RoadPoint(x: 0, y: 0), RoadPoint(x: 1380, y: 920), RoadPoint(x: -30, y: 200)] {
            #expect(near(camera.worldPoint(for: camera.screenPoint(for: point)), point))
        }
    }
}

@Test func viewportCombinedZoomAndRotationPreservesFingerAnchor() {
    var camera = CanvasViewport(scale: 0.8, rotation: 0.4, translation: RoadPoint(x: 20, y: -60))
    let anchor = RoadPoint(x: 314, y: 297)
    let world = camera.worldPoint(for: anchor)
    camera.navigate(scaleFactor: 1.7, rotationDelta: 0.9, anchor: anchor)
    #expect(near(camera.screenPoint(for: world), anchor))
    camera.pan(by: RoadPoint(x: 17, y: -11))
    #expect(near(camera.screenPoint(for: world), anchor + RoadPoint(x: 17, y: -11)))
}

@Test func viewportZoomLimitsStillPreserveAnchor() {
    var camera = CanvasViewport()
    let anchor = RoadPoint(x: 200, y: 300)
    let world = camera.worldPoint(for: anchor)
    camera.navigate(scaleFactor: 100, anchor: anchor, minimumScale: 0.2)
    #expect(camera.scale == 4)
    #expect(near(camera.screenPoint(for: world), anchor))
    camera.navigate(scaleFactor: 0.00001, anchor: anchor, minimumScale: 0.2)
    #expect(camera.scale == 0.2)
    #expect(near(camera.screenPoint(for: world), anchor))
}

@Test func viewportNorthResetTakesShortestWrappedHeading() {
    var camera = CanvasViewport(rotation: 2 * .pi - 0.1)
    #expect(abs(camera.rotation + 0.1) < 0.000001)
    let center = RoadPoint(x: 500, y: 400)
    let world = camera.worldPoint(for: center)
    camera.navigate(rotationDelta: -camera.rotation, anchor: center)
    #expect(camera.isNorthUp)
    #expect(near(camera.screenPoint(for: world), center))
}

@Test func viewportBoundsContainRotatedMapAndRecenterSmallMap() {
    var camera = CanvasViewport(scale: 0.2, rotation: .pi / 2, translation: RoadPoint(x: 10000, y: -10000))
    camera.constrain(to: RoadPoint(x: 1000, y: 800))
    #expect(near(camera.screenPoint(for: RoadPoint(x: 800, y: 600)), RoadPoint(x: 500, y: 400)))
    camera = CanvasViewport(scale: 2, rotation: .pi / 3, translation: RoadPoint(x: 10000, y: 10000))
    camera.constrain(to: RoadPoint(x: 1000, y: 800))
    let corners = [RoadPoint(x: 0, y: 0), RoadPoint(x: 1600, y: 0), RoadPoint(x: 0, y: 1200), RoadPoint(x: 1600, y: 1200)].map(camera.screenPoint)
    #expect(abs(corners.map(\.x).min()! - 36) < 0.000001)
    #expect(abs(corners.map(\.y).min()! - 36) < 0.000001)
}

@Test func rotatedSelectionDeltaAndScreenRadiusRemainCorrect() {
    let camera = CanvasViewport(scale: 2, rotation: .pi / 2)
    let origin = camera.worldPoint(for: RoadPoint(x: 200, y: 200))
    let moved = camera.worldPoint(for: RoadPoint(x: 240, y: 200))
    #expect(near(moved - origin, RoadPoint(x: 0, y: -20)))
    #expect(abs(moved.distance(to: origin) * camera.scale - 40) < 0.000001)
}

@Test func viewportSettlesNearNorthWithoutChangingZoomOrFingerAnchor() {
    let anchor = RoadPoint(x: 420, y: 310)
    for degrees in [-2.0, -0.01, 0, 0.01, 2] {
        var camera = CanvasViewport(scale: 0.07, rotation: degrees * .pi / 180,
                                    translation: RoadPoint(x: -90, y: 25))
        let world = camera.worldPoint(for: anchor)
        camera.snapToNorthIfClose(anchor: anchor)
        #expect(camera.rotation == 0)
        #expect(camera.scale == 0.07)
        #expect(near(camera.screenPoint(for: world), anchor))
    }
}

@Test func viewportPreservesIntentionalHeadingOutsideNorthSnapRange() {
    for degrees in [-179.0, -2.01, 2.01, 179] {
        var camera = CanvasViewport(scale: 1.3, rotation: degrees * .pi / 180,
                                    translation: RoadPoint(x: -90, y: 25))
        let before = camera
        camera.snapToNorthIfClose(anchor: RoadPoint(x: 420, y: 310))
        #expect(camera == before)
    }
}
