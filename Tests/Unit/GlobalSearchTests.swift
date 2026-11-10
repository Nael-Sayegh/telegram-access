import XCTest
@testable import TelegramAccess

final class SearchLabelsTests: XCTestCase {
    func testSummary() {
        XCTAssertEqual(SearchLabels.summary(chats: 0, messages: 0, hasMore: false), "Aucun résultat.")
        XCTAssertEqual(SearchLabels.summary(chats: 1, messages: 0, hasMore: false), "1 conversation.")
        XCTAssertEqual(SearchLabels.summary(chats: 3, messages: 30, hasMore: true), "3 conversations, 30 messages ou plus.")
        XCTAssertEqual(SearchLabels.summary(chats: 0, messages: 1, hasMore: false), "1 message.")
    }

    func testMoreMessages() {
        XCTAssertEqual(SearchLabels.moreMessages(0), "Aucun autre message.")
        XCTAssertEqual(SearchLabels.moreMessages(5), "5 messages de plus.")
    }

    func testMessageLabel() {
        let row = SearchMessageRow(
            chatId: 1,
            messageId: 2,
            chatTitle: "Famille",
            line: LastMessageLine(senderLabel: "Paul", text: "Salut", status: nil, date: ChatTestData.date(2026, 11, 9))
        )
        XCTAssertEqual(
            SearchLabels.message(row, now: ChatTestData.now, calendar: ChatTestData.calendar),
            "Famille, Paul : Salut, hier"
        )
    }
}

@MainActor
final class GlobalSearchViewModelTests: XCTestCase {
    private func makeSearch() async -> (GlobalSearchViewModel, FakeAuthService) {
        let service = FakeAuthService()
        let store = ChatStore(events: service.chatEvents)
        service.send(.newChat(ChatTestData.chat(1, title: "Marie Dupont")))
        service.send(.newChat(ChatTestData.chat(2, kind: .channel, title: "Infos")))
        let search = GlobalSearchViewModel(store: store, service: service)
        await waitUntil { store.state.chats.count == 2 }
        return (search, service)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition non remplie à temps", file: file, line: line)
    }

    private func page(_ messageIds: [Int64], next: String) -> MessageSearchPage {
        MessageSearchPage(
            results: messageIds.map { MessageSearchResult(chatId: 1, message: ChatTestData.message($0, text: "Bonjour")) },
            nextOffset: next
        )
    }

    func testMessagesScopeIsTheDefaultAndSearchesOnlyMessages() async {
        let (search, service) = await makeSearch()
        await service.setSearchResults(chats: [1], messagePages: [page([10, 11], next: "p2")])
        XCTAssertEqual(search.scope, .messages)

        search.query = "bon"
        search.submit()
        await waitUntil { search.lastAnnouncement != nil }

        XCTAssertEqual(search.messages.map(\.messageId), [10, 11])
        XCTAssertTrue(search.chatRows.isEmpty, "Les conversations ne sont pas cherchées")
        XCTAssertTrue(search.hasMoreMessages)
        XCTAssertEqual(search.lastAnnouncement, "2 messages ou plus.")
    }

    func testConversationsScopeGroupsKnownAndPublicChats() async {
        let (search, service) = await makeSearch()
        await service.setSearchResults(chats: [1], publicChats: [1, 2], messagePages: [page([10], next: "")])
        search.query = "bon"
        search.setScope(.conversations)
        await waitUntil { search.lastAnnouncement != nil }

        XCTAssertEqual(search.chatRows.map(\.title), ["Marie Dupont"])
        XCTAssertEqual(search.publicChatRows.map(\.title), ["Infos"], "Sans doublon avec les conversations connues")
        XCTAssertTrue(search.messages.isEmpty, "Les messages ne sont pas cherchés")
        XCTAssertEqual(search.lastAnnouncement, "2 conversations.")
        let searches = await service.messageSearches
        XCTAssertEqual(searches, [])
    }

    func testMoreMessagesUseNextOffset() async {
        let (search, service) = await makeSearch()
        await service.setSearchResults(chats: [], messagePages: [page([10], next: "p2"), page([11], next: "")])
        search.query = "bon"
        search.submit()
        await waitUntil { search.messages.count == 1 }

        await search.loadMoreMessages()
        XCTAssertEqual(search.messages.map(\.messageId), [10, 11])
        XCTAssertFalse(search.hasMoreMessages)
        XCTAssertEqual(search.lastAnnouncement, "1 message de plus.")
        let searches = await service.messageSearches
        XCTAssertEqual(searches, ["bon|", "bon|p2"])
    }

    func testTypingIsDebouncedAndClearingResets() async {
        let (search, service) = await makeSearch()
        await service.setSearchResults(chats: [], messagePages: [page([10], next: "")])
        for text in ["m", "ma", "mar"] {
            search.query = text
            search.queryChanged()
        }
        XCTAssertTrue(search.isSearching)
        await waitUntil { !search.messages.isEmpty }
        let searches = await service.messageSearches
        XCTAssertEqual(searches, ["mar|"], "Une seule recherche après la pause de frappe")

        search.query = "  "
        search.queryChanged()
        XCTAssertFalse(search.isActive)
        XCTAssertTrue(search.messages.isEmpty)
    }

    func testNoResult() async {
        let (search, _) = await makeSearch()
        search.query = "zzz"
        search.submit()
        await waitUntil { search.lastAnnouncement == "Aucun résultat." }
        XCTAssertFalse(search.failed)
        XCTAssertEqual(search.scope.noResult("zzz"), "Aucun message trouvé pour « zzz ».")
    }

    func testPartialFailureIsNotAGlobalFailure() async {
        let (search, service) = await makeSearch()
        await service.failNextCall(with: TelegramError(code: 500, message: "NETWORK"))
        search.query = "bon"
        search.setScope(.conversations)
        await waitUntil { search.lastAnnouncement != nil }
        // Les conversations connues ont échoué mais la recherche publique a répondu (vide) :
        // pas d'échec global, simplement aucun résultat.
        XCTAssertFalse(search.failed)
        XCTAssertEqual(search.lastAnnouncement, "Aucun résultat.")
    }
}
