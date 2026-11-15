import Combine
import SwiftUI
import UIKit

/// Liste des messages d'une conversation, en SwiftUI.
///
/// Ordre de lecture VoiceOver = ordre des lignes (début, jour, messages du jour, jour
/// suivant…), y compris hors de l'écran : balayer à droite donne le message suivant, à gauche
/// le précédent, sans saut (comme WhatsApp). Les titres de jour sont des lignes ordinaires, pas
/// des en-têtes « collants » qui se superposeraient aux messages. Identifiants stables : quand
/// l'historique s'insère au-dessus ou qu'un message arrive, le focus reste sur le même message.
///
/// Remplace une `UICollectionView` qui, à l'essai sur iPhone (2026-11-11), donnait sous
/// VoiceOver un parcours désordonné et différent selon le sens.
struct MessageListView: View {
    let model: ConversationViewModel
    @AccessibilityFocusState private var focusedItem: ConversationItem.ID?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    /// Messages actuellement à l'écran (apparition / disparition des lignes).
    @State private var visibleIds: Set<Int64> = []
    @State private var reportTask: Task<Void, Never>?
    /// Espace des rotors : chaque message y est repéré, même hors écran.
    @Namespace private var rotorNamespace

    var body: some View {
        let lastMessageId = model.state.newestId
        // Bouton sous la liste, pas superposé : aucun message caché derrière. Lu par VoiceOver
        // juste avant la barre de rédaction.
        VStack(spacing: 0) {
            list(lastMessageId: lastMessageId)
            if let label = newMessagesLabel(lastMessageId: lastMessageId) {
                NewMessagesButton(label: label) {
                    Task { await model.showFirstUnseen() }
                }
            }
        }
    }

    /// « 3 nouveaux messages » s'il en reste à voir et que la fin n'est pas à l'écran. Sans
    /// VoiceOver, la liste suit un message arrivé quand on voyait la fin (`follow`) : pas de
    /// bouton dans ce cas.
    private func newMessagesLabel(lastMessageId: Int64?) -> String? {
        let unseen = model.unseenIncomingIds
        guard let first = unseen.first else { return nil }
        if let lastMessageId, visibleIds.contains(lastMessageId) { return nil }
        let ids = model.state.orderedIds
        if !voiceOverEnabled, let index = ids.firstIndex(of: first), index > 0, visibleIds.contains(ids[index - 1]) {
            return nil
        }
        return ConversationLabels.newMessages(unseen.count)
    }

    private func list(lastMessageId: Int64?) -> some View {
        let items = model.items
        return ScrollViewReader { proxy in
            List(items) { item in
                row(item)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                    .accessibilityFocused($focusedItem, equals: item.id)
                    .accessibilityRotorEntry(id: item.id, in: rotorNamespace)
            }
            .listStyle(.plain)
            .messageRotors(items.compactMap(\.message), model: model, namespace: rotorNamespace)
            // Le premier titre de jour n'est jamais collé à la barre du haut, dont les
            // boutons (capsules d'iOS 26) projettent une ombre.
            .contentMargins(.top, 20, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 1)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: items.first?.id) { oldFirst, _ in
                keepPosition(previousFirst: oldFirst, items: items, proxy: proxy)
            }
            .onChange(of: lastMessageId) { oldLast, newLast in
                follow(from: oldLast, to: newLast, proxy: proxy)
            }
            .onChange(of: model.scrollToBottomRequest) {
                guard let lastMessageId else { return }
                Task { @MainActor in
                    withAnimation { proxy.scrollTo(ConversationItem.ID.message(lastMessageId), anchor: .bottom) }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                // Le clavier réduit la liste : si l'on voyait le dernier message, on le garde.
                guard let lastMessageId, visibleIds.contains(lastMessageId) else { return }
                proxy.scrollTo(ConversationItem.ID.message(lastMessageId), anchor: .bottom)
            }
            .task(id: model.focusRequest) {
                await moveFocus(model.focusRequest, proxy: proxy)
            }
        }
    }

    @ViewBuilder
    private func row(_ item: ConversationItem) -> some View {
        switch item {
        case .day(_, let title, let isStart):
            CenteredText(
                text: title,
                font: .subheadline.weight(.semibold),
                isHeader: true,
                spokenText: isStart ? "\(title), début de la conversation" : nil
            )
                .padding(.top, 10)
                .padding(.bottom, 4)
        case .message(let message):
            let actions = model.actions(for: message)
            MessageBubble(row: message)
                // Un message = un élément ; le libellé remplace les textes réunis de la bulle.
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: ConversationLabels.message(message, calendar: .current)))
                // Actions personnalisées (balayer vers le haut ou le bas), dans un ordre fixe.
                .accessibilityActions {
                    ForEach(actions, id: \.self) { action in
                        Button(MessageActionLabels.name(action)) {
                            model.perform(action, on: message)
                        }
                    }
                }
                .modifier(MessageActivation(
                    isVoice: model.voiceAction(for: message) != nil,
                    link: message.links.count == 1 ? message.links.first : nil,
                    toggleVoice: { model.toggleVoice(message) },
                    open: { model.open($0) }
                ))
                .modifier(MessageContextMenu(actions: actions, isEnabled: !voiceOverEnabled) { action in
                    model.perform(action, on: message)
                })
                .onAppear { appeared(message.id) }
                .onDisappear { disappeared(message.id) }
        }
    }

    // MARK: - Visibilité

    private func appeared(_ id: Int64) {
        visibleIds.insert(id)
        model.messageAppeared(id)
        scheduleVisibleReport()
    }

    private func disappeared(_ id: Int64) {
        visibleIds.remove(id)
        scheduleVisibleReport()
    }

    /// Signale les messages visibles une demi-seconde après le dernier changement : un message
    /// seulement survolé pendant un défilement n'est pas compté comme lu.
    private func scheduleVisibleReport() {
        reportTask?.cancel()
        reportTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            model.messagesVisible(Array(visibleIds))
        }
    }

    // MARK: - Position

    /// Des messages plus anciens ont été ajoutés au-dessus : le premier message visible reste
    /// en haut de l'écran (sans cela, la liste montrerait d'un coup les messages ajoutés).
    private func keepPosition(previousFirst: ConversationItem.ID?, items: [ConversationItem], proxy: ScrollViewProxy) {
        guard let previousFirst, items.first?.id != previousFirst,
              items.contains(where: { $0.id == previousFirst }) else { return }
        let anchor = items.first { item in
            if case .message(let row) = item { return visibleIds.contains(row.id) }
            return false
        }
        guard let anchor else { return }
        Task { @MainActor in
            proxy.scrollTo(anchor.id, anchor: .top)
        }
    }

    /// Sans VoiceOver, on suit un nouveau message si l'on voyait le précédent dernier. Sous
    /// VoiceOver, rien ne bouge : le focus ne doit jamais sauter.
    private func follow(from oldLast: Int64?, to newLast: Int64?, proxy: ScrollViewProxy) {
        guard let oldLast, let newLast, newLast > oldLast, visibleIds.contains(oldLast), !voiceOverEnabled else {
            return
        }
        Task { @MainActor in
            withAnimation { proxy.scrollTo(ConversationItem.ID.message(newLast), anchor: .bottom) }
        }
    }

    /// Amène le message demandé à l'écran puis y place le focus VoiceOver (ouverture, sauts).
    private func moveFocus(_ request: MessageFocusRequest?, proxy: ScrollViewProxy) async {
        guard let request else { return }
        let id = ConversationItem.ID.message(request.messageId)
        let anchor: UnitPoint = request.position == .top ? .top : .bottom
        proxy.scrollTo(id, anchor: anchor)
        // Seconde passe une fois les hauteurs des lignes calculées, puis le focus.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        proxy.scrollTo(id, anchor: anchor)
        focusedItem = id
    }
}

/// « 3 nouveaux messages » : amène au premier message reçu pas encore vu et y place le focus.
/// Texte « fond système » sur la couleur d'accent, comme un message envoyé (contraste vérifié
/// dans les deux modes).
private struct NewMessagesButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .accessibilityHidden(true)
                Text(label)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(uiColor: .systemBackground))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Capsule().fill(Color.accentColor))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Va au premier nouveau message.")
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// Activation d'un message (double toucher, ou toucher sans VoiceOver) :
/// - vocal : lecture / pause, sans que VoiceOver parle par-dessus (`startsMediaSession`) ;
/// - un seul lien : l'ouvre, et VoiceOver annonce « lien ». Avec plusieurs liens, chacun a
///   son action.
private struct MessageActivation: ViewModifier {
    let isVoice: Bool
    let link: URL?
    let toggleVoice: () -> Void
    let open: (URL) -> Void

    func body(content: Content) -> some View {
        if isVoice {
            content
                .accessibilityAddTraits(.startsMediaSession)
                .accessibilityHint(VoiceLabels.listenHint)
                .accessibilityAction { toggleVoice() }
                .onTapGesture { toggleVoice() }
        } else if let link {
            content
                .accessibilityAddTraits(.isLink)
                .accessibilityAction { open(link) }
                .onTapGesture { open(link) }
        } else {
            content
        }
    }
}

/// Menu contextuel (appui long) pour l'usage sans VoiceOver. Désactivé sous VoiceOver : il
/// doublerait les actions personnalisées.
private struct MessageContextMenu: ViewModifier {
    let actions: [MessageAction]
    let isEnabled: Bool
    let perform: (MessageAction) -> Void

    func body(content: Content) -> some View {
        if isEnabled, !actions.isEmpty {
            content.contextMenu {
                ForEach(actions, id: \.self) { action in
                    Button(role: action == .delete ? .destructive : nil) {
                        perform(action)
                    } label: {
                        Label(MessageActionLabels.name(action), systemImage: Self.icon(action))
                    }
                }
            }
        } else {
            content
        }
    }

    private static func icon(_ action: MessageAction) -> String {
        switch action {
        case .listen, .resumeListening: return "play"
        case .pauseListening: return "pause"
        case .reply: return "arrowshape.turn.up.left"
        case .react: return "face.smiling"
        case .copy: return "doc.on.doc"
        case .forward: return "arrowshape.turn.up.right"
        case .edit: return "pencil"
        case .pin: return "pin"
        case .unpin: return "pin.slash"
        case .openLink: return "safari"
        case .resend: return "arrow.clockwise"
        case .delete: return "trash"
        }
    }
}

extension View {
    /// Rotors VoiceOver « Messages non lus » (à l'ouverture), « Liens », « Mentions »,
    /// « Médias » : aller directement d'un message concerné au suivant, y compris hors écran.
    func messageRotors(_ rows: [MessageRowModel], model: ConversationViewModel, namespace: Namespace.ID) -> some View {
        let unread = rows.filter { model.isUnreadAtOpen($0) }
        let links = rows.filter { !$0.links.isEmpty }
        let mentions = rows.filter(\.isMention)
        let media = rows.filter { $0.mediaKind != nil }
        // Chaque entrée est lue avec le libellé complet du message.
        return self
            .accessibilityRotor(Text("Messages non lus")) {
                ForEach(unread) { row in
                    AccessibilityRotorEntry(Text(verbatim: ConversationLabels.message(row, calendar: .current)), id: ConversationItem.ID.message(row.id), in: namespace)
                }
            }
            .accessibilityRotor(Text("Liens")) {
                ForEach(links) { row in
                    AccessibilityRotorEntry(Text(verbatim: ConversationLabels.message(row, calendar: .current)), id: ConversationItem.ID.message(row.id), in: namespace)
                }
            }
            .accessibilityRotor(Text("Mentions")) {
                ForEach(mentions) { row in
                    AccessibilityRotorEntry(Text(verbatim: ConversationLabels.message(row, calendar: .current)), id: ConversationItem.ID.message(row.id), in: namespace)
                }
            }
            .accessibilityRotor(Text("Médias")) {
                ForEach(media) { row in
                    AccessibilityRotorEntry(Text(verbatim: ConversationLabels.message(row, calendar: .current)), id: ConversationItem.ID.message(row.id), in: namespace)
                }
            }
    }
}

/// Texte centré dont l'élément VoiceOver (et le cadre mesuré par l'audit d'accessibilité)
/// se limite aux lettres : le centrage vient d'espaces autour, pas d'un cadre étiré sur toute
/// la largeur, qui engloberait ce qui se trouve à côté (ombres de la barre…).
private struct CenteredText: View {
    let text: String
    let font: Font
    var isHeader = false
    /// Libellé VoiceOver, s'il diffère du texte affiché.
    var spokenText: String?

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(text)
                .font(font)
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text(verbatim: spokenText ?? text))
                .accessibilityAddTraits(isHeader ? .isHeader : [])
            Spacer(minLength: 0)
        }
    }
}
