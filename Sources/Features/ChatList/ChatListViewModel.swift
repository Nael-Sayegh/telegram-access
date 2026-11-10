import Foundation
import Observation

/// Liste de conversations (principale ou archives) : pagination, actions sur les conversations
/// et état de connexion. Les filtres arrivent au lot 4.
@MainActor
@Observable
final class ChatListViewModel {
    let list: ChatListKind
    let store: ChatStore

    private(set) var isLoading = false
    /// Vrai quand TDLib a signalé la fin de la liste.
    private(set) var isFullyLoaded = false
    /// Vrai si le dernier chargement a échoué (réseau…) ; un nouvel essai a lieu au défilement.
    private(set) var loadFailed = false
    /// Conversation dont la suppression attend confirmation (dialogue affiché).
    var deletionRequest: ChatRowModel?
    /// Dernière annonce faite (succès ou erreur d'une action), pour les tests.
    private(set) var lastAnnouncement: String?

    private let service: any ChatListService
    /// Conversations dont une action est en cours : une seule à la fois par conversation.
    private var busyChatIds: Set<Int64> = []
    private var connectionTask: Task<Void, Never>?
    /// Vrai si la perte de connexion a été annoncée : son rétablissement le sera aussi.
    private var announcedDisconnection = false

    /// Conversations chargées par page (TDLib peut en renvoyer moins).
    static let pageSize = 30
    /// Nombre de dernières lignes dont l'apparition déclenche le chargement suivant.
    static let prefetchDistance = 10
    /// Délai avant d'annoncer une perte de connexion (évite les annonces pour une coupure brève).
    static let disconnectionAnnouncementDelay: Duration = .seconds(3)

    init(list: ChatListKind, store: ChatStore, service: any ChatListService) {
        self.list = list
        self.store = store
        self.service = service
    }

    var rows: [ChatRowModel] {
        let state = store.state
        return state.chats(in: list).map { state.row(for: $0, in: list) }
    }

    /// Texte d'état de connexion à afficher, `nil` une fois connecté.
    var connectionText: String? {
        ChatListLabels.connection(store.state.connection)
    }

    // MARK: - Pagination

    func loadMore() async {
        guard !isLoading, !isFullyLoaded else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let hasMore = try await service.loadChats(list, limit: Self.pageSize)
            isFullyLoaded = !hasMore
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// À appeler à l'apparition d'une ligne : charge la suite à l'approche de la fin.
    func rowAppeared(_ chatId: Int64) {
        let ids = store.state.orderedIds[list] ?? []
        guard let index = ids.firstIndex(of: chatId), index >= ids.count - Self.prefetchDistance else { return }
        Task { await loadMore() }
    }

    // MARK: - Actions

    func actions(for row: ChatRowModel) -> [ChatRowAction] {
        ChatActionLabels.actions(for: row, in: list)
    }

    /// Exécute une action ; la suppression ouvre d'abord le dialogue de confirmation.
    /// Le résultat (ou l'erreur) est annoncé ; la liste se met à jour par les updates TDLib.
    func perform(_ action: ChatRowAction, on row: ChatRowModel) {
        if action == .delete {
            deletionRequest = row
            return
        }
        guard let chat = store.state.chats[row.id] else { return }
        let list = list
        run(action, on: row) { service in
            switch action {
            case .markAsRead: try await service.markAsRead(chat)
            case .markAsUnread: try await service.setMarkedAsUnread(chatId: chat.id, true)
            case .pin: try await service.setPinned(chatId: chat.id, in: list, true)
            case .unpin: try await service.setPinned(chatId: chat.id, in: list, false)
            case .mute: try await service.setMuted(chatId: chat.id, true)
            case .unmute: try await service.setMuted(chatId: chat.id, false)
            case .archive: try await service.moveChat(chatId: chat.id, to: .archive)
            case .unarchive: try await service.moveChat(chatId: chat.id, to: .main)
            case .delete: break
            }
        }
    }

    /// Suppression confirmée dans le dialogue.
    func confirmDeletion(of row: ChatRowModel, forEveryone: Bool) {
        deletionRequest = nil
        guard let chat = store.state.chats[row.id] else { return }
        run(.delete, on: row) { try await $0.deleteChat(chat, forEveryone: forEveryone) }
    }

    private func run(
        _ action: ChatRowAction,
        on row: ChatRowModel,
        _ operation: @escaping @Sendable (any ChatListService) async throws -> Void
    ) {
        guard !busyChatIds.contains(row.id) else { return }
        busyChatIds.insert(row.id)
        let service = service
        Task {
            do {
                try await operation(service)
                announce(ChatActionLabels.confirmation(action, for: row))
            } catch {
                announce(ChatActionLabels.error(error))
            }
            busyChatIds.remove(row.id)
        }
    }

    private func announce(_ text: String) {
        lastAnnouncement = text
        Announcer.announce(text)
    }

    // MARK: - Connexion

    /// Annonce une perte de connexion qui dure, puis son rétablissement, sans bavardage :
    /// « Connexion… » et « Mise à jour… » au démarrage ne sont pas annoncés.
    func connectionChanged(_ status: ConnectionStatus) {
        connectionTask?.cancel()
        switch status {
        case .ready, .updating:
            if announcedDisconnection {
                announcedDisconnection = false
                Announcer.announceQueued("Connecté.")
            }
        case .waitingForNetwork, .connectingToProxy, .connecting:
            guard !announcedDisconnection, let text = ChatListLabels.connection(status) else { return }
            connectionTask = Task { [weak self] in
                try? await Task.sleep(for: Self.disconnectionAnnouncementDelay)
                guard !Task.isCancelled, let self else { return }
                self.announcedDisconnection = true
                Announcer.announceQueued(text)
            }
        }
    }
}
