import CodexBarCore
import Foundation

/// Moves a storage cleanup recommendation's path to the Trash (recoverable via Finder's Put Back).
enum ProviderStorageCleanup {
    enum Failure: LocalizedError, Equatable {
        /// The path is not strictly inside one of the footprint's scanned provider roots, or the chain from that
        /// root down to the path no longer consists of real directories.
        case outsideProviderRoots

        var errorDescription: String? {
            switch self {
            case .outsideProviderRoots: L("storage_cleanup_outside_root")
            }
        }
    }

    static func moveToTrash(
        _ recommendation: ProviderStorageRecommendation,
        footprint: ProviderStorageFootprint,
        fileManager: FileManager = .default) throws
    {
        // Validate immediately before the Trash I/O so the check reflects the filesystem at deletion time.
        // Logs carry only the provider and component name, never full paths.
        let logger = CodexBarLog.logger(LogCategories.providers)
        let metadata = [
            "provider": recommendation.provider.rawValue,
            "component": URL(fileURLWithPath: recommendation.path).lastPathComponent,
        ]
        let target: URL
        do {
            target = try self.validatedTarget(recommendation.path, footprint: footprint, fileManager: fileManager)
        } catch {
            logger.warning("Storage cleanup refused: outside scanned provider root", metadata: metadata)
            throw error
        }
        try fileManager.trashItem(at: target, resultingItemURL: nil)
        logger.info("Storage cleanup moved item to Trash", metadata: metadata)
    }

    /// Binds cleanup to the objects that were scanned, not just their paths:
    /// - paths are compared as written (never symlink-resolved), and the target must be strictly inside a root;
    /// - the root and every component down to the target must still be real, non-symlink items
    ///   (`ProviderStorageScanner` never descends through a symlinked root);
    /// - the live root and target must be the same on-disk objects (device + inode) the scan recorded, so a root
    ///   or target replaced after scanning — by a symlink or by another ordinary directory — is refused.
    static func validatedTarget(
        _ path: String,
        footprint: ProviderStorageFootprint,
        fileManager: FileManager = .default) throws -> URL
    {
        let target = URL(fileURLWithPath: path).standardizedFileURL
        let targetComponents = target.pathComponents
        for root in footprint.paths {
            let rootURL = URL(fileURLWithPath: root).standardizedFileURL
            let rootComponents = rootURL.pathComponents
            guard targetComponents.count > rootComponents.count,
                  Array(targetComponents.prefix(rootComponents.count)) == rootComponents
            else { continue }

            var current = rootURL
            guard self.isRealItem(current, fileManager: fileManager) else { throw Failure.outsideProviderRoots }
            for component in targetComponents.dropFirst(rootComponents.count) {
                current.appendPathComponent(component)
                guard self.isRealItem(current, fileManager: fileManager) else {
                    throw Failure.outsideProviderRoots
                }
            }

            guard let scannedRoot = footprint.rootIdentities[root],
                  ProviderStorageFileIdentity.current(atPath: rootURL.path, fileManager: fileManager) == scannedRoot,
                  let scannedTarget = footprint.components
                      .first(where: { URL(fileURLWithPath: $0.path).standardizedFileURL == target })?.identity,
                      ProviderStorageFileIdentity
                          .current(atPath: target.path, fileManager: fileManager) == scannedTarget
            else {
                throw Failure.outsideProviderRoots
            }
            return target
        }
        throw Failure.outsideProviderRoots
    }

    /// `attributesOfItem` does not follow symlinks (lstat), so a link reports its own type.
    private static func isRealItem(_ url: URL, fileManager: FileManager) -> Bool {
        guard let type = try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType else {
            return false
        }
        return type != .typeSymbolicLink
    }
}
