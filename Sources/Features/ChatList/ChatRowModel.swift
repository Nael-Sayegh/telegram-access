import Foundation

/// Dernier message d'une ligne, avec son auteur déjà résolu.
struct LastMessageLine: Equatable {
    /// « Vous », prénom de l'auteur dans un groupe ; `nil` en tête-à-tête ou dans une chaîne.
    var senderLabel: String?
    var text: String
    /// État d'un message envoyé (« lu », « envoyé »…) ; `nil` pour un message reçu.
    var status: String?
    var date: Date
}

/// Contenu d'une ligne de la liste, prêt à afficher et à lire.
struct ChatRowModel: Identifiable, Equatable {
    let id: Int64
    var title: String
    var kind: ChatKind
    var unreadCount: Int
    var unreadMentionCount: Int
    var isMarkedAsUnread: Bool
    var isPinned: Bool
    var isMuted: Bool
    var draft: DraftSummary?
    var lastMessage: LastMessageLine?

    var isSecret: Bool {
        if case .secret = kind { return true }
        return false
    }
}

extension ChatListState {
    /// Ligne de `chat` dans `list`, avec noms et états résolus.
    func row(for chat: ChatSummary, in list: ChatListKind) -> ChatRowModel {
        ChatRowModel(
            id: chat.id,
            title: displayTitle(of: chat),
            kind: chat.kind,
            unreadCount: chat.unreadCount,
            unreadMentionCount: chat.unreadMentionCount,
            isMarkedAsUnread: chat.isMarkedAsUnread,
            isPinned: chat.position(in: list)?.isPinned ?? false,
            isMuted: isMuted(chat),
            draft: chat.draft,
            lastMessage: chat.lastMessage.map { lastMessageLine($0, in: chat) }
        )
    }

    /// Nom affiché : « Messages enregistrés » pour soi-même, nom de l'interlocuteur si le
    /// titre est vide, « Compte supprimé » à défaut.
    func displayTitle(of chat: ChatSummary) -> String {
        if isSavedMessages(chat) {
            return "Messages enregistrés"
        }
        let title = chat.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }
        if let userId = chat.kind.peerUserId {
            return users[userId]?.displayName ?? "Compte supprimé"
        }
        return "Sans nom"
    }

    private func lastMessageLine(_ message: MessagePreview, in chat: ChatSummary) -> LastMessageLine {
        LastMessageLine(
            senderLabel: senderLabel(of: message, in: chat),
            text: MessageLabels.content(message.content),
            status: status(of: message, in: chat),
            date: message.date
        )
    }

    private func senderLabel(of message: MessagePreview, in chat: ChatSummary) -> String? {
        if message.isOutgoing {
            return isSavedMessages(chat) ? nil : "Vous"
        }
        guard chat.kind.isGroup else { return nil }
        switch message.sender {
        case .user(let userId):
            guard let name = users[userId] else { return nil }
            let firstName = name.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isDeleted || firstName.isEmpty ? name.displayName : firstName
        case .chat(let senderChatId):
            // Administrateur anonyme : le groupe lui-même, inutile de le répéter.
            guard senderChatId != chat.id, let sender = chats[senderChatId] else { return nil }
            return displayTitle(of: sender)
        }
    }

    private func status(of message: MessagePreview, in chat: ChatSummary) -> String? {
        guard message.isOutgoing, !isSavedMessages(chat), chat.kind != .channel else { return nil }
        switch message.delivery {
        case .pending: return "en cours d'envoi"
        case .failed: return "échec de l'envoi"
        case .sent: return chat.isLastOutgoingMessageRead ? "lu" : "envoyé"
        }
    }
}
