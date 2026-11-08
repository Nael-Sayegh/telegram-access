import Foundation
@preconcurrency import TDLibKit

enum TDLibRuntime {
    /// Un seul gestionnaire par processus : `td_receive` n'est appelable que depuis un thread.
    static let manager = TDLibClientManager()
}

/// Enveloppe d'un client TDLib. Seul point de l'app qui importe TDLibKit pour l'authentification.
/// Un client fermé (`authorizationStateClosed`, après déconnexion) ne peut pas être réutilisé :
/// il faut en créer un nouveau.
actor TelegramClient {
    /// Étapes d'authentification, dans l'ordre reçu de TDLib.
    nonisolated let steps: AsyncStream<AuthStep>

    private let stepContinuation: AsyncStream<AuthStep>.Continuation
    private let rawStates: AsyncStream<AuthorizationState>
    private let client: TDLibClient
    private let config: AppConfig
    private var pumpTask: Task<Void, Never>?

    init(config: AppConfig, manager: TDLibClientManager = TDLibRuntime.manager) {
        self.config = config

        let stepStream = AsyncStream.makeStream(of: AuthStep.self)
        self.steps = stepStream.stream
        self.stepContinuation = stepStream.continuation

        let rawStream = AsyncStream.makeStream(of: AuthorizationState.self)
        self.rawStates = rawStream.stream
        let rawContinuation = rawStream.continuation

        self.client = manager.createClient { data, client in
            guard let update = try? client.decoder.decode(Update.self, from: data) else { return }
            if case .updateAuthorizationState(let value) = update {
                rawContinuation.yield(value.authorizationState)
                if case .authorizationStateClosed = value.authorizationState {
                    rawContinuation.finish()
                }
            }
        }
        Self.configureLogging(self.client)
    }

    /// Démarre le traitement des états d'authentification. Idempotent.
    func start() {
        guard pumpTask == nil else { return }
        pumpTask = Task {
            for await state in rawStates {
                await handle(state)
            }
            stepContinuation.finish()
        }
    }

    // MARK: - Authentification

    func setPhoneNumber(_ phoneNumber: String) async throws {
        _ = try await run { try await $0.setAuthenticationPhoneNumber(phoneNumber: phoneNumber, settings: nil) }
    }

    func resendCode() async throws {
        _ = try await run { try await $0.resendAuthenticationCode(reason: .resendCodeReasonUserRequest) }
    }

    func checkCode(_ code: String) async throws {
        _ = try await run { try await $0.checkAuthenticationCode(code: code) }
    }

    func setEmailAddress(_ email: String) async throws {
        _ = try await run { try await $0.setAuthenticationEmailAddress(emailAddress: email) }
    }

    func checkEmailCode(_ code: String) async throws {
        _ = try await run {
            try await $0.checkAuthenticationEmailCode(
                code: .emailAddressAuthenticationCode(EmailAddressAuthenticationCode(code: code))
            )
        }
    }

    func checkPassword(_ password: String) async throws {
        _ = try await run { try await $0.checkAuthenticationPassword(password: password) }
    }

    func register(firstName: String, lastName: String) async throws {
        _ = try await run {
            try await $0.registerUser(disableNotification: false, firstName: firstName, lastName: lastName)
        }
    }

    func logOut() async throws {
        _ = try await run { try await $0.logOut() }
    }

    // MARK: - Pays

    func countries() async throws -> [Country] {
        let result = try await run { try await $0.getCountries() }
        return result.countries
            .filter { !$0.isHidden && !$0.callingCodes.isEmpty }
            .map { Country(id: $0.countryCode, name: $0.name, callingCode: $0.callingCodes[0], flag: $0.flagEmoji) }
            .sorted { $0.name.compare($1.name, locale: Locale.current) == .orderedAscending }
    }

    /// Pays estimé par Telegram à partir de l'adresse IP (code ISO).
    func estimatedCountryCode() async throws -> String {
        try await run { try await $0.getCountryCode() }.text
    }

    // MARK: - Privé

    private func handle(_ state: AuthorizationState) async {
        guard case .authorizationStateWaitTdlibParameters = state else {
            stepContinuation.yield(AuthStep(state))
            return
        }
        stepContinuation.yield(.starting)
        do {
            try await sendParameters()
        } catch {
            stepContinuation.yield(.failed("Impossible d'initialiser la base locale chiffrée."))
        }
    }

    private func sendParameters() async throws {
        let key = try DatabaseKeyStore.loadOrCreateKey()
        if key.isNew {
            // Sans la clé (nouvel appareil, trousseau effacé), une base existante est illisible :
            // on repart d'un dossier vide plutôt que d'échouer.
            try TDLibStorage.reset()
        }
        let directory = try TDLibStorage.prepareDirectory()
        let version = ProcessInfo.processInfo.operatingSystemVersion

        _ = try await client.setTdlibParameters(
            apiHash: config.apiHash,
            apiId: config.apiId,
            applicationVersion: config.applicationVersion,
            databaseDirectory: directory.appendingPathComponent("db", isDirectory: true).path,
            databaseEncryptionKey: key.data,
            deviceModel: "iPhone",
            filesDirectory: directory.appendingPathComponent("files", isDirectory: true).path,
            systemLanguageCode: Locale.preferredLanguages.first ?? "fr",
            systemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            useChatInfoDatabase: true,
            useFileDatabase: true,
            useMessageDatabase: true,
            useSecretChats: true,
            useTestDc: false
        )
    }

    private func run<T>(_ body: (TDLibClient) async throws -> T) async throws -> T {
        do {
            return try await body(client)
        } catch let error as TDLibKit.Error {
            throw TelegramError(code: error.code, message: error.message)
        }
    }

    /// Les journaux TDLib peuvent contenir messages et numéros : on les réduit au strict minimum.
    private static func configureLogging(_ client: TDLibClient) {
        #if DEBUG
        let level = 1 // erreurs uniquement
        #else
        let level = 0 // erreurs fatales uniquement
        #endif
        _ = try? client.execute(query: DTO(SetLogVerbosityLevel(newVerbosityLevel: level), encoder: client.encoder))
    }
}
