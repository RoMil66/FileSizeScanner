import SwiftUI

struct VolumeInfo: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let totalSize: Int64
    let freeSize: Int64
    let isInternal: Bool
    let isLocked: Bool
}

enum StaleSort: String, CaseIterable {
    case bySize   = "sort.size"
    case byOldest = "stale.oldest"
    case byNewest = "stale.newest"
    var label: String { NSLocalizedString(rawValue, comment: "") }
}

struct ContentView: View {
    @StateObject private var viewModel = ScanViewModel()
    @State private var selectedTab = 0
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage("fontSizeStep") private var fontSizeStep: Int = 2
    @State private var staleFilterBucket: Int?
    @State private var staleSort: StaleSort = .bySize
    @State private var pendingScanURL: URL?
    @State private var showingScanWarning = false
    @State private var scanWarningMessage = ""
    @State private var showingDiskLayout = false
    @State private var showPermissionBanner = false

    private var fontSizeScale: CGFloat {
        switch fontSizeStep {
        case 0: return 0.78
        case 1: return 0.88
        case 2: return 1.0
        case 3: return 1.2
        case 4: return 1.4
        default: return 1.0
        }
    }

    private func f(_ style: Font.TextStyle, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let base: CGFloat
        switch style {
        case .largeTitle:   base = 26
        case .title:        base = 22
        case .title2:       base = 17
        case .title3:       base = 15
        case .headline:     base = 13
        case .subheadline:  base = 11
        case .body:         base = 13
        case .callout:      base = 12
        case .footnote:     base = 11
        case .caption:      base = 10
        case .caption2:     base = 10
        @unknown default:   base = 13
        }
        let w: Font.Weight = style == .headline ? .semibold : weight
        return .system(size: base * fontSizeScale, weight: w, design: design)
    }

    var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 380, ideal: 480)
        } detail: {
            detailView
        }
        .toolbar {
            toolbarContent
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if showPermissionBanner {
                    permissionBanner
                }
                if viewModel.isEditMode {
                    editModeBanner
                }
            }
        }
        .frame(minWidth: 1050, minHeight: 650)
        .onAppear {
            NSApp.appearance = NSAppearance(named: isDarkMode ? .darkAqua : .aqua)
            showPermissionBanner = !PermissionChecker.hasFullDiskAccess
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            showPermissionBanner = !PermissionChecker.hasFullDiskAccess
        }
        .alert(NSLocalizedString("scan.largeTitle", comment: ""), isPresented: $showingScanWarning, presenting: pendingScanURL) { url in
            Button(NSLocalizedString("scan.largeConfirm", comment: "")) {
                viewModel.scan(url: url)
                pendingScanURL = nil
            }
            Button(NSLocalizedString("scan.largeCancel", comment: ""), role: .cancel) {
                pendingScanURL = nil
            }
        } message: { _ in
            Text(scanWarningMessage)
        }
        .sheet(isPresented: $showingDiskLayout) {
            DiskLayoutView()
        }
    }

    private func requestScan(url: URL) {
        if isLargeTarget(url) {
            let sizeLine = largeScanSizeInfo(url)
            scanWarningMessage = sizeLine + "\n\n" + NSLocalizedString("scan.largeMessage", comment: "")
            pendingScanURL = url
            showingScanWarning = true
        } else {
            viewModel.scan(url: url)
        }
    }

    private func pickAndRequestScan() {
        if let url = viewModel.pickFolder() {
            requestScan(url: url)
        }
    }

    private func isLargeTarget(_ url: URL) -> Bool {
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]
        ) ?? []
        if volumes.contains(where: { $0.resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path }) {
            return true
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        if url.resolvingSymlinksInPath().path == home.resolvingSymlinksInPath().path {
            return true
        }
        return false
    }

    private func largeScanSizeInfo(_ url: URL) -> String {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeNameKey]
        if let vals = try? url.resourceValues(forKeys: keys),
           let total = vals.volumeTotalCapacity {
            let name = vals.volumeName ?? url.lastPathComponent
            return String(format: NSLocalizedString("scan.largeVolume", comment: ""), name, SizeFormatter.format(Int64(total)))
        }
        return url.lastPathComponent
    }

    private var mountedVolumes: [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsInternalKey, .volumeIsLocalKey
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]
        ) else { return [] }
        return urls.compactMap { url in
            guard let vals = try? url.resourceValues(forKeys: Set(keys)),
                  let name = vals.volumeName,
                  let total = vals.volumeTotalCapacity,
                  vals.volumeIsLocal == true else { return nil }
            // Use availableCapacityForImportantUsage (includes purgeable) — same as Finder
            let free = vals.volumeAvailableCapacityForImportantUsage
                ?? Int64(vals.volumeAvailableCapacity ?? 0)
            let isInternal = vals.volumeIsInternal ?? false
            // Quick POSIX access check — returns immediately even on locked/encrypted volumes
            let isLocked = !FileManager.default.isReadableFile(atPath: url.path)
            return VolumeInfo(url: url, name: name, totalSize: Int64(total), freeSize: free, isInternal: isInternal, isLocked: isLocked)
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebarView: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            
            if let root = viewModel.rootNode, !viewModel.showingWelcome {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            FileTreeRow(node: root, viewModel: viewModel, depth: 0)
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: viewModel.selectedNode?.id) { _, newID in
                        if let id = newID {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
                // Force full re-creation of the scroll view when root identity changes
                // (e.g. when hidden-files filter is toggled and a new FileNode tree is built)
                .id(root.id)
                .background(Color(NSColor.controlBackgroundColor))
            } else if viewModel.scanState == .scanning {
                VStack(spacing: 20) {
                    Spacer()
                    
                    // Animated icon
                    Image(systemName: "externaldrive.fill.badge.questionmark")
                        .font(.system(size: 48 * fontSizeScale))
                        .foregroundStyle(.blue)
                        .symbolEffect(.pulse, isActive: true)
                    
                    Text(NSLocalizedString("scan.scanning", comment: ""))
                        .font(f(.title3, weight: .medium))
                    
                    // Progress stats
                    VStack(spacing: 8) {
                        // Scanned count + size
                        HStack(spacing: 16) {
                            Label(SizeFormatter.formatCount(viewModel.scannedItemCount), systemImage: "doc.fill")
                                .font(f(.callout, weight: .medium, design: .monospaced))

                            Label(SizeFormatter.format(viewModel.scanCurrentSize), systemImage: "internaldrive.fill")
                                .font(f(.callout, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(.secondary)
                        
                        // Current folder
                        if !viewModel.scanCurrentFolder.isEmpty {
                            Label(viewModel.scanCurrentFolder, systemImage: "folder.fill")
                                .font(f(.caption))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        // Elapsed time
                        if viewModel.scanElapsedSeconds > 0 {
                            Label(formatElapsed(viewModel.scanElapsedSeconds), systemImage: "clock")
                                .font(f(.caption))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    // Indeterminate progress bar
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 250)
                    
                    // Info hint
                    Text(NSLocalizedString("scan.hint", comment: ""))
                        .font(f(.caption))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)

                    Button(action: viewModel.resetToWelcome) {
                        Label(NSLocalizedString("scan.cancel", comment: ""), systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding(.top, 8)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                welcomeView
            }
        }
    }
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        HStack {
            if viewModel.scanState == .scanning {
                ProgressView()
                    .controlSize(.small)
            }
            Text(viewModel.scanProgress)
                .font(f(.callout))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let root = viewModel.rootNode {
                Text(String(format: NSLocalizedString("status.files", comment: ""), SizeFormatter.formatCount(root.fileCount), SizeFormatter.formatCount(root.folderCount)))
                    .font(f(.callout))
                    .foregroundStyle(.secondary)
            }
            Divider().frame(height: 12)
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                .font(f(.callout))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
    
    // MARK: - Detail View
    
    private var detailView: some View {
        VStack(spacing: 0) {
            if let node = viewModel.selectedNode ?? viewModel.rootNode {
                detailBreadcrumb(node: node)
                Divider()
            }
            switch selectedTab {
            case 0: overviewTab
            case 1: listViewTab
            case 2: pieChartTab
            case 3: treemapTab
            case 4: fileTypesTab
            case 5: largestFilesTab
            case 6: analyseTab
            default: overviewTab
            }
        }
    }
    
    private func detailBreadcrumb(node: FileNode) -> some View {
        HStack(spacing: 10) {
            if viewModel.canGoBack {
                Button(action: viewModel.goBack) {
                    Image(systemName: "chevron.left")
                        .font(f(.callout, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            // Breadcrumb path from root
            if let root = viewModel.rootNode {
                let pathNodes = viewModel.findPath(from: root, to: node) ?? [node]
                let display = pathNodes.suffix(4)
                HStack(spacing: 3) {
                    if pathNodes.count > 4 {
                        Image(systemName: "ellipsis")
                            .font(f(.caption2))
                            .foregroundStyle(.tertiary)
                        Image(systemName: "chevron.right")
                            .font(f(.caption2))
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(Array(display.enumerated()), id: \.element.id) { i, n in
                        if i > 0 {
                            Image(systemName: "chevron.right")
                                .font(f(.caption2))
                                .foregroundStyle(.tertiary)
                        }
                        let isLast = i == display.count - 1
                        Button(action: { if !isLast { viewModel.navigateTo(n) } }) {
                            Text(n.name)
                                .font(f(.callout))
                                .fontWeight(isLast ? .semibold : .regular)
                                .foregroundStyle(isLast ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLast)
                    }
                }
            }

            Spacer()

            Text(node.formattedSize)
                .font(f(.callout, weight: .semibold, design: .monospaced))

            if node.isDirectory {
                Label(SizeFormatter.formatCount(node.fileCount), systemImage: "doc.fill")
                    .font(f(.caption))
                    .foregroundStyle(.secondary)
                Label(SizeFormatter.formatCount(node.folderCount), systemImage: "folder.fill")
                    .font(f(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        Group {
            if let node = viewModel.selectedNode ?? viewModel.rootNode {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        // ── Summary ──────────────────────────────────────
                        VStack(alignment: .leading, spacing: 16) {
                            if let diskInfo = viewModel.diskInfo,
                               viewModel.selectedNode == nil || viewModel.selectedNode?.url == viewModel.rootNode?.url {
                                diskSummaryView(diskInfo: diskInfo)
                                volumeDetailSection(url: node.url)
                            }
                            nodeHeader(node)
                            if !node.isDirectory {
                                Divider()
                                fileDetailSection(node: node)
                                Divider()
                            }
                        }
                        .padding(.vertical)

                        // ── File list with sticky column header ──────────
                        if node.isDirectory && !node.children.isEmpty {
                            Section {
                                VStack(spacing: 0) {
                                    let maxSize = node.children.map(\.size).max() ?? 1
                                    ForEach(node.children) { child in
                                        SizeBarRow(node: child, maxSiblingSize: maxSize, viewModel: viewModel)
                                            .padding(.horizontal)
                                    }
                                }
                                .padding(.bottom, 8)
                            } header: {
                                overviewSortHeader
                            }
                        }
                    }
                }
            } else {
                Text(NSLocalizedString("empty.selectEntry", comment: ""))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var overviewSortHeader: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 18)
            SortableColumnHeader(
                title: NSLocalizedString("list.name", comment: ""),
                option: .name, viewModel: viewModel)
            Spacer(minLength: 60)
            SortableColumnHeader(
                title: NSLocalizedString("list.files", comment: ""),
                option: .fileCount, viewModel: viewModel)
                .frame(width: 55, alignment: .trailing)
            SortableColumnHeader(
                title: NSLocalizedString("list.modified", comment: ""),
                option: .modified, viewModel: viewModel)
                .frame(width: 100, alignment: .trailing)
            SortableColumnHeader(
                title: NSLocalizedString("list.size", comment: ""),
                option: .size, viewModel: viewModel)
                .frame(width: 85, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }
    
    // MARK: - Disk Summary
    
    private func diskSummaryView(diskInfo: DiskInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("overview.disk", comment: ""))
                .font(f(.headline))
                .padding(.horizontal)
            
            HStack(spacing: 20) {
                // Ring
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: diskInfo.usedPercentage)
                        .stroke(diskUsageColor(diskInfo.usedPercentage), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(String(format: "%.0f%%", diskInfo.usedPercentage * 100))
                        .font(f(.callout, weight: .bold, design: .rounded))
                }
                .frame(width: 60, height: 60)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 16) {
                        StatBadge(title: NSLocalizedString("overview.total", comment: ""), value: SizeFormatter.format(diskInfo.totalSize), icon: "internaldrive.fill")
                        StatBadge(title: NSLocalizedString("overview.used", comment: ""), value: SizeFormatter.format(diskInfo.usedSize), icon: "square.fill")
                        StatBadge(title: NSLocalizedString("overview.free", comment: ""), value: SizeFormatter.format(diskInfo.freeSize), icon: "square.dashed")
                    }

                    if diskInfo.purgeableSize > 100_000_000 {
                        let trulyFree = diskInfo.freeSize - diskInfo.purgeableSize
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.dashed").font(f(.caption2)).foregroundStyle(.secondary)
                                Text(NSLocalizedString("overview.free", comment: "")).font(f(.caption)).foregroundStyle(.secondary)
                                Text(SizeFormatter.format(diskInfo.freeSize)).font(f(.caption, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                                Text("=").font(f(.caption)).foregroundStyle(.secondary)
                                Text(SizeFormatter.format(trulyFree)).font(f(.caption, design: .monospaced)).foregroundStyle(.primary)
                                Text(NSLocalizedString("overview.trulyFree", comment: "")).font(f(.caption)).foregroundStyle(.secondary)
                                Text("+").font(f(.caption)).foregroundStyle(.secondary)
                                PurgeableBadge(diskInfo: diskInfo)
                            }
                        }
                    }

                    if let scanned = viewModel.rootNode {
                        let unaccounted = diskInfo.usedSize - scanned.size
                        if unaccounted > 1_000_000_000 {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                    .font(f(.caption))
                                Text(String(format: NSLocalizedString("overview.unaccounted", comment: ""), SizeFormatter.format(unaccounted)))
                                    .font(f(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            
            // Usage bar
            GeometryReader { geo in
                let scannedPct = viewModel.rootNode.map { Double($0.size) / Double(max(1, diskInfo.totalSize)) } ?? 0
                let otherPct = max(0, diskInfo.usedPercentage - scannedPct)
                
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                    RoundedRectangle(cornerRadius: 4).fill(.blue)
                        .frame(width: geo.size.width * scannedPct)
                    RoundedRectangle(cornerRadius: 4).fill(.orange.opacity(0.7))
                        .frame(width: geo.size.width * otherPct)
                        .offset(x: geo.size.width * scannedPct)
                }
            }
            .frame(height: 10)
            .padding(.horizontal)
            
            HStack(spacing: 16) {
                Label(NSLocalizedString("overview.scanned", comment: ""), systemImage: "circle.fill").font(f(.caption)).foregroundStyle(.blue)
                Label(NSLocalizedString("overview.systemOther", comment: ""), systemImage: "circle.fill").font(f(.caption)).foregroundStyle(.orange)
                Label(NSLocalizedString("overview.free", comment: ""), systemImage: "circle.fill").font(f(.caption)).foregroundStyle(.quaternary)
            }
            .padding(.horizontal)
            
            Divider()
        }
    }
    
    private func diskUsageColor(_ pct: Double) -> Color {
        if pct > 0.9 { return .red }
        if pct > 0.75 { return .orange }
        return .green
    }
    
    private func nodeHeader(_ node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: node.iconName)
                    .font(f(.title))
                    .foregroundStyle(iconColor(for: node))
                VStack(alignment: .leading) {
                    Text(node.name)
                        .font(f(.title2, weight: .semibold))
                    Text(node.url.path)
                        .font(f(.callout))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            HStack(spacing: 24) {
                StatBadge(title: NSLocalizedString("stat.size", comment: ""), value: node.formattedSize, icon: "internaldrive.fill")
                if node.isDirectory {
                    StatBadge(title: NSLocalizedString("stat.files", comment: ""), value: SizeFormatter.formatCount(node.fileCount), icon: "doc.fill")
                    StatBadge(title: NSLocalizedString("stat.folders", comment: ""), value: SizeFormatter.formatCount(node.folderCount), icon: "folder.fill")
                }
                if node.percentage > 0 {
                    StatBadge(title: NSLocalizedString("stat.share", comment: ""), value: String(format: "%.1f%%", node.percentage * 100), icon: "chart.pie.fill")
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - List View Tab
    
    private var listViewTab: some View {
        Group {
            if let node = viewModel.selectedNode, !node.isDirectory {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        nodeHeader(node)
                        Divider()
                        fileDetailSection(node: node)
                    }
                    .padding(.vertical)
                }
            } else if let node = viewModel.selectedNode ?? viewModel.rootNode,
               node.isDirectory, !node.children.isEmpty {
                VStack(spacing: 0) {
                    // Header row
                    listHeaderBar(node: node)
                    
                    Divider()
                    
                    // Table header — sortable columns
                    HStack(spacing: 0) {
                        SortableColumnHeader(
                            title: NSLocalizedString("list.size", comment: ""),
                            option: .size, viewModel: viewModel
                        )
                        .frame(width: 90, alignment: .trailing)

                        SortableColumnHeader(
                            title: NSLocalizedString("list.name", comment: ""),
                            option: .name, viewModel: viewModel
                        )
                        .padding(.leading, 12)

                        Spacer()

                        Text(NSLocalizedString("list.bar", comment: ""))
                            .font(f(.caption, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 140)

                        SortableColumnHeader(
                            title: NSLocalizedString("list.files", comment: ""),
                            option: .fileCount, viewModel: viewModel
                        )
                        .frame(width: 60, alignment: .trailing)

                        SortableColumnHeader(
                            title: NSLocalizedString("list.modified", comment: ""),
                            option: .modified, viewModel: viewModel
                        )
                        .frame(width: 110, alignment: .trailing)
                        .padding(.trailing, 8)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay(alignment: .bottom) { Divider() }

                    // Rows
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            let maxSize = node.children.map(\.size).max() ?? 1
                            ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                                CompactListRow(
                                    node: child,
                                    maxSiblingSize: maxSize,
                                    index: index,
                                    viewModel: viewModel
                                )
                            }
                        }
                    }
                }
            } else {
                Text(NSLocalizedString("list.needsFolder", comment: ""))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func listHeaderBar(node: FileNode) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
            
            Text(node.formattedSize)
                .font(f(.body, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            
            Text(node.url.path)
                .font(f(.callout))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if node.isDirectory {
                Image(systemName: "doc.fill")
                    .font(f(.caption))
                    .foregroundStyle(.white.opacity(0.6))
                Text(SizeFormatter.formatCount(node.fileCount))
                    .font(.system(size: 12 * fontSizeScale, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(colors: [.blue.opacity(0.8), .purple.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
        )
    }
    
    // MARK: - Pie Chart Tab
    
    private var pieChartTab: some View {
        Group {
            if let node = viewModel.selectedNode ?? viewModel.rootNode,
               node.isDirectory, !node.children.isEmpty {
                ScrollView {
                    VStack(spacing: 20) {
                        Text(node.name)
                            .font(f(.title3, weight: .semibold))

                        Text(node.formattedSize)
                            .font(f(.title2, weight: .bold))
                            .foregroundStyle(.secondary)
                        
                        PieChartView(node: node, viewModel: viewModel)
                            .frame(width: 350, height: 350)
                            .padding()
                        
                        pieLegend(node: node)
                    }
                    .padding()
                }
            } else {
                Text(NSLocalizedString("pie.needsFolder", comment: ""))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func pieLegend(node: FileNode) -> some View {
        let topItems = Array(node.children.prefix(12))
        let otherSize = node.children.dropFirst(12).reduce(Int64(0)) { $0 + $1.size }
        
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(topItems.enumerated()), id: \.element.id) { idx, child in
                HStack(spacing: 8) {
                    Circle()
                        .fill(pieColor(index: idx))
                        .frame(width: 12, height: 12)
                    Text(child.name)
                        .font(f(.callout))
                        .lineLimit(1)
                    Spacer()
                    Text(child.formattedSize)
                        .font(f(.callout, weight: .medium, design: .monospaced))
                    Text(String(format: "%.1f%%", child.percentage * 100))
                        .font(f(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if child.isDirectory { viewModel.navigateTo(child) }
                }
            }
            
            if otherSize > 0 {
                HStack(spacing: 8) {
                    Circle().fill(.gray).frame(width: 12, height: 12)
                    Text(String(format: NSLocalizedString("pie.other", comment: ""), node.children.count - 12))
                        .font(f(.callout))
                    Spacer()
                    Text(SizeFormatter.format(otherSize))
                        .font(f(.callout, weight: .medium, design: .monospaced))
                    let otherPct = node.size > 0 ? Double(otherSize) / Double(node.size) * 100 : 0
                    Text(String(format: "%.1f%%", otherPct))
                        .font(f(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 40)
    }
    
    // MARK: - Treemap Tab
    
    private var treemapTab: some View {
        Group {
            if let node = viewModel.selectedNode ?? viewModel.rootNode,
               node.isDirectory, !node.children.isEmpty {
                TreeMapView(node: node, viewModel: viewModel)
                    .padding(12)
            } else {
                Text(NSLocalizedString("treemap.needsFolder", comment: ""))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - File Types Tab
    
    private var fileTypesTab: some View {
        Group {
            if viewModel.fileTypeBreakdown.isEmpty {
                Text(NSLocalizedString("empty.noData", comment: ""))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let totalSize = viewModel.rootNode?.size ?? 1
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("fileTypes.title", comment: ""))
                            .font(f(.headline))
                            .padding(.horizontal)
                            .padding(.top, 8)
                        
                        ForEach(Array(viewModel.fileTypeBreakdown.prefix(30).enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 8) {
                                Text(".\(item.extension)")
                                    .font(f(.callout, weight: .medium, design: .monospaced))
                                    .frame(width: 90, alignment: .leading)
                                
                                GeometryReader { geo in
                                    let pct = Double(item.size) / Double(totalSize)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.accentColor.opacity(0.7))
                                        .frame(width: max(2, geo.size.width * pct))
                                }
                                .frame(height: 18)
                                
                                Text(SizeFormatter.format(item.size))
                                    .font(f(.callout, weight: .medium, design: .monospaced))
                                    .frame(width: 85, alignment: .trailing)
                                
                                Text("\(SizeFormatter.formatCount(item.count))×")
                                    .font(f(.callout))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 65, alignment: .trailing)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 3)
                        }
                    }
                    .padding(.bottom)
                }
            }
        }
    }
    
    // MARK: - Largest Files Tab
    
    private var largestFilesTab: some View {
        Group {
            if viewModel.topLargestFiles.isEmpty {
                Text(NSLocalizedString("empty.noData", comment: ""))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.topLargestFiles) { file in
                    HStack {
                        Image(systemName: file.iconName)
                            .foregroundStyle(iconColor(for: file))
                            .frame(width: 20)
                        VStack(alignment: .leading) {
                            Text(file.name)
                                .font(f(.callout))
                                .lineLimit(1)
                            Text(file.url.deletingLastPathComponent().path)
                                .font(f(.caption))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(file.formattedSize)
                            .font(f(.callout, weight: .semibold, design: .monospaced))
                    }
                    .contextMenu {
                        Button(NSLocalizedString("context.revealFinder", comment: "")) { viewModel.revealInFinder(file) }
                        if viewModel.isEditMode {
                            Divider()
                            Button(NSLocalizedString("context.moveToTrash", comment: ""), role: .destructive) { viewModel.moveToTrash(file) }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Analyse Tab

    private var analyseTab: some View {
        Group {
            if viewModel.rootNode == nil {
                Text(NSLocalizedString("empty.noData", comment: ""))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // Disk usage summary
                        if let disk = viewModel.diskInfo {
                            analyseSection(
                                title: NSLocalizedString("analyse.diskUsage", comment: ""),
                                icon: "internaldrive.fill", color: .blue
                            ) {
                                AnyView(VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 12) {
                                        analyseStatBox(label: NSLocalizedString("overview.used", comment: ""),
                                                       value: SizeFormatter.format(disk.usedSize),
                                                       color: diskUsageColor(disk.usedPercentage))
                                        analyseStatBox(label: NSLocalizedString("overview.free", comment: ""),
                                                       value: SizeFormatter.format(disk.freeSize),
                                                       color: .green)
                                        analyseStatBox(label: NSLocalizedString("overview.total", comment: ""),
                                                       value: SizeFormatter.format(disk.totalSize),
                                                       color: .secondary)
                                        analyseStatBox(label: "%",
                                                       value: String(format: "%.0f%%", disk.usedPercentage * 100),
                                                       color: diskUsageColor(disk.usedPercentage))
                                    }
                                    if disk.purgeableSize > 100_000_000 {
                                        HStack(spacing: 10) {
                                            Image(systemName: "arrow.3.trianglepath")
                                                .foregroundStyle(.purple)
                                                .font(f(.title3))
                                            VStack(alignment: .leading, spacing: 3) {
                                                HStack(spacing: 6) {
                                                    Text(NSLocalizedString("analyse.purgeableTitle", comment: ""))
                                                        .font(f(.callout, weight: .semibold))
                                                    Text(SizeFormatter.format(disk.purgeableSize))
                                                        .font(f(.callout, weight: .semibold, design: .monospaced))
                                                        .foregroundStyle(.purple)
                                                }
                                                Text(NSLocalizedString("analyse.purgeableDesc", comment: ""))
                                                    .font(f(.caption))
                                                    .foregroundStyle(.secondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                        .padding(10)
                                        .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                })
                            }
                        }

                        // Cleanup candidates
                        if !viewModel.cleanupCandidates.isEmpty {
                            analyseSection(
                                title: NSLocalizedString("analyse.cleanupTitle", comment: ""),
                                icon: "trash.circle.fill", color: .orange
                            ) {
                                AnyView(VStack(spacing: 4) {
                                    ForEach(viewModel.cleanupCandidates.prefix(12)) { node in
                                        analyseRow(node: node, badge: NSLocalizedString("analyse.cleanable", comment: ""), badgeColor: .orange)
                                    }
                                })
                            }
                        }

                        // Top directories
                        analyseSection(
                            title: NSLocalizedString("analyse.topDirs", comment: ""),
                            icon: "folder.fill", color: .blue
                        ) {
                            AnyView(VStack(spacing: 4) {
                                ForEach(viewModel.topLargestDirectories) { node in
                                    analyseRow(node: node, badge: nil, badgeColor: .clear)
                                }
                            })
                        }

                        // Old / stale files
                        if !viewModel.ageBuckets.isEmpty {
                            analyseSection(
                                title: NSLocalizedString("analyse.oldFiles", comment: ""),
                                icon: "clock.arrow.circlepath", color: .orange
                            ) {
                                AnyView(staleFilesContent)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func analyseSection(title: String, icon: String, color: Color, @ViewBuilder content: () -> AnyView) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(f(.headline))
            }
            content()
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    private func analyseStatBox(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(f(.title3, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(f(.caption))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func analyseRow(node: FileNode, badge: String?, badgeColor: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: node.isDirectory ? "folder.fill" : node.iconName)
                .foregroundStyle(.blue)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .font(f(.callout))
                    .lineLimit(1)
                Text(node.url.path)
                    .font(f(.caption2))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let badge = badge {
                Text(badge)
                    .font(f(.caption2))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(badgeColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(badgeColor)
            }
            Text(node.formattedSize)
                .font(f(.callout, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { viewModel.navigateTo(node) }
        .contextMenu {
            Button(NSLocalizedString("context.revealFinder", comment: "")) { viewModel.revealInFinder(node) }
            if viewModel.isEditMode {
                Divider()
                Button(NSLocalizedString("context.moveToTrash", comment: ""), role: .destructive) { viewModel.moveToTrash(node) }
            }
        }
    }

    // MARK: - File & Volume Detail Helpers

    private func fileDetailSection(node: FileNode) -> some View {
        let keys: Set<URLResourceKey> = [
            .creationDateKey, .contentModificationDateKey, .contentAccessDateKey,
            .localizedTypeDescriptionKey, .fileSizeKey, .totalFileAllocatedSizeKey
        ]
        let vals = try? node.url.resourceValues(forKeys: keys)
        let typeDesc    = vals?.localizedTypeDescription
        let exactSize   = vals?.fileSize.map { Int64($0) }
        let allocSize   = vals?.totalFileAllocatedSize.map { Int64($0) }
        let createdDate = vals?.creationDate
        let modDate     = vals?.contentModificationDate ?? node.modifiedDate
        let accessDate  = vals?.contentAccessDate

        return VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("detail.fileInfo", comment: ""))
                .font(f(.headline)).padding(.horizontal)

            VStack(spacing: 0) {
                if let td = typeDesc {
                    metaRow(NSLocalizedString("detail.fileType", comment: ""), td, "tag")
                    Divider().padding(.leading, 38)
                }
                if let s = exactSize {
                    let suffix = (allocSize ?? s) != s
                        ? "  ·  \(SizeFormatter.format(allocSize!)) \(NSLocalizedString("detail.onDisk", comment: ""))"
                        : ""
                    metaRow(NSLocalizedString("detail.exactSize", comment: ""), SizeFormatter.format(s) + suffix, "doc")
                    Divider().padding(.leading, 38)
                }
                if let d = createdDate  { metaRow(NSLocalizedString("detail.created",  comment: ""), metaDate(d), "calendar.badge.plus"); Divider().padding(.leading, 38) }
                if let d = modDate      { metaRow(NSLocalizedString("detail.modified",  comment: ""), metaDate(d), "pencil.circle") }
                if let d = accessDate   { Divider().padding(.leading, 38); metaRow(NSLocalizedString("detail.accessed",  comment: ""), metaDate(d), "eye") }
            }
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
            .padding(.horizontal)
        }
    }

    private func volumeDetailSection(url: URL) -> some View {
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedFormatDescriptionKey, .volumeIsEncryptedKey,
            .volumeUUIDStringKey, .volumeCreationDateKey,
            .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey
        ]
        let vals      = try? url.resourceValues(forKeys: keys)
        let fs        = vals?.volumeLocalizedFormatDescription
        let encrypted = vals?.volumeIsEncrypted ?? false
        let isInt     = vals?.volumeIsInternal ?? false
        let uuid      = vals?.volumeUUIDString
        let created   = vals?.volumeCreationDate

        return VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("detail.volumeInfo", comment: ""))
                .font(f(.headline)).padding(.horizontal)

            VStack(spacing: 0) {
                if let f = fs { metaRow(NSLocalizedString("detail.filesystem", comment: ""), f, "externaldrive"); Divider().padding(.leading, 38) }
                metaRow(NSLocalizedString("detail.encrypted", comment: ""), encrypted ? "✓" : "✗", "lock")
                Divider().padding(.leading, 38)
                metaRow(NSLocalizedString("detail.location",   comment: ""),
                        isInt ? NSLocalizedString("detail.internal", comment: "") : NSLocalizedString("detail.external", comment: ""),
                        "internaldrive")
                if let u = uuid   { Divider().padding(.leading, 38); metaRow("UUID", u, "number") }
                if let d = created { Divider().padding(.leading, 38); metaRow(NSLocalizedString("detail.created", comment: ""), metaDate(d), "calendar.badge.plus") }
            }
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func metaRow(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
            Text(label).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(value).foregroundStyle(.primary).textSelection(.enabled).lineLimit(2)
            Spacer()
        }
        .font(f(.callout))
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
    }

    private func metaDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return "\(fmt.string(from: date))  ·  \(exactAge(date))"
    }

    // MARK: - Stale Files Section

    private var staleFilesContent: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── Sort picker ───────────────────────────────────────────
            HStack {
                Text(NSLocalizedString("stale.sortBy", comment: ""))
                    .font(f(.caption)).foregroundStyle(.secondary)
                Picker("", selection: $staleSort) {
                    ForEach(StaleSort.allCases, id: \.self) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
            }

            // ── Age bucket bars ───────────────────────────────────────
            let maxBucketSize = viewModel.ageBuckets.map(\.size).max() ?? 1
            VStack(spacing: 5) {
                ForEach(Array(viewModel.ageBuckets.enumerated()), id: \.offset) { idx, bucket in
                    let isSelected = staleFilterBucket == idx
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            staleFilterBucket = (staleFilterBucket == idx) ? nil : idx
                        }
                    } label: {
                        HStack(spacing: 8) {
                            // Checkmark or age label
                            HStack(spacing: 4) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(f(.caption)).foregroundStyle(isSelected ? Color.orange : Color.secondary)
                                Text(bucket.label)
                                    .font(f(.callout))
                                    .fontWeight(isSelected ? .semibold : .regular)
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                            }
                            .frame(width: 100, alignment: .leading)

                            // Proportional bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.orange.opacity(0.12))
                                    Capsule()
                                        .fill(isSelected ? Color.orange.opacity(0.8) : Color.orange.opacity(0.4))
                                        .frame(width: max(4, geo.size.width * CGFloat(bucket.size) / CGFloat(maxBucketSize)))
                                }
                            }
                            .frame(height: 10)

                            // Size
                            Text(SizeFormatter.format(bucket.size))
                                .font(.system(size: 10 * fontSizeScale, weight: .medium, design: .monospaced))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .frame(width: 70, alignment: .trailing)

                            // Count
                            Text(String(format: NSLocalizedString("stale.nFiles", comment: ""), bucket.count))
                                .font(f(.caption))
                                .foregroundStyle(.secondary)
                                .frame(width: 75, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(isSelected ? Color.orange.opacity(0.08) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // ── Filtered + sorted file list ───────────────────────────
            let filteredFiles: [FileNode] = {
                let now = Date()
                let cal = Calendar.current
                let base: [FileNode]
                if let idx = staleFilterBucket, idx < viewModel.ageBuckets.count {
                    let bucket = viewModel.ageBuckets[idx]
                    base = viewModel.staleFiles.filter { node in
                        guard let d = node.modifiedDate else { return false }
                        let years = cal.dateComponents([.year], from: d, to: now).year ?? 0
                        return years >= bucket.minYears &&
                               (bucket.maxYears == Int.max || years < bucket.maxYears)
                    }
                } else {
                    base = viewModel.staleFiles
                }
                switch staleSort {
                case .bySize:
                    return base.sorted { $0.size > $1.size }
                case .byOldest:
                    return base.sorted { ($0.modifiedDate ?? .distantFuture) < ($1.modifiedDate ?? .distantFuture) }
                case .byNewest:
                    return base.sorted { ($0.modifiedDate ?? .distantPast) > ($1.modifiedDate ?? .distantPast) }
                }
            }()

            // Summary bar
            let totalReclaim = filteredFiles.reduce(Int64(0)) { $0 + $1.size }
            HStack(spacing: 6) {
                if staleFilterBucket != nil {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(.orange).font(f(.caption))
                    Text(String(format: NSLocalizedString("stale.filtered", comment: ""),
                                filteredFiles.count, SizeFormatter.format(totalReclaim)))
                        .font(f(.caption)).foregroundStyle(.orange)
                    Spacer()
                    Button(NSLocalizedString("analyse.filterReset", comment: "")) {
                        withAnimation { staleFilterBucket = nil }
                    }
                    .font(f(.caption)).foregroundStyle(.orange).buttonStyle(.plain)
                } else {
                    Image(systemName: "info.circle").foregroundStyle(.secondary).font(f(.caption))
                    Text(String(format: NSLocalizedString("stale.total", comment: ""),
                                filteredFiles.count, SizeFormatter.format(totalReclaim)))
                        .font(f(.caption)).foregroundStyle(.secondary)
                    Spacer()
                }
            }

            // File rows (capped at 200 for performance)
            if !filteredFiles.isEmpty {
                VStack(spacing: 4) {
                    ForEach(filteredFiles.prefix(200)) { file in
                        staleFileRow(node: file)
                    }
                    if filteredFiles.count > 200 {
                        Text(String(format: NSLocalizedString("stale.moreFiles", comment: ""),
                                    filteredFiles.count - 200))
                            .font(f(.caption)).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                    }
                }
            } else {
                Text(NSLocalizedString("stale.empty", comment: ""))
                    .font(f(.callout)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
    }

    private func staleFileRow(node: FileNode) -> some View {
        HStack(spacing: 8) {
            Image(systemName: node.iconName)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .font(f(.callout))
                    .lineLimit(1)
                Text(node.url.deletingLastPathComponent().path)
                    .font(f(.caption2))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(node.formattedSize)
                    .font(.system(size: 10 * fontSizeScale, weight: .semibold, design: .monospaced))
                if let date = node.modifiedDate {
                    HStack(spacing: 3) {
                        Text(exactAge(date))
                            .font(f(.caption2))
                            .foregroundStyle(.orange)
                        Text("·")
                            .font(f(.caption2))
                            .foregroundStyle(.quaternary)
                        Text(shortDate(date))
                            .font(f(.caption2))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { viewModel.navigateTo(node) }
        .contextMenu {
            Button(NSLocalizedString("context.revealFinder", comment: "")) { viewModel.revealInFinder(node) }
            if viewModel.isEditMode {
                Divider()
                Button(NSLocalizedString("context.moveToTrash", comment: ""), role: .destructive) { viewModel.moveToTrash(node) }
            }
        }
    }

    private func exactAge(_ date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date, to: Date())
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        if y > 0 {
            return m > 0
                ? String(format: NSLocalizedString("stale.ageYearsMonths", comment: ""), y, m)
                : String(format: NSLocalizedString("stale.ageYears", comment: ""), y)
        }
        return String(format: NSLocalizedString("stale.ageMonths", comment: ""), max(1, m))
    }

    private func shortDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: date)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if (viewModel.rootNode != nil || viewModel.scanState == .scanning) && !viewModel.showingWelcome {
                Button(action: viewModel.resetToWelcome) {
                    Label(NSLocalizedString("toolbar.home", comment: ""), systemImage: "house")
                }
                .help(NSLocalizedString("toolbar.homeHelp", comment: ""))
            }

            Button(action: { viewModel.goBack() }) {
                Label(NSLocalizedString("toolbar.back", comment: ""), systemImage: "chevron.left")
            }
            .disabled(!viewModel.canGoBack)
            .help(NSLocalizedString("toolbar.backHelp", comment: ""))

            Button(action: { viewModel.goForward() }) {
                Label(NSLocalizedString("toolbar.forward", comment: ""), systemImage: "chevron.right")
            }
            .disabled(!viewModel.canGoForward)
            .help(NSLocalizedString("toolbar.forwardHelp", comment: ""))
            
            Button(action: { pickAndRequestScan() }) {
                Label(NSLocalizedString("toolbar.chooseFolder", comment: ""), systemImage: "folder.badge.plus")
            }
            .help(NSLocalizedString("toolbar.chooseFolderHelp", comment: ""))
        }
        
        ToolbarItem(placement: .primaryAction) {
            if let root = viewModel.rootNode {
                Button(action: { viewModel.scan(url: root.url) }) {
                    Label(NSLocalizedString("toolbar.rescan", comment: ""), systemImage: "arrow.clockwise")
                }
                .help(NSLocalizedString("toolbar.rescanHelp", comment: ""))
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: { showingDiskLayout = true }) {
                Label(NSLocalizedString("disk.layoutButton", comment: ""),
                      systemImage: "square.split.1x2.fill")
            }
            .help(NSLocalizedString("disk.layoutButtonHelp", comment: ""))
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                viewModel.showHiddenFiles.toggle()
            }) {
                Label(
                    viewModel.showHiddenFiles
                        ? NSLocalizedString("toolbar.hiddenOn", comment: "")
                        : NSLocalizedString("toolbar.hiddenOff", comment: ""),
                    systemImage: viewModel.showHiddenFiles ? "eye.fill" : "eye.slash"
                )
            }
            .foregroundStyle(viewModel.showHiddenFiles ? .blue : .secondary)
            .help(NSLocalizedString("toolbar.hiddenHelp", comment: ""))
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: { viewModel.skipCloudFolders.toggle() }) {
                Label(
                    viewModel.skipCloudFolders
                        ? NSLocalizedString("toolbar.cloudSkipOn", comment: "")
                        : NSLocalizedString("toolbar.cloudSkipOff", comment: ""),
                    systemImage: viewModel.skipCloudFolders ? "icloud.slash" : "icloud"
                )
            }
            .foregroundStyle(viewModel.skipCloudFolders ? .purple : .secondary)
            .help(NSLocalizedString("toolbar.cloudSkipHelp", comment: ""))
        }

        ToolbarItem(placement: .primaryAction) {
            Picker(NSLocalizedString("toolbar.view", comment: ""), selection: $selectedTab) {
                Label(NSLocalizedString("tab.overview", comment: ""),    systemImage: "house").tag(0)
                Label(NSLocalizedString("tab.listView", comment: ""),    systemImage: "list.bullet").tag(1)
                Label(NSLocalizedString("tab.pieChart", comment: ""),    systemImage: "chart.pie").tag(2)
                Label(NSLocalizedString("tab.treemap", comment: ""),     systemImage: "square.grid.3x3.fill").tag(3)
                Label(NSLocalizedString("tab.fileTypes", comment: ""),   systemImage: "tag").tag(4)
                Label(NSLocalizedString("tab.largestFiles", comment: ""), systemImage: "arrow.up.circle").tag(5)
                Label(NSLocalizedString("tab.analyse", comment: ""), systemImage: "sparkle.magnifyingglass").tag(6)
            }
            .pickerStyle(.menu)
            .help(NSLocalizedString("toolbar.viewHelp", comment: ""))
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: { viewModel.isEditMode.toggle() }) {
                Label(
                    viewModel.isEditMode ? NSLocalizedString("mode.readOnly", comment: "") : NSLocalizedString("mode.edit", comment: ""),
                    systemImage: viewModel.isEditMode ? "lock.open.fill" : "lock.fill"
                )
            }
            .foregroundStyle(viewModel.isEditMode ? .red : .secondary)
            .help(viewModel.isEditMode ? NSLocalizedString("mode.editModeOff", comment: "") : NSLocalizedString("mode.editModeOn", comment: ""))
        }

        ToolbarItem(placement: .primaryAction) {
            Picker(NSLocalizedString("toolbar.fontSize", comment: ""), selection: $fontSizeStep) {
                Text(NSLocalizedString("font.xsmall", comment: "")).tag(0)
                Text(NSLocalizedString("font.small", comment: "")).tag(1)
                Text(NSLocalizedString("font.medium", comment: "")).tag(2)
                Text(NSLocalizedString("font.large", comment: "")).tag(3)
                Text(NSLocalizedString("font.xlarge", comment: "")).tag(4)
            }
            .pickerStyle(.menu)
            .help(NSLocalizedString("toolbar.fontSizeHelp", comment: ""))
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                isDarkMode.toggle()
                NSApp.appearance = NSAppearance(named: isDarkMode ? .darkAqua : .aqua)
            } label: {
                Label(
                    isDarkMode ? NSLocalizedString("toolbar.lightMode", comment: "") : NSLocalizedString("toolbar.darkMode", comment: ""),
                    systemImage: isDarkMode ? "sun.max" : "moon"
                )
            }
            .help(isDarkMode ? NSLocalizedString("toolbar.lightModeHelp", comment: "") : NSLocalizedString("toolbar.darkModeHelp", comment: ""))
        }
    }
    
    // MARK: - Edit Mode Banner

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(f(.callout))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("perm.bannerTitle", comment: ""))
                        .font(f(.callout, weight: .semibold))
                    Text(NSLocalizedString("perm.bannerText", comment: ""))
                        .font(f(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: PermissionChecker.openFullDiskAccessSettings) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right.square")
                        Text(NSLocalizedString("perm.openSettings", comment: ""))
                    }
                    .font(f(.callout))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("perm.openSettingsHelp", comment: ""))

                Button(action: { withAnimation { showPermissionBanner = false } }) {
                    Image(systemName: "xmark")
                        .font(f(.caption))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("perm.dismiss", comment: ""))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.orange).frame(width: 3)
            }
            Divider()

            // Step-by-step instructions
            HStack(alignment: .top, spacing: 20) {
                permStep(nr: "1", icon: "gearshape.fill",
                         text: NSLocalizedString("perm.step1", comment: ""))
                Image(systemName: "chevron.right")
                    .font(f(.caption2)).foregroundStyle(.tertiary)
                    .padding(.top, 5)
                permStep(nr: "2", icon: "hand.raised.fill",
                         text: NSLocalizedString("perm.step2", comment: ""))
                Image(systemName: "chevron.right")
                    .font(f(.caption2)).foregroundStyle(.tertiary)
                    .padding(.top, 5)
                permStep(nr: "3", icon: "checkmark.seal.fill",
                         text: NSLocalizedString("perm.step3", comment: ""))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            Divider()
        }
    }

    private func permStep(nr: String, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(f(.caption2)).foregroundStyle(.orange)
                .frame(width: 14)
            Text(text)
                .font(f(.caption)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var editModeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.circle.fill")
                .font(f(.callout))
                .foregroundStyle(.white)
            Text(NSLocalizedString("mode.editWarning", comment: ""))
                .font(f(.callout, weight: .semibold))
                .foregroundStyle(.white)
            Text(NSLocalizedString("mode.editWarningDetail", comment: ""))
                .font(f(.callout))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Button(action: { viewModel.isEditMode = false }) {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                    Text(NSLocalizedString("mode.readOnly", comment: ""))
                }
                .font(f(.callout))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.white.opacity(0.2), in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color.red)
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(spacing: 10) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 44 * fontSizeScale))
                        .foregroundStyle(.blue)
                    Text(NSLocalizedString("welcome.title", comment: ""))
                        .font(f(.title3, weight: .bold))
                    Text(NSLocalizedString("welcome.subtitle", comment: ""))
                        .font(f(.callout))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)

                // Volumes
                let vols = mountedVolumes
                if !vols.isEmpty {
                    Text(NSLocalizedString("welcome.volumes", comment: ""))
                        .font(f(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)

                    VStack(spacing: 2) {
                        ForEach(vols) { vol in
                            WelcomeVolumeRow(vol: vol) {
                                requestScan(url: vol.url)
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }

                // Quick Access
                Text(NSLocalizedString("welcome.quickAccess", comment: ""))
                    .font(f(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)

                VStack(spacing: 2) {
                    let fm = FileManager.default
                    WelcomeQuickRow(label: NSLocalizedString("welcome.home", comment: ""), icon: "house.fill", color: .blue) {
                        requestScan(url: fm.homeDirectoryForCurrentUser)
                    }
                    if let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first {
                        WelcomeQuickRow(label: NSLocalizedString("welcome.desktop", comment: ""), icon: "menubar.rectangle", color: .purple) {
                            requestScan(url: desktop)
                        }
                    }
                    if let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                        WelcomeQuickRow(label: NSLocalizedString("welcome.downloads", comment: ""), icon: "arrow.down.circle.fill", color: .green) {
                            requestScan(url: downloads)
                        }
                    }
                    if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                        WelcomeQuickRow(label: NSLocalizedString("welcome.documents", comment: ""), icon: "doc.fill", color: .orange) {
                            requestScan(url: docs)
                        }
                    }
                }
                .padding(.bottom, 20)

                // Resume cached scan
                if let root = viewModel.rootNode {
                    Button(action: viewModel.resumeLastScan) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(NSLocalizedString("welcome.resume", comment: ""))
                                    .fontWeight(.semibold)
                                Text("\(root.name) · \(root.formattedSize)")
                                    .font(f(.caption))
                                    .opacity(0.8)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                // Browse
                Button(action: { pickAndRequestScan() }) {
                    Label(NSLocalizedString("welcome.browse", comment: ""), systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

                // Version footer
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                    .font(f(.caption2))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Helpers

    private func formatElapsed(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let min = seconds / 60
        let sec = seconds % 60
        return "\(min)m \(sec)s"
    }
    
    private func iconColor(for node: FileNode) -> Color {
        switch node.iconColorName {
        case "blue": return .blue
        case "orange": return .orange
        case "green": return .green
        case "yellow": return .yellow
        case "purple": return .purple
        case "red": return .red
        case "pink": return .pink
        case "gray": return .gray
        default: return .secondary
        }
    }
}

// MARK: - Compact List Row

private func listRowAge(_ date: Date) -> String {
    let cal = Calendar.current
    let comps = cal.dateComponents([.year, .month], from: date, to: Date())
    let y = comps.year ?? 0
    let m = comps.month ?? 0
    if y > 0 { return m > 0 ? "\(y)y \(m)mo" : "\(y)y" }
    return "\(max(1, m))mo"
}

private func listRowDate(_ date: Date) -> String {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .none
    return df.string(from: date)
}

// MARK: - Sortable Column Header

private struct SortableColumnHeader: View {
    let title: String
    let option: SortOption
    @ObservedObject var viewModel: ScanViewModel

    private var isActive: Bool { viewModel.sortOption == option }

    var body: some View {
        Button {
            if viewModel.sortOption == option {
                viewModel.sortAscending.toggle()
            } else {
                viewModel.sortOption = option
                viewModel.sortAscending = false
            }
            viewModel.sortTree()
            viewModel.objectWillChange.send()
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: isActive ? .bold : .medium))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                if isActive {
                    Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(isActive ? Color.accentColor.opacity(0.13) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact date for list rows

private func compactListDate(_ date: Date) -> String {
    let cal = Calendar.current
    let df = DateFormatter()
    if cal.isDate(date, equalTo: Date(), toGranularity: .year) {
        df.dateFormat = "MMM d"
    } else {
        df.dateFormat = "MMM ''yy"
    }
    return df.string(from: date)
}

struct CompactListRow: View {
    let node: FileNode
    let maxSiblingSize: Int64
    let index: Int
    let viewModel: ScanViewModel

    @AppStorage("fontSizeStep") private var fontSizeStep: Int = 2
    @State private var isHovered = false
    @State private var showingInfo = false

    private var fontSizeScale: CGFloat {
        switch fontSizeStep {
        case 0: return 0.78
        case 1: return 0.88
        case 2: return 1.0
        case 3: return 1.2
        case 4: return 1.4
        default: return 1.0
        }
    }

    private var folderInfo: FolderInfo? {
        SystemFolderInfo.info(for: node.name, path: node.url.path)
    }

    private var pct: Double {
        guard maxSiblingSize > 0, node.size > 0 else { return 0 }
        return sqrt(Double(node.size) / Double(maxSiblingSize))
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Size
            Text(node.formattedSize)
                .font(.system(size: 13 * fontSizeScale, weight: .semibold, design: .monospaced))
                .foregroundStyle(sizeColor)
                .frame(width: 90, alignment: .trailing)

            // Icon + Name
            HStack(spacing: 6) {
                Image(systemName: node.iconName)
                    .font(.system(size: 10 * fontSizeScale))
                    .foregroundStyle(node.isDirectory ? .blue : .secondary)
                    .frame(width: 14)

                Text(node.name)
                    .font(.system(size: 12 * fontSizeScale))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if folderInfo != nil {
                    Button(action: { showingInfo.toggle() }) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 14 * fontSizeScale, weight: .semibold))
                            .foregroundStyle(.blue)
                            .shadow(color: .blue.opacity(0.3), radius: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 12)
            
            Spacer(minLength: 8)

            // ── Size bar ────────────────────────────────────────────
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary.opacity(0.5))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [barColor.opacity(0.9), barColor.opacity(0.6)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(2, geo.size.width * pct))
                }
            }
            .frame(width: 140, height: 16)

            // ── File count ──────────────────────────────────────────
            if node.isDirectory {
                Text(SizeFormatter.formatCount(node.fileCount))
                    .font(.system(size: 10 * fontSizeScale, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
            } else {
                Text("").frame(width: 60)
            }

            // ── Modified date ───────────────────────────────────────
            if let date = node.modifiedDate {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(compactListDate(date))
                        .font(.system(size: 10 * fontSizeScale, design: .monospaced))
                        .foregroundStyle(viewModel.sortOption == .modified ? .primary : .secondary)
                    if viewModel.sortOption == .modified {
                        Text(listRowAge(date))
                            .font(.system(size: 9 * fontSizeScale, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                }
                .frame(width: 110, alignment: .trailing)
                .padding(.trailing, 8)
            } else {
                Text("—").font(.system(size: 10 * fontSizeScale, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .frame(width: 110, alignment: .trailing)
                    .padding(.trailing, 8)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.navigateTo(node) }
        .onHover { hovering in isHovered = hovering }
        .contextMenu {
            Button(NSLocalizedString("context.revealFinder", comment: "")) { viewModel.revealInFinder(node) }
            if node.isDirectory {
                Button(NSLocalizedString("context.scanThisFolder", comment: "")) { viewModel.scan(url: node.url) }
            }
            if viewModel.isEditMode {
                Divider()
                Button(NSLocalizedString("context.moveToTrash", comment: ""), role: .destructive) { viewModel.moveToTrash(node) }
            }
        }
        .popover(isPresented: $showingInfo) {
            if let fi = folderInfo {
                FolderInfoPopover(info: fi, node: node)
            }
        }
    }
    
    private var rowBackground: some View {
        Group {
            if isHovered {
                Color.accentColor.opacity(0.15)
            } else if index % 2 == 0 {
                Color.clear
            } else {
                Color(nsColor: .controlBackgroundColor).opacity(0.3)
            }
        }
    }
    
    private var sizeColor: Color {
        if pct > 0.4 { return .red }
        if pct > 0.2 { return .orange }
        if pct > 0.1 { return .yellow }
        if pct > 0.05 { return .green }
        return .primary
    }
    
    private var barColor: Color {
        let bytes = node.size
        if bytes > 10_000_000_000 { return .red }
        if bytes >  1_000_000_000 { return .orange }
        if bytes >    100_000_000 { return .yellow }
        if bytes >     10_000_000 { return .green }
        return .blue
    }
}

// MARK: - Pie Chart

func pieColor(index: Int) -> Color {
    let colors: [Color] = [
        .red, .blue, .green, .orange, .purple,
        .cyan, .yellow, .pink, .teal, .indigo,
        .mint, .brown
    ]
    return colors[index % colors.count]
}

struct PieChartView: View {
    let node: FileNode
    let viewModel: ScanViewModel
    @State private var hoveredIndex: Int? = nil
    
    var body: some View {
        let topItems = Array(node.children.prefix(12))
        let otherSize = node.children.dropFirst(12).reduce(Int64(0)) { $0 + $1.size }
        let totalSize = max(node.size, 1)
        
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 10
            var startAngle = Angle.degrees(-90)
            
            for (idx, child) in topItems.enumerated() {
                let fraction = Double(child.size) / Double(totalSize)
                let sweepAngle = Angle.degrees(360 * fraction)
                let endAngle = startAngle + sweepAngle
                let isHov = hoveredIndex == idx
                let r = isHov ? radius + 5 : radius
                
                var path = Path()
                path.move(to: center)
                path.addArc(center: center, radius: r,
                           startAngle: startAngle, endAngle: endAngle, clockwise: false)
                path.closeSubpath()
                
                context.fill(path, with: .color(pieColor(index: idx)))
                context.stroke(path, with: .color(.black.opacity(0.3)), lineWidth: 1)
                startAngle = endAngle
            }
            
            if otherSize > 0 {
                let fraction = Double(otherSize) / Double(totalSize)
                let sweepAngle = Angle.degrees(360 * fraction)
                let endAngle = startAngle + sweepAngle
                var path = Path()
                path.move(to: center)
                path.addArc(center: center, radius: radius,
                           startAngle: startAngle, endAngle: endAngle, clockwise: false)
                path.closeSubpath()
                context.fill(path, with: .color(.gray))
                context.stroke(path, with: .color(.black.opacity(0.3)), lineWidth: 1)
            }
            
            // Donut hole
            let holePath = Path(ellipseIn: CGRect(
                x: center.x - radius * 0.35,
                y: center.y - radius * 0.35,
                width: radius * 0.7,
                height: radius * 0.7
            ))
            context.fill(holePath, with: .color(Color(nsColor: .windowBackgroundColor)))
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoveredIndex = hitTest(at: location, in: CGSize(width: 350, height: 350))
            case .ended:
                hoveredIndex = nil
            @unknown default:
                break
            }
        }
    }
    
    private func hitTest(at point: CGPoint, in size: CGSize) -> Int? {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = sqrt(dx * dx + dy * dy)
        let radius = min(size.width, size.height) / 2 - 10
        guard dist <= radius && dist > radius * 0.35 else { return nil }
        
        var angle = atan2(dy, dx) * 180 / .pi + 90
        if angle < 0 { angle += 360 }
        
        let topItems = Array(node.children.prefix(12))
        let totalSize = max(node.size, 1)
        var cur: Double = 0
        
        for (idx, child) in topItems.enumerated() {
            let sweep = 360 * Double(child.size) / Double(totalSize)
            if angle >= cur && angle < cur + sweep { return idx }
            cur += sweep
        }
        return nil
    }
}

// MARK: - Supporting Views

struct StatBadge: View {
    let title: String
    let value: String
    let icon: String

    @AppStorage("fontSizeStep") private var fontSizeStep: Int = 2

    private var fontSizeScale: CGFloat {
        switch fontSizeStep {
        case 0: return 0.78
        case 1: return 0.88
        case 3: return 1.2
        case 4: return 1.4
        default: return 1.0
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .font(.system(size: 12 * fontSizeScale))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10 * fontSizeScale))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 12 * fontSizeScale, weight: .medium))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct SizeBarRow: View {
    let node: FileNode
    let maxSiblingSize: Int64
    let viewModel: ScanViewModel

    @AppStorage("fontSizeStep") private var fontSizeStep: Int = 2
    @State private var showingInfo = false

    private var fontSizeScale: CGFloat {
        switch fontSizeStep {
        case 0: return 0.78
        case 1: return 0.88
        case 2: return 1.0
        case 3: return 1.2
        case 4: return 1.4
        default: return 1.0
        }
    }

    private var folderInfo: FolderInfo? {
        SystemFolderInfo.info(for: node.name, path: node.url.path)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.isCloudSkipped ? "cloud.fill" : node.iconName)
                .foregroundStyle(node.isCloudSkipped ? .purple : (node.isDirectory ? .blue : .secondary))
                .frame(width: 18)

            HStack(spacing: 4) {
                Text(node.name)
                    .font(.system(size: 12 * fontSizeScale))
                    .foregroundStyle(node.isCloudSkipped ? .secondary : .primary)
                    .lineLimit(1)
                if node.isCloudSkipped {
                    Text(NSLocalizedString("cloud.skipped", comment: ""))
                        .font(.system(size: 9 * fontSizeScale))
                        .foregroundStyle(.purple.opacity(0.8))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.purple.opacity(0.12), in: Capsule())
                } else if folderInfo != nil {
                    Button(action: { showingInfo.toggle() }) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 14 * fontSizeScale, weight: .semibold))
                            .foregroundStyle(.blue)
                            .shadow(color: .blue.opacity(0.3), radius: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .layoutPriority(1)

            GeometryReader { geo in
                let pct: Double = (maxSiblingSize > 0 && node.size > 0)
                    ? sqrt(Double(node.size) / Double(maxSiblingSize))
                    : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary.opacity(0.5))
                    if !node.isCloudSkipped {
                        RoundedRectangle(cornerRadius: 3).fill(barColor(pct: pct))
                            .frame(width: max(2, geo.size.width * pct))
                    }
                }
            }
            .frame(minWidth: 60, maxWidth: .infinity, minHeight: 14, maxHeight: 14)

            if node.isDirectory && !node.isCloudSkipped {
                Text(SizeFormatter.formatCount(node.fileCount))
                    .font(.system(size: 10 * fontSizeScale, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 55, alignment: .trailing)
            } else {
                Color.clear.frame(width: 55)
            }

            if let date = node.modifiedDate {
                Text(compactListDate(date))
                    .font(.system(size: 10 * fontSizeScale, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .trailing)
            } else {
                Text("—")
                    .font(.system(size: 10 * fontSizeScale, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .frame(width: 100, alignment: .trailing)
            }

            Text(node.isCloudSkipped ? "—" : node.formattedSize)
                .font(.system(size: 12 * fontSizeScale, weight: .medium, design: .monospaced))
                .foregroundStyle(node.isCloudSkipped ? .tertiary : .primary)
                .frame(width: 85, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture { viewModel.navigateTo(node) }
        .contextMenu {
            Button(NSLocalizedString("context.revealFinder", comment: "")) { viewModel.revealInFinder(node) }
            if viewModel.isEditMode {
                Divider()
                Button(NSLocalizedString("context.moveToTrash", comment: ""), role: .destructive) { viewModel.moveToTrash(node) }
            }
        }
        .popover(isPresented: $showingInfo) {
            if let info = folderInfo {
                FolderInfoPopover(info: info, node: node)
            }
        }
    }
    
    private func barColor(pct: Double) -> Color {
        let bytes = node.size
        if bytes > 10_000_000_000 { return .red }
        if bytes >  1_000_000_000 { return .orange }
        if bytes >    100_000_000 { return .yellow }
        return .blue
    }
}

// MARK: - Welcome Row Views

struct WelcomeVolumeRow: View {
    let vol: VolumeInfo
    let action: () -> Void
    @State private var isHovered = false
    @State private var showingVolumeInfo = false

    var body: some View {
        Button(action: vol.isLocked ? {} : action) {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: vol.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                        .font(.title2)
                        .foregroundStyle(vol.isLocked ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.blue))
                        .frame(width: 32)
                    if vol.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                            .offset(x: 4, y: 4)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(vol.name)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(vol.isLocked ? .secondary : .primary)
                        if vol.isLocked {
                            Text(NSLocalizedString("welcome.locked", comment: ""))
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }

                    if vol.isLocked {
                        Text(NSLocalizedString("welcome.lockedHint", comment: ""))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        let used = vol.totalSize - vol.freeSize
                        let pct = vol.totalSize > 0 ? Double(used) / Double(vol.totalSize) : 0
                        HStack(spacing: 6) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(.quaternary)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(pct > 0.9 ? Color.red : pct > 0.7 ? Color.orange : Color.blue)
                                        .frame(width: max(2, geo.size.width * pct))
                                }
                            }
                            .frame(height: 4)
                            Text(SizeFormatter.format(vol.freeSize) + " " + NSLocalizedString("welcome.free", comment: ""))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Text(SizeFormatter.format(vol.totalSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: vol.isLocked ? "lock" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                (isHovered && !vol.isLocked) ? Color.accentColor.opacity(0.1) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(vol.isLocked ? 0.7 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(vol.isLocked)
        .padding(.horizontal, 8)
        .onHover { if !vol.isLocked { isHovered = $0 } }
        .contextMenu {
            Button {
                showingVolumeInfo = true
            } label: {
                Label(NSLocalizedString("context.diskInfo", comment: ""), systemImage: "info.circle")
            }
            if !vol.isLocked {
                Divider()
                Button {
                    action()
                } label: {
                    Label(NSLocalizedString("context.scanThisFolder", comment: ""), systemImage: "magnifyingglass")
                }
            }
        }
        .popover(isPresented: $showingVolumeInfo) {
            VolumeInfoPopover(vol: vol)
        }
    }
}

// MARK: - Purgeable Badge (tappable, shows explanation popover)

struct PurgeableBadge: View {
    let diskInfo: DiskInfo
    @State private var showPopover = false

    var body: some View {
        Button { showPopover.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.3.trianglepath").font(.caption2)
                Text(SizeFormatter.format(diskInfo.purgeableSize))
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                Text(NSLocalizedString("overview.purgeable", comment: ""))
                    .font(.caption)
                Image(systemName: "info.circle").font(.caption2)
            }
            .foregroundStyle(.purple)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.purple.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            PurgeablePopoverView(diskInfo: diskInfo)
        }
    }
}

struct PurgeablePopoverView: View {
    let diskInfo: DiskInfo
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.3.trianglepath").font(.title2).foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("purgeable.title", comment: ""))
                        .font(.headline)
                    Text(SizeFormatter.format(diskInfo.purgeableSize))
                        .font(.system(.callout, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.purple)
                }
            }
            Divider()
            Text(NSLocalizedString("purgeable.explanation", comment: ""))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("purgeable.sources", comment: ""))
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                ForEach([
                    ("clock.arrow.circlepath", "purgeable.source1"),
                    ("doc.on.doc", "purgeable.source2"),
                    ("arrow.down.circle", "purgeable.source3"),
                    ("tray.full", "purgeable.source4"),
                ], id: \.0) { icon, key in
                    HStack(spacing: 6) {
                        Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
                        Text(NSLocalizedString(key, comment: "")).font(.callout)
                    }
                }
            }
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "info.circle").foregroundStyle(.blue)
                Text(NSLocalizedString("purgeable.note", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

// MARK: - Volume Info Popover (welcome screen right-click)

struct VolumeInfoPopover: View {
    let vol: VolumeInfo

    private var volVals: URLResourceValues? {
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedFormatDescriptionKey, .volumeIsEncryptedKey,
            .volumeUUIDStringKey, .volumeCreationDateKey,
            .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey
        ]
        return try? vol.url.resourceValues(forKeys: keys)
    }

    var body: some View {
        let vals = volVals
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: vol.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                    .font(.title2).foregroundStyle(Color.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vol.name).font(.headline)
                    Text(vol.url.path).font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            VStack(spacing: 0) {
                infoRow("externaldrive",          NSLocalizedString("detail.filesystem", comment: ""),
                        vals?.volumeLocalizedFormatDescription ?? "—")
                infoRow("lock",                   NSLocalizedString("detail.encrypted", comment: ""),
                        (vals?.volumeIsEncrypted ?? false) ? "✓" : "✗")
                infoRow("internaldrive",          NSLocalizedString("detail.location", comment: ""),
                        (vals?.volumeIsInternal ?? false) ? NSLocalizedString("detail.internal", comment: "") : NSLocalizedString("detail.external", comment: ""))
                infoRow("eject",                  NSLocalizedString("detail.ejectable", comment: ""),
                        (vals?.volumeIsEjectable ?? false) ? "✓" : "✗")
                infoRow("internaldrive.fill",     NSLocalizedString("overview.total", comment: ""),
                        SizeFormatter.format(vol.totalSize))
                infoRow("square.dashed",          NSLocalizedString("overview.free", comment: ""),
                        SizeFormatter.format(vol.freeSize))
                if let u = vals?.volumeUUIDString {
                    Divider().padding(.leading, 28)
                    infoRow("number", "UUID", u)
                }
                if let d = vals?.volumeCreationDate {
                    Divider().padding(.leading, 28)
                    infoRow("calendar", NSLocalizedString("detail.created", comment: ""), Self.formatDate(d))
                }
            }
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
        .padding(16)
        .frame(width: 380)
    }

    private static func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: date)
    }

    @ViewBuilder
    private func infoRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
            Text(label).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(value).foregroundStyle(.primary).textSelection(.enabled)
            Spacer()
        }
        .font(.callout)
        .padding(.vertical, 6).padding(.horizontal, 10)
        if label != "UUID" && label != NSLocalizedString("detail.created", comment: "") {
            Divider().padding(.leading, 28)
        }
    }
}


struct WelcomeQuickRow: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 32)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { isHovered = $0 }
    }
}
