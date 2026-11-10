import XCTest
@testable import TelegramAccess

@MainActor
final class ChatListViewModelTests: XCTestCase {
    private func makeModel(pages: Int = 0) async -> (ChatListViewModel, FakeAuthService) {
        let service = FakeAuthService()
        await service.setPagesLeft(pages)
        let store = ChatStore(events: service.chatEvents)
        return (ChatListViewModel(list: .main, store: store, service: service), service)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition non remplie à temps", file: file, line: line)
    }

    func testLoadingStopsAtEndOfList() async {
        let (model, service) = await makeModel(pages: 1)
        await model.loadMore()
        XCTAssertFalse(model.isFullyLoaded)
        await model.loadMore()
        XCTAssertTrue(model.isFullyLoaded)

        await model.loadMore()
        let calls = await service.loadChatsCalls
        XCTAssertEqual(calls, [.main, .main], "Plus aucun chargement une fois la fin atteinte")
    }

    func testFailedLoadCanBeRetried() async {
        let (model, service) = await makeModel()
        await service.failNextCall(with: TelegramError(code: 500, message: "NETWORK"))
        await model.loadMore()
        XCTAssertTrue(model.loadFailed)
        XCTAssertFalse(model.isFullyLoaded)

        await model.loadMore()
        XCTAssertFalse(model.loadFailed)
        XCTAssertTrue(model.isFullyLoaded)
    }

    func testRowsFollowTheStoreInOrder() async {
        let (model, service) = await makeModel()
        service.send(.newChat(ChatTestData.chat(1, title: "Ancienne", order: 10)))
        service.send(.newChat(ChatTestData.chat(2, title: "Récente", order: 20)))
        await waitUntil { model.rows.map(\.title) == ["Récente", "Ancienne"] }
    }

    // MARK: - Actions

    /// Modèle avec une conversation (id 1) chargée.
    private func modelWithChat(_ chat: ChatSummary = ChatTestData.chat(1)) async -> (ChatListViewModel, FakeAuthService) {
        let (model, service) = await makeModel()
        service.send(.newChat(chat))
        await waitUntil { model.rows.count == 1 }
        return (model, service)
    }

    private func waitForCalls(_ service: FakeAuthService, count: Int = 1) async -> [String] {
        for _ in 0..<200 {
            let calls = await service.chatCalls
            if calls.count >= count { return calls }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await service.chatCalls
    }

    func testPinCallsServiceAndAnnouncesResult() async {
        let (model, service) = await modelWithChat()
        model.perform(.pin, on: model.rows[0])
        let calls = await waitForCalls(service)
        XCTAssertEqual(calls, ["pin 1 main true"])
        await waitUntil { model.lastAnnouncement == "Conversation épinglée." }
    }

    func testArchiveAndMuteActions() async {
        let (model, service) = await modelWithChat()
        model.perform(.archive, on: model.rows[0])
        model.perform(.mute, on: model.rows[0])  // ignorée : action déjà en cours sur la conversation
        _ = await waitForCalls(service)
        await waitUntil { model.lastAnnouncement == "Conversation archivée." }
        model.perform(.mute, on: model.rows[0])
        let calls = await waitForCalls(service, count: 2)
        XCTAssertEqual(calls, ["move 1 archive", "mute 1 true"])
    }

    func testFailedActionAnnouncesError() async {
        let (model, service) = await modelWithChat()
        await service.failNextCall(with: TelegramError(code: 400, message: "The maximum number of pinned chats exceeded"))
        model.perform(.pin, on: model.rows[0])
        await waitUntil {
            model.lastAnnouncement == "Nombre maximal de conversations épinglées atteint. Désépinglez-en une d'abord."
        }
    }

    func testDeleteAsksForConfirmationFirst() async {
        let (model, service) = await modelWithChat()
        let row = model.rows[0]
        model.perform(.delete, on: row)
        XCTAssertEqual(model.deletionRequest, row)
        let before = await service.chatCalls
        XCTAssertEqual(before, [])

        model.confirmDeletion(of: row, forEveryone: true)
        XCTAssertNil(model.deletionRequest)
        let calls = await waitForCalls(service)
        XCTAssertEqual(calls, ["delete 1 true"])
        await waitUntil { model.lastAnnouncement == "Conversation supprimée." }
    }

    func testLastRowsTriggerLoading() async {
        let (model, service) = await makeModel(pages: 5)
        service.send(.newChat(ChatTestData.chat(1, order: 10)))
        await waitUntil { model.rows.count == 1 }

        model.rowAppeared(1)
        var attempts = 0
        while await service.loadChatsCalls.isEmpty, attempts < 200 {
            attempts += 1
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let calls = await service.loadChatsCalls
        XCTAssertEqual(calls, [.main])
    }
}
