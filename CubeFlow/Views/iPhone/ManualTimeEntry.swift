#if os(iOS)
import SwiftUI
import UIKit

#if DEBUG
@MainActor final class ManualTimeEntryProbe {
    var frames: [String: CGRect] = [:]
    var measuredHeight: CGFloat = 0
    var edit: ((String) -> Void)?
    var save: (() -> Void)?
    var snapshot: (() -> (raw: String, value: Double?, override: Int?))?
}
struct ManualEntryFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
private struct ManualTimeEntryProbeKey: EnvironmentKey { static let defaultValue: ManualTimeEntryProbe? = nil }
extension EnvironmentValues {
    var manualTimeEntryProbe: ManualTimeEntryProbe? {
        get { self[ManualTimeEntryProbeKey.self] }
        set { self[ManualTimeEntryProbeKey.self] = newValue }
    }
}
#endif

struct ManualTimeEntry: View {
    @Binding var draft: ManualTimeDraft
    let interface: ManualInputInterface
    let selected: ManualTimeCandidate?
    let canSave: Bool
    let compact: Bool
    let save: () -> Void
    let focus: FocusState<Bool>.Binding
    var keypadMetrics = ManualKeypadMetrics(width: 300, availableHeight: 360)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var displaySize: CGFloat = 44

    private var input: Binding<String> { Binding(get: { draft.raw }, set: { draft.edit($0) }) }

    var body: some View {
        Group {
            if interface == .keypad {
                VStack(spacing: ManualKeypadMetrics.spacing) {
                    timeDisplay.frame(height: keypadMetrics.displayHeight)
                    keys
                }
                .frame(maxWidth: keypadMetrics.width)
            } else {
                VStack(spacing: compact ? 6 : 10) {
                    TextField("timer.typing_placeholder", text: input)
                        .font(.system(size: 40, weight: .semibold)).monospacedDigit()
                        .multilineTextAlignment(.center).keyboardType(.numbersAndPunctuation)
                        .focused(focus).submitLabel(.done)
                        .onSubmit { if canSave { save() } }
                        .padding(.horizontal, 20).padding(.vertical, 18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityIdentifier("manual-time-input")
                    if !draft.raw.isEmpty {
                        if let selected {
                            Text(selected.display).font(.headline.monospacedDigit())
                                .accessibilityLabel(Text("manual.preview"))
                        } else { Text("manual.invalid").font(.footnote).foregroundStyle(.secondary) }
                    }
                    Button(action: save) { Text("timer.typing_save").frame(maxWidth: .infinity, minHeight: 44) }
                        .compatibleProminentButtonFromIOS16(tint: .blue).disabled(!canSave)
                        .accessibilityIdentifier("manual-time-save")
                }
            }
        }
        .frame(maxWidth: 420)
        .onChange(of: interface) { _ in focus.wrappedValue = false }
        .onDisappear { focus.wrappedValue = false }
    }

    private var timeDisplay: some View {
        Group {
            if draft.raw.isEmpty { Text("manual.enter_time").foregroundStyle(.secondary) }
            else if let selected { Text(selected.display) }
            else { Text("manual.invalid").foregroundStyle(.secondary) }
        }
        .font(.system(size: displaySize, weight: .medium, design: .rounded).monospacedDigit())
        .lineLimit(1).minimumScaleFactor(0.4).frame(maxWidth: .infinity)
        .accessibilityLabel(Text(draft.raw.isEmpty ? "manual.enter_time" : "manual.preview"))
        .accessibilityValue(selected?.display ?? "")
        .accessibilityIdentifier("manual-time-display")
        #if DEBUG
        .background { GeometryReader { proxy in Color.clear.preference(key: ManualEntryFrameKey.self,
            value: ["display": proxy.frame(in: .global)]) } }
        #endif
    }

    private var keys: some View {
        let values = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "delete", "0", "save"]
        return VStack(spacing: ManualKeypadMetrics.spacing) {
            ForEach(0..<4) { row in
                HStack(spacing: ManualKeypadMetrics.spacing) {
                    ForEach(Array(values[(row * 3)..<(row * 3 + 3)]), id: \.self) { key in
                        Group {
                            if key == "save" {
                                // Same native prominent configuration and exact tint as Data > Sessions > Edit.
                                ManualSaveKey(title: String(localized: "timer.typing_save"), enabled: canSave) {
                                    ManualKeyFeedback.play(); save()
                                }
                                    .frame(height: 44)
                                    #if DEBUG
                                    .background { GeometryReader { proxy in Color.clear.preference(key: ManualEntryFrameKey.self,
                                        value: ["save": proxy.frame(in: .global)]) } }
                                    #endif
                            } else if key == "delete" {
                                ManualDeleteKey {
                                    guard !draft.raw.isEmpty else { return }
                                    draft.edit(String(draft.raw.dropLast())); ManualKeyFeedback.play()
                                }
                                .frame(maxWidth: .infinity).frame(height: keypadMetrics.diameter)
                                .compatibleGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            } else {
                                Button {
                                    guard draft.raw.count < 18 else { return }
                                    draft.edit(draft.raw + key); ManualKeyFeedback.play()
                                } label: {
                                    Text(key).font(.title2.weight(.medium)).monospacedDigit()
                                        .frame(minWidth: 0, maxWidth: .infinity).frame(height: keypadMetrics.diameter)
                                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(ManualKeyStyle(reduceMotion: reduceMotion))
                                .accessibilityLabel(Text(key)).accessibilityIdentifier("manual-key-\(key)")
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: keypadMetrics.diameter)
                    }
                }
            }
        }
    }
}

/// Shared by the header and keypad owners, before either is rendered. No
/// scrolling-content measurement feeds back into this allocation.
struct ManualKeypadMetrics {
    static let spacing: CGFloat = 8
    let width: CGFloat
    let diameter: CGFloat
    let displayHeight: CGFloat
    var height: CGFloat { displayHeight + 4 * diameter + 4 * Self.spacing }

    init(width: CGFloat, availableHeight: CGFloat, displayHeight: CGFloat = 64) {
        self.width = min(300, max(0, width))
        self.displayHeight = displayHeight
        diameter = max(44, min(64, (self.width - 2 * Self.spacing) / 3,
            (availableHeight - displayHeight - 4 * Self.spacing) / 4))
    }
}

private enum ManualKeyFeedback {
    static let generator = UISelectionFeedbackGenerator()
    static func play() { generator.selectionChanged(); generator.prepare() }
}

private struct ManualKeyStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.primary)
            .compatibleGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ManualSaveKey: UIViewRepresentable {
    let title: String
    let enabled: Bool
    let save: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.addAction(UIAction { [weak owner = context.coordinator] _ in owner?.save?() }, for: .touchUpInside)
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.save = save
        var configuration = SessionNativeActionStyle.configuration(tint: .systemBlue)
        configuration.title = title
        configuration.cornerStyle = .capsule
        configuration.buttonSize = .small
        configuration.titleLineBreakMode = .byClipping
        // Like a compact toolbar action, keep its native title on one line even
        // at accessibility sizes; the time display and digits still scale.
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFontMetrics(forTextStyle: .body).scaledFont(
                for: .systemFont(ofSize: 17, weight: .semibold), maximumPointSize: 22)
            return attributes
        }
        button.configuration = configuration; button.tintColor = .systemBlue; button.isEnabled = enabled
        button.titleLabel?.numberOfLines = 1
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.5
        button.accessibilityIdentifier = "manual-time-save"
    }
    final class Coordinator { var save: (() -> Void)? }
}

/// UIKit owns repeat/cancellation so a released or removed key never keeps
/// deleting. No polling or extra gesture recognizer competes with the Timer.
struct ManualDeleteKey: UIViewRepresentable {
    let delete: () -> Void
    func makeUIView(context: Context) -> DeleteButton { DeleteButton() }
    func updateUIView(_ view: DeleteButton, context: Context) {
        view.delete = delete
        view.accessibilityLabel = String(localized: "manual.delete")
    }
    static func dismantleUIView(_ view: DeleteButton, coordinator: ()) { view.stop() }

    final class DeleteButton: UIButton {
        var delete: (() -> Void)?
        private var repeatTask: Task<Void, Never>?
        init() {
            super.init(frame: .zero)
            setImage(UIImage(systemName: "delete.left"), for: .normal)
            addTarget(self, action: #selector(begin), for: .touchDown)
            addTarget(self, action: #selector(stop), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
            accessibilityTraits = .button
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.55 : 1 } }
        override func accessibilityActivate() -> Bool { delete?(); return true }
        @objc func begin() {
            stop(); delete?()
            repeatTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 350_000_000)
                    while !Task.isCancelled {
                        guard self?.window != nil else { return }
                        self?.delete?()
                        try await Task.sleep(nanoseconds: 75_000_000)
                    }
                } catch { }
            }
        }
        @objc func stop() { repeatTask?.cancel(); repeatTask = nil }
        override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { stop() } }
    }
}
#endif
