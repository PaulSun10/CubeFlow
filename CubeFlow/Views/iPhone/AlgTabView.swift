import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif

#if os(iOS)
private let showsAlgTrainingEntrypoints = false

private struct AlgBottomAccessoryVisibilityActionKey: EnvironmentKey {
    static let defaultValue: (Bool) -> Void = { _ in }
}

private extension EnvironmentValues {
    var setAlgBottomAccessoryVisible: (Bool) -> Void {
        get { self[AlgBottomAccessoryVisibilityActionKey.self] }
        set { self[AlgBottomAccessoryVisibilityActionKey.self] = newValue }
    }
}

private struct AlgBottomAccessoryVisibilityModifier: ViewModifier {
    @Environment(\.setAlgBottomAccessoryVisible) private var setVisible
    let isVisible: Bool

    func body(content: Content) -> some View {
        content.onAppear {
            setVisible(isVisible)
        }
    }
}

private extension View {
    func algBottomAccessoryVisible(_ isVisible: Bool) -> some View {
        modifier(AlgBottomAccessoryVisibilityModifier(isVisible: isVisible))
    }
}

struct AlgsTabView: View {
    private let usesSystemBottomAccessory: Bool
    private let isActive: Bool
    @Binding private var isOverviewBottomAccessoryVisible: Bool
    @Binding private var searchRequestID: Int

    @State private var selectedPuzzle: AlgPuzzle = .threeByThree
    @State private var isShowingRecentPractice = false
    @State private var isShowingSearch = false
    @State private var isShowingTrainerHome = false
    @State private var recentPracticeNavigationContext: AlgRecentPracticeContext?
    @State private var overviewSearchItemsCache: [AlgSearchItem] = []
    @State private var overviewSearchItemsSignature = ""
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("algLearnedCasesStore") private var learnedCasesStore: String = "{}"
    @AppStorage("algBrowseViewModeStore") private var overviewBrowseViewModeStore: String = AlgBrowseViewMode.list.rawValue
    @AppStorage("algTrainerAttemptStore") private var trainerAttemptStore: String = "[]"
    @AppStorage("algDismissedRecentPracticeRecordID") private var dismissedRecentPracticeRecordID: String = ""

    init(
        usesSystemBottomAccessory: Bool = false,
        isActive: Bool = true,
        isOverviewBottomAccessoryVisible: Binding<Bool> = .constant(false),
        searchRequestID: Binding<Int> = .constant(0)
    ) {
        self.usesSystemBottomAccessory = usesSystemBottomAccessory
        self.isActive = isActive
        self._isOverviewBottomAccessoryVisible = isOverviewBottomAccessoryVisible
        self._searchRequestID = searchRequestID
    }

    private var sections: [AlgSectionData] {
        AlgSectionData.sections(for: selectedPuzzle)
    }

    private var overviewBrowseViewMode: AlgBrowseViewMode {
        algBrowseViewMode(setID: "global", storage: overviewBrowseViewModeStore)
    }

    private var overviewGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]
    }

    private var recentPracticeContext: AlgRecentPracticeContext? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let records = try? decoder.decode([AlgTrainerAttemptRecord].self, from: Data(trainerAttemptStore.utf8)),
              let latestRecord = records.sorted(by: { $0.timestamp > $1.timestamp }).first,
              let set = AlgLibrarySet(itemID: latestRecord.setID),
              let payload = AlgLibraryLoader.load(set) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = appLocale(for: appLanguage)
        formatter.dateFormat = appLocalizedString("algs.trainer.last_practiced_format", languageCode: appLanguage)

        let lastPracticedText = String(
            format: localizedAlgString(key: "algs.trainer.continue_subtitle_format", languageCode: appLanguage),
            formatter.string(from: latestRecord.timestamp)
        )

        if latestRecord.scopeID == latestRecord.setID {
            let title = AlgSectionData.allSections
                .flatMap(\.items)
                .first { $0.id.caseInsensitiveCompare(payload.set) == .orderedSame }
                .map { appLocalizedString("algs.item.\($0.id).title", languageCode: appLanguage, defaultValue: payload.set) } ?? payload.set

            return AlgRecentPracticeContext(
                id: latestRecord.scopeID,
                dismissToken: latestRecord.id,
                title: title,
                subtitle: lastPracticedText,
                destination: .set(payload)
            )
        }

        if let subset = orderedSubsets(from: payload.cases).first(where: { "\(payload.set)_\($0.id)" == latestRecord.scopeID }) {
            return AlgRecentPracticeContext(
                id: latestRecord.scopeID,
                dismissToken: latestRecord.id,
                title: localizedAlgSubgroup(subset.title, languageCode: appLanguage),
                subtitle: lastPracticedText,
                destination: .subset(payload, subset)
            )
        }

        return nil
    }

    private var weakPracticeItems: [AlgTrainerWeakReviewItem] {
        makeAlgTrainerWeakReviewItems(
            from: decodeAlgTrainerAttempts(from: trainerAttemptStore),
            languageCode: appLanguage
        )
    }

    var body: some View {
        Group {
            if isActive {
                activeContent
            } else {
                Color.clear
            }
        }
        .onChange(of: isActive) { newValue in
            guard usesSystemBottomAccessory else { return }
            if newValue {
                updateOverviewBottomAccessoryVisibility()
            } else {
                isOverviewBottomAccessoryVisible = false
            }
        }
    }

    private var activeContent: some View {
        CompatibleNavigationContainer {
            Group {
                if sections.isEmpty || overviewBrowseViewMode == .list {
                    overviewListContent
                } else {
                    overviewGridContent
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !usesSystemBottomAccessory && shouldShowOverviewBottomAccessory {
                    overviewBottomBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .compatibleNavigationDestination(isPresented: $isShowingRecentPractice) {
                if let context = recentPracticeNavigationContext {
                    recentPracticeDestinationView(for: context)
                }
            }
            .compatibleNavigationDestination(isPresented: $isShowingSearch) {
                AlgSearchView(items: overviewSearchItemsCache, languageCode: appLanguage)
            }
            .compatibleNavigationDestination(isPresented: $isShowingTrainerHome) {
                AlgTrainerHomeView()
            }
            .navigationTitle(Text(localizedAlgString(key: "tab.algs", languageCode: appLanguage)))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isShowingTrainerHome = true
                    } label: {
                        Text(localizedAlgString(key: "algs.trainer.action", languageCode: appLanguage))
                            .font(.system(size: 17, weight: .semibold))
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    puzzlePickerMenu
                }
            }
            .onAppear(perform: updateOverviewBottomAccessoryVisibility)
            .onDisappear {
                if usesSystemBottomAccessory {
                    isOverviewBottomAccessoryVisible = false
                }
            }
            .onChange(of: selectedPuzzle) { _ in
                overviewSearchItemsCache = []
                overviewSearchItemsSignature = ""
                updateOverviewBottomAccessoryVisibility()
            }
            .onChange(of: searchRequestID) { _ in
                guard usesSystemBottomAccessory else { return }
                showOverviewSearch()
            }
            .onChange(of: appLanguage) { _ in
                overviewSearchItemsCache = []
                overviewSearchItemsSignature = ""
            }
        }
        .environment(\.setAlgBottomAccessoryVisible) { isVisible in
            guard usesSystemBottomAccessory else { return }
            withAnimation(.smooth(duration: 0.22)) {
                isOverviewBottomAccessoryVisible = isVisible
            }
        }
    }

    private var shouldShowOverviewBottomAccessory: Bool {
        !sections.isEmpty
    }

    private var overviewBottomPadding: CGFloat {
        usesSystemBottomAccessory ? 24 : 88
    }

    private func updateOverviewBottomAccessoryVisibility() {
        guard usesSystemBottomAccessory else { return }
        withAnimation(.smooth(duration: 0.22)) {
            isOverviewBottomAccessoryVisible = shouldShowOverviewBottomAccessory
        }
    }

    private var overviewListContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if showsAlgTrainingEntrypoints,
                   let recentPracticeContext,
                   recentPracticeContext.dismissToken != dismissedRecentPracticeRecordID {
                    recentPracticeCard(recentPracticeContext)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                }

                if showsAlgTrainingEntrypoints && !weakPracticeItems.isEmpty {
                    NavigationLink {
                        AlgTrainerWeakReviewView(items: weakPracticeItems, languageCode: appLanguage)
                    } label: {
                        weakPracticeCard
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }

                if sections.isEmpty {
                    Text("algs.coming_soon")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            sectionHeader(section.localizedTitleKey)
                                .padding(.horizontal, 16)
                                .padding(.top, 6)
                                .padding(.bottom, 6)

                            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                NavigationLink {
                                    destinationView(for: item)
                                } label: {
                                    algRow(item)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)

                                if index < section.items.count - 1 {
                                    Divider()
                                        .padding(.leading, 84)
                                        .padding(.trailing, 16)
                                }
                            }
                        }
                    }

                    overviewSourceFooter
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }
            }
            .padding(.bottom, overviewBottomPadding)
        }
    }

    private var overviewGridContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if showsAlgTrainingEntrypoints,
                   let recentPracticeContext,
                   recentPracticeContext.dismissToken != dismissedRecentPracticeRecordID {
                    recentPracticeCard(recentPracticeContext)
                    .padding(.top, 10)
                    .padding(.horizontal, 16)
                }

                if showsAlgTrainingEntrypoints && !weakPracticeItems.isEmpty {
                    NavigationLink {
                        AlgTrainerWeakReviewView(items: weakPracticeItems, languageCode: appLanguage)
                    } label: {
                        weakPracticeCard
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 0)
                    .padding(.horizontal, 16)
                }

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader(section.localizedTitleKey)
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: overviewGridColumns, spacing: 12) {
                            ForEach(section.items) { item in
                                NavigationLink {
                                    destinationView(for: item)
                                } label: {
                                    algCard(item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                overviewSourceFooter
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }
            .padding(.bottom, overviewBottomPadding)
        }
    }

    private var overviewBottomBar: some View {
        AlgOverviewBottomBar(
            languageCode: appLanguage,
            browseViewModeSelection: overviewBrowseViewModeSelection,
            usesContainerGlass: true
        ) {
            showOverviewSearch()
        }
    }

    private var overviewSearchSignature: String {
        "\(appLanguage)|\(selectedPuzzle.rawValue)"
    }

    private func showOverviewSearch() {
        prepareOverviewSearchItemsIfNeeded()
        isShowingSearch = true
    }

    private func prepareOverviewSearchItemsIfNeeded() {
        let signature = overviewSearchSignature
        guard overviewSearchItemsSignature != signature || overviewSearchItemsCache.isEmpty else { return }
        overviewSearchItemsCache = makeOverviewSearchItems()
        overviewSearchItemsSignature = signature
    }

    private func sectionHeader(_ titleKey: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleKey)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)

            Divider()
        }
        .padding(.top, 0)
        .padding(.bottom, -6)
    }

    private var puzzlePickerMenu: some View {
        Menu {
            ForEach(AlgPuzzle.regularCases) { puzzle in
                Button(appLocalizedString(puzzle.localizedTitleKey, languageCode: appLanguage)) {
                    selectedPuzzle = puzzle
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(LocalizedStringKey(selectedPuzzle.localizedTitleKey))
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var overviewBrowseViewModeSelection: Binding<String> {
        Binding(
            get: { overviewBrowseViewMode.rawValue },
            set: { newValue in
                guard let mode = AlgBrowseViewMode(rawValue: newValue) else { return }
                overviewBrowseViewModeStore = updatedAlgBrowseViewModeStorage(storage: overviewBrowseViewModeStore, setID: "global", mode: mode)
            }
        )
    }

    @ViewBuilder
    private var overviewSourceFooter: some View {
        if let sourceURL = algPuzzleSourceURL(puzzle: selectedPuzzle.rawValue) {
            Text(sourceFooterText(for: sourceURL))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func sourceFooterText(for url: URL) -> String {
        String(
            format: localizedAlgString(key: "algs.source_format", languageCode: appLanguage),
            url.absoluteString
        )
    }

    private func algRow(_ item: AlgItemData) -> some View {
        HStack(spacing: 12) {
            overviewPreviewImage(for: item, imageHeight: 56, iconSize: 16)
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 17, weight: .regular))

                Text(subtitleText(for: item))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            progressIndicator(for: item)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func makeOverviewSearchItems() -> [AlgSearchItem] {
        var items: [AlgSearchItem] = []

        for section in sections {
            let sectionTitle = localizedAlgString(key: "algs.section.\(section.id)", languageCode: appLanguage)
            for item in section.items {
                let setTitle = appLocalizedString("algs.item.\(item.id).title", languageCode: appLanguage, defaultValue: item.id)
                let setSubtitle = sectionTitle

                if let set = AlgLibrarySet(itemID: item.id),
                   let payload = AlgLibraryLoader.load(set) {
                    items.append(
                        AlgSearchItem(
                            id: "set::\(item.id)",
                            kind: .set,
                            title: setTitle,
                            subtitle: setSubtitle,
                            searchableText: [
                                setTitle,
                                payload.set,
                                item.id,
                                sectionTitle
                            ],
                            destination: .set(payload)
                        )
                    )

                    for subset in orderedSubsets(from: payload.cases) {
                        let localizedSubset = localizedAlgSubgroup(subset.title, languageCode: appLanguage)
                        items.append(
                            AlgSearchItem(
                                id: "subset::\(item.id)::\(subset.id)",
                                kind: .subset,
                                title: localizedSubset,
                                subtitle: setTitle,
                                searchableText: [
                                    localizedSubset,
                                    subset.title,
                                    subset.id,
                                    setTitle,
                                    payload.set
                                ],
                                destination: .subset(payload, subset)
                            )
                        )
                    }

                    for algCase in payload.cases {
                        let localizedSubset = algCase.subgroup.isEmpty ? "" : localizedAlgSubgroup(algCase.subgroup, languageCode: appLanguage)
                        let caseSubtitle = localizedSubset.isEmpty ? setTitle : "\(setTitle) · \(localizedSubset)"
                        let localizedCaseName = localizedAlgCaseName(setID: payload.set, caseName: algCase.displayName, languageCode: appLanguage)
                        items.append(
                            AlgSearchItem(
                                id: "case::\(item.id)::\(algCase.id)",
                                kind: .caseName,
                                title: localizedCaseName,
                                subtitle: caseSubtitle,
                                searchableText: [
                                    localizedCaseName,
                                    algCase.displayName,
                                    algCase.name,
                                    algCase.id,
                                    localizedSubset,
                                    algCase.subgroup,
                                    setTitle,
                                    payload.set
                                ],
                                destination: .caseDetail(payload, algCase)
                            )
                        )
                    }
                } else {
                    items.append(
                        AlgSearchItem(
                            id: "set::\(item.id)",
                            kind: .set,
                            title: setTitle,
                            subtitle: setSubtitle,
                            searchableText: [setTitle, item.id, sectionTitle],
                            destination: .placeholder(item)
                        )
                    )
                }
            }
        }

        return items
    }

    private func algCard(_ item: AlgItemData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            overviewPreviewImage(for: item, imageHeight: 88, iconSize: 18)
            .frame(height: 88)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitleText(for: item))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                progressIndicator(for: item)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private func overviewPreviewImage(for item: AlgItemData, imageHeight: CGFloat, iconSize: CGFloat) -> some View {
        #if os(iOS)
        if let image = overviewPreviewUIImage(for: item) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(height: imageHeight)
                .frame(maxWidth: .infinity)
        } else {
            Image(systemName: "photo")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: imageHeight)
        }
        #else
        Image(systemName: "photo")
            .font(.system(size: iconSize, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: imageHeight)
        #endif
    }

    #if os(iOS)
    private func overviewPreviewUIImage(for item: AlgItemData) -> UIImage? {
        if let image = UIImage(named: item.imageAssetName) {
            return image
        }

        guard let set = AlgLibrarySet(itemID: item.id),
              let payload = AlgLibraryLoader.load(set),
              let previewCase = payload.cases.first else {
            return nil
        }

        return AlgCaseImageProvider.image(named: previewCase.imageKey)
    }
    #endif

    private func subtitleText(for item: AlgItemData) -> String {
        if item.usesCaseCount {
            let learnedCount = learnedCaseCount(setID: item.id, storage: learnedCasesStore)
            return localizedCaseSubtitle(
                item.algorithmCount,
                learnedCount: learnedCount,
                learnedFraction: learnedFraction(setID: item.id, totalCases: item.algorithmCount, storage: learnedCasesStore),
                languageCode: appLanguage
            )
        }

        return localizedAlgorithmsSubtitle(item.algorithmCount, learnedPercent: item.learnedPercent, languageCode: appLanguage)
    }

    private func learnedPercentValue(for item: AlgItemData) -> Int {
        guard item.usesCaseCount else { return item.learnedPercent }
        return learnedPercent(setID: item.id, totalCases: item.algorithmCount, storage: learnedCasesStore)
    }

    @ViewBuilder
    private func progressIndicator(for item: AlgItemData) -> some View {
        let progress = item.usesCaseCount
            ? learnedFraction(setID: item.id, totalCases: item.algorithmCount, storage: learnedCasesStore)
            : min(max(Double(item.learnedPercent) / 100, 0), 1)
        if progress >= 1 {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.blue)
        } else if progress > 0 {
            LearnedProgressCircle(progress: progress)
                .frame(width: 16, height: 16)
        }
    }

    @ViewBuilder
    private func destinationView(for item: AlgItemData) -> some View {
        if let set = AlgLibrarySet(itemID: item.id),
           let payload = AlgLibraryLoader.load(set) {
            AlgCaseListView(payload: payload)
        } else {
            AlgSetPlaceholderView(item: item)
        }
    }

    @ViewBuilder
    private func recentPracticeDestinationView(for context: AlgRecentPracticeContext) -> some View {
        switch context.destination {
        case .set(let payload):
            AlgCaseListView(payload: payload)
        case .subset(let payload, let subset):
            AlgSubsetCaseListView(payload: payload, subset: subset)
        }
    }

    private func recentPracticeCard(_ context: AlgRecentPracticeContext) -> some View {
        HStack(spacing: 12) {
            Button {
                recentPracticeNavigationContext = context
                isShowingRecentPractice = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedAlgString(key: "algs.trainer.continue_title", languageCode: appLanguage))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(context.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(context.subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                dismissedRecentPracticeRecordID = context.dismissToken
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.secondary.opacity(0.10)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    private var weakPracticeCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedAlgString(key: "algs.trainer.weak_title", languageCode: appLanguage))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(
                    String(
                        format: localizedAlgString(key: "algs.trainer.weak_count_format", languageCode: appLanguage),
                        weakPracticeItems.count
                    )
                )
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

                Text(localizedAlgString(key: "algs.trainer.weak_subtitle", languageCode: appLanguage))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }
}

struct AlgOverviewBottomBar: View {
    let languageCode: String
    let browseViewModeSelection: Binding<String>
    let usesContainerGlass: Bool
    let searchAction: () -> Void

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.clear)
            )
            .modifier(AlgOverviewBottomBarGlassModifier(isEnabled: usesContainerGlass))
    }

    private var content: some View {
        HStack(spacing: 0) {
            Button(action: searchAction) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                    Text(localizedAlgString(key: "algs.search.placeholder", languageCode: languageCode))
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            browseInlineButton
        }
    }

    private var browseInlineButton: some View {
        Menu {
            Section(localizedAlgString(key: "algs.menu.view", languageCode: languageCode)) {
                Picker(localizedAlgString(key: "algs.menu.view", languageCode: languageCode), selection: browseViewModeSelection) {
                    Label(localizedAlgString(key: "algs.menu.grid_view", languageCode: languageCode), systemImage: "square.grid.2x2")
                        .tag(AlgBrowseViewMode.grid.rawValue)
                    Label(localizedAlgString(key: "algs.menu.list_view", languageCode: languageCode), systemImage: "list.bullet")
                        .tag(AlgBrowseViewMode.list.rawValue)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.trailing, 16)
                .padding(.vertical, 12)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct AlgOverviewBottomBarGlassModifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.compatibleGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            content
        }
    }
}
#endif

#if os(iOS)
struct AlgSetPlaceholderView: View {
    let item: AlgItemData
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 34, weight: .bold))

                Text(item.description)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(subtitleText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var subtitleText: String {
        if item.usesCaseCount {
            return localizedCaseCount(item.algorithmCount, languageCode: appLanguage)
        }

        return localizedAlgorithmsSubtitle(item.algorithmCount, learnedPercent: item.learnedPercent, languageCode: appLanguage)
    }
}

struct AlgCaseListView: View {
    let payload: AlgSetPayload
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("algLearnedCasesStore") private var learnedCasesStore: String = "{}"
    @AppStorage("algBrowseViewModeStore") private var browseViewModeStore: String = "{}"
    @AppStorage("algBrowseOrganizationStore") private var browseOrganizationStore: String = "{}"
    @State private var isShowingInfoSheet = false
    @State private var isShowingTrainer = false
    @State private var selectedHybridSubsetID = ""

    var body: some View {
        Group {
            if browseViewMode == .list {
                listContent
            } else {
                gridContent
            }
        }
        .navigationTitle(payload.set)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingInfoSheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .medium))
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    learnedCasesStore = updatedLearnedCaseStorageForAll(
                        storage: learnedCasesStore,
                        setID: payload.set,
                        caseIDs: uniqueCaseIDs,
                        learned: !allCasesLearned
                    )
                } label: {
                    Image(systemName: allCasesLearned ? "graduationcap.fill" : "graduationcap")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            browseOptionsButton
                .padding(.trailing, 16)
                .padding(.bottom, 16)
        }
        .algBottomAccessoryVisible(true)
        .compatibleNavigationDestination(isPresented: $isShowingTrainer) {
            trainerDestination
        }
        .sheet(isPresented: $isShowingInfoSheet) {
            AlgSetInfoSheet(
                setID: payload.set,
                fallbackTitle: payload.set,
                fallbackSubtitle: "",
                sourceURL: sourceURL,
                languageCode: appLanguage
            )
            .compatibleMediumLargeSheet()
        }
    }

    private var listContent: some View {
        List {
            headerContent
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)

            if showsAlgTrainingEntrypoints {
                Button {
                    isShowingTrainer = true
                } label: {
                    trainerEntryButton(
                        title: localizedAlgString(key: "algs.trainer.train_set", languageCode: appLanguage),
                        subtitle: localizedAlgString(key: "algs.trainer.recognition_subtitle", languageCode: appLanguage)
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 10, trailing: 16))
                .listRowSeparator(.hidden)
            }

            if usesHybridCapsules {
                hybridSubsetPicker
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
                    .listRowSeparator(.hidden)
            }

            if showsSubsetBrowser {
                if showsNestedSubsetGroups {
                    ForEach(subsetGroups) { group in
                        NavigationLink {
                            AlgSubsetGroupListView(payload: payload, group: group)
                        } label: {
                            subsetGroupRow(group)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                } else if showsCaseGroups {
                    ForEach(caseGroups) { group in
                        NavigationLink {
                            AlgCaseGroupListView(payload: payload, group: group)
                        } label: {
                            caseGroupRow(group)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                } else {
                    ForEach(subsets) { subset in
                        NavigationLink {
                            AlgSubsetCaseListView(payload: payload, subset: subset)
                        } label: {
                            subsetRow(subset)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
            } else {
                ForEach(visibleCases) { algCase in
                    NavigationLink {
                        AlgCaseDetailView(payload: payload, algCase: algCase)
                    } label: {
                        caseRow(algCase)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }

            if let sourceURL {
                Text(sourceFooterText(for: sourceURL))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 20, trailing: 16))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    private var gridContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerContent
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if showsAlgTrainingEntrypoints {
                    NavigationLink {
                        trainerDestination
                    } label: {
                        trainerEntryButton(
                            title: localizedAlgString(key: "algs.trainer.train_set", languageCode: appLanguage),
                            subtitle: localizedAlgString(key: "algs.trainer.recognition_subtitle", languageCode: appLanguage)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }

                if usesHybridCapsules {
                    hybridSubsetPicker
                }

                LazyVGrid(columns: gridColumns, spacing: 12) {
                    if showsSubsetBrowser {
                        if showsNestedSubsetGroups {
                            ForEach(subsetGroups) { group in
                                NavigationLink {
                                    AlgSubsetGroupListView(payload: payload, group: group)
                                } label: {
                                    subsetGroupCard(group)
                                }
                                .buttonStyle(.plain)
                            }
                        } else if showsCaseGroups {
                            ForEach(caseGroups) { group in
                                NavigationLink {
                                    AlgCaseGroupListView(payload: payload, group: group)
                                } label: {
                                    caseGroupCard(group)
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            ForEach(subsets) { subset in
                                NavigationLink {
                                    AlgSubsetCaseListView(payload: payload, subset: subset)
                                } label: {
                                    subsetCard(subset)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        ForEach(visibleCases) { algCase in
                            NavigationLink {
                                AlgCaseDetailView(payload: payload, algCase: algCase)
                            } label: {
                                caseCard(algCase)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)

                if let sourceURL {
                    Text(sourceFooterText(for: sourceURL))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                }
            }
            .padding(.bottom, 72)
        }
    }

    private var overviewItem: AlgItemData? {
        AlgSectionData.allSections
            .flatMap(\.items)
            .first { $0.id.caseInsensitiveCompare(payload.set) == .orderedSame }
    }

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let overviewItem {
                Text(overviewItem.title)
                    .font(.system(size: 34, weight: .bold))

                Text(overviewItem.description)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(overviewSubtitleText)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            Divider()
                .padding(.top, 12)
        }
        .padding(.top, 4)
    }

    private var overviewSubtitleText: String {
        switch browseOrganization {
        case .number:
            localizedCaseSubtitle(
                payload.cases.count,
                learnedCount: learnedCaseCount(setID: payload.set, storage: learnedCasesStore),
                learnedFraction: learnedFraction(setID: payload.set, totalCases: uniqueCaseCount, storage: learnedCasesStore),
                languageCode: appLanguage
            )
        case .subset:
            localizedCaseSubtitle(
                subsetBrowseGroupCount,
                learnedCount: learnedSubsetCount,
                learnedFraction: subsetLearnedFraction,
                languageCode: appLanguage
            )
        case .hybrid:
            if usesHybridCapsules {
                localizedCaseSubtitle(
                    visibleUniqueCaseCount,
                    learnedCount: learnedCaseCount(setID: payload.set, caseIDs: visibleUniqueCaseIDs, storage: learnedCasesStore),
                    learnedFraction: visibleLearnedFraction,
                    languageCode: appLanguage
                )
            } else {
                localizedCaseSubtitle(
                    subsetBrowseGroupCount,
                    learnedCount: learnedSubsetCount,
                    learnedFraction: subsetLearnedFraction,
                    languageCode: appLanguage
                )
            }
        }
    }

    private var allCasesLearned: Bool {
        uniqueCaseCount > 0 && learnedCaseCount(setID: payload.set, storage: learnedCasesStore) >= uniqueCaseCount
    }

    private var uniqueCaseCount: Int {
        Set(payload.cases.map(\.id)).count
    }

    private var uniqueCaseIDs: [String] {
        Array(Set(payload.cases.map(\.id))).sorted()
    }

    private var visibleCases: [AlgCase] {
        guard usesHybridCapsules,
              let selectedHybridSubset else {
            return payload.cases
        }
        return selectedHybridSubset.cases
    }

    private var visibleUniqueCaseCount: Int {
        Set(visibleCases.map(\.id)).count
    }

    private var visibleUniqueCaseIDs: [String] {
        Array(Set(visibleCases.map(\.id))).sorted()
    }

    private var visibleLearnedFraction: Double {
        guard visibleUniqueCaseCount > 0 else { return 0 }
        let learned = learnedCaseCount(setID: payload.set, caseIDs: visibleUniqueCaseIDs, storage: learnedCasesStore)
        return min(max(Double(learned) / Double(visibleUniqueCaseCount), 0), 1)
    }

    private var subsets: [AlgSubset] {
        orderedSubsets(from: payload.cases)
    }

    private var subsetGroups: [AlgSubsetGroup] {
        orderedSubsetGroups(setID: payload.set, subsets: subsets)
    }

    private var caseGroups: [AlgCaseGroup] {
        orderedCaseGroups(setID: payload.set, cases: payload.cases)
    }

    private var showsNestedSubsetGroups: Bool {
        normalizedAlgSetID(payload.set) == "zbll" && !subsetGroups.isEmpty
    }

    private var showsCaseGroups: Bool {
        !caseGroups.isEmpty
    }

    private var supportsSubsetBrowsing: Bool {
        showsNestedSubsetGroups || showsCaseGroups || !subsets.isEmpty
    }

    private var childGroupsHaveSourcePages: Bool {
        if showsNestedSubsetGroups {
            return subsetGroups.allSatisfy { algChildHasSourcePage(setID: payload.set, childTitle: $0.title) }
        }
        if showsCaseGroups {
            return caseGroups.allSatisfy { algChildHasSourcePage(setID: payload.set, childTitle: $0.title) }
        }
        return false
    }

    private var supportsHybridCapsules: Bool {
        algSupportsHybridCapsules(setID: payload.set, subsets: subsets) && !childGroupsHaveSourcePages
    }

    private var usesHybridCapsules: Bool {
        browseOrganization == .hybrid && supportsHybridCapsules
    }

    private var showsSubsetBrowser: Bool {
        browseOrganization == .subset || (browseOrganization == .hybrid && supportsSubsetBrowsing && childGroupsHaveSourcePages)
    }

    private var selectedHybridSubset: AlgSubset? {
        subsets.first { $0.id == selectedHybridSubsetID }
    }

    private var subsetBrowseGroupCount: Int {
        if showsNestedSubsetGroups {
            return subsetGroups.count
        }
        if showsCaseGroups {
            return caseGroups.count
        }
        return subsets.count
    }

    private var learnedSubsetCount: Int {
        if showsNestedSubsetGroups {
            return subsetGroups.filter { subsetGroupLearnedFraction(for: $0) >= 1 }.count
        }
        if showsCaseGroups {
            return caseGroups.filter { caseGroupLearnedFraction(for: $0) >= 1 }.count
        }
        return subsets.filter { subsetLearnedFraction(for: $0) >= 1 }.count
    }

    private var subsetLearnedFraction: Double {
        let totalCount = subsetBrowseGroupCount
        guard totalCount > 0 else { return 0 }
        return min(max(Double(learnedSubsetCount) / Double(totalCount), 0), 1)
    }

    private var browseViewMode: AlgBrowseViewMode {
        algBrowseViewMode(setID: payload.set, storage: browseViewModeStore)
    }

    private var browseOrganization: AlgBrowseOrganization {
        guard supportsSubsetBrowsing else { return .number }
        return algBrowseOrganization(setID: payload.set, storage: browseOrganizationStore)
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]
    }

    private var sourceURL: URL? {
        algSourceURL(puzzle: payload.puzzle, setID: payload.set)
    }

    private func sourceFooterText(for url: URL) -> String {
        String(
            format: localizedAlgString(key: "algs.source_format", languageCode: appLanguage),
            url.absoluteString
        )
    }

    private var trainerDestination: some View {
        let config = makeSetTrainerSeeds(payload: payload, languageCode: appLanguage, organization: browseOrganization)
        return AlgRecognitionTrainerView(
            title: localizedAlgString(key: "algs.trainer.train_set", languageCode: appLanguage),
            scopeTitle: payload.set,
            languageCode: appLanguage,
            setID: payload.set,
            scopeID: payload.set,
            level: config.0,
            seeds: config.1
        )
    }

    private func caseRow(_ algCase: AlgCase) -> some View {
        HStack(spacing: 12) {
            caseImage(for: algCase)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedAlgCaseName(setID: payload.set, caseName: algCase.displayName, languageCode: appLanguage))
                    .font(.system(size: 17, weight: .semibold))

                Text(formulaCountText(for: algCase.displayAlgorithmsCount))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isAlgCaseLearned(setID: payload.set, caseID: algCase.id, storage: learnedCasesStore) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private func subsetRow(_ subset: AlgSubset) -> some View {
        HStack(spacing: 12) {
            subsetPreviewImage(for: subset)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedAlgSubgroup(subset.title, languageCode: appLanguage))
                    .font(.system(size: 17, weight: .semibold))

                Text(
                    localizedCaseSubtitle(
                        subset.uniqueCaseCount,
                        learnedCount: learnedCaseCount(setID: payload.set, caseIDs: subset.uniqueCaseIDs, storage: learnedCasesStore),
                        learnedFraction: subsetLearnedFraction(for: subset),
                        languageCode: appLanguage
                    )
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Spacer()

            subsetProgressIndicator(for: subset)
        }
        .padding(.vertical, 2)
    }

    private func subsetGroupRow(_ group: AlgSubsetGroup) -> some View {
        HStack(spacing: 12) {
            subsetGroupPreviewImage(for: group)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayAlgGroupTitle(setID: payload.set, title: group.title))
                    .font(.system(size: 17, weight: .semibold))

                Text(
                    localizedCaseSubtitle(
                        group.uniqueCaseCount,
                        learnedCount: learnedCaseCount(setID: payload.set, caseIDs: group.uniqueCaseIDs, storage: learnedCasesStore),
                        learnedFraction: subsetGroupLearnedFraction(for: group),
                        languageCode: appLanguage
                    )
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Spacer()

            subsetGroupProgressIndicator(for: group)
        }
        .padding(.vertical, 2)
    }

    private func caseGroupRow(_ group: AlgCaseGroup) -> some View {
        HStack(spacing: 12) {
            caseGroupPreviewImage(for: group)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.title)
                    .font(.system(size: 17, weight: .semibold))

                Text(
                    localizedCaseSubtitle(
                        group.uniqueCaseCount,
                        learnedCount: learnedCaseCount(setID: payload.set, caseIDs: group.uniqueCaseIDs, storage: learnedCasesStore),
                        learnedFraction: caseGroupLearnedFraction(for: group),
                        languageCode: appLanguage
                    )
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Spacer()

            caseGroupProgressIndicator(for: group)
        }
        .padding(.vertical, 2)
    }

    private func formulaCountText(for count: Int) -> String {
        localizedAlgorithmCount(count, languageCode: appLanguage)
    }

    @ViewBuilder
    private func subsetProgressIndicator(for subset: AlgSubset) -> some View {
        let progress = subsetLearnedFraction(for: subset)
        if progress >= 1 {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.blue)
        } else if progress > 0 {
            LearnedProgressCircle(progress: progress)
                .frame(width: 16, height: 16)
        }
    }

    @ViewBuilder
    private func subsetGroupProgressIndicator(for group: AlgSubsetGroup) -> some View {
        let progress = subsetGroupLearnedFraction(for: group)
        if progress >= 1 {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.blue)
        } else if progress > 0 {
            LearnedProgressCircle(progress: progress)
                .frame(width: 16, height: 16)
        }
    }

    @ViewBuilder
    private func caseGroupProgressIndicator(for group: AlgCaseGroup) -> some View {
        let progress = caseGroupLearnedFraction(for: group)
        if progress >= 1 {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.blue)
        } else if progress > 0 {
            LearnedProgressCircle(progress: progress)
                .frame(width: 16, height: 16)
        }
    }

    private func subsetLearnedFraction(for subset: AlgSubset) -> Double {
        guard subset.uniqueCaseCount > 0 else { return 0 }
        let learned = learnedCaseCount(setID: payload.set, caseIDs: subset.uniqueCaseIDs, storage: learnedCasesStore)
        return min(max(Double(learned) / Double(subset.uniqueCaseCount), 0), 1)
    }

    private func subsetGroupLearnedFraction(for group: AlgSubsetGroup) -> Double {
        guard group.uniqueCaseCount > 0 else { return 0 }
        let learned = learnedCaseCount(setID: payload.set, caseIDs: group.uniqueCaseIDs, storage: learnedCasesStore)
        return min(max(Double(learned) / Double(group.uniqueCaseCount), 0), 1)
    }

    private func caseGroupLearnedFraction(for group: AlgCaseGroup) -> Double {
        guard group.uniqueCaseCount > 0 else { return 0 }
        let learned = learnedCaseCount(setID: payload.set, caseIDs: group.uniqueCaseIDs, storage: learnedCasesStore)
        return min(max(Double(learned) / Double(group.uniqueCaseCount), 0), 1)
    }

    @ViewBuilder
    private func caseImage(for algCase: AlgCase) -> some View {
        #if os(iOS)
        if let image = AlgCaseImageProvider.image(named: algCase.imageKey) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            fallbackCaseImage(for: algCase)
        }
        #else
        fallbackCaseImage(for: algCase)
        #endif
    }

    private func fallbackCaseImage(for algCase: AlgCase) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.blue.opacity(0.12))

            Text(localizedAlgCaseName(setID: payload.set, caseName: algCase.displayName, languageCode: appLanguage))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .padding(.horizontal, 6)
        }
    }

    private func caseCard(_ algCase: AlgCase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Spacer()
                if isAlgCaseLearned(setID: payload.set, caseID: algCase.id, storage: learnedCasesStore) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }

            caseImage(for: algCase)
                .frame(height: 92)
                .frame(maxWidth: .infinity)

            Text(localizedAlgCaseName(setID: payload.set, caseName: algCase.displayName, languageCode: appLanguage))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Text(formulaCountText(for: algCase.displayAlgorithmsCount))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    private func subsetCard(_ subset: AlgSubset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Spacer()
                subsetProgressIndicator(for: subset)
            }

            subsetPreviewImage(for: subset)
                .frame(height: 92)
                .frame(maxWidth: .infinity)

            Text(localizedAlgSubgroup(subset.title, languageCode: appLanguage))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Text(
                localizedCaseSubtitle(
                    subset.uniqueCaseCount,
                    learnedCount: learnedCaseCount(setID: payload.set, caseIDs: subset.uniqueCaseIDs, storage: learnedCasesStore),
                    learnedFraction: subsetLearnedFraction(for: subset),
                    languageCode: appLanguage
                )
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    private func subsetGroupCard(_ group: AlgSubsetGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Spacer()
                subsetGroupProgressIndicator(for: group)
            }

            subsetGroupPreviewImage(for: group)
                .frame(height: 92)
                .frame(maxWidth: .infinity)

            Text(displayAlgGroupTitle(setID: payload.set, title: group.title))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Text(
                localizedCaseSubtitle(
                    group.uniqueCaseCount,
                    learnedCount: learnedCaseCount(setID: payload.set, caseIDs: group.uniqueCaseIDs, storage: learnedCasesStore),
                    learnedFraction: subsetGroupLearnedFraction(for: group),
                    languageCode: appLanguage
                )
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    private func caseGroupCard(_ group: AlgCaseGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Spacer()
                caseGroupProgressIndicator(for: group)
            }

            caseGroupPreviewImage(for: group)
                .frame(height: 92)
                .frame(maxWidth: .infinity)

            Text(group.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Text(
                localizedCaseSubtitle(
                    group.uniqueCaseCount,
                    learnedCount: learnedCaseCount(setID: payload.set, caseIDs: group.uniqueCaseIDs, storage: learnedCasesStore),
                    learnedFraction: caseGroupLearnedFraction(for: group),
                    languageCode: appLanguage
                )
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    private var hybridSubsetPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HorizontalCapsuleSelectorGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(subsets) { subset in
                        hybridSubsetCapsule(subset)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    private func hybridSubsetCapsule(_ subset: AlgSubset) -> some View {
        let isSelected = selectedHybridSubsetID == subset.id
        return Button {
            selectedHybridSubsetID = isSelected ? "" : subset.id
        } label: {
            Text(localizedAlgSubgroup(subset.title, languageCode: appLanguage))
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .horizontalCapsuleSelectorSurface(isSelected: isSelected) {
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.blue : Color.secondary.opacity(0.10))
                }
        }
        .buttonStyle(.plain)
    }

    private var browseOptionsButton: some View {
        Menu {
            Section(browseViewSectionTitle) {
                Picker(browseViewSectionTitle, selection: browseViewModeSelection) {
                    Label(gridViewButtonText, systemImage: "square.grid.2x2")
                        .tag(AlgBrowseViewMode.grid.rawValue)
                    Label(listViewButtonText, systemImage: "list.bullet")
                        .tag(AlgBrowseViewMode.list.rawValue)
                }
            }

            Section(browseOrganizeSectionTitle) {
                Picker(browseOrganizeSectionTitle, selection: browseOrganizationSelection) {
                    Label(byNumberButtonText, systemImage: "number")
                        .tag(AlgBrowseOrganization.number.rawValue)
                    Label(bySubsetButtonText, systemImage: "rectangle.3.group")
                        .tag(AlgBrowseOrganization.subset.rawValue)
                    Label(hybridButtonText, systemImage: "slider.horizontal.3")
                        .tag(AlgBrowseOrganization.hybrid.rawValue)
                }
                .disabled(!supportsSubsetBrowsing)
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(14)
                .contentShape(.circle)
                .clipShape(.circle)
                .compatibleGlass(in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var browseViewModeSelection: Binding<String> {
        Binding(
            get: { browseViewMode.rawValue },
            set: { newValue in
                guard let mode = AlgBrowseViewMode(rawValue: newValue) else { return }
                browseViewModeStore = updatedAlgBrowseViewModeStorage(storage: browseViewModeStore, setID: payload.set, mode: mode)
            }
        )
    }

    private var browseOrganizationSelection: Binding<String> {
        Binding(
            get: { browseOrganization.rawValue },
            set: { newValue in
                guard let organization = AlgBrowseOrganization(rawValue: newValue) else { return }
                browseOrganizationStore = updatedAlgBrowseOrganizationStorage(storage: browseOrganizationStore, setID: payload.set, organization: organization)
            }
        )
    }

    private var browseViewSectionTitle: String {
        localizedAlgString(key: "algs.menu.view", languageCode: appLanguage)
    }

    private var browseOrganizeSectionTitle: String {
        localizedAlgString(key: "algs.menu.organize", languageCode: appLanguage)
    }

    private var gridViewButtonText: String {
        localizedAlgString(key: "algs.menu.grid_view", languageCode: appLanguage)
    }

    private var listViewButtonText: String {
        localizedAlgString(key: "algs.menu.list_view", languageCode: appLanguage)
    }

    private var byNumberButtonText: String {
        localizedAlgString(key: "algs.menu.by_number", languageCode: appLanguage)
    }

    private var bySubsetButtonText: String {
        localizedAlgString(key: "algs.menu.by_subset", languageCode: appLanguage)
    }

    private var hybridButtonText: String {
        localizedAlgString(key: "algs.menu.hybrid", languageCode: appLanguage)
    }

    @ViewBuilder
    private func subsetPreviewImage(for subset: AlgSubset) -> some View {
        if let imageKey = algSubsetPreviewImageKey(setID: payload.set, parentGroupTitle: nil, subsetTitle: subset.title),
           let image = AlgCaseImageProvider.image(named: imageKey) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else if let previewCase = subset.cases.first {
            caseImage(for: previewCase)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.blue.opacity(0.12))

                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.blue)
            }
        }
    }

    @ViewBuilder
    private func subsetGroupPreviewImage(for group: AlgSubsetGroup) -> some View {
        if let imageKey = algGroupPreviewImageKey(setID: payload.set, title: group.title),
           let image = AlgCaseImageProvider.image(named: imageKey) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else if let previewSubset = group.subsets.first {
            subsetPreviewImage(for: previewSubset)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.blue.opacity(0.12))

                Text(displayAlgGroupTitle(setID: payload.set, title: group.title))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.blue)
            }
        }
    }

    @ViewBuilder
    private func caseGroupPreviewImage(for group: AlgCaseGroup) -> some View {
        if let imageKey = algGroupPreviewImageKey(setID: payload.set, title: group.title),
           let image = AlgCaseImageProvider.image(named: imageKey) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else if let previewCase = group.cases.first {
            caseImage(for: previewCase)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.blue.opacity(0.12))

                Text(group.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.blue)
            }
        }
    }

    private func trainerEntryButton(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.orange)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }
}

struct AlgSubsetGroupListView: View {
    let payload: AlgSetPayload
    let group: AlgSubsetGroup
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("algLearnedCasesStore") private var learnedCasesStore: String = "{}"
    @AppStorage("algBrowseViewModeStore") private var browseViewModeStore: String = "{}"
    @AppStorage("algBrowseOrganizationStore") private var browseOrganizationStore: String = "{}"
    @State private var isShowingInfoSheet = false
    @State private var selectedHybridSubsetID = ""

    private var displayGroupTitle: String {
        displayAlgGroupTitle(setID: payload.set, title: group.title)
    }

    var body: some View {
        Group {
            if browseViewMode == .list {
                listContent
            } else {
                gridContent
            }
        }
        .scrollAwareNavigationTitle(displayGroupTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingInfoSheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .medium))
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    learnedCasesStore = updatedLearnedCaseStorageForAll(
                        storage: learnedCasesStore,
                        setID: payload.set,
                        caseIDs: group.uniqueCaseIDs,
                        learned: !allCasesLearned
                    )
                } label: {
                    Image(systemName: allCasesLearned ? "graduationcap.fill" : "graduationcap")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            browseOptionsButton
                .padding(.trailing, 16)
                .padding(.bottom, 16)
        }
        .algBottomAccessoryVisible(true)
        .sheet(isPresented: $isShowingInfoSheet) {
            AlgSetInfoSheet(
                setID: "\(payload.set)_\(group.id)",
                fallbackTitle: displayGroupTitle,
                fallbackSubtitle: payload.set,
                sourceURL: sourceURL,
                languageCode: appLanguage
            )
            .compatibleMediumLargeSheet()
        }
    }

    private var listContent: some View {
        List {
            headerContent
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)

            if usesHybridCapsules {
                hybridSubsetPicker
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
                    .listRowSeparator(.hidden)

                ForEach(visibleCases) { algCase in
                    NavigationLink {
                        AlgCaseDetailView(payload: payload, algCase: algCase)
                    } label: {
                        caseRow(algCase)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            } else if showsSubsetBrowser {
                ForEach(group.subsets) { subset in
                    NavigationLink {
                        AlgSubsetCaseListView(payload: payload, subset: subset)
                    } label: {
                        subsetRow(subset)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            } else {
                ForEach(visibleCases) { algCase in
                    NavigationLink {
                        AlgCaseDetailView(payload: payload, algCase: algCase)
                    } label: {
                        caseRow(algCase)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }

            if let sourceURL {
                Text(sourceFooterText(for: sourceURL))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 20, trailing: 16))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    private var gridContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerContent
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if usesHybridCapsules {
                    hybridSubsetPicker
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
                    if usesHybridCapsules {
                        ForEach(visibleCases) { algCase in
                            NavigationLink {
                                AlgCaseDetailView(payload: payload, algCase: algCase)
                            } label: {
                                caseCard(algCase)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if showsSubsetBrowser {
                        ForEach(group.subsets) { subset in
                            NavigationLink {
                                AlgSubsetCaseListView(payload: payload, subset: subset)
                            } label: {
                                subsetCard(subset)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        ForEach(visibleCases) { algCase in
                            NavigationLink {
                                AlgCaseDetailView(payload: payload, algCase: algCase)
                            } label: {
                                caseCard(algCase)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)

                if let sourceURL {
                    Text(sourceFooterText(for: sourceURL))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                }
            }
            .padding(.bottom, 72)
        }
    }

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollAwareContentTitle(title: displayGroupTitle)
                .font(.system(size: 34, weight: .bold))

            Text(
                headerSubtitleText
            )
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.secondary)

            Divider()
                .padding(.top, 12)
        }
        .padding(.top, 4)
    }

    private var allCasesLearned: Bool {
        group.uniqueCaseCount > 0 && learnedCaseCount(setID: payload.set, caseIDs: group.uniqueCaseIDs, storage: learnedCasesStore) >= group.uniqueCaseCount
    }

    private var learnedFraction: Double {
        guard group.uniqueCaseCount > 0 else { return 0 }
        let learned = learnedCaseCount(setID: payload.set, caseIDs: group.uniqueCaseIDs, storage: learnedCasesStore)
        return min(max(Double(learned) / Double(group.uniqueCaseCount), 0), 1)
    }

    private var headerSubtitleText: String {
        if usesHybridCapsules {
            return localizedCaseSubtitle(
                visibleUniqueCaseCount,
                learnedCount: learnedCaseCount(setID: payload.set, caseIDs: visibleUniqueCaseIDs, storage: learnedCasesStore),
                learnedFraction: visibleLearnedFraction,
                languageCode: appLanguage
            )
        }

        if showsSubsetBrowser {
            let learnedSubsetCount = group.subsets.filter { subsetLearnedFraction(for: $0) >= 1 }.count
            let learnedFraction = group.subsets.isEmpty ? 0 : min(max(Double(learnedSubsetCount) / Double(group.subsets.count), 0), 1)
            return localizedCaseSubtitle(
                group.subsets.count,
                learnedCount: learnedSubsetCount,
                learnedFraction: learnedFraction,
                languageCode: appLanguage
            )
        }

        return localizedCaseSubtitle(
            group.uniqueCaseCount,
            learnedCount: learnedCaseCount(setID: payload.set, caseIDs: group.uniqueCaseIDs, storage: learnedCasesStore),
            learnedFraction: learnedFraction,
            languageCode: appLanguage
        )
    }

    private var browseViewMode: AlgBrowseViewMode {
        algBrowseViewMode(setID: payload.set, storage: browseViewModeStore)
    }

    private var browseOrganization: AlgBrowseOrganization {
        algBrowseOrganization(setID: payload.set, storage: browseOrganizationStore)
    }

    private var usesHybridCapsules: Bool {
        browseOrganization == .hybrid && algSupportsHybridCapsules(setID: payload.set, subsets: group.subsets, parentTitle: group.title)
    }

    private var showsSubsetBrowser: Bool {
        browseOrganization == .subset && !algSubsetsContainOnlySelfGroup(group.subsets, groupTitle: group.title)
    }

    private var selectedHybridSubset: AlgSubset? {
        group.subsets.first { $0.id == selectedHybridSubsetID }
    }

    private var visibleCases: [AlgCase] {
        guard usesHybridCapsules,
              let selectedHybridSubset else {
            return group.subsets.flatMap(\.cases)
        }
        return selectedHybridSubset.cases
    }

    private var visibleUniqueCaseIDs: [String] {
        Array(Set(visibleCases.map(\.id))).sorted()
    }

    private var visibleUniqueCaseCount: Int {
        visibleUniqueCaseIDs.count
    }

    private var visibleLearnedFraction: Double {
        guard visibleUniqueCaseCount > 0 else { return 0 }
        let learned = learnedCaseCount(setID: payload.set, caseIDs: visibleUniqueCaseIDs, storage: learnedCasesStore)
        return min(max(Double(learned) / Double(visibleUniqueCaseCount), 0), 1)
    }

    private var sourceURL: URL? {
        algSourceURL(puzzle: payload.puzzle, setID: payload.set, childTitle: group.title)
            ?? algSourceURL(puzzle: payload.puzzle, setID: payload.set)
    }

    private func sourceFooterText(for url: URL) -> String {
        String(
            format: localizedAlgString(key: "algs.source_format", languageCode: appLanguage),
            url.absoluteString
        )
    }

    private func subsetRow(_ subset: AlgSubset) -> some View {
        HStack(spacing: 12) {
            subsetPreviewImage(for: subset)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedAlgSubgroup(subset.title, languageCode: appLanguage))
                    .font(.system(size: 17, weight: .semibold))

                Text(
                    localizedCaseSubtitle(
                        subset.uniqueCaseCount,
                        learnedCount: learnedCaseCount(setID: payload.set, caseIDs: subset.uniqueCaseIDs, storage: learnedCasesStore),
                        learnedFraction: subsetLearnedFraction(for: subset),
                        languageCode: appLanguage
                    )
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Spacer()

            subsetProgressIndicator(for: subset)
        }
        .padding(.vertical, 2)
    }

    private func subsetCard(_ subset: AlgSubset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Spacer()
                subsetProgressIndicator(for: subset)
            }

            subsetPreviewImage(for: subset)
                .frame(height: 92)
                .frame(maxWidth: .infinity)

            Text(localizedAlgSubgroup(subset.title, languageCode: appLanguage))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Text(
                localizedCaseSubtitle(
                    subset.uniqueCaseCount,
                    learnedCount: learnedCaseCount(setID: payload.set, caseIDs: subset.uniqueCaseIDs, storage: learnedCasesStore),
                    learnedFraction: subsetLearnedFraction(for: subset),
                    languageCode: appLanguage
                )
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private func subsetProgressIndicator(for subset: AlgSubset) -> some View {
        let progress = subsetLearnedFraction(for: subset)
        if progress >= 1 {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.blue)
        } else if progress > 0 {
            LearnedProgressCircle(progress: progress)
                .frame(width: 16, height: 16)
        }
    }

    private func subsetLearnedFraction(for subset: AlgSubset) -> Double {
        guard subset.uniqueCaseCount > 0 else { return 0 }
        let learned = learnedCaseCount(setID: payload.set, caseIDs: subset.uniqueCaseIDs, storage: learnedCasesStore)
        return min(max(Double(learned) / Double(subset.uniqueCaseCount), 0), 1)
    }

    private var hybridSubsetPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HorizontalCapsuleSelectorGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(group.subsets) { subset in
                        hybridSubsetCapsule(subset)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    private func hybridSubsetCapsule(_ subset: AlgSubset) -> some View {
        let isSelected = selectedHybridSubsetID == subset.id
        return Button {
            selectedHybridSubsetID = isSelected ? "" : subset.id
        } label: {
            Text(localizedAlgSubgroup(subset.title, languageCode: appLanguage))
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .horizontalCapsuleSelectorSurface(isSelected: isSelected) {
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.blue : Color.secondary.opacity(0.10))
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func subsetPreviewImage(for subset: AlgSubset) -> some View {
        if let imageKey = algSubsetPreviewImageKey(setID: payload.set, parentGroupTitle: group.title, subsetTitle: subset.title),
           let image = AlgCaseImageProvider.image(named: imageKey) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else if let previewCase = subset.cases.first {
            caseImage(for: previewCase)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.blue.opacity(0.12))

                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.blue)
            }
        }
    }

    @ViewBuilder
    private func caseImage(for algCase: AlgCase) -> some View {
        #if os(iOS)
        if let image = AlgCaseImageProvider.image(named: algCase.imageKey) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            fallbackCaseImage(for: algCase)
        }
        #else
        fallbackCaseImage(for: algCase)
        #endif
    }

    private func fallbackCaseImage(for algCase: AlgCase) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.blue.opacity(0.12))

            Text(localizedAlgCaseName(setID: payload.set, caseName: algCase.displayName, languageCode: appLanguage))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .padding(.horizontal, 6)
        }
    }

    private func caseRow(_ algCase: AlgCase) -> some View {
        HStack(spacing: 12) {
            caseImage(for: algCase)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedAlgCaseName(setID: payload.set, caseName: algCase.displayName, languageCode: appLanguage))
                    .font(.system(size: 17, weight: .semibold))

                Text(localizedAlgorithmCount(algCase.displayAlgorithmsCount, languageCode: appLanguage))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isAlgCaseLearned(setID: payload.set, caseID: algCase.id, storage: learnedCasesStore) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private func caseCard(_ algCase: AlgCase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Spacer()
                if isAlgCaseLearned(setID: payload.set, caseID: algCase.id, storage: learnedCasesStore) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }

            caseImage(for: algCase)
                .frame(height: 92)
                .frame(maxWidth: .infinity)

            Text(localizedAlgCaseName(setID: payload.set, caseName: algCase.displayName, languageCode: appLanguage))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Text(localizedAlgorithmCount(algCase.displayAlgorithmsCount, languageCode: appLanguage))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    private var browseOptionsButton: some View {
        Menu {
            Section(localizedAlgString(key: "algs.menu.view", languageCode: appLanguage)) {
                Picker(localizedAlgString(key: "algs.menu.view", languageCode: appLanguage), selection: browseViewModeSelection) {
                    Label(localizedAlgString(key: "algs.menu.grid_view", languageCode: appLanguage), systemImage: "square.grid.2x2")
                        .tag(AlgBrowseViewMode.grid.rawValue)
                    Label(localizedAlgString(key: "algs.menu.list_view", languageCode: appLanguage), systemImage: "list.bullet")
                        .tag(AlgBrowseViewMode.list.rawValue)
                }
            }

            Section(localizedAlgString(key: "algs.menu.organize", languageCode: appLanguage)) {
                Picker(localizedAlgString(key: "algs.menu.organize", languageCode: appLanguage), selection: browseOrganizationSelection) {
                    Label(localizedAlgString(key: "algs.menu.by_number", languageCode: appLanguage), systemImage: "number")
                        .tag(AlgBrowseOrganization.number.rawValue)
                    Label(localizedAlgString(key: "algs.menu.by_subset", languageCode: appLanguage), systemImage: "rectangle.3.group")
                        .tag(AlgBrowseOrganization.subset.rawValue)
                    Label(localizedAlgString(key: "algs.menu.hybrid", languageCode: appLanguage), systemImage: "slider.horizontal.3")
                        .tag(AlgBrowseOrganization.hybrid.rawValue)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(14)
                .contentShape(.circle)
                .clipShape(.circle)
                .compatibleGlass(in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var browseViewModeSelection: Binding<String> {
        Binding(
            get: { browseViewMode.rawValue },
            set: { newValue in
                guard let mode = AlgBrowseViewMode(rawValue: newValue) else { return }
                browseViewModeStore = updatedAlgBrowseViewModeStorage(storage: browseViewModeStore, setID: payload.set, mode: mode)
            }
        )
    }

    private var browseOrganizationSelection: Binding<String> {
        Binding(
            get: { browseOrganization.rawValue },
            set: { newValue in
                guard let organization = AlgBrowseOrganization(rawValue: newValue) else { return }
                browseOrganizationStore = updatedAlgBrowseOrganizationStorage(storage: browseOrganizationStore, setID: payload.set, organization: organization)
            }
        )
    }
}

private struct AlgCaseGroupListView: View {
    let payload: AlgSetPayload
    let group: AlgCaseGroup
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("algLearnedCasesStore") private var learnedCasesStore: String = "{}"
    @AppStorage("algBrowseViewModeStore") private var browseViewModeStore: String = "{}"
    @AppStorage("algBrowseOrganizationStore") private var browseOrganizationStore: String = "{}"
    @State private var isShowingInfoSheet = false
    @State private var selectedHybridSubsetID = ""

    var body: some View {
        Group {
            if browseViewMode == .list {
                listContent
            } else {
                gridContent
            }
        }
        .scrollAwareNavigationTitle(group.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingInfoSheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .medium))
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    learnedCasesStore = updatedLearnedCaseStorageForAll(
                        storage: learnedCasesStore,
                        setID: payload.set,
                        caseIDs: group.uniqueCaseIDs,
                        learned: !allCasesLearned
                    )
                } label: {
                    Image(systemName: allCasesLearned ? "graduationcap.fill" : "graduationcap")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            browseOptionsButton
                .padding(.trailing, 16)
                .padding(.bottom, 16)
        }
        .algBottomAccessoryVisible(true)
        .sheet(isPresented: $isShowingInfoSheet) {
            AlgSetInfoSheet(
                setID: "\(payload.set)_\(group.id)",
                fallbackTitle: group.title,
                fallbackSubtitle: payload.set,
                sourceURL: sourceURL,
                languageCode: appLanguage
            )
            .compatibleMediumLargeSheet()
        }
    }

    private var listContent: some View {
        List {
            headerContent
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)

            if usesHybridCapsules {
                hybridSubsetPicker
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
                    .listRowSeparator(.hidden)

                ForEach(visibleCases) { algCase in
                    NavigationLink {
                        AlgCaseDetailView(payload: payload, algCase: algCase)
                    } label: {
                        caseRow(algCase)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            } else if showsSubsetBrowser {
                ForEach(groupSubsets) { subset in
                    NavigationLink {
                        AlgSubsetCaseListView(payload: payload, subset: subset)
                    } label: {
                        subsetRow(subset)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            } else {
                ForEach(group.cases) { algCase in
                    NavigationLink {
                        AlgCaseDetailView(payload: payload, algCase: algCase)
                    } label: {
                        caseRow(algCase)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }

            if let sourceURL {
                Text(sourceFooterText(for: sourceURL))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 20, trailing: 16))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    private var gridContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerContent
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if usesHybridCapsules {
                    hybridSubsetPicker
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
                    if usesHybridCapsules {
                        ForEach(visibleCases) { algCase in
                            NavigationLink {
                                AlgCaseDetailView(payload: payload, algCase: algCase)
                            } label: {
                                caseCard(algCase)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if showsSubsetBrowser {
                        ForEach(groupSubsets) { subset in
                            NavigationLink {
                                AlgSubsetCaseListView(payload: payload, subset: subset)
                            } label: {
                                subsetCard(subset)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        ForEach(group.cases) { algCase in
                            NavigationLink {
                                AlgCaseDetailView(payload: payload, algCase: algCase)
                            } label: {
                                caseCard(algCase)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)

                if let sourceURL {
                    Text(sourceFooterText(for: sourceURL))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                }
            }
            .padding(.bottom, 72)
        }
    }

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollAwareContentTitle(title: group.title)
                .font(.system(size: 34, weight: .bold))

            Text(payload.set)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            Text(
                headerSubtitleText
            )
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.secondary)

            Divider()
                .padding(.top, 12)
        }
        .padding(.top, 4)
    }

    private var allCasesLearned: Bool {
        group.uniqueCaseCount > 0 && learnedCaseCount(setID: payload.set, caseIDs: group.uniqueCaseIDs, storage: learnedCasesStore) >= group.uniqueCaseCount
    }

    private var groupSubsets: [AlgSubset] {
        orderedSubsets(from: group.cases)
    }

    private var showsSubsets: Bool {
        !groupSubsets.isEmpty
    }

    private var showsSubsetBrowser: Bool {
        browseOrganization == .subset && showsSubsets && !algSubsetsContainOnlySelfGroup(groupSubsets, groupTitle: group.title)
    }

    private var learnedSubsetCount: Int {
        groupSubsets.filter { subsetLearnedFraction(for: $0) >= 1 }.count
    }

    private var subsetLearnedFractionValue: Double {
        guard !groupSubsets.isEmpty else { return 0 }
        return min(max(Double(learnedSubsetCount) / Double(groupSubsets.count), 0), 1)
    }

    private var headerSubtitleText: String {
        if usesHybridCapsules {
            return localizedCaseSubtitle(
                visibleUniqueCaseCount,
                learnedCount: learnedCaseCount(setID: payload.set, caseIDs: visibleUniqueCaseIDs, storage: learnedCasesStore),
                learnedFraction: visibleLearnedFraction,
                languageCode: appLanguage
            )
        }

        if showsSubsetBrowser {
            return localizedCaseSubtitle(
                groupSubsets.count,
                learnedCount: learnedSubsetCount,
                learnedFraction: subsetLearnedFractionValue,
                languageCode: appLanguage
            )
        }

        return localizedCaseSubtitle(
            group.uniqueCaseCount,
            learnedCount: learnedCaseCount(setID: payload.set, caseIDs: group.uniqueCaseIDs, storage: learnedCasesStore),
            learnedFraction: learnedFraction,
            languageCode: appLanguage
        )
    }

    private var learnedFraction: Double {
        guard group.uniqueCaseCount > 0 else { return 0 }
        let learned = learnedCaseCount(setID: payload.set, caseIDs: group.uniqueCaseIDs, storage: learnedCasesStore)
        return min(max(Double(learned) / Double(group.uniqueCaseCount), 0), 1)
    }

    private var browseViewMode: AlgBrowseViewMode {
        algBrowseViewMode(setID: payload.set, storage: browseViewModeStore)
    }

    private var browseOrganization: AlgBrowseOrganization {
        algBrowseOrganization(setID: payload.set, storage: browseOrganizationStore)
    }

    private var usesHybridCapsules: Bool {
        browseOrganization == .hybrid && algSupportsHybridCapsules(setID: payload.set, subsets: groupSubsets, parentTitle: group.title)
    }

    private var selectedHybridSubset: AlgSubset? {
        groupSubsets.first { $0.id == selectedHybridSubsetID }
    }

    private var visibleCases: [AlgCase] {
        guard usesHybridCapsules,
              let selectedHybridSubset else {
            return group.cases
        }
        return selectedHybridSubset.cases
    }

    private var visibleUniqueCaseIDs: [String] {
        Array(Set(visibleCases.map(\.id))).sorted()
    }

    private var visibleUniqueCaseCount: Int {
        visibleUniqueCaseIDs.count
    }

    private var visibleLearnedFraction: Double {
        guard visibleUniqueCaseCount > 0 else { return 0 }
        let learned = learnedCaseCount(setID: payload.set, caseIDs: visibleUniqueCaseIDs, storage: learnedCasesStore)
        return min(max(Double(learned) / Double(visibleUniqueCaseCount), 0), 1)
    }

    private var sourceURL: URL? {
        algSourceURL(puzzle: payload.puzzle, setID: payload.set, childTitle: group.title)
            ?? algSourceURL(puzzle: payload.puzzle, setID: payload.set)
    }

    private func sourceFooterText(for url: URL) -> String {
        String(
            format: localizedAlgString(key: "algs.source_format", languageCode: appLanguage),
            url.absoluteString
        )
    }

    private func formulaCountText(for count: Int) -> String {
        localizedAlgorithmCount(count, languageCode: appLanguage)
    }

    private func subsetLearnedFraction(for subset: AlgSubset) -> Double {
        guard subset.uniqueCaseCount > 0 else { return 0 }
        let learned = learnedCaseCount(setID: payload.set, caseIDs: subset.uniqueCaseIDs, storage: learnedCasesStore)
        return min(max(Double(learned) / Double(subset.uniqueCaseCount), 0), 1)
    }

    private var hybridSubsetPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HorizontalCapsuleSelectorGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(groupSubsets) { subset in
                        hybridSubsetCapsule(subset)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    private func hybridSubsetCapsule(_ subset: AlgSubset) -> some View {
        let isSelected = selectedHybridSubsetID == subset.id
        return Button {
            selectedHybridSubsetID = isSelected ? "" : subset.id
        } label: {
            Text(localizedAlgSubgroup(subset.title, languageCode: appLanguage))
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .horizontalCapsuleSelectorSurface(isSelected: isSelected) {
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.blue : Color.secondary.opacity(0.10))
                }
        }
        .buttonStyle(.plain)
    }

    private func caseRow(_ algCase: AlgCase) -> some View {
        HStack(spacing: 12) {
            caseImage(for: algCase)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedAlgCaseName(setID: payload.set, caseName: algCase.displayName, languageCode: appLanguage))
                    .font(.system(size: 17, weight: .semibold))

                Text(formulaCountText(for: algCase.displayAlgorithmsCount))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isAlgCaseLearned(setID: payload.set, caseID: algCase.id, storage: learnedCasesStore) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func caseImage(for algCase: AlgCase) -> some View {
        #if os(iOS)
        if let image = AlgCaseImageProvider.image(named: algCase.imageKey) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            fallbackCaseImage(for: algCase)
        }
        #else
        fallbackCaseImage(for: algCase)
        #endif
    }

    private func fallbackCaseImage(for algCase: AlgCase) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.blue.opacity(0.12))

            Text(localizedAlgCaseName(setID: payload.set, caseName: algCase.displayName, languageCode: appLanguage))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .padding(.horizontal, 6)
        }
    }

    private func caseCard(_ algCase: AlgCase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Spacer()
                if isAlgCaseLearned(setID: payload.set, caseID: algCase.id, storage: learnedCasesStore) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }

            caseImage(for: algCase)
                .frame(height: 92)
                .frame(maxWidth: .infinity)

            Text(localizedAlgCaseName(setID: payload.set, caseName: algCase.displayName, languageCode: appLanguage))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Text(formulaCountText(for: algCase.displayAlgorithmsCount))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    private func subsetRow(_ subset: AlgSubset) -> some View {
        HStack(spacing: 12) {
            subsetPreviewImage(for: subset)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedAlgSubgroup(subset.title, languageCode: appLanguage))
                    .font(.system(size: 17, weight: .semibold))

                Text(
                    localizedCaseSubtitle(
                        subset.uniqueCaseCount,
                        learnedCount: learnedCaseCount(setID: payload.set, caseIDs: subset.uniqueCaseIDs, storage: learnedCasesStore),
                        learnedFraction: subsetLearnedFraction(for: subset),
                        languageCode: appLanguage
                    )
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Spacer()

            subsetProgressIndicator(for: subset)
        }
        .padding(.vertical, 2)
    }

    private func subsetCard(_ subset: AlgSubset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Spacer()
                subsetProgressIndicator(for: subset)
            }

            subsetPreviewImage(for: subset)
                .frame(height: 92)
                .frame(maxWidth: .infinity)

            Text(localizedAlgSubgroup(subset.title, languageCode: appLanguage))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Text(
                localizedCaseSubtitle(
                    subset.uniqueCaseCount,
                    learnedCount: learnedCaseCount(setID: payload.set, caseIDs: subset.uniqueCaseIDs, storage: learnedCasesStore),
                    learnedFraction: subsetLearnedFraction(for: subset),
                    languageCode: appLanguage
                )
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private func subsetProgressIndicator(for subset: AlgSubset) -> some View {
        let progress = subsetLearnedFraction(for: subset)
        if progress >= 1 {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.blue)
        } else if progress > 0 {
            LearnedProgressCircle(progress: progress)
                .frame(width: 16, height: 16)
        }
    }

    @ViewBuilder
    private func subsetPreviewImage(for subset: AlgSubset) -> some View {
        if let previewCase = subset.cases.first {
            caseImage(for: previewCase)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.blue.opacity(0.12))

                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.blue)
            }
        }
    }

    private var browseOptionsButton: some View {
        Menu {
            Section(localizedAlgString(key: "algs.menu.view", languageCode: appLanguage)) {
                Picker(localizedAlgString(key: "algs.menu.view", languageCode: appLanguage), selection: browseViewModeSelection) {
                    Label(localizedAlgString(key: "algs.menu.grid_view", languageCode: appLanguage), systemImage: "square.grid.2x2")
                        .tag(AlgBrowseViewMode.grid.rawValue)
                    Label(localizedAlgString(key: "algs.menu.list_view", languageCode: appLanguage), systemImage: "list.bullet")
                        .tag(AlgBrowseViewMode.list.rawValue)
                }
            }

            Section(localizedAlgString(key: "algs.menu.organize", languageCode: appLanguage)) {
                Picker(localizedAlgString(key: "algs.menu.organize", languageCode: appLanguage), selection: browseOrganizationSelection) {
                    Label(localizedAlgString(key: "algs.menu.by_number", languageCode: appLanguage), systemImage: "number")
                        .tag(AlgBrowseOrganization.number.rawValue)
                    Label(localizedAlgString(key: "algs.menu.by_subset", languageCode: appLanguage), systemImage: "rectangle.3.group")
                        .tag(AlgBrowseOrganization.subset.rawValue)
                    Label(localizedAlgString(key: "algs.menu.hybrid", languageCode: appLanguage), systemImage: "slider.horizontal.3")
                        .tag(AlgBrowseOrganization.hybrid.rawValue)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(14)
                .contentShape(.circle)
                .clipShape(.circle)
                .compatibleGlass(in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var browseViewModeSelection: Binding<String> {
        Binding(
            get: { browseViewMode.rawValue },
            set: { newValue in
                guard let mode = AlgBrowseViewMode(rawValue: newValue) else { return }
                browseViewModeStore = updatedAlgBrowseViewModeStorage(storage: browseViewModeStore, setID: payload.set, mode: mode)
            }
        )
    }

    private var browseOrganizationSelection: Binding<String> {
        Binding(
            get: { browseOrganization.rawValue },
            set: { newValue in
                guard let organization = AlgBrowseOrganization(rawValue: newValue) else { return }
                browseOrganizationStore = updatedAlgBrowseOrganizationStorage(storage: browseOrganizationStore, setID: payload.set, organization: organization)
            }
        )
    }
}

struct AlgSubsetCaseListView: View {
    let payload: AlgSetPayload
    let subset: AlgSubset
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("algLearnedCasesStore") private var learnedCasesStore: String = "{}"
    @AppStorage("algBrowseViewModeStore") private var browseViewModeStore: String = "{}"
    @State private var isShowingInfoSheet = false
    @State private var isShowingTrainer = false

    var body: some View {
        Group {
            if browseViewMode == .list {
                listContent
            } else {
                gridContent
            }
        }
        .scrollAwareNavigationTitle(localizedAlgSubgroup(subset.title, languageCode: appLanguage))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingInfoSheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .medium))
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    learnedCasesStore = updatedLearnedCaseStorageForAll(
                        storage: learnedCasesStore,
                        setID: payload.set,
                        caseIDs: subset.uniqueCaseIDs,
                        learned: !allCasesLearned
                    )
                } label: {
                    Image(systemName: allCasesLearned ? "graduationcap.fill" : "graduationcap")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            browseOptionsButton
                .padding(.trailing, 16)
                .padding(.bottom, 16)
        }
        .algBottomAccessoryVisible(true)
        .compatibleNavigationDestination(isPresented: $isShowingTrainer) {
            trainerDestination
        }
        .sheet(isPresented: $isShowingInfoSheet) {
            AlgSetInfoSheet(
                setID: "\(payload.set)_\(subset.id)",
                fallbackTitle: localizedAlgSubgroup(subset.title, languageCode: appLanguage),
                fallbackSubtitle: payload.set,
                sourceURL: sourceURL,
                languageCode: appLanguage
            )
            .compatibleMediumLargeSheet()
        }
    }

    private var listContent: some View {
        List {
            headerContent
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)

            if showsAlgTrainingEntrypoints {
                Button {
                    isShowingTrainer = true
                } label: {
                    trainerEntryButton(
                        title: localizedAlgString(key: "algs.trainer.train_subset", languageCode: appLanguage),
                        subtitle: localizedAlgString(key: "algs.trainer.recognition_subtitle", languageCode: appLanguage)
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 10, trailing: 16))
                .listRowSeparator(.hidden)
            }

            ForEach(subset.cases) { algCase in
                NavigationLink {
                    AlgCaseDetailView(payload: payload, algCase: algCase)
                } label: {
                    caseRow(algCase)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            if let sourceURL {
                Text(sourceFooterText(for: sourceURL))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 20, trailing: 16))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    private var gridContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerContent
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if showsAlgTrainingEntrypoints {
                    NavigationLink {
                        trainerDestination
                    } label: {
                        trainerEntryButton(
                            title: localizedAlgString(key: "algs.trainer.train_subset", languageCode: appLanguage),
                            subtitle: localizedAlgString(key: "algs.trainer.recognition_subtitle", languageCode: appLanguage)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
                    ForEach(subset.cases) { algCase in
                        NavigationLink {
                            AlgCaseDetailView(payload: payload, algCase: algCase)
                        } label: {
                            caseCard(algCase)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                if let sourceURL {
                    Text(sourceFooterText(for: sourceURL))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                }
            }
            .padding(.bottom, 72)
        }
    }

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollAwareContentTitle(
                title: localizedAlgSubgroup(subset.title, languageCode: appLanguage)
            )
                .font(.system(size: 34, weight: .bold))

            Text(payload.set)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            Text(
                localizedCaseSubtitle(
                    subset.uniqueCaseCount,
                    learnedCount: learnedCaseCount(setID: payload.set, caseIDs: subset.uniqueCaseIDs, storage: learnedCasesStore),
                    learnedFraction: learnedFraction,
                    languageCode: appLanguage
                )
            )
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.secondary)

            Divider()
                .padding(.top, 12)
        }
        .padding(.top, 4)
    }

    private var allCasesLearned: Bool {
        subset.uniqueCaseCount > 0 && learnedCaseCount(setID: payload.set, caseIDs: subset.uniqueCaseIDs, storage: learnedCasesStore) >= subset.uniqueCaseCount
    }

    private var learnedFraction: Double {
        guard subset.uniqueCaseCount > 0 else { return 0 }
        let learned = learnedCaseCount(setID: payload.set, caseIDs: subset.uniqueCaseIDs, storage: learnedCasesStore)
        return min(max(Double(learned) / Double(subset.uniqueCaseCount), 0), 1)
    }

    private var browseViewMode: AlgBrowseViewMode {
        algBrowseViewMode(setID: payload.set, storage: browseViewModeStore)
    }

    private var sourceURL: URL? {
        algSourceURL(puzzle: payload.puzzle, setID: payload.set, subset: subset)
    }

    private func sourceFooterText(for url: URL) -> String {
        String(
            format: localizedAlgString(key: "algs.source_format", languageCode: appLanguage),
            url.absoluteString
        )
    }

    private var trainerDestination: some View {
        let config = makeSubsetTrainerSeeds(setID: payload.set, subset: subset, languageCode: appLanguage)
        return AlgRecognitionTrainerView(
            title: localizedAlgString(key: "algs.trainer.train_subset", languageCode: appLanguage),
            scopeTitle: localizedAlgSubgroup(subset.title, languageCode: appLanguage),
            languageCode: appLanguage,
            setID: payload.set,
            scopeID: "\(payload.set)_\(subset.id)",
            level: config.0,
            seeds: config.1
        )
    }

    private func formulaCountText(for count: Int) -> String {
        localizedAlgorithmCount(count, languageCode: appLanguage)
    }

    private func caseRow(_ algCase: AlgCase) -> some View {
        HStack(spacing: 12) {
            caseImage(for: algCase)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedAlgCaseName(setID: payload.set, caseName: algCase.displayName, languageCode: appLanguage))
                    .font(.system(size: 17, weight: .semibold))

                Text(formulaCountText(for: algCase.displayAlgorithmsCount))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isAlgCaseLearned(setID: payload.set, caseID: algCase.id, storage: learnedCasesStore) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func caseImage(for algCase: AlgCase) -> some View {
        #if os(iOS)
        if let image = AlgCaseImageProvider.image(named: algCase.imageKey) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            fallbackCaseImage(for: algCase)
        }
        #else
        fallbackCaseImage(for: algCase)
        #endif
    }

    private func fallbackCaseImage(for algCase: AlgCase) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.blue.opacity(0.12))

            Text(localizedAlgCaseName(setID: payload.set, caseName: algCase.displayName, languageCode: appLanguage))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .padding(.horizontal, 6)
        }
    }

    private func caseCard(_ algCase: AlgCase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Spacer()
                if isAlgCaseLearned(setID: payload.set, caseID: algCase.id, storage: learnedCasesStore) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }

            caseImage(for: algCase)
                .frame(height: 92)
                .frame(maxWidth: .infinity)

            Text(localizedAlgCaseName(setID: payload.set, caseName: algCase.displayName, languageCode: appLanguage))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Text(formulaCountText(for: algCase.displayAlgorithmsCount))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    private func trainerEntryButton(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.orange)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private func subsetPreviewImage(for subset: AlgSubset) -> some View {
        if let previewCase = subset.cases.first {
            caseImage(for: previewCase)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.blue.opacity(0.12))

                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.blue)
            }
        }
    }

    private var browseOptionsButton: some View {
        Menu {
            Section(localizedAlgString(key: "algs.menu.view", languageCode: appLanguage)) {
                Picker(localizedAlgString(key: "algs.menu.view", languageCode: appLanguage), selection: browseViewModeSelection) {
                    Label(localizedAlgString(key: "algs.menu.grid_view", languageCode: appLanguage), systemImage: "square.grid.2x2")
                        .tag(AlgBrowseViewMode.grid.rawValue)
                    Label(localizedAlgString(key: "algs.menu.list_view", languageCode: appLanguage), systemImage: "list.bullet")
                        .tag(AlgBrowseViewMode.list.rawValue)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(14)
                .contentShape(.circle)
                .clipShape(.circle)
                .compatibleGlass(in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var browseViewModeSelection: Binding<String> {
        Binding(
            get: { browseViewMode.rawValue },
            set: { newValue in
                guard let mode = AlgBrowseViewMode(rawValue: newValue) else { return }
                browseViewModeStore = updatedAlgBrowseViewModeStorage(storage: browseViewModeStore, setID: payload.set, mode: mode)
            }
        )
    }
}

private struct AlgSetInfoSheet: View {
    let setID: String
    let fallbackTitle: String
    let fallbackSubtitle: String
    let sourceURL: URL?
    let languageCode: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("algInfoLikedSetsStore") private var likedSetsStore: String = "[]"
    @State private var isShowingReportCopiedAlert = false

    var body: some View {
        CompatibleNavigationContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Divider()
                        .padding(.bottom, 0)

                    if let content = infoContent {
                        ForEach(Array(content.sections.enumerated()), id: \.element.id) { index, section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.title)
                                    .font(.title2)
                                    .fontWeight(.bold)

                                VStack(alignment: .leading, spacing: 14) {
                                    ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                        infoParagraph(paragraph)
                                    }

                                    ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, bullet in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("•")
                                                .font(.system(size: 17, weight: .regular))
                                            infoParagraph(bullet)
                                        }
                                    }
                                }
                            }
                            .padding(.top, index == 0 ? -12 : 0)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .medium))

                            Text(footerGeneratedLeadingText)
                                .font(.footnote)

                            Image(chatGPTLogoAssetName)
                                .renderingMode(.original)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 18)

                            Text(localizedAlgString(key: "algs.footer.chatgpt", languageCode: languageCode))
                                .font(.footnote)

                            Text(footerGeneratedConnectorText)
                                .font(.footnote)

                            Image(codexLogoAssetName)
                                .renderingMode(.original)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 12)

                            Text(footerGeneratedTrailingText)
                                .font(.footnote)
                        }

                        Text(footerAccuracyText)
                            .font(.footnote)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                    Color.clear
                        .frame(height: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 24)
            }
            .contentShape(Rectangle())
                .navigationTitle(displayTitle)
                .compatibleNavigationSubtitle(Text(displaySubtitle))
                .navigationBarTitleDisplayMode(.large)
                .background(AlgInfoNavigationBarFontConfigurator(largeSubtitle: displaySubtitle))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        if let sourceURL {
                            Link(destination: sourceURL) {
                                Image(systemName: "link")
                                    .font(.system(size: 15, weight: .medium))
                            }
                        }
                    }

                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            #if os(iOS)
                            UIPasteboard.general.string = reportTemplateText
                            #endif
                            isShowingReportCopiedAlert = true
                        } label: {
                            Label(reportButtonText, systemImage: "exclamationmark.bubble")
                        }

                        Spacer()

                        Button {
                            toggleLikedState()
                        } label: {
                            Label(likeButtonText, systemImage: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                        }

                        if #available(iOS 16.0, *) {
                            ShareLink(item: shareText, subject: Text(displayTitle)) {
                                Label(shareButtonText, systemImage: "square.and.arrow.up")
                            }
                        } else {
                            Button {
                                #if os(iOS)
                                UIPasteboard.general.string = shareText
                                #endif
                                isShowingReportCopiedAlert = true
                            } label: {
                                Label(shareButtonText, systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
        }
        .alert(reportAlertTitle, isPresented: $isShowingReportCopiedAlert) {
            Button(reportAlertDismissText, role: .cancel) {}
        } message: {
            Text(reportAlertMessage)
        }
    }

    private var infoContent: AlgSetInfoContent? {
        AlgSetInfoContent.make(setID: setID, languageCode: languageCode)
    }

    private var displayTitle: String {
        infoContent?.title ?? fallbackTitle
    }

    private var displaySubtitle: String {
        infoContent?.subtitle ?? fallbackSubtitle
    }

    private var footerGeneratedLeadingText: String {
        localizedAlgString(key: "algs.footer.generated_leading", languageCode: languageCode)
    }

    private var footerGeneratedConnectorText: String {
        localizedAlgString(key: "algs.footer.generated_connector", languageCode: languageCode)
    }

    private var footerGeneratedTrailingText: String {
        localizedAlgString(key: "algs.footer.generated_trailing", languageCode: languageCode)
    }

    private var footerAccuracyText: String {
        localizedAlgString(key: "algs.footer.inaccurate", languageCode: languageCode)
    }

    private var chatGPTLogoAssetName: String {
        colorScheme == .dark ? "logo_chatgpt_white" : "logo_chatgpt_black"
    }

    private var codexLogoAssetName: String {
        colorScheme == .dark ? "logo_codex_white" : "logo_codex_black"
    }

    private var shareText: String {
        var components = [displayTitle]
        if !displaySubtitle.isEmpty {
            components.append(displaySubtitle)
        }
        if let sourceURL {
            components.append(sourceURL.absoluteString)
        }
        return components.joined(separator: "\n")
    }

    private var reportTemplateText: String {
        let lines = [
            "Set: \(setID)",
            "Title: \(displayTitle)",
            "Subtitle: \(displaySubtitle)",
            sourceURL.map { "Source URL: \($0.absoluteString)" } ?? nil,
            "",
            localizedAlgString(key: "algs.report.issue_description", languageCode: languageCode)
        ]
        return lines.compactMap { $0 }.joined(separator: "\n")
    }

    private var likedSetIDs: Set<String> {
        guard let data = likedSetsStore.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(decoded)
    }

    private var isLiked: Bool {
        likedSetIDs.contains(normalizedAlgSetID(setID))
    }

    private func toggleLikedState() {
        var updated = likedSetIDs
        let key = normalizedAlgSetID(setID)
        if updated.contains(key) {
            updated.remove(key)
        } else {
            updated.insert(key)
        }

        guard let data = try? JSONEncoder().encode(updated.sorted()),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        likedSetsStore = string
    }

    private var reportButtonText: String {
        localizedAlgString(key: "algs.report.button", languageCode: languageCode)
    }

    private var likeButtonText: String {
        localizedAlgString(key: "algs.like.button", languageCode: languageCode)
    }

    private var shareButtonText: String {
        localizedAlgString(key: "algs.share.button", languageCode: languageCode)
    }

    private var reportAlertTitle: String {
        localizedAlgString(key: "algs.report.copied_title", languageCode: languageCode)
    }

    private var reportAlertMessage: String {
        localizedAlgString(key: "algs.report.copied_message", languageCode: languageCode)
    }

    private var reportAlertDismissText: String {
        localizedAlgString(key: "algs.ok", languageCode: languageCode)
    }

    @ViewBuilder
    private func infoParagraph(_ markdown: String) -> some View {
        if let attributed = styledMarkdownParagraph(markdown) {
            Text(attributed)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(markdown)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func styledMarkdownParagraph(_ markdown: String) -> AttributedString? {
        guard let nsAttributed = try? NSAttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return nil
        }

        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let emphasizedBodyFont = UIFont.systemFont(ofSize: bodyFont.pointSize, weight: .semibold)
        let mutable = NSMutableAttributedString(attributedString: nsAttributed)
        let fullRange = NSRange(location: 0, length: mutable.length)

        mutable.addAttribute(.font, value: bodyFont, range: fullRange)
        mutable.enumerateAttribute(.inlinePresentationIntent, in: fullRange) { value, range, _ in
            guard let rawValue = (value as? NSNumber)?.uintValue else { return }
            let intent = InlinePresentationIntent(rawValue: rawValue)
            if intent.contains(.stronglyEmphasized) {
                mutable.addAttribute(.font, value: emphasizedBodyFont, range: range)
            }
        }

        return AttributedString(mutable)
    }
}

#if os(iOS)
private struct AlgInfoNavigationBarFontConfigurator: UIViewControllerRepresentable {
    let largeSubtitle: String

    func makeUIViewController(context: Context) -> AlgInfoNavigationBarFontConfiguratorController {
        AlgInfoNavigationBarFontConfiguratorController()
    }

    func updateUIViewController(_ uiViewController: AlgInfoNavigationBarFontConfiguratorController, context: Context) {
        uiViewController.applyFontsIfNeeded(largeSubtitle: largeSubtitle)
    }
}

private final class AlgInfoNavigationBarFontConfiguratorController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }

    func applyFontsIfNeeded(largeSubtitle: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let navigationController = self.resolvedNavigationController() else { return }
            let navigationBar = navigationController.navigationBar

            let largeTitleBase = UIFont.preferredFont(forTextStyle: .largeTitle)
            let largeTitleFont = UIFont.systemFont(ofSize: largeTitleBase.pointSize, weight: .bold)
            let inlineTitleFont = UIFont.systemFont(ofSize: 15, weight: .semibold)
            let inlineSubtitleFont = UIFont.systemFont(ofSize: 12, weight: .medium)
            let largeSubtitleFont = UIFont.systemFont(ofSize: 15, weight: .medium)

            let standardAppearance = navigationBar.standardAppearance.copy()
            standardAppearance.titleTextAttributes[.font] = inlineTitleFont
            if #available(iOS 26.0, *) {
                standardAppearance.subtitleTextAttributes[.font] = inlineSubtitleFont
                standardAppearance.largeSubtitleTextAttributes[.font] = largeSubtitleFont
                standardAppearance.largeSubtitleTextAttributes[.foregroundColor] = UIColor.secondaryLabel
            }

            let scrollEdgeAppearance = navigationBar.scrollEdgeAppearance?.copy() ?? standardAppearance.copy()
            scrollEdgeAppearance.largeTitleTextAttributes[.font] = largeTitleFont
            scrollEdgeAppearance.titleTextAttributes[.font] = inlineTitleFont
            if #available(iOS 26.0, *) {
                scrollEdgeAppearance.subtitleTextAttributes[.font] = inlineSubtitleFont
                scrollEdgeAppearance.largeSubtitleTextAttributes[.font] = largeSubtitleFont
                scrollEdgeAppearance.largeSubtitleTextAttributes[.foregroundColor] = UIColor.secondaryLabel
            }

            navigationBar.standardAppearance = standardAppearance
            navigationBar.compactAppearance = standardAppearance
            navigationBar.scrollEdgeAppearance = scrollEdgeAppearance
            if #available(iOS 17.0, *) {
                navigationBar.compactScrollEdgeAppearance = scrollEdgeAppearance
            }

            guard let targetNavigationItem = self.resolvedNavigationItem(from: navigationController) else { return }

            if #available(iOS 16.0, *) {
                targetNavigationItem.style = .browser
            }
            if #available(iOS 26.0, *) {
                targetNavigationItem.subtitle = largeSubtitle
                targetNavigationItem.largeSubtitle = largeSubtitle
                targetNavigationItem.largeSubtitleView = LargeSubtitleContainerView(
                    text: largeSubtitle,
                    topInset: 4
                )
            }
        }
    }

    private func resolvedNavigationController() -> UINavigationController? {
        if let navigationController {
            return navigationController
        }

        var current: UIViewController? = parent
        while let controller = current {
            if let navigationController = controller.navigationController {
                return navigationController
            }
            current = controller.parent
        }

        return nil
    }

    private func resolvedNavigationItem(from navigationController: UINavigationController) -> UINavigationItem? {
        if let topItem = navigationController.topViewController?.navigationItem {
            return topItem
        }

        var current: UIViewController? = parent
        while let controller = current {
            let item = controller.navigationItem
            if item.title != nil {
                return item
            }
            if #available(iOS 26.0, *), item.subtitle != nil || item.largeSubtitle != nil {
                return item
            }
            current = controller.parent
        }

        return navigationController.visibleViewController?.navigationItem
    }
}

private final class LargeSubtitleContainerView: UIView {
    private let label = UILabel()
    private let topInset: CGFloat

    init(text: String, topInset: CGFloat) {
        self.topInset = topInset
        super.init(frame: .zero)

        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabel
        label.text = text
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: topInset),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let labelSize = label.intrinsicContentSize
        return CGSize(width: labelSize.width, height: labelSize.height + topInset)
    }
}
#endif

private struct AlgInfoSection: Identifiable {
    let id: String
    let title: String
    let paragraphs: [String]
    let bullets: [String]
}

private struct AlgSetInfoContent {
    let title: String
    let subtitle: String
    let sections: [AlgInfoSection]

    static func make(setID: String, languageCode: String) -> AlgSetInfoContent? {
        let normalizedID = normalizedAlgSetID(setID)
        let baseSetID = normalizedID.split(separator: "_").first.map(String.init) ?? normalizedID
        switch baseSetID {
        case "pll":
            return makePLLInfo(languageCode: languageCode)
        case "oll":
            return makeOLLInfo(languageCode: languageCode)
        case "f2l":
            return makeF2LInfo(languageCode: languageCode)
        case "advancedf2l":
            return makeAdvancedF2LInfo(languageCode: languageCode)
        case "coll":
            return makeCOLLInfo(languageCode: languageCode)
        case "cls":
            return makeCLSInfo(languageCode: languageCode)
        case "ollcp":
            return makeOLLCPInfo(languageCode: languageCode)
        case "vls":
            return makeVLSInfo(languageCode: languageCode)
        case "wv":
            return makeWVInfo(languageCode: languageCode)
        case "sv":
            return makeSVInfo(languageCode: languageCode)
        case "sbls":
            return makeSBLSInfo(languageCode: languageCode)
        case "cmll":
            return makeCMLLInfo(languageCode: languageCode)
        case "4a":
            return makeFourAInfo(languageCode: languageCode)
        case "zbls":
            return makeZBLSInfo(languageCode: languageCode)
        case "1lll":
            return makeOneLLLInfo(languageCode: languageCode)
        case "zbll":
            return makeZBLLInfo(languageCode: languageCode)
        case "ortegaoll",
             "ortegapbl",
             "cll",
             "eg1",
             "eg2",
             "ollparity",
             "pllparity",
             "l2e",
             "l2c",
             "sq1cs",
             "sq1co",
             "sq1eo",
             "sq1cp",
             "sq1ep",
             "sq1parity",
             "lin",
             "megaminxeo",
             "megaminxco",
             "megaminxep",
             "megaminxcp",
             "megaminxoll",
             "megaminxpll",
             "l3e",
             "l4e",
             "sarahsadvanced":
            return makeStandardInfo(setID: baseSetID, languageCode: languageCode)
        default:
            return makeGenericInfo(setID: baseSetID, languageCode: languageCode)
        }
    }

    private static func makeStandardInfo(setID: String, languageCode: String) -> AlgSetInfoContent {
        AlgSetInfoContent(
            title: localizedAlgString(key: "algs.info.\(setID).title", languageCode: languageCode),
            subtitle: localizedAlgString(key: "algs.info.\(setID).subtitle", languageCode: languageCode),
            sections: [
                AlgInfoSection(
                    id: "overview",
                    title: localizedAlgString(key: "algs.info.generic.section.overview", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.\(setID).overview.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "history",
                    title: localizedAlgString(key: "algs.info.shared.section.history", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.\(setID).context.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "size",
                    title: localizedAlgString(key: "algs.info.shared.section.size", languageCode: languageCode),
                    paragraphs: [],
                    bullets: [
                        localizedAlgString(key: "algs.info.\(setID).structure.b1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.\(setID).structure.b2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.\(setID).structure.b3", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.\(setID).structure.b4", languageCode: languageCode)
                    ]
                ),
                AlgInfoSection(
                    id: "insights",
                    title: localizedAlgString(key: "algs.info.zbll.section.insights", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.\(setID).insights.p1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.\(setID).insights.p2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.\(setID).insights.p3", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recognition",
                    title: localizedAlgString(key: "algs.info.zbll.section.recognition", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.\(setID).recognition.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recommended",
                    title: localizedAlgString(key: "algs.info.zbll.section.recommended", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.\(setID).recommended.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "quote",
                    title: localizedAlgString(key: "algs.info.zbll.section.quote", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.\(setID).quote.p1", languageCode: languageCode)
                    ],
                    bullets: []
                )
            ]
        )
    }

    private static func makeGenericInfo(setID: String, languageCode: String) -> AlgSetInfoContent? {
        let baseSetID = setID.split(separator: "_").first.map(String.init) ?? setID
        let localizedTitle = appLocalizedString("algs.item.\(baseSetID).title", languageCode: languageCode, defaultValue: baseSetID)
        guard localizedTitle != baseSetID || AlgLibrarySet(itemID: baseSetID) != nil else {
            return nil
        }

        let description = appLocalizedString("algs.item.\(baseSetID).description", languageCode: languageCode, defaultValue: "")
        let puzzleName: String
        if let set = AlgLibrarySet(itemID: baseSetID),
           let payload = AlgLibraryLoader.load(set) {
            puzzleName = appLocalizedString(algPuzzleEventKey(payload.puzzle), languageCode: languageCode, defaultValue: payload.puzzle)
        } else {
            puzzleName = ""
        }

        let subtitle: String
        if puzzleName.isEmpty {
            subtitle = description.isEmpty ? localizedTitle : description
        } else if description.isEmpty {
            subtitle = puzzleName
        } else {
            subtitle = String(
                format: localizedAlgString(key: "algs.info.generic.subtitle_format", languageCode: languageCode),
                puzzleName,
                description
            )
        }

        return AlgSetInfoContent(
            title: localizedTitle,
            subtitle: subtitle,
            sections: [
                AlgInfoSection(
                    id: "overview",
                    title: localizedAlgString(key: "algs.info.generic.section.overview", languageCode: languageCode),
                    paragraphs: [
                        String(
                            format: localizedAlgString(key: "algs.info.generic.overview.p1_format", languageCode: languageCode),
                            localizedTitle
                        ),
                        String(
                            format: localizedAlgString(key: "algs.info.generic.overview.p2_format", languageCode: languageCode),
                            puzzleName.isEmpty ? localizedTitle : puzzleName
                        )
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "practice",
                    title: localizedAlgString(key: "algs.info.generic.section.practice", languageCode: languageCode),
                    paragraphs: [],
                    bullets: [
                        localizedAlgString(key: "algs.info.generic.practice.b1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.generic.practice.b2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.generic.practice.b3", languageCode: languageCode)
                    ]
                ),
                AlgInfoSection(
                    id: "source",
                    title: localizedAlgString(key: "algs.info.generic.section.source", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.generic.source.p1", languageCode: languageCode)
                    ],
                    bullets: []
                )
            ]
        )
    }

    private static func makePLLInfo(languageCode: String) -> AlgSetInfoContent {
        AlgSetInfoContent(
            title: localizedAlgString(key: "algs.info.pll.title", languageCode: languageCode),
            subtitle: localizedAlgString(key: "algs.info.pll.subtitle", languageCode: languageCode),
            sections: [
                AlgInfoSection(
                    id: "overview",
                    title: localizedAlgString(key: "algs.info.pll.section.overview", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.pll.overview.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "history",
                    title: localizedAlgString(key: "algs.info.pll.section.history", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.pll.history.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "size",
                    title: localizedAlgString(key: "algs.info.pll.section.size", languageCode: languageCode),
                    paragraphs: [],
                    bullets: [
                        localizedAlgString(key: "algs.info.pll.size.b1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.pll.size.b2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.pll.size.b3", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.pll.size.b4", languageCode: languageCode)
                    ]
                ),
                AlgInfoSection(
                    id: "insights",
                    title: localizedAlgString(key: "algs.info.pll.section.insights", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.pll.insights.p1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.pll.insights.p2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.pll.insights.p3", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recognition",
                    title: localizedAlgString(key: "algs.info.pll.section.recognition", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.pll.recognition.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recommended",
                    title: localizedAlgString(key: "algs.info.pll.section.recommended", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.pll.recommended.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "quote",
                    title: localizedAlgString(key: "algs.info.pll.section.quote", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.pll.quote.p1", languageCode: languageCode)
                    ],
                    bullets: []
                )
            ]
        )
    }

    private static func makeOLLInfo(languageCode: String) -> AlgSetInfoContent {
        AlgSetInfoContent(
            title: localizedAlgString(key: "algs.info.oll.title", languageCode: languageCode),
            subtitle: localizedAlgString(key: "algs.info.oll.subtitle", languageCode: languageCode),
            sections: [
                AlgInfoSection(
                    id: "overview",
                    title: localizedAlgString(key: "algs.info.oll.section.overview", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.oll.overview.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "history",
                    title: localizedAlgString(key: "algs.info.oll.section.history", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.oll.history.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "size",
                    title: localizedAlgString(key: "algs.info.oll.section.size", languageCode: languageCode),
                    paragraphs: [],
                    bullets: [
                        localizedAlgString(key: "algs.info.oll.size.b1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.oll.size.b2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.oll.size.b3", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.oll.size.b4", languageCode: languageCode)
                    ]
                ),
                AlgInfoSection(
                    id: "insights",
                    title: localizedAlgString(key: "algs.info.oll.section.insights", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.oll.insights.p1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.oll.insights.p2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.oll.insights.p3", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recognition",
                    title: localizedAlgString(key: "algs.info.oll.section.recognition", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.oll.recognition.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recommended",
                    title: localizedAlgString(key: "algs.info.oll.section.recommended", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.oll.recommended.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "quote",
                    title: localizedAlgString(key: "algs.info.oll.section.quote", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.oll.quote.p1", languageCode: languageCode)
                    ],
                    bullets: []
                )
            ]
        )
    }

    private static func makeF2LInfo(languageCode: String) -> AlgSetInfoContent {
        AlgSetInfoContent(
            title: localizedAlgString(key: "algs.info.f2l.title", languageCode: languageCode),
            subtitle: localizedAlgString(key: "algs.info.f2l.subtitle", languageCode: languageCode),
            sections: [
                AlgInfoSection(
                    id: "overview",
                    title: localizedAlgString(key: "algs.info.f2l.section.overview", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.f2l.overview.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "history",
                    title: localizedAlgString(key: "algs.info.f2l.section.history", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.f2l.history.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "size",
                    title: localizedAlgString(key: "algs.info.f2l.section.size", languageCode: languageCode),
                    paragraphs: [],
                    bullets: [
                        localizedAlgString(key: "algs.info.f2l.size.b1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.f2l.size.b2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.f2l.size.b3", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.f2l.size.b4", languageCode: languageCode)
                    ]
                ),
                AlgInfoSection(
                    id: "insights",
                    title: localizedAlgString(key: "algs.info.f2l.section.insights", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.f2l.insights.p1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.f2l.insights.p2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.f2l.insights.p3", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recognition",
                    title: localizedAlgString(key: "algs.info.f2l.section.recognition", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.f2l.recognition.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recommended",
                    title: localizedAlgString(key: "algs.info.f2l.section.recommended", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.f2l.recommended.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "quote",
                    title: localizedAlgString(key: "algs.info.f2l.section.quote", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.f2l.quote.p1", languageCode: languageCode)
                    ],
                    bullets: []
                )
            ]
        )
    }

    private static func makeAdvancedF2LInfo(languageCode: String) -> AlgSetInfoContent {
        AlgSetInfoContent(
            title: localizedAlgString(key: "algs.info.advancedf2l.title", languageCode: languageCode),
            subtitle: localizedAlgString(key: "algs.info.advancedf2l.subtitle", languageCode: languageCode),
            sections: [
                AlgInfoSection(
                    id: "overview",
                    title: localizedAlgString(key: "algs.info.advancedf2l.section.overview", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.advancedf2l.overview.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "history",
                    title: localizedAlgString(key: "algs.info.advancedf2l.section.history", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.advancedf2l.history.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "size",
                    title: localizedAlgString(key: "algs.info.advancedf2l.section.size", languageCode: languageCode),
                    paragraphs: [],
                    bullets: [
                        localizedAlgString(key: "algs.info.advancedf2l.size.b1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.advancedf2l.size.b2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.advancedf2l.size.b3", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.advancedf2l.size.b4", languageCode: languageCode)
                    ]
                ),
                AlgInfoSection(
                    id: "insights",
                    title: localizedAlgString(key: "algs.info.advancedf2l.section.insights", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.advancedf2l.insights.p1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.advancedf2l.insights.p2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.advancedf2l.insights.p3", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recognition",
                    title: localizedAlgString(key: "algs.info.advancedf2l.section.recognition", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.advancedf2l.recognition.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recommended",
                    title: localizedAlgString(key: "algs.info.advancedf2l.section.recommended", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.advancedf2l.recommended.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "quote",
                    title: localizedAlgString(key: "algs.info.advancedf2l.section.quote", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.advancedf2l.quote.p1", languageCode: languageCode)
                    ],
                    bullets: []
                )
            ]
        )
    }

    private static func makeCOLLInfo(languageCode: String) -> AlgSetInfoContent {
        AlgSetInfoContent(
            title: localizedAlgString(key: "algs.info.coll.title", languageCode: languageCode),
            subtitle: localizedAlgString(key: "algs.info.coll.subtitle", languageCode: languageCode),
            sections: [
                AlgInfoSection(
                    id: "overview",
                    title: localizedAlgString(key: "algs.info.coll.section.overview", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.coll.overview.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "history",
                    title: localizedAlgString(key: "algs.info.coll.section.history", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.coll.history.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "size",
                    title: localizedAlgString(key: "algs.info.coll.section.size", languageCode: languageCode),
                    paragraphs: [],
                    bullets: [
                        localizedAlgString(key: "algs.info.coll.size.b1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.coll.size.b2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.coll.size.b3", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.coll.size.b4", languageCode: languageCode)
                    ]
                ),
                AlgInfoSection(
                    id: "insights",
                    title: localizedAlgString(key: "algs.info.coll.section.insights", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.coll.insights.p1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.coll.insights.p2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.coll.insights.p3", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recognition",
                    title: localizedAlgString(key: "algs.info.coll.section.recognition", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.coll.recognition.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recommended",
                    title: localizedAlgString(key: "algs.info.coll.section.recommended", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.coll.recommended.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "quote",
                    title: localizedAlgString(key: "algs.info.coll.section.quote", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.coll.quote.p1", languageCode: languageCode)
                    ],
                    bullets: []
                )
            ]
        )
    }

    private static func makeCLSInfo(languageCode: String) -> AlgSetInfoContent {
        AlgSetInfoContent(
            title: localizedAlgString(key: "algs.info.cls.title", languageCode: languageCode),
            subtitle: localizedAlgString(key: "algs.info.cls.subtitle", languageCode: languageCode),
            sections: [
                AlgInfoSection(
                    id: "overview",
                    title: localizedAlgString(key: "algs.info.cls.section.overview", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.cls.overview.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "history",
                    title: localizedAlgString(key: "algs.info.cls.section.history", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.cls.history.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "size",
                    title: localizedAlgString(key: "algs.info.cls.section.size", languageCode: languageCode),
                    paragraphs: [],
                    bullets: [
                        localizedAlgString(key: "algs.info.cls.size.b1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.cls.size.b2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.cls.size.b3", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.cls.size.b4", languageCode: languageCode)
                    ]
                ),
                AlgInfoSection(
                    id: "insights",
                    title: localizedAlgString(key: "algs.info.cls.section.insights", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.cls.insights.p1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.cls.insights.p2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.cls.insights.p3", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recognition",
                    title: localizedAlgString(key: "algs.info.cls.section.recognition", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.cls.recognition.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recommended",
                    title: localizedAlgString(key: "algs.info.cls.section.recommended", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.cls.recommended.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "quote",
                    title: localizedAlgString(key: "algs.info.cls.section.quote", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.cls.quote.p1", languageCode: languageCode)
                    ],
                    bullets: []
                )
            ]
        )
    }

    private static func makeOLLCPInfo(languageCode: String) -> AlgSetInfoContent {
        AlgSetInfoContent(
            title: localizedAlgString(key: "algs.info.ollcp.title", languageCode: languageCode),
            subtitle: localizedAlgString(key: "algs.info.ollcp.subtitle", languageCode: languageCode),
            sections: [
                AlgInfoSection(
                    id: "overview",
                    title: localizedAlgString(key: "algs.info.ollcp.section.overview", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.ollcp.overview.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "history",
                    title: localizedAlgString(key: "algs.info.ollcp.section.history", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.ollcp.history.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "size",
                    title: localizedAlgString(key: "algs.info.ollcp.section.size", languageCode: languageCode),
                    paragraphs: [],
                    bullets: [
                        localizedAlgString(key: "algs.info.ollcp.size.b1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.ollcp.size.b2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.ollcp.size.b3", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.ollcp.size.b4", languageCode: languageCode)
                    ]
                ),
                AlgInfoSection(
                    id: "insights",
                    title: localizedAlgString(key: "algs.info.ollcp.section.insights", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.ollcp.insights.p1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.ollcp.insights.p2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.ollcp.insights.p3", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recognition",
                    title: localizedAlgString(key: "algs.info.ollcp.section.recognition", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.ollcp.recognition.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recommended",
                    title: localizedAlgString(key: "algs.info.ollcp.section.recommended", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.ollcp.recommended.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "quote",
                    title: localizedAlgString(key: "algs.info.ollcp.section.quote", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.ollcp.quote.p1", languageCode: languageCode)
                    ],
                    bullets: []
                )
            ]
        )
    }

    private static func makeVLSInfo(languageCode: String) -> AlgSetInfoContent {
        AlgSetInfoContent(
            title: localizedAlgString(key: "algs.info.vls.title", languageCode: languageCode),
            subtitle: localizedAlgString(key: "algs.info.vls.subtitle", languageCode: languageCode),
            sections: [
                AlgInfoSection(
                    id: "overview",
                    title: localizedAlgString(key: "algs.info.vls.section.overview", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.vls.overview.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "history",
                    title: localizedAlgString(key: "algs.info.vls.section.history", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.vls.history.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "size",
                    title: localizedAlgString(key: "algs.info.vls.section.size", languageCode: languageCode),
                    paragraphs: [],
                    bullets: [
                        localizedAlgString(key: "algs.info.vls.size.b1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.vls.size.b2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.vls.size.b3", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.vls.size.b4", languageCode: languageCode)
                    ]
                ),
                AlgInfoSection(
                    id: "insights",
                    title: localizedAlgString(key: "algs.info.vls.section.insights", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.vls.insights.p1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.vls.insights.p2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.vls.insights.p3", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recognition",
                    title: localizedAlgString(key: "algs.info.vls.section.recognition", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.vls.recognition.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recommended",
                    title: localizedAlgString(key: "algs.info.vls.section.recommended", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.vls.recommended.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "quote",
                    title: localizedAlgString(key: "algs.info.vls.section.quote", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.vls.quote.p1", languageCode: languageCode)
                    ],
                    bullets: []
                )
            ]
        )
    }

    private static func makeWVInfo(languageCode: String) -> AlgSetInfoContent {
        AlgSetInfoContent(
            title: localizedAlgString(key: "algs.info.wv.title", languageCode: languageCode),
            subtitle: localizedAlgString(key: "algs.info.wv.subtitle", languageCode: languageCode),
            sections: [
                AlgInfoSection(
                    id: "overview",
                    title: localizedAlgString(key: "algs.info.wv.section.overview", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.wv.overview.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "history",
                    title: localizedAlgString(key: "algs.info.wv.section.history", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.wv.history.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "size",
                    title: localizedAlgString(key: "algs.info.wv.section.size", languageCode: languageCode),
                    paragraphs: [],
                    bullets: [
                        localizedAlgString(key: "algs.info.wv.size.b1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.wv.size.b2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.wv.size.b3", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.wv.size.b4", languageCode: languageCode)
                    ]
                ),
                AlgInfoSection(
                    id: "insights",
                    title: localizedAlgString(key: "algs.info.wv.section.insights", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.wv.insights.p1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.wv.insights.p2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.wv.insights.p3", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recognition",
                    title: localizedAlgString(key: "algs.info.wv.section.recognition", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.wv.recognition.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recommended",
                    title: localizedAlgString(key: "algs.info.wv.section.recommended", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.wv.recommended.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "quote",
                    title: localizedAlgString(key: "algs.info.wv.section.quote", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.wv.quote.p1", languageCode: languageCode)
                    ],
                    bullets: []
                )
            ]
        )
    }

    private static func makeSVInfo(languageCode: String) -> AlgSetInfoContent {
        AlgSetInfoContent(
            title: localizedAlgString(key: "algs.info.sv.title", languageCode: languageCode),
            subtitle: localizedAlgString(key: "algs.info.sv.subtitle", languageCode: languageCode),
            sections: [
                AlgInfoSection(
                    id: "overview",
                    title: localizedAlgString(key: "algs.info.sv.section.overview", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.sv.overview.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "history",
                    title: localizedAlgString(key: "algs.info.sv.section.history", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.sv.history.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "size",
                    title: localizedAlgString(key: "algs.info.sv.section.size", languageCode: languageCode),
                    paragraphs: [],
                    bullets: [
                        localizedAlgString(key: "algs.info.sv.size.b1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.sv.size.b2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.sv.size.b3", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.sv.size.b4", languageCode: languageCode)
                    ]
                ),
                AlgInfoSection(
                    id: "insights",
                    title: localizedAlgString(key: "algs.info.sv.section.insights", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.sv.insights.p1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.sv.insights.p2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.sv.insights.p3", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recognition",
                    title: localizedAlgString(key: "algs.info.sv.section.recognition", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.sv.recognition.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recommended",
                    title: localizedAlgString(key: "algs.info.sv.section.recommended", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.sv.recommended.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "quote",
                    title: localizedAlgString(key: "algs.info.sv.section.quote", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.sv.quote.p1", languageCode: languageCode)
                    ],
                    bullets: []
                )
            ]
        )
    }

    private static func makeSBLSInfo(languageCode: String) -> AlgSetInfoContent {
        AlgSetInfoContent(
            title: localizedAlgString(key: "algs.info.sbls.title", languageCode: languageCode),
            subtitle: localizedAlgString(key: "algs.info.sbls.subtitle", languageCode: languageCode),
            sections: [
                AlgInfoSection(
                    id: "overview",
                    title: localizedAlgString(key: "algs.info.sbls.section.overview", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.sbls.overview.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "history",
                    title: localizedAlgString(key: "algs.info.sbls.section.history", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.sbls.history.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "size",
                    title: localizedAlgString(key: "algs.info.sbls.section.size", languageCode: languageCode),
                    paragraphs: [],
                    bullets: [
                        localizedAlgString(key: "algs.info.sbls.size.b1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.sbls.size.b2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.sbls.size.b3", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.sbls.size.b4", languageCode: languageCode)
                    ]
                ),
                AlgInfoSection(
                    id: "insights",
                    title: localizedAlgString(key: "algs.info.sbls.section.insights", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.sbls.insights.p1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.sbls.insights.p2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.sbls.insights.p3", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recognition",
                    title: localizedAlgString(key: "algs.info.sbls.section.recognition", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.sbls.recognition.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recommended",
                    title: localizedAlgString(key: "algs.info.sbls.section.recommended", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.sbls.recommended.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "quote",
                    title: localizedAlgString(key: "algs.info.sbls.section.quote", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.sbls.quote.p1", languageCode: languageCode)
                    ],
                    bullets: []
                )
            ]
        )
    }

    private static func makeCMLLInfo(languageCode: String) -> AlgSetInfoContent {
        AlgSetInfoContent(
            title: localizedAlgString(key: "algs.info.cmll.title", languageCode: languageCode),
            subtitle: localizedAlgString(key: "algs.info.cmll.subtitle", languageCode: languageCode),
            sections: [
                AlgInfoSection(
                    id: "overview",
                    title: localizedAlgString(key: "algs.info.cmll.section.overview", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.cmll.overview.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "history",
                    title: localizedAlgString(key: "algs.info.cmll.section.history", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.cmll.history.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "size",
                    title: localizedAlgString(key: "algs.info.cmll.section.size", languageCode: languageCode),
                    paragraphs: [],
                    bullets: [
                        localizedAlgString(key: "algs.info.cmll.size.b1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.cmll.size.b2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.cmll.size.b3", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.cmll.size.b4", languageCode: languageCode)
                    ]
                ),
                AlgInfoSection(
                    id: "insights",
                    title: localizedAlgString(key: "algs.info.cmll.section.insights", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.cmll.insights.p1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.cmll.insights.p2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.cmll.insights.p3", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recognition",
                    title: localizedAlgString(key: "algs.info.cmll.section.recognition", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.cmll.recognition.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recommended",
                    title: localizedAlgString(key: "algs.info.cmll.section.recommended", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.cmll.recommended.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "quote",
                    title: localizedAlgString(key: "algs.info.cmll.section.quote", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.cmll.quote.p1", languageCode: languageCode)
                    ],
                    bullets: []
                )
            ]
        )
    }

    private static func makeFourAInfo(languageCode: String) -> AlgSetInfoContent {
        AlgSetInfoContent(
            title: localizedAlgString(key: "algs.info.4a.title", languageCode: languageCode),
            subtitle: localizedAlgString(key: "algs.info.4a.subtitle", languageCode: languageCode),
            sections: [
                AlgInfoSection(
                    id: "overview",
                    title: localizedAlgString(key: "algs.info.4a.section.overview", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.4a.overview.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "history",
                    title: localizedAlgString(key: "algs.info.4a.section.history", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.4a.history.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "size",
                    title: localizedAlgString(key: "algs.info.4a.section.size", languageCode: languageCode),
                    paragraphs: [],
                    bullets: [
                        localizedAlgString(key: "algs.info.4a.size.b1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.4a.size.b2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.4a.size.b3", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.4a.size.b4", languageCode: languageCode)
                    ]
                ),
                AlgInfoSection(
                    id: "insights",
                    title: localizedAlgString(key: "algs.info.4a.section.insights", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.4a.insights.p1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.4a.insights.p2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.4a.insights.p3", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recognition",
                    title: localizedAlgString(key: "algs.info.4a.section.recognition", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.4a.recognition.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recommended",
                    title: localizedAlgString(key: "algs.info.4a.section.recommended", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.4a.recommended.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "quote",
                    title: localizedAlgString(key: "algs.info.4a.section.quote", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.4a.quote.p1", languageCode: languageCode)
                    ],
                    bullets: []
                )
            ]
        )
    }

    private static func makeZBLSInfo(languageCode: String) -> AlgSetInfoContent {
        AlgSetInfoContent(
            title: localizedAlgString(key: "algs.info.zbls.title", languageCode: languageCode),
            subtitle: localizedAlgString(key: "algs.info.zbls.subtitle", languageCode: languageCode),
            sections: [
                AlgInfoSection(
                    id: "overview",
                    title: localizedAlgString(key: "algs.info.zbls.section.overview", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.zbls.overview.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "history",
                    title: localizedAlgString(key: "algs.info.zbls.section.history", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.zbls.history.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "size",
                    title: localizedAlgString(key: "algs.info.zbls.section.size", languageCode: languageCode),
                    paragraphs: [],
                    bullets: [
                        localizedAlgString(key: "algs.info.zbls.size.b1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.zbls.size.b2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.zbls.size.b3", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.zbls.size.b4", languageCode: languageCode)
                    ]
                ),
                AlgInfoSection(
                    id: "insights",
                    title: localizedAlgString(key: "algs.info.zbls.section.insights", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.zbls.insights.p1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.zbls.insights.p2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.zbls.insights.p3", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recognition",
                    title: localizedAlgString(key: "algs.info.zbls.section.recognition", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.zbls.recognition.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recommended",
                    title: localizedAlgString(key: "algs.info.zbls.section.recommended", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.zbls.recommended.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "quote",
                    title: localizedAlgString(key: "algs.info.zbls.section.quote", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.zbls.quote.p1", languageCode: languageCode)
                    ],
                    bullets: []
                )
            ]
        )
    }

    private static func makeOneLLLInfo(languageCode: String) -> AlgSetInfoContent {
        AlgSetInfoContent(
            title: localizedAlgString(key: "algs.info.1lll.title", languageCode: languageCode),
            subtitle: localizedAlgString(key: "algs.info.1lll.subtitle", languageCode: languageCode),
            sections: [
                AlgInfoSection(
                    id: "overview",
                    title: localizedAlgString(key: "algs.info.1lll.section.overview", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.1lll.overview.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "history",
                    title: localizedAlgString(key: "algs.info.1lll.section.history", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.1lll.history.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "size",
                    title: localizedAlgString(key: "algs.info.1lll.section.size", languageCode: languageCode),
                    paragraphs: [],
                    bullets: [
                        localizedAlgString(key: "algs.info.1lll.size.b1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.1lll.size.b2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.1lll.size.b3", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.1lll.size.b4", languageCode: languageCode)
                    ]
                ),
                AlgInfoSection(
                    id: "insights",
                    title: localizedAlgString(key: "algs.info.1lll.section.insights", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.1lll.insights.p1", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.1lll.insights.p2", languageCode: languageCode),
                        localizedAlgString(key: "algs.info.1lll.insights.p3", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recognition",
                    title: localizedAlgString(key: "algs.info.1lll.section.recognition", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.1lll.recognition.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "recommended",
                    title: localizedAlgString(key: "algs.info.1lll.section.recommended", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.1lll.recommended.p1", languageCode: languageCode)
                    ],
                    bullets: []
                ),
                AlgInfoSection(
                    id: "quote",
                    title: localizedAlgString(key: "algs.info.1lll.section.quote", languageCode: languageCode),
                    paragraphs: [
                        localizedAlgString(key: "algs.info.1lll.quote.p1", languageCode: languageCode)
                    ],
                    bullets: []
                )
            ]
        )
    }

    private static func makeZBLLInfo(languageCode: String) -> AlgSetInfoContent {
        return AlgSetInfoContent(
            title: localizedAlgString(key: "algs.info.zbll.title", languageCode: languageCode),
            subtitle: localizedAlgString(key: "algs.info.zbll.subtitle", languageCode: languageCode),
            sections: [
            AlgInfoSection(
                id: "overview",
                title: localizedAlgString(key: "algs.info.zbll.section.overview", languageCode: languageCode),
                paragraphs: [
                    localizedAlgString(key: "algs.info.zbll.overview.p1", languageCode: languageCode)
                ],
                bullets: []
            ),
            AlgInfoSection(
                id: "history",
                title: localizedAlgString(key: "algs.info.zbll.section.history", languageCode: languageCode),
                paragraphs: [
                    localizedAlgString(key: "algs.info.zbll.history.p1", languageCode: languageCode)
                ],
                bullets: []
            ),
            AlgInfoSection(
                id: "size",
                title: localizedAlgString(key: "algs.info.zbll.section.size", languageCode: languageCode),
                paragraphs: [],
                bullets: [
                    localizedAlgString(key: "algs.info.zbll.size.b1", languageCode: languageCode),
                    localizedAlgString(key: "algs.info.zbll.size.b2", languageCode: languageCode),
                    localizedAlgString(key: "algs.info.zbll.size.b3", languageCode: languageCode),
                    localizedAlgString(key: "algs.info.zbll.size.b4", languageCode: languageCode)
                ]
            ),
            AlgInfoSection(
                id: "insights",
                title: localizedAlgString(key: "algs.info.zbll.section.insights", languageCode: languageCode),
                paragraphs: [
                    localizedAlgString(key: "algs.info.zbll.insights.p1", languageCode: languageCode),
                    localizedAlgString(key: "algs.info.zbll.insights.p2", languageCode: languageCode),
                    localizedAlgString(key: "algs.info.zbll.insights.p3", languageCode: languageCode)
                ],
                bullets: []
            ),
            AlgInfoSection(
                id: "recognition",
                title: localizedAlgString(key: "algs.info.zbll.section.recognition", languageCode: languageCode),
                paragraphs: [
                    localizedAlgString(key: "algs.info.zbll.recognition.p1", languageCode: languageCode)
                ],
                bullets: []
            ),
            AlgInfoSection(
                id: "recommended",
                title: localizedAlgString(key: "algs.info.zbll.section.recommended", languageCode: languageCode),
                paragraphs: [
                    localizedAlgString(key: "algs.info.zbll.recommended.p1", languageCode: languageCode)
                ],
                bullets: []
            ),
            AlgInfoSection(
                id: "quote",
                title: localizedAlgString(key: "algs.info.zbll.section.quote", languageCode: languageCode),
                paragraphs: [
                    localizedAlgString(key: "algs.info.zbll.quote.p1", languageCode: languageCode)
                ],
                bullets: []
            )
        ])
    }
}

struct AlgCaseDetailView: View {
    let payload: AlgSetPayload
    let algCase: AlgCase
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("algLearnedCasesStore") private var learnedCasesStore: String = "{}"
    @Environment(\.setAlgBottomAccessoryVisible) private var setAlgBottomAccessoryVisible
    @State private var selectedAlgorithmGroupID: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if !algCase.recognition.isEmpty {
                    detailSection(title: localizedAlgString(key: "algs.recognition", languageCode: appLanguage)) {
                        Text(algCase.recognition)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }

                if !algCase.notes.isEmpty {
                    detailSection(title: localizedAlgString(key: "algs.notes", languageCode: appLanguage)) {
                        Text(algCase.notes)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }

                if let setup = algCase.setup, !setup.isEmpty {
                    detailSection(title: localizedAlgString(key: "algs.setup", languageCode: appLanguage)) {
                        setupText(setup)
                    }
                }

                detailSection(title: localizedAlgString(key: "algs.algorithms", languageCode: appLanguage)) {
                    algorithmsContent
                }

                if let sourceURL {
                    Text(sourceFooterText(for: sourceURL))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollAwareNavigationTitle(
            localizedAlgCaseName(
                setID: payload.set,
                caseName: algCase.displayName,
                languageCode: appLanguage
            )
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    learnedCasesStore = updatedLearnedCaseStorage(
                        storage: learnedCasesStore,
                        setID: payload.set,
                        caseID: algCase.id,
                        learned: !isLearned
                    )
                } label: {
                    Image(systemName: isLearned ? "graduationcap.fill" : "graduationcap")
                        .foregroundStyle(.orange)
                }
            }
        }
        .onAppear {
            setAlgBottomAccessoryVisible(false)
            guard selectedAlgorithmGroupID.isEmpty,
                  let firstDirectionalGroup = directionalAlgorithmGroups?.first else { return }
            selectedAlgorithmGroupID = firstDirectionalGroup.id
        }
        .onDisappear {
            setAlgBottomAccessoryVisible(true)
        }
    }

    private var isLearned: Bool {
        isAlgCaseLearned(setID: payload.set, caseID: algCase.id, storage: learnedCasesStore)
    }

    private var sourceURL: URL? {
        algSourceURL(puzzle: payload.puzzle, setID: payload.set)
    }

    private func sourceFooterText(for url: URL) -> String {
        String(
            format: localizedAlgString(key: "algs.source_format", languageCode: appLanguage),
            url.absoluteString
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            caseImage
                .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 6) {
                ScrollAwareContentTitle(
                    title: localizedAlgCaseName(
                        setID: payload.set,
                        caseName: algCase.displayName,
                        languageCode: appLanguage
                    )
                )
                    .font(.system(size: 34, weight: .bold))

                Text(headerMetadata)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var headerMetadata: String {
        [
            payload.set,
            localizedSubgroup(algCase.subgroup),
            localizedAlgorithmCount(algCase.displayAlgorithmsCount, languageCode: appLanguage)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    @ViewBuilder
    private var caseImage: some View {
        #if os(iOS)
        if let image = AlgCaseImageProvider.image(named: algCase.imageKey) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            fallbackCaseImage
        }
        #else
        fallbackCaseImage
        #endif
    }

    private var fallbackCaseImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.blue.opacity(0.12))

            Text(localizedAlgCaseName(setID: payload.set, caseName: algCase.displayName, languageCode: appLanguage))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.blue)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .padding(.horizontal, 8)
        }
    }

    private func detailSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)

            content()
        }
    }

    @ViewBuilder
    private var algorithmsContent: some View {
        if let directionalAlgorithmGroups {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Direction", selection: directionalAlgorithmGroupSelection) {
                    ForEach(directionalAlgorithmGroups) { group in
                        Text(localizedGroupTitle(group.title))
                            .tag(group.id)
                    }
                }
                .pickerStyle(.segmented)

                if let selectedGroup = selectedDirectionalAlgorithmGroup(from: directionalAlgorithmGroups) {
                    groupedAlgorithmsSection(selectedGroup, showsHeader: false)
                }
            }
        } else if algCase.hasAlgorithmGroups, let algorithmGroups = algCase.algorithmGroups {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(algorithmGroups) { group in
                    groupedAlgorithmsSection(group, showsHeader: true)
                }
            }
        } else {
            VStack(spacing: 12) {
                algorithmCards(for: algCase.algorithms)
            }
        }
    }

    private var directionalAlgorithmGroups: [AlgFormulaGroup]? {
        let supportsDirectionalPicker =
            payload.set.caseInsensitiveCompare("f2l") == .orderedSame ||
            payload.set.caseInsensitiveCompare("advancedf2l") == .orderedSame

        guard supportsDirectionalPicker,
              let algorithmGroups = algCase.algorithmGroups,
              algorithmGroups.count == 4 else { return nil }

        let supportedTitles = Set(["front right", "front left", "back left", "back right"])
        let normalizedTitles = Set(algorithmGroups.map { $0.title.lowercased() })
        guard normalizedTitles == supportedTitles else { return nil }
        return algorithmGroups
    }

    private var directionalAlgorithmGroupSelection: Binding<String> {
        Binding(
            get: {
                if let selectedGroup = selectedDirectionalAlgorithmGroup(from: directionalAlgorithmGroups ?? []) {
                    return selectedGroup.id
                }
                return directionalAlgorithmGroups?.first?.id ?? ""
            },
            set: { selectedAlgorithmGroupID = $0 }
        )
    }

    private func selectedDirectionalAlgorithmGroup(from groups: [AlgFormulaGroup]) -> AlgFormulaGroup? {
        if let selected = groups.first(where: { $0.id == selectedAlgorithmGroupID }) {
            return selected
        }
        return groups.first
    }

    private func groupedAlgorithmsSection(_ group: AlgFormulaGroup, showsHeader: Bool) -> some View {
        let localizedTitle = localizedGroupTitle(group.title)

        return VStack(alignment: .leading, spacing: 10) {
            if showsHeader, !localizedTitle.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(localizedTitle)
                        .font(.system(size: 18, weight: .semibold))

                    Text(localizedAlgorithmCount(group.algorithms.count, languageCode: appLanguage))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let setup = group.setup, !setup.isEmpty {
                setupText(setup)
            }

            VStack(spacing: 12) {
                algorithmCards(for: group.algorithms)
            }
        }
    }

    private func localizedGroupTitle(_ title: String) -> String {
        if title.lowercased().hasPrefix("orientation ") {
            return ""
        }

        switch title.lowercased() {
        case "front right":
            return localizedAlgString(key: "algs.orientation.front_right", languageCode: appLanguage)
        case "front left":
            return localizedAlgString(key: "algs.orientation.front_left", languageCode: appLanguage)
        case "back left":
            return localizedAlgString(key: "algs.orientation.back_left", languageCode: appLanguage)
        case "back right":
            return localizedAlgString(key: "algs.orientation.back_right", languageCode: appLanguage)
        default:
            return title
        }
    }

    private func localizedSubgroup(_ subgroup: String) -> String {
        if let key = algSubgroupLocalizationKey(subgroup) {
            return localizedAlgString(key: key, languageCode: appLanguage)
        }

        switch subgroup.lowercased() {
        case "free pairs":
            return localizedAlgString(key: "algs.f2l.subgroup.free_pairs", languageCode: appLanguage)
        case "connected pairs":
            return localizedAlgString(key: "algs.f2l.subgroup.connected_pairs", languageCode: appLanguage)
        case "corner in slot":
            return localizedAlgString(key: "algs.f2l.subgroup.corner_in_slot", languageCode: appLanguage)
        case "disconnected pairs":
            return localizedAlgString(key: "algs.f2l.subgroup.disconnected_pairs", languageCode: appLanguage)
        case "edge in slot":
            return localizedAlgString(key: "algs.f2l.subgroup.edge_in_slot", languageCode: appLanguage)
        case "pieces in slot":
            return localizedAlgString(key: "algs.f2l.subgroup.pieces_in_slot", languageCode: appLanguage)
        case "adj swap":
            return localizedAlgString(key: "algs.pll.subgroup.adj_swap", languageCode: appLanguage)
        case "opp swap":
            return localizedAlgString(key: "algs.pll.subgroup.opp_swap", languageCode: appLanguage)
        case "anti sune":
            return localizedAlgString(key: "algs.subgroup.anti_sune_display", languageCode: appLanguage)
        case "sune":
            return localizedAlgString(key: "algs.subgroup.sune_display", languageCode: appLanguage)
        default:
            return subgroup
        }
    }

    private func setupText(_ setup: String) -> some View {
        Text(setup)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.secondary.opacity(0.08))
            )
    }

    @ViewBuilder
    private func algorithmCards(for algorithms: [AlgFormula]) -> some View {
        let primaryAlgorithms = algorithms.filter(\.isPrimary)
        let secondaryAlgorithms = algorithms.filter { !$0.isPrimary }

        if let primary = primaryAlgorithms.first {
            algorithmCard(primary)
        } else if let first = algorithms.first {
            algorithmCard(first)
        }

        if !secondaryAlgorithms.isEmpty {
            secondaryAlgorithmsCard(secondaryAlgorithms)
        }
    }

    private func algorithmCard(_ algorithm: AlgFormula) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if algorithm.isPrimary {
                Text(localizedAlgString(key: "algs.primary", languageCode: appLanguage))
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(.blue)
                    .background(.blue.opacity(0.12), in: Capsule())
            }

            Text(algorithm.notation)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .textSelection(.enabled)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !algorithm.tags.isEmpty {
                Text(algorithm.tags.joined(separator: " · "))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    private func secondaryAlgorithmsCard(_ algorithms: [AlgFormula]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(algorithms.enumerated()), id: \.element.id) { index, algorithm in
                if index > 0 {
                    Divider()
                        .padding(.vertical, 10)
                }

                secondaryAlgorithmRow(algorithm)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    private func secondaryAlgorithmRow(_ algorithm: AlgFormula) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(algorithm.notation)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .textSelection(.enabled)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !algorithm.tags.isEmpty {
                Text(algorithm.tags.joined(separator: " · "))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}
#endif

#if os(iOS)
private struct LearnedProgressCircle: View {
    let progress: Double

    var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            Image(systemName: "circle", variableValue: clampedProgress)
                .font(.system(size: 16, weight: .medium))
                .symbolVariableValueMode(.draw)
                .foregroundStyle(.blue)
        } else if #available(iOS 16.0, *) {
            Image(systemName: "circle", variableValue: clampedProgress)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.blue)
        } else {
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.18), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
        }
    }
}
#endif
