# InfraCanvas

InfraCanvas is a native macOS whiteboard app for mapping systems, infrastructure, and connected ideas. It is meant for brainstorming, planning, explaining, and learning systems with many connected parts, whether those parts are technical, operational, product, or process-oriented.

InfraCanvas is open source under the MIT License.

## Requirements

- macOS 14.0 or later.
- No separate SF Symbols installation is required. InfraCanvas uses the symbols provided by macOS and automatically falls back to a built-in symbol when a newer symbol is unavailable.

## Current Phase

- SwiftUI macOS app scaffolded as a Swift Package.
- Left component catalog with 140 searchable stencil templates for general planning, people, devices, network, identity, cloud, services, data, process, and security.
- Center canvas rendered by a custom AppKit view for precise panning, zooming, and dragging.
- Connect tool for drawing labeled obstacle-aware elbow arrows between components, with straight routing still available in the connector inspector or context menu.
- Typed connectors for marking links as generic, Ethernet, Wi-Fi, fiber, VPN, Power / PoE, or dependency paths with distinct line treatments.
- Quick connection actions for connecting any two selected components or starting a connector from a right-clicked component.
- Right inspector for editing selected component details, multiline notes, or selected connector labels.
- New/Open/Save/Save As support for `.infracanvas` board files.
- Multi-select with Shift-click, marquee selection, alignment, distribution, grouping, and ungrouping.
- Right-click context menus for components, groups, connectors, and empty canvas space.
- Multiline component notes for adding paragraph-style context to any component.
- Resizable components with expanded canvas previews for title, subtitle, and notes.
- Export to PNG or PDF with native macOS save panels.
- Layout polish with snap-to-grid, arrow-key nudging, and layer ordering.
- Undo/redo history for component, connector, grouping, layout, paste, delete, and arrange edits.
- Toolbar controls for select, pan, connect, default connector type, zoom, reset, add, and delete.
- SF Symbol availability checks with automatic fallback icons for Macs that do not include a newer symbol.
- Board background toggle for switching between grid and solid canvas backgrounds.
- Minimap navigator for keeping large boards oriented while panning and zooming.
- Blank launch board so each map starts from a clean canvas.

## Run

Open `InfraCanvas.xcodeproj` in Xcode, select the `InfraCanvas` app scheme, choose `My Mac`, and run it.

The Swift Package is still present because it is useful for command-line tests, but the Xcode project is the normal way to launch the macOS app.

From Terminal:

```sh
swift run InfraCanvas
```

## Build And Test

Run the test suite:

```sh
swift test
```

Build the app with Xcode's command-line tools:

```sh
xcodebuild -project InfraCanvas.xcodeproj -scheme InfraCanvas -configuration Debug -destination platform=macOS build
```

## Releases

Downloadable builds are published through GitHub Releases.

Current public release builds are Developer ID signed and notarized by Apple.
Maintainer release tooling lives in `scripts/package_release.sh`.

## Keyboard Shortcuts

- `Command-N`: create a new board.
- `Command-O`: open a board.
- `Command-S`: save the current board.
- `Shift-Command-S`: save as a new board file.
- `Command-E`: export as PNG.
- `Shift-Command-E`: export as PDF.
- `Command-C`: copy selected components.
- `Command-X`: cut selected components.
- `Command-V`: paste copied components.
- `Command-D`: duplicate selected components.
- `Command-Z`: undo the last editing action.
- `Shift-Command-Z`: redo the last undone editing action.
- `Command-L`: connect two selected components.
- `Shift-Command-N`: add a component.
- `Command-+`: zoom in.
- `Command--`: zoom out.
- `Command-0`: reset view.
- `Command-'`: toggle snap to grid.
- `Arrow Keys`: nudge selected components by 1 point.
- `Shift-Arrow Keys`: nudge selected components by one grid step.
- `Command-G`: group selected components.
- `Shift-Command-G`: ungroup selected components.
- `Command-]`: bring selected components forward.
- `Command-[`: send selected components backward.
- `Shift-Command-]`: bring selected components to front.
- `Shift-Command-[`: send selected components to back.
- `Delete`: delete the selected component or connector.

## Canvas Tips

- Drag the selected component's corner handle to resize it.
- Drag empty canvas space to pan around the board.
- Use a mouse scroll wheel to zoom in and out around the pointer.
- On a trackpad, two-finger scroll pans and `Option`-scroll zooms.
- Hold `Shift` while dragging empty canvas space to marquee-select components.
- Hold `Shift` while resizing to preserve the component's proportions.
- Hold `Option` while dragging or resizing to bypass snap-to-grid for that gesture.
- Use the toolbar background button or Canvas menu to switch between grid and solid backgrounds.
- Use the toolbar or Canvas menu to choose the default connector type before drawing. New connectors use that type and elbow routing by default.
- Select a connector to edit its label, arrow, label visibility, type, and straight/elbow routing in the inspector.
- Right-click a connector to switch between straight and elbow routing or choose a connector type. Ethernet, Wi-Fi, fiber, VPN, Power / PoE, and dependency connectors use distinct color, width, or dash treatments on the canvas and in exports.
- Elbow connectors choose source and target edges automatically, route around other components when a clear channel is available, and shift labels away from component collisions.

## Next Phase

- More advanced board layout helpers, such as guides and reusable page templates.
