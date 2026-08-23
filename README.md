# InfraCanvas

InfraCanvas is a native macOS whiteboard for mapping systems, infrastructure, workflows, and connected ideas.

## Download

Download the latest notarized version from [GitHub Releases](https://github.com/RamenPacket84/InfraCanvas/releases).

InfraCanvas requires macOS 14.0 or later.

To install it:

1. Download the latest `.dmg` file.
2. Open the disk image.
3. Drag InfraCanvas to the Applications folder.

## Features

- Searchable component catalog with templates for planning, people, devices, networks, identity, cloud, services, data, processes, and security.
- Infinite canvas with panning, zooming, snap-to-grid, and a minimap navigator.
- Straight and obstacle-aware elbow connectors with labels, arrows, typed link styles, and manual bend points.
- Multi-selection, marquee selection, grouping, alignment, distribution, and layer ordering.
- Editable component titles, subtitles, symbols, colors, sizes, and multiline notes.
- Save and open `.infracanvas` board files.
- Export boards as PNG or PDF.
- Undo and redo for editing, layout, connectors, grouping, and deletion.
- Grid or solid canvas backgrounds.

## Quick Start

1. Choose a component from the catalog and add it to the canvas.
2. Drag components into position and resize them from the corner handle.
3. Choose **Connect**, then click a source component and a target component.
4. Select a component or connector to edit it in the Inspector.
5. Save your board with **File → Save**.

To add a connector bend, right-click an elbow connector and choose **Add Bend Here**. Drag the bend handle to reposition it, or choose **Reset to Automatic Route** to return to automatic routing.

## Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `Command-N` | New board |
| `Command-O` | Open a board |
| `Command-S` | Save |
| `Shift-Command-S` | Save As |
| `Command-E` | Export as PNG |
| `Shift-Command-E` | Export as PDF |
| `Command-C` / `Command-X` / `Command-V` | Copy / cut / paste |
| `Command-D` | Duplicate selection |
| `Command-Z` / `Shift-Command-Z` | Undo / redo |
| `Command-L` | Connect two selected components |
| `Shift-Command-N` | Add a component |
| `Command-+` / `Command--` | Zoom in / out |
| `Command-0` | Reset the view |
| `Arrow Keys` | Nudge selection |
| `Shift-Arrow Keys` | Nudge by one grid step |
| `Command-G` / `Shift-Command-G` | Group / ungroup selection |
| `Delete` | Delete the selection |

## Canvas Tips

- Drag empty canvas space to pan.
- Use the scroll wheel to zoom. On a trackpad, hold `Option` while scrolling to zoom instead of pan.
- Hold `Shift` while dragging empty space to marquee-select components.
- Hold `Shift` while resizing to preserve proportions.
- Hold `Option` while dragging or resizing to bypass snap-to-grid for that gesture.
- Use the toolbar or Canvas menu to switch between grid and solid backgrounds.
- Select a connector to edit its label, arrow, visibility, type, and routing style.
- Right-click components, connectors, groups, or empty canvas space for additional actions.

## File Format

Boards are saved as portable `.infracanvas` files. You can share them with other InfraCanvas users.

## License

InfraCanvas is open source under the [MIT License](LICENSE).
