#if os(iOS)
import SwiftUI
import UIKit

#if DEBUG
@MainActor final class SmartCubeCardEntryProbe {
    var openTimer: (() -> Void)?
    var openSettingsDevice: ((UUID) -> Void)?
}
private struct SmartCubeCardEntryProbeKey: EnvironmentKey {
    static let defaultValue: SmartCubeCardEntryProbe? = nil
}
extension EnvironmentValues {
    var smartCubeCardEntryProbe: SmartCubeCardEntryProbe? {
        get { self[SmartCubeCardEntryProbeKey.self] }
        set { self[SmartCubeCardEntryProbeKey.self] = newValue }
    }
}
#endif

struct SmartCubeDiscoveryNavigationHost<Content: View>: UIViewControllerRepresentable {
    let title: String
    @ViewBuilder let content: () -> Content

    func makeUIViewController(context: Context) -> UINavigationController {
        // A nested SwiftUI NavigationStack adopts the result presenter's hidden
        // navigation owner. Give only discovery its own card-sized native owner.
        let host = UIHostingController(rootView: root(context))
        host.view.backgroundColor = .clear
        host.title = title
        host.navigationItem.largeTitleDisplayMode = .always
        let navigation = UINavigationController(rootViewController: host)
        navigation.view.backgroundColor = .clear
        navigation.navigationBar.prefersLargeTitles = true
        applyInsets(navigation.navigationBar)
        return navigation
    }

    func updateUIViewController(_ navigation: UINavigationController, context: Context) {
        guard let host = navigation.viewControllers.first as? UIHostingController<AnyView> else { return }
        host.rootView = root(context)
        host.title = title
        applyInsets(navigation.navigationBar)
    }

    private func root(_ context: Context) -> AnyView {
        AnyView(content().environment(\.self, context.environment))
    }
    private func applyInsets(_ bar: UINavigationBar) {
        var margins = bar.directionalLayoutMargins
        let inset = CompetitionResultCardTitleStyle.contentInset
        margins.leading = max(margins.leading, inset)
        margins.trailing = max(margins.trailing, inset)
        bar.directionalLayoutMargins = margins
    }
}

struct SmartCubeManagementCard: View {
    @ObservedObject var manager: SmartCubeBluetoothManager
    @ObservedObject var saved: SavedSmartCubeDevices
    @State private var selectedID: UUID?
    @State private var pendingForgetID: UUID?
    @AppStorage("appLanguage") private var appLanguage = "en"
    let dismiss: () -> Void
    #if DEBUG
    @Environment(\.smartCubeManagementSelection) private var observeSelection
    #endif

    init(manager: SmartCubeBluetoothManager = .shared, saved: SavedSmartCubeDevices = .shared,
         selectedID: UUID?, dismiss: @escaping () -> Void) {
        self.manager = manager; self.saved = saved
        _selectedID = State(initialValue: selectedID)
        self.dismiss = dismiss
    }

    private var deviceIDs: [UUID] {
        manager.managementConnectedDeviceIDs
    }
    private var preferredID: UUID? {
        manager.activeDeviceID.flatMap { deviceIDs.contains($0) ? $0 : nil } ?? deviceIDs.first
    }
    private var displayedID: UUID? {
        selectedID.flatMap { id in
            guard deviceIDs.contains(id), let session = manager.session(for: id),
                  let attempt = session.connectionAttemptID,
                  session.connectionPolicyResolvedAttemptID == attempt else { return nil }
            return id
        }
    }
    private func name(_ id: UUID) -> String {
        saved.device(id)?.displayName ?? manager.session(for: id)?.connectedDeviceName
            ?? appLocalizedString("smart_cube.title", languageCode: appLanguage)
    }

    var body: some View {
        GeometryReader { proxy in
            let maximumHeight = CompetitionResultCardGeometry.maximumHeight(in: proxy.size)
            ZStack {
                CompetitionResultBackdrop().ignoresSafeArea().contentShape(Rectangle()).onTapGesture(perform: dismiss)
                SmartCubeManagementFittedContent(maximumHeight: maximumHeight) { content(discoveryHeight: maximumHeight) }
                    .frame(width: CompetitionResultCardGeometry.width(in: proxy.size))
                    .competitionResultCardSurface()
                    .overlay(alignment: .topTrailing) {
                        CompetitionResultCardCloseButton(label: appLocalizedString(
                            "competitions.detail.live.wca.close", languageCode: appLanguage, defaultValue: "Close"), action: dismiss)
                            .padding(12)
                    }
                    .competitionResultCardShadow()
                    .competitionResultCardMotion()
            }
        }
        .onAppear { if selectedID == nil { selectedID = preferredID } }
        .onChange(of: deviceIDs) { connected in
            if selectedID == nil { selectedID = preferredID }
            if let pendingForgetID, !connected.contains(pendingForgetID) { self.pendingForgetID = nil }
        }
        #if DEBUG
        .onAppear { observeSelection?(displayedID, deviceIDs) }
        .onChange(of: displayedID) { observeSelection?($0, deviceIDs) }
        #endif
        .confirmationDialog(Text("smart_cube.manage.forget_title"), isPresented: Binding(
            get: { pendingForgetID != nil }, set: { if !$0 { pendingForgetID = nil } })) {
                if let id = pendingForgetID {
                    Button("smart_cube.manage.forget", role: .destructive) {
                        manager.forgetDevice(id)
                        pendingForgetID = nil
                    }
                }
                Button("common.cancel", role: .cancel) { pendingForgetID = nil }
            } message: { Text("smart_cube.manage.forget_message") }
        .environment(\.locale, appLocale(for: appLanguage))
    }

    private func content(discoveryHeight: CGFloat) -> some View {
        Group {
            if let id = displayedID {
                if let session = manager.session(for: id) {
                    SmartCubeManagementDeviceContent(deviceID: id, session: session,
                        name: AnyView(deviceName(id)),
                        reset: { attempt in manager.resetCubeStateToSolved(deviceID: id, attemptID: attempt) },
                        disconnect: { manager.disconnect(deviceID: id) }, forget: { pendingForgetID = id })
                        .id(id)
                } else {
                    SmartCubeManagementBody(name: AnyView(deviceName(id)), battery: nil, liveCube: nil,
                        canReset: false, canDisconnect: false, reset: {}, disconnect: {}, forget: { pendingForgetID = id })
                }
            } else {
                SmartCubeDevicePickerView(manager: manager, savedDevices: saved,
                    onConnectionStarted: { attempt in selectedID = manager.session(attemptID: attempt)?.connectionDeviceID },
                    onConnectionApproved: { attempt in selectedID = manager.session(attemptID: attempt)?.connectionDeviceID },
                    manage: { selectedID = $0 })
                    .frame(height: discoveryHeight)
                    .accessibilityIdentifier("smart-cube-management-discovery")
            }
        }
    }

    @ViewBuilder private func deviceName(_ id: UUID) -> some View {
        if deviceIDs.count > 1 {
            Menu {
                ForEach(deviceIDs, id: \.self) { value in
                    Button { selectedID = value } label: {
                        if value == id { Label(name(value), systemImage: "checkmark") }
                        else { Text(name(value)) }
                    }
                }
            } label: {
                HStack(spacing: 6) { Text(name(id)); Image(systemName: "chevron.down").font(.caption.weight(.semibold)) }
            }.buttonStyle(.plain).accessibilityIdentifier("smart-cube-management-device")
        } else { Text(name(id)) }
    }
}

struct SmartCubeManagementFittedContent<Content: View>: View {
    let maximumHeight: CGFloat
    @ViewBuilder let content: () -> Content
    var body: some View {
        // ViewThatFits retains its rejected natural-height candidate on overflow,
        // including that candidate's live SceneKit renderer and BLE subscription.
        // Use the existing single-content fit on every supported OS instead.
        SmartCubeManagementLegacyFit(maximumHeight: maximumHeight, content: content)
            .frame(maxHeight: maximumHeight).fixedSize(horizontal: false, vertical: true)
    }
}

private struct SmartCubeManagementHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Match Results' single-content measured-overflow convention on iOS 15+:
/// normal content keeps its natural height; only actual overflow scrolls.
struct SmartCubeManagementLegacyFit<Content: View>: View {
    let maximumHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var naturalHeight: CGFloat = 0
    var body: some View {
        Group {
            if naturalHeight > maximumHeight { ScrollView { measured }.frame(height: maximumHeight) }
            else { measured }
        }.onPreferenceChange(SmartCubeManagementHeight.self) { naturalHeight = $0 }
    }
    private var measured: some View {
        content().fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in Color.clear.preference(key: SmartCubeManagementHeight.self, value: proxy.size.height) })
    }
}

private struct SmartCubeManagementDeviceContent: View {
    let deviceID: UUID
    @ObservedObject var session: SmartCubePeripheralSession
    let name: AnyView
    let reset: (UUID) -> Void
    let disconnect: () -> Void
    let forget: () -> Void
    @AppStorage("smartCubeFixedView") private var fixedViewRaw = SmartCubeFixedView.urf.rawValue

    private var visualFacelets: String? {
        session.connectedProtocol == .moyu && session.puzzleSize == 2 ? session.weiPo2VisualFacelets : session.facelets
    }
    private var canReset: Bool {
        guard session.isConnected, session.connectionDeviceID == deviceID, session.connectionAttemptID != nil else { return false }
        return session.connectedProtocol != .moyu || session.puzzleSize != 2
            || (session.hasTrustedCanonicalState && session.weiPo2LastNativeSnapshot != nil
                && session.weiPo2PendingSnapshotCount == 0 && session.weiPo2VisualFacelets != nil)
    }
    var body: some View {
        SmartCubeManagementBody(name: name, battery: session.isConnected ? session.batteryLevel : nil,
            liveCube: session.isConnected ? AnyView(Group {
                if let visualFacelets {
                    SmartCube3DView(facelets: visualFacelets,
                        stateRevision: session.connectedProtocol == .moyu && session.puzzleSize == 2
                            ? session.weiPo2VisualRevision : session.cubeStateRevision,
                        fixedView: SmartCubeFixedView(rawValue: fixedViewRaw) ?? .urf, cubeSize: session.puzzleSize,
                        events: session.canonicalEvents, connectionAttemptID: session.connectionAttemptID,
                        isStateTrusted: session.hasTrustedCanonicalState, diagnosticOwner: "management",
                        canonicalSequence: session.canonicalSequence)
                } else { ProgressView() }
            }) : nil, canReset: canReset, canDisconnect: session.isConnected,
            reset: { if let attempt = session.connectionAttemptID { reset(attempt) } },
            disconnect: disconnect, forget: forget)
    }
}

struct SmartCubeManagementBody: View {
    #if DEBUG
    @Environment(\.smartCubeManagementTitleMetrics) private var titleMetrics
    #endif
    @AppStorage("appLanguage") private var languageCode = "en"
    let name: AnyView
    let battery: Int?
    let liveCube: AnyView?
    let canReset: Bool
    let canDisconnect: Bool
    let reset: () -> Void
    let disconnect: () -> Void
    let forget: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                name.lineLimit(1).truncationMode(.tail).layoutPriority(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        #if DEBUG
                        if titleMetrics != nil {
                            GeometryReader { p in Color.clear.preference(key: SmartCubeTitleSizes.self, value: ["name": p.size]) }
                        }
                        #endif
                    }
                if let battery {
                    DeviceBatteryIndicator(percentage: battery, isProminent: true,
                        font: .system(size: 23, weight: .medium).monospacedDigit())
                        .background {
                            #if DEBUG
                            if titleMetrics != nil {
                                GeometryReader { p in Color.clear.preference(key: SmartCubeTitleSizes.self, value: ["battery": p.size]) }
                            }
                            #endif
                        }
                }
            }.modifier(CompetitionResultCardTitleStyle())
            Group {
                if let liveCube { liveCube }
                else {
                    Image(systemName: "cube").font(.system(size: 80, weight: .ultraLight))
                        .foregroundStyle(.secondary).accessibilityLabel(Text("smart_cube.manage.disconnected"))
                }
            }.frame(height: 190).frame(maxWidth: .infinity)
            SmartCubeNativeAction(title: appLocalizedString("smart_cube.manage.reset", languageCode: languageCode),
                tint: .systemBlue, enabled: canReset, identifier: "smart-cube-management-reset", perform: reset,
                isLarge: true)
            HStack(spacing: 12) {
                SmartCubeNativeAction(title: appLocalizedString("smart_cube.manage.disconnect", languageCode: languageCode),
                    tint: nil, enabled: canDisconnect, identifier: "smart-cube-management-disconnect", perform: disconnect)
                SmartCubeNativeAction(title: appLocalizedString("smart_cube.manage.forget", languageCode: languageCode),
                    tint: .systemRed, enabled: true, identifier: "smart-cube-management-forget", perform: forget)
            }
        }.padding(CompetitionResultCardTitleStyle.contentInset)
        #if DEBUG
        .onPreferenceChange(SmartCubeTitleSizes.self) { titleMetrics?($0) }
        #endif
    }
}

#if DEBUG
private struct SmartCubeTitleSizes: PreferenceKey {
    static let defaultValue: [String: CGSize] = [:]
    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
private struct SmartCubeTitleMetricsKey: EnvironmentKey {
    static let defaultValue: (([String: CGSize]) -> Void)? = nil
}
private struct SmartCubeManagementSelectionKey: EnvironmentKey {
    static let defaultValue: ((UUID?, [UUID]) -> Void)? = nil
}
extension EnvironmentValues {
    var smartCubeManagementTitleMetrics: (([String: CGSize]) -> Void)? {
        get { self[SmartCubeTitleMetricsKey.self] }
        set { self[SmartCubeTitleMetricsKey.self] = newValue }
    }
    var smartCubeManagementSelection: ((UUID?, [UUID]) -> Void)? {
        get { self[SmartCubeManagementSelectionKey.self] }
        set { self[SmartCubeManagementSelectionKey.self] = newValue }
    }
}
#endif
#endif
