import SwiftUI

@main
struct TelegramAccessApp: App {
    @State private var auth = AuthViewModel(
        config: AppConfig.isRunningUnitTests ? nil : AppConfig.fromBundle()
    )

    var body: some Scene {
        WindowGroup {
            RootView(auth: auth)
                .task {
                    guard !AppConfig.isRunningUnitTests else { return }
                    auth.start()
                }
        }
    }
}

/// Aiguille vers l'écran correspondant à l'étape d'authentification.
struct RootView: View {
    @Bindable var auth: AuthViewModel

    var body: some View {
        NavigationStack {
            content
        }
        .onChange(of: auth.step) {
            // Le contenu change sans navigation : on signale le nouvel écran à VoiceOver.
            AccessibilityNotification.ScreenChanged(nil).post()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch auth.step {
        case .starting, .loggingOut, .closed:
            ProgressView("Connexion à Telegram…")
                .navigationTitle(Self.appName)
        case .configurationMissing:
            ConfigurationMissingView()
        case .failed(let message):
            FatalErrorView(message: message) { auth.restart() }
        case .phoneNumber:
            PhoneNumberView(auth: auth)
        case .code(let info):
            CodeView(auth: auth, info: info)
        case .emailAddress:
            EmailAddressView(auth: auth)
        case .emailCode(let pattern, let length):
            EmailCodeView(auth: auth, emailPattern: pattern, codeLength: length)
        case .password(let hint, _):
            PasswordView(auth: auth, hint: hint)
        case .registration:
            RegistrationView(auth: auth)
        case .unsupported(let description):
            UnsupportedStepView(description: description) { auth.editPhoneNumber() }
        case .ready:
            HomeView(auth: auth)
        }
    }

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Accessigram"
    }
}
