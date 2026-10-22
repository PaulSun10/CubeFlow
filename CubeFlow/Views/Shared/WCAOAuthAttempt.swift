import Foundation
import Security

struct WCAOAuthAttempt {
    enum Failure: Error, Equatable { case randomSource, consumed, redirect, state, response, denied }
    let id = UUID()
    let state: String
    private(set) var isConsumed = false

    init() throws {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure.randomSource }
        state = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    mutating func consume(_ url: URL, redirectURI: String) throws -> String {
        guard !isConsumed else { throw Failure.consumed }
        isConsumed = true
        guard let expected = URLComponents(string: redirectURI),
              let actual = URLComponents(url: url, resolvingAgainstBaseURL: false),
              actual.scheme?.lowercased() == expected.scheme?.lowercased(),
              actual.host?.lowercased() == expected.host?.lowercased(),
              actual.percentEncodedPath == expected.percentEncodedPath,
              actual.port == expected.port, actual.user == nil, actual.password == nil,
              actual.fragment == nil else { throw Failure.redirect }
        let items = actual.queryItems ?? []
        let states = items.filter { $0.name == "state" }
        guard states.count == 1, let returnedState = states[0].value,
              constantTimeEqual(returnedState, state) else { throw Failure.state }
        let codes = items.filter { $0.name == "code" }, errors = items.filter { $0.name == "error" }
        if errors.count == 1, codes.isEmpty, errors[0].value == "access_denied" { throw Failure.denied }
        guard errors.isEmpty, codes.count == 1, let code = codes[0].value, !code.isEmpty else { throw Failure.response }
        return code
    }

    static func permitsBearerToken(to url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme == "https" && components.host?.lowercased() == "www.worldcubeassociation.org"
            && (components.port == nil || components.port == 443) && components.user == nil && components.password == nil
    }

    private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
