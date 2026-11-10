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
