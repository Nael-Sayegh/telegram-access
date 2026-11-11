import Foundation
@preconcurrency import TDLibKit

/// Opérations sur les messages (TDLib 1.8.69).
extension TelegramClient: ConversationService {
    /// Réactions demandées à TDLib par ligne de son sélecteur (sans effet sur le nombre total).
    private static let reactionRowSize = 8
    /// Priorité de téléchargement (1 à 32) : un fichier demandé par l'utilisateur passe en premier.
    private static let downloadPriority = 32

    func openChat(_ chatId: Int64) async throws {
        _ = try await run { try await $0.openChat(chatId: chatId) }
    }

    func closeChat(_ chatId: Int64) async throws {
        _ = try await run { try await $0.closeChat(chatId: chatId) }
    }

    func history(chatId: Int64, from fromMessageId: Int64, offset: Int, limit: Int) async throws -> [ChatMessage] {
        let result = try await run {
            try await $0.getChatHistory(
                chatId: chatId,
                fromMessageId: fromMessageId,
                limit: limit,
                offset: offset,
                onlyLocal: false
            )
        }
        return (result.messages ?? []).map { ChatMessage($0) }
    }

    func message(chatId: Int64, id: Int64) async throws -> ChatMessage {
        let message = try await run { try await $0.getMessage(chatId: chatId, messageId: id) }
        return ChatMessage(message)
    }

    func capabilities(chatId: Int64, messageId: Int64) async throws -> MessageCapabilities {
        let properties = try await run { try await $0.getMessageProperties(chatId: chatId, messageId: messageId) }
        return MessageCapabilities(properties)
    }

    func viewMessages(chatId: Int64, ids: [Int64]) async throws {
        _ = try await run {
            try await $0.viewMessages(
                chatId: chatId,
                forceRead: false,
                messageIds: ids,
                source: .messageSourceChatHistory
            )
        }
    }

    func sendText(_ text: String, chatId: Int64, replyTo: Int64?) async throws -> Int64 {
        let content = InputMessageContent.inputMessageText(Self.inputText(text, clearDraft: true))
        let reply = replyTo.map { Self.inputReply(to: $0) }
        let message = try await run {
            try await $0.sendMessage(
                chatId: chatId,
                inputMessageContent: content,
                options: nil,
                replyMarkup: nil,
                replyTo: reply,
                topicId: nil
            )
        }
        return message.id
    }

    /// Le texte modifié remplace l'ancien sans mise en forme (gras, liens nommés…).
    func editText(_ text: String, chatId: Int64, messageId: Int64) async throws {
        let content = InputMessageContent.inputMessageText(Self.inputText(text, clearDraft: false))
        _ = try await run {
            try await $0.editMessageText(
                chatId: chatId,
                inputMessageContent: content,
                messageId: messageId,
                replyMarkup: nil
            )
        }
    }

    func deleteMessages(chatId: Int64, ids: [Int64], forEveryone: Bool) async throws {
        _ = try await run { try await $0.deleteMessages(chatId: chatId, messageIds: ids, revoke: forEveryone) }
    }

    func forwardMessages(_ ids: [Int64], from chatId: Int64, to targetChatId: Int64) async throws {
        _ = try await run {
            try await $0.forwardMessages(
                chatId: targetChatId,
                fromChatId: chatId,
                messageIds: ids,
                options: nil,
                removeCaption: false,
                sendCopy: false,
                topicId: nil
            )
        }
    }

    func setMessagePinned(chatId: Int64, messageId: Int64, _ isPinned: Bool) async throws {
        if isPinned {
            _ = try await run {
                try await $0.pinChatMessage(
                    chatId: chatId,
                    disableNotification: false,
                    messageId: messageId,
                    onlyForSelf: false
                )
            }
        } else {
            _ = try await run { try await $0.unpinChatMessage(chatId: chatId, messageId: messageId) }
        }
    }

    /// Les émoji personnalisés (Premium) sont écartés : sans texte associé, ils ne peuvent pas
    /// être lus par VoiceOver.
    func availableReactions(chatId: Int64, messageId: Int64) async throws -> [ReactionKind] {
        let available = try await run {
            try await $0.getMessageAvailableReactions(chatId: chatId, messageId: messageId, rowSize: Self.reactionRowSize)
        }
        var seen = Set<ReactionKind>()
        return (available.topReactions + available.recentReactions + available.popularReactions)
            .filter { !$0.needsPremium }
            .map { ReactionKind($0.type) }
            .filter { reaction in
                guard case .emoji = reaction else { return false }
                return seen.insert(reaction).inserted
            }
    }

    func setReaction(_ reaction: ReactionKind, chatId: Int64, messageId: Int64, isChosen: Bool) async throws {
        let type = reaction.tdValue
        if isChosen {
            _ = try await run {
                try await $0.addMessageReaction(
                    chatId: chatId,
                    isBig: false,
                    messageId: messageId,
                    reactionType: type,
                    updateRecentReactions: true
                )
            }
        } else {
            _ = try await run {
                try await $0.removeMessageReaction(chatId: chatId, messageId: messageId, reactionType: type)
            }
        }
    }

    func messageLink(chatId: Int64, messageId: Int64) async throws -> String {
        let link = try await run {
            try await $0.getMessageLink(
                chatId: chatId,
                checklistTaskId: 0,
                forAlbum: false,
                inMessageThread: false,
                mediaTimestamp: 0,
                messageId: messageId,
                pollOptionId: ""
            )
        }
        return link.link
    }

    func resendMessages(chatId: Int64, ids: [Int64]) async throws {
        _ = try await run {
            try await $0.resendMessages(chatId: chatId, messageIds: ids, paidMessageStarCount: 0, quote: nil)
        }
    }

    func downloadFile(_ fileId: Int) async throws -> FileRef {
        let file = try await run {
            try await $0.downloadFile(
                fileId: fileId,
                limit: 0,
                offset: 0,
                priority: Self.downloadPriority,
                synchronous: true
            )
        }
        return FileRef(file)
    }

    func sendVoiceNote(chatId: Int64, file: URL, duration: Int, waveform: Data, replyTo: Int64?) async throws -> Int64 {
        let voiceNote = InputVoiceNote(
            duration: duration,
            voiceNote: .inputFileLocal(InputFileLocal(path: file.path)),
            waveform: waveform
        )
        let content = InputMessageContent.inputMessageVoiceNote(
            InputMessageVoiceNote(caption: nil, selfDestructType: nil, voiceNote: voiceNote)
        )
        let reply = replyTo.map { Self.inputReply(to: $0) }
        let message = try await run {
            try await $0.sendMessage(
                chatId: chatId,
                inputMessageContent: content,
                options: nil,
                replyMarkup: nil,
                replyTo: reply,
                topicId: nil
            )
        }
        return message.id
    }

    func setActivity(chatId: Int64, _ activity: ChatActivity?) async throws {
        let action = ChatActivity.tdValue(activity)
        _ = try await run {
            try await $0.sendChatAction(action: action, businessConnectionId: "", chatId: chatId, topicId: nil)
        }
    }

    // MARK: - Privé

    /// Texte brut : Telegram détecte lui-même liens et mentions.
    private static func inputText(_ text: String, clearDraft: Bool) -> InputMessageText {
        InputMessageText(
            clearDraft: clearDraft,
            linkPreviewOptions: nil,
            text: FormattedText(entities: [], text: text)
        )
    }

    private static func inputReply(to messageId: Int64) -> InputMessageReplyTo {
        .inputMessageReplyToMessage(
            InputMessageReplyToMessage(checklistTaskId: 0, messageId: messageId, pollOptionId: "", quote: nil)
        )
    }
}
