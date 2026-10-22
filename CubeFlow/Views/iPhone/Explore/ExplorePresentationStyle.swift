#if os(iOS)
import SwiftUI

enum ExploreStyle {
    static let pageInset: CGFloat = 20
    static let surfaceInset: CGFloat = 16
    static let cornerRadius: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static var page: Color { Color(uiColor: .systemGroupedBackground) }
    static var surface: Color { Color(uiColor: .secondarySystemGroupedBackground) }
}

struct ExploreSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .padding(ExploreStyle.surfaceInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ExploreStyle.surface, in: RoundedRectangle(
                cornerRadius: ExploreStyle.cornerRadius, style: .continuous))
    }
}

struct ExploreHeading: View {
    let title: String
    var body: some View {
        Text(title).font(.title2.weight(.bold)).foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }
}

struct ExploreChevron: View {
    var isSectionHeading = false
    var body: some View {
        Image(systemName: "chevron.right")
            .font((isSectionHeading ? Font.subheadline : Font.caption).weight(.semibold))
            .foregroundStyle(.secondary).accessibilityHidden(true)
    }
}

struct ExploreHomeRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 12, leading: ExploreStyle.pageInset,
                                     bottom: 12, trailing: ExploreStyle.pageInset))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

struct ExploreListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .compatibleListSectionSpacing(ExploreStyle.sectionSpacing)
            .compatibleScrollContentBackgroundHidden()
            .background(ExploreStyle.page)
            .environment(\.defaultMinListRowHeight, 48)
    }
}

struct ExploreHomeListStyle: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content.listStyle(.plain).scrollContentBackground(.hidden).background(ExploreStyle.page)
        } else {
            // The legacy grouped table supplies the semantic canvas without global appearance changes.
            content.listStyle(.grouped).background(ExploreStyle.page)
        }
    }
}
#endif
