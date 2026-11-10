import Foundation

/// État des conversations reconstruit à partir des changements TDLib. Réducteur pur, sans
/// dépendance à TDLib ni à l'interface : testé unitairement.
///
/// Règles TDLib suivies :
/// - `updateNewChat` précède tout autre changement d'une conversation ; un changement pour
///   une conversation inconnue est ignoré.
/// - Tri décroissant par (`order`, identifiant) ; `order == 0` = absente de la liste. Les
///   conversations épinglées ont déjà un `order` supérieur aux autres.
struct ChatListState {
    private(set) var chats: [Int64: ChatSummary] = [:]
    private(set) var users: [Int64: UserName] = [:]
    /// Sourdine par défaut de chaque portée (secondes, 0 = notifications actives).
    private(set) var scopeMuteFor: [NotificationScope: Int] = [:]
    private(set) var myUserId: Int64?
    private(set) var connection: ConnectionStatus = .connecting
    /// Identifiants des conversations de chaque liste, dans l'ordre d'affichage.
    private(set) var orderedIds: [ChatListKind: [Int64]] = [:]
    /// Compteurs envoyés par TDLib pour chaque liste (y compris non chargée, comme les archives).
    private(set) var listCounts: [ChatListKind: ChatListCounts] = [:]

    // MARK: - Lecture

    /// Conversations de `list`, dans l'ordre d'affichage.
    func chats(in list: ChatListKind) -> [ChatSummary] {
        (orderedIds[list] ?? []).compactMap { chats[$0] }
    }

    /// Vrai si les notifications de la conversation sont coupées (réglage propre ou de sa portée).
    func isMuted(_ chat: ChatSummary) -> Bool {
        let muteFor = chat.muteSetting.usesDefault
            ? scopeMuteFor[chat.kind.notificationScope] ?? 0
            : chat.muteSetting.muteFor
        return muteFor > 0
    }

    /// Vrai pour « Messages enregistrés » (tête-à-tête avec soi-même).
    func isSavedMessages(_ chat: ChatSummary) -> Bool {
        guard let myUserId, case .user(let userId) = chat.kind else { return false }
        return userId == myUserId
    }

    // MARK: - Changements

    mutating func apply(_ event: ChatListEvent) {
        switch event {
        case .newChat(let chat):
            let previous = chats[chat.id]?.positions ?? []
            chats[chat.id] = chat
            reindex(chat.id, from: previous)
        case .title(let chatId, let title):
            update(chatId) { $0.title = title }
        case .lastMessage(let chatId, let message, let positions):
            update(chatId) { $0.lastMessage = message }
            replacePositions(of: chatId, with: positions)
        case .position(let chatId, let position):
            guard var chat = chats[chatId] else { return }
            let previous = chat.positions
            chat.positions.removeAll { $0.list == position.list }
            if position.order != 0 {
                chat.positions.append(position)
            }
            chats[chatId] = chat
            reindex(chatId, from: previous)
        case .readInbox(let chatId, let lastReadMessageId, let unreadCount):
            update(chatId) {
                $0.lastReadInboxMessageId = lastReadMessageId
                $0.unreadCount = unreadCount
            }
        case .readOutbox(let chatId, let lastReadMessageId):
            update(chatId) { $0.lastReadOutboxMessageId = lastReadMessageId }
        case .mentionCount(let chatId, let count):
            update(chatId) { $0.unreadMentionCount = count }
        case .reactionCount(let chatId, let count):
            update(chatId) { $0.unreadReactionCount = count }
        case .markedAsUnread(let chatId, let value):
            update(chatId) { $0.isMarkedAsUnread = value }
        case .muteSetting(let chatId, let setting):
            update(chatId) { $0.muteSetting = setting }
        case .scopeMute(let scope, let muteFor):
            scopeMuteFor[scope] = muteFor
        case .draft(let chatId, let draft, let positions):
            update(chatId) { $0.draft = draft }
            replacePositions(of: chatId, with: positions)
        case .user(let id, let name):
            users[id] = name
        case .myUserId(let id):
            myUserId = id
        case .connection(let status):
            connection = status
        case .listCounts(let list, let total, let unread):
            listCounts[list] = ChatListCounts(total: total, unread: unread)
        }
    }

    // MARK: - Privé

    private mutating func update(_ chatId: Int64, _ change: (inout ChatSummary) -> Void) {
        guard var chat = chats[chatId] else { return }
        change(&chat)
        chats[chatId] = chat
    }

    private mutating func replacePositions(of chatId: Int64, with positions: [ChatListPosition]) {
        guard var chat = chats[chatId] else { return }
        let previous = chat.positions
        chat.positions = positions.filter { $0.order != 0 }
        chats[chatId] = chat
        reindex(chatId, from: previous)
    }

    /// Replace la conversation dans chaque liste où sa position a changé.
    private mutating func reindex(_ chatId: Int64, from previous: [ChatListPosition]) {
        guard let chat = chats[chatId] else { return }
        let lists = Set(previous.map(\.list)).union(chat.positions.map(\.list))
        for list in lists {
            let old = previous.first { $0.list == list && $0.order != 0 }
            let new = chat.position(in: list)
            let isIndexed = orderedIds[list]?.contains(chatId) ?? false
            if old?.order == new?.order, isIndexed == (new != nil) { continue }

            var ids = orderedIds[list] ?? []
            ids.removeAll { $0 == chatId }
            if let new {
                let index = ids.firstIndex { otherId in
                    let otherOrder = chats[otherId]?.position(in: list)?.order ?? 0
                    return (new.order, chatId) > (otherOrder, otherId)
                } ?? ids.endIndex
                ids.insert(chatId, at: index)
            }
            orderedIds[list] = ids
        }
    }
}
