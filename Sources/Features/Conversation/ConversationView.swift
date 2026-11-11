import SwiftUI

/// Écran d'une conversation : messages (liste UIKit), barre de rédaction en bas, boutons de
/// saut dans la barre du haut (ordre VoiceOver : Retour, titre, premier non lu, dernier
/// message, puis les messages et la barre de rédaction).
struct ConversationView: View {
    @State private var model: ConversationViewModel

    init(chatId: Int64, store: ChatStore, hub: MessageHub, service: any ConversationService) {
        _model = State(initialValue: ConversationViewModel(chatId: chatId, store: store, hub: hub, service: service))
    }

    var body: some View {
        MessageList(
            sections: model.sections,
            focus: model.focusRequest,
            scrollToBottomRequest: model.scrollToBottomRequest,
            model: model
        )
            .overlay { statusOverlay }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ComposerBar(model: model)
            }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    jumpButtons
                }
            }
            .task { await model.open() }
            .onDisappear { model.close() }
    }

    /// Chargement, échec ou conversation vide (la liste est alors vide, rien n'est masqué).
    @ViewBuilder
    private var statusOverlay: some View {
        if model.state.orderedIds.isEmpty {
            if model.isOpening {
                ProgressView("Chargement des messages…")
            } else if model.loadFailed {
                VStack(spacing: 12) {
                    Text("Impossible de charger les messages. Vérifiez votre connexion.")
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Réessayer") { model.retry() }
                }
                .padding()
            } else if model.isEmpty {
                Text("Aucun message pour l'instant.")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .readableSecondary()
                    .padding()
            }
        }
    }

    @ViewBuilder
    private var jumpButtons: some View {
        if model.hadUnreadAtOpen {
            Button {
                Task { await model.showFirstUnread() }
            } label: {
                Label("Aller au premier message non lu", systemImage: "envelope.badge")
            }
        }
        if !model.state.orderedIds.isEmpty {
            Button {
                Task { await model.showLatest() }
            } label: {
                Label("Aller au dernier message", systemImage: "arrow.down.to.line")
            }
        }
    }
}

/// Liste UIKit des messages (`ConversationViewController`), alimentée par le modèle.
/// Les sections et la demande de focus sont passées en paramètres : la vue parente est
/// réévaluée quand elles changent, ce qui met la liste à jour.
private struct MessageList: UIViewControllerRepresentable {
    let sections: [ConversationSection]
    let focus: MessageFocusRequest?
    let scrollToBottomRequest: Int
    let model: ConversationViewModel

    func makeUIViewController(context: Context) -> ConversationViewController {
        let controller = ConversationViewController()
        controller.onMessageAppear = { [weak model] id in
            model?.messageAppeared(id)
        }
        controller.onVisibleMessages = { [weak model] ids in
            model?.messagesVisible(ids)
        }
        return controller
    }

    func updateUIViewController(_ controller: ConversationViewController, context: Context) {
        controller.update(sections: sections, focus: focus, scrollToBottomRequest: scrollToBottomRequest)
    }
}

/// Barre de rédaction : activité des participants (« écrit… »), champ multiligne, bouton
/// Envoyer à position fixe, estompé tant que le champ est vide (VoiceOver : « Envoyer,
/// estompé, bouton »).
private struct ComposerBar: View {
    @Bindable var model: ConversationViewModel
    @ScaledMetric(relativeTo: .title2) private var sendIconSize: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let activity = model.activityText {
                Text(activity)
                    .font(.footnote)
                    .readableSecondary()
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .bottom, spacing: 8) {
                // Sur plusieurs lignes, le texte indicatif ne sert plus de libellé : sans
                // celui-ci, VoiceOver annoncerait une zone de texte sans nom.
                TextField("Message", text: $model.draft, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .accessibilityLabel("Message")
                Button {
                    model.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .resizable()
                        .frame(width: sendIconSize, height: sendIconSize)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(SendButtonStyle())
                .disabled(!model.canSend)
                .accessibilityLabel(model.isSending ? "Envoyer, en cours" : "Envoyer")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// Bouton Envoyer : bleu d'accent quand il est actif, gris quand il est estompé. Couleurs
/// fixées ici plutôt que l'atténuation automatique d'iOS, pour garder un contraste suffisant
/// (environ 5,7:1 en mode clair) : l'icône grise reste visible.
private struct SendButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.accentColor : Color.primary.opacity(0.6))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
