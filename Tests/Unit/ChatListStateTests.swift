import XCTest
@testable import TelegramAccess

final class ChatListStateTests: XCTestCase {
    private func chat(
        _ id: Int64,
        kind: ChatKind = .basicGroup,
        main order: Int64? = nil,
        archive archiveOrder: Int64? = nil,
        pinned: Bool = false,
        mute: ChatMuteSetting = ChatMuteSetting(usesDefault: true, muteFor: 0)
    ) -> ChatSummary {
        var positions: [ChatListPosition] = []
        if let order { positions.append(ChatListPosition(list: .main, order: order, isPinned: pinned)) }
        if let archiveOrder { positions.append(ChatListPosition(list: .archive, order: archiveOrder, isPinned: false)) }
        return ChatSummary(
            id: id,
            kind: kind,
            title: "Chat \(id)",
            positions: positions,
            lastMessage: nil,
            unreadCount: 0,
            unreadMentionCount: 0,
            unreadReactionCount: 0,
            isMarkedAsUnread: false,
            lastReadInboxMessageId: 0,
            lastReadOutboxMessageId: 0,
            muteSetting: mute,
            draft: nil,
            canBeDeletedOnlyForSelf: true,
            canBeDeletedForAllUsers: false
        )
    }

    private func message(_ id: Int64, outgoing: Bool = false) -> MessagePreview {
        MessagePreview(
            id: id,
            sender: .user(outgoing ? 1 : 2),
            isOutgoing: outgoing,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            content: .text("Bonjour"),
            delivery: .sent
        )
    }

    private func ids(_ state: ChatListState, _ list: ChatListKind = .main) -> [Int64] {
        state.chats(in: list).map(\.id)
    }

    // MARK: - Tri

    func testChatsAreSortedByDescendingOrder() {
        var state = ChatListState()
        state.apply(.newChat(chat(1, main: 10)))
        state.apply(.newChat(chat(2, main: 30)))
        state.apply(.newChat(chat(3, main: 20)))
        XCTAssertEqual(ids(state), [2, 3, 1])
    }

    func testEqualOrdersAreSortedByDescendingId() {
        var state = ChatListState()
        state.apply(.newChat(chat(5, main: 10)))
        state.apply(.newChat(chat(9, main: 10)))
        state.apply(.newChat(chat(7, main: 10)))
        XCTAssertEqual(ids(state), [9, 7, 5])
    }

    func testChatWithoutPositionIsNotListed() {
        var state = ChatListState()
        state.apply(.newChat(chat(1)))
        XCTAssertEqual(ids(state), [])
        XCTAssertNotNil(state.chats[1])
    }

    func testPositionUpdateMovesChat() {
        var state = ChatListState()
        state.apply(.newChat(chat(1, main: 10)))
        state.apply(.newChat(chat(2, main: 20)))
        state.apply(.position(chatId: 1, position: ChatListPosition(list: .main, order: 30, isPinned: false)))
        XCTAssertEqual(ids(state), [1, 2])
    }

    func testZeroOrderRemovesChatFromList() {
        var state = ChatListState()
        state.apply(.newChat(chat(1, main: 10)))
        state.apply(.position(chatId: 1, position: ChatListPosition(list: .main, order: 0, isPinned: false)))
        XCTAssertEqual(ids(state), [])
        XCTAssertNil(state.chats[1]?.position(in: .main))
    }

    func testArchivingMovesChatBetweenLists() {
        var state = ChatListState()
        state.apply(.newChat(chat(1, main: 10)))
        state.apply(.position(chatId: 1, position: ChatListPosition(list: .main, order: 0, isPinned: false)))
        state.apply(.position(chatId: 1, position: ChatListPosition(list: .archive, order: 10, isPinned: false)))
        XCTAssertEqual(ids(state, .main), [])
        XCTAssertEqual(ids(state, .archive), [1])
    }

    func testNewMessageMovesChatToTopAndReplacesPositions() {
        var state = ChatListState()
        state.apply(.newChat(chat(1, main: 10, archive: 5)))
        state.apply(.newChat(chat(2, main: 20)))
        state.apply(.lastMessage(
            chatId: 1,
            message: message(100),
            positions: [ChatListPosition(list: .main, order: 40, isPinned: false)]
        ))
        XCTAssertEqual(ids(state), [1, 2])
        XCTAssertEqual(state.chats[1]?.lastMessage?.id, 100)
        // Les positions reçues remplacent toutes les autres.
        XCTAssertEqual(ids(state, .archive), [])
    }

    func testDraftUpdateCanReorder() {
        var state = ChatListState()
        state.apply(.newChat(chat(1, main: 10)))
        state.apply(.newChat(chat(2, main: 20)))
        state.apply(.draft(chatId: 1, draft: .text("À suivre"), positions: [ChatListPosition(list: .main, order: 25, isPinned: false)]))
        XCTAssertEqual(ids(state), [1, 2])
        XCTAssertEqual(state.chats[1]?.draft, .text("À suivre"))
    }

    // MARK: - Compteurs et réglages

    func testReadAndMentionCounters() {
        var state = ChatListState()
        state.apply(.newChat(chat(1, main: 10)))
        state.apply(.readInbox(chatId: 1, lastReadMessageId: 50, unreadCount: 3))
        state.apply(.mentionCount(chatId: 1, count: 1))
        state.apply(.markedAsUnread(chatId: 1, value: true))
        let summary = state.chats[1]
        XCTAssertEqual(summary?.unreadCount, 3)
        XCTAssertEqual(summary?.unreadMentionCount, 1)
        XCTAssertEqual(summary?.isMarkedAsUnread, true)
        XCTAssertEqual(summary?.hasUnread, true)
    }

    func testOutgoingMessageReadState() {
        var state = ChatListState()
        state.apply(.newChat(chat(1, main: 10)))
        state.apply(.lastMessage(chatId: 1, message: message(100, outgoing: true), positions: [ChatListPosition(list: .main, order: 10, isPinned: false)]))
        XCTAssertEqual(state.chats[1]?.isLastOutgoingMessageRead, false)
        state.apply(.readOutbox(chatId: 1, lastReadMessageId: 100))
        XCTAssertEqual(state.chats[1]?.isLastOutgoingMessageRead, true)
    }

    func testMuteFollowsScopeByDefault() {
        var state = ChatListState()
        let channel = chat(1, kind: .channel, main: 10)
        state.apply(.newChat(channel))
        XCTAssertFalse(state.isMuted(channel))
        state.apply(.scopeMute(scope: .channels, muteFor: 3600))
        XCTAssertTrue(state.isMuted(channel))
        // La portée des groupes n'affecte pas une chaîne.
        state.apply(.scopeMute(scope: .groups, muteFor: 0))
        XCTAssertTrue(state.isMuted(channel))
    }

    func testOwnMuteSettingOverridesScope() {
        var state = ChatListState()
        state.apply(.scopeMute(scope: .privateChats, muteFor: 3600))
        state.apply(.newChat(chat(1, kind: .user(userId: 7), main: 10)))
        state.apply(.muteSetting(chatId: 1, setting: ChatMuteSetting(usesDefault: false, muteFor: 0)))
        XCTAssertFalse(state.isMuted(state.chats[1]!))
    }

    func testSecretChatUsesPrivateScope() {
        XCTAssertEqual(ChatKind.secret(secretChatId: 3, userId: 7).notificationScope, .privateChats)
        XCTAssertEqual(ChatKind.secret(secretChatId: 3, userId: 7).peerUserId, 7)
    }

    // MARK: - Divers

    func testEventsForUnknownChatAreIgnored() {
        var state = ChatListState()
        state.apply(.title(chatId: 99, title: "Inconnu"))
        state.apply(.position(chatId: 99, position: ChatListPosition(list: .main, order: 10, isPinned: false)))
        XCTAssertTrue(state.chats.isEmpty)
        XCTAssertEqual(ids(state), [])
    }

    func testSavedMessagesIsChatWithSelf() {
        var state = ChatListState()
        let saved = chat(42, kind: .user(userId: 42), main: 10)
        state.apply(.newChat(saved))
        XCTAssertFalse(state.isSavedMessages(saved))
        state.apply(.myUserId(42))
        XCTAssertTrue(state.isSavedMessages(saved))
    }

    func testUserDisplayName() {
        XCTAssertEqual(UserName(firstName: "Marie", lastName: "Dupont", isDeleted: false).displayName, "Marie Dupont")
        XCTAssertEqual(UserName(firstName: "Marie", lastName: " ", isDeleted: false).displayName, "Marie")
        XCTAssertEqual(UserName(firstName: "", lastName: "", isDeleted: false).displayName, "Compte supprimé")
        XCTAssertEqual(UserName(firstName: "Marie", lastName: "", isDeleted: true).displayName, "Compte supprimé")
    }

    func testConnectionStatus() {
        var state = ChatListState()
        XCTAssertEqual(state.connection, .connecting)
        state.apply(.connection(.waitingForNetwork))
        XCTAssertEqual(state.connection, .waitingForNetwork)
    }
}
