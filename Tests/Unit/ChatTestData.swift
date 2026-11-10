import Foundation
@testable import TelegramAccess

/// Données de test communes aux tests de la liste des conversations.
enum ChatTestData {
    /// Calendrier figé : français, heure de Paris.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Mardi 10 novembre 2026, 18 h.
    static let now = date(2026, 11, 10, 18, 0)

    static func chat(
        _ id: Int64,
        kind: ChatKind = .user(userId: 7),
        title: String = "Marie Dupont",
        order: Int64 = 10,
        pinned: Bool = false,
        lastMessage: MessagePreview? = nil,
        lastReadOutbox: Int64 = 0,
        mute: ChatMuteSetting = ChatMuteSetting(usesDefault: true, muteFor: 0)
    ) -> ChatSummary {
        ChatSummary(
            id: id,
            kind: kind,
            title: title,
            positions: [ChatListPosition(list: .main, order: order, isPinned: pinned)],
            lastMessage: lastMessage,
            unreadCount: 0,
            unreadMentionCount: 0,
            unreadReactionCount: 0,
            isMarkedAsUnread: false,
            lastReadInboxMessageId: 0,
            lastReadOutboxMessageId: lastReadOutbox,
            muteSetting: mute,
            draft: nil,
            canBeDeletedOnlyForSelf: true,
            canBeDeletedForAllUsers: false
        )
    }

    static func message(
        _ id: Int64 = 100,
        text: String = "Bonjour",
        sender: MessageSenderRef = .user(7),
        outgoing: Bool = false,
        delivery: MessageDeliveryState = .sent,
        date: Date = now
    ) -> MessagePreview {
        MessagePreview(id: id, sender: sender, isOutgoing: outgoing, date: date, content: .text(text), delivery: delivery)
    }

    static func row(
        title: String = "Marie Dupont",
        kind: ChatKind = .user(userId: 7),
        unread: Int = 0,
        mentions: Int = 0,
        markedUnread: Bool = false,
        pinned: Bool = false,
        muted: Bool = false,
        draft: DraftSummary? = nil,
        lastMessage: LastMessageLine? = nil
    ) -> ChatRowModel {
        ChatRowModel(
            id: 1,
            title: title,
            kind: kind,
            unreadCount: unread,
            unreadMentionCount: mentions,
            isMarkedAsUnread: markedUnread,
            isPinned: pinned,
            isMuted: muted,
            draft: draft,
            lastMessage: lastMessage
        )
    }
}
