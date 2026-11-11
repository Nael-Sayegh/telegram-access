import XCTest

/// Écran de conversation affiché avec les messages factices de `UITestChatData` (argument
/// `-uiTestAuthStep ready`, builds Debug) : libellés, audit d'accessibilité, envoi.
/// Ne remplacent pas un test manuel avec VoiceOver.
final class ConversationAccessibilityTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private static let marieRow = "Marie Dupont, 3 non lus, dernier message : On se voit demain ?, 9 h 05"
    private static let lastMessage = "On se voit demain ?, 9 h 05"

    /// Élément dont le libellé VoiceOver est exactement `label`.
    @MainActor
    private func element(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Ouvre la conversation avec Marie depuis la liste.
    @MainActor
    private func openMarie() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestAuthStep", "ready"]
        app.launch()
        let row = element(app, Self.marieRow)
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Ligne de Marie introuvable")
        row.tap()
        XCTAssertTrue(element(app, Self.lastMessage).waitForExistence(timeout: 10), "Conversation non affichée")
        return app
    }

    /// Un message = un élément, lu dans l'ordre auteur, contenu, message cité, heure, état ;
    /// auteur omis pour un message reçu en tête-à-tête.
    @MainActor
    func testMessageLabels() throws {
        let app = openMarie()
        XCTAssertTrue(element(app, "Bonjour !, 8 h 50").exists)
        XCTAssertTrue(
            element(app, "Alors, tu l'as regardé ?, en réponse à votre message : Pas encore, je regarde ce soir., 9 h").exists
        )
        // Messages d'hier : peuvent être au-dessus de la zone visible, d'où l'attente.
        XCTAssertTrue(element(app, "Message vocal, 12 secondes, 19 h").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "Vous, Pas encore, je regarde ce soir., 18 h 45, lu").exists)
    }

    @MainActor
    func testDayHeaders() throws {
        let app = openMarie()
        XCTAssertTrue(element(app, "Aujourd'hui").waitForExistence(timeout: 5), "En-tête du jour absent")
        XCTAssertTrue(element(app, "Hier").waitForExistence(timeout: 5), "En-tête d'hier absent")
    }

    @MainActor
    func testConversationScreen() throws {
        let app = openMarie()
        XCTAssertTrue(app.buttons["Aller au premier message non lu"].exists)
        XCTAssertTrue(app.buttons["Aller au dernier message"].exists)
        try AccessibilityAudit.run(app)
    }

    /// Le message envoyé apparaît en bas, « Vous » en tête de libellé.
    @MainActor
    func testSendingAMessage() throws {
        let app = openMarie()
        let field = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR placeholderValue == %@", "Message", "Message"))
            .firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Champ de rédaction introuvable")
        field.tap()
        app.typeText("Coucou")
        app.buttons["Envoyer"].tap()

        let sent = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Vous, Coucou, "))
            .firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 5), "Message envoyé absent")
        XCTAssertTrue(sent.label.hasSuffix(", envoyé"), sent.label)
    }

    /// Un message vide n'est pas envoyé (le bouton reste actif, l'erreur est annoncée).
    @MainActor
    func testEmptyMessageIsNotSent() throws {
        let app = openMarie()
        let send = app.buttons["Envoyer"]
        XCTAssertTrue(send.isEnabled, "Le bouton Envoyer n'est jamais estompé")
        send.tap()
        let sent = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Vous, Message vide"))
            .firstMatch
        XCTAssertFalse(sent.waitForExistence(timeout: 2))
    }
}
