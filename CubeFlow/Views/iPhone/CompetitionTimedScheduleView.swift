import SwiftUI

/// A shared absolute-time grid for the restored regional schedule, not independent room lists.
struct CompetitionTimedScheduleView: View {
    let days: [CompetitionScheduleDay]
    let language: String
    @State private var selectedDay = ""
    @State private var initiallyPositionedDays: Set<String> = []
    @State private var selectedEntry: CompetitionScheduleEntry?
    private let header: CGFloat = 36
    private let scale: CGFloat = 1.4
    private let axis: CGFloat = 48

    private var day: CompetitionScheduleDay? {
        days.first { $0.id == selectedDay }
            ?? days.first { CompetitionScheduleClock(entries: $0.entries)?.isToday(at: Date(), timeZone: CubingChinaDetailAdapter.timeZone) == true }
            ?? days.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(days) { item in
                        Button {
                            selectedDay = item.id
                            // An explicit selection may position near now; periodic ticks never scroll.
                            initiallyPositionedDays.remove(item.id)
                        } label: {
                            Text(item.title).font(.subheadline.weight(day?.id == item.id ? .semibold : .regular))
                                .foregroundStyle(day?.id == item.id ? Color.accentColor : Color.secondary)
                                .padding(.vertical, 6)
                        }.buttonStyle(.plain)
                    }
                }
            }
            if let day, let clock = CompetitionScheduleClock(entries: day.entries) {
                grid(day, clock: clock).id(day.id)
            }
        }
        .sheet(item: $selectedEntry) { entry in
            CompatibleNavigationContainer {
                List {
                    Text(entry.title).font(.headline)
                    Text(entry.timeText)
                    if let venue = entry.venueName { Text(venue) }
                    if let round = entry.round { LabeledContentCompat(label: PublishedCompetitionStrings.text("round", language), value: round) }
                    if let limit = entry.timeLimit { LabeledContentCompat(label: appLocalizedString("competitions.schedule.time_limit", languageCode: language, defaultValue: "Time limit"), value: limit) }
                    if let cutoff = entry.cutoff { LabeledContentCompat(label: appLocalizedString("competitions.schedule.cutoff", languageCode: language, defaultValue: "Cutoff"), value: cutoff) }
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(PublishedCompetitionStrings.text("done", language)) { selectedEntry = nil } } }
            }
        }
    }

    private func grid(_ day: CompetitionScheduleDay, clock: CompetitionScheduleClock) -> some View {
        let rooms = day.venues.isEmpty ? [CompetitionScheduleVenue(id: "all", title: "", entries: day.entries)] : day.venues
        let roomWidth: CGFloat = 174
        let width = axis + CGFloat(rooms.count) * roomWidth
        let height = header + CGFloat(clock.durationMinutes) * scale
        return ScrollViewReader { reader in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    Color(uiColor: .systemBackground)
                    ForEach(Array(stride(from: 0, through: Int(clock.durationMinutes), by: 30)), id: \.self) { minute in
                        let y = header + CGFloat(minute) * scale
                        Rectangle().fill(Color.secondary.opacity(0.16)).frame(width: width - axis, height: 0.5).offset(x: axis, y: y)
                        Text(time(clock.start.addingTimeInterval(Double(minute) * 60)))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: axis - 5, alignment: .trailing).offset(y: y - 6)
                    }
                    ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                        Text(room.title).font(.caption.weight(.semibold)).lineLimit(1)
                            .frame(width: roomWidth - 8, height: header).offset(x: axis + CGFloat(index) * roomWidth + 4)
                        ForEach(CompetitionScheduleLane.placements(room.entries)) { placement in
                            if let start = placement.entry.startTime, let end = placement.entry.endTime {
                                let laneWidth = roomWidth / CGFloat(placement.count)
                                let blockHeight = max(CGFloat(end.timeIntervalSince(start) / 60) * scale - 2, 8)
                                Button { selectedEntry = placement.entry } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(placement.entry.timeText).font(.system(size: 9).monospacedDigit()).lineLimit(1)
                                        Text(placement.entry.title).font(.system(size: 11, weight: .medium)).lineLimit(3)
                                    }
                                    .padding(4).frame(width: laneWidth - 4, height: blockHeight, alignment: .topLeading)
                                    .foregroundStyle(.primary)
                                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                    .clipped()
                                }.buttonStyle(.plain)
                                    .offset(x: axis + CGFloat(index) * roomWidth + CGFloat(placement.lane) * laneWidth + 2,
                                        y: header + CGFloat(start.timeIntervalSince(clock.start) / 60) * scale)
                            }
                        }
                    }
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        if clock.isToday(at: context.date, timeZone: CubingChinaDetailAdapter.timeZone),
                           let y = clock.y(at: context.date, headerHeight: Double(header), pointsPerMinute: Double(scale)) {
                            HStack(spacing: 4) {
                                Text(PublishedCompetitionStrings.text("now", language)).font(.caption2.weight(.semibold)).frame(width: axis - 4)
                                Rectangle().frame(height: 1)
                            }
                            .foregroundStyle(.red).frame(width: width).offset(y: CGFloat(y))
                            .allowsHitTesting(false)
                        }
                    }
                    if let y = clock.y(at: Date(), headerHeight: Double(header), pointsPerMinute: Double(scale)) {
                        // Give the scroll anchor a real layout position, not only a visual offset.
                        VStack(spacing: 0) {
                            Color.clear.frame(width: 1, height: CGFloat(y))
                            Color.clear.frame(width: 1, height: 1).id("schedule-now")
                        }
                        .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .frame(width: width, height: height)
            }
            .frame(height: min(height, 460))
            .task(id: day.id) {
                await Task.yield()
                guard !Task.isCancelled else { return }
                guard !initiallyPositionedDays.contains(day.id),
                      clock.isToday(at: Date(), timeZone: CubingChinaDetailAdapter.timeZone), clock.offsetMinutes(at: Date()) != nil else { return }
                initiallyPositionedDays.insert(day.id)
                reader.scrollTo("schedule-now", anchor: .center)
            }
        }
    }
    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLocale(for: language)
        formatter.timeZone = CubingChinaDetailAdapter.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct LabeledContentCompat: View {
    let label: String
    let value: String
    var body: some View { HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value) } }
}
