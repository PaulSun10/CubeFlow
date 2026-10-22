#if DEBUG
import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct CompetitionDebugCaptureView: View {
    let kind: CompetitionDebugStore.Kind
    @ObservedObject private var store = CompetitionDebugStore.shared
    @State private var share: URL?
    var body: some View {
        Form {
            Section {
                Text(recording ? "Recording" : "Stopped").accessibilityIdentifier("debug-capture-status")
                Button(recording ? "Stop Capture" : "Start Capture") {
                    if recording { store.stop(kind) } else { store.start(kind) }
                }.disabled(!store.enabled)
                Text("\(store.count(kind)) of \(CompetitionDebugStore.capacity) saved")
                Button("Clear Captures", role: .destructive) { store.clear(kind) }.disabled(recording)
            } footer: {
                Text(kind == .filter
                    ? "Start, navigate to Competitions, reproduce closing and immediately reopening Filter, then return here and Stop. Touch targets and lifecycle timestamps are recorded locally. No touch is intercepted."
                    : "Start, open the problematic All Results card, and use Capture Visible Table. In review, tap the incorrect lines. Stop ends the session; saved captures remain available. Import an original system screenshot if the snapshot differs.")
            }
            Section("Saved Captures") {
                ForEach(store.captures.filter { $0.kind == kind }) { capture in
                    if kind == .separator {
                        NavigationLink(capture.date.formatted(date: .abbreviated, time: .standard)) {
                            CompetitionSeparatorReview(capture: capture)
                        }
                    } else {
                        Button("Share \(capture.date.formatted(date: .omitted, time: .standard))") {
                            do { share = try store.export(capture) } catch { store.failure = error.localizedDescription }
                        }
                    }
                }
            }
        }
        .navigationTitle(kind == .filter ? "Filter Capture" : "Separator Capture")
        .sheet(isPresented: Binding(get: { share != nil }, set: { if !$0 { share = nil } })) {
            if let share { SystemShareSheet(items: [share]) }
        }
        .alert("Capture", isPresented: Binding(get: { store.failure != nil }, set: { if !$0 { store.failure = nil } })) {
            Button("OK") { store.failure = nil }
        } message: { Text(store.failure ?? "") }
    }
    private var recording: Bool { kind == .filter ? store.filterRecording : store.separatorRecording }
}

struct CompetitionSeparatorReview: View {
    let capture: CompetitionDebugStore.Capture
    @ObservedObject private var store = CompetitionDebugStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var metadata: [String: Any] = [:]
    @State private var lines: [CompetitionSeparatorLine] = []
    @State private var selection = CompetitionSeparatorSelection()
    private var selected: [String] { selection.ids }
    @State private var image: UIImage?
    @State private var importing = false
    @State private var share: URL?
    var body: some View {
        VStack(spacing: 8) {
            if let image {
                GeometryReader { proxy in
                    let fit = Self.fit(image.size, in: proxy.size)
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                        .accessibilityLabel("Captured Result Card").accessibilityIdentifier("separator-review-image")
                        .frame(width: fit.width, height: fit.height)
                        .overlay {
                            Path { path in
                                for line in lines where selected.contains(line.id) {
                                    path.move(to: CGPoint(x: line.x0 * fit.width, y: line.y * fit.height))
                                    path.addLine(to: CGPoint(x: line.x1 * fit.width, y: line.y * fit.height))
                                }
                            }.stroke(.orange, lineWidth: 3).allowsHitTesting(false)
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onEnded { gesture in
                            guard let line = CompetitionSeparatorLine.nearest(to: gesture.location, size: fit, lines: lines) else { return }
                            toggle(line.id)
                        })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(lines) { line in
                        Button(line.label) { toggle(line.id) }
                            .accessibilityIdentifier("separator-line-" + line.id)
                            .font(.caption).foregroundStyle(selected.contains(line.id) ? .orange : .primary)
                            .accessibilityAddTraits(selected.contains(line.id) ? .isSelected : [])
                    }
                }.padding(.horizontal)
            }.frame(height: 38)
            HStack {
                Button("Undo") { selection.undo() }.disabled(!selection.canUndo)
                Button("Clear Selection") { selection.clear() }.disabled(selected.isEmpty)
                Spacer()
                Button("Share") { guard saveSelection() else { return }; do { share = try store.export(capture) } catch { store.failure = error.localizedDescription } }
                    .accessibilityIdentifier("separator-review-share")
            }.padding(.horizontal)
            Button("Import Original iOS Screenshot") { importing = true }
            Text("Use the same stationary viewport and orientation. Imported screenshots are cropped to this card; other screen content is not saved. UIKit snapshots are not final compositor pixels.")
                .font(.caption2).foregroundStyle(.secondary).padding(.horizontal)
        }
        .padding(.vertical, 8)
        .navigationTitle("Mark Separators").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { if saveSelection() { dismiss() } } } }
        .onAppear(perform: load)
        .onDisappear { _ = saveSelection() }
        .onChange(of: store.enabled) { if !$0 { dismiss() } }
        .sheet(isPresented: $importing) { CompetitionDiagnosticScreenshotPicker { data in
            importing = false
            if let data {
                do {
                    let imported = try CompetitionSeparatorScreenshotImport.cropped(data, metadata: metadata)
                    metadata["imageSource"] = "Original iOS screenshot, user-attached, cropped without resampling"
                    metadata["importedAt"] = Date().timeIntervalSince1970
                    metadata["authoritativeImage"] = "system-screenshot.png"
                    try store.update(capture, metadata: metadata, image: imported)
                    image = UIImage(data: imported)
                } catch { store.failure = error.localizedDescription }
            }
        } }
        .sheet(isPresented: Binding(get: { share != nil }, set: { if !$0 { share = nil } })) {
            if let share { SystemShareSheet(items: [share]) }
        }
        .alert("Capture", isPresented: Binding(get: { store.failure != nil }, set: { if !$0 { store.failure = nil } })) {
            Button("OK") { store.failure = nil }
        } message: { Text(store.failure ?? "") }
    }
    static func fit(_ image: CGSize, in area: CGSize) -> CGSize {
        let scale = min(area.width / max(1, image.width), area.height / max(1, image.height))
        return CGSize(width: image.width * scale, height: image.height * scale)
    }
    private func toggle(_ id: String) {
        selection.toggle(id)
    }
    private func load() {
        do {
            metadata = try store.metadata(capture)
            let data = try JSONSerialization.data(withJSONObject: metadata["lines"] ?? [])
            lines = try JSONDecoder().decode([CompetitionSeparatorLine].self, from: data)
            selection.ids = metadata["selectedSeparatorIDs"] as? [String] ?? []
            let path = metadata["authoritativeImage"] as? String ?? "snapshot.png"
            image = UIImage(contentsOfFile: capture.directory.appendingPathComponent(path).path)
        } catch { store.failure = error.localizedDescription }
    }
    private func saveSelection() -> Bool {
        guard !metadata.isEmpty else { return false }
        metadata["selectedSeparatorIDs"] = selected
        metadata["selectedSeparators"] = lines.filter { selected.contains($0.id) }.map { ["id": $0.id, "label": $0.label, "identity": $0.identity] as [String: Any] }
        do { try store.update(capture, metadata: metadata); return true }
        catch { store.failure = error.localizedDescription; return false }
    }
}

enum CompetitionSeparatorScreenshotImport {
    static func cropped(_ data: Data, metadata: [String: Any]) throws -> Data {
        guard data.count < 24 * 1024 * 1024, let image = UIImage(data: data), image.imageOrientation == .up,
              let cg = image.cgImage, cg.width < 12000, cg.height < 12000,
              let size = metadata["screenSize"] as? [Double], size.count == 2,
              let rect = metadata["cropOnScreen"] as? [Double], rect.count == 4,
              abs(Double(cg.width) / Double(cg.height) - size[0] / size[1]) < 0.001 else { throw ImportError.mismatch }
        let scale = Double(cg.width) / size[0]
        let crop = CGRect(x: rect[0] * scale, y: rect[1] * scale, width: rect[2] * scale, height: rect[3] * scale).integral
        guard let cropped = cg.cropping(to: crop), let png = UIImage(cgImage: cropped).pngData() else { throw ImportError.mismatch }
        return png
    }
    enum ImportError: LocalizedError {
        case mismatch
        var errorDescription: String? { "Use an uncropped original screenshot from the same screen orientation and unchanged card viewport. This image cannot be mapped safely." }
    }
}
private struct CompetitionDiagnosticScreenshotPicker: UIViewControllerRepresentable {
    let completion: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(); configuration.filter = .images; configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let controller = PHPickerViewController(configuration: configuration); controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: (Data?) -> Void
        init(completion: @escaping (Data?) -> Void) { self.completion = completion }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else { completion(nil); return }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                DispatchQueue.main.async { self?.completion(data) }
            }
        }
    }
}
#endif
