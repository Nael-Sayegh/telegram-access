import Foundation
import Observation

/// Liste de conversations (principale ou archives) : pagination et état de connexion.
/// Les actions sur les conversations arrivent au lot 3, les filtres au lot 4.
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

    private let service: any ChatListService
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
