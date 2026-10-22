import XCTest
import SwiftUI
import Combine
@testable import CubeFlow

@MainActor private final class FilterComparisonProbe: ObservableObject {
    @Published var visible = false
    var events: [(String, Double)] = []
    var anchorFrame = CGRect.zero
    func mark(_ name: String) { events.append((name, CACurrentMediaTime())) }
}

private struct FilterComparisonAnchor: ViewModifier {
    let probe: FilterComparisonProbe
    func body(content: Content) -> some View {
        // Toolbar content can live in a separate hosting tree: preferences need
        // not reach this view. Observe the actual UIKit window coordinates.
        content.background(Reader(probe: probe))
    }
    private struct Reader: UIViewRepresentable {
        let probe: FilterComparisonProbe
        func makeUIView(context: Context) -> Anchor { Anchor(probe) }
        func updateUIView(_ view: Anchor, context: Context) { view.capture() }
    }
    private final class Anchor: UIView {
        let probe: FilterComparisonProbe
        init(_ probe: FilterComparisonProbe) { self.probe = probe; super.init(frame: .zero); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError("Not used") }
        override func didMoveToWindow() { super.didMoveToWindow(); capture() }
        override func layoutSubviews() { super.layoutSubviews(); capture() }
        func capture() {
            if let window, bounds.width > 0 { probe.anchorFrame = convert(bounds, to: window) }
        }
    }
}

/// Observe only our content controller and its real native transition coordinator.
/// Do not replace SwiftUI's presentation-controller delegate.
private struct FilterComparisonLifecycle: UIViewControllerRepresentable {
    let probe: FilterComparisonProbe
    func makeUIViewController(context: Context) -> Controller { Controller(probe: probe) }
    func updateUIViewController(_ controller: Controller, context: Context) {}
    final class Controller: UIViewController {
        let probe: FilterComparisonProbe
        init(probe: FilterComparisonProbe) { self.probe = probe; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("Not used") }
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            probe.mark("content-will-disappear")
            if let coordinator = transitionCoordinator {
                probe.mark("coordinator-observed")
                coordinator.animate(alongsideTransition: nil) { [probe] context in
                    probe.mark(context.isCancelled ? "coordinator-cancelled" : "coordinator-complete")
                }
            }
        }
        override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); probe.mark("content-did-disappear") }
    }
}

private struct FilterComparisonSwiftUI: View {
    @ObservedObject var probe: FilterComparisonProbe
    @ObservedObject var filter: CompetitionFilterPresentation
    let independent: Bool
    @State private var region = CompetitionRegionFilter.all
    @State private var events = Set(CompetitionEventFilter.selectableCases)
    @State private var year = CompetitionYearFilter.all
    @State private var status = CompetitionStatusFilter.present
    @State private var top = true
    var body: some View {
        NavigationView {
            Text("Competition Browser").toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if independent {
                        Button("Filter") { probe.visible = true }
                            .modifier(FilterComparisonAnchor(probe: probe))
                            .popover(isPresented: $probe.visible, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                                Button("Close") { probe.visible = false }.frame(width: 290, height: 348)
                                    .background(FilterComparisonLifecycle(probe: probe))
                                    .compatibleClearPresentationBackground().compatiblePopoverCompactAdaptation()
                            }
                    } else {
                        Button("Filter") { filter.open() }.modifier(FilterComparisonAnchor(probe: probe))
                            .competitionFilterPopover(presentation: filter) { visible in
                            CompetitionFiltersPopover(selectedRegion: $region, selectedEvents: $events, selectedYear: $year,
                                selectedStatus: $status, availablePastYears: [2025, 2024], showsTopCubers: $top,
                                appLanguage: "en", showsFilterPopover: visible)
                                .background(FilterComparisonLifecycle(probe: probe))
                                .compatibleClearPresentationBackground().compatiblePopoverCompactAdaptation()
                        }
                    }
                }
            }
        }.navigationViewStyle(.stack)
    }
}

@MainActor final class CompetitionFilterNativeComparisonTests: XCTestCase {
    private final class UIKitPopover: UIViewController {
        let probe: FilterComparisonProbe
        init(_ probe: FilterComparisonProbe) {
            self.probe = probe; super.init(nibName: nil, bundle: nil)
            preferredContentSize = CGSize(width: 290, height: 348); modalPresentationStyle = .popover
        }
        required init?(coder: NSCoder) { fatalError("Not used") }
        override func loadView() { view = UIView(); view.backgroundColor = .secondarySystemGroupedBackground }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated); probe.mark("content-will-disappear")
            if let coordinator = transitionCoordinator {
                probe.mark("coordinator-observed")
                coordinator.animate(alongsideTransition: nil) { [probe] context in
                    probe.mark(context.isCancelled ? "coordinator-cancelled" : "coordinator-complete")
                }
            }
        }
        override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); probe.mark("content-did-disappear") }
    }
    private final class NoAdaptation: NSObject, UIPopoverPresentationControllerDelegate {
        var didDismiss = 0
        func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle { .none }
        func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle { .none }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { didDismiss += 1 }
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Native comparison did not reach the requested lifecycle boundary")
    }
    func testIndependentSwiftUIPopoverUIKitPopoverAndActualFilterNativeDismissals() async throws {
        var samples: [[String: Any]] = []
        var referenceAnchor: CGRect?
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for variant in ["independent-swiftui", "uikit", "cubeflow-filter"] {
            let probe = FilterComparisonProbe(), filter = CompetitionFilterPresentation(), delegate = NoAdaptation()
            let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            let root: UIViewController
            let anchor = UIButton(type: .system); anchor.setTitle("Filter", for: .normal)
            if variant == "uikit" {
                let content = UIViewController(); content.view.backgroundColor = .systemBackground
                content.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: anchor)
                root = UINavigationController(rootViewController: content)
            } else {
                root = UIHostingController(rootView: FilterComparisonSwiftUI(probe: probe, filter: filter,
                    independent: variant == "independent-swiftui"))
            }
            window.rootViewController = root; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            window.layoutIfNeeded()
            for cycle in 0..<4 {
                if variant == "uikit" {
                    let popover = UIKitPopover(probe)
                    let presentation = try XCTUnwrap(popover.popoverPresentationController)
                    let reference = try XCTUnwrap(referenceAnchor)
                    presentation.sourceView = root.view
                    presentation.sourceRect = root.view.convert(reference, from: window)
                    presentation.permittedArrowDirections = .up; presentation.delegate = delegate
                    root.present(popover, animated: true)
                } else {
                    try await wait { probe.anchorFrame.width > 0 }
                    if referenceAnchor == nil { referenceAnchor = probe.anchorFrame }
                    if variant == "independent-swiftui" { probe.visible = true }
                    else { filter.open() }
                }
                try await wait { root.presentedViewController != nil && root.presentedViewController?.isBeingPresented == false }
                let presented = try XCTUnwrap(root.presentedViewController)
                XCTAssertNotNil(presented.popoverPresentationController)
                let surface = presented.presentationController?.presentedView ?? presented.view!
                let frame = surface.convert(surface.bounds, to: window)
                let contentBounds = presented.view.bounds.size
                let presentation = try XCTUnwrap(presented.popoverPresentationController)
                let sourceFrame = presentation.sourceView.map { $0.convert(presentation.sourceRect, to: window) } ?? probe.anchorFrame
                XCTAssertGreaterThan(sourceFrame.width, 0)
                XCTAssertEqual(sourceFrame, referenceAnchor, "Compare the same actual anchor rectangle")
                probe.events = []; probe.mark("dismiss-intent")
                if variant == "uikit" { root.dismiss(animated: true) { probe.mark("uikit-dismiss-completion") } }
                else if variant == "independent-swiftui" { probe.visible = false }
                else { filter.close() }
                try await wait { root.presentedViewController == nil && probe.events.contains { $0.0 == "content-did-disappear" } }
                if variant == "cubeflow-filter" { try await wait { !filter.isDismissing } }
                let start = try XCTUnwrap(probe.events.first?.1)
                let timing = Dictionary(probe.events.map { ($0.0, ($0.1 - start) * 1000) }, uniquingKeysWith: { _, latest in latest })
                XCTAssertNotNil(timing["coordinator-complete"], "Measure the actual transition coordinator, not only a binding")
                XCTAssertNil(timing["coordinator-cancelled"])
                samples.append(["variant": variant, "cycle": cycle, "warmup": cycle == 0,
                    "runtime": UIDevice.current.systemVersion, "nativeOwner": String(describing: type(of: presented)),
                    "modalStyle": presented.modalPresentationStyle.rawValue,
                    "adaptiveStyle": presented.presentationController?.presentationStyle.rawValue ?? -999,
                    "window": [window.bounds.width, window.bounds.height], "scale": window.screen.scale,
                    "surface": [frame.minX, frame.minY, frame.width, frame.height],
                    "contentBounds": [contentBounds.width, contentBounds.height],
                    "sourceObservedFrom": presentation.sourceView == nil ? "swiftui-button-layout" : "native-source-rect",
                    "source": [sourceFrame.minX, sourceFrame.minY, sourceFrame.width, sourceFrame.height],
                    "timingMS": timing, "programmaticDelegateDidDismiss": delegate.didDismiss])
                print("[FilterNativeComparison] \(variant) cycle=\(cycle) frame=\(frame) timings=\(timing)")
            }
        }
        XCTAssertEqual(samples.count, 12)
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys]),
            uniformTypeIdentifier: "public.json")
        attachment.name = "independent-native-filter-comparison-" + UIDevice.current.systemVersion
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
