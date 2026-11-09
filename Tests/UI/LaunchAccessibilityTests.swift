import XCTest

/// Audits automatiques (libellés, contraste, tailles de cibles, Dynamic Type) de chaque écran
/// de connexion, affiché par un service factice (argument `-uiTestAuthStep`, builds Debug).
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
        try runAudit(app)
    }

    /// Lance l'audit et signale tous les problèmes d'un coup (au lieu de s'arrêter au premier),
    /// avec le libellé de l'élément concerné.
    ///
    /// Ignoré : « Dynamic Type font sizes are partially unsupported » sur des textes et boutons
    /// SwiftUI qui utilisent tous les styles de texte système. L'audit agrandit la police, et dans
    /// un `Form` les lignes qui sortent alors de l'écran ne sont plus mesurables : faux positif
    /// connu, qui ne touche que les écrans assez longs. Le cas « unsupported » (police fixe)
    /// reste vérifié.
    @MainActor
    private func runAudit(_ app: XCUIApplication) throws {
        var problems: [String] = []
        try app.performAccessibilityAudit { issue in
            let element = issue.element.map { "« \($0.label) »" } ?? "élément inconnu"
            let line = "\(issue.compactDescription) — \(element) — \(issue.detailedDescription)"
            if issue.auditType == .dynamicType,
               issue.compactDescription == "Dynamic Type font sizes are partially unsupported" {
                print("Audit ignoré : \(line)")
                return true
            }
            problems.append(line)
            return true
        }
        if !problems.isEmpty {
            XCTFail("Problèmes d'accessibilité :\n" + problems.joined(separator: "\n"))
        }
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
        try runAudit(app)
    }

    @MainActor
    func testRegistrationScreen() throws {
        try audit("registration", title: "Inscription")
    }

    @MainActor
    func testHomeScreen() throws {
        try audit("ready", title: "Discussions")
    }

    /// Une erreur de saisie est ajoutée au libellé du champ concerné.
    @MainActor
    func testPhoneNumberErrorIsInFieldLabel() throws {
        let app = launch("phoneNumber")
        // Pays estimé chargé (France) : l'erreur portera sur le numéro, pas sur le pays.
        let country = app.buttons["Pays"]
        XCTAssertTrue(country.waitForExistence(timeout: 15))
        let franceSelected = NSPredicate(format: "value == %@", "France, plus 33")
        wait(for: [XCTNSPredicateExpectation(predicate: franceSelected, object: country)], timeout: 5)

        app.buttons["Recevoir le code"].tap()

        let field = app.textFields["Numéro de téléphone. Erreur : Saisissez votre numéro de téléphone."]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
    }
}
