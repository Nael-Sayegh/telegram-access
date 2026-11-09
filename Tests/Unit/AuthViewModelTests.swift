import XCTest
@testable import TelegramAccess

/// Service de connexion factice : enregistre les appels et peut simuler une erreur Telegram.
actor FakeAuthService: AuthService {
    nonisolated let steps: AsyncStream<AuthStep>
    private let continuation: AsyncStream<AuthStep>.Continuation

    private(set) var phoneNumbers: [String] = []
    private(set) var registrations: [String] = []
    private(set) var recoveries: [String] = []
    private(set) var recoveryRequests = 0
    private(set) var retryCount = 0
    private var nextError: TelegramError?

    init() {
        let stream = AsyncStream.makeStream(of: AuthStep.self)
        steps = stream.stream
        continuation = stream.continuation
    }

    /// Simule un nouvel état reçu de TDLib.
    nonisolated func send(_ step: AuthStep) {
        continuation.yield(step)
    }

    func failNextCall(with error: TelegramError) {
        nextError = error
    }

    func start() {}

    func retryInitialization() {
        retryCount += 1
    }

    func setPhoneNumber(_ phoneNumber: String) throws {
        try throwIfNeeded()
        phoneNumbers.append(phoneNumber)
    }

    func resendCode() throws { try throwIfNeeded() }
    func checkCode(_ code: String) throws { try throwIfNeeded() }
    func setEmailAddress(_ email: String) throws { try throwIfNeeded() }
    func checkEmailCode(_ code: String) throws { try throwIfNeeded() }
    func checkPassword(_ password: String) throws { try throwIfNeeded() }

    func requestPasswordRecovery() throws {
        try throwIfNeeded()
        recoveryRequests += 1
    }

    func recoverPassword(code: String, newPassword: String, newHint: String) throws {
        try throwIfNeeded()
        recoveries.append("\(code)|\(newPassword)|\(newHint)")
    }

    func register(firstName: String, lastName: String) throws {
        try throwIfNeeded()
        registrations.append("\(firstName)|\(lastName)")
    }

    func logOut() throws { try throwIfNeeded() }
    func countries() -> [Country] { [] }
    func estimatedCountryCode() -> String { "FR" }

    private func throwIfNeeded() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }
}

@MainActor
final class AuthViewModelTests: XCTestCase {
    private let config = AppConfig(apiId: 1, apiHash: "test", applicationVersion: "1")
    private let france = Country(id: "FR", name: "France", callingCode: "33", flag: "🇫🇷")

    private var services: [FakeAuthService] = []

    /// Modèle démarré sur un service factice ; chaque (re)création de client en ajoute un à `services`.
    private func makeModel() -> AuthViewModel {
        let model = AuthViewModel(config: config) { [unowned self] _ in
            let service = FakeAuthService()
            self.services.append(service)
            return service
        }
        model.start()
        return model
    }

    private var service: FakeAuthService { services[0] }

    /// Attend qu'une condition devienne vraie (les actions du modèle sont asynchrones).
    private func waitUntil(
        _ condition: @MainActor () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition non remplie à temps", file: file, line: line)
    }

    func testStepsFromServiceAreShown() async {
        let model = makeModel()
        service.send(.phoneNumber)
        await waitUntil { model.step == .phoneNumber }
    }

    func testMissingConfigurationIsReported() {
        let model = AuthViewModel(config: nil)
        XCTAssertEqual(model.step, .configurationMissing)
    }

    func testPhoneNumberRequiresCountryAndTargetsCountryButton() {
        let model = makeModel()
        model.submitPhoneNumber("06 12 34 56 78")
        XCTAssertEqual(model.errorField, .country)
        XCTAssertEqual(model.errorMessage, "Choisissez d'abord votre pays.")
        XCTAssertEqual(model.errorCount, 1)
    }

    func testPhoneNumberRequiresDigits() {
        let model = makeModel()
        model.selectedCountry = france
        model.submitPhoneNumber("abc")
        XCTAssertEqual(model.errorField, .phoneNumber)
    }

    func testPhoneNumberIsSentInInternationalFormat() async {
        let model = makeModel()
        model.selectedCountry = france
        model.submitPhoneNumber("06 12 34 56 78")
        await waitUntil { await self.service.phoneNumbers == ["+33612345678"] }
        await waitUntil { !model.isBusy }
        XCTAssertNil(model.errorMessage)
    }

    func testTelegramErrorTargetsTheRightField() async {
        let model = makeModel()
        await service.failNextCall(with: TelegramError(code: 400, message: "LASTNAME_INVALID"))
        model.register(firstName: "Marie", lastName: "@@@")
        await waitUntil { model.errorField == .lastName }
        XCTAssertEqual(model.errorMessage, "Nom invalide.")
    }

    func testRegistrationTrimsNames() async {
        let model = makeModel()
        model.register(firstName: "  Marie ", lastName: " Dupont ")
        await waitUntil { await self.service.registrations == ["Marie|Dupont"] }
    }

    func testRegistrationRequiresFirstName() {
        let model = makeModel()
        model.register(firstName: "  ", lastName: "Dupont")
        XCTAssertEqual(model.errorField, .firstName)
    }

    func testEditingPhoneNumberIgnoresPendingCodeStep() async throws {
        let model = makeModel()
        let info = CodeInfo(phoneNumber: "+33612345678", delivery: .sms, codeLength: 5, nextDelivery: nil, resendTimeout: 0)
        service.send(.code(info))
        await waitUntil { model.step == .code(info) }

        model.editPhoneNumber()
        XCTAssertEqual(model.step, .phoneNumber)

        // TDLib est toujours en attente du code : l'écran du numéro doit rester affiché.
        service.send(.code(info))
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(model.step, .phoneNumber)
    }

    func testResendBeforeDelayIsRefusedWithRemainingTime() async {
        let model = makeModel()
        let info = CodeInfo(phoneNumber: "+33612345678", delivery: .telegramApp, codeLength: 5, nextDelivery: .sms, resendTimeout: 120)
        service.send(.code(info))
        await waitUntil { model.step == .code(info) }

        model.resendCode()
        XCTAssertEqual(model.errorField, .code)
        XCTAssertTrue(model.errorMessage?.hasPrefix("Nouveau code disponible dans") == true)
    }

    func testRetryReusesTheSameClient() async {
        let model = makeModel()
        service.send(.failed("Impossible d'initialiser la base locale chiffrée."))
        await waitUntil { if case .failed = model.step { return true } else { return false } }

        model.retry()
        await waitUntil { await self.service.retryCount == 1 }
        XCTAssertEqual(services.count, 1)
        XCTAssertEqual(model.step, .starting)
    }

    func testClosedClientIsReplaced() async {
        let model = makeModel()
        service.send(.ready)
        await waitUntil { model.step == .ready }

        service.send(.closed)
        await waitUntil { self.services.count == 2 }
        XCTAssertEqual(model.step, .starting)

        // Les états de l'ancien client sont ignorés.
        services[0].send(.ready)
        services[1].send(.phoneNumber)
        await waitUntil { model.step == .phoneNumber }
    }

    func testForgotPasswordOpensRecovery() async {
        let model = makeModel()
        service.send(.password(PasswordInfo(hint: "", hasRecoveryEmail: true, recoveryEmailPattern: "")))
        await waitUntil { if case .password = model.step { return true } else { return false } }

        model.forgotPassword()
        await waitUntil { model.isRecoveringPassword }
        let requests = await service.recoveryRequests
        XCTAssertEqual(requests, 1)

        model.cancelPasswordRecovery()
        XCTAssertFalse(model.isRecoveringPassword)
    }

    func testRecoveryRequiresMatchingPasswords() {
        let model = makeModel()
        model.recoverPassword(code: "123456", newPassword: "secret-1", confirmation: "secret-2", hint: "")
        XCTAssertEqual(model.errorField, .newPassword)
    }

    func testRecoveryRequiresNewPassword() {
        let model = makeModel()
        model.recoverPassword(code: "123456", newPassword: "", confirmation: "", hint: "")
        XCTAssertEqual(model.errorField, .newPassword)
    }

    func testRecoveryHintMustNotRevealPassword() {
        let model = makeModel()
        model.recoverPassword(code: "123456", newPassword: "Soleil42", confirmation: "Soleil42", hint: "c'est soleil42")
        XCTAssertEqual(model.errorField, .passwordHint)
    }

    func testRecoverySendsCodeAndNewPassword() async {
        let model = makeModel()
        model.recoverPassword(code: " 123456 ", newPassword: "Soleil42", confirmation: "Soleil42", hint: " astre ")
        await waitUntil { await self.service.recoveries == ["123456|Soleil42|astre"] }
    }
}
