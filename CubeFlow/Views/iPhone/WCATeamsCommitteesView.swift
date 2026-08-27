import SwiftUI
import Combine

@MainActor
final class WCATeamsCommitteesViewModel: ObservableObject {
    @Published private(set) var groups: [WCAOrganizationGroup] = []
    @Published private(set) var members: [WCAOrganizationMember] = []
    @Published var selectedGroupID: Int?
    @Published private(set) var isLoadingGroups = false
    @Published private(set) var isLoadingMembers = false
    @Published private(set) var errorMessage: String?

    private let initialGroupFriendlyID: String?
    private var hasLoaded = false

    init(initialGroupFriendlyID: String?) {
        self.initialGroupFriendlyID = initialGroupFriendlyID?.lowercased()
    }

    var selectedGroup: WCAOrganizationGroup? {
        groups.first { $0.id == selectedGroupID }
    }

    func load(forceRefresh: Bool = false) async {
        guard forceRefresh || !hasLoaded else { return }

        isLoadingGroups = true
        errorMessage = nil
        do {
            groups = try await WCATeamsCommitteesService.shared.groups(forceRefresh: forceRefresh)
            hasLoaded = true

            if selectedGroupID == nil || !groups.contains(where: { $0.id == selectedGroupID }) {
                selectedGroupID = groups.first(where: {
                    $0.friendlyID.lowercased() == initialGroupFriendlyID
                })?.id ?? groups.first?.id
            }

            if let selectedGroupID {
                await loadMembers(groupID: selectedGroupID, forceRefresh: forceRefresh)
            }
        } catch {
            errorMessage = appUserFacingErrorMessage(error, languageCode: currentAppLanguageCode())
        }
        isLoadingGroups = false
    }

    func selectGroup(_ id: Int) async {
        guard selectedGroupID != id || members.isEmpty else { return }
        selectedGroupID = id
        await loadMembers(groupID: id)
    }

    func refresh() async {
        await load(forceRefresh: true)
    }

    private func loadMembers(groupID: Int, forceRefresh: Bool = false) async {
        isLoadingMembers = true
        errorMessage = nil
        members = []

        do {
            let loadedMembers = try await WCATeamsCommitteesService.shared.members(
                groupID: groupID,
                forceRefresh: forceRefresh
            )
            guard selectedGroupID == groupID else { return }
            members = loadedMembers
        } catch {
            guard selectedGroupID == groupID else { return }
            errorMessage = appUserFacingErrorMessage(error, languageCode: currentAppLanguageCode())
        }
        if selectedGroupID == groupID {
            isLoadingMembers = false
        }
    }
}

struct WCATeamsCommitteesView: View {
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @StateObject private var viewModel: WCATeamsCommitteesViewModel

    init(initialGroupFriendlyID: String? = nil) {
        _viewModel = StateObject(
            wrappedValue: WCATeamsCommitteesViewModel(
                initialGroupFriendlyID: initialGroupFriendlyID
            )
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                introduction

                if viewModel.isLoadingGroups, viewModel.groups.isEmpty {
                    loadingView
                } else if viewModel.groups.isEmpty {
                    errorView
                } else {
                    groupPicker
                    selectedGroupContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .scrollAwareNavigationTitle(localized("wca.teams_committees.title", "WCA Teams and Committees"))
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            WCAOrganizationPageTitle(
                title: localized("wca.teams_committees.title", "WCA Teams and Committees")
            )

            Text(localized(
                "wca.teams_committees.introduction",
                "The WCA's teams and committees are an integral part of the organization and perform the day-to-day tasks that are required to keep it functioning. These committees are made up of WCA community members, including WCA Delegates and competitors. Each team has a leader, whose role is to ensure the proper functioning of the team and guide other team members. When there are team or committee openings, information about how to apply is posted on the front page."
            ))
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .selectableContent()
        }
    }

    private var groupPicker: some View {
        Menu {
            ForEach(viewModel.groups) { group in
                Button {
                    Task {
                        await viewModel.selectGroup(group.id)
                    }
                } label: {
                    if group.id == viewModel.selectedGroupID {
                        Label(group.name, systemImage: "checkmark")
                    } else {
                        Text(group.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("wca.teams_committees.department", "Team or Committee"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(viewModel.selectedGroup?.name ?? "")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
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
        .accessibilityLabel(localized("wca.teams_committees.department", "Team or Committee"))
    }

    @ViewBuilder
    private var selectedGroupContent: some View {
        if let group = viewModel.selectedGroup {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.name)
                        .font(.system(size: 22, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .selectableContent()

                    if let description = group.description {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .selectableContent()
                    }

                    groupContact(group)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(localized("wca.teams_committees.members", "Members"))
                    .font(.system(size: 20, weight: .bold))

                if viewModel.isLoadingMembers {
                    loadingView
                } else if let errorMessage = viewModel.errorMessage {
                    errorView(message: errorMessage)
                } else if viewModel.members.isEmpty {
                    Text(localized("wca.teams_committees.no_members", "No members are currently listed."))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.members) { member in
                            memberDestination(member)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func memberDestination(_ member: WCAOrganizationMember) -> some View {
        if let wcaID = member.wcaID, !wcaID.isEmpty {
            NavigationLink {
                WCAProfileView(
                    wcaID: wcaID,
                    displayName: member.name,
                    avatarURL: member.avatarURL
                )
            } label: {
                memberRow(member, showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            memberRow(member, showsChevron: false)
        }
    }

    private func memberRow(_ member: WCAOrganizationMember, showsChevron: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            memberAvatar(member)

            VStack(alignment: .leading, spacing: 6) {
                Text(member.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let wcaID = member.wcaID, !wcaID.isEmpty {
                    Text(wcaID)
                        .font(.system(size: 13, weight: .regular).italic())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .selectableContent()
                }

                HStack(spacing: 5) {
                    if let countryISO2 = member.countryISO2 {
                        Text(flagEmoji(for: countryISO2))
                    }
                    if let countryName = member.countryName {
                        Text(countryName)
                    }
                    if member.countryName != nil {
                        Text("·")
                    }
                    Text(memberRoleTitle(member.status))
                }
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(minHeight: 104)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func memberAvatar(_ member: WCAOrganizationMember) -> some View {
        if let avatarURLString = member.avatarURL,
           let avatarURL = URL(string: avatarURLString) {
            AsyncImage(url: avatarURL) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                        .contentImageActions(source: .remote(avatarURL))
                } else {
                    memberAvatarPlaceholder
                }
            }
            .frame(width: 72, height: 72)
            .clipped()
        } else {
            memberAvatarPlaceholder
                .frame(width: 72, height: 72)
                .background(Color(uiColor: .tertiarySystemFill))
        }
    }

    private var memberAvatarPlaceholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 27, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(localized("wca.teams_committees.loading", "Loading…"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var errorView: some View {
        errorView(
            message: viewModel.errorMessage
                ?? localized("wca.teams_committees.error", "WCA Teams and Committees is currently unavailable.")
        )
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(localized("wca.teams_committees.unavailable", "Unable to Load"))
                .font(.system(size: 17, weight: .semibold))

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(localized("wca.teams_committees.retry", "Try Again")) {
                Task {
                    await viewModel.refresh()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func memberRoleTitle(_ status: String) -> String {
        switch status.lowercased() {
        case "leader":
            return localized("wca.teams_committees.role.leader", "Leader")
        case "senior_member":
            return localized("wca.teams_committees.role.senior_member", "Senior Member")
        case "member":
            return localized("wca.teams_committees.role.member", "Member")
        default:
            return status
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    @ViewBuilder
    private func groupContact(_ group: WCAOrganizationGroup) -> some View {
        switch group.preferredContactMode {
        case .email:
            if let email = group.email,
               let emailURL = URL(string: "mailto:\(email)") {
                Link(destination: emailURL) {
                    Label(email, systemImage: "envelope.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tint)
                }
            }
        case .contactForm:
            VStack(alignment: .leading, spacing: 8) {
                informationNotice(
                    localized(
                        "wca.teams_committees.contact_form_notice",
                        "This team or committee prefers to be contacted through the WCA contact form."
                    )
                )
                if let contactURL = URL(
                    string: "https://www.worldcubeassociation.org/contact?contactRecipient=\(group.friendlyID)"
                ) {
                    Link(destination: contactURL) {
                        HStack(spacing: 5) {
                            Text(localized("wca.teams_committees.contact_form_action", "Open WCA Contact Form"))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tint)
                    }
                }
            }
        case .noContact:
            informationNotice(
                localized(
                    "wca.teams_committees.no_contact_notice",
                    "The contact details of this team or committee are not publicly available."
                )
            )
        }
    }

    private func informationNotice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .tertiarySystemFill),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
    }

    private func localized(_ key: String, _ fallback: String) -> String {
        appLocalizedString(key, languageCode: appLanguage, defaultValue: fallback)
    }
}
