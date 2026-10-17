import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct MenuDescriptorUpdateAndVersionTests {
    @Test(arguments: [nil, "9.9.9"], [false, true])
    func `menu offers an install action only when an update is known`(available: String?, ready: Bool) {
        let descriptor = self.descriptor(availableVersion: available, ready: ready, version: "1.2.3")
        let entries = descriptor.sections.flatMap(\.entries)
        let actions = entries.compactMap { entry -> MenuDescriptor.MenuAction? in
            guard case let .action(_, action) = entry else { return nil }
            return action
        }
        let labels = entries.compactMap { entry -> String? in
            guard case let .action(label, _) = entry else { return nil }
            return label
        }

        #expect(actions.contains(.installUpdate) == (ready || available != nil))
        #expect(labels.contains(String(format: L("Update to %@"), "9.9.9")) == (available != nil && !ready))
        #expect(!labels.contains(L("check_for_updates")))
        #expect(actions.contains(.refresh))
        #expect(actions.contains(.settings))
        #expect(actions.contains(.about))
        #expect(actions.contains(.quit))
    }

    @Test(arguments: ["", "1.2.3", "1.2.3beta4"])
    func `about label includes only a known short version`(version: String) {
        let descriptor = self.descriptor(ready: false, version: version)
        let labels = descriptor.sections.flatMap(\.entries).compactMap { entry -> String? in
            guard case let .action(label, .about) = entry else { return nil }
            return label
        }

        #expect(labels == [L("About CodexBar") + (version.isEmpty ? "" : " (v\(version))")])
    }

    @Test(arguments: [
        ("codex-cli 1.2.3", "1.2.3"),
        ("1.2.3beta4", "1.2.3"),
        ("build 12 version 3.4", "12"),
        ("no version", ""),
        ("v1.2.", "1.2"),
    ])
    func `provider headline retains its first numeric version`(raw: String, expected: String) throws {
        let descriptor = self.descriptor(ready: false, version: "", providerVersion: raw)
        let headlines = descriptor.sections.flatMap(\.entries).compactMap { entry -> String? in
            guard case let .text(label, .headline) = entry else { return nil }
            return label
        }
        let name = try #require(ProviderRegistry.shared.metadata[.codex]?.displayName)
        #expect(headlines.first == name + (expected.isEmpty ? "" : " \(expected)"))
    }

    @Test
    func `install update action has its menu symbol`() {
        #expect(MenuDescriptor.MenuAction.installUpdate.systemImageName == "arrow.down.circle")
    }

    private func descriptor(
        availableVersion: String? = nil,
        ready: Bool,
        version: String,
        providerVersion: String? = nil) -> MenuDescriptor
    {
        let settings = testSettingsStore(
            suiteName: "MenuDescriptorUpdateAndVersionTests",
            userDefaults: InMemoryUserDefaults(),
            config: testConfigWithAllProvidersDisabled())
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            environmentBase: [:])
        store.accountInfoCache[.codex] = UsageStore.AccountInfoCacheEntry(
            account: AccountInfo(email: nil, plan: nil),
            configRevision: settings.configRevision,
            expiresAt: .distantFuture)
        store.versions[.codex] = providerVersion
        return MenuDescriptor.build(
            provider: providerVersion == nil ? nil : .codex,
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updateReady: ready,
            availableUpdateVersion: availableVersion,
            versionText: version,
            includeContextualActions: false)
    }
}
