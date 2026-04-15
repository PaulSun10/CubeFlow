import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif

#if os(iOS)
struct AlgsTabView: View {
    @State private var selectedPuzzle: AlgPuzzle = .threeByThree
    @State private var isShowingRecentPractice = false
    @State private var isShowingSearch = false
    @State private var recentPracticeNavigationContext: AlgRecentPracticeContext?
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("algLearnedCasesStore") private var learnedCasesStore: String = "{}"
    @AppStorage("algOverviewBrowseViewMode") private var overviewBrowseViewModeStore: String = AlgBrowseViewMode.list.rawValue
    @AppStorage("algTrainerAttemptStore") private var trainerAttemptStore: String = "[]"
    @AppStorage("algDismissedRecentPracticeRecordID") private var dismissedRecentPracticeRecordID: String = ""

    private var sections: [AlgSectionData] {
        guard selectedPuzzle == .threeByThree else { return [] }
        return AlgSectionData.threeByThreeSections
    }

    private var overviewBrowseViewMode: AlgBrowseViewMode {
        AlgBrowseViewMode(rawValue: overviewBrowseViewModeStore) ?? .list
    }

    private var overviewGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]
    }

    private var recentPracticeContext: AlgRecentPracticeContext? {
        guard selectedPuzzle == .threeByThree else { return nil }

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
            let title = AlgSectionData.threeByThreeSections
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
        guard selectedPuzzle == .threeByThree else { return [] }
        return makeAlgTrainerWeakReviewItems(
            from: decodeAlgTrainerAttempts(from: trainerAttemptStore),
            languageCode: appLanguage
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if sections.isEmpty || overviewBrowseViewMode == .list {
                    overviewListContent
                } else {
                    overviewGridContent
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !sections.isEmpty {
                    overviewBottomBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .navigationDestination(isPresented: $isShowingRecentPractice) {
                if let context = recentPracticeNavigationContext {
                    recentPracticeDestinationView(for: context)
                }
            }
            .navigationDestination(isPresented: $isShowingSearch) {
                AlgSearchView(items: overviewSearchItems, languageCode: appLanguage)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var overviewListContent: some View {
        List {
            topHeader
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: -4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if let recentPracticeContext, recentPracticeContext.dismissToken != dismissedRecentPracticeRecordID {
                recentPracticeCard(recentPracticeContext)
                .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
            }

            if !weakPracticeItems.isEmpty {
                NavigationLink {
                    AlgTrainerWeakReviewView(items: weakPracticeItems, languageCode: appLanguage)
                } label: {
                    weakPracticeCard
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
            }

            if sections.isEmpty {
                Text("algs.coming_soon")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            NavigationLink {
                                destinationView(for: item)
                            } label: {
                                algRow(item)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 2, trailing: 16))
                        }
                    } header: {
                        sectionHeader(section.localizedTitleKey)
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(6)
    }

    private var overviewGridContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if let recentPracticeContext, recentPracticeContext.dismissToken != dismissedRecentPracticeRecordID {
                    recentPracticeCard(recentPracticeContext)
                    .padding(.top, 10)
                    .padding(.horizontal, 16)
                }

                if !weakPracticeItems.isEmpty {
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
            }
            .padding(.bottom, 88)
        }
    }

    private var overviewBottomBar: some View {
        HStack(spacing: 0) {
            Button {
                isShowingSearch = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                    Text(localizedAlgString(key: "algs.search.placeholder", languageCode: appLanguage))
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
                .padding(.trailing, 12)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 24)
                .padding(.horizontal, 4)

            overviewBrowseInlineButton
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.clear)
        )
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var overviewBrowseInlineButton: some View {
        Menu {
            Section(localizedAlgString(key: "algs.menu.view", languageCode: appLanguage)) {
                Picker(localizedAlgString(key: "algs.menu.view", languageCode: appLanguage), selection: overviewBrowseViewModeSelection) {
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var topHeader: some View {
        HStack {
            Text("tab.algs")
                .font(.system(size: 40, weight: .bold))
            Spacer()
            puzzlePickerMenu
        }
    }

    private func sectionHeader(_ titleKey: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleKey)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.82))

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

            Menu(appLocalizedString("timer.menu.bld", languageCode: appLanguage)) {
                ForEach(AlgPuzzle.blindfoldedCases) { puzzle in
                    Button(appLocalizedString(puzzle.localizedTitleKey, languageCode: appLanguage)) {
                        selectedPuzzle = puzzle
                    }
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.capsule)
            .clipShape(.capsule)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private var overviewBrowseOptionsButton: some View {
        Menu {
            Section(localizedAlgString(key: "algs.menu.view", languageCode: appLanguage)) {
                Picker(localizedAlgString(key: "algs.menu.view", languageCode: appLanguage), selection: overviewBrowseViewModeSelection) {
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
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
    }

    private var overviewBrowseViewModeSelection: Binding<String> {
        Binding(
            get: { overviewBrowseViewMode.rawValue },
            set: { newValue in
                guard let mode = AlgBrowseViewMode(rawValue: newValue) else { return }
                overviewBrowseViewModeStore = mode.rawValue
            }
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
        }
        .padding(.vertical, 4)
    }

    private var overviewSearchItems: [AlgSearchItem] {
        guard selectedPuzzle == .threeByThree else { return [] }

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
                        items.append(
                            AlgSearchItem(
                                id: "case::\(item.id)::\(algCase.id)",
                                kind: .caseName,
                                title: algCase.displayName,
                                subtitle: caseSubtitle,
                                searchableText: [
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

        guard selectedPuzzle == .threeByThree,
              let set = AlgLibrarySet(itemID: item.id),
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
        if selectedPuzzle == .threeByThree,
           let set = AlgLibrarySet(itemID: item.id),
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
#endif

private enum AlgPuzzle: String, CaseIterable, Identifiable {
    case twoByTwo = "2x2"
    case threeByThree = "3x3"
    case fourByFour = "4x4"
    case fiveByFive = "5x5"
    case sixBySix = "6x6"
    case sevenBySeven = "7x7"
    case megaminx = "Megaminx"
    case pyraminx = "Pyraminx"
    case squareOne = "Square-1"
    case clock = "Clock"
    case skewb = "Skewb"
    case threeByThreeBLD = "3x3 bld"
    case fourByFourBLD = "4x4 bld"
    case fiveByFiveBLD = "5x5 bld"

    var id: String { rawValue }

    var localizedTitleKey: String {
        switch self {
        case .twoByTwo: return "event.2x2"
        case .threeByThree: return "event.3x3"
        case .fourByFour: return "event.4x4"
        case .fiveByFive: return "event.5x5"
        case .sixBySix: return "event.6x6"
        case .sevenBySeven: return "event.7x7"
        case .megaminx: return "event.megaminx"
        case .pyraminx: return "event.pyraminx"
        case .squareOne: return "event.square1"
        case .clock: return "event.clock"
        case .skewb: return "event.skewb"
        case .threeByThreeBLD: return "event.3x3bld"
        case .fourByFourBLD: return "event.4x4bld"
        case .fiveByFiveBLD: return "event.5x5bld"
        }
    }

    static var regularCases: [AlgPuzzle] {
        [
            .twoByTwo, .threeByThree, .fourByFour, .fiveByFive, .sixBySix, .sevenBySeven,
            .megaminx, .pyraminx, .squareOne, .clock, .skewb
        ]
    }

    static var blindfoldedCases: [AlgPuzzle] {
        [.threeByThreeBLD, .fourByFourBLD, .fiveByFiveBLD]
    }
}

private struct AlgSectionData: Identifiable {
    let id: String
    let localizedTitleKey: LocalizedStringKey
    let items: [AlgItemData]

    static let threeByThreeSections: [AlgSectionData] = [
        AlgSectionData(
            id: "cfop",
            localizedTitleKey: "algs.section.cfop",
            items: [
                AlgItemData(
                    id: "f2l",
                    localizedTitleKey: "algs.item.f2l.title",
                    algorithmCount: 41,
                    localizedDescriptionKey: "algs.item.f2l.description"
                ),
                AlgItemData(
                    id: "oll",
                    localizedTitleKey: "algs.item.oll.title",
                    algorithmCount: 57,
                    localizedDescriptionKey: "algs.item.oll.description"
                ),
                AlgItemData(
                    id: "pll",
                    localizedTitleKey: "algs.item.pll.title",
                    algorithmCount: 21,
                    localizedDescriptionKey: "algs.item.pll.description"
                )
            ]
        ),
        AlgSectionData(
            id: "advanced",
            localizedTitleKey: "algs.section.advanced",
            items: [
                AlgItemData(
                    id: "advancedf2l",
                    localizedTitleKey: "algs.item.advancedf2l.title",
                    algorithmCount: 54,
                    localizedDescriptionKey: "algs.item.advancedf2l.description"
                ),
                AlgItemData(
                    id: "coll",
                    localizedTitleKey: "algs.item.coll.title",
                    algorithmCount: 40,
                    localizedDescriptionKey: "algs.item.coll.description"
                ),
                AlgItemData(
                    id: "wv",
                    localizedTitleKey: "algs.item.wv.title",
                    algorithmCount: 27,
                    localizedDescriptionKey: "algs.item.wv.description"
                ),
                AlgItemData(
                    id: "sv",
                    localizedTitleKey: "algs.item.sv.title",
                    algorithmCount: 27,
                    localizedDescriptionKey: "algs.item.sv.description"
                ),
                AlgItemData(
                    id: "cls",
                    localizedTitleKey: "algs.item.cls.title",
                    algorithmCount: 97,
                    localizedDescriptionKey: "algs.item.cls.description"
                )
            ]
        ),
        AlgSectionData(
            id: "roux",
            localizedTitleKey: "algs.section.roux",
            items: [
                AlgItemData(
                    id: "sbls",
                    localizedTitleKey: "algs.item.sbls.title",
                    algorithmCount: 65,
                    localizedDescriptionKey: "algs.item.sbls.description"
                ),
                AlgItemData(
                    id: "cmll",
                    localizedTitleKey: "algs.item.cmll.title",
                    algorithmCount: 42,
                    localizedDescriptionKey: "algs.item.cmll.description"
                ),
                AlgItemData(
                    id: "4a",
                    localizedTitleKey: "algs.item.4a.title",
                    algorithmCount: 9,
                    localizedDescriptionKey: "algs.item.4a.description"
                )
            ]
        ),
        AlgSectionData(
            id: "large_sets",
            localizedTitleKey: "algs.section.large_sets",
            items: [
                AlgItemData(
                    id: "zbll",
                    localizedTitleKey: "algs.item.zbll.title",
                    algorithmCount: 472,
                    localizedDescriptionKey: "algs.item.zbll.description"
                ),
                AlgItemData(
                    id: "vls",
                    localizedTitleKey: "algs.item.vls.title",
                    algorithmCount: 189,
                    localizedDescriptionKey: "algs.item.vls.description"
                ),
                AlgItemData(
                    id: "ollcp",
                    localizedTitleKey: "algs.item.ollcp.title",
                    algorithmCount: 342,
                    localizedDescriptionKey: "algs.item.ollcp.description"
                ),
                AlgItemData(
                    id: "zbls",
                    localizedTitleKey: "algs.item.zbls.title",
                    algorithmCount: 302,
                    localizedDescriptionKey: "algs.item.zbls.description"
                ),
                AlgItemData(
                    id: "1lll",
                    localizedTitleKey: "algs.item.1lll.title",
                    algorithmCount: 3914,
                    localizedDescriptionKey: "algs.item.1lll.description"
                )
            ]
        )
    ]
}

private struct AlgItemData: Identifiable {
    let id: String
    let localizedTitleKey: LocalizedStringKey
    let algorithmCount: Int
    var learnedPercent: Int = 0
    var localizedDescriptionKey: LocalizedStringKey = ""

    var imageAssetName: String {
        "alg_\(id)"
    }

    var usesCaseCount: Bool {
        ["f2l", "advancedf2l", "oll", "pll", "coll", "wv", "sv", "cls", "sbls", "cmll", "4a", "zbll", "vls", "ollcp", "1lll"].contains(id)
    }

    var title: LocalizedStringKey { localizedTitleKey }

    var description: LocalizedStringKey { localizedDescriptionKey }
}

private enum AlgBrowseViewMode: String {
    case list
    case grid
}

private enum AlgBrowseOrganization: String {
    case number
    case subset
}

private enum AlgSearchItemKind: Int, Comparable {
    case set
    case subset
    case caseName

    static func < (lhs: AlgSearchItemKind, rhs: AlgSearchItemKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

private enum AlgSearchDestination {
    case set(AlgSetPayload)
    case subset(AlgSetPayload, AlgSubset)
    case caseDetail(AlgSetPayload, AlgCase)
    case placeholder(AlgItemData)
}

private struct AlgSearchItem: Identifiable {
    let id: String
    let kind: AlgSearchItemKind
    let title: String
    let subtitle: String
    let searchableText: [String]
    let destination: AlgSearchDestination

    func matches(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return true }
        return searchableText.joined(separator: " ").lowercased().contains(normalizedQuery)
    }
}

private struct AlgSubset: Identifiable, Hashable {
    let id: String
    let title: String
    let cases: [AlgCase]

    var uniqueCaseIDs: [String] {
        Array(Set(cases.map(\.id))).sorted()
    }

    var uniqueCaseCount: Int {
        uniqueCaseIDs.count
    }
}

private struct AlgSubsetGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let subsets: [AlgSubset]

    var uniqueCaseIDs: [String] {
        Array(Set(subsets.flatMap(\.uniqueCaseIDs))).sorted()
    }

    var uniqueCaseCount: Int {
        uniqueCaseIDs.count
    }
}

private struct AlgCaseGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let cases: [AlgCase]

    var uniqueCaseIDs: [String] {
        Array(Set(cases.map(\.id))).sorted()
    }

    var uniqueCaseCount: Int {
        uniqueCaseIDs.count
    }
}

private enum AlgTrainerRecognitionLevel: String, Codable {
    case group
    case subset
    case caseName
}

private struct AlgTrainerQuestionSeed: Identifiable, Hashable {
    let id: String
    let algCase: AlgCase
    let answerID: String
    let answerTitle: String
}

private struct AlgTrainerQuestionChoice: Identifiable, Hashable {
    let id: String
    let title: String
}

private struct AlgTrainerQuestion: Identifiable, Hashable {
    let id: String
    let algCase: AlgCase
    let choices: [AlgTrainerQuestionChoice]
    let correctAnswerID: String
    let correctAnswerTitle: String
}

private struct AlgTrainerAttemptRecord: Identifiable, Codable, Hashable {
    let id: String
    let setID: String
    let scopeID: String
    let level: AlgTrainerRecognitionLevel
    let caseID: String
    let answerID: String?
    let isCorrect: Bool
    let isSkipped: Bool
    let timestamp: Date
}

private struct AlgRecentPracticeContext: Identifiable {
    let id: String
    let dismissToken: String
    let title: String
    let subtitle: String
    let destination: AlgRecentPracticeDestination
}

private enum AlgRecentPracticeDestination {
    case set(AlgSetPayload)
    case subset(AlgSetPayload, AlgSubset)
}

private struct AlgTrainerWeakReviewItem: Identifiable {
    let id: String
    let setTitle: String
    let caseTitle: String
    let subtitle: String
    let payload: AlgSetPayload
    let algCase: AlgCase
    let lastAttempt: Date
}

private struct AlgTrainerSessionSummary {
    let title: String
    let scopeTitle: String
    let languageCode: String
    let answeredCount: Int
    let correctCount: Int
    let wrongCount: Int
    let skipCount: Int
    let bestStreak: Int
    let sessionDuration: TimeInterval
    let averageRecognitionDuration: TimeInterval?
}

private func decodeAlgTrainerAttempts(from store: String) -> [AlgTrainerAttemptRecord] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([AlgTrainerAttemptRecord].self, from: Data(store.utf8))) ?? []
}

private func makeAlgTrainerWeakReviewItems(from records: [AlgTrainerAttemptRecord], languageCode: String) -> [AlgTrainerWeakReviewItem] {
    let grouped = Dictionary(grouping: records) { "\($0.setID)::\($0.caseID)" }

    let setTitles = Dictionary(uniqueKeysWithValues: AlgSectionData.threeByThreeSections
        .flatMap(\.items)
        .map { ($0.id.lowercased(), appLocalizedString("algs.item.\($0.id).title", languageCode: languageCode, defaultValue: $0.id)) })

    return grouped.compactMap { _, attempts in
        guard let first = attempts.first,
              let latestAttempt = attempts.max(by: { $0.timestamp < $1.timestamp }),
              let set = AlgLibrarySet(itemID: first.setID),
              let payload = AlgLibraryLoader.load(set),
              let algCase = payload.cases.first(where: { $0.id == first.caseID }) else {
            return nil
        }

        let answeredAttempts = attempts.filter { !$0.isSkipped }
        let totalAnswered = answeredAttempts.count
        let mistakeCount = attempts.filter { !$0.isCorrect && !$0.isSkipped }.count
        guard mistakeCount >= 5 else { return nil }

        let errorRate = Double(mistakeCount) / Double(totalAnswered)
        guard errorRate > 0.5 else { return nil }

        let errorPercent = Int((errorRate * 100).rounded())
        let subtitle = String(
            format: localizedAlgString(key: "algs.trainer.weak_item_subtitle_format", languageCode: languageCode),
            errorPercent,
            mistakeCount,
            totalAnswered
        )

        return AlgTrainerWeakReviewItem(
            id: "\(first.setID)::\(first.caseID)",
            setTitle: setTitles[first.setID.lowercased()] ?? payload.set,
            caseTitle: algCase.displayName,
            subtitle: subtitle,
            payload: payload,
            algCase: algCase,
            lastAttempt: latestAttempt.timestamp
        )
    }
    .sorted {
        if $0.lastAttempt != $1.lastAttempt {
            return $0.lastAttempt > $1.lastAttempt
        }
        return $0.caseTitle < $1.caseTitle
    }
}

private func formatAlgTrainerSessionDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = max(Int(duration.rounded(.down)), 0)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    return String(format: "%02d:%02d", minutes, seconds)
}

private func formatAlgTrainerAverageDuration(_ duration: TimeInterval, languageCode: String) -> String {
    String(
        format: localizedAlgString(key: "algs.trainer.average_time_format", languageCode: languageCode),
        duration
    )
}

private func normalizedAlgSetID(_ setID: String) -> String {
    setID.lowercased()
}

private func normalizedAlgPreviewSlug(_ title: String) -> String {
    title
        .lowercased()
        .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
}

private func algGroupPreviewImageKey(setID: String, title: String) -> String? {
    let normalizedSet = normalizedAlgSetID(setID)
    switch normalizedSet {
    case "ollcp":
        let number = title.replacingOccurrences(of: "OLLCP", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !number.isEmpty {
            return "ollcp_group_ollcp_\(number)"
        }
        return "ollcp_group_\(normalizedAlgPreviewSlug(title))"
    case "zbll", "vls", "1lll":
        return "\(normalizedSet)_group_\(normalizedAlgPreviewSlug(title))"
    default:
        return nil
    }
}

private func algSubsetPreviewImageKey(setID: String, parentGroupTitle: String? = nil, subsetTitle: String) -> String? {
    let normalizedSet = normalizedAlgSetID(setID)
    if normalizedSet == "zbll" || (parentGroupTitle?.hasPrefix("ZBLL ") == true) {
        return "zbll_subset_\(normalizedAlgPreviewSlug(subsetTitle))"
    }

    return nil
}

private func displayAlgGroupTitle(setID: String, title: String) -> String {
    guard normalizedAlgSetID(setID) == "zbll" else { return title }

    switch title {
    case "U", "L", "T", "H", "Pi", "S", "AS":
        return "ZBLL \(title)"
    default:
        return title
    }
}

private func orderedSubsets(from cases: [AlgCase]) -> [AlgSubset] {
    var orderedTitles: [String] = []
    var grouped: [String: [AlgCase]] = [:]

    for algCase in cases {
        let subgroup = algCase.subgroup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subgroup.isEmpty else { continue }
        if grouped[subgroup] == nil {
            orderedTitles.append(subgroup)
            grouped[subgroup] = []
        }
        grouped[subgroup, default: []].append(algCase)
    }

    return orderedTitles.map { title in
        AlgSubset(id: normalizedAlgSetID(title), title: title, cases: grouped[title] ?? [])
    }
}

private func subsetGroupTitle(for setID: String, subsetTitle: String) -> String? {
    guard normalizedAlgSetID(setID) == "zbll" else { return nil }

    let trimmed = subsetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("AS") { return "AS" }
    if trimmed.hasPrefix("Pi") { return "Pi" }
    if let first = trimmed.first {
        switch first {
        case "U": return "U"
        case "L": return "L"
        case "T": return "T"
        case "H": return "H"
        case "S": return "S"
        default: break
        }
    }

    return nil
}

private func caseGroupTitle(for setID: String, algCase: AlgCase) -> String? {
    if let group = algCase.group?.trimmingCharacters(in: .whitespacesAndNewlines), !group.isEmpty {
        return group
    }

    let trimmed = algCase.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    switch normalizedAlgSetID(setID) {
    case "ollcp":
        guard trimmed.hasPrefix("OLLCP") else { return nil }
        return trimmed.split(separator: " ").first.map(String.init)
    case "1lll":
        if trimmed == "Pure" {
            return "Anti PLL"
        }

        if trimmed.hasPrefix("ZBLL ") {
            let parts = trimmed.split(separator: " ")
            guard parts.count >= 2 else { return nil }
            return parts.prefix(2).joined(separator: " ")
        }

        if trimmed.hasPrefix("1LLL ") {
            let parts = trimmed.split(separator: " ")
            guard parts.count >= 2 else { return nil }
            return parts.prefix(2).joined(separator: " ")
        }

        return "Anti PLL"
    default:
        return nil
    }
}

private func orderedSubsetGroups(setID: String, subsets: [AlgSubset]) -> [AlgSubsetGroup] {
    let preferredOrder = ["U", "L", "T", "H", "Pi", "S", "AS"]
    var grouped: [String: [AlgSubset]] = [:]
    var orderedTitles: [String] = []

    for subset in subsets {
        guard let title = subsetGroupTitle(for: setID, subsetTitle: subset.title) else { continue }
        if grouped[title] == nil {
            orderedTitles.append(title)
            grouped[title] = []
        }
        grouped[title, default: []].append(subset)
    }

    let titles = preferredOrder.filter { grouped[$0] != nil } + orderedTitles.filter { !preferredOrder.contains($0) }
    return titles.map { title in
        AlgSubsetGroup(id: normalizedAlgSetID(title), title: title, subsets: grouped[title] ?? [])
    }
}

private func orderedCaseGroups(setID: String, cases: [AlgCase]) -> [AlgCaseGroup] {
    var orderedTitles: [String] = []
    var grouped: [String: [AlgCase]] = [:]

    for algCase in cases {
        guard let title = caseGroupTitle(for: setID, algCase: algCase) else { continue }
        if grouped[title] == nil {
            orderedTitles.append(title)
            grouped[title] = []
        }
        grouped[title, default: []].append(algCase)
    }

    let titles: [String]
    if normalizedAlgSetID(setID) == "ollcp" {
        titles = orderedTitles.sorted { lhs, rhs in
            let lhsNumber = Int(lhs.replacingOccurrences(of: "OLLCP", with: "")) ?? .max
            let rhsNumber = Int(rhs.replacingOccurrences(of: "OLLCP", with: "")) ?? .max
            return lhsNumber < rhsNumber
        }
    } else if normalizedAlgSetID(setID) == "vls" {
        let preferredOrder = ["UB", "UB UL", "UF", "UF UB", "UF UL", "UL", "No Edges"]
        titles = preferredOrder.filter { grouped[$0] != nil } + orderedTitles.filter { !preferredOrder.contains($0) }
    } else if normalizedAlgSetID(setID) == "1lll" {
        let preferredOrder = ["PLL", "ZBLL U", "ZBLL L", "ZBLL T", "ZBLL H", "ZBLL Pi", "ZBLL S", "ZBLL AS", "Anti PLL"]
        let numberedGroups = orderedTitles
            .filter { $0.hasPrefix("1LLL ") }
            .sorted {
                let lhsNumber = Int($0.replacingOccurrences(of: "1LLL ", with: "")) ?? .max
                let rhsNumber = Int($1.replacingOccurrences(of: "1LLL ", with: "")) ?? .max
                return lhsNumber < rhsNumber
            }
        let remainingGroups = orderedTitles.filter { !preferredOrder.contains($0) && !$0.hasPrefix("1LLL ") }
        titles = preferredOrder.filter { grouped[$0] != nil } + numberedGroups + remainingGroups
    } else {
        titles = orderedTitles
    }

    return titles.map { title in
        AlgCaseGroup(id: normalizedAlgSetID(title), title: title, cases: grouped[title] ?? [])
    }
}

private func makeSetTrainerSeeds(
    payload: AlgSetPayload,
    languageCode: String,
    organization: AlgBrowseOrganization
) -> (AlgTrainerRecognitionLevel, [AlgTrainerQuestionSeed]) {
    let subsets = orderedSubsets(from: payload.cases)
    let subsetGroups = orderedSubsetGroups(setID: payload.set, subsets: subsets)
    let caseGroups = orderedCaseGroups(setID: payload.set, cases: payload.cases)

    if organization == .number {
        let seeds = payload.cases.map { algCase in
            AlgTrainerQuestionSeed(
                id: algCase.id,
                algCase: algCase,
                answerID: algCase.id,
                answerTitle: algCase.displayName
            )
        }
        return (.caseName, seeds)
    }

    if !subsetGroups.isEmpty {
        let seeds = payload.cases.compactMap { algCase -> AlgTrainerQuestionSeed? in
            guard let groupTitle = subsetGroupTitle(for: payload.set, subsetTitle: algCase.subgroup) else { return nil }
            return AlgTrainerQuestionSeed(
                id: algCase.id,
                algCase: algCase,
                answerID: groupTitle,
                answerTitle: displayAlgGroupTitle(setID: payload.set, title: groupTitle)
            )
        }
        return (.group, seeds)
    }

    if !caseGroups.isEmpty {
        let seeds = payload.cases.compactMap { algCase -> AlgTrainerQuestionSeed? in
            guard let groupTitle = caseGroupTitle(for: payload.set, algCase: algCase) else { return nil }
            return AlgTrainerQuestionSeed(
                id: algCase.id,
                algCase: algCase,
                answerID: groupTitle,
                answerTitle: displayAlgGroupTitle(setID: payload.set, title: groupTitle)
            )
        }
        return (.group, seeds)
    }

    if !subsets.isEmpty {
        let seeds = payload.cases.map { algCase in
            AlgTrainerQuestionSeed(
                id: algCase.id,
                algCase: algCase,
                answerID: algCase.subgroup,
                answerTitle: localizedAlgSubgroup(algCase.subgroup, languageCode: languageCode)
            )
        }
        return (.subset, seeds)
    }

    let seeds = payload.cases.map { algCase in
        AlgTrainerQuestionSeed(
            id: algCase.id,
            algCase: algCase,
            answerID: algCase.id,
            answerTitle: algCase.displayName
        )
    }
    return (.caseName, seeds)
}

private func makeSubsetTrainerSeeds(subset: AlgSubset) -> (AlgTrainerRecognitionLevel, [AlgTrainerQuestionSeed]) {
    let seeds = subset.cases.map { algCase in
        AlgTrainerQuestionSeed(
            id: algCase.id,
            algCase: algCase,
            answerID: algCase.id,
            answerTitle: algCase.displayName
        )
    }
    return (.caseName, seeds)
}

private func algBrowsePreferenceMap(from storage: String) -> [String: String] {
    guard let data = storage.data(using: .utf8),
          let map = try? JSONDecoder().decode([String: String].self, from: data) else {
        return [:]
    }
    return map
}

private func algBrowsePreferenceStorage(from map: [String: String]) -> String {
    guard let data = try? JSONEncoder().encode(map),
          let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return string
}

private func algBrowseViewMode(setID: String, storage: String) -> AlgBrowseViewMode {
    let value = algBrowsePreferenceMap(from: storage)[normalizedAlgSetID(setID)]
    return value.flatMap(AlgBrowseViewMode.init(rawValue:)) ?? .list
}

private func updatedAlgBrowseViewModeStorage(storage: String, setID: String, mode: AlgBrowseViewMode) -> String {
    var map = algBrowsePreferenceMap(from: storage)
    map[normalizedAlgSetID(setID)] = mode.rawValue
    return algBrowsePreferenceStorage(from: map)
}

private func algBrowseOrganization(setID: String, storage: String) -> AlgBrowseOrganization {
    let value = algBrowsePreferenceMap(from: storage)[normalizedAlgSetID(setID)]
    return value.flatMap(AlgBrowseOrganization.init(rawValue:)) ?? .number
}

private func updatedAlgBrowseOrganizationStorage(storage: String, setID: String, organization: AlgBrowseOrganization) -> String {
    var map = algBrowsePreferenceMap(from: storage)
    map[normalizedAlgSetID(setID)] = organization.rawValue
    return algBrowsePreferenceStorage(from: map)
}

private func learnedCaseMap(from storage: String) -> [String: Set<String>] {
    guard let data = storage.data(using: .utf8),
          let raw = try? JSONDecoder().decode([String: [String]].self, from: data) else {
        return [:]
    }

    return raw.reduce(into: [:]) { partialResult, entry in
        partialResult[entry.key] = Set(entry.value)
    }
}

private func learnedCaseStorage(from map: [String: Set<String>]) -> String {
    let raw = map.reduce(into: [String: [String]]()) { partialResult, entry in
        partialResult[entry.key] = entry.value.sorted()
    }

    guard let data = try? JSONEncoder().encode(raw),
          let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }

    return string
}

private func isAlgCaseLearned(setID: String, caseID: String, storage: String) -> Bool {
    learnedCaseMap(from: storage)[normalizedAlgSetID(setID), default: []].contains(caseID)
}

private func updatedLearnedCaseStorage(storage: String, setID: String, caseID: String, learned: Bool) -> String {
    var map = learnedCaseMap(from: storage)
    let key = normalizedAlgSetID(setID)
    var learnedCases = map[key, default: []]

    if learned {
        learnedCases.insert(caseID)
    } else {
        learnedCases.remove(caseID)
    }

    map[key] = learnedCases
    return learnedCaseStorage(from: map)
}

private func updatedLearnedCaseStorageForAll(storage: String, setID: String, caseIDs: [String], learned: Bool) -> String {
    var map = learnedCaseMap(from: storage)
    map[normalizedAlgSetID(setID)] = learned ? Set(caseIDs) : []
    return learnedCaseStorage(from: map)
}

private func learnedCaseCount(setID: String, storage: String) -> Int {
    learnedCaseMap(from: storage)[normalizedAlgSetID(setID), default: []].count
}

private func learnedCaseCount(setID: String, caseIDs: [String], storage: String) -> Int {
    let learned = learnedCaseMap(from: storage)[normalizedAlgSetID(setID), default: []]
    return learned.intersection(Set(caseIDs)).count
}

private func learnedPercent(setID: String, totalCases: Int, storage: String) -> Int {
    guard totalCases > 0 else { return 0 }
    let learned = min(learnedCaseCount(setID: setID, storage: storage), totalCases)
    return Int((Double(learned) / Double(totalCases) * 100).rounded())
}

private func learnedFraction(setID: String, totalCases: Int, storage: String) -> Double {
    guard totalCases > 0 else { return 0 }
    let learned = min(learnedCaseCount(setID: setID, storage: storage), totalCases)
    return min(max(Double(learned) / Double(totalCases), 0), 1)
}

private func localizedCaseCount(_ count: Int, languageCode: String) -> String {
    String(format: localizedAlgString(key: "algs.case_count_format", languageCode: languageCode), count)
}

private func localizedAlgorithmCount(_ count: Int, languageCode: String) -> String {
    String(format: localizedAlgString(key: "algs.algorithm_count_format", languageCode: languageCode), count)
}

private func localizedAlgorithmsSubtitle(_ count: Int, learnedPercent: Int, languageCode: String) -> String {
    let learnedText: String
    if learnedPercent <= 0 {
        learnedText = localizedAlgString(key: "algs.not_started", languageCode: languageCode)
    } else if learnedPercent >= 100 {
        learnedText = localizedAlgString(key: "algs.learned_complete", languageCode: languageCode)
    } else {
        learnedText = String(format: localizedAlgString(key: "algs.learned_percent_format", languageCode: languageCode), learnedPercent)
    }

    let countText = localizedAlgorithmCount(count, languageCode: languageCode)
    return "\(countText) · \(learnedText)"
}

private func localizedCaseSubtitle(_ count: Int, learnedCount: Int, learnedFraction: Double, languageCode: String) -> String {
    let caseText = localizedCaseCount(count, languageCode: languageCode)
    let learnedText: String
    if learnedCount <= 0 {
        learnedText = localizedAlgString(key: "algs.not_started", languageCode: languageCode)
    } else if learnedFraction >= 1 {
        learnedText = localizedAlgString(key: "algs.learned_complete", languageCode: languageCode)
    } else if learnedFraction < 0.01 {
        learnedText = localizedAlgString(key: "algs.learned_less_than_one_percent", languageCode: languageCode)
    } else {
        let learnedPercent = Int((learnedFraction * 100).rounded())
        learnedText = String(format: localizedAlgString(key: "algs.learned_percent_format", languageCode: languageCode), learnedPercent)
    }
    return "\(caseText) · \(learnedText)"
}

private func localizedAlgString(key: String, languageCode: String) -> String {
    appLocalizedString(key, languageCode: languageCode)
}

private func algSubgroupLocalizationKey(_ subgroup: String) -> String? {
    switch subgroup.lowercased() {
    case "free pairs":
        return "algs.f2l.subgroup.free_pairs"
    case "connected pairs":
        return "algs.f2l.subgroup.connected_pairs"
    case "corner in slot":
        return "algs.f2l.subgroup.corner_in_slot"
    case "disconnected pairs":
        return "algs.f2l.subgroup.disconnected_pairs"
    case "edge in slot":
        return "algs.f2l.subgroup.edge_in_slot"
    case "pieces in slot":
        return "algs.f2l.subgroup.pieces_in_slot"
    case "adj swap":
        return "algs.pll.subgroup.adj_swap"
    case "opp swap":
        return "algs.pll.subgroup.opp_swap"
    case "all corners oriented":
        return "algs.subgroup.all_corners_oriented"
    case "awkward shapes":
        return "algs.subgroup.awkward_shapes"
    case "c shapes":
        return "algs.subgroup.c_shapes"
    case "dot case":
        return "algs.subgroup.dot_case"
    case "fish shapes":
        return "algs.subgroup.fish_shapes"
    case "knight move shapes":
        return "algs.subgroup.knight_move_shapes"
    case "l shapes":
        return "algs.subgroup.l_shapes"
    case "lightning shapes":
        return "algs.subgroup.lightning_shapes"
    case "line shapes":
        return "algs.subgroup.line_shapes"
    case "p shapes":
        return "algs.subgroup.p_shapes"
    case "square shapes":
        return "algs.subgroup.square_shapes"
    case "t shapes":
        return "algs.subgroup.t_shapes"
    case "w shapes":
        return "algs.subgroup.w_shapes"
    case "both pieces trapped":
        return "algs.subgroup.both_pieces_trapped"
    case "trapped corner":
        return "algs.subgroup.trapped_corner"
    case "trapped edge":
        return "algs.subgroup.trapped_edge"
    case "cross color facing front":
        return "algs.subgroup.cross_color_facing_front"
    case "cross color facing right":
        return "algs.subgroup.cross_color_facing_right"
    case "cross color facing up":
        return "algs.subgroup.cross_color_facing_up"
    case "corner on d facing forward":
        return "algs.subgroup.corner_on_d_facing_forward"
    case "corner on d facing side":
        return "algs.subgroup.corner_on_d_facing_side"
    case "corner on d solved":
        return "algs.subgroup.corner_on_d_solved"
    case "corner on u facing up":
        return "algs.subgroup.corner_on_u_facing_up"
    case "corner on u misoriented":
        return "algs.subgroup.corner_on_u_misoriented"
    case "corner on u oriented":
        return "algs.subgroup.corner_on_u_oriented"
    case "anti sune":
        return "algs.subgroup.anti_sune"
    case "sune":
        return "algs.subgroup.sune"
    case "solved":
        return "algs.subgroup.solved"
    default:
        return nil
    }
}

private func localizedAlgSubgroup(_ subgroup: String, languageCode: String) -> String {
    guard let key = algSubgroupLocalizationKey(subgroup) else { return subgroup }
    return localizedAlgString(key: key, languageCode: languageCode)
}

#if os(iOS)
private enum AlgCaseImageProvider {
    private static var cache: [String: UIImage] = [:]

    static func image(named imageKey: String) -> UIImage? {
        if let cached = cache[imageKey] {
            return cached
        }

        if let bundled = UIImage(named: imageKey) {
            cache[imageKey] = bundled
            return bundled
        }

        let folderName = imageFolderName(for: imageKey)
        let candidates: [String?] = [
            "Resources/Algs/\(folderName)",
            "Algs/\(folderName)",
            folderName,
            nil
        ]

        for subdirectory in candidates {
            if let url = Bundle.main.url(forResource: imageKey, withExtension: "png", subdirectory: subdirectory),
               let image = UIImage(contentsOfFile: url.path) {
                cache[imageKey] = image
                return image
            }
        }

        return nil
    }

    private static func imageFolderName(for imageKey: String) -> String {
        let prefix = imageKey.split(separator: "_").first.map(String.init)?.uppercased() ?? "PLL"
        return "\(prefix)Images"
    }
}
#endif

#if os(iOS)
private struct AlgSetPlaceholderView: View {
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

private struct AlgCaseListView: View {
    let payload: AlgSetPayload
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("algLearnedCasesStore") private var learnedCasesStore: String = "{}"
    @AppStorage("algBrowseViewModeStore") private var browseViewModeStore: String = "{}"
    @AppStorage("algBrowseOrganizationStore") private var browseOrganizationStore: String = "{}"
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
        .navigationDestination(isPresented: $isShowingTrainer) {
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
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var listContent: some View {
        List {
            headerContent
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)

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

            if browseOrganization == .subset {
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
                ForEach(payload.cases) { algCase in
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

                LazyVGrid(columns: gridColumns, spacing: 12) {
                    if browseOrganization == .subset {
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
                        ForEach(payload.cases) { algCase in
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
        AlgSectionData.threeByThreeSections
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
        URL(string: "https://www.speedcubedb.com/a/3x3/\(payload.set)")
    }

    private func sourceFooterText(for url: URL) -> String {
        String(
            format: localizedAlgString(key: "algs.source_format", languageCode: appLanguage),
            url.host ?? "SpeedCubeDB"
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
                Text(algCase.displayName)
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

            Text(algCase.displayName)
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

            Text(algCase.displayName)
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
                .glassEffect(.regular.interactive(), in: .circle)
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

private struct AlgSubsetGroupListView: View {
    let payload: AlgSetPayload
    let group: AlgSubsetGroup
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("algLearnedCasesStore") private var learnedCasesStore: String = "{}"
    @AppStorage("algBrowseViewModeStore") private var browseViewModeStore: String = "{}"
    @State private var isShowingInfoSheet = false

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
        .navigationTitle(displayGroupTitle)
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
        .sheet(isPresented: $isShowingInfoSheet) {
            AlgSetInfoSheet(
                setID: "\(payload.set)_\(group.id)",
                fallbackTitle: displayGroupTitle,
                fallbackSubtitle: payload.set,
                sourceURL: sourceURL,
                languageCode: appLanguage
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var listContent: some View {
        List {
            headerContent
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)

            ForEach(group.subsets) { subset in
                NavigationLink {
                    AlgSubsetCaseListView(payload: payload, subset: subset)
                } label: {
                    subsetRow(subset)
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

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
                    ForEach(group.subsets) { subset in
                        NavigationLink {
                            AlgSubsetCaseListView(payload: payload, subset: subset)
                        } label: {
                            subsetCard(subset)
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
            Text(displayGroupTitle)
                .font(.system(size: 34, weight: .bold))

            Text(
                localizedCaseSubtitle(
                    group.uniqueCaseCount,
                    learnedCount: learnedCaseCount(setID: payload.set, caseIDs: group.uniqueCaseIDs, storage: learnedCasesStore),
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
        group.uniqueCaseCount > 0 && learnedCaseCount(setID: payload.set, caseIDs: group.uniqueCaseIDs, storage: learnedCasesStore) >= group.uniqueCaseCount
    }

    private var learnedFraction: Double {
        guard group.uniqueCaseCount > 0 else { return 0 }
        let learned = learnedCaseCount(setID: payload.set, caseIDs: group.uniqueCaseIDs, storage: learnedCasesStore)
        return min(max(Double(learned) / Double(group.uniqueCaseCount), 0), 1)
    }

    private var browseViewMode: AlgBrowseViewMode {
        algBrowseViewMode(setID: payload.set, storage: browseViewModeStore)
    }

    private var sourceURL: URL? {
        URL(string: "https://www.speedcubedb.com/a/3x3/\(payload.set)")
    }

    private func sourceFooterText(for url: URL) -> String {
        String(
            format: localizedAlgString(key: "algs.source_format", languageCode: appLanguage),
            url.host ?? "SpeedCubeDB"
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

            Text(algCase.displayName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .padding(.horizontal, 6)
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
                .glassEffect(.regular.interactive(), in: .circle)
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

private struct AlgCaseGroupListView: View {
    let payload: AlgSetPayload
    let group: AlgCaseGroup
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("algLearnedCasesStore") private var learnedCasesStore: String = "{}"
    @AppStorage("algBrowseViewModeStore") private var browseViewModeStore: String = "{}"
    @State private var isShowingInfoSheet = false

    var body: some View {
        Group {
            if browseViewMode == .list {
                listContent
            } else {
                gridContent
            }
        }
        .navigationTitle(group.title)
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
        .sheet(isPresented: $isShowingInfoSheet) {
            AlgSetInfoSheet(
                setID: "\(payload.set)_\(group.id)",
                fallbackTitle: group.title,
                fallbackSubtitle: payload.set,
                sourceURL: sourceURL,
                languageCode: appLanguage
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var listContent: some View {
        List {
            headerContent
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)

            if showsSubsets {
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

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
                    if showsSubsets {
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
            Text(group.title)
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

    private var learnedSubsetCount: Int {
        groupSubsets.filter { subsetLearnedFraction(for: $0) >= 1 }.count
    }

    private var subsetLearnedFractionValue: Double {
        guard !groupSubsets.isEmpty else { return 0 }
        return min(max(Double(learnedSubsetCount) / Double(groupSubsets.count), 0), 1)
    }

    private var headerSubtitleText: String {
        if showsSubsets {
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

    private var sourceURL: URL? {
        URL(string: "https://www.speedcubedb.com/a/3x3/\(payload.set)")
    }

    private func sourceFooterText(for url: URL) -> String {
        String(
            format: localizedAlgString(key: "algs.source_format", languageCode: appLanguage),
            url.host ?? "SpeedCubeDB"
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

    private func caseRow(_ algCase: AlgCase) -> some View {
        HStack(spacing: 12) {
            caseImage(for: algCase)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(algCase.displayName)
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

            Text(algCase.displayName)
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

            Text(algCase.displayName)
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
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(14)
                .contentShape(.circle)
                .clipShape(.circle)
                .glassEffect(.regular.interactive(), in: .circle)
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

private struct AlgSubsetCaseListView: View {
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
        .navigationTitle(localizedAlgSubgroup(subset.title, languageCode: appLanguage))
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
        .navigationDestination(isPresented: $isShowingTrainer) {
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
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var listContent: some View {
        List {
            headerContent
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)

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
            Text(localizedAlgSubgroup(subset.title, languageCode: appLanguage))
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
        URL(string: "https://www.speedcubedb.com/a/3x3/\(payload.set)")
    }

    private func sourceFooterText(for url: URL) -> String {
        String(
            format: localizedAlgString(key: "algs.source_format", languageCode: appLanguage),
            url.host ?? "SpeedCubeDB"
        )
    }

    private var trainerDestination: some View {
        let config = makeSubsetTrainerSeeds(subset: subset)
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
                Text(algCase.displayName)
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

            Text(algCase.displayName)
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

            Text(algCase.displayName)
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
                .glassEffect(.regular.interactive(), in: .circle)
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
        NavigationStack {
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
                .navigationSubtitle(displaySubtitle)
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

                        ShareLink(item: shareText, subject: Text(displayTitle)) {
                            Label(shareButtonText, systemImage: "square.and.arrow.up")
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

private struct AlgRecognitionTrainerView: View {
    let title: String
    let scopeTitle: String
    let languageCode: String
    let setID: String
    let scopeID: String
    let level: AlgTrainerRecognitionLevel
    let seeds: [AlgTrainerQuestionSeed]

    @AppStorage("algTrainerAttemptStore") private var attemptStore: String = "[]"
    @Environment(\.dismiss) private var dismiss
    private let sessionTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var currentQuestion: AlgTrainerQuestion?
    @State private var selectedAnswerID: String?
    @State private var lastQuestionSeedID: String?
    @State private var isShowingSummary = false
    @State private var answeredCount = 0
    @State private var correctCount = 0
    @State private var currentStreak = 0
    @State private var bestStreak = 0
    @State private var skipCount = 0
    @State private var sessionStartDate = Date()
    @State private var questionStartDate = Date()
    @State private var totalAnsweredRecognitionDuration: TimeInterval = 0
    @State private var now = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scopeTitle)
                        .font(.system(size: 34, weight: .bold))

                    Text(promptText)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.top, 8)
                }
                .padding(.top, 8)

                trainerStatsRow
                trainerSessionTimeCard

                NavigationLink {
                    AlgTrainerWeakReviewView(items: weakItems, languageCode: languageCode)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                        Text(localizedAlgString(key: "algs.trainer.review_weak", languageCode: languageCode))
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.secondary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)

                if let currentQuestion {
                    trainerCaseImage(for: currentQuestion.algCase)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(16)
                        .frame(height: 190)
                        .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(.secondary.opacity(0.08))
                        )
                        .animation(.easeInOut(duration: 0.2), value: currentQuestion.id)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(currentQuestion.choices) { choice in
                            Button {
                                guard selectedAnswerID == nil else { return }
                                let isCorrect = choice.id == currentQuestion.correctAnswerID
                                if let responseDuration = currentRecognitionDuration {
                                    totalAnsweredRecognitionDuration += responseDuration
                                }
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                    selectedAnswerID = choice.id
                                }
                                triggerAnswerHaptic(isCorrect: isCorrect)
                                updateSessionStats(isCorrect: isCorrect, wasSkipped: false)
                                recordAttempt(
                                    answerID: choice.id,
                                    isCorrect: isCorrect,
                                    isSkipped: false,
                                    for: currentQuestion
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    Text(choice.title)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(choiceForegroundStyle(for: choice))
                                        .multilineTextAlignment(.leading)

                                    Spacer()

                                    if let selectedAnswerID, selectedAnswerID == choice.id {
                                        Image(systemName: selectedAnswerID == currentQuestion.correctAnswerID ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(selectedAnswerID == currentQuestion.correctAnswerID ? .green : .red)
                                    } else if selectedAnswerID != nil, choice.id == currentQuestion.correctAnswerID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(.green)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(choiceBackgroundColor(for: choice))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: selectedAnswerID)

                    if selectedAnswerID == nil {
                        Button {
                            triggerActionHaptic()
                            updateSessionStats(isCorrect: false, wasSkipped: true)
                            recordAttempt(answerID: nil, isCorrect: false, isSkipped: true, for: currentQuestion)
                            withAnimation(.easeInOut(duration: 0.22)) {
                                generateNextQuestion()
                            }
                        } label: {
                            Text(localizedAlgString(key: "algs.trainer.skip", languageCode: languageCode))
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(.secondary.opacity(0.08))
                                )
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if let selectedAnswerID {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(
                                selectedAnswerID == currentQuestion.correctAnswerID
                                    ? localizedAlgString(key: "algs.trainer.correct", languageCode: languageCode)
                                    : localizedAlgString(key: "algs.trainer.incorrect", languageCode: languageCode)
                            )
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(selectedAnswerID == currentQuestion.correctAnswerID ? .green : .red)

                            if selectedAnswerID != currentQuestion.correctAnswerID {
                                Text(
                                    String(
                                        format: localizedAlgString(key: "algs.trainer.correct_answer_format", languageCode: languageCode),
                                        currentQuestion.correctAnswerTitle
                                    )
                                )
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                            }

                            Button {
                                triggerActionHaptic()
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    generateNextQuestion()
                                }
                            } label: {
                                Text(localizedAlgString(key: "algs.trainer.next_question", languageCode: languageCode))
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(Color.orange)
                                    )
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localizedAlgString(key: "algs.trainer.no_questions_title", languageCode: languageCode))
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(localizedAlgString(key: "algs.trainer.no_questions_body", languageCode: languageCode))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.secondary.opacity(0.08))
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isShowingSummary) {
            NavigationStack {
                AlgTrainerSummaryView(
                    summary: AlgTrainerSessionSummary(
                        title: title,
                        scopeTitle: scopeTitle,
                        languageCode: languageCode,
                        answeredCount: answeredCount,
                        correctCount: correctCount,
                        wrongCount: max(answeredCount - correctCount, 0),
                        skipCount: skipCount,
                        bestStreak: bestStreak,
                        sessionDuration: sessionDuration,
                        averageRecognitionDuration: averageRecognitionDuration
                    ),
                    weakItems: makeAlgTrainerWeakReviewItems(from: decodeAlgTrainerAttempts(from: attemptStore), languageCode: languageCode),
                    onTrainAgain: {
                        isShowingSummary = false
                        resetSession()
                        generateNextQuestion()
                    },
                    onDone: {
                        isShowingSummary = false
                        dismiss()
                    }
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(localizedAlgString(key: "algs.trainer.end", languageCode: languageCode)) {
                    if answeredCount == 0 && skipCount == 0 {
                        dismiss()
                    } else {
                        triggerActionHaptic()
                        isShowingSummary = true
                    }
                }
                .font(.system(size: 15, weight: .semibold))
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if currentQuestion == nil {
                sessionStartDate = Date()
                now = sessionStartDate
                generateNextQuestion()
            }
        }
        .onReceive(sessionTicker) { value in
            now = value
        }
    }

    private var promptText: String {
        switch level {
        case .group:
            return localizedAlgString(key: "algs.trainer.prompt_group", languageCode: languageCode)
        case .subset:
            return localizedAlgString(key: "algs.trainer.prompt_subset", languageCode: languageCode)
        case .caseName:
            return localizedAlgString(key: "algs.trainer.prompt_case", languageCode: languageCode)
        }
    }

    private var accuracyText: String {
        guard answeredCount > 0 else {
            return localizedAlgString(key: "algs.trainer.accuracy_empty", languageCode: languageCode)
        }

        let percent = Int((Double(correctCount) / Double(answeredCount) * 100).rounded())
        return String(
            format: localizedAlgString(key: "algs.trainer.accuracy_format", languageCode: languageCode),
            percent,
            correctCount,
            answeredCount
        )
    }

    private var trainerStatsRow: some View {
        HStack(spacing: 12) {
            trainerStatCard(
                title: localizedAlgString(key: "algs.trainer.score_title", languageCode: languageCode),
                value: accuracyText
            )

            trainerStatCard(
                title: localizedAlgString(key: "algs.trainer.streak_title", languageCode: languageCode),
                value: String(currentStreak)
            )

            trainerStatCard(
                title: localizedAlgString(key: "algs.trainer.best_streak_title", languageCode: languageCode),
                value: String(bestStreak)
            )
        }
    }

    private var trainerSessionTimeCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 14, weight: .semibold))
            Text(localizedAlgString(key: "algs.trainer.session_time_title", languageCode: languageCode))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatAlgTrainerSessionDuration(sessionDuration))
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    private var weakItems: [AlgTrainerWeakReviewItem] {
        makeAlgTrainerWeakReviewItems(from: decodeAlgTrainerAttempts(from: attemptStore), languageCode: languageCode)
    }

    private var sessionDuration: TimeInterval {
        max(now.timeIntervalSince(sessionStartDate), 0)
    }

    private var currentRecognitionDuration: TimeInterval? {
        guard selectedAnswerID == nil else { return nil }
        return max(Date().timeIntervalSince(questionStartDate), 0)
    }

    private var averageRecognitionDuration: TimeInterval? {
        guard answeredCount > 0 else { return nil }
        return totalAnsweredRecognitionDuration / Double(answeredCount)
    }

    private func generateNextQuestion() {
        guard !seeds.isEmpty else {
            currentQuestion = nil
            selectedAnswerID = nil
            return
        }

        let answerPool = seeds.reduce(into: [String: String]()) { partialResult, seed in
            partialResult[seed.answerID] = seed.answerTitle
        }
        let candidateSeeds: [AlgTrainerQuestionSeed]
        if let lastQuestionSeedID, seeds.count > 1 {
            let filtered = seeds.filter { $0.id != lastQuestionSeedID }
            candidateSeeds = filtered.isEmpty ? seeds : filtered
        } else {
            candidateSeeds = seeds
        }

        guard let seed = candidateSeeds.randomElement() else {
            currentQuestion = nil
            selectedAnswerID = nil
            return
        }

        let distractorIDs = Array(answerPool.keys.filter { $0 != seed.answerID }).shuffled().prefix(3)
        let choiceIDs = ([seed.answerID] + distractorIDs).shuffled()
        let choices = choiceIDs.map { choiceID in
            AlgTrainerQuestionChoice(id: choiceID, title: answerPool[choiceID] ?? choiceID)
        }

        currentQuestion = AlgTrainerQuestion(
            id: UUID().uuidString,
            algCase: seed.algCase,
            choices: choices,
            correctAnswerID: seed.answerID,
            correctAnswerTitle: seed.answerTitle
        )
        lastQuestionSeedID = seed.id
        selectedAnswerID = nil
        questionStartDate = Date()
    }

    private func updateSessionStats(isCorrect: Bool, wasSkipped: Bool) {
        if !wasSkipped {
            answeredCount += 1
        }

        if isCorrect {
            correctCount += 1
            currentStreak += 1
            bestStreak = max(bestStreak, currentStreak)
        } else {
            if wasSkipped {
                skipCount += 1
            }
            currentStreak = 0
        }
    }

    private func resetSession() {
        currentQuestion = nil
        selectedAnswerID = nil
        lastQuestionSeedID = nil
        answeredCount = 0
        correctCount = 0
        currentStreak = 0
        bestStreak = 0
        skipCount = 0
        totalAnsweredRecognitionDuration = 0
        sessionStartDate = Date()
        now = sessionStartDate
        questionStartDate = sessionStartDate
    }

    @ViewBuilder
    private func trainerCaseImage(for algCase: AlgCase) -> some View {
        #if os(iOS)
        if let image = AlgCaseImageProvider.image(named: algCase.imageKey) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        } else {
            fallbackTrainerCaseImage(for: algCase)
        }
        #else
        fallbackTrainerCaseImage(for: algCase)
        #endif
    }

    private func fallbackTrainerCaseImage(for algCase: AlgCase) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.blue.opacity(0.12))

            Text(algCase.displayName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.blue)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .padding(.horizontal, 12)
        }
    }

    private func choiceBackgroundColor(for choice: AlgTrainerQuestionChoice) -> Color {
        guard let currentQuestion else { return Color.secondary.opacity(0.08) }
        guard let selectedAnswerID else { return Color.secondary.opacity(0.08) }

        if choice.id == currentQuestion.correctAnswerID {
            return Color.green.opacity(0.14)
        }

        if choice.id == selectedAnswerID {
            return Color.red.opacity(0.12)
        }

        return Color.secondary.opacity(0.08)
    }

    private func choiceForegroundStyle(for choice: AlgTrainerQuestionChoice) -> Color {
        guard let currentQuestion else { return .primary }
        guard let selectedAnswerID else { return .primary }

        if choice.id == currentQuestion.correctAnswerID {
            return .green
        }

        if choice.id == selectedAnswerID {
            return .red
        }

        return .primary
    }

    private func trainerStatCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    private func triggerAnswerHaptic(isCorrect: Bool) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(isCorrect ? .success : .error)
        #endif
    }

    private func triggerActionHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    private func recordAttempt(answerID: String?, isCorrect: Bool, isSkipped: Bool, for question: AlgTrainerQuestion) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var records = (try? decoder.decode([AlgTrainerAttemptRecord].self, from: Data(attemptStore.utf8))) ?? []
        records.append(
            AlgTrainerAttemptRecord(
                id: UUID().uuidString,
                setID: setID,
                scopeID: scopeID,
                level: level,
                caseID: question.algCase.id,
                answerID: answerID,
                isCorrect: isCorrect,
                isSkipped: isSkipped,
                timestamp: Date()
            )
        )
        if records.count > 500 {
            records = Array(records.suffix(500))
        }
        if let data = try? encoder.encode(records),
           let string = String(data: data, encoding: .utf8) {
            attemptStore = string
        }
    }
}

private struct AlgTrainerWeakReviewView: View {
    let items: [AlgTrainerWeakReviewItem]
    let languageCode: String

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizedAlgString(key: "algs.trainer.weak_title", languageCode: languageCode))
                        .font(.system(size: 34, weight: .bold))

                    Text(localizedAlgString(key: "algs.trainer.weak_subtitle", languageCode: languageCode))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.top, 8)
                }
                .padding(.vertical, 4)
            }
            .listRowSeparator(.hidden)

            if items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizedAlgString(key: "algs.trainer.weak_empty_title", languageCode: languageCode))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(localizedAlgString(key: "algs.trainer.weak_empty_body", languageCode: languageCode))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            } else {
                ForEach(items) { item in
                    NavigationLink {
                        AlgCaseDetailView(payload: item.payload, algCase: item.algCase)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.caseTitle)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text(item.setTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)

                            Text(item.subtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(localizedAlgString(key: "algs.trainer.weak_nav_title", languageCode: languageCode))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AlgSearchView: View {
    let items: [AlgSearchItem]
    let languageCode: String

    @State private var query = ""

    private var filteredItems: [AlgSearchItem] {
        items.filter { $0.matches(query) }
    }

    private var setItems: [AlgSearchItem] {
        filteredItems.filter { $0.kind == .set }
    }

    private var subsetItems: [AlgSearchItem] {
        filteredItems.filter { $0.kind == .subset }
    }

    private var caseItems: [AlgSearchItem] {
        filteredItems.filter { $0.kind == .caseName }
    }

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizedAlgString(key: "algs.search.empty_query_title", languageCode: languageCode))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(localizedAlgString(key: "algs.search.empty_query_body", languageCode: languageCode))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            } else if filteredItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizedAlgString(key: "algs.search.no_results_title", languageCode: languageCode))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(localizedAlgString(key: "algs.search.no_results_body", languageCode: languageCode))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            } else {
                if !setItems.isEmpty {
                    Section(localizedAlgString(key: "algs.search.section_sets", languageCode: languageCode)) {
                        ForEach(setItems) { item in
                            searchRow(item)
                        }
                    }
                }

                if !subsetItems.isEmpty {
                    Section(localizedAlgString(key: "algs.search.section_subsets", languageCode: languageCode)) {
                        ForEach(subsetItems) { item in
                            searchRow(item)
                        }
                    }
                }

                if !caseItems.isEmpty {
                    Section(localizedAlgString(key: "algs.search.section_cases", languageCode: languageCode)) {
                        ForEach(caseItems) { item in
                            searchRow(item)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(localizedAlgString(key: "algs.search.title", languageCode: languageCode))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(localizedAlgString(key: "algs.search.placeholder", languageCode: languageCode))
        )
    }

    @ViewBuilder
    private func searchRow(_ item: AlgSearchItem) -> some View {
        NavigationLink {
            destinationView(for: item)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(item.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func destinationView(for item: AlgSearchItem) -> some View {
        switch item.destination {
        case .set(let payload):
            AlgCaseListView(payload: payload)
        case .subset(let payload, let subset):
            AlgSubsetCaseListView(payload: payload, subset: subset)
        case .caseDetail(let payload, let algCase):
            AlgCaseDetailView(payload: payload, algCase: algCase)
        case .placeholder(let item):
            AlgSetPlaceholderView(item: item)
        }
    }
}

private struct AlgTrainerSummaryView: View {
    let summary: AlgTrainerSessionSummary
    let weakItems: [AlgTrainerWeakReviewItem]
    let onTrainAgain: () -> Void
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizedAlgString(key: "algs.trainer.summary_title", languageCode: summary.languageCode))
                        .font(.system(size: 34, weight: .bold))

                    Text(summary.scopeTitle)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.top, 8)
                }
                .padding(.top, 8)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    summaryStatCard(
                        title: localizedAlgString(key: "algs.trainer.score_title", languageCode: summary.languageCode),
                        value: accuracyText
                    )
                    summaryStatCard(
                        title: localizedAlgString(key: "algs.trainer.session_time_title", languageCode: summary.languageCode),
                        value: formatAlgTrainerSessionDuration(summary.sessionDuration)
                    )
                    summaryStatCard(
                        title: localizedAlgString(key: "algs.trainer.answered_title", languageCode: summary.languageCode),
                        value: String(summary.answeredCount)
                    )
                    summaryStatCard(
                        title: localizedAlgString(key: "algs.trainer.average_time_title", languageCode: summary.languageCode),
                        value: averageRecognitionText
                    )
                    summaryStatCard(
                        title: localizedAlgString(key: "algs.trainer.best_streak_title", languageCode: summary.languageCode),
                        value: String(summary.bestStreak)
                    )
                    summaryStatCard(
                        title: localizedAlgString(key: "algs.trainer.wrong_title", languageCode: summary.languageCode),
                        value: String(summary.wrongCount)
                    )
                    summaryStatCard(
                        title: localizedAlgString(key: "algs.trainer.skipped_title", languageCode: summary.languageCode),
                        value: String(summary.skipCount)
                    )
                }

                VStack(spacing: 12) {
                    Button(action: onTrainAgain) {
                        Text(localizedAlgString(key: "algs.trainer.train_again", languageCode: summary.languageCode))
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.orange)
                            )
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    if !weakItems.isEmpty {
                        NavigationLink {
                            AlgTrainerWeakReviewView(items: weakItems, languageCode: summary.languageCode)
                        } label: {
                            Text(localizedAlgString(key: "algs.trainer.review_weak", languageCode: summary.languageCode))
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(.secondary.opacity(0.08))
                                )
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onDone) {
                        Text(localizedAlgString(key: "algs.trainer.done", languageCode: summary.languageCode))
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.secondary.opacity(0.08))
                            )
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle(summary.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
    }

    private var accuracyText: String {
        guard summary.answeredCount > 0 else {
            return localizedAlgString(key: "algs.trainer.accuracy_empty", languageCode: summary.languageCode)
        }

        let percent = Int((Double(summary.correctCount) / Double(summary.answeredCount) * 100).rounded())
        return String(
            format: localizedAlgString(key: "algs.trainer.accuracy_format", languageCode: summary.languageCode),
            percent,
            summary.correctCount,
            summary.answeredCount
        )
    }

    private var averageRecognitionText: String {
        guard let average = summary.averageRecognitionDuration else {
            return localizedAlgString(key: "algs.trainer.accuracy_empty", languageCode: summary.languageCode)
        }

        return formatAlgTrainerAverageDuration(average, languageCode: summary.languageCode)
    }

    private func summaryStatCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
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

            let standardAppearance = navigationBar.standardAppearance.copy()
            standardAppearance.titleTextAttributes[.font] = inlineTitleFont
            standardAppearance.subtitleTextAttributes[.font] = inlineSubtitleFont

            let scrollEdgeAppearance = navigationBar.scrollEdgeAppearance?.copy() ?? standardAppearance.copy()
            scrollEdgeAppearance.largeTitleTextAttributes[.font] = largeTitleFont
            scrollEdgeAppearance.titleTextAttributes[.font] = inlineTitleFont
            scrollEdgeAppearance.subtitleTextAttributes[.font] = inlineSubtitleFont

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
            targetNavigationItem.largeSubtitleView = LargeSubtitleContainerView(
                text: largeSubtitle,
                topInset: 4
            )
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
            if item.title != nil || item.subtitle != nil || item.largeSubtitle != nil {
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
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
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
        switch normalizedAlgSetID(setID) {
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
        default:
            return nil
        }
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

private struct AlgCaseDetailView: View {
    let payload: AlgSetPayload
    let algCase: AlgCase
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("algLearnedCasesStore") private var learnedCasesStore: String = "{}"
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
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle(algCase.displayName)
        .navigationBarTitleDisplayMode(.inline)
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
            guard selectedAlgorithmGroupID.isEmpty,
                  let firstDirectionalGroup = directionalAlgorithmGroups?.first else { return }
            selectedAlgorithmGroupID = firstDirectionalGroup.id
        }
    }

    private var isLearned: Bool {
        isAlgCaseLearned(setID: payload.set, caseID: algCase.id, storage: learnedCasesStore)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            caseImage
                .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 6) {
                Text(algCase.displayName)
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

            Text(algCase.displayName)
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
        Image(systemName: "circle", variableValue: clampedProgress)
            .font(.system(size: 16, weight: .medium))
            .symbolVariableValueMode(.draw)
            .foregroundStyle(.blue)
    }
}
#endif
