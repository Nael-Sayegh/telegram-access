import XCTest
@testable import TelegramAccess

final class MessageActionLabelsTests: XCTestCase {
    private func row(
        content: MessageContentSummary = .text("Bonjour"),
        outgoing: Bool = false,
        links: [URL] = [],
        pinned: Bool = false,
        failed: Bool = false,
        pending: Bool = false,
        canCopy: Bool = true
    ) -> MessageRowModel {
        var row = MessageRowModel(id: 10, senderLabel: nil, isOutgoing: outgoing, content: content, date: ChatTestData.now)
        row.links = links
        row.isPinned = pinned
        row.isFailed = failed
        row.isPending = pending
        row.canCopy = canCopy
        return row
    }

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

    func testFullActionListInFixedOrder() {
        let link = URL(string: "https://exemple.fr")!
        let actions = MessageActionLabels.actions(for: row(links: [link]), capabilities: everything, canReact: true)
        XCTAssertEqual(actions, [.reply, .react, .copy, .forward, .edit, .pin, .openLink(link), .delete])
        XCTAssertEqual(actions.map(MessageActionLabels.name), [
            "Répondre", "Réagir", "Copier", "Transférer", "Modifier", "Épingler", "Ouvrir exemple.fr", "Supprimer",
        ])
    }

    func testActionsFollowTelegramCapabilities() {
        let readOnly = MessageCapabilities(canBeReplied: true, canBeSaved: false)
        let actions = MessageActionLabels.actions(for: row(canCopy: false), capabilities: readOnly, canReact: false)
        XCTAssertEqual(actions, [.reply], "Ni copie (contenu protégé), ni réaction, ni suppression")
    }

    func testPinnedMessageOffersUnpinAndMediaCannotBeEdited() {
        let actions = MessageActionLabels.actions(
            for: row(content: .photo(caption: "Vacances"), pinned: true),
            capabilities: everything,
            canReact: true
        )
        XCTAssertTrue(actions.contains(.unpin))
        XCTAssertFalse(actions.contains(.pin))
        XCTAssertFalse(actions.contains(.edit), "Seul un texte se modifie")
    }

    func testFailedMessageOffersResendFirst() {
        let actions = MessageActionLabels.actions(for: row(outgoing: true, failed: true), capabilities: nil, canReact: true)
        XCTAssertEqual(actions, [.resend, .copy, .delete])
        XCTAssertEqual(MessageActionLabels.name(.resend), "Réessayer l'envoi")
    }

    func testBeforeCapabilitiesOnlyCopyAndLinks() {
        let links = (1...5).map { URL(string: "https://site\($0).fr")! }
        let actions = MessageActionLabels.actions(for: row(links: links), capabilities: nil, canReact: true)
        XCTAssertEqual(actions, [MessageAction.copy] + links.prefix(3).map { MessageAction.openLink($0) }, "3 liens au plus")
    }

    func testPendingMessageCannotGetReactions() {
        let actions = MessageActionLabels.actions(for: row(outgoing: true, pending: true), capabilities: everything, canReact: true)
        XCTAssertFalse(actions.contains(.react))
    }

    func testCopyableText() {
        XCTAssertEqual(MessageActionLabels.copyableText(.text("Salut")), "Salut")
        XCTAssertEqual(MessageActionLabels.copyableText(.photo(caption: "Plage")), "Plage")
        XCTAssertEqual(MessageActionLabels.copyableText(.document(fileName: "a.pdf", size: 1, caption: "Devis")), "Devis")
        XCTAssertNil(MessageActionLabels.copyableText(.photo(caption: "  ")))
        XCTAssertNil(MessageActionLabels.copyableText(.sticker(emoji: "😀")))
        XCTAssertNil(MessageActionLabels.copyableText(.text("")))
    }

    func testDeletionDialog() {
        let both = MessageActionLabels.deletionDialog(
            capabilities: everything, chatTitle: "Marie Dupont", isPrivateChat: true, isSavedMessages: false
        )
        XCTAssertEqual(both, MessageDeletionDialog(
            title: "Supprimer ce message ?",
            forMe: "Supprimer pour moi",
            forEveryone: "Supprimer aussi pour Marie Dupont"
        ))

        let group = MessageActionLabels.deletionDialog(
            capabilities: everything, chatTitle: "Famille", isPrivateChat: false, isSavedMessages: false
        )
        XCTAssertEqual(group.forEveryone, "Supprimer pour tous")

        let selfOnly = MessageActionLabels.deletionDialog(
            capabilities: MessageCapabilities(canBeDeletedOnlyForSelf: true),
            chatTitle: "Famille", isPrivateChat: false, isSavedMessages: false
        )
        XCTAssertEqual(selfOnly.forMe, "Supprimer")
        XCTAssertNil(selfOnly.forEveryone)
    }

    func testResultsAndErrors() {
        XCTAssertEqual(MessageActionLabels.reaction(.emoji("👍"), added: true), "Réaction 👍 ajoutée.")
        XCTAssertEqual(MessageActionLabels.reaction(.emoji("👍"), added: false), "Réaction 👍 retirée.")
        XCTAssertEqual(MessageActionLabels.forwarded(to: "Famille"), "Message transféré à Famille.")
        XCTAssertEqual(MessageActionLabels.replyContext(.named("Paul Martin")), "Réponse à Paul Martin")
        XCTAssertEqual(MessageActionLabels.replyContext(.me), "Réponse à votre message")
        XCTAssertEqual(
            MessageActionLabels.error(TelegramError(code: 400, message: "MESSAGE_EDIT_TIME_EXPIRED")),
            "Ce message ne peut plus être modifié."
        )
        XCTAssertEqual(
            MessageActionLabels.error(TelegramError(code: 400, message: "MESSAGE_NOT_MODIFIED")),
            "Le message n'a pas changé."
        )
        XCTAssertEqual(
            MessageActionLabels.error(TelegramError(code: 500, message: "INTERNAL")),
            "L'action n'a pas abouti. Vérifiez votre connexion et réessayez."
        )
    }
}
