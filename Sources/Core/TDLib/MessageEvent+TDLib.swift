import Foundation
@preconcurrency import TDLibKit

// Conversion des updates et objets TDLib en types de l'écran de conversation.
// Seul endroit, avec `TelegramClient`, où les messages dépendent de TDLibKit.

extension MessageEvent {
    /// `nil` pour un update sans rapport avec les messages.
    init?(_ update: Update) {
        switch update {
        case .updateNewMessage(let value):
            self = .new(ChatMessage(value.message))
        case .updateMessageSendSucceeded(let value):
            self = .sendSucceeded(ChatMessage(value.message), oldId: value.oldMessageId)
        case .updateMessageSendFailed(let value):
            self = .sendFailed(
                ChatMessage(value.message),
                oldId: value.oldMessageId,
                error: TelegramError(code: value.error.code, message: value.error.message)
            )
        case .updateMessageContent(let value):
            self = .content(chatId: value.chatId, messageId: value.messageId, body: MessageBody(value.newContent))
        case .updateMessageEdited(let value):
            self = .edited(chatId: value.chatId, messageId: value.messageId, editDate: Self.date(value.editDate))
        case .updateMessageIsPinned(let value):
            self = .pinned(chatId: value.chatId, messageId: value.messageId, isPinned: value.isPinned)
        case .updateMessageInteractionInfo(let value):
            self = .reactions(
                chatId: value.chatId,
                messageId: value.messageId,
                reactions: MessageReactionCount.list(from: value.interactionInfo)
            )
        case .updateDeleteMessages(let value):
            // Retrait du cache seulement : les messages existent toujours, on les garde affichés.
            guard !value.fromCache else { return nil }
            self = .deleted(chatId: value.chatId, messageIds: value.messageIds)
        case .updateMessageContentOpened(let value):
            self = .opened(chatId: value.chatId, messageId: value.messageId)
        case .updateChatAction(let value):
            self = .activity(
                chatId: value.chatId,
                sender: MessageSenderRef(value.senderId),
                activity: ChatActivity(value.action)
            )
        case .updateFile(let value):
            // Seule la fin d'un téléchargement intéresse l'écran (la progression arrive en rafale).
            guard value.file.local.isDownloadingCompleted else { return nil }
            self = .file(FileRef(value.file))
        default:
            return nil
        }
    }

    static func date(_ timestamp: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}

extension ChatMessage {
    init(_ message: Message) {
        self.init(
            id: message.id,
            chatId: message.chatId,
            sender: MessageSenderRef(message.senderId),
            isOutgoing: message.isOutgoing,
            date: MessageEvent.date(message.date),
            editDate: message.editDate > 0 ? MessageEvent.date(message.editDate) : nil,
            body: MessageBody(message.content),
            replyTo: message.replyTo.flatMap { MessageReplyRef($0) },
            forwardOrigin: message.forwardInfo.map { ForwardOrigin($0.origin) },
            delivery: MessageDeliveryState(message.sendingState),
            isPinned: message.isPinned,
            isChannelPost: message.isChannelPost,
            authorSignature: message.authorSignature,
            containsUnreadMention: message.containsUnreadMention,
            canBeSaved: message.canBeSaved,
            reactions: MessageReactionCount.list(from: message.interactionInfo),
            mediaAlbumId: message.mediaAlbumId.rawValue
        )
    }
}

extension MessageSenderRef {
    init(_ sender: MessageSender) {
        switch sender {
        case .messageSenderUser(let value): self = .user(value.userId)
        case .messageSenderChat(let value): self = .chat(value.chatId)
        }
    }
}

extension MessageDeliveryState {
    init(_ state: MessageSendingState?) {
        switch state {
        case .messageSendingStatePending?: self = .pending
        case .messageSendingStateFailed?: self = .failed
        case nil: self = .sent
        }
    }
}

extension MessageBody {
    init(_ content: MessageContent) {
        var text: FormattedText?
        var media: MessageMedia?
        switch content {
        case .messageText(let value):
            text = value.text
        case .messagePhoto(let value):
            text = value.caption
            media = MessageMedia.photo(value.photo)
        case .messageVideo(let value):
            text = value.caption
            media = MessageMedia(kind: .video, file: FileRef(value.video.video))
        case .messageAnimation(let value):
            text = value.caption
            media = MessageMedia(kind: .animation, file: FileRef(value.animation.animation))
        case .messageVoiceNote(let value):
            text = value.caption
            media = MessageMedia(
                kind: .voiceNote,
                file: FileRef(value.voiceNote.voice),
                isListened: value.isListened,
                waveform: value.voiceNote.waveform
            )
        case .messageVideoNote(let value):
            media = MessageMedia(
                kind: .videoNote,
                file: FileRef(value.videoNote.video),
                isListened: value.isViewed,
                waveform: value.videoNote.waveform
            )
        case .messageAudio(let value):
            text = value.caption
            media = MessageMedia(kind: .audio, file: FileRef(value.audio.audio))
        case .messageDocument(let value):
            text = value.caption
            media = MessageMedia(kind: .document, file: FileRef(value.document.document))
        case .messageSticker(let value):
            media = MessageMedia(kind: .sticker, file: FileRef(value.sticker.sticker))
        default:
            break
        }
        self.init(
            content: MessageContentSummary(content),
            links: text.map { Self.links(in: $0) } ?? [],
            mentionedUserIds: text.map { Self.mentions(in: $0) } ?? [],
            media: media
        )
    }

    /// Liens du texte : adresses écrites (« exemple.fr ») et liens nommés, sans doublon.
    /// Les décalages des entités TDLib sont en unités UTF-16.
    static func links(in text: FormattedText) -> [URL] {
        var result: [URL] = []
        for entity in text.entities {
            let raw: String?
            switch entity.type {
            case .textEntityTypeUrl:
                raw = MessageTextTools.substring(of: text.text, offset: entity.offset, length: entity.length)
            case .textEntityTypeTextUrl(let value):
                raw = value.url
            default:
                raw = nil
            }
            if let raw, let url = MessageTextTools.openableURL(raw), !result.contains(url) {
                result.append(url)
            }
        }
        return result
    }

    /// Utilisateurs mentionnés par un lien de mention (sans nom d'utilisateur public).
    static func mentions(in text: FormattedText) -> [Int64] {
        text.entities.compactMap { entity in
            if case .textEntityTypeMentionName(let value) = entity.type {
                return value.userId
            }
            return nil
        }
    }
}

extension MessageMedia {
    /// Plus grande taille ne dépassant pas 1280 pixels (assez pour décrire l'image sur
    /// l'appareil sans télécharger l'original), à défaut la plus petite.
    static func photo(_ photo: Photo) -> MessageMedia? {
        let sizes = photo.sizes.sorted { $0.width * $0.height < $1.width * $1.height }
        guard let size = sizes.last(where: { max($0.width, $0.height) <= 1280 }) ?? sizes.first else {
            return nil
        }
        return MessageMedia(kind: .photo, file: FileRef(size.photo))
    }
}

extension FileRef {
    init(_ file: File) {
        let local = file.local
        self.init(
            id: file.id,
            size: max(file.size, file.expectedSize),
            localPath: local.isDownloadingCompleted && !local.path.isEmpty ? local.path : nil
        )
    }
}

extension MessageReplyRef {
    /// `nil` pour une réponse à une story.
    init?(_ replyTo: MessageReplyTo) {
        guard case .messageReplyToMessage(let value) = replyTo else { return nil }
        self.init(
            chatId: value.chatId,
            messageId: value.messageId,
            origin: value.origin.map { ForwardOrigin($0) },
            content: value.content.map { MessageContentSummary($0) },
            quote: value.quote?.text.text ?? ""
        )
    }
}

extension ForwardOrigin {
    init(_ origin: MessageOrigin) {
        switch origin {
        case .messageOriginUser(let value):
            self = .user(value.senderUserId)
        case .messageOriginHiddenUser(let value):
            self = .hiddenUser(name: value.senderName)
        case .messageOriginChat(let value):
            self = .chat(value.senderChatId, signature: value.authorSignature)
        case .messageOriginChannel(let value):
            self = .channel(value.chatId, signature: value.authorSignature)
        }
    }
}

extension MessageReactionCount {
    static func list(from info: MessageInteractionInfo?) -> [MessageReactionCount] {
        (info?.reactions?.reactions ?? []).map {
            MessageReactionCount(kind: ReactionKind($0.type), count: $0.totalCount, isChosen: $0.isChosen)
        }
    }
}

extension ReactionKind {
    init(_ type: ReactionType) {
        switch type {
        case .reactionTypeEmoji(let value): self = .emoji(value.emoji)
        case .reactionTypeCustomEmoji(let value): self = .customEmoji(value.customEmojiId.rawValue)
        case .reactionTypePaid: self = .paid
        }
    }

    var tdValue: ReactionType {
        switch self {
        case .emoji(let emoji):
            return .reactionTypeEmoji(ReactionTypeEmoji(emoji: emoji))
        case .customEmoji(let id):
            return .reactionTypeCustomEmoji(ReactionTypeCustomEmoji(customEmojiId: TdInt64(id)))
        case .paid:
            return .reactionTypePaid
        }
    }
}

extension MessageCapabilities {
    init(_ properties: MessageProperties) {
        self.init(
            canBeReplied: properties.canBeReplied,
            canBeEdited: properties.canBeEdited,
            canBeForwarded: properties.canBeForwarded,
            canBePinned: properties.canBePinned,
            canBeSaved: properties.canBeSaved,
            canBeDeletedOnlyForSelf: properties.canBeDeletedOnlyForSelf,
            canBeDeletedForAllUsers: properties.canBeDeletedForAllUsers,
            canGetLink: properties.canGetLink
        )
    }
}

extension ChatActivity {
    /// `nil` quand l'activité cesse (`chatActionCancel`).
    init?(_ action: ChatAction) {
        switch action {
        case .chatActionTyping:
            self = .typing
        case .chatActionRecordingVoiceNote:
            self = .recordingVoiceNote
        case .chatActionRecordingVideo, .chatActionRecordingVideoNote:
            self = .recordingVideo
        case .chatActionUploadingVideo, .chatActionUploadingVoiceNote, .chatActionUploadingPhoto,
             .chatActionUploadingDocument, .chatActionUploadingVideoNote:
            self = .sendingFile
        case .chatActionChoosingSticker:
            self = .choosingSticker
        case .chatActionCancel:
            return nil
        default:
            self = .other
        }
    }

    /// Action envoyée à TDLib pour sa propre activité ; seules la saisie et l'enregistrement
    /// d'un vocal sont signalés, le reste annule l'activité.
    static func tdValue(_ activity: ChatActivity?) -> ChatAction {
        switch activity {
        case .typing?: return .chatActionTyping
        case .recordingVoiceNote?: return .chatActionRecordingVoiceNote
        default: return .chatActionCancel
        }
    }
}
