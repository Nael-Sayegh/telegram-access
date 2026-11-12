import XCTest
@testable import TelegramAccess

/// Actions sur les messages, réponse, modification et gestes du modèle de vue.
@MainActor
final class ConversationActionsTests: XCTestCase {
    private typealias Fixture = ConversationTestData

    private let everything = MessageCapabilities(
        canBeReplied: true,
        canBeEdited: true,
        canBeForwarded: true,
        canBePinned: true,
        canBeSaved: true,
        canBeDeletedOnlyForSelf: true,
        canBeDeletedForAllUsers: true,
        canGetLink: true
    )

    /// Conversation avec Marie ouverte sur `messages` (du plus récent au plus ancien), avec
    /// les propriétés Telegram `capabilities` pour chaque message.
    private func openModel(
        _ messages: [ChatMessage],
        capabilities: MessageCapabilities? = nil,
        extraChats: [ChatSummary] = []
    ) async -> (ConversationViewModel, FakeAuthService) {
        let service = FakeAuthService()
        await service.setHistoryPages([messages])
        await service.setCapabilities(capabilities ?? everything)
        let store = ChatStore(events: service.chatEvents)
        service.send(.myUserId(Fixture.me))
        service.send(.user(id: Fixture.marie, name: UserName(firstName: "Marie", lastName: "Dupont", isDeleted: false)))
        let chat = ChatTestData.chat(Fixture.chatId, kind: .user(userId: Fixture.marie))
        service.send(.newChat(chat))
        for other in extraChats {
            service.send(.newChat(other))
        }
        await waitUntil { store.state.chats[chat.id] != nil && store.state.chats.count == 1 + extraChats.count }
        let hub = MessageHub(events: service.messageEvents)
        let model = ConversationViewModel(chatId: chat.id, store: store, hub: hub, service: service)
        model.copyHandler = { _ in }
        await model.open()
        return (model, service)
    }

    private func row(_ model: ConversationViewModel, _ id: Int64) -> MessageRowModel {
        model.items.compactMap(\.message).first { $0.id == id }!
    }

    /// Propriétés chargées à l'apparition du message.
    private func appear(_ model: ConversationViewModel, _ id: Int64) async {
        model.messageAppeared(id)
        await waitUntil { model.capabilities[id] != nil }
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition non remplie à temps", file: file, line: line)
    }

    // MARK: - Actions

    func testActionsAppearOnceCapabilitiesAreLoaded() async {
        let (model, _) = await openModel([Fixture.message(10)])
        XCTAssertEqual(model.actions(for: row(model, 10)), [.copy], "Avant la réponse de Telegram")
        await appear(model, 10)
        XCTAssertEqual(model.actions(for: row(model, 10)), [.reply, .react, .copy, .forward, .edit, .pin, .delete])
    }

    func testReplyIsSentWithTheCitedMessage() async {
        let (model, service) = await openModel([Fixture.message(10, text: "On se voit ?")])
        model.perform(.reply, on: row(model, 10))
        XCTAssertEqual(model.replyingTo, 10)
        XCTAssertEqual(model.composerFocusRequest, 1, "Clavier et focus dans le champ")
        XCTAssertEqual(model.composerFieldLabel, "Réponse à Marie Dupont")
        XCTAssertEqual(model.composerContext?.excerpt, "On se voit ?")

        model.draft = "Oui"
        model.send()
        await waitUntil { await service.messageCalls.contains("send 1 Oui reply:10") }
        XCTAssertNil(model.replyingTo)
        XCTAssertEqual(model.composerFieldLabel, "Message")
    }

    func testEscapeCancelsReplyThenLetsTheScreenClose() async {
        let (model, _) = await openModel([Fixture.message(10)])
        model.perform(.reply, on: row(model, 10))
        XCTAssertTrue(model.cancelComposerMode())
        XCTAssertEqual(model.lastAnnouncement, "Réponse annulée.")
        XCTAssertNil(model.replyingTo)
        XCTAssertFalse(model.cancelComposerMode(), "Rien à annuler : Escape revient à la liste")
    }

    func testEditingReplacesTheTextAndRestoresTheDraftAfterward() async {
        let mine = Fixture.message(10, text: "Bonjoru", sender: .user(Fixture.me), outgoing: true)
        let (model, service) = await openModel([mine])
        model.draft = "brouillon"
        model.perform(.edit, on: row(model, 10))
        XCTAssertEqual(model.editing, 10)
        XCTAssertEqual(model.draft, "Bonjoru")
        XCTAssertEqual(model.composerFieldLabel, "Modification du message")

        model.draft = "Bonjour"
        model.send()
        await waitUntil { await service.messageCalls.contains("edit 1 10 Bonjour") }
        await waitUntil { model.lastAnnouncement == "Message modifié." }
        XCTAssertNil(model.editing)
        XCTAssertEqual(model.draft, "brouillon", "Le brouillon mis de côté revient")
    }

    func testCancelledEditRestoresTheDraft() async {
        let mine = Fixture.message(10, text: "Texte", sender: .user(Fixture.me), outgoing: true)
        let (model, _) = await openModel([mine])
        model.draft = "brouillon"
        model.perform(.edit, on: row(model, 10))
        XCTAssertTrue(model.cancelComposerMode())
        XCTAssertEqual(model.lastAnnouncement, "Modification annulée.")
        XCTAssertEqual(model.draft, "brouillon")
    }

    func testCopyUsesThePasteboardAndAnnounces() async {
        let (model, _) = await openModel([Fixture.message(10, text: "À copier")])
        var copied: String?
        model.copyHandler = { copied = $0 }
        model.perform(.copy, on: row(model, 10))
        XCTAssertEqual(copied, "À copier")
        XCTAssertEqual(model.lastAnnouncement, "Message copié.")
    }

    func testPinCallsTelegramAndAnnounces() async {
        let (model, service) = await openModel([Fixture.message(10)])
        model.perform(.pin, on: row(model, 10))
        await waitUntil { await service.messageCalls.contains("pinMessage 1 10 true") }
        await waitUntil { model.lastAnnouncement == "Message épinglé." }
    }

    func testDeletionAsksFirstThenDeletes() async {
        let (model, service) = await openModel([Fixture.message(10)])
        await appear(model, 10)
        let message = row(model, 10)
        model.perform(.delete, on: message)
        XCTAssertEqual(model.deletionRequest, message)
        XCTAssertEqual(model.deletionDialog(for: message).forEveryone, "Supprimer aussi pour Marie Dupont")
        let before = await service.messageCalls
        XCTAssertFalse(before.contains { $0.hasPrefix("deleteMessages") })

        model.confirmDeletion(of: message, forEveryone: true)
        XCTAssertNil(model.deletionRequest)
        await waitUntil { await service.messageCalls.contains("deleteMessages 1 10 true") }
        await waitUntil { model.lastAnnouncement == "Message supprimé." }
    }

    func testReactionIsAddedThenRemoved() async {
        var message = Fixture.message(10)
        let (model, service) = await openModel([message])
        await service.setAvailableReactions([.emoji("👍"), .emoji("❤️")])
        model.perform(.react, on: row(model, 10))
        await waitUntil { model.reactionChoices == [.emoji("👍"), .emoji("❤️")] }

        model.toggleReaction(.emoji("👍"), on: row(model, 10))
        XCTAssertNil(model.reactionRequest, "Feuille fermée au choix")
        await waitUntil { model.lastAnnouncement == "Réaction 👍 ajoutée." }

        message.reactions = [MessageReactionCount(kind: .emoji("👍"), count: 1, isChosen: true)]
        service.send(.reactions(chatId: Fixture.chatId, messageId: 10, reactions: message.reactions))
        await waitUntil { !self.row(model, 10).reactions.isEmpty }
        model.toggleReaction(.emoji("👍"), on: row(model, 10))
        await waitUntil { model.lastAnnouncement == "Réaction 👍 retirée." }
        let calls = await service.messageCalls.filter { $0.hasPrefix("react") }
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls[0].hasSuffix("true"))
        XCTAssertTrue(calls[1].hasSuffix("false"))
    }

    func testForwardToAnotherChat() async {
        let family = ChatTestData.chat(-100, kind: .supergroup, title: "Famille", order: 20)
        let secret = ChatTestData.chat(2, kind: .secret(secretChatId: 3, userId: Fixture.marie), title: "Secret", order: 5)
        let (model, service) = await openModel([Fixture.message(10)], extraChats: [family, secret])
        XCTAssertEqual(model.forwardTargets.map(\.title), ["Famille", "Marie Dupont"], "Sans conversation secrète")

        model.perform(.forward, on: row(model, 10))
        XCTAssertNotNil(model.forwardRequest)
        let target = model.forwardTargets[0]
        model.forward(row(model, 10), to: target)
        XCTAssertNil(model.forwardRequest)
        await waitUntil { await service.messageCalls.contains("forward 10 1 -100") }
        await waitUntil { model.lastAnnouncement == "Message transféré à Famille." }
    }

    func testLinkToAnotherAppNeedsConfirmation() async {
        let (model, _) = await openModel([Fixture.message(10)])
        let web = URL(string: "https://exemple.fr")!
        model.open(web)
        XCTAssertEqual(model.linkToOpen, web, "Ouvert directement")
        model.linkOpened()
        XCTAssertNil(model.linkToOpen)

        let phone = URL(string: "tel:+33899000000")!
        model.open(phone)
        XCTAssertNil(model.linkToOpen)
        XCTAssertEqual(model.linkConfirmation, phone)
        model.confirmLink(phone)
        XCTAssertNil(model.linkConfirmation)
        XCTAssertEqual(model.linkToOpen, phone)
    }

    func testResendAnnouncesThenTracksTheNewMessage() async {
        let failed = Fixture.message(10, sender: .user(Fixture.me), outgoing: true, delivery: .failed)
        let (model, service) = await openModel([failed])
        XCTAssertEqual(model.actions(for: row(model, 10)).first, .resend)
        model.perform(.resend, on: row(model, 10))
        await waitUntil { await service.messageCalls.contains("resend 1 10") }
        await waitUntil { model.lastAnnouncement == "Nouvel essai d'envoi." }

        service.send(.sendSucceeded(Fixture.message(2_000, sender: .user(Fixture.me), outgoing: true), oldId: 1000))
        await waitUntil { model.lastAnnouncement == "Message envoyé." }
    }

    // MARK: - Gestes et rotors

    func testMagicTapSendsTheDraftOrSaysThereIsNothing() async {
        let (model, service) = await openModel([Fixture.message(10)])
        model.magicTap()
        XCTAssertEqual(model.lastAnnouncement, "Aucun message à envoyer.")

        model.draft = "Envoyé au Magic Tap"
        model.magicTap()
        await waitUntil { await service.messageCalls.contains("send 1 Envoyé au Magic Tap") }
    }

    /// Rotor « Mentions » : une réponse à un de mes messages compte comme une mention, comme
    /// dans Telegram ; mes propres messages jamais.
    func testRepliesToMyMessagesAreMentions() async {
        let mine = Fixture.message(20, text: "Question", sender: .user(Fixture.me), outgoing: true)
        let answer = Fixture.message(30, text: "Réponse", replyTo: MessageReplyRef(chatId: Fixture.chatId, messageId: 20))
        let other = Fixture.message(40, text: "Autre chose")
        let (model, _) = await openModel([other, answer, mine])
        XCTAssertTrue(row(model, 30).isMention)
        XCTAssertFalse(row(model, 20).isMention)
        XCTAssertFalse(row(model, 40).isMention)
        XCTAssertFalse(model.isUnreadAtOpen(row(model, 40)), "Aucun non lu à l'ouverture")
    }
}
