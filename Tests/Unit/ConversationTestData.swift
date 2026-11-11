import Foundation
@testable import TelegramAccess

/// Données de test communes aux tests de l'écran de conversation.
enum ConversationTestData {
    static let chatId: Int64 = 1
    static let marie: Int64 = 7
    static let paul: Int64 = 5
    static let me: Int64 = 42

    /// Message texte de la conversation `chatId`, à 14 h 32 le 10 novembre 2026 par défaut.
    static func message(
        _ id: Int64,
        text: String = "Bonjour",
        chatId: Int64 = chatId,
        sender: MessageSenderRef = .user(marie),
        outgoing: Bool = false,
        date: Date = ChatTestData.date(2026, 11, 10, 14, 32),
        delivery: MessageDeliveryState = .sent,
        replyTo: MessageReplyRef? = nil,
        forward: ForwardOrigin? = nil,
        media: MessageMedia? = nil,
        content: MessageContentSummary? = nil
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            chatId: chatId,
            sender: sender,
            isOutgoing: outgoing,
            date: date,
            body: MessageBody(content: content ?? .text(text), media: media),
            replyTo: replyTo,
            forwardOrigin: forward,
            delivery: delivery
        )
    }

    /// Noms connus : Marie Dupont, Paul Martin et soi-même.
    static func listState(chats: [ChatSummary]) -> ChatListState {
        var state = ChatListState()
        state.apply(.myUserId(me))
        state.apply(.user(id: marie, name: UserName(firstName: "Marie", lastName: "Dupont", isDeleted: false)))
        state.apply(.user(id: paul, name: UserName(firstName: "Paul", lastName: "Martin", isDeleted: false)))
        state.apply(.user(id: me, name: UserName(firstName: "Moi", lastName: "", isDeleted: false)))
        for chat in chats {
            state.apply(.newChat(chat))
        }
        return state
    }

    /// État de conversation chargé jusqu'au dernier message.
    static func loadedState(_ messages: [ChatMessage], chatId: Int64 = chatId) -> ConversationState {
        var state = ConversationState(chatId: chatId)
        state.reset(with: messages, isLatest: true)
        return state
    }
}
