import SwiftUI

// MARK: - Storage pane (issue #62)

/// Settings > Storage.
/// Shows available disk space, estimated cache size, and the two destructive
/// recovery actions: clear cache and reset library database.
///
/// Neither XPC method exists yet in `EngineXPCProtocol` — both actions log
/// the intent and show a brief confirmation. Wire to the engine once
/// `clearCache` / `resetDatabase` XPC methods are added.
struct StorageSettingsPane: View {

    @State private var showClearCacheConfirm = false
    @State private var showResetDatabaseConfirm = false
    @State private var diskInfo: DiskInfo = .empty
    @State private var cacheSize: Int64 = 0

    var body: some View {
        Form {
            // MARK: Disk usage section
            Section("Disk Usage") {
                LabeledContent("Available") {
                    Text(diskInfo.availableFormatted)
                        .brandBodyRegular()
                        .foregroundStyle(BrandColors.cocoa)
                }
                LabeledContent("Total") {
                    Text(diskInfo.totalFormatted)
                        .brandBodyRegular()
                        .foregroundStyle(BrandColors.cocoaSoft)
                }
                LabeledContent("Cache size") {
                    Text(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                        .brandBodyRegular()
                        .foregroundStyle(BrandColors.cocoaSoft)
                }
            }

            // MARK: Recovery actions section
            Section("Recovery") {
                // Clear cache
                LabeledContent("Torrent cache") {
                    Button("Clear cache…") {
                        showClearCacheConfirm = true
                    }
                    .confirmationDialog(
                        "Clear cache?",
                        isPresented: $showClearCacheConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Clear cache", role: .destructive) {
                            clearCache()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        // Voice: direct, concrete, no exclamation marks (06-brand.md)
                        Text("Downloaded torrent data will be removed. Any title you re-open will need to buffer again from the start.")
                    }
                }

                // Reset library database
                LabeledContent("Library database") {
                    Button("Reset database…") {
                        showResetDatabaseConfirm = true
                    }
                    .confirmationDialog(
                        "Reset library database?",
                        isPresented: $showResetDatabaseConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Reset database", role: .destructive) {
                            resetDatabase()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will remove all watch history and favourites. This action cannot be undone.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .background(BrandColors.surfaceBase)
        .task { await loadDiskInfo() }
    }

    // MARK: - Actions

    /// Stub: logs intent. Wire to `EngineClient.clearCache()` once that XPC
    /// method is added to `EngineXPCProtocol` (#62 follow-up).
    private func clearCache() {
        NSLog("[StorageSettings] clear cache requested — XPC method not yet implemented")
    }

    /// Stub: logs intent. Wire to `EngineClient.resetDatabase()` once that XPC
    /// method is added to `EngineXPCProtocol` (#62 follow-up).
    private func resetDatabase() {
        NSLog("[StorageSettings] reset database requested — XPC method not yet implemented")
    }

    // MARK: - Disk info

    private func loadDiskInfo() async {
        // File I/O off the main actor — avoid blocking the UI thread on large trees.
        let (size, info) = await Task.detached(priority: .utility) {
            let fm = FileManager.default
            var size: Int64 = 0
            if let cacheURL = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
                size = StorageSettingsPane.directorySize(at: cacheURL)
            }
            var info = DiskInfo.empty
            if let attrs = try? fm.attributesOfFileSystem(forPath: NSHomeDirectory()) {
                let total = (attrs[.systemSize] as? Int64) ?? 0
                let free  = (attrs[.systemFreeSize] as? Int64) ?? 0
                info = DiskInfo(totalBytes: total, availableBytes: free)
            }
            return (size, info)
        }.value
        cacheSize = size
        diskInfo = info
    }

    /// Recursive byte count for a directory tree.
    /// Called from a detached task — must be `static` (no actor isolation).
    private static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}

// MARK: - DiskInfo value type

private struct DiskInfo {
    let totalBytes: Int64
    let availableBytes: Int64

    static let empty = DiskInfo(totalBytes: 0, availableBytes: 0)

    var totalFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var availableFormatted: String {
        ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
    }
}
