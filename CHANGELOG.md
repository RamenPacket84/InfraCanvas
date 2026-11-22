# Changelog

All notable changes to InfraCanvas will be documented here.

## 0.2.2 - 2026-11-22

- Updated the app icon to match the CRT style of ShellRef and Terminal Atlas.
- Gave each window its own board and kept document commands focused on the active window.
- Grouped continuous Inspector typing into single undo actions.
- Corrected the Up and Down arrow key directions on the canvas.

## 0.2.1 - 2026-08-23

- Fixed undo and redo dirty-state tracking relative to the last saved board.
- Made Save As keep the current document unchanged when writing fails.
- Rejected board files created by newer, unsupported document schemas.
- Improved elbow connector routing around dense obstacle layouts.
- Added regression coverage for persistence, schema compatibility, and routing.
- Updated the macOS app to build 3.

## 0.2.0 - 2026-07-11

- Added manual bend points for elbow connectors.
- Added draggable connector bend handles with snap-to-grid support.
- Added connector actions for adding, removing, and resetting manual bends.
- Preserved manual connector routes through save/load, copy, duplicate, undo, and export.

## 0.1.0 - 2026-07-03

- Initial open-source release preparation.
- Native macOS canvas for mapping infrastructure, systems, and connected ideas.
- Component catalog, connect tool, elbow routing, labels, grouping, export, and typed connectors.
