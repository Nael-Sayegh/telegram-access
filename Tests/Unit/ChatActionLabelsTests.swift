import XCTest
@testable import TelegramAccess

final class ChatActionLabelsTests: XCTestCase {
    private func names(_ row: ChatRowModel, _ list: ChatListKind) -> [String] {
        ChatActionLabels.actions(for: row, in: list).map { ChatActionLabels.name($0, for: row) }
    }

    func testActionsReflectStateInFixedOrder() {
        var row = ChatTestData.row(pinned: true, muted: true)
        row.hasUnread = true
        XCTAssertEqual(
            names(row, .main),
            ["Marquer comme lu", "Désépingler", "Réactiver les notifications", "Archiver", "Supprimer"]
        )
    }

    func testActionsForReadChatInArchive() {
        XCTAssertEqual(
            names(ChatTestData.row(), .archive),
            ["Marquer comme non lu", "Épingler", "Désactiver les notifications", "Désarchiver", "Supprimer"]
        )
    }

    func testDeleteIsNamedAfterChatKind() {
        XCTAssertEqual(ChatActionLabels.name(.delete, for: ChatTestData.row(kind: .supergroup)), "Quitter le groupe")
        XCTAssertEqual(ChatActionLabels.name(.delete, for: ChatTestData.row(kind: .channel)), "Quitter la chaîne")
        XCTAssertEqual(
            ChatActionLabels.confirmation(.delete, for: ChatTestData.row(kind: .channel)),
            "Vous avez quitté la chaîne."
        )
    }

    func testDeletionDialogForPrivateChat() {
        var row = ChatTestData.row()
        XCTAssertEqual(
            ChatActionLabels.deletionDialog(for: row),
            ChatDeletionDialog(title: "Supprimer la conversation avec Marie Dupont ?", confirm: "Supprimer pour moi")
        )
        row.canDeleteForEveryone = true
        XCTAssertEqual(ChatActionLabels.deletionDialog(for: row).confirmForEveryone, "Supprimer aussi pour Marie Dupont")
    }

    func testDeletionDialogForGroupsAndSavedMessages() {
        XCTAssertEqual(
            ChatActionLabels.deletionDialog(for: ChatTestData.row(title: "Famille", kind: .basicGroup)),
            ChatDeletionDialog(title: "Quitter le groupe « Famille » ?", confirm: "Quitter le groupe")
        )
        var saved = ChatTestData.row(title: "Messages enregistrés")
        saved.isSavedMessages = true
        XCTAssertEqual(ChatActionLabels.deletionDialog(for: saved).title, "Vider les Messages enregistrés ?")
    }

    func testArchiveRow() {
        XCTAssertEqual(ChatActionLabels.archiveRow(total: 12, unread: 3), "Archives, 12 conversations, 3 non lues")
        XCTAssertEqual(ChatActionLabels.archiveRow(total: 1, unread: 0), "Archives, 1 conversation")
    }

    func testErrors() {
        XCTAssertEqual(
            ChatActionLabels.error(TelegramError(code: 400, message: "The maximum number of pinned chats exceeded")),
            "Nombre maximal de conversations épinglées atteint. Désépinglez-en une d'abord."
        )
        XCTAssertEqual(
            ChatActionLabels.error(TelegramError(code: 429, message: "Too Many Requests: retry after 10")),
            "Trop de demandes. Réessayez dans quelques instants."
        )
        XCTAssertEqual(
            ChatActionLabels.error(TelegramError(code: 500, message: "Internal")),
            "L'action n'a pas abouti. Vérifiez votre connexion et réessayez."
        )
    }
}
