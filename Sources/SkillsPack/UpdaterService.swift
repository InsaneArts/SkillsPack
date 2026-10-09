import AppKit
import Sparkle

/// Sparkle, wrapped so the rest of the app never imports it. Updates are signed with EdDSA and
/// checked against appcast.xml in the repository; there is no SkillsPack server.
@MainActor
final class UpdaterService {
    static let shared = UpdaterService()

    private var controller: SPUStandardUpdaterController?
    private let userDriverDelegate = UserDriverDelegate()

    /// Starts Sparkle once at launch. Does nothing when the bundle carries no feed (a bare `swift run`).
    func start() {
        guard controller == nil, Bundle.main.infoDictionary?["SUFeedURL"] != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: userDriverDelegate)
    }

    var isAvailable: Bool { controller != nil }

    /// A check the user asked for. Sparkle shows its own window, including "you're up to date".
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

/// SkillsPack is `LSUIElement`: no Dock icon, accessory activation policy. Sparkle places and
/// focuses its windows like a regular app, so under `.accessory` the update window can open
/// unfocused. The policy becomes `.regular` while the update UI is up and reverts after.
private final class UserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard state.userInitiated else { return }
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
    }
}
