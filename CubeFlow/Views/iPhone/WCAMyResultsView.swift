import SwiftUI
import Combine
import UIKit

@MainActor
final class WCAMyResultsViewModel: ObservableObject {
    @Published private(set) var page: WCAPersonResultsPage?
    @Published private(set) var personIdentity: WCAPersonProfileIdentity?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var cachedResultsLastUpdated: Date?
    @Published var selectedEventCode: String = ""

    private var loadedWCAID: String?
    private var loadedLanguageCode: String?
    private var loadedIdentityWCAID: String?

    func loadIdentity(wcaId: String) async {
        guard loadedIdentityWCAID != wcaId else { return }

        do {
            personIdentity = try await WCAResultsService.fetchPersonIdentity(wcaId: wcaId)
            loadedIdentityWCAID = wcaId
        } catch {
            // Results remain usable when the optional public profile request fails.
        }
    }

    func load(wcaId: String, appLanguageCode: String, forceRefresh: Bool = false) async {
        if !forceRefresh, loadedWCAID == wcaId, loadedLanguageCode == appLanguageCode, page != nil {
            return
        }

        isLoading = true
        if page == nil {
            errorMessage = nil
        }

        let cachedSnapshot: WCAResultsService.CachedPersonResultsSnapshot?
        if forceRefresh {
            cachedSnapshot = nil
        } else {
            cachedSnapshot = await WCAResultsService.cachedPersonResults(
                wcaId: wcaId,
                appLanguageCode: appLanguageCode
            )
        }

        if let cachedSnapshot {
            page = cachedSnapshot.page
            cachedResultsLastUpdated = cachedSnapshot.lastUpdated
            loadedWCAID = wcaId
            loadedLanguageCode = appLanguageCode
            if !cachedSnapshot.page.resultsSections.contains(where: { $0.event.code == selectedEventCode }) {
                selectedEventCode = cachedSnapshot.page.resultsSections.first?.event.code ?? ""
            }
            errorMessage = nil
        }

        do {
            let fetchedPage = try await WCAResultsService.fetchPersonResults(
                wcaId: wcaId,
                appLanguageCode: appLanguageCode,
                useCache: false
            )
            page = fetchedPage
            cachedResultsLastUpdated = nil
            loadedWCAID = wcaId
            loadedLanguageCode = appLanguageCode
            if !fetchedPage.resultsSections.contains(where: { $0.event.code == selectedEventCode }) {
                selectedEventCode = fetchedPage.resultsSections.first?.event.code ?? ""
            }
            errorMessage = nil

            let loadedKeyWCAID = wcaId
            let loadedKeyLanguageCode = appLanguageCode
            Task { [weak self] in
                guard let self else { return }
                let enrichedPage = await WCAResultsService.enrichPersonResults(
                    fetchedPage,
                    appLanguageCode: loadedKeyLanguageCode
                )
                await MainActor.run {
                    guard self.loadedWCAID == loadedKeyWCAID,
                          self.loadedLanguageCode == loadedKeyLanguageCode else { return }
                    self.page = enrichedPage
                    if !enrichedPage.resultsSections.contains(where: { $0.event.code == self.selectedEventCode }) {
                        self.selectedEventCode = enrichedPage.resultsSections.first?.event.code ?? ""
                    }
                }
            }
        } catch {
            if cachedSnapshot == nil {
                errorMessage = appUserFacingErrorMessage(error, languageCode: appLanguageCode)
                cachedResultsLastUpdated = nil
            } else {
                errorMessage = nil
            }
        }

        isLoading = false
    }
}

private struct WCAProfileRolePresentation: Identifiable {
    let id: String
    let text: String
    let fullName: String
    let destination: WCAProfileRoleDestination
    let color: WCAProfileRoleColor
}

private enum WCAProfileRoleDestination {
    case delegates(regionFriendlyID: String?, regionName: String?)
    case teamsCommittees(groupFriendlyID: String?)
}

private struct PersonalRecordColumnWidths {
    let event: CGFloat
    let singleNationalRank: CGFloat
    let singleContinentRank: CGFloat
    let singleWorldRank: CGFloat
    let single: CGFloat
    let average: CGFloat
    let averageWorldRank: CGFloat
    let averageContinentRank: CGFloat
    let averageNationalRank: CGFloat
    let oddRankReason: CGFloat

    var total: CGFloat {
        event
            + singleNationalRank
            + singleContinentRank
            + singleWorldRank
            + single
            + average
            + averageWorldRank
            + averageContinentRank
            + averageNationalRank
            + oddRankReason
    }
}

private enum WCAProfileRoleColor {
    case board
    case leader
    case seniorMember
    case member
    case delegate
    case translator

    var foregroundColor: Color {
        switch self {
        case .board: return Self.adaptiveColor(light: 0x3B3B3B, dark: 0xDCDCD6)
        case .leader: return Self.adaptiveColor(light: 0x003366, dark: 0x9CC8FF)
        case .seniorMember: return Self.adaptiveColor(light: 0x664D00, dark: 0xFFE48A)
        case .member: return Self.adaptiveColor(light: 0x1B4D3E, dark: 0x80D5B2)
        case .delegate: return .white
        case .translator: return Self.adaptiveColor(light: 0x5D5D57, dark: 0xDCDCD6)
        }
    }

    var backgroundColor: Color {
        switch self {
        case .delegate:
            return Self.adaptiveColor(light: 0x7A1220, dark: 0x7A1220)
        default:
            return foregroundColor.opacity(0.14)
        }
    }

    var glassTint: Color {
        switch self {
        case .delegate:
            return backgroundColor.opacity(0.92)
        default:
            return foregroundColor.opacity(0.22)
        }
    }

    var usesSolidBackground: Bool {
        switch self {
        case .delegate: return true
        default: return false
        }
    }

    private static func adaptiveColor(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            uiColor(from: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func uiColor(from rgb: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

@available(iOS 16.0, *)
private struct WCAProfileRoleFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 5

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let availableWidth = proposal.width ?? sizes.reduce(0) { $0 + $1.width }
        let rows = makeRows(sizes: sizes, availableWidth: availableWidth)
        let contentWidth = rows.map(\.width).max() ?? 0
        let contentHeight = rows.reduce(0) { $0 + $1.height }
            + CGFloat(max(rows.count - 1, 0)) * verticalSpacing

        return CGSize(
            width: proposal.width ?? contentWidth,
            height: contentHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = makeRows(sizes: sizes, availableWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX + max((bounds.width - row.width) / 2, 0)
            for index in row.indices {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func makeRows(sizes: [CGSize], availableWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()

        for (index, size) in sizes.enumerated() {
            let proposedWidth = row.indices.isEmpty
                ? size.width
                : row.width + horizontalSpacing + size.width
            if !row.indices.isEmpty, proposedWidth > availableWidth {
                rows.append(row)
                row = Row()
            }

            row.indices.append(index)
            row.width += (row.indices.count == 1 ? 0 : horizontalSpacing) + size.width
            row.height = max(row.height, size.height)
        }

        if !row.indices.isEmpty {
            rows.append(row)
        }
        return rows
    }
}

struct WCAProfileView: View {
    private let requestedWCAID: String?
    private let providedDisplayName: String?
    private let providedAvatarURL: String?
    private let providedAvatarIsDefault: Bool?
    private let usesMyResultsTitle: Bool

    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @StateObject private var viewModel = WCAMyResultsViewModel()
    @State private var areEventIconsReady = CompetitionEventIconFont.isAvailable
    @State private var selectedMedalType: WCAMedalType?
    @State private var oddRankPopoverRecordID: String?
    @State private var rolePopoverID: String?
    @State private var teamsCommitteesGroupFriendlyID: String?
    @State private var isShowingTeamsCommittees = false
    @State private var delegatesRegionFriendlyID: String?
    @State private var delegatesRegionName: String?
    @State private var isShowingDelegates = false

    init(profile: WCAUserProfile?) {
        requestedWCAID = profile?.wcaId
        providedDisplayName = profile?.displayName
        providedAvatarURL = profile?.avatarURL
        providedAvatarIsDefault = profile?.avatarIsDefault
        usesMyResultsTitle = true
    }

    init(wcaID: String, displayName: String, avatarURL: String? = nil) {
        requestedWCAID = wcaID
        providedDisplayName = displayName
        providedAvatarURL = avatarURL
        providedAvatarIsDefault = nil
        usesMyResultsTitle = false
    }

    private var wcaId: String? {
        requestedWCAID?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedDisplayName: String {
        let fetchedName = viewModel.personIdentity?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fetchedName, !fetchedName.isEmpty {
            return fetchedName
        }

        let providedName = providedDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let providedName, !providedName.isEmpty {
            return providedName
        }

        return "WCA"
    }

    private var resolvedAvatarURL: String? {
        viewModel.personIdentity?.avatarURL ?? providedAvatarURL
    }

    private var resolvedAvatarIsDefault: Bool {
        viewModel.personIdentity?.avatarIsDefault ?? providedAvatarIsDefault ?? false
    }

    private var profileRoles: [WCAProfileRolePresentation] {
        guard let identity = viewModel.personIdentity else { return [] }

        var roles = identity.roles.map(profileRolePresentation)
        let representedTeamIDs = Set(
            identity.roles.compactMap { $0.groupFriendlyID?.lowercased() }
        )

        roles.append(contentsOf: identity.teams.compactMap { team -> WCAProfileRolePresentation? in
            guard !representedTeamIDs.contains(team.friendlyID.lowercased()) else { return nil }
            let teamName = team.friendlyID.uppercased()
            if teamName == "BOARD" {
                return WCAProfileRolePresentation(
                    id: "team-\(team.friendlyID)",
                    text: teamName,
                    fullName: "WCA Board",
                    destination: .teamsCommittees(groupFriendlyID: nil),
                    color: .board
                )
            }
            if team.isLeader {
                return WCAProfileRolePresentation(
                    id: "team-\(team.friendlyID)",
                    text: "\(teamName) LEADER",
                    fullName: "\(teamName) Leader",
                    destination: .teamsCommittees(groupFriendlyID: team.friendlyID),
                    color: .leader
                )
            }
            if team.isSeniorMember {
                return WCAProfileRolePresentation(
                    id: "team-\(team.friendlyID)",
                    text: "\(teamName) SENIOR MEMBER",
                    fullName: "\(teamName) Senior Member",
                    destination: .teamsCommittees(groupFriendlyID: team.friendlyID),
                    color: .seniorMember
                )
            }
            let memberColor: WCAProfileRoleColor = teamName == "WMCT" ? .translator : .member
            return WCAProfileRolePresentation(
                id: "team-\(team.friendlyID)",
                text: "\(teamName) MEMBER",
                fullName: "\(teamName) Member",
                destination: .teamsCommittees(groupFriendlyID: team.friendlyID),
                color: memberColor
            )
        })

        if let status = identity.delegateStatus?.trimmingCharacters(in: .whitespacesAndNewlines),
           !status.isEmpty,
           !identity.roles.contains(where: { $0.groupType == "delegate_regions" }) {
            roles.append(
                WCAProfileRolePresentation(
                    id: "delegate-\(status)",
                    text: status.replacingOccurrences(of: "_", with: " ").uppercased(),
                    fullName: roleStatusTitle(status),
                    destination: .delegates(regionFriendlyID: nil, regionName: nil),
                    color: .delegate
                )
            )
        }

        return roles
    }

    private func profileRolePresentation(_ role: WCAPersonRoleMembership) -> WCAProfileRolePresentation {
        let status = role.status?
            .replacingOccurrences(of: "_", with: " ")
            .uppercased()

        let text: String
        let fullName: String
        let destination: WCAProfileRoleDestination
        let color: WCAProfileRoleColor
        switch role.groupType {
        case "delegate_regions":
            text = status ?? "DELEGATE"
            fullName = roleStatusTitle(role.status ?? "delegate")
            destination = .delegates(
                regionFriendlyID: role.groupFriendlyID,
                regionName: role.groupName
            )
            color = .delegate
        case "teams_committees", "councils":
            let teamName = (role.groupFriendlyID ?? role.groupName).uppercased()
            text = [teamName, status].compactMap { $0 }.joined(separator: " ")
            fullName = [Optional(role.groupName), role.status.map(roleStatusTitle)]
                .compactMap { $0 }
                .joined(separator: " ")
            destination = .teamsCommittees(groupFriendlyID: role.groupFriendlyID)
            switch role.status {
            case "leader": color = .leader
            case "senior_member": color = .seniorMember
            default: color = teamName == "WMCT" ? .translator : .member
            }
        case "board":
            text = "BOARD"
            fullName = role.groupName
            destination = .teamsCommittees(groupFriendlyID: nil)
            color = .board
        case "officers":
            text = status ?? role.groupName.uppercased()
            fullName = role.status.map(roleStatusTitle) ?? role.groupName
            destination = .teamsCommittees(groupFriendlyID: nil)
            color = .board
        case "translators":
            text = "TRANSLATOR"
            fullName = "Translator"
            destination = .teamsCommittees(groupFriendlyID: nil)
            color = .translator
        default:
            text = [role.groupName.uppercased(), status].compactMap { $0 }.joined(separator: " ")
            fullName = [Optional(role.groupName), role.status.map(roleStatusTitle)]
                .compactMap { $0 }
                .joined(separator: " ")
            destination = .teamsCommittees(groupFriendlyID: role.groupFriendlyID)
            color = .translator
        }

        return WCAProfileRolePresentation(
            id: "role-\(role.id)",
            text: text,
            fullName: fullName,
            destination: destination,
            color: color
        )
    }

    private func roleStatusTitle(_ status: String) -> String {
        status
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    private var navigationTitle: String {
        usesMyResultsTitle
            ? appLocalizedString("settings.wca_my_results", languageCode: appLanguage)
            : resolvedDisplayName
    }

    private var selectedSection: WCAEventResultsSection? {
        guard let page = viewModel.page else { return nil }
        return page.resultsSections.first(where: { $0.event.code == viewModel.selectedEventCode }) ?? page.resultsSections.first
    }

    private var cachedResultsBannerText: String? {
        guard let cachedResultsLastUpdated = viewModel.cachedResultsLastUpdated else { return nil }
        let formattedDate = cachedResultsTimestampFormatter(languageCode: appLanguage).string(from: cachedResultsLastUpdated)
        return String(
            format: appLocalizedString("wca.results.cached_banner_format", languageCode: appLanguage),
            formattedDate
        )
    }

    var body: some View {
        Group {
            if let wcaId, !wcaId.isEmpty {
                content(for: wcaId)
            } else {
                unavailableView(message: appLocalizedString("wca.results_error_missing_wca_id", languageCode: appLanguage))
            }
        }
        .scrollAwareNavigationTitle(
            navigationTitle,
            isEnabled: !usesMyResultsTitle && viewModel.page != nil
        )
        .background {
            ZStack {
                NavigationLink(
                    destination: WCATeamsCommitteesView(
                        initialGroupFriendlyID: teamsCommitteesGroupFriendlyID
                    ),
                    isActive: $isShowingTeamsCommittees,
                    label: { EmptyView() }
                )
                NavigationLink(
                    destination: WCADelegatesView(
                        initialRegionFriendlyID: delegatesRegionFriendlyID,
                        initialRegionName: delegatesRegionName
                    ),
                    isActive: $isShowingDelegates,
                    label: { EmptyView() }
                )
            }
            .hidden()
        }
        .onAppear {
            areEventIconsReady = CompetitionEventIconFont.ensureRegistered()
        }
    }

    @ViewBuilder
    private func content(for wcaId: String) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                if let page = viewModel.page {
                    summaryCard(page: page)
                    if let cachedResultsBannerText {
                        cachedResultsBanner(text: cachedResultsBannerText)
                    }
                    personalRecordsCard(records: page.personalRecords)
                    if let medalCollection = page.medalCollection {
                        medalCollectionCard(medalCollection)
                    }
                    if let recordCollection = page.recordCollection {
                        recordCollectionCard(recordCollection)
                    }
                    resultsCard(sections: page.resultsSections)
                } else if viewModel.isLoading {
                    loadingView
                } else {
                    unavailableView(message: viewModel.errorMessage ?? appLocalizedString("wca.results_error_request_failed", languageCode: appLanguage))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 0)
            .padding(.bottom, 20)
        }
        .task(id: wcaId) {
            async let identityLoad: Void = viewModel.loadIdentity(wcaId: wcaId)
            async let resultsLoad: Void = viewModel.load(wcaId: wcaId, appLanguageCode: appLanguage)
            _ = await (identityLoad, resultsLoad)
        }
        .onChange(of: appLanguage) { newValue in
            Task {
                await viewModel.load(wcaId: wcaId, appLanguageCode: newValue, forceRefresh: true)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.page != nil {
                    Button {
                        Task {
                            await viewModel.load(wcaId: wcaId, appLanguageCode: appLanguage, forceRefresh: true)
                        }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }

    private func cachedResultsBanner(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.clock")
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("wca.results_loading")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func unavailableView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let wcaId, !wcaId.isEmpty {
                Button("wca.results_retry") {
                    Task {
                        await viewModel.load(wcaId: wcaId, appLanguageCode: appLanguage, forceRefresh: true)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryCard(page: WCAPersonResultsPage) -> some View {
        VStack(spacing: 16) {
            profileIdentitySection(page: page)
            profileInformationCard(
                summary: page.summary,
                countryCode: viewModel.personIdentity?.countryISO2
                    ?? regionCountryCode(from: page.summary.region)
            )
        }
    }

    private func profileIdentitySection(page: WCAPersonResultsPage) -> some View {
        return VStack(spacing: 14) {
            VStack(spacing: 4) {
                ScrollAwareContentTitle(title: resolvedDisplayName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .selectableContent()

                if let previousIdentityText = page.previousIdentityText {
                    Text(previousIdentityText)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .selectableContent()
                }
            }

            if !profileRoles.isEmpty {
                profileRoleBadges
            }

            profileAvatar
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var profileRoleBadges: some View {
        if #available(iOS 16.0, *) {
            WCAProfileRoleFlowLayout(horizontalSpacing: 6, verticalSpacing: 5) {
                ForEach(profileRoles) { role in
                    profileRoleBadge(role)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(profileRoles) { role in
                        profileRoleBadge(role)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let avatarURLString = resolvedAvatarURL,
           let avatarURL = URL(string: avatarURLString) {
            AsyncImage(url: avatarURL) { phase in
                switch phase {
                case .success(let image):
                    if resolvedAvatarIsDefault {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .contentImageActions(source: .remote(avatarURL))
                    } else {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 300)
                            .contentImageActions(source: .remote(avatarURL))
                    }
                case .failure:
                    profileAvatarPlaceholder
                        .frame(width: 100, height: 100)
                case .empty:
                    ProgressView()
                        .frame(width: 100, height: 100)
                @unknown default:
                    profileAvatarPlaceholder
                        .frame(width: 100, height: 100)
                }
            }
        } else {
            profileAvatarPlaceholder
                .frame(width: 100, height: 100)
        }
    }

    private var profileAvatarPlaceholder: some View {
        Image(systemName: "person.crop.square")
            .font(.system(size: 52, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func profileRoleBadge(_ role: WCAProfileRolePresentation) -> some View {
        let content = Text(role.text)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(role.color.foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

        Button {
            rolePopoverID = rolePopoverID == role.id ? nil : role.id
        } label: {
            if #available(iOS 26.0, *) {
                if role.color.usesSolidBackground {
                    content
                        .background(role.color.backgroundColor, in: Capsule())
                        .glassEffect(.regular.tint(role.color.glassTint), in: .capsule)
                } else {
                    content
                        .glassEffect(.regular.tint(role.color.glassTint), in: .capsule)
                }
            } else {
                content
                    .background(role.color.backgroundColor, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(role.color.foregroundColor.opacity(0.22), lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(role.fullName)
        .background {
            AdaptiveContextPopover(
                isPresented: Binding(
                    get: { rolePopoverID == role.id },
                    set: { isPresented in
                        if !isPresented, rolePopoverID == role.id {
                            rolePopoverID = nil
                        }
                    }
                )
            ) {
                roleContextPopover(role)
            }
        }
    }

    private func roleContextPopover(_ role: WCAProfileRolePresentation) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(role.fullName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                rolePopoverID = nil
                switch role.destination {
                case .delegates(let regionFriendlyID, let regionName):
                    delegatesRegionFriendlyID = regionFriendlyID
                    delegatesRegionName = regionName
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isShowingDelegates = true
                    }
                case .teamsCommittees(let groupFriendlyID):
                    teamsCommitteesGroupFriendlyID = groupFriendlyID
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isShowingTeamsCommittees = true
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(roleDestinationActionTitle(role.destination))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }

    private func roleDestinationActionTitle(_ destination: WCAProfileRoleDestination) -> String {
        switch destination {
        case .delegates:
            return appLocalizedString(
                "wca.delegates.view_action",
                languageCode: appLanguage,
                defaultValue: "View WCA Delegates"
            )
        case .teamsCommittees:
            return appLocalizedString(
                "wca.teams_committees.view_action",
                languageCode: appLanguage,
                defaultValue: "View WCA Teams & Committees"
            )
        }
    }

    private func profileInformationCard(
        summary: WCAPersonResultsSummary,
        countryCode: String?
    ) -> some View {
        let regionPrefix = countryCode.map(flagEmoji(for:))
        let region = [regionPrefix, localizedSummaryRegion(summary.region)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let rows = [
            SelectableKeyValueRow(
                label: localizedSummaryString(key: "wca.results_region"),
                value: region
            ),
            SelectableKeyValueRow(label: "WCA ID", value: summary.wcaId),
            SelectableKeyValueRow(
                label: localizedSummaryString(key: "wca.results_gender"),
                value: localizedGender(summary.gender)
            ),
            SelectableKeyValueRow(
                label: localizedSummaryString(key: "wca.results_competitions"),
                value: summary.competitions
            ),
            SelectableKeyValueRow(
                label: localizedSummaryString(key: "wca.results_completed_solves"),
                value: summary.completedSolves
            )
        ]

        return SelectableKeyValueContent(rows: rows)
            .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
        }
    }

    private func personalRecordsCard(records: [WCAPersonalRecord]) -> some View {
        let columnWidths = personalRecordColumnWidths(records: records)

        return VStack(alignment: .leading, spacing: 12) {
            Text("wca.results_current_personal_records")
                .font(.system(size: 18, weight: .semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    personalRecordsHeaderRow(widths: columnWidths)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            personalRecordRow(record, widths: columnWidths)

                            if index < records.count - 1 {
                                Divider()
                                    .padding(.leading, 6)
                            }
                        }
                    }
                }
                .selectableContent()
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .selectableContent()
    }

    private func personalRecordsHeaderRow(widths: PersonalRecordColumnWidths) -> some View {
        HStack(spacing: 0) {
            personalRecordHeaderCell("wca.results_event", width: widths.event, alignment: .leading)
            personalRecordHeaderCell("wca.results_nr", width: widths.singleNationalRank)
            personalRecordHeaderCell("wca.results_cr", width: widths.singleContinentRank)
            personalRecordHeaderCell("wca.results_wr", width: widths.singleWorldRank)
            personalRecordHeaderCell("wca.results_single", width: widths.single)
            personalRecordHeaderCell("wca.results_average", width: widths.average)
            personalRecordHeaderCell("wca.results_wr", width: widths.averageWorldRank)
            personalRecordHeaderCell("wca.results_cr", width: widths.averageContinentRank)
            personalRecordHeaderCell("wca.results_nr", width: widths.averageNationalRank)
            Color.clear.frame(width: widths.oddRankReason, height: 1)
        }
        .frame(width: widths.total, alignment: .leading)
        .padding(.horizontal, 6)
    }

    private func personalRecordHeaderCell(
        _ titleKey: String,
        width: CGFloat,
        alignment: Alignment = .center
    ) -> some View {
        Text(appLocalizedString(titleKey, languageCode: appLanguage))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: width, alignment: alignment)
    }

    private func personalRecordRow(
        _ record: WCAPersonalRecord,
        widths: PersonalRecordColumnWidths
    ) -> some View {
        HStack(spacing: 0) {
            myResultsEventNameLabel(record.event, font: .system(size: 14, weight: .semibold))
                .lineLimit(1)
                .frame(width: widths.event, alignment: .leading)

            personalRecordRankCell(record.singleNationalRank, width: widths.singleNationalRank, scope: .national)
            personalRecordRankCell(record.singleContinentRank, width: widths.singleContinentRank, scope: .continent)
            personalRecordRankCell(record.singleWorldRank, width: widths.singleWorldRank, scope: .world)
            personalRecordValueCell(record.single, width: widths.single, weight: .bold)
            personalRecordValueCell(record.average, width: widths.average, weight: .bold)
            personalRecordRankCell(record.averageWorldRank, width: widths.averageWorldRank, scope: .world)
            personalRecordRankCell(record.averageContinentRank, width: widths.averageContinentRank, scope: .continent)
            personalRecordRankCell(record.averageNationalRank, width: widths.averageNationalRank, scope: .national)
            ZStack {
                Color.clear
                if let reason = record.oddRankReason {
                    Button {
                        oddRankPopoverRecordID = oddRankPopoverRecordID == record.id ? nil : record.id
                    } label: {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(reason)
                    .background {
                        AdaptiveContextPopover(
                            isPresented: Binding(
                                get: { oddRankPopoverRecordID == record.id },
                                set: { isPresented in
                                    if !isPresented, oddRankPopoverRecordID == record.id {
                                        oddRankPopoverRecordID = nil
                                    }
                                }
                            )
                        ) {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                            .frame(width: 270)
                        }
                    }
                }
            }
            .frame(width: widths.oddRankReason, height: 24)
        }
        .frame(width: widths.total, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
    }

    private func personalRecordValueCell(
        _ value: String?,
        width: CGFloat,
        weight: Font.Weight = .medium
    ) -> some View {
        Text(value ?? "-")
            .font(.system(size: 13, weight: weight))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: width, alignment: .center)
    }

    private func personalRecordRankCell(
        _ value: String?,
        width: CGFloat,
        scope: WCARankScope
    ) -> some View {
        Text(value ?? "-")
            .font(.system(size: 13, weight: scope.fontWeight(for: value)))
            .foregroundStyle(scope.color(for: value))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: width, alignment: .center)
    }

    private func personalRecordColumnWidths(records: [WCAPersonalRecord]) -> PersonalRecordColumnWidths {
        let headerFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let rankFont = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let eventFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let horizontalPadding: CGFloat = 16

        func header(_ key: String) -> String {
            appLocalizedString(key, languageCode: appLanguage)
        }

        func measuredWidth(_ values: [String], font: UIFont, headerKey: String) -> CGFloat {
            let candidates = values + [header(headerKey), "-"]
            let contentWidth = candidates.map { personalRecordTextWidth($0, font: font) }.max() ?? 0
            return ceil(contentWidth + horizontalPadding)
        }

        let eventContentWidth = records.map { record -> CGFloat in
            let nameWidth = personalRecordTextWidth(localizedEventName(for: record.event), font: eventFont)
            let iconWidth: CGFloat = areEventIconsReady
                && CompetitionEventIconFont.glyph(for: record.event.code, title: record.event.name) != nil
                ? 22
                : 0
            return nameWidth + iconWidth
        }.max() ?? 0

        return PersonalRecordColumnWidths(
            event: ceil(max(
                eventContentWidth,
                personalRecordTextWidth(header("wca.results_event"), font: headerFont)
            ) + horizontalPadding),
            singleNationalRank: measuredWidth(records.compactMap(\.singleNationalRank), font: rankFont, headerKey: "wca.results_nr"),
            singleContinentRank: measuredWidth(records.compactMap(\.singleContinentRank), font: rankFont, headerKey: "wca.results_cr"),
            singleWorldRank: measuredWidth(records.compactMap(\.singleWorldRank), font: rankFont, headerKey: "wca.results_wr"),
            single: measuredWidth(records.compactMap(\.single), font: valueFont, headerKey: "wca.results_single"),
            average: measuredWidth(records.compactMap(\.average), font: valueFont, headerKey: "wca.results_average"),
            averageWorldRank: measuredWidth(records.compactMap(\.averageWorldRank), font: rankFont, headerKey: "wca.results_wr"),
            averageContinentRank: measuredWidth(records.compactMap(\.averageContinentRank), font: rankFont, headerKey: "wca.results_cr"),
            averageNationalRank: measuredWidth(records.compactMap(\.averageNationalRank), font: rankFont, headerKey: "wca.results_nr"),
            oddRankReason: 30
        )
    }

    private func personalRecordTextWidth(_ value: String, font: UIFont) -> CGFloat {
        (value as NSString).size(withAttributes: [.font: font]).width
    }

    private func medalCollectionCard(_ collection: WCAMedalCollection) -> some View {
        collectionCard(title: collection.title) {
            ForEach(WCAMedalType.allCases, id: \.self) { type in
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        if selectedMedalType == type {
                            selectedMedalType = nil
                        } else {
                            selectedMedalType = type
                            if let firstMatchingSection = viewModel.page?.resultsSections.first(where: { section in
                                section.results.contains(where: { $0.podiumPlace == type })
                            }) {
                                viewModel.selectedEventCode = firstMatchingSection.event.code
                            }
                        }
                    }
                } label: {
                    collectionMetric(
                        label: collection.label(for: type),
                        value: String(collection.count(for: type)),
                        valueColor: type.semanticColor,
                        selected: selectedMedalType == type
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedMedalType == type ? .isSelected : [])
            }
        }
    }

    private func recordCollectionCard(_ collection: WCARecordCollection) -> some View {
        collectionCard(title: collection.title) {
            collectionMetric(
                label: collection.worldLabel,
                value: collection.worldCount.map(String.init) ?? ""
            )
            collectionMetric(
                label: collection.continentLabel,
                value: collection.continentCount.map(String.init) ?? ""
            )
            collectionMetric(
                label: collection.nationalLabel,
                value: collection.nationalCount.map(String.init) ?? ""
            )
        }
    }

    private func collectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
            HStack(spacing: 8) {
                content()
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .selectableContent()
    }

    private func collectionMetric(
        label: String,
        value: String,
        valueColor: Color = .primary,
        selected: Bool = false
    ) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .frame(minWidth: 32, minHeight: 28)
                .padding(.horizontal, 7)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(WCAProfileHighlightColor.medalSelection)
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func resultsCard(sections: [WCAEventResultsSection]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("wca.results_results")
                .font(.system(size: 18, weight: .semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HorizontalCapsuleSelectorGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(sections) { section in
                            let isSelected = viewModel.selectedEventCode == section.event.code
                            Button {
                                viewModel.selectedEventCode = section.event.code
                            } label: {
                                myResultsEventNameLabel(
                                    section.event,
                                    font: .system(size: 14, weight: .semibold),
                                    color: isSelected ? .white : .primary
                                )
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .horizontalCapsuleSelectorSurface(isSelected: isSelected) {
                                        Group {
                                            if isSelected {
                                                Capsule().fill(Color.blue)
                                            } else {
                                                Capsule().fill(.thinMaterial)
                                            }
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 1)
            }

            if let selectedSection {
                LazyVStack(spacing: 10) {
                    ForEach(groupedResults(in: selectedSection)) { group in
                        competitionGroupRow(group)
                    }
                }
            } else {
                Text("wca.results_empty")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func competitionGroupRow(_ group: WCACompetitionGroup) -> some View {
        let highlightsSelectedMedal = selectedMedalType.map { selectedType in
            group.results.contains(where: { $0.podiumPlace == selectedType })
        } ?? false

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let countryISO2 = group.countryISO2 {
                    Text(flagEmoji(for: countryISO2))
                }

                Text(group.competitionName)
                    .font(.system(size: 16, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background {
                        if highlightsSelectedMedal {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(WCAProfileHighlightColor.medalSelection)
                        }
                    }
            }

            VStack(spacing: 10) {
                ForEach(Array(group.results.enumerated()), id: \.element.id) { index, result in
                    resultRow(result)

                    if index < group.results.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func resultRow(_ result: WCACompetitionResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.roundName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("wca.results_place")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(result.place ?? "—")
                        .font(.system(size: 16, weight: .bold))
                        .monospacedDigit()
                }
            }

            HStack(alignment: .top, spacing: 20) {
                resultMetric(titleKey: "wca.results_single", value: result.single, emphasis: result.singleEmphasis)
                resultMetric(titleKey: "wca.results_average", value: result.average, emphasis: result.averageEmphasis)
            }
            .padding(.top, -16)

            if !result.solves.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("wca.results_solves")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(formattedSolves(result.solves))
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func resultMetric(
        titleKey: String,
        value: String?,
        emphasis: WCAResultEmphasis?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(titleKey))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value ?? "—")
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
                if let marker = emphasis?.marker {
                    Text(marker)
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(emphasis?.color ?? .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedSolves(_ solves: [WCAAttemptResult]) -> String {
        solves
            .map { solve in
                solve.isTrimmed ? "(\(solve.value))" : solve.value
            }
            .joined(separator: ", ")
    }

    private func localizedEventName(for event: WCAEventDescriptor) -> String {
        CompetitionEventPresentation.normalizedName(
            for: event.code,
            fallback: event.name,
            languageCode: appLanguage
        )
    }

    private func myResultsEventNameLabel(
        _ event: WCAEventDescriptor,
        font: Font,
        color: Color = .primary
    ) -> some View {
        HStack(alignment: .center, spacing: 7) {
            if areEventIconsReady,
               let glyph = CompetitionEventIconFont.glyph(for: event.code, title: event.name) {
                CompetitionEventGlyph(
                    glyph: glyph,
                    eventName: localizedEventName(for: event),
                    size: 15,
                    color: color
                )
                    .accessibilityHidden(true)
            }

            Text(localizedEventName(for: event))
                .font(font)
                .foregroundStyle(color)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func groupedResults(in section: WCAEventResultsSection) -> [WCACompetitionGroup] {
        var groups: [WCACompetitionGroup] = []

        for result in section.results {
            let groupKey = result.competitionPath ?? result.competitionName

            if let lastIndex = groups.indices.last,
               groups[lastIndex].key == groupKey {
                groups[lastIndex].results.append(result)
            } else {
                groups.append(
                    WCACompetitionGroup(
                        key: groupKey,
                        competitionName: result.competitionName,
                        countryISO2: result.countryISO2,
                        results: [result]
                    )
                )
            }
        }

        return groups
    }

    private func localizedSummaryRegion(_ rawValue: String) -> String {
        rawValue
    }

    private func localizedGender(_ rawValue: String) -> String {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        let key: String
        switch normalized {
        case "m", "male":
            key = "wca.gender.male"
        case "f", "female":
            key = "wca.gender.female"
        case "o", "other":
            key = "wca.gender.other"
        default:
            return rawValue
        }

        return localizedSummaryString(key: key)
    }

    private func localizedSummaryString(key: String) -> String {
        appLocalizedString(key, languageCode: appLanguage)
    }

    private func regionCountryCode(from region: String) -> String? {
        let trimmed = region.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let override = regionCountryCodeOverrides[trimmed] {
            return override
        }

        let normalizedTarget = normalizedRegionName(trimmed)
        let localeIdentifiers = [
            "en_US",
            "zh-Hans",
            "zh_Hans_CN"
        ]

        for code in Locale.isoRegionCodes {
            guard code.count == 2 else {
                continue
            }

            for localeIdentifier in localeIdentifiers {
                let locale = Locale(identifier: localeIdentifier)
                guard let localized = locale.localizedString(forRegionCode: code) else {
                    continue
                }

                if normalizedRegionName(localized) == normalizedTarget {
                    return code
                }
            }
        }

        return nil
    }

    private func normalizedRegionName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "hong kong sar china", with: "hong kong china")
            .replacingOccurrences(of: "macao sar china", with: "macau china")
            .replacingOccurrences(of: "macao", with: "macau")
            .replacingOccurrences(of: "中國", with: "中国")
            .replacingOccurrences(of: "澳門", with: "澳门")
            .replacingOccurrences(of: "臺", with: "台")
            .replacingOccurrences(of: "[^a-zA-Z0-9\\p{Han}]+", with: "", options: .regularExpression)
            .lowercased()
    }
}

struct WCAMyResultsView: View {
    let profile: WCAUserProfile?

    var body: some View {
        WCAProfileView(profile: profile)
    }
}

@MainActor
final class WCAMyCompetitionsViewModel: ObservableObject {
    @Published private(set) var page: WCAMyCompetitionsPage?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func load(forceRefresh: Bool = false) async {
        if !forceRefresh, page != nil {
            return
        }

        isLoading = true
        if page == nil {
            errorMessage = nil
        }

        do {
            page = try await WCAMyCompetitionsService.fetchMyCompetitions(
                authManager: WCAAuthManager.shared
            )
            errorMessage = nil
        } catch {
            errorMessage = appUserFacingErrorMessage(error, languageCode: currentAppLanguageCode())
        }

        isLoading = false
    }
}

struct WCAMyCompetitionsView: View {
    let profile: WCAUserProfile?

    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("requestedIPhoneTab") private var requestedIPhoneTab: String = ""
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = WCAMyCompetitionsViewModel()
    @State private var isUpcomingExpanded = true
    @State private var isPastExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                myCompetitionsIntro

                if let page = viewModel.page {
                    myCompetitionsSection(page: page)
                    Divider()
                    bookmarkedCompetitionsSection(page.bookmarkedCompetitions)
                } else if viewModel.isLoading {
                    loadingCard
                } else {
                    errorCard(message: viewModel.errorMessage ?? appLocalizedString("wca.competitions_error_request_failed", languageCode: appLanguage))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 0)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text(appLocalizedString("settings.wca_my_competitions", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.load()
        }
        .modifier(
            WCAMyCompetitionsToolbarModifier(
                isLoading: viewModel.isLoading,
                profile: profile,
                refresh: {
                    Task {
                        await viewModel.load(forceRefresh: true)
                    }
                }
            )
        )
        .refreshable {
            await viewModel.load(forceRefresh: true)
        }
    }

    private var myCompetitionsIntro: some View {
        Text("wca.competitions_intro")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func myCompetitionsSection(page: WCAMyCompetitionsPage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if page.futureCompetitions.isEmpty {
                emptyUpcomingView
            } else {
                DisclosureGroup(isExpanded: $isUpcomingExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        competitionRows(
                            page.futureCompetitions,
                            registrationsByCompetition: page.registrationsByCompetition
                        )
                    }
                    .padding(.top, 10)
                } label: {
                    disclosureLabel("wca.competitions_upcoming")
                }
                .tint(.primary)

                Divider()
            }

            DisclosureGroup(isExpanded: $isPastExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    if page.pastCompetitions.isEmpty {
                        emptyText("wca.competitions_empty_past")
                    } else {
                        competitionRows(
                            page.pastCompetitions,
                            registrationsByCompetition: page.registrationsByCompetition
                        )
                    }
                }
                .padding(.top, 10)
            } label: {
                Text(
                    String(
                        format: appLocalizedString("wca.competitions_past_format", languageCode: appLanguage),
                        page.pastCompetitions.count
                    )
                )
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            }
            .tint(.primary)
        }
    }

    private func bookmarkedCompetitionsSection(_ competitions: [WCAMyCompetitionSummary]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.primary)

                prominentSectionHeader("wca.competitions_bookmarked")
            }

            Text("wca.competitions_bookmarked_intro")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if competitions.isEmpty {
                emptyText("wca.competitions_empty_bookmarked")
                    .padding(.top, 2)
            } else {
                competitionRows(competitions, registrationsByCompetition: [:])
                    .padding(.top, 2)
            }
        }
    }

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
    }

    private func prominentSectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.primary)
    }

    private func disclosureLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
    }

    private func competitionRows(
        _ competitions: [WCAMyCompetitionSummary],
        registrationsByCompetition: [String: String]
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(competitions.enumerated()), id: \.element.id) { index, competition in
                Button {
                    openCompetition(competition)
                } label: {
                    competitionRow(
                        competition,
                        registrationStatus: registrationsByCompetition[competition.id]
                    )
                }
                .buttonStyle(.plain)

                if index < competitions.count - 1 {
                    Divider()
                        .padding(.leading, 2)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func competitionRow(
        _ competition: WCAMyCompetitionSummary,
        registrationStatus: String?
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(competition.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let registrationStatusText = localizedRegistrationStatus(registrationStatus) {
                        Text(registrationStatusText)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(statusColor(for: registrationStatus), in: Capsule())
                    }
                }

                Text(competition.localizedLocation(languageCode: appLanguage))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(competition.localizedDateRange(languageCode: appLanguage))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var emptyUpcomingView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(emptyUpcomingAttributedMessage)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color(red: 60 / 255, green: 110 / 255, blue: 132 / 255))
                .tint(Color(red: 230 / 255, green: 69 / 255, blue: 3 / 255))
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "cubeflow", url.host == "competitions" {
                        requestedIPhoneTab = "competitions"
                        return .handled
                    }
                    openURL(url)
                    return .handled
                })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 17)
        .background(Color(red: 250 / 255, green: 255 / 255, blue: 255 / 255), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(red: 178 / 255, green: 212 / 255, blue: 221 / 255), lineWidth: 1)
        }
    }

    private var emptyUpcomingAttributedMessage: AttributedString {
        let markdown = appLocalizedString("wca.competitions_empty_upcoming_markdown", languageCode: appLanguage)
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("wca.competitions_loading")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func errorCard(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("wca.results_retry") {
                Task {
                    await viewModel.load(forceRefresh: true)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func emptyText(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func openCompetition(_ competition: WCAMyCompetitionSummary) {
        guard let url = competition.officialURL else { return }
        openURL(url)
    }

    private func localizedRegistrationStatus(_ status: String?) -> String? {
        guard let status else { return nil }
        switch status.lowercased() {
        case "accepted":
            return appLocalizedString("wca.competitions_status_accepted", languageCode: appLanguage)
        case "pending":
            return appLocalizedString("wca.competitions_status_pending", languageCode: appLanguage)
        case "waiting_list", "waitlist", "waitlisted":
            return appLocalizedString("wca.competitions_status_waitlisted", languageCode: appLanguage)
        default:
            return nil
        }
    }

    private func statusColor(for status: String?) -> Color {
        switch status?.lowercased() {
        case "accepted":
            return .green
        case "pending":
            return .orange
        case "waiting_list", "waitlist", "waitlisted":
            return .blue
        default:
            return .secondary
        }
    }
}

private struct WCAMyCompetitionsToolbarModifier: ViewModifier {
    let isLoading: Bool
    let profile: WCAUserProfile?
    let refresh: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.modifier(
                WCAMyCompetitionsToolbarWithSpacerModifier(
                    isLoading: isLoading,
                    profile: profile,
                    refresh: refresh
                )
            )
        } else {
            content.modifier(
                WCAMyCompetitionsToolbarDefaultModifier(
                    isLoading: isLoading,
                    profile: profile,
                    refresh: refresh
                )
            )
        }
    }
}

private struct WCAMyCompetitionsToolbarDefaultModifier: ViewModifier {
    let isLoading: Bool
    let profile: WCAUserProfile?
    let refresh: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            wcaCompetitionsRefreshToolbarItem(isLoading: isLoading, refresh: refresh)
            wcaCompetitionsResultsToolbarItem(profile: profile)
        }
    }
}

@available(iOS 26.0, *)
private struct WCAMyCompetitionsToolbarWithSpacerModifier: ViewModifier {
    let isLoading: Bool
    let profile: WCAUserProfile?
    let refresh: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            wcaCompetitionsRefreshToolbarItem(isLoading: isLoading, refresh: refresh)
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            wcaCompetitionsResultsToolbarItem(profile: profile)
        }
    }
}

private func wcaCompetitionsRefreshToolbarItem(
    isLoading: Bool,
    refresh: @escaping () -> Void
) -> ToolbarItem<(), some View> {
    ToolbarItem(placement: .topBarTrailing) {
        Button(action: refresh) {
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .disabled(isLoading)
    }
}

private func wcaCompetitionsResultsToolbarItem(
    profile: WCAUserProfile?
) -> ToolbarItem<(), some View> {
    ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
            WCAMyResultsView(profile: profile)
        } label: {
            Text("settings.wca_my_results")
        }
    }
}

struct WCAMyCompetitionsPage: Sendable, Codable {
    let futureCompetitions: [WCAMyCompetitionSummary]
    let pastCompetitions: [WCAMyCompetitionSummary]
    let bookmarkedCompetitions: [WCAMyCompetitionSummary]
    let registrationsByCompetition: [String: String]

    enum CodingKeys: String, CodingKey {
        case futureCompetitions = "future_competitions"
        case pastCompetitions = "past_competitions"
        case bookmarkedCompetitions = "bookmarked_competitions"
        case registrationsByCompetition = "registrations_by_competition"
    }
}

struct WCAMyCompetitionSummary: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let website: String?
    let startDate: String?
    let endDate: String?
    let registrationOpen: String?
    let url: String?
    let city: String?
    let countryISO2: String?
    let shortDisplayName: String?
    let registrationStatus: String?

    var displayName: String {
        shortDisplayName?.isEmpty == false ? shortDisplayName! : name
    }

    var officialURL: URL? {
        if let url, !url.isEmpty {
            if url.hasPrefix("http") {
                return URL(string: url)
            }
            return URL(string: "https://www.worldcubeassociation.org\(url.hasPrefix("/") ? "" : "/")\(url)")
        }
        return URL(string: "https://www.worldcubeassociation.org/competitions/\(id)")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case website
        case startDate = "start_date"
        case endDate = "end_date"
        case registrationOpen = "registration_open"
        case url
        case city
        case countryISO2 = "country_iso2"
        case shortDisplayName = "short_display_name"
        case registrationStatus = "registration_status"
    }

    func localizedLocation(languageCode: String) -> String {
        let cityText = city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let countryText = localizedCountryName(languageCode: languageCode)

        if cityText.isEmpty {
            return countryText
        }
        if countryText.isEmpty {
            return cityText
        }
        return "\(cityText), \(countryText)"
    }

    func localizedDateRange(languageCode: String) -> String {
        guard let start = parsedDate(from: startDate) else {
            return startDate ?? ""
        }

        let locale = appLocale(for: languageCode)
        if let end = parsedDate(from: endDate), !Calendar.current.isDate(start, inSameDayAs: end) {
            let formatter = DateIntervalFormatter()
            formatter.locale = locale
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: start, to: end)
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: start)
    }

    private func localizedCountryName(languageCode: String) -> String {
        guard let countryISO2, !countryISO2.isEmpty else { return "" }
        let locale = appLocale(for: languageCode)
        return locale.localizedString(forRegionCode: countryISO2) ?? countryISO2
    }

    private func parsedDate(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

enum WCAMyCompetitionsService {
    static func fetchMyCompetitions(authManager: WCAAuthManager) async throws -> WCAMyCompetitionsPage {
        guard let url = URL(string: "https://www.worldcubeassociation.org/api/v0/competitions/mine") else {
            throw WCAMyCompetitionsFetchError.invalidURL
        }

        var request = try await authManager.authorizedRequest(for: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WCAMyCompetitionsFetchError.requestFailed
        }

        if httpResponse.statusCode == 401 {
            throw WCAMyCompetitionsFetchError.notSignedIn
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw WCAMyCompetitionsFetchError.requestFailed
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(WCAMyCompetitionsPage.self, from: data)
        } catch {
            throw WCAMyCompetitionsFetchError.invalidResponse
        }
    }
}

enum WCAMyCompetitionsFetchError: LocalizedError {
    case invalidURL
    case notSignedIn
    case requestFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return currentAppLocalizedString("wca.competitions_error_request_failed")
        case .notSignedIn:
            return currentAppLocalizedString("wca.competitions_error_sign_in")
        case .requestFailed:
            return currentAppLocalizedString("wca.competitions_error_request_failed")
        case .invalidResponse:
            return currentAppLocalizedString("wca.competitions_error_invalid_response")
        }
    }
}

private struct WCACompetitionGroup: Identifiable {
    let key: String
    let competitionName: String
    let countryISO2: String?
    var results: [WCACompetitionResult]

    var id: String { key }
}

private func cachedResultsTimestampFormatter(languageCode: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = appLocale(for: languageCode)
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}

func flagEmoji(for countryCode: String) -> String {
    let uppercased = countryCode.uppercased()
    guard uppercased.count == 2 else { return "" }

    let scalars = uppercased.unicodeScalars.compactMap { scalar -> UnicodeScalar? in
        UnicodeScalar(127397 + scalar.value)
    }

    return String(String.UnicodeScalarView(scalars))
}

private let regionCountryCodeOverrides: [String: String] = [
    "China": "CN",
    "Hong Kong, China": "HK",
    "Macau, China": "MO",
    "Republic of Korea": "KR",
    "Palestine": "PS"
]

private struct AdaptiveContextPopover<Content: View>: UIViewRepresentable {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ anchorView: UIView, context: Context) {
        context.coordinator.anchorView = anchorView

        if isPresented {
            context.coordinator.presentIfNeeded(content: AnyView(content()))
        } else {
            context.coordinator.dismissIfNeeded()
        }
    }

    final class Coordinator: NSObject, UIPopoverPresentationControllerDelegate {
        private var isPresented: Binding<Bool>
        weak var anchorView: UIView?
        private weak var presentedController: UIViewController?

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }

        func presentIfNeeded(content: AnyView) {
            guard presentedController == nil,
                  let anchorView,
                  anchorView.window != nil,
                  let presenter = anchorView.nearestPresentingViewController else { return }

            let controller = UIHostingController(rootView: content)
            controller.modalPresentationStyle = .popover
            controller.view.backgroundColor = .clear

            let availableSize = CGSize(
                width: min(300, max((anchorView.window?.bounds.width ?? 320) - 32, 220)),
                height: max((anchorView.window?.bounds.height ?? 480) - 64, 180)
            )
            if #available(iOS 16.0, *) {
                controller.preferredContentSize = controller.sizeThatFits(in: availableSize)
            } else {
                controller.view.bounds.size = availableSize
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                controller.preferredContentSize = controller.view.systemLayoutSizeFitting(
                    UIView.layoutFittingCompressedSize
                )
            }

            guard let popover = controller.popoverPresentationController else { return }
            popover.sourceView = anchorView
            popover.sourceRect = anchorView.bounds
            popover.permittedArrowDirections = [.up, .down, .left, .right]
            popover.delegate = self

            presentedController = controller
            presenter.present(controller, animated: true)
        }

        func dismissIfNeeded() {
            guard let presentedController else { return }
            presentedController.dismiss(animated: true)
            self.presentedController = nil
        }

        func adaptivePresentationStyle(
            for controller: UIPresentationController
        ) -> UIModalPresentationStyle {
            .none
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            presentedController = nil
            if isPresented.wrappedValue {
                isPresented.wrappedValue = false
            }
        }
    }
}

private extension UIView {
    var nearestPresentingViewController: UIViewController? {
        sequence(first: next, next: { $0?.next })
            .compactMap { $0 as? UIViewController }
            .first
    }
}
