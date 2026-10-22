import XCTest
import SwiftUI
import Combine
@testable import CubeFlow

@MainActor final class CompetitionPresentationBoundaryTests: XCTestCase {
    @MainActor private final class State: ObservableObject {
        @Published var presented = false
        @Published var anchorIdentity = 0
        let filter = CompetitionFilterPresentation()
        var disappearances = 0
    }
    private struct Surface: View {
        @ObservedObject var state: State
        let filter: Bool
        var body: some View {
            if filter {
                Button("Filter") { state.filter.open() }
                    .competitionFilterPopover(presentation: state.filter) { visible in
                        Button("Close") { visible.wrappedValue = false }.padding().frame(width: 290)
                            .compatiblePopoverCompactAdaptation()
                    }
                    .id(state.anchorIdentity)
            } else {
                Color.white.ignoresSafeArea().background {
                    CompetitionNativePresentation(isPresented: $state.presented, style: .results) { dismiss in
                        CompetitionResultBackdrop().ignoresSafeArea().onTapGesture(perform: dismiss)
                    }
                }
                .onDisappear { state.disappearances += 1 }
            }
        }
    }
    private func mount<V: View>(_ view: V) throws -> (UIWindow, UIHostingController<V>) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        return (window, host)
    }
    private func wait(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Native presentation did not reach the requested phase")
    }
    func testResultsModalCoversWholeWindowBlocksEveryBackgroundRegionAndRestoresIt() async throws {
        let state = State()
        let (window, host) = try mount(Surface(state: state, filter: false))
        defer { window.isHidden = true; window.rootViewController = nil }
        state.presented = true
        try await wait { host.presentedViewController != nil && host.presentedViewController?.view.alpha == 1 }
        let modal = try XCTUnwrap(host.presentedViewController)
        XCTAssertEqual(modal.presentationController?.frameOfPresentedViewInContainerView, window.bounds)
        XCTAssertFalse(modal.presentationController?.shouldRemovePresentersView ?? true)
        XCTAssertEqual(state.disappearances, 0, "Showing results must not stop the underlying Live lifecycle")
        for point in [CGPoint(x: 10, y: 10), .init(x: 380, y: 10), .init(x: 10, y: 830),
                      .init(x: 380, y: 830), .init(x: 195, y: 422)] {
            let hit = try XCTUnwrap(window.hitTest(point, with: nil))
            XCTAssertTrue(hit === modal.view || hit.isDescendant(of: modal.view), "Touch-through at \(point)")
        }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "uniform-scene-wide-dimming"; attachment.lifetime = .keepAlways; add(attachment)
        state.presented = false
        try await wait { host.presentedViewController == nil }
        let hit = try XCTUnwrap(window.hitTest(CGPoint(x: 195, y: 422), with: nil))
        XCTAssertTrue(hit === host.view || hit.isDescendant(of: host.view))
    }
    func testNativeDetailBackDismissesCardThenNavigatesExactlyOnce() async throws {
        try await exerciseNativeDetailBack(rebuildToolbar: false)
    }
    func testNativeDetailBackSurvivesToolbarRebuild() async throws {
        try await exerciseNativeDetailBack(rebuildToolbar: true)
    }
    func testDetailWithoutResultCardKeepsOriginalNativeBack() async throws {
        try await exerciseNativeDetailBack(rebuildToolbar: false, withoutCard: true)
    }
    private func exerciseNativeDetailBack(rebuildToolbar: Bool, withoutCard: Bool = false) async throws {
        let state = State()
        let root = UIHostingController(rootView: Text("Competitions"))
        root.title = "Competitions"
        let detail = UIHostingController(rootView: Surface(state: state, filter: false))
        detail.title = "Competition"
        detail.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Filter", style: .plain, target: nil, action: nil)
        let navigation = UINavigationController(rootViewController: root)
        navigation.pushViewController(detail, animated: false)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = navigation; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await wait { detail.view.window != nil }
        navigation.view.layoutIfNeeded()
        let bar = navigation.navigationBar
        let controls = descendants(bar).compactMap { $0 as? UIControl }.map {
            let parents = sequence(first: $0.superview, next: { $0?.superview }).compactMap { $0 }.prefix(8).map {
                "\(type(of: $0)) bounds=\($0.bounds) hidden=\($0.isHidden) alpha=\($0.alpha)"
            }
            return "\(type(of: $0)) frame=\($0.convert($0.bounds, to: bar)) events=\($0.allControlEvents.rawValue) hidden=\($0.isHidden) alpha=\($0.alpha) parents=\(parents)"
        }
        let description = "root=\(window.rootViewController === navigation) source=\(navigation.topViewController === detail) barHidden=\(bar.isHidden) back=\(bar.backItem?.title ?? "nil") hides=\(String(describing: bar.topItem?.hidesBackButton)) left=\(bar.topItem?.leftBarButtonItems?.count ?? 0) controls=\(controls)"
        print("[NativeBackMetadata] \(description)")
        let diagnostic = XCTAttachment(string: description); diagnostic.name = "native-back-public-metadata"
        diagnostic.lifetime = .keepAlways; add(diagnostic)
        let target = try XCTUnwrap(CompetitionDetailBackTarget.find(from: detail.view))
        XCTAssertFalse(target.frame(in: window).isEmpty)
        let originalFrame = target.frame(in: window)
        let sample = CGPoint(x: originalFrame.midX + 12, y: originalFrame.midY)
        let originalBackColor = pixel(in: window, at: sample)
        if withoutCard {
            XCTAssertNil(navigation.presentedViewController)
            XCTAssertFalse(descendants(window).contains { $0.accessibilityIdentifier == "competition-detail-back" })
            let frame = target.frame(in: window)
            let hit = try XCTUnwrap(window.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil))
            XCTAssertTrue(hit.isDescendant(of: bar))
            var view: UIView? = hit
            while view != nil && !(view is UIControl) { view = view?.superview }
            let nativeBack = try XCTUnwrap(view as? UIControl)
            nativeBack.sendActions(for: nativeBack.allControlEvents.contains(.touchUpInside) ? .touchUpInside : .primaryActionTriggered)
            try await wait { navigation.viewControllers.count == 1 }
            XCTAssertTrue(navigation.topViewController === root)
            XCTAssertNil(navigation.presentedViewController)
            XCTAssertFalse(state.presented)
            return
        }
        state.presented = true
        try await wait { navigation.presentedViewController != nil && !(navigation.presentedViewController?.isBeingPresented ?? true) }
        let modal = try XCTUnwrap(navigation.presentedViewController)
        let back = try XCTUnwrap(descendants(modal.view).compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "competition-detail-back" })
        if rebuildToolbar {
            detail.navigationItem.setHidesBackButton(true, animated: false)
            bar.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 30_000_000)
            detail.navigationItem.setHidesBackButton(false, animated: false)
            bar.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 30_000_000)
            let current = try XCTUnwrap(CompetitionDetailBackTarget.find(from: detail.view))
            print("[BackRebuild] captured=\(target.frame(in: window)) current=\(current.frame(in: window))")
            XCTAssertEqual(target.frame(in: window), current.frame(in: window))
            modal.view.setNeedsLayout()
            modal.view.layoutIfNeeded()
        }
        XCTAssertFalse(back.isHidden)
        XCTAssertFalse(back.frame.isEmpty)
        XCTAssertTrue(back.isAccessibilityElement)
        let dimmedBackColor = pixel(in: window, at: sample)
        XCTAssertLessThan(dimmedBackColor.reduce(0, +), originalBackColor.reduce(0, +) - 20,
            "The accepted fallback is uniform dimming, not a special Back aperture")
        back.sendActions(for: .touchDown)
        XCTAssertTrue(descendants(bar).compactMap { $0 as? UIControl }.contains { $0.isHighlighted },
            "Forward press state to the real native Back, not a drawn replacement")
        back.sendActions(for: .touchCancel)
        let frame = target.frame(in: window)
        let point = CGPoint(x: frame.midX, y: frame.midY)
        XCTAssertTrue(window.hitTest(point, with: nil) === back)
        let blockedPoint = navigation.navigationBar.convert(CGPoint(x: navigation.navigationBar.bounds.width - 20,
            y: navigation.navigationBar.bounds.midY), to: window)
        let blocked = try XCTUnwrap(window.hitTest(blockedPoint, with: nil))
        XCTAssertFalse(blocked.isDescendant(of: navigation.navigationBar), "Only native Back, not other toolbar controls, is enabled")
        back.sendActions(for: .touchUpInside)
        back.sendActions(for: .touchUpInside)
        try await wait { navigation.presentedViewController == nil && navigation.viewControllers.count == 1 }
        XCTAssertTrue(navigation.topViewController === root)
        XCTAssertFalse(state.presented)
    }

    private func pixel(in window: UIWindow, at point: CGPoint) -> [Double] {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let cg = image.cgImage else { return [] }
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = CGContext(data: &bytes, width: cg.width, height: cg.height, bitsPerComponent: 8,
            bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let offset = (Int(point.y) * cg.width + Int(point.x)) * 4
        return (0..<3).map { Double(bytes[offset + $0]) }
    }

    func testNativeResultTransitionsUseHistoricalDurations() async throws {
        let state = State()
        let (window, host) = try mount(Surface(state: state, filter: false))
        defer { window.isHidden = true; window.rootViewController = nil }
        state.presented = true
        try await wait { host.presentedViewController?.transitionCoordinator != nil }
        let modal = try XCTUnwrap(host.presentedViewController)
        let duration = try XCTUnwrap(modal.transitionCoordinator?.transitionDuration)
        XCTAssertEqual(duration, UIAccessibility.isReduceMotionEnabled ? 0 : 0.18, accuracy: 0.001)
        try await wait { !modal.isBeingPresented }
        state.presented = false
        try await wait { modal.isBeingDismissed }
        XCTAssertEqual(modal.transitionCoordinator?.transitionDuration ?? -1,
            UIAccessibility.isReduceMotionEnabled ? 0 : 0.16, accuracy: 0.001)
        try await wait { host.presentedViewController == nil }
    }
    private func descendants(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(descendants) }
    func testResultRequestDuringForeignDismissalResumesAfterNativeCompletion() async throws {
        let (window, host) = try mount(Color.white)
        defer { window.isHidden = true; window.rootViewController = nil }
        let foreign = UIViewController()
        try await wait { host.view.window != nil }
        await withCheckedContinuation { continuation in
            host.present(foreign, animated: false) { continuation.resume() }
        }
        foreign.dismiss(animated: true)
        XCTAssertTrue(foreign.isBeingDismissed)
        let coordinator = CompetitionPresentationCoordinator()
        coordinator.anchor = host.view
        coordinator.makeContent = { AnyView(Color.black.opacity(0.42).ignoresSafeArea()) }
        coordinator.desired = true
        coordinator.reconcile()
        try await wait { host.presentedViewController != nil && host.presentedViewController !== foreign }
        XCTAssertNotNil(coordinator.host, "A valid request must not disappear behind another modal's dismissal")
        coordinator.desired = false
        coordinator.reconcile()
        try await wait { host.presentedViewController == nil }
    }
    func testWithdrawnResultRequestDoesNotReappearAfterForeignDismissal() async throws {
        let (window, host) = try mount(Color.white)
        defer { window.isHidden = true; window.rootViewController = nil }
        let foreign = UIViewController()
        try await wait { host.view.window != nil }
        await withCheckedContinuation { continuation in
            host.present(foreign, animated: false) { continuation.resume() }
        }
        foreign.dismiss(animated: true)
        let coordinator = CompetitionPresentationCoordinator()
        coordinator.anchor = host.view
        coordinator.makeContent = { AnyView(Color.black) }
        coordinator.desired = true
        coordinator.reconcile()
        coordinator.desired = false
        coordinator.reconcile()
        try await wait { host.presentedViewController == nil }
        await Task.yield()
        XCTAssertNil(coordinator.host)
    }
    func testOriginalPopoverQueuesReopenDuringNativeDismissalWithoutDelayOrDuplicateHost() async throws {
        let state = State()
        let (window, host) = try mount(Surface(state: state, filter: true))
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<3 {
            state.filter.open()
            try await wait { host.presentedViewController != nil && !(host.presentedViewController?.isBeingPresented ?? true) }
            let original = try XCTUnwrap(host.presentedViewController)
            XCTAssertNotNil(original.popoverPresentationController)
            state.filter.close()
            try await wait { original.isBeingDismissed }
            state.filter.open()
            try await wait { host.presentedViewController != nil && host.presentedViewController !== original && !(host.presentedViewController?.isBeingPresented ?? true) }
            XCTAssertNil(host.presentedViewController?.presentedViewController)
            XCTAssertTrue(state.filter.isPresented)
            state.filter.close()
            try await wait { host.presentedViewController == nil }
        }
    }
    func testFilterRecoversWhenNativeDismissalPrecedesBindingAcknowledgement() async throws {
        let state = State()
        let (window, host) = try mount(Surface(state: state, filter: true))
        defer { window.isHidden = true; window.rootViewController = nil }
        state.filter.open()
        try await wait { host.presentedViewController != nil && !(host.presentedViewController?.isBeingPresented ?? true) }
        let original = try XCTUnwrap(host.presentedViewController)
        original.dismiss(animated: false)
        try await wait { host.presentedViewController == nil }
        // Models an outside/parent dismissal acknowledgement delivered after the
        // native content has disappeared, rather than the in-content X path.
        state.filter.frameworkChanged(false, generation: state.filter.generation)
        state.filter.open()
        try await wait { host.presentedViewController != nil }
        XCTAssertTrue(state.filter.isPresented)
        XCTAssertFalse(state.filter.isDismissing)
        state.filter.close()
        try await wait { host.presentedViewController == nil }
    }
    func testFilterBoundedTwentyCycleStressWithQueuedAndExternalDismissals() async throws {
        let state = State()
        let (window, host) = try mount(Surface(state: state, filter: true))
        defer { window.isHidden = true; window.rootViewController = nil }
        for index in 0..<20 {
            state.filter.open()
            try await wait { host.presentedViewController != nil && !(host.presentedViewController?.isBeingPresented ?? true) }
            let original = try XCTUnwrap(host.presentedViewController)
            XCTAssertNil(original.presentedViewController, "Duplicate presentation at cycle \(index)")
            if index.isMultiple(of: 4) {
                original.dismiss(animated: false)
                try await wait { host.presentedViewController == nil }
                state.filter.frameworkChanged(false, generation: state.filter.generation)
            } else {
                state.filter.close()
                XCTAssertTrue(state.filter.isDismissing, "Queue before the nonanimated native dismissal completes")
                state.filter.open()
                try await wait { host.presentedViewController != nil && host.presentedViewController !== original && !(host.presentedViewController?.isBeingPresented ?? true) }
                XCTAssertNil(host.presentedViewController?.presentedViewController)
                state.filter.close()
                try await wait { host.presentedViewController == nil }
            }
            XCTAssertFalse(state.filter.isDismissing, "Permanent lockout at cycle \(index)")
        }
    }
    func testFilterUsesNativeTransitionsWithoutCustomSurfaceAnimations() async throws {
        let state = State()
        let (window, host) = try mount(Surface(state: state, filter: true))
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<3 {
            let requested = CACurrentMediaTime()
            state.filter.open()
            try await wait { host.presentedViewController?.presentationController?.presentedView?.window != nil }
            XCTAssertLessThan(CACurrentMediaTime() - requested, 0.3, "Do not delay mounting behind a synthetic animation")
            let modal = try XCTUnwrap(host.presentedViewController)
            let coordinator = try XCTUnwrap(modal.transitionCoordinator)
            XCTAssertTrue(coordinator.isAnimated, "UIKit, not a custom layer animation, must own presentation")
            XCTAssertGreaterThan(coordinator.transitionDuration, 0)
            XCTAssertNil(modal.presentationController?.presentedView?.layer.animation(forKey: "competition-filter-surface"))
            try await wait { !modal.isBeingPresented }
            XCTAssertTrue(modal.view.isUserInteractionEnabled)
            state.filter.close()
            try await wait { modal.isBeingDismissed }
            XCTAssertTrue(try XCTUnwrap(modal.transitionCoordinator).isAnimated)
            XCTAssertNil(modal.presentationController?.presentedView?.layer.animation(forKey: "competition-filter-surface"))
            try await wait { host.presentedViewController == nil && !state.filter.isDismissing }
        }
    }
    func testFilterQueuedReopenSurvivesParentReconstructionDuringDismissal() async throws {
        let state = State()
        let (window, host) = try mount(Surface(state: state, filter: true))
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<3 {
            state.filter.open()
            try await wait { host.presentedViewController != nil && !(host.presentedViewController?.isBeingPresented ?? true) }
            let original = try XCTUnwrap(host.presentedViewController)
            state.filter.close()
            XCTAssertTrue(state.filter.isDismissing)
            // Queue before native completion, including a nonanimated dismissal
            // whose transient UIKit isBeingDismissed phase cannot be polled.
            state.filter.open()
            state.anchorIdentity += 1
            try await wait { !state.filter.isDismissing && state.filter.isPresented }
            try await wait { host.presentedViewController != nil && host.presentedViewController !== original && !(host.presentedViewController?.isBeingPresented ?? true) }
            XCTAssertNil(host.presentedViewController?.presentedViewController)
            state.filter.close()
            try await wait { host.presentedViewController == nil }
        }
    }
    func testDismissalAcknowledgementCannotCancelNewPopoverGeneration() {
        let state = CompetitionFilterPresentation()
        state.open()
        let old = state.generation
        state.contentMounted(generation: old)
        state.close()
        state.open()
        XCTAssertFalse(state.isPresented, "Do not overlap the dismissing native presentation")
        state.dismissalFinished(generation: old)
        XCTAssertTrue(state.isPresented)
        XCTAssertGreaterThan(state.generation, old)
        state.frameworkChanged(false, generation: old)
        XCTAssertTrue(state.isPresented, "An old dismissal must not cancel newer intent")
    }

    func testNativeBindingRejectsLateAcknowledgementWithoutClosingNewHost() {
        let state = CompetitionFilterPresentation()
        var native = CompetitionFilterNativeBindingState()
        state.open()
        let old = state.generation
        native.request(true, generation: old)
        state.contentMounted(generation: old)
        state.close()
        native.request(false, generation: old)
        state.open()
        state.dismissalFinished(generation: old)
        native.request(true, generation: state.generation)
        native.acknowledge(false, generation: old, currentGeneration: state.generation)
        XCTAssertTrue(native.presented, "The old binding must not close the new native popover")
        XCTAssertNil(native.dismissedGeneration)
        XCTAssertTrue(state.isPresented)
        native.acknowledge(false, generation: state.generation, currentGeneration: state.generation)
        XCTAssertFalse(native.presented)
        XCTAssertEqual(native.dismissedGeneration, state.generation)
    }

    func testRapidReopenHasNoCooldownAfterRealNativeDismissal() async throws {
        let state = State()
        let (window, host) = try mount(Surface(state: state, filter: true))
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<3 {
            state.filter.open()
            try await wait { host.presentedViewController != nil && !(host.presentedViewController?.isBeingPresented ?? true) }
            let original = try XCTUnwrap(host.presentedViewController)
            let old = state.filter.generation
            state.filter.close()
            state.filter.open()
            state.filter.open() // Repeated intent must not create another host.
            XCTAssertEqual(state.filter.generation, old)
            try await wait { !state.filter.isDismissing && state.filter.isPresented }
            let ready = CACurrentMediaTime()
            try await wait {
                host.presentedViewController !== original && host.presentedViewController?.view.window != nil
            }
            let mounted = CACurrentMediaTime() - ready
            print("[FilterRapidReopen] native completion to mounted content: \(mounted * 1000)ms")
            XCTAssertLessThan(mounted, 0.3, "No app cooldown after native dismissal")
            XCTAssertEqual(state.filter.generation, old + 1)
            XCTAssertNil(host.presentedViewController?.presentedViewController)
            state.filter.close()
            try await wait { host.presentedViewController == nil }
        }
    }
    func testNativeCompletionBeforeBindingAcknowledgementCannotDeadlockFilter() {
        let state = CompetitionFilterPresentation()
        state.open()
        let old = state.generation
        state.contentMounted(generation: old)
        // Native completion and SwiftUI binding acknowledgement are distinct
        // event sources. Do not require one fixed callback order.
        state.dismissalFinished(generation: old)
        state.frameworkChanged(false, generation: old)
        state.open()
        XCTAssertFalse(state.isDismissing)
        XCTAssertTrue(state.isPresented)
        XCTAssertGreaterThan(state.generation, old)
    }
    func testCancelledNativeDismissalRestoresActivePopoverAndRejectsOldAcknowledgement() {
        let state = CompetitionFilterPresentation()
        state.open()
        let old = state.generation
        state.contentMounted(generation: old)
        state.nativeDismissalBegan(generation: old)
        state.nativeDismissalCancelled(generation: old)
        XCTAssertTrue(state.isPresented)
        XCTAssertFalse(state.isDismissing)
        XCTAssertGreaterThan(state.generation, old)
        state.frameworkChanged(false, generation: old)
        state.dismissalFinished(generation: old)
        XCTAssertTrue(state.isPresented)
        state.close()
        state.dismissalFinished(generation: state.generation)
        XCTAssertFalse(state.isPresented)
    }
    func testClosedIntentWinsWhilePopoverDismisses() {
        let state = CompetitionFilterPresentation()
        state.open()
        let old = state.generation
        state.contentMounted(generation: old)
        state.close(); state.open(); state.close()
        state.dismissalFinished(generation: old)
        XCTAssertFalse(state.isPresented)
        XCTAssertFalse(state.isDismissing)
    }
    func testAllResultsPaddingLeavesExtraWidthBetweenFixedColumns() async throws {
        for minimum in [CGFloat(220), 300, 550] {
            let state = GeometryState()
            let (window, _) = try mount(TableSurface(state: state, minimum: minimum))
            defer { window.isHidden = true; window.rootViewController = nil }
            // This fixture omits an explicit viewport. Wait for its existing
            // geometry preference to reach the content, not just the first fit.
            try await wait {
                guard let table = state.frames["table"], let viewport = state.frames["viewport"] else { return false }
                return abs(table.width - max(viewport.width, minimum)) < 0.5
            }
            let table = try XCTUnwrap(state.frames["table"])
            let viewport = try XCTUnwrap(state.frames["viewport"])
            XCTAssertEqual(viewport.minX, 22, accuracy: 0.5)
            XCTAssertEqual(390 - viewport.maxX, 22, accuracy: 0.5)
            XCTAssertEqual(table.width, max(346, minimum), accuracy: 0.5)
            XCTAssertEqual(state.frames["round"]?.width ?? 0, 60, accuracy: 0.5)
            XCTAssertEqual(state.frames["score"]?.width ?? 0, 80, accuracy: 0.5)
            XCTAssertEqual(state.frames["score"]?.maxX ?? 0, table.maxX, accuracy: 0.5)
        }
    }
    func testTopDisclosureSurvivesHostingGraphRecyclingAndUpdatesInsideIt() async throws {
        let store = CompetitionTopCuberDisclosureStore()
        let model = store.disclosure(for: "Beijing")
        XCTAssertTrue(model === store.disclosure(for: "Beijing"))
        XCTAssertFalse(model === store.disclosure(for: "Other"))
        let values = try XCTUnwrap(CompetitionService.decodeCompetitionTopCuberPreviews(
            CompetitionPhysicalRegressionFixtures.beijingWCIF,
            eventIDs: CompetitionPhysicalRegressionFixtures.beijing.eventIDs))
        var visible: CompetitionTopCubersVisibility?
        let root = CompetitionPersistentTopCubers(previews: values, language: "en", disclosure: model) { person in
            Text(person.name).font(.body).padding(8)
        }.environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
            .onPreferenceChange(CompetitionTopCubersVisibilityKey.self) { visible = $0 }
        let (window, host) = try mount(root)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await wait { visible != nil }
        let collapsed = try XCTUnwrap(visible?.collapsed)
        XCTAssertLessThan(collapsed, values.count)
        model.expanded = true
        try await wait { visible?.visible == values.count }
        window.rootViewController = nil
        visible = nil
        window.rootViewController = UIHostingController(rootView: root)
        try await wait { visible?.visible == values.count }
        XCTAssertTrue(model.expanded)
        model.expanded = false
        try await wait { visible?.visible == collapsed }
        _ = host
    }
    private final class GeometryState: ObservableObject { var frames: [String: CGRect] = [:] }
    private struct Frames: PreferenceKey {
        static var defaultValue: [String: CGRect] = [:]
        static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, b in b }) }
    }
    private struct TableSurface: View {
        let state: GeometryState
        let minimum: CGFloat
        private func measure(_ id: String) -> some View {
            GeometryReader { proxy in Color.clear.preference(key: Frames.self, value: [id: proxy.frame(in: .named("table"))]) }
        }
        var body: some View {
            CompetitionAdaptiveResultsTable(minimumWidth: minimum) {
              VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("Round").frame(width: 60).background(measure("round"))
                    Spacer(minLength: 0)
                    Text("1:23:45.67").frame(width: 80).background(measure("score"))
                }.background(measure("table"))
                Divider()
              }
            }.background(measure("viewport")).padding(22)
                .coordinateSpace(name: "table")
                .onPreferenceChange(Frames.self) { state.frames = $0 }
        }
    }
}
