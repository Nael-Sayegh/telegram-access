import SwiftUI

extension View {
    /// Élément d'un écran de connexion (champ de saisie, bouton Pays…).
    ///
    /// Quand une erreur concerne cet élément :
    /// - l'erreur est ajoutée à son libellé (relue à chaque passage, même indices désactivés) ;
    /// - le focus VoiceOver y est placé, ce qui lit le libellé avec l'erreur ;
    /// - si le focus y est déjà, VoiceOver ne relirait pas le libellé modifié : l'erreur est
    ///   alors annoncée ;
    /// - pour un champ de saisie, le clavier y est aussi replacé.
    func authField(_ field: AuthField, label: String, auth: AuthViewModel, isTextInput: Bool = true) -> some View {
        modifier(AuthFieldModifier(field: field, label: label, auth: auth, isTextInput: isTextInput))
    }
}

private struct AuthFieldModifier: ViewModifier {
    let field: AuthField
    let label: String
    let auth: AuthViewModel
    let isTextInput: Bool

    @AccessibilityFocusState private var isVoiceOverFocused: Bool
    @FocusState private var isKeyboardFocused: Bool

    private var error: String? {
        auth.errorField == field ? auth.errorMessage : nil
    }

    func body(content: Content) -> some View {
        content
            .focused($isKeyboardFocused)
            .accessibilityFocused($isVoiceOverFocused)
            .accessibilityLabel(error.map { "\(label). Erreur : \($0)" } ?? label)
            .onChange(of: auth.errorCount) {
                guard let error else { return }
                if isTextInput {
                    isKeyboardFocused = true
                }
                if isVoiceOverFocused {
                    Announcer.announce(error)
                } else {
                    isVoiceOverFocused = true
                }
            }
    }
}

/// Erreur visible à l'écran. Masquée pour VoiceOver : elle est déjà dans le libellé de l'élément
/// concerné, qui reçoit le focus.
struct ErrorSection: View {
    let message: String?

    var body: some View {
        if let message {
            Section {
                Label {
                    Text(message)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                .accessibilityHidden(true)
            }
        }
    }
}

/// Bouton principal d'un écran, annoncé « en cours » pendant l'envoi.
/// Le libellé est posé directement sur le `Button` : `.accessibilityElement(children:)` sur un
/// bouton crée un second élément de même nom (doublon pour VoiceOver et les tests UI).
struct SubmitButton: View {
    let title: String
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                if isBusy {
                    Spacer()
                    ProgressView()
                        .accessibilityHidden(true)
                }
            }
        }
        .disabled(isBusy)
        .accessibilityLabel(isBusy ? "\(title), en cours" : title)
    }
}

extension View {
    /// Texte secondaire lisible. Les gris système (`.secondary`, en-têtes et pieds de section)
    /// n'atteignent pas tout à fait le contraste exigé par l'audit d'accessibilité.
    func readableSecondary() -> some View {
        foregroundStyle(Color.primary.opacity(0.75))
    }
}

/// Lien de retour vers la saisie du numéro, disponible à chaque étape après le numéro.
struct ChangePhoneNumberButton: View {
    let auth: AuthViewModel

    var body: some View {
        Button("Modifier le numéro de téléphone") { auth.editPhoneNumber() }
    }
}

struct AppDisclaimer: View {
    var body: some View {
        Text("\(RootView.appName) est un client Telegram non officiel.")
            .readableSecondary()
    }
}
