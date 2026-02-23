<p align="center">
  <img src=".github/icon.png" width="128" height="128" alt="Orbiter">
</p>

<h1 align="center">Orbiter</h1>

<p align="center">
  <strong>See where your disk space goes.</strong><br>
  A macOS disk space analyzer with an interactive sunburst chart.
</p>

## Requirements

- macOS 14.0+
- Xcode 16.0+ / Swift 5.9+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for Xcode project generation)

## Building

```bash
# Generate Xcode project (first time or after changing project.yml)
xcodegen generate

# Open in Xcode (recommended)
open Orbiter.xcodeproj

# Or build via command line
swift build
```

## Running

```bash
# Via Xcode: select Orbiter scheme and Run
# Or via command line (no sandbox):
swift run Orbiter
```

## Usage

1. Click "Select Folder" to choose a directory to analyze
2. Explore the sunburst chart - inner rings represent parent directories, outer rings show children
3. Single-click to select a file/folder and see details in the right panel
4. Double-click a folder to expand/collapse it in the chart
5. Use breadcrumbs or the back button to navigate
6. Right-click items to add favorites or open in Finder

## App Store Distribution

The app is sandbox-ready with:
- App Sandbox entitlements (`Orbiter.entitlements`)
- Security-scoped bookmarks for persistent favorites
- Privacy manifest (`PrivacyInfo.xcprivacy`)
- App icon asset catalog

To archive for the App Store, set your signing team in Xcode under Signing & Capabilities.

## License

MIT
