import SwiftUI

/// Écran affiché une fois connecté. Provisoire : la liste des conversations arrive en phase 2.
struct HomeView: View {
    @Bindable var auth: AuthViewModel
    @State private var confirmsLogout = false

    var body: some View {
        List {
            Section {
                Text("Vous êtes connecté.")
                Text("La liste des conversations sera disponible dans une prochaine version.")
                    .readableSecondary()
            }
            Section {
                Button("Se déconnecter", role: .destructive) {
                    confirmsLogout = true
                }
                // Rouge plus contrasté que le rouge système (audit d'accessibilité).
                .foregroundStyle(Color("DestructiveColor"))
                .disabled(auth.isBusy)
            } footer: {
                AppDisclaimer()
            }
        }
        .navigationTitle("Discussions")
        .confirmationDialog("Se déconnecter de Telegram sur cet appareil ?", isPresented: $confirmsLogout, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) { auth.logOut() }
            Button("Annuler", role: .cancel) {}
        }
        .onChange(of: auth.errorCount) {
            if let message = auth.errorMessage { Announcer.announce(message) }
        }
    }
}
