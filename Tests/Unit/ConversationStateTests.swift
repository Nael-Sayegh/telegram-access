import XCTest
@testable import TelegramAccess

final class ConversationStateTests: XCTestCase {
    private typealias Fixture = ConversationTestData

    func testResetSortsMessagesChronologically() {
        // TDLib renvoie l'historique du plus récent au plus ancien.
        let state = Fixture.loadedState([Fixture.message(30), Fixture.message(20), Fixture.message(10)])
        XCTAssertEqual(state.orderedIds, [10, 20, 30])
        XCTAssertTrue(state.reachedLatest)
        XCTAssertFalse(state.reachedOldest)
    }

    func testEmptyHistoryMeansBothEndsReached() {
        let state = Fixture.loadedState([])
        XCTAssertTrue(state.reachedOldest)
        XCTAssertTrue(state.reachedLatest)
    }

    func testOlderPagesAreMergedWithoutDuplicates() {
        var state = Fixture.loadedState([Fixture.message(30), Fixture.message(20)])
        // Avec offset 0, TDLib inclut le message de départ (20).
        state.appendOlder([Fixture.message(20), Fixture.message(15), Fixture.message(5)])
        XCTAssertEqual(state.orderedIds, [5, 15, 20, 30])
        XCTAssertFalse(state.reachedOldest)

        state.appendOlder([Fixture.message(5)])
        XCTAssertTrue(state.reachedOldest, "Aucun message plus ancien : début atteint")
    }

    func testNewerPagesReachTheLatestMessage() {
        var state = ConversationState(chatId: Fixture.chatId)
        state.reset(with: [Fixture.message(20), Fixture.message(10)], isLatest: false)
        XCTAssertFalse(state.reachedLatest)

        state.appendNewer([Fixture.message(40), Fixture.message(30), Fixture.message(20)], lastMessageId: 50)
        XCTAssertEqual(state.orderedIds, [10, 20, 30, 40])
        XCTAssertFalse(state.reachedLatest)

        state.appendNewer([Fixture.message(50), Fixture.message(40)], lastMessageId: 50)
        XCTAssertTrue(state.reachedLatest, "Dernier message connu atteint")
    }

    func testNewMessageIsAppendedOnlyWhenWindowReachesLatest() {
        var latest = Fixture.loadedState([Fixture.message(10)])
        latest.apply(.new(Fixture.message(20)))
        XCTAssertEqual(latest.orderedIds, [10, 20])

        var jumped = ConversationState(chatId: Fixture.chatId)
        jumped.reset(with: [Fixture.message(10)], isLatest: false)
        jumped.apply(.new(Fixture.message(20)))
        XCTAssertEqual(jumped.orderedIds, [10], "Pas de trou : le message viendra avec la suite")
    }

    func testEventsOfOtherChatsAreIgnored() {
        var state = Fixture.loadedState([Fixture.message(10)])
        state.apply(.new(Fixture.message(20, chatId: 99)))
        state.apply(.deleted(chatId: 99, messageIds: [10]))
        XCTAssertEqual(state.orderedIds, [10])
    }

    /// Un message arrivé pendant le chargement de l'historique n'est pas perdu.
    func testEventsReceivedWhileLoadingAreReplayed() {
        var state = ConversationState(chatId: Fixture.chatId)
        state.apply(.new(Fixture.message(30)))
        state.apply(.edited(chatId: Fixture.chatId, messageId: 10, editDate: ChatTestData.now))
        XCTAssertTrue(state.orderedIds.isEmpty)

        state.reset(with: [Fixture.message(20), Fixture.message(10)], isLatest: true)
        XCTAssertEqual(state.orderedIds, [10, 20, 30])
        XCTAssertNotNil(state.messages[10]?.editDate)

        state.beginLoading()
        state.apply(.new(Fixture.message(40)))
        state.reset(with: [Fixture.message(35)], isLatest: true)
        XCTAssertEqual(state.orderedIds, [35, 40])
    }

    func testSentMessageReplacesTemporaryOne() {
        var state = Fixture.loadedState([Fixture.message(10)])
        state.apply(.new(Fixture.message(11, outgoing: true, delivery: .pending)))
        XCTAssertEqual(state.orderedIds, [10, 11])

        state.apply(.sendSucceeded(Fixture.message(1_048_576, outgoing: true), oldId: 11))
        XCTAssertEqual(state.orderedIds, [10, 1_048_576])
        XCTAssertNil(state.messages[11])
        XCTAssertEqual(state.messages[1_048_576]?.delivery, .sent)
    }

    func testFailedMessageStaysWithFailedState() {
        var state = Fixture.loadedState([Fixture.message(10)])
        state.apply(.new(Fixture.message(11, outgoing: true, delivery: .pending)))
        let failed = Fixture.message(12, outgoing: true, delivery: .failed)
        state.apply(.sendFailed(failed, oldId: 11, error: TelegramError(code: 400, message: "MESSAGE_TOO_LONG")))
        XCTAssertEqual(state.orderedIds, [10, 12])
        XCTAssertEqual(state.messages[12]?.delivery, .failed)
    }

    func testEditPinReactionsAndContentUpdates() {
        var state = Fixture.loadedState([Fixture.message(10)])
        let date = ChatTestData.now
        state.apply(.edited(chatId: Fixture.chatId, messageId: 10, editDate: date))
        state.apply(.pinned(chatId: Fixture.chatId, messageId: 10, isPinned: true))
        let thumbs = MessageReactionCount(kind: .emoji("👍"), count: 2, isChosen: true)
        state.apply(.reactions(chatId: Fixture.chatId, messageId: 10, reactions: [thumbs]))
        state.apply(.content(chatId: Fixture.chatId, messageId: 10, body: MessageBody(content: .text("Corrigé"))))

        let message = state.messages[10]
        XCTAssertEqual(message?.editDate, date)
        XCTAssertEqual(message?.isPinned, true)
        XCTAssertEqual(message?.reactions, [thumbs])
        XCTAssertEqual(message?.body.content, .text("Corrigé"))
    }

    func testDeletedMessagesAreRemovedAndRemembered() {
        var state = Fixture.loadedState([Fixture.message(10), Fixture.message(20)])
        state.apply(.deleted(chatId: Fixture.chatId, messageIds: [10]))
        XCTAssertEqual(state.orderedIds, [20])
        XCTAssertTrue(state.deletedIds.contains(10))
    }

    func testVoiceNoteBecomesListened() {
        let voice = MessageMedia(kind: .voiceNote, file: FileRef(id: 3, size: 1000, localPath: nil), isListened: false)
        var state = Fixture.loadedState([Fixture.message(10, media: voice, content: .voiceNote(duration: 12, caption: ""))])
        state.apply(.opened(chatId: Fixture.chatId, messageId: 10))
        XCTAssertEqual(state.messages[10]?.body.media?.isListened, true)
    }

    func testDownloadedFileIsReportedOnMessages() {
        let photo = MessageMedia(kind: .photo, file: FileRef(id: 3, size: 1000, localPath: nil))
        var state = Fixture.loadedState([Fixture.message(10, media: photo, content: .photo(caption: ""))])
        state.addReferenced(Fixture.message(2, media: photo, content: .photo(caption: "")))
        state.apply(.file(FileRef(id: 3, size: 1000, localPath: "/tmp/photo.jpg")))
        XCTAssertEqual(state.messages[10]?.body.media?.file.localPath, "/tmp/photo.jpg")
        XCTAssertEqual(state.referenced[2]?.body.media?.file.localPath, "/tmp/photo.jpg")
    }

    func testActivityIsTrackedPerSender() {
        var state = Fixture.loadedState([])
        state.apply(.activity(chatId: Fixture.chatId, sender: .user(Fixture.marie), activity: .typing))
        XCTAssertEqual(state.activities[.user(Fixture.marie)], .typing)
        state.apply(.activity(chatId: Fixture.chatId, sender: .user(Fixture.marie), activity: nil))
        XCTAssertTrue(state.activities.isEmpty)
    }

    func testReferencedMessageIsFoundButNotShown() {
        var state = Fixture.loadedState([Fixture.message(20)])
        state.addReferenced(Fixture.message(5, text: "Ancien"))
        XCTAssertEqual(state.message(5)?.body.content, .text("Ancien"))
        XCTAssertEqual(state.orderedIds, [20])
    }
}
