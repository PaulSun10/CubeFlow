import SwiftUI

enum CubingChinaTicketPresentation {
    static func commonUnavailableReason(_ tickets: [CubingChinaTicket]) -> String? {
        guard let reason = tickets.first?.unavailableReason, !reason.isEmpty,
              tickets.allSatisfy({ $0.unavailableReason == reason }) else { return nil }
        return reason
    }

    static func validDate(_ text: String, language: String, timeZone: TimeZone = .current) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = timeZone
        parser.dateFormat = "yyyy-MM-dd"
        parser.isLenient = false
        guard let date = parser.date(from: text), parser.string(from: date) == text else { return text }
        // Ticket validity is a calendar date, not a UTC instant.
        let formatter = DateFormatter()
        formatter.calendar = parser.calendar
        formatter.locale = Locale(identifier: language)
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

struct CubingChinaTicketsContent: View {
    let tickets: [CubingChinaTicket]?
    let isLoading: Bool
    let slug: String
    let language: String
    private func t(_ key: String) -> String { PublishedCompetitionStrings.text(key, language) }
    private var commonReason: String? { CubingChinaTicketPresentation.commonUnavailableReason(tickets ?? []) }
    private func status(_ reason: String) -> String {
        appLocalizedString("tickets.status." + reason, languageCode: language,
            defaultValue: t("tickets.unavailable"), tableName: "CompetitionPublished")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoading, tickets == nil { ProgressView() }
            else if tickets?.isEmpty != false { Text(t("tickets.unavailable")).foregroundStyle(.secondary) }
            if let reason = commonReason {
                Text(status(reason)).font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("competition-ticket-sales-state")
            }
            officialWebsiteAction
            ForEach(tickets ?? []) { ticket in
                VStack(alignment: .leading, spacing: 12) {
                    Text(ticket.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text((Double(ticket.payableFeeCents ?? ticket.feeCents) / 100).formatted(.currency(code: "CNY")))
                            .font(.title2.weight(.bold)).monospacedDigit()
                        if let fee = ticket.payableFeeCents, fee < ticket.feeCents {
                            Text((Double(ticket.feeCents) / 100).formatted(.currency(code: "CNY")))
                                .font(.caption).strikethrough().foregroundStyle(.secondary)
                        }
                    }
                    if !ticket.validDates.isEmpty {
                        Text(ticket.validDates.map { CubingChinaTicketPresentation.validDate($0, language: language) }
                            .joined(separator: " \u{b7} "))
                            .font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    }
                    if let description = ticket.description, !description.isEmpty {
                        Text(CubingChinaSemanticHTML.text(description)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let limit = ticket.purchaseLimit { Text(t("tickets.limit") + " \(limit)").font(.caption) }
                    if ticket.competitorsOnly { Text(t("tickets.competitors_only")).font(.caption) }
                    if commonReason == nil, let reason = ticket.unavailableReason {
                        Text(status(reason)).font(.subheadline.weight(.semibold))
                    }
                    if ticket.stock != nil || ticket.saleStart != nil || ticket.saleEnd != nil {
                        DisclosureGroup(t("tickets.details")) {
                            VStack(alignment: .leading, spacing: 8) {
                                if let stock = ticket.stock { Text(t("tickets.stock") + " \(stock)") }
                                if let start = ticket.saleStart, let date = CubingChinaDetailAdapter.date(start) {
                                    Text(t("tickets.sale_start") + " " + date.formatted(date: .abbreviated, time: .shortened))
                                }
                                if let end = ticket.saleEnd, let date = CubingChinaDetailAdapter.date(end) {
                                    Text(t("tickets.sale_end") + " " + date.formatted(date: .abbreviated, time: .shortened))
                                }
                            }.font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        }.font(.subheadline)
                            .tint(CubingChinaNavigationColors.Section.spectatorTicket.foreground)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var officialWebsiteAction: some View {
        if let url = CubingChinaTicket.website(slug: slug) {
            Link(destination: url) {
                HStack {
                    Text(t("tickets.website")).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right").accessibilityHidden(true)
                }.frame(maxWidth: .infinity, minHeight: 44)
            }
            .font(.headline).buttonStyle(.bordered)
            .tint(CubingChinaNavigationColors.Section.spectatorTicket.foreground)
            .accessibilityIdentifier("competition-ticket-website")
        }
    }
}
