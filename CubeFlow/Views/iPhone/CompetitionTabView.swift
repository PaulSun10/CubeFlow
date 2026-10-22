import SwiftUI
import UIKit
import MapKit
import CoreLocation
import Combine
import WeatherKit

#if os(iOS)
nonisolated func competitionListRequestIsCurrent(expected: String, current: String, isActive: Bool) -> Bool {
    !Task.isCancelled && isActive && expected == current
}

private struct CompetitionSkeletonBreathingModifier: ViewModifier {
    @State private var isDimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(isDimmed ? 0.6 : 1.0)
            .brightness(isDimmed ? 0.08 : -0.03)
            .scaleEffect(isDimmed ? 0.988 : 1.0)
            .onAppear {
                guard !isDimmed else { return }
                withAnimation(.easeInOut(duration: 0.82).repeatForever(autoreverses: true)) {
                    isDimmed = true
                }
            }
    }
}

private struct CompetitionAddressText: View {
    let address: CompetitionService.ParsedAddress
    let competitionID: String
    @Binding var tappedCompetitionID: String?
    var emphasizedPrefix: String?
    var emphasizedPrefixFont: Font?

    var body: some View {
        Text(attributedAddress)
            .environment(\.openURL, OpenURLAction { _ in
                tappedCompetitionID = competitionID
                DispatchQueue.main.async {
                    if tappedCompetitionID == competitionID {
                        tappedCompetitionID = nil
                    }
                }
                return .systemAction
            })
    }

    private var attributedAddress: AttributedString {
        var output = AttributedString()
        for segment in address.segments {
            let isLinked = segment.destinationURL != nil
            var run = AttributedString(segment.text + (isLinked ? " ↗" : ""))
            run.foregroundColor = isLinked ? Color.accentColor : Color.primary
            run.link = segment.destinationURL
            output += run
        }

        if let emphasizedPrefix,
           let emphasizedPrefixFont,
           let range = output.range(of: emphasizedPrefix) {
            output[range].font = emphasizedPrefixFont
        }
        return output
    }
}

private struct CompetitionCompactStatusButton: UIViewRepresentable {
    let symbolName: String
    let tintColor: UIColor
    let accessibilityLabel: String
    let message: String
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.didTap(_:)),
            for: .touchUpInside
        )
        configure(button)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
        configure(button)
    }

    private func configure(_ button: UIButton) {
        let imageConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        button.setImage(UIImage(systemName: symbolName, withConfiguration: imageConfiguration), for: .normal)
        button.tintColor = tintColor
        button.accessibilityLabel = accessibilityLabel
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
    }

    final class Coordinator: NSObject, UIPopoverPresentationControllerDelegate {
        var parent: CompetitionCompactStatusButton
        weak var presentedController: UIViewController?

        init(parent: CompetitionCompactStatusButton) {
            self.parent = parent
        }

        @objc func didTap(_ sender: UIButton) {
            parent.onTap()
            guard presentedController == nil,
                  let presenter = nearestViewController(from: sender) else { return }

            let label = UILabel()
            label.text = parent.message
            label.font = UIFont.preferredFont(forTextStyle: .subheadline)
            label.textColor = .label
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false

            let content = UIViewController()
            content.view.backgroundColor = .clear
            content.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: content.view.leadingAnchor, constant: 14),
                label.trailingAnchor.constraint(equalTo: content.view.trailingAnchor, constant: -14),
                label.topAnchor.constraint(equalTo: content.view.topAnchor, constant: 11),
                label.bottomAnchor.constraint(equalTo: content.view.bottomAnchor, constant: -11)
            ])

            let availableWidth = max((sender.window?.bounds.width ?? 320) - 32, 180)
            let maximumWidth = min(availableWidth, 300)
            let measured = label.sizeThatFits(
                CGSize(width: maximumWidth - 28, height: .greatestFiniteMagnitude)
            )
            content.preferredContentSize = CGSize(
                width: min(max(ceil(measured.width) + 28, 108), maximumWidth),
                height: ceil(measured.height) + 22
            )
            content.modalPresentationStyle = .popover

            guard let popover = content.popoverPresentationController else { return }
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
            popover.permittedArrowDirections = [.up, .down]
            popover.delegate = self
            presentedController = content
            presenter.present(content, animated: true)
        }

        func adaptivePresentationStyle(
            for controller: UIPresentationController
        ) -> UIModalPresentationStyle {
            .none
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            presentedController = nil
        }

        private func nearestViewController(from view: UIView) -> UIViewController? {
            sequence(first: view.next, next: { $0?.next })
                .compactMap { $0 as? UIViewController }
                .first
        }
    }
}

private extension View {
    func competitionSkeletonBreathing() -> some View {
        modifier(CompetitionSkeletonBreathingModifier())
    }

    @ViewBuilder
    func competitionSystemChromeUnderlap() -> some View {
        if #available(iOS 26.0, *) {
            ignoresSafeArea(.container, edges: .vertical)
        } else {
            self
        }
    }
}

private struct CompetitionDetailHeaderSeparatorPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CompetitionDetailScrollTopInsetModifier: ViewModifier {
    @Binding var topInset: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentInsets.top
            } action: { _, newValue in
                topInset = newValue
            }
        } else {
            content
        }
    }
}

private struct CompetitionCardSurfaceModifier: ViewModifier {
    let isGlass: Bool
    let shape: RoundedRectangle

    @ViewBuilder
    func body(content: Content) -> some View {
        if isGlass {
            content.compatibleGlass(in: shape)
                .background { CompetitionTopCubersSurfaceBridge() }
        } else {
            content
        }
    }
}

private struct CompetitionListRowBackgroundModifier: ViewModifier {
    let isGlass: Bool
    let shape: RoundedRectangle

    @ViewBuilder
    func body(content: Content) -> some View {
        if isGlass {
            content
                .background(
                    shape
                        .fill(.black.opacity(0.001))
                )
        } else {
            content
        }
    }
}

private struct CompetitionConditionalAsyncTaskModifier: ViewModifier {
    let isEnabled: Bool
    let id: String
    let action: () async -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.task(id: id) {
                await action()
            }
        } else {
            content
        }
    }
}

private extension ShapeStyle where Self == Color {
    static var competitionSkeletonFill: Color {
        Color(uiColor: .secondarySystemFill)
    }
}

@MainActor
private enum CompetitionDateRangeFormatterCache {
    private static let calendar = Calendar(identifier: .gregorian)
    private static var formatters: [String: DateFormatter] = [:]

    static func string(from date: Date, locale: Locale, format: String) -> String {
        formatter(locale: locale, format: format).string(from: date)
    }

    private static func formatter(locale: Locale, format: String) -> DateFormatter {
        let key = "\(locale.identifier)|\(format)"
        if let formatter = formatters[key] {
            return formatter
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateFormat = format
        formatters[key] = formatter
        return formatter
    }
}

#if DEBUG
private struct CompetitionSizeDebugModifier: ViewModifier {
    let label: String
    let color: Color
    @AppStorage(CompetitionTopCubersDebugBounds.key) private var enabled = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if enabled {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(color.opacity(0.75), lineWidth: 0.75)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topTrailing) {
                if enabled {
                    GeometryReader { proxy in
                        Text("\(label) \(proxy.size.width, specifier: "%.1f") × \(proxy.size.height, specifier: "%.1f")")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(color)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(.regularMaterial, in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: label == "section available" ? .bottomTrailing : .topTrailing)
                            .offset(y: label == "section available" ? 12 : 0)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }
}
#endif

extension View {
    @ViewBuilder
    func competitionSizeDebug(_ label: String, color: Color) -> some View {
        #if DEBUG
        modifier(CompetitionSizeDebugModifier(label: label, color: color))
        #else
        self
        #endif
    }
}

@available(iOS 16.0, *)
struct CompetitionWrappingLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func measuredSize(for subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let naturalSize = subview.sizeThatFits(.unspecified)
        guard naturalSize.width > maxWidth else { return naturalSize }
        return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = measuredSize(for: subview, maxWidth: maxWidth)
            let startsNewRow = currentRowWidth > 0 && currentRowWidth + horizontalSpacing + size.width > maxWidth

            if startsNewRow {
                totalWidth = max(totalWidth, currentRowWidth)
                totalHeight += currentRowHeight + verticalSpacing
                currentRowWidth = size.width
                currentRowHeight = size.height
            } else {
                currentRowWidth += (currentRowWidth > 0 ? horizontalSpacing : 0) + size.width
                currentRowHeight = max(currentRowHeight, size.height)
            }
        }

        totalWidth = max(totalWidth, currentRowWidth)
        totalHeight += currentRowHeight

        return CGSize(
            width: proposal.width ?? totalWidth,
            height: totalHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = measuredSize(for: subview, maxWidth: maxWidth)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += currentRowHeight + verticalSpacing
                currentRowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + horizontalSpacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
    }
}

@available(iOS 16.0, *)
struct CompetitionTopCuberChipLayout: Layout {
    var spacing: CGFloat = 8

    private func badgeSizes(for subviews: Subviews) -> [CGSize] {
        guard subviews.count > 1 else { return [] }
        return subviews.dropFirst().map { $0.sizeThatFits(.unspecified) }
    }

    private func badgeWidth(from sizes: [CGSize]) -> CGFloat {
        guard !sizes.isEmpty else { return 0 }
        return sizes.map(\.width).reduce(0, +) + CGFloat(sizes.count) * spacing
    }

    private func measuredNameSize(
        for subviews: Subviews,
        badgeWidth: CGFloat,
        maxWidth: CGFloat
    ) -> CGSize {
        guard let name = subviews.first else { return .zero }

        let naturalNameSize = name.sizeThatFits(.unspecified)
        let naturalWidth = naturalNameSize.width + badgeWidth
        guard maxWidth.isFinite, naturalWidth > maxWidth else {
            return naturalNameSize
        }

        let proposedNameWidth = max(0, maxWidth - badgeWidth)
        return name.sizeThatFits(ProposedViewSize(width: proposedNameWidth, height: nil))
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let badgeSizes = badgeSizes(for: subviews)
        let badgesWidth = badgeWidth(from: badgeSizes)
        let nameSize = measuredNameSize(for: subviews, badgeWidth: badgesWidth, maxWidth: maxWidth)
        let contentWidth = nameSize.width + badgesWidth
        let contentHeight = max(nameSize.height, badgeSizes.map(\.height).max() ?? 0)

        return CGSize(
            width: maxWidth.isFinite ? min(contentWidth, maxWidth) : contentWidth,
            height: contentHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        guard let name = subviews.first else { return }

        let badgeSizes = badgeSizes(for: subviews)
        let badgesWidth = badgeWidth(from: badgeSizes)
        let nameSize = measuredNameSize(for: subviews, badgeWidth: badgesWidth, maxWidth: bounds.width)
        let nameY = bounds.minY + (bounds.height - nameSize.height) / 2

        name.place(
            at: CGPoint(x: bounds.minX, y: nameY),
            proposal: ProposedViewSize(nameSize)
        )

        var badgeX = bounds.minX + nameSize.width + spacing
        for (index, badge) in subviews.dropFirst().enumerated() {
            let size = badgeSizes[index]
            let badgeY = bounds.minY + (bounds.height - size.height) / 2
            badge.place(
                at: CGPoint(x: badgeX, y: badgeY),
                proposal: ProposedViewSize(size)
            )
            badgeX += size.width + spacing
        }
    }
}

@MainActor
private final class CompetitionListRuntimeCache {
    struct Snapshot {
        let competitions: [CompetitionSummary]
        let competitionsByID: [String: CompetitionSummary]
        let displayItems: [CompetitionListItem]
        let nextPage: Int?
        let loadedCount: Int
        let totalCount: Int?
        let topCuberStatesByCompetitionID: [String: CompetitionTopCuberLoadState]
    }

    static let shared = CompetitionListRuntimeCache()

    private var snapshotsBySignature: [String: Snapshot] = [:]
    private var snapshotOrder: [String] = []

    func snapshot(for signature: String) -> Snapshot? {
        if snapshotsBySignature[signature] != nil {
            snapshotOrder.removeAll { $0 == signature }; snapshotOrder.append(signature)
        }
        return snapshotsBySignature[signature]
    }

    func store(_ snapshot: Snapshot, for signature: String) {
        snapshotsBySignature[signature] = snapshot
        snapshotOrder.removeAll { $0 == signature }; snapshotOrder.append(signature)
        while snapshotOrder.count > CompetitionCachePolicy.maximumQueryCount {
            snapshotsBySignature[snapshotOrder.removeFirst()] = nil
        }
    }
}

@MainActor
private final class CompetitionListLookupStore: ObservableObject {
    private(set) var sourceRevision: UInt64 = 0
    private(set) var competitions: [CompetitionSummary] = []
    private(set) var visibleCompetitionsSnapshot: [CompetitionSummary] = []
    private(set) var competitionsByID: [String: CompetitionSummary] = [:]
    private(set) var publishedCompetitions: [CompetitionSummary] = []
    private(set) var preparedDisplayItems: [CompetitionListItem] = []

    func setCompetitions(_ competitions: [CompetitionSummary]) {
        sourceRevision &+= 1
        self.competitions = competitions
        rebuildLookup()
    }

    func setVisibleCompetitionsSnapshot(_ visibleCompetitionsSnapshot: [CompetitionSummary]) {
        sourceRevision &+= 1
        self.visibleCompetitionsSnapshot = visibleCompetitionsSnapshot
    }

    func setPublishedCompetitions(_ publishedCompetitions: [CompetitionSummary]) {
        self.publishedCompetitions = publishedCompetitions
        rebuildLookup()
    }

    func setPreparedDisplayItems(_ items: [CompetitionListItem]) {
        preparedDisplayItems = items
    }

    func setListSnapshot(_ competitions: [CompetitionSummary]) {
        setListSnapshot(
            competitions,
            lookup: Dictionary(uniqueKeysWithValues: competitions.map { ($0.id, $0) })
        )
    }

    func setListSnapshot(
        _ competitions: [CompetitionSummary],
        lookup: [String: CompetitionSummary]
    ) {
        sourceRevision &+= 1
        self.competitions = competitions
        visibleCompetitionsSnapshot = competitions
        publishedCompetitions = competitions
        competitionsByID = lookup
    }

    private func rebuildLookup() {
        var nextByID: [String: CompetitionSummary] = [:]

        for competition in competitions {
            nextByID[competition.id] = competition
        }
        for competition in publishedCompetitions {
            nextByID[competition.id] = competition
        }
        competitionsByID = nextByID
    }

    func clear() {
        sourceRevision &+= 1
        competitions = []
        visibleCompetitionsSnapshot = []
        competitionsByID = [:]
        publishedCompetitions = []
        preparedDisplayItems = []
    }

    func competition(id: String) -> CompetitionSummary? {
        competitionsByID[id]
    }
}

private struct CompetitionDetailSelection: Identifiable, Hashable {
    let id: String
}

enum CompetitionCardStyleOption: String, CaseIterable, Identifiable {
    case list
    case glass
    case compact

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .list:
            return "settings.competition_card_style_list"
        case .glass:
            return "settings.competition_card_style_glass"
        case .compact:
            return "settings.competition_card_style_compact"
        }
    }
}

private enum CompactRegistrationDisplayStatus: Hashable {
    case open
    case closed
    case limitReached
    case notOpenYet
}

private enum CompetitionRowStatusTint: Hashable {
    case orange
    case yellow
    case green
    case mint
    case blue
    case teal
    case secondary

    var color: Color {
        switch self {
        case .orange:
            return .orange
        case .yellow:
            return .yellow
        case .green:
            return .green
        case .mint:
            return .mint
        case .blue:
            return .blue
        case .teal:
            return .teal
        case .secondary:
            return .secondary
        }
    }
}

private struct CompetitionRowModel: Identifiable, Equatable {
    let id: String
    let rowIndex: Int
    let startYear: Int
    let showsYearSeparator: Bool
    let contentHash: Int
    let name: String
    let compactDisplayName: String
    let flagEmoji: String
    let dateRangeText: String
    let locationLine: String
    let venueLine: String
    let competitorLimit: Int?
    let statusBadgeTitle: String
    let statusTint: CompetitionRowStatusTint
    let compactStatus: CompactRegistrationDisplayStatus
    let compactStatusMessage: String
    let compactAddressCountry: String
    let compactAddress: CompetitionService.ParsedAddress
    let venueAddress: CompetitionService.ParsedAddress

    static func == (lhs: CompetitionRowModel, rhs: CompetitionRowModel) -> Bool {
        lhs.id == rhs.id && lhs.contentHash == rhs.contentHash
    }
}

private enum CompetitionListItem: Identifiable, Equatable {
    case year(Int)
    case competition(CompetitionRowModel)

    var id: String {
        switch self {
        case .year(let year):
            return "year:\(year)"
        case .competition(let row):
            return "competition:\(row.id)"
        }
    }

    var diffableID: String {
        switch self {
        case .year(let year):
            return "year:\(year)"
        case .competition(let row):
            return "competition:\(row.id):\(row.contentHash)"
        }
    }
}

private enum CompetitionListLoadPhase: Equatable {
    case initialLoading
    case loadingMore
    case rateLimited(Date)
    case failed(String)
    case completed
}

private enum CompetitionVirtualizedFooterState: Equatable {
    case loading
    case rateLimited
    case failed(String)
    case completed
}

final class CompetitionHostingCollectionViewCell: UICollectionViewCell {
    private var host: UIHostingController<AnyView>?

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        guard let collection = sequence(first: superview, next: { $0?.superview })
            .compactMap({ $0 as? UICollectionView }).first,
              collection.collectionViewLayout is CompetitionVerticalListLayout,
              let attributes = layoutAttributes.copy() as? UICollectionViewLayoutAttributes else {
            return super.preferredLayoutAttributesFitting(layoutAttributes)
        }
        let width = CompetitionVerticalListLayout.rowWidth(collection)
        #if DEBUG
        let fitStart = CACurrentMediaTime()
        #endif
        attributes.size = CGSize(width: width, height: ceil(contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height))
        #if DEBUG
        CompetitionDisclosureViewportProbe.shared.recordFit(self, height: attributes.size.height,
            milliseconds: (CACurrentMediaTime() - fitStart) * 1000)
        CompetitionPhysicalBrowserAcceptance.recordFit(attributes, original: layoutAttributes, collection: collection)
        CompetitionScrollOwnerDiagnostics.cellEvent("preferred-size", cell: self, details: [
            "row": layoutAttributes.indexPath.item, "original": CompetitionScrollOwnerDiagnostics.rect(layoutAttributes.frame),
            "preferred": CompetitionScrollOwnerDiagnostics.rect(attributes.frame),
            "offsetY": collection.contentOffset.y, "dragging": collection.isDragging,
            "decelerating": collection.isDecelerating])
        #endif
        return attributes
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        #if DEBUG
        CompetitionScrollOwnerDiagnostics.cellEvent("prepare-reuse", cell: self)
        #endif
        if #available(iOS 16.0, *) {
            contentConfiguration = nil
        } else {
            host?.rootView = AnyView(EmptyView())
        }
    }

    func setRootView(_ rootView: AnyView) {
        #if DEBUG
        CompetitionScrollOwnerDiagnostics.cellEvent("set-root", cell: self)
        #endif
        // Accept the current hosting height while self-sizing catches up. A
        // content-derived minimum recenters growing content in the old bounds.
        let rootView = AnyView(rootView.frame(minHeight: 0, maxHeight: .infinity, alignment: .top))
        if #available(iOS 16.0, *) {
            contentConfiguration = UIHostingConfiguration {
                rootView
            }
            .margins(.all, 0)
            .background(.clear)
            return
        }

        if let host {
            host.rootView = rootView
            host.view.invalidateIntrinsicContentSize()
            return
        }

        let host = UIHostingController(rootView: rootView)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        self.host = host
    }
}

#if DEBUG
func competitionDisclosureAcceptanceList(state: CompetitionDisclosureAcceptanceState, controlled: Bool,
                                        boundary: Bool, edge: Bool, glass: Bool,
                                        productionTop: CompetitionProductionTopAcceptanceInput? = nil) -> some View {
    CompetitionVirtualizedList(items: [.year(0), .year(1), .year(2)], dataRevision: 1,
        querySignature: "disclosure", presentationSignature: "disclosure", footerState: .completed,
        backgroundColor: .clear, rowContent: { item in
            if case .year(let index) = item {
                return AnyView(CompetitionDisclosureAcceptanceRow(index: index, state: state, controlled: controlled,
                    boundary: boundary, edge: edge, glass: glass, productionTop: productionTop))
            }
            return AnyView(EmptyView())
        }, footerContent: { _ in AnyView(Text("No more competitions").frame(height: 44)) },
        onRefresh: {}, observesDisclosure: true)
        .competitionSystemChromeUnderlap()
}
func competitionDisclosureAcceptanceCard<Content: View>(glass: Bool, @ViewBuilder content: () -> Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    return content().modifier(CompetitionCardSurfaceModifier(isGlass: glass, shape: shape))
        .modifier(CompetitionListRowBackgroundModifier(isGlass: glass, shape: shape))
}
#endif

/// A single self-sizing row per line. Compositional estimated groups anchor their
/// trailing edge when a partially visible row shrinks, moving the viewport with it.
final class CompetitionVerticalListLayout: UICollectionViewFlowLayout {
    #if DEBUG
    override func invalidationContext(forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
                                      withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forPreferredLayoutAttributes: preferredAttributes, withOriginalAttributes: originalAttributes)
        CompetitionPhysicalBrowserAcceptance.record(preferredAttributes, original: originalAttributes, context: context, collection: collectionView)
        CompetitionScrollOwnerDiagnostics.event("preferred-invalidation", details: [
            "row": preferredAttributes.indexPath.item,
            "original": CompetitionScrollOwnerDiagnostics.rect(originalAttributes.frame),
            "preferred": CompetitionScrollOwnerDiagnostics.rect(preferredAttributes.frame),
            "offsetAdjustmentY": context.contentOffsetAdjustment.y,
            "sizeAdjustmentY": context.contentSizeAdjustment.height,
            "offsetY": collectionView?.contentOffset.y ?? 0,
            "dragging": collectionView?.isDragging ?? false, "decelerating": collectionView?.isDecelerating ?? false])
        return context
    }
    #endif
    static func rowWidth(_ collectionView: UICollectionView) -> CGFloat {
        max(1, collectionView.bounds.width - collectionView.adjustedContentInset.left - collectionView.adjustedContentInset.right)
    }
    override init() {
        super.init()
        minimumLineSpacing = 0
        minimumInteritemSpacing = 0
        estimatedItemSize = CGSize(width: 1, height: 76)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func prepare() {
        if let collectionView {
            let width = Self.rowWidth(collectionView)
            if estimatedItemSize.width != width {
                estimatedItemSize = CGSize(width: width, height: 76)
            }
        }
        super.prepare()
    }
}

private struct CompetitionVirtualizedList: UIViewRepresentable {
    let items: [CompetitionListItem]
    let dataRevision: Int
    let querySignature: String
    let presentationSignature: String
    let footerState: CompetitionVirtualizedFooterState
    let backgroundColor: UIColor
    let rowContent: (CompetitionListItem) -> AnyView
    let footerContent: (CompetitionVirtualizedFooterState) -> AnyView
    let onRefresh: () async -> Void
    #if DEBUG
    var observesDisclosure = false
    var publicationScope: UUID? = nil
    func scopedPublication(_ scope: UUID?) -> Self {
        var view = self; view.publicationScope = scope; return view
    }
    #endif
    var observesPublication = false

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: CompetitionVerticalListLayout()
        )
        collectionView.backgroundColor = backgroundColor
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        if #available(iOS 16.0, *) {
            collectionView.selfSizingInvalidation = .enabledIncludingConstraints
        }
        collectionView.contentInsetAdjustmentBehavior = .automatic
        if #available(iOS 26.0, *) {
            collectionView.topEdgeEffect.style = .soft
            collectionView.bottomEdgeEffect.style = .soft
        }
        collectionView.delegate = context.coordinator
        #if DEBUG
        if CompetitionLongListAcceptance.traceEnabled { collectionView.accessibilityIdentifier = "competition-long-list" }
        #endif
        collectionView.register(
            CompetitionHostingCollectionViewCell.self,
            forCellWithReuseIdentifier: Coordinator.cellReuseIdentifier
        )
        context.coordinator.installDataSource(on: collectionView)
        #if DEBUG
        if observesDisclosure || CompetitionLongListAcceptance.traceEnabled {
            CompetitionDisclosureViewportProbe.shared.attach(collectionView)
        }
        #endif

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(
            context.coordinator,
            action: #selector(Coordinator.didRequestRefresh(_:)),
            for: .valueChanged
        )
        collectionView.refreshControl = refreshControl
        context.coordinator.registerAsContentScrollView(collectionView)
        context.coordinator.update(parent: self, collectionView: collectionView)
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        #if DEBUG
        let beforeOffset = collectionView.contentOffset.y
        let beforeInset = collectionView.adjustedContentInset.top
        #endif
        collectionView.backgroundColor = backgroundColor
        collectionView.contentInsetAdjustmentBehavior = .automatic
        if #available(iOS 26.0, *) {
            collectionView.topEdgeEffect.style = .soft
            collectionView.bottomEdgeEffect.style = .soft
        }
        context.coordinator.registerAsContentScrollView(collectionView)
        context.coordinator.update(parent: self, collectionView: collectionView)
        #if DEBUG
        CompetitionPhysicalBrowserAcceptance.recordUpdate(collectionView, beforeOffset: beforeOffset, beforeInset: beforeInset)
        #endif
    }

    static func dismantleUIView(_ collectionView: UICollectionView, coordinator: Coordinator) {
        coordinator.unregisterContentScrollView(collectionView)
    }

    final class Coordinator: NSObject, UICollectionViewDelegate {
        static let cellReuseIdentifier = "CompetitionVirtualizedCell"
        static let footerID = "competition-list-footer"

        private var parent: CompetitionVirtualizedList
        private var itemsByID: [String: CompetitionListItem] = [:]
        private var appliedDataRevision = -1
        private var appliedQuerySignature = ""
        private var appliedPresentationSignature = ""
        private var appliedFooterState: CompetitionVirtualizedFooterState?
        private var isApplyingSnapshot = false
        private var pendingParent: CompetitionVirtualizedList?
        private var refreshTask: Task<Void, Never>?
        private var dataSource: UICollectionViewDiffableDataSource<Int, String>?
        private let scrollActivity = CompetitionListInteraction()
        #if DEBUG
        private let longScrollTrace = CompetitionLongScrollTrace()
        #endif
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            #if DEBUG
            CompetitionScrollOwnerDiagnostics.event("drag-began", details: ["offsetY": scrollView.contentOffset.y])
            #endif
            scrollActivity.setActive(true)
            #if DEBUG
            if CompetitionPhysicalBrowserAcceptance.enabled { CompetitionPhysicalBrowserAcceptance.dragCount += 1 }
            if CompetitionLongListAcceptance.traceEnabled {
                CompetitionLongListAcceptance.firstDragStarted = true
                longScrollTrace.begin(scrollView)
            }
            #endif
        }
        #if DEBUG
        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                      targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            CompetitionScrollOwnerDiagnostics.event("drag-will-end", details: ["offsetY": scrollView.contentOffset.y,
                "velocityY": velocity.y, "nativeTargetY": targetContentOffset.pointee.y])
        }
        func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
            CompetitionScrollOwnerDiagnostics.event("deceleration-began", details: ["offsetY": scrollView.contentOffset.y])
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if CompetitionLongListAcceptance.traceEnabled { longScrollTrace.sample(scrollView) }
        }
        #endif
        private weak var contentScrollViewController: UIViewController?
        private weak var registeredContentScrollView: UICollectionView?
        private var isContentScrollViewRegistrationPending = false
        private var isContentScrollViewRegistered = false

        init(parent: CompetitionVirtualizedList) {
            self.parent = parent
        }

        deinit {
            refreshTask?.cancel()
        }

        func installDataSource(on collectionView: UICollectionView) {
            dataSource = UICollectionViewDiffableDataSource<Int, String>(
                collectionView: collectionView
            ) { [weak self] collectionView, indexPath, identifier in
                guard let self else { return nil }
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: Self.cellReuseIdentifier,
                    for: indexPath
                )
                guard let hostingCell = cell as? CompetitionHostingCollectionViewCell else {
                    return cell
                }
                if identifier == Self.footerID {
                    #if DEBUG
                    if CompetitionPhysicalBrowserAcceptance.enabled, CompetitionPhysicalBrowserAcceptance.interior {
                        hostingCell.setRootView(AnyView(VStack(spacing: 0) {
                            self.parent.footerContent(self.parent.footerState)
                            Color.clear.frame(height: 1600)
                        }))
                    } else {
                        hostingCell.setRootView(parent.footerContent(parent.footerState))
                    }
                    #else
                    hostingCell.setRootView(parent.footerContent(parent.footerState))
                    #endif
                } else if let item = itemsByID[identifier] {
                    hostingCell.setRootView(AnyView(parent.rowContent(item)
                        .environment(\.competitionListInteraction, scrollActivity)))
                }
                return hostingCell
            }
        }

        func registerAsContentScrollView(_ collectionView: UICollectionView) {
            if registeredContentScrollView === collectionView,
               isContentScrollViewRegistered {
                return
            }
            registeredContentScrollView = collectionView
            guard !isContentScrollViewRegistrationPending else { return }
            isContentScrollViewRegistrationPending = true
            DispatchQueue.main.async { [weak self, weak collectionView] in
                guard let self else { return }
                self.isContentScrollViewRegistrationPending = false
                guard let collectionView,
                      self.registeredContentScrollView === collectionView,
                      let viewController = self.nearestViewController(from: collectionView) else {
                    return
                }

                if self.contentScrollViewController !== viewController {
                    self.contentScrollViewController?.setContentScrollView(nil)
                    self.contentScrollViewController = viewController
                }
                viewController.setContentScrollView(collectionView)
                self.isContentScrollViewRegistered = true
            }
        }

        func unregisterContentScrollView(_ collectionView: UICollectionView) {
            guard registeredContentScrollView === collectionView else { return }
            contentScrollViewController?.setContentScrollView(nil)
            contentScrollViewController = nil
            registeredContentScrollView = nil
            isContentScrollViewRegistered = false
            scrollActivity.setActive(false)
        }

        private func nearestViewController(from view: UIView) -> UIViewController? {
            sequence(first: view.next, next: { $0?.next })
                .compactMap { $0 as? UIViewController }
                .first
        }

        func update(parent: CompetitionVirtualizedList, collectionView: UICollectionView) {
            self.parent = parent

            if appliedDataRevision != parent.dataRevision {
                #if DEBUG
                CompetitionScrollOwnerDiagnostics.event("data-update-request", details: ["revision": parent.dataRevision,
                    "query": parent.querySignature, "dragging": collectionView.isDragging,
                    "decelerating": collectionView.isDecelerating])
                #endif
                pendingParent = parent
                applyPendingUpdateIfPossible(on: collectionView)
                return
            }

            if appliedPresentationSignature != parent.presentationSignature
                || appliedFooterState != parent.footerState {
                #if DEBUG
                CompetitionScrollOwnerDiagnostics.event("presentation-update-request", details: [
                    "oldSignature": appliedPresentationSignature, "newSignature": parent.presentationSignature,
                    "footerChanged": appliedFooterState != parent.footerState,
                    "dragging": collectionView.isDragging, "decelerating": collectionView.isDecelerating])
                #endif
                pendingParent = parent
                applyPendingUpdateIfPossible(on: collectionView)
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            #if DEBUG
            CompetitionScrollOwnerDiagnostics.event("drag-ended-before-publication", details: [
                "offsetY": scrollView.contentOffset.y, "willDecelerate": decelerate])
            #endif
            scrollActivity.setActive(decelerate)
            #if DEBUG
            CompetitionPhysicalBrowserAcceptance.flush()
            #endif
            guard !decelerate, let collectionView = scrollView as? UICollectionView else { return }
            #if DEBUG
            if CompetitionLongListAcceptance.traceEnabled { longScrollTrace.finish(scrollView) }
            #endif
            applyPendingUpdateIfPossible(on: collectionView)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            #if DEBUG
            CompetitionScrollOwnerDiagnostics.event("deceleration-ended-before-publication", details: ["offsetY": scrollView.contentOffset.y])
            #endif
            scrollActivity.setActive(false)
            #if DEBUG
            CompetitionScrollOwnerDiagnostics.event("idle-publication-returned", details: ["offsetY": scrollView.contentOffset.y])
            #endif
            #if DEBUG
            CompetitionPhysicalBrowserAcceptance.flush()
            #endif
            guard let collectionView = scrollView as? UICollectionView else { return }
            #if DEBUG
            if CompetitionLongListAcceptance.traceEnabled { longScrollTrace.finish(scrollView) }
            #endif
            applyPendingUpdateIfPossible(on: collectionView)
        }

        private func applyPendingUpdateIfPossible(on collectionView: UICollectionView) {
            guard !isApplyingSnapshot, let pendingParent else { return }
            guard !collectionView.isDragging, !collectionView.isDecelerating else { return }
            self.pendingParent = nil
            self.parent = pendingParent

            if appliedDataRevision != pendingParent.dataRevision {
                #if DEBUG
                CompetitionScrollOwnerDiagnostics.event("snapshot-begin", details: ["revision": pendingParent.dataRevision,
                    "count": pendingParent.items.count, "queryChanged": appliedQuerySignature != pendingParent.querySignature])
                #endif
                itemsByID = Dictionary(
                    uniqueKeysWithValues: pendingParent.items.map { ($0.diffableID, $0) }
                )
                var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
                snapshot.appendSections([0])
                snapshot.appendItems(pendingParent.items.map(\.diffableID), toSection: 0)
                snapshot.appendItems([Self.footerID], toSection: 0)
                isApplyingSnapshot = true
                dataSource?.apply(snapshot, animatingDifferences: false) { [weak self, weak collectionView] in
                    guard let self else { return }
                    #if DEBUG
                    CompetitionScrollOwnerDiagnostics.event("snapshot-completed", details: ["offsetY": collectionView?.contentOffset.y ?? 0])
                    #endif
                    appliedDataRevision = pendingParent.dataRevision
                    appliedPresentationSignature = pendingParent.presentationSignature
                    appliedFooterState = pendingParent.footerState
                    isApplyingSnapshot = false
                    #if DEBUG
                    if pendingParent.observesPublication {
                        let ids = dataSource?.snapshot().itemIdentifiers.compactMap { id -> String? in
                            if let item = self.itemsByID[id], case .competition(let row) = item { return row.id }; return nil
                        } ?? []
                        CompetitionBrowserPublicationAcceptance.reportDisplayed(ids, scope: parent.publicationScope)
                    }
                    #endif
                    guard let collectionView else { return }
                    if appliedQuerySignature != pendingParent.querySignature {
                        #if DEBUG
                        let previousQuery = appliedQuerySignature
                        let previousOffset = collectionView.contentOffset.y
                        #endif
                        appliedQuerySignature = pendingParent.querySignature
                        #if DEBUG
                        CompetitionScrollOwnerDiagnostics.event("query-offset-reset", details: [
                            "query": pendingParent.querySignature, "offsetY": collectionView.contentOffset.y])
                        #endif
                        collectionView.setContentOffset(
                            CGPoint(x: 0, y: -collectionView.adjustedContentInset.top),
                            animated: false
                        )
                        #if DEBUG
                        if pendingParent.observesDisclosure {
                            CompetitionDisclosureViewportProbe.shared.recordQueryScroll(from: previousQuery,
                                to: appliedQuerySignature, before: previousOffset, after: collectionView.contentOffset.y)
                        }
                        #endif
                    }
                    applyPendingUpdateIfPossible(on: collectionView)
                }
                return
            }

            guard var snapshot = dataSource?.snapshot() else { return }
            var identifiersToReconfigure: [String] = []
            if appliedPresentationSignature != pendingParent.presentationSignature {
                identifiersToReconfigure.append(contentsOf: collectionView.indexPathsForVisibleItems.compactMap {
                    dataSource?.itemIdentifier(for: $0)
                })
            }
            if appliedFooterState != pendingParent.footerState,
               snapshot.indexOfItem(Self.footerID) != nil {
                identifiersToReconfigure.append(Self.footerID)
            }
            let uniqueIdentifiers = Array(Set(identifiersToReconfigure))
            guard !uniqueIdentifiers.isEmpty else { return }
            snapshot.reconfigureItems(uniqueIdentifiers)
            #if DEBUG
            CompetitionScrollOwnerDiagnostics.event("reconfigure-begin", details: ["ids": uniqueIdentifiers,
                "oldSignature": appliedPresentationSignature, "newSignature": pendingParent.presentationSignature])
            #endif
            isApplyingSnapshot = true
            dataSource?.apply(snapshot, animatingDifferences: false) { [weak self, weak collectionView] in
                guard let self else { return }
                #if DEBUG
                CompetitionScrollOwnerDiagnostics.event("reconfigure-completed", details: ["offsetY": collectionView?.contentOffset.y ?? 0])
                #endif
                appliedPresentationSignature = pendingParent.presentationSignature
                appliedFooterState = pendingParent.footerState
                isApplyingSnapshot = false
                guard let collectionView else { return }
                applyPendingUpdateIfPossible(on: collectionView)
            }
        }

        @objc func didRequestRefresh(_ sender: UIRefreshControl) {
            refreshTask?.cancel()
            let refresh = parent.onRefresh
            refreshTask = Task { @MainActor in
                await refresh()
                sender.endRefreshing()
            }
        }
    }
}

private struct CompetitionPreparedRow: Sendable {
    let competition: CompetitionSummary
    let rowIndex: Int
    let competitionYear: Int
    let showsYearSeparator: Bool
    let name: String
    let compactDisplayName: String
    let flagEmoji: String
    let dateRangeText: String
    let locationLine: String
    let venueLine: String
    let compactAddressCountry: String
    let compactAddress: CompetitionService.ParsedAddress
    let venueAddress: CompetitionService.ParsedAddress
}

private enum CompetitionRowPreparation {
    nonisolated static func prepare(
        _ competitions: [CompetitionSummary],
        languageCode: String
    ) -> [CompetitionPreparedRow] {
        let locale = appLocale(for: languageCode)
        let calendar = Calendar(identifier: .gregorian)
        let fullFormat = appLocalizedString("competition.date.full_format", languageCode: languageCode)
        let monthDayFormat = appLocalizedString("competition.date.month_day_format", languageCode: languageCode)
        let daySuffixFormat = appLocalizedString("competition.date.day_suffix_format", languageCode: languageCode)
        let fullFormatter = dateFormatter(locale: locale, format: fullFormat)
        let monthDayFormatter = dateFormatter(locale: locale, format: monthDayFormat)
        let daySuffixFormatter = dateFormatter(locale: locale, format: daySuffixFormat)

        return competitions.enumerated().map { index, competition in
            let year = CompetitionService.officialCompetitionYear(for: competition)
            let previousYear = index > 0
                ? CompetitionService.officialCompetitionYear(for: competitions[index - 1])
                : year
            let addressParts = compactAddressParts(for: competition, locale: locale)
            let addressCountry = addressParts.first ?? ""
            let addressRemainder = addressParts.dropFirst().map { ", \($0)" }.joined()
            let addressSource = competition.addressLinkSource
            let compactAddress = addressSource.projected(onto: addressCountry + addressRemainder)
            let venueAddress = addressSource.projected(onto: competition.venueLine)

            return CompetitionPreparedRow(
                competition: competition,
                rowIndex: index,
                competitionYear: year,
                showsYearSeparator: index > 0 && year != previousYear,
                name: competition.name,
                compactDisplayName: competition.compactDisplayName,
                flagEmoji: flagEmoji(for: competition.countryISO2),
                dateRangeText: dateRange(
                    for: competition,
                    calendar: calendar,
                    fullFormatter: fullFormatter,
                    monthDayFormatter: monthDayFormatter,
                    daySuffixFormatter: daySuffixFormatter
                ),
                locationLine: CompetitionService.parseAddress(competition.locationLine).displayText,
                venueLine: venueAddress.displayText,
                compactAddressCountry: addressCountry,
                compactAddress: compactAddress,
                venueAddress: venueAddress
            )
        }
    }

    nonisolated private static func dateFormatter(locale: Locale, format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter
    }

    nonisolated private static func dateRange(
        for competition: CompetitionSummary,
        calendar: Calendar,
        fullFormatter: DateFormatter,
        monthDayFormatter: DateFormatter,
        daySuffixFormatter: DateFormatter
    ) -> String {
        let sameYear = calendar.component(.year, from: competition.startDate)
            == calendar.component(.year, from: competition.endDate)
        let sameMonth = sameYear
            && calendar.component(.month, from: competition.startDate)
                == calendar.component(.month, from: competition.endDate)
        let sameDay = sameMonth
            && calendar.component(.day, from: competition.startDate)
                == calendar.component(.day, from: competition.endDate)
        if sameDay {
            return fullFormatter.string(from: competition.startDate)
        }
        if sameMonth {
            return "\(monthDayFormatter.string(from: competition.startDate)) - \(daySuffixFormatter.string(from: competition.endDate))"
        }
        return "\(fullFormatter.string(from: competition.startDate)) - \(fullFormatter.string(from: competition.endDate))"
    }

    nonisolated private static func compactAddressParts(
        for competition: CompetitionSummary,
        locale: Locale
    ) -> [String] {
        let countryName = locale.localizedString(forRegionCode: competition.countryISO2)
            ?? competition.countryISO2
        var parts = [countryName]
        if let localizedRegion = competition.localizedRegionLineOverride, !localizedRegion.isEmpty {
            let region = localizedRegion.components(separatedBy: "·").first ?? localizedRegion
            let regionParts = splitAddressComponent(region)
            if competition.usesCubingChinaDetailSource, regionParts.count >= 2 {
                parts.append(contentsOf: [regionParts[1], regionParts[0]] + Array(regionParts.dropFirst(2)))
            } else {
                parts.append(contentsOf: regionParts.filter {
                    $0.caseInsensitiveCompare(countryName) != .orderedSame
                })
            }
        } else {
            parts.append(contentsOf: splitAddressComponent(competition.city))
        }

        if let localizedAddress = competition.localizedAddressLineOverride, !localizedAddress.isEmpty {
            parts.append(contentsOf: splitAddressComponent(localizedAddress))
        } else if !competition.venue.isEmpty {
            parts.append(contentsOf: splitAddressComponent(competition.venue))
        } else {
            parts.append(contentsOf: splitAddressComponent(competition.venueAddress))
        }
        return deduplicated(parts)
    }

    nonisolated private static func splitAddressComponent(_ component: String) -> [String] {
        CompetitionService.parseAddress(component).displayText
            .replacingOccurrences(of: " · ", with: ",")
            .replacingOccurrences(of: "·", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated private static func deduplicated(_ parts: [String]) -> [String] {
        var seen = Set<String>()
        return parts.compactMap { part in
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    nonisolated private static func flagEmoji(for countryCode: String) -> String {
        guard countryCode.count == 2 else { return "" }
        let base: UInt32 = 127397
        let scalars = countryCode.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(base + $0.value)
        }
        return String(String.UnicodeScalarView(scalars))
    }
}

struct CompetitionBrowserView: View {
    private static let paginationProgressPublishInterval: TimeInterval = 1.0
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("competitionCardStyle") private var competitionCardStyle: String = CompetitionCardStyleOption.list.rawValue
    @AppStorage("competitionsBackgroundAppearanceData") private var competitionsBackgroundAppearanceData: Data?
    @AppStorage("competitionsBackgroundImageData") private var competitionsBackgroundImageData: Data?
    @AppStorage("competition_filter_region") private var storedRegionID: String = CompetitionRegionFilter.all.id
    @AppStorage("competition_filter_events") private var storedEventIDs: String = CompetitionEventFilter.selectableCases
        .map(\.rawValue)
        .sorted()
        .joined(separator: ",")
    @AppStorage("competition_filter_year") private var storedYearRawValue: String = CompetitionYearFilter.all.id
    @AppStorage("competition_filter_status") private var storedStatusRawValue: String = CompetitionStatusFilter.present.rawValue
    @AppStorage("competition_show_top_cubers") private var showsTopCubers: Bool = false
    @StateObject private var competitionLookupStore = CompetitionListLookupStore()
    @State private var publishedCompetitionListItems: [CompetitionListItem] = []
    @State private var competitionListLoadPhase: CompetitionListLoadPhase = .initialLoading
    @State private var competitionListDataRevision = 0
    @State private var competitionVisibleRowRevision = 0
    @State private var nextPage: Int? = 1
    @State private var loadedCompetitionCount = 0
    @State private var totalCompetitionCount: Int?
    @State private var showsMapView = false
    @StateObject private var filterPresentation = CompetitionFilterPresentation()
    @State private var isShowingSearch = false
    @State private var selectedCompetitionForDetail: CompetitionDetailSelection?
    @State private var selectedTopCuberProfile: CompetitionTopCuberProfileSelection?
    @State private var cubingRowClassesByKey: [String: String] = [:]
    @State private var showsRefreshSuccessBanner = false
    @State private var topCuberStatesByCompetitionID: [String: CompetitionTopCuberLoadState] = [:]
    @StateObject private var topCuberDisclosureStore = CompetitionTopCuberDisclosureStore()
    @State private var topCuberRefreshingIDs: Set<String> = []
    @State private var areCompetitionEventIconsReady = CompetitionEventIconFont.isAvailable
    @State private var compactStatusTapCompetitionID: String?
    @State private var addressTapCompetitionID: String?
    @State private var competitionsBackgroundAppearance = AppearanceConfiguration.defaultBackground
    @State private var decodedCompetitionsBackgroundImage: UIImage?
    @State private var activeLoadSignature: String?
    @State private var activeLoadID: UUID?
    @State private var competitionDateRevision = 0
    #if DEBUG
    @Environment(\.competitionBrowserPublicationEnabled) private var publicationAcceptanceEnabled
    @Environment(\.competitionBrowserPublicationScope) private var publicationAcceptanceScope
    #endif
    @State private var displayedFilterSignature: String?
    @State private var lastLoadedFilterSignature: String?
    @State private var lastLoadedFilterDate: Date?

    private let usesSystemBottomAccessory: Bool
    private let isActive: Bool
    @Binding private var isBottomAccessoryVisible: Bool
    @Binding private var searchRequestID: Int

    private var competitions: [CompetitionSummary] {
        get { competitionLookupStore.competitions }
        nonmutating set { competitionLookupStore.setCompetitions(newValue) }
    }

    private var visibleCompetitionsSnapshot: [CompetitionSummary] {
        get { competitionLookupStore.visibleCompetitionsSnapshot }
        nonmutating set { competitionLookupStore.setVisibleCompetitionsSnapshot(newValue) }
    }

    private var publishedVisibleCompetitions: [CompetitionSummary] {
        get { competitionLookupStore.publishedCompetitions }
        nonmutating set { competitionLookupStore.setPublishedCompetitions(newValue) }
    }

    init(
        usesSystemBottomAccessory: Bool = false,
        isActive: Bool = true,
        isBottomAccessoryVisible: Binding<Bool> = .constant(false),
        searchRequestID: Binding<Int> = .constant(0)
    ) {
        self.usesSystemBottomAccessory = usesSystemBottomAccessory
        self.isActive = isActive
        _isBottomAccessoryVisible = isBottomAccessoryVisible
        _searchRequestID = searchRequestID
    }

    @ViewBuilder var body: some View {
        #if DEBUG
        if CompetitionPhysicalBrowserAcceptance.enabled, !publicationAcceptanceEnabled {
            let _ = CompetitionPhysicalBrowserAcceptance.configure()
            CompetitionBrowserView(usesSystemBottomAccessory: usesSystemBottomAccessory, isActive: isActive,
                isBottomAccessoryVisible: $isBottomAccessoryVisible, searchRequestID: $searchRequestID)
                .environment(\.competitionBrowserPublicationEnabled, true)
        } else if CompetitionLongListAcceptance.enabled, isActive {
            CompetitionBrowserView(isActive: false)
        } else if CompetitionLongListAcceptance.enabled {
            normalCompetitionBody.task {
                guard publishedCompetitionListItems.isEmpty else { return }
                areCompetitionEventIconsReady = CompetitionEventIconFont.ensureRegistered()
                let values = CompetitionLongListAcceptance.summaries
                competitionLookupStore.setListSnapshot(values)
                publishedVisibleCompetitions = values
                publishPreparedCompetitionListItems(await makeCompetitionListItems(for: values))
                nextPage = nil; competitionListLoadPhase = .completed
            }
        } else if ProcessInfo.processInfo.arguments.contains("--competition-real-detail-acceptance") {
            CompetitionPublishedDetailAcceptanceSurface()
        } else if ProcessInfo.processInfo.arguments.contains("--competition-disclosure-acceptance") {
            CompetitionDisclosureAcceptanceSurface().navigationTitle("Competitions").navigationBarTitleDisplayMode(.large)
        } else if ProcessInfo.processInfo.arguments.contains("--competition-results-detail-acceptance") {
            NavigationLink("Open Results") { CompetitionResultsAcceptanceSurface() }
                .navigationTitle("Competitions")
        } else if ProcessInfo.processInfo.arguments.contains("--competition-results-acceptance") {
            CompetitionResultsAcceptanceSurface()
        } else if ProcessInfo.processInfo.arguments.contains("--competition-filter-acceptance"), isActive {
            CompetitionBrowserView(isActive: false)
        } else if ProcessInfo.processInfo.arguments.contains("--competition-filter-acceptance") {
            normalCompetitionBody.onAppear { competitionListLoadPhase = .completed }
        } else { normalCompetitionBody }
        #else
        normalCompetitionBody
        #endif
    }

    private var normalCompetitionBody: some View {
            // Loading and loaded surfaces have different root types. Keep
            // toolbar/popover ownership outside that conditional lifetime.
            ZStack { competitionListSurface }
            .background(competitionsTabBackgroundView.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if !usesSystemBottomAccessory && shouldShowCompetitionBottomAccessory {
                    competitionBottomSearchBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle(Text(localizedCompetitionStringInView(key: "tab.competitions", languageCode: appLanguage)))
            .compatibleNavigationSubtitle(Text(competitionNavigationSubtitle))
            .navigationBarTitleDisplayMode(.large)
            .background {
                if isActive {
                    CompetitionNavigationBarFontConfigurator(largeSubtitle: competitionNavigationSubtitle)
                }
            }
            .task(id: isActive) {
                guard isActive else { return }
                areCompetitionEventIconsReady = CompetitionEventIconFont.ensureRegistered()
            }
            .onAppear {
                updateBottomAccessoryVisibility()
                updateCompetitionsBackgroundAppearance()
                updateCompetitionsBackgroundImage()
                #if DEBUG
                if publicationAcceptanceEnabled { CompetitionBrowserPublicationAcceptance.filter = filterPresentation }
                #endif
            }
            .onDisappear {
                if usesSystemBottomAccessory {
                    isBottomAccessoryVisible = false
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    mapButton
                    filterButton
                }
            }
            .task(id: "\(isActive)|\(appLanguage)") {
                guard isActive else { return }
                await CompetitionService.warmRecognizedCountriesCache()
                do {
                    try await Task.sleep(nanoseconds: 700_000_000)
                } catch {
                    return
                }
                guard isActive, !Task.isCancelled else { return }
                let rowClasses = await fetchCubingRowClasses(languageCode: appLanguage)
                guard isActive, !Task.isCancelled, cubingRowClassesByKey != rowClasses else { return }
                cubingRowClassesByKey = rowClasses
            }
            .onChange(of: cubingRowClassesByKey) { _ in
                let signature = filterSignature
                Task {
                    await publishVisibleCompetitionsSnapshot(expectedSignature: signature)
                }
            }
            .onChange(of: showsTopCubers) { _ in
                if !showsTopCubers {
                    topCuberStatesByCompetitionID = [:]
                    topCuberDisclosureStore.reset()
                    topCuberRefreshingIDs = []
                }
            }
            .onChange(of: competitionCardStyle) { _ in
                updateCompetitionsBackgroundImage()
            }
            .onChange(of: competitionsBackgroundAppearanceData) { _ in
                updateCompetitionsBackgroundAppearance()
                updateCompetitionsBackgroundImage()
            }
            .onChange(of: competitionsBackgroundImageData) { _ in
                updateCompetitionsBackgroundImage()
            }
            .onChange(of: searchRequestID) { _ in
                guard usesSystemBottomAccessory else { return }
                isShowingSearch = true
            }
            .task(id: "\(isActive)|\(filterSignature)") {
                guard isActive else { return }
                await loadCompetitions()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                competitionDateRevision &+= 1
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                competitionDateRevision &+= 1
            }
            #if DEBUG
            .onReceive(CompetitionBrowserPublicationAcceptance.refreshRequests) { _ in
                guard publicationAcceptanceEnabled else { return }
                Task { await refreshCompetitionsForPullToRefresh() }
            }
            .preference(key: CompetitionBrowserPublicationKey.self, value: CompetitionBrowserPublicationSnapshot(
                revision: competitionListDataRevision, signature: filterSignature, ids: publishedVisibleCompetitions.map(\.id),
                sourceIDs: competitions.map(\.id),
                preparedIDs: publishedCompetitionListItems.compactMap {
                    if case .competition(let row) = $0 { return row.id }; return nil
                }, isActive: isActive,
                phase: String(describing: competitionListLoadPhase)))
            #endif
            .compatibleNavigationDestination(isPresented: $showsMapView) {
                competitionMapDestination
            }
            .compatibleNavigationDestination(isPresented: $isShowingSearch) {
                CompetitionSearchView(
                    competitionsProvider: { competitionLookupStore.publishedCompetitions },
                    competitionProvider: { competitionLookupStore.competition(id: $0) },
                    appLanguage: appLanguage
                )
            }
            .compatibleNavigationDestination(item: $selectedCompetitionForDetail) { selection in
                if let competition = competitionLookupStore.competition(id: selection.id) {
                    CompetitionDetailView(
                        competition: competition,
                        appLanguage: appLanguage
                    )
                } else {
                    competitionDetailMissingView
                }
            }
            .competitionTopCuberProfileDestination(selection: $selectedTopCuberProfile)
    }

    private var competitionsTabBackgroundView: some View {
        let usesGlassStyle = CompetitionCardStyleOption(rawValue: competitionCardStyle) == .glass

        guard usesGlassStyle else {
            return AnyView(Color.clear)
        }

        switch competitionsBackgroundAppearance.style {
        case .system:
            return AnyView(Color.clear)
        case .color:
            return AnyView(competitionsBackgroundAppearance.color(for: colorScheme))
        case .gradient:
            let gradient = competitionsBackgroundAppearance.gradient(for: colorScheme)
            return AnyView(
                LinearGradient(
                    gradient: Gradient(stops: gradient.resolvedStops),
                    startPoint: competitionsGradientStartPoint(angle: gradient.angle),
                    endPoint: competitionsGradientEndPoint(angle: gradient.angle)
                )
            )
        case .photo:
            #if os(iOS)
            if let image = decodedCompetitionsBackgroundImage {
                return AnyView(
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                )
            }
            #endif
            return AnyView(Color.clear)
        }
    }

    private func updateCompetitionsBackgroundAppearance() {
        let decoded = AppearanceConfiguration.decode(
            from: competitionsBackgroundAppearanceData,
            fallback: .defaultBackground
        )
        if competitionsBackgroundAppearance != decoded {
            competitionsBackgroundAppearance = decoded
        }
    }

    private func updateCompetitionsBackgroundImage() {
        let usesGlassStyle = CompetitionCardStyleOption(rawValue: competitionCardStyle) == .glass
        guard usesGlassStyle,
              competitionsBackgroundAppearance.style == .photo,
              let data = competitionsBackgroundImageData else {
            decodedCompetitionsBackgroundImage = nil
            return
        }

        decodedCompetitionsBackgroundImage = UIImage(data: data)
    }

    private func competitionsGradientStartPoint(angle: Double) -> UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 - cos(radians) * 0.5, y: 0.5 - sin(radians) * 0.5)
    }

    private func competitionsGradientEndPoint(angle: Double) -> UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 + cos(radians) * 0.5, y: 0.5 + sin(radians) * 0.5)
    }

    private var selectedRegion: CompetitionRegionFilter {
        get { CompetitionRegionFilter(storedID: storedRegionID) ?? .all }
        nonmutating set { storedRegionID = newValue.id }
    }

    private var selectedEvents: Set<CompetitionEventFilter> {
        get {
            let restored = Set(
                storedEventIDs
                    .split(separator: ",")
                    .compactMap { CompetitionEventFilter(rawValue: String($0)) }
            )
            let allEvents = Set(CompetitionEventFilter.selectableCases)
            let preFTOAllEvents = allEvents.subtracting([.faceTurningOctahedron])
            if restored == preFTOAllEvents {
                return allEvents
            }
            return restored.isEmpty ? allEvents : restored
        }
        nonmutating set {
            let normalized = newValue.isEmpty ? Set(CompetitionEventFilter.selectableCases) : newValue
            storedEventIDs = normalized.map(\.rawValue).sorted().joined(separator: ",")
        }
    }

    private var selectedYear: CompetitionYearFilter {
        get { CompetitionYearFilter(storedID: storedYearRawValue) }
        nonmutating set { storedYearRawValue = newValue.id }
    }

    private var selectedStatus: CompetitionStatusFilter {
        get {
            if let status = CompetitionStatusFilter(rawValue: storedStatusRawValue) {
                return status
            }
            switch storedStatusRawValue {
            case "ended":
                return .past
            case "upcoming", "registrationNotOpenYet", "registrationOpen", "waitlist", "ongoing":
                return .present
            default:
                return .present
            }
        }
        nonmutating set { storedStatusRawValue = newValue.rawValue }
    }

    private var availablePastYears: [Int] {
        Set(competitions.map { CompetitionService.officialCompetitionYear(for: $0) })
            .sorted(by: >)
    }

    private var filterButton: some View {
        Button {
            filterPresentation.open()
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .accessibilityIdentifier("competition-filter")
        .competitionFilterPopover(presentation: filterPresentation) { showsFilterPopover in
        CompetitionFiltersPopover(
            selectedRegion: Binding(
                get: { selectedRegion },
                set: { selectedRegion = $0 }
            ),
            selectedEvents: Binding(
                get: { selectedEvents },
                set: { selectedEvents = $0 }
            ),
            selectedYear: Binding(
                get: { selectedYear },
                set: { selectedYear = $0 }
            ),
            selectedStatus: Binding(
                get: { selectedStatus },
                set: { selectedStatus = $0 }
            ),
            availablePastYears: availablePastYears,
            showsTopCubers: $showsTopCubers,
            appLanguage: appLanguage,
            showsFilterPopover: showsFilterPopover
        )
        .compatibleClearPresentationBackground()
        .compatiblePopoverCompactAdaptation()
        }
    }

    private var mapButton: some View {
        Button {
            showsMapView = true
        } label: {
            Image(systemName: "map")
        }
    }

    @ViewBuilder
    private var competitionMapDestination: some View {
        if #available(iOS 17.0, *) {
            CompetitionMapView(
                query: competitionQuery,
                appLanguage: appLanguage
            )
        } else {
            VStack(spacing: 12) {
                Image(systemName: "map")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(localizedCompetitionStringInView(key: "competitions.map_title", languageCode: appLanguage))
                    .font(.system(size: 18, weight: .semibold))
                Text("iOS 17+")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var competitionDetailMissingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(localizedCompetitionStringInView(key: "competitions.detail.unavailable", languageCode: appLanguage))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var competitionListSurface: some View {
        if publishedCompetitionListItems.isEmpty {
            List {
                if competitionListLoadPhase == .initialLoading {
                    competitionLoadingSkeletonRows
                } else {
                    switch competitionListLoadPhase {
                    case .rateLimited:
                        rateLimitStatusRow
                    case .failed(let message):
                        errorRow(message: message)
                    case .initialLoading, .loadingMore:
                        loadingMoreRow
                    case .completed:
                        emptyRow
                    }
                }
            }
            .listStyle(.plain)
            .compatibleScrollContentBackgroundHidden()
        } else {
            CompetitionVirtualizedList(
                items: publishedCompetitionListItems,
                dataRevision: competitionListDataRevision,
                querySignature: filterSignature,
                presentationSignature: competitionListPresentationSignature,
                footerState: competitionVirtualizedFooterState,
                backgroundColor: .clear,
                rowContent: { item in
                    AnyView(competitionVirtualizedListItem(item))
                },
                footerContent: { state in
                    AnyView(competitionVirtualizedFooter(state))
                },
                onRefresh: {
                    await refreshCompetitionsForPullToRefresh()
                }, observesPublication: publicationAcceptanceIsEnabled
            )
            #if DEBUG
            .scopedPublication(publicationAcceptanceScope)
            #endif
            .competitionSystemChromeUnderlap()
            .overlay(alignment: .topLeading) {
                if showsRefreshSuccessBanner {
                    refreshSuccessOverlay
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private var competitionListPresentationSignature: String {
        [
            competitionCardStyle,
            colorScheme == .dark ? "dark" : "light",
            appLanguage,
            areCompetitionEventIconsReady ? "icons" : "no-icons",
            showsTopCubers ? "top-cubers" : "no-top-cubers",
            String(competitionVisibleRowRevision)
        ].joined(separator: "|")
    }

    private var competitionVirtualizedFooterState: CompetitionVirtualizedFooterState {
        switch competitionListLoadPhase {
        case .initialLoading, .loadingMore:
            return .loading
        case .rateLimited:
            return .rateLimited
        case .failed(let message):
            return .failed(message)
        case .completed:
            return .completed
        }
    }

    @ViewBuilder
    private func competitionVirtualizedListItem(_ item: CompetitionListItem) -> some View {
        switch item {
        case .year(let year):
            competitionYearSeparator(year)
                .padding(.horizontal, 16)
        case .competition(let row):
            let cardStyle = CompetitionCardStyleOption(rawValue: competitionCardStyle) ?? .list
            competitionListRow(row, rowIndex: row.rowIndex)
                .padding(.horizontal, cardStyle == .compact ? 8 : 16)
                .padding(.vertical, cardStyle == .compact ? 0 : 4)
                .overlay(alignment: .bottom) {
                    if cardStyle == .list {
                        Divider()
                    }
                }
        }
    }

    @ViewBuilder
    private func competitionVirtualizedFooter(_ state: CompetitionVirtualizedFooterState) -> some View {
        switch state {
        case .loading:
            loadingMoreContent
        case .rateLimited:
            rateLimitStatusContent
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .center)
        case .failed(let message):
            errorContent(message: message)
        case .completed:
            Text(
                appLocalizedString(
                    "competitions.no_more",
                    languageCode: appLanguage,
                    defaultValue: "No more competitions"
                )
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var refreshSuccessOverlay: some View {
        Text(localizedCompetitionStringInView(key: "competitions.refresh_success", languageCode: appLanguage))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            .padding(.leading, 16)
            .padding(.top, 4)
    }

    private var competitionNavigationSubtitle: String {
        if competitionListLoadPhase == .initialLoading,
           loadedCompetitionCount == 0,
           publishedVisibleCompetitions.isEmpty {
            return localizedCompetitionStringInView(
                key: "competitions.loading",
                languageCode: appLanguage
            )
        }
        let presentation = CompetitionService.listCountPresentation(
            loadedCount: loadedCompetitionCount,
            visibleCount: publishedVisibleCompetitions.count,
            totalCount: totalCompetitionCount,
            hasPendingPages: nextPage != nil && competitionListLoadPhase != .completed
        )
        switch presentation {
        case .progress(let loaded, let total):
            return String(
                format: localizedCompetitionStringInView(
                    key: "competitions.loading_progress_format",
                    languageCode: appLanguage
                ),
                loaded,
                total
            )
        case .count(let count):
            return String(
                format: localizedCompetitionStringInView(
                    key: "competitions.count_format",
                    languageCode: appLanguage
                ),
                count
            )
        }
    }

    private var filterSignature: String {
        [
            selectedRegion.id,
            selectedEvents
                .map(\.rawValue)
                .sorted()
                .joined(separator: ","),
            selectedStatus == .past ? selectedYear.id : CompetitionYearFilter.all.id,
            selectedStatus.rawValue,
            appLanguage,
            competitionDateWindow?.key(status: selectedStatus, year: selectedYear) ?? "invalid-date"
        ].joined(separator: "|")
    }

    private var competitionQuery: CompetitionQuery {
        CompetitionQuery(
            languageCode: appLanguage,
            region: selectedRegion,
            events: selectedEvents,
            year: selectedStatus == .past ? selectedYear : .all,
            status: selectedStatus,
            dateWindow: competitionDateWindow
        )
    }

    private var competitionDateWindow: CompetitionDateWindow? {
        // Reading this revision makes civil-day/timezone notifications invalidate
        // the query identity even when no other Browser state has changed.
        _ = competitionDateRevision
        #if DEBUG
        if publicationAcceptanceEnabled, let now = CompetitionBrowserPublicationAcceptance.now { return CompetitionDateWindow(now: now()) }
        #endif
        return CompetitionDateWindow(now: Date())
    }

    private var shouldShowCompetitionBottomAccessory: Bool {
        !publishedCompetitionListItems.isEmpty
    }

    private var competitionBottomSearchBar: some View {
        CompetitionBottomSearchBar(
            languageCode: appLanguage,
            usesContainerGlass: true
        ) {
            isShowingSearch = true
        }
    }

    private func updateBottomAccessoryVisibility() {
        guard usesSystemBottomAccessory else { return }
        isBottomAccessoryVisible = shouldShowCompetitionBottomAccessory
    }

    private var competitionLoadingSkeletonRows: some View {
        ForEach(0..<6, id: \.self) { _ in
            competitionSkeletonRow
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    private var competitionSkeletonRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.competitionSkeletonFill)
                        .frame(width: 220, height: 20)
                        .competitionSkeletonBreathing()

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.competitionSkeletonFill)
                        .frame(width: 132, height: 16)
                        .competitionSkeletonBreathing()

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.competitionSkeletonFill)
                        .frame(width: 164, height: 16)
                        .competitionSkeletonBreathing()
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    Capsule()
                        .fill(.competitionSkeletonFill)
                        .frame(width: 72, height: 28)
                        .competitionSkeletonBreathing()

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.competitionSkeletonFill)
                        .frame(width: 56, height: 14)
                        .competitionSkeletonBreathing()
                }
            }
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.competitionSkeletonFill)
                .frame(width: 188, height: 16)
                .competitionSkeletonBreathing()
        }
        .padding(.vertical, 8)
        .redacted(reason: .placeholder)
    }

    private var emptyRow: some View {
        Text(localizedCompetitionStringInView(key: "competitions.empty", languageCode: appLanguage))
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.vertical, 24)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private var loadingMoreRow: some View {
        loadingMoreContent
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .center)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var loadingMoreContent: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.9)
            Text(localizedCompetitionStringInView(key: "competitions.loading", languageCode: appLanguage))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var rateLimitStatusRow: some View {
        rateLimitStatusContent
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private var rateLimitStatusContent: some View {
        Text(
            appLocalizedString(
                "competitions.rate_limited",
                languageCode: appLanguage,
                defaultValue: "WCA request limit reached. Loading will resume shortly."
            )
        )
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func errorRow(message: String) -> some View {
        errorContent(message: message)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func errorContent(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            Button(localizedCompetitionStringInView(key: "wca.results_retry", languageCode: appLanguage)) {
                Task {
                    await loadCompetitions()
                }
            }
            .font(.system(size: 16, weight: .semibold))
        }
        .padding(.vertical, 18)
    }

    private var refreshSuccessRow: some View {
        Text(localizedCompetitionStringInView(key: "competitions.refresh_success", languageCode: appLanguage))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 30)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private func competitionRow(_ row: CompetitionRowModel, rowIndex: Int) -> some View {
        switch CompetitionCardStyleOption(rawValue: competitionCardStyle) ?? .list {
        case .list:
            listCompetitionRow(row)
        case .glass:
            glassCompetitionRow(row)
        case .compact:
            compactCompetitionRow(row, rowIndex: rowIndex)
        }
    }

    private func compactCompetitionRow(_ row: CompetitionRowModel, rowIndex: Int) -> some View {
        ZStack(alignment: .leading) {
            if !rowIndex.isMultiple(of: 2) {
                Rectangle()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    compactCompetitionTitle(row)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                    Spacer(minLength: 4)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        CompetitionCompactStatusButton(
                            symbolName: compactRegistrationStatusSymbol(for: row.compactStatus),
                            tintColor: UIColor(compactRegistrationStatusColor(for: row.compactStatus)),
                            accessibilityLabel: compactRegistrationStatusAccessibilityTitle(for: row.compactStatus),
                            message: row.compactStatusMessage,
                            onTap: {
                                compactStatusTapCompetitionID = row.id
                                DispatchQueue.main.async {
                                    if compactStatusTapCompetitionID == row.id {
                                        compactStatusTapCompetitionID = nil
                                    }
                                }
                            }
                        )
                            .frame(width: 28, height: 28, alignment: .center)
                            .contentShape(Rectangle())

                        Text(row.dateRangeText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary.opacity(0.78))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }

                CompetitionAddressText(
                    address: row.compactAddress,
                    competitionID: row.id,
                    tappedCompetitionID: $addressTapCompetitionID,
                    emphasizedPrefix: row.compactAddressCountry,
                    emphasizedPrefixFont: .caption.weight(.semibold)
                )
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.12))
                .frame(width: 0.5)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.12))
                .frame(width: 0.5)
        }
        .overlay(alignment: .bottom) {
            compactRowHorizontalSeparator
        }
        .overlay(alignment: .top) {
            if row.rowIndex == 0 || row.showsYearSeparator {
                compactRowHorizontalSeparator
            }
        }
    }

    private func compactCompetitionTitle(_ row: CompetitionRowModel) -> Text {
        guard !row.flagEmoji.isEmpty else {
            return Text(row.compactDisplayName)
                .font(.subheadline.weight(.semibold))
        }
        return Text(row.flagEmoji)
            .font(.system(size: 15))
            + Text(" " + row.compactDisplayName)
            .font(.subheadline.weight(.semibold))
    }

    private var compactRowHorizontalSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.12))
            .frame(height: 0.5)
    }

    private func competitionYearSeparator(_ year: Int) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 0.5)
            Text(String(year))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 0.5)
        }
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func listCompetitionRow(_ row: CompetitionRowModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(row.flagEmoji)
                            .font(.system(size: 18))
                        Text(row.name)
                            .font(.system(size: 18, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .competitionDisclosureTitleProbe(row.id)
                    }

                    Text(row.dateRangeText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(row.locationLine)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    statusBadge(title: row.statusBadgeTitle, tint: row.statusTint)

                    if let competitorLimit = row.competitorLimit {
                        Text(String(format: localizedCompetitionStringInView(key: "competitions.competitor_limit_format", languageCode: appLanguage), competitorLimit))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { openCompetitionRowIfNeeded(row, cardStyle: .list) }
            .accessibilityAction { openCompetitionRowIfNeeded(row, cardStyle: .list) }

            if !row.venueLine.isEmpty {
                CompetitionAddressText(
                    address: row.venueAddress,
                    competitionID: row.id,
                    tappedCompetitionID: $addressTapCompetitionID
                )
                    .font(.system(size: 15, weight: .regular))
                    .fixedSize(horizontal: false, vertical: true)
                    .competitionDisclosureTitleProbe("\(row.id)|venue")
                    .padding(.top, 8)
                    .onTapGesture { openCompetitionRowIfNeeded(row, cardStyle: .list) }
            }

            if showsTopCubers {
                competitionTopCubersContent(for: row.id)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func glassCompetitionRow(_ row: CompetitionRowModel) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(row.flagEmoji)
                                .font(.system(size: 18))
                            Text(row.name)
                                .font(.system(size: 18, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                                .competitionDisclosureTitleProbe(row.id)
                        }

                        Text(row.dateRangeText)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(row.locationLine)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 8) {
                        statusBadge(title: row.statusBadgeTitle, tint: row.statusTint)

                        if let competitorLimit = row.competitorLimit {
                            Text(String(format: localizedCompetitionStringInView(key: "competitions.competitor_limit_format", languageCode: appLanguage), competitorLimit))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                            }
                    }
                }
                .padding(.trailing, 18)

                if !row.venueLine.isEmpty {
                    CompetitionAddressText(
                        address: row.venueAddress,
                        competitionID: row.id,
                        tappedCompetitionID: $addressTapCompetitionID
                    )
                        .font(.system(size: 15, weight: .regular))
                        .fixedSize(horizontal: false, vertical: true)
                        .competitionDisclosureTitleProbe("\(row.id)|venue")
                        .padding(.top, 8)
                }

                if showsTopCubers {
                    competitionTopCubersContent(for: row.id)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CompetitionCardSurfaceModifier(isGlass: true, shape: shape))
        .modifier(CompetitionListRowBackgroundModifier(isGlass: true, shape: shape))
    }

    @ViewBuilder
    private func competitionTopCubersContent(for competitionID: String) -> some View {
        if let competition = competitionForRow(id: competitionID) {
            CompetitionLoadedTopCubers(competition: competition, language: appLanguage,
                initial: topCuberStatesByCompetitionID[competitionID] ?? .idle,
                topSpacing: 8,
                onState: { state in
                    guard topCuberStatesByCompetitionID[competitionID] != state else { return }
                    topCuberStatesByCompetitionID[competitionID] = state
                    storeCompetitionRuntimeSnapshot()
                }, cache: topCubersAcceptanceCache, fetch: topCubersAcceptanceFetch) { previews in
                    Divider()
                    competitionTopCubersSection(previews: previews, competitionID: competitionID)
                } placeholder: {
                    Divider()
                    competitionTopCubersSkeletonSection
                }.id(competitionID)
        }
    }

    private var topCubersAcceptanceCache: ((String) async -> [CompetitionTopCuberPreview]?)? {
        #if DEBUG
        if CompetitionPhysicalBrowserAcceptance.enabled { return { id in await CompetitionPhysicalBrowserAcceptance.cached(id) } }
        guard CompetitionLongListAcceptance.enabled else { return nil }
        return { id in await CompetitionLongListAcceptance.cached(id) }
        #else
        return nil
        #endif
    }
    private var topCubersAcceptanceFetch: ((CompetitionSummary, String) async -> [CompetitionTopCuberPreview]?)? {
        #if DEBUG
        if CompetitionPhysicalBrowserAcceptance.enabled { return { competition, _ in await CompetitionPhysicalBrowserAcceptance.fetched(competition) } }
        guard CompetitionLongListAcceptance.enabled else { return nil }
        return { competition, language in await CompetitionLongListAcceptance.fetched(competition, language) }
        #else
        return nil
        #endif
    }

    @ViewBuilder
    private func competitionTopCubersSection(previews: [CompetitionTopCuberPreview], competitionID: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizedCompetitionStringInView(key: "competitions.top_cubers", languageCode: appLanguage))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .competitionDisclosureTitleProbe("\(competitionID)|top-heading")
                .onTapGesture { selectedCompetitionForDetail = CompetitionDetailSelection(id: competitionID) }

            CompetitionPersistentTopCubers(previews: previews, language: appLanguage,
                disclosure: topCuberDisclosureStore.disclosure(for: competitionID), traceIdentity: competitionID) { preview in
                topCuberChip(for: preview)
            }
            .competitionSizeDebug("section available", color: .blue)
        }
    }

    @ViewBuilder
    private func topCuberChip(for preview: CompetitionTopCuberPreview) -> some View {
        CompetitionTopCuberProfileChip(preview: preview, language: appLanguage,
            iconsReady: areCompetitionEventIconsReady) { selectedTopCuberProfile = $0 }
    }

    private var competitionTopCubersSkeletonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizedCompetitionStringInView(key: "competitions.top_cubers", languageCode: appLanguage))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<2, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.competitionSkeletonFill)
                        .frame(width: index == 0 ? 188 : 172, height: 34)
                        .competitionSkeletonBreathing()
                }
            }
        }
    }

    @ViewBuilder
    private func competitionListItem(_ item: CompetitionListItem) -> some View {
        switch item {
        case .year(let year):
            competitionYearSeparator(year)
        case .competition(let row):
            competitionListRow(row, rowIndex: row.rowIndex)
        }
    }

    @ViewBuilder
    private func competitionListRow(_ rowModel: CompetitionRowModel, rowIndex: Int) -> some View {
        let cardStyle = CompetitionCardStyleOption(rawValue: competitionCardStyle) ?? .list
        if cardStyle == .compact {
            compactCompetitionRow(rowModel, rowIndex: rowIndex)
                .contentShape(Rectangle())
                .onTapGesture {
                    openCompetitionRowIfNeeded(rowModel, cardStyle: cardStyle)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else {
            competitionListRowBase(rowModel, rowIndex: rowIndex, cardStyle: cardStyle)
        }
    }

    private func competitionListRowBase(
        _ rowModel: CompetitionRowModel,
        rowIndex: Int,
        cardStyle: CompetitionCardStyleOption
    ) -> some View {
        Group {
            if cardStyle == .glass {
                Button { openCompetitionRowIfNeeded(rowModel, cardStyle: cardStyle) } label: {
                    competitionRow(rowModel, rowIndex: rowIndex)
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("competition-card-\(rowModel.id)")
            } else {
                competitionRow(rowModel, rowIndex: rowIndex)
            }
        }
        .listRowInsets(EdgeInsets(top: cardStyle == .compact ? 0 : 4, leading: cardStyle == .compact ? 8 : 16, bottom: cardStyle == .compact ? 0 : 4, trailing: cardStyle == .compact ? 8 : 16))
        .listRowSeparator(cardStyle == .glass || cardStyle == .compact ? .hidden : .visible)
        .listRowBackground(Color.clear)
    }

    private func openCompetitionRowIfNeeded(
        _ rowModel: CompetitionRowModel,
        cardStyle: CompetitionCardStyleOption
    ) {
        if addressTapCompetitionID == rowModel.id {
            addressTapCompetitionID = nil
            return
        }
        if cardStyle == .compact, compactStatusTapCompetitionID == rowModel.id {
            compactStatusTapCompetitionID = nil
            return
        }
        selectedCompetitionForDetail = CompetitionDetailSelection(id: rowModel.id)
    }

    private func competitionForRow(id: String) -> CompetitionSummary? {
        competitionLookupStore.competition(id: id)
    }

    private func statusBadge(for status: CompetitionAvailabilityStatus, competition: CompetitionSummary, languageCode: String) -> some View {
        let badgeColor = statusColor(for: status, competition: competition)
        return Text(statusBadgeTitle(for: status, competition: competition, languageCode: languageCode))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(badgeColor.opacity(0.12), in: Capsule())
    }

    private func statusBadge(title: String, tint: CompetitionRowStatusTint) -> some View {
        let badgeColor = tint.color
        return Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(badgeColor.opacity(0.12), in: Capsule())
    }

    private func statusBadgeTitle(for status: CompetitionAvailabilityStatus, competition: CompetitionSummary, languageCode: String) -> String {
        statusBadgeTitle(
            for: status,
            competition: competition,
            rowClass: cubingRowClass(for: competition),
            languageCode: languageCode
        )
    }

    private func statusBadgeTitle(
        for status: CompetitionAvailabilityStatus,
        competition: CompetitionSummary,
        rowClass: String?,
        languageCode: String
    ) -> String {
        if let rowClass {
            switch rowClass {
            case "info":
                if let waitlistStart = competition.localizedWaitlistStartOverride, Date() < waitlistStart {
                    let days = daysUntil(waitlistStart)
                    return String(
                        format: localizedCompetitionStringInView(
                            key: "competitions.status.waitlist_in_format",
                            languageCode: languageCode
                        ),
                        days
                    )
                }
                return CompetitionAvailabilityStatus.upcoming.localizedTitle(languageCode: languageCode)
            case "danger":
                if let waitlistStart = competition.localizedWaitlistStartOverride, Date() >= waitlistStart {
                    return localizedCompetitionStringInView(
                        key: "competitions.status.waitlist_open",
                        languageCode: languageCode
                    )
                }
                return CompetitionAvailabilityStatus.registrationOpen.localizedTitle(languageCode: languageCode)
            default:
                break
            }
        }

        switch status {
        case .registrationNotOpenYet:
            let days = daysUntil(competition.localizedRegistrationStartOverride)
            return String(
                format: localizedCompetitionStringInView(
                    key: "competitions.status.registration_not_open_yet_in_format",
                    languageCode: languageCode
                ),
                days
            )
        case .upcoming:
            if let waitlistStart = competition.localizedWaitlistStartOverride, Date() < waitlistStart {
                let days = daysUntil(waitlistStart)
                return String(
                    format: localizedCompetitionStringInView(
                        key: "competitions.status.waitlist_in_format",
                        languageCode: languageCode
                    ),
                    days
                )
            }
            return status.localizedTitle(languageCode: languageCode)
        case .waitlist:
            if let waitlistStart = competition.localizedWaitlistStartOverride, Date() < waitlistStart {
                let days = daysUntil(waitlistStart)
                return String(
                    format: localizedCompetitionStringInView(
                        key: "competitions.status.waitlist_in_format",
                        languageCode: languageCode
                        ),
                        days
                    )
                }
            return localizedCompetitionStringInView(
                key: "competitions.status.waitlist_open",
                languageCode: languageCode
            )
        default:
            return status.localizedTitle(languageCode: languageCode)
        }
    }

    private func daysUntil(_ date: Date?) -> Int {
        guard let date else { return 0 }
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return max(calendar.dateComponents([.day], from: now, to: target).day ?? 0, 0)
    }

    private func daysUntil(_ date: Date) -> Int {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return max(calendar.dateComponents([.day], from: now, to: target).day ?? 0, 0)
    }

    private func compactRegistrationDisplayStatus(for competition: CompetitionSummary) -> CompactRegistrationDisplayStatus {
        compactRegistrationDisplayStatus(
            for: competition,
            availabilityStatus: competitionAvailabilityStatus(for: competition)
        )
    }

    private func compactRegistrationDisplayStatus(
        for competition: CompetitionSummary,
        availabilityStatus status: CompetitionAvailabilityStatus
    ) -> CompactRegistrationDisplayStatus {
        let now = Date()

        if !competition.usesCubingChinaDetailSource {
            switch competition.registrationStatus {
            case .open:
                return .open
            case .full:
                return .limitReached
            case .notYetOpened:
                return .notOpenYet
            case .past:
                return .closed
            case .none:
                break
            }
        }

        switch status {
        case .registrationOpen:
            return .open
        case .waitlist:
            return competition.usesCubingChinaDetailSource ? .limitReached : .open
        case .registrationNotOpenYet:
            return .notOpenYet
        case .ended, .ongoing:
            return .closed
        case .upcoming:
            let registrationOpenDate = competition.localizedRegistrationStartOverride ?? competition.registrationOpen
            if let registrationOpenDate, registrationOpenDate > now {
                return .notOpenYet
            }
            if let registrationClose = competition.registrationClose, registrationClose < now {
                return .closed
            }
            return .notOpenYet
        }
    }

    private func compactRegistrationStatusSymbol(for status: CompactRegistrationDisplayStatus) -> String {
        switch status {
        case .open:
            if #available(iOS 26.0, *) {
                return "person.badge.plus.fill"
            }
            return "person.fill.badge.plus"
        case .closed:
            return "person.fill.xmark"
        case .limitReached:
            return "person.badge.clock.fill"
        case .notOpenYet:
            return "clock.fill"
        }
    }

    private func compactRegistrationStatusColor(for status: CompactRegistrationDisplayStatus) -> Color {
        switch status {
        case .open:
            return Color(uiColor: .systemGreen).opacity(colorScheme == .dark ? 0.86 : 0.76)
        case .closed:
            return Color(uiColor: .systemRed).opacity(colorScheme == .dark ? 0.86 : 0.76)
        case .limitReached:
            return Color(uiColor: .systemOrange).opacity(colorScheme == .dark ? 0.90 : 0.80)
        case .notOpenYet:
            return Color(uiColor: .systemBlue).opacity(colorScheme == .dark ? 0.86 : 0.76)
        }
    }

    private func compactRegistrationStatusAccessibilityTitle(for status: CompactRegistrationDisplayStatus) -> String {
        switch status {
        case .open:
            return localizedCompetitionStringInView(key: "competitions.registration.open", languageCode: appLanguage)
        case .closed:
            return localizedCompetitionStringInView(key: "competitions.registration.closed", languageCode: appLanguage)
        case .limitReached:
            return localizedCompetitionStringInView(key: "competitions.registration.full_short", languageCode: appLanguage)
        case .notOpenYet:
            return localizedCompetitionStringInView(key: "competitions.registration.not_open_yet", languageCode: appLanguage)
        }
    }

    private func compactRegistrationStatusMessage(
        for status: CompactRegistrationDisplayStatus,
        competition: CompetitionSummary
    ) -> String {
        switch status {
        case .open:
            return localizedCompetitionStringInView(key: "competitions.registration.open_message", languageCode: appLanguage)
        case .limitReached:
            return localizedCompetitionStringInView(key: "competitions.registration.full_message", languageCode: appLanguage)
        case .notOpenYet:
            let registrationOpenDate = competition.localizedRegistrationStartOverride ?? competition.registrationOpen
            if let registrationOpenDate, registrationOpenDate > Date() {
                return String(
                    format: localizedCompetitionStringInView(
                        key: "competitions.registration.will_open_format",
                        languageCode: appLanguage
                    ),
                    compactRelativeTimeDescription(until: registrationOpenDate)
                )
            }
            return localizedCompetitionStringInView(key: "competitions.registration.details_unavailable", languageCode: appLanguage)
        case .closed:
            let now = Date()
            if competition.endDate < Calendar.current.startOfDay(for: now) {
                return localizedCompetitionStringInView(key: "competitions.registration.closed_ended", languageCode: appLanguage)
            }
            if competition.startDate <= now {
                return localizedCompetitionStringInView(key: "competitions.registration.closed_started", languageCode: appLanguage)
            }
            return String(
                format: localizedCompetitionStringInView(
                    key: "competitions.registration.closed_starts_format",
                    languageCode: appLanguage
                ),
                compactRelativeTimeDescription(until: competition.startDate)
            )
        }
    }

    private func compactRelativeTimeDescription(until date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = appLocale(for: appLanguage)
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    private func compactAddressParts(for competition: CompetitionSummary) -> [String] {
        let countryName = appLocale(for: appLanguage).localizedString(forRegionCode: competition.countryISO2) ?? competition.countryISO2
        var parts = [countryName]
        parts.append(contentsOf: compactLocationParts(for: competition, countryName: countryName))
        parts.append(contentsOf: compactVenueParts(for: competition))
        return compactDeduplicatedParts(parts)
    }

    private func compactLocationParts(for competition: CompetitionSummary, countryName: String) -> [String] {
        if let localizedRegionLine = competition.localizedRegionLineOverride, !localizedRegionLine.isEmpty {
            let region = localizedRegionLine.components(separatedBy: "·").first ?? localizedRegionLine
            let regionParts = compactSplitAddressComponent(region)
            if competition.usesCubingChinaDetailSource, regionParts.count >= 2 {
                return [regionParts[1], regionParts[0]] + Array(regionParts.dropFirst(2))
            }
            return regionParts.filter { $0.caseInsensitiveCompare(countryName) != .orderedSame }
        }

        return compactSplitAddressComponent(competition.city)
    }

    private func compactVenueParts(for competition: CompetitionSummary) -> [String] {
        if let localizedAddressLine = competition.localizedAddressLineOverride, !localizedAddressLine.isEmpty {
            return compactSplitAddressComponent(localizedAddressLine)
        }
        if !competition.venue.isEmpty {
            return compactSplitAddressComponent(competition.venue)
        }
        return compactSplitAddressComponent(competition.venueAddress)
    }

    private func compactSplitAddressComponent(_ component: String) -> [String] {
        CompetitionService.parseAddress(component).displayText
            .replacingOccurrences(of: " · ", with: ",")
            .replacingOccurrences(of: "·", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func compactDeduplicatedParts(_ parts: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for part in parts {
            let normalized = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(part.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return result
    }

    private func statusColor(for status: CompetitionAvailabilityStatus, competition: CompetitionSummary) -> Color {
        if let rowClass = cubingRowClass(for: competition) {
            switch rowClass {
            case "info":
                if let waitlistStart = competition.localizedWaitlistStartOverride, Date() < waitlistStart {
                    return .teal
                }
                return .orange
            case "danger":
                if let waitlistStart = competition.localizedWaitlistStartOverride, Date() >= waitlistStart {
                    return .teal
                }
                return .green
            default:
                break
            }
        }

        if status == .waitlist {
            if let waitlistStart = competition.localizedWaitlistStartOverride, Date() < waitlistStart {
                return .teal
            }
            return .teal
        }

        return statusColor(for: status)
    }

    private func statusTint(for status: CompetitionAvailabilityStatus, competition: CompetitionSummary) -> CompetitionRowStatusTint {
        statusTint(for: status, competition: competition, rowClass: cubingRowClass(for: competition))
    }

    private func statusTint(
        for status: CompetitionAvailabilityStatus,
        competition: CompetitionSummary,
        rowClass: String?
    ) -> CompetitionRowStatusTint {
        if let rowClass {
            switch rowClass {
            case "info":
                if let waitlistStart = competition.localizedWaitlistStartOverride, Date() < waitlistStart {
                    return .teal
                }
                return .orange
            case "danger":
                if let waitlistStart = competition.localizedWaitlistStartOverride, Date() >= waitlistStart {
                    return .teal
                }
                return .green
            default:
                break
            }
        }

        if status == .waitlist {
            return .teal
        }

        return statusTint(for: status)
    }

    private func competitionAvailabilityStatus(for competition: CompetitionSummary) -> CompetitionAvailabilityStatus {
        if let localizedStatusOverride = competition.localizedStatusOverride {
            return localizedStatusOverride
        }

        let now = Date()
        let today = Calendar.current.startOfDay(for: now)

        if competition.endDate < today {
            return .ended
        }

        let startOfCompetition = Calendar.current.startOfDay(for: competition.startDate)
        let endOfCompetition = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: competition.endDate))
            ?? competition.endDate
        if now >= startOfCompetition && now < endOfCompetition {
            return .ongoing
        }

        switch competition.registrationStatus {
        case .notYetOpened:
            return .registrationNotOpenYet
        case .full:
            return .waitlist
        case .open:
            return .registrationOpen
        case .past, .none:
            break
        }

        if let open = competition.registrationOpen,
           let close = competition.registrationClose,
           open <= now && close >= now {
            return .registrationOpen
        }

        return .upcoming
    }

    private func statusColor(for status: CompetitionAvailabilityStatus) -> Color {
        switch status {
        case .upcoming:
            return .orange
        case .registrationNotOpenYet:
            return .yellow
        case .registrationOpen:
            return .green
        case .waitlist:
            return .mint
        case .ongoing:
            return .blue
        case .ended:
            return .secondary
        }
    }

    private func statusTint(for status: CompetitionAvailabilityStatus) -> CompetitionRowStatusTint {
        switch status {
        case .upcoming:
            return .orange
        case .registrationNotOpenYet:
            return .yellow
        case .registrationOpen:
            return .green
        case .waitlist:
            return .mint
        case .ongoing:
            return .blue
        case .ended:
            return .secondary
        }
    }

    private func isCancellationLikeError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        let lowered = nsError.localizedDescription.lowercased()
        return lowered.contains("cancelled")
    }

    private func isTimeoutLikeError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
            return true
        }
        return nsError.localizedDescription.lowercased().contains("timed out")
    }

    private func competitionListErrorMessage(for error: Error) -> String {
        if isTimeoutLikeError(error) {
            return localizedCompetitionStringInView(key: "competitions.error_timed_out", languageCode: appLanguage)
        }
        return localizedCompetitionStringInView(key: "competitions.error_request_failed", languageCode: appLanguage)
    }

    @MainActor
    private func loadCompetitions() async {
        let query = competitionQuery
        let expectedSignature = filterSignature
        guard isCompetitionListRequestCurrent(expectedSignature) else { return }
        // The identity-bound task owns query transitions; a cancelled old task
        // may still be awaiting a non-cancellable cache/network response.
        let requestID = UUID()
        activeLoadID = requestID
        activeLoadSignature = expectedSignature
        defer {
            if activeLoadID == requestID {
                activeLoadID = nil
                activeLoadSignature = nil
            }
        }
        if lastLoadedFilterSignature == expectedSignature,
           displayedFilterSignature == expectedSignature,
           !publishedVisibleCompetitions.isEmpty,
           let lastLoadedFilterDate,
           Date().timeIntervalSince(lastLoadedFilterDate) < 60 {
            competitionListLoadPhase = nextPage == nil ? .completed : .loadingMore
            return
        }

        let runtimeSnapshot = CompetitionListRuntimeCache.shared.snapshot(for: expectedSignature)
        if let runtimeSnapshot {
            if displayedFilterSignature != expectedSignature {
                restoreCompetitionRuntimeSnapshot(runtimeSnapshot)
            }
            displayedFilterSignature = expectedSignature
        } else if displayedFilterSignature != expectedSignature {
            resetCompetitionListForQueryTransition(signature: expectedSignature)
        }

        let cachedSnapshot = await cachedCompetitionList(for: query)
        guard isCompetitionListRequestCurrent(expectedSignature, requestID: requestID) else { return }
        let localizedCachedCompetitions = await CompetitionService.localizeCompetitionNamesIfNeeded(
            cachedSnapshot?.competitions ?? [],
            languageCode: appLanguage
        )
        guard isCompetitionListRequestCurrent(expectedSignature, requestID: requestID) else { return }
        let reusesCachedList = cachedSnapshot.map { CompetitionCachePolicy.canReuseList($0, query: query) } ?? false
        if (competitions.isEmpty && !localizedCachedCompetitions.isEmpty)
            || (reusesCachedList && competitions != localizedCachedCompetitions) {
            let cached = uniqueCompetitions(localizedCachedCompetitions)
            let lookup = await Task.detached(priority: .userInitiated) {
                Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
            }.value
            guard isCompetitionListRequestCurrent(expectedSignature, requestID: requestID) else { return }
            competitionLookupStore.setListSnapshot(cached, lookup: lookup)
            await publishVisibleCompetitionsSnapshot(expectedSignature: expectedSignature, requestID: requestID)
            guard isCompetitionListRequestCurrent(expectedSignature, requestID: requestID) else { return }
            displayedFilterSignature = expectedSignature
            loadedCompetitionCount = competitions.count
            totalCompetitionCount = cachedSnapshot?.totalCount
            if let totalCount = cachedSnapshot?.totalCount,
               cachedSnapshot?.competitions.count ?? 0 >= totalCount {
                nextPage = nil
                competitionListLoadPhase = .completed
                storeCompetitionRuntimeSnapshot(signature: expectedSignature)
            }
        }
        if publishedVisibleCompetitions.isEmpty {
            competitionListLoadPhase = .initialLoading
        }

        if let cachedSnapshot, CompetitionCachePolicy.canReuseList(cachedSnapshot, query: query) {
            nextPage = nil; competitionListLoadPhase = .completed
            markCompetitionFilterLoaded(signature: expectedSignature)
            return
        }

        do {
            try await loadAllCompetitionPages(
                for: query,
                expectedSignature: expectedSignature,
                cachedCompetitions: competitions,
                requestID: requestID
            )
        } catch {
            if isCancellationLikeError(error) || !isCompetitionListRequestCurrent(expectedSignature, requestID: requestID) {
                return
            }
            if publishedVisibleCompetitions.isEmpty {
                competitions = []
                visibleCompetitionsSnapshot = []
                publishedVisibleCompetitions = []
                publishedCompetitionListItems = []
                competitionLookupStore.clear()
                competitionListDataRevision &+= 1
            }
            competitionListLoadPhase = .failed(competitionListErrorMessage(for: error))
        }

        guard isCompetitionListRequestCurrent(expectedSignature, requestID: requestID) else { return }
        markCompetitionFilterLoaded(signature: expectedSignature)
    }

    private func isCompetitionListRequestCurrent(_ signature: String, requestID: UUID? = nil) -> Bool {
        guard competitionListRequestIsCurrent(expected: signature, current: filterSignature, isActive: isActive) else { return false }
        #if DEBUG
        if publicationAcceptanceEnabled, publicationAcceptanceScope != CompetitionBrowserPublicationAcceptance.scope { return false }
        // Negative control for the old independent pull-refresh ABA lifetime.
        if publicationAcceptanceEnabled, !CompetitionBrowserPublicationAcceptance.checksRequestEpoch { return true }
        #endif
        return requestID == nil || activeLoadID == requestID
    }

    private var publicationAcceptanceIsEnabled: Bool {
        #if DEBUG
        publicationAcceptanceEnabled
        #else
        false
        #endif
    }

    private func cachedCompetitionList(for query: CompetitionQuery) async -> CompetitionCacheSnapshot? {
        #if DEBUG
        if publicationAcceptanceEnabled, let cache = CompetitionBrowserPublicationAcceptance.cache {
            return await cache(query)
        }
        #endif
        return await CompetitionService.cachedCompetitions(for: query)
    }

    private func fetchCompetitionListPage(query: CompetitionQuery, page: Int) async throws -> CompetitionPageResult {
        #if DEBUG
        if publicationAcceptanceEnabled, let fetch = CompetitionBrowserPublicationAcceptance.page {
            return try await fetch(query, page)
        }
        #endif
        return try await CompetitionService.fetchCompetitionsPage(query: query, page: page)
    }

    @MainActor
    private func refreshCompetitionsForPullToRefresh() async {
        let query = competitionQuery
        let expectedSignature = filterSignature
        guard isCompetitionListRequestCurrent(expectedSignature) else { return }
        guard activeLoadSignature == nil else { return }
        let requestID = UUID()
        activeLoadID = requestID
        activeLoadSignature = expectedSignature
        defer {
            if activeLoadID == requestID {
                activeLoadID = nil
                activeLoadSignature = nil
            }
        }
        do {
            try await loadAllCompetitionPages(
                for: query,
                expectedSignature: expectedSignature,
                cachedCompetitions: competitions,
                requestID: requestID
            )
            guard isCompetitionListRequestCurrent(expectedSignature, requestID: requestID) else { return }
            announceRefreshSuccess()
        } catch {
            if isCancellationLikeError(error) || !isCompetitionListRequestCurrent(expectedSignature, requestID: requestID) {
                return
            }
            competitionListLoadPhase = .failed(competitionListErrorMessage(for: error))
        }
    }

    @MainActor
    private func markCompetitionFilterLoaded(signature: String) {
        lastLoadedFilterSignature = signature
        lastLoadedFilterDate = Date()
    }


    @MainActor
    private func announceRefreshSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.snappy(duration: 0.22)) {
            showsRefreshSuccessBanner = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                withAnimation(.snappy(duration: 0.22)) {
                    showsRefreshSuccessBanner = false
                }
            }
        }
    }

    @MainActor
    private func loadAllCompetitionPages(
        for query: CompetitionQuery,
        expectedSignature: String,
        cachedCompetitions: [CompetitionSummary],
        requestID: UUID
    ) async throws {
        guard isCompetitionListRequestCurrent(expectedSignature, requestID: requestID) else { return }

        var freshByID: [String: CompetitionSummary] = [:]
        var pageToFetch: Int? = 1
        var totalCount: Int?
        var pagesSincePublish = 0
        var lastProgressPublishDate = Date.distantPast
        let hasCachedPresentation = !cachedCompetitions.isEmpty
            && !publishedCompetitionListItems.isEmpty
        let preservesCompletedPresentation = competitionListLoadPhase == .completed
            && !publishedCompetitionListItems.isEmpty

        if !preservesCompletedPresentation {
            competitionListLoadPhase = publishedVisibleCompetitions.isEmpty
                ? .initialLoading
                : .loadingMore
        }

        while let page = pageToFetch {
            try Task.checkCancellation()
            let result: CompetitionPageResult
            do {
                result = try await fetchCompetitionListPage(query: query, page: page)
            } catch let serviceError as CompetitionServiceError {
                try Task.checkCancellation()
                guard isCompetitionListRequestCurrent(expectedSignature, requestID: requestID) else { return }
                guard let retryDelay = serviceError.rateLimitRetryDelay else { throw serviceError }
                let delay = min(max(retryDelay, 1), 3_600)
                if !preservesCompletedPresentation {
                    competitionListLoadPhase = .rateLimited(Date().addingTimeInterval(delay))
                }
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                try Task.checkCancellation()
                guard isCompetitionListRequestCurrent(expectedSignature, requestID: requestID) else { return }
                competitionListLoadPhase = preservesCompletedPresentation
                    ? .completed
                    : (publishedCompetitionListItems.isEmpty ? .initialLoading : .loadingMore)
                continue
            }
            try Task.checkCancellation()
            guard isCompetitionListRequestCurrent(expectedSignature, requestID: requestID) else { return }

            for competition in result.competitions {
                freshByID[competition.id] = competition
            }
            pageToFetch = result.nextPage
            totalCount = result.totalCount ?? totalCount
            pagesSincePublish += 1

            let isFirstPage = page == 1
            let isComplete = pageToFetch == nil
            if isComplete, query.status == .recent { totalCount = freshByID.count }
            let now = Date()
            if isFirstPage
                || isComplete
                || now.timeIntervalSince(lastProgressPublishDate) >= Self.paginationProgressPublishInterval {
                // Keep the count truthful while avoiding a full List diff for
                // every 25-item API response.
                loadedCompetitionCount = freshByID.count
                totalCompetitionCount = totalCount
                self.nextPage = pageToFetch
                lastProgressPublishDate = now
            }
            let pageBatchSize = competitionPaginationPublishPageBatchSize(loadedCount: freshByID.count)
            let shouldPublishIncrementally = !hasCachedPresentation
                && (isFirstPage || pagesSincePublish >= pageBatchSize)
            if isComplete || shouldPublishIncrementally {
                if isComplete {
                    competitionListLoadPhase = .completed
                }
                let fresh = Array(freshByID.values)
                await publishCompetitionPaginationBatch(
                    fresh,
                    cachedCompetitions: isComplete ? [] : cachedCompetitions,
                    freshLoadedCount: freshByID.count,
                    totalCount: totalCount,
                    nextPage: pageToFetch,
                    query: query,
                    expectedSignature: expectedSignature,
                    requestID: requestID
                )
                try Task.checkCancellation()
                guard isCompetitionListRequestCurrent(expectedSignature, requestID: requestID) else { return }
                if !isComplete, !preservesCompletedPresentation {
                    competitionListLoadPhase = .loadingMore
                }
                pagesSincePublish = 0
            }

            guard pageToFetch != nil else { break }
            try await Task.sleep(nanoseconds: 45_000_000)
        }

        guard isCompetitionListRequestCurrent(expectedSignature, requestID: requestID) else { return }
        competitionListLoadPhase = .completed
        nextPage = nil
        storeCompetitionRuntimeSnapshot(signature: expectedSignature)
        await CompetitionService.cacheCompetitions(
            Array(freshByID.values),
            totalCount: totalCount,
            for: query
        )
    }

    private func competitionPaginationPublishPageBatchSize(loadedCount: Int) -> Int {
        switch loadedCount {
        case ..<250:
            return 3
        case ..<1_000:
            return 8
        case ..<3_000:
            return 16
        default:
            return 28
        }
    }

    @MainActor
    private func publishCompetitionPaginationBatch(
        _ freshCompetitions: [CompetitionSummary],
        cachedCompetitions: [CompetitionSummary],
        freshLoadedCount: Int,
        totalCount: Int?,
        nextPage: Int?,
        query: CompetitionQuery,
        expectedSignature: String,
        requestID: UUID
    ) async {
        let preparedSnapshot = await Task.detached(priority: .utility) {
            var seenIDs = Set<String>()
            let merged = (freshCompetitions + cachedCompetitions).filter { competition in
                seenIDs.insert(competition.id).inserted
            }
            let normalized = CompetitionService.filterCompetitions(merged, for: query)
            let lookup = Dictionary(uniqueKeysWithValues: normalized.map { ($0.id, $0) })
            return (normalized, lookup)
        }.value
        guard isCompetitionListRequestCurrent(expectedSignature, requestID: requestID) else { return }

        let normalized = preparedSnapshot.0
        competitionLookupStore.setListSnapshot(normalized, lookup: preparedSnapshot.1)
        displayedFilterSignature = expectedSignature
        loadedCompetitionCount = freshLoadedCount
        totalCompetitionCount = totalCount
        self.nextPage = nextPage
        let sourceRevision = competitionLookupStore.sourceRevision
        let listItems = await makeCompetitionListItems(for: normalized)
        guard isCompetitionListRequestCurrent(expectedSignature, requestID: requestID),
              sourceRevision == competitionLookupStore.sourceRevision else { return }
        publishPreparedCompetitionListItems(listItems)
        updateBottomAccessoryVisibility()
        storeCompetitionRuntimeSnapshot(signature: expectedSignature)
    }

    private func uniqueCompetitions(_ competitions: [CompetitionSummary]) -> [CompetitionSummary] {
        var seenIDs = Set<String>()
        return competitions.filter { competition in
            seenIDs.insert(competition.id).inserted
        }
    }

    @MainActor
    private func resetCompetitionListForQueryTransition(signature: String) {
        competitionLookupStore.clear()
        publishedCompetitionListItems = []
        topCuberStatesByCompetitionID = [:]
        topCuberDisclosureStore.reset()
        loadedCompetitionCount = 0
        totalCompetitionCount = nil
        nextPage = 1
        competitionListLoadPhase = .initialLoading
        competitionListDataRevision &+= 1
        displayedFilterSignature = signature
        updateBottomAccessoryVisibility()
    }

    @MainActor
    private func publishVisibleCompetitionsSnapshot(expectedSignature: String, requestID: UUID? = nil) async {
        guard displayedFilterSignature == expectedSignature else { return }
        let sourceRevision = competitionLookupStore.sourceRevision
        let published = uniqueCompetitions(visibleCompetitionsSnapshot)
        let listItems = await makeCompetitionListItems(for: published)
        // A same-query metadata task can finish preparing an older dataset after
        // cache/page loading has installed newer rows.
        guard isCompetitionListRequestCurrent(expectedSignature, requestID: requestID),
              sourceRevision == competitionLookupStore.sourceRevision else { return }
        publishedVisibleCompetitions = published
        publishPreparedCompetitionListItems(listItems)
        updateBottomAccessoryVisibility()
        storeCompetitionRuntimeSnapshot(signature: expectedSignature)
    }

    @MainActor
    private func makeCompetitionRowModels(for publishedCompetitions: [CompetitionSummary]) async -> [CompetitionRowModel] {
        let languageCode = appLanguage
        let preparedRows = await Task.detached(priority: .userInitiated) {
            CompetitionRowPreparation.prepare(
                publishedCompetitions,
                languageCode: languageCode
            )
        }.value
        guard !Task.isCancelled else { return [] }

        return preparedRows.map { prepared in
            let competition = prepared.competition
            let availabilityStatus = competitionAvailabilityStatus(for: competition)
            let rowClass = cubingRowClass(for: competition)
            let compactStatus = compactRegistrationDisplayStatus(for: competition, availabilityStatus: availabilityStatus)
            let competitorLimit = competition.competitorLimit
            let statusBadgeTitle = statusBadgeTitle(
                for: availabilityStatus,
                competition: competition,
                rowClass: rowClass,
                languageCode: appLanguage
            )
            let statusTint = statusTint(for: availabilityStatus, competition: competition, rowClass: rowClass)
            let compactStatusMessage = compactRegistrationStatusMessage(for: compactStatus, competition: competition)

            return CompetitionRowModel(
                id: competition.id,
                rowIndex: prepared.rowIndex,
                startYear: prepared.competitionYear,
                showsYearSeparator: prepared.showsYearSeparator,
                contentHash: competitionRowContentHash(
                    rowIndex: prepared.rowIndex,
                    startYear: prepared.competitionYear,
                    showsYearSeparator: prepared.showsYearSeparator,
                    name: prepared.name,
                    compactDisplayName: prepared.compactDisplayName,
                    flagEmoji: prepared.flagEmoji,
                    dateRangeText: prepared.dateRangeText,
                    locationLine: prepared.locationLine,
                    venueLine: prepared.venueLine,
                    competitorLimit: competitorLimit,
                    statusBadgeTitle: statusBadgeTitle,
                    statusTint: statusTint,
                    compactStatus: compactStatus,
                    compactStatusMessage: compactStatusMessage,
                    compactAddressCountry: prepared.compactAddressCountry,
                    compactAddress: prepared.compactAddress,
                    venueAddress: prepared.venueAddress
                ),
                name: prepared.name,
                compactDisplayName: prepared.compactDisplayName,
                flagEmoji: prepared.flagEmoji,
                dateRangeText: prepared.dateRangeText,
                locationLine: prepared.locationLine,
                venueLine: prepared.venueLine,
                competitorLimit: competitorLimit,
                statusBadgeTitle: statusBadgeTitle,
                statusTint: statusTint,
                compactStatus: compactStatus,
                compactStatusMessage: compactStatusMessage,
                compactAddressCountry: prepared.compactAddressCountry,
                compactAddress: prepared.compactAddress,
                venueAddress: prepared.venueAddress
            )
        }
    }

    @MainActor
    private func makeCompetitionListItems(for competitions: [CompetitionSummary]) async -> [CompetitionListItem] {
        let rowModels = await makeCompetitionRowModels(for: competitions)
        var items: [CompetitionListItem] = []
        items.reserveCapacity(rowModels.count + 32)
        for row in rowModels {
            if row.showsYearSeparator {
                items.append(.year(row.startYear))
            }
            items.append(.competition(row))
        }
        return items
    }

    private func competitionRowContentHash(
        rowIndex: Int,
        startYear: Int,
        showsYearSeparator: Bool,
        name: String,
        compactDisplayName: String,
        flagEmoji: String,
        dateRangeText: String,
        locationLine: String,
        venueLine: String,
        competitorLimit: Int?,
        statusBadgeTitle: String,
        statusTint: CompetitionRowStatusTint,
        compactStatus: CompactRegistrationDisplayStatus,
        compactStatusMessage: String,
        compactAddressCountry: String,
        compactAddress: CompetitionService.ParsedAddress,
        venueAddress: CompetitionService.ParsedAddress
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(rowIndex)
        hasher.combine(startYear)
        hasher.combine(showsYearSeparator)
        hasher.combine(name)
        hasher.combine(compactDisplayName)
        hasher.combine(flagEmoji)
        hasher.combine(dateRangeText)
        hasher.combine(locationLine)
        hasher.combine(venueLine)
        hasher.combine(competitorLimit)
        hasher.combine(statusBadgeTitle)
        hasher.combine(statusTint)
        hasher.combine(compactStatus)
        hasher.combine(compactStatusMessage)
        hasher.combine(compactAddressCountry)
        hasher.combine(compactAddress)
        hasher.combine(venueAddress)
        return hasher.finalize()
    }

    @MainActor
    private func restoreCompetitionRuntimeSnapshot(_ snapshot: CompetitionListRuntimeCache.Snapshot) {
        guard !snapshot.competitions.isEmpty else { return }
        competitionLookupStore.setListSnapshot(
            snapshot.competitions,
            lookup: snapshot.competitionsByID
        )
        competitionLookupStore.setPreparedDisplayItems(snapshot.displayItems)
        if publishedCompetitionListItems != snapshot.displayItems {
            publishedCompetitionListItems = snapshot.displayItems
            competitionListDataRevision &+= 1
        }
        updateBottomAccessoryVisibility()
        nextPage = snapshot.nextPage
        loadedCompetitionCount = snapshot.loadedCount
        totalCompetitionCount = snapshot.totalCount
        topCuberStatesByCompetitionID = snapshot.topCuberStatesByCompetitionID
        competitionListLoadPhase = snapshot.nextPage == nil ? .completed : .loadingMore
    }

    @MainActor
    private func storeCompetitionRuntimeSnapshot(signature: String? = nil) {
        guard !publishedVisibleCompetitions.isEmpty else { return }
        CompetitionListRuntimeCache.shared.store(
            CompetitionListRuntimeCache.Snapshot(
                competitions: publishedVisibleCompetitions,
                competitionsByID: competitionLookupStore.competitionsByID,
                displayItems: competitionLookupStore.preparedDisplayItems.isEmpty
                    ? publishedCompetitionListItems
                    : competitionLookupStore.preparedDisplayItems,
                nextPage: nextPage,
                loadedCount: loadedCompetitionCount,
                totalCount: totalCompetitionCount,
                topCuberStatesByCompetitionID: topCuberStatesByCompetitionID
            ),
            for: signature ?? filterSignature
        )
    }

    @MainActor
    private func publishPreparedCompetitionListItems(_ items: [CompetitionListItem]) {
        competitionLookupStore.setPreparedDisplayItems(items)
        if publishedCompetitionListItems != items {
            publishedCompetitionListItems = items
            competitionListDataRevision &+= 1
        }
        #if DEBUG
        if publicationAcceptanceEnabled, publicationAcceptanceScope == CompetitionBrowserPublicationAcceptance.scope {
            CompetitionBrowserPublicationAcceptance.published?(.init(revision: competitionListDataRevision,
                signature: filterSignature, ids: competitionLookupStore.publishedCompetitions.map(\.id),
                sourceIDs: competitionLookupStore.competitions.map(\.id),
                preparedIDs: competitionLookupStore.preparedDisplayItems.compactMap {
                    if case .competition(let row) = $0 { return row.id }; return nil
                }, isActive: isActive, phase: String(describing: competitionListLoadPhase)))
        }
        #endif
    }

    private func localizedCompetitionDateRange(for competition: CompetitionSummary) -> String {
        let locale = appLocale(for: appLanguage)
        let calendar = Calendar(identifier: .gregorian)

        let sameYear = calendar.component(.year, from: competition.startDate) == calendar.component(.year, from: competition.endDate)
        let sameMonth = sameYear && calendar.component(.month, from: competition.startDate) == calendar.component(.month, from: competition.endDate)
        let sameDay = sameMonth && calendar.component(.day, from: competition.startDate) == calendar.component(.day, from: competition.endDate)

        let fullFormat = localizedCompetitionStringInView(key: "competition.date.full_format", languageCode: appLanguage)
        if sameDay {
            return CompetitionDateRangeFormatterCache.string(from: competition.startDate, locale: locale, format: fullFormat)
        }
        if sameMonth {
            let monthDayFormat = localizedCompetitionStringInView(key: "competition.date.month_day_format", languageCode: appLanguage)
            let daySuffixFormat = localizedCompetitionStringInView(key: "competition.date.day_suffix_format", languageCode: appLanguage)
            let start = CompetitionDateRangeFormatterCache.string(from: competition.startDate, locale: locale, format: monthDayFormat)
            let end = CompetitionDateRangeFormatterCache.string(from: competition.endDate, locale: locale, format: daySuffixFormat)
            return "\(start) - \(end)"
        }
        let start = CompetitionDateRangeFormatterCache.string(from: competition.startDate, locale: locale, format: fullFormat)
        let end = CompetitionDateRangeFormatterCache.string(from: competition.endDate, locale: locale, format: fullFormat)
        return "\(start) - \(end)"
    }

    private func cubingRowClass(for competition: CompetitionSummary) -> String? {
        let keys = [
            normalizeCompetitionLookupKeyForUI(competition.id),
            normalizeCompetitionLookupKeyForUI(competition.website ?? ""),
            normalizeCompetitionLookupKeyForUI(competition.name)
        ]

        for key in keys where !key.isEmpty {
            if let value = cubingRowClassesByKey[key] {
                return value
            }
        }
        return nil
    }

    private func fetchCubingRowClasses(languageCode: String) async -> [String: String] {
        let cubingLanguage = cubingLanguageCode(for: languageCode)
        guard let url = URL(string: "https://cubing.com/competition?lang=\(cubingLanguage)&year=&type=WCA&province=&event=") else {
            return [:]
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .useProtocolCachePolicy
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(appAcceptLanguageHeader(for: languageCode), forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode,
              let html = String(data: data, encoding: .utf8) else {
            return [:]
        }

        let pattern = #"(?s)<tr[^>]*class=\"([^\"]+)\"[^>]*>\s*<td[^>]*>.*?</td>\s*<td[^>]*>\s*<a[^>]*class="comp-type-wca"[^>]*href="(?:https://cubing\.com)?/(?:competition|live)/([^"]+)"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [:]
        }

        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        var mapping: [String: String] = [:]

        regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 4 else { return }
            let rowClass = cleanCompetitionHTMLTextForUI(nsHTML.substring(with: match.range(at: 1))).lowercased()
            let slug = nsHTML.substring(with: match.range(at: 2))
            let titleHTML = nsHTML.substring(with: match.range(at: 3))
            let localizedName = cleanCompetitionHTMLTextForUI(titleHTML)

            let slugKey = normalizeCompetitionLookupKeyForUI(slug)
            if !slugKey.isEmpty, !rowClass.isEmpty {
                mapping[slugKey] = rowClass
            }

            let nameKey = normalizeCompetitionLookupKeyForUI(localizedName)
            if !nameKey.isEmpty, !rowClass.isEmpty {
                mapping[nameKey] = rowClass
            }
        }

        return mapping
    }

    private func cleanCompetitionHTMLTextForUI(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"&nbsp;"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeCompetitionLookupKeyForUI(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^https?://www\.worldcubeassociation\.org/competitions/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^/competitions/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^https?://cubing\.com/competition/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^/competition/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^https?://cubing\.com/live/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^/live/"#, with: "", options: .regularExpression)
            .components(separatedBy: "/").first ?? value
            .components(separatedBy: "?").first ?? value
            .components(separatedBy: "#").first ?? value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "", options: .regularExpression)
            .lowercased()
    }
}

struct CompetitionBottomSearchBar: View {
    let languageCode: String
    let usesContainerGlass: Bool
    let searchAction: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        Button(action: searchAction) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                Text(localizedCompetitionStringInView(key: "competitions.search_placeholder", languageCode: languageCode))
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .background(
            shape
                .fill(.black.opacity(0.001))
        )
        .contentShape(shape)
        .modifier(CompetitionBottomSearchBarGlassModifier(isEnabled: usesContainerGlass, shape: shape))
    }
}

private struct CompetitionBottomSearchBarGlassModifier: ViewModifier {
    let isEnabled: Bool
    let shape: RoundedRectangle

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.compatibleGlass(in: shape)
        } else {
            content
        }
    }
}

private struct CompetitionNavigationSubtitleModifier: ViewModifier {
    let subtitle: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), let subtitle, !subtitle.isEmpty {
            content.navigationSubtitle(Text(subtitle))
        } else {
            content
        }
    }
}

enum CompetitionDetailTabKind: Hashable {
    case info
    case results
    case scrambles
    case rules
    case register
    case competitors
    case schedule
    case events
    case travel
    case live
    case custom(String)
}

struct CompetitionDetailTab: Identifiable, Hashable {
    let kind: CompetitionDetailTabKind
    let titleOverride: String?

    static func == (lhs: CompetitionDetailTab, rhs: CompetitionDetailTab) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }

    static let info = CompetitionDetailTab(kind: .info)
    static let results = CompetitionDetailTab(kind: .results)
    static let scrambles = CompetitionDetailTab(kind: .scrambles)
    static let rules = CompetitionDetailTab(kind: .rules)
    static let register = CompetitionDetailTab(kind: .register)
    static let competitors = CompetitionDetailTab(kind: .competitors)
    static let schedule = CompetitionDetailTab(kind: .schedule)
    static let events = CompetitionDetailTab(kind: .events)
    static let travel = CompetitionDetailTab(kind: .travel)
    static let live = CompetitionDetailTab(kind: .live)
    static func spectatorTicket(language: String) -> CompetitionDetailTab {
        .custom(id: "spectator-ticket", title: PublishedCompetitionStrings.text("tickets", language))
    }

    static let standardCases: [CompetitionDetailTab] = [.info, .register, .competitors, .schedule, .live]

    init(kind: CompetitionDetailTabKind, titleOverride: String? = nil) {
        self.kind = kind
        self.titleOverride = titleOverride
    }

    static func custom(id: String, title: String) -> CompetitionDetailTab {
        CompetitionDetailTab(kind: .custom(id), titleOverride: title)
    }

    func titled(_ title: String?) -> CompetitionDetailTab {
        CompetitionDetailTab(kind: kind, titleOverride: title)
    }

    var id: String { rawValue }

    var rawValue: String {
        switch kind {
        case .info: return "info"
        case .results: return "results"
        case .scrambles: return "scrambles"
        case .rules: return "rules"
        case .register: return "register"
        case .competitors: return "competitors"
        case .schedule: return "schedule"
        case .events: return "events"
        case .travel: return "travel"
        case .live: return "live"
        case .custom(let id): return "custom-\(id)"
        }
    }

    func localizedTitle(languageCode: String) -> String {
        if let titleOverride, !titleOverride.isEmpty {
            return titleOverride
        }

        switch kind {
        case .info:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.info", languageCode: languageCode)
        case .results:
            return PublishedCompetitionStrings.text("results", languageCode)
        case .scrambles:
            return PublishedCompetitionStrings.text("scrambles", languageCode)
        case .rules:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.rules", languageCode: languageCode)
        case .register:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.register", languageCode: languageCode)
        case .competitors:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.competitors", languageCode: languageCode)
        case .schedule:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.schedule", languageCode: languageCode)
        case .events:
            return localizedCompetitionStringInView(key: "competitions.detail.section.events", languageCode: languageCode)
        case .travel:
            return localizedCompetitionStringInView(key: "competitions.detail.section.travel", languageCode: languageCode)
        case .live:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.live", languageCode: languageCode)
        case .custom:
            return localizedCompetitionStringInView(key: "competitions.detail.tab.info", languageCode: languageCode)
        }
    }
}

enum CompetitionLoadingPresentation {
    static func title(_ work: CompetitionLoadingLifecycle.Work?, language: String, cubingChina: Bool) -> String {
        guard let work else { return PublishedCompetitionStrings.text("session.idle", language) }
        if case .publication = work { return PublishedCompetitionStrings.text("session.checking_results", language) }
        let section: String
        switch work {
        case .detail(.info): section = cubingChina ? PublishedCompetitionStrings.text("about", language) : CompetitionDetailTab.info.localizedTitle(languageCode: language)
        case .detail(.regulations): section = localizedCompetitionStringInView(key: "competitions.detail.tab.regulations", languageCode: language)
        case .detail(.schedule): section = CompetitionDetailTab.schedule.localizedTitle(languageCode: language)
        case .detail(.travel): section = CompetitionDetailTab.travel.localizedTitle(languageCode: language)
        case .detail(.registration): section = CompetitionDetailTab.register.localizedTitle(languageCode: language)
        case .detail(.competitors), .psych: section = CompetitionDetailTab.competitors.localizedTitle(languageCode: language)
        case .detail(.tickets): section = PublishedCompetitionStrings.text("tickets", language)
        case .detail(.live): section = CompetitionDetailTab.live.localizedTitle(languageCode: language)
        case .scrambles: section = PublishedCompetitionStrings.text("scrambles", language)
        case .publication: section = PublishedCompetitionStrings.text("results", language)
        }
        return String(format: PublishedCompetitionStrings.text("session.loading_stage", language), section)
    }
}

enum CompetitionDetailNavigationPolicy {
    static func shouldCheckPublication(competitionEnded: Bool, explicitPublishedResult: Bool) -> Bool {
        competitionEnded || explicitPublishedResult
    }

    static func usesCubingChinaLive(cubingChina: Bool, explicitWCALive: Bool, hasContent: Bool) -> Bool {
        cubingChina && hasContent
    }

    static func tabs(lifecycle: PublishedCompetitionLifecycle, cubingChina: Bool, showLive: Bool,
                     language: String, showTickets: Bool = false) -> [CompetitionDetailTab] {
        if lifecycle == .published { return [.info, .results, .scrambles] + (showLive ? [.live] : []) }
        return [.info, .register, .competitors] + (showLive ? [.live] : [])
            + (cubingChina && showTickets ? [.spectatorTicket(language: language)] : [])
    }

    static func infoSections(lifecycle: PublishedCompetitionLifecycle, cubingChina: Bool,
                             language: String, showTickets: Bool = false) -> [CompetitionDetailTab] {
        guard cubingChina else { return [] }
        return [.info.titled(PublishedCompetitionStrings.text("about", language)),
                .rules.titled(localizedCompetitionStringInView(key: "competitions.detail.tab.regulations", languageCode: language)),
                .schedule, .travel] + (lifecycle == .published ? [.competitors, .register]
                    + (showTickets ? [.spectatorTicket(language: language)] : []) : [])
    }

    static func selection(lifecycle: PublishedCompetitionLifecycle, cubingChina: Bool, showLive: Bool,
                          explicitLive: Bool, primary: CompetitionDetailTab,
                          section: CompetitionDetailTab, showTickets: Bool = false) -> (primary: CompetitionDetailTab, section: CompetitionDetailTab) {
        let sections = infoSections(lifecycle: lifecycle, cubingChina: cubingChina, language: "en", showTickets: showTickets)
        let validSection = sections.contains(section) ? section : .info
        if lifecycle == .published {
            if primary == .live { return (showLive ? .live : .results, validSection) }
            if cubingChina, sections.contains(primary), primary != .info { return (.info, primary) }
        }
        let tabs = tabs(lifecycle: lifecycle, cubingChina: cubingChina, showLive: showLive, language: "en", showTickets: showTickets)
        return (tabs.contains(primary) ? primary : .info, validSection)
    }

    static func permitsRegistrationAction(_ competition: CompetitionSummary,
                                          lifecycle: PublishedCompetitionLifecycle, now: Date) -> Bool {
        lifecycle != .published && now < competition.startDate && now <= competition.endDate
            && (competition.registrationClose.map { now < $0 } ?? true)
    }

    static func showsLive(content: CompetitionDetailContent, cubingChina: Bool) -> Bool {
        if cubingChina {
            return content.cubingChinaLiveWebsite != nil
                || (content.liveContent != nil && [.available, .ended].contains(content.liveAvailability))
        }
        return content.wcaLiveContent != nil && [.available, .ended].contains(content.liveAvailability)
    }
}

private enum WCAScheduleDisplayMode: String, CaseIterable, Identifiable {
    case calendar
    case table

    var id: String { rawValue }
}

private struct CompetitionWCAScheduleBlockPlacement: Identifiable {
    let entry: CompetitionScheduleEntry
    let lane: Int
    let laneCount: Int

    var id: String { entry.id }
}

private struct CompetitionWCAScheduleBlockView: View {
    let entry: CompetitionScheduleEntry
    let backgroundColor: Color
    let foregroundColor: Color
    let availableHeight: CGFloat

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Group {
                if availableHeight < 28 {
                    Text("\(entry.timeText)  \(entry.title)")
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.timeText)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)

                        Text(entry.title)
                            .font(.system(size: 10, weight: .semibold))
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    }
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 3)
            .padding(.vertical, availableHeight < 28 ? 1 : 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(foregroundColor.opacity(0.22), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text(entry.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                Label(entry.timeText, systemImage: "clock")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)

                if let venueName = entry.venueName, !venueName.isEmpty {
                    Label(venueName, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .modifier(CompetitionEventPopoverAdaptationModifier())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title), \(entry.timeText)")
    }
}

private struct CompetitionTextPopoverButton<Label: View>: View {
    let text: String
    let label: Label

    @State private var isPresented = false

    init(text: String, @ViewBuilder label: () -> Label) {
        self.text = text
        self.label = label()
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(CompetitionEventPopoverAdaptationModifier())
        }
    }
}

private struct CompetitionEventPopoverAdaptationModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationCompactAdaptation(.popover)
        } else {
            content
        }
    }
}

private struct CubingCompetitionDetailNavigation: View {
    let tabs: [CompetitionDetailTab]
    let languageCode: String
    @Binding var selection: CompetitionDetailTab

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(tabs) { tab in
                        let isSelected = selection == tab
                        let tint = CubingChinaNavigationColors.accent(for: tab.kind, about: true)

                        Button {
                            guard !isSelected else { return }
                            withAnimation(.snappy(duration: 0.28)) {
                                selection = tab
                            }
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            VStack(spacing: 7) {
                                Text(tab.localizedTitle(languageCode: languageCode))
                                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(tint)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)

                                Capsule()
                                    .fill(isSelected ? tint : Color.clear)
                                    .frame(height: 2)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .id(tab.id)
                    }
                }
            }
            .onAppear { proxy.scrollTo(selection.id, anchor: .center) }
            .onChange(of: selection) { newValue in
                withAnimation(.snappy(duration: 0.28)) {
                    proxy.scrollTo(newValue.id, anchor: .center)
                }
            }
        }
    }

}

struct CompetitionDetailTabStrip: View {
    let tabs: [CompetitionDetailTab]
    let languageCode: String
    @Binding var selection: CompetitionDetailTab

    @State private var tabWidths: [String: CGFloat] = [:]
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var pressedTab: CompetitionDetailTab?

    private let spacing: CGFloat = 8
    private let horizontalPadding: CGFloat = 6
    private let labelHorizontalPadding: CGFloat = 14
    private let selectedHeight: CGFloat = 34

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HorizontalCapsuleSelectorGroup(spacing: spacing) {
                ZStack(alignment: .leading) {
                    selectionIndicator
                        .zIndex(0)

                    tabLabelsLayer
                        .zIndex(1)

                    dragOverlay
                        .zIndex(2)
                }
            }
            .onPreferenceChange(CompetitionTabWidthPreferenceKey.self) { widths in
                let cleanedWidths = widths.filter { $0.value.isFinite && $0.value > 0 }
                guard !cleanedWidths.isApproximatelyEqual(to: tabWidths) else { return }
                DispatchQueue.main.async {
                    guard !cleanedWidths.isApproximatelyEqual(to: tabWidths) else { return }
                    tabWidths = cleanedWidths
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 48)
    }

    private var selectionIndicator: some View {
        HorizontalCapsuleSelectionIndicator {
            Capsule()
                .fill(Color.primary.opacity(isDragging ? 0.12 : 0.08))
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.6)
                }
                .compatibleGlassFromIOS16(in: Capsule())
        }
            .frame(width: selectedWidth, height: selectedHeight)
            .scaleEffect(isDragging ? 1.04 : 1.0)
            .offset(x: clampedIndicatorOffset)
            .legacyHorizontalSelectorShadow(
                color: .black.opacity(0.08),
                radius: isDragging ? 10 : 6,
                y: 3
            )
            .animation(.spring(response: 0.32, dampingFraction: 0.76), value: selection)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isDragging)
            .allowsHitTesting(false)
    }

    private var tabLabelsLayer: some View {
        HStack(spacing: spacing) {
            ForEach(tabs) { tab in
                tabLabel(for: tab)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 5)
    }

    private func tabLabel(for tab: CompetitionDetailTab) -> some View {
        Text(tab.localizedTitle(languageCode: languageCode))
            .font(.system(size: 15, weight: fontWeight(for: tab)))
            .foregroundStyle(foregroundStyle(for: tab))
            .lineLimit(1)
            .padding(.horizontal, labelHorizontalPadding)
            .padding(.vertical, 9)
            .scaleEffect(pressedTab == tab ? 0.97 : 1.0)
            .contentShape(Rectangle())
            .modifier(CompetitionDetailTabMeasurementModifier(tabID: tab.id))
            .onTapGesture {
                pressThenSelect(tab)
            }
            .animation(.spring(response: 0.18, dampingFraction: 0.78), value: pressedTab)
    }

    private var dragOverlay: some View {
        Color.clear
            .frame(width: selectedWidth, height: selectedHeight)
            .contentShape(Capsule())
            .offset(x: selectedBaseOffset, y: 5)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        pressedTab = selection
                        dragOffset = gesture.translation.width
                    }
                    .onEnded { gesture in
                        snapToNearestTab(dragDistance: gesture.translation.width)
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                            dragOffset = 0
                            isDragging = false
                            pressedTab = nil
                        }
                    }
            )
    }

    private var selectedWidth: CGFloat {
        max(width(for: selection), 44)
    }

    private var selectedBaseOffset: CGFloat {
        offset(for: selection)
    }

    private var clampedIndicatorOffset: CGFloat {
        let proposed = selectedBaseOffset + dragOffset
        let maximum = max(horizontalPadding, totalTabsWidth - selectedWidth + horizontalPadding)
        return min(max(proposed, horizontalPadding), maximum)
    }

    private var totalTabsWidth: CGFloat {
        tabs.reduce(CGFloat(0)) { partial, tab in
            partial + width(for: tab)
        } + CGFloat(max(tabs.count - 1, 0)) * spacing
    }

    private func width(for tab: CompetitionDetailTab) -> CGFloat {
        tabWidths[tab.id] ?? fallbackWidth(for: tab)
    }

    private func offset(for tab: CompetitionDetailTab) -> CGFloat {
        guard let index = tabs.firstIndex(of: tab) else { return horizontalPadding }
        let previousWidths = tabs.prefix(index).reduce(CGFloat(0)) { partial, tab in
            partial + width(for: tab)
        }
        return horizontalPadding + previousWidths + CGFloat(index) * spacing
    }

    private func fallbackWidth(for tab: CompetitionDetailTab) -> CGFloat {
        let title = tab.localizedTitle(languageCode: languageCode)
        return max(CGFloat(title.count) * 8.5 + labelHorizontalPadding * 2, 54)
    }

    private func fontWeight(for tab: CompetitionDetailTab) -> Font.Weight {
        selection == tab ? .semibold : .regular
    }

    private func foregroundStyle(for tab: CompetitionDetailTab) -> Color {
        selection == tab ? .primary : .secondary
    }

    private func pressThenSelect(_ tab: CompetitionDetailTab) {
        withAnimation(.spring(response: 0.16, dampingFraction: 0.74)) {
            pressedTab = tab
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            select(tab)
            withAnimation(.spring(response: 0.20, dampingFraction: 0.84)) {
                pressedTab = nil
            }
        }
    }

    private func select(_ tab: CompetitionDetailTab) {
        guard selection != tab else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
            selection = tab
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func snapToNearestTab(dragDistance: CGFloat) {
        let proposedCenter = selectedBaseOffset + dragDistance + selectedWidth / 2
        let nearest = tabs.min { lhs, rhs in
            let lhsDistance = abs((offset(for: lhs) + width(for: lhs) / 2) - proposedCenter)
            let rhsDistance = abs((offset(for: rhs) + width(for: rhs) / 2) - proposedCenter)
            return lhsDistance < rhsDistance
        }

        if let nearest {
            select(nearest)
        }
    }
}

private struct WCAInfoSectionStrip: View {
    let sections: [CompetitionDetailTextBlock]
    @Binding var selectionID: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(sections) { section in
                        Button {
                            guard selectionID != section.id else { return }
                            withAnimation(.snappy(duration: 0.28)) {
                                selectionID = section.id
                            }
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            VStack(spacing: 7) {
                                Text(section.title ?? "")
                                    .font(.system(size: 15, weight: selectionID == section.id ? .semibold : .regular))
                                    .foregroundStyle(selectionID == section.id ? .primary : .secondary)
                                    .lineLimit(1)

                                Capsule()
                                    .fill(selectionID == section.id ? Color.accentColor : Color.clear)
                                    .frame(height: 2)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(section.id)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onChange(of: selectionID) { newValue in
                guard !newValue.isEmpty else { return }
                withAnimation(.snappy(duration: 0.28)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(height: 42)
    }
}

private struct CompetitionTabWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private extension Dictionary where Key == String, Value == CGFloat {
    func isApproximatelyEqual(to other: [String: CGFloat]) -> Bool {
        guard count == other.count else { return false }
        return allSatisfy { entry in
            guard let otherValue = other[entry.key] else { return false }
            return abs(entry.value - otherValue) < 0.5
        }
    }
}

private struct CompetitionDetailTabMeasurementModifier: ViewModifier {
    let tabID: String

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CompetitionTabWidthPreferenceKey.self,
                    value: [tabID: proxy.size.width]
                )
            }
        )
    }
}

private enum CompetitionCompetitorsMode: String, CaseIterable, Identifiable {
    case registration
    case psych

    var id: String { rawValue }

    func localizedTitle(languageCode: String) -> String {
        switch self {
        case .registration:
            return localizedCompetitionStringInView(key: "competitions.detail.competitors_mode.registration", languageCode: languageCode)
        case .psych:
            return localizedCompetitionStringInView(key: "competitions.detail.competitors_mode.psych", languageCode: languageCode)
        }
    }
}

private enum WCACompetitorSortColumn: String {
    case name
    case representing
}

private enum WCAPsychSortColumn: String {
    case single
    case average
}

struct CompetitionLiveResultRow: Identifiable, Hashable {
    let id: String
    let rankText: String
    let numberText: String
    let name: String
    let bestResultText: String
    let averageResultText: String?
    let regionText: String?
    let detailText: String?
    var personWCAID: String? = nil
    var singleRecordTag: String? = nil
    var averageRecordTag: String? = nil
}

struct CompetitionLiveChatEntry: Identifiable, Hashable {
    let id: String
    let author: String
    let timestamp: Int
    let body: String
    let linkURL: URL?
    let isResult: Bool
}

@MainActor
final class CompetitionCubingLiveSession: ObservableObject {
    @Published var selectedRoundOptionID: String = ""
    @Published var selectedFilterValue: String = "all"
    @Published var onlineNumber: Int = 0
    @Published var resultRows: [CompetitionLiveResultRow] = []
    @Published var chatEntries: [CompetitionLiveChatEntry] = []
    @Published var isLoadingResults = false
    @Published var isLoadingMessages = false
    @Published var connectionError: String?
    @Published var showsMessagesInChat = true
    @Published var showsResultsInChat = true

    private struct LiveUser {
        let name: String
        let region: String?
    }

    private let session = URLSession(configuration: .default)
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var content: CompetitionLiveContent?
    private var usersByNumber: [Int: LiveUser] = [:]
    private var latestRawResults: [[String: Any]] = []
    private var liveStaticEntries: [CompetitionLiveChatEntry] = []
    private var liveMessageEntries: [CompetitionLiveChatEntry] = []
    private var hasFetchedMessages = false
    private(set) var modernSession: CubingChinaModernLiveSession?
    private var modernObservation: AnyCancellable?
    private var configuredTransport: AnyObject?
    private var consumedInitialRoundOptionID: String?
    private var language = "en"

    var roundOptions: [CompetitionLiveRoundOption] {
        if let modernSession {
            return CubingChinaLivePresentation.options(modernSession.rounds, snapshot: modernSession.snapshot, language: language)
        }
        return content?.roundOptions ?? []
    }

    var staticChatEntries: [CompetitionLiveChatEntry] {
        liveStaticEntries.sorted { lhs, rhs in lhs.timestamp < rhs.timestamp }
    }

    var recentChatEntries: [CompetitionLiveChatEntry] {
        liveMessageEntries.sorted { lhs, rhs in lhs.timestamp < rhs.timestamp }
    }

    func configure(with content: CompetitionLiveContent, language: String = "en",
                   transport: any CubingChinaLiveTransport = CubingChinaLiveHTTPClient.shared) {
        let isNewCompetition = self.content?.competitionID != content.competitionID
            || (self.content?.modern != nil) != (content.modern != nil)
        if isNewCompetition { consumedInitialRoundOptionID = nil }
        self.language = language
        if let bootstrap = content.modern {
            let transportOwner = transport as AnyObject
            if isNewCompetition || modernSession == nil || configuredTransport !== transportOwner {
                stop(); modernObservation = nil
                let modern = CubingChinaModernLiveSession(bootstrap: bootstrap, transport: transport)
                modernSession = modern
                modernObservation = modern.objectWillChange.sink { [weak self] _ in
                    Task { @MainActor [weak self] in self?.synchronizeModern() }
                }
                selectedRoundOptionID = bootstrap.defaultRound.key.selectionID
                resultRows = []; liveStaticEntries = []; liveMessageEntries = []; rebuildChatEntries()
            }
            configuredTransport = transportOwner
            self.content = content; synchronizeModern()
            return
        }
        if modernSession != nil { modernSession?.stop(); modernSession = nil; modernObservation = nil }
        self.content = content

        if isNewCompetition {
            selectedRoundOptionID = "\(content.defaultEventID)|\(content.defaultRoundID)"
            selectedFilterValue = content.defaultFilterValue
            usersByNumber = [:]
            latestRawResults = []
            onlineNumber = 0
            resultRows = []
            connectionError = nil
            hasFetchedMessages = false
            liveStaticEntries = content.staticMessages.map {
                CompetitionLiveChatEntry(
                    id: "static-\($0.id)",
                    author: $0.author,
                    timestamp: $0.timestamp,
                    body: $0.text,
                    linkURL: $0.linkURL,
                    isResult: false
                )
            }
            liveMessageEntries = []
            rebuildChatEntries()
        } else {
            if !content.roundOptions.contains(where: { $0.id == selectedRoundOptionID }) {
                selectedRoundOptionID = "\(content.defaultEventID)|\(content.defaultRoundID)"
            }
            if !content.filterOptions.contains(where: { $0.id == selectedFilterValue }) {
                selectedFilterValue = content.defaultFilterValue
            }
            liveStaticEntries = content.staticMessages.map {
                CompetitionLiveChatEntry(
                    id: "static-\($0.id)",
                    author: $0.author,
                    timestamp: $0.timestamp,
                    body: $0.text,
                    linkURL: $0.linkURL,
                    isResult: false
                )
            }
            rebuildChatEntries()
        }
    }

    func start() {
        if let modernSession {
            selectionDidChange(); modernSession.start(); return
        }
        guard receiveTask == nil else {
            Task {
                await fetchResults()
                await fetchMessagesIfNeeded(force: false)
            }
            return
        }

        guard let url = URL(string: "wss://cubing.com/ws") else { return }
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop(task: task)
        }

        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 150_000_000)
            await self.sendCompetitionSubscription()
            await self.fetchResults()
            await self.fetchMessagesIfNeeded(force: true)
        }
    }

    func stop() {
        modernSession?.stop()
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    func selectionDidChange() {
        if let modernSession, let round = modernSession.rounds.first(where: { $0.key.selectionID == selectedRoundOptionID }) {
            modernSession.select(round.key); return
        }
        Task { [weak self] in
            guard let self else { return }
            await self.fetchResults()
        }
    }

    func messagesPreferenceDidChange() {
        if modernSession != nil { rebuildChatEntries(); return }
        Task { [weak self] in
            guard let self else { return }
            await self.fetchMessagesIfNeeded(force: false)
        }
    }

    var currentRoundOption: CompetitionLiveRoundOption? {
        roundOptions.first(where: { $0.id == selectedRoundOptionID })
    }

    func applyInitialRoundOption(_ id: String?) {
        guard let id, consumedInitialRoundOptionID != id,
              roundOptions.contains(where: { $0.id == id }) else { return }
        consumedInitialRoundOptionID = id
        if selectedRoundOptionID != id { selectedRoundOptionID = id }
    }

    private func synchronizeModern() {
        guard let modern = modernSession else { return }
        if onlineNumber != modern.viewers { onlineNumber = modern.viewers }
        if isLoadingResults != modern.isLoadingResults { isLoadingResults = modern.isLoadingResults }
        if isLoadingMessages != modern.isLoadingMessages { isLoadingMessages = modern.isLoadingMessages }
        let error = (modern.resultError ?? modern.connectionError).map {
            appUserFacingErrorMessage($0, languageCode: language)
        }
        if connectionError != error { connectionError = error }
        let rows = (modern.snapshot?.rankedResults ?? []).map { value in
            let preview = CubingChinaLivePresentation.preview(value, language: language)
            return CompetitionLiveResultRow(id: preview.id, rankText: value.position.map(String.init) ?? "\u{2014}",
                numberText: value.competitor?.number.map(String.init) ?? "\u{2014}", name: preview.name,
                bestResultText: WCAResultFormatter.string(from: value.best, eventID: value.eventId),
                averageResultText: WCAResultFormatter.string(from: value.average, eventID: value.eventId, resultType: "average"),
                regionText: preview.region,
                detailText: value.attempts.map { WCAResultFormatter.string(from: $0, eventID: value.eventId, zeroRepresentation: "\u{2014}") }.joined(separator: "  "),
                personWCAID: preview.personWCAID, singleRecordTag: preview.singleRecordTag, averageRecordTag: preview.averageRecordTag)
        }
        if resultRows != rows { resultRows = rows }
        let messages = modern.messages.map { value in
            let date = ISO8601DateFormatter()
            date.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestamp = date.date(from: value.createdAt) ?? ISO8601DateFormatter().date(from: value.createdAt)
            return CompetitionLiveChatEntry(id: "ccc-message:\(value.id.rawValue)", author: value.user?.name ?? "",
                timestamp: timestamp.map { Int($0.timeIntervalSince1970) } ?? 0, body: value.content, linkURL: nil, isResult: false)
        }
        if liveMessageEntries != messages { liveMessageEntries = messages }
        rebuildChatEntries()
    }

    private func sendCompetitionSubscription() async {
        guard let competitionID = content?.competitionID else { return }
        await send([
            "type": "competition",
            "competitionId": competitionID
        ])
    }

    private func fetchResults() async {
        guard let round = currentRoundOption else { return }
        isLoadingResults = true
        await send([
            "type": "result",
            "action": "fetch",
            "params": [
                "event": round.eventID,
                "round": round.roundID,
                "filter": selectedFilterValue
            ]
        ])
    }

    private func fetchMessagesIfNeeded(force: Bool) async {
        guard showsMessagesInChat else {
            rebuildChatEntries()
            return
        }
        guard force || !hasFetchedMessages else { return }
        hasFetchedMessages = true
        isLoadingMessages = true
        await send([
            "type": "chat",
            "action": "fetch"
        ])
    }

    private func send(_ object: [String: Any]) async {
        guard let task = webSocketTask,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        do {
            try await task.send(.string(text))
        } catch {
            connectionError = appUserFacingErrorMessage(error, languageCode: currentAppLanguageCode())
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                let payloadText: String
                switch message {
                case .string(let string):
                    payloadText = string
                case .data(let data):
                    payloadText = String(data: data, encoding: .utf8) ?? ""
                @unknown default:
                    payloadText = ""
                }

                if payloadText.isEmpty { continue }
                handleIncomingMessage(payloadText)
            } catch {
                if Task.isCancelled { return }
                connectionError = appUserFacingErrorMessage(error, languageCode: currentAppLanguageCode())
                isLoadingResults = false
                isLoadingMessages = false
                return
            }
        }
    }

    private func handleIncomingMessage(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else {
            return
        }

        if let onlineNumber = json["onlineNumber"] as? Int {
            self.onlineNumber = onlineNumber
        }

        switch type {
        case "users":
            handleUsers(json["data"])
            rebuildResultRows()

        case "result.all":
            latestRawResults = (json["data"] as? [[String: Any]]) ?? []
            isLoadingResults = false
            rebuildResultRows()

        case "message.recent":
            handleRecentMessages(json["data"])

        case "message.new":
            if let entry = makeChatEntry(from: json["data"], fallbackIDPrefix: "live-message") {
                liveMessageEntries.append(entry)
                rebuildChatEntries()
            }

        case "result.new", "result.update":
            if showsResultsInChat, let entry = makeResultChatEntry(from: json["data"]) {
                liveMessageEntries.append(entry)
                rebuildChatEntries()
            }
            if let result = json["data"] as? [String: Any],
               currentRoundMatches(result: result) {
                replaceOrAppendResult(result)
                rebuildResultRows()
            }

        default:
            break
        }
    }

    private func handleUsers(_ payload: Any?) {
        guard let dictionary = payload as? [String: Any] else { return }
        var users: [Int: LiveUser] = [:]
        for (_, value) in dictionary {
            guard let user = value as? [String: Any],
                  let number = user["number"] as? Int else {
                continue
            }
            users[number] = LiveUser(
                name: user["name"] as? String ?? "",
                region: user["region"] as? String
            )
        }
        usersByNumber = users
    }

    private func handleRecentMessages(_ payload: Any?) {
        let entries = (payload as? [Any] ?? []).compactMap {
            makeChatEntry(from: $0, fallbackIDPrefix: "recent-message")
        }
        liveMessageEntries = entries
        isLoadingMessages = false
        rebuildChatEntries()
    }

    private func rebuildChatEntries() {
        let entries = showsMessagesInChat
            ? (staticChatEntries + recentChatEntries)
            : []
        if chatEntries != entries { chatEntries = entries }
    }

    private func rebuildResultRows() {
        guard let round = currentRoundOption else {
            resultRows = []
            return
        }

        let sortedResults = latestRawResults.sorted { lhs, rhs in
            compareLiveResults(lhs, rhs, for: round)
        }

        let rankValues = sortedResults.map { result in
            rankMetric(for: result, round: round)
        }

        var rows: [CompetitionLiveResultRow] = []
        var lastMetric: (Int, Int)?
        var lastRank = 0

        for (index, result) in sortedResults.enumerated() {
            let metric = rankValues[index]
            let rankText: String
            if metric == nil {
                rankText = "—"
            } else if let lastMetric, let metric, metric == lastMetric {
                rankText = "\(lastRank)"
            } else {
                lastRank = index + 1
                rankText = "\(lastRank)"
            }
            lastMetric = metric

            let number = result["n"] as? Int ?? 0
            let user = usersByNumber[number]
            let name = user?.name ?? "\(number)"
            let best = result["b"] as? Int ?? 0
            let average = result["a"] as? Int ?? 0
            let attempts = result["v"] as? [Int] ?? []

            let bestText = formatCompetitionLiveResultValue(best, eventID: round.eventID)
            let averageText = formatCompetitionLiveResultValue(average, eventID: round.eventID)

            rows.append(
                CompetitionLiveResultRow(
                    id: "\(result["i"] as? Int ?? index)",
                    rankText: rankText,
                    numberText: number > 0 ? "\(number)" : "—",
                    name: name,
                    bestResultText: bestText,
                    averageResultText: averageText.isEmpty ? nil : averageText,
                    regionText: user?.region,
                    detailText: attempts.isEmpty ? nil : attempts
                        .map { formatCompetitionLiveResultValue($0, eventID: round.eventID) }
                        .filter { !$0.isEmpty }
                        .joined(separator: "  ")
                )
            )
        }

        resultRows = rows
    }

    private func replaceOrAppendResult(_ result: [String: Any]) {
        let resultID = result["i"] as? Int
        if let resultID,
           let index = latestRawResults.firstIndex(where: { ($0["i"] as? Int) == resultID }) {
            latestRawResults[index] = result
        } else {
            latestRawResults.append(result)
        }
    }

    private func currentRoundMatches(result: [String: Any]) -> Bool {
        guard let round = currentRoundOption else { return false }
        return (result["e"] as? String) == round.eventID
            && (result["r"] as? String) == round.roundID
    }

    private func compareLiveResults(_ lhs: [String: Any], _ rhs: [String: Any], for round: CompetitionLiveRoundOption) -> Bool {
        let lhsMetric = rankMetric(for: lhs, round: round)
        let rhsMetric = rankMetric(for: rhs, round: round)

        switch (lhsMetric, rhsMetric) {
        case let (lhs?, rhs?):
            if lhs != rhs { return lhs < rhs }
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            break
        }

        let lhsNumber = lhs["n"] as? Int ?? .max
        let rhsNumber = rhs["n"] as? Int ?? .max
        return lhsNumber < rhsNumber
    }

    private func rankMetric(for result: [String: Any], round: CompetitionLiveRoundOption) -> (Int, Int)? {
        let best = result["b"] as? Int ?? 0
        let average = result["a"] as? Int ?? 0

        if usesCompetitionLiveAverage(formatID: round.formatID) {
            if average > 0 { return (average, best > 0 ? best : .max) }
            if best > 0 { return (Int.max - 1, best) }
            return nil
        }

        if best > 0 { return (best, average > 0 ? average : .max) }
        if average > 0 { return (average, .max) }
        return nil
    }

    private func makeChatEntry(from payload: Any?, fallbackIDPrefix: String) -> CompetitionLiveChatEntry? {
        guard let dictionary = payload as? [String: Any] else { return nil }
        let user = dictionary["user"] as? [String: Any]
        let rawContent = dictionary["content"] as? String ?? ""
        let body = competitionLiveDecodeHTMLEntities(rawContent)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: NSString.CompareOptions.regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: NSString.CompareOptions.regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        let identifier = (dictionary["id"] as? String).flatMap { "\($0)-\(dictionary["time"] as? Int ?? 0)" } ?? "\(fallbackIDPrefix)-\(UUID().uuidString)"
        let linkURL = competitionLiveFirstCapture(
            in: rawContent,
            pattern: #"href=\"([^\"]+)\""#
        ).flatMap(URL.init(string:))

        return CompetitionLiveChatEntry(
            id: identifier,
            author: user?["name"] as? String ?? "System",
            timestamp: dictionary["time"] as? Int ?? 0,
            body: body,
            linkURL: linkURL,
            isResult: false
        )
    }

    private func makeResultChatEntry(from payload: Any?) -> CompetitionLiveChatEntry? {
        guard let dictionary = payload as? [String: Any] else { return nil }
        let number = dictionary["n"] as? Int ?? 0
        let round = currentRoundOption
        let eventID = dictionary["e"] as? String ?? round?.eventID ?? ""
        let best = dictionary["b"] as? Int ?? 0
        let average = dictionary["a"] as? Int ?? 0
        let user = usersByNumber[number]
        let resultText = usesCompetitionLiveAverage(formatID: round?.formatID ?? "")
            ? formatCompetitionLiveResultValue(average, eventID: eventID)
            : formatCompetitionLiveResultValue(best, eventID: eventID)
        guard !resultText.isEmpty else { return nil }

        return CompetitionLiveChatEntry(
            id: "result-\(dictionary["i"] as? Int ?? Int.random(in: 1...999999))",
            author: "System",
            timestamp: Int(Date().timeIntervalSince1970),
            body: "\(user?.name ?? "\(number)") · \(resultText)",
            linkURL: nil,
            isResult: true
        )
    }
}

nonisolated private func competitionLiveFirstCapture(in text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
        return nil
    }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          match.numberOfRanges > 1,
          let captureRange = Range(match.range(at: 1), in: text) else {
        return nil
    }
    return String(text[captureRange])
}

nonisolated private func competitionLiveDecodeHTMLEntities(_ text: String) -> String {
    let replacements: [(String, String)] = [
        ("&quot;", "\""),
        ("&#34;", "\""),
        ("&apos;", "'"),
        ("&#39;", "'"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&amp;", "&"),
        ("&nbsp;", " ")
    ]

    var value = text
    for (source, target) in replacements {
        value = value.replacingOccurrences(of: source, with: target)
    }
    return value
}

private func usesCompetitionLiveAverage(formatID: String) -> Bool {
    formatID == "a" || formatID == "m"
}

private func formatCompetitionLiveResultValue(_ value: Int, eventID: String) -> String {
    WCAResultFormatter.string(from: value, eventID: eventID)
}

private func secondaryCompetitionLiveResultText(best: Int, average: Int, eventID: String) -> String? {
    let bestText = formatCompetitionLiveResultValue(best, eventID: eventID)
    let averageText = formatCompetitionLiveResultValue(average, eventID: eventID)

    if !averageText.isEmpty && !bestText.isEmpty {
        return "\(bestText) / \(averageText)"
    }
    if !bestText.isEmpty {
        return bestText
    }
    if !averageText.isEmpty {
        return averageText
    }
    return nil
}

private func competitionLiveShortEventTitle(for eventID: String, languageCode: String) -> String {
    CompetitionEventPresentation.localizedFullName(
        for: eventID,
        languageCode: languageCode
    )
}

private struct CompetitionEventIconPopoverButton: View {
    let glyph: String
    let eventTitle: String
    let size: CGFloat
    var color: Color = .primary
    var centersInkInCell = false

    @State private var showsEventName = false

    var body: some View {
        Button {
            showsEventName = true
        } label: {
            CompetitionEventGlyph(
                glyph: glyph,
                eventName: eventTitle,
                size: size,
                color: color
            )
                .offset(x: centersInkInCell
                    ? -(CompetitionEventIconFont.glyphMetrics(for: glyph, pointSize: size)?.centerOffset ?? 0)
                    : 0)
                .frame(minWidth: 30, minHeight: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(eventTitle)
        .background {
            VerticalTextPopoverPresenter(
                isPresented: $showsEventName,
                text: eventTitle,
                glyph: glyph,
                glyphFontName: CompetitionEventIconFont.fontName,
                glyphFontSize: size
            )
        }
    }
}

private struct CompetitionEventIconNameLabel: View {
    let glyph: String?
    let eventTitle: String
    let name: String
    var iconSize: CGFloat = 15
    var iconWidth: CGFloat = 22
    var spacing: CGFloat = 7
    var nameFont: Font = .system(size: 14, weight: .medium)
    var iconColor: Color = .primary
    var nameColor: Color = .primary
    var lineLimit: Int? = 2
    var showsIconPopover = true
    var reservesIconSpace = false

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            if let glyph {
                Group {
                    if showsIconPopover {
                        CompetitionEventIconPopoverButton(
                            glyph: glyph,
                            eventTitle: eventTitle,
                            size: iconSize,
                            color: iconColor
                        )
                    } else {
                        CompetitionEventGlyph(
                            glyph: glyph,
                            eventName: eventTitle,
                            size: iconSize,
                            color: iconColor
                        )
                    }
                }
                .frame(width: iconWidth, alignment: .center)
            } else if reservesIconSpace {
                Color.clear
                    .frame(width: iconWidth, height: 1)
            }

            Text(name)
                .font(nameFont)
                .foregroundStyle(nameColor)
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CompetitionLiveEventIconView: View {
    let eventID: String
    let languageCode: String
    let isReady: Bool
    var color: Color = .primary
    var size: CGFloat = 15

    var body: some View {
        if isReady, let glyph = CompetitionEventIconFont.glyph(for: eventID) {
            CompetitionEventGlyph(
                glyph: glyph,
                eventName: competitionLiveShortEventTitle(for: eventID, languageCode: languageCode),
                size: size,
                color: color
            )
        } else {
            Text(competitionLiveShortEventTitle(for: eventID, languageCode: languageCode))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }
}

private struct CompetitionWCALiveScheduleItem: Identifiable {
    let round: CompetitionWCALiveRound
    let startTime: Date
    let endTime: Date
    let colorHex: String?

    var id: String { round.id }
}

enum CompetitionWCALiveResultStatistic: Hashable {
    case average
    case best
}

private struct CompetitionWCALiveCompetitorEventGroup: Identifiable {
    let id: String
    let name: String
    let results: [CompetitionWCALiveCompetitorResult]
}

struct CompetitionWCARecordTagView: View {
    enum Variant {
        case standard
        case compact
    }

    let tag: String
    var usesLitePersonalRecord = false
    var variant: Variant = .compact
    var isOwnPersonalRecord = false

    @Environment(\.colorScheme) private var colorScheme

    private var displayTag: String { PublishedCompetitionResult.recordBadge(tag) ?? tag.uppercased() }

    var body: some View {
        Text(displayTag)
            .font(.system(size: isStandard ? 12 : 9.5, weight: .bold))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, isStandard ? 8 : 2.2)
            .padding(.vertical, isStandard ? 6 : 1)
            .frame(minWidth: isStandard ? nil : 0, minHeight: isStandard ? nil : 0)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: isStandard ? 4 : 4.5, style: .continuous))
            .fixedSize()
            .accessibilityLabel(displayTag)
    }

    private var isStandard: Bool {
        if case .standard = variant { return true }
        return false
    }

    private var backgroundColor: Color {
        switch displayTag {
        case "WR": Color(red: 244 / 255, green: 67 / 255, blue: 54 / 255)
        case "CR": Color(red: 255 / 255, green: 235 / 255, blue: 59 / 255)
        case "NR": Color(red: 0 / 255, green: 230 / 255, blue: 118 / 255)
        case "PR" where !isOwnPersonalRecord:
            colorScheme == .dark
                ? Color(red: 66 / 255, green: 66 / 255, blue: 66 / 255)
                : Color(red: 238 / 255, green: 238 / 255, blue: 238 / 255)
        case "PR": Color(red: 25 / 255, green: 118 / 255, blue: 210 / 255)
        default: Color.secondary.opacity(0.18)
        }
    }

    private var foregroundColor: Color {
        switch displayTag {
        case "CR", "NR": .black
        case "PR" where !isOwnPersonalRecord: colorScheme == .dark ? .white : .black
        case "WR", "PR": .white
        default: .primary
        }
    }
}

private struct CompetitionWCALiveRoundDetailView: View {
    @Environment(\.scenePhase) private var scenePhase

    private let initialRound: CompetitionWCALiveRound
    let competitionID: Int
    let languageCode: String
    let areEventIconsReady: Bool
    let resultDeepLink: CompetitionWCALiveResultDeepLink?
    let session: CompetitionWCALiveSession?

    @StateObject private var realtimeManager: CompetitionWCALiveRealtimeManager

    @StateObject private var resultCard = CompetitionResultCardState()

    init(
        round: CompetitionWCALiveRound,
        competitionID: Int,
        languageCode: String,
        areEventIconsReady: Bool,
        resultDeepLink: CompetitionWCALiveResultDeepLink? = nil,
        session: CompetitionWCALiveSession? = nil
    ) {
        initialRound = round
        self.competitionID = competitionID
        self.languageCode = languageCode
        self.areEventIconsReady = areEventIconsReady
        self.resultDeepLink = resultDeepLink
        self.session = session
        let cached = session?.knownRound(round, competitionID: competitionID, language: languageCode)
        _realtimeManager = StateObject(
            wrappedValue: CompetitionWCALiveRealtimeManager(
                round: cached ?? round,
                languageCode: languageCode,
                hasCachedSnapshot: cached != nil,
                snapshotSink: { [weak session] value in
                    session?.accept(value, competitionID: competitionID, language: languageCode)
                }
            )
        )
    }

    private var round: CompetitionWCALiveRound {
        realtimeManager.round
    }

    private var roundDisplayTitle: String {
        "\(CompetitionEventPresentation.normalizedName(for: round.eventID, fallback: round.eventName, languageCode: languageCode)) - \(round.roundName)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    ScrollAwareContentTitle(title: roundDisplayTitle)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)
                }

                if realtimeManager.roundContentState == .loaded, !realtimeManager.hasCurrentSnapshot {
                    Text(appLocalizedString("explore.cached", languageCode: languageCode))
                        .font(.caption).foregroundStyle(.secondary)
                }

                switch realtimeManager.roundContentState {
                case .loading:
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(
                            appLocalizedString(
                                "common.loading",
                                languageCode: languageCode,
                                defaultValue: "Loading…"
                            )
                        )
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)

                case .failed:
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(
                            appLocalizedString(
                                "common.unable_to_load",
                                languageCode: languageCode,
                                defaultValue: "Unable to load"
                            )
                        )
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)

                case .loaded where round.results.isEmpty:
                    VStack(spacing: 10) {
                        Image(systemName: "list.number")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(
                            appLocalizedString(
                                "competitions.detail.live.wca.no_results",
                                languageCode: languageCode,
                                defaultValue: "No results yet"
                            )
                        )
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)

                case .loaded:
                    CompetitionResultExperience(round: round, languageCode: languageCode, cardState: resultCard,
                        loadAllResults: liveCompetitorContent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemBackground))
        .scrollAwareNavigationTitle(roundDisplayTitle)
        .competitionResultsPresentation(state: resultCard, language: languageCode, round: round)
        .competitionDebugCompetition(String(competitionID))
        .onAppear {
            if let session {
                session.activate(realtimeManager, competitionID: competitionID, language: languageCode)
            } else { realtimeManager.start() }
            revealDeepLinkedResultIfAvailable()
        }
        .onDisappear {
            if let session { session.deactivate(realtimeManager) } else { realtimeManager.stop() }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                realtimeManager.resume()
            case .background:
                realtimeManager.suspend()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onChange(of: round.results) { _ in
            revealDeepLinkedResultIfAvailable()
        }
    }

    private func liveCompetitorContent(_ result: CompetitionWCALiveResultPreview) async -> CompetitionWCALiveCompetitorContent? {
        guard let id = result.personID else { return nil }
        return await CompetitionService.fetchWCALiveCompetitorContent(personID: id, languageCode: languageCode)
    }

    private func revealDeepLinkedResultIfAvailable() {
        guard resultCard.selection == nil, let result = resultDeepLink?.result(in: round) else { return }
        resultCard.present(result: result, round: round, loader: liveCompetitorContent)
    }
}

/// One card/list implementation for provisional Live and authoritative published data.
/// The source supplies All Results; the card never assumes a WCA ID is a Live person ID.
@MainActor
final class CompetitionResultCardState: ObservableObject {
    enum Entry { case round, competition }
    struct Selection {
        let result: CompetitionWCALiveResultPreview
        let round: CompetitionWCALiveRound
        let loader: ((CompetitionWCALiveResultPreview) async -> CompetitionWCALiveCompetitorContent?)?
        let isPublished: Bool
        let entry: Entry
    }
    @Published private(set) var selection: Selection?
    @Published var selectedCompetitorContent: CompetitionWCALiveCompetitorContent?
    @Published var isLoadingCompetitorContent = false
    @Published var competitorContentLoadFailed = false
    @Published var resultSummaryHeight: CGFloat = 0
    @Published var allResultsHeight: CGFloat = 0
    private var task: Task<Void, Never>?

    func present(result: CompetitionWCALiveResultPreview, round: CompetitionWCALiveRound,
                 isPublished: Bool = false,
                 entry: Entry = .round,
                 initialContent: CompetitionWCALiveCompetitorContent? = nil,
                 loader: ((CompetitionWCALiveResultPreview) async -> CompetitionWCALiveCompetitorContent?)?) {
        task?.cancel()
        // Install already available data before selection publishes and mounts the overlay.
        selectedCompetitorContent = initialContent; isLoadingCompetitorContent = false
        competitorContentLoadFailed = false; resultSummaryHeight = 0; allResultsHeight = 0
        withAnimation(.easeOut(duration: 0.18)) {
            selection = Selection(result: result, round: round, loader: loader, isPublished: isPublished, entry: entry)
        }
    }

    func presentCompetition(id: String, name: String, isPublished: Bool = false,
                            content: CompetitionWCALiveCompetitorContent? = nil,
                            loader: (() async -> CompetitionWCALiveCompetitorContent?)? = nil) {
        let preview = CompetitionWCALiveResultPreview(id: id, ranking: nil, personID: nil, personWCAID: content?.wcaID,
            name: name, region: content?.countryISO2, attempts: [], best: 0, average: 0, isAdvancing: nil,
            isAdvancingQuestionable: nil, singleRecordTag: nil, averageRecordTag: nil)
        // A presentation context, not an event/round selection or a provider route.
        let context = CompetitionWCALiveRound(id: "competition-all-results", eventID: "", eventName: "",
            roundName: "", number: nil, formatID: nil, numberOfAttempts: nil, sortBy: nil,
            isFinished: nil, advancementType: nil, advancementLevel: nil, isActive: false, isOpen: false, results: [])
        present(result: preview, round: context, isPublished: isPublished, entry: .competition,
            initialContent: content,
            loader: loader.map { load in { _ in await load() } })
        if content == nil { loadAllResults() }
    }

    func loadAllResults() {
        guard let selection, let loader = selection.loader, !isLoadingCompetitorContent else { return }
        isLoadingCompetitorContent = true; competitorContentLoadFailed = false
        task = Task {
            let content = await loader(selection.result)
            guard !Task.isCancelled, self.selection?.result.id == selection.result.id else { return }
            isLoadingCompetitorContent = false; competitorContentLoadFailed = content == nil
            if let content {
                withAnimation(.easeOut(duration: 0.18)) { allResultsHeight = 0; selectedCompetitorContent = content }
            }
        }
    }

    func close() {
        task?.cancel(); task = nil
        withAnimation(.easeIn(duration: 0.16)) {
            selection = nil; selectedCompetitorContent = nil
            isLoadingCompetitorContent = false; competitorContentLoadFailed = false
            resultSummaryHeight = 0; allResultsHeight = 0
        }
    }

    func cancelLoading() { task?.cancel(); task = nil; isLoadingCompetitorContent = false }

    func refreshPublishedRecordEvidence(_ data: PublishedCompetitionData, language: String) {
        guard let selection, selection.isPublished else { return }
        if let source = data.rounds.first(where: { "published-" + $0.id == selection.round.id }) {
            let updated = PublishedCompetitionPresentation.round(source, language: language, data: data)
            if let result = updated.results.first(where: { $0.id == selection.result.id }),
               result != selection.result || updated != selection.round {
                self.selection = Selection(result: result, round: updated, loader: selection.loader,
                    isPublished: true, entry: selection.entry)
            }
        }
        if let content = selectedCompetitorContent, let id = content.wcaID, content.id == id,
           let updated = PublishedCompetitionPresentation.competitor(id, data: data, language: language), updated != content {
            selectedCompetitorContent = updated
        }
    }
}

struct CompetitionResultExperience: View {
    enum Mode { case list, card, competitor }
    let round: CompetitionWCALiveRound
    let languageCode: String
    @ObservedObject var cardState: CompetitionResultCardState
    var mode: Mode = .list
    var showsHeader = true
    var isPublished = false
    var decoratesList = true
    var usesEagerRows = false
    var showsMyResultsShortcut = true
    var allowsProviderResultsLoader = false
    var showsCompetitorBack = true
    var loadAllResults: ((CompetitionWCALiveResultPreview) async -> CompetitionWCALiveCompetitorContent?)?
    var onFirstResult: () -> Void = {}
    var onResultVisible: (CompetitionWCALiveResultPreview) -> Void = { _ in }
    var onResultHidden: (CompetitionWCALiveResultPreview) -> Void = { _ in }
    var onRequestDismiss: (() -> Void)?
    @Environment(\.competitionProfilePresenter) private var profilePresenter
    @Environment(\.accessibilityReduceMotion) private var reducesContentMotion
    @ObservedObject private var auth = WCAAuthManager.shared
    #if DEBUG
    @Environment(\.competitionLivePreviewIdentity) private var previewIdentity
    #endif

    private var ownWCAID: String? {
        #if DEBUG
        if let previewIdentity { return previewIdentity }
        #endif
        return auth.isSignedIn ? auth.profile?.wcaId : nil
    }

    private var currentSelectedResult: CompetitionWCALiveResultPreview? {
        guard let selected = cardState.selection?.result else { return nil }
        return round.results.first { $0.id == selected.id } ?? selected
    }

    var body: some View {
        switch mode {
        case .list:
            Group {
                if usesEagerRows {
                    // Small final tables must end at the row, not a rounded lazy estimate.
                    VStack(spacing: 0) { resultListRows }
                } else {
                    LazyVStack(spacing: 0) { resultListRows }
                }
            }
            .competitionResultRowProbe("table-\(round.id)")
            .modifier(CompetitionResultListDecoration(enabled: decoratesList, darkShadow: isPublished))
        case .card:
            if let result = currentSelectedResult {
                resultDialog(result)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("competition-result-card")
            }
        case .competitor:
            if let content = cardState.selectedCompetitorContent { competitorResultsContent(content) }
            else if cardState.isLoadingCompetitorContent { ProgressView().frame(maxWidth: .infinity).padding(32) }
            else if cardState.competitorContentLoadFailed {
                Text(PublishedCompetitionStrings.text("live.results_unavailable", languageCode)).foregroundStyle(.secondary).padding()
            }
        }
    }

    @ViewBuilder private var resultListRows: some View {
        if !isPublished, showsMyResultsShortcut, let own = round.results.first(where: {
            CompetitionPersonalIdentity.matches(signedInWCAID: ownWCAID, competitorWCAID: $0.personWCAID)
        }) {
            Button(PublishedCompetitionStrings.text("live.my_results", languageCode)) {
                cardState.presentCompetition(id: own.id, name: own.name,
                    loader: own.personID == nil ? nil : loadAllResults.map { load in { await load(own) } })
            }
            .font(.subheadline).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
            .accessibilityIdentifier("competition-live-my-results")
        }
        if showsHeader { resultHeader; Divider() }
        ForEach(Array(round.results.enumerated()), id: \.element.id) { index, result in
            if index > 0 { Divider() }
            Button {
                cardState.present(result: result, round: round, isPublished: isPublished,
                    loader: isPublished || result.personID != nil || allowsProviderResultsLoader ? loadAllResults : nil)
            } label: { resultRow(result) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("competition-result-\(result.id)")
            .competitionResultRowProbe("button-\(result.id)")
            .onAppear { onResultVisible(result); if index == 0 { onFirstResult() } }
            .onDisappear { onResultHidden(result) }
        }
    }

    private var resultHeader: some View {
        CompetitionResultTableHeader(nameTitle: localizedCompetitionStringInView(
            key: "competitions.detail.competitors_column.name", languageCode: languageCode),
            columns: resultStatistics.map { statistic in
                CompetitionResultTableColumn(id: String(describing: statistic), title: resultStatisticTitle(statistic),
                    width: resultStatisticWidth(statistic))
            })
    }

    private func resultRow(_ result: CompetitionWCALiveResultPreview) -> some View {
        CompetitionResultTableRow(rank: result.ranking.map(String.init) ?? "", name: result.name,
            values: resultStatistics.map { statistic in
                CompetitionResultTableValue(id: String(describing: statistic),
                    text: resultStatisticValue(statistic, result: result),
                    recordTag: resultStatisticRecordTag(statistic, result: result), width: resultStatisticWidth(statistic))
            }, rankingForeground: resultRankingForegroundColor(result), rankingBackground: resultRankingBackgroundColor(result),
            isOwn: CompetitionPersonalIdentity.matches(signedInWCAID: ownWCAID, competitorWCAID: result.personWCAID), language: languageCode)
            .modifier(CompetitionPersonalRowTreatment(isOwn: CompetitionPersonalIdentity.matches(
                signedInWCAID: ownWCAID, competitorWCAID: result.personWCAID)))
            .competitionResultRowProbe("list-\(result.id)")
    }

    private func resultHeaderText(_ text: String, width: CGFloat?, alignment: Alignment) -> some View {
        CompetitionResultTableHeaderCell(text: text, width: width, alignment: alignment)
    }

    private func resultValue(_ value: String, recordTag: String?, width: CGFloat, emphasized: Bool) -> some View {
        CompetitionResultTableStatisticValue(text: value, recordTag: recordTag, width: width, emphasized: emphasized,
            isOwnRecord: CompetitionPersonalIdentity.matches(signedInWCAID: ownWCAID,
                competitorWCAID: cardState.selectedCompetitorContent?.wcaID))
    }

    private var resultStatistics: [CompetitionWCALiveResultStatistic] {
        if isPublished, !["a", "m"].contains(round.formatID ?? ""), round.results.allSatisfy({ $0.average == 0 }) {
            return [.best]
        }
        let attemptCount = round.numberOfAttempts
            ?? round.results.map(\.attempts.count).max()
            ?? 0
        let computesAverage = round.eventID != "333mbf"
            && [3, 5].contains(attemptCount)

        guard computesAverage else { return [.best] }
        let sortsByBest = round.sortBy?.lowercased() == "best"
            || (["1", "2", "3"].contains(round.formatID ?? "") && round.sortBy == nil)
        return sortsByBest ? [.best, .average] : [.average, .best]
    }

    private func resultStatisticTitle(_ statistic: CompetitionWCALiveResultStatistic) -> String {
        switch statistic {
        case .best:
            return appLocalizedString("common.best", languageCode: languageCode, defaultValue: "Best")
        case .average:
            if (round.numberOfAttempts ?? round.results.map(\.attempts.count).max()) == 3 {
                return appLocalizedString("wca.results_mean", languageCode: languageCode, defaultValue: "Mean")
            }
            return appLocalizedString("wca.results_average", languageCode: languageCode, defaultValue: "Average")
        }
    }

    private func resultStatisticWidth(_ statistic: CompetitionWCALiveResultStatistic) -> CGFloat {
        if isPublished, round.eventID.hasPrefix("333mb") { return 105 }
        return statistic == .average ? 72 : 62
    }

    private func resultRankingBackgroundColor(_ result: CompetitionWCALiveResultPreview) -> Color {
        CompetitionAdvancementStyle.background(advancing: result.isAdvancing, questionable: result.isAdvancingQuestionable)
    }

    private func resultRankingForegroundColor(_ result: CompetitionWCALiveResultPreview) -> Color {
        CompetitionAdvancementStyle.foreground(advancing: result.isAdvancing, questionable: result.isAdvancingQuestionable)
    }

    private func resultStatisticValue(
        _ statistic: CompetitionWCALiveResultStatistic,
        result: CompetitionWCALiveResultPreview
    ) -> String {
        if isPublished {
            return WCAResultFormatter.string(from: statistic == .average ? result.average : result.best,
                eventID: round.eventID, resultType: statistic == .average ? "average" : "single", zeroRepresentation: "\u{2014}")
        }
        return switch statistic {
        case .average: formatCompetitionLiveResultValue(result.average, eventID: round.eventID)
        case .best: formatCompetitionLiveResultValue(result.best, eventID: round.eventID)
        }
    }

    private func resultStatisticRecordTag(
        _ statistic: CompetitionWCALiveResultStatistic,
        result: CompetitionWCALiveResultPreview
    ) -> String? {
        switch statistic {
        case .average: result.averageRecordTag
        case .best: result.singleRecordTag
        }
    }

    private func resultDialog(_ result: CompetitionWCALiveResultPreview) -> some View {
        GeometryReader { proxy in
            let maximumCardHeight = CompetitionResultCardGeometry.maximumHeight(in: proxy.size)
            let cardWidth = CompetitionResultCardGeometry.width(in: proxy.size)
            let internalSwitch = cardState.selection?.entry == .round && cardState.resultSummaryHeight > 0
            let showsAll = cardState.selectedCompetitorContent != nil
                && (!internalSwitch || cardState.allResultsHeight > 0)

            ZStack {
                CompetitionResultBackdrop()
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { closeResultDialog() }

                ZStack {
                  Group {
                    if let content = cardState.selectedCompetitorContent, showsAll {
                        if cardState.allResultsHeight > maximumCardHeight {
                            ScrollView {
                                measuredCompetitorResultsContent(content, width: cardWidth)
                                    .frame(width: cardWidth)
                            }
                            .frame(height: maximumCardHeight)
                        } else {
                            measuredCompetitorResultsContent(content, width: cardWidth)
                                .frame(width: cardWidth)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if cardState.selection?.entry == .competition {
                        VStack(spacing: 12) {
                            Text(result.name).font(.title3.weight(.semibold))
                            if cardState.isLoadingCompetitorContent { ProgressView() }
                            else if cardState.competitorContentLoadFailed {
                                Text(PublishedCompetitionStrings.text("live.results_unavailable", languageCode)).foregroundStyle(.secondary)
                                Button(PublishedCompetitionStrings.text("retry", languageCode)) { cardState.loadAllResults() }
                            }
                        }.padding(28).padding(.trailing, 32)
                    } else if cardState.resultSummaryHeight > maximumCardHeight {
                        ScrollView {
                            measuredResultSummaryContent(result)
                        }
                        .frame(height: maximumCardHeight)
                    } else {
                        measuredResultSummaryContent(result)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .id(showsAll ? "all-results" : "round-results")
                .transition(internalSwitch && !reducesContentMotion ? .opacity : .identity)
                }
                .background(alignment: .topLeading) {
                    if internalSwitch, let content = cardState.selectedCompetitorContent, !showsAll {
                        measuredCompetitorResultsContent(content, width: cardWidth)
                            .frame(width: cardWidth).fixedSize(horizontal: false, vertical: true)
                            .hidden().allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .onPreferenceChange(ResultSummaryHeightPreferenceKey.self) { height in
                    guard height > 0, abs(cardState.resultSummaryHeight - height) > 0.5 else { return }
                    cardState.resultSummaryHeight = height
                }
                .onPreferenceChange(AllResultsHeightPreferenceKey.self) { measurements in
                    guard let content = cardState.selectedCompetitorContent,
                          let height = measurements[AllResultsMeasurement(content: content, width: cardWidth, language: languageCode)] else { return }
                    guard height > 0, abs(cardState.allResultsHeight - height) > 0.5 else { return }
                    withAnimation(internalSwitch && !reducesContentMotion ? .easeInOut(duration: 0.24) : nil) {
                        cardState.allResultsHeight = height
                    }
                }
                .frame(width: cardWidth)
                .competitionResultCardSurface()
                .overlay(alignment: .topTrailing) {
                    resultDialogCloseButton
                        .accessibilityIdentifier("competition-result-close")
                        .padding(12)
                }
                .competitionResultCardShadow()
                // This owner survives the child identity change in both directions.
                .animation(internalSwitch && !reducesContentMotion ? .easeInOut(duration: 0.24) : nil, value: showsAll)
                .competitionResultCardMotion()
                .competitionSeparatorCaptureControl()
            }
        }
    }

    private func resultSummaryContent(_ result: CompetitionWCALiveResultPreview) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(result.ranking.map { "\(result.name) #\($0)" } ?? result.name)
                .modifier(CompetitionResultCardTitleStyle())

            resultNameField(result)

            if let country = nonempty(result.region) {
                resultDetailField(
                    title: appLocalizedString(
                        "competitions.detail.live.wca.country",
                        languageCode: languageCode,
                        defaultValue: "Country"
                    ),
                    value: country
                )
            }

            if let attempts = formattedAttempts(result) {
                resultDetailField(
                    title: appLocalizedString(
                        "competitions.detail.live.wca.attempts",
                        languageCode: languageCode,
                        defaultValue: "Attempts"
                    ),
                    value: attempts
                )
            }

            ForEach(resultStatistics, id: \.self) { statistic in
                if let value = nonempty(resultStatisticValue(statistic, result: result)) {
                    resultDetailField(
                        title: resultStatisticTitle(statistic),
                        value: value,
                        recordTag: resultStatisticRecordTag(statistic, result: result)
                    )
                }
            }
        }
        .padding(CompetitionResultCardTitleStyle.contentInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .selectableContent()
    }

    private func measuredResultSummaryContent(_ result: CompetitionWCALiveResultPreview) -> some View {
        resultSummaryContent(result)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ResultSummaryHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            }
    }

    private func competitorResultsContent(_ content: CompetitionWCALiveCompetitorContent, width: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsCompetitorBack, cardState.selection?.entry != .competition { Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    cardState.selectedCompetitorContent = nil
                    cardState.allResultsHeight = 0
                }
            } label: {
                Label(
                    appLocalizedString("common.back", languageCode: languageCode, defaultValue: "Back"),
                    systemImage: "chevron.left"
                )
                .font(.system(size: 15, weight: .semibold))
            }.accessibilityIdentifier("competition-all-results-back") }

            Text(
                content.countryISO2.map {
                    "\(content.name) \(competitionFlagEmoji(for: $0))"
                } ?? content.name
            )
            .modifier(CompetitionResultCardTitleStyle())

            if let wcaID = nonempty(content.wcaID) {
                Group {
                    if let profilePresenter {
                        Button { profilePresenter(wcaID, content.name) } label: { profileLinkLabel }
                    } else {
                        NavigationLink { WCAProfileView(wcaID: wcaID, displayName: content.name) } label: { profileLinkLabel }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("competition-wca-profile")
            }

            ForEach(competitorEventGroups(content.results)) { group in
                VStack(alignment: .leading, spacing: 7) {
                    if group.id == "smart", content.id.hasPrefix("ccc-user:") {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            CubingChinaEventIcon(event: group.id, language: languageCode)
                            Text(group.name)
                        }.font(.system(size: 16, weight: .medium)).foregroundStyle(.primary)
                    } else {
                        Text(group.name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                    }

                    competitorEventResultsTable(group, allResults: content.results, viewportWidth: width.map { $0 - 44 })
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if content.results.isEmpty {
                Text(
                    appLocalizedString(
                        "competitions.detail.live.wca.no_results",
                        languageCode: languageCode,
                        defaultValue: "No results yet"
                    )
                )
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            }

        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .selectableContent()
    }

    private func measuredCompetitorResultsContent(
        _ content: CompetitionWCALiveCompetitorContent, width: CGFloat? = nil
    ) -> some View {
        competitorResultsContent(content, width: width)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: AllResultsHeightPreferenceKey.self,
                        value: [AllResultsMeasurement(content: content, width: width, language: languageCode): proxy.size.height]
                    )
                }
            }
    }

    private func competitorEventResultsTable(_ group: CompetitionWCALiveCompetitorEventGroup,
                                            allResults: [CompetitionWCALiveCompetitorResult], viewportWidth: CGFloat? = nil) -> some View {
        let columns = CompetitionAllResultsColumns(roundNames: allResults.map(\.roundName),
            averageTexts: allResults.filter { competitorResultStatistics($0).contains(.average) }.map {
                competitorResultStatisticValue(.average, result: $0)
            }, bestTexts: allResults.map { competitorResultStatisticValue(.best, result: $0) },
            hasAverage: allResults.contains { competitorResultStatistics($0).contains(.average) })
        let statistics = columns.statistics
        let roundWidth = columns.round
        let widths = columns.widths
        let reserves = columns.reserves
        let solves = CompetitionAllResultsSolves(results: group.results, language: languageCode)
        return CompetitionAdaptiveResultsTable(minimumWidth: columns.minimumWidth, viewportWidth: viewportWidth,
                                                additionalWidth: solves.width) { summaryWidth in
          VStack(spacing: 0) {
            CompetitionResultRoundRow(showsBoundary: true, boundaryAtBottom: true) {
            HStack(spacing: 0) {
            HStack(spacing: 0) {
                resultHeaderText("#", width: 34, alignment: .trailing)
                    .padding(.horizontal, 6)
                resultHeaderText(
                    appLocalizedString("competitions.detail.live.wca.round", languageCode: languageCode, defaultValue: "Round"),
                    width: roundWidth,
                    alignment: .leading
                )
                .padding(.leading, 8)

                Spacer(minLength: 0)

                ForEach(statistics, id: \.self) { statistic in
                    let sample = group.results.first { competitorResultStatistics($0).contains(statistic) }
                    resultHeaderText(
                        sample.map { competitorResultStatisticTitle(statistic, result: $0) } ?? "",
                        width: widths[statistic] ?? resultStatisticWidth(statistic),
                        alignment: .trailing
                    )
                    .padding(.leading, CompetitionAllResultsLayout.leading)
                    .padding(.trailing, reserves[statistic] ?? CompetitionAllResultsLayout.badgeReserve)
                }
            }
            .padding(.vertical, 6)
            .frame(width: summaryWidth)
            CompetitionAllResultsSolveCells(plan: solves, traceID: "\(group.id)-solve-header").padding(.vertical, 6)
            }
            }
            .competitionSeparatorIdentity(event: group.id, beforeID: nil, before: nil,
                afterID: group.results.first?.roundID ?? "", after: group.results.first?.roundName ?? "")

            ForEach(Array(group.results.enumerated()), id: \.element.id) { index, result in
              CompetitionResultRoundRow(showsBoundary: index > 0) {
                HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text(result.ranking.map(String.init) ?? "")
                        .font(.system(size: 14))
                        .foregroundStyle(competitorResultRankingForegroundColor(result))
                        .frame(width: 34, alignment: .trailing)
                        .frame(maxHeight: .infinity)
                        .padding(.horizontal, 6)
                        .background(competitorResultRankingBackgroundColor(result))

                    Text(result.roundName)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: roundWidth, alignment: .leading)
                        .padding(.leading, 8)

                    Spacer(minLength: 0)

                    ForEach(statistics, id: \.self) { statistic in
                        resultValue(
                            competitorResultStatistics(result).contains(statistic)
                                && (statistic == .average ? result.average : result.best) != 0
                                ? competitorResultStatisticValue(statistic, result: result) : "",
                            recordTag: competitorResultStatistics(result).contains(statistic) ? competitorResultStatisticRecordTag(statistic, result: result) : nil,
                            width: widths[statistic] ?? resultStatisticWidth(statistic),
                            emphasized: competitorResultStatistics(result).first == statistic
                        )
                        .padding(.leading, CompetitionAllResultsLayout.leading)
                        .padding(.trailing, reserves[statistic] ?? CompetitionAllResultsLayout.badgeReserve)
                    }
                }
                .frame(width: summaryWidth, height: 36)
                .competitionResultRowProbe(result.id)
                CompetitionAllResultsSolveCells(plan: solves, values: CompetitionAllResultsDisplay.attempts(result), traceID: "\(result.id)-solve")
                }
                .frame(height: 36)
              }
              .competitionSeparatorIdentity(event: group.id,
                  beforeID: index > 0 ? group.results[index - 1].roundID : nil,
                  before: index > 0 ? group.results[index - 1].roundName : nil,
                  afterID: result.roundID, after: result.roundName, index: index)
            }
        }
        .background(Color(uiColor: .tertiarySystemBackground))
        }
        .modifier(CompetitionResultListDecoration(enabled: true, darkShadow: true))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
        }
    }

    private var profileLinkLabel: some View {
        HStack(spacing: 8) {
            Image("wca_logo").resizable().scaledToFit().frame(width: 20, height: 20)
            Text("WCA Profile").font(.system(size: 15, weight: .semibold))
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
        }.foregroundStyle(.tint).contentShape(Rectangle())
    }

    private var resultDialogCloseButton: some View {
        CompetitionResultCardCloseButton(label: appLocalizedString(
            "competitions.detail.live.wca.close", languageCode: languageCode, defaultValue: "Close"),
            action: closeResultDialog)
    }

    private func resultNameField(_ result: CompetitionWCALiveResultPreview) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(
                appLocalizedString(
                    "competitions.detail.live.wca.name",
                    languageCode: languageCode,
                    defaultValue: "Name"
                )
            )
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)

            Text(result.name)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if cardState.selection?.loader != nil {
                Button {
                    loadCompetitorContent(for: result)
                } label: {
                    HStack(spacing: 7) {
                        if cardState.isLoadingCompetitorContent {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(
                            appLocalizedString(
                                "competitions.detail.live.wca.all_results",
                                languageCode: languageCode,
                                defaultValue: "All results"
                            )
                        )
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 15, weight: .semibold))
                }
                .disabled(cardState.isLoadingCompetitorContent)
                .padding(.top, 1)

                if cardState.competitorContentLoadFailed {
                    Text(
                        appLocalizedString(
                            "common.unable_to_load",
                            languageCode: languageCode,
                            defaultValue: "Unable to load"
                        )
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formattedAttempts(_ result: CompetitionWCALiveResultPreview) -> String? {
        let attempts = result.attempts.compactMap { attempt -> String? in
            nonempty(formatCompetitionLiveResultValue(attempt, eventID: round.eventID))
        }
        return nonempty(attempts.joined(separator: ", "))
    }

    private func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func competitorEventGroups(
        _ results: [CompetitionWCALiveCompetitorResult]
    ) -> [CompetitionWCALiveCompetitorEventGroup] {
        Dictionary(grouping: results, by: \.eventID)
            .compactMap { eventID, eventResults in
                guard let first = eventResults.first else { return nil }
                return CompetitionWCALiveCompetitorEventGroup(
                    id: eventID,
                    name: first.eventName,
                    results: eventResults.sorted {
                        ($0.roundNumber ?? Int.max) < ($1.roundNumber ?? Int.max)
                    }
                )
            }
            .sorted {
                ($0.results.first?.eventRank ?? Int.max) < ($1.results.first?.eventRank ?? Int.max)
            }
    }

    private func competitorResultStatistics(
        _ result: CompetitionWCALiveCompetitorResult
    ) -> [CompetitionWCALiveResultStatistic] {
        if isPublished, !["a", "m"].contains(result.formatID), result.average == 0 { return [.best] }
        guard result.eventID != "333mbf", [3, 5].contains(result.numberOfAttempts) else {
            return [.best]
        }
        return result.sortBy == "best" ? [.best, .average] : [.average, .best]
    }

    private func competitorResultStatisticTitle(
        _ statistic: CompetitionWCALiveResultStatistic,
        result: CompetitionWCALiveCompetitorResult
    ) -> String {
        switch statistic {
        case .best:
            return appLocalizedString("common.best", languageCode: languageCode, defaultValue: "Best")
        case .average:
            let key = result.numberOfAttempts == 3 ? "wca.results_mean" : "wca.results_average"
            let fallback = result.numberOfAttempts == 3 ? "Mean" : "Average"
            return appLocalizedString(key, languageCode: languageCode, defaultValue: fallback)
        }
    }

    private func competitorResultStatisticValue(
        _ statistic: CompetitionWCALiveResultStatistic,
        result: CompetitionWCALiveCompetitorResult
    ) -> String {
        CompetitionAllResultsDisplay.value(statistic, result: result)
    }

    private func competitorResultStatisticRecordTag(
        _ statistic: CompetitionWCALiveResultStatistic,
        result: CompetitionWCALiveCompetitorResult
    ) -> String? {
        switch statistic {
        case .best: result.singleRecordTag
        case .average: result.averageRecordTag
        }
    }

    private func competitorResultRankingBackgroundColor(
        _ result: CompetitionWCALiveCompetitorResult
    ) -> Color {
        CompetitionAdvancementStyle.background(advancing: result.isAdvancing, questionable: result.isAdvancingQuestionable)
    }

    private func competitorResultRankingForegroundColor(
        _ result: CompetitionWCALiveCompetitorResult
    ) -> Color {
        CompetitionAdvancementStyle.foreground(advancing: result.isAdvancing, questionable: result.isAdvancingQuestionable)
    }

    private func loadCompetitorContent(for result: CompetitionWCALiveResultPreview) {
        cardState.loadAllResults()
    }

    private func closeResultDialog() {
        if let onRequestDismiss { onRequestDismiss() } else { cardState.close() }
    }

    private func resultDetailField(title: String, value: String, recordTag: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            HStack(alignment: .top, spacing: 4) {
                Text(value)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let recordTag, !recordTag.isEmpty {
                    CompetitionWCARecordTagView(tag: recordTag, usesLitePersonalRecord: true, variant: .compact,
                        isOwnPersonalRecord: CubingLiveRecordIndicators.isOwnPR(recordTag, ownWCAID: ownWCAID,
                            competitorWCAID: currentSelectedResult?.personWCAID))
                        .offset(y: -3)
                }
            }
        }
    }
}

private struct ResultSummaryHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AllResultsMeasurement: Hashable {
    let content: CompetitionWCALiveCompetitorContent
    let width: CGFloat?
    let language: String
}
private struct AllResultsHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [AllResultsMeasurement: CGFloat] = [:]

    static func reduce(value: inout [AllResultsMeasurement: CGFloat], nextValue: () -> [AllResultsMeasurement: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct CompetitionCubingLiveSection: View {
    let content: CompetitionLiveContent
    let appLanguage: String
    let liveURL: URL?
    let areCompetitionEventIconsReady: Bool
    var initialRoundOptionID: String? = nil
    var initialPersonWCAID: String? = nil
    var modernTransport: any CubingChinaLiveTransport = CubingChinaLiveHTTPClient.shared
    var extrasTransport: (any CubingChinaLiveExtrasTransport)? = nil
    var openOfficialResults: (() -> Void)? = nil
    var chatPresentation: Binding<Bool>? = nil
    @ObservedObject var resultCard: CompetitionResultCardState
    private var transportForSession: any CubingChinaLiveTransport {
        #if DEBUG
        if let previewTransport { return previewTransport }
        #endif
        return modernTransport
    }

    @ObservedObject private var session: CompetitionCubingLiveSession
    @ObservedObject private var extras: CubingChinaLiveExtrasStore

    init(content: CompetitionLiveContent, appLanguage: String, liveURL: URL?, areCompetitionEventIconsReady: Bool,
         initialRoundOptionID: String? = nil, initialPersonWCAID: String? = nil,
         modernTransport: any CubingChinaLiveTransport = CubingChinaLiveHTTPClient.shared,
         extrasTransport: (any CubingChinaLiveExtrasTransport)? = nil,
         openOfficialResults: (() -> Void)? = nil, chatPresentation: Binding<Bool>? = nil,
         resultCard: CompetitionResultCardState, stores: CompetitionCubingLiveStores? = nil) {
        self.content = content; self.appLanguage = appLanguage; self.liveURL = liveURL
        self.areCompetitionEventIconsReady = areCompetitionEventIconsReady
        self.initialRoundOptionID = initialRoundOptionID; self.initialPersonWCAID = initialPersonWCAID
        self.modernTransport = modernTransport; self.extrasTransport = extrasTransport
        self.openOfficialResults = openOfficialResults; self.chatPresentation = chatPresentation
        self.resultCard = resultCard
        let entry = (stores ?? CompetitionCubingLiveStores()).entry(content: content, language: appLanguage, transport: modernTransport)
        _session = ObservedObject(wrappedValue: entry.session)
        _extras = ObservedObject(wrappedValue: entry.extras)
    }
    @State private var showsChat = false
    private var chatBinding: Binding<Bool> { chatPresentation ?? $showsChat }
    @State private var showsSumOfRanks = false
    @State private var showsPodiums = false
    @State private var didRevealInitialResult = false
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var auth = WCAAuthManager.shared
    #if DEBUG
    @Environment(\.competitionLivePreviewIdentity) private var previewIdentity
    @Environment(\.competitionLivePreviewTransport) private var previewTransport
    @Environment(\.competitionLivePreviewSheet) private var previewSheet
    @State private var didPresentPreviewSheet = false
    #endif

    private var ownWCAID: String? {
        #if DEBUG
        if let previewIdentity { return previewIdentity }
        #endif
        return auth.isSignedIn ? auth.profile?.wcaId : nil
    }

    private var modernRound: CompetitionWCALiveRound? {
        guard let modern = session.modernSession, let snapshot = modern.snapshot else { return nil }
        return CubingChinaLivePresentation.round(snapshot, rounds: modern.rounds, language: appLanguage,
            nextParticipants: modern.nextParticipants(for: snapshot.round))
    }

    private var selectedRoundOption: CompetitionLiveRoundOption? {
        session.roundOptions.first(where: { $0.id == session.selectedRoundOptionID })
    }

    private var groupedRoundOptions: [(title: String, options: [CompetitionLiveRoundOption])] {
        var grouped: [(title: String, options: [CompetitionLiveRoundOption])] = []
        for option in session.roundOptions {
            if let index = grouped.firstIndex(where: { $0.title == option.eventName }) {
                grouped[index].options.append(option)
            } else {
                grouped.append((title: option.eventName, options: [option]))
            }
        }
        return grouped
    }

    private var recentChatEntryIDs: [String] {
        session.recentChatEntries.map(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if content.modern != nil {
                if let modern = session.modernSession {
                    CubingChinaUnifiedLiveContent(session: modern, extras: extras, card: resultCard,
                        roundSelection: $session.selectedRoundOptionID, language: appLanguage,
                        loadCompetitor: loadModernCompetitor, ownWCAID: ownWCAID,
                        openCompetitor: { presentModernCompetitor($0) }) { modernNavigationActions }
                    if (modern.resultError != nil || modern.connectionError != nil), let liveURL {
                        Link(PublishedCompetitionStrings.text("live.website", appLanguage), destination: liveURL)
                            .font(.footnote)
                    }
                } else { ProgressView() }
            } else {
                actionBar
                controlBar
                if let selectedRoundOption { roundSummaryCard(selectedRoundOption) }
                resultsCard
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                if chatPresentation == nil {
                    Spacer()
                    CompetitionLiveChatButton(language: appLanguage) { chatBinding.wrappedValue = true }
                }
            }
        }
        .task(id: content.competitionID) {
            session.configure(with: content, language: appLanguage, transport: transportForSession)
            session.applyInitialRoundOption(initialRoundOptionID)
            session.start()
            refreshExtras()
        }
        .onChange(of: content.competitionID) { _ in
            resultCard.close()
            session.configure(with: content, language: appLanguage, transport: transportForSession)
            session.start()
            refreshExtras()
        }
        .onChange(of: session.selectedRoundOptionID) { _ in
            resultCard.close()
            session.selectionDidChange()
        }
        .onChange(of: session.selectedFilterValue) { _ in
            session.selectionDidChange()
        }
        .onChange(of: session.showsMessagesInChat) { _ in
            session.messagesPreferenceDidChange()
        }
        .onDisappear {
            session.stop(); extras.stop(); resultCard.close()
        }
        .onChange(of: scenePhase) { phase in
            guard content.modern != nil else { return }
            if phase == .background { session.stop(); extras.stop(); resultCard.cancelLoading() }
            if phase == .active { session.start(); refreshExtras() }
        }
        .onChange(of: session.modernSession?.aggregateRefreshID) { _ in refreshExtras() }
        .onChange(of: session.resultRows) { _ in
            guard !didRevealInitialResult, let person = initialPersonWCAID, let round = modernRound,
                  let result = round.results.first(where: {
                      CompetitionPersonalIdentity.matches(signedInWCAID: person, competitorWCAID: $0.personWCAID)
                  }) else { return }
            didRevealInitialResult = true; openResult(result.id)
        }
        #if DEBUG
        .onChange(of: session.resultRows) { _ in
            guard !didPresentPreviewSheet, !session.resultRows.isEmpty, let previewSheet else { return }
            didPresentPreviewSheet = true
            if previewSheet == "chat" { chatBinding.wrappedValue = true }
            if previewSheet == "my_results" { presentMyResults() }
        }
        #endif
        .sheet(isPresented: chatBinding) {
            CompatibleNavigationContainer {
                ScrollView { chatCard.padding(16) }
                    .navigationTitle(localizedCompetitionStringInView(key: "competitions.detail.live.chat", languageCode: appLanguage))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                        Button(PublishedCompetitionStrings.text("done", appLanguage)) { chatBinding.wrappedValue = false }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Menu {
                            Toggle(localizedCompetitionStringInView(key: "competitions.detail.live.settings.show_messages", languageCode: appLanguage), isOn: $session.showsMessagesInChat)
                            if content.modern == nil {
                                Toggle(localizedCompetitionStringInView(key: "competitions.detail.live.settings.show_results", languageCode: appLanguage), isOn: $session.showsResultsInChat)
                            }
                        } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                        .accessibilityLabel(localizedCompetitionStringInView(key: "competitions.detail.live.settings", languageCode: appLanguage))
                    } }
            }
        }
        .sheet(isPresented: $showsSumOfRanks) {
            CompatibleNavigationContainer {
                CompetitionLiveSumOfRanksSheet(
                    content: content.sumOfRanksContent,
                    appLanguage: appLanguage,
                    areCompetitionEventIconsReady: areCompetitionEventIconsReady
                )
            }
        }
        .sheet(isPresented: $showsPodiums) {
            CompatibleNavigationContainer {
                CompetitionLivePodiumsSheet(
                    sections: content.podiumSections,
                    appLanguage: appLanguage
                )
            }
        }
    }

    private var actionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if let round = modernRound, let own = round.results.first(where: {
                    CompetitionPersonalIdentity.matches(signedInWCAID: ownWCAID, competitorWCAID: $0.personWCAID)
                }) {
                    Button { openResult(own.id) } label: {
                        liveActionPill(title: PublishedCompetitionStrings.text("live.my_results", appLanguage), systemImage: "person.crop.rectangle")
                    }.buttonStyle(.plain).accessibilityIdentifier("competition-live-my-results")
                }
                if content.sumOfRanksContent != nil || content.sumOfRanksURL != nil {
                    Button {
                        showsSumOfRanks = true
                    } label: {
                        liveActionPill(
                            title: localizedCompetitionStringInView(key: "competitions.detail.live.sum_of_ranks", languageCode: appLanguage),
                            systemImage: "sum"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if !content.podiumSections.isEmpty || content.podiumsURL != nil {
                    Button {
                        showsPodiums = true
                    } label: {
                        liveActionPill(
                            title: localizedCompetitionStringInView(key: "competitions.detail.live.podiums", languageCode: appLanguage),
                            systemImage: "medal"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let liveURL {
                    Link(destination: liveURL) {
                        liveActionPill(
                            title: localizedCompetitionStringInView(key: "competitions.detail.open_live", languageCode: appLanguage),
                            systemImage: "safari"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var controlBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(groupedRoundOptions, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.options) { option in
                                Button {
                                    session.selectedRoundOptionID = option.id
                                } label: {
                                    Text(option.roundName)
                                    if let tag = session.modernSession?.roundRecordTags(in: extras)[option.id] {
                                        CompetitionWCARecordTagView(tag: tag, variant: .compact)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        liveControlPill(
                            title: selectedRoundOption.map(roundLabel) ?? localizedCompetitionStringInView(key: "competitions.detail.live.round", languageCode: appLanguage),
                            systemImage: "list.bullet"
                        )
                        if let tag = session.modernSession?.roundRecordTags(in: extras)[session.selectedRoundOptionID] {
                            CompetitionWCARecordTagView(tag: tag, variant: .compact)
                        }
                    }
                }
                .buttonStyle(.plain)
                .tint(.primary)
                .accessibilityIdentifier("competition-ccc-round-selector")

                if !content.filterOptions.isEmpty { Menu {
                    ForEach(content.filterOptions) { filter in
                        Button {
                            session.selectedFilterValue = filter.id
                        } label: {
                            Text(filter.label)
                        }
                    }
                } label: {
                    let selectedFilter = content.filterOptions.first(where: { $0.id == session.selectedFilterValue })?.label
                        ?? localizedCompetitionStringInView(key: "competitions.detail.live.filter", languageCode: appLanguage)
                    liveControlPill(
                        title: selectedFilter,
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }
                .buttonStyle(.plain)
                .tint(.primary)
                }
            }
        }
    }

    private func roundSummaryCard(_ round: CompetitionLiveRoundOption) -> some View {
        liveCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    CompetitionEventIconNameLabel(
                        glyph: areCompetitionEventIconsReady
                            ? CompetitionEventIconFont.glyph(for: round.eventID, title: roundLabel(round))
                            : nil,
                        eventTitle: competitionLiveShortEventTitle(for: round.eventID, languageCode: appLanguage),
                        name: roundLabel(round),
                        iconSize: 18,
                        iconWidth: 22,
                        spacing: 8,
                        nameFont: .system(size: 16, weight: .semibold),
                        iconColor: .orange,
                        lineLimit: 2
                    )
                    Spacer()
                    if session.onlineNumber > 0 {
                        Text(String(
                            format: localizedCompetitionStringInView(key: "competitions.detail.live.online_count", languageCode: appLanguage),
                            session.onlineNumber
                        ))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                }

                Text(
                    String(
                        format: localizedCompetitionStringInView(key: "competitions.detail.live.progress", languageCode: appLanguage),
                        round.recordedCount,
                        max(round.totalCount - round.recordedCount, 0),
                        round.totalCount
                    )
                )
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

                if let error = session.connectionError, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let modern = session.modernSession {
                        Button(PublishedCompetitionStrings.text("retry", appLanguage)) { modern.retry() }
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private var resultsCard: some View {
        liveCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(localizedCompetitionStringInView(key: "competitions.detail.live.results", languageCode: appLanguage))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                if session.isLoadingResults {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(localizedCompetitionStringInView(key: "competitions.loading", languageCode: appLanguage))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else if session.modernSession?.resultError != nil && session.resultRows.isEmpty {
                    Text(PublishedCompetitionStrings.text("live.results_unavailable", appLanguage))
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if session.resultRows.isEmpty {
                    Text(localizedCompetitionStringInView(key: "competitions.detail.live.results_empty", languageCode: appLanguage))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(session.resultRows) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    Text(row.rankText)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.orange)
                                        .frame(width: 24, alignment: .leading)

                                    Text(row.numberText)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        if let regionText = row.regionText, !regionText.isEmpty {
                                            Text(regionText)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer(minLength: 8)

                                    VStack(alignment: .trailing, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(localizedCompetitionStringInView(key: "common.best", languageCode: appLanguage))
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.secondary)
                                            Text(row.bestResultText.isEmpty ? "—" : row.bestResultText)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(.primary)
                                            if let tag = row.singleRecordTag {
                                                CompetitionWCARecordTagView(tag: tag, variant: .compact)
                                            }
                                        }

                                        if let average = row.averageResultText, !average.isEmpty {
                                            HStack(spacing: 6) {
                                                Text(localizedCompetitionStringInView(key: "wca.results_average", languageCode: appLanguage))
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(.secondary)
                                                Text(average)
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(.secondary)
                                                if let tag = row.averageRecordTag {
                                                    CompetitionWCARecordTagView(tag: tag, variant: .compact)
                                                }
                                            }
                                        }
                                    }
                                }

                                if let detailText = row.detailText, !detailText.isEmpty {
                                    Text(detailText)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                if row.id != session.resultRows.last?.id {
                                    Divider()
                                }
                            }
                            .modifier(CompetitionPersonalRowTreatment(isOwn: CompetitionPersonalIdentity.matches(
                                signedInWCAID: ownWCAID, competitorWCAID: row.personWCAID)))
                            .contentShape(Rectangle())
                            .simultaneousGesture(TapGesture().onEnded { openResult(row.id) },
                                including: content.modern == nil ? .none : .all)
                            .accessibilityIdentifier("competition-ccc-result-\(row.id)")
                        }
                    }
                }
            }
        }
    }

    private var chatCard: some View {
        liveCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(localizedCompetitionStringInView(key: "competitions.detail.live.chat", languageCode: appLanguage))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                if content.modern != nil {
                    Text(PublishedCompetitionStrings.text("live.chat_read_only", appLanguage))
                        .font(.caption).foregroundStyle(.secondary)
                }

                if session.modernSession?.chatError != nil {
                    Text(PublishedCompetitionStrings.text("live.chat_unavailable", appLanguage))
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let liveURL { Link(PublishedCompetitionStrings.text("live.chat_website", appLanguage), destination: liveURL) }
                } else if session.isLoadingMessages {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(localizedCompetitionStringInView(key: "competitions.loading", languageCode: appLanguage))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else if session.chatEntries.isEmpty {
                    Text(localizedCompetitionStringInView(key: "competitions.detail.live.chat_empty", languageCode: appLanguage))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    if !session.staticChatEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(session.staticChatEntries) { entry in
                                chatEntryView(entry, isLast: entry.id == session.staticChatEntries.last?.id)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.orange.opacity(0.08))
                        )
                    }

                    if !session.recentChatEntries.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(session.recentChatEntries) { entry in
                                        chatEntryView(entry, isLast: entry.id == session.recentChatEntries.last?.id)
                                            .id(entry.id)
                                    }

                                    Color.clear
                                        .frame(height: 1)
                                        .id("chat-bottom-anchor")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(maxHeight: 280)
                            .onAppear {
                                scrollChatToBottom(using: proxy, animated: false)
                            }
                            .onChange(of: recentChatEntryIDs) { _ in
                                scrollChatToBottom(using: proxy, animated: true)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chatEntryView(_ entry: CompetitionLiveChatEntry, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(entry.author)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.isResult ? .orange : .primary)
                if entry.timestamp > 0 {
                    Text(competitionLiveFormattedChatTime(entry.timestamp))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(entry.body)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let linkURL = entry.linkURL {
                Link(destination: linkURL) {
                    Text(linkURL.absoluteString)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            if !isLast {
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scrollChatToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                action()
            }
        } else {
            action()
        }
    }

    private func refreshExtras() {
        guard let bootstrap = content.modern,
              let transport = extrasTransport ?? (transportForSession as? any CubingChinaLiveExtrasTransport) else { return }
        let current = (try? CubingChinaLiveBootstrap.make(slug: bootstrap.slug, rounds: session.modernSession?.rounds ?? bootstrap.rounds)) ?? bootstrap
        extras.refresh(current, transport: transport)
    }

    private func loadModernCompetitor(_ result: CompetitionWCALiveResultPreview) async -> CompetitionWCALiveCompetitorContent? {
        guard let modern = session.modernSession else { return nil }
        let known = (modern.snapshot?.results ?? []) + extras.records + extras.podiums.flatMap(\.results)
        let number = known.first(where: { "ccc-result:\($0.id.rawValue)" == result.id })?.competitor?.number
            ?? extras.sums.first(where: { CompetitionPersonalIdentity.matches(signedInWCAID: result.personWCAID, competitorWCAID: $0.competitor.wcaId) })?.competitor.number
        guard let number,
              let values = await modern.competitorResults(number: number) else { return nil }
        return CubingChinaLivePresentation.competitor(values, rounds: modern.rounds, language: appLanguage,
            knownAdvancement: modern.knownAdvancement)
    }

    private var knownPersonalCompetitor: CubingChinaLiveResult.Competitor? {
        let values = (session.modernSession?.snapshot?.results ?? []) + extras.records + extras.podiums.flatMap(\.results)
        return CubingChinaPersonalShortcut.competitor(signedInWCAID: ownWCAID, results: values, sums: extras.sums)
    }

    private var modernNavigationActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let openOfficialResults {
                    Button(action: openOfficialResults) {
                        Label(PublishedCompetitionStrings.text("live.official_results", appLanguage), systemImage: "list.number")
                            .modifier(CompetitionNativeActionCapsule(tint: CubingChinaNavigationColors.Section.results.foreground))
                    }.buttonStyle(.plain).accessibilityIdentifier("competition-live-official-results")
                }
                let streams = content.photoStreams ?? []
                if streams.count == 1, let stream = streams.first {
                    Link(destination: stream.url) {
                        Label(PublishedCompetitionStrings.text("live.stream", appLanguage), systemImage: "camera")
                            .modifier(CompetitionNativeActionCapsule(tint: .orange))
                    }.buttonStyle(.plain).accessibilityIdentifier("competition-live-stream")
                } else if streams.count > 1 {
                    Menu {
                        ForEach(streams, id: \.url) { stream in Link(stream.title, destination: stream.url) }
                    } label: {
                        Label(PublishedCompetitionStrings.text("live.stream", appLanguage), systemImage: "camera")
                            .modifier(CompetitionNativeActionCapsule(tint: .orange))
                    }.accessibilityIdentifier("competition-live-stream")
                }
                if knownPersonalCompetitor != nil {
                    Button(action: presentMyResults) {
                        Label(PublishedCompetitionStrings.text("live.my_results", appLanguage), systemImage: "person.crop.rectangle")
                            .modifier(CompetitionNativeActionCapsule(tint: .blue))
                    }.buttonStyle(.plain).accessibilityIdentifier("competition-live-my-results")
                }
            }
        }
    }

    private func presentMyResults() {
        guard let competitor = knownPersonalCompetitor else { return }
        presentModernCompetitor(competitor, requiresPersonalIdentity: true)
    }

    private func presentModernCompetitor(_ competitor: CubingChinaLiveResult.Competitor, requiresPersonalIdentity: Bool = false) {
        guard let modern = session.modernSession, let number = competitor.number, number > 0 else { return }
        resultCard.presentCompetition(id: "ccc-user:\(competitor.id.rawValue)", name: competitor.name) {
            let values = await modern.competitorResults(number: number)
            guard let values, !values.isEmpty,
                  values.allSatisfy({ value in
                      value.competitor?.id == competitor.id && modern.rounds.contains { value.belongs(to: $0) }
                          && (!requiresPersonalIdentity || CompetitionPersonalIdentity.matches(signedInWCAID: ownWCAID, competitorWCAID: value.competitor?.wcaId))
                  }) else { return nil }
            return CubingChinaLivePresentation.competitor(values, rounds: modern.rounds, language: appLanguage,
                knownAdvancement: modern.knownAdvancement)
        }
    }

    private func openResult(_ id: String) {
        guard let modern = session.modernSession, let round = modernRound,
              let result = round.results.first(where: { $0.id == id }) else { return }
        let number = modern.snapshot?.results.first(where: { "ccc-result:\($0.id.rawValue)" == id })?.competitor?.number
        resultCard.present(result: result, round: round, loader: number.map { number in
            { _ in
                guard let values = await modern.competitorResults(number: number) else { return nil }
                return CubingChinaLivePresentation.competitor(values, rounds: modern.rounds, language: appLanguage,
                    knownAdvancement: modern.knownAdvancement)
            }
        })
    }

    private func roundLabel(_ option: CompetitionLiveRoundOption) -> String {
        if let statusText = option.statusText, !statusText.isEmpty {
            return "\(option.eventName) · \(option.roundName) · \(statusText)"
        }
        return "\(option.eventName) · \(option.roundName)"
    }

    private func liveCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }

    private func liveActionPill(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
    }

    private func liveControlPill(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.primary)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private func competitionLiveFormattedChatTime(_ timestamp: Int) -> String {
    guard timestamp > 0 else { return "" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MM-dd HH:mm:ss"
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}

private struct CompetitionLiveSumOfRanksSheet: View {
    let content: CompetitionLiveSumOfRanksContent?
    let appLanguage: String
    let areCompetitionEventIconsReady: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let content, !content.entries.isEmpty {
                ForEach(content.entries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text(entry.placeText)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.orange)
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(.system(size: 15, weight: .semibold))
                                if !entry.region.isEmpty {
                                    Text(entry.region)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(localizedCompetitionStringInView(key: "competitions.detail.live.total", languageCode: appLanguage))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text(entry.totalText)
                                    .font(.system(size: 15, weight: .semibold))
                            }
                        }

                        if !entry.items.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(entry.items) { item in
                                        HStack(spacing: 6) {
                                            CompetitionLiveEventIconView(
                                                eventID: item.eventID,
                                                languageCode: appLanguage,
                                                isReady: areCompetitionEventIconsReady,
                                                color: .orange,
                                                size: 14
                                            )
                                            Text(item.rankText)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.primary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text(localizedCompetitionStringInView(key: "competitions.detail.live.local_empty", languageCode: appLanguage))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(localizedCompetitionStringInView(key: "competitions.detail.live.sum_of_ranks", languageCode: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(localizedCompetitionStringInView(key: "common.done", languageCode: appLanguage)) {
                    dismiss()
                }
            }
        }
    }
}

private struct CompetitionLivePodiumsSheet: View {
    let sections: [CompetitionLivePodiumSection]
    let appLanguage: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if sections.isEmpty || sections.allSatisfy({ $0.placements.isEmpty }) {
                Text(localizedCompetitionStringInView(key: "competitions.detail.live.local_empty", languageCode: appLanguage))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sections) { section in
                    Section(section.title ?? localizedCompetitionStringInView(key: "competitions.detail.live.podiums", languageCode: appLanguage)) {
                        ForEach(section.placements) { placement in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    Text(placement.placeText)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.orange)
                                        .frame(width: 28, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(placement.name)
                                            .font(.system(size: 15, weight: .semibold))
                                        if !placement.region.isEmpty {
                                            Text(placement.region)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                HStack(spacing: 12) {
                                    if !placement.bestText.isEmpty {
                                        Text("\(localizedCompetitionStringInView(key: "common.best", languageCode: appLanguage)) \(placement.bestText)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    if !placement.averageText.isEmpty {
                                        Text("\(localizedCompetitionStringInView(key: "wca.results_average", languageCode: appLanguage)) \(placement.averageText)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle(localizedCompetitionStringInView(key: "competitions.detail.live.podiums", languageCode: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(localizedCompetitionStringInView(key: "common.done", languageCode: appLanguage)) {
                    dismiss()
                }
            }
        }
    }
}

private struct CompetitionWCALiveSectionHeadingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func wcaLiveSectionHeadingStyle() -> some View {
        modifier(CompetitionWCALiveSectionHeadingModifier())
    }
}

struct CompetitionDetailView: View {
    let competition: CompetitionSummary
    let appLanguage: String
    let initialWCALiveResultDeepLink: CompetitionWCALiveResultDeepLink?
    private let explicitlyOpenedLive: Bool
    private let explicitlyOpenedPublishedResult: Bool

    @StateObject private var publishedStore = PublishedCompetitionStore()
    @StateObject private var publishedRecordEvidence = PublishedCompetitionRecordEnrichment()
    @StateObject private var cubingLiveStores = CompetitionCubingLiveStores()
    @StateObject private var wcaLiveSession = CompetitionWCALiveSession()
    @ObservedObject private var auth = WCAAuthManager.shared
    @StateObject private var publishedResultCard = CompetitionResultCardState()
    @State private var selectedPublishedInfoSection: CompetitionDetailTab = .info
    @State private var pendingPublishedResultDeepLink: PublishedCompetitionResultDeepLink?

    @State private var selectedTab: CompetitionDetailTab = .info
    @State private var selectedWCAInfoSectionID = ""
    @State private var detailContent: CompetitionDetailContent = .empty
    @State private var detailContentIdentity = ""
    @State private var staleCachedDetailResources: Set<CompetitionDetailResource> = []
    @State private var loadingLifecycle = CompetitionLoadingLifecycle()
    @State private var detailReloadGeneration = 0
    private var pendingDetailResources: Set<CompetitionDetailResource> { loadingLifecycle.detailResources }
    private var isLoadingDetail: Bool { !pendingDetailResources.subtracting([.live, .competitors]).isEmpty }
    @State private var detailOpenedAt = CACurrentMediaTime()
    @State private var competitorSearchText = ""
    @State private var selectedCompetitorEventID: String = ""
    @State private var selectedCompetitorsMode: CompetitionCompetitorsMode = .registration
    @State private var areCompetitionEventIconsReady = CompetitionEventIconFont.isAvailable
    @State private var isLoadingPsych = false
    @State private var isLoadingCompetitors = false
    @State private var psychPreviewCache: [String: [CompetitionCompetitorPsychPreview]] = [:]
    @State private var psychInFlightKeys: Set<String> = []
    @State private var isLoadingWCALive = false
    @State private var wcaLiveContentOverride: CompetitionWCALiveContent?
    @State private var didAttemptInitialWCALiveRoundLoad = false
    @State private var selectedWCALiveRoundID = ""
    @State private var isPresentingInitialWCALiveResult = false
    @State private var didPresentInitialWCALiveResult = false
    @State private var selectedWCALiveScheduleDate: Date?
    @State private var selectedScheduleEventCode = ""
    @State private var wcaScheduleDisplayMode: WCAScheduleDisplayMode = .calendar
    @State private var selectedWCAScheduleRoomIDs: Set<String> = []
    @State private var knownWCAScheduleRoomIDs: Set<String> = []
    @State private var wcaScheduleRoomSelectionCompetitionID: String?
    @State private var filteredCompetitorsSnapshot: [CompetitionCompetitorPreview] = []
    @State private var competitorMatrixEventIDsSnapshot: [String] = []
    @State private var showsCompetitorNumbersSnapshot = false
    @State private var showsCompetitorGenderSnapshot = false
    @State private var filteredPsychCompetitorsSnapshot: [CompetitionCompetitorPsychPreview] = []
    @State private var displayedPsychCompetitorsSnapshot: [CompetitionCompetitorPsychPreview] = []
    @State private var psychOverallRankByCompetitorIDSnapshot: [String: Int] = [:]
    @State private var psychMatrixEventIDsSnapshot: [String] = []
    @State private var collapsedNavigationTitleOpacity: CGFloat = 0
    @State private var detailScrollTopInset: CGFloat = 0
    @State private var detailHeaderSeparatorY: CGFloat = .greatestFiniteMagnitude
    @State private var calendarImport: CompetitionCalendarImport?
    @State private var calendarPreviewError: String?
    @State private var isLoadingCalendarPreview = false
    @State private var wcaCompetitorSortColumn: WCACompetitorSortColumn = .name
    @State private var isWCACompetitorSortAscending = true
    @State private var wcaPsychSortColumn: WCAPsychSortColumn = .average
    @State private var wcaCompetitorNameColumnWidth: CGFloat = 180
    @State private var wcaCompetitorRepresentingColumnWidth: CGFloat = 180
    @State private var wcaPsychNameColumnWidth: CGFloat = 180
    @State private var wcaPsychRepresentingColumnWidth: CGFloat = 140

    private let collapsedNavigationTitleFadeDistance: CGFloat = 28
    private let collapsedNavigationTitleTriggerOffset: CGFloat = 0

    #if DEBUG
    private var isRenderingFixture = false

    /// Deterministic previews exercise the real detail tree without provider traffic.
    init(competition: CompetitionSummary, appLanguage: String, renderingContent: CompetitionDetailContent,
         renderingPublishedStore: PublishedCompetitionStore, renderingTab: CompetitionDetailTab,
         renderingInfoSection: CompetitionDetailTab = .info,
         renderingPublishedResultDeepLink: PublishedCompetitionResultDeepLink? = nil,
         renderingLiveResultDeepLink: CompetitionWCALiveResultDeepLink? = nil) {
        self.init(competition: competition, appLanguage: appLanguage,
            initialWCALiveResultDeepLink: renderingLiveResultDeepLink,
            initialPublishedResultDeepLink: renderingPublishedResultDeepLink)
        _detailContent = State(initialValue: renderingContent)
        _publishedStore = StateObject(wrappedValue: renderingPublishedStore)
        _selectedTab = State(initialValue: renderingTab)
        _selectedPublishedInfoSection = State(initialValue: renderingInfoSection)
        isRenderingFixture = true
    }
    #endif

    init(
        competition: CompetitionSummary,
        appLanguage: String,
        initialWCALiveRoundID: String? = nil,
        initialWCALiveResultDeepLink: CompetitionWCALiveResultDeepLink? = nil,
        initialPublishedResultDeepLink: PublishedCompetitionResultDeepLink? = nil
    ) {
        self.competition = competition
        self.appLanguage = appLanguage
        self.initialWCALiveResultDeepLink = initialWCALiveResultDeepLink
        explicitlyOpenedPublishedResult = initialPublishedResultDeepLink != nil
        _pendingPublishedResultDeepLink = State(initialValue: initialPublishedResultDeepLink)
        let roundID = initialWCALiveResultDeepLink?.roundID
            ?? initialWCALiveRoundID?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        explicitlyOpenedLive = !roundID.isEmpty
        _selectedTab = State(initialValue: roundID.isEmpty ? .info : .live)
        _selectedWCALiveRoundID = State(initialValue: roundID)
    }
    private let wcaCompetitorEventColumnWidth: CGFloat = 40

    private var activeScheduleEventCode: String {
        let selected = selectedScheduleEventCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !selected.isEmpty,
              detailContent.scheduleEventSummaries.contains(where: { $0.eventCode?.lowercased() == selected }) else {
            return ""
        }

        return selected
    }

    private var wcaScheduleRoomOptions: [CompetitionScheduleRoomDescriptor] {
        CompetitionScheduleRoomFilter.rooms(in: detailContent.scheduleDays)
    }

    private var displayedScheduleDays: [CompetitionScheduleDay] {
        guard !isMainlandChinaCompetition, !wcaScheduleRoomOptions.isEmpty else {
            return detailContent.scheduleDays
        }

        let availableIDs = Set(wcaScheduleRoomOptions.map(\.id))
        let selectedIDs = knownWCAScheduleRoomIDs.isEmpty
            ? availableIDs
            : selectedWCAScheduleRoomIDs.intersection(availableIDs)

        return CompetitionScheduleRoomFilter.filteredDays(
            detailContent.scheduleDays,
            selectedRoomIDs: selectedIDs
        )
    }

    private var hasVisibleWCAScheduleEntries: Bool {
        displayedScheduleDays.contains { !$0.entries.isEmpty }
    }

    private var displayCompetitionName: String {
        guard let localizedName = detailContent.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !localizedName.isEmpty else {
            return competition.name
        }
        return localizedName
    }

    private var isMainlandChinaCompetition: Bool {
        competition.usesCubingChinaDetailSource
    }

    private var eventTitles: [String] {
        competition.eventIDs.compactMap { eventID in
            CompetitionEventPresentation.localizedFullName(
                for: eventID,
                languageCode: appLanguage
            )
        }
    }

    private var officialURL: URL? {
        if isMainlandChinaCompetition, let website = competition.website, let url = URL(string: website) {
            return url
        }
        return URL(string: competition.url)
    }

    private var cubingSectionFallbackURL: URL? {
        guard isMainlandChinaCompetition, let slug = competition.cubingChinaCompetitionSlug else { return nil }
        let path: String
        switch detailContentTab.kind {
        case .info where detailContent.overviewBlocks.isEmpty: path = ""
        case .rules where detailContent.regulationBlocks.isEmpty: path = "/regulations"
        case .travel where detailContent.travelBlocks.isEmpty: path = "/travel"
        case .schedule where detailContent.scheduleDays.isEmpty: path = "/schedule"
        case .register where detailContent.registerBlocks.isEmpty: path = "/registration"
        case .competitors where detailContent.competitorPreviews.isEmpty: path = "/competitors"
        default: return nil
        }
        return URL(string: "https://cubing.com/competition/\(slug)\(path)")
    }

    private var registerURL: URL? {
        if isMainlandChinaCompetition,
           let website = competition.website,
           let url = URL(string: website.replacingOccurrences(of: "/competition/", with: "/competition/").appending("/registration")) {
            return url
        }

        if let url = URL(string: competition.url + "/register") {
            return url
        }

        return officialURL
    }

    private var competitorsURL: URL? {
        if isMainlandChinaCompetition,
           let website = competition.website,
           let url = URL(string: website.replacingOccurrences(of: "/competition/", with: "/competition/").appending("/competitors")) {
            return url
        }

        if let url = URL(string: competition.url + "/registrations") {
            return url
        }

        return officialURL
    }

    private var mapsURL: URL? {
        let query = [competition.venue, CompetitionService.parseAddress(competition.venueAddress).displayText, competition.city]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        guard !query.isEmpty else { return nil }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: "http://maps.apple.com/?q=\(encoded)")
    }

    private var travelMapLocations: [CompetitionTravelMapLocation] {
        if !detailContent.travelMapLocations.isEmpty {
            return detailContent.travelMapLocations
        }

        guard let latitude = competition.latitude,
              let longitude = competition.longitude else {
            return []
        }

        return [
            CompetitionTravelMapLocation(
                id: "competition-location-\(competition.id)",
                latitude: latitude,
                longitude: longitude,
                venue: competition.venue,
                address: [CompetitionService.parseAddress(competition.venueAddress).displayText, competition.city]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
            )
        ]
    }

    private var travelMapURL: URL? {
        guard let location = travelMapLocations.first else { return mapsURL }
        let query = [location.venue, location.address]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        if !query.isEmpty {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            return URL(string: "http://maps.apple.com/?q=\(encoded)&ll=\(location.latitude),\(location.longitude)")
        }

        return URL(string: "http://maps.apple.com/?ll=\(location.latitude),\(location.longitude)")
    }

    private var liveURL: URL? {
        if isMainlandChinaCompetition, let website = detailContent.cubingChinaLiveWebsite {
            return website.targetURL(for: initialWCALiveResultDeepLink)
        }
        if explicitlyOpenedLive && !isMainlandChinaCompetition {
            return effectiveWCALiveContent.flatMap {
                CompetitionService.canonicalWCALiveCompetitionURL(for: $0.competitionID)
            }
        }
        if isMainlandChinaCompetition,
           let website = competition.website,
           let liveURL = URL(string: website.replacingOccurrences(of: "/competition/", with: "/live/")) {
            return liveURL
        }

        return detailContent.liveURLOverride
    }

    private var sourceWCALiveContent: CompetitionWCALiveContent? {
        wcaLiveContentOverride ?? detailContent.wcaLiveContent
    }

    private var effectiveWCALiveContent: CompetitionWCALiveContent? {
        guard let source = sourceWCALiveContent else { return nil }
        return wcaLiveSession.content?.competitionID == source.competitionID ? wcaLiveSession.content : source
    }

    private var ownWCAID: String? { auth.isSignedIn ? auth.profile?.wcaId : nil }

    private var shouldRefreshWCALiveContent: Bool {
        guard !isMainlandChinaCompetition else { return false }
        if wcaLiveContentOverride != nil, detailContent.wcaLiveContent == nil { return true }
        guard let content = effectiveWCALiveContent else { return true }
        guard content.competitionName != nil else { return true }
        return !content.venues.contains { venue in
            venue.rooms.contains { $0.activities != nil }
        }
    }

    private var wcaLiveRounds: [CompetitionWCALiveRound] {
        effectiveWCALiveContent?.rounds ?? []
    }

    private var effectiveWCALiveRoundID: String {
        if wcaLiveRounds.contains(where: { $0.id == selectedWCALiveRoundID }) {
            return selectedWCALiveRoundID
        }
        return wcaLiveRounds.first(where: { !$0.results.isEmpty })?.id
            ?? wcaLiveRounds.first?.id
            ?? ""
    }

    private var selectedWCALiveRound: CompetitionWCALiveRound? {
        guard !effectiveWCALiveRoundID.isEmpty else { return nil }
        return wcaLiveRounds.first(where: { $0.id == effectiveWCALiveRoundID })
    }

    private var shouldShowLiveLink: Bool {
        if explicitlyOpenedLive && !isMainlandChinaCompetition { return liveURL != nil }
        if !isMainlandChinaCompetition {
            return liveURL != nil
        }

        switch detailContent.liveAvailability {
        case .available, .ended:
            return liveURL != nil
        case .upcoming:
            return !isMainlandChinaCompetition && liveURL != nil
        case .loading, .unavailable, .failed:
            return false
        }
    }

    private var canShowCubingCalendarSchedule: Bool {
        guard isMainlandChinaCompetition else { return false }
        return detailContent.scheduleDays.contains { day in
            day.venues.count > 1 || day.venues.contains { $0.title != "赛程" && !$0.entries.isEmpty }
        }
    }

    private var liveStatusTitle: String {
        if explicitlyOpenedLive, !isMainlandChinaCompetition, effectiveWCALiveContent == nil {
            return localizedCompetitionStringInView(key: "competitions.detail.live_status.unavailable", languageCode: appLanguage)
        }
        if !isMainlandChinaCompetition {
            if detailContent.liveAvailability == .ended {
                return localizedCompetitionStringInView(key: "competitions.detail.live_status.ended", languageCode: appLanguage)
            }
            return localizedCompetitionStringInView(key: "competitions.detail.live_status.available", languageCode: appLanguage)
        }

        switch detailContent.liveAvailability {
        case .loading:
            return localizedCompetitionStringInView(key: "competitions.loading", languageCode: appLanguage)
        case .available:
            return localizedCompetitionStringInView(key: "competitions.detail.live_status.available", languageCode: appLanguage)
        case .unavailable, .failed:
            return localizedCompetitionStringInView(key: "competitions.detail.live_status.unavailable", languageCode: appLanguage)
        case .upcoming:
            return localizedCompetitionStringInView(key: "competitions.detail.live_status.upcoming", languageCode: appLanguage)
        case .ended:
            return localizedCompetitionStringInView(key: "competitions.detail.live_status.ended", languageCode: appLanguage)
        }
    }

    private var liveStatusBody: String {
        if isMainlandChinaCompetition, let website = detailContent.cubingChinaLiveWebsite,
           initialWCALiveResultDeepLink != nil, website.targetURL(for: initialWCALiveResultDeepLink) == nil {
            return localizedCompetitionStringInView(key: "competitions.detail.live_body_unavailable", languageCode: appLanguage)
        }
        if explicitlyOpenedLive, !isMainlandChinaCompetition, effectiveWCALiveContent == nil {
            return localizedCompetitionStringInView(key: "competitions.detail.live_body_unavailable", languageCode: appLanguage)
        }
        if !isMainlandChinaCompetition {
            if detailContent.liveAvailability == .ended {
                return localizedCompetitionStringInView(key: "competitions.detail.live_body_ended", languageCode: appLanguage)
            }
            return localizedCompetitionStringInView(key: "competitions.detail.live_body_available", languageCode: appLanguage)
        }

        switch detailContent.liveAvailability {
        case .loading:
            return localizedCompetitionStringInView(key: "competitions.loading", languageCode: appLanguage)
        case .available:
            return localizedCompetitionStringInView(key: "competitions.detail.live_body_available", languageCode: appLanguage)
        case .unavailable, .failed:
            return localizedCompetitionStringInView(key: "competitions.detail.live_body_unavailable", languageCode: appLanguage)
        case .upcoming:
            return localizedCompetitionStringInView(key: "competitions.detail.live_body_upcoming", languageCode: appLanguage)
        case .ended:
            return localizedCompetitionStringInView(key: "competitions.detail.live_body_ended", languageCode: appLanguage)
        }
    }

    private var visibleTabs: [CompetitionDetailTab] {
        CompetitionDetailNavigationPolicy.tabs(lifecycle: publishedStore.lifecycle,
            cubingChina: isMainlandChinaCompetition, showLive: shouldShowLiveTab, language: appLanguage,
            showTickets: detailContent.showTickets == true)
    }

    private var effectiveSelectedTab: CompetitionDetailTab {
        visibleTabs.first(where: { $0.rawValue == selectedTab.rawValue }) ?? selectedTab
    }

    private var selectedCustomTabBlock: CompetitionDetailTextBlock? {
        guard case .custom(let id) = selectedTab.kind else { return nil }
        return detailContent.noteBlocks.first { $0.id == id }
    }

    private var selectedWCASourceBlock: CompetitionDetailTextBlock? {
        wcaSourceBlock(for: selectedTab.kind)
    }

    private var shouldShowLiveTab: Bool {
        if !isMainlandChinaCompetition, wcaLiveContentOverride != nil { return true }
        return CompetitionDetailNavigationPolicy.showsLive(content: detailContent, cubingChina: isMainlandChinaCompetition)
    }

    private var wcaInfoSections: [CompetitionDetailTextBlock] {
        detailContent.noteBlocks.filter { block in
            guard let title = block.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                return false
            }

            switch normalizedWCASourceID(block.id) {
            case "register", "registration", "registrations", "competitors", "registrations-list", "live":
                return false
            default:
                return true
            }
        }
    }

    private var effectiveWCAInfoSectionID: String {
        if wcaInfoSections.contains(where: { $0.id == selectedWCAInfoSectionID }) {
            return selectedWCAInfoSectionID
        }

        return wcaInfoSections.first(where: { normalizedWCASourceID($0.id) == "general-info" })?.id
            ?? wcaInfoSections.first?.id
            ?? ""
    }

    private var selectedWCAInfoSection: CompetitionDetailTextBlock? {
        wcaInfoSections.first(where: { $0.id == effectiveWCAInfoSectionID })
    }

    private var selectedWCAInfoSectionKind: CompetitionDetailTabKind {
        guard let section = selectedWCAInfoSection else { return .info }
        switch normalizedWCASourceID(section.id) {
        case "general-info": return .info
        case "competition-events": return .events
        case "competition-schedule": return .schedule
        default: return .custom(section.id)
        }
    }

    private func wcaSourceBlock(for kind: CompetitionDetailTabKind) -> CompetitionDetailTextBlock? {
        let candidates: Set<String>
        switch kind {
        case .info:
            candidates = ["general-info"]
        case .events:
            candidates = ["competition-events"]
        case .schedule:
            candidates = ["competition-schedule"]
        case .register:
            candidates = ["register", "registration", "registrations"]
        case .competitors:
            candidates = ["competitors", "registrations-list"]
        case .travel:
            candidates = ["travel"]
        case .rules, .live, .results, .scrambles, .custom:
            return nil
        }

        return detailContent.noteBlocks.first { block in
            let normalizedID = normalizedWCASourceID(block.id)
            return candidates.contains(normalizedID) || candidates.contains(where: { normalizedID.hasSuffix("-\($0)") })
        }
    }

    private func normalizedWCASourceID(_ id: String) -> String {
        id.replacingOccurrences(of: "wca-", with: "")
    }

    private var overviewDescription: String {
        let status = competitionAvailabilityStatus(for: competition).localizedTitle(languageCode: appLanguage)
        let eventCount = eventTitles.count
        let formatKey = isMainlandChinaCompetition
            ? "competitions.detail.overview_cn_format"
            : "competitions.detail.overview_wca_format"
        return String(
            format: localizedCompetitionStringInView(key: formatKey, languageCode: appLanguage),
            status,
            eventCount
        )
    }

    private var travelDescription: String {
        localizedCompetitionStringInView(
            key: isMainlandChinaCompetition ? "competitions.detail.travel_cn_body" : "competitions.detail.travel_wca_body",
            languageCode: appLanguage
        )
    }

    private var eventSummaryText: String {
        String(
            format: localizedCompetitionStringInView(
                key: "competitions.detail.events_count_format",
                languageCode: appLanguage
            ),
            eventTitles.count
        )
    }

    private var competitionDayTexts: [String] {
        let calendar = Calendar(identifier: .gregorian)
        let dayCount = max(calendar.dateComponents([.day], from: calendar.startOfDay(for: competition.startDate), to: calendar.startOfDay(for: competition.endDate)).day ?? 0, 0)

        return (0...dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: competition.startDate) else { return nil }
            return localizedCompetitionDateRange(startingAt: date)
        }
    }

    private var registrationSummaryText: String {
        if let competitorLimit = competition.competitorLimit {
            return String(
                format: localizedCompetitionStringInView(key: "competitions.detail.registration_summary_limit_format", languageCode: appLanguage),
                competitorLimit
            )
        }
        return localizedCompetitionStringInView(key: "competitions.detail.registration_summary_open", languageCode: appLanguage)
    }

    private var registrationFacts: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusBadge(
                for: competitionAvailabilityStatus(for: competition),
                competition: competition,
                languageCode: appLanguage
            )

            if let registrationOpen = competition.registrationOpen {
                detailLine(
                    systemImage: "calendar.badge.plus",
                    text: String(
                        format: localizedCompetitionStringInView(
                            key: "competitions.detail.registration_open_format",
                            languageCode: appLanguage
                        ),
                        localizedCompetitionDateRange(startingAt: registrationOpen)
                    )
                )
            }

            if let registrationClose = competition.registrationClose {
                detailLine(
                    systemImage: "calendar.badge.clock",
                    text: String(
                        format: localizedCompetitionStringInView(
                            key: "competitions.detail.registration_close_format",
                            languageCode: appLanguage
                        ),
                        localizedCompetitionDateRange(startingAt: registrationClose)
                    )
                )
            }

            if let competitorLimit = competition.competitorLimit {
                detailLine(
                    systemImage: "person.3",
                    text: String(
                        format: localizedCompetitionStringInView(
                            key: "competitions.competitor_limit_format",
                            languageCode: appLanguage
                        ),
                        competitorLimit
                    )
                )
            }
        }
    }

    private var wcaRegistrationContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !detailContent.registerBlocks.isEmpty {
                detailTextBlocks(detailContent.registerBlocks)
            }

            if let registerURL {
                Link(destination: registerURL) {
                    detailPrimaryButton(
                        localizedCompetitionStringInView(
                            key: "competitions.detail.open_registration",
                            languageCode: appLanguage
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cubingRegistrationContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            registrationFacts

            if !detailContent.registerBlocks.isEmpty {
                detailTextBlocks(detailContent.registerBlocks)
            }

            if permitsCubingRegistrationAction, detailContent.registrationRequiresSignIn {
                detailLine(
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    text: localizedCompetitionStringInView(
                        key: "competitions.detail.registration_login_required",
                        languageCode: appLanguage
                    )
                )
            }

            if permitsCubingRegistrationAction, let registerURL {
                Link(destination: registerURL) {
                    detailPrimaryButton(
                        localizedCompetitionStringInView(
                            key: "competitions.detail.open_registration",
                            languageCode: appLanguage
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var permitsCubingRegistrationAction: Bool {
        detailContent.hasRegisterLink && CompetitionDetailNavigationPolicy.permitsRegistrationAction(
            competition, lifecycle: publishedStore.lifecycle, now: Date())
    }

    private var filteredCompetitors: [CompetitionCompetitorPreview] {
        filteredCompetitorsSnapshot
    }

    private var competitorMatrixEventIDs: [String] {
        competitorMatrixEventIDsSnapshot
    }

    private var showsCompetitorNumbers: Bool {
        isMainlandChinaCompetition && showsCompetitorNumbersSnapshot
    }

    private var showsCompetitorGender: Bool {
        isMainlandChinaCompetition && showsCompetitorGenderSnapshot
    }

    private var currentPsychCacheKey: String {
        let eventKey = selectedCompetitorEventID.isEmpty ? "__all__" : selectedCompetitorEventID
        guard !isMainlandChinaCompetition else { return eventKey }
        return "\(eventKey)|\(wcaPsychSortColumn.rawValue)"
    }

    private var isPsychModeAvailable: Bool {
        !selectedCompetitorEventID.isEmpty
    }

    private var filteredPsychCompetitors: [CompetitionCompetitorPsychPreview] {
        filteredPsychCompetitorsSnapshot
    }

    private var showsPsychOverallRank: Bool {
        selectedCompetitorEventID.isEmpty
    }

    private var psychOverallRankByCompetitorID: [String: Int] {
        psychOverallRankByCompetitorIDSnapshot
    }

    private var displayedPsychCompetitors: [CompetitionCompetitorPsychPreview] {
        displayedPsychCompetitorsSnapshot
    }

    private var psychMatrixEventIDs: [String] {
        psychMatrixEventIDsSnapshot
    }

    @State private var showsLiveChat = false

    private var hasMountedCubingChinaLive: Bool {
        guard selectedTab == .live,
              CompetitionDetailNavigationPolicy.usesCubingChinaLive(cubingChina: isMainlandChinaCompetition,
                explicitWCALive: explicitlyOpenedLive, hasContent: detailContent.liveContent != nil),
              let content = detailContent.liveContent else { return false }
        return initialWCALiveResultDeepLink.map { content.targetRound(for: $0) != nil } ?? true
    }

    var body: some View {
        historicalDetailBody
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hasMountedCubingChinaLive {
                CompetitionLiveChatAccessory(language: appLanguage) { showsLiveChat = true }
            }
        }
        .onChange(of: selectedTab) { tab in
            if tab != .live { showsLiveChat = false }
            if tab == .results { publishedStore.beginResultsPresentation() }
        }
        .onChange(of: publishedStore.lifecycle) { state in
            recoverDetailSelection(lifecycle: state)
            if state == .published, !explicitlyOpenedLive, selectedTab == .live { selectedTab = .results }
            if state == .published, pendingPublishedResultDeepLink != nil { selectedTab = .results }
        }
        .onChange(of: shouldShowLiveTab) { _ in
            recoverDetailSelection(lifecycle: publishedStore.lifecycle)
        }
        .onChange(of: detailContent.showTickets) { _ in
            recoverDetailSelection(lifecycle: publishedStore.lifecycle)
        }
    }

    private func recoverDetailSelection(lifecycle: PublishedCompetitionLifecycle) {
        let recovered = CompetitionDetailNavigationPolicy.selection(lifecycle: lifecycle,
            cubingChina: isMainlandChinaCompetition, showLive: shouldShowLiveTab,
            explicitLive: explicitlyOpenedLive,
            primary: selectedTab, section: selectedPublishedInfoSection, showTickets: detailContent.showTickets == true)
        selectedPublishedInfoSection = recovered.section
        selectedTab = recovered.primary
    }

    private var historicalDetailBody: some View {
        let bodyStart = CACurrentMediaTime()
        defer { CompetitionLoadingTrace.record("detail-body-construction", since: bodyStart, detail: competition.id) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                wcaPrimaryNavigationList
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                wcaPageHeader.padding(.horizontal, 16)

                tabContent
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)

                if (selectedTab == .info && !staleCachedDetailResources.isEmpty)
                    || (selectedTab == .results && publishedStore.failed && publishedStore.data != nil)
                    || (selectedTab == .scrambles && publishedStore.scrambles.isStale) {
                    Text(appLocalizedString("explore.cached", languageCode: appLanguage))
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.bottom, 8)
                }

                if !isLoadingDetail, let url = cubingSectionFallbackURL {
                    Link(PublishedCompetitionStrings.text("open_source", appLanguage), destination: url)
                        .font(.footnote).padding(.horizontal, 16).padding(.bottom, 12)
                }
            }
        }
        .competitionResultsPresentation(state: publishedResultCard, language: appLanguage)
        .competitionDebugCompetition(competition.id)
        .onDisappear { publishedResultCard.cancelLoading() }
        .coordinateSpace(name: "competitionDetailScrollFallback")
        .modifier(CompetitionDetailScrollTopInsetModifier(topInset: $detailScrollTopInset))
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear { CompetitionLoadingTrace.record("detail-first-visible", since: detailOpenedAt, detail: competition.id) }
        .background {
            if detailContent != .empty {
                Color.clear.onAppear {
                    CompetitionLoadingTrace.record("detail-useful-view-mounted", since: detailOpenedAt, detail: competition.id)
                }
            }
        }
        .navigationTitle(displayCompetitionName)
        .navigationBarTitleDisplayMode(.inline)
        .background {
            CompetitionNativeDetailTitle(title: displayCompetitionName, inlineOpacity: collapsedNavigationTitleOpacity)
        }
        .background {
            if !isMainlandChinaCompetition, shouldShowLiveTab, let initialWCALiveResultDeepLink,
               let round = wcaLiveRounds.first(where: { $0.id == initialWCALiveResultDeepLink.roundID }),
               let competitionID = effectiveWCALiveContent?.competitionID {
                NavigationLink(
                    destination: CompetitionWCALiveRoundDetailView(
                        round: round,
                        competitionID: competitionID,
                        languageCode: appLanguage,
                        areEventIconsReady: areCompetitionEventIconsReady,
                        resultDeepLink: initialWCALiveResultDeepLink,
                        session: wcaLiveSession
                    ),
                    isActive: $isPresentingInitialWCALiveResult
                ) {
                    EmptyView()
                }
                .hidden()
            }
        }
        .onPreferenceChange(CompetitionDetailHeaderSeparatorPreferenceKey.self) { separatorY in
            guard !isUsingModernScrollGeometry else { return }
            detailHeaderSeparatorY = separatorY
            updateCollapsedNavigationTitleOpacity()
        }
        .onChange(of: detailScrollTopInset) { _ in
            updateCollapsedNavigationTitleOpacity()
        }
        .task(id: "\(competition.id)|\(appLanguage)|\(detailReloadGeneration)") {
            areCompetitionEventIconsReady = CompetitionEventIconFont.ensureRegistered()
            var refresh = detailReloadGeneration > 0
            #if DEBUG
            refresh = refresh || CompetitionColdLoadDiagnostics.forceFirstLoad("\(competition.id)|\(appLanguage)")
            #endif
            if refresh { psychPreviewCache = [:] }
            await loadDetailContent(refresh: refresh)
        }
        .task(id: "\(competition.id)|\(appLanguage)|\(initialWCALiveResultDeepLink?.roundID ?? "")") {
            await loadInitialWCALiveRoundIfNeeded()
        }
        .onAppear { configureWCALiveSession() }
        .onChange(of: sourceWCALiveContent) { _ in configureWCALiveSession() }
        .onChange(of: appLanguage) { _ in configureWCALiveSession() }
        .task(id: "\(wcaLiveSession.personalIdentity)|\(ownWCAID ?? "guest")") {
            guard !isMainlandChinaCompetition else { return }
            await wcaLiveSession.loadPersonalRecords(ownWCAID: ownWCAID)
        }
        .task(id: "\(competition.id)|\(appLanguage)|\(detailContentTab.rawValue)|\(selectedCompetitorsMode.rawValue)|\(selectedCompetitorEventID)|\(wcaPsychSortColumn.rawValue)|\(detailReloadGeneration)") {
            await loadPsychPreviewsIfNeeded()
        }
        .onChange(of: selectedTab) { _ in
            presentInitialWCALiveResultIfAvailable()
        }
        .onChange(of: wcaLiveRounds.map(\.id)) { _ in
            presentInitialWCALiveResultIfAvailable()
        }
        .onChange(of: competitorSearchText) { _ in
            updateCompetitionDetailDerivedState()
        }
        .onChange(of: selectedCompetitorEventID) { _ in
            updateCompetitionDetailDerivedState()
        }
        .onChange(of: selectedCompetitorsMode) { _ in
            updateCompetitionDetailDerivedState()
        }
        .onChange(of: wcaCompetitorSortColumn) { _ in
            updateCompetitionDetailDerivedState()
        }
        .onChange(of: isWCACompetitorSortAscending) { _ in
            updateCompetitionDetailDerivedState()
        }
        .onChange(of: wcaPsychSortColumn) { _ in
            if psychPreviewCache[currentPsychCacheKey] != nil {
                updateCompetitionDetailDerivedState()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    detailReloadGeneration += 1
                } label: {
                    if loadingLifecycle.isLoading {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(CompetitionLoadingPresentation.title(loadingLifecycle.currentWork,
                                language: appLanguage, cubingChina: isMainlandChinaCompetition)).font(.caption)
                        }
                    } else {
                        Image(systemName: publishedStore.failed ? "exclamationmark.icloud" : "arrow.clockwise")
                    }
                }
                .tint(.primary)
                .accessibilityIdentifier("competition-refresh")
                .accessibilityLabel(PublishedCompetitionStrings.text("refresh", appLanguage))
                .accessibilityValue(CompetitionLoadingPresentation.title(loadingLifecycle.currentWork,
                    language: appLanguage, cubingChina: isMainlandChinaCompetition))
            }
        }
        .sheet(item: $calendarImport) { calendarImport in
            CompetitionCalendarImportSheet(
                calendarImport: calendarImport,
                appLanguage: appLanguage
            )
        }
        .alert(
            appLocalizedString(
                "competitions.calendar.title",
                languageCode: appLanguage,
                defaultValue: "Calendar"
            ),
            isPresented: Binding(
                get: { calendarPreviewError != nil },
                set: { if !$0 { calendarPreviewError = nil } }
            )
        ) {
            Button(appLocalizedString("common.done", languageCode: appLanguage, defaultValue: "Done")) {
                calendarPreviewError = nil
            }
        } message: {
            Text(calendarPreviewError ?? "")
        }
    }

    private func presentInitialWCALiveResultIfAvailable() {
        if isMainlandChinaCompetition {
            guard explicitlyOpenedLive, shouldShowLiveTab, !didPresentInitialWCALiveResult else { return }
            selectedTab = .live
            didPresentInitialWCALiveResult = true
            return
        }
        guard !didPresentInitialWCALiveResult,
              let deepLink = initialWCALiveResultDeepLink,
              wcaLiveRounds.contains(where: { $0.id == deepLink.roundID }) else { return }
        selectedTab = .live
        selectedWCALiveRoundID = deepLink.roundID
        didPresentInitialWCALiveResult = true
        isPresentingInitialWCALiveResult = true
    }

    private var wcaPrimaryNavigationList: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleTabs.enumerated()), id: \.element.id) { index, tab in
                Button {
                    guard selectedTab != tab else { return }
                    withAnimation(.snappy(duration: 0.24)) {
                        selectedTab = tab
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: wcaPrimaryTabSymbol(for: tab.kind))
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 26)

                        Text(tab.localizedTitle(languageCode: appLanguage))
                            .font(isMainlandChinaCompetition ? .body.weight(selectedTab == tab ? .semibold : .regular)
                                : .system(size: 17, weight: selectedTab == tab ? .semibold : .regular))

                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(primaryNavigationForeground(tab))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 58)
                    .contentShape(Rectangle())
                    .background(selectedTab == tab ? CubingChinaNavigationColors.primaryAccent(
                        for: tab.kind, cubingChina: isMainlandChinaCompetition, selected: true) : Color.clear)
                }
                .buttonStyle(.plain)

                if index < visibleTabs.count - 1 {
                    Divider()
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.7)
        }
    }

    private func primaryNavigationForeground(_ tab: CompetitionDetailTab) -> Color {
        guard selectedTab == tab else { return .primary }
        guard isMainlandChinaCompetition else { return .white }
        return CubingChinaNavigationColors.selectedForeground(for: tab.kind)
    }

    private func wcaPrimaryTabSymbol(for kind: CompetitionDetailTabKind) -> String {
        switch kind {
        case .info: return "info.circle.fill"
        case .register: return "rectangle.portrait.and.arrow.right"
        case .competitors: return "person.3.fill"
        case .results: return "list.number"
        case .scrambles: return "shuffle"
        case .live: return "dot.radiowaves.left.and.right"
        case .custom("spectator-ticket"): return "ticket.fill"
        default: return "circle.fill"
        }
    }

    private var wcaPageHeader: some View {
        let titleSize = CompetitionDetailNavigationBarConfiguratorController.fittedLargeTitleSize(
            for: displayCompetitionName, baseSize: UIFont.preferredFont(forTextStyle: .largeTitle).pointSize)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if !championshipTitles.isEmpty {
                    CompetitionTextPopoverButton(text: championshipTitles.joined(separator: "\n")) {
                        CompetitionChampionshipSymbol()
                    }
                }
                Text(displayCompetitionName)
                    .font(.system(size: titleSize, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .alignmentGuide(.firstTextBaseline) { _ in UIFont.systemFont(ofSize: titleSize, weight: .bold).lineHeight / 2 }
                    .accessibilityIdentifier("competition-large-title")
            }

            headerSeparator
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var championshipTitles: [String] {
        if let titles = detailContent.championshipTitles, !titles.isEmpty {
            return titles
        }

        return (competition.championshipTypes ?? []).map { type in
            switch type {
            case "world":
                return appLocalizedString(
                    "competitions.championship.world",
                    languageCode: appLanguage,
                    defaultValue: "World Championship"
                )
            case "greater_china":
                return appLocalizedString(
                    "competitions.championship.greater_china",
                    languageCode: appLanguage,
                    defaultValue: "Greater China Championship"
                )
            default:
                if type.hasPrefix("_") {
                    let continent = String(type.dropFirst())
                    return String(
                        format: appLocalizedString(
                            "competitions.championship.continental_format",
                            languageCode: appLanguage,
                            defaultValue: "Continental Championship: %@"
                        ),
                        continent
                    )
                }

                if type.count == 2 {
                    let country = appLocale(for: appLanguage).localizedString(forRegionCode: type) ?? type
                    return String(
                        format: appLocalizedString(
                            "competitions.championship.national_format",
                            languageCode: appLanguage,
                            defaultValue: "National Championship: %@"
                        ),
                        country
                    )
                }

                return String(
                    format: appLocalizedString(
                        "competitions.championship.generic_format",
                        languageCode: appLanguage,
                        defaultValue: "Championship: %@"
                    ),
                    type
                )
            }
        }
    }

    private var cubingPageHeader: some View {
        VStack(spacing: 8) {
            Text(displayCompetitionName)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .selectableContent()

            headerSeparator
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var isUsingModernScrollGeometry: Bool {
        if #available(iOS 18.0, *) {
            return true
        }
        return false
    }

    private var headerSeparator: some View {
        let separator = Divider()
            .padding(.top, 6)

        return Group {
            if #available(iOS 18.0, *) {
                separator.onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .scrollView).minY
                } action: { _, separatorY in
                    detailHeaderSeparatorY = separatorY
                    updateCollapsedNavigationTitleOpacity()
                }
            } else {
                separator.background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: CompetitionDetailHeaderSeparatorPreferenceKey.self,
                            value: proxy.frame(in: .named("competitionDetailScrollFallback")).minY
                        )
                    }
                )
            }
        }
    }

    private func updateCollapsedNavigationTitleOpacity() {
        guard detailHeaderSeparatorY.isFinite else {
            collapsedNavigationTitleOpacity = 0
            return
        }

        let triggerY = collapsedNavigationTitleTriggerOffset
        let distanceBeforeSeparatorHitsTrigger = detailHeaderSeparatorY - triggerY
        let opacity = min(max((collapsedNavigationTitleFadeDistance - distanceBeforeSeparatorHitsTrigger) / collapsedNavigationTitleFadeDistance, 0), 1)
        collapsedNavigationTitleOpacity = opacity
    }

    @ViewBuilder
    private var tabContent: some View {
        if isMainlandChinaCompetition, selectedTab == .info {
            VStack(alignment: .leading, spacing: 14) {
                CubingCompetitionDetailNavigation(tabs: CompetitionDetailNavigationPolicy.infoSections(
                    lifecycle: publishedStore.lifecycle, cubingChina: true, language: appLanguage,
                    showTickets: detailContent.showTickets == true),
                    languageCode: appLanguage, selection: $selectedPublishedInfoSection)
                detailDestinationContent
            }
        } else {
            detailDestinationContent
        }
    }

    private var detailContentTab: CompetitionDetailTab {
        if isMainlandChinaCompetition, selectedTab == .info {
            return CompetitionDetailNavigationPolicy.infoSections(lifecycle: publishedStore.lifecycle,
                cubingChina: true, language: appLanguage, showTickets: detailContent.showTickets == true)
                .first { $0 == selectedPublishedInfoSection } ?? .info
        }
        return selectedTab
    }

    @ViewBuilder
    private var detailDestinationContent: some View {
        if detailContentTab.rawValue == "custom-spectator-ticket", let slug = competition.cubingChinaCompetitionSlug {
            CubingChinaTicketsContent(tickets: detailContent.tickets,
                isLoading: pendingDetailResources.contains(.tickets), slug: slug, language: appLanguage)
        } else if selectedTab == .results, let published = publishedStore.data {
            PublishedCompetitionResultsContent(data: published, language: appLanguage,
                initialResult: pendingPublishedResultDeepLink,
                onFirstResult: { publishedStore.didPresentResults() }, resultCard: publishedResultCard,
                recordEvidenceRefreshID: publishedStore.recordEvidenceRefreshID,
                recordEnrichment: publishedRecordEvidence)
                .onAppear { pendingPublishedResultDeepLink = nil }
        } else if selectedTab == .scrambles, let published = publishedStore.data {
            PublishedCompetitionScramblesContent(data: published, language: appLanguage, state: publishedStore.scrambles,
                isCoordinated: true, isPreparing: loadingLifecycle.pending.contains(.scrambles),
                onRetry: { detailReloadGeneration += 1 })
        } else if isWaitingForDetailDestination {
            detailLoadingCard
        } else {
            switch detailContentTab.kind {
        case .results, .scrambles:
            EmptyView()
        case .info:
            detailSectionStack {
                if isLoadingDetail && detailContent == .empty {
                    detailLoadingCard
                }

                if isMainlandChinaCompetition {
                    if detailContent.overviewBlocks.isEmpty {
                        detailSectionCard(title: detailContentTab.localizedTitle(languageCode: appLanguage)) {
                            Text(localizedCompetitionStringInView(key: "competitions.detail.unavailable", languageCode: appLanguage))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        cubingDetailDocument(
                            detailContent.overviewBlocks,
                            fallbackTitle: detailContentTab.localizedTitle(languageCode: appLanguage)
                        )
                    }
                } else {
                    wcaInfoContent
                }
            }

        case .rules:
            detailSectionStack {
                if isLoadingDetail && detailContent == .empty {
                    detailLoadingCard
                }

                if isMainlandChinaCompetition {
                    if detailContent.regulationBlocks.isEmpty {
                        detailSectionCard(title: detailContentTab.localizedTitle(languageCode: appLanguage)) {
                            Text(localizedCompetitionStringInView(key: "competitions.detail.unavailable", languageCode: appLanguage))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        cubingDetailDocument(
                            detailContent.regulationBlocks,
                            fallbackTitle: detailContentTab.localizedTitle(languageCode: appLanguage)
                        )
                    }
                } else {
                    detailSectionCard(title: detailContentTab.localizedTitle(languageCode: appLanguage)) {
                        if detailContent.registerBlocks.isEmpty {
                            Text(localizedCompetitionStringInView(key: "competitions.detail.unavailable", languageCode: appLanguage))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            detailTextBlocks(detailContent.registerBlocks)
                        }
                    }
                }
            }

        case .events:
            detailSectionStack {
                if isLoadingDetail && detailContent == .empty {
                    detailLoadingCard
                }

                if let sourceBlock = selectedWCASourceBlock, !sourceBlock.body.isEmpty {
                    detailSectionCard(title: sourceBlock.title ?? detailContentTab.localizedTitle(languageCode: appLanguage)) {
                        detailTextBlocks([sourceBlock])
                    }
                }

                if !eventTitles.isEmpty {
                    detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.events", languageCode: appLanguage)) {
                        FlexibleTagFlow(items: eventTitles)
                    }
                }
            }

        case .travel:
            detailSectionStack {
                if isLoadingDetail && detailContent == .empty {
                    detailLoadingCard
                }

                if !isMainlandChinaCompetition {
                    detailSectionCard(title: detailContentTab.localizedTitle(languageCode: appLanguage)) {
                        if let sourceBlock = selectedWCASourceBlock {
                            detailTextBlocks([sourceBlock])
                        } else if detailContent.travelBlocks.isEmpty {
                            Text(travelDescription)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            detailTextBlocks(detailContent.travelBlocks)
                        }
                    }
                } else if detailContent.travelBlocks.isEmpty {
                    Text(travelDescription)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    cubingDetailDocumentBody(
                        detailContent.travelBlocks,
                        fallbackTitle: detailContentTab.localizedTitle(languageCode: appLanguage),
                        mapLocations: travelMapLocations,
                        mapURL: travelMapURL
                    )
                }

                if let officialURL {
                    Link(destination: officialURL) {
                        detailSecondaryLink(localizedCompetitionStringInView(key: "competitions.detail.open_official", languageCode: appLanguage))
                    }
                    .buttonStyle(.plain)
                }
            }

        case .custom:
            detailSectionStack {
                if isLoadingDetail && detailContent == .empty {
                    detailLoadingCard
                }

                if let selectedCustomTabBlock {
                    detailSectionCard(title: selectedCustomTabBlock.title ?? detailContentTab.localizedTitle(languageCode: appLanguage)) {
                        detailTextBlocks([selectedCustomTabBlock])
                    }
                } else {
                    detailSectionCard(title: detailContentTab.localizedTitle(languageCode: appLanguage)) {
                        Text(localizedCompetitionStringInView(key: "competitions.detail.unavailable", languageCode: appLanguage))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

        case .register:
            detailSectionStack {
                if isLoadingDetail && detailContent == .empty {
                    detailLoadingCard
                }

                if isMainlandChinaCompetition {
                    cubingRegistrationContent
                } else {
                    wcaRegistrationContent
                }
            }

        case .competitors:
            detailSectionStack {
                if isLoadingDetail && detailContent == .empty {
                    detailLoadingCard
                }

                VStack(alignment: .leading, spacing: 10) {
                    if !detailContent.competitorPreviews.isEmpty {
                        competitorEventFilterStrip

                        if isMainlandChinaCompetition {
                            competitorSearchField
                            competitorsModePicker
                        } else {
                            wcaCompetitorPeopleSummary
                        }

                        if selectedCompetitorEventID.isEmpty || (isMainlandChinaCompetition && selectedCompetitorsMode == .registration) {
                            competitorsMatrixTable
                        } else if isLoadingPsych {
                            competitorsPsychLoadingCard
                        } else if filteredPsychCompetitors.isEmpty {
                            Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_psych_unavailable", languageCode: appLanguage))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            competitorsPsychTable
                        }
                    } else if isLoadingCompetitors {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(localizedCompetitionStringInView(key: "competitions.loading", languageCode: appLanguage))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    } else if !isLoadingDetail {
                        Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_unavailable", languageCode: appLanguage))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    if let competitorsURL {
                        Link(destination: competitorsURL) {
                            detailSecondaryLink(localizedCompetitionStringInView(key: "competitions.detail.open_competitors", languageCode: appLanguage))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        case .schedule:
            detailSectionStack {
                if isLoadingDetail && detailContent == .empty {
                    detailLoadingCard
                }

                detailScheduleContent
            }

        case .live:
            detailSectionStack {
                if isLoadingWCALive && (isMainlandChinaCompetition ? detailContent.liveContent == nil : effectiveWCALiveContent == nil) {
                    detailLoadingCard
                } else if CompetitionDetailNavigationPolicy.usesCubingChinaLive(cubingChina: isMainlandChinaCompetition,
                    explicitWCALive: explicitlyOpenedLive, hasContent: detailContent.liveContent != nil),
                    let liveContent = detailContent.liveContent {
                    if let target = initialWCALiveResultDeepLink,
                       liveContent.targetRound(for: target) == nil {
                        Text(localizedCompetitionStringInView(key: "competitions.detail.live_body_unavailable", languageCode: appLanguage))
                            .foregroundStyle(.secondary)
                    } else {
                        CompetitionCubingLiveSection(
                            content: liveContent,
                            appLanguage: appLanguage,
                            liveURL: liveURL,
                            areCompetitionEventIconsReady: areCompetitionEventIconsReady,
                            initialRoundOptionID: initialWCALiveResultDeepLink.flatMap { liveContent.targetRound(for: $0)?.id },
                            initialPersonWCAID: initialWCALiveResultDeepLink?.personWCAID,
                            openOfficialResults: publishedStore.data == nil ? nil : { selectedTab = .results },
                            chatPresentation: $showsLiveChat,
                            resultCard: publishedResultCard, stores: cubingLiveStores
                        )
                    }
                } else if !isMainlandChinaCompetition, let wcaLiveContent = effectiveWCALiveContent {
                    wcaLiveHomeContent(wcaLiveContent)
                } else {
                    detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.live", languageCode: appLanguage)) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(liveStatusTitle)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text(liveStatusBody)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            detailLine(
                                systemImage: "dot.radiowaves.left.and.right",
                                text: localizedCompetitionStringInView(
                                    key: isMainlandChinaCompetition
                                        ? "competitions.detail.source.cubingchina"
                                        : "competitions.detail.source.wca_live",
                                    languageCode: appLanguage
                                )
                            )

                            if !eventTitles.isEmpty {
                                FlexibleTagFlow(items: eventTitles)
                            }

                            if shouldShowLiveLink, let liveURL {
                                Link(destination: liveURL) {
                                    detailPrimaryButton(localizedCompetitionStringInView(key: "competitions.detail.open_live", languageCode: appLanguage))
                                }
                                .buttonStyle(.plain)
                            }

                            if isLoadingWCALive {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text(localizedCompetitionStringInView(key: "competitions.loading", languageCode: appLanguage))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 4)
                            }
                        }
                    }

                    if !detailContent.scheduleDays.isEmpty {
                        detailSectionCard(title: localizedCompetitionStringInView(key: "competitions.detail.section.schedule", languageCode: appLanguage)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(localizedCompetitionStringInView(key: "competitions.detail.wca_live_rounds_body", languageCode: appLanguage))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                ForEach(detailContent.scheduleDays) { day in
                                    detailScheduleDayCard(day)
                                }
                            }
                        }
                    }
                }
            }
        }
        }
    }

    private var isWaitingForDetailDestination: Bool {
        switch detailContentTab.kind {
        case .info: return pendingDetailResources.contains(.info) && detailContent.noteBlocks.isEmpty && detailContent.overviewBlocks.isEmpty
        case .rules: return pendingDetailResources.contains(.regulations) && detailContent.regulationBlocks.isEmpty
        case .travel: return pendingDetailResources.contains(.travel) && detailContent.travelBlocks.isEmpty
        case .schedule: return pendingDetailResources.contains(.schedule) && detailContent.scheduleDays.isEmpty
        case .register: return pendingDetailResources.contains(.registration) && detailContent.registerBlocks.isEmpty
        default: return false
        }
    }

    @ViewBuilder
    private var wcaInfoContent: some View {
        if wcaInfoSections.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if detailContent.overviewBlocks.isEmpty {
                    Text(overviewDescription)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    detailTextBlocks(detailContent.overviewBlocks)
                }

                detailLine(systemImage: "calendar", text: localizedCompetitionDateRange(for: competition))
                detailLine(systemImage: "location", text: competition.locationLine)
            }
        } else {
            WCAInfoSectionStrip(
                sections: wcaInfoSections,
                selectionID: $selectedWCAInfoSectionID
            )

            Divider()

            switch selectedWCAInfoSectionKind {
            case .events:
                if !detailContent.wcaEvents.isEmpty {
                    wcaEventsContent
                } else {
                    wcaSelectedInfoDocument
                }
            case .schedule:
                detailScheduleContent
            default:
                wcaSelectedInfoDocument
            }
        }
    }

    @ViewBuilder
    private var wcaSelectedInfoDocument: some View {
        if let section = selectedWCAInfoSection {
            detailTextBlockBody(
                section,
                baseURL: URL(string: "https://www.worldcubeassociation.org"),
                includesBlockTitleInSelection: true
            )
        } else {
            Text(localizedCompetitionStringInView(key: "competitions.detail.unavailable", languageCode: appLanguage))
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    private var wcaEventsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    wcaEventsTableHeader

                    ForEach(wcaEventTableGroups) { group in
                        detailScheduleHorizontalDivider
                        wcaEventsTableGroup(group)
                    }
                }
                .frame(minWidth: wcaEventsTableWidth, alignment: .leading)
                .overlay(alignment: .topLeading) {
                    GeometryReader { proxy in
                        ZStack(alignment: .topLeading) {
                            ForEach(
                                Array(wcaEventsColumnSeparatorOffsets.enumerated()),
                                id: \.offset
                            ) { _, offset in
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.10))
                                    .frame(width: 1, height: proxy.size.height)
                                    .offset(x: offset)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.55), lineWidth: 1)
            }

            CompetitionRichHTMLContent(
                html: wcaEventsInformationHTML,
                languageCode: appLanguage,
                baseURL: URL(string: "https://www.worldcubeassociation.org")
            )
        }
    }

    private struct WCAEventTableRoundRow: Identifiable {
        let id: String
        let roundTitle: String
        let round: CompetitionWCAEventRound
    }

    private struct WCAEventTableGroup: Identifiable {
        let id: String
        let eventID: String
        let eventTitle: String
        let qualification: CompetitionWCAQualification?
        let firstRowIndex: Int
        let rounds: [WCAEventTableRoundRow]
    }

    private var wcaEventTableGroups: [WCAEventTableGroup] {
        var rowIndex = 0
        return detailContent.wcaEvents.map { event in
            let group = WCAEventTableGroup(
                id: event.id,
                eventID: event.id,
                eventTitle: officialWCAEventTitle(event.id),
                qualification: event.qualification,
                firstRowIndex: rowIndex,
                rounds: event.rounds.enumerated().map { index, round in
                    WCAEventTableRoundRow(
                        id: round.id,
                        roundTitle: localizedWCARoundTitle(index: index, count: event.rounds.count),
                        round: round
                    )
                }
            )
            rowIndex += event.rounds.count
            return group
        }
    }

    private var wcaEventsShowsQualification: Bool {
        detailContent.wcaEvents.contains { $0.qualification != nil }
    }

    private var wcaEventsShowsCutoff: Bool {
        detailContent.wcaEvents.contains { event in
            event.rounds.contains { $0.cutoffAttempts != nil && $0.cutoffResult != nil }
        }
    }

    private var wcaEventsTableHeader: some View {
        HStack(spacing: 0) {
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.event), width: 190)
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.round), width: 104)
            detailScheduleTraditionalHeaderCell(
                localizedScheduleFieldLabel(.format),
                width: wcaEventsFormatColumnWidth
            )
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.timeLimit), width: 160)
            if wcaEventsShowsCutoff {
                detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.cutoff), width: 156)
            }
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.proceed), width: 180)
            if wcaEventsShowsQualification {
                detailScheduleTraditionalHeaderCell(
                    appLocalizedString(
                        "competitions.wca.qualification",
                        languageCode: appLanguage,
                        defaultValue: "Qualification"
                    ),
                    width: 210
                )
            }
        }
        .background(Color.secondary.opacity(0.08))
    }

    private func wcaEventsTableGroup(_ group: WCAEventTableGroup) -> some View {
        HStack(spacing: 0) {
            CompetitionEventIconNameLabel(
                glyph: areCompetitionEventIconsReady
                    ? CompetitionEventIconFont.glyph(for: group.eventID, title: group.eventTitle)
                    : nil,
                eventTitle: group.eventTitle,
                name: group.eventTitle,
                iconSize: 16,
                iconWidth: 22,
                spacing: 8,
                nameFont: .system(size: 14, weight: .medium),
                reservesIconSpace: true
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .frame(width: 190, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(wcaEventTableRowBackground(group.firstRowIndex))

            VStack(spacing: 0) {
                ForEach(Array(group.rounds.enumerated()), id: \.element.id) { roundIndex, row in
                    if roundIndex > 0 {
                        detailScheduleHorizontalDivider
                    }
                    wcaEventsRoundColumns(
                        row,
                        eventID: group.eventID,
                        qualification: roundIndex == 0 ? group.qualification : nil,
                        rowIndex: group.firstRowIndex + roundIndex
                    )
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func wcaEventsRoundColumns(
        _ row: WCAEventTableRoundRow,
        eventID: String,
        qualification: CompetitionWCAQualification?,
        rowIndex: Int
    ) -> some View {
        HStack(spacing: 0) {
            wcaEventTableCell(row.roundTitle, width: 104)
            wcaEventTableCell(
                localizedWCAFormatDescription(row.round),
                width: wcaEventsFormatColumnWidth
            )
            wcaEventTimeLimitCell(row.round, eventID: eventID, width: 160)
            if wcaEventsShowsCutoff {
                wcaEventTableCell(localizedWCACutoff(row.round, eventID: eventID) ?? "", width: 156)
            }
            wcaEventTableCell(localizedWCAAdvancement(row.round, eventID: eventID) ?? "", width: 180)
            if wcaEventsShowsQualification {
                wcaEventTableCell(
                    qualification.map { localizedWCAQualification($0, eventID: eventID) } ?? "",
                    width: 210
                )
            }
        }
        .background(wcaEventTableRowBackground(rowIndex))
    }

    private func wcaEventTableRowBackground(_ index: Int) -> Color {
        index.isMultiple(of: 2) ? .clear : Color.primary.opacity(0.025)
    }

    private func competitionEventIconButton(
        glyph: String,
        eventTitle: String,
        size: CGFloat
    ) -> some View {
        CompetitionEventIconPopoverButton(
            glyph: glyph,
            eventTitle: eventTitle,
            size: size
        )
    }

    private func wcaEventTableCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.primary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .frame(width: width, alignment: .leading)
    }

    private func wcaEventTimeLimitCell(
        _ round: CompetitionWCAEventRound,
        eventID: String,
        width: CGFloat
    ) -> some View {
        let value = localizedWCATimeLimit(round, eventID: eventID) ?? ""
        let marker = wcaTimeLimitMarker(for: round)
        return (Text(value) + Text(marker).foregroundColor(.blue))
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.primary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .frame(width: width, alignment: .leading)
    }

    private var wcaEventsFormatColumnWidth: CGFloat {
        let rowValues = detailContent.wcaEvents.flatMap { event in
            event.rounds.map(localizedWCAFormatDescription)
        }
        let rowFont = UIFont.systemFont(ofSize: 13, weight: .regular)
        let headerFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let rowWidth = rowValues.map {
            ceil(($0 as NSString).size(withAttributes: [.font: rowFont]).width)
        }.max() ?? 0
        let headerWidth = ceil(
            (localizedScheduleFieldLabel(.format) as NSString)
                .size(withAttributes: [.font: headerFont])
                .width
        )
        return max(rowWidth, headerWidth) + 16
    }

    private var wcaEventsTableWidth: CGFloat {
        190 + 104 + wcaEventsFormatColumnWidth + 160 + 180
            + (wcaEventsShowsCutoff ? 156 : 0)
            + (wcaEventsShowsQualification ? 210 : 0)
    }

    private var wcaEventsColumnSeparatorOffsets: [CGFloat] {
        var widths: [CGFloat] = [190, 104, wcaEventsFormatColumnWidth, 160]
        if wcaEventsShowsCutoff {
            widths.append(156)
        }
        widths.append(180)
        if wcaEventsShowsQualification {
            widths.append(210)
        }

        var offset: CGFloat = 0
        return widths.dropLast().map { width in
            offset += width
            return offset
        }
    }

    private var wcaEventsInformationHTML: String {
        guard let html = selectedWCAInfoSection?.html else { return "" }
        return html.replacingOccurrences(
            of: #"(?is)<div\b[^>]*data-react-class=['\"]EventsTable['\"][^>]*>\s*</div>"#,
            with: "",
            options: .regularExpression
        )
    }

    private var detailScheduleContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if detailContent.scheduleDays.isEmpty {
                Text(localizedCompetitionStringInView(key: "competitions.detail.schedule_body", languageCode: appLanguage))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !competitionDayTexts.isEmpty {
                    detailLine(
                        systemImage: "calendar.day.timeline.left",
                        text: String(
                            format: localizedCompetitionStringInView(
                                key: "competitions.detail.schedule_days_format",
                                languageCode: appLanguage
                            ),
                            competitionDayTexts.count
                        )
                    )

                    FlexibleTagFlow(items: competitionDayTexts)
                }

                if !eventTitles.isEmpty {
                    FlexibleTagFlow(items: eventTitles)
                }
            } else {
                if isMainlandChinaCompetition {
                    cubingScheduleWebsiteIntro
                } else {
                    if wcaScheduleRoomOptions.count > 1 {
                        wcaScheduleRoomsFilter
                    }
                    wcaScheduleDisplayPicker
                }

                if isMainlandChinaCompetition, detailContent.scheduleDays.flatMap(\.entries).allSatisfy({ $0.startTime != nil && $0.endTime != nil }) {
                    CompetitionTimedScheduleView(days: detailContent.scheduleDays, language: appLanguage)
                } else if !isMainlandChinaCompetition, !hasVisibleWCAScheduleEntries {
                    wcaScheduleNoRoomsSelected
                } else if !isMainlandChinaCompetition, wcaScheduleDisplayMode == .calendar {
                    wcaScheduleCalendar
                } else {
                    ForEach(displayedScheduleDays) { day in
                        detailScheduleDayCard(day)
                    }
                }

                if isMainlandChinaCompetition {
                    cubingScheduleWebsiteComment
                } else if !wcaScheduleInformationHTML.isEmpty {
                    wcaScheduleInformation
                }
            }

            if let officialURL {
                Link(destination: officialURL) {
                    detailSecondaryLink(localizedCompetitionStringInView(key: "competitions.detail.open_official", languageCode: appLanguage))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var wcaScheduleRoomsFilter: some View {
        let roomIDs = Set(wcaScheduleRoomOptions.map(\.id))
        let effectiveSelection = knownWCAScheduleRoomIDs.isEmpty
            ? roomIDs
            : selectedWCAScheduleRoomIDs.intersection(roomIDs)
        let areAllRoomsSelected = !roomIDs.isEmpty && effectiveSelection == roomIDs

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(
                    appLocalizedString(
                        "competitions.schedule.rooms.title",
                        languageCode: appLanguage,
                        defaultValue: "Rooms"
                    )
                )
                .font(.headline)
                .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Button(
                    appLocalizedString(
                        areAllRoomsSelected
                            ? "competitions.schedule.rooms.none"
                            : "competitions.schedule.rooms.all",
                        languageCode: appLanguage,
                        defaultValue: areAllRoomsSelected ? "None" : "All"
                    )
                ) {
                    if areAllRoomsSelected {
                        selectedWCAScheduleRoomIDs.removeAll()
                    } else {
                        selectedWCAScheduleRoomIDs = roomIDs
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            .font(.system(size: 14, weight: .semibold))

            ForEach(wcaScheduleRoomOptions) { room in
                let isSelected = selectedWCAScheduleRoomIDs.contains(room.id)
                    || knownWCAScheduleRoomIDs.isEmpty
                let roomColor = colorFromHex(room.colorHex) ?? Color.secondary
                let foregroundColor = isSelected
                    ? scheduleRoomForegroundColor(room.colorHex)
                    : Color.primary
                Button {
                    if isSelected {
                        selectedWCAScheduleRoomIDs.remove(room.id)
                    } else {
                        selectedWCAScheduleRoomIDs.insert(room.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .opacity(isSelected ? 1 : 0)
                            .accessibilityHidden(true)

                        Text(room.name)
                            .font(.system(size: 15, weight: .regular))
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(foregroundColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        roomColor.opacity(isSelected ? 1 : 0.18),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay {
                        if !isSelected {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(roomColor.opacity(0.45), lineWidth: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
            }
        }
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private var wcaScheduleNoRoomsSelected: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.3.group")
                .foregroundStyle(.secondary)
            Text(
                appLocalizedString(
                    "competitions.schedule.rooms.empty",
                    languageCode: appLanguage,
                    defaultValue: "Select at least one room to view its schedule."
                )
            )
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    private var wcaScheduleInformationHTML: String {
        wcaInfoSections.first {
            normalizedWCASourceID($0.id) == "competition-schedule"
        }?.html ?? ""
    }

    private var wcaScheduleInformation: some View {
        CompetitionRichHTMLContent(
            html: wcaScheduleInformationHTML,
            areEventIconsReady: areCompetitionEventIconsReady,
            languageCode: appLanguage,
            baseURL: URL(string: "https://www.worldcubeassociation.org")
        )
    }

    private func scheduleRoomForegroundColor(_ value: String?) -> Color {
        guard let value else { return .white }
        let cleaned = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let number = UInt64(cleaned, radix: 16) else { return .white }
        let red = Double((number >> 16) & 0xFF)
        let green = Double((number >> 8) & 0xFF)
        let blue = Double(number & 0xFF)
        return red * 0.299 + green * 0.587 + blue * 0.114 > 186 ? .black : .white
    }

    private var wcaScheduleDisplayPicker: some View {
        Picker(
            localizedScheduleFieldLabel(.display),
            selection: $wcaScheduleDisplayMode
        ) {
            Label(
                appLocalizedString(
                    "competitions.schedule.view.calendar",
                    languageCode: appLanguage,
                    defaultValue: "Calendar"
                ),
                systemImage: "calendar"
            )
            .tag(WCAScheduleDisplayMode.calendar)

            Label(
                appLocalizedString(
                    "competitions.schedule.view.table",
                    languageCode: appLanguage,
                    defaultValue: "Table"
                ),
                systemImage: "tablecells"
            )
            .tag(WCAScheduleDisplayMode.table)
        }
        .pickerStyle(.segmented)
    }

    private var wcaScheduleCalendar: some View {
        let days = displayedScheduleDays
        let minuteRange = wcaScheduleCalendarMinuteRange(days: days)
        let startMinute = minuteRange.lowerBound
        let endMinute = minuteRange.upperBound
        let hourHeight: CGFloat = 72
        let pointsPerMinute = hourHeight / 60
        let headerHeight: CGFloat = 46
        let timeAxisWidth: CGFloat = 52
        let timelineHeight = CGFloat(endMinute - startMinute) * pointsPerMinute
        let totalHeight = headerHeight + timelineHeight

        return GeometryReader { proxy in
            let availableDayWidth = max(proxy.size.width - timeAxisWidth, 210)
            let dayWidth = days.count == 1
                ? availableDayWidth
                : min(max(availableDayWidth * 0.82, 196), 236)
            let contentWidth = timeAxisWidth + dayWidth * CGFloat(days.count)

            ZStack(alignment: .topLeading) {
                ScrollView(.horizontal, showsIndicators: days.count > 1) {
                    ZStack(alignment: .topLeading) {
                        Color(uiColor: .systemBackground)

                        ForEach(Array(days.enumerated()), id: \.element.id) { dayIndex, day in
                            if wcaScheduleDayIsToday(day.title) {
                                Rectangle()
                                    .fill(wcaScheduleTodayColumnColor)
                                    .frame(width: dayWidth, height: totalHeight)
                                    .offset(x: timeAxisWidth + CGFloat(dayIndex) * dayWidth, y: 0)
                            }
                        }

                        Rectangle()
                            .fill(Color(uiColor: .separator).opacity(0.55))
                            .frame(width: contentWidth - timeAxisWidth, height: 0.5)
                            .offset(x: timeAxisWidth, y: headerHeight)

                        ForEach(Array(stride(from: startMinute, through: endMinute, by: 15)), id: \.self) { minute in
                            let y = headerHeight + CGFloat(minute - startMinute) * pointsPerMinute
                            let isHour = minute.isMultiple(of: 60)

                            Rectangle()
                                .fill(Color(uiColor: .separator).opacity(isHour ? 0.32 : 0.14))
                                .frame(width: contentWidth - timeAxisWidth, height: 0.5)
                                .offset(x: timeAxisWidth, y: y)
                        }

                        ForEach(Array(days.enumerated()), id: \.element.id) { dayIndex, day in
                            let dayX = timeAxisWidth + CGFloat(dayIndex) * dayWidth

                            Rectangle()
                                .fill(Color(uiColor: .separator).opacity(0.35))
                                .frame(width: 0.5, height: totalHeight)
                                .offset(x: dayX, y: 0)

                            Text(wcaScheduleCalendarDayTitle(day.title))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: dayWidth - 12, height: headerHeight, alignment: .center)
                                .offset(x: dayX + 6, y: 0)

                            ForEach(wcaScheduleBlockPlacements(for: day.entries)) { placement in
                                if let entryRange = wcaScheduleMinuteRange(for: placement.entry) {
                                    let laneWidth = (dayWidth - 8) / CGFloat(max(placement.laneCount, 1))
                                    let x = dayX + 4 + CGFloat(placement.lane) * laneWidth
                                    let y = headerHeight
                                        + CGFloat(entryRange.lowerBound - startMinute) * pointsPerMinute
                                        + 2
                                    let height = max(
                                        CGFloat(entryRange.upperBound - entryRange.lowerBound) * pointsPerMinute - 4,
                                        12
                                    )

                                    CompetitionWCAScheduleBlockView(
                                        entry: placement.entry,
                                        backgroundColor: wcaScheduleBlockColor(placement.entry),
                                        foregroundColor: wcaScheduleBlockTextColor(placement.entry),
                                        availableHeight: height
                                    )
                                    .frame(width: max(laneWidth - 2, 34), height: height)
                                    // A short entry's intrinsic label height can otherwise paint over the next time slot.
                                    .clipped()
                                    .offset(x: x, y: y)
                                }
                            }
                        }
                    }
                    .frame(width: contentWidth, height: totalHeight, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(uiColor: .separator).opacity(0.45), lineWidth: 0.5)
                    }
                }

                Color(uiColor: .systemBackground)
                    .frame(width: timeAxisWidth, height: totalHeight)
                    .allowsHitTesting(false)

                Rectangle()
                    .fill(Color(uiColor: .separator).opacity(0.45))
                    .frame(width: 0.5, height: totalHeight)
                    .offset(x: timeAxisWidth, y: 0)
                    .allowsHitTesting(false)

                ForEach(Array(stride(from: startMinute, through: endMinute, by: 60)), id: \.self) { minute in
                    let y = headerHeight + CGFloat(minute - startMinute) * pointsPerMinute
                    Text(wcaScheduleHourLabel(minute))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: timeAxisWidth - 8, alignment: .trailing)
                        .offset(x: 0, y: y - 7)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: totalHeight)
    }

    private func wcaScheduleCalendarMinuteRange(days: [CompetitionScheduleDay]) -> ClosedRange<Int> {
        let ranges = days
            .flatMap(\.entries)
            .compactMap(wcaScheduleMinuteRange(for:))
        guard let earliest = ranges.map(\.lowerBound).min(),
              let latest = ranges.map(\.upperBound).max() else {
            return 8 * 60 ... 18 * 60
        }

        if ranges.contains(where: { $0.upperBound > 24 * 60 }) {
            return 0 ... 24 * 60
        }

        let roundedStart = max((earliest / 60) * 60, 0)
        let bufferedEnd = min(max(latest + 10, roundedStart + 60), 24 * 60)
        return roundedStart ... bufferedEnd
    }

    private func wcaScheduleMinuteRange(for entry: CompetitionScheduleEntry) -> ClosedRange<Int>? {
        if let start = entry.startMinuteOfDay, var end = entry.endMinuteOfDay {
            if end <= start { end += 24 * 60 }
            return start ... end
        }

        let components = entry.timeText
            .components(separatedBy: CharacterSet(charactersIn: "-–—"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard components.count >= 2,
              let start = wcaScheduleMinuteValue(components[0]),
              var end = wcaScheduleMinuteValue(components[1]) else {
            return nil
        }
        if end <= start { end += 24 * 60 }
        return start ... end
    }

    private func wcaScheduleMinuteValue(_ value: String) -> Int? {
        let components = value.split(separator: ":", maxSplits: 1).map(String.init)
        guard components.count == 2,
              let hour = Int(components[0]),
              let minuteText = components[1].split(whereSeparator: { !$0.isNumber }).first,
              let minute = Int(minuteText),
              (0 ... 23).contains(hour),
              (0 ... 59).contains(minute) else {
            return nil
        }
        return hour * 60 + minute
    }

    private func wcaScheduleBlockPlacements(
        for entries: [CompetitionScheduleEntry]
    ) -> [CompetitionWCAScheduleBlockPlacement] {
        let sorted = entries
            .compactMap { entry -> (CompetitionScheduleEntry, ClosedRange<Int>)? in
                wcaScheduleMinuteRange(for: entry).map { (entry, $0) }
            }
            .sorted { lhs, rhs in
                if lhs.1.lowerBound != rhs.1.lowerBound { return lhs.1.lowerBound < rhs.1.lowerBound }
                return lhs.1.upperBound > rhs.1.upperBound
            }

        var placements: [CompetitionWCAScheduleBlockPlacement] = []
        var clusterStart = 0
        while clusterStart < sorted.count {
            var clusterEnd = clusterStart + 1
            var latestEnd = sorted[clusterStart].1.upperBound
            while clusterEnd < sorted.count, sorted[clusterEnd].1.lowerBound < latestEnd {
                latestEnd = max(latestEnd, sorted[clusterEnd].1.upperBound)
                clusterEnd += 1
            }

            var laneEndMinutes: [Int] = []
            var clusterAssignments: [(CompetitionScheduleEntry, Int)] = []
            for (entry, range) in sorted[clusterStart ..< clusterEnd] {
                let lane = laneEndMinutes.firstIndex(where: { $0 <= range.lowerBound })
                    ?? laneEndMinutes.count
                if lane == laneEndMinutes.count {
                    laneEndMinutes.append(range.upperBound)
                } else {
                    laneEndMinutes[lane] = range.upperBound
                }
                clusterAssignments.append((entry, lane))
            }

            let laneCount = max(laneEndMinutes.count, 1)
            placements.append(contentsOf: clusterAssignments.map { entry, lane in
                CompetitionWCAScheduleBlockPlacement(entry: entry, lane: lane, laneCount: laneCount)
            })
            clusterStart = clusterEnd
        }
        return placements
    }

    private func wcaScheduleCalendarDayTitle(_ value: String) -> String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: value) else { return value }

        let output = DateFormatter()
        output.locale = appLocale(for: appLanguage)
        output.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return output.string(from: date)
    }

    private func wcaScheduleDayIsToday(_ value: String) -> Bool {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: value) else { return false }
        return Calendar.current.isDateInToday(date)
    }

    private var wcaScheduleTodayColumnColor: Color {
        Color(uiColor: UIColor { traits in
            UIColor.systemYellow.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.10 : 0.07)
        })
    }

    private func wcaScheduleHourLabel(_ minute: Int) -> String {
        String(format: "%02d:00", (minute / 60) % 24)
    }

    private func wcaScheduleBlockColor(_ entry: CompetitionScheduleEntry) -> Color {
        guard entry.eventCode != nil else {
            return Color(red: 102 / 255, green: 102 / 255, blue: 102 / 255)
        }
        return colorFromHex(entry.roomColorHex) ?? .accentColor
    }

    private func wcaScheduleBlockTextColor(_ entry: CompetitionScheduleEntry) -> Color {
        guard entry.eventCode != nil else { return .white }
        guard let value = entry.roomColorHex else { return .white }
        let cleaned = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let number = UInt64(cleaned, radix: 16) else { return .white }
        let red = Double((number >> 16) & 0xFF)
        let green = Double((number >> 8) & 0xFF)
        let blue = Double(number & 0xFF)
        return red * 0.299 + green * 0.587 + blue * 0.114 > 186 ? .black : .white
    }

    private func previewOfficialScheduleCalendar() {
        guard !isLoadingCalendarPreview else { return }
        isLoadingCalendarPreview = true

        Task {
            defer { isLoadingCalendarPreview = false }

            do {
                guard let sourceURL = URL(
                    string: "https://www.worldcubeassociation.org/competitions/\(competition.id).ics"
                ) else {
                    throw URLError(.badURL)
                }

                var request = URLRequest(
                    url: sourceURL,
                    cachePolicy: .reloadIgnoringLocalCacheData,
                    timeoutInterval: 30
                )
                request.setValue("text/calendar", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      data.range(of: Data("BEGIN:VCALENDAR".utf8)) != nil else {
                    throw URLError(.cannotParseResponse)
                }

                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("CubeFlow-Calendars", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                let destination = directory.appendingPathComponent("\(competition.id).ics")
                try data.write(to: destination, options: .atomic)
                calendarImport = CompetitionCalendarImport(
                    fileURL: destination,
                    events: try CompetitionCalendarParser.parse(data)
                )
            } catch {
                calendarPreviewError = String(
                    format: appLocalizedString(
                        "competitions.calendar.error_format",
                        languageCode: appLanguage,
                        defaultValue: "Calendar could not open this schedule: %@"
                    ),
                    appUserFacingErrorMessage(error, languageCode: appLanguage)
                )
            }
        }
    }

    private var detailLoadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            Text(localizedCompetitionStringInView(key: "competitions.loading", languageCode: appLanguage))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    private var competitorSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(
                localizedCompetitionStringInView(key: "competitions.detail.competitors_search_placeholder", languageCode: appLanguage),
                text: $competitorSearchText
            )
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var competitorEventFilterStrip: some View {
        HStack(spacing: 8) {
            HorizontalCapsuleSelectorGroup(spacing: 8) {
                competitorEventFilterChip(
                    title: localizedCompetitionStringInView(key: "competitions.event.all", languageCode: appLanguage),
                    eventID: ""
                )
                .fixedSize(horizontal: true, vertical: false)
            }
            .zIndex(1)

            Divider()
                .frame(height: 24)

            CompetitionProgressiveBlurScrollView {
                HorizontalCapsuleSelectorGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(competitorMatrixEventIDs, id: \.self) { eventID in
                            competitorEventFilterChip(
                                title: localizedWCAEventTitle(eventID),
                                eventID: eventID
                            )
                        }
                    }
                    .padding(.trailing, 1)
                }
            }
            .accessibilityIdentifier("competitionCompetitorEventScroll")
            .frame(
                maxWidth: .infinity,
                minHeight: HorizontalCapsuleSelectorLayout.compactContainerHeight,
                maxHeight: HorizontalCapsuleSelectorLayout.compactContainerHeight,
                alignment: .leading
            )
            .clipped()
            .zIndex(0)
        }
    }

    private var competitorsModePicker: some View {
        HorizontalCapsuleSelectorGroup(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(CompetitionCompetitorsMode.allCases, id: \.self) { mode in
                    let isSelected = selectedCompetitorsMode == mode
                    let isEnabled = mode == .registration || isPsychModeAvailable
                    Button {
                        guard isEnabled else { return }
                        withAnimation(.snappy(duration: 0.18)) {
                            selectedCompetitorsMode = mode
                        }
                    } label: {
                        Text(mode.localizedTitle(languageCode: appLanguage))
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .horizontalCapsuleSelectorSurface(
                                isSelected: isSelected,
                                isEnabled: isEnabled,
                                legacySelectedForeground: isEnabled ? .primary : Color(uiColor: .tertiaryLabel),
                                legacyUnselectedForeground: isEnabled ? .secondary : Color(uiColor: .tertiaryLabel)
                            ) {
                                Capsule()
                                    .fill(
                                        isEnabled
                                            ? (isSelected ? Color.primary.opacity(0.08) : Color(uiColor: .secondarySystemGroupedBackground))
                                            : Color(uiColor: .tertiarySystemGroupedBackground)
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                }
            }
        }
    }

    private func competitorEventFilterChip(title: String, eventID: String) -> some View {
        let isSelected = selectedCompetitorEventID == eventID
        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                selectedCompetitorEventID = eventID
                wcaPsychSortColumn = eventID == "333mbf" ? .single : .average
                if eventID.isEmpty, selectedCompetitorsMode == .psych {
                    selectedCompetitorsMode = .registration
                }
            }
        } label: {
            CompetitionEventIconNameLabel(
                glyph: !eventID.isEmpty && areCompetitionEventIconsReady
                    ? CompetitionEventIconFont.glyph(for: eventID, title: title)
                    : nil,
                eventTitle: title,
                name: title,
                iconSize: 14,
                iconWidth: 17,
                spacing: 6,
                nameFont: .system(size: 14, weight: .semibold),
                iconColor: HorizontalCapsuleSelectorForeground.color(
                    isSelected: isSelected,
                    legacyUnselected: .white
                ),
                nameColor: HorizontalCapsuleSelectorForeground.color(
                    isSelected: isSelected,
                    legacyUnselected: .white
                ),
                lineLimit: 1,
                showsIconPopover: false
            )
            .competitionEventPickerCapsule(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var competitorsMatrixTable: some View {
        if isMainlandChinaCompetition {
            cubingCompetitorsMatrixTable
        } else {
            wcaCompetitorsMatrixTable
        }
    }

    private var cubingCompetitorsMatrixTable: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    cubingCompetitorsMatrixHeader

                    Divider()
                        .padding(.vertical, 8)

                    VStack(spacing: 10) {
                        ForEach(filteredCompetitors) { competitor in
                            cubingCompetitorsMatrixRow(competitor)
                        }
                    }
                }
                .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var wcaCompetitorsMatrixTable: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                wcaCompetitorsMatrixHeader
                Divider()

                ForEach(Array(filteredCompetitors.enumerated()), id: \.element.id) { index, competitor in
                    wcaCompetitorsMatrixRow(competitor, displayIndex: index)
                    if index < filteredCompetitors.count - 1 {
                        Divider()
                    }
                }

                Divider()
                wcaCompetitorsMatrixFooter
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
        }
    }

    private var wcaCompetitorsStripeColor: Color {
        Color(uiColor: .tertiarySystemFill).opacity(0.55)
    }

    private var cubingCompetitorsMatrixHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            if showsCompetitorNumbers {
                Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_column.number", languageCode: appLanguage))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
            }

            Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_column.name", languageCode: appLanguage))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)

            if showsCompetitorGender {
                Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_column.gender", languageCode: appLanguage))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
            }

            Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_column.region", languageCode: appLanguage))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            ForEach(competitorMatrixEventIDs, id: \.self) { eventID in
                competitionEventIconLabel(
                    for: eventID,
                    isEmphasized: false
                )
                .frame(width: 44, alignment: .center)
            }

        }
    }

    private func cubingCompetitorsMatrixRow(_ competitor: CompetitionCompetitorPreview) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if showsCompetitorNumbers {
                Text(competitor.number ?? "—")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
            }

            Text(competitor.name)
                .foregroundStyle(.primary)
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 180, alignment: .leading)

            if showsCompetitorGender {
                Text(localizedCompetitorGender(competitor.gender))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
            }

            HStack(spacing: 5) {
                if let countryISO2 = competitor.countryISO2, !countryISO2.isEmpty {
                    Text(competitionFlagEmoji(for: countryISO2))
                }
                Text(competitor.subtitle ?? "")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 96, alignment: .leading)

            ForEach(competitorMatrixEventIDs, id: \.self) { eventID in
                competitorMatrixEventCell(
                    eventID: eventID,
                    isRegistered: competitor.registeredEventIDs.contains(eventID)
                )
            }

        }
        .padding(.vertical, 2)
    }

    private var wcaCompetitorsMatrixHeader: some View {
        HStack(alignment: .center, spacing: 0) {
            wcaCompetitorSortableHeader(
                localizedCompetitionStringInView(key: "competitions.detail.competitors_column.name", languageCode: appLanguage),
                column: .name,
                width: wcaCompetitorNameColumnWidth,
                alignment: .leading
            )
            wcaCompetitorSortableHeader(
                appLocalizedString(
                    "competitions.detail.competitors_column.representing",
                    languageCode: appLanguage,
                    defaultValue: "Representing"
                ),
                column: .representing,
                width: wcaCompetitorRepresentingColumnWidth,
                alignment: .leading
            )
            ForEach(competitorMatrixEventIDs, id: \.self) { eventID in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selectedCompetitorEventID = eventID
                        selectedCompetitorsMode = .psych
                        wcaPsychSortColumn = eventID == "333mbf" ? .single : .average
                    }
                } label: {
                    wcaCompetitionEventIconLabel(for: eventID)
                        .frame(width: wcaCompetitorEventColumnWidth, height: 18)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    appLocalizedString(
                        "competitions.detail.competitors_mode.psych",
                        languageCode: appLanguage,
                        defaultValue: "Psych Sheet"
                    )
                )
            }
            wcaTableHeaderText(
                appLocalizedString("competitions.detail.competitors_column.total", languageCode: appLanguage, defaultValue: "Total"),
                width: 60,
                alignment: .center
            )
        }
        .background(wcaCompetitorsStripeColor)
    }

    private func wcaCompetitorsMatrixRow(
        _ competitor: CompetitionCompetitorPreview,
        displayIndex: Int
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Group {
                if let wcaID = competitor.wcaID, !wcaID.isEmpty {
                    NavigationLink {
                        WCAProfileView(wcaID: wcaID, displayName: competitor.name)
                    } label: {
                        Text(competitor.name)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(competitor.name)
                        .foregroundStyle(.primary)
                }
            }
            .font(.system(size: 14, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(width: wcaCompetitorNameColumnWidth, alignment: .leading)

            HStack(spacing: 4) {
                if let countryISO2 = competitor.countryISO2, !countryISO2.isEmpty {
                    Text(competitionFlagEmoji(for: countryISO2))
                }
                Text(competitor.subtitle ?? "")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.primary)
            .layoutPriority(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(width: wcaCompetitorRepresentingColumnWidth, alignment: .leading)

            ForEach(competitorMatrixEventIDs, id: \.self) { eventID in
                Group {
                    if competitor.registeredEventIDs.contains(eventID) {
                        wcaCompetitionEventIconLabel(for: eventID)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: wcaCompetitorEventColumnWidth, height: 18)
                .padding(.vertical, 12)
            }

            Text("\(competitor.registeredEventIDs.count)")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(width: 60, alignment: .center)
                .padding(.vertical, 12)
        }
        .background {
            if !displayIndex.isMultiple(of: 2) {
                wcaCompetitorsStripeColor
            }
        }
    }

    private var wcaCompetitorPeopleSummary: some View {
        let competitors = detailContent.competitorPreviews
        let newcomers = competitors.filter { $0.wcaID == nil || $0.wcaID?.isEmpty == true }.count
        let returners = competitors.count - newcomers
        return Text(
            String(
                format: appLocalizedString(
                    "competitions.detail.competitors.people_summary_format",
                    languageCode: appLanguage,
                    defaultValue: "%d first-timers + %d returners = %d people"
                ),
                newcomers,
                returners,
                competitors.count
            )
        )
        .font(.system(size: 14, weight: .regular))
        .foregroundStyle(.primary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var wcaCompetitorsMatrixFooter: some View {
        let competitors = detailContent.competitorPreviews
        let regionCount = Set(competitors.compactMap(\.countryISO2)).count
        let eventCounts = Dictionary(uniqueKeysWithValues: competitorMatrixEventIDs.map { eventID in
            (eventID, competitors.filter { $0.registeredEventIDs.contains(eventID) }.count)
        })
        let totalEntries = competitors.reduce(0) { $0 + $1.registeredEventIDs.count }

        return HStack(alignment: .center, spacing: 0) {
            Text(String(format: appLocalizedString("competitions.detail.competitors.people_count_format", languageCode: appLanguage, defaultValue: "%d people"), competitors.count))
                .padding(.horizontal, 12)
                .frame(width: wcaCompetitorNameColumnWidth, alignment: .leading)
            Text(String(format: appLocalizedString("competitions.detail.competitors.region_count_format", languageCode: appLanguage, defaultValue: "%d regions"), regionCount))
                .padding(.horizontal, 12)
                .frame(width: wcaCompetitorRepresentingColumnWidth, alignment: .leading)
            ForEach(competitorMatrixEventIDs, id: \.self) { eventID in
                Text("\(eventCounts[eventID] ?? 0)")
                    .frame(width: wcaCompetitorEventColumnWidth, alignment: .center)
            }
            Text("\(totalEntries)")
                .frame(width: 60, alignment: .center)
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.primary)
        .monospacedDigit()
        .padding(.vertical, 12)
        .background(wcaCompetitorsStripeColor)
    }

    private var competitorsPsychLoadingCard: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_psych_loading", languageCode: appLanguage))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
            }
            .frame(height: 72)
    }

    @ViewBuilder
    private var competitorsPsychTable: some View {
        if isMainlandChinaCompetition {
            cubingCompetitorsPsychTable
        } else {
            wcaCompetitorsPsychTable
        }
    }

    private var cubingCompetitorsPsychTable: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    cubingCompetitorsPsychHeader

                    Divider()
                        .padding(.vertical, 8)

                    VStack(spacing: 10) {
                        ForEach(displayedPsychCompetitors) { competitor in
                            cubingCompetitorsPsychRow(competitor)
                        }
                    }
                }
                .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var wcaCompetitorsPsychTable: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                wcaCompetitorsPsychHeader
                Divider()

                ForEach(Array(displayedPsychCompetitors.enumerated()), id: \.element.id) { index, competitor in
                    wcaCompetitorsPsychRow(competitor)
                    if index < displayedPsychCompetitors.count - 1 {
                        Divider()
                    }
                }

                Divider()
                wcaCompetitorsPsychFooter
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
        }
    }

    private var cubingCompetitorsPsychHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_column.name", languageCode: appLanguage))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)

            if showsPsychOverallRank {
                Text(localizedCompetitionStringInView(key: "competitions.detail.competitors_column.overall", languageCode: appLanguage))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .center)
            }

            ForEach(psychMatrixEventIDs, id: \.self) { eventID in
                competitionEventIconLabel(
                    for: eventID,
                    isEmphasized: false
                )
                .frame(width: 92, alignment: .center)
            }
        }
    }

    private func cubingCompetitorsPsychRow(_ competitor: CompetitionCompetitorPsychPreview) -> some View {
        let itemsByEvent = Dictionary(uniqueKeysWithValues: competitor.items.map { ($0.eventID, $0) })

        return HStack(alignment: .center, spacing: 10) {
            Text(competitor.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 180, alignment: .leading)

            if showsPsychOverallRank {
                psychOverallRankCell(psychOverallRankByCompetitorID[competitor.id])
            }

            ForEach(psychMatrixEventIDs, id: \.self) { eventID in
                competitorPsychCell(itemsByEvent[eventID], eventID: eventID)
            }
        }
        .padding(.vertical, 2)
    }

    private var wcaCompetitorsPsychHeader: some View {
        HStack(alignment: .center, spacing: 0) {
            wcaCompetitionEventIconLabel(for: selectedCompetitorEventID)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(width: 54, alignment: .center)
            wcaPsychHeaderText(
                localizedCompetitionStringInView(key: "competitions.detail.competitors_column.name", languageCode: appLanguage),
                width: wcaPsychNameColumnWidth,
                alignment: .leading
            )
            wcaPsychHeaderText(
                appLocalizedString(
                    "competitions.detail.competitors_column.representing",
                    languageCode: appLanguage,
                    defaultValue: "Representing"
                ),
                width: wcaPsychRepresentingColumnWidth,
                alignment: .leading
            )
            wcaPsychHeaderText("WR", width: 64, alignment: .trailing)
            wcaPsychSortableHeader(
                appLocalizedString("common.single", languageCode: appLanguage, defaultValue: "Single"),
                column: .single,
                width: 94
            )
            if selectedCompetitorEventID != "333mbf" {
                wcaPsychSortableHeader(
                    appLocalizedString("wca.results_average", languageCode: appLanguage, defaultValue: "Average"),
                    column: .average,
                    width: 94
                )
                wcaPsychHeaderText("WR", width: 64, alignment: .trailing)
            }
        }
    }

    private func wcaPsychSortableHeader(
        _ title: String,
        column: WCAPsychSortColumn,
        width: CGFloat
    ) -> some View {
        let isSelected = wcaPsychSortColumn == column

        return Button {
            updateWCAPsychSort(column: column)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tint)
                }
            }
            .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(width: width, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(
            isSelected
                ? appLocalizedString(
                    "common.sort.ascending",
                    languageCode: appLanguage,
                    defaultValue: "Ascending"
                )
                : ""
        )
    }

    private func wcaPsychHeaderText(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(width: width, alignment: alignment)
    }

    private func wcaTableHeaderText(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(width: width, alignment: alignment)
    }

    private func wcaCompetitorSortableHeader(
        _ title: String,
        column: WCACompetitorSortColumn,
        width: CGFloat,
        alignment: Alignment
    ) -> some View {
        let isSelected = wcaCompetitorSortColumn == column

        return Button {
            updateWCACompetitorSort(column: column)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                wcaSortIndicator(
                    isSelected: isSelected,
                    isAscending: isWCACompetitorSortAscending
                )
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(width: width, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(
            isSelected
                ? appLocalizedString(
                    isWCACompetitorSortAscending ? "common.sort.ascending" : "common.sort.descending",
                    languageCode: appLanguage,
                    defaultValue: isWCACompetitorSortAscending ? "Ascending" : "Descending"
                )
                : ""
        )
    }

    @ViewBuilder
    private func wcaSortIndicator(isSelected: Bool, isAscending: Bool) -> some View {
        if isSelected {
            Image(systemName: isAscending ? "chevron.up" : "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }

    private func updateWCACompetitorSort(column: WCACompetitorSortColumn) {
        if wcaCompetitorSortColumn == column {
            isWCACompetitorSortAscending.toggle()
        } else {
            wcaCompetitorSortColumn = column
            isWCACompetitorSortAscending = true
        }
    }

    private func updateWCAPsychSort(column: WCAPsychSortColumn) {
        guard wcaPsychSortColumn != column else { return }
        wcaPsychSortColumn = column
    }

    private func wcaCompetitorsPsychRow(_ competitor: CompetitionCompetitorPsychPreview) -> some View {
        let item = competitor.items.first
        return HStack(alignment: .center, spacing: 0) {
            Text((item?.rank ?? 0) > 0 ? item.map { "\($0.rank)" } ?? "" : "")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(width: 54, alignment: .trailing)

            Group {
                if let wcaID = competitor.wcaID, !wcaID.isEmpty {
                    NavigationLink {
                        WCAProfileView(wcaID: wcaID, displayName: competitor.name)
                    } label: {
                        Text(competitor.name)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(competitor.name)
                        .foregroundStyle(.primary)
                }
            }
            .font(.system(size: 14, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(width: wcaPsychNameColumnWidth, alignment: .leading)

            HStack(spacing: 7) {
                if let countryISO2 = competitor.countryISO2, !countryISO2.isEmpty {
                    Text(competitionFlagEmoji(for: countryISO2))
                }
                Text(competitor.region ?? "")
                    .lineLimit(1)
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(width: wcaPsychRepresentingColumnWidth, alignment: .leading)

            wcaPsychValue(item?.singleWorldRank.map(String.init) ?? "", width: 64)
            wcaPsychValue(item?.singleResultText ?? "", width: 94)
            if selectedCompetitorEventID != "333mbf" {
                wcaPsychValue(item?.averageResultText ?? "", width: 94)
                wcaPsychValue(item?.averageWorldRank.map(String.init) ?? "", width: 64)
            }
        }
    }

    private func wcaPsychValue(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.primary)
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(width: width, alignment: .trailing)
    }

    private var wcaCompetitorsPsychFooter: some View {
        let competitors = displayedPsychCompetitors
        let regionCount = Set(competitors.compactMap(\.countryISO2)).count
        return HStack(alignment: .center, spacing: 0) {
            Color.clear.frame(width: 54)
            Text(String(format: appLocalizedString("competitions.detail.competitors.people_count_format", languageCode: appLanguage, defaultValue: "%d people"), competitors.count))
                .padding(.horizontal, 12)
                .frame(width: wcaPsychNameColumnWidth, alignment: .leading)
            Text(String(format: appLocalizedString("competitions.detail.competitors.region_count_format", languageCode: appLanguage, defaultValue: "%d regions"), regionCount))
                .padding(.horizontal, 12)
                .frame(width: wcaPsychRepresentingColumnWidth, alignment: .leading)
            Color.clear.frame(width: 64)
            Color.clear.frame(width: 94)
            if selectedCompetitorEventID != "333mbf" {
                Color.clear.frame(width: 94)
                Color.clear.frame(width: 64)
            }
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.primary)
        .monospacedDigit()
        .padding(.vertical, 12)
    }

    private func psychOverallRankCell(_ rank: Int?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rank == nil ? Color.clear : Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(rank == nil ? Color.secondary.opacity(0.12) : Color.orange.opacity(0.22), lineWidth: 1)
                )

            if let rank {
                Text("\(rank)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.orange)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 56, height: 32)
    }

    @ViewBuilder
    private func competitorPsychCell(_ item: CompetitionPsychItem?, eventID: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(item == nil ? Color.clear : Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(item == nil ? Color.secondary.opacity(0.12) : Color.orange.opacity(0.22), lineWidth: 1)
                )

            if let item {
                HStack(spacing: 4) {
                    Text("\(item.rank)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.orange)

                    competitionEventIconLabel(for: eventID, isEmphasized: true)

                    Text(item.resultText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 6)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 92, height: 32)
    }

    private func competitorMatrixEventCell(eventID: String, isRegistered: Bool) -> some View {
        if !isMainlandChinaCompetition {
            return AnyView(
                Group {
                    if isRegistered {
                        competitionEventIconLabel(for: eventID, isEmphasized: false)
                            .foregroundStyle(.primary)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 44, height: 32)
            )
        }

        return AnyView(ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isRegistered ? Color.orange.opacity(0.14) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isRegistered ? Color.orange.opacity(0.25) : Color.secondary.opacity(0.12), lineWidth: 1)
                )

            if isRegistered {
                competitionEventIconLabel(
                    for: eventID,
                    isEmphasized: true
                )
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 44, height: 32))
    }

    @ViewBuilder
    private func competitionEventIconLabel(for eventID: String, isEmphasized: Bool) -> some View {
        if areCompetitionEventIconsReady,
           let glyph = CompetitionEventIconFont.glyph(for: eventID) {
            CompetitionEventGlyph(
                glyph: glyph,
                eventName: shortEventTitle(for: eventID),
                size: isEmphasized ? 17 : 15,
                color: isEmphasized ? .orange : .secondary
            )
        } else {
            Text(shortEventTitle(for: eventID))
                .font(.system(size: isEmphasized ? 12 : 11, weight: .semibold))
                .foregroundStyle(isEmphasized ? Color.orange : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .accessibilityLabel(shortEventTitle(for: eventID))
        }
    }

    @ViewBuilder
    private func wcaCompetitionEventIconLabel(for eventID: String) -> some View {
        if areCompetitionEventIconsReady,
           let glyph = CompetitionEventIconFont.glyph(for: eventID) {
            CompetitionEventGlyph(
                glyph: glyph,
                eventName: shortEventTitle(for: eventID),
                size: 15
            )
        } else {
            Text(shortEventTitle(for: eventID))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func shortEventTitle(for eventID: String) -> String {
        CompetitionEventPresentation.localizedFullName(
            for: eventID,
            languageCode: appLanguage
        )
    }

    private func localizedWCAEventTitle(_ eventID: String) -> String {
        CompetitionEventPresentation.localizedFullName(
            for: eventID,
            languageCode: appLanguage
        )
    }

    private func officialWCAEventTitle(_ eventID: String) -> String {
        CompetitionEventPresentation.officialName(
            for: eventID,
            fallback: localizedWCAEventTitle(eventID)
        )
    }

    private func localizedWCARoundTitle(index: Int, count: Int) -> String {
        if count == 1 || index == count - 1 {
            return appLocalizedString(
                "competitions.wca.round.final",
                languageCode: appLanguage,
                defaultValue: "Final"
            )
        }
        if index == 0 {
            return appLocalizedString(
                "competitions.wca.round.first",
                languageCode: appLanguage,
                defaultValue: "First round"
            )
        }
        if index == 1 {
            return appLocalizedString(
                "competitions.wca.round.second",
                languageCode: appLanguage,
                defaultValue: "Second round"
            )
        }
        return appLocalizedString(
            "competitions.wca.round.semi_final",
            languageCode: appLanguage,
            defaultValue: "Semi Final"
        )
    }

    private func localizedWCAFormat(_ formatID: String) -> String {
        let value: (String, String)
        switch formatID {
        case "1": value = ("competitions.wca.format.best_of_1", "Best of 1")
        case "2": value = ("competitions.wca.format.best_of_2", "Best of 2")
        case "3": value = ("competitions.wca.format.best_of_3", "Best of 3")
        case "5": value = ("competitions.wca.format.best_of_5", "Best of 5")
        case "m": value = ("competitions.wca.format.mean_of_3", "Mean of 3")
        default: value = ("competitions.wca.format.average_of_5", "Average of 5")
        }
        return appLocalizedString(value.0, languageCode: appLanguage, defaultValue: value.1)
    }

    private func localizedWCAFormatDescription(_ round: CompetitionWCAEventRound) -> String {
        let format = officialWCAFormatShortName(round.formatID)
        guard let cutoffAttempts = round.cutoffAttempts else { return format }
        return "\(officialWCAFormatShortName(String(cutoffAttempts))) / \(format)"
    }

    private func officialWCAFormatShortName(_ formatID: String) -> String {
        switch formatID {
        case "1": return "Bo1"
        case "2": return "Bo2"
        case "3": return "Bo3"
        case "5": return "Bo5"
        case "m": return "Mo3"
        case "h": return "H2H"
        case "a": return "Ao5"
        default: return formatID.uppercased()
        }
    }

    private func localizedWCAQualification(
        _ qualification: CompetitionWCAQualification?,
        eventID: String
    ) -> String {
        guard let qualification else { return "" }

        let resultType = appLocalizedString(
            qualification.resultType == "average"
                ? "competitions.wca.qualification.average"
                : "competitions.wca.qualification.single",
            languageCode: appLanguage,
            defaultValue: qualification.resultType == "average" ? "average" : "single"
        )
        let requirement: String
        switch qualification.type {
        case "ranking":
            requirement = String(
                format: appLocalizedString(
                    "competitions.wca.qualification.ranking_format",
                    languageCode: appLanguage,
                    defaultValue: "Top %d by %@"
                ),
                qualification.level ?? 0,
                resultType
            )
        case "anyResult":
            requirement = String(
                format: appLocalizedString(
                    "competitions.wca.qualification.any_result_format",
                    languageCode: appLanguage,
                    defaultValue: "Any %@ result"
                ),
                resultType
            )
        case "attemptResult":
            let result = qualification.level.map {
                formatCompetitionLiveResultValue($0, eventID: eventID)
            } ?? ""
            requirement = String(
                format: appLocalizedString(
                    "competitions.wca.qualification.attempt_result_format",
                    languageCode: appLanguage,
                    defaultValue: "%@ under %@"
                ),
                resultType.capitalized,
                result
            )
        default:
            requirement = ""
        }

        let sourceFormatter = DateFormatter()
        sourceFormatter.locale = Locale(identifier: "en_US_POSIX")
        sourceFormatter.dateFormat = "yyyy-MM-dd"
        let deadline = sourceFormatter.date(from: qualification.whenDate).map { date -> String in
            let formatter = DateFormatter()
            formatter.locale = appLocale(for: appLanguage)
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        } ?? qualification.whenDate
        return String(
            format: appLocalizedString(
                "competitions.wca.qualification.deadline_format",
                languageCode: appLanguage,
                defaultValue: "%@ by %@"
            ),
            requirement,
            deadline
        )
    }

    private func localizedWCATimeLimit(
        _ round: CompetitionWCAEventRound,
        eventID: String
    ) -> String? {
        guard let centiseconds = round.timeLimitCentiseconds else {
            switch eventID {
            case "333fm":
                return appLocalizedString(
                    "competitions.wca.time_limit.fmc",
                    languageCode: appLanguage,
                    defaultValue: "1 hour"
                )
            case "333mbf":
                return appLocalizedString(
                    "competitions.wca.time_limit.multiblind",
                    languageCode: appLanguage,
                    defaultValue: "10:00.00 per cube, up to 60:00.00"
                )
            default:
                return nil
            }
        }
        let duration = formattedWCAEventDuration(centiseconds)
        guard !round.cumulativeRoundIDs.isEmpty else { return duration }

        let eventNames = Array(Set(round.cumulativeRoundIDs.compactMap { roundID -> String? in
            guard let eventID = roundID.components(separatedBy: "-r").first, !eventID.isEmpty else { return nil }
            return shortEventTitle(for: eventID)
        })).sorted().joined(separator: ", ")
        if round.cumulativeRoundIDs.count == 1 {
            return String(
                format: appLocalizedString(
                    "competitions.wca.time_limit.cumulative_format",
                    languageCode: appLanguage,
                    defaultValue: "%@ cumulative"
                ),
                duration
            )
        }
        return String(
            format: appLocalizedString(
                "competitions.wca.time_limit.total_for_format",
                languageCode: appLanguage,
                defaultValue: "%@ total for %@"
            ),
            duration,
            eventNames
        )
    }

    private func wcaTimeLimitMarker(for round: CompetitionWCAEventRound) -> String {
        guard round.timeLimitCentiseconds != nil else { return "" }
        switch round.cumulativeRoundIDs.count {
        case 1:
            return "*"
        case 2...:
            return "**"
        default:
            return ""
        }
    }

    private func localizedWCACutoff(_ round: CompetitionWCAEventRound, eventID: String) -> String? {
        guard let attempts = round.cutoffAttempts,
              let result = round.cutoffResult else { return nil }
        let resultText = formatCompetitionLiveResultValue(result, eventID: eventID)
        return String(
            format: appLocalizedString(
                "competitions.wca.cutoff.official_format",
                languageCode: appLanguage,
                defaultValue: "%d attempts to get < %@"
            ),
            attempts,
            resultText
        )
    }

    private func localizedWCAAdvancement(_ round: CompetitionWCAEventRound, eventID: String) -> String? {
        guard let type = round.advancementType,
              let level = round.advancementLevel else { return nil }
        let condition: String
        switch type {
        case "ranking":
            condition = String(
                format: appLocalizedString(
                    "competitions.wca.advancement.ranking_format",
                    languageCode: appLanguage,
                    defaultValue: "Top %d"
                ),
                level
            )
        case "percent":
            condition = String(
                format: appLocalizedString(
                    "competitions.wca.advancement.percent_format",
                    languageCode: appLanguage,
                    defaultValue: "Top %d%%"
                ),
                level
            )
        default:
            condition = formatCompetitionLiveResultValue(level, eventID: eventID)
        }
        return String(
            format: appLocalizedString(
                "competitions.wca.advancement.next_round_format",
                languageCode: appLanguage,
                defaultValue: "%@ advance to next round"
            ),
            condition
        )
    }

    private func formattedWCADuration(_ centiseconds: Int) -> String {
        let totalSeconds = max(centiseconds, 0) / 100
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formattedWCAEventDuration(_ centiseconds: Int) -> String {
        let safeValue = max(centiseconds, 0)
        let totalSeconds = safeValue / 100
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        let hundredths = safeValue % 100
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, hundredths)
        }
        return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
    }

    private func localizedCompetitorGender(_ rawValue: String?) -> String {
        guard let rawValue else { return "—" }

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "m", "male", "男":
            return localizedCompetitionStringInView(key: "wca.gender.male", languageCode: appLanguage)
        case "f", "female", "女":
            return localizedCompetitionStringInView(key: "wca.gender.female", languageCode: appLanguage)
        case "o", "other", "其他":
            return localizedCompetitionStringInView(key: "wca.gender.other", languageCode: appLanguage)
        default:
            return rawValue
        }
    }

    private func detailTextBlockCards(_ blocks: [CompetitionDetailTextBlock], fallbackTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks) { block in
                detailSectionCard(title: block.title?.isEmpty == false ? block.title! : fallbackTitle) {
                    detailTextBlockBody(block)
                }
            }
        }
    }

    private func cubingDetailDocument(_ blocks: [CompetitionDetailTextBlock], fallbackTitle: String) -> some View {
        cubingDetailDocumentBody(blocks, fallbackTitle: fallbackTitle)
    }

    private func cubingDetailDocumentBody(
        _ blocks: [CompetitionDetailTextBlock],
        fallbackTitle: String,
        mapLocations: [CompetitionTravelMapLocation] = [],
        mapURL: URL? = nil
    ) -> some View {
        let visibleBlocks = blocks.filter {
            !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.html?.localizedCaseInsensitiveContains("<img") == true
        }
        let mapBlockID = cubingTravelMapAnchorBlockID(in: visibleBlocks, mapLocations: mapLocations)

        return VStack(alignment: .leading, spacing: 14) {
            ForEach(visibleBlocks) { block in
                CubingDetailDocumentBlock(
                    block: block,
                    fallbackTitle: fallbackTitle,
                    areEventIconsReady: areCompetitionEventIconsReady
                )

                if block.id == mapBlockID {
                    CompetitionTravelMapCard(
                        locations: mapLocations,
                        openMapsURL: mapURL
                    )
                }
            }
        }
    }

    private func cubingTravelMapAnchorBlockID(
        in blocks: [CompetitionDetailTextBlock],
        mapLocations: [CompetitionTravelMapLocation]
    ) -> String? {
        guard !mapLocations.isEmpty else { return nil }

        if let block = blocks.first(where: { $0.html?.contains("location-map") == true }) {
            return block.id
        }

        if let block = blocks.first(where: { block in
            let title = block.title ?? ""
            return title.localizedCaseInsensitiveContains("location")
                || title.localizedCaseInsensitiveContains("venue")
                || title.contains("地点")
                || title.contains("地址")
                || title.contains("地點")
                || title.contains("場地")
        }) {
            return block.id
        }

        return blocks.first?.id
    }

    private func detailPlainSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailTextBlocks(_ blocks: [CompetitionDetailTextBlock]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                detailTextBlockBody(block, includesBlockTitleInSelection: true)
            }
        }
    }

    @ViewBuilder
    private func detailTextBlockBody(
        _ block: CompetitionDetailTextBlock,
        baseURL: URL? = nil,
        includesBlockTitleInSelection: Bool = false
    ) -> some View {
        if let html = block.html, !html.isEmpty {
            if isMainlandChinaCompetition {
                CompetitionRichHTMLContent(
                    html: html,
                    areEventIconsReady: areCompetitionEventIconsReady,
                    languageCode: appLanguage,
                    baseURL: baseURL,
                    addressFallback: competitionAddressDisplayFallback,
                    leadingTitle: includesBlockTitleInSelection ? block.title : nil
                )
            } else {
                CompetitionRichHTMLContent(
                    html: html,
                    areEventIconsReady: areCompetitionEventIconsReady,
                    languageCode: appLanguage,
                    baseURL: baseURL,
                    addressFallback: competitionAddressDisplayFallback,
                    onAddScheduleToCalendar: {
                        previewOfficialScheduleCalendar()
                    },
                    leadingTitle: includesBlockTitleInSelection ? block.title : nil
                )
            }
        } else {
            CompetitionRichHTMLContent(
                html: block.body,
                areEventIconsReady: areCompetitionEventIconsReady,
                languageCode: appLanguage,
                baseURL: baseURL,
                addressFallback: competitionAddressDisplayFallback,
                leadingTitle: includesBlockTitleInSelection ? block.title : nil
            )
        }
    }

    private var competitionAddressDisplayFallback: String {
        let address = CompetitionService.addressDisplayText(in: competition.venueAddress)
        if !address.isEmpty {
            return address
        }
        if !competition.venueLine.isEmpty {
            return competition.venueLine
        }
        return competition.locationLine
    }

    @ViewBuilder
    private func detailScheduleDayCard(_ day: CompetitionScheduleDay) -> some View {
        if isMainlandChinaCompetition {
            detailScheduleWebsiteDayPanel(day)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(wcaScheduleCalendarDayTitle(day.title))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                detailScheduleTraditionalTable(day, showsRoom: true, showsGroup: false)
            }
        }
    }

    private var cubingScheduleWebsiteIntro: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !detailContent.scheduleEventSummaries.isEmpty {
                cubingScheduleEventSelector
            }

            if let html = detailContent.scheduleIntroHTML, !html.isEmpty {
                CompetitionRichHTMLContent(
                    html: html,
                    areEventIconsReady: areCompetitionEventIconsReady,
                    languageCode: appLanguage
                )
                    .font(.system(size: 13, weight: .regular))
            }
        }
    }

    private var cubingScheduleEventSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HorizontalCapsuleSelectorGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(detailContent.scheduleEventSummaries) { summary in
                        cubingScheduleEventSelectorButton(summary)
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func cubingScheduleEventSelectorButton(_ summary: CompetitionScheduleEventSummary) -> some View {
        let eventCode = summary.eventCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let isSelected = !eventCode.isEmpty && eventCode == activeScheduleEventCode

        return Button {
            selectedScheduleEventCode = isSelected ? "" : eventCode
        } label: {
            CompetitionEventIconNameLabel(
                glyph: CompetitionEventIconFont.glyph(for: eventCode, title: summary.title),
                eventTitle: summary.title,
                name: summary.detail,
                iconSize: 15,
                iconWidth: 18,
                spacing: 7,
                nameFont: .system(size: 13, weight: isSelected ? .semibold : .regular),
                iconColor: HorizontalCapsuleSelectorForeground.color(isSelected: isSelected),
                nameColor: HorizontalCapsuleSelectorForeground.color(isSelected: isSelected),
                lineLimit: 1,
                showsIconPopover: false
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .horizontalCapsuleSelectorSurface(isSelected: isSelected) {
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.blue : Color.secondary.opacity(0.10))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cubingScheduleWebsiteComment: some View {
        if let html = detailContent.scheduleCommentHTML, !html.isEmpty {
            CompetitionRichHTMLContent(
                html: html,
                areEventIconsReady: areCompetitionEventIconsReady,
                languageCode: appLanguage
            )
                .padding(.top, 2)
        }
    }

    private func detailScheduleWebsiteDayPanel(_ day: CompetitionScheduleDay) -> some View {
        let showsGroup = day.entries.contains { detailScheduleOptionalValue($0.group) != nil }
        return VStack(alignment: .leading, spacing: 8) {
            Text(day.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            detailScheduleTraditionalTable(day, showsRoom: false, showsGroup: showsGroup)
        }
    }

    private var cubingScheduleCalendar: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(detailContent.scheduleDays) { day in
                cubingScheduleCalendarDay(day)
            }
        }
    }

    private func cubingScheduleCalendarDay(_ day: CompetitionScheduleDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)

                Text(day.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(String(format: "%d 项", day.entries.count))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(day.venues) { venue in
                        cubingScheduleCalendarVenueColumn(venue)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.background)
        )
    }

    private func cubingScheduleCalendarVenueColumn(_ venue: CompetitionScheduleVenue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(venue.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text("\(venue.entries.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.10), in: Capsule())
            }

            ForEach(venue.entries) { entry in
                cubingScheduleCalendarBlock(entry)
            }
        }
        .padding(12)
        .frame(width: 210, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func cubingScheduleCalendarBlock(_ entry: CompetitionScheduleEntry) -> some View {
        let color = cubingScheduleEventColor(for: entry)
        let chips = cubingScheduleCalendarChips(for: entry)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.timeText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)

                Spacer(minLength: 6)

                if let eventCode = entry.eventCode, !eventCode.isEmpty {
                    Text(shortEventTitle(for: eventCode))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.12), in: Capsule())
                }
            }

            Text(entry.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !chips.isEmpty {
                FlexibleTagFlow(items: Array(chips.prefix(3)))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }

    private func cubingScheduleCalendarChips(for entry: CompetitionScheduleEntry) -> [String] {
        var chips: [String] = []

        if let round = entry.round, !round.isEmpty {
            chips.append(round)
        }
        if let cutoff = entry.cutoff, !cutoff.isEmpty {
            chips.append(appLanguage.hasPrefix("zh") ? "及格线 \(cutoff)" : "Cutoff \(cutoff)")
        }
        if let timeLimit = entry.timeLimit, !timeLimit.isEmpty {
            chips.append(appLanguage.hasPrefix("zh") ? "时限 \(timeLimit)" : "Limit \(timeLimit)")
        }
        if let advancingCount = entry.advancingCount, !advancingCount.isEmpty {
            chips.append(appLanguage.hasPrefix("zh") ? "晋级 \(advancingCount)" : "Top \(advancingCount)")
        }

        return chips
    }

    private func cubingScheduleEventColor(for entry: CompetitionScheduleEntry) -> Color {
        switch entry.eventCode ?? "" {
        case "222":
            return .cyan
        case "333":
            return .blue
        case "444":
            return .indigo
        case "555", "666", "777":
            return .purple
        case "333bf", "444bf", "555bf", "333mbf":
            return .red
        case "333oh":
            return .orange
        case "clock":
            return .pink
        case "minx":
            return .teal
        case "pyram", "skewb":
            return .green
        case "sq1":
            return .yellow
        default:
            return .orange
        }
    }

    private func detailScheduleEntryCard(_ entry: CompetitionScheduleEntry, showsVenue: Bool) -> some View {
        let times = detailScheduleTimeParts(entry.timeText)
        let roundValue = detailScheduleOptionalValue(entry.round)
        let venueValue = showsVenue ? detailScheduleOptionalValue(entry.venueName) : nil
        let groupValue = detailScheduleOptionalValue(entry.group)
        let formatValue = detailScheduleOptionalValue(entry.format)
        let cutoffValue = detailScheduleOptionalValue(entry.cutoff)
        let timeLimitValue = detailScheduleOptionalValue(entry.timeLimit)
        let proceedValue = detailScheduleOptionalValue(entry.advancingCount)
        let color = cubingScheduleEventColor(for: entry)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(times.start)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    HStack(spacing: 4) {
                        Text(localizedScheduleFieldLabel(.start))
                        if let end = times.end {
                            Text("->")
                            Text(end)
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
                .frame(width: 86, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 7) {
                    CompetitionEventIconNameLabel(
                        glyph: areCompetitionEventIconsReady
                            ? CompetitionEventIconFont.glyph(for: entry.eventCode ?? "", title: entry.title)
                            : nil,
                        eventTitle: entry.title,
                        name: entry.title,
                        iconSize: 17,
                        iconWidth: 24,
                        spacing: 8,
                        nameFont: .system(size: 17, weight: .semibold),
                        iconColor: .orange
                    )

                    HStack(spacing: 6) {
                        if let roundValue {
                            detailScheduleCapsule(roundValue, color: color)
                        }
                        if let formatValue {
                            detailScheduleCapsule(formatValue, color: .secondary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 8) {
                if let cutoffValue {
                    detailScheduleInfoPill(
                        label: localizedScheduleFieldLabel(.cutoff),
                        value: cutoffValue
                    )
                }
                if let timeLimitValue {
                    detailScheduleInfoPill(
                        label: localizedScheduleFieldLabel(.timeLimit),
                        value: timeLimitValue
                    )
                }
                if let proceedValue {
                    detailScheduleInfoPill(
                        label: localizedScheduleFieldLabel(.proceed),
                        value: proceedValue
                    )
                }
            }

            if venueValue != nil || groupValue != nil {
                HStack(spacing: 8) {
                    if let venueValue {
                        detailScheduleMetaText(
                        label: localizedScheduleFieldLabel(.venue),
                            value: venueValue
                    )
                    }

                    if let groupValue {
                        detailScheduleMetaText(
                        label: localizedScheduleFieldLabel(.group),
                            value: groupValue
                    )
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }

    private func detailScheduleTraditionalTable(
        _ day: CompetitionScheduleDay,
        showsRoom: Bool,
        showsGroup: Bool
    ) -> some View {
        let isWebsiteTable = isMainlandChinaCompetition
        let tableWidth = detailScheduleTraditionalTableWidth(
            showsRoom: showsRoom,
            showsGroup: showsGroup
        )

        return ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                detailScheduleTraditionalHeader(showsRoom: showsRoom, showsGroup: showsGroup)

                ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                    detailScheduleHorizontalDivider
                    detailScheduleTraditionalRow(
                        entry,
                        index: index,
                        showsRoom: showsRoom,
                        showsGroup: showsGroup
                    )
                }
            }
            .frame(minWidth: tableWidth, alignment: .leading)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        ForEach(
                            Array(
                                detailScheduleColumnSeparatorOffsets(
                                    showsRoom: showsRoom,
                                    showsGroup: showsGroup
                                ).enumerated()
                            ),
                            id: \.offset
                        ) { _, offset in
                            Rectangle()
                                .fill(Color.secondary.opacity(0.10))
                                .frame(width: 1, height: proxy.size.height)
                                .offset(x: offset)
                        }
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .background(isWebsiteTable ? Color(uiColor: .systemBackground) : Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.55), lineWidth: 1)
        )
    }

    private func detailScheduleTraditionalHeader(showsRoom: Bool, showsGroup: Bool) -> some View {
        HStack(spacing: 0) {
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.start), width: detailScheduleStartColumnWidth)
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.end), width: detailScheduleEndColumnWidth)
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.event), width: detailScheduleEventColumnWidth)
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.round), width: detailScheduleRoundColumnWidth)
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.format), width: detailScheduleFormatColumnWidth)
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.cutoff), width: detailScheduleCutoffColumnWidth)
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.timeLimit), width: detailScheduleTimeLimitColumnWidth)
            detailScheduleTraditionalHeaderCell(localizedScheduleFieldLabel(.proceed), width: detailScheduleCompetitorsColumnWidth)

            if showsRoom {
                detailScheduleTraditionalHeaderCell(
                    localizedScheduleFieldLabel(.room),
                    width: detailScheduleRoomColumnWidth
                )
            }
            if showsGroup {
                detailScheduleTraditionalHeaderCell(
                    localizedScheduleFieldLabel(.group),
                    width: detailScheduleGroupColumnWidth
                )
            }
        }
        .background(Color.secondary.opacity(0.08))
    }

    private func detailScheduleTraditionalRow(
        _ entry: CompetitionScheduleEntry,
        index: Int,
        showsRoom: Bool,
        showsGroup: Bool
    ) -> some View {
        let times = detailScheduleTimeParts(entry.timeText)
        let roundValue = detailScheduleOptionalValue(entry.round)
        let roomValue = showsRoom ? detailScheduleOptionalValue(entry.venueName) : nil
        let groupValue = detailScheduleOptionalValue(entry.group)
        let formatValue = detailScheduleOptionalValue(entry.format)
        let cutoffValue = detailScheduleOptionalValue(entry.cutoff)
        let timeLimitValue = detailScheduleOptionalValue(entry.timeLimit)
        let proceedValue = detailScheduleOptionalValue(entry.advancingCount)
        let isHighlighted = detailScheduleEntryMatchesActiveEvent(entry)

        let blankValue = ""

        return HStack(spacing: 0) {
            detailScheduleTraditionalCell(times.start, width: detailScheduleStartColumnWidth, role: .time)
            detailScheduleTraditionalCell(times.end ?? blankValue, width: detailScheduleEndColumnWidth, role: .time)
            detailScheduleTraditionalEventCell(entry, width: detailScheduleEventColumnWidth)
            detailScheduleTraditionalCell(roundValue ?? blankValue, width: detailScheduleRoundColumnWidth, role: .secondary)
            detailScheduleTraditionalCell(formatValue ?? blankValue, width: detailScheduleFormatColumnWidth, role: .secondary)
            detailScheduleTraditionalCell(cutoffValue ?? blankValue, width: detailScheduleCutoffColumnWidth, role: .secondary)
            detailScheduleTraditionalCell(timeLimitValue ?? blankValue, width: detailScheduleTimeLimitColumnWidth, role: .secondary)
            detailScheduleTraditionalCell(proceedValue ?? blankValue, width: detailScheduleCompetitorsColumnWidth, role: .secondary)

            if showsRoom {
                detailScheduleTraditionalCell(
                    roomValue ?? blankValue,
                    width: detailScheduleRoomColumnWidth,
                    role: .secondary
                )
            }
            if showsGroup {
                detailScheduleTraditionalCell(
                    groupValue ?? blankValue,
                    width: detailScheduleGroupColumnWidth,
                    role: .secondary
                )
            }
        }
        .background(detailScheduleRowBackground(index: index, isHighlighted: isHighlighted))
    }

    private func detailScheduleEntryMatchesActiveEvent(_ entry: CompetitionScheduleEntry) -> Bool {
        guard isMainlandChinaCompetition, !activeScheduleEventCode.isEmpty else { return false }
        return entry.eventCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == activeScheduleEventCode
    }

    private func detailScheduleRowBackground(index: Int, isHighlighted: Bool) -> Color {
        if isHighlighted {
            return Color.blue.opacity(0.10)
        }

        return index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025)
    }

    private func detailScheduleCapsule(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.10), in: Capsule())
    }

    private func detailScheduleInfoPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.70), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func detailScheduleMetaText(label: String, value: String) -> some View {
        Text("\(label): \(value)")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private enum DetailScheduleCellRole {
        case time
        case event
        case secondary
    }

    private func detailScheduleTraditionalHeaderCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(width: width, alignment: .leading)
    }

    private func detailScheduleTraditionalCell(_ text: String, width: CGFloat, role: DetailScheduleCellRole) -> some View {
        Text(text)
            .font(detailScheduleCellValueFont(for: role))
            .foregroundStyle(Color.primary.opacity(role == .secondary ? 0.88 : 1))
            .lineLimit(role == .event ? 2 : 1)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
            .frame(width: width, alignment: .leading)
    }

    private func detailScheduleTraditionalEventCell(_ entry: CompetitionScheduleEntry, width: CGFloat) -> some View {
        let code = entry.eventCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let eventTitle = !isMainlandChinaCompetition && code != nil && code != "other"
            ? localizedWCAEventTitle(code ?? "")
            : entry.title

        return CompetitionEventIconNameLabel(
            glyph: areCompetitionEventIconsReady
                ? CompetitionEventIconFont.glyph(for: code ?? "", title: entry.title)
                : nil,
            eventTitle: eventTitle,
            name: eventTitle,
            iconSize: 15,
            iconWidth: 22,
            spacing: 7,
            nameFont: detailScheduleCellValueFont(for: .event),
            lineLimit: 2
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .frame(width: width, alignment: .leading)
    }

    private var detailScheduleHorizontalDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.10))
            .frame(height: 1)
    }

    private var detailScheduleVerticalDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.10))
            .frame(width: 1)
    }

    private func detailScheduleCellValueFont(for role: DetailScheduleCellRole) -> Font {
        switch role {
        case .time:
            return .system(size: 13, weight: .regular, design: .default)
        case .event:
            return .system(size: 14, weight: .medium)
        case .secondary:
            return .system(size: 13, weight: .regular)
        }
    }

    private var detailScheduleStartColumnWidth: CGFloat { isMainlandChinaCompetition ? 72 : 64 }
    private var detailScheduleEndColumnWidth: CGFloat { isMainlandChinaCompetition ? 72 : 64 }
    private var detailScheduleEventColumnWidth: CGFloat { isMainlandChinaCompetition ? 236 : 210 }
    private var detailScheduleRoundColumnWidth: CGFloat { isMainlandChinaCompetition ? 102 : 92 }
    private var detailScheduleFormatColumnWidth: CGFloat { isMainlandChinaCompetition ? 156 : 110 }
    private var detailScheduleCutoffColumnWidth: CGFloat { isMainlandChinaCompetition ? 145 : 118 }
    private var detailScheduleTimeLimitColumnWidth: CGFloat { isMainlandChinaCompetition ? 145 : 118 }
    private var detailScheduleCompetitorsColumnWidth: CGFloat { isMainlandChinaCompetition ? 72 : 86 }
    private var detailScheduleRoomColumnWidth: CGFloat { 112 }
    private var detailScheduleGroupColumnWidth: CGFloat { 82 }

    private func detailScheduleTraditionalTableWidth(showsRoom: Bool, showsGroup: Bool) -> CGFloat {
        let baseWidth = detailScheduleStartColumnWidth
            + detailScheduleEndColumnWidth
            + detailScheduleEventColumnWidth
            + detailScheduleRoundColumnWidth
            + detailScheduleFormatColumnWidth
            + detailScheduleCutoffColumnWidth
            + detailScheduleTimeLimitColumnWidth
            + detailScheduleCompetitorsColumnWidth
        return baseWidth
            + (showsRoom ? detailScheduleRoomColumnWidth : 0)
            + (showsGroup ? detailScheduleGroupColumnWidth : 0)
    }

    private func detailScheduleColumnSeparatorOffsets(showsRoom: Bool, showsGroup: Bool) -> [CGFloat] {
        var widths = [
            detailScheduleStartColumnWidth,
            detailScheduleEndColumnWidth,
            detailScheduleEventColumnWidth,
            detailScheduleRoundColumnWidth,
            detailScheduleFormatColumnWidth,
            detailScheduleCutoffColumnWidth,
            detailScheduleTimeLimitColumnWidth,
            detailScheduleCompetitorsColumnWidth
        ]
        if showsRoom {
            widths.append(detailScheduleRoomColumnWidth)
        }
        if showsGroup {
            widths.append(detailScheduleGroupColumnWidth)
        }

        var offset: CGFloat = 0
        return widths.dropLast().map { width in
            offset += width
            return offset
        }
    }

    private func detailScheduleOptionalValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func detailScheduleTimeParts(_ timeText: String) -> (start: String, end: String?) {
        let separators = ["–", "-", "—", "~"]
        for separator in separators {
            let parts = timeText.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count >= 2 {
                return (parts[0], parts[1])
            }
        }

        return (timeText, nil)
    }

    private enum ScheduleFieldLabel {
        case display
        case start
        case end
        case event
        case round
        case format
        case cutoff
        case timeLimit
        case proceed
        case venue
        case room
        case group
    }

    private func localizedScheduleFieldLabel(_ label: ScheduleFieldLabel) -> String {
        let isChinese = appLanguage.hasPrefix("zh")
        switch label {
        case .display:
            return isChinese ? "显示方式" : "View"
        case .start:
            return isChinese ? "开始" : "Start"
        case .end:
            return isChinese ? "结束" : "End"
        case .event:
            return isChinese ? "项目" : "Event"
        case .round:
            return isChinese ? "轮次" : "Round"
        case .format:
            return isChinese ? "赛制" : "Format"
        case .cutoff:
            return isChinese ? "及格线" : "Cutoff"
        case .timeLimit:
            return isChinese ? "时限" : "Time Limit"
        case .proceed:
            return isChinese ? "晋级" : "Proceed"
        case .venue:
            return isChinese ? "场地" : "Venue"
        case .room:
            return isChinese ? "赛区" : "Room"
        case .group:
            return isChinese ? "分组" : "Group"
        }
    }

    private func configureWCALiveSession() {
        guard !isMainlandChinaCompetition, let source = sourceWCALiveContent else { return }
        wcaLiveSession.configure(source, language: appLanguage)
    }

    @ViewBuilder private func wcaLiveRoundBadge(_ id: String) -> some View {
        if let tag = wcaLiveSession.roundTag(id, ownWCAID: ownWCAID) {
            CompetitionWCARecordTagView(tag: tag, variant: .compact, isOwnPersonalRecord: tag == "PR")
        }
    }

    private func wcaLiveHomeContent(_ content: CompetitionWCALiveContent) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    String(
                        format: appLocalizedString(
                            "competitions.detail.live.wca.welcome_format",
                            languageCode: appLanguage,
                            defaultValue: "Welcome to %@!"
                        ),
                        content.competitionName ?? displayCompetitionName
                    )
                )
                .wcaLiveSectionHeadingStyle()
                .selectableContent()

                if let countryText = wcaLiveCountryText(content) {
                    Text(wcaLiveIntroduction(countryText: countryText, officialURL: officialURL))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.primary)
                        .tint(.blue)
                        .fixedSize(horizontal: false, vertical: true)
                        .selectableContent()
                }
            }

            let activeRounds = content.rounds.filter(\.isActive)
            if !activeRounds.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        appLocalizedString(
                            "competitions.detail.live.wca.active_rounds",
                            languageCode: appLanguage,
                            defaultValue: "Active Rounds"
                        )
                    )
                    .wcaLiveSectionHeadingStyle()

                    ForEach(activeRounds) { round in
                        NavigationLink {
                            CompetitionWCALiveRoundDetailView(
                                round: round,
                                competitionID: content.competitionID,
                                languageCode: appLanguage,
                                areEventIconsReady: areCompetitionEventIconsReady,
                                session: wcaLiveSession
                            )
                        } label: {
                            HStack(spacing: 12) {
                                competitionEventIconLabel(for: round.eventID, isEmphasized: true)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(
                                        CompetitionEventPresentation.normalizedName(
                                            for: round.eventID,
                                            fallback: round.eventName,
                                            languageCode: appLanguage
                                        )
                                    )
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)

                                    Text(round.roundName)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 8)
                                wcaLiveRoundBadge(round.id)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let scheduleItems = wcaLiveScheduleItems(content)
            if !scheduleItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(
                            localizedCompetitionStringInView(
                                key: "competitions.detail.section.schedule",
                                languageCode: appLanguage
                            )
                        )
                        .wcaLiveSectionHeadingStyle()

                        Spacer(minLength: 8)

                        CompetitionTextPopoverButton(text: wcaLiveTimezoneNotice) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    wcaLiveScheduleDateStrip(scheduleItems)

                    VStack(spacing: 0) {
                        ForEach(Array(wcaLiveScheduleItemsForSelectedDate(scheduleItems).enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider().padding(.leading, 48) }
                            NavigationLink {
                                CompetitionWCALiveRoundDetailView(
                                    round: item.round,
                                    competitionID: content.competitionID,
                                    languageCode: appLanguage,
                                    areEventIconsReady: areCompetitionEventIconsReady,
                                session: wcaLiveSession
                                )
                            } label: {
                                wcaLiveScheduleRow(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            if let records = content.records, !records.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        appLocalizedString(
                            "competitions.detail.live.wca.records",
                            languageCode: appLanguage,
                            defaultValue: "Records"
                        )
                    )
                    .wcaLiveSectionHeadingStyle()

                    VStack(spacing: 0) {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            if index > 0 { Divider() }
                            if let round = content.rounds.first(where: { $0.id == record.roundID }) {
                                NavigationLink {
                                    CompetitionWCALiveRoundDetailView(
                                        round: round,
                                        competitionID: content.competitionID,
                                        languageCode: appLanguage,
                                        areEventIconsReady: areCompetitionEventIconsReady,
                                        resultDeepLink: record.resultDeepLink,
                                        session: wcaLiveSession
                                    )
                                } label: {
                                    wcaLiveRecordRow(record)
                                }
                                .buttonStyle(.plain)
                            } else {
                                wcaLiveRecordRow(record)
                            }
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            if shouldShowLiveLink, let liveURL {
                Link(destination: liveURL) {
                    detailPrimaryButton(
                        localizedCompetitionStringInView(
                            key: "competitions.detail.open_live",
                            languageCode: appLanguage
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { configureWCALiveSession(); wcaLiveSession.beginHomeVisit() }
    }

    private func wcaLiveCountryText(_ content: CompetitionWCALiveContent) -> String? {
        let countries = Array(
            Set(
                content.venues.compactMap { venue in
                    venue.countryName?.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
            )
        ).sorted()

        guard !countries.isEmpty else { return nil }
        if countries.count == 1 { return countries[0] }
        return appLocalizedString(
            "competitions.detail.live.wca.multiple_countries",
            languageCode: appLanguage,
            defaultValue: "multiple countries"
        )
    }

    private func wcaLiveIntroduction(countryText: String, officialURL: URL?) -> AttributedString {
        let websiteTitle = appLocalizedString(
            "competitions.detail.live.wca.website",
            languageCode: appLanguage,
            defaultValue: "WCA website"
        )
        let text = String(
            format: appLocalizedString(
                "competitions.detail.live.wca.introduction_format",
                languageCode: appLanguage,
                defaultValue: "This competition takes place in %@. Check out the WCA website for more details on the competition."
            ),
            countryText
        )
        var attributed = AttributedString(text)
        if let officialURL,
           let websiteRange = attributed.range(of: websiteTitle) {
            attributed[websiteRange].link = officialURL
            attributed[websiteRange].foregroundColor = .blue
        }
        return attributed
    }

    private var wcaLiveTimezoneNotice: String {
        String(
            format: appLocalizedString(
                "competitions.detail.live.wca.timezone_format",
                languageCode: appLanguage,
                defaultValue: "All dates and times below are displayed in your local timezone: %@"
            ),
            TimeZone.current.identifier
        )
    }

    private func wcaLiveScheduleItems(_ content: CompetitionWCALiveContent) -> [CompetitionWCALiveScheduleItem] {
        let activities = content.venues
            .flatMap(\.rooms)
            .flatMap { $0.activities ?? [] }

        return content.rounds.compactMap { round in
            guard let number = round.number else { return nil }
            let activityPrefix = "\(round.eventID)-r\(number)"
            let matchingActivities = activities.filter { activity in
                guard let code = activity.activityCode else { return false }
                return code == activityPrefix || code.hasPrefix(activityPrefix + "-")
            }
            guard let startTime = matchingActivities.map(\.startTime).min(),
                  let endTime = matchingActivities.map(\.endTime).max() else {
                return nil
            }
            return CompetitionWCALiveScheduleItem(
                round: round,
                startTime: startTime,
                endTime: endTime,
                colorHex: CompetitionLiveScheduleColor.hex(activities: matchingActivities, event: round.eventID, round: number)
            )
        }
        .sorted { lhs, rhs in
            if lhs.startTime != rhs.startTime { return lhs.startTime < rhs.startTime }
            return lhs.round.eventName.localizedCaseInsensitiveCompare(rhs.round.eventName) == .orderedAscending
        }
    }

    private func wcaLiveScheduleDates(_ items: [CompetitionWCALiveScheduleItem]) -> [Date] {
        Array(Set(items.map { Calendar.current.startOfDay(for: $0.startTime) })).sorted()
    }

    private func effectiveWCALiveScheduleDate(_ items: [CompetitionWCALiveScheduleItem]) -> Date? {
        let dates = wcaLiveScheduleDates(items)
        guard !dates.isEmpty else { return nil }
        if let selectedWCALiveScheduleDate,
           dates.contains(selectedWCALiveScheduleDate) {
            return selectedWCALiveScheduleDate
        }

        let today = Calendar.current.startOfDay(for: Date())
        return dates.min { lhs, rhs in
            abs(lhs.timeIntervalSince(today)) < abs(rhs.timeIntervalSince(today))
        }
    }

    private func wcaLiveScheduleItemsForSelectedDate(
        _ items: [CompetitionWCALiveScheduleItem]
    ) -> [CompetitionWCALiveScheduleItem] {
        guard let selectedDate = effectiveWCALiveScheduleDate(items) else { return items }
        return items.filter { Calendar.current.isDate($0.startTime, inSameDayAs: selectedDate) }
    }

    private func wcaLiveScheduleDateStrip(_ items: [CompetitionWCALiveScheduleItem]) -> some View {
        let dates = wcaLiveScheduleDates(items)
        let selectedDate = effectiveWCALiveScheduleDate(items)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(dates, id: \.self) { date in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedWCALiveScheduleDate = date
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(wcaLiveScheduleDateTitle(date))
                                .font(.system(size: 15, weight: date == selectedDate ? .semibold : .medium))
                                .foregroundStyle(date == selectedDate ? Color.primary : Color.secondary)
                                .lineLimit(1)

                            Rectangle()
                                .fill(date == selectedDate ? Color.accentColor : Color.clear)
                                .frame(height: 2)
                        }
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func wcaLiveScheduleDateTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: appLanguage)
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return formatter.string(from: date).uppercased(with: formatter.locale)
    }

    private func wcaLiveScheduleRow(_ item: CompetitionWCALiveScheduleItem) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    CompetitionLiveEventIconView(
                        eventID: item.round.eventID,
                        languageCode: appLanguage,
                        isReady: areCompetitionEventIconsReady,
                        color: .primary,
                        size: 18
                    )
                    .frame(width: 24)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(
                            "\(CompetitionEventPresentation.normalizedName(for: item.round.eventID, fallback: item.round.eventName, languageCode: appLanguage)) - \(item.round.roundName)"
                        )
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(colorFromHex(item.colorHex) ?? Color.secondary)
                                .frame(width: 8, height: 8)

                            Text("\(localizedCompetitionTime(item.startTime))-\(localizedCompetitionTime(item.endTime))")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)
                    wcaLiveRoundBadge(item.round.id)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                let progress = wcaLiveScheduleProgress(item, at: context.date)
                if progress > 0, progress < 1 {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                }
            }
            .contentShape(Rectangle())
        }
    }

    private func wcaLiveScheduleProgress(_ item: CompetitionWCALiveScheduleItem, at date: Date) -> Double {
        let duration = item.endTime.timeIntervalSince(item.startTime)
        guard duration > 0 else { return 0 }
        return min(max(date.timeIntervalSince(item.startTime) / duration, 0), 1)
    }

    private func wcaLiveScheduleVenue(_ venue: CompetitionWCALiveVenue) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(venue.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                if let countryName = venue.countryName, !countryName.isEmpty {
                    Text(countryName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(venue.rooms) { room in
                VStack(alignment: .leading, spacing: 8) {
                    Text(room.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    let activities = (room.activities ?? []).sorted { $0.startTime < $1.startTime }
                    if activities.isEmpty {
                        if let subtitle = wcaLiveRoomSubtitle(room) {
                            Text(subtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(activities) { activity in
                            wcaLiveActivityRow(activity)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func wcaLiveActivityRow(_ activity: CompetitionWCALiveActivity) -> some View {
        let eventID = activity.activityCode?
            .split(separator: "-")
            .first
            .map(String.init)
        let tint = colorFromHex(activity.roomColorHex) ?? .accentColor

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(localizedCompetitionTime(activity.startTime))
                Text(localizedCompetitionTime(activity.endTime))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium))
            .frame(width: 48, alignment: .trailing)

            Capsule()
                .fill(tint)
                .frame(width: 4, height: 38)

            CompetitionEventIconNameLabel(
                glyph: CompetitionEventIconFont.glyph(for: eventID ?? "", title: activity.name),
                eventTitle: eventID.map(localizedWCAEventTitle) ?? activity.name,
                name: activity.name,
                iconSize: 15,
                iconWidth: 22,
                spacing: 10,
                nameFont: .system(size: 14, weight: .medium),
                lineLimit: 3
            )

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func wcaLiveRecordRow(_ record: CompetitionWCALiveRecord) -> some View {
        let result = formatCompetitionLiveResultValue(record.attemptResult, eventID: record.eventID)
        let summary = String(
            format: appLocalizedString(
                "competitions.detail.live.wca.record_result_format",
                languageCode: appLanguage,
                defaultValue: "%1$@ %2$@ of %3$@"
            ),
            record.eventName,
            record.type,
            result
        )
        var styledSummary = AttributedString(summary)
        styledSummary.font = .system(size: 14, weight: .regular)
        if let resultRange = summary.range(of: result, options: .backwards),
           let attributedResultRange = Range(resultRange, in: styledSummary) {
            styledSummary[attributedResultRange].font = .system(size: 14, weight: .semibold)
        }

        return HStack(alignment: .center, spacing: 10) {
            CompetitionWCARecordTagView(tag: record.tag, variant: .standard)
                .frame(width: 36, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(styledSummary)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    String(
                        format: appLocalizedString(
                            "competitions.detail.live.wca.record_person_format",
                            languageCode: appLanguage,
                            defaultValue: "%1$@ from %2$@"
                        ),
                        record.personName,
                        record.countryName
                    )
                )
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func colorFromHex(_ value: String?) -> Color? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let number = UInt64(cleaned, radix: 16) else { return nil }

        switch cleaned.count {
        case 6:
            return Color(
                red: Double((number >> 16) & 0xFF) / 255,
                green: Double((number >> 8) & 0xFF) / 255,
                blue: Double(number & 0xFF) / 255
            )
        default:
            return nil
        }
    }

    private var wcaLiveRoundPicker: some View {
        Picker(
            localizedCompetitionStringInView(key: "competitions.detail.live.wca.rounds", languageCode: appLanguage),
            selection: Binding(
                get: { effectiveWCALiveRoundID },
                set: { selectedWCALiveRoundID = $0 }
            )
        ) {
            ForEach(groupedWCALiveRounds, id: \.eventID) { group in
                Section(shortEventTitle(for: group.eventID)) {
                    ForEach(group.rounds) { round in
                        Text(round.roundName)
                            .tag(round.id)
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .tint(.primary)
    }

    private var groupedWCALiveRounds: [(eventID: String, rounds: [CompetitionWCALiveRound])] {
        Dictionary(grouping: wcaLiveRounds, by: \.eventID)
            .keys
            .sorted()
            .map { eventID in
                let rounds = wcaLiveRounds
                    .filter { $0.eventID == eventID }
                    .sorted { lhs, rhs in (lhs.number ?? 0) < (rhs.number ?? 0) }
                return (eventID: eventID, rounds: rounds)
            }
    }

    private func wcaLiveResultsTable(_ round: CompetitionWCALiveRound) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                competitionEventIconLabel(for: round.eventID, isEmphasized: true)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(round.roundName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(
                        CompetitionEventPresentation.normalizedName(
                            for: round.eventID,
                            fallback: round.eventName,
                            languageCode: appLanguage
                        )
                    )
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                if round.isActive || round.isOpen {
                    Text(
                        localizedCompetitionStringInView(
                            key: round.isActive ? "competitions.detail.live.wca.active" : "competitions.detail.live.wca.open",
                            languageCode: appLanguage
                        )
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(round.isActive ? Color.orange : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(round.isActive ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.08))
                    )
                }
            }

            if round.results.isEmpty {
                Text(liveStatusBody)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        wcaLiveResultsHeader

                        Divider()
                            .padding(.vertical, 8)

                        VStack(spacing: 10) {
                            ForEach(round.results) { result in
                                wcaLiveResultsRow(result, eventID: round.eventID)
                            }
                        }
                    }
                    .padding(12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var wcaLiveResultsHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            wcaLiveHeaderCell("#", width: 36)
            wcaLiveHeaderCell(localizedCompetitionStringInView(key: "competitions.detail.competitors_column.name", languageCode: appLanguage), width: 180)
            wcaLiveHeaderCell(localizedCompetitionStringInView(key: "competitions.detail.competitors_column.region", languageCode: appLanguage), width: 96)
            ForEach(1...5, id: \.self) { attempt in
                wcaLiveHeaderCell("\(attempt)", width: 58)
            }
            wcaLiveHeaderCell(localizedCompetitionStringInView(key: "wca.results_average", languageCode: appLanguage), width: 78)
            wcaLiveHeaderCell(localizedCompetitionStringInView(key: "common.best", languageCode: appLanguage), width: 68)
        }
    }

    private func wcaLiveHeaderCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
    }

    private func wcaLiveResultsRow(_ result: CompetitionWCALiveResultPreview, eventID: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(result.ranking.map(String.init) ?? "")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.orange)
                .frame(width: 36, alignment: .leading)

            Text(result.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)

            Text(result.region ?? "")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)

            ForEach(0..<5, id: \.self) { index in
                Text(wcaLiveAttemptText(result.attempts, index: index, eventID: eventID))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 58, alignment: .leading)
            }

            Text(formatCompetitionLiveResultValue(result.average, eventID: eventID))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 78, alignment: .leading)

            Text(formatCompetitionLiveResultValue(result.best, eventID: eventID))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 68, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private func wcaLiveAttemptText(_ attempts: [Int], index: Int, eventID: String) -> String {
        guard attempts.indices.contains(index) else { return "" }
        return formatCompetitionLiveResultValue(attempts[index], eventID: eventID)
    }

    private func wcaLiveVenueCard(_ venue: CompetitionWCALiveVenue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(venue.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                if let countryName = venue.countryName, !countryName.isEmpty {
                    Text(countryName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(venue.rooms) { room in
                VStack(alignment: .leading, spacing: 3) {
                    Text(room.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let subtitle = wcaLiveRoomSubtitle(room) {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.background)
        )
    }

    private func wcaLiveRoomSubtitle(_ room: CompetitionWCALiveRoom) -> String? {
        if let currentActivityName = room.currentActivityName {
            if let start = room.currentActivityStart, let end = room.currentActivityEnd {
                return "\(localizedCompetitionStringInView(key: "competitions.detail.live.wca.now", languageCode: appLanguage)) · \(localizedCompetitionTime(start))–\(localizedCompetitionTime(end)) · \(currentActivityName)"
            }
            return "\(localizedCompetitionStringInView(key: "competitions.detail.live.wca.now", languageCode: appLanguage)) · \(currentActivityName)"
        }

        if let nextActivityName = room.nextActivityName,
           let nextActivityStart = room.nextActivityStart {
            return "\(localizedCompetitionStringInView(key: "competitions.detail.live.wca.next", languageCode: appLanguage)) · \(localizedCompetitionTime(nextActivityStart)) · \(nextActivityName)"
        }

        return nil
    }

    private func localizedCompetitionTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLocale(for: appLanguage)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private enum DetailLoadEvent: Sendable {
        case resource(CompetitionDetailResource, CompetitionDetailContent)
        case publication, publicationScrambles
    }

    private func loadDetailContent(refresh: Bool = false) async {
        #if DEBUG
        if isRenderingFixture {
            updateCompetitionDetailDerivedState()
            loadingLifecycle.finishSession()
            return
        }
        #endif
        let loadStart = CACurrentMediaTime()
        let identity = "\(competition.id)|\(appLanguage)"
        if detailContentIdentity != identity {
            detailContent = .empty
            staleCachedDetailResources = []
            detailContentIdentity = identity
            selectedWCAInfoSectionID = ""
        }
        updateCompetitionDetailDerivedState()
        let competition = competition
        let language = appLanguage
        let china = isMainlandChinaCompetition
        let publicationApplies = CompetitionDetailNavigationPolicy.shouldCheckPublication(
            competitionEnded: competition.endDate <= Date(), explicitPublishedResult: explicitlyOpenedPublishedResult)
        let store = publishedStore
        let initial = CompetitionSectionLoadingPlan.initialResources(china: china, explicitLive: explicitlyOpenedLive,
            knownTickets: detailContent.showTickets == true)
        let generation = loadingLifecycle.begin(identity: identity, resources: initial,
            publication: publicationApplies, refresh: refresh)
        isLoadingWCALive = initial.contains(.live)
        isLoadingCompetitors = initial.contains(.competitors)
        var scheduled = Set(initial)
        var publicationChecked = !publicationApplies
        // Disk-backed, non-provisional sections are useful before revalidation.
        // Live/competitors/tickets are deliberately excluded from stale hydration.
        for resource in CompetitionDetailResource.allCases where CompetitionCachePolicy.persists(resource) {
            let cached = await CompetitionService.cachedCompetitionResourceSnapshot(resource, for: competition, languageCode: language)
            guard !Task.isCancelled, loadingLifecycle.accepts(generation, identity: identity) else { return }
            if let cached {
                detailContent = detailContent.merging(cached.content, resource: resource)
                if cached.isStale(resource: resource) { staleCachedDetailResources.insert(resource) }
            }
        }
        updateCompetitionDetailDerivedState()
        await withTaskGroup(of: DetailLoadEvent.self) { group in
            for resource in initial {
                group.addTask {
                    .resource(resource, await CompetitionService.fetchCompetitionResource(resource, for: competition,
                        languageCode: language, forceRefresh: refresh))
                }
            }
            if publicationApplies {
                group.addTask {
                    await store.load(competition: competition, language: language, refresh: refresh)
                    return .publication
                }
            } else if scheduled.insert(.live).inserted {
                loadingLifecycle.schedule(.detail(.live)); isLoadingWCALive = true
                group.addTask {
                    .resource(.live, await CompetitionService.fetchCompetitionResource(.live, for: competition,
                        languageCode: language, forceRefresh: refresh))
                }
            }
            for await event in group {
                guard !Task.isCancelled, loadingLifecycle.accepts(generation, identity: identity) else { group.cancelAll(); continue }
                var additions: [CompetitionDetailResource] = []
                switch event {
                case let .resource(resource, fetched):
                    detailContent = detailContent.merging(fetched, resource: resource)
                    if fetched != .empty { staleCachedDetailResources.remove(resource) }
                    loadingLifecycle.finish(.detail(resource))
                    if resource == .info {
                        if china, fetched.showTickets == true { additions.append(.tickets) }
                        synchronizeWCAInfoSectionSelection()
                        additions += CompetitionSectionLoadingPlan.historicalResources(china: china,
                            publicationChecked: publicationChecked, lifecycle: store.lifecycle,
                            hasRegistration: fetched.hasRegisterLink, hasCompetitors: fetched.hasCompetitorsLink)
                        CompetitionLoadingTrace.record("detail-first-useful", since: loadStart, detail: competition.id)
                    }
                    if resource == .schedule { synchronizeWCAScheduleRoomSelection() }
                    if resource == .competitors { isLoadingCompetitors = false }
                    if resource == .live { isLoadingWCALive = false; presentInitialWCALiveResultIfAvailable() }
                    updateCompetitionDetailDerivedState()
                case .publication:
                    loadingLifecycle.finish(.publication)
                    publicationChecked = true
                    additions += CompetitionSectionLoadingPlan.historicalResources(china: china,
                        publicationChecked: true, lifecycle: store.lifecycle,
                        hasRegistration: detailContent.hasRegisterLink, hasCompetitors: detailContent.hasCompetitorsLink)
                    additions.append(.live)
                    if store.lifecycle == .published, let id = store.data?.competitionID {
                        // No scramble request before official publication has been validated.
                        loadingLifecycle.schedule(.scrambles)
                        group.addTask {
                            await store.scrambles.load(id: id, refresh: refresh)
                            return .publicationScrambles
                        }
                    }
                case .publicationScrambles: loadingLifecycle.finish(.scrambles)
                }
                for resource in additions where scheduled.insert(resource).inserted {
                    loadingLifecycle.schedule(.detail(resource))
                    if resource == .competitors { isLoadingCompetitors = true }
                    if resource == .live { isLoadingWCALive = true }
                    group.addTask {
                        .resource(resource, await CompetitionService.fetchCompetitionResource(resource, for: competition,
                            languageCode: language, forceRefresh: refresh))
                    }
                }
            }
        }
        guard !Task.isCancelled, loadingLifecycle.accepts(generation, identity: identity) else { return }
        await loadPsychPreviewsIfNeeded()
        guard !Task.isCancelled, loadingLifecycle.accepts(generation, identity: identity) else { return }
        if !loadingLifecycle.isLoading {
            CompetitionLoadingTrace.record("detail-all-sections", since: loadStart, detail: competition.id)
        }
    }

    private func synchronizeWCAInfoSectionSelection() {
        guard !isMainlandChinaCompetition else { return }
        selectedWCAInfoSectionID = effectiveWCAInfoSectionID
    }

    private func synchronizeWCAScheduleRoomSelection() {
        guard !isMainlandChinaCompetition else {
            selectedWCAScheduleRoomIDs.removeAll()
            knownWCAScheduleRoomIDs.removeAll()
            wcaScheduleRoomSelectionCompetitionID = nil
            return
        }

        let availableIDs = Set(wcaScheduleRoomOptions.map(\.id))
        if wcaScheduleRoomSelectionCompetitionID != competition.id {
            wcaScheduleRoomSelectionCompetitionID = competition.id
            knownWCAScheduleRoomIDs = availableIDs
            selectedWCAScheduleRoomIDs = availableIDs
            return
        }

        // Preserve the user's current choices across refreshes while selecting
        // newly introduced rooms by default, matching the website's behavior.
        selectedWCAScheduleRoomIDs.formIntersection(availableIDs)
        selectedWCAScheduleRoomIDs.formUnion(availableIDs.subtracting(knownWCAScheduleRoomIDs))
        knownWCAScheduleRoomIDs = availableIDs
    }

    private func loadInitialWCALiveRoundIfNeeded() async {
        guard !isMainlandChinaCompetition, let deepLink = initialWCALiveResultDeepLink else { return }
        let fetched = await CompetitionService.fetchCompetitionWCALiveContent(
            for: competition,
            languageCode: appLanguage,
            targetRoundID: deepLink.roundID
        )
        guard !Task.isCancelled else { return }
        if let fetched {
            wcaLiveContentOverride = fetched
            presentInitialWCALiveResultIfAvailable()
        }
        didAttemptInitialWCALiveRoundLoad = true
    }

    private func loadPsychPreviewsIfNeeded() async {
        #if DEBUG
        guard !isRenderingFixture else { return }
        #endif
        guard detailContentTab == .competitors,
              isPsychModeAvailable,
              (!isMainlandChinaCompetition || selectedCompetitorsMode == .psych) else { return }

        let requestedCacheKey = currentPsychCacheKey
        if psychPreviewCache[requestedCacheKey] != nil {
            return
        }

        let requestedEventID = selectedCompetitorEventID
        let requestedSortBy = isMainlandChinaCompetition ? nil : wcaPsychSortColumn.rawValue
        let generation = loadingLifecycle.generation
        let identity = loadingLifecycle.identity
        let requestKey = "\(generation)|\(requestedCacheKey)"
        guard psychInFlightKeys.insert(requestKey).inserted else { return }
        loadingLifecycle.schedule(.psych(requestedCacheKey))
        defer {
            psychInFlightKeys.remove(requestKey)
            if loadingLifecycle.accepts(generation, identity: identity) {
                loadingLifecycle.finish(.psych(requestedCacheKey))
                if currentPsychCacheKey == requestedCacheKey { isLoadingPsych = false }
            }
        }
        isLoadingPsych = true
        let previews = await CompetitionService.fetchCompetitionPsychPreviews(
            for: competition,
            languageCode: appLanguage,
            eventID: requestedEventID.isEmpty ? nil : requestedEventID,
            sortBy: requestedSortBy
        )
        guard !Task.isCancelled, loadingLifecycle.accepts(generation, identity: identity) else { return }
        psychPreviewCache[requestedCacheKey] = previews
        if currentPsychCacheKey == requestedCacheKey {
            updateCompetitionDetailDerivedState()
            isLoadingPsych = false
        }
    }

    private func updateCompetitionDetailDerivedState() {
        let matrixEventIDs = CompetitionEventFilter.selectableCases
            .map(\.wcaEventID)
            .filter { competition.eventIDs.contains($0) }
        competitorMatrixEventIDsSnapshot = matrixEventIDs
        showsCompetitorNumbersSnapshot = detailContent.competitorPreviews.contains { $0.number != nil }
        showsCompetitorGenderSnapshot = detailContent.competitorPreviews.contains { $0.gender != nil }

        let query = competitorSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var filteredCompetitors = detailContent.competitorPreviews.filter { competitor in
            let matchesQuery = query.isEmpty
                || competitor.name.localizedCaseInsensitiveContains(query)
                || (competitor.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
            let matchesEvent = selectedCompetitorEventID.isEmpty
                || competitor.registeredEventIDs.contains(selectedCompetitorEventID)
            return matchesQuery && matchesEvent
        }
        if !isMainlandChinaCompetition {
            filteredCompetitors.sort { lhs, rhs in
                let comparison: ComparisonResult
                switch wcaCompetitorSortColumn {
                case .name:
                    comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                case .representing:
                    let lhsRegion = lhs.subtitle ?? ""
                    let rhsRegion = rhs.subtitle ?? ""
                    comparison = lhsRegion.localizedCaseInsensitiveCompare(rhsRegion)
                    if comparison == .orderedSame {
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                }
                if comparison == .orderedSame {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return isWCACompetitorSortAscending
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }
        }
        filteredCompetitorsSnapshot = filteredCompetitors

        if !isMainlandChinaCompetition {
            wcaCompetitorNameColumnWidth = measuredWCATableColumnWidth(
                values: [localizedCompetitionStringInView(key: "competitions.detail.competitors_column.name", languageCode: appLanguage)]
                    + filteredCompetitors.map(\.name),
                font: .systemFont(ofSize: 14, weight: .medium),
                minimum: 160,
                maximum: 260
            )
            wcaCompetitorRepresentingColumnWidth = measuredWCATableColumnWidth(
                values: [
                    appLocalizedString(
                        "competitions.detail.competitors_column.representing",
                        languageCode: appLanguage,
                        defaultValue: "Representing"
                    )
                ] + filteredCompetitors.compactMap(\.subtitle),
                font: .systemFont(ofSize: 14, weight: .regular),
                minimum: 140,
                maximum: .greatestFiniteMagnitude,
                leadingAccessoryWidth: 25
            )
        }

        let psychEventIDs = selectedCompetitorEventID.isEmpty
            ? matrixEventIDs
            : matrixEventIDs.filter { $0 == selectedCompetitorEventID }
        psychMatrixEventIDsSnapshot = psychEventIDs

        let psychPreviews = psychPreviewCache[currentPsychCacheKey] ?? []
        let filteredPsych = query.isEmpty
            ? psychPreviews
            : psychPreviews.filter { $0.name.localizedCaseInsensitiveContains(query) }
        filteredPsychCompetitorsSnapshot = filteredPsych

        if !isMainlandChinaCompetition {
            wcaPsychNameColumnWidth = measuredWCATableColumnWidth(
                values: [localizedCompetitionStringInView(key: "competitions.detail.competitors_column.name", languageCode: appLanguage)]
                    + filteredPsych.map(\.name),
                font: .systemFont(ofSize: 14, weight: .medium),
                minimum: 160,
                maximum: 260
            )
            wcaPsychRepresentingColumnWidth = measuredWCATableColumnWidth(
                values: [
                    appLocalizedString(
                        "competitions.detail.competitors_column.representing",
                        languageCode: appLanguage,
                        defaultValue: "Representing"
                    )
                ] + filteredPsych.compactMap(\.region),
                font: .systemFont(ofSize: 14, weight: .bold),
                minimum: 140,
                maximum: 220,
                leadingAccessoryWidth: 25
            )
        }

        guard selectedCompetitorEventID.isEmpty else {
            psychOverallRankByCompetitorIDSnapshot = [:]
            displayedPsychCompetitorsSnapshot = filteredPsych.sorted { lhs, rhs in
                let lhsItem = lhs.items.first
                let rhsItem = rhs.items.first
                let lhsRank = lhsItem?.rank ?? 0
                let rhsRank = rhsItem?.rank ?? 0
                let lhsIsRanked = lhsRank > 0
                let rhsIsRanked = rhsRank > 0
                if lhsIsRanked != rhsIsRanked {
                    return lhsIsRanked
                }
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return
        }

        let scored = filteredPsych.map { competitor in
            (
                competitor,
                competitor.items
                    .filter { psychEventIDs.contains($0.eventID) }
                    .map(\.rank)
                    .reduce(0, +)
            )
        }
        .filter { !$0.0.items.isEmpty && $0.1 > 0 }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
        }

        let rankByID = Dictionary(uniqueKeysWithValues: scored.enumerated().map { index, element in
            (element.0.id, index + 1)
        })
        psychOverallRankByCompetitorIDSnapshot = rankByID
        displayedPsychCompetitorsSnapshot = filteredPsych.sorted { lhs, rhs in
            let lhsRank = rankByID[lhs.id] ?? .max
            let rhsRank = rankByID[rhs.id] ?? .max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func measuredWCATableColumnWidth(
        values: [String],
        font: UIFont,
        minimum: CGFloat,
        maximum: CGFloat,
        leadingAccessoryWidth: CGFloat = 0
    ) -> CGFloat {
        let contentWidth = values.reduce(CGFloat.zero) { widest, value in
            let width = (value as NSString).size(withAttributes: [.font: font]).width
            return max(widest, ceil(width))
        }

        // Chakra's official medium table recipe uses 12 points on each side of a cell.
        return min(maximum, max(minimum, contentWidth + leadingAccessoryWidth + 24))
    }

    private func detailSectionStack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
    }

    private func detailSectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.background)
        )
    }

    private func detailLine(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .center)

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detailPrimaryButton(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.orange)
            )
    }

    private func detailSecondaryLink(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Color.orange)
    }

    private func localizedCompetitionDateRange(startingAt date: Date) -> String {
        let locale = appLocale(for: appLanguage)
        let fullFormat = localizedCompetitionStringInView(key: "competition.date.full_format", languageCode: appLanguage)
        return CompetitionDateRangeFormatterCache.string(from: date, locale: locale, format: fullFormat)
    }

    private func localizedCompetitionDateRange(for competition: CompetitionSummary) -> String {
        let locale = appLocale(for: appLanguage)
        let calendar = Calendar(identifier: .gregorian)

        let sameYear = calendar.component(.year, from: competition.startDate) == calendar.component(.year, from: competition.endDate)
        let sameMonth = sameYear && calendar.component(.month, from: competition.startDate) == calendar.component(.month, from: competition.endDate)
        let sameDay = sameMonth && calendar.component(.day, from: competition.startDate) == calendar.component(.day, from: competition.endDate)

        let fullFormat = localizedCompetitionStringInView(key: "competition.date.full_format", languageCode: appLanguage)
        if sameDay {
            return CompetitionDateRangeFormatterCache.string(from: competition.startDate, locale: locale, format: fullFormat)
        }
        if sameMonth {
            let monthDayFormat = localizedCompetitionStringInView(key: "competition.date.month_day_format", languageCode: appLanguage)
            let daySuffixFormat = localizedCompetitionStringInView(key: "competition.date.day_suffix_format", languageCode: appLanguage)
            let start = CompetitionDateRangeFormatterCache.string(from: competition.startDate, locale: locale, format: monthDayFormat)
            let end = CompetitionDateRangeFormatterCache.string(from: competition.endDate, locale: locale, format: daySuffixFormat)
            return "\(start) - \(end)"
        }
        let start = CompetitionDateRangeFormatterCache.string(from: competition.startDate, locale: locale, format: fullFormat)
        let end = CompetitionDateRangeFormatterCache.string(from: competition.endDate, locale: locale, format: fullFormat)
        return "\(start) - \(end)"
    }

    private func competitionAvailabilityStatus(for competition: CompetitionSummary) -> CompetitionAvailabilityStatus {
        if let localizedStatusOverride = competition.localizedStatusOverride {
            return localizedStatusOverride
        }

        let now = Date()
        let today = Calendar.current.startOfDay(for: now)

        if competition.endDate < today {
            return .ended
        }

        let startOfCompetition = Calendar.current.startOfDay(for: competition.startDate)
        let endOfCompetition = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: competition.endDate))
            ?? competition.endDate
        if now >= startOfCompetition && now < endOfCompetition {
            return .ongoing
        }

        if let open = competition.registrationOpen,
           let close = competition.registrationClose,
           open <= now && close >= now {
            return .registrationOpen
        }

        return .upcoming
    }

    private func daysUntil(_ date: Date?) -> Int {
        guard let date else { return 0 }
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return max(calendar.dateComponents([.day], from: now, to: target).day ?? 0, 0)
    }

    private func statusBadge(for status: CompetitionAvailabilityStatus, competition: CompetitionSummary, languageCode: String) -> some View {
        let badgeColor = statusColor(for: status, competition: competition)
        return Text(statusBadgeTitle(for: status, competition: competition, languageCode: languageCode))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(badgeColor.opacity(0.12), in: Capsule())
    }

    private func statusBadgeTitle(for status: CompetitionAvailabilityStatus, competition: CompetitionSummary, languageCode: String) -> String {
        switch status {
        case .registrationNotOpenYet:
            let days = daysUntil(competition.localizedRegistrationStartOverride)
            return String(
                format: localizedCompetitionStringInView(
                    key: "competitions.status.registration_not_open_yet_in_format",
                    languageCode: languageCode
                ),
                days
            )
        case .waitlist:
            if let waitlistStart = competition.localizedWaitlistStartOverride, Date() < waitlistStart {
                let days = daysUntil(waitlistStart)
                return String(
                    format: localizedCompetitionStringInView(
                        key: "competitions.status.waitlist_in_format",
                        languageCode: languageCode
                    ),
                    days
                )
            }
            return localizedCompetitionStringInView(
                key: "competitions.status.waitlist_open",
                languageCode: languageCode
            )
        default:
            return status.localizedTitle(languageCode: languageCode)
        }
    }

    private func statusColor(for status: CompetitionAvailabilityStatus, competition: CompetitionSummary) -> Color {
        if status == .waitlist {
            if let waitlistStart = competition.localizedWaitlistStartOverride, Date() < waitlistStart {
                return .teal
            }
            return .teal
        }

        switch status {
        case .upcoming:
            return .orange
        case .registrationNotOpenYet:
            return .yellow
        case .registrationOpen:
            return .green
        case .waitlist:
            return .mint
        case .ongoing:
            return .blue
        case .ended:
            return .secondary
        }
    }
}

private struct CubingDetailDocumentBlock: View {
    let block: CompetitionDetailTextBlock
    let fallbackTitle: String
    let areEventIconsReady: Bool

    @State private var isExpanded = false

    private var title: String? {
        guard let title = block.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }
        return title
    }

    private var isEntryFeeBlock: Bool {
        title?.localizedCaseInsensitiveContains("entry fee") == true
            || title?.contains("报名费") == true
            || title?.contains("報名費") == true
    }

    private var isContactBlock: Bool {
        guard let title else { return false }
        return title.localizedCaseInsensitiveContains("organizer")
            || title.localizedCaseInsensitiveContains("delegate")
            || title.contains("主办")
            || title.contains("主辦")
            || title.contains("代表")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title, isEntryFeeBlock || isContactBlock {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .selectableContent()

                    Spacer(minLength: 8)

                    if isEntryFeeBlock {
                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Text(isExpanded ? "less" : "more")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                }
            }

            if isContactBlock, let html = block.html {
                let contacts = CubingContactLink.links(from: html)
                if contacts.isEmpty {
                    richContent
                } else {
                    CubingContactLinksView(contacts: contacts)
                }
            } else {
                richContent
            }
        }
    }

    private var richContent: some View {
        CompetitionRichHTMLContent(
            html: block.html ?? block.body,
            tableRowLimit: isEntryFeeBlock && !isExpanded ? 2 : nil,
            areEventIconsReady: areEventIconsReady,
            baseURL: URL(string: "https://cubing.com"),
            leadingTitle: isEntryFeeBlock || isContactBlock ? nil : title
        )
    }
}

private struct CubingContactLink: Identifiable {
    let id: String
    let name: String
    let email: String

    var url: URL? {
        URL(string: "mailto:\(email)")
    }

    static func links(from html: String) -> [CubingContactLink] {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<a\b[^>]*href=['\"]mailto:([^'\"]+)['\"][^>]*>(.*?)</a>"#) else {
            return []
        }
        let nsHTML = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)).compactMap { match in
            guard match.numberOfRanges > 2 else { return nil }
            let email = simpleHTMLDecode(nsHTML.substring(with: match.range(at: 1))).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawName = nsHTML.substring(with: match.range(at: 2))
            let name = simpleHTMLDecode(
                rawName.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !email.isEmpty, !name.isEmpty else { return nil }
            return CubingContactLink(id: "\(email)-\(name)", name: name, email: email)
        }
    }
}

private struct CubingContactLinksView: View {
    let contacts: [CubingContactLink]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(contacts) { contact in
                if let url = contact.url {
                    Link(destination: url) {
                        contactLabel(contact.name)
                    }
                } else {
                    contactLabel(contact.name)
                }
            }
        }
    }

    private func contactLabel(_ name: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(name)
                .font(.system(size: 15, weight: .regular))
        }
        .foregroundStyle(.blue)
    }
}

private struct CompetitionTravelMapAnnotation: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
}

private struct CompetitionTravelMapCard: View {
    let locations: [CompetitionTravelMapLocation]
    let openMapsURL: URL?

    @State private var region: MKCoordinateRegion

    init(locations: [CompetitionTravelMapLocation], openMapsURL: URL?) {
        self.locations = locations
        self.openMapsURL = openMapsURL
        _region = State(initialValue: Self.initialRegion(for: locations))
    }

    private var annotationItems: [CompetitionTravelMapAnnotation] {
        locations.map { location in
            CompetitionTravelMapAnnotation(
                id: location.id,
                title: location.venue.isEmpty ? location.address : location.venue,
                subtitle: location.address,
                coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            )
        }
    }

    var body: some View {
        Map(coordinateRegion: $region, annotationItems: annotationItems) { item in
            MapAnnotation(coordinate: item.coordinate) {
                Image(systemName: "mappin")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.red)
                    .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            if let openMapsURL {
                Link(destination: openMapsURL) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 34, height: 34)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
    }

    private static func initialRegion(for locations: [CompetitionTravelMapLocation]) -> MKCoordinateRegion {
        let coordinates = locations.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }

        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }

        guard coordinates.count > 1 else {
            return MKCoordinateRegion(
                center: first,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            )
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLatitude = latitudes.min() ?? first.latitude
        let maxLatitude = latitudes.max() ?? first.latitude
        let minLongitude = longitudes.min() ?? first.longitude
        let maxLongitude = longitudes.max() ?? first.longitude

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLatitude - minLatitude) * 1.6, 0.012),
                longitudeDelta: max((maxLongitude - minLongitude) * 1.6, 0.012)
            )
        )
    }
}

private func simpleHTMLDecode(_ text: String) -> String {
    text
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&apos;", with: "'")
}

enum CompetitionRichTextParagraphLayout {
    static func addsSpacingAfterParagraph(
        in string: NSString,
        paragraphRange: NSRange,
        contentRange: NSRange
    ) -> Bool {
        let paragraphEnd = NSMaxRange(paragraphRange)
        guard paragraphEnd < NSMaxRange(contentRange) else { return false }

        let paragraphText = string.substring(with: paragraphRange)
        let isBlankParagraph = paragraphText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let nextCharacterIsAnotherBreak = string.character(at: paragraphEnd) == 0x0A
        return !isBlankParagraph && !nextCharacterIsAnotherBreak
    }
}

private struct CompetitionRichHTMLContent: View {
    let html: String
    let leadingTitle: String?
    @State private var parsedElements: [CompetitionRichHTMLElement]?
    private var elements: [CompetitionRichHTMLElement] { parsedElements ?? [] }
    let tableRowLimit: Int?
    let areEventIconsReady: Bool
    let languageCode: String
    let baseURL: URL?
    let addressFallback: String?
    let onAddScheduleToCalendar: (() -> Void)?

    init(
        html: String,
        tableRowLimit: Int? = nil,
        areEventIconsReady: Bool = false,
        languageCode: String = "en",
        baseURL: URL? = nil,
        addressFallback: String? = nil,
        onAddScheduleToCalendar: (() -> Void)? = nil,
        leadingTitle: String? = nil
    ) {
        self.html = html
        self.leadingTitle = leadingTitle
        self.tableRowLimit = tableRowLimit
        self.areEventIconsReady = areEventIconsReady
        self.languageCode = languageCode
        self.baseURL = baseURL
        self.addressFallback = addressFallback
        self.onAddScheduleToCalendar = onAddScheduleToCalendar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(renderBlocks) { block in
                if block.isSelectableTextGroup {
                    let document = selectableDocument(for: block.range)
                    SelectableAttributedContent(
                        attributedText: document.attributedText,
                        inlineControls: document.inlineControls,
                        onOpenURL: { url in
                            guard url.scheme == "cubeflow",
                                  url.host == "add-competition-schedule" else { return false }
                            onAddScheduleToCalendar?()
                            return true
                        }
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(
                            .top,
                            elements[block.range.lowerBound].topSpacing(
                                isFirst: block.range.lowerBound == 0
                            )
                        )
                        .padding(.bottom, elements[block.range.upperBound - 1].bottomSpacing)
                } else {
                    let index = block.range.lowerBound
                    let element = elements[index]
                    richElement(element)
                        .padding(.top, element.topSpacing(isFirst: index == 0))
                        .padding(.bottom, element.bottomSpacing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(parsedElements == nil ? "competition-document-loading" : "competition-rich-document")
        .task(id: CompetitionRichDocumentStore.Key(html: html, baseURL: baseURL, leadingTitle: leadingTitle)) {
            let parsed = await CompetitionRichDocumentStore.shared.elements(html: html, baseURL: baseURL)
            guard !Task.isCancelled else { return }
            var document = parsed
            if let title = leadingTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                document.insert(CompetitionRichHTMLElement(kind: .heading(title, 5)), at: 0)
            }
            parsedElements = document
        }
    }

    private var renderBlocks: [CompetitionRichHTMLRenderBlock] {
        var blocks: [CompetitionRichHTMLRenderBlock] = []
        var index = 0
        while index < elements.count {
            if elements[index].isSelectableDocumentElement {
                let start = index
                repeat { index += 1 } while index < elements.count
                    && elements[index].isSelectableDocumentElement
                blocks.append(
                    CompetitionRichHTMLRenderBlock(
                        range: start..<index,
                        isSelectableTextGroup: true
                    )
                )
            } else {
                blocks.append(
                    CompetitionRichHTMLRenderBlock(
                        range: index..<(index + 1),
                        isSelectableTextGroup: false
                    )
                )
                index += 1
            }
        }
        return blocks
    }

    private func selectableDocument(for range: Range<Int>) -> CompetitionSelectableDocument {
        let result = NSMutableAttributedString()
        var inlineControls: [SelectableInlineControl] = []
        for index in range {
            if result.length > 0 {
                result.append(NSAttributedString(string: "\n"))
            }

            let start = result.length
            let usesOwnParagraphLayout = appendSelectable(
                element: elements[index],
                elementIndex: index,
                to: result,
                inlineControls: &inlineControls
            )
            if !usesOwnParagraphLayout {
                let naturalSpacing: CGFloat
                if index < range.upperBound - 1 {
                    naturalSpacing = elements[index].bottomSpacing
                        + elements[index + 1].topSpacing(isFirst: false)
                } else {
                    naturalSpacing = 0
                }

                if case .linkedText = elements[index].kind {
                    applyLinkedTextParagraphLayout(
                        to: result,
                        range: NSRange(location: start, length: result.length - start),
                        trailingSpacing: naturalSpacing
                    )
                    continue
                }

                let paragraph = NSMutableParagraphStyle()
                if case .eventLine = elements[index].kind {
                    paragraph.lineSpacing = 2
                } else {
                    paragraph.lineSpacing = 3
                }
                if naturalSpacing > 0 {
                    if case .eventLine = elements[index].kind {
                        paragraph.paragraphSpacing = max(naturalSpacing, 10)
                    } else {
                        paragraph.paragraphSpacing = naturalSpacing
                    }
                }
                result.addAttribute(
                    .paragraphStyle,
                    value: paragraph,
                    range: NSRange(location: start, length: result.length - start)
                )
            }
        }
        return CompetitionSelectableDocument(
            attributedText: result,
            inlineControls: inlineControls
        )
    }

    private func applyLinkedTextParagraphLayout(
        to result: NSMutableAttributedString,
        range: NSRange,
        trailingSpacing: CGFloat
    ) {
        guard range.length > 0 else { return }
        let string = result.string as NSString
        let rangeEnd = NSMaxRange(range)
        var location = range.location

        while location < rangeEnd {
            let discovered = string.paragraphRange(for: NSRange(location: location, length: 0))
            let paragraphRange = NSIntersectionRange(discovered, range)
            guard paragraphRange.length > 0 else { break }

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            let paragraphEnd = NSMaxRange(paragraphRange)
            if paragraphEnd >= rangeEnd {
                paragraph.paragraphSpacing = trailingSpacing
            } else {
                // A single semantic line break gets a small native paragraph
                // separation. Existing blank lines already provide their own
                // vertical space and must not receive another spacing layer.
                if CompetitionRichTextParagraphLayout.addsSpacingAfterParagraph(
                    in: string,
                    paragraphRange: paragraphRange,
                    contentRange: range
                ) {
                    paragraph.paragraphSpacing = 4
                }
            }

            result.addAttribute(.paragraphStyle, value: paragraph, range: paragraphRange)
            location = paragraphEnd
        }
    }

    @discardableResult
    private func appendSelectable(
        element: CompetitionRichHTMLElement,
        elementIndex: Int,
        to result: NSMutableAttributedString,
        inlineControls: inout [SelectableInlineControl]
    ) -> Bool {
        switch element.kind {
        case .heading(let text, let level):
            result.append(
                NSAttributedString(
                    string: text,
                    attributes: textAttributes(font: richHeadingUIFont(level: level), color: .label)
                )
            )
        case .paragraph(let text):
            result.append(
                NSAttributedString(
                    string: text,
                    attributes: textAttributes(font: richBodyUIFont(), color: .label)
                )
            )
        case .linkedText(let runs):
            var currentText = ""
            for (runIndex, run) in runs.enumerated() {
                var text = resolvedRunText(run.text, after: currentText)
                let nextRunHasSameLink = runs.indices.contains(runIndex + 1)
                    && runs[runIndex + 1].url == run.url
                if run.showsExternalLinkIndicator && !nextRunHasSameLink {
                    text += " ↗"
                }
                guard !text.isEmpty else { continue }

                var font = richBodyUIFont(weight: run.isBold ? .bold : .regular)
                if run.isItalic,
                   let italicDescriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
                    font = UIFont(descriptor: italicDescriptor, size: font.pointSize)
                }
                var attributes = textAttributes(
                    font: font,
                    color: run.url == nil ? run.color.uiColor : .tintColor
                )
                if let url = run.url {
                    attributes[.link] = url
                }
                result.append(NSAttributedString(string: text, attributes: attributes))
                currentText += text
            }
        case .info(let text):
            result.append(
                NSAttributedString(
                    string: text,
                    attributes: textAttributes(font: richBodyUIFont(), color: .systemBlue)
                )
            )
        case .definitionList(let rows):
            appendDefinitionList(
                rows,
                elementIndex: elementIndex,
                to: result,
                inlineControls: &inlineControls
            )
            return true
        case .list(let items):
            appendSelectableList(
                items,
                elementIndex: elementIndex,
                to: result,
                inlineControls: &inlineControls
            )
            return true
        case .eventLine(let eventID, let text):
            if areEventIconsReady,
               let glyph = CompetitionEventIconFont.glyph(for: eventID, title: text) {
                appendInlineEventIcon(
                    glyph: glyph,
                    eventID: eventID,
                    title: localizedEventTitle(eventID),
                    id: "element-\(elementIndex)-event",
                    alignment: .paragraphCenter,
                    to: result,
                    inlineControls: &inlineControls
                )
                result.append(NSAttributedString(string: " "))
            }
            result.append(NSAttributedString(string: text, attributes: [
                .font: richBodyUIFont(),
                .foregroundColor: UIColor.label
            ]))
        default:
            break
        }
        return false
    }

    private func richHeadingUIFont(level: Int) -> UIFont {
        let specification: (CGFloat, UIFont.Weight, UIFont.TextStyle) = {
            switch level {
            case 1: return (30, .bold, .largeTitle)
            case 2: return (26, .bold, .title1)
            case 3: return (22, .semibold, .title2)
            case 4: return (18, .semibold, .headline)
            case 5: return (17, .semibold, .headline)
            default: return (15, .semibold, .body)
            }
        }()
        return UIFontMetrics(forTextStyle: specification.2).scaledFont(
            for: UIFont.systemFont(ofSize: specification.0, weight: specification.1)
        )
    }

    private func richBodyUIFont(weight: UIFont.Weight = .regular) -> UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.systemFont(ofSize: 15, weight: weight)
        )
    }

    private func textAttributes(font: UIFont, color: UIColor) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: color
        ]
    }

    private func resolvedRunText(_ nextText: String, after currentText: String) -> String {
        guard !currentText.isEmpty,
              !nextText.isEmpty,
              !nextText.hasPrefix(" "),
              nextText.first.map({ !$0.isNewline }) == true,
              !currentText.last.map({ $0.isWhitespace || $0.isNewline })! else {
            return nextText
        }
        let noSpacePrefixes = [".", ",", ";", ":", "!", "?", ")", "]", "}", "。", "，", "；", "：", "！", "？", "、"]
        let previous = String(currentText.suffix(1))
        guard !noSpacePrefixes.contains(where: nextText.hasPrefix),
              !["(", "[", "{"].contains(previous) else {
            return nextText
        }
        return " " + nextText
    }

    @ViewBuilder
    private func richElement(_ element: CompetitionRichHTMLElement) -> some View {
        switch element.kind {
        case .heading(let text, let level):
            Text(text)
                .font(richHeadingFont(level: level))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph(let text):
            Text(text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .linkedText(let runs):
            LinkedTextFlow(runs: runs)
        case .list(let items):
            richList(items: items)
        case .definitionList(let rows):
            if rows.allSatisfy({ !$0.prefersExpandedLayout }) {
                selectableDefinitionList(rows)
            } else {
                richDefinitionList(rows)
            }
        case .eventLine(let eventID, let text):
            HStack(alignment: .center, spacing: 8) {
                if areEventIconsReady, let glyph = CompetitionEventIconFont.glyph(for: eventID, title: text) {
                    richEventIcon(glyph, eventID: eventID, size: 19)
                }

                Text(text)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .info(let text):
            Text(text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.blue)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .table(let table):
            richTable(table)
        case .image(let source):
            CompetitionRichHTMLImage(source: source, baseURL: baseURL)
        case .separator:
            Divider()
        }
    }

    private func richHeadingFont(level: Int) -> Font {
        switch level {
        case 1: return .system(size: 30, weight: .bold)
        case 2: return .system(size: 26, weight: .bold)
        case 3: return .system(size: 22, weight: .semibold)
        case 4: return .system(size: 18, weight: .semibold)
        case 5: return .system(size: 17, weight: .semibold)
        default: return .system(size: 15, weight: .semibold)
        }
    }

    private func appendDefinitionList(
        _ rows: [CompetitionRichHTMLDefinitionRow],
        elementIndex: Int,
        to result: NSMutableAttributedString,
        inlineControls: inout [SelectableInlineControl]
    ) {
        let compactTermFont = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.systemFont(ofSize: 14, weight: .semibold)
        )
        let verticalTermFont = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.systemFont(ofSize: 15, weight: .semibold)
        )
        let valueColumnOffset = definitionValueColumnOffset(rows: rows, font: compactTermFont)

        for (rowIndex, row) in rows.enumerated() {
            if rowIndex > 0 { result.append(NSAttributedString(string: "\n")) }
            let rowStart = result.length

            if row.prefersExpandedLayout || row.prefersVerticalFieldLayout {
                if row.termSymbol == "printer" {
                    appendInlineSystemIcon(
                        name: "printer.fill",
                        label: "Print",
                        id: "element-\(elementIndex)-row-\(rowIndex)-term",
                        color: row.isTermSecondary ? .secondaryLabel : .label,
                        to: result,
                        inlineControls: &inlineControls
                    )
                } else {
                    result.append(NSAttributedString(string: row.term, attributes: [
                        .font: row.prefersVerticalFieldLayout ? verticalTermFont : compactTermFont,
                        .foregroundColor: row.isTermSecondary ? UIColor.secondaryLabel : UIColor.label
                    ]))
                }

                let termParagraph = NSMutableParagraphStyle()
                let titleRange = NSRange(location: rowStart, length: result.length - rowStart)
                termParagraph.paragraphSpacing = row.eventIDs.isEmpty ? 4 : 0
                result.addAttribute(
                    .paragraphStyle,
                    value: termParagraph,
                    range: NSRange(location: rowStart, length: result.length - rowStart)
                )
                result.append(NSAttributedString(string: "\n"))

                let valueStart = result.length
                appendDefinitionValue(
                    row,
                    elementIndex: elementIndex,
                    rowIndex: rowIndex,
                    titleRange: titleRange,
                    to: result,
                    font: richBodyUIFont(),
                    inlineControls: &inlineControls
                )
                if row.hasCalendarLink, onAddScheduleToCalendar != nil {
                    result.append(NSAttributedString(string: " "))
                    appendInlineSystemIcon(
                        name: "calendar.badge.plus",
                        label: "Add schedule to Calendar",
                        id: "element-\(elementIndex)-row-\(rowIndex)-calendar",
                        color: .systemBlue,
                        action: onAddScheduleToCalendar,
                        to: result,
                        inlineControls: &inlineControls
                    )
                }

                let valueParagraph = NSMutableParagraphStyle()
                valueParagraph.lineSpacing = 3
                valueParagraph.paragraphSpacing = 12
                result.addAttribute(
                    .paragraphStyle,
                    value: valueParagraph,
                    range: NSRange(location: valueStart, length: result.length - valueStart)
                )
                continue
            }

            if row.termSymbol == "printer" {
                appendInlineSystemIcon(
                    name: "printer.fill",
                    label: "Print",
                    id: "element-\(elementIndex)-row-\(rowIndex)-term",
                    color: row.isTermSecondary ? .secondaryLabel : .label,
                    to: result,
                    inlineControls: &inlineControls
                )
            } else {
                result.append(NSAttributedString(string: row.term, attributes: [
                    .font: compactTermFont,
                    .foregroundColor: row.isTermSecondary ? UIColor.secondaryLabel : UIColor.label
                ]))
            }
            result.append(NSAttributedString(string: "\t"))
            appendDefinitionValue(
                row,
                elementIndex: elementIndex,
                rowIndex: rowIndex,
                to: result,
                font: richBodyUIFont(),
                inlineControls: &inlineControls
            )

            if row.hasCalendarLink, onAddScheduleToCalendar != nil {
                result.append(NSAttributedString(string: " "))
                appendInlineSystemIcon(
                    name: "calendar.badge.plus",
                    label: "Add schedule to Calendar",
                    id: "element-\(elementIndex)-row-\(rowIndex)-calendar",
                    color: .systemBlue,
                    action: onAddScheduleToCalendar,
                    to: result,
                    inlineControls: &inlineControls
                )
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: valueColumnOffset)]
            paragraph.defaultTabInterval = valueColumnOffset
            paragraph.headIndent = valueColumnOffset
            paragraph.firstLineHeadIndent = 0
            paragraph.lineSpacing = 3
            paragraph.paragraphSpacing = 10
            result.addAttribute(
                .paragraphStyle,
                value: paragraph,
                range: NSRange(location: rowStart, length: result.length - rowStart)
            )
        }
    }

    private func definitionValueColumnOffset(
        rows: [CompetitionRichHTMLDefinitionRow],
        font: UIFont
    ) -> CGFloat {
        let longestTermWidth = rows
            .filter { !$0.prefersVerticalFieldLayout && !$0.prefersExpandedLayout }
            .map { row -> CGFloat in
            if row.termSymbol != nil { return 18 }
            return ceil((row.term as NSString).size(withAttributes: [.font: font]).width)
        }.max() ?? 0
        return max(longestTermWidth + 14, 108)
    }

    private func appendSelectableList(
        _ items: [CompetitionRichHTMLListItem],
        elementIndex: Int,
        to result: NSMutableAttributedString,
        inlineControls: inout [SelectableInlineControl]
    ) {
        for (itemIndex, item) in items.enumerated() {
            if itemIndex > 0 { result.append(NSAttributedString(string: "\n")) }
            let start = result.length
            result.append(NSAttributedString(string: item.marker + "\t", attributes: [
                .font: richBodyUIFont(),
                .foregroundColor: UIColor.label
            ]))
            if let eventID = item.eventID,
               areEventIconsReady,
               let glyph = CompetitionEventIconFont.glyph(for: eventID) {
                appendInlineEventIcon(
                    glyph: glyph,
                    eventID: eventID,
                    title: localizedEventTitle(eventID),
                    id: "element-\(elementIndex)-item-\(itemIndex)-event",
                    alignment: .glyphCenter,
                    to: result,
                    inlineControls: &inlineControls
                )
                result.append(NSAttributedString(string: " "))
            }
            appendTextRuns(item.runs, to: result)

            let depthOffset = CGFloat(item.depth) * 20
            let contentOffset = depthOffset + item.markerWidth + 8
            let paragraph = NSMutableParagraphStyle()
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: contentOffset)]
            paragraph.firstLineHeadIndent = depthOffset
            paragraph.headIndent = contentOffset
            paragraph.lineSpacing = 3
            paragraph.paragraphSpacing = 6
            result.addAttribute(
                .paragraphStyle,
                value: paragraph,
                range: NSRange(location: start, length: result.length - start)
            )
        }
    }

    private func appendTextRuns(
        _ runs: [CompetitionRichHTMLTextRun],
        to result: NSMutableAttributedString
    ) {
        var currentText = ""
        for (index, run) in runs.enumerated() {
            let semanticText = run.text.replacingOccurrences(
                of: #"\[\[event-icon:[A-Za-z0-9_]+\]\]"#,
                with: "",
                options: .regularExpression
            )
            var text = resolvedRunText(semanticText, after: currentText)
            let nextRunHasSameLink = runs.indices.contains(index + 1)
                && runs[index + 1].url == run.url
            if run.showsExternalLinkIndicator && !nextRunHasSameLink {
                text += " ↗"
            }
            guard !text.isEmpty else { continue }

            var font = richBodyUIFont(weight: run.isBold ? .bold : .regular)
            if run.isItalic,
               let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
                font = UIFont(descriptor: descriptor, size: font.pointSize)
            }
            var attributes = textAttributes(
                font: font,
                color: run.url == nil ? run.color.uiColor : .tintColor
            )
            if let url = run.url { attributes[.link] = url }
            result.append(NSAttributedString(string: text, attributes: attributes))
            currentText += text
        }
    }

    private func appendInlineEventIcon(
        glyph: String,
        eventID: String,
        title: String,
        id: String,
        alignment: SelectableInlineControl.Alignment,
        to result: NSMutableAttributedString,
        inlineControls: inout [SelectableInlineControl]
    ) {
        // Each icon remains one atomic TextKit item. The zero-width break after
        // the slot lets the layout manager wrap only between complete icons.
        let placeholderFont = UIFont.systemFont(ofSize: 38)
        result.append(NSAttributedString(string: "\u{2003}", attributes: [
            .font: placeholderFont,
            .foregroundColor: UIColor.clear,
            .selectableInlineControlID: id
        ]))
        result.append(NSAttributedString(string: "\u{200B}", attributes: [
            .font: placeholderFont,
            .foregroundColor: UIColor.clear
        ]))
        inlineControls.append(
            SelectableInlineControl(
                id: id,
                content: .glyph(
                    glyph,
                    fontName: CompetitionEventIconFont.fontName,
                    fontSize: 24
                ),
                accessibilityLabel: title,
                color: .label,
                popoverText: title,
                alignment: alignment,
                minimumHitSize: CGSize(width: 38, height: 40)
            )
        )
    }

    private func eventIconRowOriginCorrection(for row: CompetitionRichHTMLDefinitionRow) -> CGFloat {
        guard let firstGlyph = row.eventIDs.compactMap({ CompetitionEventIconFont.glyph(for: $0) }).first else {
            return 0
        }
        return CompetitionEventIconFont.rowOriginCorrection(
            firstGlyph: firstGlyph,
            cellWidth: 38,
            pointSize: 24,
            titleInkLeading: CompetitionEventIconFont.textInkBounds(NSAttributedString(
                string: row.term,
                attributes: [.font: UIFont.systemFont(ofSize: row.prefersVerticalFieldLayout ? 15 : 14, weight: .semibold)]
            )).minX
        )
    }

    private func appendInlineSystemIcon(
        name: String,
        label: String,
        id: String,
        color: UIColor,
        action: (() -> Void)? = nil,
        to result: NSMutableAttributedString,
        inlineControls: inout [SelectableInlineControl]
    ) {
        result.append(NSAttributedString(string: "\u{2003}", attributes: [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor.clear,
            .selectableInlineControlID: id
        ]))
        inlineControls.append(
            SelectableInlineControl(
                id: id,
                content: .systemImage(name, pointSize: 15, weight: .semibold),
                accessibilityLabel: label,
                color: color,
                action: action
            )
        )
    }

    private func selectableDefinitionList(_ rows: [CompetitionRichHTMLDefinitionRow]) -> some View {
        let document = standaloneDefinitionDocument(rows)
        return SelectableAttributedContent(
            attributedText: document.attributedText,
            inlineControls: document.inlineControls,
            onOpenURL: { url in
                guard url.scheme == "cubeflow",
                      url.host == "add-competition-schedule" else { return false }
                onAddScheduleToCalendar?()
                return true
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func standaloneDefinitionDocument(
        _ rows: [CompetitionRichHTMLDefinitionRow]
    ) -> CompetitionSelectableDocument {
        let result = NSMutableAttributedString()
        var controls: [SelectableInlineControl] = []
        appendDefinitionList(
            rows,
            elementIndex: 0,
            to: result,
            inlineControls: &controls
        )
        return CompetitionSelectableDocument(attributedText: result, inlineControls: controls)
    }

    private func appendDefinitionValue(
        _ row: CompetitionRichHTMLDefinitionRow,
        elementIndex: Int,
        rowIndex: Int,
        titleRange: NSRange? = nil,
        to result: NSMutableAttributedString,
        font: UIFont,
        inlineControls: inout [SelectableInlineControl]
    ) {
        let valueStart = result.length
        let hasVisibleValueText = !row.valueText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let containsOnlyEventIcons = !row.eventIDs.isEmpty && !hasVisibleValueText
        let runs = CompetitionRichHTMLElement.textRuns(from: row.valueHTML)
        if !containsOnlyEventIcons {
            appendTextRuns(runs, to: result)
        }

        if runs.isEmpty, hasVisibleValueText {
            result.append(NSAttributedString(string: row.valueText, attributes: [
                .font: font,
                .foregroundColor: UIColor.label
            ]))
        }

        if !row.eventIDs.isEmpty {
            if result.length > valueStart, hasVisibleValueText {
                result.append(NSAttributedString(string: " "))
            }
            let firstVisibleGlyph = row.eventIDs.compactMap { CompetitionEventIconFont.glyph(for: $0) }.first
            for (index, eventID) in row.eventIDs.enumerated() {
                guard let glyph = CompetitionEventIconFont.glyph(for: eventID) else { continue }
                let alignment: SelectableInlineControl.Alignment
                if containsOnlyEventIcons, let firstVisibleGlyph {
                    alignment = .glyphRow(firstGlyph: firstVisibleGlyph, titleRange: titleRange)
                } else {
                    alignment = .glyphCenter
                }
                appendInlineEventIcon(
                    glyph: glyph,
                    eventID: eventID,
                    title: localizedEventTitle(eventID),
                    id: "element-\(elementIndex)-row-\(rowIndex)-event-\(index)",
                    alignment: alignment,
                    to: result,
                    inlineControls: &inlineControls
                )
            }
        }
    }

    private func richDefinitionList(_ rows: [CompetitionRichHTMLDefinitionRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                if row.prefersExpandedLayout || row.prefersVerticalFieldLayout {
                    VStack(
                        alignment: .leading,
                        spacing: row.eventIDs.isEmpty ? 5 : 1
                    ) {
                        richDefinitionTerm(row)
                        richDefinitionValue(row)
                    }
                    .padding(.vertical, 8)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        richDefinitionTerm(row)
                            .frame(width: 108, alignment: .leading)

                        richDefinitionValue(row)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }

    @ViewBuilder
    private func richDefinitionTerm(_ row: CompetitionRichHTMLDefinitionRow) -> some View {
        if row.termSymbol == "printer" {
            Image(systemName: "printer.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(row.isTermSecondary ? .secondary : .primary)
                .accessibilityLabel("Print")
        } else if !row.term.isEmpty {
            Text(row.term)
                .font(.system(size: row.prefersVerticalFieldLayout ? 15 : 14, weight: .semibold))
                .foregroundStyle(
                    row.isTermSecondary ? Color.secondary : Color.primary
                )
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func richDefinitionValue(_ row: CompetitionRichHTMLDefinitionRow) -> some View {
        if row.isAddress {
            richAddressValue(row)
        } else if !row.eventIDs.isEmpty,
           row.valueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Group {
                if #available(iOS 16.0, *) {
                    CompetitionWrappingLayout(horizontalSpacing: 8, verticalSpacing: 10) {
                        ForEach(row.eventIDs, id: \.self) { eventID in
                            if areEventIconsReady, let glyph = CompetitionEventIconFont.glyph(for: eventID) {
                                CompetitionEventIconPopoverButton(
                                    glyph: glyph,
                                    eventTitle: localizedEventTitle(eventID),
                                    size: 24,
                                    centersInkInCell: true
                                )
                                .frame(width: 38, height: 40)
                            }
                        }
                    }
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 38, maximum: 38), spacing: 8)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(row.eventIDs, id: \.self) { eventID in
                            if areEventIconsReady, let glyph = CompetitionEventIconFont.glyph(for: eventID) {
                                CompetitionEventIconPopoverButton(
                                    glyph: glyph,
                                    eventTitle: localizedEventTitle(eventID),
                                    size: 24,
                                    centersInkInCell: true
                                )
                                .frame(width: 38, height: 40)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: eventIconRowOriginCorrection(for: row))
            .frame(minHeight: 40)
        } else {
            if row.hasCalendarLink, let onAddScheduleToCalendar {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CompetitionRichHTMLContent(
                        html: row.valueHTML,
                        tableRowLimit: tableRowLimit,
                        areEventIconsReady: areEventIconsReady,
                        languageCode: languageCode,
                        baseURL: baseURL,
                        addressFallback: addressFallback,
                        onAddScheduleToCalendar: onAddScheduleToCalendar
                    )
                    .fixedSize(horizontal: true, vertical: false)

                    Button(action: onAddScheduleToCalendar) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Add schedule to Calendar")

                    Spacer(minLength: 0)
                }
            } else {
                CompetitionRichHTMLContent(
                    html: row.valueHTML,
                    tableRowLimit: tableRowLimit,
                    areEventIconsReady: areEventIconsReady,
                    languageCode: languageCode,
                    baseURL: baseURL,
                    addressFallback: addressFallback,
                    onAddScheduleToCalendar: onAddScheduleToCalendar
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func richAddressValue(_ row: CompetitionRichHTMLDefinitionRow) -> some View {
        let runs = CompetitionRichHTMLElement.textRuns(from: row.valueHTML)
        if let destination = runs.compactMap(\.url).first {
            let sourceText = runs.map(\.text).joined(separator: " ")
            let parsedText = CompetitionService.addressDisplayText(in: sourceText)
            let fallbackText = CompetitionService.addressDisplayText(in: addressFallback ?? "")
            let displayText = !parsedText.isEmpty
                ? parsedText
                : (!fallbackText.isEmpty
                    ? fallbackText
                    : appLocalizedString(
                        "competitions.detail.open_maps",
                        languageCode: languageCode,
                        defaultValue: "Open in Maps"
                    ))

            let attributedAddress = linkedAddressText(
                displayText + " ↗",
                destination: destination
            )
            Text(attributedAddress)
                .font(.system(size: 15, weight: .regular))
                .tint(.blue)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .selectableContent()
        } else {
            CompetitionRichHTMLContent(
                html: row.valueHTML,
                tableRowLimit: tableRowLimit,
                areEventIconsReady: areEventIconsReady,
                languageCode: languageCode,
                baseURL: baseURL,
                addressFallback: addressFallback,
                onAddScheduleToCalendar: onAddScheduleToCalendar
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func linkedAddressText(_ text: String, destination: URL) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.link = destination
        attributed.foregroundColor = .blue
        return attributed
    }

    private func richList(items: [CompetitionRichHTMLListItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(item.marker)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: item.markerWidth, alignment: .trailing)
                        .padding(.top, 1)
                        .selectableContent()

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .center, spacing: 7) {
                            if let eventID = item.eventID,
                               areEventIconsReady,
                               let glyph = CompetitionEventIconFont.glyph(for: eventID) {
                                richEventIcon(glyph, eventID: eventID, size: 19)
                            }

                            if !item.runs.isEmpty {
                                LinkedTextFlow(runs: item.runs)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .selectableContent()
                            }
                        }

                        ForEach(Array(item.imageSources.enumerated()), id: \.offset) { _, source in
                            CompetitionRichHTMLImage(source: source, baseURL: baseURL)
                        }
                    }
                }
                .padding(.leading, CGFloat(item.depth) * 20)
            }
        }
        .padding(.vertical, 1)
    }

    private func richEventIcon(_ glyph: String, eventID: String, size: CGFloat) -> some View {
        CompetitionEventIconPopoverButton(
            glyph: glyph,
            eventTitle: localizedEventTitle(eventID),
            size: size
        )
        .frame(width: 30, alignment: .center)
        .frame(minHeight: 32)
    }

    private func localizedEventTitle(_ eventID: String) -> String {
        CompetitionEventFilter.selectableCases
            .first(where: { $0.wcaEventID == eventID })?
            .localizedTitle(languageCode: languageCode)
            ?? competitionLiveShortEventTitle(for: eventID, languageCode: languageCode)
    }

    private func richTable(_ table: CompetitionRichHTMLTable) -> some View {
        let rows = tableRowLimit.map { Array(table.rows.prefix($0)) } ?? table.rows
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.system(size: 14, weight: rowIndex == 0 ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .selectableContent()
                    }
                }
                .background(rowIndex == 0 ? Color.secondary.opacity(0.08) : Color.clear)

                if rowIndex < rows.count - 1 {
                    Divider()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.7)
        }
    }
}

enum CompetitionContentImageSourceResolver {
    static func normalized(_ source: String) -> String {
        source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
    }

    static func remoteURL(from source: String, baseURL: URL? = nil) -> URL? {
        let normalizedSource = normalized(source)
        let absoluteSource: String
        if normalizedSource.hasPrefix("//") {
            absoluteSource = "https:\(normalizedSource)"
        } else if let baseURL,
                  let resolvedURL = URL(string: normalizedSource, relativeTo: baseURL)?.absoluteURL {
            return resolvedURL
        } else if normalizedSource.hasPrefix("/") {
            absoluteSource = "https://cubing.com\(normalizedSource)"
        } else {
            absoluteSource = normalizedSource
        }

        if let url = URL(string: absoluteSource) { return url }
        guard let encoded = absoluteSource.addingPercentEncoding(
            withAllowedCharacters: .urlFragmentAllowed
        ) else { return nil }
        return URL(string: encoded)
    }
}

private struct CompetitionRichHTMLImage: View {
    let source: String
    let baseURL: URL?

    @State private var remoteImage: UIImage?
    @State private var loadedRemoteImageURL: URL?
    @State private var imageLoadFailed = false

    var body: some View {
        Group {
            if let image = dataImage {
                renderedImage(Image(uiImage: image))
                    .contentImageActions(source: .image(image), presentation: .white)
            } else if let url = resolvedURL {
                Group {
                    if let remoteImage, loadedRemoteImageURL == url {
                        renderedImage(Image(uiImage: remoteImage))
                            .contentImageActions(source: .image(remoteImage), presentation: .white)
                    } else if imageLoadFailed {
                        imagePlaceholder(systemImage: "photo.badge.exclamationmark")
                    } else {
                        imageLoadingPlaceholder
                    }
                }
                .task(id: url) {
                    await loadRemoteImage(from: url)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func renderedImage(_ image: Image) -> some View {
        image
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Color.white)
    }

    private var dataImage: UIImage? {
        let normalizedSource = CompetitionContentImageSourceResolver.normalized(source)
        guard normalizedSource.lowercased().hasPrefix("data:image"),
              let commaIndex = normalizedSource.firstIndex(of: ",") else { return nil }
        let payload = String(normalizedSource[normalizedSource.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else {
            return nil
        }
        return UIImage(data: data)
    }

    private var resolvedURL: URL? {
        CompetitionContentImageSourceResolver.remoteURL(from: source, baseURL: baseURL)
    }

    @MainActor
    private func loadRemoteImage(from url: URL) async {
        remoteImage = nil
        loadedRemoteImageURL = nil
        imageLoadFailed = false
        do {
            let image = try await ContentImageLoader.shared.image(for: url)
            guard !Task.isCancelled else { return }
            remoteImage = image
            loadedRemoteImageURL = url
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            imageLoadFailed = true
        }
    }

    private func imagePlaceholder(systemImage: String) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.secondary.opacity(0.08))
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 120)
    }

    private var imageLoadingPlaceholder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.secondary.opacity(0.08))
            .overlay {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(height: 120)
    }
}

nonisolated struct CompetitionRichHTMLElement: Sendable {
    enum Kind {
        case heading(String, Int)
        case paragraph(String)
        case linkedText([CompetitionRichHTMLTextRun])
        case list([CompetitionRichHTMLListItem])
        case definitionList([CompetitionRichHTMLDefinitionRow])
        case eventLine(eventID: String, text: String)
        case info(String)
        case table(CompetitionRichHTMLTable)
        case image(String)
        case separator
    }

    let kind: Kind

    var isSelectableDocumentElement: Bool {
        switch kind {
        case .heading, .paragraph, .linkedText, .info:
            return true
        case .eventLine:
            return true
        case .list(let items):
            return items.allSatisfy { $0.imageSources.isEmpty }
        case .definitionList(let rows):
            // WCA General Info is a definition list whose values can contain an
            // entire rich document. Keep those block elements out of the single
            // TextKit document so images and semantic blocks remain in order.
            return !rows.isEmpty && rows.allSatisfy { !$0.prefersExpandedLayout }
        default:
            return false
        }
    }

    static func parse(_ html: String) -> [CompetitionRichHTMLElement] {
        let cleanedHTML = normalizeCubingIconHTML(html)
            .replacingOccurrences(of: #"(?is)<script\b.*?</script>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style\b.*?</style>"#, with: "", options: .regularExpression)

        let pattern = #"(?is)<dl\b[^>]*>(.*?)</dl>|<table\b[^>]*>(.*?)</table>|<div\b[^>]*class=['\"][^'\"]*text-info[^'\"]*['\"][^>]*>(.*?)</div>|<h([1-6])[^>]*>(.*?)</h\4>|<ol\b[^>]*>(.*?)</ol>|<ul\b[^>]*>(.*?)</ul>|<p\b[^>]*>(.*?)</p>|<li\b[^>]*>(.*?)</li>|<hr\b[^>]*>|<img\b[^>]*src=['\"]([^'\"]+)['\"][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return paragraphElements(from: cleanedHTML)
        }

        let nsHTML = cleanedHTML as NSString
        let matches = regex.matches(in: cleanedHTML, range: NSRange(location: 0, length: nsHTML.length))
        var elements: [CompetitionRichHTMLElement] = []
        var cursor = 0

        for match in matches {
            if match.range.location > cursor {
                let fragment = nsHTML.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                elements.append(contentsOf: paragraphElements(from: fragment))
            }

            if match.range(at: 1).location != NSNotFound {
                let rows = definitionRows(from: nsHTML.substring(with: match.range(at: 1)))
                if !rows.isEmpty {
                    elements.append(CompetitionRichHTMLElement(kind: .definitionList(rows)))
                }
            } else if match.range(at: 2).location != NSNotFound {
                if let table = table(from: nsHTML.substring(with: match.range(at: 2))) {
                    elements.append(CompetitionRichHTMLElement(kind: .table(table)))
                }
            } else if match.range(at: 3).location != NSNotFound {
                let infoHTML = nsHTML.substring(with: match.range(at: 3))
                let plain = plainText(from: infoHTML)
                if !plain.isEmpty {
                    elements.append(CompetitionRichHTMLElement(kind: .info(plain)))
                }
            } else if match.range(at: 5).location != NSNotFound {
                let levelText = nsHTML.substring(with: match.range(at: 4))
                let level = Int(levelText) ?? 3
                let title = plainText(from: nsHTML.substring(with: match.range(at: 5)))
                if !title.isEmpty {
                    elements.append(CompetitionRichHTMLElement(kind: .heading(title, level)))
                }
            } else if match.range(at: 6).location != NSNotFound {
                if let list = listElement(from: nsHTML.substring(with: match.range(at: 6)), ordered: true, depth: 0) {
                    elements.append(list)
                }
            } else if match.range(at: 7).location != NSNotFound {
                if let list = listElement(from: nsHTML.substring(with: match.range(at: 7)), ordered: false, depth: 0) {
                    elements.append(list)
                }
            } else if match.range(at: 8).location != NSNotFound {
                elements.append(contentsOf: inlineElements(from: nsHTML.substring(with: match.range(at: 8))))
            } else if match.range(at: 9).location != NSNotFound {
                let itemHTML = "• " + nsHTML.substring(with: match.range(at: 9))
                elements.append(contentsOf: inlineElements(from: itemHTML))
            } else if match.range(at: 10).location != NSNotFound {
                let source = decodeHTMLText(nsHTML.substring(with: match.range(at: 10)))
                if !source.isEmpty {
                    elements.append(CompetitionRichHTMLElement(kind: .image(source)))
                }
            } else {
                elements.append(CompetitionRichHTMLElement(kind: .separator))
            }

            cursor = match.range.location + match.range.length
        }

        if cursor < nsHTML.length {
            let fragment = nsHTML.substring(with: NSRange(location: cursor, length: nsHTML.length - cursor))
            elements.append(contentsOf: paragraphElements(from: fragment))
        }

        return coalesced(elements)
    }

    private static func definitionRows(from html: String) -> [CompetitionRichHTMLDefinitionRow] {
        let pattern = #"(?is)<dt\b([^>]*)>(.*?)</dt>\s*<dd\b([^>]*)>(.*?)</dd>"#
        let captures = htmlCaptures(in: html, pattern: pattern)
        return captures.compactMap { capture in
            guard capture.count >= 4 else { return nil }
            let termAttributes = capture[0]
            let termHTML = capture[1]
            let valueAttributes = capture[2]
            var valueHTML = capture[3]
            let hasCalendarLink = valueHTML.range(
                of: #"(?is)<a\b[^>]*href=['\"][^'\"]+\.ics[^'\"]*['\"][^>]*>.*?</a>"#,
                options: .regularExpression
            ) != nil
            valueHTML = valueHTML.replacingOccurrences(
                of: #"(?is)<a\b[^>]*href=['\"][^'\"]+\.ics[^'\"]*['\"][^>]*>.*?</a>"#,
                with: "",
                options: .regularExpression
            )

            let term = plainText(from: termHTML)
            let valueText = plainText(from: valueHTML)
            let eventIDs = eventIconIDs(in: valueHTML)
            let lowercasedTermHTML = termHTML.lowercased()
            let lowercasedValueHTML = valueHTML.lowercased()
            let termSymbol = lowercasedTermHTML.contains("icon print") ? "printer" : nil
            let isTermSecondary = termAttributes.lowercased().range(
                of: #"\btext-muted\b"#,
                options: .regularExpression
            ) != nil
            let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isAddress = normalizedTerm == "address"
                || normalizedTerm == "地址"
                || normalizedTerm == "地點"
                || normalizedTerm == "地点"
            let paragraphBlockCount = htmlCaptures(
                in: lowercasedValueHTML,
                pattern: #"(?is)<p\b[^>]*>.*?</p>"#
            ).count
            let isEventField = valueAttributes.lowercased().contains("competition-events-list")
            let compactNumericValue = valueText.replacingOccurrences(
                of: #"[\s,._]"#,
                with: "",
                options: .regularExpression
            )
            let isStandaloneNumericField = captures.count == 1
                && !compactNumericValue.isEmpty
                && compactNumericValue.allSatisfy(\.isNumber)
                && termSymbol == nil
            let prefersVerticalFieldLayout = isEventField || isStandaloneNumericField
            let prefersExpandedLayout = lowercasedValueHTML.range(
                of: #"<(?:h[1-6]|ul|ol|table|img|hr)\b"#,
                options: .regularExpression
            ) != nil || paragraphBlockCount > 1 || valueText.count > 180

            guard !term.isEmpty || termSymbol != nil || !valueText.isEmpty || !eventIDs.isEmpty else {
                return nil
            }

            return CompetitionRichHTMLDefinitionRow(
                term: term,
                termSymbol: termSymbol,
                isTermSecondary: isTermSecondary,
                isAddress: isAddress,
                valueHTML: valueHTML,
                valueText: valueText,
                eventIDs: eventIDs,
                hasCalendarLink: hasCalendarLink,
                prefersVerticalFieldLayout: prefersVerticalFieldLayout,
                prefersExpandedLayout: prefersExpandedLayout
            )
        }
    }

    private static func eventIconIDs(in html: String) -> [String] {
        let captures = htmlCaptures(in: html, pattern: #"\[\[event-icon:([A-Za-z0-9_]+)\]\]"#)
            .compactMap(\.first)
            .map { $0.lowercased() }
        var seen = Set<String>()
        return captures.filter { seen.insert($0).inserted }
    }

    private static func listElement(from html: String, ordered: Bool, depth: Int) -> CompetitionRichHTMLElement? {
        let items = listItems(from: html, ordered: ordered, depth: depth)

        guard !items.isEmpty else { return nil }
        return CompetitionRichHTMLElement(kind: .list(items))
    }

    private static func listItems(from html: String, ordered: Bool, depth: Int) -> [CompetitionRichHTMLListItem] {
        let trimmedHTML = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nestedList = leadingNestedList(in: trimmedHTML) {
            return listItems(
                from: nestedList.body,
                ordered: nestedList.ordered,
                depth: depth + 1
            )
        }

        let itemHTMLs = htmlCaptures(in: html, pattern: #"(?is)<li\b[^>]*>(.*?)</li>"#)
            .compactMap(\.first)
        if itemHTMLs.isEmpty {
            return nestedListItems(in: html, depth: depth + 1)
        }

        return itemHTMLs.enumerated().flatMap { index, itemHTML -> [CompetitionRichHTMLListItem] in
            var result: [CompetitionRichHTMLListItem] = []
            let contentHTML = removingNestedListContainers(from: itemHTML)
            let marker = ordered ? "\(index + 1)." : "•"

            if let item = listItem(from: contentHTML, marker: marker, depth: depth) {
                result.append(item)
            }

            result.append(contentsOf: nestedListItems(in: itemHTML, depth: depth + 1))
            return result
        }
    }

    private static func listItem(from html: String, marker: String, depth: Int) -> CompetitionRichHTMLListItem? {
        let runs = textRuns(from: html)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let imageSources = imageSources(from: html)
        guard !runs.isEmpty || !imageSources.isEmpty else { return nil }

        return CompetitionRichHTMLListItem(
            marker: marker,
            depth: depth,
            eventID: eventIconID(in: html),
            runs: runs,
            imageSources: imageSources
        )
    }

    private static func leadingNestedList(in html: String) -> (ordered: Bool, body: String)? {
        let lowercased = html.lowercased()
        guard lowercased.hasPrefix("<ul") || lowercased.hasPrefix("<ol"),
              let closeBracket = html.firstIndex(of: ">") else {
            return nil
        }

        let ordered = lowercased.hasPrefix("<ol")
        let body = String(html[html.index(after: closeBracket)...])
            .replacingOccurrences(of: #"(?is)</(?:ol|ul)>\s*$"#, with: "", options: .regularExpression)
        return (ordered, body)
    }

    private static func nestedListItems(in html: String, depth: Int) -> [CompetitionRichHTMLListItem] {
        let pattern = #"(?is)<(ol|ul)\b[^>]*>(.*?)</\1>"#
        let captures = htmlCaptures(in: html, pattern: pattern)
        return captures.flatMap { capture -> [CompetitionRichHTMLListItem] in
            guard capture.count >= 2 else { return [] }
            return listItems(
                from: capture[1],
                ordered: capture[0].lowercased() == "ol",
                depth: depth
            )
        }
    }

    private static func removingNestedListContainers(from html: String) -> String {
        html.replacingOccurrences(
            of: #"(?is)<(?:ol|ul)\b[^>]*>.*?</(?:ol|ul)>"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func inlineElements(from html: String) -> [CompetitionRichHTMLElement] {
        let pattern = #"(?is)<img\b[^>]*src=['\"]([^'\"]+)['\"][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return paragraphElements(from: html)
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        var elements: [CompetitionRichHTMLElement] = []
        var cursor = 0

        for match in matches {
            if match.range.location > cursor {
                let fragment = nsHTML.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                elements.append(contentsOf: paragraphElements(from: fragment))
            }
            let source = decodeHTMLText(nsHTML.substring(with: match.range(at: 1)))
            if !source.isEmpty {
                elements.append(CompetitionRichHTMLElement(kind: .image(source)))
            }
            cursor = match.range.location + match.range.length
        }

        if cursor < nsHTML.length {
            let fragment = nsHTML.substring(with: NSRange(location: cursor, length: nsHTML.length - cursor))
            elements.append(contentsOf: paragraphElements(from: fragment))
        }
        return elements
    }

    private static func paragraphElements(from html: String) -> [CompetitionRichHTMLElement] {
        let normalizedHTML = normalizeCubingIconHTML(html)
        if let eventLine = eventLineElement(from: normalizedHTML) {
            return [eventLine]
        }
        if let linkedText = linkedTextElement(from: normalizedHTML) {
            return [linkedText]
        }
        let plain = plainText(from: normalizedHTML)
        guard !plain.isEmpty else { return [] }
        return [CompetitionRichHTMLElement(kind: .paragraph(plain))]
    }

    private static func linkedTextElement(from html: String) -> CompetitionRichHTMLElement? {
        let runs = textRuns(from: html)
        guard runs.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return nil
        }
        let hasInlineSemantics = runs.contains {
            $0.url != nil || $0.isBold || $0.isItalic || $0.color != .primary
                || $0.text.contains("\n")
        }
        guard hasInlineSemantics else { return nil }
        return CompetitionRichHTMLElement(kind: .linkedText(runs))
    }

    static func textRuns(from html: String) -> [CompetitionRichHTMLTextRun] {
        coalescedTextRuns(
            from: inlineTextRuns(
                from: normalizeCubingIconHTML(html),
                style: CompetitionRichHTMLInlineStyle()
            )
        )
    }

    private static func inlineTextRuns(
        from html: String,
        style: CompetitionRichHTMLInlineStyle
    ) -> [CompetitionRichHTMLTextRun] {
        let pattern = #"(?is)<(a|strong|b|em|i|span)\b([^>]*)>(.*?)</\1>|<br\s*/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return plainInlineRuns(from: html, style: style)
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        var runs: [CompetitionRichHTMLTextRun] = []
        var cursor = 0

        for match in matches {
            if match.range.location > cursor {
                let prefix = nsHTML.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                runs.append(contentsOf: plainInlineRuns(from: prefix, style: style))
            }

            if match.range(at: 1).location != NSNotFound {
                let tag = nsHTML.substring(with: match.range(at: 1)).lowercased()
                let attributes = nsHTML.substring(with: match.range(at: 2))
                let body = nsHTML.substring(with: match.range(at: 3))
                runs.append(contentsOf: inlineTextRuns(from: body, style: style.applying(tag: tag, attributes: attributes)))
            } else {
                runs.append(
                    CompetitionRichHTMLTextRun(
                        text: "\n",
                        url: style.url,
                        showsExternalLinkIndicator: style.showsExternalLinkIndicator,
                        isBold: style.isBold,
                        isItalic: style.isItalic,
                        color: style.color
                    )
                )
            }

            cursor = match.range.location + match.range.length
        }

        if cursor < nsHTML.length {
            let suffix = nsHTML.substring(with: NSRange(location: cursor, length: nsHTML.length - cursor))
            runs.append(contentsOf: plainInlineRuns(from: suffix, style: style))
        }

        return runs
    }

    private static func plainInlineRuns(
        from html: String,
        style: CompetitionRichHTMLInlineStyle
    ) -> [CompetitionRichHTMLTextRun] {
        let text = plainText(from: html)
        guard !text.isEmpty else { return [] }
        if style.url == nil {
            let markdownSegments = CompetitionService.inlineLinkSegments(in: text)
            if markdownSegments.contains(where: { $0.url != nil }) {
                return markdownSegments.compactMap { segment in
                    guard !segment.text.isEmpty else { return nil }
                    return CompetitionRichHTMLTextRun(
                        text: segment.text,
                        url: segment.url,
                        showsExternalLinkIndicator: segment.url != nil,
                        isBold: style.isBold,
                        isItalic: style.isItalic,
                        color: style.color
                    )
                }
            }
        }
        if style.url == nil,
           let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) {
            let nsText = text as NSString
            let matches = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length))
                .filter { $0.resultType == .phoneNumber && $0.range.length >= 7 }
            if !matches.isEmpty {
                var runs: [CompetitionRichHTMLTextRun] = []
                var cursor = 0
                for match in matches {
                    if match.range.location > cursor {
                        runs.append(
                            CompetitionRichHTMLTextRun(
                                text: nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor)),
                                url: nil,
                                isBold: style.isBold,
                                isItalic: style.isItalic,
                                color: style.color
                            )
                        )
                    }

                    let displayedNumber = nsText.substring(with: match.range)
                    let phoneNumber = match.phoneNumber ?? displayedNumber
                    let dialableNumber = phoneNumber.filter { $0.isNumber || $0 == "+" }
                    runs.append(
                        CompetitionRichHTMLTextRun(
                            text: displayedNumber,
                            url: URL(string: "tel:\(dialableNumber)"),
                            isBold: style.isBold,
                            isItalic: style.isItalic,
                            color: style.color
                        )
                    )
                    cursor = match.range.location + match.range.length
                }

                if cursor < nsText.length {
                    runs.append(
                        CompetitionRichHTMLTextRun(
                            text: nsText.substring(from: cursor),
                            url: nil,
                            isBold: style.isBold,
                            isItalic: style.isItalic,
                            color: style.color
                        )
                    )
                }
                return runs
            }
        }
        return [
            CompetitionRichHTMLTextRun(
                text: text,
                url: style.url,
                showsExternalLinkIndicator: style.showsExternalLinkIndicator,
                isBold: style.isBold,
                isItalic: style.isItalic,
                color: style.color
            )
        ]
    }

    private static func coalescedTextRuns(from runs: [CompetitionRichHTMLTextRun]) -> [CompetitionRichHTMLTextRun] {
        var result: [CompetitionRichHTMLTextRun] = []
        for run in runs where !run.text.isEmpty {
            if run.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !run.text.contains("\n") {
                continue
            }
            if let last = result.last,
               last.url == run.url,
               last.showsExternalLinkIndicator == run.showsExternalLinkIndicator,
               last.isBold == run.isBold,
               last.isItalic == run.isItalic,
               last.color == run.color {
                result[result.count - 1] = CompetitionRichHTMLTextRun(
                    text: last.text + run.text,
                    url: last.url,
                    showsExternalLinkIndicator: last.showsExternalLinkIndicator,
                    isBold: last.isBold,
                    isItalic: last.isItalic,
                    color: last.color
                )
            } else {
                result.append(run)
            }
        }
        return result
    }

    fileprivate static func resolvedURL(from href: String) -> URL? {
        if href.hasPrefix("mailto:") {
            return URL(string: href)
        }
        if href.hasPrefix("//") {
            return URL(string: "https:\(href)")
        }
        if href.hasPrefix("/") {
            return URL(string: "https://cubing.com\(href)")
        }
        return URL(string: href)
    }

    private static func imageSources(from html: String) -> [String] {
        htmlCaptures(in: html, pattern: #"(?is)<img\b[^>]*src=['\"]([^'\"]+)['\"][^>]*>"#)
            .compactMap(\.first)
            .map(decodeHTMLText)
            .filter { !$0.isEmpty }
    }

    private static func eventLineElement(from html: String) -> CompetitionRichHTMLElement? {
        guard let eventID = eventIconID(in: html) else { return nil }
        let text = plainText(
            from: html.replacingOccurrences(of: #"\[\[event-icon:[A-Za-z0-9_]+\]\]"#, with: "", options: .regularExpression)
        )
        guard !eventID.isEmpty, !text.isEmpty else { return nil }
        return CompetitionRichHTMLElement(kind: .eventLine(eventID: eventID, text: text))
    }

    private static func eventIconID(in html: String) -> String? {
        let pattern = #"\[\[event-icon:([A-Za-z0-9_]+)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsHTML = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: nsHTML.length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        return nsHTML.substring(with: match.range(at: 1)).lowercased()
    }

    private static func table(from html: String) -> CompetitionRichHTMLTable? {
        let rowCaptures = htmlCaptures(in: html, pattern: #"(?is)<tr\b[^>]*>(.*?)</tr>"#)
        let rows = rowCaptures.compactMap { rowCapture -> [String]? in
            guard let rowHTML = rowCapture.first else { return nil }
            let cellCaptures = htmlCaptures(in: rowHTML, pattern: #"(?is)<t[hd]\b[^>]*>(.*?)</t[hd]>"#)
            let cells = cellCaptures.compactMap { cellCapture -> String? in
                guard let cellHTML = cellCapture.first else { return nil }
                let plain = plainText(from: cellHTML.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression))
                guard !plain.isEmpty else { return nil }
                return plain
            }
            return cells.isEmpty ? nil : cells
        }
        guard !rows.isEmpty else { return nil }
        return CompetitionRichHTMLTable(rows: rows)
    }

    private static func htmlCaptures(in text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                let range = match.range(at: index)
                guard range.location != NSNotFound else { return nil }
                return nsText.substring(with: range)
            }
        }
    }

    private static func plainText(from html: String) -> String {
        decodeHTMLText(
            normalizeCubingIconHTML(html)
                .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
                .replacingOccurrences(of: #"\[\[event-icon:[A-Za-z0-9_]+\]\]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        )
        .replacingOccurrences(of: #"[ \t\r\f]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated fileprivate static func decodeHTMLText(_ text: String) -> String {
        var decoded = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&yen;", with: "¥")
            .replacingOccurrences(of: "&rmb;", with: "¥")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&hellip;", with: "…")

        decoded = decodeNumericHTMLEntities(in: decoded, pattern: #"&#(\d+);"#, radix: 10)
        decoded = decodeNumericHTMLEntities(in: decoded, pattern: #"&#x([0-9A-Fa-f]+);"#, radix: 16)
        return decoded
    }

    nonisolated private static func decodeNumericHTMLEntities(in text: String, pattern: String, radix: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).reversed()
        let result = NSMutableString(string: text)

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let fullRange = match.range(at: 0)
            let valueRange = match.range(at: 1)
            guard valueRange.location != NSNotFound else { continue }
            let valueText = nsText.substring(with: valueRange)
            guard let value = Int(valueText, radix: radix),
                  let scalar = UnicodeScalar(value) else { continue }
            result.replaceCharacters(in: fullRange, with: String(scalar))
        }

        return result as String
    }

    private static func normalizeCubingIconHTML(_ html: String) -> String {
        injectEventIconMarkers(in: html)
            .replacingOccurrences(of: #"(?is)<i\b[^>]*class=['\"][^'\"]*fa-rmb[^'\"]*['\"][^>]*>\s*</i>"#, with: "¥", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<i\b[^>]*class=['\"][^'\"]*(?:fa|event-icon)[^'\"]*['\"][^>]*>\s*</i>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "　", with: " ")
    }

    private static func normalizeDefinitionListHTML(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"(?is)<dt\b[^>]*>"#, with: "<h4>", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)</dt>"#, with: "</h4>", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<dd\b[^>]*>"#, with: "<div>", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)</dd>"#, with: "</div>", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)</?dl\b[^>]*>"#, with: "", options: .regularExpression)
    }

    private static func injectEventIconMarkers(in html: String) -> String {
        let patterns = [
            #"(?is)<i\b[^>]*class=['\"][^'\"]*event-icon-([A-Za-z0-9_]+)[^'\"]*['\"][^>]*>\s*</i>"#,
            #"(?is)<i\b[^>]*class=['\"][^'\"]*cubing-icon[^'\"]*event-([A-Za-z0-9_]+)[^'\"]*['\"][^>]*>\s*</i>"#
        ]
        var output = html

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let source = output as NSString
            let result = NSMutableString(string: output)
            for match in regex.matches(in: output, range: NSRange(location: 0, length: source.length)).reversed() {
                guard match.numberOfRanges > 1 else { continue }
                let eventID = source.substring(with: match.range(at: 1))
                result.replaceCharacters(in: match.range(at: 0), with: " [[event-icon:\(eventID)]] ")
            }
            output = result as String
        }

        return output
    }

    private static func coalesced(_ elements: [CompetitionRichHTMLElement]) -> [CompetitionRichHTMLElement] {
        var result: [CompetitionRichHTMLElement] = []
        var previousWasSeparator = false

        for element in elements {
            if case .separator = element.kind {
                guard !previousWasSeparator, !result.isEmpty else { continue }
                previousWasSeparator = true
            } else {
                previousWasSeparator = false
            }
            result.append(element)
        }

        if result.last.map({ if case .separator = $0.kind { return true }; return false }) == true {
            result.removeLast()
        }
        return result
    }

    func topSpacing(isFirst: Bool) -> CGFloat {
        guard !isFirst else { return 0 }
        switch kind {
        case .heading(_, let level): return level <= 2 ? 22 : 16
        case .separator: return 10
        case .image, .table, .definitionList: return 8
        case .list: return 4
        default: return 2
        }
    }

    var bottomSpacing: CGFloat {
        switch kind {
        case .heading: return 8
        case .paragraph, .linkedText, .eventLine, .info: return 8
        case .list, .table, .image, .definitionList: return 10
        case .separator: return 10
        }
    }
}

private struct CompetitionRichHTMLRenderBlock: Identifiable {
    let range: Range<Int>
    let isSelectableTextGroup: Bool

    var id: Int { range.lowerBound }
}

nonisolated private struct CompetitionRichHTMLInlineStyle: Sendable {
    var url: URL?
    var showsExternalLinkIndicator = false
    var isBold = false
    var isItalic = false
    var color: CompetitionRichHTMLTextColor = .primary

    func applying(tag: String, attributes: String) -> CompetitionRichHTMLInlineStyle {
        var copy = self
        switch tag {
        case "a":
            if let href = Self.attribute("href", in: attributes) {
                copy.url = CompetitionRichHTMLElement.resolvedURL(from: href)
            }
            copy.showsExternalLinkIndicator = Self.attribute("target", in: attributes)?.lowercased() == "_blank"
                && !attributes.lowercased().contains("hide-new-window-icon")
        case "strong", "b":
            copy.isBold = true
        case "em", "i":
            copy.isItalic = true
        case "span":
            if let color = Self.colorRole(from: attributes) {
                copy.color = color
            }
        default:
            break
        }
        return copy
    }

    private static func attribute(_ name: String, in attributes: String) -> String? {
        let patterns = [
            #"\#(name)\s*=\s*"([^"]*)""#,
            #"\#(name)\s*=\s*'([^']*)'"#
        ]
        let nsAttributes = attributes as NSString

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: attributes, range: NSRange(location: 0, length: nsAttributes.length)),
                  match.numberOfRanges > 1 else {
                continue
            }
            return CompetitionRichHTMLElement.decodeHTMLText(nsAttributes.substring(with: match.range(at: 1)))
        }

        return nil
    }

    private static func colorRole(from attributes: String) -> CompetitionRichHTMLTextColor? {
        let lowercased = attributes.lowercased()
        if lowercased.contains("text-danger")
            || lowercased.contains("color:#e53333")
            || lowercased.contains("color: #e53333")
            || lowercased.contains("color:red")
            || lowercased.contains("color: red") {
            return .danger
        }
        if lowercased.contains("text-info") || lowercased.contains("color:#31708f") {
            return .info
        }
        return nil
    }
}

private struct CompetitionSelectableDocument {
    let attributedText: NSAttributedString
    let inlineControls: [SelectableInlineControl]
}

nonisolated struct CompetitionRichHTMLTable: Sendable {
    let rows: [[String]]
}

nonisolated struct CompetitionRichHTMLDefinitionRow: Sendable {
    let term: String
    let termSymbol: String?
    let isTermSecondary: Bool
    let isAddress: Bool
    let valueHTML: String
    let valueText: String
    let eventIDs: [String]
    let hasCalendarLink: Bool
    let prefersVerticalFieldLayout: Bool
    let prefersExpandedLayout: Bool
}

nonisolated struct CompetitionRichHTMLListItem: Hashable, Sendable {
    let marker: String
    let depth: Int
    let eventID: String?
    let runs: [CompetitionRichHTMLTextRun]
    let imageSources: [String]

    var markerWidth: CGFloat {
        marker == "•" ? 16 : 24
    }
}

nonisolated enum CompetitionRichHTMLTextColor: Hashable, Sendable {
    case primary
    case info
    case danger

    var swiftUIColor: Color {
        switch self {
        case .primary:
            return .primary
        case .info:
            return .blue
        case .danger:
            return Color(red: 229 / 255, green: 51 / 255, blue: 51 / 255)
        }
    }

    var uiColor: UIColor {
        switch self {
        case .primary:
            return .label
        case .info:
            return .systemBlue
        case .danger:
            return UIColor(red: 229 / 255, green: 51 / 255, blue: 51 / 255, alpha: 1)
        }
    }
}

nonisolated struct CompetitionRichHTMLTextRun: Hashable, Sendable {
    let text: String
    let url: URL?
    let showsExternalLinkIndicator: Bool
    let isBold: Bool
    let isItalic: Bool
    let color: CompetitionRichHTMLTextColor

    init(
        text: String,
        url: URL?,
        showsExternalLinkIndicator: Bool = false,
        isBold: Bool = false,
        isItalic: Bool = false,
        color: CompetitionRichHTMLTextColor = .primary
    ) {
        self.text = text
        self.url = url
        self.showsExternalLinkIndicator = showsExternalLinkIndicator
        self.isBold = isBold
        self.isItalic = isItalic
        self.color = color
    }
}

private struct LinkedTextFlow: View {
    let runs: [CompetitionRichHTMLTextRun]

    var body: some View {
        Text(attributedString)
            .foregroundStyle(.primary)
            .tint(.blue)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedString: AttributedString {
        var result = AttributedString()
        var plainText = ""
        for (index, run) in runs.enumerated() {
            var text = resolvedText(for: run, after: plainText)
            let nextRunHasSameLink = runs.indices.contains(index + 1) && runs[index + 1].url == run.url
            if run.showsExternalLinkIndicator && !nextRunHasSameLink {
                text += " ↗"
            }
            guard !text.isEmpty else { continue }

            var part = AttributedString(text)
            var font = Font.system(size: 15, weight: run.isBold ? .bold : .regular)
            if run.isItalic {
                font = font.italic()
            }
            part.font = font
            part.foregroundColor = run.url == nil ? run.color.swiftUIColor : .blue
            if let url = run.url {
                part.link = url
            }

            result.append(part)
            plainText += text
        }
        return result
    }

    private func resolvedText(for run: CompetitionRichHTMLTextRun, after currentText: String) -> String {
        if !currentText.isEmpty, shouldInsertSpace(before: run.text, after: currentText) {
            return " " + run.text
        }
        return run.text
    }

    private func shouldInsertSpace(before nextText: String, after currentText: String) -> Bool {
        guard !nextText.isEmpty else { return false }
        let previous = String(currentText.suffix(1))
        guard !previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if nextText.hasPrefix(" ") { return false }

        let noSpacePrefixes = [".", ",", ";", ":", "!", "?", ")", "]", "}", "。", "，", "；", "：", "！", "？", "、"]
        if noSpacePrefixes.contains(where: { nextText.hasPrefix($0) }) {
            return false
        }

        let noSpaceAfter = ["(", "[", "{"]
        if noSpaceAfter.contains(previous) {
            return false
        }

        return true
    }
}

private struct FlexibleTagFlow: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chunkedItems, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        Text(item)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.secondary.opacity(0.08), in: Capsule())
                    }
                }
            }
        }
    }

    private var chunkedItems: [[String]] {
        stride(from: 0, to: items.count, by: 3).map { start in
            Array(items[start ..< min(start + 3, items.count)])
        }
    }
}


#endif
