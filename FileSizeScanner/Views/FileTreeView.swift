import SwiftUI

struct FileTreeRow: View {
    let node: FileNode
    @ObservedObject var viewModel: ScanViewModel
    let depth: Int

    @State private var showingInfo = false
    @State private var showingDeleteConfirm = false
    @State private var isHovered = false

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

    private func sf(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size * fontSizeScale, weight: weight, design: design)
    }

    private var isExpanded: Bool { viewModel.expandedNodeIDs.contains(node.id) }
    private var isSelected: Bool { viewModel.selectedNode?.id == node.id }
    private var hasChildren: Bool { node.isDirectory && !node.children.isEmpty }
    private var folderInfo: FolderInfo? { SystemFolderInfo.info(for: node.name, path: node.url.path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowContent
                .id(node.id)
            if isExpanded && node.isDirectory {
                ForEach(node.children) { child in
                    FileTreeRow(node: child, viewModel: viewModel, depth: depth + 1)
                }
            }
        }
        .popover(isPresented: $showingInfo) {
            if let info = folderInfo {
                FolderInfoPopover(info: info, node: node)
            }
        }
        .alert(NSLocalizedString("delete.confirmTitle", comment: ""), isPresented: $showingDeleteConfirm) {
            Button(NSLocalizedString("delete.confirmButton", comment: ""), role: .destructive) {
                viewModel.moveToTrash(node)
            }
            Button(NSLocalizedString("delete.cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(String(format: NSLocalizedString("delete.confirmMessage", comment: ""), node.name, node.formattedSize))
        }
    }

    private var rowContent: some View {
        HStack(spacing: 0) {
            // Indentation
            if depth > 0 {
                Color.clear.frame(width: CGFloat(depth) * 16)
            }

            // Expand / collapse arrow
            if hasChildren {
                Button {
                    withAnimation(.spring(duration: 0.18)) {
                        if isExpanded {
                            viewModel.expandedNodeIDs.remove(node.id)
                        } else {
                            viewModel.expandedNodeIDs.insert(node.id)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(sf(10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 18)
            }

            // Icon + Name + size
            HStack(spacing: 5) {
                Image(systemName: node.iconName)
                    .foregroundStyle(node.isDirectory ? .blue : iconColor)
                    .font(sf(13))
                    .frame(width: 16 * fontSizeScale)

                Text(node.name)
                    .font(sf(14))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if folderInfo != nil {
                    Button(action: { showingInfo.toggle() }) {
                        Image(systemName: "info.circle.fill")
                            .font(sf(12, weight: .semibold))
                            .foregroundStyle(.blue.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 4)

                Text(node.formattedSize)
                    .font(sf(11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if node.percentage > 0 {
                    PercentageBar(percentage: node.percentage)
                        .frame(width: 44, height: 8)
                }
            }
            .padding(.vertical, 3)
            .padding(.leading, 2)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.22)
                            : isHovered ? Color.secondary.opacity(0.1) : Color.clear
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture { viewModel.navigateTo(node) }
            .onHover { isHovered = $0 }
            .contextMenu {
                Button(NSLocalizedString("context.revealFinder", comment: "")) {
                    viewModel.revealInFinder(node)
                }
                if node.isDirectory {
                    Divider()
                    Button(NSLocalizedString("context.scanThisFolder", comment: "")) {
                        viewModel.scan(url: node.url)
                    }
                }
                if viewModel.isEditMode {
                    Divider()
                    Button(NSLocalizedString("context.moveToTrash", comment: ""), role: .destructive) {
                        showingDeleteConfirm = true
                    }
                }
            }
        }
        .padding(.leading, 6)
    }

    private var iconColor: Color {
        switch node.iconColorName {
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

// MARK: - Percentage Bar

struct PercentageBar: View {
    let percentage: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(.quaternary)
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: max(1, geo.size.width * min(percentage, 1.0)))
            }
        }
    }

    private var barColor: Color {
        if percentage > 0.5 { return .red }
        if percentage > 0.25 { return .orange }
        if percentage > 0.1 { return .yellow }
        return .blue
    }
}

// MARK: - Folder Info Popover

struct FolderInfoPopover: View {
    let info: FolderInfo
    let node: FileNode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title).font(.headline)
                    Text(node.formattedSize)
                        .font(.system(.callout, design: .monospaced, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "doc.text.fill").foregroundStyle(.secondary).frame(width: 16)
                Text(info.description).font(.callout).fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: info.isDeletable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(info.isDeletable ? .green : .orange)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.isDeletable
                         ? NSLocalizedString("folderInfo.canCleanUp", comment: "")
                         : NSLocalizedString("folderInfo.cautionDelete", comment: ""))
                        .font(.callout).fontWeight(.semibold)
                        .foregroundStyle(info.isDeletable ? .green : .orange)
                    Text(info.cleanup)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(16)
        .frame(width: 480)
    }
}
