import Foundation

/// Opérations de connexion à Telegram.
///
/// `TelegramClient` en est l'implémentation réelle (TDLib). L'abstraction permet de tester
/// `AuthViewModel` et d'afficher les écrans de connexion sans réseau (tests UI).
protocol AuthService: AnyObject, Sendable {
    /// Étapes d'authentification, dans l'ordre reçu.
    var steps: AsyncStream<AuthStep> { get }

    func start() async
    /// Relance l'initialisation après un échec (`AuthStep.failed`), sans recréer de client.
    func retryInitialization() async

    func setPhoneNumber(_ phoneNumber: String) async throws
    func resendCode() async throws
    func checkCode(_ code: String) async throws
    func setEmailAddress(_ email: String) async throws
    func checkEmailCode(_ code: String) async throws
    func checkPassword(_ password: String) async throws
    /// Envoie un code de récupération à l'adresse e-mail de récupération.
    func requestPasswordRecovery() async throws
    /// Remplace le mot de passe oublié grâce au code de récupération.
    func recoverPassword(code: String, newPassword: String, newHint: String) async throws
    func register(firstName: String, lastName: String) async throws
    func logOut() async throws

    func countries() async throws -> [Country]
    /// Pays estimé par Telegram à partir de l'adresse IP (code ISO).
    func estimatedCountryCode() async throws -> String
}
