#if os(iOS)
import XCTest
@testable import CubeFlow

@MainActor final class DiagramScriptCacheTests: XCTestCase {
    func testBundledSourcesAreAvailableAndRepeatedReadsReuseImmutableEncoding() throws {
        let first = ScrambleDiagramResources.encodedSources
        XCTAssertGreaterThan(first.utf8.count, 90_000)
        let sources = try XCTUnwrap(JSONSerialization.jsonObject(with: Data("{\(first)}".utf8)) as? [String: String])
        XCTAssertEqual(sources.count, 11)
        for name in ["main", "mathlib", "raster_geometry", "fto_engine", "cubes/fto", "cubes/nnn", "cubes/clk", "cubes/megaminx", "cubes/pyraminx", "cubes/skewb", "cubes/squareone"] {
            XCTAssertFalse(try XCTUnwrap(sources[name]).isEmpty, name)
        }
        for _ in 0..<100 { XCTAssertEqual(ScrambleDiagramResources.encodedSources, first) }
    }
    func testPreparationCanBeSharedFromBackgroundWithoutChangingSources() async {
        let first = ScrambleDiagramResources.encodedSources
        let other = await Task.detached {
            ScrambleDiagramResources.prewarm()
            return ScrambleDiagramResources.encodedSources
        }.value
        XCTAssertEqual(first, other)
    }
}
#endif
