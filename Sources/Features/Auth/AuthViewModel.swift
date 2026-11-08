import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {
    private(set) var step: AuthStep
    private(set) var isBusy = false
    /// Dernière erreur à afficher sous le champ concerné.
    private(set) var errorMessage: String?
    /// Incrémenté à chaque erreur : les vues y réagissent pour replacer le focus sur le champ.
    private(set) var errorCount = 0

    private(set) var countries: [Country] = []
    var selectedCountry: Country?

    /// Moment où le code actuel a été demandé (calcul du délai de renvoi).
    private(set) var codeRequestedAt: Date?

    private let config: AppConfig?
    private var client: TelegramClient?
    private var listenTask: Task<Void, Never>?
    /// Vrai pendant un retour volontaire à la saisie du numéro depuis l'écran du code.
    private var isEditingPhoneNumber = false

    init(config: AppConfig?) {
        self.config = config
        self.step = config == nil ? .configurationMissing : .starting
    }

    // MARK: - Cycle de vie

    func start() {
        guard client == nil, let config else { return }
        let client = TelegramClient(config: config)
        self.client = client
        listenTask = Task { [weak self] in
            await client.start()
            for await step in client.steps {
                self?.apply(step, from: client)
            }
        }
    }

    func restart() {
        listenTask?.cancel()
        listenTask = nil
        client = nil
        step = .starting
        start()
    }

    private func apply(_ newStep: AuthStep, from source: TelegramClient) {
        // Ignore les derniers états d'un client remplacé.
        guard source === client else { return }

        if case .phoneNumber = newStep {
            isEditingPhoneNumber = false
            Task { await loadCountriesIfNeeded() }
        }
        if case .code = newStep {
            codeRequestedAt = Date()
        }
        clearError()

        if case .closed = newStep {
            // Après une déconnexion, le client TDLib est définitivement fermé : on en recrée un.
            step = .closed
            restart()
            return
        }
        if isEditingPhoneNumber { return }
        step = newStep
    }

    // MARK: - Actions

    func editPhoneNumber() {
        isEditingPhoneNumber = true
        clearError()
        step = .phoneNumber
        Task { await loadCountriesIfNeeded() }
    }

    func submitPhoneNumber(_ input: String) {
        guard let country = selectedCountry else {
            return fail("Choisissez d'abord votre pays.")
        }
        guard input.contains(where: \.isNumber) else {
            return fail("Saisissez votre numéro de téléphone.")
        }
        let number = PhoneNumberFormatter.international(callingCode: country.callingCode, input: input)
        // Remis à faux avant l'appel : le nouvel état TDLib peut arriver avant la réponse.
        isEditingPhoneNumber = false
        perform { try await $0.setPhoneNumber(number) }
    }

    func submitCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fail("Saisissez le code reçu.") }
        perform { try await $0.checkCode(trimmed) }
    }

    func resendCode() {
        if case .code(let info) = step, let requestedAt = codeRequestedAt {
            let remaining = info.resendTimeout - Int(Date().timeIntervalSince(requestedAt))
            if remaining > 0 {
                return fail("Nouveau code disponible dans \(AuthLabels.duration(remaining)).")
            }
        }
        perform(announcement: "Nouveau code demandé.") { try await $0.resendCode() }
    }

    func submitEmailAddress(_ email: String) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@") else { return fail("Saisissez une adresse e-mail valide.") }
        perform { try await $0.setEmailAddress(trimmed) }
    }

    func submitEmailCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fail("Saisissez le code reçu par e-mail.") }
        perform { try await $0.checkEmailCode(trimmed) }
    }

    func submitPassword(_ password: String) {
        guard !password.isEmpty else { return fail("Saisissez votre mot de passe.") }
        perform { try await $0.checkPassword(password) }
    }

    func register(firstName: String, lastName: String) {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty else { return fail("Le prénom est obligatoire.") }
        perform {
            try await $0.register(firstName: first, lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func logOut() {
        perform(announcement: "Déconnexion en cours.") { try await $0.logOut() }
    }

    // MARK: - Privé

    private func loadCountriesIfNeeded() async {
        guard countries.isEmpty, let client else { return }
        do {
            let list = try await client.countries()
            countries = list
            if selectedCountry == nil {
                let estimated = try? await client.estimatedCountryCode()
                let regionCode = estimated ?? Locale.current.region?.identifier
                selectedCountry = list.first { $0.id == regionCode }
            }
        } catch {
            // La liste reste vide : l'écran propose de réessayer via le sélecteur.
        }
    }

    func reloadCountries() {
        Task { await loadCountriesIfNeeded() }
    }

    private func perform(announcement: String? = nil, _ action: @escaping (TelegramClient) async throws -> Void) {
        guard let client, !isBusy else { return }
        isBusy = true
        clearError()
        Task {
            do {
                try await action(client)
                if let announcement { Announcer.announce(announcement) }
            } catch {
                fail(AuthErrorText.message(for: error))
            }
            isBusy = false
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        errorCount += 1
    }

    private func clearError() {
        errorMessage = nil
    }
}
