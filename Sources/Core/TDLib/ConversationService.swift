import Foundation

/// Opérations sur les messages d'une conversation.
///
/// `TelegramClient` en est l'implémentation réelle (TDLib). L'abstraction permet de tester les
/// modèles de vue et d'afficher une conversation sans réseau (tests UI).
protocol ConversationService: AnyObject, Sendable {
    /// Changements des messages de toutes les conversations, dans l'ordre reçu. Émis dès la
    /// création du client : consommés par `MessageHub`, né avec lui.
    var messageEvents: AsyncStream<MessageEvent> { get }

    /// Signale l'affichage de la conversation (TDLib envoie alors ses changements et marque lus
    /// les messages vus) ; `closeChat` à la sortie de l'écran.
    func openChat(_ chatId: Int64) async throws
    func closeChat(_ chatId: Int64) async throws

    /// Messages à partir de `fromMessageId` (0 : depuis le dernier), du plus récent au plus
    /// ancien. `offset` négatif (jusqu'à -99) : inclut autant de messages plus récents.
    /// TDLib peut en renvoyer moins que `limit`, même s'il en reste.
    func history(chatId: Int64, from fromMessageId: Int64, offset: Int, limit: Int) async throws -> [ChatMessage]
    /// Un message précis (message cité absent de l'historique chargé).
    func message(chatId: Int64, id: Int64) async throws -> ChatMessage
    /// Ce que Telegram permet de faire du message. Hors ligne.
    func capabilities(chatId: Int64, messageId: Int64) async throws -> MessageCapabilities
    /// Messages affichés à l'écran (lecture, compteurs de vues).
    func viewMessages(chatId: Int64, ids: [Int64]) async throws

    /// Envoie un texte, en réponse à `replyTo` s'il est donné. Le message provisoire arrive par
    /// `messageEvents` (`.new`), puis `.sendSucceeded` ou `.sendFailed`.
    func sendText(_ text: String, chatId: Int64, replyTo: Int64?) async throws
    func editText(_ text: String, chatId: Int64, messageId: Int64) async throws
    /// `forEveryone` : supprime aussi chez les autres participants, si Telegram le permet.
    func deleteMessages(chatId: Int64, ids: [Int64], forEveryone: Bool) async throws
    func forwardMessages(_ ids: [Int64], from chatId: Int64, to targetChatId: Int64) async throws
    func setMessagePinned(chatId: Int64, messageId: Int64, _ isPinned: Bool) async throws
    /// Réactions proposées pour ce message (émoji seulement, dans l'ordre de Telegram).
    func availableReactions(chatId: Int64, messageId: Int64) async throws -> [ReactionKind]
    /// Ajoute (`isChosen`) ou retire une réaction.
    func setReaction(_ reaction: ReactionKind, chatId: Int64, messageId: Int64, isChosen: Bool) async throws
    /// Lien public ou privé vers le message (t.me).
    func messageLink(chatId: Int64, messageId: Int64) async throws -> String
    /// Renvoie des messages dont l'envoi a échoué.
    func resendMessages(chatId: Int64, ids: [Int64]) async throws
    /// Télécharge entièrement le fichier et renvoie son état final (chemin local).
    func downloadFile(_ fileId: Int) async throws -> FileRef
    /// Envoie un vocal enregistré (fichier local) ; `waveform` en 5 bits par échantillon.
    func sendVoiceNote(chatId: Int64, file: URL, duration: Int, waveform: Data, replyTo: Int64?) async throws
    /// Signale sa propre activité (« écrit… ») ; `nil` l'annule.
    func setActivity(chatId: Int64, _ activity: ChatActivity?) async throws
}
