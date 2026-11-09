import Foundation

/// Traduit les erreurs Telegram en phrases compréhensibles.
enum AuthErrorText {
    static func message(for error: Error) -> String {
        guard let telegram = error as? TelegramError else {
            return "Une erreur est survenue. Vérifiez votre connexion et réessayez."
        }
        return message(code: telegram.code, text: telegram.message)
    }

    /// Champ concerné par une erreur Telegram quand il diffère du champ principal de l'écran
    /// (ex. le nom refusé sur l'écran d'inscription, dont le champ principal est le prénom).
    static func field(for error: Error) -> AuthField? {
        guard let telegram = error as? TelegramError else { return nil }
        switch telegram.message {
        case "FIRSTNAME_INVALID": return .firstName
        case "LASTNAME_INVALID": return .lastName
        default: return nil
        }
    }

    static func message(code: Int, text: String) -> String {
        if code == 429 || text.hasPrefix("FLOOD_WAIT") || text.contains("Too Many Requests") {
            if let seconds = retryDelay(in: text) {
                return "Trop de tentatives. Réessayez dans \(AuthLabels.duration(seconds))."
            }
            return "Trop de tentatives. Réessayez plus tard."
        }

        switch text {
        case "PHONE_NUMBER_INVALID":
            return "Numéro de téléphone invalide. Vérifiez le pays et le numéro."
        case "PHONE_NUMBER_BANNED":
            return "Ce numéro est banni de Telegram."
        case "PHONE_NUMBER_FLOOD":
            return "Trop de demandes de code pour ce numéro. Réessayez plus tard."
        case "PHONE_CODE_INVALID", "CODE_INVALID":
            return "Code incorrect."
        case "PHONE_CODE_EXPIRED":
            return "Ce code a expiré. Demandez-en un nouveau."
        case "PHONE_CODE_EMPTY", "CODE_EMPTY":
            return "Saisissez le code reçu."
        case "PASSWORD_HASH_INVALID":
            return "Mot de passe incorrect."
        case "PASSWORD_RECOVERY_NA":
            return "Aucune adresse e-mail de récupération n'est configurée pour ce compte."
        case "PASSWORD_RECOVERY_EXPIRED":
            return "Le code de récupération a expiré. Demandez-en un nouveau."
        case "NEW_SETTINGS_INVALID":
            return "Le nouveau mot de passe ou son indice a été refusé."
        case "EMAIL_INVALID":
            return "Adresse e-mail invalide."
        case "EMAIL_CODE_INVALID":
            return "Code reçu par e-mail incorrect."
        case "FIRSTNAME_INVALID":
            return "Prénom invalide."
        case "LASTNAME_INVALID":
            return "Nom invalide."
        case "SEND_CODE_UNAVAILABLE":
            return "Aucun autre moyen d'envoi du code n'est disponible."
        default:
            return "Erreur Telegram : \(text)"
        }
    }

    /// Extrait le délai d'attente de « FLOOD_WAIT_120 » ou « Too Many Requests: retry after 120 ».
    static func retryDelay(in text: String) -> Int? {
        let digits = text.reversed().prefix(while: \.isASCIIDigit)
        guard !digits.isEmpty else { return nil }
        return Int(String(digits.reversed()))
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
