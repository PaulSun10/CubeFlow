import SwiftUI
import Combine
import UIKit

/// Visual-only progress follows the existing native self-sizing animation. It
/// never writes a cell frame, scroll offset, or collection-layout invalidation.
@MainActor final class CompetitionTopCubersMotion: NSObject, ObservableObject {
    @Published private(set) var fraction: CGFloat?
    weak var anchor: CompetitionTopCubersMotionAnchor?
    private weak var cell: UICollectionViewCell?
    private weak var surface: CompetitionTopCubersSurfaceAnchor?
    private var surfaceInset: CGFloat = 0
    private var hasSurfaceInset = false
    private var link: CADisplayLink?
    private var sourceHeight: CGFloat = 0
    private var previousModelHeight: CGFloat = 0
    private var sourceFraction: CGFloat = 0
    private var targetFraction: CGFloat = 0
    private var started: CFTimeInterval = 0
    private var modelGoals: [Bool: CGFloat] = [:]

    func begin(expanded: Bool, reduceMotion: Bool) -> Bool {
        guard !reduceMotion, let anchor, anchor.window != nil,
              let cell = sequence(first: anchor.superview, next: { $0?.superview })
                .compactMap({ $0 as? UICollectionViewCell }).first else {
            cancel(); return false
        }
        let source = fraction ?? (expanded ? 1 : 0)
        let target: CGFloat = expanded ? 0 : 1
        let wasActive = fraction != nil
        let goals = modelGoals
        cancel()
        guard abs(target - source) > 0.001 else { return true }
        self.cell = cell
        modelGoals = wasActive ? goals : [expanded: cell.bounds.height]
        func surface(in view: UIView) -> CompetitionTopCubersSurfaceAnchor? {
            if let surface = view as? CompetitionTopCubersSurfaceAnchor { return surface }
            return view.subviews.lazy.compactMap { surface(in: $0) }.first
        }
        self.surface = surface(in: cell)
        if !hasSurfaceInset, let surface = self.surface {
            surfaceInset = cell.bounds.height - surface.bounds.height
            hasSurfaceInset = true
        }
        let layer = self.surface?.layer ?? cell.layer
        sourceHeight = layer.presentation()?.bounds.height ?? layer.bounds.height
        previousModelHeight = cell.bounds.height
        sourceFraction = source; targetFraction = target
        fraction = source; started = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(sample))
        self.link = link; link.add(to: .main, forMode: .common)
        return true
    }

    @objc private func sample() {
        guard let cell, let anchor, anchor.window != nil, anchor.isDescendant(of: cell) else { cancel(); return }
        // Teardown/coalesced updates must not leave a display link alive. This
        // bound is cleanup only, not an animation duration or delayed reveal.
        guard CACurrentMediaTime() - started < 1 else { cancel(); return }
        let targetExpanded = targetFraction == 1
        guard anchor.expanded == targetExpanded else { return }
        // A reversed/coalesced tap may return to an already allocated endpoint;
        // it need not produce another distinct model-height write.
        if let goal = modelGoals[targetExpanded] {
            guard abs(cell.bounds.height - goal) < 0.1 else { return }
        } else {
            guard abs(cell.bounds.height - previousModelHeight) > 0.1 else { return }
            modelGoals[targetExpanded] = cell.bounds.height
        }
        let targetHeight = cell.bounds.height - surfaceInset
        let layer = surface?.layer ?? cell.layer
        let presented = layer.presentation()?.bounds.height ?? layer.bounds.height
        let distance = targetHeight - sourceHeight
        let progress = abs(distance) > 0.1 ? min(1, max(0, (presented - sourceHeight) / distance)) : 1
        let next = sourceFraction + (targetFraction - sourceFraction) * progress
        if fraction != next {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { fraction = next }
        }
        // The fitter rounds the row up to whole points; the surface retains its
        // fractional intrinsic height, so endpoint rounding can differ by <1 pt.
        if abs(presented - targetHeight) < 1, cell.layer.animation(forKey: "bounds.size") == nil { cancel() }
    }

    func cancel() {
        link?.invalidate(); link = nil; cell = nil; surface = nil
        modelGoals = [:]
        if fraction != nil {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { fraction = nil }
        }
    }
    #if DEBUG
    var acceptanceState: String {
        "source=\(sourceHeight), model=\(cell?.bounds.height ?? 0), inset=\(surfaceInset), goals=\(modelGoals)"
    }
    #endif
}

/// A public, layout-neutral marker on the existing content-wrapping surface.
/// Its bounds follow SwiftUI's rendered surface size, independently of the
/// collection cell's allocation animation. No private glass hierarchy lookup.
final class CompetitionTopCubersSurfaceAnchor: UIView {}
struct CompetitionTopCubersSurfaceBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> CompetitionTopCubersSurfaceAnchor {
        let view = CompetitionTopCubersSurfaceAnchor()
        view.isUserInteractionEnabled = false; view.isAccessibilityElement = false
        return view
    }
    func updateUIView(_ view: CompetitionTopCubersSurfaceAnchor, context: Context) {}
}

final class CompetitionTopCubersMotionAnchor: UIView {
    weak var motion: CompetitionTopCubersMotion?
    var expanded = false
    #if DEBUG
    var acceptanceTap: (() -> Void)?
    #endif
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { motion?.cancel() }
    }
}

private struct CompetitionTopCubersMotionBridge: UIViewRepresentable {
    let motion: CompetitionTopCubersMotion
    let expanded: Bool
    let action: () -> Void
    func makeUIView(context: Context) -> CompetitionTopCubersMotionAnchor {
        let view = CompetitionTopCubersMotionAnchor()
        view.isUserInteractionEnabled = false; view.isAccessibilityElement = false
        return view
    }
    func updateUIView(_ view: CompetitionTopCubersMotionAnchor, context: Context) {
        view.motion = motion; view.expanded = expanded; motion.anchor = view
        #if DEBUG
        view.acceptanceTap = action
        #endif
    }
    static func dismantleUIView(_ view: CompetitionTopCubersMotionAnchor, coordinator: ()) {
        view.motion?.cancel()
        #if DEBUG
        view.acceptanceTap = nil
        #endif
    }
}

private struct CompetitionTopCuberReveal: ViewModifier {
    let visibleHeight: CGFloat?
    let rowHeight: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        if let visibleHeight {
            content.opacity(min(1, visibleHeight / max(1, rowHeight)))
                .mask(alignment: .top) { Rectangle().frame(height: visibleHeight) }
                .accessibilityHidden(visibleHeight < rowHeight)
                .allowsHitTesting(visibleHeight >= rowHeight)
        } else { content }
    }
}

@MainActor final class CompetitionTopCuberDisclosure: ObservableObject {
    @Published var expanded = false
}

@MainActor final class CompetitionTopCuberDisclosureStore: ObservableObject {
    private var values: [String: CompetitionTopCuberDisclosure] = [:]
    func disclosure(for id: String) -> CompetitionTopCuberDisclosure {
        if let value = values[id] { return value }
        let value = CompetitionTopCuberDisclosure(); values[id] = value
        return value
    }
    func reset() { values.removeAll() }
}

/// Observe inside the hosting cell's SwiftUI graph; retain identity outside it.
struct CompetitionPersistentTopCubers<Content: View>: View {
    let previews: [CompetitionTopCuberPreview]
    let language: String
    @ObservedObject var disclosure: CompetitionTopCuberDisclosure
    var traceIdentity: String = "fixture"
    @ViewBuilder let entry: (CompetitionTopCuberPreview) -> Content
    var body: some View {
        #if DEBUG
        CompetitionExpandableTopCubers(previews: previews, language: language, expansion: $disclosure.expanded,
            traceIdentity: traceIdentity,
            onDisclosureTap: { if CompetitionLongListAcceptance.traceEnabled { CompetitionDisclosureViewportProbe.shared.begin(identity: traceIdentity) } }, entry: entry)
        #else
        CompetitionExpandableTopCubers(previews: previews, language: language, expansion: $disclosure.expanded, entry: entry)
        #endif
    }
}

enum CompetitionTopCuberRows {
    static func visibleCount(ids: [String], frames: [String: CGRect], rowLimit: Int = 3) -> Int? {
        guard !ids.isEmpty, ids.allSatisfy({ frames[$0] != nil }) else { return nil }
        var rowY: CGFloat?
        var rows = 0
        var count = 0
        for id in ids {
            guard let frame = frames[id] else { return nil }
            if rowY == nil || abs(frame.minY - rowY!) > 1 {
                rows += 1; rowY = frame.minY
            }
            if rows > rowLimit { break }
            count += 1
        }
        return count
    }
}

/// Measure the same complete wrapping layout, then render a stable prefix, never a clipping mask.
struct CompetitionExpandableTopCubers<Content: View>: View {
    let previews: [CompetitionTopCuberPreview]
    let language: String
    var expansion: Binding<Bool>? = nil
    #if DEBUG
    var traceIdentity: String? = nil
    var onDisclosureTap: (() -> Void)? = nil
    var reduceMotionForAcceptance: Bool? = nil
    #endif
    @ViewBuilder let entry: (CompetitionTopCuberPreview) -> Content
    @State private var localExpanded = false
    private var expanded: Bool { expansion?.wrappedValue ?? localExpanded }
    @State private var width: CGFloat = 0
    @State private var collapsedCount: Int?
    @State private var measuredFrames: [String: CGRect] = [:]
    @StateObject private var motion = CompetitionTopCubersMotion()
    @Namespace private var measurementSpace
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool {
        #if DEBUG
        if let reduceMotionForAcceptance { return reduceMotionForAcceptance }
        #endif
        return systemReduceMotion
    }
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.layoutDirection) private var layoutDirection
    private var visible: [CompetitionTopCuberPreview] {
        Array(previews.prefix(expanded || motion.fraction != nil ? previews.count : collapsedCount ?? 0))
    }
    private var fullHeight: CGFloat { measuredFrames.values.map(\.maxY).max() ?? 0 }
    private var collapsedHeight: CGFloat {
        previews.prefix(collapsedCount ?? 0).compactMap { measuredFrames[$0.id]?.maxY }.max() ?? 0
    }
    private var revealedHeight: CGFloat {
        collapsedHeight + (fullHeight - collapsedHeight) * (motion.fraction ?? (expanded ? 1 : 0))
    }
    @ViewBuilder
    var body: some View {
        if #available(iOS 16.0, *) {
            CompetitionTopCubersSizingLayout(entryCount: previews.count, expanded: expanded) {
                ForEach(previews) { preview in
                    item(preview, measuring: true).hidden().allowsHitTesting(false).accessibilityHidden(true)
                }
                // Measure only the applicable label in the layout pass. Candidates
                // keep localized wrapping exact even before collapsedCount exists.
                ForEach(1..<max(1, previews.count), id: \.self) { hiddenCount in
                    disclosureLabel(hiddenCount: hiddenCount).hidden().allowsHitTesting(false).accessibilityHidden(true)
                }
                visibleContent
            }
            .coordinateSpace(name: measurementSpace)
            .onPreferenceChange(TopCubersFramesKey.self, perform: updateCollapsedCount)
            .background { CompetitionTopCubersMotionBridge(motion: motion, expanded: expanded, action: toggleDisclosure) }
            .onDisappear { motion.cancel() }
            .onChange(of: previews) { _ in motion.cancel() }
            .onChange(of: language) { _ in motion.cancel() }
            .onChange(of: reduceMotion) { _ in motion.cancel() }
            .onChange(of: sizeCategory) { _ in motion.cancel() }
            .onChange(of: layoutDirection) { _ in motion.cancel() }
        } else {
            legacyContent
        }
    }
    private var visibleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            flow(visible, measuring: false)
            if let collapsedCount, collapsedCount < previews.count {
                Button(action: toggleDisclosure) {
                    disclosureLabel(hiddenCount: previews.count - collapsedCount)
                }.buttonStyle(.plain).accessibilityIdentifier("competition-top-cubers-expand")
                    .accessibilityValue(expanded ? PublishedCompetitionStrings.text("expanded", language) : PublishedCompetitionStrings.text("collapsed", language))
                    .competitionDisclosureTitleProbe(disclosureProbeID("disclosure"))
                    .offset(y: motion.fraction != nil ? revealedHeight - fullHeight : 0)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .transaction { transaction in
                if motion.fraction != nil { transaction.animation = nil; transaction.disablesAnimations = true }
            }
            .preference(key: CompetitionTopCubersVisibilityKey.self, value: collapsedCount.map {
                CompetitionTopCubersVisibility(collapsed: $0, visible: expanded ? previews.count : $0, total: previews.count)
            })
    }
    private func disclosureLabel(hiddenCount: Int) -> some View {
        HStack(spacing: 5) {
            Text(expanded ? PublishedCompetitionStrings.text("show_less", language)
                : String(format: PublishedCompetitionStrings.text("show_more_count", language), hiddenCount))
            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                .rotationEffect(.degrees(-180 * Double(motion.fraction ?? (expanded ? 1 : 0))))
        }.font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).frame(minHeight: 44).contentShape(Rectangle())
    }
    private func updateCollapsedCount(_ frames: [String: CGRect]) {
        if measuredFrames != frames {
            motion.cancel()
            measuredFrames = frames
        }
        if let count = CompetitionTopCuberRows.visibleCount(ids: previews.map(\.id), frames: frames), collapsedCount != count {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { collapsedCount = count }
        }
    }
    private var legacyContent: some View {
        visibleContent
            .background { GeometryReader { proxy in Color.clear.preference(key: TopCubersWidthKey.self, value: proxy.size.width) } }
            .onPreferenceChange(TopCubersWidthKey.self) { if width != $0 { width = $0 } }
            .background(alignment: .topLeading) {
                if width > 0 {
                    flow(previews, measuring: true).frame(width: width).fixedSize(horizontal: false, vertical: true)
                        .coordinateSpace(name: measurementSpace).opacity(0).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .onPreferenceChange(TopCubersFramesKey.self, perform: updateCollapsedCount)
    }
    private func toggleDisclosure() {
        #if DEBUG
        onDisclosureTap?()
        #endif
        if #available(iOS 16.0, *), motion.begin(expanded: expanded, reduceMotion: reduceMotion) || reduceMotion {
            // Match the native critically damped self-sizing spring, retaining
            // the content-wrapping glass surface's own layout animation.
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) {
                if let expansion { expansion.wrappedValue.toggle() } else { localExpanded.toggle() }
            }
        } else { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.32)) {
            if let expansion { expansion.wrappedValue.toggle() } else { localExpanded.toggle() }
        } }
    }
    @ViewBuilder private func flow(_ values: [CompetitionTopCuberPreview], measuring: Bool) -> some View {
        if #available(iOS 16.0, *) {
            CompetitionWrappingLayout(horizontalSpacing: 8, verticalSpacing: 8) { items(values, measuring: measuring) }
        } else {
            // The original iOS 15 adaptive grid uses a 112-point minimum. Non-lazy
            // measurement is necessary even when the visible prefix is initially empty.
            let columns = max(1, Int((width + 8) / 120))
            let cellWidth = max(0, (width - CGFloat(columns - 1) * 8) / CGFloat(columns))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(stride(from: 0, to: values.count, by: columns)), id: \.self) { start in
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(Array(values[start..<min(start + columns, values.count)])) { preview in
                            item(preview, measuring: measuring).frame(width: cellWidth, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
    private func disclosureProbeID(_ component: String) -> String {
        #if DEBUG
        return traceIdentity.map { "\($0)|\(component)" } ?? ""
        #else
        return ""
        #endif
    }
    private func items(_ values: [CompetitionTopCuberPreview], measuring: Bool) -> some View {
        ForEach(values) { preview in
            item(preview, measuring: measuring)
        }
    }
    private func item(_ preview: CompetitionTopCuberPreview, measuring: Bool) -> some View {
        entry(preview)
                .modifier(CompetitionTopCuberReveal(visibleHeight: revealHeight(preview, measuring: measuring),
                                                   rowHeight: measuredFrames[preview.id]?.height ?? 0))
                .competitionDisclosureTitleProbe(measuring ? "" : disclosureProbeID("cuber:\(preview.id)"))
                .background {
                    #if DEBUG
                    Color.clear.preference(key: CompetitionTopCubersRevealKey.self,
                        value: !measuring ? revealHeight(preview, measuring: false).map { [preview.id: $0] } ?? [:] : [:])
                    #endif
                    if measuring {
                        GeometryReader { proxy in
                            Color.clear.preference(key: TopCubersFramesKey.self, value: [preview.id: proxy.frame(in: .named(measurementSpace))])
                        }
                    }
                }
                .transition(.identity)
    }
    private func revealHeight(_ preview: CompetitionTopCuberPreview, measuring: Bool) -> CGFloat? {
        guard !measuring, motion.fraction != nil, let count = collapsedCount,
              let index = previews.firstIndex(where: { $0.id == preview.id }), index >= count,
              let frame = measuredFrames[preview.id] else { return nil }
        return min(frame.height, max(0, revealedHeight - frame.minY))
    }
}

#if DEBUG
struct CompetitionTopCubersRevealKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
#endif

/// Intrinsic height comes from loaded entries, not the asynchronously populated
/// visible prefix. A fresh hosting configuration therefore cannot commit its
/// temporary empty-prefix height to the collection layout.
@available(iOS 16.0, *)
private struct CompetitionTopCubersSizingLayout: Layout {
    let entryCount: Int
    let expanded: Bool

    private func measurement(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat, label: Int?) {
        let wrapping = CompetitionWrappingLayout()
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var row = 1
        var collapsed = 0
        for index in 0..<entryCount {
            let size = wrapping.measuredSize(for: subviews[index], maxWidth: width)
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + wrapping.verticalSpacing; rowHeight = 0; row += 1
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            if row <= 3 { collapsed += 1 }
            x += size.width + wrapping.horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
        let count = expanded ? entryCount : collapsed
        let contentHeight = frames.prefix(count).map(\.maxY).max() ?? 0
        guard collapsed < entryCount else { return (frames, contentHeight, nil) }
        let label = entryCount + (entryCount - collapsed - 1)
        let labelHeight = subviews[label].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return (frames, contentHeight + wrapping.verticalSpacing + labelHeight, label)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = measurement(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? result.frames.map(\.maxX).max() ?? 0, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = measurement(width: bounds.width, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                  proposal: ProposedViewSize(frame.size))
        }
        if let label = result.label {
            subviews[label].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
        subviews[subviews.count - 1].place(at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: result.height))
    }
}
struct CompetitionTopCubersVisibility: Equatable {
    let collapsed: Int
    let visible: Int
    let total: Int
}
struct CompetitionTopCubersVisibilityKey: PreferenceKey {
    static var defaultValue: CompetitionTopCubersVisibility? = nil
    static func reduce(value: inout CompetitionTopCubersVisibility?, nextValue: () -> CompetitionTopCubersVisibility?) { value = nextValue() ?? value }
}
private struct TopCubersFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
private struct TopCubersWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
