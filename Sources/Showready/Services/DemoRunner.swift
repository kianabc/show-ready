#if os(macOS)
import AppKit
import ShowreadyCore

/// Unattended run used by CI to prove the app works end to end.
/// Enabled only when SHOWREADY_DEMO_DIR is set:
///   SHOWREADY_DEMO_DIR  folder of photos to import
///   SHOWREADY_DEMO_OUT  folder for exports, edit log and window screenshots
///   SHOWREADY_DEMO_AI   "1" to run real OpenAI edits (needs OPENAI_API_KEY), otherwise the free local enhance
///   SHOWREADY_DEMO_AI_COUNT  how many photos to send to OpenAI (default 2)
@MainActor
enum DemoRunner {
    static var env: [String: String] { ProcessInfo.processInfo.environment }
    static var isEnabled: Bool { env["SHOWREADY_DEMO_DIR"] != nil }

    static func run(_ store: AppStore) async {
        guard let dir = env["SHOWREADY_DEMO_DIR"] else { return }
        let out = URL(fileURLWithPath: env["SHOWREADY_DEMO_OUT"] ?? NSTemporaryDirectory() + "showready-demo")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var log = ""
        func note(_ s: String) { log += s + "\n"; print("[demo] " + s); fflush(stdout) }

        let folder = URL(fileURLWithPath: dir)
        let expected = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { !$0.hasPrefix(".") }.count
        store.importURLs([folder])
        await waitUntil(60) { store.photos.count >= expected }
        note("Imported \(store.photos.count) of \(expected) photos")
        for p in store.photos { note("  \(p.url.lastPathComponent): \(p.size) detected as \(p.options.kind.label)") }
        guard let first = store.photos.first else { finish(out, log); return }
        store.selection = [first.id]
        await pause(2)
        snapshot(out.appendingPathComponent("1-imported.png"))

        let ids = store.photos.map(\.id)
        if env["SHOWREADY_DEMO_AI"] == "1", !store.apiKey.isEmpty {
            let count = Int(env["SHOWREADY_DEMO_AI_COUNT"] ?? "2") ?? 2
            let aiIDs = Array(ids.prefix(count))
            note("Model \(store.model.id), quality \(store.effectiveQuality.rawValue), long edge \(store.settings.outputLongEdge)")
            note("Estimated cost for \(aiIDs.count) photos: \(store.estimate(ids: aiIDs).dollarString)")
            store.run(aiIDs)
            await waitUntil(900) { !store.isRunning }
        } else {
            note("No AI run (set SHOWREADY_DEMO_AI=1 and OPENAI_API_KEY). Running free local enhance.")
            store.quickEnhance(ids)
            await waitUntil(120) { store.photos.allSatisfy { $0.status != .working } }
        }
        for p in store.photos {
            switch p.status {
            case .failed(let m): note("  FAILED \(p.name): \(m)")
            case .done: note("  done \(p.name): \(p.results.count) version(s), cost \((p.lastCost ?? 0).dollarString)")
            default: note("  \(p.name): \(p.status.label.isEmpty ? "not edited" : p.status.label)")
            }
        }
        note("Spend recorded: \(store.ledger.total.dollarString)")

        // Show the before/after slider on the first edited photo.
        if let edited = store.photos.first(where: { $0.chosenResult != nil }) { store.selection = [edited.id] }
        await pause(4)
        snapshot(out.appendingPathComponent("2-before-after.png"))

        let failures = await store.exportTo(out, ids: ids)
        note("Exported to \(out.path)\(failures.isEmpty ? "" : ", failures: \(failures)")")
        finish(out, log)
    }

    private static func finish(_ out: URL, _ log: String) {
        try? log.write(to: out.appendingPathComponent("demo-log.txt"), atomically: true, encoding: .utf8)
        if env["SHOWREADY_DEMO_QUIT"] == "1" { NSApp.terminate(nil) }
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func waitUntil(_ timeout: Double, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { await pause(0.5) }
    }

    /// Renders the main window into a PNG without needing screen-recording permission.
    static func snapshot(_ url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
