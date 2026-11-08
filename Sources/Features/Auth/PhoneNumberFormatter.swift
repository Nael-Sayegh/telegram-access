import Foundation

enum PhoneNumberFormatter {
    /// Pays dont le 0 initial fait partie du numéro international (Italie, Saint-Marin, Vatican).
    private static let keepsLeadingZero: Set<String> = ["39", "378", "379"]

    /// Construit le numéro international à partir de l'indicatif et de la saisie.
    /// Une saisie commençant par « + » ou « 00 » est considérée comme déjà internationale.
    static func international(callingCode: String, input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)

        if trimmed.hasPrefix("+") {
            return "+" + digits
        }
        if digits.hasPrefix("00") {
            return "+" + String(digits.dropFirst(2))
        }

        var national = Substring(digits)
        if !keepsLeadingZero.contains(callingCode) {
            while national.hasPrefix("0") { national = national.dropFirst() }
        }
        return "+" + callingCode + String(national)
    }
}
