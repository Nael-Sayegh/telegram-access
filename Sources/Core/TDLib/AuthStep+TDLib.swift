import Foundation
@preconcurrency import TDLibKit

extension AuthStep {
    init(_ state: AuthorizationState) {
        switch state {
        case .authorizationStateWaitTdlibParameters:
            self = .starting
        case .authorizationStateWaitPhoneNumber:
            self = .phoneNumber
        case .authorizationStateWaitPremiumPurchase:
            self = .unsupported("Telegram demande un achat Premium pour connecter ce numéro, ce que cette application ne gère pas.")
        case .authorizationStateWaitEmailAddress:
            self = .emailAddress
        case .authorizationStateWaitEmailCode(let value):
            self = .emailCode(pattern: value.codeInfo.emailAddressPattern, length: value.codeInfo.length)
        case .authorizationStateWaitCode(let value):
            self = .code(CodeInfo(value.codeInfo))
        case .authorizationStateWaitOtherDeviceConfirmation:
            self = .unsupported("La connexion par QR code n'est pas prise en charge.")
        case .authorizationStateWaitRegistration:
            self = .registration
        case .authorizationStateWaitPassword(let value):
            self = .password(hint: value.passwordHint, hasRecoveryEmail: value.hasRecoveryEmailAddress)
        case .authorizationStateReady:
            self = .ready
        case .authorizationStateLoggingOut, .authorizationStateClosing:
            // Attendre `closed` avant de recréer un client sur le même dossier.
            self = .loggingOut
        case .authorizationStateClosed:
            self = .closed
        }
    }
}

extension CodeInfo {
    init(_ info: AuthenticationCodeInfo) {
        let current = Self.delivery(for: info.type)
        self.init(
            phoneNumber: info.phoneNumber,
            delivery: current.delivery,
            codeLength: current.length,
            nextDelivery: info.nextType.map { Self.delivery(for: $0).delivery },
            resendTimeout: info.timeout
        )
    }

    private static func delivery(for type: AuthenticationCodeType) -> (delivery: CodeDelivery, length: Int?) {
        switch type {
        case .authenticationCodeTypeTelegramMessage(let value):
            return (.telegramApp, value.length)
        case .authenticationCodeTypeSms(let value):
            return (.sms, value.length)
        case .authenticationCodeTypeSmsWord(let value):
            return (.smsWord(firstLetter: value.firstLetter), nil)
        case .authenticationCodeTypeSmsPhrase(let value):
            return (.smsPhrase(firstWord: value.firstWord), nil)
        case .authenticationCodeTypeCall(let value):
            return (.call, value.length)
        case .authenticationCodeTypeFlashCall:
            return (.flashCall, nil)
        case .authenticationCodeTypeMissedCall(let value):
            return (.missedCall(phoneNumberPrefix: value.phoneNumberPrefix), value.length)
        case .authenticationCodeTypeFragment(let value):
            return (.fragment, value.length)
        case .authenticationCodeTypeFirebaseAndroid(let value):
            return (.firebase, value.length)
        case .authenticationCodeTypeFirebaseIos(let value):
            return (.firebase, value.length)
        }
    }
}
