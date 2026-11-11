import Foundation

/// Opérations sur la liste des conversations.
///
/// `TelegramClient` en est l'implémentation réelle (TDLib). L'abstraction permet de tester les
/// modèles de vue et d'afficher la liste sans réseau (tests UI).
protocol ChatListService: AnyObject, Sendable {
    /// Changements de la liste, dans l'ordre reçu. Émis dès la création du client : le
    /// consommateur doit être branché tout de suite (TDLib n'envoie chaque conversation qu'une fois).
    var chatEvents: AsyncStream<ChatListEvent> { get }

    /// Charge d'autres conversations (livrées par `chatEvents`). Renvoie `false` quand toute
    /// la liste est déjà chargée.
    func loadChats(_ list: ChatListKind, limit: Int) async throws -> Bool
    /// Marque comme lus les messages, mentions et réactions, et retire la marque « non lu ».
    func markAsRead(_ chat: ChatSummary) async throws
    func setMarkedAsUnread(chatId: Int64, _ isMarkedAsUnread: Bool) async throws
    func setPinned(chatId: Int64, in list: ChatListKind, _ isPinned: Bool) async throws
    /// Coupe (sans limite de durée) ou réactive les notifications de la conversation.
    func setMuted(chatId: Int64, _ isMuted: Bool) async throws
    /// Déplace la conversation (archiver : `.archive`, désarchiver : `.main`).
    func moveChat(chatId: Int64, to list: ChatListKind) async throws
    /// Supprime la conversation de la liste : quitte un groupe ou une chaîne, ferme une
    /// conversation secrète. `forEveryone` : supprime aussi l'historique chez l'interlocuteur
    /// (tête-à-tête seulement, si Telegram le permet).
    func deleteChat(_ chat: ChatSummary, forEveryone: Bool) async throws

    /// Conversations connues correspondant à la recherche (appareil puis serveur), sans doublon.
    func searchChats(_ query: String, limit: Int) async throws -> [Int64]
    /// Groupes et chaînes publics correspondant à la recherche.
    func searchPublicChats(_ query: String) async throws -> [Int64]
    /// Messages de toutes les conversations ; `offset` vide pour la première page.
    func searchMessages(_ query: String, offset: String, limit: Int) async throws -> MessageSearchPage
}

/// Service Telegram complet : connexion, liste des conversations et messages, sur le même
/// client TDLib.
protocol TelegramService: AuthService, ChatListService, ConversationService {}
