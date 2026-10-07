import Foundation
import Testing
import UIKit
import SwiftUI
@testable import CubeFlow

@Suite("Physical acceptance corrections", .serialized)
@MainActor struct PhysicalAcceptanceCorrectionTests {
    @Test func strokeLevelsPreserveStoredAppearance() {
        #expect(DiagramStrokeStyle.allCases.count == 3)
        #expect(DiagramStrokeStyle(rawValue: "thin") == .thin)
        #expect(DiagramStrokeStyle(rawValue: "thick") == .medium)
        #expect(DiagramStrokeStyle(rawValue: "heavy") == .thick)
        #expect(DiagramStrokeStyle.thin.scale == 1)
        #expect(DiagramStrokeStyle.medium.scale == 1.6)
        #expect(DiagramStrokeStyle.thick.scale == 2.6)
        #expect(DiagramStrokeStyle.medium.localizationKey == "settings.diagram_stroke_medium")
    }

    @Test func viewportUsesItsActualOriginIncludingPlacementAndSafeArea() {
        for contentHeight in [180.0, 720.0, 8_000.0] {
            for timerTop in [100.0, 245.0, 370.0] {
                for actualTop in [70.0, 94.0, 130.0] {
                    let height = TimerArrangementLayout.measuredScrollViewportHeight(
                        availableHeight: 500, timerTop: timerTop, viewportTop: actualTop)
                    let offset = TimerArrangementLayout.scrambleTop(
                        availableHeight: height, contentHeight: contentHeight, normalizedPosition: 0.75)
                    let viewport = TimerArrangementLayout.scrollViewportHeight(availableHeight: height, topOffset: offset)
                    #expect(offset + viewport == height)
                    if actualTop < timerTop - 12 { #expect(actualTop + height <= timerTop - 12) }
                    else { #expect(height == 0) }
                }
            }
        }
        #expect(TimerArrangementLayout.measuredScrollViewportHeight(availableHeight: 139, timerTop: 245, viewportTop: 110) == 123)
        #expect(TimerArrangementLayout.measuredScrollViewportHeight(availableHeight: 139, timerTop: nil, viewportTop: 110) == 139)
        #expect(TimerArrangementLayout.measuredScrollViewportHeight(availableHeight: 139, timerTop: .nan, viewportTop: 110) == 0)
    }

    @Test func rainStopsBirthsWithoutRemovingOrFadingParticles() {
        let view = SwiftConfettiView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.applyPreset(.rain)
        view.startConfetti()
        let layer = view.layer.sublayers?.first as? CAEmitterLayer
        let cells = layer?.emitterCells
        let drain = view.stopEmissionAndDrain()
        #expect(drain == 10.5)
        #expect(layer?.birthRate == 0 && layer?.opacity == 1)
        #expect(layer?.animation(forKey: "fadeOut") == nil)
        #expect(layer?.animation(forKey: "initialBurst") == nil)
        #expect(layer?.superlayer === view.layer)
        #expect(cells?.map(\.lifetime) == layer?.emitterCells?.map(\.lifetime))
        #expect(layer?.animationKeys()?.contains(where: { $0.hasPrefix("gravity_") }) == true)
        view.cancelConfetti()
        #expect(view.layer.sublayers?.isEmpty != false)
    }

    @Test func longScrollContentIsActuallyRasterClippedBeforeTimer() throws {
        guard #available(iOS 16.0, *) else { return }
        for contentHeight in [720.0, 8_000.0] {
            let content = ZStack(alignment: .top) {
                Color.white
                TimerScrambleScrollViewport(availableHeight: 139, timerTop: 245, coordinateSpace: "test-timer") { height in
                    // Deliberately overflowing child models arbitrary-length content,
                    // including an outgoing drawing transition outside its own layout.
                    Color(red: 1, green: 0, blue: 0).frame(height: contentHeight).frame(height: height, alignment: .top)
                }
                .offset(y: 110)
            }
            .frame(width: 390, height: 600)
            .coordinateSpace(name: "test-timer")
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            let image = try #require(renderer.uiImage?.cgImage)
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = try #require(CGContext(data: &pixels, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let redRows = (0..<image.height).filter { y in
                let p = (y * image.width + 195) * 4
                return pixels[p] > 240 && pixels[p + 1] < 20
            }
            print("[ViewportRaster] red_rows=\(redRows.first ?? -1)...\(redRows.last ?? -1) image=\(image.width)x\(image.height)")
            let before = (220 * image.width + 195) * 4
            #expect(pixels[before] > 240 && pixels[before + 1] < 20)
            for y in 234..<300 {
                let p = (y * image.width + 195) * 4
                #expect(pixels[p] > 240 && pixels[p + 1] > 240 && pixels[p + 2] > 240)
            }
        }
    }

    @Test func celebrationDrainsThenCleansAndCancellationDoesNotFinish() async throws {
        let view = SwiftConfettiView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let lifecycle = TimerPBConfettiLifecycle()
        view.applyPreset(.rain)
        view.intensity = 0.005
        view.startConfetti()
        var finished = 0
        lifecycle.start(view: view, emissionDuration: 0.01) { finished += 1 }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(finished == 0 && view.layer.sublayers?.isEmpty == false)
        try await Task.sleep(nanoseconds: 220_000_000)
        #expect(finished == 1 && view.layer.sublayers?.isEmpty != false && lifecycle.task == nil)
        for _ in 0..<4 {
            view.startConfetti()
            lifecycle.start(view: view, emissionDuration: 0.01) { finished += 1 }
            lifecycle.cancel()
            #expect(view.layer.sublayers?.isEmpty != false && lifecycle.task == nil)
        }
        try await Task.sleep(nanoseconds: 220_000_000)
        #expect(finished == 1)
    }

    @Test func poolOverlapsProducersJoinsRefillAndBoundsWork() async throws {
        let gate = DispatchSemaphore(value: 0)
        let counter = GenerationCounter()
        let pool = FTOGenerationPool(capacity: 4, producerCount: 2) { _ in
            let id = counter.begin()
            gate.wait()
            counter.end()
            return "fixture-\(id)"
        }
        pool.prewarm()
        for _ in 0..<100 where counter.started < 2 { try await Task.sleep(nanoseconds: 5_000_000) }
        #expect(counter.started == 2 && counter.maximumActive == 2)
        let consumer = Task.detached { pool.take() }
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(counter.started == 2) // Empty consumer joins these solves, not a third one.
        for _ in 0..<6 { gate.signal() }
        let first = try #require(await consumer.value)
        for _ in 0..<100 where pool.count < 4 { try await Task.sleep(nanoseconds: 5_000_000) }
        #expect(pool.count == 4 && counter.started == 5 && counter.maximumActive == 2)
        let cached = try (0..<4).map { _ in try #require(pool.take()) }
        #expect(Set([first] + cached).count == 5)
        for _ in 0..<20 { gate.signal() }
        for _ in 0..<100 where pool.count < 4 { try await Task.sleep(nanoseconds: 5_000_000) }
        #expect(pool.count == 4 && counter.started == 9)
    }

    @Test func failedPoolReturnsNilWithoutUnboundedRetries() async {
        let pool = FTOGenerationPool { _ in nil }
        let result = await Task.detached { pool.take() }.value
        #expect(result == nil && pool.count == 0)
        pool.prewarm()
        #expect(pool.count == 0)
    }

    @Test func laterDemandCanRecoverFromFailedGeneration() async {
        let counter = GenerationCounter()
        let pool = FTOGenerationPool(capacity: 1, producerCount: 1) { _ in
            let id = counter.begin()
            counter.end()
            return id == 1 ? nil : "recovered-\(id)"
        }
        let first = await Task.detached(priority: .userInitiated) { pool.take() }.value
        #expect(first == nil && counter.started == 1)
        let second = await Task.detached(priority: .userInitiated) { pool.take() }.value
        #expect(second == "recovered-2")
    }

    @Test func actualFTOReserveAndSustainedDeliveryRemainIndependent() async throws {
        FTOScrambler.prewarm()
        for _ in 0..<4_000 where FTOScrambler.debugReserveCount < 4 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(FTOScrambler.debugReserveCount == 4)
        let results = await Task.detached {
            (0..<12).compactMap { _ in FTOScrambler.scramble() }
        }.value
        #expect(results.count == 12 && Set(results).count == 12)
        for scramble in results {
            #expect(FTOScrambler.isValidNotation(scramble))
            #expect(FTOScrambler.facelets(after: scramble)?.count == 72)
        }
    }

    @Test func profileAppFTOColdWarmExhaustedAndSustained() async throws {
        let pool = FTOScrambler.debugColdPool()
        let captured = await Task.detached(priority: .userInitiated) {
            func timed() -> (String?, Double) {
                let start = ProcessInfo.processInfo.systemUptime
                let value = pool.take()
                return (value, (ProcessInfo.processInfo.systemUptime - start) * 1_000)
            }
            let cold = timed()
            let deadline = ProcessInfo.processInfo.systemUptime + 40
            while pool.count < 4 && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.01) }
            let warm = (0..<4).map { _ in timed() }
            let exhausted = timed()
            let start = ProcessInfo.processInfo.systemUptime
            var sustained: [(String?, Double)] = []
            for _ in 0..<24 {
                sustained.append(timed())
                Thread.sleep(forTimeInterval: 0.1)
            }
            let times = sustained.map(\.1).sorted()
            print(String(format: "[FTOAcceptanceProfile] cold_ms=%.3f warm_max_ms=%.3f exhausted_ms=%.3f sustained_median_ms=%.3f sustained_max_ms=%.3f throughput_per_s=%.3f",
                cold.1, warm.map(\.1).max() ?? 0, exhausted.1, times[times.count / 2], times.last ?? 0,
                24 / (ProcessInfo.processInfo.systemUptime - start)))
            return [cold.0] + warm.map(\.0) + [exhausted.0] + sustained.map(\.0)
        }.value
        let values = captured.compactMap { $0 }
        #expect(values.count == 30 && Set(values).count == 30)
        #expect(values.allSatisfy(FTOScrambler.isValidNotation))
    }

    @Test func squareOneTerminologyUsesApprovedChineseAndStableEnglish() {
        #expect(appLocalizedString("algs.subset.parity", languageCode: "zh-Hans") == "有特")
        #expect(appLocalizedString("algs.subset.non_parity", languageCode: "zh-Hans") == "无特")
        #expect(appLocalizedString("algs.subset.non_parity", languageCode: "zh-Hant") == "無特")
        #expect(appLocalizedString("algs.subset.non_parity", languageCode: "en") == "Non-Parity")
    }
}

nonisolated private final class GenerationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var issued = 0
    private var active = 0
    private var peak = 0
    var started: Int { lock.lock(); defer { lock.unlock() }; return issued }
    var maximumActive: Int { lock.lock(); defer { lock.unlock() }; return peak }
    func begin() -> Int {
        lock.lock(); defer { lock.unlock() }
        issued += 1; active += 1; peak = max(peak, active)
        return issued
    }
    func end() { lock.lock(); active -= 1; lock.unlock() }
}
