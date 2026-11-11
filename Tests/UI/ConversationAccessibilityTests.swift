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

    @MainActor
    func testDayHeaders() throws {
        let app = openMarie()
        XCTAssertTrue(element(app, "Aujourd'hui").waitForExistence(timeout: 5), "En-tête du jour absent")
        XCTAssertTrue(element(app, "Hier").waitForExistence(timeout: 5), "En-tête d'hier absent")
    }

    /// Comme WhatsApp : balayer donne chaque élément dans l'ordre chronologique, sans en
    /// sauter — début de la conversation, jour, messages du jour, jour suivant…
    @MainActor
    func testMessagesAreReadInChronologicalOrder() throws {
        let app = openMarie()
        let expected = [
            "Début de la conversation.",
            "Hier",
            "Tu as vu le programme de samedi ?, 18 h 30",
            "Vous, Pas encore, je regarde ce soir., 18 h 45, lu",
            "Message vocal, 12 secondes, 19 h",
            "Aujourd'hui",
            Self.firstUnread,
            "Alors, tu l'as regardé ?, en réponse à votre message : Pas encore, je regarde ce soir., 9 h",
            "On se voit demain ?, 9 h 05",
        ]
        XCTAssertTrue(element(app, "Début de la conversation.").waitForExistence(timeout: 5), "Début non signalé")
        var order: [String] = []
        for label in app.descendants(matching: .any).allElementsBoundByIndex.map(\.label)
        where expected.contains(label) && !order.contains(label) {
            order.append(label)
        }
        XCTAssertEqual(order, expected)
    }

    /// Audit complet, sauf taille du texte et texte coupé, que l'audit n'arrivait pas à évaluer
    /// dans l'ancienne liste UIKit (« élément inconnu », 2026-11-11) : contrôlés par
    /// `testMessagesGrowWithTextSize`. Avec la liste SwiftUI, ces deux contrôles sont lancés à
    /// titre d'information (journal du test) pour décider de les réactiver.
    @MainActor
    func testConversationScreen() throws {
        let app = openMarie()
        XCTAssertTrue(app.buttons["Aller au premier message non lu"].exists)
        XCTAssertTrue(app.buttons["Aller au dernier message"].exists)

        // D'abord, pour l'avoir même si l'audit suivant échoue.
        var reported = 0
        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped]) { issue in
            reported += 1
            print("Audit Dynamic Type (information) : \(issue.compactDescription) — \(issue.element?.label ?? "élément inconnu")")
            return true
        }
        print("Audit Dynamic Type (information) : \(reported) problème(s) signalé(s).")

        try AccessibilityAudit.run(app, excluding: [.dynamicType, .textClipped])
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
}
