import Foundation
import Observation
import UIKit

/// Jour d'une conversation : en-tête et messages, dans l'ordre chronologique.
struct ConversationSection: Identifiable, Equatable {
    /// Début du jour ; unique dans une conversation (identifiant de section de la liste).
    let id: Date
    var title: String
    var rows: [MessageRowModel]

    /// Regroupe par jour des lignes triées. Un message daté hors de l'ordre (importé…) rejoint
    /// la section courante : un jour n'apparaît jamais deux fois.
    static func make(_ rows: [MessageRowModel], now: Date, calendar: Calendar) -> [ConversationSection] {
        var sections: [ConversationSection] = []
        var days: Set<Date> = []
        for row in rows {
            let day = calendar.startOfDay(for: row.date)
            if let last = sections.indices.last, sections[last].id == day || days.contains(day) {
                sections[last].rows.append(row)
            } else {
                days.insert(day)
                let title = ConversationLabels.day(row.date, now: now, calendar: calendar)
                sections.append(ConversationSection(id: day, title: title, rows: [row]))
            }
        }
        return sections
    }
}

/// Ligne de la liste des messages, dans l'ordre de lecture VoiceOver : pour chaque jour son
/// titre suivi de ses messages. Les titres de jour sont des lignes ordinaires (pas des
/// en-têtes « collants ») : balayer à droite donne toujours l'élément suivant, à gauche le
/// précédent, sans saut.
enum ConversationItem: Identifiable, Equatable {
    /// Titre d'un jour. `isStart` : premier jour de la conversation, tout l'historique est
    /// chargé (« Hier, début de la conversation »). Pas de ligne séparée : une ligne insérée
    /// après coup en haut de liste échouait à l'audit de contraste, et ce serait un élément
    /// de plus à balayer.
    case day(id: Date, title: String, isStart: Bool)
    case message(MessageRowModel)

    enum ID: Hashable {
        case day(Date)
        case message(Int64)
    }

    var id: ID {
        switch self {
        case .day(let day, _, _): return .day(day)
        case .message(let row): return .message(row.id)
        }
    }

    /// Le message de la ligne, `nil` pour un titre de jour.
    var message: MessageRowModel? {
        if case .message(let row) = self { return row }
        return nil
    }

    /// `reachedStart` : le premier message de la conversation est chargé.
    static func list(_ sections: [ConversationSection], reachedStart: Bool) -> [ConversationItem] {
        var items: [ConversationItem] = []
        for (index, section) in sections.enumerated() {
            items.append(.day(id: section.id, title: section.title, isStart: reachedStart && index == 0))
            items += section.rows.map { .message($0) }
        }
        return items
    }
}

/// Demande d'amener un message à l'écran et d'y placer le focus VoiceOver. Réservée aux
/// actions de l'utilisateur (ouverture, « Aller au premier message non lu ») : un message
/// entrant ne déplace jamais le focus.
struct MessageFocusRequest: Equatable {
    enum Position: Equatable {
        case top
        case bottom
    }

    let messageId: Int64
    let position: Position
    /// Distingue deux demandes successives pour le même message.
    let serial: Int
}

/// Écran de conversation : chargement de l'historique (autour du premier non lu ou depuis le
/// dernier message), pagination dans les deux sens, lecture des messages vus, envoi.
@MainActor
@Observable
final class ConversationViewModel {
    let chatId: Int64
    let store: ChatStore
    private(set) var state: ConversationState
    /// Texte en cours de rédaction.
    var draft = ""
    /// Vrai jusqu'au premier historique chargé.
    private(set) var isOpening = true
    /// Vrai si le chargement initial a échoué (bouton « Réessayer »).
    private(set) var loadFailed = false
    private(set) var isSending = false
    /// Dernier message lu à l'ouverture : les messages reçus ensuite sont « non lus » pour
    /// toute la durée de l'écran, même une fois marqués lus.
    private(set) var lastReadAtOpen: Int64 = 0
    /// Vrai s'il restait des messages non lus à l'ouverture.
    private(set) var hadUnreadAtOpen = false
    private(set) var focusRequest: MessageFocusRequest?
    /// Incrémenté après chaque envoi : la liste défile jusqu'au dernier message (sans
    /// déplacer le focus VoiceOver, qui reste sur le bouton Envoyer).
    private(set) var scrollToBottomRequest = 0
    /// Dernière annonce faite, pour les tests.
    private(set) var lastAnnouncement: String?

    // Actions sur les messages.
    /// Ce que Telegram permet pour chaque message affiché, chargé à son apparition.
    private(set) var capabilities: [Int64: MessageCapabilities] = [:]
    /// Message auquel le brouillon répond (bandeau au-dessus du champ).
    private(set) var replyingTo: Int64?
    /// Message en cours de modification (son texte est dans le champ).
    private(set) var editing: Int64?
    /// Incrémenté pour placer le clavier et le focus VoiceOver dans le champ (Répondre,
    /// Modifier : actions de l'utilisateur).
    private(set) var composerFocusRequest = 0
    /// Message dont la suppression attend confirmation (alerte).
    var deletionRequest: MessageRowModel?
    /// Message auquel réagir (feuille des réactions) ; `reactionChoices` : `nil` pendant le
    /// chargement des réactions proposées.
    var reactionRequest: MessageRowModel?
    private(set) var reactionChoices: [ReactionKind]?
    /// Message à transférer (feuille de choix de la conversation).
    var forwardRequest: MessageRowModel?
    /// Lien vers une autre app, ouvert après confirmation (alerte).
    var linkConfirmation: URL?
    /// Lien à ouvrir par la vue (ouverture système), remis à `nil` une fois ouvert.
    private(set) var linkToOpen: URL?
    /// Copie dans le presse-papiers ; remplacée dans les tests.
    @ObservationIgnored var copyHandler: @MainActor (String) -> Void = { UIPasteboard.general.string = $0 }

    private let hub: MessageHub
    private let service: any ConversationService
    private var isOpen = false
    private var isLoadingOlder = false
    private var isLoadingNewer = false
    /// Incrémenté à chaque remplacement de la fenêtre : une page demandée avant est ignorée.
    private var generation = 0
    private var focusSerial = 0
    /// Messages envoyés depuis cet écran, en attente de la réponse de Telegram.
    private var pendingSentIds: Set<Int64> = []
    /// Réponse de Telegram arrivée avant que l'envoi n'ait renvoyé l'identifiant provisoire.
    private var earlyOutcomes: [Int64: SendOutcome] = [:]
    private var viewedIds: Set<Int64> = []
    private var requestedReplyIds: Set<Int64> = []
    private var requestedCapabilities: Set<Int64> = []
    /// Brouillon mis de côté pendant une modification, rendu à son annulation.
    private var draftBeforeEdit = ""

    private enum SendOutcome {
        case sent
        case failed(TelegramError)
    }

    /// Messages demandés par page (maximum TDLib : 100).
    static let pageSize = 50
    /// Messages plus récents demandés en plus autour du premier non lu.
    static let newerAroundUnread = 25
    /// À l'ouverture, on complète l'historique jusqu'à ce nombre de messages (TDLib n'en renvoie
    /// souvent qu'un au premier appel).
    static let initialMinimum = 20
    /// Nombre de messages du bord de la fenêtre dont l'affichage charge la suite.
    static let prefetchDistance = 10

    init(chatId: Int64, store: ChatStore, hub: MessageHub, service: any ConversationService) {
        self.chatId = chatId
        self.store = store
        self.hub = hub
        self.service = service
        self.state = ConversationState(chatId: chatId)
    }

    // MARK: - Lecture

    var title: String {
        let list = store.state
        return list.chats[chatId].map { list.displayTitle(of: $0) } ?? "Conversation"
    }

    /// Messages groupés par jour, prêts à afficher et à lire.
    var sections: [ConversationSection] {
        let list = store.state
        guard let chat = list.chats[chatId] else { return [] }
        let conversation = state
        let rows = conversation.orderedMessages.map { list.messageRow($0, in: chat, conversation: conversation) }
        return ConversationSection.make(rows, now: Date(), calendar: .current)
    }

    /// Lignes de la liste : jours et messages, dans l'ordre.
    var items: [ConversationItem] {
        ConversationItem.list(sections, reachedStart: state.reachedOldest)
    }

    /// Faux tant que le brouillon est vide (espaces compris) : le bouton Envoyer est estompé.
    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Vrai pour une conversation chargée sans aucun message.
    var isEmpty: Bool {
        state.isLoaded && state.orderedIds.isEmpty && state.reachedOldest
    }

    /// Premier message reçu non lu à l'ouverture, s'il est dans la fenêtre chargée.
    var firstUnreadId: Int64? {
        guard hadUnreadAtOpen else { return nil }
        return state.orderedMessages.first { !$0.isOutgoing && $0.id > lastReadAtOpen }?.id
    }

    /// « écrit… », « Paul écrit… » ; `nil` sans activité.
    var activityText: String? {
        let list = store.state
        let isPrivate = list.chats[chatId]?.kind.peerUserId != nil
        let entries = state.activities
            .map { (name: list.authorName(of: $0.key) ?? "Quelqu'un", activity: $0.value) }
            .sorted { $0.name < $1.name }
        return ConversationLabels.activity(entries, isPrivateChat: isPrivate)
    }

    // MARK: - Ouverture et fermeture

    /// Abonnement aux changements **avant** le chargement de l'historique (rien n'est perdu),
    /// puis ouverture côté TDLib et chargement. Le focus est ensuite placé sur le premier
    /// message non lu, ou sur le dernier message.
    func open() async {
        guard !isOpen else { return }
        isOpen = true
        hub.openChatId = chatId
        hub.observe(chatId, owner: self) { [weak self] event in
            self?.handle(event)
        }
        try? await service.openChat(chatId)
        await loadInitial()
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        hub.stopObserving(self)
        if hub.openChatId == chatId {
            hub.openChatId = nil
        }
        let service = service
        let chatId = chatId
        Task { try? await service.closeChat(chatId) }
    }

    /// Nouvel essai après un échec du chargement initial.
    func retry() {
        Task { await loadInitial() }
    }

    private func loadInitial() async {
        let chat = store.state.chats[chatId]
        lastReadAtOpen = chat?.lastReadInboxMessageId ?? 0
        hadUnreadAtOpen = (chat?.unreadCount ?? 0) > 0
        isOpening = true
        generation += 1
        state.beginLoading()
        do {
            let lastRead = lastReadAtOpen
            if hadUnreadAtOpen, lastRead > 0, try await loadAround(lastRead) {
                // Fenêtre autour du premier non lu.
            } else {
                try await loadLatest()
            }
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isOpening = false
        guard !loadFailed else { return }
        requestMissingReplies()
        if let target = firstUnreadId {
            requestFocus(target, .top)
        } else if let newest = state.newestId {
            requestFocus(newest, .bottom)
        }
    }

    // MARK: - Pagination

    /// À appeler quand un message va s'afficher : charge la suite à l'approche d'un bord.
    func messageAppeared(_ id: Int64) {
        loadCapabilities(id)
        guard !isOpening, let index = state.orderedIds.firstIndex(of: id) else { return }
        if index < Self.prefetchDistance {
            Task { await loadOlder() }
        }
        if index >= state.orderedIds.count - Self.prefetchDistance {
            Task { await loadNewer() }
        }
    }

    func loadOlder() async {
        guard state.isLoaded, !isLoadingOlder, !state.reachedOldest, let oldest = state.oldestId else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        let current = generation
        do {
            var page = try await service.history(chatId: chatId, from: oldest, offset: 0, limit: Self.pageSize)
            if !page.contains(where: { $0.id < oldest }) {
                // TDLib peut renvoyer une page vide le temps d'interroger le serveur : un second
                // essai avant de conclure au début de la conversation.
                page = try await service.history(chatId: chatId, from: oldest, offset: 0, limit: Self.pageSize)
            }
            guard current == generation else { return }
            state.appendOlder(page)
            requestMissingReplies()
        } catch {
            // Nouvel essai au prochain défilement.
        }
    }

    func loadNewer() async {
        guard state.isLoaded, !isLoadingNewer, !state.reachedLatest, let newest = state.newestId else { return }
        isLoadingNewer = true
        defer { isLoadingNewer = false }
        let current = generation
        do {
            let page = try await service.history(
                chatId: chatId,
                from: newest,
                offset: -(Self.pageSize - 1),
                limit: Self.pageSize
            )
            guard current == generation else { return }
            state.appendNewer(page, lastMessageId: store.state.chats[chatId]?.lastMessage?.id)
            requestMissingReplies()
        } catch {
            // Nouvel essai au prochain défilement.
        }
    }

    /// Messages visibles à l'écran : les messages reçus sont signalés vus une fois (lecture).
    func messagesVisible(_ ids: [Int64]) {
        guard isOpen else { return }
        let fresh = ids.filter { id in
            guard let message = state.messages[id], !message.isOutgoing else { return false }
            return viewedIds.insert(id).inserted
        }
        guard !fresh.isEmpty else { return }
        let service = service
        let chatId = chatId
        Task { try? await service.viewMessages(chatId: chatId, ids: fresh.sorted()) }
    }

    // MARK: - Sauts

    /// « Aller au premier message non lu » : charge la fenêtre autour si besoin, puis y place
    /// le focus.
    func showFirstUnread() async {
        if firstUnreadId == nil, hadUnreadAtOpen, lastReadAtOpen > 0 {
            let lastRead = lastReadAtOpen
            let loaded = await replaceWindow {
                if try await self.loadAround(lastRead) == false {
                    try await self.loadLatest()
                }
            }
            guard loaded else { return }
        }
        if let id = firstUnreadId {
            requestFocus(id, .top)
        } else {
            announce("Aucun message non lu.")
        }
    }

    /// « Aller au dernier message » ; `focus` à faux pour seulement recharger la fin (envoi).
    func showLatest(focus: Bool = true) async {
        if !state.reachedLatest {
            let loaded = await replaceWindow { try await self.loadLatest() }
            guard loaded else { return }
        }
        if focus, let newest = state.newestId {
            requestFocus(newest, .bottom)
        }
    }

    // MARK: - Envoi

    /// Envoie le brouillon. « Message envoyé. » est annoncé quand Telegram l'accepte ; en cas
    /// d'échec, la raison est annoncée et le texte remis dans le champ. Un brouillon vide est
    /// signalé (le bouton est alors estompé, mais l'envoi pourra venir d'ailleurs : Magic Tap).
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            announce("Saisissez d'abord un message.")
            return
        }
        guard !isSending else { return }
        if let editing {
            saveEdit(text, messageId: editing)
            return
        }
        // Réponse à un message toujours présent (il a pu être supprimé entre-temps).
        let replyTo = replyingTo.flatMap { state.message($0) != nil ? $0 : nil }
        isSending = true
        draft = ""
        replyingTo = nil
        Task {
            do {
                if !state.reachedLatest {
                    await showLatest(focus: false)
                }
                let temporaryId = try await service.sendText(text, chatId: chatId, replyTo: replyTo)
                track(temporaryId)
                scrollToBottomRequest += 1
            } catch {
                if draft.isEmpty {
                    draft = text
                    replyingTo = replyTo
                }
                announce(ConversationLabels.sendFailure(error))
            }
            isSending = false
        }
    }

    /// Magic Tap (double toucher à deux doigts) : envoie le brouillon s'il y en a un.
    /// (Lot 5 : lecture / pause du vocal en cours d'abord.)
    func magicTap() {
        if canSend {
            send()
        } else {
            announce(MessageActionLabels.nothingToSend)
        }
    }

    // MARK: - Actions sur les messages

    /// Réactions possibles : pas dans une conversation secrète ni dans les Messages enregistrés.
    var canReact: Bool {
        let list = store.state
        guard let chat = list.chats[chatId] else { return false }
        if case .secret = chat.kind { return false }
        return !list.isSavedMessages(chat)
    }

    /// Actions proposées pour un message (actions personnalisées VoiceOver, menu contextuel).
    func actions(for row: MessageRowModel) -> [MessageAction] {
        MessageActionLabels.actions(for: row, capabilities: capabilities[row.id], canReact: canReact)
    }

    /// Vrai pour un message reçu après le dernier lu à l'ouverture (rotor « Messages non lus »).
    func isUnreadAtOpen(_ row: MessageRowModel) -> Bool {
        hadUnreadAtOpen && !row.isOutgoing && row.id > lastReadAtOpen
    }

    /// Exécute une action ; celles qui demandent un choix ouvrent d'abord une feuille ou une
    /// alerte. Le résultat (ou l'erreur) est annoncé ; la liste suit les changements de TDLib.
    func perform(_ action: MessageAction, on row: MessageRowModel) {
        let chatId = chatId
        let messageId = row.id
        switch action {
        case .reply:
            startReply(to: row)
        case .react:
            openReactions(for: row)
        case .copy:
            guard row.canCopy, let text = MessageActionLabels.copyableText(row.content) else { return }
            copyHandler(text)
            announce(MessageActionLabels.copied)
        case .forward:
            forwardRequest = row
        case .edit:
            startEditing(row)
        case .pin, .unpin:
            let isPinned = action == .pin
            runAction(success: isPinned ? MessageActionLabels.pinned : MessageActionLabels.unpinned) {
                try await $0.setMessagePinned(chatId: chatId, messageId: messageId, isPinned)
            }
        case .openLink(let url):
            open(url)
        case .resend:
            resend(messageId)
        case .delete:
            deletionRequest = row
        }
    }

    /// Ouvre un lien : directement pour le web, Telegram et le courriel ; après confirmation
    /// (destination complète affichée) pour une autre app.
    func open(_ url: URL) {
        if MessageTextTools.requiresConfirmation(url) {
            linkConfirmation = url
        } else {
            linkToOpen = url
        }
    }

    /// Ouverture confirmée dans l'alerte.
    func confirmLink(_ url: URL) {
        linkConfirmation = nil
        linkToOpen = url
    }

    /// À appeler par la vue une fois le lien transmis au système.
    func linkOpened() {
        linkToOpen = nil
    }

    /// Bandeau au-dessus du champ pendant une réponse ou une modification.
    struct ComposerContext: Equatable {
        /// « Réponse à Paul Martin », « Modification du message » ; aussi libellé du champ.
        var title: String
        /// Extrait du message concerné.
        var excerpt: String
        var cancelLabel: String
        var isEditing: Bool
    }

    var composerContext: ComposerContext? {
        let list = store.state
        if let editing, let message = state.message(editing) {
            return ComposerContext(
                title: MessageActionLabels.editContext,
                excerpt: ConversationLabels.excerpt(MessageLabels.content(message.body.content)),
                cancelLabel: MessageActionLabels.cancelEdit,
                isEditing: true
            )
        }
        guard let replyingTo, let message = state.message(replyingTo), let chat = list.chats[chatId] else {
            return nil
        }
        let author: ReplyLine.Author
        if message.isOutgoing && !list.isSavedMessages(chat) {
            author = .me
        } else if let name = list.authorName(of: message.sender, signature: message.authorSignature) {
            author = .named(name)
        } else {
            author = .unknown
        }
        return ComposerContext(
            title: MessageActionLabels.replyContext(author),
            excerpt: ConversationLabels.excerpt(MessageLabels.content(message.body.content)),
            cancelLabel: MessageActionLabels.cancelReply,
            isEditing: false
        )
    }

    /// Libellé du champ de saisie : « Message », ou le contexte (« Réponse à Paul Martin »).
    var composerFieldLabel: String {
        composerContext?.title ?? "Message"
    }

    /// Annule une réponse ou une modification en cours (geste Escape, bouton du bandeau).
    /// Renvoie faux s'il n'y avait rien à annuler (Escape fait alors revenir à la liste).
    @discardableResult
    func cancelComposerMode() -> Bool {
        if editing != nil {
            editing = nil
            draft = draftBeforeEdit
            draftBeforeEdit = ""
            announce(MessageActionLabels.editCancelled)
            return true
        }
        if replyingTo != nil {
            replyingTo = nil
            announce(MessageActionLabels.replyCancelled)
            return true
        }
        return false
    }

    /// Choix d'une réaction dans la feuille : l'ajoute, ou la retire si elle était choisie.
    func toggleReaction(_ kind: ReactionKind, on row: MessageRowModel) {
        let add = !row.reactions.contains { $0.kind == kind && $0.isChosen }
        let chatId = chatId
        let messageId = row.id
        reactionRequest = nil
        runAction(success: MessageActionLabels.reaction(kind, added: add)) {
            try await $0.setReaction(kind, chatId: chatId, messageId: messageId, isChosen: add)
        }
    }

    /// Conversations proposées pour un transfert : liste principale, sans les conversations
    /// secrètes (Telegram n'y transfère pas).
    var forwardTargets: [ChatRowModel] {
        let list = store.state
        return list.chats(in: .main)
            .filter { if case .secret = $0.kind { return false } else { return true } }
            .map { list.row(for: $0, in: .main) }
    }

    func forward(_ row: MessageRowModel, to target: ChatRowModel) {
        let chatId = chatId
        let messageId = row.id
        let targetId = target.id
        forwardRequest = nil
        runAction(success: MessageActionLabels.forwarded(to: target.title)) {
            try await $0.forwardMessages([messageId], from: chatId, to: targetId)
        }
    }

    /// Textes de l'alerte de suppression, selon ce que Telegram permet pour ce message.
    func deletionDialog(for row: MessageRowModel) -> MessageDeletionDialog {
        let list = store.state
        let chat = list.chats[chatId]
        return MessageActionLabels.deletionDialog(
            capabilities: capabilities[row.id] ?? MessageCapabilities(canBeDeletedOnlyForSelf: true),
            chatTitle: title,
            isPrivateChat: chat?.kind.peerUserId != nil,
            isSavedMessages: chat.map { list.isSavedMessages($0) } ?? false
        )
    }

    func confirmDeletion(of row: MessageRowModel, forEveryone: Bool) {
        let chatId = chatId
        let messageId = row.id
        deletionRequest = nil
        if replyingTo == messageId { replyingTo = nil }
        if editing == messageId { cancelComposerMode() }
        runAction(success: MessageActionLabels.deleted) {
            try await $0.deleteMessages(chatId: chatId, ids: [messageId], forEveryone: forEveryone)
        }
    }

    private func startReply(to row: MessageRowModel) {
        if editing != nil {
            editing = nil
            draft = draftBeforeEdit
            draftBeforeEdit = ""
        }
        replyingTo = row.id
        composerFocusRequest += 1
    }

    private func startEditing(_ row: MessageRowModel) {
        guard case .text(let text) = row.content else { return }
        if editing == nil {
            draftBeforeEdit = draft
        }
        replyingTo = nil
        editing = row.id
        draft = text
        composerFocusRequest += 1
    }

    private func saveEdit(_ text: String, messageId: Int64) {
        let chatId = chatId
        let service = service
        isSending = true
        editing = nil
        draft = draftBeforeEdit
        draftBeforeEdit = ""
        Task {
            do {
                try await service.editText(text, chatId: chatId, messageId: messageId)
                announce(MessageActionLabels.edited)
            } catch {
                // Le texte modifié revient dans le champ, toujours en modification.
                draftBeforeEdit = draft
                editing = messageId
                draft = text
                announce(MessageActionLabels.error(error))
            }
            isSending = false
        }
    }

    private func openReactions(for row: MessageRowModel) {
        let chatId = chatId
        let messageId = row.id
        let service = service
        reactionChoices = nil
        reactionRequest = row
        Task {
            let choices = (try? await service.availableReactions(chatId: chatId, messageId: messageId)) ?? []
            guard reactionRequest?.id == messageId else { return }
            reactionChoices = choices
        }
    }

    private func resend(_ messageId: Int64) {
        let chatId = chatId
        let service = service
        Task {
            do {
                let newIds = try await service.resendMessages(chatId: chatId, ids: [messageId])
                announce(MessageActionLabels.resending)
                for id in newIds {
                    track(id)
                }
            } catch {
                announce(MessageActionLabels.error(error))
            }
        }
    }

    /// Lance une opération sur le service et annonce son résultat ou son erreur.
    private func runAction(
        success: String,
        _ operation: @escaping @Sendable (any ConversationService) async throws -> Void
    ) {
        let service = service
        Task {
            do {
                try await operation(service)
                announce(success)
            } catch {
                announce(MessageActionLabels.error(error))
            }
        }
    }

    /// Propriétés Telegram d'un message affiché (hors ligne), une seule fois par message.
    private func loadCapabilities(_ id: Int64) {
        guard capabilities[id] == nil,
              let message = state.messages[id], message.delivery == .sent,
              requestedCapabilities.insert(id).inserted else { return }
        let chatId = chatId
        let service = service
        Task {
            if let loaded = try? await service.capabilities(chatId: chatId, messageId: id) {
                capabilities[id] = loaded
            }
        }
    }

    // MARK: - Privé

    private func handle(_ event: MessageEvent) {
        switch event {
        case .sendSucceeded(_, let oldId):
            settle(oldId, .sent)
        case .sendFailed(_, let oldId, let error):
            settle(oldId, .failed(error))
        default:
            break
        }
        state.apply(event)
        if case .new = event {
            requestMissingReplies()
        }
    }

    private func track(_ temporaryId: Int64) {
        if let outcome = earlyOutcomes.removeValue(forKey: temporaryId) {
            announce(outcome)
        } else {
            pendingSentIds.insert(temporaryId)
        }
    }

    private func settle(_ temporaryId: Int64, _ outcome: SendOutcome) {
        if pendingSentIds.remove(temporaryId) != nil {
            announce(outcome)
        } else {
            earlyOutcomes[temporaryId] = outcome
        }
    }

    private func announce(_ outcome: SendOutcome) {
        switch outcome {
        case .sent: announce(ConversationLabels.messageSent)
        case .failed(let error): announce(ConversationLabels.sendFailure(error))
        }
    }

    private func announce(_ text: String) {
        lastAnnouncement = text
        Announcer.announce(text)
    }

    private func requestFocus(_ id: Int64, _ position: MessageFocusRequest.Position) {
        focusSerial += 1
        focusRequest = MessageFocusRequest(messageId: id, position: position, serial: focusSerial)
    }

    /// Derniers messages, complétés vers le haut jusqu'à `initialMinimum`.
    private func loadLatest() async throws {
        var page = try await service.history(chatId: chatId, from: 0, offset: 0, limit: Self.pageSize)
        var attempts = 0
        while page.count < Self.initialMinimum, attempts < 3, let oldest = page.map(\.id).min() {
            attempts += 1
            let older = try await service.history(chatId: chatId, from: oldest, offset: 0, limit: Self.pageSize)
                .filter { $0.id < oldest }
            if older.isEmpty { break }
            page += older
        }
        state.reset(with: page, isLatest: true)
    }

    /// Fenêtre autour de `messageId` (et des messages qui le suivent) ; `false` si TDLib ne
    /// renvoie rien (message supprimé…).
    private func loadAround(_ messageId: Int64) async throws -> Bool {
        let page = try await service.history(
            chatId: chatId,
            from: messageId,
            offset: -Self.newerAroundUnread,
            limit: Self.pageSize
        )
        guard !page.isEmpty else { return false }
        let lastId = store.state.chats[chatId]?.lastMessage?.id
        let isLatest = lastId.map { last in page.contains { $0.id >= last } } ?? false
        state.reset(with: page, isLatest: isLatest)
        return true
    }

    /// Remplace la fenêtre par `load` ; en cas d'échec, l'ancienne fenêtre est rétablie et
    /// l'échec annoncé.
    private func replaceWindow(_ load: () async throws -> Void) async -> Bool {
        generation += 1
        let previous = state.orderedMessages
        let wasLatest = state.reachedLatest
        state.beginLoading()
        do {
            try await load()
            requestMissingReplies()
            return true
        } catch {
            state.reset(with: previous, isLatest: wasLatest)
            announce("Impossible de charger les messages. Vérifiez votre connexion.")
            return false
        }
    }

    /// Charge les messages cités par des réponses et absents de la fenêtre.
    private func requestMissingReplies() {
        for message in state.orderedMessages {
            guard let reply = message.replyTo,
                  reply.origin == nil,
                  reply.chatId == chatId,
                  reply.messageId != 0,
                  state.message(reply.messageId) == nil,
                  !state.deletedIds.contains(reply.messageId),
                  requestedReplyIds.insert(reply.messageId).inserted else { continue }
            let citedId = reply.messageId
            let service = service
            let chatId = chatId
            Task {
                if let cited = try? await service.message(chatId: chatId, id: citedId) {
                    state.addReferenced(cited)
                }
            }
        }
    }
}
