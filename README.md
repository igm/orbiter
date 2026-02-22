# Orbiter

A macOS disk space analyzer with an interactive sunburst chart visualization.

## Requirements

- macOS 14.0+
- Xcode 15.0+ or Swift 5.9+

## Building

```bash
swift build
```

## Running

```bash
swift run Orbiter
```

Or open `Package.swift` in Xcode.

## Usage

1. Click "Select Folder" to choose a directory to analyze
2. Explore the sunburst chart - inner rings represent parent directories, outer rings show children
3. Single-click to select a file/folder and see details in the right panel
4. Double-click a folder to expand/collapse it in the chart
5. Use breadcrumbs or the back button to navigate

## License

MIT
