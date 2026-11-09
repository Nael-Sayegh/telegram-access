import SwiftUI

struct PasswordView: View {
    @Bindable var auth: AuthViewModel
    let info: PasswordInfo
    @State private var password = ""

    var body: some View {
        Form {
            Section {
                SecureField("Mot de passe", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit { auth.submitPassword(password) }
                    .authField(.password, label: "Mot de passe", auth: auth)
                if !info.hint.isEmpty {
                    // Texte brut : l'indice vient du serveur, aucun Markdown ni lien interprété.
                    Text(verbatim: "Indice : " + info.hint)
                }
            } header: {
                Text("Validation en deux étapes")
                    .readableSecondary()
            } footer: {
                Text("Votre compte est protégé par un mot de passe supplémentaire.")
                    .readableSecondary()
            }

            ErrorSection(message: auth.errorMessage)

            Section {
                SubmitButton(title: "Valider le mot de passe", isBusy: auth.isBusy) {
                    auth.submitPassword(password)
                }
                if info.hasRecoveryEmail {
                    Button("Mot de passe oublié") { auth.forgotPassword() }
                        .disabled(auth.isBusy)
                        .accessibilityHint("Envoie un code de récupération à votre adresse e-mail de récupération.")
                }
                ChangePhoneNumberButton(auth: auth)
            } footer: {
                if !info.hasRecoveryEmail {
                    Text("Aucune adresse e-mail de récupération n'est configurée pour ce compte : le mot de passe ne peut pas être récupéré depuis cette application.")
                        .readableSecondary()
                }
            }
        }
        .navigationTitle("Mot de passe")
    }
}

/// Récupération du mot de passe oublié : code reçu par e-mail, puis nouveau mot de passe.
struct PasswordRecoveryView: View {
    @Bindable var auth: AuthViewModel
    let info: PasswordInfo
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var hint = ""

    var body: some View {
        Form {
            Section {
                Text(AuthLabels.recoveryCodeSent(pattern: info.recoveryEmailPattern))
                TextField("Code de récupération", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .authField(.recoveryCode, label: "Code de récupération", auth: auth)
            }

            Section {
                SecureField("Nouveau mot de passe", text: $newPassword)
                    .textContentType(.newPassword)
                    .authField(.newPassword, label: "Nouveau mot de passe", auth: auth)
                SecureField("Confirmation du nouveau mot de passe", text: $confirmation)
                    .textContentType(.newPassword)
                TextField("Indice (facultatif)", text: $hint)
                    .autocorrectionDisabled()
                    .authField(.passwordHint, label: "Indice, facultatif", auth: auth)
            } header: {
                Text("Nouveau mot de passe")
                    .readableSecondary()
            } footer: {
                Text("La validation en deux étapes reste active avec ce nouveau mot de passe. L'indice est visible par toute personne qui tente de se connecter : il ne doit pas révéler le mot de passe.")
                    .readableSecondary()
            }

            ErrorSection(message: auth.errorMessage)

            Section {
                SubmitButton(title: "Changer le mot de passe", isBusy: auth.isBusy) {
                    auth.recoverPassword(code: code, newPassword: newPassword, confirmation: confirmation, hint: hint)
                }
                Button("Revenir à la saisie du mot de passe") { auth.cancelPasswordRecovery() }
                    .disabled(auth.isBusy)
            }
        }
        .navigationTitle("Récupération")
        .onChange(of: auth.errorCount) {
            // Mots de passe différents : on fait tout ressaisir (les champs masqués ne se relisent pas).
            if auth.errorField == .newPassword {
                newPassword = ""
                confirmation = ""
            }
        }
    }
}

struct EmailAddressView: View {
    @Bindable var auth: AuthViewModel
    @State private var email = ""

    var body: some View {
        Form {
            Section {
                TextField("Adresse e-mail", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.next)
                    .onSubmit { auth.submitEmailAddress(email) }
                    .authField(.emailAddress, label: "Adresse e-mail", auth: auth)
            } footer: {
                Text("Telegram demande une adresse e-mail pour sécuriser la connexion.")
                    .readableSecondary()
            }

            ErrorSection(message: auth.errorMessage)

            Section {
                SubmitButton(title: "Continuer", isBusy: auth.isBusy) {
                    auth.submitEmailAddress(email)
                }
                ChangePhoneNumberButton(auth: auth)
            }
        }
        .navigationTitle("Adresse e-mail")
    }
}

struct EmailCodeView: View {
    @Bindable var auth: AuthViewModel
    let emailPattern: String
    let codeLength: Int?
    @State private var code = ""

    var body: some View {
        Form {
            Section {
                Text(AuthLabels.emailCodeSent(pattern: emailPattern, length: codeLength))
                TextField("Code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .authField(.emailCode, label: "Code reçu par e-mail", auth: auth)
            }

            ErrorSection(message: auth.errorMessage)

            Section {
                SubmitButton(title: "Valider le code", isBusy: auth.isBusy) {
                    auth.submitEmailCode(code)
                }
                ChangePhoneNumberButton(auth: auth)
            }
        }
        .navigationTitle("Code e-mail")
    }
}

struct RegistrationView: View {
    @Bindable var auth: AuthViewModel
    let terms: RegistrationTerms
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var showsTerms = false
    @State private var hasAcceptedTerms = false

    var body: some View {
        Form {
            Section {
                TextField("Prénom", text: $firstName)
                    .textContentType(.givenName)
                    .authField(.firstName, label: "Prénom", auth: auth)
                TextField("Nom (facultatif)", text: $lastName)
                    .textContentType(.familyName)
                    .authField(.lastName, label: "Nom, facultatif", auth: auth)
            } header: {
                Text("Nouveau compte Telegram")
                    .readableSecondary()
            }

            Section {
                Button("Lire les conditions d'utilisation de Telegram") { showsTerms = true }
                if let age = AuthLabels.minimumAge(terms.minimumAge) {
                    Text(age)
                }
            } footer: {
                Text(termsFooter)
                    .readableSecondary()
            }

            ErrorSection(message: auth.errorMessage)

            Section {
                SubmitButton(title: "Créer le compte", isBusy: auth.isBusy) {
                    if mustAcceptTerms {
                        showsTerms = true
                    } else {
                        auth.register(firstName: firstName, lastName: lastName)
                    }
                }
                ChangePhoneNumberButton(auth: auth)
            }
        }
        .navigationTitle("Inscription")
        .onAppear {
            // Telegram exige parfois une fenêtre bloquante : elle s'ouvre d'elle-même.
            if mustAcceptTerms { showsTerms = true }
        }
        .sheet(isPresented: $showsTerms) {
            TermsOfServiceView(
                terms: terms,
                onAccept: terms.requiresExplicitAcceptance ? { hasAcceptedTerms = true } : nil,
                onDecline: terms.requiresExplicitAcceptance ? { auth.editPhoneNumber() } : nil
            )
        }
    }

    private var mustAcceptTerms: Bool {
        terms.requiresExplicitAcceptance && !hasAcceptedTerms
    }

    private var termsFooter: String {
        if !terms.requiresExplicitAcceptance {
            return "En créant un compte, vous acceptez les conditions d'utilisation de Telegram."
        }
        return hasAcceptedTerms
            ? "Vous avez accepté les conditions d'utilisation de Telegram."
            : "Vous devez accepter les conditions d'utilisation de Telegram pour créer un compte."
    }
}

/// Texte des conditions d'utilisation, découpé en paragraphes pour une lecture VoiceOver
/// paragraphe par paragraphe. Avec `onAccept` / `onDecline`, la fenêtre est bloquante.
struct TermsOfServiceView: View {
    let terms: RegistrationTerms
    let onAccept: (() -> Void)?
    let onDecline: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let age = AuthLabels.minimumAge(terms.minimumAge) {
                        Text(age).font(.headline)
                    }
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Conditions d'utilisation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .interactiveDismissDisabled(onAccept != nil)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let onAccept, let onDecline {
            ToolbarItem(placement: .cancellationAction) {
                Button("Refuser") {
                    dismiss()
                    onDecline()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Accepter") {
                    onAccept()
                    dismiss()
                }
            }
        } else {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fermer") { dismiss() }
            }
        }
    }

    private var paragraphs: [String] {
        let parts = terms.text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? ["Texte des conditions indisponible."] : parts
    }
}

struct UnsupportedStepView: View {
    let description: String
    let onChangeNumber: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Étape non prise en charge", systemImage: "exclamationmark.circle")
        } description: {
            Text(description)
        } actions: {
            Button("Utiliser un autre numéro", action: onChangeNumber)
        }
        .navigationTitle("Connexion")
    }
}

struct ConfigurationMissingView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Configuration manquante", systemImage: "key.slash")
        } description: {
            Text("Les identifiants de l'API Telegram n'ont pas été intégrés à cette version de l'application.")
        }
        .navigationTitle(RootView.appName)
    }
}

struct FatalErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Erreur", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Réessayer", action: onRetry)
        }
        .navigationTitle(RootView.appName)
    }
}
