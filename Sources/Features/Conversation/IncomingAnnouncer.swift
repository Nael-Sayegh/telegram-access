import Foundation
import UIKit

/// Annonce VoiceOver des messages reçus, selon le réglage du menu Options.
///
/// Créé avec le client, comme `MessageHub` et `ChatStore` : il suit toutes les conversations,
/// ouvertes ou non. Les annonces sont mises en file d'attente (elles ne coupent pas la parole)
/// et regroupées par rafale (`IncomingAnnouncements.burstDelay`). Elles ne déplacent jamais le
/// focus et ne font pas défiler la conversation.
@MainActor
final class IncomingAnnouncer {
    /// Dernière annonce faite, pour les tests.
    private(set) var lastAnnouncement: String?

    private let hub: MessageHub
    private let store: ChatStore
    private let mode: @MainActor () -> IncomingAnnouncementMode
    private let canSpeak: @MainActor () -> Bool
    private let now: @MainActor () -> Date
    private let delay: Duration
    private let speak: @MainActor (String) -> Void
    private var pending: [IncomingMessage] = []
    private var flushTask: Task<Void, Never>?

    /// `canSpeak` : app au premier plan avec VoiceOver actif (sinon rien n'est dit).
    init(
        hub: MessageHub,
        store: ChatStore,
        mode: @escaping @MainActor () -> IncomingAnnouncementMode = { IncomingAnnouncementMode.stored(in: .standard) },
        canSpeak: @escaping @MainActor () -> Bool = {
            UIApplication.shared.applicationState == .active && UIAccessibility.isVoiceOverRunning
        },
        now: @escaping @MainActor () -> Date = { Date() },
        delay: Duration = IncomingAnnouncements.burstDelay,
        speak: @escaping @MainActor (String) -> Void = { Announcer.announceQueued($0) }
    ) {
        self.hub = hub
        self.store = store
        self.mode = mode
        self.canSpeak = canSpeak
        self.now = now
        self.delay = delay
        self.speak = speak
        hub.observe(nil, owner: self) { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: MessageEvent) {
        guard case .new(let message) = event, let incoming = incoming(message) else { return }
        pending.append(incoming)
        guard flushTask == nil else { return }
        let delay = delay
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.flush()
        }
    }

    /// Message à annoncer, `nil` s'il ne doit pas l'être.
    private func incoming(_ message: ChatMessage) -> IncomingMessage? {
        let list = store.state
        guard let chat = list.chats[message.chatId] else { return nil }
        let isInOpenChat = hub.openChatId == chat.id
        let shouldAnnounce = IncomingAnnouncements.shouldAnnounce(
            mode: mode(),
            isOutgoing: message.isOutgoing,
            isInOpenChat: isInOpenChat,
            isMuted: list.isMuted(chat),
            isAlreadyRead: message.id <= chat.lastReadInboxMessageId,
            age: now().timeIntervalSince(message.date)
        )
        guard shouldAnnounce else { return nil }
        let place: IncomingMessage.Place
        switch chat.kind {
        case .user, .secret: place = .privateChat
        case .basicGroup, .supergroup: place = .group
        case .channel: place = .channel
        }
        return IncomingMessage(
            chatId: chat.id,
            messageId: message.id,
            chatTitle: list.displayTitle(of: chat),
            place: place,
            author: list.authorName(of: message.sender, signature: message.authorSignature),
            content: MessageLabels.content(message.body.content),
            isInOpenChat: isInOpenChat
        )
    }

    private func flush() {
        flushTask = nil
        let burst = pending
        pending = []
        guard canSpeak(), let text = IncomingAnnouncements.text(burst) else { return }
        lastAnnouncement = text
        speak(text)
    }
}
