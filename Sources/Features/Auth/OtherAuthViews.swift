import SwiftUI

struct PasswordView: View {
    @Bindable var auth: AuthViewModel
    let hint: String
    @State private var password = ""

    var body: some View {
        Form {
            Section {
                SecureField("Mot de passe", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit { auth.submitPassword(password) }
                    .authField(label: "Mot de passe", error: auth.errorMessage, errorCount: auth.errorCount)
                if !hint.isEmpty {
                    Text("Indice : \(hint)")
                }
            } header: {
                Text("Validation en deux étapes")
            } footer: {
                Text("Votre compte est protégé par un mot de passe supplémentaire.")
            }

            ErrorSection(message: auth.errorMessage)

            Section {
                SubmitButton(title: "Valider le mot de passe", isBusy: auth.isBusy) {
                    auth.submitPassword(password)
                }
                ChangePhoneNumberButton(auth: auth)
            }
        }
        .navigationTitle("Mot de passe")
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
                    .authField(label: "Adresse e-mail", error: auth.errorMessage, errorCount: auth.errorCount)
            } footer: {
                Text("Telegram demande une adresse e-mail pour sécuriser la connexion.")
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
    let codeLength: Int
    @State private var code = ""

    var body: some View {
        Form {
            Section {
                Text("Un code de \(codeLength) chiffres a été envoyé à \(emailPattern).")
                TextField("Code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .authField(label: "Code reçu par e-mail", error: auth.errorMessage, errorCount: auth.errorCount)
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
    @State private var firstName = ""
    @State private var lastName = ""

    var body: some View {
        Form {
            Section {
                TextField("Prénom", text: $firstName)
                    .textContentType(.givenName)
                    .authField(label: "Prénom", error: auth.errorMessage, errorCount: auth.errorCount)
                TextField("Nom (facultatif)", text: $lastName)
                    .textContentType(.familyName)
            } header: {
                Text("Nouveau compte Telegram")
            } footer: {
                Text("En créant un compte, vous acceptez les conditions d'utilisation de Telegram.")
            }

            ErrorSection(message: auth.errorMessage)

            Section {
                SubmitButton(title: "Créer le compte", isBusy: auth.isBusy) {
                    auth.register(firstName: firstName, lastName: lastName)
                }
                ChangePhoneNumberButton(auth: auth)
            }
        }
        .navigationTitle("Inscription")
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
