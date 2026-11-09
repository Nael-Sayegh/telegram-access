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

/// Étape « mot de passe » de la validation en deux étapes.
struct PasswordInfo: Equatable {
    var hint: String
    /// Vrai si une adresse e-mail de récupération est configurée (« Mot de passe oublié » possible).
    var hasRecoveryEmail: Bool
    /// Adresse masquée où le code de récupération a été envoyé ; vide tant qu'aucun code n'a été demandé.
    var recoveryEmailPattern: String
}

/// Conditions d'utilisation de Telegram, à présenter avant la création d'un compte.
struct RegistrationTerms: Equatable {
    var text: String
    /// Âge minimum pour accepter les conditions ; 0 si aucune restriction.
    var minimumAge: Int
    /// Vrai si Telegram exige une acceptation explicite (fenêtre bloquante).
    var requiresExplicitAcceptance: Bool
}

/// Étape courante de la connexion, telle que présentée à l'interface.
enum AuthStep: Equatable {
    case starting
    case configurationMissing
    case failed(String)
    case phoneNumber
    case code(CodeInfo)
    case emailAddress
    /// `length` vaut `nil` si la longueur du code est inconnue.
    case emailCode(pattern: String, length: Int?)
    case password(PasswordInfo)
    case registration(RegistrationTerms)
    /// Étape TDLib non prise en charge (QR code, achat Premium…).
    case unsupported(String)
    case ready
    case loggingOut
    case closed
}

/// Élément d'un écran de connexion auquel se rapporte une erreur : il reçoit le focus
/// et l'erreur est ajoutée à son libellé VoiceOver.
enum AuthField: Equatable {
    case country
    case phoneNumber
    case code
    case emailAddress
    case emailCode
    case password
    case recoveryCode
    case newPassword
    case passwordHint
    case firstName
    case lastName
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
