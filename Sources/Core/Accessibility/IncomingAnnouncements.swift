import Foundation

/// Réglage d'annonce des messages reçus (menu Options), enregistré dans les préférences.
enum IncomingAnnouncementMode: String, CaseIterable, Identifiable {
    /// Toutes les conversations, sauf celles en sourdine (la conversation ouverte, toujours).
    case allChats
    /// Seulement la conversation affichée à l'écran.
    case openChat
    case never

    static let storageKey = "incomingAnnouncementMode"
    static let defaultValue: IncomingAnnouncementMode = .openChat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allChats: return "Toutes les conversations, sauf en sourdine"
        case .openChat: return "Conversation ouverte"
        case .never: return "Jamais"
        }
    }

    /// Réglage enregistré, ou celui par défaut.
    static func stored(in defaults: UserDefaults) -> IncomingAnnouncementMode {
        defaults.string(forKey: storageKey).flatMap(IncomingAnnouncementMode.init(rawValue:)) ?? defaultValue
    }
}

/// Message reçu à annoncer, réduit à ce qui sert à le dire.
struct IncomingMessage: Equatable {
    enum Place: Equatable {
        case privateChat
        case group
        case channel
    }

    var chatId: Int64
    var messageId: Int64
    /// Nom de la conversation : l'interlocuteur en tête-à-tête, le groupe, la chaîne.
    var chatTitle: String
    var place: Place
    /// Auteur dans un groupe ; ignoré en tête-à-tête et dans une chaîne.
    var author: String?
    /// Contenu décrit (« Salut », « Photo », « Message vocal, 12 secondes »).
    var content: String
    /// Vrai si la conversation était affichée à la réception.
    var isInOpenChat: Bool
}

/// Règles et textes des annonces de messages reçus. Fonctions pures, testées unitairement.
enum IncomingAnnouncements {
    /// Au-delà, un message « nouveau » pour TDLib est un rattrapage (reconnexion, démarrage) :
    /// il n'est pas annoncé, pour éviter une avalanche d'annonces.
    static let maximumAge: TimeInterval = 120
    /// Messages arrivés pendant ce délai annoncés ensemble.
    static let burstDelay: Duration = .milliseconds(1500)
    /// Longueur maximale du contenu annoncé.
    static let contentLimit = 200

    /// Vrai si un message reçu doit être annoncé. La conversation ouverte est annoncée même en
    /// sourdine (on la regarde) ; les autres seulement avec « Toutes les conversations » et
    /// hors sourdine.
    static func shouldAnnounce(
        mode: IncomingAnnouncementMode,
        isOutgoing: Bool,
        isInOpenChat: Bool,
        isMuted: Bool,
        isAlreadyRead: Bool,
        age: TimeInterval
    ) -> Bool {
        guard !isOutgoing, !isAlreadyRead, age <= maximumAge else { return false }
        switch mode {
        case .never: return false
        case .openChat: return isInOpenChat
        case .allChats: return isInOpenChat || !isMuted
        }
    }

    /// Texte d'une rafale : une phrase par conversation, dans l'ordre d'arrivée. Un message seul
    /// est lu (« Paul Martin dans Famille : Salut ») ; plusieurs sont comptés (« 3 nouveaux
    /// messages dans Famille »). `nil` pour une rafale vide.
    static func text(_ messages: [IncomingMessage]) -> String? {
        var order: [Int64] = []
        var byChat: [Int64: [IncomingMessage]] = [:]
        for message in messages {
            if byChat[message.chatId] == nil {
                order.append(message.chatId)
            }
            byChat[message.chatId, default: []].append(message)
        }
        let sentences = order.compactMap { byChat[$0] }.map { group in
            group.count == 1 ? single(group[0]) : several(group)
        }
        guard !sentences.isEmpty else { return nil }
        return sentences.map(Self.ended).joined(separator: " ")
    }

    /// « Marie Dupont : Salut », « Paul Martin dans Famille : Salut » (« Paul Martin : Salut »
    /// si Famille est ouverte), « Infos : Nouvelle publication ».
    static func single(_ message: IncomingMessage) -> String {
        var content = ConversationLabels.excerpt(message.content, limit: contentLimit)
        if content.isEmpty {
            content = "Message vide"
        }
        guard message.place == .group, let author = message.author, author != message.chatTitle else {
            return "\(message.chatTitle) : \(content)"
        }
        return message.isInOpenChat
            ? "\(author) : \(content)"
            : "\(author) dans \(message.chatTitle) : \(content)"
    }

    /// « 3 nouveaux messages de Marie Dupont », « 3 nouveaux messages dans Famille »,
    /// « 3 nouveaux messages » dans la conversation ouverte.
    static func several(_ messages: [IncomingMessage]) -> String {
        let count = "\(messages.count) nouveaux messages"
        guard let first = messages.first, !first.isInOpenChat else { return count }
        switch first.place {
        case .privateChat: return "\(count) de \(first.chatTitle)"
        case .group, .channel: return "\(count) dans \(first.chatTitle)"
        }
    }

    /// Phrase terminée par une ponctuation, pour enchaîner plusieurs conversations.
    private static func ended(_ sentence: String) -> String {
        guard let last = sentence.last, !".!?…".contains(last) else { return sentence }
        return sentence + "."
    }
}
