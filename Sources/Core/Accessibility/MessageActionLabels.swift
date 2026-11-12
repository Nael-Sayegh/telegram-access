import Foundation

/// Action sur un message : action personnalisée VoiceOver et entrée du menu contextuel.
enum MessageAction: Hashable {
    case reply
    case react
    case copy
    case forward
    case edit
    case pin
    case unpin
    case openLink(URL)
    /// Nouvel essai d'un message dont l'envoi a échoué.
    case resend
    /// Supprimer (après confirmation).
    case delete
}

/// Textes de l'alerte de suppression d'un message ; un bouton absent n'est pas proposé.
struct MessageDeletionDialog: Equatable {
    var title: String
    /// Supprimer seulement pour soi.
    var forMe: String?
    /// Supprimer aussi chez les autres participants.
    var forEveryone: String?
}

/// Règles et textes des actions sur les messages. Fonctions pures, testées unitairement.
enum MessageActionLabels {
    /// Liens proposés en action au plus (« Ouvrir exemple.fr »), dans l'ordre du texte.
    static let maxLinkActions = 3

    /// Actions proposées pour un message, dans un ordre fixe : répondre, réagir, copier,
    /// transférer, modifier, épingler, liens, supprimer. Un message en échec propose d'abord
    /// « Réessayer l'envoi ». `capabilities` : `nil` tant que Telegram n'a pas répondu (copie
    /// et liens seulement). `canReact` : faux dans une conversation secrète ou les Messages
    /// enregistrés.
    static func actions(for row: MessageRowModel, capabilities: MessageCapabilities?, canReact: Bool) -> [MessageAction] {
        let links = row.links.prefix(maxLinkActions).map { MessageAction.openLink($0) }
        let copy: [MessageAction] = row.canCopy ? [.copy] : []
        if row.isFailed {
            return [.resend] + copy + links + [.delete]
        }
        guard let capabilities else {
            return copy + links
        }
        var actions: [MessageAction] = []
        if capabilities.canBeReplied { actions.append(.reply) }
        if canReact, !row.isPending { actions.append(.react) }
        actions += copy
        if capabilities.canBeForwarded { actions.append(.forward) }
        if capabilities.canBeEdited, case .text = row.content { actions.append(.edit) }
        if capabilities.canBePinned { actions.append(row.isPinned ? .unpin : .pin) }
        actions += links
        if capabilities.canBeDeleted { actions.append(.delete) }
        return actions
    }

    static func name(_ action: MessageAction) -> String {
        switch action {
        case .reply: return "Répondre"
        case .react: return "Réagir"
        case .copy: return "Copier"
        case .forward: return "Transférer"
        case .edit: return "Modifier"
        case .pin: return "Épingler"
        case .unpin: return "Désépingler"
        case .openLink(let url): return ConversationLabels.openLinkAction(url)
        case .resend: return "Réessayer l'envoi"
        case .delete: return "Supprimer"
        }
    }

    /// Texte copiable d'un message : le texte, ou la légende d'un média ; `nil` s'il n'y a
    /// rien à copier.
    static func copyableText(_ content: MessageContentSummary) -> String? {
        let text: String
        switch content {
        case .text(let value):
            text = value
        case .photo(let caption), .animation(let caption):
            text = caption
        case .video(_, let caption), .voiceNote(_, let caption):
            text = caption
        case .audio(_, _, _, let caption), .document(_, _, let caption):
            text = caption
        case .poll(let question):
            text = question
        default:
            return nil
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    // MARK: - Rédaction

    /// Titre du bandeau et libellé du champ pendant une réponse : « Réponse à Paul Martin »,
    /// « Réponse à votre message ».
    static func replyContext(_ author: ReplyLine.Author) -> String {
        switch author {
        case .me: return "Réponse à votre message"
        case .named(let name): return "Réponse à \(name)"
        case .unknown: return "Réponse à un message"
        }
    }

    static let editContext = "Modification du message"
    static let cancelReply = "Annuler la réponse"
    static let cancelEdit = "Annuler la modification"
    static let replyCancelled = "Réponse annulée."
    static let editCancelled = "Modification annulée."

    // MARK: - Résultats

    static let copied = "Message copié."
    static let pinned = "Message épinglé."
    static let unpinned = "Message désépinglé."
    static let deleted = "Message supprimé."
    static let edited = "Message modifié."
    static let resending = "Nouvel essai d'envoi."
    static let nothingToSend = "Aucun message à envoyer."

    static func forwarded(to title: String) -> String {
        "Message transféré à \(title)."
    }

    /// « Réaction 👍 ajoutée. » (VoiceOver lit le nom de l'émoji).
    static func reaction(_ kind: ReactionKind, added: Bool) -> String {
        "Réaction \(ConversationLabels.reactionName(kind)) \(added ? "ajoutée" : "retirée")."
    }

    /// Alerte de suppression : « Supprimer pour moi » et « Supprimer aussi pour Marie Dupont »
    /// (tête-à-tête) ou « Supprimer pour tous » (groupe), selon ce que Telegram permet.
    static func deletionDialog(
        capabilities: MessageCapabilities,
        chatTitle: String,
        isPrivateChat: Bool,
        isSavedMessages: Bool
    ) -> MessageDeletionDialog {
        let both = capabilities.canBeDeletedOnlyForSelf && capabilities.canBeDeletedForAllUsers
        let everyone = isPrivateChat && !isSavedMessages ? "Supprimer aussi pour \(chatTitle)" : "Supprimer pour tous"
        return MessageDeletionDialog(
            title: "Supprimer ce message ?",
            forMe: capabilities.canBeDeletedOnlyForSelf ? (both ? "Supprimer pour moi" : "Supprimer") : nil,
            forEveryone: capabilities.canBeDeletedForAllUsers ? everyone : nil
        )
    }

    /// Message d'erreur d'une action, en phrase compréhensible.
    static func error(_ error: Error) -> String {
        let generic = "L'action n'a pas abouti. Vérifiez votre connexion et réessayez."
        guard let telegram = error as? TelegramError else { return generic }
        let text = telegram.message.uppercased()
        if telegram.code == 429 || text.hasPrefix("FLOOD_WAIT") || text.contains("TOO MANY REQUESTS") {
            return "Trop de demandes. Réessayez dans quelques instants."
        }
        if text.contains("MESSAGE_NOT_MODIFIED") {
            return "Le message n'a pas changé."
        }
        if text.contains("MESSAGE_EDIT_TIME_EXPIRED") {
            return "Ce message ne peut plus être modifié."
        }
        if text.contains("REACTION") {
            return "Cette réaction n'est pas disponible."
        }
        if text.contains("CHAT_WRITE_FORBIDDEN") || text.contains("WRITE ACCESS") {
            return "Vous ne pouvez pas écrire dans cette conversation."
        }
        if text.contains("MESSAGE_ID_INVALID") || text.contains("MESSAGE NOT FOUND") {
            return "Ce message n'existe plus."
        }
        return generic
    }
}
