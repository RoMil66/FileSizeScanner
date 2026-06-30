import Foundation
import SwiftUI
import Combine
import os

/// Lock-based counter — synchronous, no actor/await overhead, no thread pool stall
private final class AtomicCounter: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<(count: Int, size: Int64)>(initialState: (0, 0))

    @discardableResult
    func add(size: Int64) -> (count: Int, size: Int64) {
        lock.withLock { s in
            s.count += 1
            s.size  += size
            return s
        }
    }

    var values: (count: Int, size: Int64) { lock.withLock { $0 } }
}

/// Scan state
enum ScanState: Equatable {
    case idle
    case scanning
    case completed
    case error(String)
}

/// Sort options for the tree
enum SortOption: String, CaseIterable {
    case size
    case name
    case fileCount
    case modified

    var label: String {
        switch self {
        case .size:     return NSLocalizedString("sort.size", comment: "")
        case .name:     return NSLocalizedString("sort.name", comment: "")
        case .fileCount: return NSLocalizedString("sort.fileCount", comment: "")
        case .modified: return NSLocalizedString("sort.modified", comment: "")
        }
    }

    var sectionTitle: String {
        switch self {
        case .size:      return NSLocalizedString("overview.contentBySize", comment: "")
        case .name:      return NSLocalizedString("overview.contentByName", comment: "")
        case .fileCount: return NSLocalizedString("overview.contentByFiles", comment: "")
        case .modified:  return NSLocalizedString("overview.contentByDate", comment: "")
        }
    }
}

/// Age bucket for the stale-files analysis
struct AgeBucket: Identifiable {
    let id = UUID()
    let label: String
    var size: Int64
    var count: Int
    var minYears: Int   // lower bound of bucket (inclusive)
    var maxYears: Int   // upper bound (exclusive; Int.max = no limit)
}

/// Disk space info
struct DiskInfo {
    let totalSize: Int64
    let freeSize: Int64
    let usedSize: Int64
    let purgeableSize: Int64
    
    var usedPercentage: Double {
        totalSize > 0 ? Double(usedSize) / Double(totalSize) : 0
    }
}

/// Main ViewModel that drives the scanning and display
@MainActor
final class ScanViewModel: ObservableObject {
    @Published var rootNode: FileNode?
    @Published var scanState: ScanState = .idle
    @Published var selectedNode: FileNode?
    @Published var scanProgress: String = ""
    @Published var sortOption: SortOption = .size
    @Published var sortAscending: Bool = false
    @Published var skipCloudFolders: Bool = UserDefaults.standard.object(forKey: "skipCloudFolders") == nil ? true : UserDefaults.standard.bool(forKey: "skipCloudFolders") {
        didSet { UserDefaults.standard.set(skipCloudFolders, forKey: "skipCloudFolders") }
    }
    @Published var showHiddenFiles: Bool = true {
        didSet {
            guard oldValue != showHiddenFiles else { return }
            applyHiddenFilter()
        }
    }
    @Published var navigationPath: [FileNode] = []
    @Published var scannedItemCount: Int = 0
    @Published var diskInfo: DiskInfo?
    @Published var scanElapsedSeconds: Int = 0
    @Published var scanCurrentSize: Int64 = 0
    @Published var scanCurrentFolder: String = ""
    @Published var isEditMode: Bool = false
    @Published var expandedNodeIDs: Set<UUID> = []
    @Published var showingWelcome: Bool = true

    // Full unfiltered scan tree — always contains all files including hidden ones
    private var _fullRootNode: FileNode?

    // Navigation history
    private var backStack: [FileNode] = []
    private var forwardStack: [FileNode] = []
    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    
    /// Navigate to a node with history tracking
    func navigateTo(_ node: FileNode) {
        if let current = selectedNode { backStack.append(current) }
        forwardStack.removeAll()
        selectedNode = node
        if node.isDirectory { expandedNodeIDs.insert(node.id) }
        if let root = rootNode {
            let path = findPath(from: root, to: node) ?? []
            for ancestor in path.dropLast() {
                expandedNodeIDs.insert(ancestor.id)
            }
        }
    }
    
    /// Go back in navigation history
    func goBack() {
        guard let prev = backStack.popLast() else { return }
        if let current = selectedNode {
            forwardStack.append(current)
        }
        selectedNode = prev
    }
    
    /// Go forward in navigation history
    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let current = selectedNode {
            backStack.append(current)
        }
        selectedNode = next
    }

    func findPath(from node: FileNode, to target: FileNode) -> [FileNode]? {
        if node.id == target.id { return [node] }
        for child in node.children {
            if let path = findPath(from: child, to: target) {
                return [node] + path
            }
        }
        return nil
    }

    /// Top file types by total size
    @Published var fileTypeBreakdown: [(extension: String, size: Int64, count: Int)] = []

    /// Top largest files
    @Published var topLargestFiles: [FileNode] = []

    /// Top largest directories
    @Published var topLargestDirectories: [FileNode] = []

    /// Known cleanup candidates found in the scanned tree
    @Published var cleanupCandidates: [FileNode] = []

    /// Top largest files not modified in over a year
    @Published var staleFiles: [FileNode] = []

    /// Distribution of file space across age buckets (1-2y, 2-3y, 3-5y, 5y+)
    @Published var ageBuckets: [AgeBucket] = []
    
    private var scanTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    
    /// Go to welcome screen — keeps scan data cached
    func resetToWelcome() {
        if scanState == .scanning {
            scanTask?.cancel()
            timerTask?.cancel()
            scanState = .idle
            scanProgress = ""
            // Clear partial scan data
            rootNode = nil
            selectedNode = nil
            navigationPath = []
            backStack = []
            forwardStack = []
            expandedNodeIDs = []
            scannedItemCount = 0
            scanElapsedSeconds = 0
            scanCurrentSize = 0
            scanCurrentFolder = ""
            diskInfo = nil
            fileTypeBreakdown = []
            topLargestFiles = []
            topLargestDirectories = []
            cleanupCandidates = []
            staleFiles = []
            ageBuckets = []
        }
        showingWelcome = true
    }

    /// Resume showing the cached scan result
    func resumeLastScan() {
        showingWelcome = false
    }

    /// Show folder picker and return selected URL (without scanning)
    func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = NSLocalizedString("panel.message", comment: "")
        panel.prompt = NSLocalizedString("panel.prompt", comment: "")
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
    
    /// Scan a given URL
    func scan(url: URL) {
        scanTask?.cancel()
        timerTask?.cancel()
        _fullRootNode = nil
        rootNode = nil
        selectedNode = nil
        navigationPath = []
        scannedItemCount = 0
        scanElapsedSeconds = 0
        scanCurrentSize = 0
        scanCurrentFolder = ""
        showingWelcome = false
        scanState = .scanning
        scanProgress = String(format: NSLocalizedString("scan.scanningFolder", comment: ""), url.lastPathComponent)
        
        // Fetch disk info for the volume
        fetchDiskInfo(for: url)
        
        // Timer for elapsed seconds
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                scanElapsedSeconds += 1
            }
        }
        
        scanTask = Task {
            do {
                // Pre-check: bail immediately if volume is locked/encrypted
                guard FileManager.default.isReadableFile(atPath: url.path) else {
                    self.timerTask?.cancel()
                    let msg = NSLocalizedString("scan.volumeLocked", comment: "")
                    self.scanState = .error(msg)
                    self.scanProgress = msg
                    return
                }

                let node = try await scanDirectory(url: url)
                if Task.isCancelled { return }
                
                scanProgress = NSLocalizedString("scan.calculatingSizes", comment: "")
                node.computeSizeAndSort()
                sortTree(node: node)
                
                self.timerTask?.cancel()
                self._fullRootNode = node
                self.applyHiddenFilter()
                self.scanState = .completed
                self.scanProgress = String(format: NSLocalizedString("scan.done", comment: ""), SizeFormatter.format(node.size), formatDuration(scanElapsedSeconds))
            } catch {
                self.timerTask?.cancel()
                if !Task.isCancelled {
                    self.scanState = .error(error.localizedDescription)
                    self.scanProgress = String(format: NSLocalizedString("scan.error", comment: ""), error.localizedDescription)
                }
            }
        }
    }
    
    /// Format seconds into human-readable duration
    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        let min = seconds / 60
        let sec = seconds % 60
        return "\(min)m \(sec)s"
    }
    
    /// Fetch disk usage info for the volume containing url
    private func fetchDiskInfo(for url: URL) {
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])
            let total = Int64(values.volumeTotalCapacity ?? 0)
            // availableCapacityForImportantUsage includes purgeable space
            let freeImportant = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
            let free = freeImportant
            let used = total - free
            
            // Get purgeable space via statvfs
            var stat = statvfs()
            let purgeableSize: Int64
            if statvfs(url.path, &stat) == 0 {
                let realFree = Int64(stat.f_bavail) * Int64(stat.f_frsize)
                purgeableSize = max(0, free - realFree)
            } else {
                purgeableSize = 0
            }
            
            self.diskInfo = DiskInfo(
                totalSize: total,
                freeSize: free,
                usedSize: used,
                purgeableSize: purgeableSize
            )
        } catch {
            self.diskInfo = nil
        }
    }
    
    /// Entry point: parallel scan with lock-based counter + watchdog
    private func scanDirectory(url: URL) async throws -> FileNode {
        let counter = AtomicCounter()

        // Collect ALL mounted volume paths including hidden ones (e.g. /.nofollow).
        // isVolumeKey alone misses hidden APFS mounts; this set is the reliable fallback.
        let allMounts = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: []
        ) ?? []
        let mountPoints = Set(allMounts.map { $0.standardizedFileURL.path })

        // Watchdog: cancel after 8s if nothing was found (locked/encrypted volume)
        let watchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if counter.values.count == 0 { self.scanTask?.cancel() }
        }
        defer { watchdogTask.cancel() }

        return try await scanSubtree(url: url, counter: counter, depth: 0,
                                     mountPoints: mountPoints,
                                     skipCloud: skipCloudFolders)
    }

    /// Returns true when `url` is a cloud-provider sync folder that should not be recursed into.
    nonisolated private static func isCloudSyncFolder(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cloudStorageDir = home.appendingPathComponent("Library/CloudStorage")
            .standardizedFileURL
        let parent = url.deletingLastPathComponent().standardizedFileURL
        // Direct children of ~/Library/CloudStorage are cloud-provider mount points
        if parent == cloudStorageDir { return true }
        // Traditional / legacy locations
        let known: [URL] = [
            home.appendingPathComponent("Dropbox"),
            home.appendingPathComponent("Google Drive"),
            home.appendingPathComponent("Box"),
            home.appendingPathComponent("OneDrive"),
        ].map { $0.standardizedFileURL }
        return known.contains(url.standardizedFileURL)
    }

    /// Parallel recursive scan — nonisolated, runs off main actor
    nonisolated private func scanSubtree(
        url: URL,
        counter: AtomicCounter,
        depth: Int,
        mountPoints: Set<String>,
        skipCloud: Bool
    ) async throws -> FileNode {
        let fm = FileManager.default
        let resKeys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey, .isVolumeKey,
            .fileSizeKey, .totalFileAllocatedSizeKey,
            .contentModificationDateKey
        ]

        let node = FileNode(url: url, name: url.lastPathComponent, isDirectory: true)
        guard fm.isReadableFile(atPath: url.path) else { return node }

        let opts: FileManager.DirectoryEnumerationOptions = []
        guard let items = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Array(resKeys), options: opts
        ) else { return node }

        var subdirs: [URL] = []

        for itemURL in items {
            if Task.isCancelled { throw CancellationError() }
            guard let vals = try? itemURL.resourceValues(forKeys: resKeys) else { continue }
            if vals.isSymbolicLink == true { continue }
            let itemPath = itemURL.standardizedFileURL.path
            if vals.isVolume == true || mountPoints.contains(itemPath) { continue }
            // Skip known virtual APFS overlays that mirror the root volume
            let itemName = itemURL.lastPathComponent
            if itemName == ".nofollow" || itemName == ".vol" { continue }

            if vals.isDirectory == true {
                // statfs-based mount-point check: if the filesystem reports this directory
                // as its own mount-on path, it is a separate volume root — skip it.
                // This reliably catches /.nofollow and similar hidden APFS mounts that
                // neither isVolumeKey nor mountedVolumeURLs detect.
                var sfs = statfs()
                if statfs(itemURL.path, &sfs) == 0 {
                    let mnt = withUnsafeBytes(of: sfs.f_mntonname) {
                        String(cString: $0.bindMemory(to: CChar.self).baseAddress!)
                    }
                    if mnt == itemPath || mnt == itemURL.path { continue }
                }
                // Cloud sync folders: add as placeholder, do not recurse
                if skipCloud && ScanViewModel.isCloudSyncFolder(itemURL) {
                    let placeholder = FileNode(url: itemURL,
                                               name: itemURL.lastPathComponent,
                                               isDirectory: true,
                                               modifiedDate: vals.contentModificationDate)
                    placeholder.isCloudSkipped = true
                    node.children.append(placeholder)
                    continue
                }
                subdirs.append(itemURL)
            } else {
                let size = Int64(vals.totalFileAllocatedSize ?? vals.fileSize ?? 0)
                node.children.append(FileNode(
                    url: itemURL, name: itemURL.lastPathComponent,
                    isDirectory: false, size: size,
                    modifiedDate: vals.contentModificationDate
                ))
                // Synchronous lock — no await, no thread pool stall
                let (count, totalSz) = counter.add(size: size)
                if count % 5000 == 0 {
                    let folder = url.lastPathComponent
                    // Fire-and-forget UI update (no await = no suspension)
                    Task { @MainActor [weak self] in
                        self?.scannedItemCount = count
                        self?.scanCurrentSize  = totalSz
                        self?.scanCurrentFolder = folder
                        self?.scanProgress = String(
                            format: NSLocalizedString("scan.scanningCount", comment: ""),
                            SizeFormatter.formatCount(count),
                            SizeFormatter.format(totalSz)
                        )
                    }
                }
            }
        }

        // Parallelize only the top 4 levels — bounds max concurrent tasks to ~10^4
        // Below that, sequential is fine (dirs are small) and avoids task explosion
        if subdirs.count > 1 && depth < 4 {
            let childNodes = try await withThrowingTaskGroup(of: FileNode?.self) { group in
                for dir in subdirs {
                    group.addTask {
                        try await self.scanSubtree(url: dir, counter: counter,
                                                   depth: depth + 1, mountPoints: mountPoints,
                                                   skipCloud: skipCloud)
                    }
                }
                var results: [FileNode] = []
                for try await child in group { if let child { results.append(child) } }
                return results
            }
            node.children.append(contentsOf: childNodes)
        } else {
            for dir in subdirs {
                if Task.isCancelled { throw CancellationError() }
                node.children.append(
                    try await scanSubtree(url: dir, counter: counter,
                                          depth: depth + 1, mountPoints: mountPoints,
                                          skipCloud: skipCloud)
                )
            }
        }

        return node
    }
    
    /// Sort the tree based on current sort option
    func sortTree(node: FileNode? = nil) {
        guard let root = node ?? rootNode else { return }
        sortNodeRecursive(root)
    }
    
    /// Apply hidden-file filter to the full tree without re-scanning the filesystem
    func applyHiddenFilter() {
        guard let full = _fullRootNode else { return }
        let node: FileNode
        if showHiddenFiles {
            node = full
        } else {
            node = filteredCopy(of: full)
            node.computeSizeAndSort()
            sortTree(node: node)
        }
        showingWelcome = false
        expandedNodeIDs = [node.id]
        rootNode = node
        selectedNode = node
        computeFileTypeBreakdown(node: node)
        collectTopLargestFiles(node: node)
        collectTopLargestDirectories(node: node)
        collectCleanupCandidates(node: node)
        collectStaleFiles(node: node)
        computeAgeBuckets(node: node)
    }

    /// Deep-copy a FileNode tree, filtering out hidden files/directories
    private func filteredCopy(of node: FileNode) -> FileNode {
        if node.isDirectory {
            let filteredChildren = node.children
                .filter { !$0.name.hasPrefix(".") }
                .map { filteredCopy(of: $0) }
            return FileNode(url: node.url, name: node.name, isDirectory: true,
                            children: filteredChildren, modifiedDate: node.modifiedDate)
        } else {
            return FileNode(url: node.url, name: node.name, isDirectory: false,
                            size: node.size, modifiedDate: node.modifiedDate)
        }
    }

    private func sortNodeRecursive(_ node: FileNode) {
        guard node.isDirectory else { return }
        let asc = sortAscending
        switch sortOption {
        case .size:
            node.children.sort { asc ? $0.size < $1.size : $0.size > $1.size }
        case .name:
            node.children.sort {
                let r = $0.name.localizedCaseInsensitiveCompare($1.name)
                return asc ? r == .orderedDescending : r == .orderedAscending
            }
        case .fileCount:
            node.children.sort { asc ? $0.fileCount < $1.fileCount : $0.fileCount > $1.fileCount }
        case .modified:
            let past = Date.distantPast
            node.children.sort {
                let d0 = $0.modifiedDate ?? past
                let d1 = $1.modifiedDate ?? past
                return asc ? d0 < d1 : d0 > d1
            }
        }
        for child in node.children { sortNodeRecursive(child) }
    }
    
    /// Compute file type breakdown for the scanned tree
    private func computeFileTypeBreakdown(node: FileNode) {
        var typeMap: [String: (size: Int64, count: Int)] = [:]
        collectFileTypes(node: node, map: &typeMap)
        
        fileTypeBreakdown = typeMap
            .map { (extension: $0.key, size: $0.value.size, count: $0.value.count) }
            .sorted { $0.size > $1.size }
    }
    
    private func collectFileTypes(node: FileNode, map: inout [String: (size: Int64, count: Int)]) {
        if !node.isDirectory {
            let ext = node.fileExtension.isEmpty ? "(ohne)" : node.fileExtension
            let current = map[ext, default: (size: 0, count: 0)]
            map[ext] = (size: current.size + node.size, count: current.count + 1)
        }
        for child in node.children {
            collectFileTypes(node: child, map: &map)
        }
    }
    
    /// Collect top 100 largest files
    private func collectTopLargestFiles(node: FileNode) {
        var files: [FileNode] = []
        collectFiles(node: node, into: &files)
        topLargestFiles = Array(files.sorted { $0.size > $1.size }.prefix(100))
    }
    
    private func collectFiles(node: FileNode, into files: inout [FileNode]) {
        if !node.isDirectory {
            files.append(node)
        }
        for child in node.children {
            collectFiles(node: child, into: &files)
        }
    }
    
    /// Collect top 15 largest directories
    private func collectTopLargestDirectories(node: FileNode) {
        var dirs: [FileNode] = []
        collectDirs(node: node, into: &dirs)
        topLargestDirectories = Array(dirs.sorted { $0.size > $1.size }.prefix(15))
    }

    private func collectDirs(node: FileNode, into dirs: inout [FileNode]) {
        if node.isDirectory { dirs.append(node) }
        for child in node.children { collectDirs(node: child, into: &dirs) }
    }

    /// Collect known cleanup candidates found in the scanned tree
    private func collectCleanupCandidates(node: FileNode) {
        var candidates: [FileNode] = []
        findCleanupCandidates(node: node, into: &candidates)
        cleanupCandidates = candidates.sorted { $0.size > $1.size }
    }

    private func findCleanupCandidates(node: FileNode, into candidates: inout [FileNode]) {
        if node.isDirectory,
           let info = SystemFolderInfo.info(for: node.name, path: node.url.path),
           info.isDeletable,
           node.size > 0 {
            candidates.append(node)
            return // don't recurse into cleanup candidates
        }
        for child in node.children {
            findCleanupCandidates(node: child, into: &candidates)
        }
    }

    /// Reveal in Finder
    func revealInFinder(_ node: FileNode) {
        NSWorkspace.shared.selectFile(node.url.path, inFileViewerRootedAtPath: node.url.deletingLastPathComponent().path)
    }
    
    /// Delete file/folder (move to Trash)
    func moveToTrash(_ node: FileNode) {
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
            removeNode(node)
        } catch {
            scanProgress = String(format: NSLocalizedString("context.deleteFailed", comment: ""), error.localizedDescription)
        }
    }

    private func removeNode(_ node: FileNode) {
        guard let root = rootNode else { return }
        guard let path = findPath(from: root, to: node), path.count >= 2 else { return }

        // path: [root, …, parent, node]
        let ancestors = path.dropLast()   // [root, …, parent]
        let parent = ancestors.last!

        // Remove from parent
        parent.children.removeAll { $0.id == node.id }

        // Propagate size/count change upward — O(depth) instead of O(total nodes)
        let removedSize    = node.size
        let removedFiles   = node.fileCount
        let removedFolders = node.isDirectory ? node.folderCount : 0

        for ancestor in ancestors.reversed() {
            ancestor.size        -= removedSize
            ancestor.fileCount   -= removedFiles
            ancestor.folderCount -= removedFolders
            // Re-sort only immediate children of this ancestor
            sortSingleLevel(ancestor)
            // Recompute percentages for immediate children
            if ancestor.size > 0 {
                for child in ancestor.children {
                    child.percentage = Double(child.size) / Double(ancestor.size)
                }
            }
        }

        // Analytics are in-memory walks — no filesystem access
        computeFileTypeBreakdown(node: root)
        collectTopLargestFiles(node: root)
        collectTopLargestDirectories(node: root)
        collectCleanupCandidates(node: root)

        if selectedNode?.id == node.id {
            selectedNode = parent
        }
        objectWillChange.send()
    }

    /// Sort only the immediate children of a single node (no recursion)
    private func sortSingleLevel(_ node: FileNode) {
        switch sortOption {
        case .size:      node.children.sort { $0.size > $1.size }
        case .name:      node.children.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .fileCount: node.children.sort { $0.fileCount > $1.fileCount }
        case .modified:  node.children.sort { ($0.modifiedDate ?? .distantFuture) < ($1.modifiedDate ?? .distantFuture) }
        }
    }

    // MARK: - Stale File Analysis

    /// Collect top 50 largest files not modified in over a year
    private func collectStaleFiles(node: FileNode) {
        let threshold = Date().addingTimeInterval(-365.25 * 86400)
        var files: [FileNode] = []
        gatherStaleFiles(node: node, before: threshold, into: &files)
        // Keep up to 2 000 files (sorted by size so the most impactful are always included)
        staleFiles = Array(files.sorted { $0.size > $1.size }.prefix(2000))
    }

    private func gatherStaleFiles(node: FileNode, before date: Date, into files: inout [FileNode]) {
        if !node.isDirectory, let mod = node.modifiedDate, mod < date, node.size > 0 {
            files.append(node)
        }
        for child in node.children {
            gatherStaleFiles(node: child, before: date, into: &files)
        }
    }

    /// Compute space distribution across age buckets (1-2y, 2-3y, 3-5y, 5y+)
    private func computeAgeBuckets(node: FileNode) {
        let now = Date()
        let y1 = now.addingTimeInterval(-1 * 365.25 * 86400)
        let y2 = now.addingTimeInterval(-2 * 365.25 * 86400)
        let y3 = now.addingTimeInterval(-3 * 365.25 * 86400)
        let y5 = now.addingTimeInterval(-5 * 365.25 * 86400)

        var b = [
            AgeBucket(label: NSLocalizedString("analyse.age1to2", comment: ""), size: 0, count: 0, minYears: 1, maxYears: 2),
            AgeBucket(label: NSLocalizedString("analyse.age2to3", comment: ""), size: 0, count: 0, minYears: 2, maxYears: 3),
            AgeBucket(label: NSLocalizedString("analyse.age3to5", comment: ""), size: 0, count: 0, minYears: 3, maxYears: 5),
            AgeBucket(label: NSLocalizedString("analyse.age5plus", comment: ""), size: 0, count: 0, minYears: 5, maxYears: Int.max),
        ]
        fillBuckets(node: node, y1: y1, y2: y2, y3: y3, y5: y5, buckets: &b)
        ageBuckets = b.filter { $0.count > 0 }
    }

    private func fillBuckets(node: FileNode, y1: Date, y2: Date, y3: Date, y5: Date, buckets: inout [AgeBucket]) {
        if !node.isDirectory, let mod = node.modifiedDate, node.size > 0 {
            if mod < y5 {
                buckets[3].size += node.size; buckets[3].count += 1
            } else if mod < y3 {
                buckets[2].size += node.size; buckets[2].count += 1
            } else if mod < y2 {
                buckets[1].size += node.size; buckets[1].count += 1
            } else if mod < y1 {
                buckets[0].size += node.size; buckets[0].count += 1
            }
        }
        for child in node.children {
            fillBuckets(node: child, y1: y1, y2: y2, y3: y3, y5: y5, buckets: &buckets)
        }
    }
}
