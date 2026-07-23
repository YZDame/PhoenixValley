# RoadSketch

RoadSketch is an iPad-first road-network sketching sandbox. Apple Pencil draws semantic roads; fingers pan and zoom the terrain.

## Current prototype

- Four tools: motorway, arterial, street, and railway
- Pencil-sweep eraser with multi-road preview and single-step undo
- Ground, elevated, and tunnel levels
- Stroke filtering, smoothing, simplification, direction snapping, and endpoint snapping
- One-finger pan and two-finger zoom on iPad; one-finger drawing fallback in Simulator
- Seeded geographic terrain with coherent coastlines, mountain chains, branches, saddles, valleys, basins, coastal plains, and contour lines
- Topographic, planning, and monochrome map themes
- Native collapsible iPad sidebar with a multi-map library
- Persistent map groups with visible rename, duplicate, move, and delete actions
- Native split-view sidebar control, a corner-aligned Apple Maps-style appearance popover, and a draggable Pencil palette that docks horizontally at the bottom or vertically at either side
- Rename, duplicate, delete, undo, redo, and per-project JSON autosave
- App Shortcuts for opening the canvas with a selected road tool or creating a random map

## Run

1. Install the full Xcode application.
2. Open `RoadSketch.xcodeproj`.
3. Select the `RoadSketch` scheme and an iPad Simulator or connected iPad.
4. Set your Development Team under Signing & Capabilities when installing on a physical iPad.
5. Build and run.

The app targets iPadOS 17 or later. The core geometry module is also a Swift package and can be tested independently with `swift test` in a correctly matched Xcode toolchain.
