#if os(iOS) && DEBUG
import SwiftUI
import UIKit
import Combine

@MainActor final class SmartCubeGuidanceCaptureStore: ObservableObject {
    static let shared = SmartCubeGuidanceCaptureStore()
    @Published private(set) var recording = false
    @Published private(set) var count = 0

    func setRecording(_ value: Bool) {
        recording = value
        SmartCubeDiagnostics.shared.recordGuidance(value)
        refresh()
    }
    func refresh() { count = SmartCubeDiagnostics.shared.guidanceCount }
    func clear() { SmartCubeDiagnostics.shared.clearGuidance(); refresh() }
}

/// Reachable without a connected peripheral, Protocol Debug, or the master debug
/// toggle. Recording belongs to the process, not the lifetime of this screen.
struct SmartCubeGuidanceCaptureView: View {
    @ObservedObject private var store = SmartCubeGuidanceCaptureStore.shared
    @State private var copied = false
    var body: some View {
        Form {
            Section {
                Toggle("Record Guidance", isOn: Binding(get: { store.recording }, set: store.setRecording))
                    .accessibilityIdentifier("guidance-capture-record")
                Text("\(store.count) of 2048 events retained")
                    .accessibilityIdentifier("guidance-capture-count")
                Button("Copy Guidance Diagnostics") {
                    store.refresh()
                    UIPasteboard.general.string = SmartCubeDiagnostics.shared.guidanceExport()
                    copied = true
                }
                .disabled(store.count == 0)
                .accessibilityIdentifier("smart-cube-copy-guidance-diagnostics")
                .accessibilityValue(copied ? "Copied" : "Not copied")
                Button("Clear Guidance Capture", role: .destructive) { store.clear() }
            } footer: {
                Text("Enable recording, return to Timer, make one deviation and pause. Return here to stop and copy. No Mark Solved or Protocol Debug is needed. This optional bug report contains monotonic system-uptime timestamps, state digests and displayed/candidate move paths, not raw facelets or device names. Copy only if you choose to share it. Recording survives tab navigation; force-quitting discards it.")
            }
        }
        .navigationTitle("Guidance Capture")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.refresh() }
    }
}
#endif
