# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**FileSizeScanner** is a native macOS application for visualizing and analyzing disk space usage. It provides multiple visualization modes (file tree, list view, pie charts, treemaps) and identifies large files, space hogs, and system folders that can be cleaned up.

- **Type**: macOS Desktop Application
- **Language**: Swift 5.9
- **Framework**: SwiftUI
- **Build System**: Xcode 16 with XCGen (project.yml)
- **Target**: macOS 14.0+
- **Bundle ID**: at.milberger.filesizescanner
- **Version**: 1.1.0
- **Localization**: English, German

## Build & Run

### Building in Xcode

```bash
# Generate Xcode project from project.yml (if modified)
# NOTE: Uses XCGen for project generation
xcodegen

# Build the app for macOS (uses Xcode GUI or xcodebuild)
xcodebuild -project FileSizeScanner.xcodeproj -scheme FileSizeScanner -configuration Release -derivedDataPath build
```

### Running the App

```bash
# From Xcode: Cmd+R (default run scheme is FileSizeScanner)
# From command line:
xcodebuild -project FileSizeScanner.xcodeproj -scheme FileSizeScanner -configuration Debug -derivedDataPath build run
```

### Install to /Applications

```bash
cp -R build/Build/Products/Release/FileSizeScanner.app /Applications/
```

### Icon Generation

The app includes a custom icon generation script (`generate_icon.swift`):
```bash
# Run from project root to generate all icon assets
swift generate_icon.swift FileSizeScanner/Assets.xcassets/AppIcon.appiconset
```
Generates icons at all standard macOS sizes (16x16 to 512x512 with 1x/2x variants).

## Code Architecture

### Core Model: FileNode

**File**: `FileSizeScanner/Models/FileNode.swift`

`FileNode` is the central data structure representing files and directories:
- Identifiable by UUID with recursive tree structure (`children: [FileNode]`)
- Computes aggregate sizes and file/folder counts via `computeSizeAndSort()`
- Calculates percentage of parent's size for visualizations
- Provides file extension and SF Symbol icon mapping (by file type)
- Includes icon color mapping for different file categories (code files, images, videos, etc.)

**Key method**: `computeSizeAndSort()` recursively walks the tree, sums sizes bottom-up, sorts children by size descending, and computes percentage values for visualizations.

### ViewModel: ScanViewModel

**File**: `FileSizeScanner/ViewModels/ScanViewModel.swift`

Manages all app state and logic:
- **Scanning**: Async directory enumeration with progress updates, cancellation support
- **Navigation**: Back/forward history stack for folder navigation
- **Sorting**: Three sort modes (by size, name, file count)
- **Analytics**: File type breakdown, top 100 largest files
- **Disk info**: Volume capacity, used/free space, purgeable size (via statvfs)
- **UI state**: `@Published` properties drive all UI updates

Key async operations:
- `scanDirectory(url:)`: Recursively enumerates filesystem using `FileManager.enumerator` with resource keys for efficiency
- Skips symlinks to avoid cycles; can optionally hide hidden files
- Updates progress UI every 500 items scanned
- `computeSizeAndSort()`: Post-scan computation (expensive but only runs once per scan)
- `computeFileTypeBreakdown()`, `collectTopLargestFiles()`: Analytics computed after scan completes

### UI Layer: ContentView

**File**: `FileSizeScanner/Views/ContentView.swift` (~1700 lines)

Main UI with 6 tabs accessed via segmented picker:

1. **Overview**: Disk usage ring chart, file/folder stats, content breakdown with percentage bars
2. **List View**: Tabular display with size bars, file/folder counts, compact layout
3. **Pie Chart**: Top 12 items as pie chart with legend; hit-test hover detection
4. **Treemap**: Squarified treemap layout (see TreeMapView) with colors by file type/size
5. **File Types**: Aggregated by extension; shows size, count, and bar width proportional to total
6. **Largest Files**: Top 100 files with size display and context menu (reveal in Finder, delete)

**Navigation**:
- Split view: sidebar (file tree) + detail (tabs)
- Sidebar uses `FileTreeRow` for recursive disclosure groups
- Each node clickable to select and display in detail view
- Toolbar with back/forward buttons, folder picker, rescan, sort options, hidden file toggle

**Initial behavior**: Automatically scans user home directory on app launch

### Supporting Views

**FileTreeView.swift**: Recursive tree sidebar with:
- `FileTreeRow`: Disclosure group for directories, shows size and mini percentage bar
- Supports context menu (reveal in Finder, rescan folder, move to trash)
- Root expands automatically on launch

**TreeMapView.swift**: Squarified treemap visualization:
- `TreeMapLayout`: Implements squarified rectangle packing algorithm
- Aspect ratio optimization for readable tiles
- Colors by file type for files, hue gradient for directories
- Font size scales with rect area; hover effect with opacity

**DiskLayoutView.swift**: Disk partition and volume layout sheet:

- Shows all mounted physical and external disks
- Proportional partition map bar with hover tooltips
- APFS volume cards with usage bars
- Filters synthesized internal disks (disk1/2/3)

**PieChartView**: Canvas-based pie chart with:
- Top 12 items rendered, "Other" grouping for remainder
- Hit-test hover detection for visual feedback
- Interactive (tap to navigate to folder)

### Utilities

**SizeFormatter.swift**: Number formatting
- `format(_ bytes: Int64)`: Converts bytes to B/KB/MB/GB/TB/PB with 1 decimal place
- `formatCount(_ count: Int)`: Formats integers with locale-specific thousands separator

**SystemFolderInfo.swift**: System/cache folder identification
- Maps 40+ known macOS system folders (Time Machine, Xcode caches, Docker, etc.)
- Bilingual titles, descriptions, and cleanup instructions (German/English)
- Flags whether folders are safe to delete
- Accessed via info button in tree rows and list items (shows popover)

**PermissionChecker.swift**: Full Disk Access detection

- `hasFullDiskAccess`: checks readability of TCC.db
- `openFullDiskAccessSettings()`: opens System Settings to the FDA pane

## Key Design Patterns & Conventions

### State Management
- All state centralized in `ScanViewModel` with `@Published` properties
- UI driven by single source of truth (FileNode tree + selection)
- Async scanning does not block UI; progress updates every 500 items

### Recursive Data Structures
- FileNode children recursively render via `ForEach` in FileTreeRow
- Size computation and sorting done bottom-up in single pass

### Performance Optimizations
- Directory enumeration uses `resourceKeys` to fetch only needed metadata (size, isDirectory, isSymlink)
- Symlinks skipped to avoid cycles
- LazyVStack in list view for smooth scrolling
- Progress throttled to every 500 items to avoid excessive UI updates

### Localization
- All user-facing strings use `NSLocalizedString()` with keys
- Two `.lproj` bundles: `de.lproj` (German) and `en.lproj` (English)
- Folder descriptions in SystemFolderInfo are dual-language

### macOS Integration
- No sandbox (entitlements set to `false`) — unrestricted filesystem access needed
- Uses `NSWorkspace` to reveal items in Finder
- Uses `FileManager.trashItem()` to move files to Trash (not permanent delete)
- Uses `statvfs()` for accurate purgeable space detection

## File Structure

```
FileSizeScanner/
├── FileSizeScannerApp.swift       # @main entry point, window config
├── Models/
│   └── FileNode.swift             # File/folder tree node (UUID, size, children, icons)
├── ViewModels/
│   └── ScanViewModel.swift        # State, scanning, navigation, analytics
├── Views/
│   ├── ContentView.swift          # Main UI: split view, 6 tabs
│   ├── FileTreeView.swift         # Sidebar file tree, recursive rows
│   ├── TreeMapView.swift          # Squarified treemap visualization
│   └── DiskLayoutView.swift       # Disk partition/volume layout sheet
├── Helpers/
│   ├── SizeFormatter.swift        # Byte/count formatting
│   ├── SystemFolderInfo.swift     # Known folder mapping + cleanup info (40+)
│   └── PermissionChecker.swift    # Full Disk Access detection + settings link
├── Resources/
│   ├── de.lproj/Localizable.strings  # German UI text
│   └── en.lproj/Localizable.strings  # English UI text
├── Assets.xcassets/               # App icon, accent color
├── Info.plist
└── FileSizeScanner.entitlements   # No sandbox

project.yml                         # XCGen project definition
generate_icon.swift                 # Icon generation utility
```

## Development Notes

### Build after every change

After editing source files, build Release and install to /Applications:

```bash
xcodebuild -project FileSizeScanner.xcodeproj -scheme FileSizeScanner -configuration Release -derivedDataPath build && \
cp -R build/Build/Products/Release/FileSizeScanner.app /Applications/
```

If `project.yml` was modified, run `xcodegen` first.

### Adding New UI Tabs

1. Add case to the tab picker in `ContentView`
2. Create new `@State` variable for tab tracking (e.g., `selectedTab`)
3. Implement tab view builder (e.g., `private var newTab: some View`)
4. Add localization keys to both `Localizable.strings` files

### Adding New Sort Options

1. Add case to `SortOption` enum in `ScanViewModel`
2. Implement sort logic in `sortNodeRecursive()`
3. Update toolbar picker in `ContentView`

### Identifying New System Folders

Add cases to `SystemFolderInfo.info(for:path:)` function with bilingual `FolderInfo` entries. Each folder info includes:
- Bilingual title, description, cleanup steps
- `isDeletable` flag (affects warning color in popover)

### Scanning Large Directories

For very large directories, the `scanDirectory()` async function may take minutes. Progress updates are shown every 500 items. The scan can be cancelled by triggering a new scan. Consider:
- Skipped items (symlinks) are not counted in progress
- Hidden files toggle (`showHiddenFiles`) filters pre-enumeration
- Total time scales with number of files and filesystem performance

### Treemap Algorithm

The squarified algorithm in `TreeMapLayout.computeLayout()` greedily packs items into rows to minimize aspect ratios (more square = more readable). For very wide/tall containers, layout may produce thin strips; this is expected.

## Localization Keys Reference

UI strings organized by feature area in `Localizable.strings`:
- `tab.*`, `toolbar.*`, `sort.*`: Navigation/controls
- `scan.*`: Scanning progress and errors
- `overview.*`, `list.*`, `pie.*`, `treemap.*`, `fileTypes.*`: Tab-specific labels
- `status.*`, `empty.*`, `stat.*`: Status bar and empty states
- `context.*`: Context menu items
- `folderInfo.*`: Folder info popover text
- `perm.*`: Permission banner text
- `stale.*`: Stale files analysis
- `disk.*`: Disk layout sheet

## Entitlements & Permissions

The app runs **without sandbox** (`com.apple.security.app-sandbox = false`). This is necessary because FileSizeScanner needs unrestricted filesystem access to:
- Read all directories and files
- Compute accurate disk usage across the entire system
- Identify and delete files

Users must trust the app; macOS will warn on first launch.
