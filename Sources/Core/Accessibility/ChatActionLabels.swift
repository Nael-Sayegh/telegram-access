import Foundation

/// Action sur une conversation de la liste.
enum ChatRowAction: Hashable {
    case markAsRead
    case markAsUnread
    case pin
    case unpin
    case mute
    case unmute
    case archive
    case unarchive
    /// Supprimer, quitter le groupe ou la chaîne (après confirmation).
    case delete
}

/// Textes du dialogue de suppression d'une conversation.
struct ChatDeletionDialog: Equatable {
    var title: String
    /// Bouton principal : supprimer pour soi, ou quitter.
    var confirm: String
    /// Bouton « supprimer aussi chez l'interlocuteur », si Telegram le permet.
    var confirmForEveryone: String?
}

/// Textes des actions sur les conversations. Fonctions pures, testées unitairement.
enum ChatActionLabels {
    /// Actions proposées, dans un ordre fixe : lecture, épinglage, notifications, archivage,
    /// suppression. Le libellé reflète l'état (« Épingler » ou « Désépingler »).
    static func actions(for row: ChatRowModel, in list: ChatListKind) -> [ChatRowAction] {
        [
            row.hasUnread ? .markAsRead : .markAsUnread,
            row.isPinned ? .unpin : .pin,
            row.isMuted ? .unmute : .mute,
            list == .archive ? .unarchive : .archive,
            .delete,
        ]
    }

    static func name(_ action: ChatRowAction, for row: ChatRowModel) -> String {
        switch action {
        case .markAsRead: return "Marquer comme lu"
        case .markAsUnread: return "Marquer comme non lu"
        case .pin: return "Épingler"
        case .unpin: return "Désépingler"
        case .mute: return "Désactiver les notifications"
        case .unmute: return "Réactiver les notifications"
        case .archive: return "Archiver"
        case .unarchive: return "Désarchiver"
        case .delete:
            switch row.kind {
            case .basicGroup, .supergroup: return "Quitter le groupe"
            case .channel: return "Quitter la chaîne"
            case .user, .secret: return "Supprimer"
            }
        }
    }

    /// Annonce après une action réussie.
    static func confirmation(_ action: ChatRowAction, for row: ChatRowModel) -> String {
        switch action {
        case .markAsRead: return "Conversation marquée comme lue."
        case .markAsUnread: return "Conversation marquée comme non lue."
        case .pin: return "Conversation épinglée."
        case .unpin: return "Conversation désépinglée."
        case .mute: return "Notifications désactivées."
        case .unmute: return "Notifications réactivées."
        case .archive: return "Conversation archivée."
        case .unarchive: return "Conversation désarchivée."
        case .delete:
            switch row.kind {
            case .basicGroup, .supergroup: return "Vous avez quitté le groupe."
            case .channel: return "Vous avez quitté la chaîne."
            case .user, .secret: return "Conversation supprimée."
            }
        }
    }

    static func deletionDialog(for row: ChatRowModel) -> ChatDeletionDialog {
        switch row.kind {
        case .basicGroup, .supergroup:
            return ChatDeletionDialog(title: "Quitter le groupe « \(row.title) » ?", confirm: "Quitter le groupe")
        case .channel:
            return ChatDeletionDialog(title: "Quitter la chaîne « \(row.title) » ?", confirm: "Quitter la chaîne")
        case .secret:
            return ChatDeletionDialog(
                title: "Supprimer la conversation secrète avec \(row.title) ?",
                confirm: "Supprimer"
            )
        case .user where row.isSavedMessages:
            return ChatDeletionDialog(title: "Vider les Messages enregistrés ?", confirm: "Supprimer")
        case .user:
            return ChatDeletionDialog(
                title: "Supprimer la conversation avec \(row.title) ?",
                confirm: "Supprimer pour moi",
                confirmForEveryone: row.canDeleteForEveryone ? "Supprimer aussi pour \(row.title)" : nil
            )
        }
    }

    /// Ligne d'accès aux archives : « Archives, 12 conversations, 3 non lues ».
    static func archiveRow(total: Int, unread: Int) -> String {
        var parts = ["Archives"]
        if total > 0 {
            parts.append("\(total) conversation\(total > 1 ? "s" : "")")
        }
        if unread > 0 {
            parts.append("\(unread) non lue\(unread > 1 ? "s" : "")")
        }
        return parts.joined(separator: ", ")
    }

    /// Message d'erreur d'une action, en phrase compréhensible.
    static func error(_ error: Error) -> String {
        guard let telegram = error as? TelegramError else {
            return "L'action n'a pas abouti. Vérifiez votre connexion et réessayez."
        }
        let text = telegram.message.lowercased()
        if telegram.code == 429 || text.hasPrefix("flood_wait") || text.contains("too many requests") {
            return "Trop de demandes. Réessayez dans quelques instants."
        }
        if text.contains("pinned") {
            return "Nombre maximal de conversations épinglées atteint. Désépinglez-en une d'abord."
        }
        return "L'action n'a pas abouti. Vérifiez votre connexion et réessayez."
    }
}
