import SwiftUI
import Foundation

// MARK: - Models

struct PhysicalDisk: Identifiable {
    let id = UUID()
    let identifier: String
    let size: Int64
    let isInternal: Bool
    let partitions: [DiskPartitionInfo]
    var transportType: String? = nil
    var mediaName: String? = nil
    var content: String = ""
    var imagePath: String? = nil

    var formattedSize: String { SizeFormatter.format(size) }

    /// Mounted disk image (.dmg / .img / simulator container)
    var isDiskImage: Bool {
        if imagePath != nil { return true }
        let name = (mediaName ?? "").lowercased()
        return name.contains("disk image") || name.contains("apple disk image")
    }

    /// True for synthesized APFS virtual disks (disk1/2/3) — these duplicate volumes already shown under the APFS container partition.
    var isSynthesized: Bool {
        if content == "Apple_APFS" { return true }
        return partitions.isEmpty && isInternal
    }

    var diskIcon: String {
        if isDiskImage { return "opticaldiscdrive" }
        return isInternal ? "internaldrive" : "externaldrive"
    }

    var transportLabel: String {
        switch (transportType ?? "").lowercased() {
        case "usb":         return "USB"
        case "thunderbolt": return "Thunderbolt"
        case "firewire":    return "FireWire"
        case "pci", "nvme": return "NVMe"
        case "sata":        return "SATA"
        case "sas":         return "SAS"
        case "sd":          return "SD Card"
        default:
            return isInternal
                ? NSLocalizedString("disk.internal", comment: "")
                : NSLocalizedString("disk.external", comment: "")
        }
    }

    var transportIcon: String {
        switch (transportType ?? "").lowercased() {
        case "usb":         return "cable.connector"
        case "thunderbolt": return "bolt.fill"
        case "firewire":    return "flame.fill"
        case "pci", "nvme": return "memorychip"
        case "sata":        return "internaldrive"
        case "sd":          return "sdcard"
        default:            return isInternal ? "internaldrive" : "externaldrive"
        }
    }
}

struct DiskPartitionInfo: Identifiable {
    let id = UUID()
    let identifier: String
    let name: String
    let type: String
    let size: Int64
    let mountPoint: String?
    var apfsVolumes: [APFSVolumeEntry]

    var formattedSize: String { SizeFormatter.format(size) }
    var isAPFSContainer: Bool { type == "Apple_APFS" }

    var typeLabel: String {
        switch type {
        case "EFI":                  return "EFI"
        case "Apple_APFS":           return "APFS"
        case "Apple_APFS_ISC":       return "iBoot SC"
        case "Apple_APFS_Recovery":  return "Recovery"
        case "Apple_HFS":            return "HFS+"
        case "Apple_Boot":           return "Boot"
        case "Apple_Free":           return "Free"
        case "Microsoft Basic Data": return "NTFS"
        case "ExFAT":                return "ExFAT"
        default:
            return type
                .replacingOccurrences(of: "Apple_", with: "")
                .replacingOccurrences(of: "_", with: " ")
        }
    }

    var displayName: String {
        if !name.isEmpty { return name }
        switch type {
        case "EFI":                  return "EFI System Partition"
        case "Apple_APFS":           return "APFS Container"
        case "Apple_APFS_ISC":       return "iBoot System Container"
        case "Apple_APFS_Recovery":  return "APFS Recovery"
        case "Apple_HFS":            return "HFS+ Volume"
        case "Apple_Boot":           return "Recovery HD"
        case "Apple_Free":           return "Free Space"
        default:                     return typeLabel
        }
    }

    var typeDescription: String {
        switch type {
        case "EFI":                  return "Firmware boot partition required by UEFI"
        case "Apple_APFS":           return "APFS container — holds multiple volumes"
        case "Apple_APFS_ISC":       return "iBoot System Container for secure boot"
        case "Apple_APFS_Recovery":  return "macOS Recovery environment"
        case "Apple_HFS":            return "HFS+ filesystem volume"
        case "Apple_Boot":           return "Legacy recovery partition"
        case "Apple_Free":           return "Unallocated space"
        case "Microsoft Basic Data": return "Windows NTFS data partition"
        default:                     return ""
        }
    }

    var typeColor: Color {
        switch type {
        case "EFI":                  return Color(.sRGB, red: 0.42, green: 0.42, blue: 0.46)
        case "Apple_APFS":           return Color(.sRGB, red: 0.22, green: 0.48, blue: 0.83)
        case "Apple_APFS_ISC":       return Color(.sRGB, red: 0.52, green: 0.32, blue: 0.72)
        case "Apple_APFS_Recovery":  return Color(.sRGB, red: 0.72, green: 0.42, blue: 0.18)
        case "Apple_HFS":            return Color(.sRGB, red: 0.22, green: 0.62, blue: 0.38)
        case "Apple_Boot":           return Color(.sRGB, red: 0.68, green: 0.38, blue: 0.18)
        case "Apple_Free":           return Color(.sRGB, red: 0.28, green: 0.28, blue: 0.30)
        case "Microsoft Basic Data": return Color(.sRGB, red: 0.18, green: 0.52, blue: 0.68)
        default:                     return Color(.sRGB, red: 0.48, green: 0.28, blue: 0.62)
        }
    }
}

struct APFSVolumeEntry: Identifiable {
    let id = UUID()
    let name: String
    let deviceIdentifier: String
    let mountPoint: String?
    let totalSize: Int64
    let usedSize: Int64

    var isMounted: Bool { !(mountPoint ?? "").isEmpty }
    var freeSize: Int64 { max(0, totalSize - usedSize) }
    var formattedTotal: String { totalSize > 0 ? SizeFormatter.format(totalSize) : "—" }
    var formattedUsed: String  { usedSize  > 0 ? SizeFormatter.format(usedSize)  : "—" }
    var formattedFree: String  { freeSize  > 0 ? SizeFormatter.format(freeSize)  : "—" }
    var usedPercentage: Double { totalSize > 0 ? Double(usedSize) / Double(totalSize) : 0 }

    var roleIcon: String {
        guard let mp = mountPoint, !mp.isEmpty else { return "cylinder" }
        if mp == "/"                 { return "desktopcomputer" }
        if mp.hasSuffix("/Data")     { return "doc.fill" }
        if mp.contains("Recovery")  { return "lifepreserver" }
        if mp.contains("Preboot")   { return "bolt.fill" }
        if mp.contains("/VM")       { return "memorychip" }
        if mp.contains("Update")    { return "arrow.triangle.2.circlepath" }
        return "cylinder"
    }

    var roleLabel: String {
        guard let mp = mountPoint, !mp.isEmpty else {
            return NSLocalizedString("disk.unmounted", comment: "")
        }
        if mp == "/"                  { return "System + Data" }
        if mp.hasSuffix("/Data")      { return "User Data" }
        if mp.contains("Recovery")   { return "Recovery" }
        if mp.contains("Preboot")    { return "Preboot" }
        if mp.contains("/VM")        { return "Swap / VM" }
        if mp.contains("Update")     { return "Update" }
        if mp.contains("xarts")      { return "xART Security" }
        return mp
    }
}

// MARK: - ViewModel

@MainActor
final class DiskLayoutViewModel: ObservableObject {
    @Published var disks: [PhysicalDisk] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    var visibleDisks: [PhysicalDisk] { disks.filter { !$0.isSynthesized } }
    var internalDisks: [PhysicalDisk] { visibleDisks.filter {  $0.isInternal && !$0.isDiskImage } }
    var externalDisks: [PhysicalDisk] { visibleDisks.filter { !$0.isInternal && !$0.isDiskImage } }
    var diskImageDisks: [PhysicalDisk] { visibleDisks.filter {  $0.isDiskImage } }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do { disks = try await fetchLayout() }
            catch { errorMessage = error.localizedDescription }
            isLoading = false
        }
    }

    private func fetchLayout() async throws -> [PhysicalDisk] {
        async let listData = runDiskutil(["list", "-plist"])
        async let apfsData = runDiskutil(["apfs", "list", "-plist"])
        let (listRaw, apfsRaw) = try await (listData, apfsData)

        guard
            let root     = try? PropertyListSerialization.propertyList(from: listRaw, format: nil) as? [String: Any],
            let allDisks = root["AllDisksAndPartitions"] as? [[String: Any]]
        else { throw NSError(domain: "DiskLayout", code: 1,
                             userInfo: [NSLocalizedDescriptionKey: "Cannot parse diskutil output"]) }

        let apfsVolumes = parseAPFSVolumes(from: apfsRaw)
        let capacities  = mountedVolumeCapacities()

        var result: [PhysicalDisk] = allDisks.compactMap { dict -> PhysicalDisk? in
            guard let identifier = dict["DeviceIdentifier"] as? String else { return nil }
            let size       = int64(dict, "Size")
            let isInternal = dict["OSInternalDisk"] as? Bool ?? true
            let partDicts  = dict["Partitions"] as? [[String: Any]] ?? []

            let diskContent = dict["Content"] as? String ?? ""
            let partitions: [DiskPartitionInfo] = partDicts.compactMap { pd -> DiskPartitionInfo? in
                guard let pid = pd["DeviceIdentifier"] as? String else { return nil }
                let pname  = pd["VolumeName"] as? String ?? ""
                let ptype  = pd["Content"] as? String ?? "Unknown"
                let psize  = int64(pd, "Size")
                let pmount = pd["MountPoint"] as? String

                var vols: [APFSVolumeEntry] = apfsVolumes[pid] ?? []
                if vols.isEmpty, let inline = pd["APFSVolumes"] as? [[String: Any]] {
                    vols = inline.compactMap { vd -> APFSVolumeEntry? in
                        guard let vid = vd["DeviceIdentifier"] as? String else { return nil }
                        let vname  = vd["VolumeName"] as? String ?? vd["Name"] as? String ?? vid
                        let vmount = vd["MountPoint"] as? String
                        let cap    = capacities[vmount ?? ""] ?? (0, 0)
                        return APFSVolumeEntry(name: vname, deviceIdentifier: vid,
                                               mountPoint: vmount, totalSize: cap.0, usedSize: cap.1)
                    }
                }
                vols = vols.map { v in
                    guard let mp = v.mountPoint, !mp.isEmpty, v.totalSize == 0,
                          let cap = capacities[mp] else { return v }
                    return APFSVolumeEntry(name: v.name, deviceIdentifier: v.deviceIdentifier,
                                          mountPoint: v.mountPoint, totalSize: cap.0, usedSize: cap.1)
                }
                return DiskPartitionInfo(identifier: pid, name: pname, type: ptype,
                                         size: psize, mountPoint: pmount, apfsVolumes: vols)
            }
            return PhysicalDisk(identifier: identifier, size: size,
                                isInternal: isInternal, partitions: partitions, content: diskContent)
        }

        // Fetch transport type + media name for each disk in parallel
        let transportMap = await fetchTransportInfo(for: result)
        result = result.map { d in
            var d2 = d
            d2.transportType = transportMap[d.identifier]?.0
            d2.mediaName     = transportMap[d.identifier]?.1
            d2.content       = d.content
            d2.imagePath     = transportMap[d.identifier]?.2
            return d2
        }
        return result
    }

    private func fetchTransportInfo(for disks: [PhysicalDisk]) async -> [String: (String?, String?, String?)] {
        await withTaskGroup(of: (String, String?, String?, String?).self) { group in
            for disk in disks {
                let id = disk.identifier
                group.addTask {
                    guard let data = try? await self.runDiskutil(["info", "-plist", id]),
                          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                    else { return (id, nil, nil, nil) }
                    let bus      = plist["BusProtocol"] as? String
                    let rawMedia = plist["MediaName"] as? String
                    let name     = (rawMedia?.isEmpty == false ? rawMedia : nil)
                                   ?? (plist["IORegistryEntryName"] as? String)
                    let ipath = plist["ImagePath"] as? String
                                ?? (plist["DiskImageURL"] as? String).flatMap { URL(string: $0)?.path }
                    return (id, bus, name, ipath)
                }
            }
            var map: [String: (String?, String?, String?)] = [:]
            for await (id, bus, name, ipath) in group { map[id] = (bus, name, ipath) }
            return map
        }
    }

    private func parseAPFSVolumes(from data: Data) -> [String: [APFSVolumeEntry]] {
        guard
            let root       = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let containers = root["Containers"] as? [[String: Any]]
        else { return [:] }

        let capacities = mountedVolumeCapacities()
        var result: [String: [APFSVolumeEntry]] = [:]
        for container in containers {
            guard let ref     = container["ContainerReference"] as? String,
                  let volumes = container["Volumes"] as? [[String: Any]] else { continue }
            result[ref] = volumes.compactMap { vd in
                guard let vid = vd["DeviceIdentifier"] as? String else { return nil }
                let vname  = vd["Name"] as? String ?? vd["VolumeName"] as? String ?? vid
                let vmount = vd["MountPoint"] as? String
                let cap    = capacities[vmount ?? ""] ?? (0, 0)
                return APFSVolumeEntry(name: vname, deviceIdentifier: vid,
                                       mountPoint: vmount, totalSize: cap.0, usedSize: cap.1)
            }
        }
        return result
    }

    private func mountedVolumeCapacities() -> [String: (Int64, Int64)] {
        var result: [String: (Int64, Int64)] = [:]
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey,
                                         .volumeAvailableCapacityKey]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys), options: []) ?? []
        for url in urls {
            guard let vals = try? url.resourceValues(forKeys: keys) else { continue }
            let total = Int64(vals.volumeTotalCapacity ?? 0)
            let free  = vals.volumeAvailableCapacityForImportantUsage
                        ?? Int64(vals.volumeAvailableCapacity ?? 0)
            result[url.path] = (total, max(0, total - free))
        }
        return result
    }

    private func runDiskutil(_ args: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                p.arguments = args
                let out = Pipe()
                p.standardOutput = out
                p.standardError  = Pipe()
                do { try p.run(); p.waitUntilExit()
                    cont.resume(returning: out.fileHandleForReading.readDataToEndOfFile())
                } catch { cont.resume(throwing: error) }
            }
        }
    }

    private func int64(_ dict: [String: Any], _ key: String) -> Int64 {
        if let n = dict[key] as? Int64    { return n }
        if let n = dict[key] as? Int      { return Int64(n) }
        if let n = dict[key] as? Double   { return Int64(n) }
        if let n = dict[key] as? NSNumber { return n.int64Value }
        return 0
    }
}

// MARK: - Root View

struct DiskLayoutView: View {
    @StateObject private var vm = DiskLayoutViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label(NSLocalizedString("disk.layoutTitle", comment: ""),
                      systemImage: "internaldrive.fill")
                    .font(.headline)
                Spacer()
                Button { vm.load() } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if vm.isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(NSLocalizedString("disk.loading", comment: ""))
                        .foregroundStyle(.secondary).font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text(err).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !vm.internalDisks.isEmpty {
                            DiskSectionHeader(
                                title: NSLocalizedString("disk.section.internal", comment: ""),
                                icon: "internaldrive.fill"
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 18)
                            .padding(.bottom, 10)

                            VStack(spacing: 22) {
                                ForEach(vm.internalDisks) { disk in
                                    DiskCard(disk: disk)
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        if !vm.externalDisks.isEmpty {
                            if !vm.internalDisks.isEmpty {
                                DiskSectionDivider()
                                    .padding(.vertical, 16)
                                    .padding(.horizontal, 20)
                            }

                            DiskSectionHeader(
                                title: NSLocalizedString("disk.section.external", comment: ""),
                                icon: "externaldrive.fill"
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, vm.internalDisks.isEmpty ? 18 : 0)
                            .padding(.bottom, 10)

                            VStack(spacing: 22) {
                                ForEach(vm.externalDisks) { disk in
                                    DiskCard(disk: disk)
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        if !vm.diskImageDisks.isEmpty {
                            DiskSectionDivider()
                                .padding(.vertical, 16)
                                .padding(.horizontal, 20)

                            DiskSectionHeader(
                                title: NSLocalizedString("disk.section.images", comment: ""),
                                icon: "opticaldiscdrive.fill"
                            )
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)

                            VStack(spacing: 22) {
                                ForEach(vm.diskImageDisks) { disk in
                                    DiskCard(disk: disk)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(width: 720, height: 640)
        .onAppear { vm.load() }
    }
}

// MARK: - Section Header / Divider

private struct DiskSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)
        }
    }
}

private struct DiskSectionDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }
}

// MARK: - Disk Card

private struct DiskCard: View {
    let disk: PhysicalDisk

    private var primaryLabel: String {
        if let name = disk.mediaName, !name.isEmpty { return name }
        return disk.identifier
    }

    private var accentColor: Color {
        if disk.isDiskImage { return .purple }
        return disk.isInternal ? Color.accentColor : .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Disk header ──────────────────────────────────────────
            HStack(spacing: 12) {
                // Icon in tinted rounded square
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 42, height: 42)
                    Image(systemName: disk.diskIcon)
                        .font(.title2)
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Primary: media name / model
                    Text(primaryLabel)
                        .font(.headline)
                        .lineLimit(1)

                    // Secondary: identifier badge + transport badge
                    HStack(spacing: 5) {
                        if disk.mediaName != nil {
                            Text(disk.identifier)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 4))
                        }
                        Label(disk.transportLabel, systemImage: disk.transportIcon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.12), in: Capsule())
                        if disk.isDiskImage {
                            Text(NSLocalizedString("disk.section.images", comment: ""))
                                .font(.caption)
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.purple.opacity(0.10), in: Capsule())
                        }
                    }
                }

                Spacer()
                Text(disk.formattedSize)
                    .font(.title3.monospacedDigit().weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(accentColor.opacity(0.13))

            Divider()

            if disk.partitions.isEmpty {
                // External drive with no readable partition table
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("disk.noPartitionInfo", comment: ""))
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else {
                // ── Partition map ─────────────────────────────────────
                PartitionMapBar(disk: disk)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                // ── Partition rows ────────────────────────────────────
                VStack(spacing: 0) {
                    ForEach(disk.partitions) { p in
                        PartitionRow(partition: p, diskSize: disk.size)
                        if p.id != disk.partitions.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accentColor.opacity(0.35), lineWidth: 1.0))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        .contextMenu { diskContextMenu }
        .help(disk.imagePath.map { "Disk Image: \($0)" } ?? "")
    }

    @ViewBuilder
    private var diskContextMenu: some View {
        if let path = disk.imagePath {
            Button {
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            } label: {
                Label(NSLocalizedString("disk.context.revealImage", comment: ""), systemImage: "doc.badge.magnifyingglass")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            } label: {
                Label(NSLocalizedString("disk.context.copyImagePath", comment: ""), systemImage: "doc.on.doc")
            }
            Divider()
        }

        if let mp = firstMountPoint {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: mp))
            } label: {
                Label(NSLocalizedString("disk.context.revealVolume", comment: ""), systemImage: "magnifyingglass")
            }
        }

        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Disk Utility.app"))
        } label: {
            Label(NSLocalizedString("disk.context.openDiskUtility", comment: ""), systemImage: "internaldrive")
        }

        if !disk.isInternal || disk.imagePath != nil {
            Divider()
            Button {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                p.arguments = ["eject", disk.identifier]
                p.standardOutput = Pipe(); p.standardError = Pipe()
                try? p.run()
            } label: {
                Label(NSLocalizedString("disk.context.eject", comment: ""), systemImage: "eject")
            }
        }
    }

    private var firstMountPoint: String? {
        for p in disk.partitions {
            if let mp = p.mountPoint, !mp.isEmpty { return mp }
            if let mp = p.apfsVolumes.first(where: { !($0.mountPoint ?? "").isEmpty })?.mountPoint { return mp }
        }
        return nil
    }
}

// MARK: - Partition Map Bar

private struct PartitionMapBar: View {
    let disk: PhysicalDisk

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(disk.partitions) { p in
                    let frac = disk.size > 0
                        ? CGFloat(p.size) / CGFloat(disk.size) : 0
                    let gap  = CGFloat(max(disk.partitions.count - 1, 0)) * 2
                    let w    = max(frac * (geo.size.width - gap), 4)
                    ZStack {
                        RoundedRectangle(cornerRadius: 3).fill(p.typeColor)
                        if w > 50 {
                            Text(p.typeLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1).padding(.horizontal, 4)
                        }
                    }
                    .frame(width: w, height: 22)
                    .help("\(p.displayName)  ·  \(p.typeLabel)  ·  \(p.formattedSize)")
                }
            }
        }
        .frame(height: 22)
    }
}

// MARK: - Partition Row

private struct PartitionRow: View {
    let partition: DiskPartitionInfo
    let diskSize: Int64
    @State private var expanded = true

    private var fraction: Double {
        diskSize > 0 ? Double(partition.size) / Double(diskSize) : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Row header
            HStack(spacing: 10) {
                // Color swatch
                RoundedRectangle(cornerRadius: 2)
                    .fill(partition.typeColor)
                    .frame(width: 10, height: 10)

                // Name + identifier
                VStack(alignment: .leading, spacing: 1) {
                    Text(partition.displayName)
                        .font(.callout).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(partition.identifier)
                            .font(.caption2).foregroundStyle(.tertiary)
                        if !partition.typeDescription.isEmpty {
                            Text("·").foregroundStyle(.quaternary).font(.caption2)
                            Text(partition.typeDescription)
                                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Size + fraction
                VStack(alignment: .trailing, spacing: 1) {
                    Text(partition.formattedSize)
                        .font(.callout.monospacedDigit())
                    Text(String(format: "%.1f%%", fraction * 100))
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                // Expand chevron for APFS
                if partition.isAPFSContainer && !partition.apfsVolumes.isEmpty {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .frame(width: 14)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                        }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                if partition.isAPFSContainer && !partition.apfsVolumes.isEmpty {
                    withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                }
            }

            // APFS volume cards
            if expanded && partition.isAPFSContainer && !partition.apfsVolumes.isEmpty {
                VStack(spacing: 6) {
                    ForEach(partition.apfsVolumes) { vol in
                        APFSVolumeCard(volume: vol)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - APFS Volume Card

private struct APFSVolumeCard: View {
    let volume: APFSVolumeEntry

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: volume.roleIcon)
                .font(.title3)
                .foregroundStyle(volume.isMounted ? .blue : .secondary)
                .frame(width: 28)

            // Name + role
            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name)
                    .font(.callout).fontWeight(.medium).lineLimit(1)
                Text(volume.roleLabel)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            // Usage
            if volume.totalSize > 0 {
                VStack(alignment: .trailing, spacing: 4) {
                    // Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(usageColor)
                                .frame(width: max(geo.size.width * volume.usedPercentage, 0))
                        }
                    }
                    .frame(width: 100, height: 5)

                    // Numbers
                    HStack(spacing: 0) {
                        Text(volume.formattedUsed)
                            .foregroundStyle(.primary)
                        Text(" used · ")
                            .foregroundStyle(.tertiary)
                        Text(volume.formattedFree)
                            .foregroundStyle(.secondary)
                        Text(" free")
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption.monospacedDigit())
                }
            } else {
                Text(NSLocalizedString("disk.unmounted", comment: ""))
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
    }

    private var usageColor: Color {
        volume.usedPercentage > 0.9 ? .red
            : volume.usedPercentage > 0.75 ? .orange
            : Color.accentColor
    }
}
