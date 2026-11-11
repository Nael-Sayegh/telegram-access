import XCTest
@testable import TelegramAccess

/// Libellés VoiceOver des messages, à partir des lignes résolues (`messageRow`).
final class ConversationLabelsTests: XCTestCase {
    private typealias Fixture = ConversationTestData
    private let calendar = ChatTestData.calendar

    private let marieChat = ChatTestData.chat(Fixture.chatId, kind: .user(userId: Fixture.marie), lastReadOutbox: 20)
    private let family = ChatTestData.chat(-100, kind: .supergroup, title: "Famille")
    private let channel = ChatTestData.chat(-200, kind: .channel, title: "Infos")
    private let saved = ChatTestData.chat(42, kind: .user(userId: ConversationTestData.me), title: "Moi")

    /// Libellé du message `id` de la conversation `chat` chargée avec `messages`.
    private func label(_ id: Int64, in chat: ChatSummary, _ messages: [ChatMessage]) -> String {
        let list = Fixture.listState(chats: [marieChat, family, channel, saved])
        let conversation = Fixture.loadedState(messages, chatId: chat.id)
        let message = conversation.messages[id]!
        let row = list.messageRow(message, in: list.chats[chat.id]!, conversation: conversation)
        return ConversationLabels.message(row, calendar: calendar)
    }

    // MARK: - Auteur et état

    func testIncomingPrivateMessageHasNoAuthor() {
        XCTAssertEqual(
            label(10, in: marieChat, [Fixture.message(10, text: "On se voit demain ?")]),
            "On se voit demain ?, 14 h 32"
        )
    }

    func testOutgoingMessageSaysYouAndReadState() {
        let read = Fixture.message(20, text: "D'accord", sender: .user(Fixture.me), outgoing: true)
        let unread = Fixture.message(30, text: "À demain", sender: .user(Fixture.me), outgoing: true)
        XCTAssertEqual(label(20, in: marieChat, [read, unread]), "Vous, D'accord, 14 h 32, lu")
        XCTAssertEqual(label(30, in: marieChat, [read, unread]), "Vous, À demain, 14 h 32, envoyé")
    }

    func testPendingAndFailedStates() {
        let pending = Fixture.message(40, text: "Envoi", sender: .user(Fixture.me), outgoing: true, delivery: .pending)
        let failed = Fixture.message(41, text: "Raté", sender: .user(Fixture.me), outgoing: true, delivery: .failed)
        XCTAssertEqual(label(40, in: marieChat, [pending, failed]), "Vous, Envoi, 14 h 32, en cours d'envoi")
        XCTAssertEqual(label(41, in: marieChat, [pending, failed]), "Vous, Raté, 14 h 32, échec de l'envoi")
    }

    func testGroupMessageGivesFullAuthorName() {
        let message = Fixture.message(10, text: "Salut à tous", chatId: -100, sender: .user(Fixture.paul))
        XCTAssertEqual(label(10, in: family, [message]), "Paul Martin, Salut à tous, 14 h 32")
    }

    func testChannelPostShowsSignatureOnlyAndNoStatus() {
        var signed = Fixture.message(10, text: "Nouvelle version", chatId: -200, sender: .chat(-200), outgoing: true)
        signed.isChannelPost = true
        signed.authorSignature = "Jean"
        var plain = Fixture.message(11, text: "Correctif", chatId: -200, sender: .chat(-200))
        plain.isChannelPost = true
        XCTAssertEqual(label(10, in: channel, [signed, plain]), "Jean, Nouvelle version, 14 h 32")
        XCTAssertEqual(label(11, in: channel, [signed, plain]), "Correctif, 14 h 32")
    }

    func testSavedMessagesHaveNoAuthorNorStatus() {
        let note = Fixture.message(10, text: "Liste de courses", chatId: 42, sender: .user(Fixture.me), outgoing: true)
        XCTAssertEqual(label(10, in: saved, [note]), "Liste de courses, 14 h 32")
    }

    // MARK: - Réponses et transferts

    func testReplyToOwnMessage() {
        let mine = Fixture.message(10, text: "On se voit demain ?", sender: .user(Fixture.me), outgoing: true)
        let answer = Fixture.message(
            11, text: "Oui", replyTo: MessageReplyRef(chatId: Fixture.chatId, messageId: 10)
        )
        XCTAssertEqual(
            label(11, in: marieChat, [mine, answer]),
            "Oui, en réponse à votre message : On se voit demain ?, 14 h 32"
        )
    }

    func testReplyInGroupNamesTheAuthorAndPrefersTheQuote() {
        let question = Fixture.message(10, text: "Qui vient samedi ? Il faut réserver", chatId: -100, sender: .user(Fixture.marie))
        let answer = Fixture.message(
            11, text: "Moi", chatId: -100, sender: .user(Fixture.paul),
            replyTo: MessageReplyRef(chatId: -100, messageId: 10, quote: "Qui vient samedi ?")
        )
        XCTAssertEqual(
            label(11, in: family, [question, answer]),
            "Paul Martin, Moi, en réponse à Marie Dupont : Qui vient samedi ?, 14 h 32"
        )
    }

    func testReplyToDeletedOrUnknownMessage() {
        var conversation = Fixture.loadedState([
            Fixture.message(10),
            Fixture.message(11, text: "Oui", replyTo: MessageReplyRef(chatId: Fixture.chatId, messageId: 10)),
            Fixture.message(12, text: "Et ça ?", replyTo: MessageReplyRef(chatId: Fixture.chatId, messageId: 3)),
        ])
        conversation.apply(.deleted(chatId: Fixture.chatId, messageIds: [10]))
        let list = Fixture.listState(chats: [marieChat])
        let chat = list.chats[Fixture.chatId]!
        let deleted = list.messageRow(conversation.messages[11]!, in: chat, conversation: conversation)
        let unknown = list.messageRow(conversation.messages[12]!, in: chat, conversation: conversation)
        XCTAssertEqual(ConversationLabels.message(deleted, calendar: calendar), "Oui, en réponse à un message supprimé, 14 h 32")
        XCTAssertEqual(ConversationLabels.message(unknown, calendar: calendar), "Et ça ?, en réponse à un message, 14 h 32")
    }

    func testReplyFromAnotherChatUsesItsOrigin() {
        let reply = MessageReplyRef(
            chatId: -200, messageId: 9, origin: .channel(-200, signature: ""), content: .photo(caption: "Affiche")
        )
        let message = Fixture.message(10, text: "Joli", replyTo: reply)
        XCTAssertEqual(label(10, in: marieChat, [message]), "Joli, en réponse à Infos : Photo : Affiche, 14 h 32")
    }

    func testForwardedMessage() {
        let fromPaul = Fixture.message(10, forward: .user(Fixture.paul))
        let fromChannel = Fixture.message(11, forward: .channel(-200, signature: "Jean"))
        let hidden = Fixture.message(12, forward: .hiddenUser(name: "Anonyme"))
        let messages = [fromPaul, fromChannel, hidden]
        XCTAssertEqual(label(10, in: marieChat, messages), "transféré de Paul Martin, Bonjour, 14 h 32")
        XCTAssertEqual(label(11, in: marieChat, messages), "transféré de Infos (Jean), Bonjour, 14 h 32")
        XCTAssertEqual(label(12, in: marieChat, messages), "transféré de Anonyme, Bonjour, 14 h 32")
    }

    // MARK: - États du message

    func testEditedPinnedAndReactions() {
        var message = Fixture.message(10)
        message.editDate = ChatTestData.now
        message.isPinned = true
        message.reactions = [
            MessageReactionCount(kind: .emoji("👍"), count: 2, isChosen: true),
            MessageReactionCount(kind: .emoji("❤️"), count: 1, isChosen: false),
        ]
        XCTAssertEqual(
            label(10, in: marieChat, [message]),
            "Bonjour, 14 h 32, modifié, épinglé, réactions : 👍 2 dont vous, ❤️ 1"
        )
    }

    func testReactionWording() {
        XCTAssertNil(ConversationLabels.reactions([]))
        XCTAssertEqual(
            ConversationLabels.reactions([MessageReactionCount(kind: .emoji("😂"), count: 1, isChosen: true)]),
            "réactions : 😂 de vous"
        )
        XCTAssertEqual(
            ConversationLabels.reactions([MessageReactionCount(kind: .paid, count: 5, isChosen: false)]),
            "réactions : étoiles 5"
        )
    }

    func testUnlistenedVoiceNote() {
        let media = MessageMedia(kind: .voiceNote, file: FileRef(id: 1, size: 0, localPath: nil), isListened: false)
        let incoming = Fixture.message(10, media: media, content: .voiceNote(duration: 12, caption: ""))
        let outgoing = Fixture.message(
            11, sender: .user(Fixture.me), outgoing: true, media: media, content: .voiceNote(duration: 3, caption: "")
        )
        XCTAssertEqual(label(10, in: marieChat, [incoming, outgoing]), "Message vocal, 12 secondes, non écouté, 14 h 32")
        // Envoyé : « non écouté » n'est jamais dit (il concernerait le destinataire).
        XCTAssertEqual(label(11, in: marieChat, [incoming, outgoing]), "Vous, Message vocal, 3 secondes, 14 h 32, lu")
    }

    func testEmptyTextIsNamed() {
        XCTAssertEqual(label(10, in: marieChat, [Fixture.message(10, text: "  ")]), "Message vide, 14 h 32")
    }

    func testLongReplyExcerptIsCutOnAWord() {
        let long = String(repeating: "mot ", count: 40)
        let excerpt = ConversationLabels.excerpt(long)
        XCTAssertTrue(excerpt.hasSuffix("mot…"), excerpt)
        XCTAssertLessThanOrEqual(excerpt.count, ConversationLabels.replyExcerptLimit + 1)
    }

    // MARK: - Dates

    func testTime() {
        XCTAssertEqual(ConversationLabels.time(ChatTestData.date(2026, 11, 10, 9, 0), calendar: calendar), "9 h")
        XCTAssertEqual(ConversationLabels.time(ChatTestData.date(2026, 11, 10, 14, 5), calendar: calendar), "14 h 05")
        XCTAssertEqual(ConversationLabels.visibleTime(ChatTestData.date(2026, 11, 10, 9, 5), calendar: calendar), "09:05")
    }

    /// Mardi 10 novembre 2026.
    func testDayHeaders() {
        let now = ChatTestData.now
        func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> String {
            ConversationLabels.day(ChatTestData.date(year, month, dayOfMonth), now: now, calendar: calendar)
        }
        XCTAssertEqual(day(2026, 11, 10), "Aujourd'hui")
        XCTAssertEqual(day(2026, 11, 9), "Hier")
        XCTAssertEqual(day(2026, 11, 8), "Dimanche 8 novembre")
        XCTAssertEqual(day(2026, 11, 3), "3 novembre")
        XCTAssertEqual(day(2025, 11, 1), "1er novembre 2025")
    }

    // MARK: - Activité

    func testActivityText() {
        XCTAssertNil(ConversationLabels.activity([], isPrivateChat: true))
        typealias Active = (name: String, activity: ChatActivity)
        let marie: Active = (name: "Marie", activity: .typing)
        let paul: Active = (name: "Paul", activity: .typing)
        let paulRecording: Active = (name: "Paul", activity: .recordingVoiceNote)
        let lea: Active = (name: "Léa", activity: .sendingFile)
        XCTAssertEqual(ConversationLabels.activity([marie], isPrivateChat: true), "écrit…")
        XCTAssertEqual(
            ConversationLabels.activity([paulRecording], isPrivateChat: false),
            "Paul enregistre un message vocal…"
        )
        XCTAssertEqual(ConversationLabels.activity([paul, marie], isPrivateChat: false), "Paul et Marie écrivent…")
        XCTAssertEqual(
            ConversationLabels.activity([paul, marie, lea], isPrivateChat: false),
            "3 personnes sont en activité…"
        )
    }
}

final class MessageTextToolsTests: XCTestCase {
    /// Les décalages TDLib comptent en UTF-16 : un émoji vaut 2 unités.
    func testSubstringUsesUTF16Offsets() {
        let text = "😀 voir exemple.fr"
        XCTAssertEqual(MessageTextTools.substring(of: text, offset: 8, length: 10), "exemple.fr")
        XCTAssertNil(MessageTextTools.substring(of: text, offset: 15, length: 10))
        XCTAssertNil(MessageTextTools.substring(of: text, offset: -1, length: 2))
    }

    func testOpenableURLs() {
        XCTAssertEqual(MessageTextTools.openableURL("exemple.fr")?.absoluteString, "https://exemple.fr")
        XCTAssertEqual(MessageTextTools.openableURL(" http://exemple.fr/page ")?.absoluteString, "http://exemple.fr/page")
        XCTAssertEqual(MessageTextTools.openableURL("exemple.fr:8080/page")?.host, "exemple.fr")
        XCTAssertNotNil(MessageTextTools.openableURL("mailto:marie@exemple.fr"))
        XCTAssertNotNil(MessageTextTools.openableURL("tg://resolve?domain=canal"))
        XCTAssertEqual(MessageTextTools.openableURL("tel:0612345678")?.absoluteString, "tel:0612345678")
        XCTAssertNotNil(MessageTextTools.openableURL("shortcuts://run-shortcut?name=Test"))
        XCTAssertNil(MessageTextTools.openableURL("javascript:alert(1)"))
        XCTAssertNil(MessageTextTools.openableURL("file:///etc/hosts"))
        XCTAssertNil(MessageTextTools.openableURL("https://"))
        XCTAssertNil(MessageTextTools.openableURL(""))
    }

    /// Web, Telegram et courriel s'ouvrent directement ; une autre app après confirmation.
    func testOtherAppsRequireConfirmation() {
        func confirms(_ text: String) -> Bool {
            MessageTextTools.requiresConfirmation(MessageTextTools.openableURL(text)!)
        }
        XCTAssertFalse(confirms("exemple.fr"))
        XCTAssertFalse(confirms("HTTPS://exemple.fr"))
        XCTAssertFalse(confirms("tg://resolve?domain=canal"))
        XCTAssertFalse(confirms("mailto:marie@exemple.fr"))
        XCTAssertTrue(confirms("tel:+33899000000"))
        XCTAssertTrue(confirms("sms:+33612345678"))
        XCTAssertTrue(confirms("shortcuts://run-shortcut?name=Test"))
    }

    func testShortNames() {
        func name(_ text: String) -> String {
            MessageTextTools.shortName(URL(string: text)!)
        }
        XCTAssertEqual(name("https://www.exemple.fr/page"), "exemple.fr")
        XCTAssertEqual(name("https://t.me/canal/12"), "t.me/canal")
        XCTAssertEqual(name("mailto:marie@exemple.fr"), "marie@exemple.fr")
        XCTAssertEqual(name("tg://resolve?domain=canal"), "lien Telegram")
        XCTAssertEqual(name("tel:+33612345678"), "tel:+33612345678")
    }

    /// L'action donne la vraie destination, jamais le texte affiché dans le message.
    func testOpenLinkActionsAndConfirmation() {
        func action(_ text: String) -> String {
            ConversationLabels.openLinkAction(URL(string: text)!)
        }
        XCTAssertEqual(action("https://www.exemple.fr/page"), "Ouvrir exemple.fr")
        XCTAssertEqual(action("mailto:marie@exemple.fr"), "Écrire à marie@exemple.fr")
        XCTAssertEqual(action("tg://resolve?domain=canal"), "Ouvrir le lien Telegram")
        XCTAssertEqual(action("tel:+33899000000"), "Ouvrir dans une autre app : tel:+33899000000")

        let confirmation = ConversationLabels.linkConfirmation(URL(string: "tel:+33899000000")!)
        XCTAssertEqual(confirmation.title, "Ouvrir ce lien dans une autre app ?")
        XCTAssertEqual(confirmation.message, "Destination : tel:+33899000000")
        XCTAssertEqual(confirmation.confirm, "Ouvrir")
    }
}
