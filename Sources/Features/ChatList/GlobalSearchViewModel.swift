import Foundation
import Observation

/// Message trouvé par la recherche, prêt à afficher et à lire.
struct SearchMessageRow: Identifiable, Equatable {
    /// Unique parmi les résultats : conversation et message.
    var id: String { "\(chatId)-\(messageId)" }
    let chatId: Int64
    let messageId: Int64
    var chatTitle: String
    var line: LastMessageLine
}

/// Ce que porte la recherche.
enum SearchScope: CaseIterable, Hashable {
    /// Texte des messages de toutes les conversations (par défaut).
    case messages
    /// Conversations connues (appareil puis serveur), groupes et chaînes publics.
    case conversations

    var name: String {
        switch self {
        case .messages: return "Messages"
        case .conversations: return "Conversations"
        }
    }

    /// Libellé du champ de recherche (lu par VoiceOver, affiché tant que le champ est vide).
    var prompt: String {
        switch self {
        case .messages: return "Rechercher dans les messages"
        case .conversations: return "Rechercher une conversation"
        }
    }

    func noResult(_ query: String) -> String {
        switch self {
        case .messages: return "Aucun message trouvé pour « \(query) »."
        case .conversations: return "Aucune conversation trouvée pour « \(query) »."
        }
    }
}

/// Recherche globale, dans les messages ou parmi les conversations (`SearchScope`).
@MainActor
@Observable
final class GlobalSearchViewModel {
    /// Texte saisi ; la vue appelle `queryChanged()` à chaque modification.
    var query = ""
    private(set) var scope: SearchScope = .messages

    private(set) var chatIds: [Int64] = []
    private(set) var publicChatIds: [Int64] = []
    private(set) var messages: [SearchMessageRow] = []
    private(set) var isSearching = false
    private(set) var failed = false
    /// Vrai s'il reste des messages à charger.
    private(set) var hasMoreMessages = false
    /// Dernière annonce faite, pour les tests.
    private(set) var lastAnnouncement: String?

    let store: ChatStore
    private let service: any ChatListService
    private var searchTask: Task<Void, Never>?
    private var nextOffset = ""

    static let debounce: Duration = .milliseconds(400)
    static let chatLimit = 50
    static let messagePageSize = 30

    init(store: ChatStore, service: any ChatListService) {
        self.store = store
        self.service = service
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isActive: Bool { !trimmedQuery.isEmpty }

    /// Lignes des conversations trouvées (connues, puis publiques sans doublon).
    var chatRows: [ChatRowModel] { rows(for: chatIds) }

    var publicChatRows: [ChatRowModel] {
        let known = Set(chatIds)
        return rows(for: publicChatIds.filter { !known.contains($0) })
    }

    // MARK: - Recherche

    /// Relance la recherche après une courte pause de frappe (une recherche par mot tapé
    /// serait coûteuse et produirait des annonces en rafale).
    func queryChanged() {
        searchTask?.cancel()
        let text = trimmedQuery
        guard !text.isEmpty else {
            reset()
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.search(text)
        }
    }

    /// Lance la recherche immédiatement (bouton Rechercher du clavier, tests).
    func submit() {
        searchTask?.cancel()
        let text = trimmedQuery
        guard !text.isEmpty else { return }
        isSearching = true
        searchTask = Task { [weak self] in await self?.search(text) }
    }

    /// Change la portée ; une recherche en cours est relancée aussitôt.
    func setScope(_ newScope: SearchScope) {
        guard newScope != scope else { return }
        scope = newScope
        reset()
        submit()
    }

    private func search(_ text: String) async {
        let scope = scope
        switch scope {
        case .messages:
            let page = try? await service.searchMessages(text, offset: "", limit: Self.messagePageSize)
            // Une nouvelle saisie (ou portée) a remplacé cette recherche.
            guard !Task.isCancelled, text == trimmedQuery, scope == self.scope else { return }
            reset()
            failed = page == nil
            messages = (page?.results ?? []).compactMap(makeRow)
            nextOffset = page?.nextOffset ?? ""
            hasMoreMessages = !nextOffset.isEmpty
        case .conversations:
            let service = service
            async let chats = try? service.searchChats(text, limit: Self.chatLimit)
            async let publicChats = try? service.searchPublicChats(text)
            let (foundChats, foundPublic) = await (chats, publicChats)
            guard !Task.isCancelled, text == trimmedQuery, scope == self.scope else { return }
            reset()
            failed = foundChats == nil && foundPublic == nil
            chatIds = foundChats ?? []
            publicChatIds = foundPublic ?? []
        }

        announce(failed
            ? "La recherche a échoué. Vérifiez votre connexion."
            : SearchLabels.summary(
                chats: chatRows.count + publicChatRows.count,
                messages: messages.count,
                hasMore: hasMoreMessages
            ))
    }

    /// Page suivante de messages.
    func loadMoreMessages() async {
        let text = trimmedQuery
        guard scope == .messages, hasMoreMessages, !isSearching, !text.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let page = try await service.searchMessages(text, offset: nextOffset, limit: Self.messagePageSize)
            guard text == trimmedQuery else { return }
            let added = page.results.compactMap(makeRow)
            messages += added
            nextOffset = page.nextOffset
            hasMoreMessages = !page.nextOffset.isEmpty
            announce(SearchLabels.moreMessages(added.count))
        } catch {
            announce("Impossible de charger d'autres messages.")
        }
    }

    // MARK: - Privé

    private func reset() {
        isSearching = false
        failed = false
        chatIds = []
        publicChatIds = []
        messages = []
        nextOffset = ""
        hasMoreMessages = false
    }

    private func rows(for ids: [Int64]) -> [ChatRowModel] {
        let state = store.state
        return ids.compactMap { state.chats[$0] }.map { state.row(for: $0, in: .main) }
    }

    private func makeRow(_ result: MessageSearchResult) -> SearchMessageRow? {
        let state = store.state
        guard let chat = state.chats[result.chatId] else { return nil }
        return SearchMessageRow(
            chatId: chat.id,
            messageId: result.message.id,
            chatTitle: state.displayTitle(of: chat),
            line: state.lastMessageLine(result.message, in: chat)
        )
    }

    private func announce(_ text: String) {
        lastAnnouncement = text
        Announcer.announceQueued(text)
    }
}

/// Textes de la recherche globale. Fonctions pures, testées unitairement.
enum SearchLabels {
    /// « 3 conversations, 12 messages », « 30 messages ou plus », « Aucun résultat. »
    static func summary(chats: Int, messages: Int, hasMore: Bool) -> String {
        guard chats > 0 || messages > 0 else { return "Aucun résultat." }
        var parts: [String] = []
        if chats > 0 {
            parts.append("\(chats) conversation\(chats > 1 ? "s" : "")")
        }
        if messages > 0 {
            parts.append("\(messages) message\(messages > 1 ? "s" : "")\(hasMore ? " ou plus" : "")")
        }
        return parts.joined(separator: ", ") + "."
    }

    /// Annonce après « Charger plus de messages ».
    static func moreMessages(_ count: Int) -> String {
        count == 0 ? "Aucun autre message." : "\(count) message\(count > 1 ? "s" : "") de plus."
    }

    /// Libellé d'un message trouvé : « Famille, Paul : Salut, hier ».
    static func message(_ row: SearchMessageRow, now: Date, calendar: Calendar) -> String {
        let text = ChatListLabels.truncated(row.line.text)
        var parts = [row.chatTitle]
        parts.append(row.line.senderLabel.map { "\($0) : \(text)" } ?? text)
        if let status = row.line.status {
            parts.append(status)
        }
        parts.append(ChatListLabels.spokenTime(row.line.date, now: now, calendar: calendar))
        return parts.joined(separator: ", ")
    }
}
