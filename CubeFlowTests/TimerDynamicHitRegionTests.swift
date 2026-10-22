import SwiftUI
import XCTest
@testable import CubeFlow

@MainActor
final class TimerDynamicHitRegionTests: XCTestCase {
    func testOtherInputModesRetainTheOriginalHeaderHitRegion() {
        let shape = TimerHeaderInteractiveShape(frames: [], lowerEdge: 400, includesEntireVisibleArea: true)
            .path(in: CGRect(x: 0, y: 0, width: 390, height: 800))
        XCTAssertTrue(shape.contains(CGPoint(x: 195, y: 180)))
        XCTAssertFalse(shape.contains(CGPoint(x: 195, y: 420)))
    }
    func testOnlyActualControlsConsumeHeaderTouches() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 800)
        let shape = TimerHeaderInteractiveShape(frames: [
            CGRect(x: 16, y: 8, width: 44, height: 44),
            CGRect(x: 150, y: 8, width: 90, height: 44),
            CGRect(x: 30, y: 72, width: 300, height: 56)
        ], lowerEdge: 400).path(in: bounds)
        XCTAssertTrue(shape.contains(CGPoint(x: 36, y: 24)))
        XCTAssertTrue(shape.contains(CGPoint(x: 195, y: 24)))
        XCTAssertTrue(shape.contains(CGPoint(x: 195, y: 90)))
        XCTAssertFalse(shape.contains(CGPoint(x: 110, y: 24)), "Gap between header controls is a timing surface")
        XCTAssertFalse(shape.contains(CGPoint(x: 195, y: 180)), "Blank space above digits is not the whole header")
        XCTAssertFalse(shape.contains(CGPoint(x: 12, y: 90)), "Blank side margin remains touchable")
    }

    func testLongScrambleAndLayoutChangesUpdateHitRegionWithoutFixedReserve() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 800)
        let short = TimerHeaderInteractiveShape(frames: [CGRect(x: 20, y: 70, width: 300, height: 30)], lowerEdge: 400)
        let long = TimerHeaderInteractiveShape(frames: [CGRect(x: 20, y: 70, width: 300, height: 600)], lowerEdge: 400)
        XCTAssertFalse(short.path(in: bounds).contains(CGPoint(x: 195, y: 250)))
        XCTAssertTrue(long.path(in: bounds).contains(CGPoint(x: 195, y: 250)))
        XCTAssertFalse(long.path(in: bounds).contains(CGPoint(x: 195, y: 420)), "Clipped scramble cannot intercept timer")
        let moved = TimerHeaderInteractiveShape(frames: [CGRect(x: 20, y: 190, width: 300, height: 30)], lowerEdge: 400)
        XCTAssertFalse(moved.path(in: bounds).contains(CGPoint(x: 195, y: 80)))
        XCTAssertTrue(moved.path(in: bounds).contains(CGPoint(x: 195, y: 200)))
    }
}
