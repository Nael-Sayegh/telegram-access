import Foundation

enum PhoneNumberFormatter {
    /// Pays dont le 0 initial fait partie du numéro international (Italie, Saint-Marin, Vatican).
    private static let keepsLeadingZero: Set<String> = ["39", "378", "379"]

    /// Construit le numéro international à partir de l'indicatif et de la saisie.
    /// Une saisie commençant par « + » ou « 00 » est considérée comme déjà internationale.
    static func international(callingCode: String, input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let allDigits = Self.digits(in: trimmed)

        if trimmed.hasPrefix("+") || trimmed.hasPrefix("＋") {
            return "+" + allDigits
        }
        if allDigits.hasPrefix("00") {
            return "+" + String(allDigits.dropFirst(2))
        }

        var national = Substring(allDigits)
        if !keepsLeadingZero.contains(callingCode) {
            while national.hasPrefix("0") { national = national.dropFirst() }
        }
        return "+" + callingCode + String(national)
    }

    /// Chiffres décimaux de la saisie, convertis en chiffres ASCII (0 à 9).
    /// Les chiffres d'autres écritures (arabe, persan, pleine chasse…) sont convertis ;
    /// « ½ », « ² » ou les chiffres romains sont ignorés.
    static func digits(in text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            guard scalar.properties.numericType == .decimal,
                  let value = scalar.properties.numericValue
            else { continue }
            result += String(Int(value))
        }
        return result
    }
}
