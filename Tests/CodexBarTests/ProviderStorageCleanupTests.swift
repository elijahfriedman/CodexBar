import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// Records Trash requests instead of touching the user's real Trash.
private final class RecordingTrashFileManager: FileManager, @unchecked Sendable {
    private(set) var trashedPaths: [String] = []

    override func trashItem(at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?)
        throws
    {
        self.trashedPaths.append(url.path)
    }
}

struct ProviderStorageCleanupTests {
    private struct Sandbox {
        let base: URL
        let root: URL
        let outside: URL

        init() throws {
            let fm = FileManager.default
            // Resolve /var -> /private/var once so fixtures match what the scanner records.
            self.base = fm.temporaryDirectory
                .appendingPathComponent("storage-cleanup-\(UUID().uuidString)")
                .resolvingSymlinksInPath()
            self.root = self.base.appendingPathComponent(".claude")
            self.outside = self.base.appendingPathComponent("outside")
            try fm.createDirectory(at: self.root, withIntermediateDirectories: true)
            try fm.createDirectory(at: self.outside, withIntermediateDirectories: true)
        }

        func remove() {
            try? FileManager.default.removeItem(at: self.base)
        }
    }

    private func recommendation(path: String) -> ProviderStorageRecommendation {
        ProviderStorageRecommendation(
            provider: .claude,
            path: path,
            bytes: 10,
            title: "Manual cleanup: debug logs",
            riskLevel: .manualCleanup,
            consequence: "Clearing removes past debug logs.",
            sortPriority: 40)
    }

    private func footprint(root: URL) -> ProviderStorageFootprint {
        ProviderStorageFootprint(
            provider: .claude,
            totalBytes: 10,
            paths: [root.path],
            missingPaths: [],
            unreadablePaths: [],
            updatedAt: Date())
    }

    private func expectRefused(_ path: URL, root: URL, fileManager: RecordingTrashFileManager) {
        #expect(throws: ProviderStorageCleanup.Failure.outsideProviderRoots) {
            try ProviderStorageCleanup.moveToTrash(
                self.recommendation(path: path.path),
                footprint: self.footprint(root: root),
                fileManager: fileManager)
        }
        #expect(fileManager.trashedPaths.isEmpty)
    }

    @Test
    func `child of a real scanned root is sent to the trash`() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let debug = sandbox.root.appendingPathComponent("debug")
        try FileManager.default.createDirectory(at: debug, withIntermediateDirectories: true)
        let fm = RecordingTrashFileManager()

        try ProviderStorageCleanup.moveToTrash(
            self.recommendation(path: debug.path),
            footprint: self.footprint(root: sandbox.root),
            fileManager: fm)

        #expect(fm.trashedPaths == [debug.path])
    }

    @Test
    func `root itself, siblings, dot-dot escapes, and outside paths are refused`() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let sibling = sandbox.base.appendingPathComponent(".claude-other/debug")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let fm = RecordingTrashFileManager()

        self.expectRefused(sandbox.root, root: sandbox.root, fileManager: fm)
        self.expectRefused(sibling, root: sandbox.root, fileManager: fm)
        self.expectRefused(
            URL(fileURLWithPath: sandbox.root.path + "/../outside"),
            root: sandbox.root,
            fileManager: fm)
        self.expectRefused(sandbox.outside, root: sandbox.root, fileManager: fm)
    }

    @Test
    func `symlinked target escaping the root is refused`() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let link = sandbox.root.appendingPathComponent("debug")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sandbox.outside)
        let fm = RecordingTrashFileManager()

        self.expectRefused(link, root: sandbox.root, fileManager: fm)
        #expect(FileManager.default.fileExists(atPath: sandbox.outside.path))
    }

    @Test
    func `symlinked intermediate folder is refused`() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try FileManager.default.createDirectory(
            at: sandbox.outside.appendingPathComponent("logs"),
            withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: sandbox.root.appendingPathComponent("projects"),
            withDestinationURL: sandbox.outside)
        let fm = RecordingTrashFileManager()

        self.expectRefused(sandbox.root.appendingPathComponent("projects/logs"), root: sandbox.root, fileManager: fm)
    }

    @Test
    func `root replaced by a symlink after scanning is refused`() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let fm = RecordingTrashFileManager()
        let footprint = self.footprint(root: sandbox.root)
        let scannedChild = sandbox.root.appendingPathComponent("debug")
        try FileManager.default.createDirectory(at: scannedChild, withIntermediateDirectories: true)

        // After the scan, the provider root is swapped for a symlink to a directory with the same child name.
        let redirected = sandbox.outside.appendingPathComponent("debug")
        try FileManager.default.createDirectory(at: redirected, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: sandbox.root)
        try FileManager.default.createSymbolicLink(at: sandbox.root, withDestinationURL: sandbox.outside)

        #expect(throws: ProviderStorageCleanup.Failure.outsideProviderRoots) {
            try ProviderStorageCleanup.moveToTrash(
                self.recommendation(path: scannedChild.path),
                footprint: footprint,
                fileManager: fm)
        }
        #expect(fm.trashedPaths.isEmpty)
        #expect(FileManager.default.fileExists(atPath: redirected.path))
    }

    @Test
    func `missing target is refused`() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let fm = RecordingTrashFileManager()

        self.expectRefused(sandbox.root.appendingPathComponent("debug"), root: sandbox.root, fileManager: fm)
    }
}
