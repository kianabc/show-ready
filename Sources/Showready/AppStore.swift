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
    var status: PhotoStatus = .idle
    var results: [EditVersion] = []  // one per variation, newest run last
    var chosen: Int = 0
    var maskStrokes: [MaskStroke] = []

    var chosenVersion: EditVersion? { results.indices.contains(chosen) ? results[chosen] : nil }
    var chosenResult: URL? { chosenVersion?.url }
    var lastCost: Double? { results.last?.cost }
}

/// One edited result, with what was asked for when it was made (for the MLS disclosure log).
struct EditVersion: Equatable {
    var url: URL
    var edits: [String]
    var altered: Bool
    var cost: Double
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

    private var runTask: Task<Void, Never>?
    let workDir: URL

    init() {
        settings = AppStore.load("settings") ?? AppSettings()
        models = AppStore.load("models") ?? ModelCatalog.defaults
        calibration = AppStore.load("calibration") ?? Calibration()
        ledger = AppStore.load("ledger") ?? SpendLedger()
        apiKey = Keychain.load()
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
        for url in files where exts.contains(url.pathExtension.lowercased()) && !known.contains(url) {
            Task {
                let loaded = await Task.detached(priority: .userInitiated) { () -> (PixelSize, NSImage?, PhotoKind)? in
                    guard let size = ImageTools.pixelSize(url) else { return nil }
                    return (size, ImageTools.thumbnail(url), ImageTools.guessKind(url))
                }.value
                guard let loaded else {
                    self.alert = "Could not read \(url.lastPathComponent)."
                    return
                }
                let (size, thumb, kind) = loaded
                guard !self.photos.contains(where: { $0.url == url }) else { return }
                self.photos.append(PhotoItem(url: url, size: size, thumbnail: thumb,
                                             options: .defaults(for: kind)))
                if self.selection.isEmpty, let first = self.photos.first { self.selection = [first.id] }
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
            let work = Task.detached(priority: .userInitiated) { () -> (EditResult, [URL]) in
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
                return (r, urls)
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
            let versions = result.1.map {
                EditVersion(url: $0, edits: summary, altered: altered, cost: perImage)
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
        for id in ids {
            guard let i = index(id) else { continue }
            let url = photos[i].url
            photos[i].status = .working
            let out = workDir.appendingPathComponent("\(UUID().uuidString).jpg")
            Task {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        let img = try ImageTools.quickEnhance(url, levelHorizon: level)
                        try ImageTools.jpeg(img, quality: 0.93).write(to: out)
                    }.value
                    guard let j = self.index(id) else { return }
                    self.photos[j].results.append(EditVersion(url: out, edits: ["local auto-enhance"], altered: false, cost: 0))
                    self.photos[j].chosen = self.photos[j].results.count - 1
                    self.photos[j].status = .done
                } catch {
                    if let j = self.index(id) { self.photos[j].status = .failed(error.localizedDescription) }
                }
            }
        }
    }

    // MARK: Export

    func export(_ ids: [PhotoItem.ID]) {
        let ready = photos.filter { ids.contains($0.id) && $0.chosenResult != nil }
        guard !ready.isEmpty else { alert = "Nothing to export yet. Edit some photos first."; return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let longEdge = settings.exportLongEdge > 0 ? settings.exportLongEdge : nil
        let addSuffix = settings.addDisclosureToFilename
        let jobs = ready.map { ($0.name, $0.url.lastPathComponent, $0.chosenVersion!) }
        isRunning = true
        Task {
            let failures = await Task.detached(priority: .userInitiated) { () -> [String] in
                var csv = "file,original,edits,digitally_altered,cost_usd\n"
                var failures: [String] = []
                for (n, job) in jobs.enumerated() {
                    let (base, original, v) = job
                    let suffix = (v.altered && addSuffix) ? "-virtually-enhanced" : ""
                    let name = String(format: "%02d-%@%@.jpg", n + 1, base, suffix)
                    do {
                        try ImageTools.export(v.url, to: folder.appendingPathComponent(name), longEdge: longEdge)
                        let edits = v.edits.joined(separator: "; ").replacingOccurrences(of: "\"", with: "'")
                        csv += "\"\(name)\",\"\(original)\",\"\(edits)\",\(v.altered ? "yes" : "no"),\(String(format: "%.4f", v.cost))\n"
                    } catch {
                        failures.append(base)
                    }
                }
                try? csv.write(to: folder.appendingPathComponent("edit-log.csv"), atomically: true, encoding: .utf8)
                return failures
            }.value
            isRunning = false
            NSWorkspace.shared.activateFileViewerSelecting([folder])
            if !failures.isEmpty { alert = "Could not export: \(failures.joined(separator: ", "))" }
        }
    }
}
#endif
