import Foundation
import Combine

/// A detail-page lifetime, not another network owner or a process-wide live session.
/// Conditional Info/Results/Live children may unmount without losing known Live state.
@MainActor final class CompetitionCubingLiveStores: ObservableObject {
    struct Entry {
        let identity: String
        let session: CompetitionCubingLiveSession
        let extras: CubingChinaLiveExtrasStore
        let transportOwner: AnyObject
    }
    private var retained: Entry?
    func entry(content: CompetitionLiveContent, language: String, transport: any CubingChinaLiveTransport) -> Entry {
        let key = "cubing|\(content.competitionID)|\(content.modern?.slug ?? "legacy")"
        let transportOwner = transport as AnyObject
        if let retained, retained.identity == key, retained.transportOwner === transportOwner { return retained }
        retained?.session.stop(); retained?.extras.stop()
        let session = CompetitionCubingLiveSession()
        session.configure(with: content, language: language, transport: transport)
        let value = Entry(identity: key, session: session, extras: CubingChinaLiveExtrasStore(), transportOwner: transportOwner)
        retained = value
        return value
    }
}
