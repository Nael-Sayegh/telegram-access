import XCTest

/// Liste des conversations affichée avec les conversations factices de `UITestChatData`
/// (argument `-uiTestAuthStep ready`, builds Debug) : audits d'accessibilité et libellés.
/// Ne remplacent pas un test manuel avec VoiceOver.
final class ChatListAccessibilityTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchList() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestAuthStep", "ready"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Discussions"].waitForExistence(timeout: 15), "Liste absente")
        return app
    }

    /// Élément dont le libellé VoiceOver est exactement `label`.
    @MainActor
    private func element(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private static let marieRow = "Marie Dupont, 3 non lus, dernier message : On se voit demain ?, 9 h 05"

    /// Une ligne = un seul élément, lu dans l'ordre nom, non lus, dernier message, heure.
    @MainActor
    func testChatRowLabels() throws {
        let app = launchList()
        XCTAssertTrue(element(app, Self.marieRow).waitForExistence(timeout: 5), "Ligne de Marie introuvable")
        XCTAssertTrue(element(app, "Famille, 1 non lu, 1 mention, Paul : Salut à tous, hier").exists)
        XCTAssertTrue(element(app, "Marie Dupont, conversation secrète, marquée comme non lue, Vous : D'accord, lu, 9 h 05").exists)
        XCTAssertTrue(element(app, "Messages enregistrés, dernier message : Liste de courses, 9 h 05").exists)
    }

    @MainActor
    func testChatListScreen() throws {
        let app = launchList()
        XCTAssertTrue(element(app, Self.marieRow).waitForExistence(timeout: 5))
        try AccessibilityAudit.run(app)
    }

    /// Ordre de la barre du haut pour VoiceOver : Options, Discussions, Rechercher, Filtre.
    @MainActor
    func testTopBarOrder() throws {
        let app = launchList()
        let bar = app.navigationBars["Discussions"]
        let labels = bar.descendants(matching: .any)
            .allElementsBoundByIndex
            .map(\.label)
            .filter { ["Options", "Discussions", "Rechercher", "Filtre : Tous"].contains($0) }
        var seen: [String] = []
        for label in labels where !seen.contains(label) { seen.append(label) }
        XCTAssertEqual(seen, ["Options", "Discussions", "Rechercher", "Filtre : Tous"])
    }

    @MainActor
    func testUnreadFilter() throws {
        let app = launchList()
        let paulRow = element(app, "Paul Martin, dernier message : Merci, hier")
        XCTAssertTrue(paulRow.waitForExistence(timeout: 5))

        let filter = app.buttons["Filtre : Tous"]
        XCTAssertTrue(filter.exists)
        filter.tap()
        // Non lus : Marie, Famille et la conversation secrète marquée « non lue ».
        let unread = app.buttons["Non lus (3)"]
        XCTAssertTrue(unread.waitForExistence(timeout: 5), "Option du menu Filtre absente")
        unread.tap()

        XCTAssertTrue(app.buttons["Filtre : Non lus"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, Self.marieRow).exists)
        XCTAssertFalse(paulRow.exists, "Conversation lue masquée par le filtre")
    }

    @MainActor
    func testArchiveScreen() throws {
        let app = launchList()
        let archive = element(app, "Archives, 1 conversation, 1 non lue")
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.tap()
        XCTAssertTrue(app.navigationBars["Archives"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "Ancien groupe, 1 non lu, Paul : Au revoir, hier").waitForExistence(timeout: 5))
        try AccessibilityAudit.run(app)
    }

    /// Recherche dans les messages (par défaut), puis parmi les conversations.
    @MainActor
    func testSearchScreen() throws {
        let app = launchList()
        app.buttons["Rechercher"].tap()
        XCTAssertTrue(app.navigationBars["Rechercher"].waitForExistence(timeout: 5))

        // Champ sur plusieurs lignes : vu comme une zone de texte, d'où la recherche par libellé.
        let field = element(app, "Rechercher dans les messages")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        app.typeText("demain\n")
        let message = element(app, "Marie Dupont, On se voit demain ?, 9 h 05")
        XCTAssertTrue(message.waitForExistence(timeout: 5), "Message trouvé absent")
        try AccessibilityAudit.run(app)

        app.buttons["Conversations"].tap()
        XCTAssertTrue(app.staticTexts["Aucune conversation trouvée pour « demain »."].waitForExistence(timeout: 5))
        XCTAssertFalse(message.exists)
    }

    /// Sans VoiceOver, la suppression passe par le balayage et demande confirmation.
    @MainActor
    func testDeletionAsksForConfirmation() throws {
        let app = launchList()
        let row = element(app, Self.marieRow)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        let delete = app.buttons["Supprimer"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirm = app.buttons["Supprimer pour moi"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Supprimer aussi pour Marie Dupont"].exists)

        // iOS 26 : pas de bouton « Annuler » visible, le dialogue (affiché près de la ligne, en
        // haut) se ferme en touchant à côté. Avec VoiceOver : geste d'échappement.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        if !confirm.waitForNonExistence(timeout: 3) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.6)).tap()
        }
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5), "Dialogue toujours affiché")
        XCTAssertTrue(row.exists, "La conversation doit rester sans confirmation")
    }
}
