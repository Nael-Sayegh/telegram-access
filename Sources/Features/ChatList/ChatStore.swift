import Foundation
import Observation

/// État observable des conversations, alimenté par les changements TDLib.
///
/// Créé en même temps que le client TDLib (dans `AuthViewModel`) : TDLib n'envoie chaque
/// conversation qu'une seule fois, un store branché plus tard en manquerait. Abandonné avec
/// le client après une déconnexion.
@MainActor
@Observable
final class ChatStore {
    private(set) var state = ChatListState()

    init(events: AsyncStream<ChatListEvent>) {
        Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.state.apply(event)
            }
        }
    }
}
