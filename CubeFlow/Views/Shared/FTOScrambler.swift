import Foundation
import JavaScriptCore

nonisolated enum FTOScrambler {
    // No JS objects cross queues. Solver tables are initialized once per producer,
    // and the cheap state interpreter cannot queue behind a random-state search.
    private final class Engine: @unchecked Sendable {
        private var context: JSContext?

        func exports() -> JSValue? {
            if context == nil, let source, let vm = JSContext() {
                let random: @convention(block) () -> Double = { Double.random(in: 0..<1) }
                vm.setObject(random, forKeyedSubscript: "cubeFlowRandom" as NSString)
                vm.evaluateScript("var performance={now:function(){return Date.now();}}; var module={exports:{}};" + source
                    + "\nmathlib.setRandomGen({random: cubeFlowRandom});")
                guard vm.exception == nil else { return nil }
                context = vm
            }
            context?.exception = nil
            return context?.objectForKeyedSubscript("module")?.objectForKeyedSubscript("exports")
        }

        func scramble() -> String? {
            let value = exports()?.objectForKeyedSubscript("generate")?.call(withArguments: [])?.toString()
            guard context?.exception == nil, let value, !value.isEmpty, isValidNotation(value) else { return nil }
            return value
        }

        func facelets(_ notation: String) -> [Int]? {
            let values = exports()?.objectForKeyedSubscript("state")?.call(withArguments: [notation])?.toArray() as? [Int]
            return context?.exception == nil && values?.count == 72 ? values : nil
        }
    }

    private static let source: String? = {
        guard let url = Bundle.main.url(forResource: "fto_engine", withExtension: "js", subdirectory: "Resources/DrawScramble")
                ?? Bundle.main.url(forResource: "fto_engine", withExtension: "js", subdirectory: "DrawScramble")
                ?? Bundle.main.url(forResource: "fto_engine", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()
    private static let producers = [Engine(), Engine()]
    private static let pool = FTOGenerationPool { producers[$0].scramble() }
    private static let stateQueue = DispatchQueue(label: "CubeFlow.fto-state", qos: .userInitiated)
    private static let stateEngine = Engine()

    static func prewarm() { pool.prewarm() }
    static func scramble() -> String? { pool.take() }

    #if DEBUG
    static var debugReserveCount: Int { pool.count }
    static func debugColdPool() -> FTOGenerationPool {
        let engines = [Engine(), Engine()]
        return FTOGenerationPool { engines[$0].scramble() }
    }
    #endif

    static func facelets(after notation: String) -> [Int]? {
        guard isValidNotation(notation) else { return nil }
        return stateQueue.sync { stateEngine.facelets(notation) }
    }

    static func isValidNotation(_ notation: String) -> Bool {
        notation.split(whereSeparator: { $0.isWhitespace }).allSatisfy {
            $0.range(of: "^(U|F|BR|BL|D|B|R|L)('?|2)$", options: .regularExpression) != nil
        }
    }
}
