import SwiftUI
import EventKit

struct CompetitionCalendarImport: Identifiable {
    let id = UUID()
    let fileURL: URL
    let events: [CompetitionCalendarEvent]
}

struct CompetitionCalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let url: URL?
}

enum CompetitionCalendarParser {
    enum ParseError: Error {
        case invalidCalendar
        case noEvents
    }

    static func parse(_ data: Data) throws -> [CompetitionCalendarEvent] {
        guard let text = String(data: data, encoding: .utf8), text.contains("BEGIN:VCALENDAR") else {
            throw ParseError.invalidCalendar
        }

        let lines = unfoldedLines(text)
        var eventProperties: [[String: (parameters: [String: String], value: String)]] = []
        var current: [String: (parameters: [String: String], value: String)]?

        for line in lines {
            if line == "BEGIN:VEVENT" {
                current = [:]
                continue
            }
            if line == "END:VEVENT" {
                if let current { eventProperties.append(current) }
                current = nil
                continue
            }
            guard current != nil,
                  let colon = line.firstIndex(of: ":") else { continue }

            let property = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            let components = property.split(separator: ";", omittingEmptySubsequences: false)
            guard let rawName = components.first else { continue }
            let name = rawName.uppercased()
            var parameters: [String: String] = [:]
            for component in components.dropFirst() {
                let pair = component.split(separator: "=", maxSplits: 1).map(String.init)
                if pair.count == 2 { parameters[pair[0].uppercased()] = pair[1] }
            }
            current?[name] = (parameters, value)
        }

        let events = eventProperties.compactMap { properties -> CompetitionCalendarEvent? in
            guard let startProperty = properties["DTSTART"],
                  let start = parsedDate(startProperty.value, parameters: startProperty.parameters) else {
                return nil
            }
            let isAllDay = startProperty.parameters["VALUE"]?.uppercased() == "DATE"
                || startProperty.value.count == 8
            let end = properties["DTEND"].flatMap {
                parsedDate($0.value, parameters: $0.parameters)
            } ?? Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
            let uid = properties["UID"].map { decodedText($0.value) } ?? UUID().uuidString
            let title = properties["SUMMARY"].map { decodedText($0.value) } ?? "Event"

            return CompetitionCalendarEvent(
                id: uid,
                title: title,
                startDate: start,
                endDate: end,
                isAllDay: isAllDay,
                location: properties["LOCATION"].map { decodedText($0.value) },
                notes: properties["DESCRIPTION"].map { decodedText($0.value) },
                url: properties["URL"].flatMap { URL(string: decodedText($0.value)) }
            )
        }

        guard !events.isEmpty else { throw ParseError.noEvents }
        return events.sorted {
            if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private static func unfoldedLines(_ text: String) -> [String] {
        let rawLines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var lines: [String] = []
        for line in rawLines {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += line.dropFirst()
            } else {
                lines.append(line)
            }
        }
        return lines
    }

    private static func parsedDate(_ value: String, parameters: [String: String]) -> Date? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let isUTC = normalized.hasSuffix("Z")
        let dateValue = isUTC ? String(normalized.dropLast()) : normalized
        let timeZone = isUTC
            ? TimeZone(secondsFromGMT: 0)
            : parameters["TZID"].flatMap(TimeZone.init(identifier:)) ?? .current

        let formats = dateValue.count == 8
            ? ["yyyyMMdd"]
            : ["yyyyMMdd'T'HHmmss", "yyyyMMdd'T'HHmm"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: dateValue) { return date }
        }
        return nil
    }

    private static func decodedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

private enum CompetitionCalendarFontWeight: String, CaseIterable, Identifiable {
    case regular
    case medium
    case semibold
    case bold

    var id: String { rawValue }

    var fontWeight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

private struct CompetitionCalendarLayoutValues {
    var pageHorizontalPadding: CGFloat = 16
    var pageTopPadding: CGFloat = 26
    var pageBottomPadding: CGFloat = 32
    var sectionBottomPadding: CGFloat = 24
    var dateToFirstEventPadding: CGFloat = 10
    var eventSpacing: CGFloat = 10

    var dateFontSize: CGFloat = 16
    var dateFontWeight: CompetitionCalendarFontWeight = .semibold
    var dateTracking: CGFloat = 0.4
    var dateHorizontalPadding: CGFloat = 0
    var dateVerticalPadding: CGFloat = 8

    var eventLeadingPadding: CGFloat = 6
    var eventContentSpacing: CGFloat = 8
    var eventMinimumHeight: CGFloat = 50
    var eventTitleFontSize: CGFloat = 17
    var eventTitleFontWeight: CompetitionCalendarFontWeight = .semibold
    var eventTitleMinimumScale: CGFloat = 0.9
    var eventTitleToTimeSpacing: CGFloat = 6

    var eventBarWidth: CGFloat = 4
    var eventBarHeight: CGFloat = 38
    var eventBarTopPadding: CGFloat = 2

    var timeStackSpacing: CGFloat = 2
    var timeFontSize: CGFloat = 16
    var timeFontWeight: CompetitionCalendarFontWeight = .regular
    var dayPeriodFontSize: CGFloat = 16
    var dayPeriodFontWeight: CompetitionCalendarFontWeight = .regular
    var timeDayPeriodSpacing: CGFloat = 0
}

struct CompetitionCalendarImportSheet: View {
    let calendarImport: CompetitionCalendarImport
    let appLanguage: String

    @Environment(\.dismiss) private var dismiss
    @State private var isAddingAll = false
    @State private var errorMessage: String?
    @State private var showsShareSheet = false
    @State private var selectedEvent: CompetitionCalendarEvent?
    @State private var layout = CompetitionCalendarLayoutValues()
#if DEBUG
    @State private var showsLayoutDebugger = false
#endif

    private var groupedEvents: [(date: Date, events: [CompetitionCalendarEvent])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: calendarImport.events) {
            calendar.startOfDay(for: $0.startDate)
        }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    private var navigationTitle: String {
        String(
            format: appLocalizedString(
                "competitions.detail.events_count_format",
                languageCode: appLanguage,
                defaultValue: "%d events"
            ),
            calendarImport.events.count
        )
        .localizedCapitalized
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedEvents, id: \.date) { group in
                        Section {
                            LazyVStack(alignment: .leading, spacing: layout.eventSpacing) {
                                ForEach(group.events) { event in
                                    calendarEventRow(event)
                                }
                            }
                            .padding(.top, layout.dateToFirstEventPadding)
                            .padding(.bottom, layout.sectionBottomPadding)
                        } header: {
                            calendarDayHeader(group.date)
                        }
                    }
                }
                .padding(.horizontal, layout.pageHorizontalPadding)
                .padding(.top, layout.pageTopPadding)
                .padding(.bottom, layout.pageBottomPadding)
            }
            .background(calendarBackground)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .background(
                CompetitionCalendarToolbarConfigurator(
                    isAddingAll: isAddingAll,
                    doneLabel: appLocalizedString("common.done", languageCode: appLanguage, defaultValue: "Done"),
                    addAllLabel: appLocalizedString(
                        "competitions.calendar.add_all",
                        languageCode: appLanguage,
                        defaultValue: "Add All"
                    ),
                    dismissAction: { dismiss() },
                    shareAction: { showsShareSheet = true },
                    addAllAction: addAllEvents,
                    debugAction: {
#if DEBUG
                        showsLayoutDebugger = true
#endif
                    }
                )
            )
            .background(eventDetailNavigationLink)
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showsShareSheet) {
            CompetitionCalendarShareSheet(activityItems: [calendarImport.fileURL])
        }
#if DEBUG
        .sheet(isPresented: $showsLayoutDebugger) {
            CompetitionCalendarLayoutDebugger(values: $layout)
        }
#endif
        .alert(
            appLocalizedString(
                "competitions.calendar.title",
                languageCode: appLanguage,
                defaultValue: "Calendar"
            ),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(appLocalizedString("common.done", languageCode: appLanguage, defaultValue: "Done")) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func calendarDayHeader(_ date: Date) -> some View {
        Text(calendarDayTitle(date))
            .font(.system(size: layout.dateFontSize, weight: layout.dateFontWeight.fontWeight))
            .tracking(layout.dateTracking)
            .foregroundStyle(Calendar.current.isDateInToday(date) ? Color.red : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, layout.dateHorizontalPadding)
            .padding(.vertical, layout.dateVerticalPadding)
            .background(calendarBackground)
    }

    private var calendarBackground: Color {
        Color(uiColor: .systemBackground)
    }

    private func calendarDayTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLocale(for: appLanguage)
        formatter.setLocalizedDateFormatFromTemplate("EEEE MMM d")
        return formatter.string(from: date).uppercased(with: formatter.locale)
    }

    private func calendarEventRow(_ event: CompetitionCalendarEvent) -> some View {
        Button {
            selectedEvent = event
        } label: {
            HStack(alignment: .top, spacing: layout.eventContentSpacing) {
                Capsule(style: .continuous)
                    .fill(Color.blue)
                    .frame(width: layout.eventBarWidth, height: layout.eventBarHeight)
                    .padding(.top, layout.eventBarTopPadding)

                Text(event.title)
                    .font(.system(size: layout.eventTitleFontSize, weight: layout.eventTitleFontWeight.fontWeight))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(layout.eventTitleMinimumScale)

                Spacer(minLength: layout.eventTitleToTimeSpacing)

                VStack(alignment: .trailing, spacing: layout.timeStackSpacing) {
                    calendarTimeLabel(for: event.startDate, color: .primary)

                    if eventEndTimeText(event) != nil {
                        calendarTimeLabel(for: event.endDate, color: .secondary)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minHeight: layout.eventMinimumHeight, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, layout.eventLeadingPadding)
        .accessibilityElement(children: .combine)
    }

    private func calendarTimeLabel(for date: Date, color: Color) -> some View {
        let parts = calendarTimeParts(for: date)
        return HStack(alignment: .firstTextBaseline, spacing: layout.timeDayPeriodSpacing) {
            Text(parts.time)
                .font(.system(size: layout.timeFontSize, weight: layout.timeFontWeight.fontWeight))
                .monospacedDigit()

            if let dayPeriod = parts.dayPeriod {
                Text(dayPeriod.lowercased())
                    .font(
                        .system(size: layout.dayPeriodFontSize, weight: layout.dayPeriodFontWeight.fontWeight)
                            .smallCaps()
                    )
            }
        }
        .foregroundStyle(color)
    }

    private var eventDetailNavigationLink: some View {
        NavigationLink(
            destination: Group {
                if let selectedEvent {
                    CompetitionCalendarEventDetailView(
                        event: selectedEvent,
                        appLanguage: appLanguage
                    )
                }
            },
            isActive: Binding(
                get: { selectedEvent != nil },
                set: { if !$0 { selectedEvent = nil } }
            )
        ) {
            EmptyView()
        }
        .hidden()
    }

    private func calendarTimeParts(for date: Date) -> (time: String, dayPeriod: String?) {
        let fullTime = calendarTimeFormatter.string(from: date)
        let periodFormatter = DateFormatter()
        periodFormatter.locale = appLocale(for: appLanguage)
        periodFormatter.dateFormat = "a"
        let period = periodFormatter.string(from: date).uppercased()
        guard period == "AM" || period == "PM",
              let range = fullTime.range(of: period, options: [.caseInsensitive, .backwards]) else {
            return (fullTime, nil)
        }

        let time = fullTime.replacingCharacters(in: range, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (time, period)
    }

    private func eventStartTimeText(_ event: CompetitionCalendarEvent) -> String {
        if event.isAllDay {
            return appLocalizedString(
                "competitions.calendar.all_day",
                languageCode: appLanguage,
                defaultValue: "All-day"
            )
        }
        return calendarTimeFormatter.string(from: event.startDate)
    }

    private func eventEndTimeText(_ event: CompetitionCalendarEvent) -> String? {
        guard !event.isAllDay, event.endDate > event.startDate else { return nil }
        return calendarTimeFormatter.string(from: event.endDate)
    }

    private var calendarTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = appLocale(for: appLanguage)
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }

    private func addAllEvents() {
        guard !isAddingAll else { return }
        isAddingAll = true

        Task { @MainActor in
            defer { isAddingAll = false }
            let eventStore = EKEventStore()
            do {
                guard try await requestCalendarWriteAccess(eventStore) else {
                    errorMessage = appLocalizedString(
                        "competitions.calendar.permission_denied",
                        languageCode: appLanguage,
                        defaultValue: "Calendar access was not granted."
                    )
                    return
                }
                guard let calendar = eventStore.defaultCalendarForNewEvents else {
                    errorMessage = appLocalizedString(
                        "competitions.calendar.permission_denied",
                        languageCode: appLanguage,
                        defaultValue: "Calendar access was not granted."
                    )
                    return
                }

                for source in calendarImport.events {
                    let event = EKEvent(eventStore: eventStore)
                    event.calendar = calendar
                    event.title = source.title
                    event.startDate = source.startDate
                    event.endDate = source.endDate
                    event.isAllDay = source.isAllDay
                    event.location = source.location
                    event.notes = source.notes
                    event.url = source.url
                    try eventStore.save(event, span: .thisEvent, commit: false)
                }
                try eventStore.commit()
                dismiss()
            } catch {
                errorMessage = String(
                    format: appLocalizedString(
                        "competitions.calendar.add_error_format",
                        languageCode: appLanguage,
                        defaultValue: "Could not add these events: %@"
                    ),
                    appUserFacingErrorMessage(error, languageCode: appLanguage)
                )
            }
        }
    }

    private func requestCalendarWriteAccess(_ eventStore: EKEventStore) async throws -> Bool {
        if #available(iOS 17.0, *) {
            return try await eventStore.requestWriteOnlyAccessToEvents()
        }
        return try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}

private struct CompetitionCalendarEventDetailView: View {
    let event: CompetitionCalendarEvent
    let appLanguage: String

    @Environment(\.dismiss) private var dismiss
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                eventHeader

                if let location = nonempty(event.location) {
                    detailRow(systemImage: "location.fill", text: location)
                }

                if let notes = nonempty(event.notes) {
                    detailRow(systemImage: "note.text", text: notes)
                }

                if let url = event.url {
                    Link(destination: url) {
                        detailRow(systemImage: "link", text: url.absoluteString)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 120)
        }
        .background(Color(uiColor: .systemBackground))
        .scrollAwareNavigationTitle(event.title)
        .safeAreaInset(edge: .bottom) {
            Button(action: addEvent) {
                if isAdding {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(
                        appLocalizedString(
                            "competitions.calendar.add_event",
                            languageCode: appLanguage,
                            defaultValue: "Add to Calendar"
                        )
                    )
                }
            }
            .compatibleProminentButtonFromIOS16(tint: .blue)
            .disabled(isAdding)
            .padding(.vertical, 12)
        }
        .alert(
            appLocalizedString("competitions.calendar.title", languageCode: appLanguage, defaultValue: "Calendar"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(appLocalizedString("common.done", languageCode: appLanguage, defaultValue: "Done")) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var eventHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule(style: .continuous)
                .fill(Color.blue)
                .frame(width: 5, height: 132)

            VStack(alignment: .leading, spacing: 8) {
                ScrollAwareContentTitle(title: event.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detailDateFormatter.string(from: event.startDate))
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)

                Text(localTimeRange)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)

                if !event.isAllDay {
                    Text("\(utcTimeRange) (UTC)")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func detailRow(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(text)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var localTimeRange: String {
        if event.isAllDay {
            return appLocalizedString("competitions.calendar.all_day", languageCode: appLanguage, defaultValue: "All-day")
        }
        return "\(localTimeFormatter.string(from: event.startDate))–\(localTimeFormatter.string(from: event.endDate))"
    }

    private var utcTimeRange: String {
        "\(utcTimeFormatter.string(from: event.startDate))–\(utcTimeFormatter.string(from: event.endDate))"
    }

    private var detailDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = appLocale(for: appLanguage)
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }

    private var localTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = appLocale(for: appLanguage)
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }

    private var utcTimeFormatter: DateFormatter {
        let formatter = localTimeFormatter
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func addEvent() {
        guard !isAdding else { return }
        isAdding = true

        Task { @MainActor in
            defer { isAdding = false }
            let eventStore = EKEventStore()
            do {
                let granted: Bool
                if #available(iOS 17.0, *) {
                    granted = try await eventStore.requestWriteOnlyAccessToEvents()
                } else {
                    granted = try await withCheckedThrowingContinuation { continuation in
                        eventStore.requestAccess(to: .event) { granted, error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: granted)
                            }
                        }
                    }
                }

                guard granted, let calendar = eventStore.defaultCalendarForNewEvents else {
                    errorMessage = appLocalizedString(
                        "competitions.calendar.permission_denied",
                        languageCode: appLanguage,
                        defaultValue: "Calendar access was not granted."
                    )
                    return
                }

                let newEvent = EKEvent(eventStore: eventStore)
                newEvent.calendar = calendar
                newEvent.title = event.title
                newEvent.startDate = event.startDate
                newEvent.endDate = event.endDate
                newEvent.isAllDay = event.isAllDay
                newEvent.location = event.location
                newEvent.notes = event.notes
                newEvent.url = event.url
                try eventStore.save(newEvent, span: .thisEvent)
                dismiss()
            } catch {
                errorMessage = String(
                    format: appLocalizedString(
                        "competitions.calendar.add_error_format",
                        languageCode: appLanguage,
                        defaultValue: "Could not add this event: %@"
                    ),
                    appUserFacingErrorMessage(error, languageCode: appLanguage)
                )
            }
        }
    }
}

#if DEBUG
private struct CompetitionCalendarLayoutDebugger: View {
    @Binding var values: CompetitionCalendarLayoutValues
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Page") {
                    slider("Horizontal Padding", value: $values.pageHorizontalPadding, range: 0...40)
                    slider("Top Padding", value: $values.pageTopPadding, range: 0...60)
                    slider("Bottom Padding", value: $values.pageBottomPadding, range: 0...80)
                    slider("Section Bottom", value: $values.sectionBottomPadding, range: 0...60)
                    slider("Date to First Event", value: $values.dateToFirstEventPadding, range: 0...40)
                    slider("Event Spacing", value: $values.eventSpacing, range: 0...40)
                }

                Section("Date Header") {
                    slider("Font Size", value: $values.dateFontSize, range: 10...30, step: 0.5)
                    weightPicker("Font Weight", selection: $values.dateFontWeight)
                    slider("Tracking", value: $values.dateTracking, range: -2...4, step: 0.1)
                    slider("Horizontal Padding", value: $values.dateHorizontalPadding, range: 0...40)
                    slider("Vertical Padding", value: $values.dateVerticalPadding, range: 0...30)
                }

                Section("Event Row") {
                    slider("Leading Padding", value: $values.eventLeadingPadding, range: 0...40)
                    slider("Content Spacing", value: $values.eventContentSpacing, range: 0...30)
                    slider("Minimum Height", value: $values.eventMinimumHeight, range: 30...100)
                    slider("Title Font Size", value: $values.eventTitleFontSize, range: 10...30, step: 0.5)
                    weightPicker("Title Font Weight", selection: $values.eventTitleFontWeight)
                    slider("Title Minimum Scale", value: $values.eventTitleMinimumScale, range: 0.5...1, step: 0.05)
                    slider("Title to Time", value: $values.eventTitleToTimeSpacing, range: 0...30)
                }

                Section("Blue Bar") {
                    slider("Width", value: $values.eventBarWidth, range: 1...16, step: 0.5)
                    slider("Height", value: $values.eventBarHeight, range: 10...80)
                    slider("Top Padding", value: $values.eventBarTopPadding, range: 0...30)
                }

                Section("Time") {
                    slider("Line Spacing", value: $values.timeStackSpacing, range: 0...20)
                    slider("Time Font Size", value: $values.timeFontSize, range: 10...30, step: 0.5)
                    weightPicker("Time Font Weight", selection: $values.timeFontWeight)
                    slider("AM/PM Font Size", value: $values.dayPeriodFontSize, range: 8...30, step: 0.5)
                    weightPicker("AM/PM Font Weight", selection: $values.dayPeriodFontWeight)
                    slider("Time to AM/PM", value: $values.timeDayPeriodSpacing, range: -4...10, step: 0.5)
                }
            }
            .navigationTitle("Calendar Layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        values = CompetitionCalendarLayoutValues()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func slider(
        _ title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: step < 1 ? "%.1f" : "%.0f", Double(value.wrappedValue)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: value, in: range, step: step)
        }
    }

    private func weightPicker(
        _ title: String,
        selection: Binding<CompetitionCalendarFontWeight>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(CompetitionCalendarFontWeight.allCases) { weight in
                Text(weight.rawValue.capitalized).tag(weight)
            }
        }
    }
}
#endif

private struct CompetitionCalendarToolbarConfigurator: UIViewControllerRepresentable {
    let isAddingAll: Bool
    let doneLabel: String
    let addAllLabel: String
    let dismissAction: () -> Void
    let shareAction: () -> Void
    let addAllAction: () -> Void
    let debugAction: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        context.coordinator.configuration = self
        DispatchQueue.main.async {
            context.coordinator.apply(to: viewController)
        }
    }

    static func dismantleUIViewController(_ viewController: UIViewController, coordinator: Coordinator) {
        coordinator.clear(from: viewController)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(configuration: self)
    }

    final class Coordinator: NSObject {
        private struct ToolbarState: Equatable {
            let isAddingAll: Bool
            let doneLabel: String
            let addAllLabel: String
        }

        var configuration: CompetitionCalendarToolbarConfigurator
        private var appliedState: ToolbarState?

        init(configuration: CompetitionCalendarToolbarConfigurator) {
            self.configuration = configuration
        }

        func apply(to viewController: UIViewController) {
            guard let navigationItem = navigationItem(for: viewController) else { return }
            configureNavigationBar(for: viewController)

            let state = ToolbarState(
                isAddingAll: configuration.isAddingAll,
                doneLabel: configuration.doneLabel,
                addAllLabel: configuration.addAllLabel
            )
            guard appliedState != state else { return }
            appliedState = state

            let doneItem = UIBarButtonItem(
                image: UIImage(systemName: "checkmark"),
                style: prominentStyle,
                target: self,
                action: #selector(doneTapped)
            )
            doneItem.tintColor = .systemBlue
            doneItem.accessibilityLabel = configuration.doneLabel

            let shareItem = UIBarButtonItem(
                image: UIImage(systemName: "square.and.arrow.up"),
                style: .plain,
                target: self,
                action: #selector(shareTapped)
            )
            shareItem.tintColor = .label
            shareItem.accessibilityLabel = "Share"

            let addAllItem = UIBarButtonItem(
                title: configuration.addAllLabel,
                style: prominentStyle,
                target: self,
                action: #selector(addAllTapped)
            )
            addAllItem.tintColor = .systemBlue
            addAllItem.isEnabled = !configuration.isAddingAll

            var leftItems = [doneItem, shareItem]
#if DEBUG
            let debugItem = UIBarButtonItem(
                image: UIImage(systemName: "slider.horizontal.3"),
                style: .plain,
                target: self,
                action: #selector(debugTapped)
            )
            debugItem.tintColor = .systemOrange
            debugItem.accessibilityLabel = "Calendar layout debugger"
            leftItems.append(debugItem)
#endif

            navigationItem.setLeftBarButtonItems(leftItems, animated: false)
            navigationItem.setRightBarButtonItems([addAllItem], animated: false)
        }

        func clear(from viewController: UIViewController) {
            appliedState = nil
            guard let navigationItem = navigationItem(for: viewController) else { return }
            navigationItem.setLeftBarButtonItems(nil, animated: false)
            navigationItem.setRightBarButtonItems(nil, animated: false)
        }

        private var prominentStyle: UIBarButtonItem.Style {
            if #available(iOS 26.0, *) {
                return .prominent
            }
            return .done
        }

        private func navigationItem(for viewController: UIViewController) -> UINavigationItem? {
            if let navigationController = navigationController(for: viewController) {
                return navigationController.topViewController?.navigationItem
            }
            return viewController.parent?.navigationItem
        }

        private func navigationController(for viewController: UIViewController) -> UINavigationController? {
            if let navigationController = viewController.navigationController {
                return navigationController
            }
            if let navigationController = viewController.parent?.navigationController {
                return navigationController
            }
            var parent = viewController.parent
            while let current = parent {
                if let navigationController = current as? UINavigationController {
                    return navigationController
                }
                if let navigationController = current.navigationController {
                    return navigationController
                }
                parent = current.parent
            }
            return nil
        }

        private func configureNavigationBar(for viewController: UIViewController) {
            guard let navigationBar = navigationController(for: viewController)?.navigationBar else { return }

            let standardAppearance = navigationBar.standardAppearance.copy()
            standardAppearance.shadowColor = .clear
            standardAppearance.shadowImage = UIImage()
            navigationBar.standardAppearance = standardAppearance

            let scrollEdgeAppearance = navigationBar.scrollEdgeAppearance?.copy()
                ?? standardAppearance.copy()
            scrollEdgeAppearance.shadowColor = .clear
            scrollEdgeAppearance.shadowImage = UIImage()
            navigationBar.scrollEdgeAppearance = scrollEdgeAppearance
        }

        @objc private func doneTapped() {
            configuration.dismissAction()
        }

        @objc private func shareTapped() {
            configuration.shareAction()
        }

        @objc private func addAllTapped() {
            configuration.addAllAction()
        }

#if DEBUG
        @objc private func debugTapped() {
            configuration.debugAction()
        }
#endif
    }
}

private struct CompetitionCalendarShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
