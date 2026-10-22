#if DEBUG
import SwiftUI

struct CompetitionScrollDiagnosticsView: View {
    @AppStorage(CompetitionScrollOwnerDiagnostics.enabledKey) private var recording = false
    @ObservedObject private var store = CompetitionScrollCaptureStore.shared
    @ObservedObject private var debugStore = CompetitionDebugStore.shared
    @State private var shareURL: URL?
    @State private var showingShare = false
    @State private var failure: String?

    var body: some View {
        Form {
            Section {
                Toggle("Record Scroll Owners", isOn: $recording)
                    .accessibilityIdentifier("competition-scroll-recording")
                    .disabled(!debugStore.enabled)
                    .onChange(of: recording) { _ in NotificationCenter.default.post(name: CompetitionDebugStore.changed, object: nil) }
                Text("Captures: \(store.captures.count) of 4 retained")
                    .accessibilityIdentifier("competition-scroll-capture-count")
                Button("Clear Captures") {
                    CompetitionScrollOwnerDiagnostics.clear()
                }.disabled(recording)
                    .accessibilityIdentifier("competition-scroll-clear")
                Button("Share Captured Scrolls") {
                    do {
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CubeFlow-Competition-Scroll.json")
                        try CompetitionScrollOwnerDiagnostics.export(to: url)
                        shareURL = url; showingShare = true
                    } catch { failure = error.localizedDescription }
                }.disabled(recording || store.captures.isEmpty)
                    .accessibilityIdentifier("competition-scroll-share")
            } footer: {
                Text("DEBUG only. Enable, reproduce ordinary competition scrolling, then wait one second after scrolling stops. Return here and disable recording before sharing. The last four captures are kept in memory. Interrupted coverage is identified in the JSON. View identities, competition IDs, frame timings, layout events and device OS are included; no network requests or account data are captured.")
            }
        }
        .navigationTitle("Scroll Diagnostics")
        .sheet(isPresented: $showingShare) {
            if let shareURL { SystemShareSheet(items: [shareURL]) }
        }
        .alert("Capture Export Failed", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }
        } message: { Text(failure ?? "") }
    }
}
#endif
