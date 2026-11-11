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

    var body: some View {
        let items = model.items
        let lastMessageId = model.state.newestId
        ScrollViewReader { proxy in
            List(items) { item in
                row(item)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                    .accessibilityFocused($focusedItem, equals: item.id)
            }
            .listStyle(.plain)
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
        case .start:
            Text("Début de la conversation.")
                .font(.footnote)
                .readableSecondary()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        case .day(_, let title):
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
        case .message(let message):
            MessageBubble(row: message)
                // Un message = un élément ; le libellé remplace les textes réunis de la bulle.
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: ConversationLabels.message(message, calendar: .current)))
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
