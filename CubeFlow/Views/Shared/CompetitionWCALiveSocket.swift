import Foundation

/// The production socket remains URLSession's native Phoenix/Absinthe transport.
/// This seam permits deterministic handshake/reconnect tests without a live server.
nonisolated protocol CompetitionWCALiveSocket: AnyObject, Sendable {
    func resume()
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
}
extension URLSessionWebSocketTask: CompetitionWCALiveSocket {}
