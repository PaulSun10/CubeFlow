import SwiftUI

struct CompetitionResultTableColumn: Identifiable {
    let id: String
    let title: String
    let width: CGFloat
}

struct CompetitionResultTableValue: Identifiable {
    let id: String
    let text: String
    let recordTag: String?
    let width: CGFloat
}

/// Shared presentation extracted from the WCA Live round table, without Live state/models.
struct CompetitionResultTableHeader: View {
    let nameTitle: String
    let columns: [CompetitionResultTableColumn]

    var body: some View {
        HStack(spacing: 0) {
            cell("#", width: 40, alignment: .trailing)
                .padding(.leading, 7).padding(.trailing, 8)
            cell(nameTitle, width: nil, alignment: .leading)
                .padding(.leading, 10)
            ForEach(columns) { column in
                cell(column.title, width: column.width, alignment: .trailing)
                    .padding(.leading, 10)
                    .padding(.trailing, column.id == columns.last?.id ? 25 : 6)
            }
        }
        .padding(.vertical, 6)
    }

    private func cell(_ text: String, width: CGFloat?, alignment: Alignment) -> some View {
        CompetitionResultTableHeaderCell(text: text, width: width, alignment: alignment)
    }
}

struct CompetitionResultTableHeaderCell: View {
    let text: String
    let width: CGFloat?
    let alignment: Alignment
    var body: some View {
        Text(text).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
            .lineLimit(1).minimumScaleFactor(0.65)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
            .frame(width: width, alignment: alignment)
    }
}

struct CompetitionResultTableRow: View {
    let rank: String
    let name: String
    let values: [CompetitionResultTableValue]
    var rankingForeground: Color = .primary
    var rankingBackground: Color = .clear
    var attempts: [String] = []
    var isOwn = false
    var language = "en"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Text(rank).font(.system(size: 14, weight: .regular))
                    .foregroundStyle(rankingForeground)
                    .frame(width: 40, alignment: .trailing).frame(maxHeight: .infinity)
                    .padding(.leading, 7).padding(.trailing, 8)
                    .background(rankingBackground)
                HStack(spacing: 4) {
                    Text(name).font(.system(size: 14, weight: .regular)).foregroundStyle(.primary)
                        .lineLimit(1).truncationMode(.tail)
                    if isOwn { CompetitionPersonalNameBadge(language: language).fixedSize() }
                }.padding(.leading, 10).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(values.enumerated()), id: \.element.id) { index, value in
                    resultValue(value, emphasized: index == 0)
                        .padding(.leading, 10)
                        .padding(.trailing, value.id == values.last?.id ? 25 : 6)
                }
            }
            .frame(height: 34)
            if !attempts.isEmpty {
                Text(attempts.joined(separator: "   ")).font(.caption).monospacedDigit()
                    .foregroundStyle(PublishedResultsStyle.attemptForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 65).padding(.trailing, 25).padding(.bottom, 7)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func resultValue(_ value: CompetitionResultTableValue, emphasized: Bool) -> some View {
        CompetitionResultTableStatisticValue(text: value.text, recordTag: value.recordTag, width: value.width,
            emphasized: emphasized, isOwnRecord: isOwn)
    }
}

struct CompetitionResultTableStatisticValue: View {
    let text: String
    let recordTag: String?
    let width: CGFloat
    let emphasized: Bool
    var isOwnRecord = false
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(text).font(.system(size: 14, weight: emphasized ? .semibold : .regular))
                .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if let tag = recordTag, !tag.isEmpty {
                CompetitionWCARecordTagView(tag: tag, usesLitePersonalRecord: true, variant: .compact,
                    isOwnPersonalRecord: isOwnRecord)
                    .offset(x: 23, y: -6)
            }
        }
        .frame(width: width, alignment: .trailing)
    }
}
