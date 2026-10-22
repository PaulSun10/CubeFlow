import Foundation
import QuartzCore

nonisolated enum CompetitionLoadingTrace {
    static func record(_ phase: String, since start: TimeInterval, detail: String = "") {
        #if DEBUG
        print(String(format: "[CompetitionLoad] %@ %.2fms main=%@ %@", phase,
            (CACurrentMediaTime() - start) * 1000, Thread.isMainThread ? "yes" : "no", detail))
        #endif
    }
}

#if DEBUG
@MainActor
enum CompetitionColdLoadDiagnostics {
    private static var measured: Set<String> = []
    static func forceFirstLoad(_ identity: String) -> Bool {
        UserDefaults.standard.bool(forKey: "competitionForceFreshFirstDetail") && measured.insert(identity).inserted
    }
}

/// Separate connection/server/transfer time from parsing; no credentials or headers are logged.
nonisolated final class CompetitionNetworkMetrics: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        for transaction in metrics.transactionMetrics {
            func milliseconds(_ start: Date?, _ end: Date?) -> Double {
                guard let start, let end else { return 0 }
                return end.timeIntervalSince(start) * 1000
            }
            print(String(format: "[CompetitionNetwork] %@ protocol=%@ reused=%@ dns=%.2fms connect=%.2fms tls=%.2fms server=%.2fms transfer=%.2fms wire=%lld decoded=%lld",
                transaction.request.url?.absoluteString ?? "", transaction.networkProtocolName ?? "unknown",
                transaction.isReusedConnection ? "yes" : "no",
                milliseconds(transaction.domainLookupStartDate, transaction.domainLookupEndDate),
                milliseconds(transaction.connectStartDate, transaction.connectEndDate),
                milliseconds(transaction.secureConnectionStartDate, transaction.secureConnectionEndDate),
                milliseconds(transaction.requestEndDate, transaction.responseStartDate),
                milliseconds(transaction.responseStartDate, transaction.responseEndDate),
                transaction.countOfResponseBodyBytesReceived, transaction.countOfResponseBodyBytesAfterDecoding))
        }
    }
}
#endif
