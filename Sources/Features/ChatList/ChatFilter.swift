import Foundation

/// Rotor VoiceOver de la liste : passe directement d'une conversation concernée à la suivante.
enum ChatRotor: CaseIterable {
    case unread
    case mentions
    case pinned

    var name: String {
        switch self {
        case .unread: return "Non lus"
        case .mentions: return "Mentions"
        case .pinned: return "Épinglées"
        }
    }

    func matches(_ row: ChatRowModel) -> Bool {
        switch self {
        case .unread: return row.hasUnread
        case .mentions: return row.unreadMentionCount > 0
        case .pinned: return row.isPinned
        }
    }
}

/// Filtre de la liste principale. Appliqué sur l'appareil, aux conversations chargées : un
/// filtre autre que « Tous » fait charger toute la liste (sinon « Non lus » serait incomplet).
enum ChatFilter: CaseIterable, Hashable {
    case all
    case unread
    case people
    case groups
    case channels

    /// Vrai si la conversation correspond au filtre.
    func matches(_ chat: ChatSummary) -> Bool {
        switch self {
        case .all:
            return true
        case .unread:
            return chat.hasUnread
        case .people:
            switch chat.kind {
            case .user, .secret: return true
            case .basicGroup, .supergroup, .channel: return false
            }
        case .groups:
            return chat.kind.isGroup
        case .channels:
            return chat.kind == .channel
        }
    }

    var name: String {
        switch self {
        case .all: return "Tous"
        case .unread: return "Non lus"
        case .people: return "Personnes"
        case .groups: return "Groupes"
        case .channels: return "Chaînes"
        }
    }

    /// Texte de la liste vide pour ce filtre.
    var emptyText: String {
        switch self {
        case .all: return "Aucune conversation."
        case .unread: return "Aucune conversation non lue."
        case .people: return "Aucune conversation avec une personne."
        case .groups: return "Aucun groupe."
        case .channels: return "Aucune chaîne."
        }
    }

    /// Libellé du bouton Filtre de la barre : « Filtre : Non lus ».
    var buttonLabel: String {
        "Filtre : \(name)"
    }

    /// Option du menu Filtre : « Non lus (4) ». Nombre omis tant qu'il n'est pas connu
    /// (liste pas encore entièrement chargée).
    func menuTitle(count: Int?) -> String {
        guard let count else { return name }
        return "\(name) (\(count))"
    }

    /// Annonce après le choix d'un filtre : « 4 conversations », « Aucune conversation ».
    static func resultAnnouncement(count: Int) -> String {
        count == 0 ? "Aucune conversation." : "\(conversations(count))."
    }

    private static func conversations(_ count: Int) -> String {
        "\(count) conversation\(count > 1 ? "s" : "")"
    }
}
