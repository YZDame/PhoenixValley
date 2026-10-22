# Canvas navigation

## Ground and sketch

RoadCanvasRepresentable supplies project data. RoadCanvasView owns transient interaction and renders the map in a CoreGraphics context. All drawing, erasing, selection, deformation and interchange hits already pass through worldPoint; accessibility elements pass through screenPoint. MapScale describes physical distances and must not change with viewing zoom.

Candidate A: rotate/scale a content UIView inside a scroll view. This offers native scrolling, but divides ownership between scroll offsets and a rotation transform, and makes the custom drawing/hit coordinates and screen-sized road widths harder to maintain.

Candidate B: one pure CanvasViewport similarity transform owns scale, rotation and translation. The drawing context and both point conversions use it. Native pan, pinch and rotation recognizers mutate it. Screen overlays remain ordinary upright UIKit controls. This concentrates inverse mapping and anchor math, preserves existing renderer structure, and is the chosen shape.

Public usage: viewport.screenPoint(for:), viewport.worldPoint(for:), viewport.navigate(scaleFactor:rotationDelta:anchor:), viewport.pan(by:), viewport.constrain(to:). The UIKit owner supplies current layout bounds and gesture state. The Core model does not persist view orientation into a road project.

## Controls and verification

UIKit UIButton supplies accessible zoom controls. A small custom compass UIControl is needed because MKCompassButton is tied to MKMapView; embedding a hidden map would add another camera solely for a control. The compass draws a north arrow and reports the actual viewport heading. It appears during rotation and while away from north, and resets about the viewport center along the shortest angular path. Reduce Motion resets immediately. When the last navigation gesture ends within two degrees of north, the viewport settles to exactly north while retaining its scale and finger anchor; this prevents incidental pinch rotation from leaving a nearly upright compass visible.

Core tests cover inversion, anchor preservation, combined transformations, heading wrapping, bounds and resize. iPad runtime checks must exercise simultaneous pinch/rotate/pan, north reset, zoom buttons, rotated selection/eraser, project switching and resize; a build alone is not runtime proof.

## Verified result

The final Core run passed 150 tests. On iPad Pro 13-inch (M5), iPadOS 26.5, both native UI tests passed: zoom buttons and pinch in/out, then rotation, pinch while rotated, compass visibility, and animated north reset. Run `swift test --disable-sandbox --build-system native` and the shared PhoenixValley scheme's CanvasNavigationUITests. UI test screenshots are retained in the xcresult; `Docs/CanvasNavigation-rotated.png` shows the rotated state. Physical Pencil, combined three-recognizer stress gestures, and narrow multiwindow layouts were not tested on hardware.
