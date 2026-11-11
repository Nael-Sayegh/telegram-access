import Foundation

/// Messages d'une conversation, reconstruits à partir de l'historique et des changements
/// TDLib. Réducteur pur, sans dépendance à TDLib ni à l'interface : testé unitairement.
///
/// La conversation affichée est une **fenêtre contiguë** de messages triés par identifiant
/// (ordre chronologique ; les identifiants provisoires des messages en cours d'envoi suivent le
/// dernier message envoyé). Elle s'étend vers le haut (plus anciens) et, après un saut au
/// premier non lu, vers le bas. Un nouveau message ne s'y ajoute que si elle atteint le dernier
/// message : sinon il apparaîtra en chargeant la suite, sans trou dans l'historique.
struct ConversationState {
    let chatId: Int64
    private(set) var messages: [Int64: ChatMessage] = [:]
    /// Identifiants de la fenêtre, du plus ancien au plus récent.
    private(set) var orderedIds: [Int64] = []
    /// Vrai quand le premier message de la conversation est chargé.
    private(set) var reachedOldest = false
    /// Vrai quand la fenêtre va jusqu'au dernier message : les nouveaux messages s'y ajoutent.
    private(set) var reachedLatest = false
    /// Messages cités hors de la fenêtre (réponses), chargés à part.
    private(set) var referenced: [Int64: ChatMessage] = [:]
    /// Messages supprimés pendant l'affichage (une réponse à l'un d'eux le signale).
    private(set) var deletedIds: Set<Int64> = []
    /// Activité en cours des participants (« écrit… »).
    private(set) var activities: [MessageSenderRef: ChatActivity] = [:]
    /// Faux pendant un chargement qui va remplacer la fenêtre (ouverture, saut) : les
    /// changements reçus entre-temps sont mis de côté puis appliqués à la nouvelle fenêtre,
    /// pour ne perdre aucun message arrivé pendant la requête.
    private(set) var isLoaded = false
    private var pendingEvents: [MessageEvent] = []

    init(chatId: Int64) {
        self.chatId = chatId
    }

    // MARK: - Lecture

    var oldestId: Int64? { orderedIds.first }
    var newestId: Int64? { orderedIds.last }

    /// Messages de la fenêtre, du plus ancien au plus récent.
    var orderedMessages: [ChatMessage] {
        orderedIds.compactMap { messages[$0] }
    }

    /// Message de la fenêtre ou message cité chargé à part.
    func message(_ id: Int64) -> ChatMessage? {
        messages[id] ?? referenced[id]
    }

    // MARK: - Historique

    /// À appeler avant de demander une page qui remplacera la fenêtre (`reset`) : les
    /// changements reçus d'ici là seront appliqués après le remplacement.
    mutating func beginLoading() {
        isLoaded = false
    }

    /// Remplace la fenêtre : ouverture, saut au premier non lu ou au dernier message.
    /// `isLatest` : la page va jusqu'au dernier message de la conversation.
    mutating func reset(with page: [ChatMessage], isLatest: Bool) {
        messages = [:]
        orderedIds = []
        reachedLatest = isLatest
        reachedOldest = page.isEmpty
        merge(page)
        isLoaded = true
        let pending = pendingEvents
        pendingEvents = []
        for event in pending {
            apply(event)
        }
    }

    /// Ajoute une page de messages plus anciens. Une page sans message plus ancien que la
    /// fenêtre marque le début de la conversation.
    mutating func appendOlder(_ page: [ChatMessage]) {
        let oldest = oldestId ?? .max
        let older = page.filter { $0.chatId == chatId && $0.id < oldest }
        if older.isEmpty {
            reachedOldest = true
        }
        merge(older)
    }

    /// Ajoute une page de messages plus récents. Une page sans message plus récent, ou qui
    /// atteint `lastMessageId` (dernier message connu de la conversation), marque la fin.
    mutating func appendNewer(_ page: [ChatMessage], lastMessageId: Int64?) {
        let newest = newestId ?? .min
        let newer = page.filter { $0.chatId == chatId && $0.id > newest }
        merge(newer)
        if newer.isEmpty {
            reachedLatest = true
        } else if let lastMessageId, let newestId, newestId >= lastMessageId {
            reachedLatest = true
        }
    }

    /// Message cité absent de la fenêtre, chargé à part.
    mutating func addReferenced(_ message: ChatMessage) {
        referenced[message.id] = message
    }

    // MARK: - Changements

    /// Applique un changement ; ceux d'une autre conversation sont ignorés. Pendant un
    /// chargement (`beginLoading`), le changement est mis de côté jusqu'au `reset`.
    mutating func apply(_ event: MessageEvent) {
        if let eventChatId = event.chatId, eventChatId != chatId { return }
        guard isLoaded else {
            pendingEvents.append(event)
            return
        }
        switch event {
        case .new(let message):
            insertIfInWindow(message)
        case .sendSucceeded(let message, let oldId), .sendFailed(let message, let oldId, _):
            let wasShown = messages[oldId] != nil
            remove(oldId)
            if wasShown {
                insertSorted(message)
            } else {
                insertIfInWindow(message)
            }
        case .content(_, let messageId, let body):
            update(messageId) { $0.body = body }
        case .edited(_, let messageId, let editDate):
            update(messageId) { $0.editDate = editDate }
        case .pinned(_, let messageId, let isPinned):
            update(messageId) { $0.isPinned = isPinned }
        case .reactions(_, let messageId, let reactions):
            update(messageId) { $0.reactions = reactions }
        case .deleted(_, let messageIds):
            for id in messageIds {
                remove(id)
                referenced[id] = nil
            }
            deletedIds.formUnion(messageIds)
        case .opened(_, let messageId):
            update(messageId) { $0.body.media?.isListened = true }
        case .activity(_, let sender, let activity):
            activities[sender] = activity
        case .file(let file):
            updateFile(file)
        }
    }

    // MARK: - Privé

    /// Ajoute des messages à la fenêtre (doublons remplacés) et rétablit l'ordre.
    private mutating func merge(_ page: [ChatMessage]) {
        let fresh = page.filter { $0.chatId == chatId }
        guard !fresh.isEmpty else { return }
        for message in fresh {
            messages[message.id] = message
            referenced[message.id] = nil
        }
        orderedIds = Array(Set(orderedIds).union(fresh.map(\.id))).sorted()
    }

    /// Ajoute un message s'il tombe dans la fenêtre, ou juste après si elle atteint le dernier
    /// message (juste avant si elle atteint le premier).
    private mutating func insertIfInWindow(_ message: ChatMessage) {
        guard messages[message.id] == nil else {
            messages[message.id] = message
            return
        }
        guard let oldest = oldestId, let newest = newestId else {
            // Fenêtre vide : conversation sans message, ou historique pas encore chargé.
            if reachedLatest { insertSorted(message) }
            return
        }
        if message.id > newest, !reachedLatest { return }
        if message.id < oldest, !reachedOldest { return }
        insertSorted(message)
    }

    private mutating func insertSorted(_ message: ChatMessage) {
        messages[message.id] = message
        referenced[message.id] = nil
        guard !orderedIds.contains(message.id) else { return }
        let index = orderedIds.firstIndex { $0 > message.id } ?? orderedIds.endIndex
        orderedIds.insert(message.id, at: index)
    }

    private mutating func remove(_ id: Int64) {
        guard messages.removeValue(forKey: id) != nil else { return }
        orderedIds.removeAll { $0 == id }
    }

    private mutating func update(_ id: Int64, _ change: (inout ChatMessage) -> Void) {
        if var message = messages[id] {
            change(&message)
            messages[id] = message
        }
        if var message = referenced[id] {
            change(&message)
            referenced[id] = message
        }
    }

    /// Reporte un téléchargement terminé sur les messages qui affichent ce fichier.
    private mutating func updateFile(_ file: FileRef) {
        for (id, message) in messages where message.body.media?.file.id == file.id {
            messages[id]?.body.media?.file = file
        }
        for (id, message) in referenced where message.body.media?.file.id == file.id {
            referenced[id]?.body.media?.file = file
        }
    }
}
