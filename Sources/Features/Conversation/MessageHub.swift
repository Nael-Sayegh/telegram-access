import Foundation

/// Distribue les changements de messages aux écrans qui les suivent.
///
/// Créé en même temps que le client TDLib (dans `AuthViewModel`), comme `ChatStore` : un écran
/// de conversation s'abonne avant de charger son historique, aucun message n'est perdu entre les
/// deux. Abandonné avec le client après une déconnexion.
@MainActor
final class MessageHub {
    /// Conversation affichée à l'écran, `nil` sinon (annonce des messages entrants).
    var openChatId: Int64?

    private struct Observer {
        weak var owner: AnyObject?
        /// `nil` : toutes les conversations.
        let chatId: Int64?
        let handler: @MainActor (MessageEvent) -> Void
    }

    private var observers: [ObjectIdentifier: Observer] = [:]

    init(events: AsyncStream<MessageEvent>) {
        Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.dispatch(event)
            }
        }
    }

    /// `handler` reçoit les changements de `chatId` (toutes les conversations si `nil`) et les
    /// téléchargements terminés, tant que `owner` existe et jusqu'à `stopObserving(owner)`.
    /// Un seul abonnement par `owner` (le dernier remplace le précédent). `handler` doit
    /// référencer `owner` faiblement.
    func observe(_ chatId: Int64?, owner: AnyObject, handler: @escaping @MainActor (MessageEvent) -> Void) {
        observers[ObjectIdentifier(owner)] = Observer(owner: owner, chatId: chatId, handler: handler)
    }

    func stopObserving(_ owner: AnyObject) {
        observers[ObjectIdentifier(owner)] = nil
    }

    /// Transmet un changement aux abonnés concernés ; ceux dont le propriétaire a disparu sont
    /// retirés. Appelé pour chaque changement de TDLib (et par les tests).
    func dispatch(_ event: MessageEvent) {
        let chatId = event.chatId
        for (key, observer) in observers {
            guard observer.owner != nil else {
                observers[key] = nil
                continue
            }
            if chatId == nil || observer.chatId == nil || observer.chatId == chatId {
                observer.handler(event)
            }
        }
    }
}
