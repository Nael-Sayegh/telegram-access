import XCTest
@testable import TelegramAccess

final class AuthLabelsTests: XCTestCase {
    func testCountryLabel() {
        XCTAssertEqual(AuthLabels.country(name: "France", callingCode: "33"), "France, plus 33")
    }

    func testSpokenPhoneNumberReadsDigitByDigit() {
        XCTAssertEqual(AuthLabels.spokenPhoneNumber("+33 6 12"), "plus 3 3 6 1 2")
        XCTAssertEqual(AuthLabels.spokenPhoneNumber("0612"), "0 6 1 2")
    }

    func testCodeSentInTelegramApp() {
        let info = CodeInfo(phoneNumber: "+33612345678", delivery: .telegramApp, codeLength: 5, nextDelivery: .sms, resendTimeout: 60)
        XCTAssertEqual(
            AuthLabels.codeSent(info),
            "Un code de 5 chiffres a été envoyé dans l'application Telegram, sur un autre de vos appareils connectés."
        )
    }

    func testCodeSentBySms() {
        let info = CodeInfo(phoneNumber: "+3361", delivery: .sms, codeLength: 6, nextDelivery: nil, resendTimeout: 0)
        XCTAssertEqual(AuthLabels.codeSent(info), "Un code de 6 chiffres a été envoyé par SMS au plus 3 3 6 1.")
    }

    func testCodeSentWithoutLength() {
        let info = CodeInfo(phoneNumber: "+1", delivery: .call, codeLength: nil, nextDelivery: nil, resendTimeout: 0)
        XCTAssertEqual(AuthLabels.codeSent(info), "Vous allez recevoir un appel au plus 1 qui vous dictera un code.")
    }

    func testUnknownOrZeroLengthIsOmitted() {
        let info = CodeInfo(phoneNumber: "+3361", delivery: .sms, codeLength: 0, nextDelivery: nil, resendTimeout: 0)
        XCTAssertEqual(AuthLabels.codeSent(info), "Un code a été envoyé par SMS au plus 3 3 6 1.")
    }

    func testEmailCodeSent() {
        XCTAssertEqual(
            AuthLabels.emailCodeSent(pattern: "a***@exemple.fr", length: 6),
            "Un code de 6 chiffres a été envoyé à a***@exemple.fr."
        )
        XCTAssertEqual(
            AuthLabels.emailCodeSent(pattern: "a***@exemple.fr", length: nil),
            "Un code a été envoyé à a***@exemple.fr."
        )
        XCTAssertEqual(
            AuthLabels.emailCodeSent(pattern: "a***@exemple.fr", length: 0),
            "Un code a été envoyé à a***@exemple.fr."
        )
    }

    func testRecoveryCodeSent() {
        XCTAssertEqual(AuthLabels.recoveryCodeSent(pattern: "b***@exemple.fr"), "Un code de récupération a été envoyé à b***@exemple.fr.")
        XCTAssertEqual(
            AuthLabels.recoveryCodeSent(pattern: ""),
            "Un code de récupération a été envoyé à votre adresse e-mail de récupération."
        )
    }

    func testMinimumAge() {
        XCTAssertEqual(AuthLabels.minimumAge(16), "Vous devez avoir au moins 16 ans pour utiliser Telegram.")
        XCTAssertNil(AuthLabels.minimumAge(0))
    }

    func testResendButton() {
        XCTAssertEqual(AuthLabels.resendButton(.sms), "Recevoir le code par SMS")
        XCTAssertEqual(AuthLabels.resendButton(.call), "Recevoir le code par appel")
    }

    func testDuration() {
        XCTAssertEqual(AuthLabels.duration(0), "0 seconde")
        XCTAssertEqual(AuthLabels.duration(1), "1 seconde")
        XCTAssertEqual(AuthLabels.duration(45), "45 secondes")
        XCTAssertEqual(AuthLabels.duration(60), "1 minute")
        XCTAssertEqual(AuthLabels.duration(125), "2 minutes 5 secondes")
    }

    func testResendAvailability() {
        XCTAssertEqual(AuthLabels.resendAvailability(after: 0), "Vous pouvez demander un nouveau code.")
        XCTAssertEqual(
            AuthLabels.resendAvailability(after: 90),
            "Vous pourrez demander un nouveau code 1 minute 30 secondes après l'envoi du précédent."
        )
    }
}
