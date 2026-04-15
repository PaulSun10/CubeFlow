import SwiftUI
import PhotosUI
import SwiftData
import UniformTypeIdentifiers

#if os(iOS)
struct SettingsTabView: View {
    enum AppearanceSelectionTarget: String, Identifiable {
        case timerFontDesign
        case scrambleFontDesign
        case averageFontDesign
        case timerFontWeight
        case scrambleFontWeight
        case averageFontWeight

        var id: String { rawValue }
    }

    enum TextAppearancePreviewKind {
        case timer
        case scramble
        case average
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var currentColorScheme
    @ObservedObject private var ganTimer = GANTimerBluetoothManager.shared
    @Query(sort: [SortDescriptor(\Session.createdAt, order: .forward)])
    private var sessions: [Session]

    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("timerBackgroundAppearanceData") private var timerBackgroundAppearanceData: Data?
    @AppStorage("competitionsBackgroundAppearanceData") private var competitionsBackgroundAppearanceData: Data?
    @AppStorage("timerTextAppearanceData") private var timerTextAppearanceData: Data?
    @AppStorage("scrambleTextAppearanceData") private var scrambleTextAppearanceData: Data?
    @AppStorage("averageTextAppearanceData") private var averageTextAppearanceData: Data?
    @AppStorage("wcaInspectionEnabled") private var wcaInspectionEnabled: Bool = false
    @AppStorage("ganInspectionStartsOnPress") private var ganInspectionStartsOnPress: Bool = false
    @AppStorage("ganShowResultPopup") private var ganShowResultPopup: Bool = true
    @AppStorage("ganResultInputMode") private var ganResultInputMode: String = GANResultInputMode.manual.rawValue
    @AppStorage("inspectionAlertVoiceMode") private var inspectionAlertVoiceMode: String = InspectionAlertVoiceMode.off.rawValue
    @AppStorage("averageDisplayOption") private var averageDisplayOption: String = AverageDisplayOption.ao5AndAo12.rawValue
    @AppStorage("timerUpdatingMode") private var timerUpdatingMode: String = TimerUpdatingMode.on.rawValue
    @AppStorage("timerAccuracy") private var timerAccuracy: String = TimerAccuracy.thousandths.rawValue
    @AppStorage("enteringTimesWith") private var enteringTimesWith: String = TimeEntryMode.timer.rawValue
    @AppStorage("hideElementsWhenSolving") private var hideElementsWhenSolving: Bool = false
    @AppStorage("timerBackgroundImageData") private var timerBackgroundImageData: Data?
    @AppStorage("competitionsBackgroundImageData") private var competitionsBackgroundImageData: Data?
    @AppStorage("drawScramblePlacement") private var drawScramblePlacement: String = DrawScramblePlacement.inline.rawValue
    @AppStorage("drawScrambleFloatingSize") private var drawScrambleFloatingSize: Double = 132
    @AppStorage("timerTextFontSize") private var timerTextFontSize: Double = 64
    @AppStorage("scrambleTextFontSize") private var scrambleTextFontSize: Double = 20
    @AppStorage("averageTextFontSize") private var averageTextFontSize: Double = 20
    @AppStorage("timerTextFontDesign") private var timerTextFontDesign: String = TimerFontDesignOption.default.rawValue
    @AppStorage("scrambleTextFontDesign") private var scrambleTextFontDesign: String = TimerFontDesignOption.default.rawValue
    @AppStorage("averageTextFontDesign") private var averageTextFontDesign: String = TimerFontDesignOption.default.rawValue
    @AppStorage("timerTextFontWeight") private var timerTextFontWeight: String = TimerFontWeightOption.semibold.rawValue
    @AppStorage("scrambleTextFontWeight") private var scrambleTextFontWeight: String = TimerFontWeightOption.medium.rawValue
    @AppStorage("averageTextFontWeight") private var averageTextFontWeight: String = TimerFontWeightOption.medium.rawValue
    @AppStorage("selectedAppIcon") private var selectedAppIcon: String = AppIconOption.red.rawValue
    @AppStorage("competitionCardStyle") private var competitionCardStyle: String = CompetitionCardStyleOption.list.rawValue

    @State private var timerBackgroundPhotoItem: PhotosPickerItem?
    @State private var competitionsBackgroundPhotoItem: PhotosPickerItem?
    @State private var timerBackgroundAppearance = AppearanceConfiguration.defaultBackground
    @State private var competitionsBackgroundAppearance = AppearanceConfiguration.defaultBackground
    @State private var timerTextAppearance = AppearanceConfiguration.defaultTimerText
    @State private var scrambleTextAppearance = AppearanceConfiguration.defaultScrambleText
    @State private var averageTextAppearance = AppearanceConfiguration.defaultAverageText
    @State private var showingImportPicker = false
    @State private var showingExportFormatDialog = false
    @State private var showingExportPicker = false
    @State private var exportDocument = DataTransferDocument(data: Data())
    @State private var exportContentType: UTType = .json
    @State private var exportDefaultFilename = "CubeFlowBackup"
    @State private var importExportAlertMessage: String?
    @State private var showingImportInfoAlert = false
    @State private var isImportingData = false
    @State private var importProgressCurrent = 0
    @State private var importProgressTotal = 1
    @State private var importProgressLabel = ""
    @State private var pendingPreparedImport: DataTransferPreparedImport?
    @State private var showingImportConflictDialog = false
    @State private var wcaAlertMessage: String?
    @State private var appIconAlertMessage: String?
    @State private var wcaDestination: WCASettingsDestination?
    @State private var appearanceSelectionTarget: AppearanceSelectionTarget?
    @State private var showingGANDevicePicker = false
    @StateObject private var wcaAuth = WCAAuthManager.shared

    private func languageDisplayKey(for languageCode: String) -> String {
        switch languageCode {
        case "zh-Hans":
            return "settings.language_zh"
        case "en":
            return "settings.language_en"
        default:
            return "settings.language_unknown"
        }
    }

    private var currentLanguageKey: LocalizedStringKey {
        LocalizedStringKey(languageDisplayKey(for: appLanguage))
    }

    private var settingsCardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(.systemBackground))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.section.wca")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            if wcaAuth.isSignedIn {
                                wcaStatusCard
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 18)
                            } else {
                                HStack(alignment: .center, spacing: 12) {
                                    Image("wca_logo")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36, height: 36)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("settings.wca_about_title")
                                            .font(.system(size: 15, weight: .medium))

                                        Text("settings.wca_about_message")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                            }

                            Divider()

                            VStack(spacing: 10) {
                                Button {
                                    authenticateWithWCA()
                                } label: {
                                    HStack {
                                        Spacer()
                                        if wcaAuth.isSigningIn {
                                            ProgressView()
                                                .tint(.white)
                                        } else {
                                            Text(LocalizedStringKey(wcaAuth.isSignedIn ? "settings.wca_refresh_profile" : "settings.wca_sign_in"))
                                                .font(.system(size: 16, weight: .semibold))
                                        }
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .contentShape(Rectangle())
                                    .glassEffect(.regular.interactive(), in: .capsule)
                                }
                                .buttonStyle(.plain)
                                .disabled(wcaAuth.isSigningIn)

                                if wcaAuth.isSignedIn {
                                    Button("settings.wca_sign_out", role: .destructive) {
                                        wcaAuth.signOut()
                                    }
                                    .font(.system(size: 15, weight: .semibold))
                                    .padding(.vertical, 6)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                        }
                        .background(settingsCardBackground)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.section.general")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            HStack {
                                Text("settings.language_label")
                                    .font(.system(size: 16, weight: .medium))

                                Spacer()

                                Menu {
                                    Button(LocalizedStringKey(languageDisplayKey(for: "en"))) {
                                        appLanguage = "en"
                                    }
                                    Button(LocalizedStringKey(languageDisplayKey(for: "zh-Hans"))) {
                                        appLanguage = "zh-Hans"
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(currentLanguageKey)
                                            .font(.system(size: 15, weight: .medium))
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .glassEffect(.regular.interactive(), in: .capsule)
                                }
                                .tint(.primary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

                            Divider()

                            importDataRow

                            Divider()

                            exportDataRow
                        }
                        .background(settingsCardBackground)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.section.appearance")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 12) {
                            appearanceOverviewCard

                            appearanceEditorCard(
                                titleKey: "settings.timer_bg_label",
                                configuration: $timerBackgroundAppearance,
                                photoData: $timerBackgroundImageData,
                                photoItem: $timerBackgroundPhotoItem,
                                allowsPhoto: true
                            )

                            if CompetitionCardStyleOption(rawValue: competitionCardStyle) == .glass {
                                appearanceEditorCard(
                                    titleKey: "settings.competitions_bg_label",
                                    configuration: $competitionsBackgroundAppearance,
                                    photoData: $competitionsBackgroundImageData,
                                    photoItem: $competitionsBackgroundPhotoItem,
                                    allowsPhoto: true
                                )
                                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                            }

                            appearanceEditorCard(
                                titleKey: "settings.timer_text_label",
                                configuration: $timerTextAppearance,
                                fontSize: $timerTextFontSize,
                                fontSizeTitleKey: "settings.timer_text_size",
                                defaultFontSize: 64,
                                fontDesign: $timerTextFontDesign,
                                fontDesignTarget: .timerFontDesign,
                                defaultFontDesign: TimerFontDesignOption.default.rawValue,
                                fontWeight: $timerTextFontWeight,
                                fontWeightTarget: .timerFontWeight,
                                defaultFontWeight: TimerFontWeightOption.semibold.rawValue,
                                previewKind: .timer
                            )

                            appearanceEditorCard(
                                titleKey: "settings.scramble_text_label",
                                configuration: $scrambleTextAppearance,
                                fontSize: $scrambleTextFontSize,
                                fontSizeTitleKey: "settings.scramble_text_size",
                                defaultFontSize: 20,
                                fontDesign: $scrambleTextFontDesign,
                                fontDesignTarget: .scrambleFontDesign,
                                defaultFontDesign: TimerFontDesignOption.default.rawValue,
                                fontWeight: $scrambleTextFontWeight,
                                fontWeightTarget: .scrambleFontWeight,
                                defaultFontWeight: TimerFontWeightOption.medium.rawValue,
                                previewKind: .scramble
                            )

                            appearanceEditorCard(
                                titleKey: "settings.average_text_label",
                                configuration: $averageTextAppearance,
                                fontSize: $averageTextFontSize,
                                fontSizeTitleKey: "settings.average_text_size",
                                defaultFontSize: 20,
                                fontDesign: $averageTextFontDesign,
                                fontDesignTarget: .averageFontDesign,
                                defaultFontDesign: TimerFontDesignOption.default.rawValue,
                                fontWeight: $averageTextFontWeight,
                                fontWeightTarget: .averageFontWeight,
                                defaultFontWeight: TimerFontWeightOption.medium.rawValue,
                                previewKind: .average
                            )
                        }
                        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: competitionCardStyle)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.section.timer")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            Toggle(isOn: $wcaInspectionEnabled) {
                                Text("settings.wca_inspection")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

                            Divider()

                            settingsMenuRow(
                                titleKey: "settings.inspection_alert",
                                selectedKey: InspectionAlertVoiceMode(rawValue: inspectionAlertVoiceMode)?.localizedKey ?? "settings.inspection_alert_off"
                            ) {
                                ForEach(InspectionAlertVoiceMode.allCases) { mode in
                                    Button(mode.localizedKey) {
                                        inspectionAlertVoiceMode = mode.rawValue
                                    }
                                }
                            }

                            Divider()

                            settingsMenuRow(
                                titleKey: "settings.timer_updating",
                                selectedKey: TimerUpdatingMode(rawValue: timerUpdatingMode)?.localizedKey ?? "settings.timer_updating_on"
                            ) {
                                ForEach(TimerUpdatingMode.allCases) { mode in
                                    Button(mode.localizedKey) {
                                        timerUpdatingMode = mode.rawValue
                                    }
                                }
                            }

                            Divider()

                            settingsMenuRow(
                                titleKey: "settings.timer_accuracy",
                                selectedKey: TimerAccuracy(rawValue: timerAccuracy)?.localizedKey ?? "settings.timer_accuracy_001"
                            ) {
                                ForEach(TimerAccuracy.allCases) { accuracy in
                                    Button(accuracy.localizedKey) {
                                        timerAccuracy = accuracy.rawValue
                                    }
                                }
                            }

                            Divider()

                            settingsMenuRow(
                                titleKey: "settings.entering_times_with",
                                selectedKey: TimeEntryMode(rawValue: enteringTimesWith)?.localizedKey ?? "settings.entering_times_timer"
                            ) {
                                ForEach(TimeEntryMode.allCases) { mode in
                                    Button(mode.localizedKey) {
                                        enteringTimesWith = mode.rawValue
                                        if mode == .gan {
                                            ganTimer.prepareIfNeeded()
                                        }
                                    }
                                }
                            }

                            Divider()

                            Toggle(isOn: $ganShowResultPopup) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("settings.result_popup")
                                        .font(.system(size: 16, weight: .medium))

                                    Text("settings.result_popup_help")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

                            Divider()

                            if enteringTimesWith == TimeEntryMode.gan.rawValue {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("settings.gan_timer")
                                            .font(.system(size: 16, weight: .medium))

                                        Text(LocalizedStringKey(ganTimer.statusLocalizedKey))
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Button {
                                        switch ganTimer.connectionState {
                                        case .scanning, .connecting, .connected, .handsOn, .ready, .running, .finished:
                                            ganTimer.performPrimaryAction()
                                        default:
                                            ganTimer.startDeviceDiscovery()
                                            showingGANDevicePicker = true
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            if case .scanning = ganTimer.connectionState {
                                                ProgressView()
                                                    .controlSize(.small)
                                            }
                                            Text(LocalizedStringKey(ganTimer.actionLocalizedKey))
                                                .font(.system(size: 15, weight: .medium))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .glassEffect(.regular.interactive(), in: .capsule)
                                    }
                                    .buttonStyle(.plain)
                                    .tint(.primary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)

                                if let deviceName = ganTimer.deviceName, !deviceName.isEmpty {
                                    Divider()

                                    HStack {
                                        Text("settings.gan_device")
                                            .font(.system(size: 16, weight: .medium))

                                        Spacer()

                                        Text(deviceName)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                }

                                Divider()

                                Toggle(isOn: $ganInspectionStartsOnPress) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("settings.gan_inspection_on_press")
                                            .font(.system(size: 16, weight: .medium))

                                        Text("settings.gan_inspection_on_press_help")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)

                                Divider()

                                VStack(alignment: .leading, spacing: 8) {
                                    settingsMenuRow(
                                        titleKey: "settings.gan_result_input_mode",
                                        selectedKey: GANResultInputMode(rawValue: ganResultInputMode)?.localizedKey ?? "settings.gan_result_mode_manual"
                                    ) {
                                        ForEach(GANResultInputMode.allCases) { mode in
                                            Button(mode.localizedKey) {
                                                ganResultInputMode = mode.rawValue
                                            }
                                        }
                                    }

                                    Text(GANResultInputMode(rawValue: ganResultInputMode)?.helpLocalizedKey ?? "settings.gan_result_mode_cycle_help")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.horizontal, 14)
                                        .padding(.bottom, 12)
                                }

                                Divider()
                            }

                            settingsMenuRow(
                                titleKey: "settings.average_display",
                                selectedKey: AverageDisplayOption(rawValue: averageDisplayOption)?.localizedKey ?? "settings.average_display_ao5_ao12"
                            ) {
                                ForEach(AverageDisplayOption.allCases) { option in
                                    Button(option.localizedKey) {
                                        averageDisplayOption = option.rawValue
                                    }
                                }
                            }

                            Divider()

                            settingsMenuRow(
                                titleKey: "settings.draw_scramble_position",
                                selectedKey: DrawScramblePlacement(rawValue: drawScramblePlacement)?.localizedKey ?? "settings.draw_scramble_position_inline"
                            ) {
                                ForEach(DrawScramblePlacement.allCases) { placement in
                                    Button(placement.localizedKey) {
                                        drawScramblePlacement = placement.rawValue
                                    }
                                }
                            }

                            if (DrawScramblePlacement(rawValue: drawScramblePlacement) ?? .inline).isFloating {
                                Divider()

                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("settings.draw_scramble_size")
                                            .font(.system(size: 16, weight: .medium))

                                        Spacer()

                                        Text("\(Int(drawScrambleFloatingSize.rounded()))")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }

                                    Slider(value: $drawScrambleFloatingSize, in: 96...500, step: 1)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)

                                Divider()
                            } else {
                                Divider()
                            }

                            Toggle(isOn: $hideElementsWhenSolving) {
                                Text("settings.hide_elements_when_solving")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                        .background(settingsCardBackground)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text("tab.settings"))
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $appearanceSelectionTarget) { target in
                appearanceSelectionSheet(for: target)
            }
            .sheet(isPresented: $showingGANDevicePicker) {
                ganDevicePickerSheet
            }
            .onAppear {
                if enteringTimesWith == TimeEntryMode.gan.rawValue {
                    ganTimer.prepareIfNeeded()
                }
                timerBackgroundAppearance = AppearanceConfiguration.decode(
                    from: timerBackgroundAppearanceData,
                    fallback: .defaultBackground
                )
                competitionsBackgroundAppearance = AppearanceConfiguration.decode(
                    from: competitionsBackgroundAppearanceData,
                    fallback: .defaultBackground
                )
                timerTextAppearance = AppearanceConfiguration.decode(
                    from: timerTextAppearanceData,
                    fallback: .defaultTimerText
                )
                scrambleTextAppearance = AppearanceConfiguration.decode(
                    from: scrambleTextAppearanceData,
                    fallback: .defaultScrambleText
                )
                averageTextAppearance = AppearanceConfiguration.decode(
                    from: averageTextAppearanceData,
                    fallback: .defaultAverageText
                )
                selectedAppIcon = AppIconOption.fromCurrentSystemIcon()?.rawValue ?? AppIconOption.red.rawValue
            }
            .onChange(of: timerBackgroundAppearance) { _, newValue in
                timerBackgroundAppearanceData = try? JSONEncoder().encode(newValue)
            }
            .onChange(of: competitionsBackgroundAppearance) { _, newValue in
                competitionsBackgroundAppearanceData = try? JSONEncoder().encode(newValue)
            }
            .onChange(of: timerTextAppearance) { _, newValue in
                timerTextAppearanceData = try? JSONEncoder().encode(newValue)
            }
            .onChange(of: scrambleTextAppearance) { _, newValue in
                scrambleTextAppearanceData = try? JSONEncoder().encode(newValue)
            }
            .onChange(of: averageTextAppearance) { _, newValue in
                averageTextAppearanceData = try? JSONEncoder().encode(newValue)
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.json, .plainText]
            ) { result in
                handleImport(result: result)
            }
            .alert(
                appLocalizedString("settings.data_transfer_title", languageCode: appLanguage),
                isPresented: Binding(
                    get: { importExportAlertMessage != nil },
                    set: { newValue in
                        if !newValue {
                            importExportAlertMessage = nil
                        }
                    }
                )
            ) {
                Button("common.done", role: .cancel) {
                    importExportAlertMessage = nil
                }
            } message: {
                Text(importExportAlertMessage ?? "")
            }
            .alert(
                appLocalizedString("settings.section.wca", languageCode: appLanguage),
                isPresented: Binding(
                    get: { wcaAlertMessage != nil },
                    set: { newValue in
                        if !newValue {
                            wcaAlertMessage = nil
                        }
                    }
                )
            ) {
                Button("common.done", role: .cancel) {
                    wcaAlertMessage = nil
                }
            } message: {
                Text(wcaAlertMessage ?? "")
            }
            .alert(
                appLocalizedString("settings.app_icon", languageCode: appLanguage),
                isPresented: Binding(
                    get: { appIconAlertMessage != nil },
                    set: { newValue in
                        if !newValue {
                            appIconAlertMessage = nil
                        }
                    }
                )
            ) {
                Button("common.done", role: .cancel) {
                    appIconAlertMessage = nil
                }
            } message: {
                Text(appIconAlertMessage ?? "")
            }
            .confirmationDialog(
                appLocalizedString("settings.import_conflict_title", languageCode: appLanguage),
                isPresented: $showingImportConflictDialog,
                titleVisibility: .visible
            ) {
                Button("settings.import_conflict_merge") {
                    confirmPendingImport(with: .merge)
                }
                Button("settings.import_conflict_keep_separate") {
                    confirmPendingImport(with: .rename)
                }
                Button("common.cancel", role: .cancel) {
                    pendingPreparedImport = nil
                }
            } message: {
                Text(importConflictMessage)
            }
            .navigationDestination(item: $wcaDestination) { destination in
                switch destination {
                case .myCompetitions:
                    WCAMyCompetitionsPlaceholderView()
                case .myResults:
                    WCAMyResultsView(profile: wcaAuth.profile)
                }
            }
            .overlay {
                if isImportingData {
                    ZStack {
                        Color.black.opacity(0.16)
                            .ignoresSafeArea()

                        VStack(spacing: 14) {
                            ProgressView(
                                value: Double(importProgressCurrent),
                                total: Double(max(importProgressTotal, 1))
                            )
                            .tint(.blue)
                            .animation(.linear(duration: 0.08), value: importProgressCurrent)
                            .animation(.linear(duration: 0.08), value: importProgressTotal)

                            Text(importProgressLabel.isEmpty ? appLocalizedString("settings.import_in_progress", languageCode: appLanguage) : importProgressLabel)
                                .font(.system(size: 15, weight: .medium))
                                .multilineTextAlignment(.center)

                            Text("\(importProgressCurrent)/\(importProgressTotal)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .frame(maxWidth: 280)
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}

private extension SettingsTabView {
    var ganDevicePickerSheet: some View {
        NavigationStack {
            List {
                if ganTimer.discoveredDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.gan_no_devices")
                            .font(.system(size: 16, weight: .semibold))

                        Text("settings.gan_scanning_help")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(ganTimer.discoveredDevices) { device in
                        Button {
                            ganTimer.connect(to: device.id)
                            showingGANDevicePicker = false
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.name)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.primary)

                                    Text("RSSI \(device.rssi)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if device.hasGANService {
                                    Text("GAN")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.regularMaterial, in: Capsule())
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(Text("settings.gan_choose_device"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel") {
                        ganTimer.stopScanning()
                        showingGANDevicePicker = false
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.refresh") {
                        ganTimer.startDeviceDiscovery()
                    }
                }
            }
            .onAppear {
                ganTimer.startDeviceDiscovery()
            }
        }
        .presentationDetents([.medium, .large])
    }

    var wcaStatusCard: some View {
        HStack(spacing: 12) {
            if let avatarURLString = wcaAuth.profile?.avatarURL,
               let avatarURL = URL(string: avatarURLString) {
                AsyncImage(url: avatarURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                .frame(width: 44, height: 44)
            } else {
                Image(systemName: wcaAuth.isSignedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.questionmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(wcaAuth.isSignedIn ? .blue : .secondary)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(wcaAuth.profile?.displayName ?? appLocalizedString("settings.wca_title", languageCode: appLanguage))
                    .font(.system(size: 17, weight: .semibold))

                Text(wcaAuth.profile?.secondaryText ?? appLocalizedString("settings.wca_signed_out", languageCode: appLanguage))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if wcaAuth.isSignedIn {
                Menu {
                    Button("settings.wca_my_competitions") {
                        wcaDestination = .myCompetitions
                    }
                    Button("settings.wca_my_results") {
                        wcaDestination = .myResults
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("settings.detail")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .tint(.primary)
            }
        }
    }

    var importDataRow: some View {
        Button {
            showingImportPicker = true
        } label: {
            HStack {
                HStack(spacing: 6) {
                    Text("settings.import_data")
                        .font(.system(size: 16, weight: .medium))

                    Button {
                        showingImportInfoAlert = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingImportInfoAlert, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("settings.import_info_title")
                                .font(.system(size: 15, weight: .semibold))
                            Text("settings.import_info_message")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, appLayoutLanguageCategory(for: appLanguage) == .widerCJK ? 22 : 30)
                        .frame(maxWidth: 260, alignment: .leading)
                        .presentationCompactAdaptation(.popover)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var exportDataRow: some View {
        Button {
            showingExportFormatDialog = true
        } label: {
            HStack {
                Text("settings.export_data")
                    .font(.system(size: 16, weight: .medium))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingExportFormatDialog, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("settings.export_format_title")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .center)

                Button {
                    showingExportFormatDialog = false
                    prepareExport(format: .cubeFlow)
                } label: {
                    Text("settings.export_format_cubeflow")
                        .font(.system(size: 16, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .glassEffect(.regular.tint(.secondary.opacity(0.22)).interactive(), in: .capsule)
                }
                .buttonStyle(.plain)

                Button {
                    showingExportFormatDialog = false
                    prepareExport(format: .csTimer)
                } label: {
                    Text("settings.export_format_cstimer")
                        .font(.system(size: 16, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .glassEffect(.regular.tint(.secondary.opacity(0.22)).interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .frame(width: 248, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
        .fileExporter(
            isPresented: $showingExportPicker,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportDefaultFilename
        ) { result in
            if case .failure(let error) = result {
                importExportAlertMessage = error.localizedDescription
            }
        }
    }

    func settingsActionRow(titleKey: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(titleKey)
                    .font(.system(size: 16, weight: .medium))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func authenticateWithWCA() {
        Task { @MainActor in
            do {
                if wcaAuth.isSignedIn {
                    try await wcaAuth.refreshProfile()
                } else {
                    try await wcaAuth.signIn()
                }
            } catch {
                if let localizedError = error as? LocalizedError,
                   let errorDescription = localizedError.errorDescription {
                    wcaAlertMessage = errorDescription
                } else {
                    wcaAlertMessage = error.localizedDescription
                }
            }
        }
    }

    func applyAppIcon(_ option: AppIconOption) {
        guard UIApplication.shared.supportsAlternateIcons else {
            appIconAlertMessage = appLocalizedString("settings.app_icon_not_supported", languageCode: appLanguage)
            return
        }

        let currentAlternate = UIApplication.shared.alternateIconName
        if currentAlternate == option.alternateIconName {
            selectedAppIcon = option.rawValue
            return
        }

        UIApplication.shared.setAlternateIconName(option.alternateIconName) { error in
            Task { @MainActor in
                if let error {
                    appIconAlertMessage = error.localizedDescription
                } else {
                    selectedAppIcon = option.rawValue
                }
            }
        }
    }

    func prepareExport(format: DataTransferExportFormat) {
        do {
            let solves = try fetchAllSolves()
            let package = try DataTransferManager.prepareExport(
                format: format,
                sessions: sessions,
                solves: solves
            )
            exportDocument = package.document
            exportContentType = package.contentType
            exportDefaultFilename = package.defaultFilename
            showingExportPicker = true
        } catch {
            importExportAlertMessage = error.localizedDescription
        }
    }

    func handleImport(result: Result<URL, Error>) {
        Task {
            do {
                let url = try result.get()
                let didAccessSecurityScopedResource = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccessSecurityScopedResource {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: url)
                let existingSessionReferences = sessions.map {
                    DataTransferExistingSessionReference(
                        id: $0.id,
                        name: $0.name,
                        createdAt: $0.createdAt
                    )
                }
                beginImportProgress(label: appLocalizedString("settings.import_preparing", languageCode: appLanguage), total: 1)

                let preparedImport = try await Task.detached(priority: .userInitiated) {
                    try DataTransferManager.prepareImport(
                        data,
                        existingSessions: existingSessionReferences
                    )
                }.value
                endImportProgress()

                if preparedImport.preview.hasSessionConflicts {
                    pendingPreparedImport = preparedImport
                    showingImportConflictDialog = true
                } else {
                    try await runImport(preparedImport, conflictResolution: .rename)
                }
            } catch {
                endImportProgress()
                if let transferError = error as? DataTransferError, transferError == .unsupportedImportFile {
                    importExportAlertMessage = appLocalizedString("settings.import_unsupported", languageCode: appLanguage)
                } else {
                    importExportAlertMessage = error.localizedDescription
                }
            }
        }
    }

    func confirmPendingImport(with conflictResolution: DataTransferSessionConflictResolution) {
        guard let pendingPreparedImport else { return }
        self.pendingPreparedImport = nil

        Task {
            do {
                try await runImport(pendingPreparedImport, conflictResolution: conflictResolution)
            } catch {
                endImportProgress()
                if let transferError = error as? DataTransferError, transferError == .unsupportedImportFile {
                    importExportAlertMessage = appLocalizedString("settings.import_unsupported", languageCode: appLanguage)
                } else {
                    importExportAlertMessage = error.localizedDescription
                }
            }
        }
    }

    func runImport(
        _ preparedImport: DataTransferPreparedImport,
        conflictResolution: DataTransferSessionConflictResolution
    ) async throws {
        beginImportProgress(label: appLocalizedString("settings.import_in_progress", languageCode: appLanguage), total: max(preparedImport.preview.solveCount + preparedImport.preview.sessionCount, 1))
        try await DataTransferManager.importPreparedImport(
            preparedImport,
            conflictResolution: conflictResolution,
            modelContext: modelContext,
        ) { progress in
            switch progress.stage {
            case .preparing:
                beginImportProgress(
                    label: appLocalizedString("settings.import_preparing", languageCode: appLanguage),
                    total: progress.total
                )
                updateImportProgress(current: progress.current, total: progress.total)
            case .importing:
                if !isImportingData || importProgressLabel != appLocalizedString("settings.import_in_progress", languageCode: appLanguage) {
                    beginImportProgress(
                        label: appLocalizedString("settings.import_in_progress", languageCode: appLanguage),
                        total: progress.total
                    )
                }
                updateImportProgress(current: progress.current, total: progress.total)
            }
        }
        endImportProgress()
        importExportAlertMessage = appLocalizedString("settings.import_success", languageCode: appLanguage)
    }

    func fetchAllSolves() throws -> [Solve] {
        let descriptor = FetchDescriptor<Solve>(
            sortBy: [SortDescriptor(\Solve.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func beginImportProgress(label: String, total: Int) {
        isImportingData = true
        importProgressLabel = label
        importProgressCurrent = 0
        importProgressTotal = max(total, 1)
    }

    func updateImportProgress(current: Int, total: Int? = nil) {
        withAnimation(.linear(duration: 0.08)) {
            if let total {
                importProgressTotal = max(total, 1)
            }
            importProgressCurrent = min(current, importProgressTotal)
        }
    }

    func endImportProgress() {
        isImportingData = false
        importProgressCurrent = 0
        importProgressTotal = 1
        importProgressLabel = ""
    }

    var appearanceOverviewCard: some View {
        VStack(spacing: 0) {
            settingsMenuRow(
                titleKey: "settings.app_icon",
                selectedKey: (AppIconOption(rawValue: selectedAppIcon) ?? .red).localizedKey
            ) {
                ForEach(AppIconOption.allCases) { option in
                    Button(option.localizedKey) {
                        applyAppIcon(option)
                    }
                }
            }

            Divider()

            settingsMenuRow(
                titleKey: "settings.competition_card_style",
                selectedKey: (CompetitionCardStyleOption(rawValue: competitionCardStyle) ?? .list).localizedKey
            ) {
                ForEach(CompetitionCardStyleOption.allCases) { option in
                    Button(option.localizedKey) {
                        competitionCardStyle = option.rawValue
                    }
                }
            }
        }
        .background(settingsCardBackground)
    }

    var importConflictMessage: String {
        let conflictNames = pendingPreparedImport?.preview.sessionConflicts.map(\.displayName) ?? []
        let shownNames = conflictNames.prefix(4).joined(separator: ", ")
        return String(
            format: appLocalizedString("settings.import_conflict_message", languageCode: appLanguage),
            shownNames
        )
    }

    func appearanceEditorCard(
        titleKey: LocalizedStringKey,
        configuration: Binding<AppearanceConfiguration>,
        fontSize: Binding<Double>? = nil,
        fontSizeTitleKey: LocalizedStringKey? = nil,
        defaultFontSize: Double? = nil,
        fontDesign: Binding<String>? = nil,
        fontDesignTarget: AppearanceSelectionTarget? = nil,
        defaultFontDesign: String? = nil,
        fontWeight: Binding<String>? = nil,
        fontWeightTarget: AppearanceSelectionTarget? = nil,
        defaultFontWeight: String? = nil,
        previewKind: TextAppearancePreviewKind? = nil,
        photoData: Binding<Data?>? = nil,
        photoItem: Binding<PhotosPickerItem?>? = nil,
        allowsPhoto: Bool = false
    ) -> AnyView {
        AnyView(
            VStack(spacing: 0) {
                settingsMenuRow(
                    titleKey: titleKey,
                    selectedKey: configuration.wrappedValue.style.localizedKey
                ) {
                    ForEach(appearanceStyleOptions(allowsPhoto: allowsPhoto)) { style in
                        Button(style.localizedKey) {
                            configuration.wrappedValue.style = style
                        }
                    }
                }

                if configuration.wrappedValue.style == .color {
                    Divider()
                    appearanceColorRows(configuration: configuration)
                }

                if configuration.wrappedValue.style == .gradient {
                    Divider()
                    appearanceGradientRows(configuration: configuration)
                }

                if allowsPhoto,
                   configuration.wrappedValue.style == .photo,
                   let photoData,
                   let photoItem {
                    Divider()
                    appearancePhotoRow(photoData: photoData, photoItem: photoItem)
                }

                if let fontSize, let fontSizeTitleKey, let defaultFontSize {
                    Divider()
                    appearanceFontSizeRow(
                        titleKey: fontSizeTitleKey,
                        value: fontSize,
                        defaultValue: defaultFontSize
                    )
                }

                if let fontDesign, let defaultFontDesign {
                    Divider()
                    appearanceFontDesignRow(
                        value: fontDesign,
                        target: fontDesignTarget ?? .timerFontDesign,
                        defaultValue: defaultFontDesign
                    )
                }

                if let fontWeight, let defaultFontWeight {
                    Divider()
                    appearanceFontWeightRow(
                        value: fontWeight,
                        target: fontWeightTarget ?? .timerFontWeight,
                        defaultValue: defaultFontWeight
                    )
                }

                if let previewKind, let fontSize, let fontDesign, let fontWeight {
                    Divider()
                    appearancePreviewRow(
                        kind: previewKind,
                        configuration: configuration.wrappedValue,
                        fontSize: fontSize.wrappedValue,
                        fontDesign: TimerFontDesignOption(rawValue: fontDesign.wrappedValue) ?? .default,
                        fontWeight: TimerFontWeightOption(rawValue: fontWeight.wrappedValue) ?? .medium
                    )
                }

            }
            .background(settingsCardBackground)
        )
    }

    func appearanceStyleOptions(allowsPhoto: Bool) -> [AppearanceStyleOption] {
        AppearanceStyleOption.allCases.filter { allowsPhoto || $0 != .photo }
    }

    func appearanceColorRows(configuration: Binding<AppearanceConfiguration>) -> AnyView {
        AnyView(
            VStack(spacing: 0) {
                ForEach(AppearanceModeVariant.allCases) { variant in
                    if variant == .dark {
                        Divider()
                    }

                    HStack {
                        Text(variant.localizedKey)
                            .font(.system(size: 16, weight: .medium))

                        Spacer()

                        ColorPicker(
                            "",
                            selection: colorBinding(configuration: configuration, variant: variant)
                        )
                        .labelsHidden()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        )
    }

    func appearanceGradientRows(configuration: Binding<AppearanceConfiguration>) -> AnyView {
        AnyView(
            VStack(spacing: 0) {
                ForEach(AppearanceModeVariant.allCases) { variant in
                    if variant == .dark {
                        Divider()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(variant.localizedKey)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)

                        GradientPicker(
                            stops: gradientStopsBinding(configuration: configuration, variant: variant),
                            angle: gradientAngleBinding(configuration: configuration, variant: variant)
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        )
    }

    private func appearancePhotoRow(
        photoData: Binding<Data?>,
        photoItem: Binding<PhotosPickerItem?>
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("settings.timer_bg_photo")
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                PhotosPicker(
                    selection: photoItem,
                    matching: .images
                ) {
                    Text("settings.timer_bg_photo_button")
                        .font(.system(size: 15, weight: .medium))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .onChange(of: photoItem.wrappedValue) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        photoData.wrappedValue = data
                    }
                }
            }

            if photoData.wrappedValue != nil {
                Divider()
                HStack {
                    Spacer()
                    Button("settings.timer_bg_photo_clear") {
                        photoData.wrappedValue = nil
                        photoItem.wrappedValue = nil
                    }
                    .font(.system(size: 14, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    func appearanceFontSizeRow(
        titleKey: LocalizedStringKey,
        value: Binding<Double>,
        defaultValue: Double
    ) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(titleKey)
                        .font(.system(size: 16, weight: .medium))

                    Spacer()

                    Button("common.reset") {
                        value.wrappedValue = defaultValue
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.tint(.blue).interactive(), in: .capsule)
                    .buttonStyle(.plain)
                    .disabled(abs(value.wrappedValue - defaultValue) < 0.5)
                    .opacity(abs(value.wrappedValue - defaultValue) < 0.5 ? 0.45 : 1)

                    Text("\(Int(value.wrappedValue.rounded()))")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: value, in: 12...96, step: 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        )
    }

    func appearanceFontDesignRow(
        value: Binding<String>,
        target: AppearanceSelectionTarget,
        defaultValue: String
    ) -> AnyView {
        return AnyView(
            Button {
                appearanceSelectionTarget = target
            } label: {
                HStack {
                    Text("settings.font_design_label")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    fontDesignMenuLabel(TimerFontDesignOption(rawValue: value.wrappedValue) ?? .default)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        )
    }

    func appearanceFontWeightRow(
        value: Binding<String>,
        target: AppearanceSelectionTarget,
        defaultValue: String
    ) -> AnyView {
        return AnyView(
            Button {
                appearanceSelectionTarget = target
            } label: {
                HStack {
                    Text("settings.font_weight_label")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    fontWeightMenuLabel(TimerFontWeightOption(rawValue: value.wrappedValue) ?? .medium)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        )
    }

    @ViewBuilder
    func fontDesignMenuLabel(_ option: TimerFontDesignOption) -> some View {
        Text(option.localizedKey)
            .font(.system(size: 15, weight: .medium, design: option.fontDesign))
            .fontWidth(option.fontWidth)
    }

    var orderedFontDesignOptions: [TimerFontDesignOption] {
        [
            .default,
            .rounded,
            .serif,
            .monospaced,
            .expanded,
            .condensed,
            .compressed
        ]
    }

    @ViewBuilder
    func fontWeightMenuLabel(_ option: TimerFontWeightOption) -> some View {
        Text(option.localizedKey)
            .font(.system(size: 15, weight: option.fontWeight))
    }

    func fontDesignBinding(for target: AppearanceSelectionTarget) -> Binding<String> {
        switch target {
        case .timerFontDesign:
            return $timerTextFontDesign
        case .scrambleFontDesign:
            return $scrambleTextFontDesign
        case .averageFontDesign:
            return $averageTextFontDesign
        case .timerFontWeight, .scrambleFontWeight, .averageFontWeight:
            return .constant(TimerFontDesignOption.default.rawValue)
        }
    }

    func fontWeightBinding(for target: AppearanceSelectionTarget) -> Binding<String> {
        switch target {
        case .timerFontWeight:
            return $timerTextFontWeight
        case .scrambleFontWeight:
            return $scrambleTextFontWeight
        case .averageFontWeight:
            return $averageTextFontWeight
        case .timerFontDesign, .scrambleFontDesign, .averageFontDesign:
            return .constant(TimerFontWeightOption.medium.rawValue)
        }
    }

    func defaultFontWeightValue(for target: AppearanceSelectionTarget) -> String {
        switch target {
        case .timerFontWeight:
            return TimerFontWeightOption.semibold.rawValue
        case .scrambleFontWeight, .averageFontWeight:
            return TimerFontWeightOption.medium.rawValue
        case .timerFontDesign, .scrambleFontDesign, .averageFontDesign:
            return TimerFontWeightOption.medium.rawValue
        }
    }

    @ViewBuilder
    func appearanceSelectionSheet(for target: AppearanceSelectionTarget) -> some View {
        switch target {
        case .timerFontDesign, .scrambleFontDesign, .averageFontDesign:
            NavigationStack {
                List {
                    ForEach(orderedFontDesignOptions) { option in
                        Button {
                            fontDesignBinding(for: target).wrappedValue = option.rawValue
                            appearanceSelectionTarget = nil
                        } label: {
                            HStack {
                                fontDesignMenuLabel(option)
                                Spacer()
                                if fontDesignBinding(for: target).wrappedValue == option.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button("common.reset") {
                        fontDesignBinding(for: target).wrappedValue = TimerFontDesignOption.default.rawValue
                        appearanceSelectionTarget = nil
                    }
                    .disabled(fontDesignBinding(for: target).wrappedValue == TimerFontDesignOption.default.rawValue)
                }
                .navigationTitle("settings.font_design_label")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])

        case .timerFontWeight, .scrambleFontWeight, .averageFontWeight:
            NavigationStack {
                List {
                    ForEach(TimerFontWeightOption.allCases) { option in
                        Button {
                            fontWeightBinding(for: target).wrappedValue = option.rawValue
                            appearanceSelectionTarget = nil
                        } label: {
                            HStack {
                                fontWeightMenuLabel(option)
                                Spacer()
                                if fontWeightBinding(for: target).wrappedValue == option.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button("common.reset") {
                        fontWeightBinding(for: target).wrappedValue = defaultFontWeightValue(for: target)
                        appearanceSelectionTarget = nil
                    }
                    .disabled(fontWeightBinding(for: target).wrappedValue == defaultFontWeightValue(for: target))
                }
                .navigationTitle("settings.font_weight_label")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
    }

    func appearancePreviewRow(
        kind: TextAppearancePreviewKind,
        configuration: AppearanceConfiguration,
        fontSize: Double,
        fontDesign: TimerFontDesignOption,
        fontWeight: TimerFontWeightOption
    ) -> AnyView {
        let previewText: Text = {
            switch kind {
            case .timer:
                return Text("12.34")
            case .scramble:
                return Text("R U R' U'")
            case .average:
                return Text("ao5 8.21")
            }
        }()

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text("common.preview")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    styledPreviewText(
                        previewText,
                        configuration: configuration,
                        fontSize: fontSize,
                        fontDesign: fontDesign,
                        fontWeight: fontWeight
                    )
                    .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 18)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        )
    }


    @ViewBuilder
    func styledPreviewText(
        _ text: Text,
        configuration: AppearanceConfiguration,
        fontSize: Double,
        fontDesign: TimerFontDesignOption,
        fontWeight: TimerFontWeightOption
    ) -> some View {
        let base = text
            .font(.system(size: fontSize, weight: fontWeight.fontWeight, design: fontDesign.fontDesign))
            .fontWidth(fontDesign.fontWidth)

        switch configuration.style {
        case .system, .photo:
            base.foregroundStyle(.primary)
        case .color:
            base.foregroundStyle(configuration.lightColor.color)
        case .gradient:
            base.foregroundStyle(
                LinearGradient(
                    gradient: Gradient(stops: configuration.lightGradient.resolvedStops),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }

    @ViewBuilder
    func settingsMenuRow<Content: View>(
        titleKey: LocalizedStringKey,
        selectedKey: LocalizedStringKey? = nil,
        selectedText: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> AnyView {
        AnyView(
            HStack {
                Text(titleKey)
                    .font(.system(size: 16, weight: .medium))

                Spacer()

                Menu {
                    content()
                } label: {
                    HStack(spacing: 6) {
                        if let selectedKey {
                            Text(selectedKey)
                                .font(.system(size: 15, weight: .medium))
                        } else if let selectedText {
                            Text(selectedText)
                                .font(.system(size: 15, weight: .medium))
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .tint(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        )
    }

    func colorBinding(
        configuration: Binding<AppearanceConfiguration>,
        variant: AppearanceModeVariant
    ) -> Binding<Color> {
        Binding(
            get: {
                switch variant {
                case .light:
                    configuration.wrappedValue.lightColor.color
                case .dark:
                    configuration.wrappedValue.darkColor.color
                }
            },
            set: { newValue in
                configuration.wrappedValue.setColor(newValue, for: variant)
            }
        )
    }

    func gradientStopsBinding(
        configuration: Binding<AppearanceConfiguration>,
        variant: AppearanceModeVariant
    ) -> Binding<[GradientStop]> {
        Binding(
            get: {
                switch variant {
                case .light:
                    configuration.wrappedValue.lightGradient.pickerStops
                case .dark:
                    configuration.wrappedValue.darkGradient.pickerStops
                }
            },
            set: { newValue in
                configuration.wrappedValue.setGradientStops(newValue, for: variant)
            }
        )
    }

    func gradientAngleBinding(
        configuration: Binding<AppearanceConfiguration>,
        variant: AppearanceModeVariant
    ) -> Binding<Double> {
        Binding(
            get: {
                switch variant {
                case .light:
                    configuration.wrappedValue.lightGradient.angle
                case .dark:
                    configuration.wrappedValue.darkGradient.angle
                }
            },
            set: { newValue in
                configuration.wrappedValue.setGradientAngle(newValue, for: variant)
            }
        )
    }
}

private enum WCASettingsDestination: String, Identifiable {
    case myCompetitions
    case myResults

    var id: String { rawValue }
}

private enum AppIconOption: String, CaseIterable, Identifiable {
    case red = "CubeflowRed"
    case orange = "CubeflowAmber"
    case yellow = "CubeflowGold"
    case green = "CubeflowGreen"
    case teal = "CubeflowTeal"
    case turquoise = "CubeflowTurquoise"
    case cyan = "CubeflowCyan"
    case blue = "CubeflowBlue"
    case indigo = "CubeflowIndigo"
    case purple = "CubeflowPurple"
    case black = "CubeflowBlack"
    case darkGray = "CubeflowDarkGray"
    case gray = "CubeflowGray"
    case lightGray = "CubeflowLightGray"

    var id: String { rawValue }

    var alternateIconName: String? {
        switch self {
        case .red:
            return nil
        default:
            return rawValue
        }
    }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .red: "settings.app_icon_red"
        case .orange: "settings.app_icon_orange"
        case .yellow: "settings.app_icon_yellow"
        case .green: "settings.app_icon_green"
        case .teal: "settings.app_icon_teal"
        case .turquoise: "settings.app_icon_turquoise"
        case .cyan: "settings.app_icon_cyan"
        case .blue: "settings.app_icon_blue"
        case .indigo: "settings.app_icon_indigo"
        case .purple: "settings.app_icon_purple"
        case .black: "settings.app_icon_black"
        case .darkGray: "settings.app_icon_dark_gray"
        case .gray: "settings.app_icon_gray"
        case .lightGray: "settings.app_icon_light_gray"
        }
    }

    static func fromCurrentSystemIcon() -> AppIconOption? {
        guard let alternateIconName = UIApplication.shared.alternateIconName else {
            return .red
        }
        return AppIconOption(rawValue: alternateIconName)
    }
}

private enum TimerUpdatingMode: String, CaseIterable, Identifiable {
    case on
    case seconds
    case inspectionOnly
    case off

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .on: "settings.timer_updating_on"
        case .seconds: "settings.timer_updating_seconds"
        case .inspectionOnly: "settings.timer_updating_inspection_only"
        case .off: "settings.timer_updating_off"
        }
    }
}

private enum TimerAccuracy: String, CaseIterable, Identifiable {
    case hundredths
    case thousandths

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .hundredths: "settings.timer_accuracy_01"
        case .thousandths: "settings.timer_accuracy_001"
        }
    }

    var decimals: Int {
        switch self {
        case .hundredths: 2
        case .thousandths: 3
        }
    }
}

private enum TimeEntryMode: String, CaseIterable, Identifiable {
    case timer
    case typing
    case gan

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .timer: "settings.entering_times_timer"
        case .typing: "settings.entering_times_typing"
        case .gan: "settings.entering_times_gan"
        }
    }
}

#endif
