import AppKit

/// Checks GitHub for a newer release and, with the user's say-so, installs it.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case found(String)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// Automatic checks are a day apart; the timer ticks more often than that so a Mac that
    /// spends most of its time asleep still gets around to one.
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private var timer: Timer?

    private init() {}

    var isBusy: Bool {
        state == .checking || state == .installing
    }

    /// Called once at launch. The first check waits a few seconds so it never competes with
    /// getting the menu bar and event tap up.
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkInBackground() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.checkInBackground()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// The scheduled check: silent unless there is something to install, and skipped
    /// entirely when the user has turned automatic checks off or is already up to date for
    /// today.
    private func checkInBackground() {
        guard Preferences.shared.checksForUpdates, !isBusy else { return }
        if let last = Preferences.shared.lastUpdateCheck,
            Date().timeIntervalSince(last) < checkInterval
        {
            return
        }
        Task { await check(userInitiated: false) }
    }

    /// The "Check for Updates…" command: reports the outcome either way, and ignores a
    /// previously skipped version because the user just asked.
    func checkNow() {
        guard !isBusy else { return }
        Task { await check(userInitiated: true) }
    }

    private func check(userInitiated: Bool) async {
        state = .checking
        // Stamped whether or not the check succeeded: a release with no asset for us, or a
        // Mac that was offline, should wait for tomorrow rather than retry every hour.
        defer { Preferences.shared.lastUpdateCheck = Date() }
        do {
            let release = try await GitHubReleases.latest()

            guard release.version > AppVersion.current else {
                state = .upToDate
                if userInitiated { presentUpToDate() }
                return
            }
            if !userInitiated, Preferences.shared.skippedUpdateVersion == release.version.description
            {
                state = .idle
                return
            }
            state = .found(release.version.description)
            present(release, userInitiated: userInitiated)
        } catch {
            state = .failed(error.localizedDescription)
            if userInitiated { presentFailure(error) }
        }
    }

    // MARK: - Prompts

    private func present(_ release: GitHubRelease, userInitiated: Bool) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "LangKeys \(release.version) is available"
        alert.informativeText =
            release.notes.isEmpty
            ? "You have \(AppVersion.current). Install the update and relaunch?"
            : "You have \(AppVersion.current).\n\n\(release.notes)"
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        // Skipping only suppresses the automatic prompt, so it is pointless on a manual check.
        if !userInitiated { alert.addButton(withTitle: "Skip This Version") }

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            install(release)
        case .alertThirdButtonReturn:
            Preferences.shared.skippedUpdateVersion = release.version.description
            state = .idle
        default:
            state = .idle
        }
    }

    private func install(_ release: GitHubRelease) {
        state = .installing
        Task {
            do {
                try await UpdateInstaller.installAndRelaunch(release)
            } catch {
                state = .failed(error.localizedDescription)
                presentInstallFailure(error, release: release)
            }
        }
    }

    private func presentUpToDate() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "LangKeys is up to date"
        alert.informativeText = "You are running version \(AppVersion.current)."
        alert.runModal()
        state = .idle
    }

    private func presentFailure(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Could not check for updates"
        alert.informativeText = error.localizedDescription
        alert.runModal()
        state = .idle
    }

    /// A failed install leaves the app it was replacing untouched, so the way out is always
    /// to grab the release by hand.
    private func presentInstallFailure(_ error: Error, release: GitHubRelease) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "The update was not installed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.pageURL)
        }
        state = .idle
    }
}
