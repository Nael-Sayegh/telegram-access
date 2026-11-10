import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {
    private(set) var step: AuthStep
    private(set) var isBusy = false
    /// Dernière erreur à afficher.
    private(set) var errorMessage: String?
    /// Élément auquel se rapporte l'erreur : il reçoit le focus et l'erreur dans son libellé.
    /// `nil` pour une erreur sans champ (déconnexion…), annoncée par l'écran.
    private(set) var errorField: AuthField?
    /// Incrémenté à chaque erreur : les vues y réagissent pour replacer le focus.
    private(set) var errorCount = 0

    private(set) var countries: [Country] = []
    var selectedCountry: Country?

    /// Moment où le code actuel a été demandé (calcul du délai de renvoi).
    private(set) var codeRequestedAt: Date?
    /// Vrai une fois un code de récupération du mot de passe demandé (écran de récupération).
    private(set) var isRecoveringPassword = false

    /// Conversations du client courant. Créé avec le client (TDLib n'envoie chaque conversation
    /// qu'une fois), remplacé avec lui après une déconnexion.
    private(set) var chats: ChatStore?
    /// Service du client courant, pour les opérations sur les conversations.
    var chatService: (any ChatListService)? { service }

    private let config: AppConfig?
    private let makeService: (AppConfig) -> any TelegramService
    private var service: (any TelegramService)?
    private var listenTask: Task<Void, Never>?
    /// Vrai pendant un retour volontaire à la saisie du numéro depuis une étape ultérieure.
    private var isEditingPhoneNumber = false

    init(
        config: AppConfig?,
        makeService: @escaping (AppConfig) -> any TelegramService = { TelegramClient(config: $0) }
    ) {
        self.config = config
        self.makeService = makeService
        self.step = config == nil ? .configurationMissing : .starting
    }

    // MARK: - Cycle de vie

    func start() {
        guard service == nil, let config else { return }
        let service = makeService(config)
        self.service = service
        chats = ChatStore(events: service.chatEvents)
        listenTask = Task { [weak self] in
            await service.start()
            for await step in service.steps {
                self?.apply(step, from: service)
            }
        }
    }

    /// Nouvel essai après un échec d'initialisation (trousseau verrouillé…), sur le même client :
    /// TDLib attend toujours ses paramètres, inutile d'en créer un autre.
    func retry() {
        guard let service else {
            start()
            return
        }
        step = .starting
        Task { await service.retryInitialization() }
    }

    /// Après une déconnexion, le client TDLib est définitivement fermé : on en crée un nouveau.
    private func restart() {
        listenTask?.cancel()
        listenTask = nil
        service = nil
        chats = nil
        isRecoveringPassword = false
        step = .starting
        start()
    }

    private func apply(_ newStep: AuthStep, from source: any AuthService) {
        // Ignore les derniers états d'un client remplacé.
        guard source === service else { return }

        switch newStep {
        case .phoneNumber:
            isEditingPhoneNumber = false
            Task { await loadCountriesIfNeeded() }
        case .code:
            codeRequestedAt = Date()
        case .closed:
            clearError()
            step = .closed
            restart()
            return
        default:
            break
        }
        if case .password = newStep {} else {
            isRecoveringPassword = false
        }
        clearError()

        if isEditingPhoneNumber { return }
        step = newStep
    }

    // MARK: - Actions

    func editPhoneNumber() {
        isEditingPhoneNumber = true
        isRecoveringPassword = false
        clearError()
        step = .phoneNumber
        Task { await loadCountriesIfNeeded() }
    }

    func submitPhoneNumber(_ input: String) {
        guard let country = selectedCountry else {
            return fail("Choisissez d'abord votre pays.", field: .country)
        }
        guard !PhoneNumberFormatter.digits(in: input).isEmpty else {
            return fail("Saisissez votre numéro de téléphone.", field: .phoneNumber)
        }
        let number = PhoneNumberFormatter.international(callingCode: country.callingCode, input: input)
        // Remis à faux avant l'appel : le nouvel état TDLib peut arriver avant la réponse.
        isEditingPhoneNumber = false
        perform(errorField: .phoneNumber) { try await $0.setPhoneNumber(number) }
    }

    func submitCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fail("Saisissez le code reçu.", field: .code) }
        perform(errorField: .code) { try await $0.checkCode(trimmed) }
    }

    func resendCode() {
        if case .code(let info) = step, let requestedAt = codeRequestedAt {
            let remaining = info.resendTimeout - Int(Date().timeIntervalSince(requestedAt))
            if remaining > 0 {
                return fail("Nouveau code disponible dans \(AuthLabels.duration(remaining)).", field: .code)
            }
        }
        perform(errorField: .code, announcement: "Nouveau code demandé.") { try await $0.resendCode() }
    }

    func submitEmailAddress(_ email: String) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@") else {
            return fail("Saisissez une adresse e-mail valide.", field: .emailAddress)
        }
        perform(errorField: .emailAddress) { try await $0.setEmailAddress(trimmed) }
    }

    func submitEmailCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fail("Saisissez le code reçu par e-mail.", field: .emailCode) }
        perform(errorField: .emailCode) { try await $0.checkEmailCode(trimmed) }
    }

    func submitPassword(_ password: String) {
        guard !password.isEmpty else { return fail("Saisissez votre mot de passe.", field: .password) }
        perform(errorField: .password) { try await $0.checkPassword(password) }
    }

    /// Demande un code de récupération à l'adresse e-mail de récupération.
    func forgotPassword() {
        perform(
            errorField: .password,
            announcement: "Code de récupération envoyé.",
            { try await $0.requestPasswordRecovery() },
            onSuccess: { [weak self] in self?.isRecoveringPassword = true }
        )
    }

    func cancelPasswordRecovery() {
        clearError()
        isRecoveringPassword = false
    }

    /// Remplace le mot de passe oublié. Un nouveau mot de passe est exigé : la validation en
    /// deux étapes reste active (TDLib permettrait de la supprimer avec un mot de passe vide).
    func recoverPassword(code: String, newPassword: String, confirmation: String, hint: String) {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            return fail("Saisissez le code de récupération reçu par e-mail.", field: .recoveryCode)
        }
        guard !newPassword.isEmpty else {
            return fail("Choisissez un nouveau mot de passe.", field: .newPassword)
        }
        guard newPassword == confirmation else {
            return fail("Les deux mots de passe saisis sont différents. Saisissez-les à nouveau.", field: .newPassword)
        }
        guard !trimmedHint.localizedCaseInsensitiveContains(newPassword) else {
            return fail("L'indice ne doit pas contenir le mot de passe.", field: .passwordHint)
        }
        perform(errorField: .recoveryCode) {
            try await $0.recoverPassword(code: trimmedCode, newPassword: newPassword, newHint: trimmedHint)
        }
    }

    /// L'acceptation des conditions d'utilisation, quand Telegram l'exige explicitement,
    /// est recueillie par l'écran d'inscription avant cet appel.
    func register(firstName: String, lastName: String) {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty else { return fail("Le prénom est obligatoire.", field: .firstName) }
        perform(errorField: .firstName) { try await $0.register(firstName: first, lastName: last) }
    }

    func logOut() {
        perform(errorField: nil, announcement: "Déconnexion en cours.") { try await $0.logOut() }
    }

    func reloadCountries() {
        Task { await loadCountriesIfNeeded() }
    }

    // MARK: - Privé

    private func loadCountriesIfNeeded() async {
        guard countries.isEmpty, let service else { return }
        do {
            let list = try await service.countries()
            countries = list
            if selectedCountry == nil {
                let estimated = try? await service.estimatedCountryCode()
                let regionCode = estimated ?? Locale.current.region?.identifier
                selectedCountry = list.first { $0.id == regionCode }
            }
        } catch {
            // La liste reste vide : l'écran propose de réessayer via le sélecteur.
        }
    }

    private func perform(
        errorField field: AuthField?,
        announcement: String? = nil,
        _ action: @escaping @Sendable (any AuthService) async throws -> Void,
        onSuccess: (@MainActor () -> Void)? = nil
    ) {
        guard let service, !isBusy else { return }
        isBusy = true
        clearError()
        Task {
            do {
                try await action(service)
                onSuccess?()
                if let announcement { Announcer.announce(announcement) }
            } catch {
                fail(AuthErrorText.message(for: error), field: AuthErrorText.field(for: error) ?? field)
            }
            isBusy = false
        }
    }

    private func fail(_ message: String, field: AuthField?) {
        errorMessage = message
        errorField = field
        errorCount += 1
    }

    private func clearError() {
        errorMessage = nil
        errorField = nil
    }
}
