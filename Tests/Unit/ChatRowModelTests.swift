import XCTest
@testable import TelegramAccess

/// Construction des lignes à partir de l'état : noms, auteurs, états d'envoi.
final class ChatRowModelTests: XCTestCase {
    private func makeState(_ events: ChatListEvent...) -> ChatListState {
        var state = ChatListState()
        events.forEach { state.apply($0) }
        return state
    }

    private func makeRow(_ chatId: Int64, _ state: ChatListState) -> ChatRowModel {
        state.row(for: state.chats[chatId]!, in: .main)
    }

    func testSavedMessages() {
        let message = ChatTestData.message(sender: .user(42), outgoing: true)
        let state = makeState(
            .myUserId(42),
            .newChat(ChatTestData.chat(42, kind: .user(userId: 42), title: "Moi", lastMessage: message))
        )
        let row = makeRow(42, state)
        XCTAssertEqual(row.title, "Messages enregistrés")
        XCTAssertNil(row.lastMessage?.senderLabel)
        XCTAssertNil(row.lastMessage?.status)
    }

    func testEmptyTitleUsesPeerName() {
        let state = makeState(
            .user(id: 7, name: UserName(firstName: "Marie", lastName: "Dupont", isDeleted: false)),
            .newChat(ChatTestData.chat(1, kind: .user(userId: 7), title: ""))
        )
        XCTAssertEqual(makeRow(1, state).title, "Marie Dupont")
    }

    func testEmptyTitleOfUnknownPeerIsDeletedAccount() {
        let state = makeState(.newChat(ChatTestData.chat(1, kind: .user(userId: 7), title: " ")))
        XCTAssertEqual(makeRow(1, state).title, "Compte supprimé")
    }

    func testGroupMessageShowsSenderFirstName() {
        let state = makeState(
            .user(id: 5, name: UserName(firstName: "Paul", lastName: "Martin", isDeleted: false)),
            .newChat(ChatTestData.chat(1, kind: .supergroup, title: "Famille", lastMessage: ChatTestData.message(sender: .user(5))))
        )
        XCTAssertEqual(makeRow(1, state).lastMessage?.senderLabel, "Paul")
    }

    func testPrivateIncomingMessageHasNoSender() {
        let state = makeState(.newChat(ChatTestData.chat(1, lastMessage: ChatTestData.message())))
        XCTAssertNil(makeRow(1, state).lastMessage?.senderLabel)
        XCTAssertNil(makeRow(1, state).lastMessage?.status)
    }

    func testOutgoingMessageStatus() {
        let pending = makeState(.newChat(ChatTestData.chat(1, lastMessage: ChatTestData.message(100, outgoing: true, delivery: .pending))))
        XCTAssertEqual(makeRow(1, pending).lastMessage?.status, "en cours d'envoi")
        XCTAssertEqual(makeRow(1, pending).lastMessage?.senderLabel, "Vous")

        let sent = makeState(.newChat(ChatTestData.chat(1, lastMessage: ChatTestData.message(100, outgoing: true))))
        XCTAssertEqual(makeRow(1, sent).lastMessage?.status, "envoyé")

        let read = makeState(.newChat(ChatTestData.chat(1, lastMessage: ChatTestData.message(100, outgoing: true), lastReadOutbox: 100)))
        XCTAssertEqual(makeRow(1, read).lastMessage?.status, "lu")
    }

    func testChannelPostHasNoReadStatus() {
        let state = makeState(.newChat(ChatTestData.chat(1, kind: .channel, title: "Infos", lastMessage: ChatTestData.message(outgoing: true))))
        XCTAssertNil(makeRow(1, state).lastMessage?.status)
    }

    func testPinnedAndMutedFlags() {
        let state = makeState(
            .scopeMute(scope: .groups, muteFor: 3600),
            .newChat(ChatTestData.chat(1, kind: .basicGroup, title: "Club", pinned: true))
        )
        let row = makeRow(1, state)
        XCTAssertTrue(row.isPinned)
        XCTAssertTrue(row.isMuted)
    }
}
