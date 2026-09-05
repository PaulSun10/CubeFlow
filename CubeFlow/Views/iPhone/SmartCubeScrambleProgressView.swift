#if os(iOS)
import SwiftUI

private enum SmartCubeRecoveryDisplayItem: Identifiable {
    case original(Int)
    case recoveryMove(Int)

    var id: String {
        switch self {
        case .original(let index): "original-\(index)"
        case .recoveryMove(let index): "recovery-move-\(index)"
        }
    }
}

struct SmartCubeScrambleProgressView: View {
    let scramble: String
    let tokens: [String]
    let completedTokenIndices: Set<Int>
    let highlightedTokenIndex: Int?
    let recoveryPlan: SmartCubeRecoveryPlan?
    let recoveryDisplay: SmartCubeRecoveryDisplay
    let highlightAnimation: SmartCubeHighlightAnimation
    let behavior: SmartCubeCompletedMovesBehavior
    let transition: SmartCubeScrambleTransition
    let fontDesign: TimerFontDesignOption
    let fontStyle: TimerFontStyleOption
    let fontSize: Double
    let foregroundStyle: AnyShapeStyle
    let highlightBackgroundStyle: AnyShapeStyle
    let highlightForegroundStyle: AnyShapeStyle

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if #available(iOS 16.0, *) {
                    SmartCubeMoveFlowLayout(
                        horizontalSpacing: 7,
                        verticalSpacing: 5,
                        collapsesCompletedMoves: behavior == .collapse
                    ) {
                        moveTokens
                    }
                    .backgroundPreferenceValue(SmartCubeHighlightedTokenBoundsKey.self) { anchor in
                        GeometryReader { proxy in
                            if let anchor {
                                let tokenFrame = proxy[anchor]
                                let capsuleFrame = SmartCubeHighlightCapsuleGeometry.frame(
                                    around: tokenFrame,
                                    containerSize: proxy.size
                                )
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(highlightBackgroundStyle)
                                    .frame(width: capsuleFrame.width, height: capsuleFrame.height)
                                    .position(x: capsuleFrame.midX, y: capsuleFrame.midY)
                                    .transaction(disableHighlightAnimationIfNeeded)
                            }
                        }
                    }
                } else {
                    Text(fallbackText)
                        .multilineTextAlignment(.center)
                }
            }
            .font(fontDesign.font(size: fontSize, style: fontStyle))
            .compatibleFontWidth(fontDesign)
            .foregroundStyle(foregroundStyle)
            .frame(maxWidth: .infinity, alignment: .center)

            if let recoveryPlan, recoveryDisplay == .separate {
                recoveryLane(recoveryPlan)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .id(scramble)
    }

    @ViewBuilder
    @available(iOS 16.0, *)
    private var moveTokens: some View {
        ForEach(displayItems) { item in
            switch item {
            case .original(let index):
                originalToken(at: index, allowsHighlight: recoveryPlan == nil)
            case .recoveryMove(let index):
                if let recoveryPlan {
                    recoveryToken(recoveryPlan.correctionMoves[index], index: index)
                }
            }
        }
    }

    @available(iOS 16.0, *)
    private func originalToken(at index: Int, allowsHighlight: Bool) -> some View {
        let isHighlighted = allowsHighlight && highlightedTokenIndex == index
        return Text(tokens[index])
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isHighlighted ? highlightForegroundStyle : foregroundStyle)
            .anchorPreference(
                key: SmartCubeHighlightedTokenBoundsKey.self,
                value: .bounds
            ) { anchor in isHighlighted ? anchor : nil }
            .opacity(tokenOpacity(at: index))
            .blur(radius: tokenBlur(at: index))
            .offset(
                x: tokenHorizontalOffset(at: index),
                y: tokenVerticalOffset(at: index)
            )
            .scaleEffect(tokenScale(at: index))
            .layoutValue(
                key: SmartCubeMoveCompletedLayoutKey.self,
                value: completedTokenIndices.contains(index)
            )
    }

    @available(iOS 16.0, *)
    private func recoveryToken(_ move: String, index: Int) -> some View {
        let isHighlighted = index == 0
        return Text(move)
            .lineLimit(1)
            .fixedSize()
            .fontWeight(.semibold)
            .foregroundStyle(isHighlighted ? highlightForegroundStyle : AnyShapeStyle(Color.orange))
            .anchorPreference(
                key: SmartCubeHighlightedTokenBoundsKey.self,
                value: .bounds
            ) { anchor in isHighlighted ? anchor : nil }
            .transaction(disableHighlightAnimationIfNeeded)
            .layoutValue(key: SmartCubeMoveCompletedLayoutKey.self, value: false)
    }

    private func recoveryLane(_ plan: SmartCubeRecoveryPlan) -> some View {
        Group {
            if #available(iOS 16.0, *) {
                SmartCubeMoveFlowLayout(horizontalSpacing: 6, verticalSpacing: 4, collapsesCompletedMoves: false) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .accessibilityHidden(true)
                    ForEach(plan.correctionMoves.indices, id: \.self) { index in
                        Text(plan.correctionMoves[index])
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(index == 0 ? highlightForegroundStyle : AnyShapeStyle(Color.orange))
                            .padding(.horizontal, index == 0 ? 4 : 0)
                            .padding(.vertical, index == 0 ? 1 : 0)
                            .background {
                                if index == 0 {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(highlightBackgroundStyle)
                                        .transaction(disableHighlightAnimationIfNeeded)
                                }
                            }
                    }
                }
            } else {
                Text(plan.correctionMoves.joined(separator: " "))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(
                .orange.opacity(0.55),
                style: StrokeStyle(lineWidth: 1, dash: [3, 2])
            )
        }
        .accessibilityLabel(Text("smart_cube.timer.recovery"))
        .accessibilityValue(Text(plan.correctionMoves.joined(separator: " ")))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func inlineItems(for plan: SmartCubeRecoveryPlan) -> [SmartCubeRecoveryDisplayItem] {
        let insertionIndex = recoveryInsertionIndex(for: plan)
        var result: [SmartCubeRecoveryDisplayItem] = []
        for index in tokens.indices {
            if index == insertionIndex {
                result += plan.correctionMoves.indices.map(SmartCubeRecoveryDisplayItem.recoveryMove)
            }
            result.append(.original(index))
        }
        if insertionIndex == tokens.count {
            result += plan.correctionMoves.indices.map(SmartCubeRecoveryDisplayItem.recoveryMove)
        }
        return result
    }

    private var displayItems: [SmartCubeRecoveryDisplayItem] {
        guard let recoveryPlan else {
            return tokens.indices.map(SmartCubeRecoveryDisplayItem.original)
        }
        switch recoveryDisplay {
        case .separate:
            return tokens.indices.map(SmartCubeRecoveryDisplayItem.original)
        case .inline:
            return inlineItems(for: recoveryPlan)
        }
    }

    private func recoveryInsertionIndex(for plan: SmartCubeRecoveryPlan) -> Int {
        tokens.indices.first { !plan.checkpoint.completedTokenIndices.contains($0) } ?? tokens.count
    }

    private func disableHighlightAnimationIfNeeded(_ transaction: inout Transaction) {
        if highlightAnimation == .instant {
            transaction.animation = nil
        }
    }

    private var fallbackText: String {
        let indices = behavior == .collapse
            ? tokens.indices.filter { !completedTokenIndices.contains($0) }
            : Array(tokens.indices)
        var visibleTokens = indices.map { tokens[$0] }
        guard let recoveryPlan else { return visibleTokens.joined(separator: " ") }
        let insertionIndex = min(
            indices.firstIndex(of: recoveryInsertionIndex(for: recoveryPlan)) ?? visibleTokens.count,
            visibleTokens.count
        )
        switch recoveryDisplay {
        case .separate:
            break
        case .inline:
            visibleTokens.insert(contentsOf: recoveryPlan.correctionMoves, at: insertionIndex)
        }
        return visibleTokens.joined(separator: " ")
    }

    private func tokenOpacity(at index: Int) -> Double {
        guard completedTokenIndices.contains(index) else { return 1 }
        if behavior == .collapse { return 0 }
        return transition == .blur ? 0.36 : 0.34
    }

    private func tokenBlur(at index: Int) -> CGFloat {
        guard completedTokenIndices.contains(index), transition == .blur else { return 0 }
        return behavior == .collapse ? 8 : 3
    }

    private func tokenHorizontalOffset(at index: Int) -> CGFloat {
        guard behavior == .collapse,
              transition == .slide,
              completedTokenIndices.contains(index)
        else { return 0 }
        return -18
    }

    private func tokenVerticalOffset(at index: Int) -> CGFloat {
        guard behavior == .collapse,
              transition == .slide,
              completedTokenIndices.contains(index)
        else { return 0 }
        return -3
    }

    private func tokenScale(at index: Int) -> CGFloat {
        guard behavior == .collapse,
              transition == .bounce,
              completedTokenIndices.contains(index)
        else { return 1 }
        return 0.58
    }
}

@available(iOS 16.0, *)
nonisolated private struct SmartCubeHighlightedTokenBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

nonisolated enum SmartCubeHighlightCapsuleGeometry {
    private static let horizontalExpansion: CGFloat = 4
    private static let verticalExpansion: CGFloat = 1

    static func frame(around tokenFrame: CGRect, containerSize: CGSize) -> CGRect {
        let containerWidth = max(containerSize.width, 0)
        let centeredAvailableWidth = max(
            0,
            min(tokenFrame.midX, containerWidth - tokenFrame.midX) * 2
        )
        let width = min(
            tokenFrame.width + horizontalExpansion * 2,
            containerWidth,
            centeredAvailableWidth
        )
        return CGRect(
            x: tokenFrame.midX - width / 2,
            y: tokenFrame.minY - verticalExpansion,
            width: width,
            height: tokenFrame.height + verticalExpansion * 2
        )
    }
}

@available(iOS 16.0, *)
nonisolated private struct SmartCubeMoveCompletedLayoutKey: LayoutValueKey {
    static let defaultValue = false
}

@available(iOS 16.0, *)
private struct SmartCubeMoveFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let collapsesCompletedMoves: Bool

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
        let rows = survivingRows(
            from: makeRows(sizes: sizes, availableWidth: availableWidth),
            subviews: subviews
        )
        let height = rows.reduce(0) { $0 + $1.height }
            + CGFloat(max(rows.count - 1, 0)) * verticalSpacing
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let originalRows = makeRows(sizes: sizes, availableWidth: bounds.width)
        let rows = survivingRows(from: originalRows, subviews: subviews)

        if collapsesCompletedMoves {
            let originalHeight = originalRows.reduce(0) { $0 + $1.height }
                + CGFloat(max(originalRows.count - 1, 0)) * verticalSpacing
            var originalY = bounds.midY - originalHeight / 2
            for row in originalRows {
                var originalX = bounds.minX + max((bounds.width - row.width) / 2, 0)
                for index in row.indices {
                    let size = sizes[index]
                    if subviews[index][SmartCubeMoveCompletedLayoutKey.self] {
                        subviews[index].place(
                            at: CGPoint(
                                x: originalX,
                                y: originalY + (row.height - size.height) / 2
                            ),
                            anchor: .topLeading,
                            proposal: ProposedViewSize(size)
                        )
                    }
                    originalX += size.width + horizontalSpacing
                }
                originalY += row.height + verticalSpacing
            }
        }

        var y = bounds.minY
        for row in rows {
            let indices = activeIndices(in: row, subviews: subviews)
            let width = indices.reduce(CGFloat.zero) { $0 + sizes[$1].width }
                + CGFloat(max(indices.count - 1, 0)) * horizontalSpacing
            var x = bounds.minX + max((bounds.width - width) / 2, 0)

            for index in indices {
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

    private func survivingRows(from rows: [Row], subviews: Subviews) -> [Row] {
        guard collapsesCompletedMoves else { return rows }
        return rows.filter { !activeIndices(in: $0, subviews: subviews).isEmpty }
    }

    private func activeIndices(in row: Row, subviews: Subviews) -> [Int] {
        guard collapsesCompletedMoves else { return row.indices }
        return row.indices.filter { !subviews[$0][SmartCubeMoveCompletedLayoutKey.self] }
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
            row.width += (row.indices.count > 1 ? horizontalSpacing : 0) + size.width
            row.height = max(row.height, size.height)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
#endif
