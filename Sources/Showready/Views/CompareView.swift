#if os(macOS)
import SwiftUI
import ShowreadyCore

/// Before/after viewer with a draggable divider, plus a brush to mark objects to remove.
struct CompareView: View {
    @EnvironmentObject var store: AppStore
    @Binding var photo: PhotoItem

    enum Mode: String, CaseIterable, Identifiable {
        case compare = "Before / After", original = "Original", edited = "Edited", mark = "Mark objects"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .compare
    @State private var split: CGFloat = 0.5
    @State private var original: NSImage?
    @State private var edited: NSImage?
    @State private var brush: CGFloat = 0.025
    @State private var currentStroke: [CGPoint] = []
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            controls.padding(10)
            Divider()
            GeometryReader { geo in
                let rect = fittedRect(in: geo.size)
                ZStack(alignment: .topLeading) {
                    Color(nsColor: .underPageBackgroundColor)
                    if let original {
                        Image(nsImage: showEditedOnly ? (edited ?? original) : original)
                            .resizable()
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                    if mode == .compare, let edited {
                        Image(nsImage: edited)
                            .resizable()
                            .frame(width: rect.width, height: rect.height)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: rect.width * split)
                            }
                            .offset(x: rect.minX, y: rect.minY)
                        divider(rect)
                    }
                    if mode == .mark { maskOverlay(rect) }
                    if photo.status == .working {
                        ProgressView("Editing with \(store.model.displayName)…")
                            .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                }
                .contentShape(Rectangle())
                .gesture(mode == .mark ? paintGesture(rect) : nil)
            }
            if photo.chosenVersion?.structureSuspect == true {
                Label("This version looks structurally different from the original. The AI may have redrawn parts of the building — compare carefully and re-run or discard it.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout).padding(8)
                    .frame(maxWidth: .infinity).background(.orange.opacity(0.1))
            }
            if case .failed(let msg) = photo.status {
                Text(msg).foregroundStyle(.red).font(.callout).padding(8)
                    .frame(maxWidth: .infinity).background(.red.opacity(0.08))
            }
        }
        .task(id: photo.url) { original = await load(photo.url) }
        .task(id: photo.chosenResult) {
            edited = nil
            if let r = photo.chosenResult { edited = await load(r) }
            if edited != nil && mode == .original { mode = .compare }
        }
        .onChange(of: photo.chosen) {
            // A different version is on screen now; the old approval no longer applies.
            photo.approved = false
        }
        .onAppear { installKeyMonitor() }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    /// Left/right arrows switch versions and A toggles approval,
    /// unless the user is typing in a text field.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                  !(NSApp.keyWindow?.firstResponder is NSTextView)
            else { return event }
            switch event.keyCode {
            case 123 where photo.results.count > 1: stepVersion(-1); return nil   // left arrow
            case 124 where photo.results.count > 1: stepVersion(1); return nil    // right arrow
            default:
                if event.charactersIgnoringModifiers?.lowercased() == "a", photo.chosenResult != nil {
                    photo.approved.toggle()
                    return nil
                }
                return event
            }
        }
    }

    private func stepVersion(_ delta: Int) {
        photo.chosen = min(max(photo.chosen + delta, 0), photo.results.count - 1)
    }

    private var showEditedOnly: Bool { mode == .edited }

    private var controls: some View {
        HStack {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 440)

            if mode == .mark {
                Slider(value: $brush, in: 0.005...0.08) { Text("Brush") }.frame(width: 160)
                Button("Clear") { photo.maskStrokes.removeAll() }
                    .disabled(photo.maskStrokes.isEmpty)
            }
            Spacer()
            if photo.chosenResult != nil {
                Toggle(isOn: $photo.approved) {
                    Label(photo.approved ? "Approved" : "Approve",
                          systemImage: photo.approved ? "checkmark.seal.fill" : "checkmark.seal")
                }
                .toggleStyle(.button).tint(.green)
                .help("Approve this edit for saving (A)")
            }
            if photo.results.count > 1 {
                Button { stepVersion(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(photo.chosen == 0)
                    .help("Previous version (←)")
                Picker("Version", selection: $photo.chosen) {
                    ForEach(photo.results.indices, id: \.self) { i in
                        Text("v\(i + 1)\(photo.results[i].structureSuspect ? " ⚠" : "")").tag(i)
                    }
                }
                .frame(width: 130)
                Button { stepVersion(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(photo.chosen == photo.results.count - 1)
                    .help("Next version (→)")
            }
            Text("\(photo.size.width)×\(photo.size.height)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func divider(_ rect: CGRect) -> some View {
        let x = rect.minX + rect.width * split
        return ZStack {
            Rectangle().fill(.white).frame(width: 2, height: rect.height).shadow(radius: 2)
            Circle().fill(.white).frame(width: 28, height: 28).shadow(radius: 2)
                .overlay(Image(systemName: "arrow.left.and.right").font(.caption.bold()).foregroundStyle(.black))
        }
        .position(x: x, y: rect.midY)
        .gesture(DragGesture().onChanged { v in
            split = min(max((v.location.x - rect.minX) / rect.width, 0), 1)
        })
        .overlay(alignment: .topLeading) {
            HStack {
                cornerLabel("Edited")
                Spacer()
                cornerLabel("Original")
            }
            .frame(width: rect.width - 20)
            .position(x: rect.midX, y: rect.minY + 20)
        }
    }

    private func cornerLabel(_ s: String) -> some View {
        Text(s).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
    }

    private func maskOverlay(_ rect: CGRect) -> some View {
        Canvas { ctx, _ in
            let all = photo.maskStrokes + (currentStroke.isEmpty ? [] : [MaskStroke(points: currentStroke, radius: brush)])
            for s in all {
                var path = Path()
                let pts = s.points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
                guard let first = pts.first else { continue }
                path.move(to: first)
                if pts.count == 1 { path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y)) }
                for p in pts.dropFirst() { path.addLine(to: p) }
                ctx.stroke(path, with: .color(.red.opacity(0.45)),
                           style: StrokeStyle(lineWidth: s.radius * 2 * rect.width, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
        .overlay(alignment: .bottom) {
            Text("Paint over things to remove, then run the edit. Only painted areas are changed for removal.")
                .font(.caption).padding(6).background(.regularMaterial, in: Capsule()).padding(10)
        }
    }

    private func paintGesture(_ rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let p = CGPoint(x: (v.location.x - rect.minX) / rect.width, y: (v.location.y - rect.minY) / rect.height)
                guard (0...1).contains(p.x), (0...1).contains(p.y) else { return }
                currentStroke.append(p)
            }
            .onEnded { _ in
                if !currentStroke.isEmpty { photo.maskStrokes.append(MaskStroke(points: currentStroke, radius: brush)) }
                currentStroke = []
            }
    }

    private func fittedRect(in container: CGSize) -> CGRect {
        let pad: CGFloat = 16
        let w = container.width - pad * 2, h = container.height - pad * 2
        let aspect = photo.size.aspect
        var fw = w, fh = w / aspect
        if fh > h { fh = h; fw = h * aspect }
        return CGRect(x: (container.width - fw) / 2, y: (container.height - fh) / 2, width: max(fw, 1), height: max(fh, 1))
    }

    private func load(_ url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) { ImageTools.thumbnail(url, maxEdge: 2400) }.value
    }
}
#endif
