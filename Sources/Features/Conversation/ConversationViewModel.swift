import Foundation
import Observation

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
        isSending = true
        draft = ""
        Task {
            do {
                if !state.reachedLatest {
                    await showLatest(focus: false)
                }
                let temporaryId = try await service.sendText(text, chatId: chatId, replyTo: nil)
                track(temporaryId)
                scrollToBottomRequest += 1
            } catch {
                if draft.isEmpty {
                    draft = text
                }
                announce(ConversationLabels.sendFailure(error))
            }
            isSending = false
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
