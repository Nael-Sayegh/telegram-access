import XCTest
@testable import TelegramAccess

final class PhoneNumberFormatterTests: XCTestCase {
    func testFrenchNationalNumberDropsLeadingZero() {
        XCTAssertEqual(PhoneNumberFormatter.international(callingCode: "33", input: "06 12 34 56 78"), "+33612345678")
    }

    func testNumberWithoutLeadingZero() {
        XCTAssertEqual(PhoneNumberFormatter.international(callingCode: "33", input: "612345678"), "+33612345678")
    }

    func testItalyKeepsLeadingZero() {
        XCTAssertEqual(PhoneNumberFormatter.international(callingCode: "39", input: "06 1234567"), "+39061234567")
    }

    func testInternationalInputIsKeptAsIs() {
        XCTAssertEqual(PhoneNumberFormatter.international(callingCode: "33", input: "+44 7700 900123"), "+447700900123")
        XCTAssertEqual(PhoneNumberFormatter.international(callingCode: "33", input: "0044 7700 900123"), "+447700900123")
    }

    func testSeparatorsAreIgnored() {
        XCTAssertEqual(PhoneNumberFormatter.international(callingCode: "1", input: "(555) 010-9999"), "+15550109999")
    }
}
