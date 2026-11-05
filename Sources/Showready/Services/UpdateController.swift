#if os(macOS)
import AppKit
import Foundation
import ShowreadyCore

/// Owns the update lifecycle: the quiet scheduled check, the offer alert, and
/// the download–verify–swap install. One instance for the whole app, created
/// at launch.
@MainActor
final class UpdateController: ObservableObject {
    @Published var availableUpdate: AvailableUpdate?
    @Published var checking = false
    @Published var status = ""
    @Published private(set) var isInstalling = false

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private var timer: Timer?

    /// Starts the launch check plus an hourly tick that consults the user's
    /// daily/weekly preference. A launch-only check is a bug: a copy left open
    /// for a week would never check again.
    func start() {
        // `swift run` has no bundle and so no version: auto-offering 0.0.0 →
        // latest on every dev run would be noise, not an updater.
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            Task { @MainActor in self.checkIfDue() }
        }
    }

    /// Quiet scheduled check. Nothing interrupts the user on failure — a
    /// network error here retries on the next hourly tick, not a day later,
    /// because the check time is only recorded on success.
    private func checkIfDue() {
        guard UpdatePreference.isDue else { return }
        Task {
            do {
                let found = try await UpdateChecker().check()
                UpdatePreference.lastChecked = Date()
                if let update = found {
                    availableUpdate = update
                    offer(update)
                }
            } catch {
                // Retried on the next tick.
            }
        }
    }

    /// Manual check from Settings: always contacts GitHub and reports either
    /// way.
    func checkNow() {
        guard !checking else { return }
        checking = true
        status = "Checking…"
        Task {
            do {
                let found = try await UpdateChecker().check()
                UpdatePreference.lastChecked = Date()
                availableUpdate = found
                status = found.map { "Version \($0.version) is available." } ?? "You're up to date."
            } catch {
                status = error.localizedDescription
            }
            checking = false
        }
    }

    /// Asks, then does the whole thing. The user's part is one button.
    func offer(_ update: AvailableUpdate) {
        guard !isInstalling else { return }
        guard UpdateOfferAlert.ask(version: update.version.description, notes: update.releaseNotes) else {
            return
        }
        install(update)
    }

    private func install(_ update: AvailableUpdate) {
        isInstalling = true
        let progress = UpdateProgressWindow(version: update.version.description)
        progress.show(UpdateProgress("Starting…"))
        Task {
            do {
                let staged = try await Updater().stage(update) { step in
                    Task { @MainActor in progress.show(step) }
                }
                // Replaces the app and relaunches it; this process does not
                // return from here.
                try Updater.relaunch(with: staged)
            } catch {
                progress.close()
                isInstalling = false

                let failed = NSAlert()
                failed.alertStyle = .warning
                failed.messageText = "Couldn't install the update"
                failed.informativeText = """
                \(error.localizedDescription)

                Showready is still running and unchanged. You can download it yourself from the releases page.
                """
                failed.addButton(withTitle: "Open Releases Page")
                failed.addButton(withTitle: "Cancel")
                NSApp.activate()
                if failed.runModal() == .alertFirstButtonReturn,
                   let page = UpdateChecker.trusted(update.pageURL) {
                    NSWorkspace.shared.open(page)
                }
            }
        }
    }
}
#endif
