import Foundation

// Types de la liste des conversations, indépendants de TDLib : l'interface, le réducteur
// et les tests n'importent pas TDLibKit. Noms choisis pour ne pas masquer ceux de TDLibKit
// (`Chat`, `ChatList`, `ChatPosition`, `ChatEvent`, `User`, `Message`…).

/// Liste de conversations TDLib.
enum ChatListKind: Hashable {
    case main
    case archive
    /// Dossier Telegram personnalisé (pris en charge en phase 6).
    case folder(Int)
}

/// Nature d'une conversation.
enum ChatKind: Equatable {
    /// Tête-à-tête (y compris « Messages enregistrés » si `userId` est le sien).
    case user(userId: Int64)
    case basicGroup
    case supergroup
    case channel
    /// Conversation secrète, chiffrée de bout en bout.
    case secret(secretChatId: Int, userId: Int64)

    /// Identifiant de l'interlocuteur pour un tête-à-tête ou une conversation secrète.
    var peerUserId: Int64? {
        switch self {
        case .user(let id), .secret(_, let id): return id
        case .basicGroup, .supergroup, .channel: return nil
        }
    }

    var isGroup: Bool {
        self == .basicGroup || self == .supergroup
    }

    var notificationScope: NotificationScope {
        switch self {
        case .user, .secret: return .privateChats
        case .basicGroup, .supergroup: return .groups
        case .channel: return .channels
        }
    }
}

/// Place d'une conversation dans une liste.
struct ChatListPosition: Equatable {
    var list: ChatListKind
    /// Tri décroissant par (order, identifiant du chat) ; 0 = absente de la liste.
    var order: Int64
    var isPinned: Bool
}

/// Auteur d'un message : un utilisateur, ou un chat (chaîne, groupe anonyme).
enum MessageSenderRef: Equatable {
    case user(Int64)
    case chat(Int64)
}

/// État d'envoi d'un message sortant.
enum MessageDeliveryState: Equatable {
    case sent
    case pending
    case failed
}

/// Issue d'un appel.
enum CallOutcome: Equatable {
    case ended
    case missed
    case declined
}

/// Contenu d'un message, réduit à ce qui sert à le décrire. Les légendes vides valent "".
/// Les durées sont en secondes.
enum MessageContentSummary: Equatable {
    case text(String)
    case photo(caption: String)
    case video(duration: Int, caption: String)
    case animation(caption: String)
    case voiceNote(duration: Int, caption: String)
    case videoNote(duration: Int)
    case audio(title: String, performer: String, duration: Int, caption: String)
    /// `size` en octets, 0 si inconnue.
    case document(fileName: String, size: Int64, caption: String)
    /// Autocollant, décrit par son émoji associé.
    case sticker(emoji: String)
    case location
    case venue
    case contact(firstName: String, lastName: String)
    case poll(question: String)
    case call(isVideo: Bool, duration: Int, outcome: CallOutcome)
    case story
    // Messages de service.
    case groupCreated
    case titleChanged(String)
    case photoChanged
    case membersAdded
    case memberRemoved
    case pinnedMessage
    /// Type non décrit (TDLib en compte plus d'une centaine).
    case unsupported
}

/// Dernier message d'une conversation, tel qu'affiché dans la liste.
struct MessagePreview: Equatable {
    var id: Int64
    var sender: MessageSenderRef
    var isOutgoing: Bool
    var date: Date
    var content: MessageContentSummary
    var delivery: MessageDeliveryState
}

/// Brouillon d'une conversation.
enum DraftSummary: Equatable {
    case text(String)
    case voiceNote
    case videoNote
    case other
}

/// Réglage de sourdine propre à une conversation.
struct ChatMuteSetting: Equatable {
    /// Vrai : la conversation suit le réglage de sa portée (personnes, groupes, chaînes).
    var usesDefault: Bool
    /// Secondes de sourdine restantes ; 0 = notifications actives.
    var muteFor: Int
}

/// Portée des réglages de notification par défaut.
enum NotificationScope: Hashable {
    case privateChats
    case groups
    case channels
}

/// Nom d'un utilisateur, pour l'auteur d'un message ou le titre d'un tête-à-tête.
struct UserName: Equatable {
    var firstName: String
    var lastName: String
    var isDeleted: Bool

    /// « Marie Dupont », « Compte supprimé » pour un compte supprimé ou sans nom.
    var displayName: String {
        let full = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return isDeleted || full.isEmpty ? "Compte supprimé" : full
    }
}

/// État de la connexion aux serveurs Telegram.
enum ConnectionStatus: Equatable {
    case waitingForNetwork
    case connectingToProxy
    case connecting
    case updating
    case ready
}

/// Conversation, telle que présentée dans la liste.
struct ChatSummary: Identifiable, Equatable {
    let id: Int64
    var kind: ChatKind
    var title: String
    var positions: [ChatListPosition]
    var lastMessage: MessagePreview?
    var unreadCount: Int
    var unreadMentionCount: Int
    var unreadReactionCount: Int
    var isMarkedAsUnread: Bool
    var lastReadInboxMessageId: Int64
    var lastReadOutboxMessageId: Int64
    var muteSetting: ChatMuteSetting
    var draft: DraftSummary?
    var canBeDeletedOnlyForSelf: Bool
    var canBeDeletedForAllUsers: Bool

    /// Position dans `list`, si la conversation y figure.
    func position(in list: ChatListKind) -> ChatListPosition? {
        positions.first { $0.list == list && $0.order != 0 }
    }

    /// Vrai si le dernier message, envoyé par soi, a été lu par le destinataire.
    var isLastOutgoingMessageRead: Bool {
        guard let lastMessage, lastMessage.isOutgoing else { return false }
        return lastMessage.id <= lastReadOutboxMessageId
    }

    /// Vrai s'il reste quelque chose à lire (messages, mentions, réactions, marque « non lu »).
    var hasUnread: Bool {
        unreadCount > 0 || unreadMentionCount > 0 || unreadReactionCount > 0 || isMarkedAsUnread
    }
}

/// Changement reçu de TDLib, appliqué par `ChatListState`.
enum ChatListEvent: Equatable {
    case newChat(ChatSummary)
    case title(chatId: Int64, title: String)
    /// `positions` remplace toutes les positions de la conversation.
    case lastMessage(chatId: Int64, message: MessagePreview?, positions: [ChatListPosition])
    /// Position dans une seule liste ; `order == 0` retire la conversation de cette liste.
    case position(chatId: Int64, position: ChatListPosition)
    case readInbox(chatId: Int64, lastReadMessageId: Int64, unreadCount: Int)
    case readOutbox(chatId: Int64, lastReadMessageId: Int64)
    case mentionCount(chatId: Int64, count: Int)
    case reactionCount(chatId: Int64, count: Int)
    case markedAsUnread(chatId: Int64, value: Bool)
    case muteSetting(chatId: Int64, setting: ChatMuteSetting)
    case scopeMute(scope: NotificationScope, muteFor: Int)
    /// `positions` remplace toutes les positions de la conversation.
    case draft(chatId: Int64, draft: DraftSummary?, positions: [ChatListPosition])
    case user(id: Int64, name: UserName)
    case myUserId(Int64)
    case connection(ConnectionStatus)
}

/// Résultat d'une recherche de messages, toutes conversations confondues.
struct MessageSearchResult: Equatable {
    var chatId: Int64
    var message: MessagePreview
}

/// Page de résultats d'une recherche de messages.
struct MessageSearchPage: Equatable {
    var results: [MessageSearchResult]
    /// À passer pour la page suivante ; vide s'il n'y en a plus.
    var nextOffset: String
}
