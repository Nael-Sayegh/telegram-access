import XCTest
@testable import TelegramAccess

/// Annonce des messages reçus : règles et textes (fonctions pures).
final class IncomingAnnouncementsTests: XCTestCase {
    private func incoming(
        _ id: Int64 = 1,
        chatId: Int64 = 1,
        title: String = "Marie Dupont",
        place: IncomingMessage.Place = .privateChat,
        author: String? = "Marie Dupont",
        content: String = "Salut",
        open: Bool = false
    ) -> IncomingMessage {
        IncomingMessage(
            chatId: chatId,
            messageId: id,
            chatTitle: title,
            place: place,
            author: author,
            content: content,
            isInOpenChat: open
        )
    }

    private func famille(_ id: Int64, author: String = "Paul Martin", content: String = "Salut", open: Bool = false) -> IncomingMessage {
        incoming(id, chatId: -100, title: "Famille", place: .group, author: author, content: content, open: open)
    }

    private func should(
        _ mode: IncomingAnnouncementMode,
        open: Bool = false,
        muted: Bool = false,
        outgoing: Bool = false,
        read: Bool = false,
        age: TimeInterval = 5
    ) -> Bool {
        IncomingAnnouncements.shouldAnnounce(
            mode: mode,
            isOutgoing: outgoing,
            isInOpenChat: open,
            isMuted: muted,
            isAlreadyRead: read,
            age: age
        )
    }

    // MARK: - Règles

    func testOpenChatModeAnnouncesOnlyTheOpenChat() {
        XCTAssertTrue(should(.openChat, open: true))
        XCTAssertTrue(should(.openChat, open: true, muted: true), "On regarde la conversation : sourdine ignorée")
        XCTAssertFalse(should(.openChat, open: false))
    }

    func testAllChatsModeSkipsMutedChatsExceptTheOpenOne() {
        XCTAssertTrue(should(.allChats))
        XCTAssertFalse(should(.allChats, muted: true))
        XCTAssertTrue(should(.allChats, open: true, muted: true))
    }

    func testNeverModeIsSilent() {
        XCTAssertFalse(should(.never, open: true))
        XCTAssertFalse(should(.never))
    }

    func testOwnReadAndCatchUpMessagesAreNotAnnounced() {
        XCTAssertFalse(should(.allChats, open: true, outgoing: true), "Message envoyé, même depuis un autre appareil")
        XCTAssertFalse(should(.allChats, open: true, read: true), "Déjà lu ailleurs")
        XCTAssertFalse(should(.allChats, open: true, age: 600), "Rattrapage après une reconnexion")
        XCTAssertTrue(should(.allChats, open: true, age: IncomingAnnouncements.maximumAge))
    }

    func testModeIsStoredWithConversationOpenAsDefault() throws {
        let suite = "IncomingAnnouncementsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(IncomingAnnouncementMode.stored(in: defaults), .openChat)
        defaults.set(IncomingAnnouncementMode.allChats.rawValue, forKey: IncomingAnnouncementMode.storageKey)
        XCTAssertEqual(IncomingAnnouncementMode.stored(in: defaults), .allChats)
        defaults.set("inconnu", forKey: IncomingAnnouncementMode.storageKey)
        XCTAssertEqual(IncomingAnnouncementMode.stored(in: defaults), .openChat)
    }

    func testModeTitles() {
        XCTAssertEqual(IncomingAnnouncementMode.allCases.map(\.title), [
            "Toutes les conversations, sauf en sourdine",
            "Conversation ouverte",
            "Jamais",
        ])
    }

    // MARK: - Textes

    func testSingleMessage() {
        XCTAssertEqual(IncomingAnnouncements.text([incoming()]), "Marie Dupont : Salut.")
        XCTAssertEqual(IncomingAnnouncements.text([incoming(content: "On se voit ?")]), "Marie Dupont : On se voit ?")
        XCTAssertEqual(IncomingAnnouncements.text([famille(1)]), "Paul Martin dans Famille : Salut.")
        XCTAssertEqual(IncomingAnnouncements.text([famille(1, open: true)]), "Paul Martin : Salut.")
        XCTAssertEqual(
            IncomingAnnouncements.text([famille(1, author: "Famille")]),
            "Famille : Salut.",
            "Administrateur anonyme : le groupe parle"
        )
        let post = incoming(chatId: -200, title: "Infos", place: .channel, author: "Infos", content: "Photo, Le marché")
        XCTAssertEqual(IncomingAnnouncements.text([post]), "Infos : Photo, Le marché.")
        XCTAssertEqual(IncomingAnnouncements.text([incoming(content: "  ")]), "Marie Dupont : Message vide.")
    }

    func testBurstIsCountedPerChat() {
        XCTAssertEqual(IncomingAnnouncements.text([incoming(1), incoming(2), incoming(3)]), "3 nouveaux messages de Marie Dupont.")
        XCTAssertEqual(IncomingAnnouncements.text([famille(1), famille(2)]), "2 nouveaux messages dans Famille.")
        XCTAssertEqual(IncomingAnnouncements.text([famille(1, open: true), famille(2, open: true)]), "2 nouveaux messages.")
    }

    func testSeveralChatsInArrivalOrder() {
        let text = IncomingAnnouncements.text([
            incoming(1, content: "On se voit ?"),
            famille(10),
            famille(11),
        ])
        XCTAssertEqual(text, "Marie Dupont : On se voit ? 2 nouveaux messages dans Famille.")
        XCTAssertNil(IncomingAnnouncements.text([]))
    }

    func testLongContentIsCut() throws {
        let long = Array(repeating: "mot", count: 100).joined(separator: " ")
        let text = try XCTUnwrap(IncomingAnnouncements.text([incoming(content: long)]))
        XCTAssertTrue(text.hasSuffix("…"), text)
        XCTAssertLessThanOrEqual(text.count, "Marie Dupont : ".count + IncomingAnnouncements.contentLimit + 1)
    }
}

/// Annonceur branché sur le hub des messages et la liste des conversations.
@MainActor
final class IncomingAnnouncerTests: XCTestCase {
    private typealias Fixture = ConversationTestData

    /// Ce qui a été dit.
    private final class Spoken {
        var texts: [String] = []
    }

    private let familleId: Int64 = -100
    /// Une minute après les messages de test (14 h 32).
    private let now = ChatTestData.date(2026, 11, 10, 14, 33)
    /// Gardé pendant le test : le hub ne retient pas ses abonnés.
    private var announcer: IncomingAnnouncer?

    private func makeAnnouncer(
        mode: IncomingAnnouncementMode,
        familleMuted: Bool = false,
        delay: Duration = .milliseconds(10),
        canSpeak: Bool = true
    ) async -> (IncomingAnnouncer, MessageHub, FakeAuthService, Spoken) {
        let service = FakeAuthService()
        let store = ChatStore(events: service.chatEvents)
        service.send(.myUserId(Fixture.me))
        service.send(.user(id: Fixture.marie, name: UserName(firstName: "Marie", lastName: "Dupont", isDeleted: false)))
        service.send(.user(id: Fixture.paul, name: UserName(firstName: "Paul", lastName: "Martin", isDeleted: false)))
        service.send(.newChat(ChatTestData.chat(Fixture.chatId, kind: .user(userId: Fixture.marie))))
        let mute = ChatMuteSetting(usesDefault: false, muteFor: familleMuted ? 3600 : 0)
        service.send(.newChat(ChatTestData.chat(familleId, kind: .supergroup, title: "Famille", mute: mute)))
        await waitUntil { store.state.chats.count == 2 && store.state.users.count == 2 }
        let hub = MessageHub(events: service.messageEvents)
        let spoken = Spoken()
        let now = now
        let announcer = IncomingAnnouncer(
            hub: hub,
            store: store,
            mode: { mode },
            canSpeak: { canSpeak },
            now: { now },
            delay: delay,
            speak: { spoken.texts.append($0) }
        )
        self.announcer = announcer
        return (announcer, hub, service, spoken)
    }

    private func fromMarie(_ id: Int64, _ text: String = "Bonjour") -> ChatMessage {
        Fixture.message(id, text: text)
    }

    private func inFamille(_ id: Int64, _ text: String = "Salut") -> ChatMessage {
        Fixture.message(id, text: text, chatId: familleId, sender: .user(Fixture.paul))
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition non remplie à temps", file: file, line: line)
    }

    func testOpenChatModeAnnouncesOnlyTheOpenConversation() async {
        let (announcer, hub, service, spoken) = await makeAnnouncer(mode: .openChat)
        hub.openChatId = Fixture.chatId
        service.send(.new(fromMarie(10)))
        await waitUntil { spoken.texts.count == 1 }
        XCTAssertEqual(announcer.lastAnnouncement, "Marie Dupont : Bonjour.")

        service.send(.new(inFamille(20)))
        service.send(.new(fromMarie(11, "Tu es là ?")))
        await waitUntil { spoken.texts.count == 2 }
        XCTAssertEqual(spoken.texts.last, "Marie Dupont : Tu es là ?", "Famille n'est pas ouverte")
    }

    func testAllChatsModeGroupsABurstPerChat() async {
        let (_, _, service, spoken) = await makeAnnouncer(mode: .allChats, delay: .milliseconds(300))
        service.send(.new(inFamille(20)))
        service.send(.new(inFamille(21)))
        service.send(.new(inFamille(22)))
        service.send(.new(fromMarie(10)))
        await waitUntil { !spoken.texts.isEmpty }
        XCTAssertEqual(spoken.texts, ["3 nouveaux messages dans Famille. Marie Dupont : Bonjour."])
    }

    func testMutedChatIsSkippedInAllChatsMode() async {
        let (_, _, service, spoken) = await makeAnnouncer(mode: .allChats, familleMuted: true)
        service.send(.new(inFamille(20)))
        service.send(.new(fromMarie(10)))
        await waitUntil { !spoken.texts.isEmpty }
        XCTAssertEqual(spoken.texts, ["Marie Dupont : Bonjour."])
    }

    func testOutgoingAndCatchUpMessagesAreSkipped() async {
        let (_, hub, service, spoken) = await makeAnnouncer(mode: .openChat)
        hub.openChatId = Fixture.chatId
        service.send(.new(Fixture.message(10, text: "Moi", sender: .user(Fixture.me), outgoing: true)))
        service.send(.new(Fixture.message(11, text: "Ancien", date: ChatTestData.date(2026, 11, 10, 9, 0))))
        service.send(.new(fromMarie(12, "Récent")))
        await waitUntil { !spoken.texts.isEmpty }
        XCTAssertEqual(spoken.texts, ["Marie Dupont : Récent."])
    }

    func testNothingIsSaidWithoutVoiceOverOrInBackground() async throws {
        let (_, hub, service, spoken) = await makeAnnouncer(mode: .openChat, canSpeak: false)
        hub.openChatId = Fixture.chatId
        service.send(.new(fromMarie(10)))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(spoken.texts.isEmpty)
    }
}
