import SwiftUI

/// Treemap visualization of disk space usage
struct TreeMapView: View {
    let node: FileNode
    let viewModel: ScanViewModel
    
    var body: some View {
        GeometryReader { geo in
            TreeMapLayout(
                items: node.children,
                totalSize: node.size,
                rect: CGRect(origin: .zero, size: geo.size),
                viewModel: viewModel
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Recursively lays out treemap rectangles using squarified algorithm
struct TreeMapLayout: View {
    let items: [FileNode]
    let totalSize: Int64
    let rect: CGRect
    let viewModel: ScanViewModel
    
    var body: some View {
        let rects = computeLayout(items: items, totalSize: totalSize, rect: rect)
        
        ZStack(alignment: .topLeading) {
            ForEach(Array(rects.enumerated()), id: \.element.node.id) { _, item in
                TreeMapCell(
                    node: item.node,
                    rect: item.rect,
                    viewModel: viewModel
                )
            }
        }
    }
    
    private struct LayoutItem {
        let node: FileNode
        let rect: CGRect
    }
    
    /// Squarified treemap layout
    private func computeLayout(items: [FileNode], totalSize: Int64, rect: CGRect) -> [LayoutItem] {
        guard !items.isEmpty, totalSize > 0, rect.width > 0, rect.height > 0 else { return [] }
        
        var result: [LayoutItem] = []
        var remaining = items.filter { $0.size > 0 }
        var currentRect = rect
        
        while !remaining.isEmpty {
            let isHorizontal = currentRect.width >= currentRect.height
            let totalRemaining = remaining.reduce(Int64(0)) { $0 + $1.size }
            
            // Find best row
            var row: [FileNode] = []
            var rowSize: Int64 = 0
            var bestAspect = Double.infinity
            
            for item in remaining {
                let testRow = row + [item]
                let testSize = rowSize + item.size
                let aspect = worstAspectRatio(
                    row: testRow,
                    rowSize: testSize,
                    totalSize: totalRemaining,
                    length: isHorizontal ? currentRect.height : currentRect.width
                )
                
                if aspect <= bestAspect {
                    bestAspect = aspect
                    row = testRow
                    rowSize = testSize
                } else {
                    break
                }
            }
            
            // Layout the row
            let fraction = Double(rowSize) / Double(totalRemaining)
            let rowLength = isHorizontal
                ? currentRect.width * fraction
                : currentRect.height * fraction
            
            var offset: CGFloat = 0
            for item in row {
                let itemFraction = Double(item.size) / Double(rowSize)
                let itemLength = (isHorizontal ? currentRect.height : currentRect.width) * itemFraction
                
                let itemRect: CGRect
                if isHorizontal {
                    itemRect = CGRect(
                        x: currentRect.minX,
                        y: currentRect.minY + offset,
                        width: rowLength,
                        height: itemLength
                    )
                } else {
                    itemRect = CGRect(
                        x: currentRect.minX + offset,
                        y: currentRect.minY,
                        width: itemLength,
                        height: rowLength
                    )
                }
                
                result.append(LayoutItem(node: item, rect: itemRect))
                offset += itemLength
            }
            
            // Update remaining rect
            if isHorizontal {
                currentRect = CGRect(
                    x: currentRect.minX + rowLength,
                    y: currentRect.minY,
                    width: currentRect.width - rowLength,
                    height: currentRect.height
                )
            } else {
                currentRect = CGRect(
                    x: currentRect.minX,
                    y: currentRect.minY + rowLength,
                    width: currentRect.width,
                    height: currentRect.height - rowLength
                )
            }
            
            remaining = Array(remaining.dropFirst(row.count))
        }
        
        return result
    }
    
    private func worstAspectRatio(row: [FileNode], rowSize: Int64, totalSize: Int64, length: CGFloat) -> Double {
        guard rowSize > 0, totalSize > 0, length > 0 else { return .infinity }
        
        let rowFraction = Double(rowSize) / Double(totalSize)
        let rowWidth = Double(length) * rowFraction
        guard rowWidth > 0 else { return .infinity }
        
        var worst = 0.0
        for item in row {
            let itemFraction = Double(item.size) / Double(rowSize)
            let itemHeight = Double(length) // this dimension is the full length
            let itemWidth = rowWidth * itemFraction
            
            guard itemWidth > 0 else { continue }
            let aspect = max(itemHeight / itemWidth, itemWidth / itemHeight)
            worst = max(worst, aspect)
        }
        
        return worst
    }
}

/// A single cell in the treemap
struct TreeMapCell: View {
    let node: FileNode
    let rect: CGRect
    let viewModel: ScanViewModel
    
    @State private var isHovered = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(cellColor)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(.background, lineWidth: 1)
            )
            .overlay {
                if rect.width > 40 && rect.height > 20 {
                    VStack(spacing: 1) {
                        Text(node.name)
                            .font(.system(size: fontSize))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        if rect.height > 35 {
                            Text(node.formattedSize)
                                .font(.system(size: max(8, fontSize - 2)))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(3)
                }
            }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .opacity(isHovered ? 0.8 : 1.0)
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                viewModel.navigateTo(node)
            }
            .contextMenu {
                Button(NSLocalizedString("context.revealFinder", comment: "")) {
                    viewModel.revealInFinder(node)
                }
                if node.isDirectory {
                    Button(NSLocalizedString("context.openFolder", comment: "")) {
                        viewModel.navigateTo(node)
                    }
                }
            }
            .help("\(node.name)\n\(node.formattedSize)")
    }
    
    private var fontSize: CGFloat {
        let area = rect.width * rect.height
        if area > 10000 { return 11 }
        if area > 3000 { return 9 }
        return 8
    }
    
    private var cellColor: Color {
        if node.isDirectory {
            return Color(hue: 0.6, saturation: 0.5 + node.percentage * 0.3, brightness: 0.5 + node.percentage * 0.3)
        }
        
        // Color by file type
        switch node.fileExtension {
        case "swift", "py", "js", "ts", "c", "cpp", "java":
            return .blue
        case "jpg", "jpeg", "png", "gif", "heic", "svg", "webp":
            return .purple
        case "mp4", "mov", "avi", "mkv":
            return .red
        case "mp3", "wav", "aac", "m4a":
            return .pink
        case "pdf":
            return .orange
        case "zip", "gz", "tar", "dmg":
            return .gray
        default:
            return .teal
        }
    }
}
