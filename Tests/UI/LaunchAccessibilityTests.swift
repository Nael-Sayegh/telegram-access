import XCTest

/// Audits automatiques (libellés, contraste, tailles de cibles, Dynamic Type) de chaque écran
/// de connexion, affiché par un service factice (argument `-uiTestAuthStep`, builds Debug).
/// La liste des conversations est contrôlée par `ChatListAccessibilityTests`.
/// Ne remplacent pas un test manuel avec VoiceOver.
final class LaunchAccessibilityTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ step: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestAuthStep", step]
        app.launch()
        return app
    }

    @MainActor
    private func audit(_ step: String, title: String) throws {
        let app = launch(step)
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 15), "Écran « \(title) » absent")
        try AccessibilityAudit.run(app)
    }

    @MainActor
    func testPhoneNumberScreen() throws {
        try audit("phoneNumber", title: "Connexion")
    }

    @MainActor
    func testCodeScreen() throws {
        try audit("code", title: "Code de connexion")
    }

    @MainActor
    func testEmailAddressScreen() throws {
        try audit("emailAddress", title: "Adresse e-mail")
    }

    @MainActor
    func testEmailCodeScreen() throws {
        try audit("emailCode", title: "Code e-mail")
    }

    @MainActor
    func testPasswordScreen() throws {
        try audit("password", title: "Mot de passe")
    }

    @MainActor
    func testPasswordRecoveryScreen() throws {
        let app = launch("password")
        XCTAssertTrue(app.navigationBars["Mot de passe"].waitForExistence(timeout: 15))
        app.buttons["Mot de passe oublié"].tap()
        XCTAssertTrue(app.navigationBars["Récupération"].waitForExistence(timeout: 5))
        try AccessibilityAudit.run(app)
    }

    @MainActor
    func testRegistrationScreen() throws {
        try audit("registration", title: "Inscription")
    }

    /// Une erreur de saisie est ajoutée au libellé du champ concerné.
    @MainActor
    func testPhoneNumberErrorIsInFieldLabel() throws {
        let app = launch("phoneNumber")
        // Pays estimé chargé (France) : l'erreur portera sur le numéro, pas sur le pays.
        let country = app.buttons["Pays"]
        XCTAssertTrue(country.waitForExistence(timeout: 15))
        let franceSelected = NSPredicate(format: "value == %@", "France, plus 33")
        // 15 s : sur une machine CI chargée, le chargement des pays a déjà dépassé 5 s.
        wait(for: [XCTNSPredicateExpectation(predicate: franceSelected, object: country)], timeout: 15)

        app.buttons["Recevoir le code"].tap()

        let field = app.textFields["Numéro de téléphone. Erreur : Saisissez votre numéro de téléphone."]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
    }
}
