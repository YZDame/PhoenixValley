<p align="center">
  <img src="PhoenixValleyApp/Assets.xcassets/AppIcon.appiconset/PhoenixValley-AppIcon-1024.png" width="128" height="128" alt="Phoenix Valley app icon">
</p>

<h1 align="center">Phoenix Valley</h1>

<p align="center">
  An iPad-first road-network sandbox for drawing terrain-aware transport maps with Apple Pencil.
</p>

<p align="center">
  <a href="README.zh-Hans.md">中文 README</a>
</p>

## Overview

Phoenix Valley is a native iPadOS planning game prototype about building road networks across generated terrain. It focuses on the tactile loop of sketching roads with Apple Pencil, reviewing the engineering consequences, and shaping a readable transport map over mountains, water, valleys, and crossings.

The project is currently a local prototype, not an App Store release. It targets iPadOS 17 or later, with the core geometry and planning model packaged as a testable Swift module.

![IMG_0916](https://pauline.oss-cn-shenzhen.aliyuncs.com/img/IMG_0916.PNG)

## Pure Design Sandbox

New maps start as an empty 32 × 24 km world with no prebuilt road network. Terrain, roads, bridges, tunnels, and ramps share one world-coordinate system, so zooming, rotating, resetting north, and reopening a save never detach roads from the terrain.

The canvas uses MapKit's native camera, navigation gestures, compass, and scale control. A replacement overlay removes existing real-world roads from generated worlds. The palette works with both finger and Apple Pencil: enable Hand Drawing to sketch with a finger, or turn it off for one-finger navigation while Pencil remains available for drawing.

The export panel previews the actual renderer and offers full-map or current-viewport output, four file formats, coordinated theme selection, and optional title, scale, extent/road count, and source attribution text.

## Experience

- Draw motorway, arterial, street, and railway routes with Apple Pencil or a finger.
- Use every palette button, segmented control, and slider with either finger or Apple Pencil.
- Work with ground roads, elevated roads, tunnels, bridges, ramps, and explicit interchanges.
- Review terrain-aware bridge, tunnel, slope, water, and crossing recommendations before applying them.
- Edit existing networks with selection, marquee selection, moving, road-type changes, undo, redo, and local erasing.
- Organize a multi-map library with groups, previews, rename, duplicate, move, and delete actions.
- Choose from six refined themes: Misty Terrain, Silk Planning, Graphite Ink, Coastal Bay, Midnight Blue, and Sage Forest.
- Export PNG, PDF, SVG, or GeoJSON from a live preview, choosing full-map or current-viewport output.

## iPadOS Design

Phoenix Valley uses native Apple platform patterns instead of a custom desktop-style shell:

- `NavigationSplitView` for the map library and canvas.
- A draggable Pencil palette that docks to the bottom, left, or right edge.
- Popovers and toolbar actions for appearance, export, editing, and project management.
- App Shortcuts for starting the canvas with a selected road tool or creating a random map.
- Local-first project storage with optional iCloud document container support in the app target.

## Engineering Model

The core model treats drawn strokes as semantic transport geometry rather than simple pixels. It maintains stable road sources, topology nodes and edges, directed traffic rules, structure transitions, bridge and tunnel engineering assets, and construction diagnostics. Terrain generation is seeded and deterministic, so map projects can be saved, tested, and reproduced.

The Swift package contains tests for stroke processing, topology, terrain generation, bridge and tunnel planning, ramp planning, traffic rules, map export, layer visibility, and persistence compatibility.

## Repository Layout

```text
PhoenixValleyApp/              Native iPadOS app target
Sources/PhoenixValleyCore/     Road, terrain, topology, export, and planning logic
Tests/PhoenixValleyCoreTests/  Core unit tests
Tests/PhoenixValleyCoreSmoke/  Smoke test entry point
Docs/                          Release, privacy, and App Store notes
```

## Requirements

- macOS with the full Xcode application installed
- iPadOS 17 or later target
- Swift 6 toolchain from Xcode
- Apple Developer signing setup for physical iPad installation

## Run

1. Open `PhoenixValley.xcodeproj` in Xcode.
2. Select the `PhoenixValley` scheme.
3. Choose an iPad Simulator or a connected iPad.
4. Set your Development Team under Signing & Capabilities when installing on a physical device.
5. Build and run.

## Test

Run the core package tests with a matching Xcode Swift toolchain:

```bash
swift test
```

## Status

Phoenix Valley is under active development. The current prototype has a functioning drawing canvas, generated terrain, topology-aware road editing, bridge and tunnel recommendations, interchange editing, traffic rules, project persistence, exports, and privacy documentation. Remaining work includes physical iPad Pencil testing, richer terrain systems, Apple Pencil advanced gestures, custom styles, more complete road design tools, and formal App Store release work.
