import XCTest
@testable import TelegramAccess

@MainActor
final class ConversationViewModelTests: XCTestCase {
    private typealias Fixture = ConversationTestData

    /// Modèle de la conversation 1 (Marie), avec le résumé `chat` déjà dans le store.
    private func makeModel(
        chat: ChatSummary = ChatTestData.chat(ConversationTestData.chatId),
        pages: [[ChatMessage]] = []
    ) async -> (ConversationViewModel, FakeAuthService) {
        let service = FakeAuthService()
        await service.setHistoryPages(pages)
        let store = ChatStore(events: service.chatEvents)
        service.send(.newChat(chat))
        await waitUntil { store.state.chats[chat.id] != nil }
        let hub = MessageHub(events: service.messageEvents)
        let model = ConversationViewModel(chatId: chat.id, store: store, hub: hub, service: service)
        return (model, service)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition non remplie à temps", file: file, line: line)
    }

    /// Conversation sans non lus : derniers messages, focus sur le dernier.
    func testOpeningLoadsLatestMessagesAndFocusesTheLastOne() async {
        let (model, service) = await makeModel(pages: [[Fixture.message(30), Fixture.message(20), Fixture.message(10)]])
        await model.open()

        XCTAssertEqual(model.state.orderedIds, [10, 20, 30])
        XCTAssertTrue(model.state.reachedLatest)
        XCTAssertFalse(model.isOpening)
        XCTAssertEqual(model.focusRequest?.messageId, 30)
        XCTAssertEqual(model.focusRequest?.position, .bottom)
        let calls = await service.messageCalls
        XCTAssertEqual(calls.first, "open 1")
        let history = await service.historyCalls
        XCTAssertEqual(history.first, "1 0 0 50", "Depuis le dernier message")
    }

    /// Non lus à l'ouverture : fenêtre autour du dernier message lu, focus sur le premier non lu.
    func testOpeningWithUnreadMessagesFocusesTheFirstUnread() async {
        var chat = ChatTestData.chat(Fixture.chatId, lastMessage: ChatTestData.message(40))
        chat.unreadCount = 2
        chat.lastReadInboxMessageId = 20
        let page = [Fixture.message(40), Fixture.message(30), Fixture.message(20), Fixture.message(10)]
        let (model, service) = await makeModel(chat: chat, pages: [page])
        await model.open()

        let history = await service.historyCalls
        XCTAssertEqual(history, ["1 20 -25 50"])
        XCTAssertTrue(model.state.reachedLatest, "La page contient le dernier message (40)")
        XCTAssertEqual(model.firstUnreadId, 30)
        XCTAssertEqual(model.focusRequest, MessageFocusRequest(messageId: 30, position: .top, serial: 1))
        // Rotor « Messages non lus » : les messages reçus après le dernier lu à l'ouverture.
        let unread = model.items.compactMap(\.message).filter { model.isUnreadAtOpen($0) }
        XCTAssertEqual(unread.map(\.id), [30, 40])
    }

    func testFailedOpeningCanBeRetried() async {
        let (model, service) = await makeModel(pages: [[Fixture.message(10)]])
        await service.failNextHistory(with: TelegramError(code: 500, message: "NETWORK"))
        await model.open()
        XCTAssertTrue(model.loadFailed)
        XCTAssertFalse(model.isOpening)
        XCTAssertNil(model.focusRequest)

        model.retry()
        await waitUntil { model.state.orderedIds == [10] }
        XCTAssertFalse(model.loadFailed)
        XCTAssertEqual(model.focusRequest?.messageId, 10)
    }

    // MARK: - Envoi

    func testSendingAnnouncesWhenTelegramAcceptsTheMessage() async {
        let (model, service) = await makeModel(pages: [[Fixture.message(10)]])
        await model.open()

        model.draft = "  Coucou  "
        model.send()
        XCTAssertEqual(model.draft, "", "Champ vidé dès l'envoi")
        await waitUntil { await service.messageCalls.contains("send 1 Coucou") }
        await waitUntil { !model.isSending }
        XCTAssertEqual(model.scrollToBottomRequest, 1, "La liste descend jusqu'au message envoyé")

        let sent = Fixture.message(2_000, text: "Coucou", outgoing: true)
        service.send(.sendSucceeded(sent, oldId: 1000))
        await waitUntil { model.lastAnnouncement == "Message envoyé." }
    }

    /// La confirmation de Telegram peut arriver avant que l'envoi ne rende l'identifiant.
    func testEarlyConfirmationIsAnnouncedToo() async {
        let (model, service) = await makeModel(pages: [[Fixture.message(10)]])
        await model.open()

        service.send(.sendSucceeded(Fixture.message(2_000, outgoing: true), oldId: 1000))
        await waitUntil { model.state.messages[2_000] != nil }
        XCTAssertNil(model.lastAnnouncement, "Pas encore envoyé depuis cet écran")

        model.draft = "Coucou"
        model.send()
        await waitUntil { model.lastAnnouncement == "Message envoyé." }
    }

    func testEmptyMessageIsNotSent() async {
        let (model, service) = await makeModel(pages: [[Fixture.message(10)]])
        await model.open()
        XCTAssertFalse(model.canSend, "Bouton estompé : champ vide")
        model.draft = " \n "
        XCTAssertFalse(model.canSend, "Bouton estompé : espaces seuls")
        model.send()
        XCTAssertEqual(model.lastAnnouncement, "Saisissez d'abord un message.")
        let calls = await service.messageCalls
        XCTAssertFalse(calls.contains { $0.hasPrefix("send") })

        model.draft = "Salut"
        XCTAssertTrue(model.canSend)
    }

    func testFailedSendKeepsTheTextAndAnnouncesTheReason() async {
        let (model, service) = await makeModel(pages: [[Fixture.message(10)]])
        await model.open()
        await service.failNextCall(with: TelegramError(code: 400, message: "MESSAGE_TOO_LONG"))

        model.draft = "Très long"
        model.send()
        await waitUntil { model.lastAnnouncement == "Échec de l'envoi : message trop long." }
        XCTAssertEqual(model.draft, "Très long")
    }

    func testRejectedMessageIsAnnounced() async {
        let (model, service) = await makeModel(pages: [[Fixture.message(10)]])
        await model.open()
        model.draft = "Bonjour"
        model.send()
        await waitUntil { !model.isSending }

        let failed = Fixture.message(1_001, text: "Bonjour", outgoing: true, delivery: .failed)
        service.send(.sendFailed(failed, oldId: 1000, error: TelegramError(code: 403, message: "CHAT_WRITE_FORBIDDEN")))
        await waitUntil {
            model.lastAnnouncement == "Échec de l'envoi : vous ne pouvez pas écrire dans cette conversation."
        }
    }

    // MARK: - Lecture et pagination

    /// Les messages reçus visibles sont signalés vus une seule fois ; les messages envoyés jamais.
    func testVisibleIncomingMessagesAreViewedOnce() async {
        let mine = Fixture.message(20, sender: .user(Fixture.me), outgoing: true)
        let (model, service) = await makeModel(pages: [[mine, Fixture.message(10)]])
        await model.open()

        model.messagesVisible([10, 20])
        await waitUntil { await service.messageCalls.contains("view 1 10") }
        model.messagesVisible([10, 20])
        try? await Task.sleep(nanoseconds: 100_000_000)
        let views = await service.messageCalls.filter { $0.hasPrefix("view") }
        XCTAssertEqual(views, ["view 1 10"])
    }

    func testFirstMessagesLoadOlderHistory() async {
        let page = (1...30).reversed().map { Fixture.message(Int64($0) * 10) }
        let older = [Fixture.message(5), Fixture.message(3)]
        let (model, service) = await makeModel(pages: [page, older])
        await model.open()
        XCTAssertEqual(model.state.orderedIds.first, 10)

        model.messageAppeared(10)
        await waitUntil { model.state.orderedIds.first == 3 }
        let history = await service.historyCalls
        XCTAssertEqual(history.last, "1 10 0 50")
    }

    func testCitedMessageOutsideTheWindowIsFetched() async {
        let answer = Fixture.message(20, text: "Oui", replyTo: MessageReplyRef(chatId: Fixture.chatId, messageId: 5))
        let (model, service) = await makeModel(pages: [[answer]])
        await service.setStoredMessages([Fixture.message(5, text: "On se voit ?", sender: .user(Fixture.me), outgoing: true)])
        await model.open()

        await waitUntil { model.state.message(5) != nil }
        XCTAssertEqual(model.state.orderedIds, [20], "Le message cité n'entre pas dans la fenêtre")
        let calls = await service.messageCalls
        XCTAssertTrue(calls.contains("get 1 5"))
    }

    // MARK: - Messages entrants et fermeture

    func testIncomingMessageIsAddedWithoutMovingFocus() async {
        let (model, service) = await makeModel(pages: [[Fixture.message(10)]])
        await model.open()
        let focus = model.focusRequest

        service.send(.new(Fixture.message(11, text: "Nouveau")))
        await waitUntil { model.state.orderedIds == [10, 11] }
        XCTAssertEqual(model.focusRequest, focus, "Un message entrant ne déplace jamais le focus")
    }

    func testClosingStopsUpdatesAndClosesTheChat() async {
        let (model, service) = await makeModel(pages: [[Fixture.message(10)]])
        await model.open()
        model.close()
        await waitUntil { await service.messageCalls.contains("close 1") }

        service.send(.new(Fixture.message(11)))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.state.orderedIds, [10])
    }

    func testActivityText() async {
        let (model, service) = await makeModel(pages: [[Fixture.message(10)]])
        await model.open()
        service.send(.activity(chatId: Fixture.chatId, sender: .user(Fixture.marie), activity: .typing))
        await waitUntil { model.activityText == "écrit…" }
    }
}

final class ConversationSectionTests: XCTestCase {
    private let calendar = ChatTestData.calendar

    private func row(_ id: Int64, _ date: Date) -> MessageRowModel {
        MessageRowModel(id: id, senderLabel: nil, isOutgoing: false, content: .text("Texte"), date: date)
    }

    func testRowsAreGroupedByDay() {
        let rows = [
            row(1, ChatTestData.date(2026, 11, 9, 18, 0)),
            row(2, ChatTestData.date(2026, 11, 9, 19, 0)),
            row(3, ChatTestData.date(2026, 11, 10, 9, 0)),
        ]
        let sections = ConversationSection.make(rows, now: ChatTestData.now, calendar: calendar)
        XCTAssertEqual(sections.map(\.title), ["Hier", "Aujourd'hui"])
        XCTAssertEqual(sections.map { $0.rows.map(\.id) }, [[1, 2], [3]])
    }

    /// Lignes de la liste dans l'ordre de lecture : chaque jour suivi de ses messages ; le
    /// premier jour signale le début de la conversation une fois tout l'historique chargé.
    func testItemsFollowReadingOrder() {
        let rows = [
            row(1, ChatTestData.date(2026, 11, 9, 18, 0)),
            row(2, ChatTestData.date(2026, 11, 10, 9, 0)),
            row(3, ChatTestData.date(2026, 11, 10, 9, 30)),
        ]
        let sections = ConversationSection.make(rows, now: ChatTestData.now, calendar: calendar)
        let items = ConversationItem.list(sections, reachedStart: true)
        XCTAssertEqual(items.map(\.id), [
            .day(sections[0].id), .message(1),
            .day(sections[1].id), .message(2), .message(3),
        ])
        XCTAssertEqual(items.first, .day(id: sections[0].id, title: "Hier", isStart: true))
        XCTAssertEqual(items[2], .day(id: sections[1].id, title: "Aujourd'hui", isStart: false))

        let partial = ConversationItem.list(sections, reachedStart: false)
        XCTAssertEqual(partial.first, .day(id: sections[0].id, title: "Hier", isStart: false))
    }

    /// Un message daté hors de l'ordre ne recrée pas un jour déjà présent (identifiants de
    /// section uniques, exigés par la liste).
    func testOutOfOrderDateDoesNotDuplicateADay() {
        let rows = [
            row(1, ChatTestData.date(2026, 11, 9, 18, 0)),
            row(2, ChatTestData.date(2026, 11, 10, 9, 0)),
            row(3, ChatTestData.date(2026, 11, 9, 20, 0)),
        ]
        let sections = ConversationSection.make(rows, now: ChatTestData.now, calendar: calendar)
        XCTAssertEqual(Set(sections.map(\.id)).count, sections.count)
        XCTAssertEqual(sections.map { $0.rows.map(\.id) }, [[1], [2, 3]])
    }
}
