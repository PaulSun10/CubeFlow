import SwiftUI
import Combine

@MainActor
final class WCADelegatesViewModel: ObservableObject {
    @Published private(set) var regions: [WCADelegateRegion] = []
    @Published private(set) var membersByRegionID: [Int: [WCADelegateMember]] = [:]
    @Published var selectedRegionID: Int?
    @Published private(set) var isLoadingRegions = false
    @Published private(set) var isLoadingMembers = false
    @Published private(set) var errorMessage: String?

    private let initialRegionFriendlyID: String?
    private let initialRegionName: String?
    private var hasLoaded = false

    init(initialRegionFriendlyID: String?, initialRegionName: String?) {
        self.initialRegionFriendlyID = initialRegionFriendlyID?.lowercased()
        self.initialRegionName = initialRegionName?.lowercased()
    }

    var rootRegions: [WCADelegateRegion] {
        regions.filter { $0.parentRegionID == nil }
    }

    var selectedRegion: WCADelegateRegion? {
        rootRegions.first { $0.id == selectedRegionID }
    }

    var selectedSubregions: [WCADelegateRegion] {
        guard let selectedRegionID else { return [] }
        return regions.filter { $0.parentRegionID == selectedRegionID }
    }

    func members(in region: WCADelegateRegion) -> [WCADelegateMember] {
        membersByRegionID[region.id] ?? []
    }

    func load(forceRefresh: Bool = false) async {
        guard forceRefresh || !hasLoaded else { return }
        isLoadingRegions = true
        errorMessage = nil

        do {
            regions = try await WCADelegatesService.shared.regions(forceRefresh: forceRefresh)
            hasLoaded = true
            let initialRegion = regionMatchingInitialDestination()
            if selectedRegionID == nil || !rootRegions.contains(where: { $0.id == selectedRegionID }) {
                selectedRegionID = initialRegion?.id ?? rootRegions.first?.id
            }
            if let selectedRegionID {
                await loadMembers(forRootRegionID: selectedRegionID, forceRefresh: forceRefresh)
            }
        } catch {
            errorMessage = appUserFacingErrorMessage(error, languageCode: currentAppLanguageCode())
        }
        isLoadingRegions = false
    }

    func selectRegion(_ id: Int) async {
        guard selectedRegionID != id || membersByRegionID[id] == nil else { return }
        selectedRegionID = id
        await loadMembers(forRootRegionID: id)
    }

    func refresh() async {
        await load(forceRefresh: true)
    }

    private func regionMatchingInitialDestination() -> WCADelegateRegion? {
        guard initialRegionFriendlyID != nil || initialRegionName != nil,
              let matching = regions.first(where: { region in
                  region.friendlyID?.lowercased() == initialRegionFriendlyID
                      || region.name.lowercased() == initialRegionName
              }) else {
            return nil
        }
        if let parentID = matching.parentRegionID {
            return rootRegions.first { $0.id == parentID }
        }
        return matching
    }

    private func loadMembers(forRootRegionID rootID: Int, forceRefresh: Bool = false) async {
        let targetRegions = regions.filter { $0.id == rootID || $0.parentRegionID == rootID }
        guard !targetRegions.isEmpty else { return }

        isLoadingMembers = true
        errorMessage = nil
        do {
            let loaded = try await withThrowingTaskGroup(
                of: (Int, [WCADelegateMember]).self,
                returning: [Int: [WCADelegateMember]].self
            ) { group in
                for region in targetRegions {
                    group.addTask {
                        let members = try await WCADelegatesService.shared.members(
                            regionID: region.id,
                            forceRefresh: forceRefresh
                        )
                        return (region.id, members)
                    }
                }

                var result: [Int: [WCADelegateMember]] = [:]
                for try await (regionID, members) in group {
                    result[regionID] = members
                }
                return result
            }
            guard selectedRegionID == rootID else { return }
            membersByRegionID.merge(loaded) { _, new in new }
        } catch {
            guard selectedRegionID == rootID else { return }
            errorMessage = appUserFacingErrorMessage(error, languageCode: currentAppLanguageCode())
        }
        if selectedRegionID == rootID {
            isLoadingMembers = false
        }
    }
}

struct WCADelegatesView: View {
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @StateObject private var viewModel: WCADelegatesViewModel
    private let roleColumnWidth: CGFloat = 60
    private let regionColumnWidth: CGFloat = 58
    private let actionsColumnWidth: CGFloat = 44

    init(initialRegionFriendlyID: String? = nil, initialRegionName: String? = nil) {
        _viewModel = StateObject(
            wrappedValue: WCADelegatesViewModel(
                initialRegionFriendlyID: initialRegionFriendlyID,
                initialRegionName: initialRegionName
            )
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                introduction

                if viewModel.isLoadingRegions, viewModel.regions.isEmpty {
                    loadingView
                } else if viewModel.rootRegions.isEmpty {
                    errorView
                } else {
                    regionPicker
                    selectedRegionContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .scrollAwareNavigationTitle(localized("wca.delegates.title", "WCA Delegates"))
        .task { await viewModel.load() }
        .refreshable { await viewModel.refresh() }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            WCAOrganizationPageTitle(
                title: localized("wca.delegates.title", "WCA Delegates")
            )

            delegateIntroductionParagraph(
                text: localized(
                    "wca.delegates.introduction",
                    "WCA Delegate is a role defined in the WCA Motions and depicted in the WCA Regulations. The primary duty of a Delegate is to oversee competitions on behalf of the WCA. A WCA Delegate is responsible for making sure that all WCA Competitions are run according to the Purpose, Values, and Regulations of the WCA."
                ) + " " + localized(
                    "wca.delegates.levels",
                    "The WCA distinguishes between Senior Delegates, Regional Delegates, Full Delegates, Junior Delegates, and Trainee Delegates."
                ),
                emphasized: ["WCA Delegate", "Senior Delegates", "Regional Delegates", "Full Delegates", "Junior Delegates", "Trainee Delegates"],
                firstOccurrenceOnly: ["WCA Delegate"]
            )
            delegateIntroductionParagraph(
                text: localized(
                    "wca.delegates.regional_duties",
                    "In addition to the duties of a WCA Delegate, a Senior Delegate or Regional Delegate is responsible for managing the WCA Delegates in their area and can also be contacted by the community for regional matters."
                )
            )
            delegateIntroductionParagraph(
                text: localized(
                    "wca.delegates.junior_delegates",
                    "New Delegates are listed as Junior Delegates at first; afterwards they are requested to show proficiency managing WCA Competitions before being promoted to WCA Delegates."
                )
            )
            delegateIntroductionParagraph(
                text: localized(
                    "wca.delegates.trainee_delegates",
                    "Trainee Delegates are being trained for the position of WCA Delegate and can only oversee competitions in which a WCA Delegate is present."
                )
            )
            Text(localized(
                "wca.delegates.acknowledges",
                "The WCA acknowledges the following WCA Delegates:"
            ))
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .selectableContent()
        }
    }

    private func delegateIntroductionParagraph(
        text: String,
        emphasized phrases: [String] = [],
        firstOccurrenceOnly: Set<String> = []
    ) -> some View {
        var attributed = AttributedString(text)
        for phrase in phrases {
            var searchStart = attributed.startIndex
            while let range = attributed[searchStart...].range(of: phrase) {
                attributed[range].font = .body.bold()
                if firstOccurrenceOnly.contains(phrase) { break }
                searchStart = range.upperBound
            }
        }
        return Text(attributed)
            .font(.body)
            .foregroundColor(.primary)
            .selectableContent()
    }

    private var regionPicker: some View {
        Menu {
            ForEach(viewModel.rootRegions) { region in
                Button {
                    Task { await viewModel.selectRegion(region.id) }
                } label: {
                    if region.id == viewModel.selectedRegionID {
                        Label(region.name, systemImage: "checkmark")
                    } else {
                        Text(region.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("wca.delegates.region", "Region"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.selectedRegion?.name ?? "")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectedRegionContent: some View {
        if let region = viewModel.selectedRegion {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text(region.name)
                        .font(.system(size: 22, weight: .bold))
                        .selectableContent()
                    Spacer()
                    if let email = region.email, let emailURL = URL(string: "mailto:\(email)") {
                        Link(destination: emailURL) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.tint)
                                .frame(width: 34, height: 34)
                        }
                        .accessibilityLabel(email)
                    }
                }

                if viewModel.isLoadingMembers {
                    loadingView
                } else if let errorMessage = viewModel.errorMessage {
                    errorView(message: errorMessage)
                } else {
                    delegateSections(rootRegion: region)
                }
            }
        }
    }

    @ViewBuilder
    private func delegateSections(rootRegion: WCADelegateRegion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            delegateTableHeader

            let rootMembers = viewModel.members(in: rootRegion)
            if let senior = rootMembers.first(where: { $0.status == "senior_delegate" }) {
                delegateSection(
                    title: localized("wca.delegates.senior_delegate", "Senior Delegate"),
                    members: [senior]
                )
            }

            let otherRootMembers = rootMembers.filter { $0.status != "senior_delegate" }
            if !otherRootMembers.isEmpty {
                delegateSection(title: localized("wca.delegates.delegates", "Delegates"), members: otherRootMembers)
            }

            ForEach(viewModel.selectedSubregions) { subregion in
                let members = viewModel.members(in: subregion)
                if !members.isEmpty {
                    delegateSection(title: subregion.name, members: members)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func delegateSection(
        title: String,
        members: [WCADelegateMember]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                if index > 0 {
                    Divider().padding(.leading, 12)
                }
                delegateRow(member)
            }
        }
    }

    private var delegateTableHeader: some View {
        HStack(spacing: 8) {
            Text(localized("wca.delegates.name", "Name"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(localized("wca.delegates.role", "Role"))
                .frame(width: roleColumnWidth, alignment: .leading)
            Text(localized("wca.delegates.region", "Region"))
                .frame(width: regionColumnWidth, alignment: .leading)
            Color.clear.frame(width: actionsColumnWidth, height: 1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .tertiarySystemFill))
    }

    private func delegateRow(_ member: WCADelegateMember) -> some View {
        ZStack(alignment: .trailing) {
            if let wcaID = member.wcaID, !wcaID.isEmpty {
                NavigationLink {
                    WCAProfileView(wcaID: wcaID, displayName: member.name, avatarURL: member.avatarURL)
                } label: {
                    delegateTableRowContent(member, showsChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                delegateTableRowContent(member, showsChevron: false)
            }

            if let email = member.email, let emailURL = URL(string: "mailto:\(email)") {
                Link(destination: emailURL) {
                    Image(systemName: "envelope.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 30, height: 34)
                }
                .accessibilityLabel(email)
                .padding(.trailing, member.wcaID == nil ? 10 : 26)
                .zIndex(1)
            }
        }
    }

    private func delegateTableRowContent(_ member: WCADelegateMember, showsChevron: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                delegateAvatar(member)

                VStack(alignment: .leading, spacing: 3) {
                    Text(member.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let wcaID = member.wcaID {
                        Text(wcaID)
                            .font(.caption2.italic())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .selectableContent()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(2)

            Text(delegateStatusTitle(member.status))
                .font(.caption)
                .foregroundStyle(.primary)
                .frame(width: roleColumnWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(member.location ?? "")
                .font(.caption)
                .foregroundStyle(.primary)
                .frame(width: regionColumnWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 0) {
                Color.clear.frame(width: 32, height: 1)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18)
                } else {
                    Color.clear.frame(width: 18, height: 1)
                }
            }
            .frame(width: actionsColumnWidth)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func delegateAvatar(_ member: WCADelegateMember) -> some View {
        if let avatarURLString = member.avatarURL, let avatarURL = URL(string: avatarURLString) {
            AsyncImage(url: avatarURL) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                        .contentImageActions(source: .remote(avatarURL))
                } else {
                    delegateAvatarPlaceholder
                }
            }
            .frame(width: 44, height: 44)
            .clipped()
        } else {
            delegateAvatarPlaceholder
                .frame(width: 44, height: 44)
                .background(Color(uiColor: .tertiarySystemFill))
        }
    }

    private var delegateAvatarPlaceholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(localized("wca.delegates.loading", "Loading…"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var errorView: some View {
        errorView(message: viewModel.errorMessage ?? localized("wca.delegates.error", "WCA Delegates is currently unavailable."))
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(localized("wca.delegates.retry", "Try Again")) {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func delegateStatusTitle(_ status: String) -> String {
        switch status {
        case "senior_delegate": return localized("wca.delegates.senior_delegate", "Senior Delegate")
        case "regional_delegate": return localized("wca.delegates.regional_delegate", "Regional Delegate")
        case "junior_delegate": return localized("wca.delegates.junior_delegate", "Junior Delegate")
        case "trainee_delegate": return localized("wca.delegates.trainee_delegate", "Trainee Delegate")
        default: return localized("wca.delegates.delegate", "Delegate")
        }
    }

    private func localized(_ key: String, _ fallback: String) -> String {
        appLocalizedString(key, languageCode: appLanguage, defaultValue: fallback)
    }
}
