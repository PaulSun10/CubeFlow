import SwiftUI

enum CubingChinaEventDisplay {
    static func name(_ event: String, language: String) -> String {
        if event == "smart" { return PublishedCompetitionStrings.text("live.smart_cube", language) }
        return CompetitionEventPresentation.normalizedName(for: event,
            fallback: CompetitionEventPresentation.localizedFullName(for: event, languageCode: language), languageCode: language)
    }
}

/// Bluetooth's standard mark, independent of SF Symbols availability on iOS 15.
struct CompetitionBluetoothSymbol: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { .init(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        path.move(to: point(0.08, 0.25)); path.addLine(to: point(0.92, 0.75))
        path.addLine(to: point(0.42, 1)); path.addLine(to: point(0.42, 0))
        path.addLine(to: point(0.92, 0.25)); path.addLine(to: point(0.08, 0.75))
        return path
    }
}

struct CubingChinaEventIcon: View {
    let event: String
    let language: String
    var size: CGFloat = 18
    var body: some View {
        Group {
            if event == "smart" {
                CompetitionBluetoothSymbol().stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.6, height: size)
            } else if let glyph = CompetitionEventIconFont.glyph(for: event) {
                let _ = CompetitionEventIconFont.ensureRegistered()
                Text(glyph).font(.custom(CompetitionEventIconFont.fontName, fixedSize: size))
                    .fixedSize()
                    .offset(y: PublishedEventSelectorStyle.inkOffset(glyph, size: size).height)
                    .frame(height: size)
            } else {
                CompetitionLiveEventIconView(eventID: event, languageCode: language, isReady: true, color: .primary, size: size)
            }
        }.accessibilityHidden(true).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
    }
}

struct CubingChinaResultsHeading: View {
    let round: CubingChinaLiveRound
    let rounds: [CubingChinaLiveRound]
    let language: String
    var category: String? = nil
    @ScaledMetric(relativeTo: .subheadline) private var titleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .subheadline) private var iconSize: CGFloat = 18
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            CubingChinaEventIcon(event: round.eventId, language: language, size: iconSize)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.center] + UIFont.systemFont(ofSize: titleSize, weight: .semibold).capHeight / 2
                }
            Text(CubingChinaEventDisplay.name(round.eventId, language: language) + " - "
                + CubingChinaLivePresentation.roundName(round, rounds: rounds, language: language)
                + (category.map { " - " + $0 } ?? ""))
                .fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: titleSize, weight: .semibold)).accessibilityElement(children: .combine)
    }
}

struct CompetitionNativeActionCapsule: ViewModifier {
    let tint: Color
    var compact = true
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.font(.caption.weight(.semibold)).padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 4 : 0).frame(minHeight: compact ? 32 : 44)
                .foregroundStyle(tint).glassEffect(.regular.tint(tint.opacity(0.16)).interactive(), in: .capsule)
                .frame(minHeight: 44).contentShape(Rectangle())
        } else {
            content.font(.caption.weight(.semibold)).padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 4 : 0).frame(minHeight: compact ? 32 : 44)
                .foregroundStyle(tint).background(.regularMaterial, in: Capsule())
                .background(tint.opacity(0.10), in: Capsule())
                .frame(minHeight: 44).contentShape(Rectangle())
        }
    }
}

struct CompetitionLiveChatButton: View {
    let language: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "bubble.left.and.bubble.right").font(.body)
                .frame(width: 44, height: 44)
        }.buttonStyle(.plain).modifier(CompetitionNativeActionCapsule(tint: .primary, compact: false))
            .accessibilityLabel(appLocalizedString("competitions.detail.live.chat", languageCode: language))
            .accessibilityIdentifier("competition-live-chat-bottom")
    }
}

struct CompetitionLiveChatAccessory: View {
    let language: String
    let action: () -> Void
    var body: some View {
        HStack {
            Spacer()
            CompetitionLiveChatButton(language: language, action: action)
        }.padding(.horizontal, 16).padding(.vertical, 4)
    }
}

enum CubingChinaSumRankDisplay {
    static let eventOrder = ["333", "222", "444", "555", "666", "777", "333bf", "333fm", "333oh", "clock", "minx", "pyram", "skewb", "sq1", "444bf", "555bf", "333mbf", "smart"]
    static func filtered(_ entries: [CubingChinaLiveSumRank], gender: String) -> [CubingChinaLiveSumRank] {
        gender == "all" ? entries : entries.filter { $0.gender == gender }
    }
    static func events(_ entries: [CubingChinaLiveSumRank]) -> [String] {
        let keys = Set(entries.flatMap { $0.ranks.keys })
        return eventOrder.filter(keys.contains) + keys.subtracting(eventOrder).sorted()
    }
    // Website display ordinal: equal sum AND entered count share the preceding position.
    // This is not an API-authored overall rank; filtering happens before numbering.
    static func positions(_ entries: [CubingChinaLiveSumRank]) -> [Int] {
        var position = 0
        return entries.indices.map { index in
            if index == 0 || entries[index].sum != entries[index - 1].sum || entries[index].count != entries[index - 1].count { position = index + 1 }
            return position
        }
    }
}

enum CubingChinaPersonalShortcut {
    static func competitor(signedInWCAID: String?, results: [CubingChinaLiveResult], sums: [CubingChinaLiveSumRank]) -> CubingChinaLiveResult.Competitor? {
        (results.compactMap(\.competitor) + sums.map(\.competitor)).first {
            ($0.number ?? 0) > 0 && CompetitionPersonalIdentity.matches(signedInWCAID: signedInWCAID, competitorWCAID: $0.wcaId)
        }
    }
}

struct CompetitionSumRankColumns {
    static let inset: CGFloat = 10
    let position: CGFloat
    let name: CGFloat
    let region: CGFloat
    let sum: CGFloat
    let count: CGFloat
    init(width: CGFloat, scale: CGFloat) {
        let minimumSum = 54 * scale
        let available = max(width, Self.inset + (36 + 84 + 104 + 54) * scale)
        position = 36 * scale
        name = min(170 * scale, max(84 * scale, available * 0.34),
            available - Self.inset - position - 104 * scale - minimumSum)
        region = min(175 * scale, max(104 * scale,
            available - Self.inset - position - name - minimumSum))
        count = 44 * scale
        let firstGroup = Self.inset + position + name + region
        // The trailing inset belongs after all columns, not between Sum and Count.
        // Reveal Count only when its entire column fits; otherwise Sum ends at the viewport.
        sum = firstGroup + minimumSum + count <= available ? minimumSum : max(minimumSum, available - firstGroup)
    }
    var leadingWidth: CGFloat { position + name + region + Self.inset }
    var countOrigin: CGFloat { leadingWidth + sum }
}

struct CubingChinaSumRankTable: View {
    let entries: [CubingChinaLiveSumRank]
    let language: String
    var ownWCAID: String? = nil
    var genderSelection: Binding<String>? = nil
    var openCompetitor: ((CubingChinaLiveResult.Competitor) -> Void)? = nil
    @State private var localGender = "all"
    @State private var width: CGFloat = 0
    private var gender: Binding<String> { genderSelection ?? $localGender }
    @ScaledMetric(relativeTo: .body) private var eventWidth: CGFloat = 46
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    private func t(_ key: String) -> String { PublishedCompetitionStrings.text(key, language) }
    var body: some View {
        let values = CubingChinaSumRankDisplay.filtered(entries, gender: gender.wrappedValue)
        let events = CubingChinaSumRankDisplay.events(values)
        let positions = CubingChinaSumRankDisplay.positions(values)
        let columns = CompetitionSumRankColumns(width: width, scale: scale)
        VStack(alignment: .leading, spacing: 8) {
            Picker(t("live.gender"), selection: gender) {
                ForEach(["all", "male", "female"], id: \.self) { Text(t("live.gender." + $0)).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("competition-sum-ranks-gender")
            if values.isEmpty {
                Text(t("no_matches")).font(.subheadline).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        HStack(spacing: 0) {
                            header("#", width: columns.position)
                            header(t("competitor_name"), width: columns.name, leading: true)
                            header(t("live.region"), width: columns.region)
                            header(t("live.sum"), width: columns.sum)
                            header(t("live.entered_count"), width: columns.count)
                            ForEach(events, id: \.self) { event in
                                CubingChinaEventIcon(event: event, language: language).frame(width: eventWidth)
                                    .accessibilityHidden(false).accessibilityLabel(CubingChinaEventDisplay.name(event, language: language))
                            }
                        }.padding(.horizontal, CompetitionSumRankColumns.inset).padding(.vertical, 6)
                        Divider()
                        ForEach(Array(values.enumerated()), id: \.element.id) { index, entry in
                            Group {
                                if let openCompetitor {
                                    Button { openCompetitor(entry.competitor) } label: {
                                        row(entry, position: positions[index], events: events, columns: columns)
                                    }.buttonStyle(.plain)
                                        .accessibilityHint(appLocalizedString("competitions.detail.live.wca.all_results", languageCode: language))
                                } else { row(entry, position: positions[index], events: events, columns: columns) }
                            }.accessibilityElement(children: .combine)
                                .accessibilityIdentifier("competition-sum-ranks-row-\(entry.id.rawValue)")
                            Divider()
                        }
                    }.frame(width: columns.leadingWidth + columns.sum + columns.count + CGFloat(events.count) * eventWidth + CompetitionSumRankColumns.inset)
                }.fixedSize(horizontal: false, vertical: true).modifier(CompetitionResultsSurface())
                    .accessibilityIdentifier("competition-sum-ranks-table")
            }
        }.frame(maxWidth: .infinity)
            .background { GeometryReader { proxy in Color.clear.preference(key: CompetitionSumRankWidthKey.self, value: proxy.size.width) } }
            .onPreferenceChange(CompetitionSumRankWidthKey.self) { width = $0 }
    }
    private func row(_ entry: CubingChinaLiveSumRank, position: Int, events: [String], columns: CompetitionSumRankColumns) -> some View {
        let own = CompetitionPersonalIdentity.matches(signedInWCAID: ownWCAID, competitorWCAID: entry.competitor.wcaId)
        return HStack(spacing: 0) {
            cell(String(position), width: columns.position)
            HStack(spacing: 4) {
                Text(language.hasPrefix("zh") && !(entry.competitor.localName ?? "").isEmpty ? entry.competitor.localName! : entry.competitor.name)
                    .lineLimit(1)
                if own { CompetitionPersonalNameBadge(language: language).fixedSize() }
            }.frame(width: columns.name, alignment: .leading)
            cell(entry.competitor.regionIso2.flatMap { appLocale(for: language).localizedString(forRegionCode: $0) } ?? "—", width: columns.region)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("competition-sum-region-\(entry.id.rawValue)")
            cell(String(entry.sum), width: columns.sum).font(.subheadline.weight(.semibold))
            cell(String(entry.count), width: columns.count)
            ForEach(events, id: \.self) { event in
                Text(entry.ranks[event].map(String.init) ?? "—")
                    .foregroundStyle(entry.enteredEventIds.contains(event) ? Color.primary : .secondary.opacity(0.55))
                    .frame(width: eventWidth)
                    .accessibilityLabel(CubingChinaEventDisplay.name(event, language: language) + ": " + (entry.ranks[event].map(String.init) ?? "—"))
            }
        }.font(.subheadline).monospacedDigit().foregroundStyle(.primary)
            .padding(.horizontal, CompetitionSumRankColumns.inset).padding(.vertical, 4).frame(minHeight: 36)
            .contentShape(Rectangle()).modifier(CompetitionPersonalRowTreatment(isOwn: own))
    }
    private func cell(_ text: String, width: CGFloat, leading: Bool = false) -> some View {
        Text(text).frame(width: width, alignment: leading ? .leading : .center)
    }
    private func header(_ text: String, width: CGFloat, leading: Bool = false) -> some View {
        CompetitionResultTableHeaderCell(text: text, width: width, alignment: leading ? .leading : .center)
    }
}
private struct CompetitionSumRankWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
