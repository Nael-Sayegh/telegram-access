import XCTest
@testable import TelegramAccess

/// Messages reçus pendant l'affichage : jamais de focus déplacé, bouton « n nouveaux messages »
/// jusqu'à ce qu'ils soient vus.
@MainActor
final class ConversationNewMessagesTests: XCTestCase {
    private typealias Fixture = ConversationTestData

    /// Conversation avec Marie ouverte sur `messages` (du plus récent au plus ancien).
    private func openModel(_ messages: [ChatMessage]) async -> (ConversationViewModel, FakeAuthService) {
        let service = FakeAuthService()
        await service.setHistoryPages([messages])
        let store = ChatStore(events: service.chatEvents)
        let chat = ChatTestData.chat(Fixture.chatId)
        service.send(.newChat(chat))
        await waitUntil { store.state.chats[chat.id] != nil }
        let hub = MessageHub(events: service.messageEvents)
        let model = ConversationViewModel(chatId: chat.id, store: store, hub: hub, service: service)
        await model.open()
        return (model, service)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition non remplie à temps", file: file, line: line)
    }

    func testIncomingMessagesAreCountedUntilSeenWithoutMovingFocus() async {
        let (model, service) = await openModel([Fixture.message(10)])
        let focusAtOpen = model.focusRequest

        service.send(.new(Fixture.message(12)))
        service.send(.new(Fixture.message(11)))
        service.send(.new(Fixture.message(13, sender: .user(Fixture.me), outgoing: true)))
        await waitUntil { model.state.orderedIds == [10, 11, 12, 13] }
        XCTAssertEqual(model.unseenIncomingIds, [11, 12], "Messages reçus seulement, dans l'ordre")
        XCTAssertEqual(model.focusRequest, focusAtOpen, "Un message reçu ne déplace jamais le focus")

        model.messagesVisible([11])
        XCTAssertEqual(model.unseenIncomingIds, [12])
        model.messagesVisible([12, 13])
        XCTAssertTrue(model.unseenIncomingIds.isEmpty)
    }

    func testButtonFocusesTheFirstUnseenMessage() async {
        let (model, service) = await openModel([Fixture.message(10)])
        service.send(.new(Fixture.message(11)))
        service.send(.new(Fixture.message(12)))
        await waitUntil { model.unseenIncomingIds == [11, 12] }

        await model.showFirstUnseen()
        XCTAssertEqual(model.focusRequest?.messageId, 11)
        XCTAssertEqual(model.focusRequest?.position, .top)
    }

    func testDeletedMessageIsNoLongerCounted() async {
        let (model, service) = await openModel([Fixture.message(10)])
        service.send(.new(Fixture.message(11)))
        await waitUntil { model.unseenIncomingIds == [11] }
        service.send(.deleted(chatId: Fixture.chatId, messageIds: [11]))
        await waitUntil { model.unseenIncomingIds.isEmpty }
    }

    func testButtonLabel() {
        XCTAssertEqual(ConversationLabels.newMessages(1), "1 nouveau message")
        XCTAssertEqual(ConversationLabels.newMessages(3), "3 nouveaux messages")
    }
}
