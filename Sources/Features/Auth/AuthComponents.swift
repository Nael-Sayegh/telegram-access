import SwiftUI

extension View {
    /// Champ de saisie d'un écran de connexion : en cas d'erreur, le focus VoiceOver revient
    /// sur le champ et l'erreur fait partie de son libellé (lue même si les indices sont désactivés).
    func authField(label: String, error: String?, errorCount: Int) -> some View {
        modifier(AuthFieldModifier(label: label, error: error, errorCount: errorCount))
    }
}

private struct AuthFieldModifier: ViewModifier {
    let label: String
    let error: String?
    let errorCount: Int

    @AccessibilityFocusState private var isVoiceOverFocused: Bool
    @FocusState private var isKeyboardFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isKeyboardFocused)
            .accessibilityFocused($isVoiceOverFocused)
            .accessibilityLabel(error.map { "\(label). Erreur : \($0)" } ?? label)
            .onChange(of: errorCount) {
                isKeyboardFocused = true
                isVoiceOverFocused = true
            }
    }
}

/// Erreur visible à l'écran. Masquée pour VoiceOver : elle est déjà dans le libellé du champ.
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
                }
            }
        }
        .disabled(isBusy)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isBusy ? "\(title), en cours" : title)
        .accessibilityAddTraits(.isButton)
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
    }
}
