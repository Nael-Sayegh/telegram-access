import XCTest

/// Écran de conversation affiché avec les messages factices de `UITestChatData` (argument
/// `-uiTestAuthStep ready`, builds Debug) : libellés, audit d'accessibilité, envoi.
/// Ne remplacent pas un test manuel avec VoiceOver.
final class ConversationAccessibilityTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private static let marieRow = "Marie Dupont, 3 non lus, dernier message : On se voit demain ?, 9 h 05"

    /// Élément dont le libellé VoiceOver est exactement `label`.
    @MainActor
    private func element(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Premier message non lu de Marie : le focus et l'écran y sont placés à l'ouverture.
    private static let firstUnread = "Bonjour !, 8 h 50"

    /// Ouvre la conversation avec Marie depuis la liste ; `textSize` : catégorie de taille de
    /// texte imposée au lancement (`UIContentSizeCategory`), taille du système sinon.
    @MainActor
    private func openMarie(textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestAuthStep", "ready"]
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        app.launch()
        XCTAssertTrue(app.navigationBars["Discussions"].waitForExistence(timeout: 15), "Liste absente")
        // Aux grandes tailles de texte, les premières lignes (Archives, Messages enregistrés)
        // remplissent l'écran : celle de Marie, plus bas, n'existe qu'une fois amenée à l'écran.
        let row = element(app, Self.marieRow)
        var swipes = 0
        while !row.waitForExistence(timeout: 2), swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(row.exists, "Ligne de Marie introuvable")
        row.tap()
        XCTAssertTrue(element(app, Self.firstUnread).waitForExistence(timeout: 10), "Conversation non affichée")
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

    /// Titres de jour ; le premier signale le début de la conversation une fois tout
    /// l'historique chargé.
    @MainActor
    func testDayHeaders() throws {
        let app = openMarie()
        XCTAssertTrue(element(app, "Aujourd'hui").waitForExistence(timeout: 5), "En-tête du jour absent")
        XCTAssertTrue(element(app, Self.firstDay).waitForExistence(timeout: 5), "Début de la conversation non signalé")
    }

    /// Premier titre de jour de Marie, une fois tout l'historique chargé.
    private static let firstDay = "Hier, début de la conversation"

    /// Comme WhatsApp : balayer donne chaque élément dans l'ordre chronologique, sans en
    /// sauter — jour (le premier signale le début), messages du jour, jour suivant…
    @MainActor
    func testMessagesAreReadInChronologicalOrder() throws {
        let app = openMarie()
        let expected = [
            Self.firstDay,
            "Tu as vu le programme de samedi ?, 18 h 30",
            "Vous, Pas encore, je regarde ce soir., 18 h 45, lu",
            "Message vocal, 12 secondes, 19 h",
            "Aujourd'hui",
            Self.firstUnread,
            "Alors, tu l'as regardé ?, en réponse à votre message : Pas encore, je regarde ce soir., 9 h",
            "On se voit demain ?, 9 h 05",
        ]
        XCTAssertTrue(element(app, Self.firstDay).waitForExistence(timeout: 5), "Début non signalé")
        var order: [String] = []
        for label in app.descendants(matching: .any).allElementsBoundByIndex.map(\.label)
        where expected.contains(label) && !order.contains(label) {
            order.append(label)
        }
        XCTAssertEqual(order, expected)
    }

    /// Audit complet, taille du texte comprise : avec la liste SwiftUI, l'audit l'évalue (il
    /// n'y arrivait pas dans l'ancienne liste UIKit, 2026-11-11). `testMessagesGrowWithTextSize`
    /// la contrôle aussi directement.
    @MainActor
    func testConversationScreen() throws {
        let app = openMarie()
        XCTAssertTrue(app.buttons["Aller au premier message non lu"].exists)
        XCTAssertTrue(app.buttons["Aller au dernier message"].exists)
        XCTAssertTrue(element(app, Self.firstDay).waitForExistence(timeout: 5))
        try AccessibilityAudit.run(app)
    }

    /// Dynamic Type : en très grande taille de texte (accessibilité XXXL), un message est
    /// nettement plus haut qu'à la taille par défaut (la bulle grandit, rien n'est coupé).
    /// Captures jointes au rapport pour un contrôle visuel.
    @MainActor
    func testMessagesGrowWithTextSize() throws {
        let regular = openMarie(textSize: "UICTContentSizeCategoryL")
        let regularHeight = element(regular, Self.firstUnread).frame.height
        attachScreenshot(of: regular, named: "Taille de texte par défaut")
        regular.terminate()

        let large = openMarie(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        let largeHeight = element(large, Self.firstUnread).frame.height
        attachScreenshot(of: large, named: "Taille de texte accessibilité XXXL")

        XCTAssertGreaterThan(regularHeight, 0)
        XCTAssertGreaterThan(
            largeHeight,
            regularHeight * 1.8,
            "Le message doit grandir avec la taille du texte (\(regularHeight) → \(largeHeight) points)"
        )
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
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

    /// Envoyer est estompé tant que le champ est vide ou ne contient que des espaces.
    @MainActor
    func testSendButtonIsDimmedWhileTheFieldIsEmpty() throws {
        let app = openMarie()
        let send = app.buttons["Envoyer"]
        XCTAssertTrue(send.exists)
        XCTAssertFalse(send.isEnabled, "Champ vide : bouton estompé")

        let field = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR placeholderValue == %@", "Message", "Message"))
            .firstMatch
        field.tap()
        app.typeText("   ")
        XCTAssertFalse(send.isEnabled, "Espaces seuls : bouton estompé")
        app.typeText("Salut")
        XCTAssertTrue(send.isEnabled)
    }

    // MARK: - Actions (menu contextuel, sans VoiceOver ; les mêmes actions sont proposées en
    // actions personnalisées sous VoiceOver)

    /// Appui long sur un message, puis une action du menu.
    @MainActor
    private func chooseInMenu(_ app: XCUIApplication, message: String, action: String) {
        let bubble = element(app, message)
        XCTAssertTrue(bubble.waitForExistence(timeout: 5), "Message « \(message) » absent")
        bubble.press(forDuration: 1.2)
        let button = app.buttons[action]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Action « \(action) » absente du menu")
        button.tap()
    }

    /// Répondre : bandeau au-dessus du champ, champ renommé ; « Annuler la réponse » revient
    /// au champ normal. Écran audité pendant la réponse.
    @MainActor
    func testReplyFromContextMenu() throws {
        let app = openMarie()
        chooseInMenu(app, message: Self.firstUnread, action: "Répondre")

        let field = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Réponse à Marie Dupont"))
            .firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Le champ doit rappeler la réponse")
        let cancel = app.buttons["Annuler la réponse"]
        XCTAssertTrue(cancel.exists)
        try AccessibilityAudit.run(app)

        cancel.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertFalse(cancel.exists)
    }

    /// Supprimer demande confirmation ; « Annuler » ferme l'alerte sans rien supprimer.
    @MainActor
    func testDeletingAMessageAsksForConfirmation() throws {
        let app = openMarie()
        let mine = "Vous, Pas encore, je regarde ce soir., 18 h 45, lu"
        chooseInMenu(app, message: mine, action: "Supprimer")

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Alerte de confirmation absente")
        XCTAssertTrue(alert.staticTexts["Supprimer ce message ?"].exists)
        XCTAssertTrue(alert.buttons["Supprimer pour moi"].exists)
        XCTAssertTrue(alert.buttons["Supprimer aussi pour Marie Dupont"].exists)
        alert.buttons["Annuler"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertTrue(element(app, mine).exists, "Le message doit rester après Annuler")
    }
}
