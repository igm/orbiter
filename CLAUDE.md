# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Orbiter (DiskSpaceAnalyzer) is a macOS SwiftUI application that visualizes disk space usage through an interactive sunburst chart. It scans directories recursively and displays file/folder sizes in a radial, hierarchical visualization.

## Build Commands

```bash
# Generate Xcode project from project.yml
xcodegen generate

# Open in Xcode (recommended for development)
open Orbiter.xcodeproj

# Build via command line (SPM, no sandbox)
swift build

# Run via command line (SPM, no sandbox)
swift run Orbiter
```

## Architecture

### Data Flow
1. **FileScanner** (`Scanner.swift`) - ObservableObject that performs async directory scanning using TaskGroup for parallelism
2. **FileNode** (`Models.swift`) - Tree-structured data model representing files/folders with size calculations
3. **ContentView** - Main view managing navigation state and coordinating scanner with UI
4. **SunburstChart** (`Views.swift`) - Custom visualization using SwiftUI Shapes

### Key Patterns
- **Concurrent Scanning**: Uses `withTaskGroup` for parallel directory traversal; packages (`.app`, `.dmg`) are sized via synchronous enumeration
- **Navigation**: State-based breadcrumb navigation via `navigationPath: [FileNode]` array
- **Chart Rendering**: Rings built lazily; beyond depth 3, nodes expand only when explicitly toggled via double-click
- **App Sandbox**: Security-scoped URLs for file access; security-scoped bookmarks for persisting favorites across launches
- **Xcode Project**: Generated via XcodeGen from `project.yml`; `.xcodeproj` is gitignored

### File Responsibilities
| File | Purpose |
|------|---------|
| `OrbiterApp.swift` | App entry point, window configuration |
| `Scanner.swift` | Async file system scanning, security-scoped resource access, trash operations |
| `Models.swift` | `FileNode` tree model, `SliceData` for chart arcs |
| `ContentView.swift` | Main layout, navigation, state coordination, bookmark-based favorites |
| `Views.swift` | All UI components: SunburstChart, CenterCircle, FileInfoPanel, etc. |
| `project.yml` | XcodeGen spec for generating `Orbiter.xcodeproj` |
| `Orbiter.entitlements` | App Sandbox, user-selected file access, app-scoped bookmarks |
| `PrivacyInfo.xcprivacy` | Privacy manifest declaring FileTimestamp and DiskSpace API usage |
| `Assets.xcassets` | App icon asset catalog |

## Platform Requirements
- macOS 14.0+
- Swift 5.9
- SwiftUI (AppKit interop via `NSColor`, `NSWorkspace`)
- XcodeGen (for project generation)
