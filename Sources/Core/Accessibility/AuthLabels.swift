import Foundation

/// Textes destinés à VoiceOver pour les écrans de connexion. Fonctions pures, testées unitairement.
enum AuthLabels {
    /// « France, plus 33 »
    static func country(name: String, callingCode: String) -> String {
        "\(name), plus \(callingCode)"
    }

    /// Numéro lu chiffre par chiffre : « plus 3 3 6 1 2 … » plutôt qu'un grand nombre.
    static func spokenPhoneNumber(_ number: String) -> String {
        let digits = PhoneNumberFormatter.digits(in: number)
        let spaced = digits.map(String.init).joined(separator: " ")
        return number.hasPrefix("+") ? "plus \(spaced)" : spaced
    }

    /// Phrase expliquant où le code a été envoyé.
    static func codeSent(_ info: CodeInfo) -> String {
        let length = lengthText(info.codeLength)
        let number = spokenPhoneNumber(info.phoneNumber)
        switch info.delivery {
        case .telegramApp:
            return "Un code\(length) a été envoyé dans l'application Telegram, sur un autre de vos appareils connectés."
        case .sms:
            return "Un code\(length) a été envoyé par SMS au \(number)."
        case .smsWord(let firstLetter):
            return "Un mot commençant par la lettre \(firstLetter) a été envoyé par SMS au \(number)."
        case .smsPhrase(let firstWord):
            return "Une phrase commençant par « \(firstWord) » a été envoyée par SMS au \(number)."
        case .call:
            return "Vous allez recevoir un appel au \(number) qui vous dictera un code\(length)."
        case .flashCall:
            return "Vous allez recevoir un appel au \(number) qui raccrochera aussitôt."
        case .missedCall(let prefix):
            let total = info.codeLength.flatMap { $0 > 0 ? " Saisissez les \($0) derniers chiffres du numéro appelant." : nil } ?? ""
            return "Vous allez recevoir un appel manqué d'un numéro commençant par \(spokenPhoneNumber(prefix)).\(total)"
        case .fragment:
            return "Un code\(length) a été envoyé sur fragment.com."
        case .firebase:
            return "Un code\(length) a été envoyé."
        }
    }

    /// « Un code de 6 chiffres a été envoyé à a***@exemple.fr. » (longueur omise si inconnue).
    static func emailCodeSent(pattern: String, length: Int?) -> String {
        "Un code\(lengthText(length)) a été envoyé à \(pattern)."
    }

    /// Phrase expliquant où le code de récupération du mot de passe a été envoyé.
    static func recoveryCodeSent(pattern: String) -> String {
        pattern.isEmpty
            ? "Un code de récupération a été envoyé à votre adresse e-mail de récupération."
            : "Un code de récupération a été envoyé à \(pattern)."
    }

    /// « Vous devez avoir au moins 16 ans… », ou `nil` sans restriction d'âge.
    static func minimumAge(_ age: Int) -> String? {
        age > 0 ? "Vous devez avoir au moins \(age) ans pour utiliser Telegram." : nil
    }

    /// Libellé du bouton de renvoi (« Recevoir le code par SMS »).
    static func resendButton(_ next: CodeDelivery) -> String {
        switch next {
        case .sms, .smsWord, .smsPhrase: return "Recevoir le code par SMS"
        case .call, .flashCall, .missedCall: return "Recevoir le code par appel"
        case .telegramApp: return "Recevoir le code dans Telegram"
        case .fragment, .firebase: return "Recevoir un nouveau code"
        }
    }

    /// Indication donnée une seule fois, sans décompte, et qui reste vraie avec le temps.
    static func resendAvailability(after seconds: Int) -> String {
        seconds <= 0
            ? "Vous pouvez demander un nouveau code."
            : "Vous pourrez demander un nouveau code \(duration(seconds)) après l'envoi du précédent."
    }

    /// Durée en toutes lettres : « 45 secondes », « 1 minute », « 2 minutes 5 secondes ».
    static func duration(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let minutes = seconds / 60
        let rest = seconds % 60
        var parts: [String] = []
        if minutes > 0 { parts.append("\(minutes) minute\(minutes > 1 ? "s" : "")") }
        if rest > 0 || minutes == 0 { parts.append("\(rest) seconde\(rest > 1 ? "s" : "")") }
        return parts.joined(separator: " ")
    }

    /// « de 6 chiffres », ou rien si la longueur est inconnue (absente ou nulle).
    private static func lengthText(_ length: Int?) -> String {
        guard let length, length > 0 else { return "" }
        return " de \(length) chiffre\(length > 1 ? "s" : "")"
    }
}
