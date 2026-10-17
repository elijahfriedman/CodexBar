import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
private final class BackgroundCheckRecordingUpdater: UpdaterProviding {
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    let isAvailable = true
    let unavailableReason: String? = nil
    let updateStatus = UpdateStatus()
    var backgroundCheckCount = 0

    func checkForUpdates(_: Any?) {}
    func checkForUpdatesInBackground() {
        self.backgroundCheckCount += 1
    }

    func installUpdate() {}
}

@MainActor
@Suite(.serialized, CodexCredentialFixtures())
struct StatusMenuRefreshUpdateCheckTests {
    private func makeController(updater: UpdaterProviding) -> StatusItemController {
        let settings = testSettingsStore(suiteName: "StatusMenuRefreshUpdateCheckTests")
        settings.refreshFrequency = .manual
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let environment = [
            "HOME": root.path,
            "CODEX_HOME": root.appendingPathComponent(".codex", isDirectory: true).path,
            "XDG_CONFIG_HOME": root.appendingPathComponent(".config", isDirectory: true).path,
        ]
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: environment)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: updater,
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        controller._test_manualRefreshOperation = {}
        return controller
    }

    @Test
    func `manual refresh also checks for updates in the background`() async throws {
        let updater = BackgroundCheckRecordingUpdater()
        let controller = self.makeController(updater: updater)

        controller.refreshNow()
        let task = try #require(controller.manualRefreshTasks[.global])
        await task.value

        #expect(updater.backgroundCheckCount == 1)
    }

    @Test(arguments: ["ready", "available", "installing"])
    func `manual refresh skips the update check once an update is known`(state: String) async throws {
        let updater = BackgroundCheckRecordingUpdater()
        updater.updateStatus.isUpdateReady = state == "ready"
        updater.updateStatus.availableVersion = state == "available" ? "9.9.9" : nil
        updater.updateStatus.isInstalling = state == "installing"
        let controller = self.makeController(updater: updater)

        controller.refreshNow()
        let task = try #require(controller.manualRefreshTasks[.global])
        await task.value

        #expect(updater.backgroundCheckCount == 0)
    }
}
