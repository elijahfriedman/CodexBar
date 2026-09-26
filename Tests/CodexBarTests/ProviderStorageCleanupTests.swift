import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// Records Trash requests instead of touching the user's real Trash.
private final class RecordingTrashFileManager: FileManager, @unchecked Sendable {
    private(set) var trashedPaths: [String] = []

    override func trashItem(
        at url: URL,
        resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws
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

        /// Creates `<dir>/<name>/data.log` with content so the scanner reports `<dir>/<name>` as a component.
        @discardableResult
        func makeComponent(_ name: String, in dir: URL? = nil) throws -> URL {
            let component = (dir ?? self.root).appendingPathComponent(name)
            try FileManager.default.createDirectory(at: component, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 16).write(to: component.appendingPathComponent("data.log"))
            return component
        }

        /// A real scan of the root, so the footprint carries genuine scanned identities.
        func scan() -> ProviderStorageFootprint {
            ProviderStorageScanner().scan(provider: .claude, candidatePaths: [self.root.path])
        }
    }

    private func recommendation(path: URL) -> ProviderStorageRecommendation {
        ProviderStorageRecommendation(
            provider: .claude,
            path: path.path,
            bytes: 16,
            title: "Manual cleanup: debug logs",
            riskLevel: .manualCleanup,
            consequence: "Clearing removes past debug logs.",
            sortPriority: 40)
    }

    private func expectRefused(
        _ path: URL,
        footprint: ProviderStorageFootprint,
        fileManager: RecordingTrashFileManager)
    {
        #expect(throws: ProviderStorageCleanup.Failure.outsideProviderRoots) {
            try ProviderStorageCleanup.moveToTrash(
                self.recommendation(path: path),
                footprint: footprint,
                fileManager: fileManager)
        }
        #expect(fileManager.trashedPaths.isEmpty)
    }

    @Test
    func `scanned child of a scanned root is sent to the trash`() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let debug = try sandbox.makeComponent("debug")
        let footprint = sandbox.scan()
        #expect(footprint.rootIdentities[sandbox.root.path] != nil)
        #expect(footprint.components.first { $0.path == debug.path }?.identity != nil)
        let fm = RecordingTrashFileManager()

        try ProviderStorageCleanup.moveToTrash(self.recommendation(path: debug), footprint: footprint, fileManager: fm)

        #expect(fm.trashedPaths == [debug.path])
    }

    @Test
    func `root itself, siblings, dot-dot escapes, and outside paths are refused`() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.makeComponent("debug")
        let sibling = try sandbox.makeComponent("debug", in: sandbox.base.appendingPathComponent(".claude-other"))
        let footprint = sandbox.scan()
        let fm = RecordingTrashFileManager()

        self.expectRefused(sandbox.root, footprint: footprint, fileManager: fm)
        self.expectRefused(sibling, footprint: footprint, fileManager: fm)
        self.expectRefused(
            URL(fileURLWithPath: sandbox.root.path + "/../outside"),
            footprint: footprint,
            fileManager: fm)
        self.expectRefused(sandbox.outside, footprint: footprint, fileManager: fm)
    }

    @Test
    func `symlinked target escaping the root is refused`() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let link = sandbox.root.appendingPathComponent("debug")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sandbox.outside)
        let footprint = sandbox.scan()
        let fm = RecordingTrashFileManager()

        self.expectRefused(link, footprint: footprint, fileManager: fm)
        #expect(FileManager.default.fileExists(atPath: sandbox.outside.path))
    }

    @Test
    func `symlinked intermediate folder is refused`() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.makeComponent("logs", in: sandbox.outside)
        try FileManager.default.createSymbolicLink(
            at: sandbox.root.appendingPathComponent("projects"),
            withDestinationURL: sandbox.outside)
        let footprint = sandbox.scan()
        let fm = RecordingTrashFileManager()

        self.expectRefused(
            sandbox.root.appendingPathComponent("projects/logs"),
            footprint: footprint,
            fileManager: fm)
    }

    @Test
    func `root replaced by a symlink after scanning is refused`() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let scannedChild = try sandbox.makeComponent("debug")
        let footprint = sandbox.scan()
        let fm = RecordingTrashFileManager()

        // After the scan, the provider root is swapped for a symlink to a directory with the same child name.
        let redirected = try sandbox.makeComponent("debug", in: sandbox.outside)
        try FileManager.default.removeItem(at: sandbox.root)
        try FileManager.default.createSymbolicLink(at: sandbox.root, withDestinationURL: sandbox.outside)

        self.expectRefused(scannedChild, footprint: footprint, fileManager: fm)
        #expect(FileManager.default.fileExists(atPath: redirected.path))
    }

    @Test
    func `root replaced by another real directory after scanning is refused`() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let scannedChild = try sandbox.makeComponent("debug")
        let footprint = sandbox.scan()
        let fm = RecordingTrashFileManager()

        // An ordinary directory takes the scanned root's path and supplies a same-named, never-scanned child.
        let original = sandbox.base.appendingPathComponent(".claude-original")
        try FileManager.default.moveItem(at: sandbox.root, to: original)
        try FileManager.default.createDirectory(at: sandbox.root, withIntermediateDirectories: false)
        let unscanned = try sandbox.makeComponent("debug")
        #expect(unscanned.path == scannedChild.path)

        self.expectRefused(scannedChild, footprint: footprint, fileManager: fm)
        #expect(FileManager.default.fileExists(atPath: unscanned.appendingPathComponent("data.log").path))
    }

    @Test
    func `target replaced by a same-named item after scanning is refused`() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let scannedChild = try sandbox.makeComponent("debug")
        let footprint = sandbox.scan()
        let fm = RecordingTrashFileManager()

        let moved = sandbox.base.appendingPathComponent("debug-scanned")
        try FileManager.default.moveItem(at: scannedChild, to: moved)
        try sandbox.makeComponent("debug")

        self.expectRefused(scannedChild, footprint: footprint, fileManager: fm)
    }

    @Test
    func `missing target is refused`() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let scannedChild = try sandbox.makeComponent("debug")
        let footprint = sandbox.scan()
        try FileManager.default.removeItem(at: scannedChild)
        let fm = RecordingTrashFileManager()

        self.expectRefused(scannedChild, footprint: footprint, fileManager: fm)
    }
}
