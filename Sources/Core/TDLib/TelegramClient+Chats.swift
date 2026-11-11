import Foundation
@preconcurrency import TDLibKit

extension TelegramClient: TelegramService {}

/// Opérations sur la liste des conversations (TDLib 1.8.69).
extension TelegramClient: ChatListService {
    /// Sourdine sans limite de durée (TDLib plafonne lui-même la valeur).
    private static let muteForever = Int(Int32.max)

    func loadChats(_ list: ChatListKind, limit: Int) async throws -> Bool {
        do {
            _ = try await run { try await $0.loadChats(chatList: list.tdValue, limit: limit) }
            return true
        } catch let error as TelegramError where error.code == 404 {
            // 404 : toutes les conversations de la liste sont déjà chargées.
            return false
        }
    }

    func markAsRead(_ chat: ChatSummary) async throws {
        if let last = chat.lastMessage {
            _ = try await run {
                try await $0.viewMessages(
                    chatId: chat.id,
                    forceRead: true,
                    messageIds: [last.id],
                    source: .messageSourceChatList
                )
            }
        }
        if chat.unreadMentionCount > 0 {
            _ = try await run { try await $0.readAllChatMentions(chatId: chat.id) }
        }
        if chat.unreadReactionCount > 0 {
            _ = try await run { try await $0.readAllChatReactions(chatId: chat.id) }
        }
        if chat.isMarkedAsUnread {
            _ = try await run { try await $0.toggleChatIsMarkedAsUnread(chatId: chat.id, isMarkedAsUnread: false) }
        }
    }

    func setMarkedAsUnread(chatId: Int64, _ isMarkedAsUnread: Bool) async throws {
        _ = try await run { try await $0.toggleChatIsMarkedAsUnread(chatId: chatId, isMarkedAsUnread: isMarkedAsUnread) }
    }

    func setPinned(chatId: Int64, in list: ChatListKind, _ isPinned: Bool) async throws {
        _ = try await run { try await $0.toggleChatIsPinned(chatId: chatId, chatList: list.tdValue, isPinned: isPinned) }
    }

    /// Les réglages de notification comptent 16 champs : on relit ceux de la conversation et on
    /// ne change que la sourdine, pour ne pas écraser le son, l'aperçu, etc.
    func setMuted(chatId: Int64, _ isMuted: Bool) async throws {
        let current = try await run { try await $0.getChat(chatId: chatId) }.notificationSettings
        let updated = ChatNotificationSettings(
            disableMentionNotifications: current.disableMentionNotifications,
            disablePinnedMessageNotifications: current.disablePinnedMessageNotifications,
            muteFor: isMuted ? Self.muteForever : 0,
            muteStories: current.muteStories,
            showPreview: current.showPreview,
            showStoryPoster: current.showStoryPoster,
            soundId: current.soundId,
            storySoundId: current.storySoundId,
            useDefaultDisableMentionNotifications: current.useDefaultDisableMentionNotifications,
            useDefaultDisablePinnedMessageNotifications: current.useDefaultDisablePinnedMessageNotifications,
            useDefaultMuteFor: false,
            useDefaultMuteStories: current.useDefaultMuteStories,
            useDefaultShowPreview: current.useDefaultShowPreview,
            useDefaultShowStoryPoster: current.useDefaultShowStoryPoster,
            useDefaultSound: current.useDefaultSound,
            useDefaultStorySound: current.useDefaultStorySound
        )
        _ = try await run { try await $0.setChatNotificationSettings(chatId: chatId, notificationSettings: updated) }
    }

    func moveChat(chatId: Int64, to list: ChatListKind) async throws {
        _ = try await run { try await $0.addChatToList(chatId: chatId, chatList: list.tdValue) }
    }

    /// N'utilise jamais `deleteChat` de TDLib, qui supprime un groupe pour tous ses membres.
    func deleteChat(_ chat: ChatSummary, forEveryone: Bool) async throws {
        switch chat.kind {
        case .user:
            let revoke = forEveryone && chat.canBeDeletedForAllUsers
            _ = try await run {
                try await $0.deleteChatHistory(chatId: chat.id, removeFromChatList: true, revoke: revoke)
            }
        case .secret(let secretChatId, _):
            _ = try await run { try await $0.closeSecretChat(secretChatId: secretChatId) }
            _ = try await run {
                try await $0.deleteChatHistory(chatId: chat.id, removeFromChatList: true, revoke: false)
            }
        case .basicGroup:
            // Un groupe simple reste dans la liste après l'avoir quitté : on efface aussi l'historique.
            _ = try await run { try await $0.leaveChat(chatId: chat.id) }
            _ = try await run {
                try await $0.deleteChatHistory(chatId: chat.id, removeFromChatList: true, revoke: false)
            }
        case .supergroup, .channel:
            // Quitter suffit à retirer la conversation de la liste.
            _ = try await run { try await $0.leaveChat(chatId: chat.id) }
        }
    }

    func searchChats(_ query: String, limit: Int) async throws -> [Int64] {
        let local = try await run { try await $0.searchChats(limit: limit, query: query, typeFilter: nil) }.chatIds
        let remote = try await run {
            try await $0.searchChatsOnServer(limit: limit, query: query, typeFilter: nil)
        }.chatIds
        var seen = Set<Int64>()
        return (local + remote).filter { seen.insert($0).inserted }
    }

    func searchPublicChats(_ query: String) async throws -> [Int64] {
        try await run { try await $0.searchPublicChats(query: query, typeFilter: nil) }.chatIds
    }

    func searchMessages(_ query: String, offset: String, limit: Int) async throws -> MessageSearchPage {
        let found = try await run {
            try await $0.searchMessages(
                chatList: nil,
                chatTypeFilter: nil,
                filter: nil,
                limit: limit,
                maxDate: 0,
                minDate: 0,
                offset: offset,
                query: query
            )
        }
        return MessageSearchPage(
            results: found.messages.map { MessageSearchResult(chatId: $0.chatId, message: MessagePreview($0)) },
            nextOffset: found.nextOffset
        )
    }
}
