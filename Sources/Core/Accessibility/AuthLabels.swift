import Foundation

/// Textes destinés à VoiceOver pour les écrans de connexion. Fonctions pures, testées unitairement.
enum AuthLabels {
    /// « France, plus 33 »
    static func country(name: String, callingCode: String) -> String {
        "\(name), plus \(callingCode)"
    }

    /// Numéro lu chiffre par chiffre : « plus 3 3 6 1 2 … » plutôt qu'un grand nombre.
    static func spokenPhoneNumber(_ number: String) -> String {
        let digits = number.filter(\.isNumber)
        let spaced = digits.map(String.init).joined(separator: " ")
        return number.hasPrefix("+") ? "plus \(spaced)" : spaced
    }

    /// Phrase expliquant où le code a été envoyé.
    static func codeSent(_ info: CodeInfo) -> String {
        let length = info.codeLength.map { " de \($0) chiffres" } ?? ""
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
            let total = info.codeLength.map { " Saisissez les \($0) derniers chiffres du numéro appelant." } ?? ""
            return "Vous allez recevoir un appel manqué d'un numéro commençant par \(spokenPhoneNumber(prefix)).\(total)"
        case .fragment:
            return "Un code\(length) a été envoyé sur fragment.com."
        case .firebase:
            return "Un code\(length) a été envoyé."
        }
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
}
