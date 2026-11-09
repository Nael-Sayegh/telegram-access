import SwiftUI

@main
struct TelegramAccessApp: App {
    @State private var auth = TelegramAccessApp.makeAuthViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(auth: auth)
                .task {
                    guard !AppConfig.isRunningUnitTests else { return }
                    auth.start()
                }
        }
    }

    @MainActor
    private static func makeAuthViewModel() -> AuthViewModel {
        #if DEBUG
        if let scenario = UITestScenario.fromLaunchArguments() {
            return AuthViewModel(config: UITestScenario.config) { _ in UITestAuthService(scenario: scenario) }
        }
        #endif
        return AuthViewModel(config: AppConfig.isRunningUnitTests ? nil : AppConfig.fromBundle())
    }
}

/// Aiguille vers l'écran correspondant à l'étape d'authentification.
struct RootView: View {
    @Bindable var auth: AuthViewModel

    var body: some View {
        NavigationStack {
            content
        }
        // Le contenu change sans navigation : on signale le nouvel écran à VoiceOver.
        .onChange(of: auth.step) {
            AccessibilityNotification.ScreenChanged(nil).post()
        }
        .onChange(of: auth.isRecoveringPassword) {
            AccessibilityNotification.ScreenChanged(nil).post()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch auth.step {
        case .starting:
            ProgressView("Connexion à Telegram…")
                .navigationTitle(Self.appName)
        case .loggingOut, .closed:
            ProgressView("Déconnexion…")
                .navigationTitle(Self.appName)
        case .configurationMissing:
            ConfigurationMissingView()
        case .failed(let message):
            FatalErrorView(message: message) { auth.retry() }
        case .phoneNumber:
            PhoneNumberView(auth: auth)
        case .code(let info):
            CodeView(auth: auth, info: info)
        case .emailAddress:
            EmailAddressView(auth: auth)
        case .emailCode(let pattern, let length):
            EmailCodeView(auth: auth, emailPattern: pattern, codeLength: length)
        case .password(let info):
            if auth.isRecoveringPassword {
                PasswordRecoveryView(auth: auth, info: info)
            } else {
                PasswordView(auth: auth, info: info)
            }
        case .registration(let terms):
            RegistrationView(auth: auth, terms: terms)
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
