import XCTest

/// Audits automatiques (libellés, contraste, tailles de cibles, Dynamic Type).
/// Ne remplacent pas un test manuel avec VoiceOver.
final class LaunchAccessibilityTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstScreenPassesAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15))
        try app.performAccessibilityAudit()
    }
}
