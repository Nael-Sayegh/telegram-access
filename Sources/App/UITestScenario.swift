#if DEBUG
import Foundation

/// Écrans de connexion affichés sans TDLib ni réseau, pour les audits d'accessibilité des
/// tests UI. Activé par l'argument de lancement `-uiTestAuthStep <étape>`.
/// Compilé uniquement en Debug : absent des builds distribués.
enum UITestScenario: String, CaseIterable {
    case phoneNumber
    case code
    case emailAddress
    case emailCode
    case password
    case registration
    case ready

    static let launchArgument = "-uiTestAuthStep"

    /// Configuration factice : le service de test n'utilise ni `api_id` ni `api_hash`.
    static let config = AppConfig(apiId: 1, apiHash: "ui-tests", applicationVersion: "0")

    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> UITestScenario? {
        guard let index = arguments.firstIndex(of: launchArgument), arguments.indices.contains(index + 1) else {
            return nil
        }
        return UITestScenario(rawValue: arguments[index + 1])
    }

    var step: AuthStep {
        switch self {
        case .phoneNumber:
            return .phoneNumber
        case .code:
            return .code(CodeInfo(
                phoneNumber: "+33612345678",
                delivery: .telegramApp,
                codeLength: 5,
                nextDelivery: .sms,
                resendTimeout: 60
            ))
        case .emailAddress:
            return .emailAddress
        case .emailCode:
            return .emailCode(pattern: "a***@exemple.fr", length: 6)
        case .password:
            return .password(PasswordInfo(hint: "Indice de test", hasRecoveryEmail: true, recoveryEmailPattern: ""))
        case .registration:
            return .registration(RegistrationTerms(
                text: "Premier paragraphe des conditions.\nDeuxième paragraphe des conditions.",
                minimumAge: 16,
                requiresExplicitAcceptance: false
            ))
        case .ready:
            return .ready
        }
    }
}

/// Service factice : envoie l'étape demandée et accepte toutes les actions, sans réseau.
actor UITestAuthService: AuthService {
    nonisolated let steps: AsyncStream<AuthStep>
    private let continuation: AsyncStream<AuthStep>.Continuation
    private let scenario: UITestScenario

    init(scenario: UITestScenario) {
        let stream = AsyncStream.makeStream(of: AuthStep.self)
        self.steps = stream.stream
        self.continuation = stream.continuation
        self.scenario = scenario
    }

    func start() {
        continuation.yield(scenario.step)
    }

    func retryInitialization() {}
    func setPhoneNumber(_ phoneNumber: String) {}
    func resendCode() {}
    func checkCode(_ code: String) {}
    func setEmailAddress(_ email: String) {}
    func checkEmailCode(_ code: String) {}
    func checkPassword(_ password: String) {}
    func requestPasswordRecovery() {}
    func recoverPassword(code: String, newPassword: String, newHint: String) {}
    func register(firstName: String, lastName: String) {}
    func logOut() {}

    func countries() -> [Country] {
        [
            Country(id: "BE", name: "Belgique", callingCode: "32", flag: "🇧🇪"),
            Country(id: "FR", name: "France", callingCode: "33", flag: "🇫🇷"),
            Country(id: "CH", name: "Suisse", callingCode: "41", flag: "🇨🇭"),
        ]
    }

    func estimatedCountryCode() -> String {
        "FR"
    }
}
#endif
