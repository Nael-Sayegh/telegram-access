import Foundation

// Types indépendants de TDLib : l'interface et les tests n'importent pas TDLibKit.

/// Moyen par lequel le code de connexion est (ou sera) transmis.
enum CodeDelivery: Equatable {
    case telegramApp
    case sms
    case smsWord(firstLetter: String)
    case smsPhrase(firstWord: String)
    case call
    case flashCall
    case missedCall(phoneNumberPrefix: String)
    case fragment
    case firebase
}

struct CodeInfo: Equatable {
    var phoneNumber: String
    var delivery: CodeDelivery
    /// Longueur attendue du code, si connue.
    var codeLength: Int?
    /// Moyen utilisé si l'on demande un nouveau code ; `nil` si aucun renvoi possible.
    var nextDelivery: CodeDelivery?
    /// Délai avant de pouvoir redemander un code, en secondes.
    var resendTimeout: Int
}

/// Étape courante de la connexion, telle que présentée à l'interface.
enum AuthStep: Equatable {
    case starting
    case configurationMissing
    case failed(String)
    case phoneNumber
    case code(CodeInfo)
    case emailAddress
    case emailCode(pattern: String, length: Int)
    case password(hint: String, hasRecoveryEmail: Bool)
    case registration
    /// Étape TDLib non prise en charge (QR code, achat Premium…).
    case unsupported(String)
    case ready
    case loggingOut
    case closed
}

/// Erreur renvoyée par Telegram, sans dépendance à TDLibKit.
struct TelegramError: Error, Equatable {
    let code: Int
    let message: String
}

struct Country: Identifiable, Equatable, Hashable {
    /// Code ISO 3166-1 alpha-2 (ex. « FR »).
    let id: String
    let name: String
    let callingCode: String
    let flag: String
}
