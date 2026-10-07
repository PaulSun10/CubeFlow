import SwiftUI
import UIKit

/// This mask is resolved beside the positioned Timer, not inside the scroll
/// content's animated layout proposal. It bounds every descendant drawing layer.
struct TimerScrambleExclusionLayer<Content: View>: View {
    let timerTop: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        content().mask(alignment: .top) {
            Rectangle().fill(Color.white, style: FillStyle(antialiased: false))
                .frame(height: max(0, timerTop - 12))
                .frame(maxHeight: .infinity, alignment: .top)
                .transaction { $0.animation = nil }
        }
        .contentShape(TimerScrambleExclusionShape(lowerEdge: max(0, timerTop - 12)))
    }
}

private struct TimerScrambleExclusionShape: Shape {
    let lowerEdge: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width,
            height: min(rect.height, lowerEdge)))
    }
}

enum TimerScrambleFontFit {
    static func height(text: String, width: CGFloat, font: UIFont) -> CGFloat {
        guard width > 0 else { return .infinity }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        return ceil((text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph], context: nil).height)
    }

    static func size(text: String, available: CGSize, maximum: Double,
        design: TimerFontDesignOption, style: TimerFontStyleOption) -> Double {
        guard available.width > 0, available.height > 0 else { return 0 }
        func fits(_ size: Double) -> Bool {
            height(text: text, width: available.width,
                font: design.uiFont(size: CGFloat(size), style: style)) <= available.height
        }
        if fits(maximum) { return maximum }
        // No fixed 45% floor: long scrambles must fit completely, not silently scroll.
        var lower = 0.0, upper = maximum
        for _ in 0..<24 {
            let middle = (lower + upper) / 2
            if fits(middle) { lower = middle } else { upper = middle }
        }
        return lower
    }
}

/// Shrink must fit to the same final coordinate edge that the root mask clips.
/// An upstream controls-height preference can still be stale during layout.
struct TimerScrambleShrinkViewport<Content: View>: View {
    let availableHeight: CGFloat
    let timerTop: CGFloat?
    let coordinateSpace: String
    @ViewBuilder var content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { viewport in
            let height = TimerArrangementLayout.measuredScrollViewportHeight(
                availableHeight: availableHeight, timerTop: timerTop,
                viewportTop: viewport.frame(in: .named(coordinateSpace)).minY)
            content(height)
                .frame(width: viewport.size.width, height: height, alignment: .top)
        }
        .frame(height: TimerArrangementLayout.nonnegativeFinite(availableHeight))
        .transaction { $0.animation = nil }
    }
}

struct TimerFittingScrambleText<Content: View>: View {
    let text: String
    let maximumFontSize: Double
    let design: TimerFontDesignOption
    let style: TimerFontStyleOption
    @ViewBuilder var content: (Double) -> Content
    @ScaledMetric(relativeTo: .body) private var customFontScale: Double = 1

    private var maximumSize: Double {
        if case .custom = style.source { return maximumFontSize * customFontScale }
        return maximumFontSize
    }

    var body: some View {
        GeometryReader { viewport in
            let size = TimerScrambleFontFit.size(text: text, available: viewport.size,
                maximum: maximumSize, design: design, style: style)
            if size > 0 {
                TimerMeasuredFittingScramble(initialSize: size, availableSize: viewport.size, content: content)
                    .id(TimerScrambleFitIdentity(text: text, width: viewport.size.width, height: viewport.size.height,
                        maximum: maximumSize, design: design, style: style))
            }
        }
        .transaction { $0.animation = nil }
        .clipped()
    }
}

private struct TimerScrambleFitIdentity: Hashable {
    let text: String
    let width: CGFloat
    let height: CGFloat
    let maximum: Double
    let design: TimerFontDesignOption
    let style: TimerFontStyleOption
}

private struct TimerFittedScrambleHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct TimerMeasuredFittingScramble<Content: View>: View {
    let initialSize: Double
    let availableSize: CGSize
    @ViewBuilder var content: (Double) -> Content
    @State private var correctedSize: Double?

    private var size: Double { max(0.25, min(initialSize, correctedSize ?? initialSize)) }

    var body: some View {
        content(size)
            .frame(width: availableSize.width)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { rendered in
                    Color.clear.preference(key: TimerFittedScrambleHeight.self, value: rendered.size.height)
                }
            }
            .onPreferenceChange(TimerFittedScrambleHeight.self) { height in
                guard height.isFinite, height > availableSize.height, size > 0.25 else { return }
                // SwiftUI wrapping/rounding can exceed the initial UIFont estimate.
                // Check real intrinsic height and continue shrinking, never scrolling.
                correctedSize = max(0.25, size * Double(availableSize.height / height) * 0.98)
            }
    }
}
