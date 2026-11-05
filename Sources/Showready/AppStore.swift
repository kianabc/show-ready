#if os(macOS)
import AppKit
import SwiftUI
import ShowreadyCore

enum PhotoStatus: Equatable {
    case idle, queued, working, done, failed(String)

    var label: String {
        switch self {
        case .idle: return ""
        case .queued: return "Queued"
        case .working: return "Editing…"
        case .done: return "Done"
        case .failed: return "Failed"
        }
    }
}

struct PhotoItem: Identifiable {
    let id = UUID()
    let url: URL
    var name: String { url.deletingPathExtension().lastPathComponent }
    var size: PixelSize
    var thumbnail: NSImage?
    var options: EditOptions
    /// Listing this photo belongs to; empty means unsorted.
    var listing: String = ""
    var status: PhotoStatus = .idle
    var results: [EditVersion] = []  // one per variation, newest run last
    var chosen: Int = 0
    /// The user approved the chosen version. Cleared when the chosen version changes.
    var approved = false
    var maskStrokes: [MaskStroke] = []

    var chosenVersion: EditVersion? { results.indices.contains(chosen) ? results[chosen] : nil }
    var chosenResult: URL? { chosenVersion?.url }
    var lastCost: Double? { results.last?.cost }
}

/// One edited result, with what was asked for when it was made (for the MLS disclosure log).
struct EditVersion: Equatable, Sendable {
    var url: URL
    var edits: [String]
    var altered: Bool
    var cost: Double
    /// Edge-similarity to the original (0-1); nil for local edits, which cannot drift.
    var structureScore: Double? = nil

    /// The AI changed the structure of the scene; the user should review before using it.
    var structureSuspect: Bool { (structureScore ?? 1) < StructureCheck.warnBelow }
}

/// Settings that persist between launches.
struct AppSettings: Codable, Equatable {
    var modelID = "gpt-image-2"
    var quality: ImageQuality = .medium
    var outputLongEdge = 2048
    var variations = 1
    var concurrency = 2
    var levelHorizonLocally = false
    var exportLongEdge = 2048          // common MLS upload size; 0 keeps model size
    var confirmAbove = 5.0             // ask before batches above this many dollars
    var addDisclosureToFilename = false
    // The user's favorite edit settings, used for every newly imported photo.
    // Optional so settings saved by older builds still decode.
    var defaultInteriorOptions: EditOptions? = nil
    var defaultExteriorOptions: EditOptions? = nil
}

@MainActor
final class AppStore: ObservableObject {
    @Published var photos: [PhotoItem] = []
    @Published var selection: Set<PhotoItem.ID> = []
    @Published var settings: AppSettings { didSet { save(settings, "settings") } }
    @Published var models: [ImageModel] { didSet { save(models, "models") } }
    @Published var calibration: Calibration { didSet { save(calibration, "calibration") } }
    @Published var ledger: SpendLedger { didSet { save(ledger, "ledger") } }
    @Published var apiKey: String { didSet { Keychain.save(apiKey) } }
    @Published var isRunning = false
    @Published var alert: String?
    @Published var pendingBatch: (ids: [PhotoItem.ID], estimate: Double)?
    @Published var listings: [String] = []
    /// New imports go into this listing; nil means unsorted.
    @Published var currentListing: String?

    private var runTask: Task<Void, Never>?
    let workDir: URL

    init() {
        settings = AppStore.load("settings") ?? AppSettings()
        models = AppStore.load("models") ?? ModelCatalog.defaults
        calibration = AppStore.load("calibration") ?? Calibration()
        ledger = AppStore.load("ledger") ?? SpendLedger()
        // An OPENAI_API_KEY environment variable is used when the Keychain is empty (handy for CI and terminal runs).
        let stored = Keychain.load()
        apiKey = stored.isEmpty ? (ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "") : stored
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        workDir = support.appendingPathComponent("Showready/Results", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    // MARK: Persistence

    private func save<T: Encodable>(_ v: T, _ key: String) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    // MARK: Model helpers

    var model: ImageModel {
        models.first { $0.id == settings.modelID } ?? models.first ?? ModelCatalog.defaults[0]
    }

    var effectiveQuality: ImageQuality {
        model.qualities.contains(settings.quality) ? settings.quality : (model.qualities.last ?? .high)
    }

    func outputSize(for p: PhotoItem) -> PixelSize {
        OutputSizer.size(for: p.size, longEdge: settings.outputLongEdge, model: model)
    }

    func estimate(for p: PhotoItem) -> CostEstimate {
        let out = outputSize(for: p)
        return CostEstimator.estimate(model: model, quality: effectiveQuality, inputSize: out, outputSize: out,
                                      prompt: PromptBuilder.prompt(for: p.options, hasMask: !p.maskStrokes.isEmpty),
                                      variations: settings.variations, hasMask: !p.maskStrokes.isEmpty,
                                      calibration: calibration)
    }

    func estimate(ids: [PhotoItem.ID]) -> Double {
        photos.filter { ids.contains($0.id) }.reduce(0) { $0 + estimate(for: $1).dollars }
    }

    func index(_ id: PhotoItem.ID) -> Int? { photos.firstIndex { $0.id == id } }

    var selectedIDs: [PhotoItem.ID] { photos.map(\.id).filter { selection.contains($0) } }

    // MARK: Default edit settings (the user's presets)

    /// What a newly imported photo starts with: the saved preset for its kind, or the built-in defaults.
    func defaultOptions(for kind: PhotoKind) -> EditOptions {
        var o = (kind == .interior ? settings.defaultInteriorOptions : settings.defaultExteriorOptions)
            ?? EditOptions.defaults(for: kind)
        o.kind = kind
        o.customInstructions = ""
        return o
    }

    /// Saves one photo's options as the preset for new photos of that kind.
    func saveDefaultOptions(from id: PhotoItem.ID) {
        guard let src = photos.first(where: { $0.id == id }) else { return }
        var o = src.options
        o.customInstructions = ""   // photo-specific notes don't belong in a preset
        if o.kind == .interior { settings.defaultInteriorOptions = o }
        else { settings.defaultExteriorOptions = o }
    }

    /// Copies one photo's options to every photo of the same kind,
    /// keeping each photo's own custom instructions.
    func applyOptionsToAll(from id: PhotoItem.ID) {
        guard let src = photos.first(where: { $0.id == id }) else { return }
        for i in photos.indices where photos[i].options.kind == src.options.kind && photos[i].id != id {
            var o = src.options
            o.customInstructions = photos[i].options.customInstructions
            photos[i].options = o
        }
    }

    // MARK: Listings

    func addListing(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        if !listings.contains(n) { listings.append(n) }
        currentListing = n
    }

    func moveToListing(_ ids: [PhotoItem.ID], listing: String) {
        for i in photos.indices where ids.contains(photos[i].id) { photos[i].listing = listing }
    }

    /// Sidebar sections. A single unnamed section until the first listing exists.
    var listingSections: [(name: String, items: [PhotoItem])] {
        let hasListings = !listings.isEmpty || photos.contains { !$0.listing.isEmpty }
        guard hasListings else { return [("", photos)] }
        var names = listings
        for p in photos where !p.listing.isEmpty && !names.contains(p.listing) { names.append(p.listing) }
        var out: [(String, [PhotoItem])] = names.map { n in (n, photos.filter { $0.listing == n }) }
        let unsorted = photos.filter { $0.listing.isEmpty }
        if !unsorted.isEmpty { out.append(("Unsorted", unsorted)) }
        return out
    }

    // MARK: Approval

    var approvedIDs: [PhotoItem.ID] { photos.filter { $0.approved && $0.chosenResult != nil }.map(\.id) }

    // MARK: Import

    func importURLs(_ urls: [URL]) {
        var files: [URL] = []
        for u in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                let items = (try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? []
                files += items.sorted { $0.lastPathComponent < $1.lastPathComponent }
            } else {
                files.append(u)
            }
        }
        let exts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "dng", "cr2", "cr3", "nef", "arw"]
        let known = Set(photos.map(\.url))
        let newFiles = files.filter { exts.contains($0.pathExtension.lowercased()) && !known.contains($0) }
        guard !newFiles.isEmpty else { return }
        Task {
            // Load a few photos at a time. One decode + Vision classification per
            // file is fine; dozens at once spike memory and get the app killed.
            let window = 3
            var unreadable: [String] = []
            await withTaskGroup(of: (URL, (PixelSize, NSImage?, PhotoKind)?).self) { group in
                var iterator = newFiles.makeIterator()
                func addNext() {
                    guard let url = iterator.next() else { return }
                    group.addTask {
                        await Task.detached(priority: .userInitiated) { () -> (URL, (PixelSize, NSImage?, PhotoKind)?) in
                            guard let size = ImageTools.pixelSize(url) else { return (url, nil) }
                            return (url, (size, ImageTools.thumbnail(url), ImageTools.guessKind(url)))
                        }.value
                    }
                }
                for _ in 0..<window { addNext() }
                for await (url, loaded) in group {
                    if let (size, thumb, kind) = loaded {
                        if !self.photos.contains(where: { $0.url == url }) {
                            self.photos.append(PhotoItem(url: url, size: size, thumbnail: thumb,
                                                         options: self.defaultOptions(for: kind),
                                                         listing: self.currentListing ?? ""))
                            if self.selection.isEmpty, let first = self.photos.first { self.selection = [first.id] }
                        }
                    } else {
                        unreadable.append(url.lastPathComponent)
                    }
                    addNext()
                }
            }
            if !unreadable.isEmpty {
                self.alert = "Could not read: \(unreadable.joined(separator: ", "))"
            }
        }
    }

    func remove(_ ids: [PhotoItem.ID]) {
        photos.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    /// Copies one photo's options to others of the same kind, for consistent listings.
    func applyOptionsToSelection(from id: PhotoItem.ID) {
        guard let src = photos.first(where: { $0.id == id }) else { return }
        for i in photos.indices where selection.contains(photos[i].id) && photos[i].options.kind == src.options.kind {
            photos[i].options = src.options
        }
    }

    // MARK: Processing

    func requestRun(_ ids: [PhotoItem.ID]) {
        guard !ids.isEmpty else { return }
        guard !apiKey.isEmpty else { alert = OpenAIError.missingKey.errorDescription; return }
        let est = estimate(ids: ids)
        if est > settings.confirmAbove {
            pendingBatch = (ids, est)
        } else {
            run(ids)
        }
    }

    func run(_ ids: [PhotoItem.ID]) {
        pendingBatch = nil
        for id in ids { if let i = index(id) { photos[i].status = .queued } }
        isRunning = true
        let limit = max(1, settings.concurrency)
        runTask = Task {
            await withTaskGroup(of: Void.self) { group in
                var running = 0
                for id in ids {
                    if Task.isCancelled { break }
                    if running >= limit { _ = await group.next(); running -= 1 }
                    group.addTask { await self.process(id) }
                    running += 1
                }
            }
            for i in photos.indices where photos[i].status == .queued { photos[i].status = .idle }
            isRunning = false
        }
    }

    func cancel() {
        runTask?.cancel()
    }

    private func process(_ id: PhotoItem.ID) async {
        guard !Task.isCancelled, let i = index(id) else { return }
        photos[i].status = .working
        let p = photos[i]
        let model = self.model
        let quality = effectiveQuality
        let size = outputSize(for: p)
        let hasMask = !p.maskStrokes.isEmpty
        let prompt = PromptBuilder.prompt(for: p.options, hasMask: hasMask)
        let est = estimate(for: p)
        let level = settings.levelHorizonLocally
        let n = settings.variations
        let client = OpenAIImageClient(apiKey: apiKey)
        let strokes = p.maskStrokes
        let workDir = self.workDir
        let sourceURL = p.url
        let sourceSize = p.size
        let summary = p.options.summary
        let altered = p.options.isMaterialAlteration

        do {
            let work = Task.detached(priority: .userInitiated) { () -> (EditResult, [URL], [Double?]) in
                // Levelling rotates the photo, which would misplace a painted mask.
                let upload = try ImageTools.uploadData(sourceURL, size: size, levelHorizon: level && !hasMask, asPNG: hasMask)
                let crop = ImageTools.fillCrop(source: sourceSize, target: size)
                let mask = hasMask ? MaskRenderer.png(strokes: strokes, size: size, crop: crop) : nil
                let req = EditRequest(model: model, prompt: prompt, image: upload,
                                      imageMime: hasMask ? "image/png" : "image/jpeg", mask: mask,
                                      size: size, quality: quality, variations: n)
                let r = try await client.edit(req)
                var urls: [URL] = []
                for data in r.images {
                    let u = workDir.appendingPathComponent("\(UUID().uuidString).jpg")
                    try data.write(to: u)
                    urls.append(u)
                }
                let scores = urls.map {
                    ImageTools.structureScore(sourceURL: sourceURL, resultURL: $0, leveled: level && !hasMask)
                }
                return (r, urls, scores)
            }
            let result = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }

            let actual = result.0.usage.map { CostEstimator.actualCost(model: model, usage: $0) }
            if let usage = result.0.usage {
                calibration.record(model: model.id, quality: quality, usage: usage, outputSize: size,
                                   imageCount: result.1.count, inputSize: size)
            }
            ledger.entries.append(SpendEntry(photoName: p.url.lastPathComponent, model: model.id,
                                             quality: quality, estimated: est.dollars, actual: actual,
                                             edits: p.options.summary))
            guard let j = index(id) else { return }
            let perImage = (actual ?? est.dollars) / Double(max(result.1.count, 1))
            let versions = zip(result.1, result.2).map {
                EditVersion(url: $0, edits: summary, altered: altered, cost: perImage, structureScore: $1)
            }
            photos[j].results.append(contentsOf: versions)
            photos[j].chosen = photos[j].results.count - versions.count
            photos[j].status = .done
        } catch is CancellationError {
            if let j = index(id) { photos[j].status = .idle }
        } catch let e as URLError where e.code == .cancelled {
            if let j = index(id) { photos[j].status = .idle }
        } catch {
            if let j = index(id) { photos[j].status = .failed(error.localizedDescription) }
        }
    }

    /// Free local enhancement, no API call.
    func quickEnhance(_ ids: [PhotoItem.ID]) {
        let level = settings.levelHorizonLocally
        let jobs: [(PhotoItem.ID, URL)] = ids.compactMap { id in index(id).map { (id, photos[$0].url) } }
        guard !jobs.isEmpty else { return }
        for (id, _) in jobs { if let i = index(id) { photos[i].status = .queued } }
        let workDir = self.workDir
        Task {
            // A couple at a time: each job renders the photo at full resolution,
            // and dozens at once spike memory and freeze the Mac.
            let window = 2
            await withTaskGroup(of: (PhotoItem.ID, Result<URL, Error>).self) { group in
                var iterator = jobs.makeIterator()
                @MainActor func addNext() {
                    guard let (id, url) = iterator.next() else { return }
                    if let i = self.index(id) { self.photos[i].status = .working }
                    group.addTask {
                        await Task.detached(priority: .userInitiated) {
                            do {
                                let out = workDir.appendingPathComponent("\(UUID().uuidString).jpg")
                                let img = try ImageTools.quickEnhance(url, levelHorizon: level)
                                try ImageTools.jpeg(img, quality: 0.93).write(to: out)
                                return (id, .success(out))
                            } catch {
                                return (id, .failure(error))
                            }
                        }.value
                    }
                }
                for _ in 0..<window { addNext() }
                for await (id, result) in group {
                    if let j = self.index(id) {
                        switch result {
                        case .success(let out):
                            self.photos[j].results.append(EditVersion(url: out, edits: ["local auto-enhance"], altered: false, cost: 0))
                            self.photos[j].chosen = self.photos[j].results.count - 1
                            self.photos[j].status = .done
                        case .failure(let e):
                            self.photos[j].status = .failed(e.localizedDescription)
                        }
                    }
                    addNext()
                }
            }
        }
    }

    // MARK: Export

    /// Exports every approved photo in one go.
    func saveApproved() {
        let ids = approvedIDs
        guard !ids.isEmpty else {
            alert = "No approved photos yet. Open a photo and press Approve (or the A key) on the edits you like."
            return
        }
        export(ids)
    }

    func export(_ ids: [PhotoItem.ID]) {
        let ready = photos.filter { ids.contains($0.id) && $0.chosenResult != nil }
        guard !ready.isEmpty else { alert = "Nothing to export yet. Edit some photos first."; return }
        // Hop off SwiftUI's action dispatch before touching NSOpenPanel; creating
        // one inside the update transaction deadlocks (see ImportPanel.run).
        DispatchQueue.main.async { [self] in
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Export Here"
            guard panel.runModal() == .OK, let folder = panel.url else { return }

            Task {
                let failures = await exportTo(folder, ids: ready.map(\.id))
                NSWorkspace.shared.activateFileViewerSelecting([folder])
                if !failures.isEmpty { alert = "Could not export: \(failures.joined(separator: ", "))" }
            }
        }
    }

    /// Writes chosen versions plus edit-log.csv into `folder`. Photos spanning
    /// several listings land in one subfolder per listing. Returns names that failed.
    func exportTo(_ folder: URL, ids: [PhotoItem.ID]) async -> [String] {
        struct Job: Sendable {
            var base: String; var original: String; var version: EditVersion
            var approved: Bool; var listing: String
        }
        let ready = photos.filter { ids.contains($0.id) && $0.chosenVersion != nil }
        let longEdge = settings.exportLongEdge > 0 ? settings.exportLongEdge : nil
        let addSuffix = settings.addDisclosureToFilename
        let jobs = ready.map {
            Job(base: $0.name, original: $0.url.lastPathComponent, version: $0.chosenVersion!,
                approved: $0.approved, listing: $0.listing)
        }
        isRunning = true
        defer { isRunning = false }
        return await Task.detached(priority: .userInitiated) { () -> [String] in
            var failures: [String] = []
            let split = Set(jobs.map(\.listing)).count > 1
            for (listing, jobs) in Dictionary(grouping: jobs, by: \.listing).sorted(by: { $0.key < $1.key }) {
                var dir = folder
                if split {
                    let name = listing.isEmpty ? "Unsorted"
                        : listing.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                    dir = folder.appendingPathComponent(name, isDirectory: true)
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                var csv = "file,original,edits,digitally_altered,approved,structure_check,cost_usd\n"
                for (n, job) in jobs.enumerated() {
                    let v = job.version
                    let suffix = (v.altered && addSuffix) ? "-virtually-enhanced" : ""
                    let name = String(format: "%02d-%@%@.jpg", n + 1, job.base, suffix)
                    do {
                        try ImageTools.export(v.url, to: dir.appendingPathComponent(name), longEdge: longEdge)
                        let edits = v.edits.joined(separator: "; ").replacingOccurrences(of: "\"", with: "'")
                        let check = v.structureScore.map { String(format: $0 < StructureCheck.warnBelow ? "REVIEW %.2f" : "ok %.2f", $0) } ?? ""
                        csv += "\"\(name)\",\"\(job.original)\",\"\(edits)\",\(v.altered ? "yes" : "no"),\(job.approved ? "yes" : "no"),\(check),\(String(format: "%.4f", v.cost))\n"
                    } catch {
                        failures.append(job.base)
                    }
                }
                try? csv.write(to: dir.appendingPathComponent("edit-log.csv"), atomically: true, encoding: .utf8)
            }
            return failures
        }.value
    }
}
#endif
