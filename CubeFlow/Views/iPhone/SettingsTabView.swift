import SwiftUI
import PhotosUI
import CoreData
import UniformTypeIdentifiers

#if os(iOS)
private enum TimerCustomizationPage: String, Hashable {
    case root
    case scramblePosition
    case backgroundStyle
    case timerStyle
    case scrambleStyle
    case statisticsStyle
    case statistics
    case scrambleDiagram
    case scrambleDiagramColors

    var section: TimerCustomizationSection? {
        switch self {
        case .root:
            nil
        case .scramblePosition:
            .layout
        case .backgroundStyle, .timerStyle, .scrambleStyle, .statisticsStyle:
            .style
        case .statistics, .scrambleDiagram, .scrambleDiagramColors:
            .components
        }
    }
}

private enum TimerCustomizationSection: Hashable {
    case layout
    case style
    case components
}

private enum TimerCustomizationListRow: Hashable, Identifiable {
    case arrangement
    case splitOrder
    case minimalMode
    case navigation(TimerCustomizationPage)
    case nextScrambleToggle
    case back(TimerCustomizationSection)
    case scramblePositionEditor
    case appearanceEditor(TimerCustomizationPage)
    case statistic(TimerStatisticMetric)
    case cardsStatisticsArrangement
    case cardsPositionsHeader
    case cardsStatisticSlot(Int)
    case diagramPlacement
    case diagramSize
    case colorPuzzle
    case colorPreview
    case colorFace(Int)
    case colorHelp
    case colorReset
    case numeralSystem(NumeralScope)
    case chineseFinancial(NumeralScope)
    case chineseNumberFormat(NumeralScope)
    case chineseDecimalStyle(NumeralScope)

    var id: Self { self }
}

private enum AppNumeralSettingsRow: Hashable, Identifiable {
    case numeralSystem
    case chineseFinancial
    case chineseNumberFormat
    case chineseDecimalStyle

    var id: Self { self }
}

private struct TimerCustomizationListRowHost: View {
    let content: AnyView

    var body: some View {
        content
    }
}

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

    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.colorScheme) private var currentColorScheme
    #if DEBUG
    @Environment(\.isMarketingPreview) private var isMarketingPreview
    #endif
    @ObservedObject private var ganTimer = GANTimerBluetoothManager.shared
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Session.createdAt, ascending: true)],
        animation: .default
    )
    private var sessions: FetchedResults<Session>
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Solve.date, ascending: false)],
        animation: .default
    )
    private var solves: FetchedResults<Solve>

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
    @AppStorage("timerAccuracy") private var timerAccuracy: String = SolveTimeAccuracy.thousandths.rawValue
    @AppStorage("enteringTimesWith") private var enteringTimesWith: String = TimeEntryMode.timer.rawValue
    @AppStorage("hideElementsWhenSolving") private var hideElementsWhenSolving: Bool = false
    @AppStorage("scrambleDisplayMode") private var scrambleDisplayMode: String = ScrambleDisplayMode.shrinkFont.rawValue
    @AppStorage("timerBackgroundImageData") private var timerBackgroundImageData: Data?
    @AppStorage("competitionsBackgroundImageData") private var competitionsBackgroundImageData: Data?
    @AppStorage("drawScramblePlacement") private var drawScramblePlacement: String = DrawScramblePlacement.inline.rawValue
    @AppStorage("drawScrambleFloatingSize") private var drawScrambleFloatingSize: Double = TimerCustomizationDefaults.drawScrambleSize
    @AppStorage("scrambleDiagramColorSchemeData") private var scrambleDiagramColorSchemeData: Data?
    @AppStorage("timerTextFontSize") private var timerTextFontSize: Double = 64
    @AppStorage("scrambleTextFontSize") private var scrambleTextFontSize: Double = 20
    @AppStorage("averageTextFontSize") private var averageTextFontSize: Double = 20
    @AppStorage("timerTextFontDesign") private var timerTextFontDesign: String = TimerFontDesignOption.default.rawValue
    @AppStorage("scrambleTextFontDesign") private var scrambleTextFontDesign: String = TimerFontDesignOption.default.rawValue
    @AppStorage("averageTextFontDesign") private var averageTextFontDesign: String = TimerFontDesignOption.default.rawValue
    @AppStorage("timerTextFontWeight") private var timerTextFontWeight: String = TimerFontWeightOption.semibold.rawValue
    @AppStorage("scrambleTextFontWeight") private var scrambleTextFontWeight: String = TimerFontWeightOption.medium.rawValue
    @AppStorage("averageTextFontWeight") private var averageTextFontWeight: String = TimerFontWeightOption.medium.rawValue
    @AppStorage("timerArrangement") private var timerArrangement: String = TimerArrangement.classic.rawValue
    @AppStorage("timerMinimalMode") private var timerMinimalMode: Bool = false
    @AppStorage("timerMinimalArrangementMigrationCompleted") private var timerMinimalArrangementMigrationCompleted: Bool = false
    @AppStorage("timerSplitOrder") private var timerSplitOrder: String = TimerSplitOrder.statisticsLeading.rawValue
    @AppStorage("timerScrambleVerticalPosition") private var timerScrambleVerticalPosition: Double = 0
    @AppStorage("timerStatisticsSelection") private var timerStatisticsSelection: String = ""
    @AppStorage("timerClassicStatisticsSelection") private var timerClassicStatisticsSelection: String = ""
    @AppStorage("timerCardsStatisticsSelection") private var timerCardsStatisticsSelection: String = ""
    @AppStorage("timerCardsTwoStatisticsArrangement") private var timerCardsTwoStatisticsArrangement: String = TimerCardsTwoStatisticArrangement.vertical.rawValue
    @AppStorage("timerCardsThreeStatisticsArrangement") private var timerCardsThreeStatisticsArrangement: String = TimerCardsThreeStatisticArrangement.topEmphasis.rawValue
    @AppStorage("timerCardsStatisticsPositions") private var timerCardsStatisticsPositions: String = ""
    @AppStorage("showNextScrambleButton") private var showNextScrambleButton: Bool = true
    @AppStorage("selectedAppIcon") private var selectedAppIcon: String = AppIconOption.red.rawValue
    @AppStorage("competitionCardStyle") private var competitionCardStyle: String = CompetitionCardStyleOption.list.rawValue
    @AppStorage("appNumeralSystem") private var appNumeralSystem = NumeralSystem.systemDefault.rawValue
    @AppStorage("timerNumeralSystem") private var timerNumeralSystem = NumeralPreferenceKeys.inheritedRawValue
    @AppStorage("statisticsNumeralSystem") private var statisticsNumeralSystem = NumeralPreferenceKeys.inheritedRawValue
    @AppStorage("appNumeralChineseFinancial") private var appNumeralChineseFinancial = false
    @AppStorage("timerNumeralChineseFinancial") private var timerNumeralChineseFinancial = false
    @AppStorage("statisticsNumeralChineseFinancial") private var statisticsNumeralChineseFinancial = false
    @AppStorage("appNumeralChineseNumberFormat") private var appNumeralChineseNumberFormat = ChineseNumeralNumberFormat.digits.rawValue
    @AppStorage("timerNumeralChineseNumberFormat") private var timerNumeralChineseNumberFormat = ChineseNumeralNumberFormat.digits.rawValue
    @AppStorage("statisticsNumeralChineseNumberFormat") private var statisticsNumeralChineseNumberFormat = ChineseNumeralNumberFormat.digits.rawValue
    @AppStorage("appNumeralChineseDecimalStyle") private var appNumeralChineseDecimalStyle = ChineseNumeralDecimalStyle.period.rawValue
    @AppStorage("timerNumeralChineseDecimalStyle") private var timerNumeralChineseDecimalStyle = ChineseNumeralDecimalStyle.period.rawValue
    @AppStorage("statisticsNumeralChineseDecimalStyle") private var statisticsNumeralChineseDecimalStyle = ChineseNumeralDecimalStyle.period.rawValue

    @State private var timerBackgroundAppearance = AppearanceConfiguration.defaultBackground
    @State private var competitionsBackgroundAppearance = AppearanceConfiguration.defaultBackground
    @State private var timerTextAppearance = AppearanceConfiguration.defaultTimerText
    @State private var scrambleTextAppearance = AppearanceConfiguration.defaultScrambleText
    @State private var averageTextAppearance = AppearanceConfiguration.defaultAverageText
    @State private var scrambleDiagramColorScheme = ScrambleColorConfiguration.default
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
    @State private var timerCustomizationPath: [TimerCustomizationPage] = []
    @State private var selectedScrambleColorPuzzle: ScrambleColorPuzzle = .cube
    @State private var showingGANDevicePicker = false
    @State private var showingCompetitionCalculator = false
    @StateObject private var wcaAuth = WCAAuthManager.shared
    @StateObject private var fontDownloadManager = TimerFontDownloadManager.shared

    let isActive: Bool

    init(isActive: Bool = true) {
        self.isActive = isActive
    }

    private var currentLanguageOption: AppLanguageOption {
        appLanguageOptions().first(where: { $0.id == appLanguage }) ?? appLanguageOptions()[0]
    }

    private var settingsCardBackgroundFillColor: Color {
        currentColorScheme == .dark
            ? Color(.secondarySystemGroupedBackground)
            : Color(.systemBackground)
    }

    private var settingsCardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(settingsCardBackgroundFillColor)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(.separator).opacity(currentColorScheme == .dark ? 0.28 : 0.12), lineWidth: 0.5)
            }
    }

    var body: some View {
        if !isActive {
            Color.clear
        } else {
            settingsContent
        }
    }

    private var settingsContent: some View {
        CompatibleNavigationContainer {
            settingsRootList
            .navigationTitle(Text(appLocalizedString("tab.settings", languageCode: appLanguage)))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCompetitionCalculator = true
                    } label: {
                        Image(systemName: "function")
                    }
                    .accessibilityLabel(Text("settings.competition_calculator_title"))
                }
            }
            .sheet(item: $appearanceSelectionTarget) { target in
                appearanceSelectionSheet(for: target)
            }
            .sheet(isPresented: $showingGANDevicePicker) {
                ganDevicePickerSheet
            }
            .sheet(isPresented: $showingCompetitionCalculator) {
                CompetitionCalculatorSheet(appLanguage: appLanguage)
            }
            .onAppear {
                migrateTimerArrangementPreferencesIfNeeded()
                normalizeUnavailableFontSelections()
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
                scrambleDiagramColorScheme = ScrambleColorConfiguration.decode(from: scrambleDiagramColorSchemeData)
                selectedAppIcon = AppIconOption.fromCurrentSystemIcon()?.rawValue ?? AppIconOption.red.rawValue
            }
            .onChange(of: timerBackgroundAppearance) { newValue in
                timerBackgroundAppearanceData = try? JSONEncoder().encode(newValue)
            }
            .onChange(of: competitionsBackgroundAppearance) { newValue in
                competitionsBackgroundAppearanceData = try? JSONEncoder().encode(newValue)
            }
            .onChange(of: timerTextAppearance) { newValue in
                timerTextAppearanceData = try? JSONEncoder().encode(newValue)
            }
            .onChange(of: scrambleTextAppearance) { newValue in
                scrambleTextAppearanceData = try? JSONEncoder().encode(newValue)
            }
            .onChange(of: averageTextAppearance) { newValue in
                averageTextAppearanceData = try? JSONEncoder().encode(newValue)
            }
            .onChange(of: scrambleDiagramColorScheme) { newValue in
                scrambleDiagramColorSchemeData = newValue.encodedData()
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
            .compatibleNavigationDestination(item: $wcaDestination) { destination in
                switch destination {
                case .account:
                    wcaAccountSettingsList
                case .myCompetitions:
                    WCAMyCompetitionsView(profile: wcaAuth.profile)
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
                        .compatibleGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}

private extension SettingsTabView {
    var settingsRootList: some View {
            List {
                wcaSettingsSection

                Section {
                    NavigationLink {
                        CacheSettingsView()
                    } label: {
                        settingsNavigationLabel(titleKey: "settings.cache_title")
                    }
                } header: {
                    Text("settings.section.storage_cache")
                }

                Section {
                    languageListRow
                    appIconListRow
                } header: {
                Text("settings.section.general")
            }

            Section {
                ForEach(appNumeralSettingsRows) { row in
                    TimerCustomizationListRowHost(content: appNumeralSettingsListRow(row))
                        .transition(.opacity)
                }

                NavigationLink {
                    timerTabAppearanceSettingsList
                } label: {
                    settingsNavigationLabel(titleKey: "settings.timer_tab")
                }

                NavigationLink {
                    competitionTabAppearanceSettingsList
                } label: {
                    settingsNavigationLabel(titleKey: "settings.competition_tab")
                }
            } header: {
                Text("settings.section.appearance")
            }

            Section {
                NavigationLink {
                    timerSolvingSettingsList
                } label: {
                    settingsNavigationLabel(
                        titleKey: "settings.wca_inspection",
                        valueKey: wcaInspectionEnabled ? "settings.timer_updating_on" : "settings.timer_updating_off"
                    )
                }

                NavigationLink {
                    timerDisplaySettingsList
                } label: {
                    settingsNavigationLabel(titleKey: "settings.timer_updating")
                }

                NavigationLink {
                    timerInputSettingsList
                } label: {
                    settingsNavigationLabel(
                        titleKey: "settings.entering_times_with",
                        valueKey: TimeEntryMode(rawValue: enteringTimesWith)?.localizedKey ?? "settings.entering_times_timer"
                    )
                }

            } header: {
                Text("settings.section.timer")
            }

            Section {
                NavigationLink {
                    SmartCubeLabView()
                } label: {
                    settingsNavigationLabel(titleKey: "smart_cube.title")
                }
            } header: {
                Text("smart_cube.section")
            } footer: {
                Text("smart_cube.settings_footer")
            }

            Section {
                importDataRow
                exportDataRow
            } header: {
                Text("settings.data_transfer_title")
            }

            #if DEBUG
            if !isMarketingPreview {
                Section {
                    NavigationLink {
                        MarketingPreviewCatalogView()
                    } label: {
                        Label("Marketing Preview", systemImage: "camera.viewfinder")
                    }
                } header: {
                    Text("Development")
                }
            }
            #endif

            Section {
                NavigationLink {
                    AboutCubeFlowView()
                } label: {
                    settingsNavigationLabel(titleKey: "about.title")
                }
            } header: {
                Text("settings.section.about")
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
        .animation(.easeInOut(duration: 0.27), value: appNumeralSystem)
    }

    @ViewBuilder
    var wcaSettingsSection: some View {
        Section {
            if wcaAuth.isSignedIn {
                Button {
                    wcaDestination = .account
                } label: {
                    wcaStatusCard(showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)

                Button {
                    wcaDestination = .myCompetitions
                } label: {
                    settingsActionNavigationLabel(titleKey: "settings.wca_my_competitions")
                }
                .buttonStyle(.plain)

                Button {
                    wcaDestination = .myResults
                } label: {
                    settingsActionNavigationLabel(titleKey: "settings.wca_my_results")
                }
                .buttonStyle(.plain)
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
                .padding(.vertical, 4)
                
                Button {
                    authenticateWithWCA()
                } label: {
                    HStack {
                        if wcaAuth.isSigningIn {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("settings.wca_sign_in")
                    }
                }
                .disabled(wcaAuth.isSigningIn)
            }
        } header: {
            Text("settings.section.wca")
        }
    }

    var wcaAccountSettingsList: some View {
        List {
            Section {
                wcaStatusCard(showsDisclosure: false)
                    .padding(.vertical, 4)
            }

            Section {
                Button("settings.wca_my_competitions") {
                    wcaDestination = .myCompetitions
                }

                Button("settings.wca_my_results") {
                    wcaDestination = .myResults
                }
            }

            Section {
                Button {
                    authenticateWithWCA()
                } label: {
                    HStack {
                        if wcaAuth.isSigningIn {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("settings.wca_refresh_profile")
                    }
                }
                .disabled(wcaAuth.isSigningIn)

                Button("settings.wca_sign_out", role: .destructive) {
                    wcaAuth.signOut()
                    wcaDestination = nil
                }
            } footer: {
                Text("settings.wca_sign_out_footer")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(appLocalizedString("settings.wca_title", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.inline)
    }

    var languageListRow: some View {
        HStack {
            Text("settings.language_label")

            Spacer()

            Menu {
                ForEach(appLanguageOptions()) { language in
                    Button {
                        appLanguage = language.id
                    } label: {
                        Text(verbatim: language.nativeName)
                        Text(appLocalizedString(language.displayNameKey, languageCode: appLanguage))
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(verbatim: currentLanguageOption.nativeName)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
        }
    }

    var appIconListRow: some View {
        listSettingsMenuRow(
            titleKey: "settings.app_icon",
            selectedKey: (AppIconOption(rawValue: selectedAppIcon) ?? .red).localizedKey
        ) {
            ForEach(AppIconOption.allCases) { option in
                Button(option.localizedKey) {
                    applyAppIcon(option)
                }
            }
        }
    }

    private var appNumeralSettingsRows: [AppNumeralSettingsRow] {
        var rows: [AppNumeralSettingsRow] = [.numeralSystem]
        if selectedNumeralSystem(for: .app)?.isChinese == true {
            rows += [.chineseFinancial, .chineseNumberFormat, .chineseDecimalStyle]
        }
        return rows
    }

    private func appNumeralSettingsListRow(_ row: AppNumeralSettingsRow) -> AnyView {
        switch row {
        case .numeralSystem:
            AnyView(numeralSystemMenuRow(for: .app))
        case .chineseFinancial:
            AnyView(Toggle(
                localizedNumeralSetting("settings.numeral_financial", fallback: "Financial"),
                isOn: numeralFinancialBinding(for: .app)
            ))
        case .chineseNumberFormat:
            AnyView(chineseNumberFormatMenuRow(for: .app))
        case .chineseDecimalStyle:
            AnyView(chineseDecimalStyleMenuRow(for: .app))
        }
    }

    private func chineseNumeralRows(for scope: NumeralScope) -> [TimerCustomizationListRow] {
        guard selectedNumeralSystem(for: scope)?.isChinese == true else { return [] }
        return [
            .chineseFinancial(scope),
            .chineseNumberFormat(scope),
            .chineseDecimalStyle(scope)
        ]
    }

    private func numeralSystemMenuRow(for scope: NumeralScope) -> some View {
        let rawSelection = numeralSystemBinding(for: scope).wrappedValue
        return HStack {
            Text(localizedNumeralSetting(numeralScopeTitleKey(scope), fallback: numeralScopeFallback(scope)))
            Spacer()
            Menu {
                if scope != .app {
                    Button {
                        withAnimation(.easeInOut(duration: 0.27)) {
                            numeralSystemBinding(for: scope).wrappedValue = NumeralPreferenceKeys.inheritedRawValue
                        }
                    } label: {
                        numeralMenuLabel(
                            title: localizedNumeralSetting("settings.numeral_app", fallback: "App Numerals"),
                            preview: numeralPreview(for: .app)
                        )
                    }
                }
                ForEach(NumeralSystem.allCases) { system in
                    Button {
                        withAnimation(.easeInOut(duration: 0.27)) {
                            numeralSystemBinding(for: scope).wrappedValue = system.rawValue
                        }
                    } label: {
                        numeralMenuLabel(
                            title: localizedNumeralSystem(system),
                            preview: numeralPreview(for: system, scope: scope)
                        )
                    }
                }
            } label: {
                timerCustomizationMenuValue(localizedNumeralSelection(rawSelection, scope: scope))
            }
            .tint(.secondary)
        }
    }

    private func chineseNumberFormatMenuRow(for scope: NumeralScope) -> some View {
        let binding = numeralNumberFormatBinding(for: scope)
        let selected = ChineseNumeralNumberFormat(rawValue: binding.wrappedValue) ?? .digits
        return HStack {
            Text(localizedNumeralSetting("settings.numeral_number_format", fallback: "Number Format"))
            Spacer()
            Menu {
                ForEach(ChineseNumeralNumberFormat.allCases) { format in
                    Button(localizedChineseNumberFormat(format)) {
                        binding.wrappedValue = format.rawValue
                    }
                }
            } label: {
                timerCustomizationMenuValue(localizedChineseNumberFormat(selected))
            }
            .tint(.secondary)
        }
    }

    private func chineseDecimalStyleMenuRow(for scope: NumeralScope) -> some View {
        let binding = numeralDecimalStyleBinding(for: scope)
        let selected = ChineseNumeralDecimalStyle(rawValue: binding.wrappedValue) ?? .period
        return HStack {
            Text(localizedNumeralSetting("settings.numeral_decimal_style", fallback: "Decimal Style"))
            Spacer()
            Menu {
                ForEach(ChineseNumeralDecimalStyle.allCases) { style in
                    Button(localizedChineseDecimalStyle(style)) {
                        binding.wrappedValue = style.rawValue
                    }
                }
            } label: {
                timerCustomizationMenuValue(localizedChineseDecimalStyle(selected))
            }
            .tint(.secondary)
        }
    }

    private func numeralSystemBinding(for scope: NumeralScope) -> Binding<String> {
        switch scope {
        case .app: $appNumeralSystem
        case .timer: $timerNumeralSystem
        case .statistics: $statisticsNumeralSystem
        }
    }

    private func numeralFinancialBinding(for scope: NumeralScope) -> Binding<Bool> {
        switch scope {
        case .app: $appNumeralChineseFinancial
        case .timer: $timerNumeralChineseFinancial
        case .statistics: $statisticsNumeralChineseFinancial
        }
    }

    private func numeralNumberFormatBinding(for scope: NumeralScope) -> Binding<String> {
        switch scope {
        case .app: $appNumeralChineseNumberFormat
        case .timer: $timerNumeralChineseNumberFormat
        case .statistics: $statisticsNumeralChineseNumberFormat
        }
    }

    private func numeralDecimalStyleBinding(for scope: NumeralScope) -> Binding<String> {
        switch scope {
        case .app: $appNumeralChineseDecimalStyle
        case .timer: $timerNumeralChineseDecimalStyle
        case .statistics: $statisticsNumeralChineseDecimalStyle
        }
    }

    private func selectedNumeralSystem(for scope: NumeralScope) -> NumeralSystem? {
        NumeralSystem(rawValue: numeralSystemBinding(for: scope).wrappedValue)
    }

    private func localizedNumeralSelection(_ rawValue: String, scope: NumeralScope) -> String {
        if scope != .app, rawValue == NumeralPreferenceKeys.inheritedRawValue {
            return localizedNumeralSetting("settings.numeral_app", fallback: "App Numerals")
        }
        return localizedNumeralSystem(NumeralSystem(rawValue: rawValue) ?? .systemDefault)
    }

    private func localizedNumeralSystem(_ system: NumeralSystem) -> String {
        localizedNumeralSetting(system.localizationKey, fallback: system.defaultTitle)
    }

    private func numeralMenuLabel(title: String, preview: String) -> some View {
        Text(verbatim: "\(preview)   \(title)")
    }

    private func numeralPreview(for scope: NumeralScope) -> String {
        NumeralPresentation.presentNumericText(
            "12",
            scope: scope,
            preferences: numeralPreferencesSnapshot
        )
    }

    private func numeralPreview(for system: NumeralSystem, scope: NumeralScope) -> String {
        switch system {
        case .simplifiedChinese:
            return "贰"
        case .traditionalChinese:
            return "貳"
        default:
            break
        }

        let preference = NumeralScopePreference(
            system: system,
            chineseOptions: ChineseNumeralOptions(
                financial: numeralFinancialBinding(for: scope).wrappedValue,
                numberFormat: ChineseNumeralNumberFormat(
                    rawValue: numeralNumberFormatBinding(for: scope).wrappedValue
                ) ?? .digits,
                decimalStyle: ChineseNumeralDecimalStyle(
                    rawValue: numeralDecimalStyleBinding(for: scope).wrappedValue
                ) ?? .period
            )
        )
        return NumeralPresentation.presentNumericText(
            "12",
            scope: .app,
            preferences: NumeralPreferencesSnapshot(
                app: preference,
                timerOverride: nil,
                statisticsOverride: nil
            )
        )
    }

    private func localizedChineseNumberFormat(_ format: ChineseNumeralNumberFormat) -> String {
        localizedNumeralSetting(
            format == .digits ? "settings.numeral_digits" : "settings.numeral_chinese_numerals",
            fallback: format == .digits ? "Digits" : "Chinese Numerals"
        )
    }

    private func localizedChineseDecimalStyle(_ style: ChineseNumeralDecimalStyle) -> String {
        localizedNumeralSetting(
            style == .period ? "settings.numeral_period" : "settings.numeral_chinese_decimal",
            fallback: style == .period ? "Period" : "Chinese Decimal"
        )
    }

    private func numeralScopeTitleKey(_ scope: NumeralScope) -> String {
        switch scope {
        case .app: "settings.numeral_app"
        case .timer: "settings.numeral_timer"
        case .statistics: "settings.numeral_statistics"
        }
    }

    private func numeralScopeFallback(_ scope: NumeralScope) -> String {
        switch scope {
        case .app: "App Numerals"
        case .timer: "Timer Numerals"
        case .statistics: "Statistics Numerals"
        }
    }

    private func localizedNumeralSetting(_ key: String, fallback: String) -> String {
        appLocalizedString(key, languageCode: appLanguage, defaultValue: fallback)
    }

    private var numeralPreferencesSnapshot: NumeralPreferencesSnapshot {
        NumeralPreferencesSnapshot(
            app: storedNumeralPreference(for: .app) ?? NumeralPreferencesSnapshot.defaults.app,
            timerOverride: storedNumeralPreference(for: .timer),
            statisticsOverride: storedNumeralPreference(for: .statistics)
        )
    }

    private func storedNumeralPreference(for scope: NumeralScope) -> NumeralScopePreference? {
        guard let system = selectedNumeralSystem(for: scope) else { return nil }
        return NumeralScopePreference(
            system: system,
            chineseOptions: ChineseNumeralOptions(
                financial: numeralFinancialBinding(for: scope).wrappedValue,
                numberFormat: ChineseNumeralNumberFormat(
                    rawValue: numeralNumberFormatBinding(for: scope).wrappedValue
                ) ?? .digits,
                decimalStyle: ChineseNumeralDecimalStyle(
                    rawValue: numeralDecimalStyleBinding(for: scope).wrappedValue
                ) ?? .period
            )
        )
    }

    var timerTabAppearanceSettingsList: some View {
        let previewStreak = timerPreviewStreak
        return List {
            Section {
                VStack(spacing: 24) {
                    TimerCustomizationPreview(
                        arrangement: resolvedTimerArrangement,
                        minimalMode: timerMinimalMode,
                        splitOrder: resolvedTimerSplitOrder,
                        scramblePosition: timerScrambleVerticalPosition,
                        backgroundAppearance: timerBackgroundAppearance,
                        backgroundImageData: timerBackgroundImageData,
                        timerAppearance: timerTextAppearance,
                        scrambleAppearance: scrambleTextAppearance,
                        statisticsAppearance: averageTextAppearance,
                        timerFontDesign: resolvedFontDesignOption(timerTextFontDesign),
                        timerFontStyle: resolvedTimerPreviewFontStyle,
                        timerFontSize: timerTextFontSize,
                        scrambleFontDesign: resolvedFontDesignOption(scrambleTextFontDesign),
                        scrambleFontStyle: resolvedScramblePreviewFontStyle,
                        scrambleFontSize: scrambleTextFontSize,
                        statisticsFontDesign: resolvedFontDesignOption(averageTextFontDesign),
                        statisticsFontStyle: resolvedStatisticsPreviewFontStyle,
                        statisticsFontSize: averageTextFontSize,
                        numeralPreferences: numeralPreferencesSnapshot,
                        statistics: timerPreviewStatistics,
                        cardsStatisticsConfiguration: resolvedCardsStatisticsConfiguration,
                        diagramPlacement: previewDiagramPlacement,
                        diagramSize: resolvedDrawScrambleFloatingSize,
                        showsNextScrambleButton: showNextScrambleButton,
                        streakCount: previewStreak.count,
                        isTodaySolved: previewStreak.isTodaySolved
                    )
                    .layoutPriority(1)

                    Rectangle()
                        .fill(Color(.separator))
                        .frame(maxWidth: .infinity)
                        .frame(height: 0.5)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                Text(localizedTimerCustomization("settings.timer_live_preview", fallback: "Live Preview"))
            }

            timerCustomizationLowerRegion
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
        .animation(.easeInOut(duration: 0.27), value: timerCustomizationPath)
        .animation(.easeInOut(duration: 0.27), value: timerArrangement)
        .animation(.easeInOut(duration: 0.27), value: timerMinimalMode)
        .animation(.easeInOut(duration: 0.27), value: selectedTimerStatistics)
        .animation(.easeInOut(duration: 0.27), value: selectedScrambleColorPuzzle)
        .animation(.easeInOut(duration: 0.27), value: timerNumeralSystem)
        .animation(.easeInOut(duration: 0.27), value: statisticsNumeralSystem)
        .onChange(of: timerMinimalMode) { isEnabled in
            guard isEnabled else { return }
            switch currentTimerCustomizationPage {
            case .statisticsStyle, .statistics, .scrambleDiagram, .scrambleDiagramColors:
                withAnimation(.easeInOut(duration: 0.27)) {
                    timerCustomizationPath.removeAll()
                }
            default:
                break
            }
        }
        .navigationTitle(Text(appLocalizedString("settings.timer_tab", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.large)
        .onDisappear {
            timerCustomizationPath.removeAll()
        }
    }

    private var currentTimerCustomizationPage: TimerCustomizationPage {
        timerCustomizationPath.last ?? .root
    }

    private var resolvedTimerArrangement: TimerArrangement {
        TimerArrangement.resolved(storedRawValue: timerArrangement)
    }

    private var resolvedTimerSplitOrder: TimerSplitOrder {
        TimerSplitOrder.resolved(
            storedRawValue: timerSplitOrder,
            legacyArrangementRawValue: timerArrangement
        )
    }

    private var selectedTimerStatistics: [TimerStatisticMetric] {
        TimerStatisticSelection.resolved(
            arrangement: resolvedTimerArrangement,
            sharedStoredValue: timerStatisticsSelection,
            classicStoredValue: timerClassicStatisticsSelection,
            cardsStoredValue: timerCardsStatisticsSelection,
            legacyDisplayOption: AverageDisplayOption(rawValue: averageDisplayOption) ?? .ao5AndAo12
        )
    }

    private var resolvedCardsTwoStatisticsArrangement: TimerCardsTwoStatisticArrangement {
        TimerCardsTwoStatisticArrangement(rawValue: timerCardsTwoStatisticsArrangement) ?? .vertical
    }

    private var resolvedCardsThreeStatisticsArrangement: TimerCardsThreeStatisticArrangement {
        TimerCardsThreeStatisticArrangement(rawValue: timerCardsThreeStatisticsArrangement) ?? .topEmphasis
    }

    private var resolvedCardsStatisticsConfiguration: TimerCardsStatisticsConfiguration {
        TimerCardsStatisticsConfiguration.resolve(
            selectedMetrics: TimerStatisticSelection.resolved(
                arrangement: .cards,
                sharedStoredValue: timerStatisticsSelection,
                classicStoredValue: timerClassicStatisticsSelection,
                cardsStoredValue: timerCardsStatisticsSelection,
                legacyDisplayOption: AverageDisplayOption(rawValue: averageDisplayOption) ?? .ao5AndAo12
            ),
            twoArrangement: resolvedCardsTwoStatisticsArrangement,
            threeArrangement: resolvedCardsThreeStatisticsArrangement,
            positionStore: TimerCardsPositionStore.decode(timerCardsStatisticsPositions)
        )
    }

    private var previewDiagramPlacement: DrawScramblePlacement {
        DrawScramblePlacement(rawValue: drawScramblePlacement) ?? .inline
    }

    private var resolvedDrawScrambleFloatingSize: Double {
        TimerCustomizationDefaults.resolvedDrawScrambleSize(drawScrambleFloatingSize)
    }

    private var resolvedTimerPreviewFontStyle: TimerFontStyleOption {
        resolvedFontDesignOption(timerTextFontDesign).resolvedStyle(
            rawValue: timerTextFontWeight,
            preferredLegacyWeight: .semibold
        )
    }

    private var resolvedScramblePreviewFontStyle: TimerFontStyleOption {
        resolvedFontDesignOption(scrambleTextFontDesign).resolvedStyle(
            rawValue: scrambleTextFontWeight,
            preferredLegacyWeight: .medium
        )
    }

    private var resolvedStatisticsPreviewFontStyle: TimerFontStyleOption {
        resolvedFontDesignOption(averageTextFontDesign).resolvedStyle(
            rawValue: averageTextFontWeight,
            preferredLegacyWeight: .medium
        )
    }

    private var timerPreviewStatistics: [TimerStatisticDisplayItem] {
        selectedTimerStatistics.map { metric in
            let rawValue: String = switch metric {
            case .mean: "10.68"
            case .best: "8.92"
            case .mo3: "10.41"
            case .ao5: "10.24"
            case .ao12: "10.71"
            case .ao50: "11.03"
            case .ao100: "11.18"
            case .solveCount: "128"
            }
            return TimerStatisticDisplayItem(
                metric: metric,
                title: appLocalizedString(metric.localizedKey, languageCode: appLanguage, defaultValue: metric.defaultTitle),
                value: NumeralPresentation.presentNumericText(
                    rawValue,
                    scope: .statistics,
                    preferences: numeralPreferencesSnapshot
                )
            )
        }
    }

    private var timerPreviewStreak: (count: Int, isTodaySolved: Bool) {
        let calendar = Calendar.current
        let solvedDays = Set(solves.map { calendar.startOfDay(for: $0.date) })
        let today = calendar.startOfDay(for: Date())
        let isTodaySolved = solvedDays.contains(today)
        var day = isTodaySolved
            ? today
            : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var count = 0
        while solvedDays.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return (count, isTodaySolved)
    }

    @ViewBuilder
    private var timerCustomizationLowerRegion: some View {
        Group {
            timerCustomizationLayoutSection
            timerCustomizationStyleSection
            timerCustomizationComponentsSection
        }
    }

    @ViewBuilder
    private var timerCustomizationLayoutSection: some View {
        Section {
            ForEach(timerCustomizationLayoutRows) { row in
                TimerCustomizationListRowHost(content: timerCustomizationListRow(row))
                    .transition(.opacity)
            }
        } header: {
            Text(localizedTimerCustomization("settings.timer_customization_layout", fallback: "Layout"))
        } footer: {
            if currentTimerCustomizationPage == .scramblePosition {
                Text(localizedTimerCustomization(
                    "settings.timer_scramble_position_help",
                    fallback: "Long scrambles expand around this preferred position without changing it."
                ))
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var timerCustomizationStyleSection: some View {
        Section {
            ForEach(timerCustomizationStyleRows) { row in
                TimerCustomizationListRowHost(content: timerCustomizationListRow(row))
                    .transition(.opacity)
            }
        } header: {
            Text(localizedTimerCustomization("settings.timer_customization_style", fallback: "Style"))
        }
    }

    @ViewBuilder
    private var timerCustomizationComponentsSection: some View {
        Section {
            ForEach(timerCustomizationComponentsRows) { row in
                TimerCustomizationListRowHost(content: timerCustomizationListRow(row))
                    .transition(.opacity)
            }
        } header: {
            Text(localizedTimerCustomization("settings.timer_customization_components", fallback: "Components"))
        } footer: {
            if currentTimerCustomizationPage == .statistics {
                Text(localizedTimerCustomization(
                    "settings.timer_statistics_help",
                    fallback: "Choose which existing session statistics appear on the Timer."
                ))
                .transition(.opacity)
            }
        }
    }

    private var timerCustomizationLayoutRows: [TimerCustomizationListRow] {
        if activeTimerCustomizationPage(in: .layout) != nil {
            return [.back(.layout), .scramblePositionEditor]
        }

        var rows: [TimerCustomizationListRow] = []
        if !timerMinimalMode {
            rows.append(.arrangement)
            if resolvedTimerArrangement == .split {
                rows.append(.splitOrder)
            }
        }
        rows.append(.navigation(.scramblePosition))
        rows.append(.minimalMode)
        return rows
    }

    private var timerCustomizationStyleRows: [TimerCustomizationListRow] {
        if let page = activeTimerCustomizationPage(in: .style) {
            var rows: [TimerCustomizationListRow] = [.back(.style), .appearanceEditor(page)]
            let numeralScope: NumeralScope? = switch page {
            case .timerStyle: .timer
            case .statisticsStyle: .statistics
            default: nil
            }
            if let numeralScope {
                rows.append(.numeralSystem(numeralScope))
                rows += chineseNumeralRows(for: numeralScope)
            }
            return rows
        }

        var rows: [TimerCustomizationListRow] = [
            .navigation(.backgroundStyle),
            .navigation(.timerStyle),
            .navigation(.scrambleStyle)
        ]
        if !timerMinimalMode {
            rows.append(.navigation(.statisticsStyle))
        }
        return rows
    }

    private var timerCustomizationComponentsRows: [TimerCustomizationListRow] {
        switch activeTimerCustomizationPage(in: .components) {
        case .statistics:
            var rows = [.back(.components)]
                + TimerStatisticMetric.allCases.map(TimerCustomizationListRow.statistic)
            if resolvedTimerArrangement == .cards {
                if selectedTimerStatistics.count == 2 || selectedTimerStatistics.count == 3 {
                    rows.append(.cardsStatisticsArrangement)
                }
                if (2...4).contains(selectedTimerStatistics.count) {
                    rows.append(.cardsPositionsHeader)
                    rows += resolvedCardsStatisticsConfiguration.positionedMetrics.indices.map(
                        TimerCustomizationListRow.cardsStatisticSlot
                    )
                }
            }
            return rows

        case .scrambleDiagram:
            var rows: [TimerCustomizationListRow] = [.back(.components), .diagramPlacement, .diagramSize]
            rows.append(.navigation(.scrambleDiagramColors))
            return rows

        case .scrambleDiagramColors:
            return [
                .back(.components),
                .colorPuzzle,
                .colorPreview
            ] + selectedScrambleColorPuzzle.faceLabels.indices.map(TimerCustomizationListRow.colorFace) + [
                .colorHelp,
                .colorReset
            ]

        default:
            var rows: [TimerCustomizationListRow] = []
            if !timerMinimalMode {
                rows += [.navigation(.statistics), .navigation(.scrambleDiagram)]
            }
            rows.append(.nextScrambleToggle)
            return rows
        }
    }

    private func timerCustomizationListRow(_ row: TimerCustomizationListRow) -> AnyView {
        switch row {
        case .arrangement:
            return AnyView(timerArrangementMenuRow)

        case .splitOrder:
            return AnyView(timerSplitOrderMenuRow)

        case .minimalMode:
            return AnyView(Toggle(
                localizedTimerCustomization("settings.timer_minimal_mode", fallback: "Minimal Mode"),
                isOn: $timerMinimalMode
            ))

        case .navigation(let page):
            return timerCustomizationNavigationListRow(for: page)

        case .nextScrambleToggle:
            return AnyView(Toggle(
                localizedTimerCustomization("settings.timer_show_next_scramble", fallback: "Show Next Scramble Button"),
                isOn: $showNextScrambleButton
            ))

        case .back:
            return AnyView(timerCustomizationBackRow)

        case .scramblePositionEditor:
            return AnyView(timerScramblePositionEditorRow)

        case .appearanceEditor(let page):
            return AnyView(
                timerCustomizationAppearanceEditor(for: page)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(settingsCardBackgroundFillColor)
            )

        case .statistic(let metric):
            return AnyView(Toggle(
                localizedTimerCustomization(metric.localizedKey, fallback: metric.defaultTitle),
                isOn: timerStatisticSelectionBinding(metric)
            )
            .disabled(isTimerStatisticDisabled(metric)))

        case .cardsStatisticsArrangement:
            return AnyView(timerCardsStatisticsArrangementMenuRow)

        case .cardsPositionsHeader:
            return AnyView(Text(localizedTimerCustomization(
                "settings.timer_statistics_positions",
                fallback: "Positions"
            ))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary))

        case .cardsStatisticSlot(let index):
            return AnyView(timerCardsStatisticSlotRow(index: index))

        case .diagramPlacement:
            if resolvedTimerArrangement.allowsIndependentDiagramPlacement {
                return AnyView(timerDiagramPlacementMenuRow)
            }
            return AnyView(HStack {
                Text(localizedTimerCustomization("settings.draw_scramble_position", fallback: "Position"))
                Spacer()
                Text(localizedTimerCustomization(
                    "settings.timer_diagram_arrangement_controlled",
                    fallback: "Controlled by Arrangement"
                ))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            })

        case .diagramSize:
            return AnyView(VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("settings.draw_scramble_size")
                    Spacer()
                    timerCustomizationResetButton(
                        isDisabled: abs(resolvedDrawScrambleFloatingSize - TimerCustomizationDefaults.drawScrambleSize) < 0.5
                    ) {
                        drawScrambleFloatingSize = TimerCustomizationDefaults.drawScrambleSize
                    }
                    Text("\(Int(resolvedDrawScrambleFloatingSize.rounded()))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $drawScrambleFloatingSize, in: TimerCustomizationDefaults.drawScrambleSizeRange, step: 1)
            })

        case .colorPuzzle:
            return AnyView(timerScrambleColorPuzzleMenuRow)

        case .colorPreview:
            return AnyView(
                ScrambleColorPreviewStrip(colors: scrambleDiagramColorScheme.colors(for: selectedScrambleColorPuzzle))
                    .padding(.vertical, 4)
            )

        case .colorFace(let index):
            guard selectedScrambleColorPuzzle.faceLabels.indices.contains(index) else {
                return AnyView(EmptyView())
            }
            return AnyView(ColorPicker(
                selection: scrambleColorBinding(for: selectedScrambleColorPuzzle, index: index),
                supportsOpacity: false
            ) {
                Text(selectedScrambleColorPuzzle.faceLabels[index])
            })

        case .colorHelp:
            return AnyView(Text(selectedScrambleColorPuzzle.helpText)
                .font(.footnote)
                .foregroundStyle(.secondary))

        case .colorReset:
            return AnyView(Button("settings.draw_scramble_colors_reset", role: .destructive) {
                scrambleDiagramColorScheme = .default
            })

        case .numeralSystem(let scope):
            return AnyView(numeralSystemMenuRow(for: scope))

        case .chineseFinancial(let scope):
            return AnyView(Toggle(
                localizedNumeralSetting("settings.numeral_financial", fallback: "Financial"),
                isOn: numeralFinancialBinding(for: scope)
            ))

        case .chineseNumberFormat(let scope):
            return AnyView(chineseNumberFormatMenuRow(for: scope))

        case .chineseDecimalStyle(let scope):
            return AnyView(chineseDecimalStyleMenuRow(for: scope))
        }
    }

    private func timerCustomizationNavigationListRow(for page: TimerCustomizationPage) -> AnyView {
        switch page {
        case .scramblePosition:
            return AnyView(timerCustomizationNavigationRow(
                title: localizedTimerCustomization("settings.timer_scramble_position", fallback: "Scramble Text Position"),
                destination: page
            ))
        case .backgroundStyle:
            return AnyView(timerCustomizationNavigationRow(
                title: localizedTimerCustomization("settings.timer_bg_label", fallback: "Background"),
                destination: page
            ))
        case .timerStyle:
            return AnyView(timerCustomizationNavigationRow(
                title: localizedTimerCustomization("settings.timer_text_label", fallback: "Timer"),
                destination: page
            ))
        case .scrambleStyle:
            return AnyView(timerCustomizationNavigationRow(
                title: localizedTimerCustomization("settings.scramble_text_label", fallback: "Scramble"),
                destination: page
            ))
        case .statisticsStyle:
            return AnyView(timerCustomizationNavigationRow(
                title: localizedTimerCustomization("settings.timer_statistics", fallback: "Statistics"),
                destination: page
            ))
        case .statistics:
            return AnyView(timerCustomizationNavigationRow(
                title: localizedTimerCustomization("settings.timer_statistics", fallback: "Statistics"),
                value: "\(selectedTimerStatistics.count)",
                destination: page
            ))
        case .scrambleDiagram:
            return AnyView(timerCustomizationNavigationRow(
                title: localizedTimerCustomization("settings.timer_scramble_diagram", fallback: "Scramble Diagram"),
                destination: page
            ))
        case .scrambleDiagramColors:
            return AnyView(timerCustomizationNavigationRow(
                title: localizedTimerCustomization("settings.draw_scramble_colors", fallback: "Colors"),
                destination: page
            ))
        case .root:
            return AnyView(EmptyView())
        }
    }

    @ViewBuilder
    private var timerCustomizationBackRow: some View {
        Button {
            navigateBackInTimerCustomization()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text(localizedTimerCustomization("settings.timer_customization_back", fallback: "Back"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var timerScramblePositionEditorRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localizedTimerCustomization("settings.timer_scramble_position", fallback: "Scramble Text Position"))
                Spacer()
                Text("\(Int((Double(TimerArrangementLayout.normalizedScramblePosition(timerScrambleVerticalPosition)) * 100).rounded()))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $timerScrambleVerticalPosition, in: 0...1)
            HStack {
                Text(localizedTimerCustomization("settings.timer_scramble_position_top", fallback: "Top"))
                Spacer()
                Text(localizedTimerCustomization("settings.timer_scramble_position_timer", fallback: "Near Timer"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func timerCustomizationAppearanceEditor(for page: TimerCustomizationPage) -> AnyView {
        switch page {
        case .backgroundStyle:
            return appearanceEditorCard(
                titleKey: "settings.timer_bg_label",
                configuration: $timerBackgroundAppearance,
                photoData: $timerBackgroundImageData,
                allowsPhoto: true,
                showsContainerBackground: false
            )

        case .timerStyle:
            return appearanceEditorCard(
                titleKey: "settings.timer_text_label",
                configuration: $timerTextAppearance,
                fontSize: $timerTextFontSize,
                fontSizeTitleKey: "settings.timer_text_size",
                defaultFontSize: 64,
                fontDesign: $timerTextFontDesign,
                fontDesignTarget: .timerFontDesign,
                defaultFontDesign: TimerFontDesignOption.default.rawValue,
                fontStyle: $timerTextFontWeight,
                fontStyleTarget: .timerFontWeight,
                defaultFontStyle: TimerFontWeightOption.semibold.rawValue,
                previewKind: .timer,
                showsContainerBackground: false
            )

        case .scrambleStyle:
            return appearanceEditorCard(
                titleKey: "settings.scramble_text_label",
                configuration: $scrambleTextAppearance,
                fontSize: $scrambleTextFontSize,
                fontSizeTitleKey: "settings.scramble_text_size",
                defaultFontSize: 20,
                fontSizeMaximum: 45,
                fontDesign: $scrambleTextFontDesign,
                fontDesignTarget: .scrambleFontDesign,
                defaultFontDesign: TimerFontDesignOption.default.rawValue,
                fontStyle: $scrambleTextFontWeight,
                fontStyleTarget: .scrambleFontWeight,
                defaultFontStyle: TimerFontWeightOption.medium.rawValue,
                previewKind: .scramble,
                scrambleDisplayMode: $scrambleDisplayMode,
                showsContainerBackground: false
            )

        case .statisticsStyle:
            return appearanceEditorCard(
                titleKey: "settings.timer_statistics",
                configuration: $averageTextAppearance,
                fontSize: $averageTextFontSize,
                fontSizeTitleKey: "settings.average_text_size",
                defaultFontSize: 20,
                fontSizeMaximum: 56,
                fontSizeIsAutomatic: resolvedTimerArrangement == .cards,
                fontDesign: $averageTextFontDesign,
                fontDesignTarget: .averageFontDesign,
                defaultFontDesign: TimerFontDesignOption.default.rawValue,
                fontStyle: $averageTextFontWeight,
                fontStyleTarget: .averageFontWeight,
                defaultFontStyle: TimerFontWeightOption.medium.rawValue,
                previewKind: .average,
                showsContainerBackground: false
            )

        default:
            return AnyView(EmptyView())
        }
    }

    private func activeTimerCustomizationPage(
        in section: TimerCustomizationSection
    ) -> TimerCustomizationPage? {
        let page = currentTimerCustomizationPage
        return page.section == section ? page : nil
    }

    private var timerDiagramPlacementMenuRow: some View {
        let selected = independentDiagramPlacement
        return HStack {
            Text(localizedTimerCustomization("settings.draw_scramble_position", fallback: "Position"))
            Spacer()
            Menu {
                ForEach([DrawScramblePlacement.bottomLeft, .bottomCenter, .bottomRight, .off]) { placement in
                    Button(placement.localizedKey) {
                        drawScramblePlacement = placement.rawValue
                    }
                }
            } label: {
                timerCustomizationMenuValue(localizedDiagramPlacement(selected))
            }
            .tint(.secondary)
        }
    }

    private var independentDiagramPlacement: DrawScramblePlacement {
        let placement = DrawScramblePlacement(rawValue: drawScramblePlacement) ?? .inline
        return placement.isFloating ? placement : .off
    }

    private func localizedDiagramPlacement(_ placement: DrawScramblePlacement) -> String {
        let key: String = switch placement {
        case .inline: "settings.draw_scramble_position_inline"
        case .bottomLeft: "settings.draw_scramble_position_bottom_left"
        case .bottomRight: "settings.draw_scramble_position_bottom_right"
        case .bottomCenter: "settings.draw_scramble_position_bottom_center"
        case .off: "settings.draw_scramble_position_off"
        }
        return appLocalizedString(key, languageCode: appLanguage)
    }

    private var timerScrambleColorPuzzleMenuRow: some View {
        HStack {
            Text(localizedTimerCustomization("settings.draw_scramble_puzzle", fallback: "Puzzle"))
            Spacer()
            Menu {
                ForEach(ScrambleColorPuzzle.allCases) { puzzle in
                    Button(puzzle.title) {
                        withAnimation(.easeInOut(duration: 0.27)) {
                            selectedScrambleColorPuzzle = puzzle
                        }
                    }
                }
            } label: {
                timerCustomizationMenuValue(selectedScrambleColorPuzzle.title)
            }
            .tint(.secondary)
        }
    }

    private var timerArrangementMenuRow: some View {
        HStack {
            Text(localizedTimerCustomization("settings.timer_arrangement", fallback: "Arrangement"))
            Spacer()
            Menu {
                ForEach(TimerArrangement.allCases) { arrangement in
                    Button {
                        withAnimation(.easeInOut(duration: 0.27)) {
                            timerArrangement = arrangement.rawValue
                        }
                    } label: {
                        Text(localizedTimerArrangement(arrangement))
                    }
                }
            } label: {
                timerCustomizationMenuValue(localizedTimerArrangement(resolvedTimerArrangement))
            }
            .tint(.secondary)
        }
    }

    private var timerSplitOrderMenuRow: some View {
        HStack {
            Text(localizedTimerCustomization("settings.timer_split_order", fallback: "Component Order"))
            Spacer()
            Menu {
                ForEach(TimerSplitOrder.allCases) { order in
                    Button {
                        timerSplitOrder = order.rawValue
                    } label: {
                        Text(localizedTimerSplitOrder(order))
                    }
                }
            } label: {
                timerCustomizationMenuValue(localizedTimerSplitOrder(resolvedTimerSplitOrder))
            }
            .tint(.secondary)
        }
    }

    private var timerCardsStatisticsArrangementMenuRow: some View {
        HStack {
            Text(localizedTimerCustomization("settings.timer_statistics_arrangement", fallback: "Arrangement"))
            Spacer()
            if selectedTimerStatistics.count == 2 {
                Menu {
                    ForEach(TimerCardsTwoStatisticArrangement.allCases) { arrangement in
                        Button(localizedCardsTwoArrangement(arrangement)) {
                            timerCardsTwoStatisticsArrangement = arrangement.rawValue
                            normalizeCardsPositionStore()
                        }
                    }
                } label: {
                    timerCustomizationMenuValue(localizedCardsTwoArrangement(resolvedCardsTwoStatisticsArrangement))
                }
                .tint(.secondary)
            } else {
                Menu {
                    ForEach(TimerCardsThreeStatisticArrangement.allCases) { arrangement in
                        Button(localizedCardsThreeArrangement(arrangement)) {
                            timerCardsThreeStatisticsArrangement = arrangement.rawValue
                            normalizeCardsPositionStore()
                        }
                    }
                } label: {
                    timerCustomizationMenuValue(localizedCardsThreeArrangement(resolvedCardsThreeStatisticsArrangement))
                }
                .tint(.secondary)
            }
        }
    }

    private func timerCardsStatisticSlotRow(index: Int) -> some View {
        let configuration = resolvedCardsStatisticsConfiguration
        let keys = configuration.layout.slotLocalizationKeys
        let metric = configuration.positionedMetrics.indices.contains(index)
            ? configuration.positionedMetrics[index]
            : nil
        return HStack {
            Text(localizedTimerCustomization(
                keys.indices.contains(index) ? keys[index] : "settings.timer_statistics_positions",
                fallback: "Position"
            ))
            Spacer()
            if let metric {
                Menu {
                    ForEach(configuration.selectedMetrics) { candidate in
                        Button(localizedTimerCustomization(candidate.localizedKey, fallback: candidate.defaultTitle)) {
                            var store = TimerCardsPositionStore.decode(timerCardsStatisticsPositions)
                            store = store.assigning(
                                metric: candidate,
                                to: index,
                                layout: configuration.layout,
                                selectedMetrics: configuration.selectedMetrics
                            )
                            timerCardsStatisticsPositions = store.encoded()
                        }
                    }
                } label: {
                    timerCustomizationMenuValue(localizedTimerCustomization(
                        metric.localizedKey,
                        fallback: metric.defaultTitle
                    ))
                }
                .tint(.secondary)
            }
        }
    }

    private func localizedCardsTwoArrangement(_ arrangement: TimerCardsTwoStatisticArrangement) -> String {
        localizedTimerCustomization(
            arrangement == .vertical ? "settings.timer_cards_vertical" : "settings.timer_cards_horizontal",
            fallback: arrangement == .vertical ? "Vertical" : "Horizontal"
        )
    }

    private func localizedCardsThreeArrangement(_ arrangement: TimerCardsThreeStatisticArrangement) -> String {
        localizedTimerCustomization(
            arrangement == .topEmphasis ? "settings.timer_cards_top_emphasis" : "settings.timer_cards_bottom_emphasis",
            fallback: arrangement == .topEmphasis ? "Top Emphasis" : "Bottom Emphasis"
        )
    }

    private func timerCustomizationMenuValue(_ value: String) -> some View {
        HStack(spacing: 5) {
            Text(value)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.secondary)
    }

    private func timerCustomizationResetButton(
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button("common.reset", action: action)
            .font(.system(size: 14, weight: .medium))
            .compatibleProminentButtonFromIOS16(tint: .blue)
            .controlSize(.small)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.45 : 1)
    }

    private func timerCustomizationNavigationRow(
        title: String,
        value: String? = nil,
        destination: TimerCustomizationPage
    ) -> some View {
        Button {
            navigateForwardInTimerCustomization(to: destination)
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if let value {
                    Text(value)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func navigateForwardInTimerCustomization(to page: TimerCustomizationPage) {
        withAnimation(.easeInOut(duration: 0.27)) {
            if currentTimerCustomizationPage.section == page.section {
                timerCustomizationPath.append(page)
            } else {
                timerCustomizationPath = [page]
            }
        }
    }

    private func navigateBackInTimerCustomization() {
        guard !timerCustomizationPath.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.27)) {
            _ = timerCustomizationPath.removeLast()
        }
    }

    private func localizedTimerArrangement(_ arrangement: TimerArrangement) -> String {
        localizedTimerCustomization(arrangement.localizedKey, fallback: arrangement.defaultTitle)
    }

    private func localizedTimerSplitOrder(_ order: TimerSplitOrder) -> String {
        localizedTimerCustomization(order.localizedKey, fallback: order.defaultTitle)
    }

    private func migrateTimerArrangementPreferencesIfNeeded() {
        let legacyArrangement = timerArrangement
        let migration = TimerArrangementMigration.resolve(
            storedArrangement: legacyArrangement,
            minimalMode: timerMinimalMode,
            completed: timerMinimalArrangementMigrationCompleted
        )
        let migratedArrangement = migration.arrangement
        let migratedOrder = TimerSplitOrder.resolved(
            storedRawValue: timerSplitOrder,
            legacyArrangementRawValue: legacyArrangement
        )
        if timerArrangement != migratedArrangement.rawValue {
            timerArrangement = migratedArrangement.rawValue
        }
        if timerSplitOrder != migratedOrder.rawValue {
            timerSplitOrder = migratedOrder.rawValue
        }
        if timerMinimalMode != migration.minimalMode {
            timerMinimalMode = migration.minimalMode
        }
        if timerMinimalArrangementMigrationCompleted != migration.completed {
            timerMinimalArrangementMigrationCompleted = migration.completed
        }
        let normalizedPosition = Double(
            TimerArrangementLayout.normalizedScramblePosition(timerScrambleVerticalPosition)
        )
        if timerScrambleVerticalPosition != normalizedPosition {
            timerScrambleVerticalPosition = normalizedPosition
        }
        let normalizedDiagramSize = TimerCustomizationDefaults.resolvedDrawScrambleSize(drawScrambleFloatingSize)
        if drawScrambleFloatingSize != normalizedDiagramSize {
            drawScrambleFloatingSize = normalizedDiagramSize
        }
        let migratedClassicStatistics = TimerStatisticSelection.migratedClassicStoredValue(
            sharedStoredValue: timerStatisticsSelection,
            classicStoredValue: timerClassicStatisticsSelection,
            legacyDisplayOption: AverageDisplayOption(rawValue: averageDisplayOption) ?? .ao5AndAo12
        )
        if timerClassicStatisticsSelection != migratedClassicStatistics {
            timerClassicStatisticsSelection = migratedClassicStatistics
        }
        let migratedCardsStatistics = TimerStatisticSelection.migratedCardsStoredValue(
            cardsStoredValue: timerCardsStatisticsSelection,
            legacyDisplayOption: AverageDisplayOption(rawValue: averageDisplayOption) ?? .ao5AndAo12
        )
        if timerCardsStatisticsSelection != migratedCardsStatistics {
            timerCardsStatisticsSelection = migratedCardsStatistics
        }
        normalizeCardsPositionStore()
    }

    private func localizedTimerCustomization(_ key: String, fallback: String) -> String {
        appLocalizedString(key, languageCode: appLanguage, defaultValue: fallback)
    }

    private func timerStatisticSelectionBinding(_ metric: TimerStatisticMetric) -> Binding<Bool> {
        Binding {
            selectedTimerStatistics.contains(metric)
        } set: { isSelected in
            let metrics = TimerStatisticSelection.updating(
                selectedTimerStatistics,
                metric: metric,
                isSelected: isSelected,
                arrangement: resolvedTimerArrangement
            )
            let stored = TimerStatisticMetric.storedValue(for: metrics)
            if resolvedTimerArrangement == .classic {
                timerClassicStatisticsSelection = stored
            } else if resolvedTimerArrangement == .cards {
                timerCardsStatisticsSelection = stored
                normalizeCardsPositionStore(selectedMetrics: metrics)
            } else {
                timerStatisticsSelection = stored
            }
        }
    }

    private func isTimerStatisticDisabled(_ metric: TimerStatisticMetric) -> Bool {
        let maximumCount = TimerStatisticSelection.maximumCount(for: resolvedTimerArrangement)
        return maximumCount != nil
            && !selectedTimerStatistics.contains(metric)
            && selectedTimerStatistics.count >= (maximumCount ?? .max)
    }

    private func normalizeCardsPositionStore(selectedMetrics: [TimerStatisticMetric]? = nil) {
        let metrics = selectedMetrics ?? TimerStatisticSelection.resolved(
            arrangement: .cards,
            sharedStoredValue: timerStatisticsSelection,
            classicStoredValue: timerClassicStatisticsSelection,
            cardsStoredValue: timerCardsStatisticsSelection,
            legacyDisplayOption: AverageDisplayOption(rawValue: averageDisplayOption) ?? .ao5AndAo12
        )
        let layout = TimerCardsStatisticsLayout.resolved(
            count: metrics.count,
            two: resolvedCardsTwoStatisticsArrangement,
            three: resolvedCardsThreeStatisticsArrangement
        )
        let normalized = TimerCardsPositionStore.decode(timerCardsStatisticsPositions)
            .normalizing(layout: layout, selectedMetrics: metrics)
            .encoded()
        if timerCardsStatisticsPositions != normalized {
            timerCardsStatisticsPositions = normalized
        }
    }

    var competitionTabAppearanceSettingsList: some View {
        List {
            Section {
                listSettingsMenuRow(
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

            if CompetitionCardStyleOption(rawValue: competitionCardStyle) == .glass {
                appearanceEditorSection {
                    appearanceEditorCard(
                        titleKey: "settings.competitions_bg_label",
                        configuration: $competitionsBackgroundAppearance,
                        photoData: $competitionsBackgroundImageData,
                        allowsPhoto: true
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: competitionCardStyle)
        .navigationTitle(Text(appLocalizedString("settings.competition_tab", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.inline)
    }

    var timerSolvingSettingsList: some View {
        List {
            Section {
                Toggle("settings.wca_inspection", isOn: $wcaInspectionEnabled)

                listSettingsMenuRow(
                    titleKey: "settings.inspection_alert",
                    selectedKey: InspectionAlertVoiceMode(rawValue: inspectionAlertVoiceMode)?.localizedKey ?? "settings.inspection_alert_off"
                ) {
                    ForEach(InspectionAlertVoiceMode.allCases) { mode in
                        Button(mode.localizedKey) {
                            inspectionAlertVoiceMode = mode.rawValue
                        }
                    }
                }

                Toggle("settings.hide_elements_when_solving", isOn: $hideElementsWhenSolving)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(appLocalizedString("settings.wca_inspection", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.inline)
    }

    var timerDisplaySettingsList: some View {
        List {
            Section {
                listSettingsMenuRow(
                    titleKey: "settings.timer_updating",
                    selectedKey: TimerUpdatingMode(rawValue: timerUpdatingMode)?.localizedKey ?? "settings.timer_updating_on"
                ) {
                    ForEach(TimerUpdatingMode.allCases) { mode in
                        Button(mode.localizedKey) {
                            timerUpdatingMode = mode.rawValue
                        }
                    }
                }

                listSettingsMenuRow(
                    titleKey: "settings.timer_accuracy",
                    selectedKey: SolveTimeAccuracy(rawValue: timerAccuracy)?.localizedKey ?? "settings.timer_accuracy_001"
                ) {
                    ForEach(SolveTimeAccuracy.allCases) { accuracy in
                        Button(accuracy.localizedKey) {
                            timerAccuracy = accuracy.rawValue
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(appLocalizedString("settings.timer_updating", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.inline)
    }

    var timerInputSettingsList: some View {
        List {
            Section {
                listSettingsMenuRow(
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

                Toggle(isOn: $ganShowResultPopup) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("settings.result_popup")
                        Text("settings.result_popup_help")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if enteringTimesWith == TimeEntryMode.gan.rawValue {
                Section {
                    ganTimerConnectionRow

                    if let deviceName = ganTimer.deviceName, !deviceName.isEmpty {
                        HStack {
                            Text("settings.gan_device")
                            Spacer()
                            Text(deviceName)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle(isOn: $ganInspectionStartsOnPress) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("settings.gan_inspection_on_press")
                            Text("settings.gan_inspection_on_press_help")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    listSettingsMenuRow(
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
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("settings.gan_timer")
                }
            }

            if enteringTimesWith == TimeEntryMode.smartCube.rawValue {
                Section {
                    NavigationLink {
                        SmartCubeLabView()
                    } label: {
                        settingsNavigationLabel(titleKey: "smart_cube.title")
                    }
                } header: {
                    Text("smart_cube.section")
                } footer: {
                    Text("smart_cube.timer_settings_footer")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(appLocalizedString("settings.entering_times_with", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.inline)
    }

    func scrambleColorBinding(for puzzle: ScrambleColorPuzzle, index: Int) -> Binding<Color> {
        Binding {
            let colors = scrambleDiagramColorScheme.colors(for: puzzle)
            let fallback = ScrambleColorConfiguration.default.colors(for: puzzle)
            return Color(scrambleHex: colors.indices.contains(index) ? colors[index] : fallback[index])
        } set: { newColor in
            var colors = scrambleDiagramColorScheme.colors(for: puzzle)
            guard colors.indices.contains(index) else { return }
            colors[index] = newColor.scrambleHexString()
            scrambleDiagramColorScheme.setColors(colors, for: puzzle)
        }
    }

    var ganTimerConnectionRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("settings.gan_timer")
                Text(LocalizedStringKey(ganTimer.statusLocalizedKey))
                    .font(.footnote)
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
                }
            }
            .buttonStyle(.bordered)
        }
    }

    func appearanceEditorSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Section {
            content()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }

    func settingsNavigationLabel(
        titleKey: LocalizedStringKey,
        valueKey: LocalizedStringKey? = nil
    ) -> some View {
        HStack {
            Text(titleKey)
            Spacer()
            if let valueKey {
                Text(valueKey)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func listSettingsMenuRow<Content: View>(
        titleKey: LocalizedStringKey,
        selectedKey: LocalizedStringKey? = nil,
        selectedText: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(titleKey)

            Spacer()

            Menu {
                content()
            } label: {
                HStack(spacing: 6) {
                    if let selectedKey {
                        Text(selectedKey)
                            .foregroundStyle(.secondary)
                    } else if let selectedText {
                        Text(selectedText)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
        }
    }

    var ganDevicePickerSheet: some View {
        CompatibleNavigationContainer {
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
            .navigationTitle(Text(appLocalizedString("settings.gan_choose_device", languageCode: appLanguage)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel") {
                        ganTimer.stopScanning()
                        showingGANDevicePicker = false
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(appLocalizedString("common.refresh", languageCode: appLanguage, defaultValue: "Refresh")) {
                        ganTimer.startDeviceDiscovery()
                    }
                }
            }
            .onAppear {
                ganTimer.startDeviceDiscovery()
            }
        }
        .compatibleMediumLargeSheet()
    }

    func wcaStatusCard(showsDisclosure: Bool) -> some View {
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

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
    }

    func settingsActionNavigationLabel(titleKey: LocalizedStringKey) -> some View {
        HStack {
            Text(titleKey)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .contentShape(Rectangle())
    }

    var importDataRow: some View {
        Button {
            showingImportPicker = true
        } label: {
            HStack {
                HStack(spacing: 6) {
                    Text("settings.import_data")

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
                        .compatiblePopoverCompactAdaptation()
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
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

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
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
                        .compatibleTintedGlassFromIOS16(.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        .compatibleTintedGlassFromIOS16(.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .frame(width: 248, alignment: .leading)
            .compatiblePopoverCompactAdaptation()
        }
        .fileExporter(
            isPresented: $showingExportPicker,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportDefaultFilename
        ) { result in
            if case .failure(let error) = result {
                importExportAlertMessage = appUserFacingErrorMessage(error, languageCode: appLanguage)
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
                    .foregroundStyle(Color(.tertiaryLabel))
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
                wcaAlertMessage = appUserFacingErrorMessage(error, languageCode: appLanguage)
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
                    appIconAlertMessage = appUserFacingErrorMessage(error, languageCode: appLanguage)
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
                sessions: Array(sessions),
                solves: solves
            )
            exportDocument = package.document
            exportContentType = package.contentType
            exportDefaultFilename = package.defaultFilename
            showingExportPicker = true
        } catch {
            importExportAlertMessage = appUserFacingErrorMessage(error, languageCode: appLanguage)
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
                    importExportAlertMessage = appUserFacingErrorMessage(error, languageCode: appLanguage)
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
                    importExportAlertMessage = appUserFacingErrorMessage(error, languageCode: appLanguage)
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
        try modelContext.fetchSolvesSortedByDateDescending()
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
        fontSizeMaximum: Double = 96,
        fontSizeIsAutomatic: Bool = false,
        fontDesign: Binding<String>? = nil,
        fontDesignTarget: AppearanceSelectionTarget? = nil,
        defaultFontDesign: String? = nil,
        fontStyle: Binding<String>? = nil,
        fontStyleTarget: AppearanceSelectionTarget? = nil,
        defaultFontStyle: String? = nil,
        previewKind: TextAppearancePreviewKind? = nil,
        scrambleDisplayMode: Binding<String>? = nil,
        photoData: Binding<Data?>? = nil,
        allowsPhoto: Bool = false,
        showsContainerBackground: Bool = true
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
                   let photoData {
                    Divider()
                    appearancePhotoRow(photoData: photoData)
                }

                if let fontSize, let fontSizeTitleKey, let defaultFontSize {
                    Divider()
                    if fontSizeIsAutomatic {
                        HStack {
                            Text(fontSizeTitleKey)
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                            Text(localizedTimerCustomization("settings.timer_size_automatic", fallback: "Automatic"))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    } else {
                        appearanceFontSizeRow(
                            titleKey: fontSizeTitleKey,
                            value: fontSize,
                            defaultValue: defaultFontSize,
                            maximumValue: fontSizeMaximum
                        )
                    }
                }

                if let scrambleDisplayMode {
                    Divider()
                    scrambleDisplayModeRow(value: scrambleDisplayMode)
                }

                if let fontDesign, let defaultFontDesign {
                    Divider()
                    appearanceFontDesignRow(
                        value: fontDesign,
                        target: fontDesignTarget ?? .timerFontDesign,
                        defaultValue: defaultFontDesign
                    )
                }

                if let fontStyle, let defaultFontStyle {
                    Divider()
                    appearanceFontStyleRow(
                        value: fontStyle,
                        target: fontStyleTarget ?? .timerFontWeight,
                        defaultValue: defaultFontStyle
                    )
                }

                if let previewKind, let fontSize, let fontDesign, let fontStyle {
                    let design = resolvedFontDesignOption(fontDesign.wrappedValue)
                    let preferredWeight = preferredLegacyWeight(for: fontStyleTarget ?? .timerFontWeight)
                    Divider()
                    appearancePreviewRow(
                        kind: previewKind,
                        configuration: configuration.wrappedValue,
                        fontSize: fontSize.wrappedValue,
                        fontDesign: design,
                        fontStyle: design.resolvedStyle(
                            rawValue: fontStyle.wrappedValue,
                            preferredLegacyWeight: preferredWeight
                        )
                    )
                }

            }
            .background {
                if showsContainerBackground {
                    settingsCardBackground
                }
            }
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
        photoData: Binding<Data?>
    ) -> some View {
        Group {
            if #available(iOS 16.0, *) {
                AppearancePhotoPickerRow(photoData: photoData)
            } else {
                HStack {
                    Text("settings.timer_bg_photo")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    Text("iOS 16+")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    func appearanceFontSizeRow(
        titleKey: LocalizedStringKey,
        value: Binding<Double>,
        defaultValue: Double,
        maximumValue: Double = 96
    ) -> AnyView {
        let clampedValue = Binding<Double>(
            get: { min(max(value.wrappedValue, 12), maximumValue) },
            set: { value.wrappedValue = min(max($0, 12), maximumValue) }
        )

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(titleKey)
                        .font(.system(size: 16, weight: .medium))

                    Spacer()

                    timerCustomizationResetButton(
                        isDisabled: abs(clampedValue.wrappedValue - min(defaultValue, maximumValue)) < 0.5
                    ) {
                        value.wrappedValue = min(defaultValue, maximumValue)
                    }

                    Text("\(Int(clampedValue.wrappedValue.rounded()))")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: clampedValue, in: 12...maximumValue, step: 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        )
    }

    func scrambleDisplayModeRow(value: Binding<String>) -> AnyView {
        return AnyView(
            settingsMenuRow(
                titleKey: "settings.scramble_display_mode",
                selectedKey: (ScrambleDisplayMode(rawValue: value.wrappedValue) ?? .shrinkFont).localizedKey
            ) {
                ForEach(ScrambleDisplayMode.allCases) { mode in
                    Button(mode.localizedKey) {
                        value.wrappedValue = mode.rawValue
                    }
                }
            }
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
                    fontDesignMenuLabel(resolvedFontDesignOption(value.wrappedValue))
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

    func appearanceFontStyleRow(
        value: Binding<String>,
        target: AppearanceSelectionTarget,
        defaultValue: String
    ) -> AnyView {
        let design = fontDesignOption(forStyleTarget: target)
        let styles = design.availableStyles(preferredLegacyWeight: preferredLegacyWeight(for: target))
        let selectedStyle = design.resolvedStyle(
            rawValue: value.wrappedValue,
            preferredLegacyWeight: preferredLegacyWeight(for: target)
        )
        return AnyView(
            Button {
                appearanceSelectionTarget = target
            } label: {
                HStack {
                    Text("settings.font_style_label")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    fontStyleMenuLabel(selectedStyle, design: design)
                    if styles.count > 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(styles.count <= 1)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        )
    }

    @ViewBuilder
    func fontDesignMenuLabel(_ option: TimerFontDesignOption) -> some View {
        if option.isAvailable {
            let style = option.resolvedStyle(rawValue: "regular", preferredLegacyWeight: .regular)
            Text(option.localizedKey)
                .font(option.font(size: 15, style: style))
                .compatibleFontWidth(option)
        } else {
            Text(option.localizedKey)
                .font(.system(size: 15, weight: .regular))
        }
    }

    var orderedFontDesignOptions: [TimerFontDesignOption] {
        TimerFontDesignOption.availableOptions
    }

    func resolvedFontDesignOption(_ rawValue: String) -> TimerFontDesignOption {
        TimerFontDesignOption.resolvedAvailableOption(rawValue: rawValue)
    }

    func normalizeUnavailableFontSelections() {
        let timer = resolvedFontDesignOption(timerTextFontDesign).rawValue
        let scramble = resolvedFontDesignOption(scrambleTextFontDesign).rawValue
        let average = resolvedFontDesignOption(averageTextFontDesign).rawValue
        if timer != timerTextFontDesign { timerTextFontDesign = timer }
        if scramble != scrambleTextFontDesign { scrambleTextFontDesign = scramble }
        if average != averageTextFontDesign { averageTextFontDesign = average }
        normalizeFontStyleSelection(for: .timerFontWeight)
        normalizeFontStyleSelection(for: .scrambleFontWeight)
        normalizeFontStyleSelection(for: .averageFontWeight)
    }

    @ViewBuilder
    func fontStyleMenuLabel(_ option: TimerFontStyleOption, design: TimerFontDesignOption) -> some View {
        Text(option.name)
            .font(design.font(size: 15, style: option))
            .compatibleFontWidth(design)
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

    func fontDesignOption(forStyleTarget target: AppearanceSelectionTarget) -> TimerFontDesignOption {
        switch target {
        case .timerFontWeight:
            return resolvedFontDesignOption(timerTextFontDesign)
        case .scrambleFontWeight:
            return resolvedFontDesignOption(scrambleTextFontDesign)
        case .averageFontWeight:
            return resolvedFontDesignOption(averageTextFontDesign)
        case .timerFontDesign, .scrambleFontDesign, .averageFontDesign:
            return .default
        }
    }

    func preferredLegacyWeight(for target: AppearanceSelectionTarget) -> TimerFontWeightOption {
        target == .timerFontWeight ? .semibold : .medium
    }

    func normalizeFontStyleSelection(for target: AppearanceSelectionTarget) {
        let design = fontDesignOption(forStyleTarget: target)
        let binding = fontWeightBinding(for: target)
        let resolved = design.resolvedStyle(
            rawValue: binding.wrappedValue,
            preferredLegacyWeight: preferredLegacyWeight(for: target)
        )
        if binding.wrappedValue != resolved.id {
            binding.wrappedValue = resolved.id
        }
    }

    func styleTarget(forDesignTarget target: AppearanceSelectionTarget) -> AppearanceSelectionTarget? {
        switch target {
        case .timerFontDesign: return .timerFontWeight
        case .scrambleFontDesign: return .scrambleFontWeight
        case .averageFontDesign: return .averageFontWeight
        case .timerFontWeight, .scrambleFontWeight, .averageFontWeight: return nil
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
            CompatibleNavigationContainer {
                List {
                    ForEach(orderedFontDesignOptions) { option in
                        Button {
                            selectFontDesign(option, for: target)
                        } label: {
                            HStack {
                                fontDesignMenuLabel(option)
                                Spacer()
                                if option.isAvailable,
                                   fontDesignBinding(for: target).wrappedValue == option.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.tint)
                                } else {
                                    fontDownloadAccessory(for: option)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button("common.reset") {
                        fontDesignBinding(for: target).wrappedValue = TimerFontDesignOption.default.rawValue
                        if let styleTarget = styleTarget(forDesignTarget: target) {
                            normalizeFontStyleSelection(for: styleTarget)
                        }
                        appearanceSelectionTarget = nil
                    }
                    .disabled(fontDesignBinding(for: target).wrappedValue == TimerFontDesignOption.default.rawValue)
                }
                .navigationTitle(appLocalizedString("settings.font_design_label", languageCode: appLanguage))
                .navigationBarTitleDisplayMode(.inline)
            }
            .compatibleMediumLargeSheet()

        case .timerFontWeight, .scrambleFontWeight, .averageFontWeight:
            let design = fontDesignOption(forStyleTarget: target)
            let styles = design.availableStyles(preferredLegacyWeight: preferredLegacyWeight(for: target))
            let selectedStyle = design.resolvedStyle(
                rawValue: fontWeightBinding(for: target).wrappedValue,
                preferredLegacyWeight: preferredLegacyWeight(for: target)
            )
            CompatibleNavigationContainer {
                List {
                    ForEach(styles) { option in
                        Button {
                            fontWeightBinding(for: target).wrappedValue = option.id
                            appearanceSelectionTarget = nil
                        } label: {
                            HStack {
                                fontStyleMenuLabel(option, design: design)
                                Spacer()
                                if selectedStyle.id == option.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button("common.reset") {
                        let defaultStyle = design.resolvedStyle(
                            rawValue: defaultFontWeightValue(for: target),
                            preferredLegacyWeight: preferredLegacyWeight(for: target)
                        )
                        fontWeightBinding(for: target).wrappedValue = defaultStyle.id
                        appearanceSelectionTarget = nil
                    }
                    .disabled(selectedStyle.id == design.resolvedStyle(
                        rawValue: defaultFontWeightValue(for: target),
                        preferredLegacyWeight: preferredLegacyWeight(for: target)
                    ).id)
                }
                .navigationTitle(appLocalizedString("settings.font_style_label", languageCode: appLanguage, defaultValue: "Font Style"))
                .navigationBarTitleDisplayMode(.inline)
            }
            .compatibleMediumSheet()
        }
    }

    private func selectFontDesign(
        _ option: TimerFontDesignOption,
        for target: AppearanceSelectionTarget
    ) {
        if option.isAvailable {
            applyFontDesign(option, for: target)
            return
        }

#if canImport(UIKit)
        guard option.isSystemDownloadable else { return }
        fontDownloadManager.start(option)
#endif
    }

    @ViewBuilder
    private func fontDownloadAccessory(for option: TimerFontDesignOption) -> some View {
        switch fontDownloadManager.state(for: option) {
        case .downloading(let progress):
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .accessibilityLabel(
                        Text("Downloading ") + Text(option.localizedKey)
                    )
                    .accessibilityValue("\(Int(progress * 100)) percent")
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(
                        Text("Downloading ") + Text(option.localizedKey)
                    )
            }

        case .failed:
            Label("Retry", systemImage: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)

        case .downloaded:
            EmptyView()

        case nil:
            if option.isSystemDownloadable {
                Label("Download", systemImage: "icloud.and.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func applyFontDesign(
        _ option: TimerFontDesignOption,
        for target: AppearanceSelectionTarget
    ) {
        fontDesignBinding(for: target).wrappedValue = option.rawValue
        if let styleTarget = styleTarget(forDesignTarget: target) {
            normalizeFontStyleSelection(for: styleTarget)
        }
        appearanceSelectionTarget = nil
    }

    func appearancePreviewRow(
        kind: TextAppearancePreviewKind,
        configuration: AppearanceConfiguration,
        fontSize: Double,
        fontDesign: TimerFontDesignOption,
        fontStyle: TimerFontStyleOption
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
                        fontStyle: fontStyle
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
        fontStyle: TimerFontStyleOption
    ) -> some View {
        let base = text
            .font(fontDesign.font(size: fontSize, style: fontStyle))
            .compatibleFontWidth(fontDesign)

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
                    .compatibleGlassFromIOS16(in: Capsule())
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


private struct ScrambleColorPreviewStrip: View {
    let colors: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, hex in
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(scrambleHex: hex))
                    .frame(height: 32)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color(.separator).opacity(0.45), lineWidth: 0.5)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CacheSettingsView: View {
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    @State private var report = AppCacheReport.empty
    @State private var isClearing = false
    @State private var pendingClearTarget: CacheClearTarget?
    @State private var alertMessageKey: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("settings.cache_total")
                            .font(.system(size: 16, weight: .semibold))

                        Text(AppCacheManager.formattedSize(report.totalBytes))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Spacer()

                    if isClearing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("settings.cache_description")
            }

            Section {
                cacheActionRow(
                    target: .competitionList,
                    sizeText: AppCacheManager.formattedSize(report.competitionListBytes)
                )
                cacheActionRow(
                    target: .competitionSupport,
                    sizeText: AppCacheManager.formattedSize(report.competitionSupportBytes)
                )
                cacheActionRow(
                    target: .competitionDetails,
                    sizeText: AppCacheManager.formattedSize(report.competitionDetailBytes)
                )
                cacheActionRow(
                    target: .topCubers,
                    sizeText: AppCacheManager.formattedSize(report.competitionTopCubersBytes)
                )
            } header: {
                Text("settings.cache_section_competitions")
            }

            Section {
                cacheActionRow(
                    target: .wcaResults,
                    sizeText: AppCacheManager.formattedSize(report.wcaResultsBytes)
                )
            } header: {
                Text("settings.cache_section_wca")
            }

            Section {
                Button(role: .destructive) {
                    pendingClearTarget = .all
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: CacheClearTarget.all.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 26)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(LocalizedStringKey(CacheClearTarget.all.titleKey))
                                .font(.system(size: 16, weight: .semibold))
                            Text(LocalizedStringKey(CacheClearTarget.all.detailKey))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .disabled(isClearing)
            } footer: {
                Text("settings.cache_clear_all_footer")
            }
        }
        .navigationTitle(Text("settings.cache_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshReport()
        }
        .refreshable {
            await refreshReport()
        }
        .confirmationDialog(
            appLocalizedString("settings.cache_clear_confirm_title", languageCode: appLanguage),
            isPresented: Binding(
                get: { pendingClearTarget != nil },
                set: { newValue in
                    if !newValue {
                        pendingClearTarget = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingClearTarget {
                Button(appLocalizedString(pendingClearTarget.clearButtonKey, languageCode: appLanguage), role: .destructive) {
                    Task {
                        await clear(pendingClearTarget)
                    }
                }
            }
            Button("common.cancel", role: .cancel) {
                pendingClearTarget = nil
            }
        } message: {
            Text("settings.cache_clear_confirm_message")
        }
        .alert(
            appLocalizedString("settings.cache_title", languageCode: appLanguage),
            isPresented: Binding(
                get: { alertMessageKey != nil },
                set: { newValue in
                    if !newValue {
                        alertMessageKey = nil
                    }
                }
            )
        ) {
            Button("common.done", role: .cancel) {
                alertMessageKey = nil
            }
        } message: {
            Text(LocalizedStringKey(alertMessageKey ?? "settings.cache_cleared_message"))
        }
    }

    private func cacheActionRow(target: CacheClearTarget, sizeText: String) -> some View {
        Button {
            pendingClearTarget = target
        } label: {
            HStack(spacing: 12) {
                Image(systemName: target.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(target.tint)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(target.titleKey))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(LocalizedStringKey(target.detailKey))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                Text(sizeText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isClearing)
    }

    @MainActor
    private func clear(_ target: CacheClearTarget) async {
        pendingClearTarget = nil
        isClearing = true
        defer {
            isClearing = false
        }

        switch target {
        case .competitionList:
            await AppCacheManager.clearCompetitionListCache()
        case .competitionSupport:
            await AppCacheManager.clearCompetitionSupportCache()
        case .competitionDetails:
            await AppCacheManager.clearCompetitionDetailCache()
        case .topCubers:
            await AppCacheManager.clearCompetitionTopCubersCache()
        case .wcaResults:
            await AppCacheManager.clearWCAResultsCache()
        case .all:
            await AppCacheManager.clearAllCaches()
        }
        alertMessageKey = "settings.cache_cleared_message"
        await refreshReport()
    }

    @MainActor
    private func refreshReport() async {
        let currentReport = await Task.detached(priority: .utility) {
            AppCacheManager.currentReport()
        }.value
        report = currentReport
    }
}

private enum CacheClearTarget: Identifiable, Hashable {
    case competitionList
    case competitionSupport
    case competitionDetails
    case topCubers
    case wcaResults
    case all

    var id: String { titleKey }

    var titleKey: String {
        switch self {
        case .competitionList: return "settings.cache_competition_list"
        case .competitionSupport: return "settings.cache_competition_support"
        case .competitionDetails: return "settings.cache_competition_details"
        case .topCubers: return "settings.cache_top_cubers"
        case .wcaResults: return "settings.cache_wca_results"
        case .all: return "settings.cache_clear_all"
        }
    }

    var detailKey: String {
        switch self {
        case .competitionList: return "settings.cache_competition_list_detail"
        case .competitionSupport: return "settings.cache_competition_support_detail"
        case .competitionDetails: return "settings.cache_competition_details_detail"
        case .topCubers: return "settings.cache_top_cubers_detail"
        case .wcaResults: return "settings.cache_wca_results_detail"
        case .all: return "settings.cache_clear_all_detail"
        }
    }

    var clearButtonKey: String {
        switch self {
        case .all:
            return "settings.cache_clear_all"
        default:
            return "settings.cache_clear_button"
        }
    }

    var systemImage: String {
        switch self {
        case .competitionList: return "list.bullet.rectangle"
        case .competitionSupport: return "globe.asia.australia"
        case .competitionDetails: return "doc.text.magnifyingglass"
        case .topCubers: return "trophy"
        case .wcaResults: return "person.text.rectangle"
        case .all: return "trash"
        }
    }

    var tint: Color {
        switch self {
        case .competitionList: return .blue
        case .competitionSupport: return .green
        case .competitionDetails: return .orange
        case .topCubers: return .yellow
        case .wcaResults: return .indigo
        case .all: return .red
        }
    }
}

private enum WCASettingsDestination: String, Identifiable, Hashable {
    case account
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

private extension SolveTimeAccuracy {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .hundredths: "settings.timer_accuracy_01"
        case .thousandths: "settings.timer_accuracy_001"
        }
    }

}

private enum TimeEntryMode: String, CaseIterable, Identifiable {
    case timer
    case typing
    case gan
    case smartCube

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .timer: "settings.entering_times_timer"
        case .typing: "settings.entering_times_typing"
        case .gan: "settings.entering_times_gan"
        case .smartCube: "settings.entering_times_smart_cube"
        }
    }
}

private struct CompetitionCalculatorAttempt: Identifiable {
    let id = UUID()
    var timeText: String = ""
    var result: SolveResult = .solved

    var parsedBaseTime: Double? {
        guard result != .dnf else { return 0 }
        return Double(timeText)
    }

    var isComplete: Bool {
        switch result {
        case .dnf:
            return true
        case .solved, .plusTwo:
            return parsedBaseTime != nil
        }
    }
}

private enum CompetitionCalculatorMetrics {
    static func averageOfFive(for attempts: [CompetitionCalculatorAttempt]) -> Double? {
        guard attempts.count == 5 else { return nil }

        let adjustedTimes = attempts.map { attempt -> Double? in
            switch attempt.result {
            case .solved:
                return attempt.parsedBaseTime
            case .plusTwo:
                return attempt.parsedBaseTime.map { $0 + 2 }
            case .dnf:
                return nil
            }
        }

        return averageValue(adjustedTimes: adjustedTimes, trimmingCount: 1)
    }

    private static func averageValue(adjustedTimes: [Double?], trimmingCount: Int) -> Double? {
        guard !adjustedTimes.isEmpty else { return nil }
        guard trimmingCount >= 0, trimmingCount * 2 < adjustedTimes.count else { return nil }

        let ranked = adjustedTimes
            .map { adjusted -> (Double, Bool) in
                if let adjusted {
                    return (adjusted, false)
                }
                return (Double.greatestFiniteMagnitude, true)
            }
            .sorted { $0.0 < $1.0 }

        let trimmed = ranked.dropFirst(trimmingCount).dropLast(trimmingCount)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains(where: \.1) {
            return .nan
        }

        let total = trimmed.reduce(0) { $0 + $1.0 }
        return total / Double(trimmed.count)
    }
}

private struct CompetitionCalculatorSheet: View {
    let appLanguage: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.solveTimeAccuracy) private var solveTimeAccuracy
    @FocusState private var focusedAttemptID: UUID?
    @State private var attempts = Self.makeEmptyAttempts()

    private var enteredAttempts: [CompetitionCalculatorAttempt] {
        attempts.filter(\.isComplete)
    }

    private var currentAverageText: String {
        guard enteredAttempts.count == 5 else {
            return appLocalizedString("settings.competition_calculator_waiting", languageCode: appLanguage)
        }
        return SolveMetrics.formatAverage(
            CompetitionCalculatorMetrics.averageOfFive(for: enteredAttempts),
            decimals: solveTimeAccuracy.decimals
        )
    }

    private var bestPossibleAverageText: String? {
        guard enteredAttempts.count == 4 else { return nil }
        let bestAttempt = CompetitionCalculatorAttempt(timeText: "0.001", result: .solved)
        return SolveMetrics.formatAverage(
            CompetitionCalculatorMetrics.averageOfFive(for: enteredAttempts + [bestAttempt]),
            decimals: solveTimeAccuracy.decimals
        )
    }

    private var worstPossibleAverageText: String? {
        guard enteredAttempts.count == 4 else { return nil }
        let worstAttempt = CompetitionCalculatorAttempt(timeText: "", result: .dnf)
        return SolveMetrics.formatAverage(
            CompetitionCalculatorMetrics.averageOfFive(for: enteredAttempts + [worstAttempt]),
            decimals: solveTimeAccuracy.decimals
        )
    }

    var body: some View {
        CompatibleNavigationContainer {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("settings.competition_calculator_intro")
                            .font(.system(size: 15, weight: .medium))

                        Text("settings.competition_calculator_help")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }

                Section("settings.competition_calculator_attempts") {
                    ForEach($attempts) { $attempt in
                        HStack(spacing: 12) {
                            Text("\(attemptIndex(for: attempt.id) + 1).")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .leading)

                            TextField(
                                appLocalizedString("settings.competition_calculator_time_placeholder", languageCode: appLanguage),
                                text: $attempt.timeText
                            )
                            .keyboardType(.decimalPad)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .focused($focusedAttemptID, equals: attempt.id)
                            .disabled(attempt.result == .dnf)
                            .onChange(of: attempt.timeText) { newValue in
                                attempt.timeText = sanitizeTimeInput(newValue)
                            }

                            Picker("", selection: $attempt.result) {
                                Text("common.solved").tag(SolveResult.solved)
                                Text("+2").tag(SolveResult.plusTwo)
                                Text("common.dnf").tag(SolveResult.dnf)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("settings.competition_calculator_results") {
                    metricRow(
                        title: appLocalizedString("settings.competition_calculator_current_average", languageCode: appLanguage),
                        value: currentAverageText
                    )

                    if let bestPossibleAverageText, let worstPossibleAverageText {
                        metricRow(
                            title: appLocalizedString("settings.competition_calculator_bpa", languageCode: appLanguage),
                            value: bestPossibleAverageText
                        )

                        metricRow(
                            title: appLocalizedString("settings.competition_calculator_wpa", languageCode: appLanguage),
                            value: worstPossibleAverageText
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(appLocalizedString("settings.competition_calculator_title", languageCode: appLanguage))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.reset") {
                        attempts = Self.makeEmptyAttempts()
                        focusedAttemptID = nil
                    }
                }
            }
        }
    }

    private func attemptIndex(for id: UUID) -> Int {
        attempts.firstIndex { $0.id == id } ?? 0
    }

    private func sanitizeTimeInput(_ text: String) -> String {
        let filtered = text.filter { $0.isNumber || $0 == "." }
        let components = filtered.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count > 2 else { return filtered }
        return components.prefix(2).joined(separator: ".")
    }

    private static func makeEmptyAttempts() -> [CompetitionCalculatorAttempt] {
        (0..<5).map { _ in CompetitionCalculatorAttempt() }
    }

    @ViewBuilder
    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .medium))

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

@available(iOS 16.0, *)
private struct AppearancePhotoPickerRow: View {
    @Binding var photoData: Data?
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("settings.timer_bg_photo")
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                PhotosPicker(
                    selection: $photoItem,
                    matching: .images
                ) {
                    Text("settings.timer_bg_photo_button")
                        .font(.system(size: 15, weight: .medium))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .onChange(of: photoItem) { newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        photoData = data
                    }
                }
            }

            if photoData != nil {
                Divider()
                HStack {
                    Spacer()
                    Button("settings.timer_bg_photo_clear") {
                        photoData = nil
                        photoItem = nil
                    }
                    .font(.system(size: 14, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }
}

#endif
