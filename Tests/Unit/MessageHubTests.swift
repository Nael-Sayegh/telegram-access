import XCTest
@testable import TelegramAccess

@MainActor
final class MessageHubTests: XCTestCase {
    /// Abonné de test : enregistre les changements reçus.
    private final class Recorder {
        var events: [MessageEvent] = []
    }

    private func makeHub() -> MessageHub {
        MessageHub(events: AsyncStream.makeStream(of: MessageEvent.self).stream)
    }

    private func observe(_ hub: MessageHub, chatId: Int64?, _ recorder: Recorder) {
        hub.observe(chatId, owner: recorder) { [weak recorder] in recorder?.events.append($0) }
    }

    func testEventsAreRoutedByChat() {
        let hub = makeHub()
        let chat1 = Recorder()
        let all = Recorder()
        observe(hub, chatId: 1, chat1)
        observe(hub, chatId: nil, all)

        let first = MessageEvent.new(ConversationTestData.message(10, chatId: 1))
        let second = MessageEvent.new(ConversationTestData.message(11, chatId: 2))
        let file = MessageEvent.file(FileRef(id: 3, size: 0, localPath: "/tmp/a"))
        hub.dispatch(first)
        hub.dispatch(second)
        hub.dispatch(file)

        XCTAssertEqual(chat1.events, [first, file], "Fichiers diffusés à tous")
        XCTAssertEqual(all.events, [first, second, file])
    }

    func testStoppedOrReleasedObserversReceiveNothing() {
        let hub = makeHub()
        let stopped = Recorder()
        observe(hub, chatId: 1, stopped)
        hub.stopObserving(stopped)

        var released: Recorder? = Recorder()
        observe(hub, chatId: 1, released!)
        weak var weakReleased = released
        released = nil
        XCTAssertNil(weakReleased, "Le hub ne retient pas ses abonnés")

        hub.dispatch(.deleted(chatId: 1, messageIds: [5]))
        XCTAssertTrue(stopped.events.isEmpty)
    }

    /// Les changements du flux TDLib arrivent aux abonnés.
    func testStreamEventsAreDispatched() async {
        let stream = AsyncStream.makeStream(of: MessageEvent.self)
        let hub = MessageHub(events: stream.stream)
        let recorder = Recorder()
        observe(hub, chatId: 1, recorder)
        stream.continuation.yield(.opened(chatId: 1, messageId: 4))
        for _ in 0..<200 where recorder.events.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(recorder.events, [.opened(chatId: 1, messageId: 4)])
    }
}
