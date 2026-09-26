import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct ProviderStorageCleanupTests {
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

    private func footprint(root: String) -> ProviderStorageFootprint {
        ProviderStorageFootprint(
            provider: .claude,
            totalBytes: 10,
            paths: [root],
            missingPaths: [],
            unreadablePaths: [],
            updatedAt: Date())
    }

    @Test
    func `only paths strictly inside a provider root are eligible`() {
        let roots = ["/Users/test/.claude"]
        #expect(ProviderStorageCleanup.isStrictlyInsideRoot("/Users/test/.claude/debug", roots: roots))
        #expect(ProviderStorageCleanup.isStrictlyInsideRoot("/Users/test/.claude/projects/a", roots: roots))
        #expect(!ProviderStorageCleanup.isStrictlyInsideRoot("/Users/test/.claude", roots: roots))
        #expect(!ProviderStorageCleanup.isStrictlyInsideRoot("/Users/test/.claude-other/debug", roots: roots))
        #expect(!ProviderStorageCleanup.isStrictlyInsideRoot("/Users/test/.claude/../Documents", roots: roots))
        #expect(!ProviderStorageCleanup.isStrictlyInsideRoot("/Users/test/Documents", roots: roots))
    }

    @Test
    func `symlinked component escaping the root is refused`() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("storage-cleanup-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: base) }
        let root = base.appendingPathComponent("root")
        let outside = base.appendingPathComponent("outside")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("debug")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)

        #expect(throws: ProviderStorageCleanup.Failure.outsideProviderRoots) {
            try ProviderStorageCleanup.moveToTrash(
                self.recommendation(path: link.path),
                footprint: self.footprint(root: root.path))
        }
        #expect(fm.fileExists(atPath: outside.path))
    }

    @Test
    func `root itself is never trashed`() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("storage-cleanup-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        #expect(throws: ProviderStorageCleanup.Failure.outsideProviderRoots) {
            try ProviderStorageCleanup.moveToTrash(
                self.recommendation(path: root.path),
                footprint: self.footprint(root: root.path))
        }
        #expect(fm.fileExists(atPath: root.path))
    }
}
