import Foundation

// Types de l'écran de conversation, indépendants de TDLib : l'interface, le réducteur et les
// tests n'importent pas TDLibKit. Noms choisis pour ne pas masquer ceux de TDLibKit
// (`Message`, `File`, `MessageContent`, `ReactionType`, `MessageProperties`…).

/// Fichier TDLib d'un média.
struct FileRef: Equatable {
    let id: Int
    /// Taille en octets, 0 si inconnue.
    var size: Int64
    /// Chemin local une fois le téléchargement terminé, `nil` sinon.
    var localPath: String?

    var isDownloaded: Bool { localPath != nil }
}

/// Média d'un message : de quoi le lire, le télécharger ou le décrire.
struct MessageMedia: Equatable {
    enum Kind: Equatable {
        case photo
        case video
        case animation
        case voiceNote
        case videoNote
        case audio
        case document
        case sticker
    }

    var kind: Kind
    var file: FileRef
    /// Vocal ou message vidéo écouté / vu au moins une fois (toujours vrai pour les autres
    /// médias). Pour un message envoyé : écouté par un destinataire.
    var isListened: Bool = true
    /// Forme d'onde d'un vocal (5 bits par échantillon), vide sinon.
    var waveform = Data()
}

/// Contenu complet d'un message : sa description, ses liens, ses mentions et son média.
struct MessageBody: Equatable {
    var content: MessageContentSummary
    /// Liens du texte ou de la légende, dans l'ordre, sans doublon.
    var links: [URL] = []
    /// Utilisateurs mentionnés par un lien de mention (utilisateurs sans nom public).
    var mentionedUserIds: [Int64] = []
    var media: MessageMedia?
}

/// Auteur d'origine d'un message transféré.
enum ForwardOrigin: Equatable {
    case user(Int64)
    /// Utilisateur qui masque son compte dans les transferts : seul son nom est connu.
    case hiddenUser(name: String)
    /// Groupe (administrateur anonyme), avec la signature éventuelle de l'auteur.
    case chat(Int64, signature: String)
    case channel(Int64, signature: String)
}

/// Message auquel un autre répond.
struct MessageReplyRef: Equatable {
    /// Conversation du message cité (une autre conversation est possible).
    var chatId: Int64
    /// 0 si le message cité n'est pas accessible (supprimé, conversation privée…).
    var messageId: Int64
    /// Message d'une autre conversation : origine et contenu fournis par TDLib.
    var origin: ForwardOrigin?
    var content: MessageContentSummary?
    /// Extrait choisi par l'auteur de la réponse, vide sinon.
    var quote: String = ""
}

/// Type de réaction.
enum ReactionKind: Hashable {
    case emoji(String)
    /// Émoji personnalisé (Telegram Premium), sans texte associé connu.
    case customEmoji(Int64)
    /// Réaction payante (étoiles Telegram).
    case paid
}

/// Réaction d'un message et son nombre.
struct MessageReactionCount: Equatable {
    var kind: ReactionKind
    var count: Int
    /// Vrai si l'utilisateur a lui-même choisi cette réaction.
    var isChosen: Bool
}

/// Ce que Telegram permet de faire d'un message (`getMessageProperties`, hors ligne).
struct MessageCapabilities: Equatable {
    var canBeReplied = false
    var canBeEdited = false
    var canBeForwarded = false
    var canBePinned = false
    /// Contenu enregistrable, donc copiable ; faux pour un contenu protégé.
    var canBeSaved = false
    var canBeDeletedOnlyForSelf = false
    var canBeDeletedForAllUsers = false
    var canGetLink = false

    var canBeDeleted: Bool { canBeDeletedOnlyForSelf || canBeDeletedForAllUsers }
}

/// Activité d'un participant, affichée sous le titre (« Marie écrit… »).
enum ChatActivity: Equatable {
    case typing
    case recordingVoiceNote
    case recordingVideo
    case sendingFile
    case choosingSticker
    case other
}

/// Message d'une conversation.
struct ChatMessage: Identifiable, Equatable {
    /// Identifiant dans la conversation ; provisoire tant que le message est en cours d'envoi.
    let id: Int64
    let chatId: Int64
    var sender: MessageSenderRef
    var isOutgoing: Bool
    var date: Date
    /// Date de la dernière modification, `nil` si le message n'a jamais été modifié.
    var editDate: Date?
    var body: MessageBody
    var replyTo: MessageReplyRef?
    var forwardOrigin: ForwardOrigin?
    var delivery: MessageDeliveryState
    var isPinned: Bool = false
    var isChannelPost: Bool = false
    /// Signature de l'auteur (publication de chaîne, administrateur anonyme), vide sinon.
    var authorSignature: String = ""
    var containsUnreadMention: Bool = false
    /// Contenu enregistrable (copie autorisée) ; faux pour un contenu protégé.
    var canBeSaved: Bool = true
    var reactions: [MessageReactionCount] = []
    /// Album (photos ou vidéos groupées), 0 sinon.
    var mediaAlbumId: Int64 = 0

    /// Aperçu au format de la liste des conversations (auteur et état d'envoi résolus de la
    /// même façon).
    var preview: MessagePreview {
        MessagePreview(id: id, sender: sender, isOutgoing: isOutgoing, date: date, content: body.content, delivery: delivery)
    }
}

/// Outils sur le texte des messages. Fonctions pures, testées unitairement.
enum MessageTextTools {
    /// Schémas ouverts directement : web, Telegram, courriel. Un lien web peut aussi ouvrir une
    /// app (lien universel YouTube, Plans…), c'est voulu.
    static let directSchemes: Set<String> = ["http", "https", "tg", "mailto"]
    /// Schémas jamais ouverts : sans usage légitime dans un message, ou qui exécuteraient du
    /// code ou liraient un fichier local.
    static let blockedSchemes: Set<String> = ["javascript", "vbscript", "data", "file", "about", "blob"]

    /// Portion de `text` désignée en unités UTF-16 (décalages des entités TDLib), `nil` si la
    /// plage déborde.
    static func substring(of text: String, offset: Int, length: Int) -> String? {
        let string = text as NSString
        guard offset >= 0, length > 0, offset + length <= string.length else { return nil }
        return string.substring(with: NSRange(location: offset, length: length))
    }

    /// Adresse ouvrable : « exemple.fr » devient « https://exemple.fr » ; `nil` pour un schéma
    /// bloqué (« javascript: », « file: »…) ou une adresse invalide. Les liens vers une autre
    /// app (« tel: », « shortcuts: »…) sont gardés : ils s'ouvrent après confirmation
    /// (`requiresConfirmation`).
    static func openableURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var candidate = URL(string: trimmed)
        if let scheme = candidate?.scheme, scheme.contains("."), !trimmed.contains("://") {
            // « exemple.fr:8080/page » se lit comme un schéma « exemple.fr » : c'est une
            // adresse sans schéma (un vrai schéma d'app n'a pas de point, ou est suivi de « :// »).
            candidate = nil
        }
        if candidate?.scheme == nil {
            candidate = URL(string: "https://\(trimmed)")
        }
        guard let url = candidate, let scheme = url.scheme?.lowercased(), !blockedSchemes.contains(scheme) else {
            return nil
        }
        if scheme == "http" || scheme == "https" {
            guard let host = url.host, !host.isEmpty else { return nil }
        }
        return url
    }

    /// Vrai pour un lien vers une autre app (appel, SMS, raccourci, lien profond…) : il peut
    /// déclencher une action que le texte affiché ne laisse pas deviner. L'app demande alors
    /// confirmation en montrant la destination complète.
    static func requiresConfirmation(_ url: URL) -> Bool {
        !directSchemes.contains(url.scheme?.lowercased() ?? "")
    }

    /// Nom court d'un lien, pour l'action « Ouvrir … » : « exemple.fr », « t.me/canal »,
    /// « marie@exemple.fr », « lien Telegram » ; destination complète pour une autre app
    /// (« tel:+33612345678 »).
    static func shortName(_ url: URL) -> String {
        let scheme = url.scheme?.lowercased()
        if scheme == "mailto" {
            return String(url.absoluteString.dropFirst("mailto:".count))
        }
        if scheme == "tg" {
            return "lien Telegram"
        }
        guard scheme == "http" || scheme == "https", let host = url.host?.lowercased() else {
            return url.absoluteString
        }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        // Pour Telegram, le premier élément du chemin (canal, utilisateur) est l'information utile.
        if domain == "t.me" || domain == "telegram.me",
           let first = url.path.split(separator: "/").first {
            return "\(domain)/\(first)"
        }
        return domain
    }
}

/// Changement reçu de TDLib concernant les messages, appliqué par `ConversationState`.
enum MessageEvent: Equatable {
    /// Nouveau message, reçu ou en cours d'envoi (identifiant provisoire).
    case new(ChatMessage)
    /// Envoi réussi : le message définitif remplace le message provisoire `oldId`.
    case sendSucceeded(ChatMessage, oldId: Int64)
    /// Envoi échoué : le message, en état d'échec, remplace le message provisoire `oldId`.
    case sendFailed(ChatMessage, oldId: Int64, error: TelegramError)
    case content(chatId: Int64, messageId: Int64, body: MessageBody)
    case edited(chatId: Int64, messageId: Int64, editDate: Date)
    case pinned(chatId: Int64, messageId: Int64, isPinned: Bool)
    case reactions(chatId: Int64, messageId: Int64, reactions: [MessageReactionCount])
    /// Messages supprimés définitivement (pas un simple retrait du cache).
    case deleted(chatId: Int64, messageIds: [Int64])
    /// Vocal ou message vidéo écouté / vu.
    case opened(chatId: Int64, messageId: Int64)
    /// Activité d'un participant ; `nil` : l'activité a cessé.
    case activity(chatId: Int64, sender: MessageSenderRef, activity: ChatActivity?)
    /// Téléchargement d'un fichier terminé (concerne toutes les conversations).
    case file(FileRef)

    /// Conversation concernée ; `nil` pour un fichier.
    var chatId: Int64? {
        switch self {
        case .new(let message), .sendSucceeded(let message, _), .sendFailed(let message, _, _):
            return message.chatId
        case .content(let chatId, _, _), .edited(let chatId, _, _), .pinned(let chatId, _, _),
             .reactions(let chatId, _, _), .deleted(let chatId, _), .opened(let chatId, _),
             .activity(let chatId, _, _):
            return chatId
        case .file:
            return nil
        }
    }
}
