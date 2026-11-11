import Foundation
@preconcurrency import TDLibKit

enum TDLibRuntime {
    /// Un seul gestionnaire par processus : `td_receive` n'est appelable que depuis un thread.
    static let manager = TDLibClientManager()

    /// Les journaux TDLib peuvent contenir messages et numéros de téléphone.
    /// - Release : aucun journal (flux vide, niveau 0).
    /// - Debug : erreurs seulement, sur la sortie d'erreur (console Xcode, non conservée).
    ///
    /// `td_execute` est global au processus. Appelé juste après la création du client, avant
    /// tout envoi de paramètres, de numéro ou de code.
    static func configureLogging(using client: TDLibClient) {
        #if DEBUG
        let verbosityApplied = isOk(try? client.execute(
            query: DTO(SetLogVerbosityLevel(newVerbosityLevel: 1), encoder: client.encoder)
        ))
        assert(verbosityApplied, "Niveau de journalisation TDLib refusé")
        #else
        _ = try? client.execute(
            query: DTO(SetLogVerbosityLevel(newVerbosityLevel: 0), encoder: client.encoder)
        )
        _ = try? client.execute(
            query: DTO(SetLogStream(logStream: .logStreamEmpty), encoder: client.encoder)
        )
        #endif
    }

    private static func isOk(_ result: [String: Any]?) -> Bool {
        (result?["@type"] as? String) == "ok"
    }
}

/// Enveloppe d'un client TDLib. Seul point de l'app qui importe TDLibKit (avec les conversions
/// `AuthStep+TDLib`, `ChatListEvent+TDLib` et `MessageEvent+TDLib`).
/// Un client fermé (`authorizationStateClosed`, après déconnexion) ne peut pas être réutilisé :
/// il faut en créer un nouveau.
actor TelegramClient: AuthService {
    /// Étapes d'authentification, dans l'ordre reçu de TDLib.
    nonisolated let steps: AsyncStream<AuthStep>
    /// Changements de la liste des conversations, émis dès la création du client.
    nonisolated let chatEvents: AsyncStream<ChatListEvent>
    /// Changements des messages de toutes les conversations, émis dès la création du client.
    nonisolated let messageEvents: AsyncStream<MessageEvent>

    private let stepContinuation: AsyncStream<AuthStep>.Continuation
    private let rawStates: AsyncStream<AuthorizationState>
    private let client: TDLibClient
    private let config: AppConfig
    private var pumpTask: Task<Void, Never>?

    /// Vrai tant que TDLib attend ses paramètres (première initialisation ou nouvel essai).
    private var awaitsParameters = false
    private var isInitializing = false
    /// Vrai après `authorizationStateLoggingOut` : la fermeture qui suit est une déconnexion
    /// (locale ou session révoquée à distance), et non une simple fermeture du client.
    private var isLoggingOut = false

    init(config: AppConfig, manager: TDLibClientManager = TDLibRuntime.manager) {
        self.config = config

        let stepStream = AsyncStream.makeStream(of: AuthStep.self)
        self.steps = stepStream.stream
        self.stepContinuation = stepStream.continuation

        let rawStream = AsyncStream.makeStream(of: AuthorizationState.self)
        self.rawStates = rawStream.stream
        let rawContinuation = rawStream.continuation

        let chatStream = AsyncStream.makeStream(of: ChatListEvent.self)
        self.chatEvents = chatStream.stream
        let chatContinuation = chatStream.continuation

        let messageStream = AsyncStream.makeStream(of: MessageEvent.self)
        self.messageEvents = messageStream.stream
        let messageContinuation = messageStream.continuation

        self.client = manager.createClient { data, client in
            guard let update = try? client.decoder.decode(Update.self, from: data) else { return }
            if case .updateAuthorizationState(let value) = update {
                rawContinuation.yield(value.authorizationState)
                if case .authorizationStateClosed = value.authorizationState {
                    rawContinuation.finish()
                    chatContinuation.finish()
                    messageContinuation.finish()
                }
            } else if let event = ChatListEvent(update) {
                chatContinuation.yield(event)
            } else if let event = MessageEvent(update) {
                messageContinuation.yield(event)
            }
        }
        TDLibRuntime.configureLogging(using: self.client)
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

    func retryInitialization() async {
        guard awaitsParameters, !isInitializing else { return }
        await initialize()
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

    func requestPasswordRecovery() async throws {
        _ = try await run { try await $0.requestAuthenticationPasswordRecovery() }
    }

    func recoverPassword(code: String, newPassword: String, newHint: String) async throws {
        _ = try await run {
            try await $0.recoverAuthenticationPassword(newHint: newHint, newPassword: newPassword, recoveryCode: code)
        }
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

    func estimatedCountryCode() async throws -> String {
        try await run { try await $0.getCountryCode() }.text
    }

    // MARK: - Privé

    private func handle(_ state: AuthorizationState) async {
        switch state {
        case .authorizationStateWaitTdlibParameters:
            awaitsParameters = true
            await initialize()
        case .authorizationStateLoggingOut:
            isLoggingOut = true
            stepContinuation.yield(AuthStep(state))
        case .authorizationStateClosed:
            if isLoggingOut {
                Self.eraseLocalData()
            }
            stepContinuation.yield(.closed)
        default:
            awaitsParameters = false
            stepContinuation.yield(AuthStep(state))
        }
    }

    private func initialize() async {
        isInitializing = true
        defer { isInitializing = false }
        stepContinuation.yield(.starting)
        do {
            try await sendParameters()
            awaitsParameters = false
        } catch {
            stepContinuation.yield(.failed("Impossible d'initialiser la base locale chiffrée."))
        }
    }

    private func sendParameters() async throws {
        let key = try Self.databaseKey()
        let directory = try TDLibStorage.prepareDirectory()
        let version = ProcessInfo.processInfo.operatingSystemVersion

        _ = try await client.setTdlibParameters(
            apiHash: config.apiHash,
            apiId: config.apiId,
            applicationVersion: config.applicationVersion,
            databaseDirectory: directory.appendingPathComponent("db", isDirectory: true).path,
            databaseEncryptionKey: key,
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

    /// Clé de chiffrement de la base. Sans clé (premier lancement, nouvel appareil, trousseau
    /// effacé), une base existante est illisible : le dossier est vidé *avant* de créer la clé,
    /// pour ne jamais associer une clé neuve à une ancienne base si l'effacement échoue.
    /// Un trousseau verrouillé lève une erreur et n'efface rien.
    private static func databaseKey() throws -> Data {
        if let existing = try DatabaseKeyStore.loadKey() {
            return existing
        }
        try TDLibStorage.reset()
        return try DatabaseKeyStore.createKey()
    }

    /// Après une déconnexion, TDLib a détruit sa base. On supprime aussi le dossier et la clé :
    /// la session suivante repart d'une clé neuve. Au mieux : un échec ici est rattrapé au
    /// lancement suivant (clé absente → dossier vidé ; dossier vide → nouvelle base).
    private static func eraseLocalData() {
        try? TDLibStorage.reset()
        try? DatabaseKeyStore.deleteKey()
    }

    /// Exécute une requête TDLib ; les erreurs deviennent des `TelegramError`.
    func run<T>(_ body: (TDLibClient) async throws -> T) async throws -> T {
        do {
            return try await body(client)
        } catch let error as TDLibKit.Error {
            throw TelegramError(code: error.code, message: error.message)
        }
    }
}
