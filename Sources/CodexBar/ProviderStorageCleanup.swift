import CodexBarCore
import Foundation

/// Moves a storage cleanup recommendation's path to the Trash (recoverable via Finder's Put Back).
enum ProviderStorageCleanup {
    enum Failure: LocalizedError, Equatable {
        /// The path is not strictly inside one of the footprint's scanned provider roots.
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
        guard self.isStrictlyInsideRoot(recommendation.path, roots: footprint.paths) else {
            throw Failure.outsideProviderRoots
        }
        try fileManager.trashItem(at: URL(fileURLWithPath: recommendation.path), resultingItemURL: nil)
    }

    /// Resolves symlinks on both sides so a component can never escape its provider root, and refuses the
    /// root itself: cleanup targets a provider's sub-folder, never the whole provider directory.
    static func isStrictlyInsideRoot(_ path: String, roots: [String]) -> Bool {
        let target = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return roots.contains { root in
            let rootComponents = URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL
                .pathComponents
            return target.count > rootComponents.count && Array(target.prefix(rootComponents.count)) == rootComponents
        }
    }
}
