import XCTest
@testable import TelegramAccess

final class AuthErrorTextTests: XCTestCase {
    func testKnownErrors() {
        XCTAssertEqual(AuthErrorText.message(code: 400, text: "PHONE_CODE_INVALID"), "Code incorrect.")
        XCTAssertEqual(AuthErrorText.message(code: 400, text: "PASSWORD_HASH_INVALID"), "Mot de passe incorrect.")
    }

    func testFloodWaitWithDelay() {
        XCTAssertEqual(
            AuthErrorText.message(code: 429, text: "Too Many Requests: retry after 125"),
            "Trop de tentatives. Réessayez dans 2 minutes 5 secondes."
        )
        XCTAssertEqual(
            AuthErrorText.message(code: 420, text: "FLOOD_WAIT_30"),
            "Trop de tentatives. Réessayez dans 30 secondes."
        )
    }

    func testUnknownErrorKeepsTelegramText() {
        XCTAssertEqual(AuthErrorText.message(code: 400, text: "SOMETHING_NEW"), "Erreur Telegram : SOMETHING_NEW")
    }

    func testNonTelegramError() {
        struct Other: Error {}
        XCTAssertEqual(
            AuthErrorText.message(for: Other()),
            "Une erreur est survenue. Vérifiez votre connexion et réessayez."
        )
    }

    func testRetryDelayExtraction() {
        XCTAssertEqual(AuthErrorText.retryDelay(in: "FLOOD_WAIT_120"), 120)
        XCTAssertNil(AuthErrorText.retryDelay(in: "PHONE_NUMBER_FLOOD"))
    }

    func testPasswordRecoveryErrors() {
        XCTAssertEqual(
            AuthErrorText.message(code: 400, text: "PASSWORD_RECOVERY_NA"),
            "Aucune adresse e-mail de récupération n'est configurée pour ce compte."
        )
        XCTAssertEqual(
            AuthErrorText.message(code: 400, text: "PASSWORD_RECOVERY_EXPIRED"),
            "Le code de récupération a expiré. Demandez-en un nouveau."
        )
    }

    func testErrorFieldForNames() {
        XCTAssertEqual(AuthErrorText.field(for: TelegramError(code: 400, message: "LASTNAME_INVALID")), .lastName)
        XCTAssertEqual(AuthErrorText.field(for: TelegramError(code: 400, message: "FIRSTNAME_INVALID")), .firstName)
        XCTAssertNil(AuthErrorText.field(for: TelegramError(code: 400, message: "PHONE_CODE_INVALID")))
    }
}
