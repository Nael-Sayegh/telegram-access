import Foundation

/// Message cité par une réponse, résolu pour l'affichage.
struct ReplyLine: Equatable {
    enum Author: Equatable {
        /// Message de l'utilisateur lui-même.
        case me
        case named(String)
        case unknown
    }

    var author: Author
    /// Extrait cité ou contenu du message ; `nil` s'il n'est pas (encore) disponible.
    var text: String?
    var isDeleted = false
}

/// Message prêt à afficher et à lire.
struct MessageRowModel: Identifiable, Equatable {
    let id: Int64
    /// « Vous », nom de l'auteur dans un groupe ; `nil` quand il est implicite (reçu en
    /// tête-à-tête, chaîne sans signature, Messages enregistrés).
    var senderLabel: String?
    var isOutgoing: Bool
    var content: MessageContentSummary
    /// Vocal reçu pas encore écouté, message vidéo reçu pas encore vu.
    var isUnopened = false
    /// « Marie Dupont », « Infos (Jean) » pour un message transféré.
    var forwardedFrom: String?
    var reply: ReplyLine?
    var date: Date
    /// État d'un message envoyé (« lu », « envoyé »…) ; `nil` pour un message reçu.
    var status: String?
    var isEdited = false
    var isPinned = false
    var reactions: [MessageReactionCount] = []
    var links: [URL] = []
    var mediaKind: MessageMedia.Kind?
    var isFailed = false
}

extension ChatListState {
    /// Ligne de `message` dans la conversation `chat`, avec noms et états résolus.
    /// `conversation` sert à retrouver le message cité par une réponse.
    func messageRow(_ message: ChatMessage, in chat: ChatSummary, conversation: ConversationState) -> MessageRowModel {
        let media = message.body.media
        let opens = media.map { $0.kind == .voiceNote || $0.kind == .videoNote } ?? false
        return MessageRowModel(
            id: message.id,
            senderLabel: conversationSender(of: message, in: chat),
            isOutgoing: message.isOutgoing,
            content: message.body.content,
            isUnopened: opens && !message.isOutgoing && !(media?.isListened ?? true),
            forwardedFrom: message.forwardOrigin.map { originName($0) },
            reply: message.replyTo.map { replyLine($0, in: chat, conversation: conversation) },
            date: message.date,
            status: conversationStatus(of: message, in: chat),
            isEdited: message.editDate != nil,
            isPinned: message.isPinned,
            reactions: message.reactions,
            links: message.body.links,
            mediaKind: media?.kind,
            isFailed: message.delivery == .failed
        )
    }

    /// Nom complet de l'auteur d'un message reçu ou cité (sans « Vous »).
    func authorName(of sender: MessageSenderRef, signature: String = "") -> String? {
        switch sender {
        case .user(let userId):
            return users[userId]?.displayName
        case .chat(let chatId):
            let trimmed = signature.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            return chats[chatId].map { displayTitle(of: $0) }
        }
    }

    // MARK: - Privé

    private func conversationSender(of message: ChatMessage, in chat: ChatSummary) -> String? {
        if isSavedMessages(chat) { return nil }
        if chat.kind == .channel || message.isChannelPost {
            // Publication : la chaîne est implicite ; seule une signature apporte une information.
            let signature = message.authorSignature.trimmingCharacters(in: .whitespacesAndNewlines)
            return signature.isEmpty ? nil : signature
        }
        if message.isOutgoing { return "Vous" }
        guard chat.kind.isGroup else { return nil }
        return authorName(of: message.sender, signature: message.authorSignature)
    }

    private func conversationStatus(of message: ChatMessage, in chat: ChatSummary) -> String? {
        guard message.isOutgoing, !isSavedMessages(chat), chat.kind != .channel, !message.isChannelPost else {
            return nil
        }
        switch message.delivery {
        case .pending: return "en cours d'envoi"
        case .failed: return "échec de l'envoi"
        case .sent: return message.id <= chat.lastReadOutboxMessageId ? "lu" : "envoyé"
        }
    }

    /// Auteur d'origine d'un transfert : « Marie Dupont », « Infos (Jean) ».
    private func originName(_ origin: ForwardOrigin) -> String {
        switch origin {
        case .user(let userId):
            return users[userId]?.displayName ?? "un utilisateur"
        case .hiddenUser(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "un utilisateur" : trimmed
        case .chat(let chatId, let signature), .channel(let chatId, let signature):
            let title = chats[chatId].map { displayTitle(of: $0) } ?? "une conversation"
            let trimmed = signature.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? title : "\(title) (\(trimmed))"
        }
    }

    private func replyLine(_ reply: MessageReplyRef, in chat: ChatSummary, conversation: ConversationState) -> ReplyLine {
        let quote = reply.quote.trimmingCharacters(in: .whitespacesAndNewlines)
        // Message d'une autre conversation : TDLib fournit son origine et son contenu.
        if let origin = reply.origin {
            let text = quote.isEmpty ? reply.content.map { MessageLabels.content($0) } : quote
            return ReplyLine(author: .named(originName(origin)), text: text)
        }
        if conversation.deletedIds.contains(reply.messageId) {
            return ReplyLine(author: .unknown, text: nil, isDeleted: true)
        }
        guard let cited = conversation.message(reply.messageId) else {
            return ReplyLine(author: .unknown, text: quote.isEmpty ? nil : quote)
        }
        let author: ReplyLine.Author
        if cited.isOutgoing && !isSavedMessages(chat) {
            author = .me
        } else if let name = authorName(of: cited.sender, signature: cited.authorSignature) {
            author = .named(name)
        } else {
            author = .unknown
        }
        return ReplyLine(author: author, text: quote.isEmpty ? MessageLabels.content(cited.body.content) : quote)
    }
}
