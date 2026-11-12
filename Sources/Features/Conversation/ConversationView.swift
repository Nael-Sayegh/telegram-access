import SwiftUI

/// Écran d'une conversation : messages (`MessageListView`), barre de rédaction en bas, boutons
/// de saut dans la barre du haut (ordre VoiceOver : Retour, titre, premier non lu, dernier
/// message, puis les messages et la barre de rédaction).
///
/// Gestes VoiceOver : Magic Tap (double toucher à deux doigts) envoie le brouillon ; Escape
/// (Z à deux doigts) annule une réponse ou une modification, sinon revient à la liste.
struct ConversationView: View {
    @State private var model: ConversationViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(chatId: Int64, store: ChatStore, hub: MessageHub, service: any ConversationService) {
        _model = State(initialValue: ConversationViewModel(chatId: chatId, store: store, hub: hub, service: service))
    }

    var body: some View {
        MessageListView(model: model)
            .overlay { statusOverlay }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ComposerBar(model: model)
            }
            .accessibilityAction(.magicTap) { model.magicTap() }
            .accessibilityAction(.escape) {
                if !model.cancelComposerMode() {
                    dismiss()
                }
            }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    jumpButtons
                }
            }
            .sheet(item: $model.reactionRequest) { row in
                ReactionPicker(row: row, model: model)
            }
            .sheet(item: $model.forwardRequest) { row in
                ForwardPicker(targets: model.forwardTargets) { target in
                    model.forward(row, to: target)
                }
            }
            .modifier(MessageDeletionAlert(model: model))
            .modifier(LinkConfirmationAlert(model: model))
            .onChange(of: model.linkToOpen) { _, url in
                guard let url else { return }
                openURL(url)
                model.linkOpened()
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

/// Barre de rédaction : activité des participants (« écrit… »), bandeau de réponse ou de
/// modification, champ multiligne, bouton Envoyer à position fixe, estompé tant que le champ
/// est vide (VoiceOver : « Envoyer, estompé, bouton »).
///
/// Fond opaque, pas de matériau translucide : les messages qui défilent derrière ne
/// transparaissent pas sous le texte du bandeau (contraste constant, comme avec « Réduire la
/// transparence »).
private struct ComposerBar: View {
    @Bindable var model: ConversationViewModel
    @ScaledMetric(relativeTo: .title2) private var sendIconSize: CGFloat = 32
    @FocusState private var isFieldFocused: Bool
    @AccessibilityFocusState private var isFieldVoiceOverFocused: Bool

    private var sendLabel: String {
        let base = model.editing != nil ? "Enregistrer la modification" : "Envoyer"
        return model.isSending ? "\(base), en cours" : base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let activity = model.activityText {
                Text(activity)
                    .font(.footnote)
                    .readableSecondary()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let context = model.composerContext {
                ComposerContextBanner(context: context) {
                    _ = model.cancelComposerMode()
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                // Sur plusieurs lignes, le texte indicatif ne sert plus de libellé : sans
                // celui-ci, VoiceOver annoncerait une zone de texte sans nom. Pendant une
                // réponse, le libellé la rappelle (« Réponse à Paul Martin »).
                TextField("Message", text: $model.draft, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .focused($isFieldFocused)
                    .accessibilityFocused($isFieldVoiceOverFocused)
                    .accessibilityLabel(model.composerFieldLabel)
                Button {
                    model.send()
                } label: {
                    Image(systemName: model.editing != nil ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                        .resizable()
                        .frame(width: sendIconSize, height: sendIconSize)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(SendButtonStyle())
                .disabled(!model.canSend)
                .accessibilityLabel(sendLabel)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .top) { Divider() }
        // Répondre, Modifier : clavier et focus VoiceOver dans le champ (action de l'utilisateur).
        .onChange(of: model.composerFocusRequest) {
            isFieldFocused = true
            isFieldVoiceOverFocused = true
        }
    }
}

/// Bandeau au-dessus du champ : « Réponse à Paul Martin » ou « Modification du message », avec
/// un extrait, et un bouton pour annuler.
private struct ComposerContextBanner: View {
    let context: ConversationViewModel.ComposerContext
    let cancel: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: context.isEditing ? "pencil" : "arrowshape.turn.up.left")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.title)
                    .font(.footnote.weight(.semibold))
                // Couleur de texte pleine : l'extrait se distingue du titre par la graisse.
                Text(context.excerpt)
                    .font(.footnote)
                    .foregroundStyle(Color.primary)
                    // Aux tailles « accessibilité », rien n'est tronqué.
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button(action: cancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .foregroundStyle(Color.primary.opacity(0.6))
            .accessibilityLabel(context.cancelLabel)
        }
    }
}

/// Alerte de suppression d'un message : « Annuler » toujours visible (comme pour les
/// conversations), boutons selon ce que Telegram permet.
private struct MessageDeletionAlert: ViewModifier {
    @Bindable var model: ConversationViewModel

    func body(content: Content) -> some View {
        let request = model.deletionRequest
        let dialog = request.map { model.deletionDialog(for: $0) }
        content.alert(
            Text(dialog?.title ?? ""),
            isPresented: Binding(
                get: { model.deletionRequest != nil },
                set: { if !$0 { model.deletionRequest = nil } }
            ),
            presenting: request
        ) { row in
            if let forMe = dialog?.forMe {
                Button(forMe, role: .destructive) {
                    model.confirmDeletion(of: row, forEveryone: false)
                }
            }
            if let forEveryone = dialog?.forEveryone {
                Button(forEveryone, role: .destructive) {
                    model.confirmDeletion(of: row, forEveryone: true)
                }
            }
            Button("Annuler", role: .cancel) {}
        }
    }
}

/// Alerte avant d'ouvrir un lien vers une autre app : destination complète, « Ouvrir » et
/// « Annuler ».
private struct LinkConfirmationAlert: ViewModifier {
    @Bindable var model: ConversationViewModel

    func body(content: Content) -> some View {
        let url = model.linkConfirmation
        let confirmation = url.map { ConversationLabels.linkConfirmation($0) }
        content.alert(
            Text(confirmation?.title ?? ""),
            isPresented: Binding(
                get: { model.linkConfirmation != nil },
                set: { if !$0 { model.linkConfirmation = nil } }
            ),
            presenting: url
        ) { url in
            Button(confirmation?.confirm ?? "Ouvrir") {
                model.confirmLink(url)
            }
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text(confirmation?.message ?? "")
        }
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
