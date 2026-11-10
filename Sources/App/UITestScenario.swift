#if DEBUG
import Foundation

/// Écrans de connexion affichés sans TDLib ni réseau, pour les audits d'accessibilité des
/// tests UI. Activé par l'argument de lancement `-uiTestAuthStep <étape>`.
/// Compilé uniquement en Debug : absent des builds distribués.
enum UITestScenario: String, CaseIterable {
    case phoneNumber
    case code
    case emailAddress
    case emailCode
    case password
    case registration
    case ready

    static let launchArgument = "-uiTestAuthStep"

    /// Configuration factice : le service de test n'utilise ni `api_id` ni `api_hash`.
    static let config = AppConfig(apiId: 1, apiHash: "ui-tests", applicationVersion: "0")

    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> UITestScenario? {
        guard let index = arguments.firstIndex(of: launchArgument), arguments.indices.contains(index + 1) else {
            return nil
        }
        return UITestScenario(rawValue: arguments[index + 1])
    }

    var step: AuthStep {
        switch self {
        case .phoneNumber:
            return .phoneNumber
        case .code:
            return .code(CodeInfo(
                phoneNumber: "+33612345678",
                delivery: .telegramApp,
                codeLength: 5,
                nextDelivery: .sms,
                resendTimeout: 60
            ))
        case .emailAddress:
            return .emailAddress
        case .emailCode:
            return .emailCode(pattern: "a***@exemple.fr", length: 6)
        case .password:
            return .password(PasswordInfo(hint: "Indice de test", hasRecoveryEmail: true, recoveryEmailPattern: ""))
        case .registration:
            return .registration(RegistrationTerms(
                text: "Premier paragraphe des conditions.\nDeuxième paragraphe des conditions.",
                minimumAge: 16,
                requiresExplicitAcceptance: false
            ))
        case .ready:
            return .ready
        }
    }
}

/// Service factice : envoie l'étape demandée et accepte toutes les actions, sans réseau.
/// Une fois connecté (`ready`), fournit les conversations de `UITestChatData`.
actor UITestAuthService: TelegramService {
    nonisolated let steps: AsyncStream<AuthStep>
    nonisolated let chatEvents: AsyncStream<ChatListEvent>
    private let continuation: AsyncStream<AuthStep>.Continuation
    private let scenario: UITestScenario

    init(scenario: UITestScenario) {
        let stream = AsyncStream.makeStream(of: AuthStep.self)
        self.steps = stream.stream
        self.continuation = stream.continuation
        let chatStream = AsyncStream.makeStream(of: ChatListEvent.self)
        self.chatEvents = chatStream.stream
        self.scenario = scenario
        // Mis en mémoire tampon par le flux jusqu'à ce que le store le lise.
        if scenario == .ready {
            UITestChatData.events().forEach { chatStream.continuation.yield($0) }
        }
    }

    func start() {
        continuation.yield(scenario.step)
    }

    func retryInitialization() {}
    func setPhoneNumber(_ phoneNumber: String) {}
    func resendCode() {}
    func checkCode(_ code: String) {}
    func setEmailAddress(_ email: String) {}
    func checkEmailCode(_ code: String) {}
    func checkPassword(_ password: String) {}
    func requestPasswordRecovery() {}
    func recoverPassword(code: String, newPassword: String, newHint: String) {}
    func register(firstName: String, lastName: String) {}
    func logOut() {}

    func countries() -> [Country] {
        [
            Country(id: "BE", name: "Belgique", callingCode: "32", flag: "🇧🇪"),
            Country(id: "FR", name: "France", callingCode: "33", flag: "🇫🇷"),
            Country(id: "CH", name: "Suisse", callingCode: "41", flag: "🇨🇭"),
        ]
    }

    func estimatedCountryCode() -> String {
        "FR"
    }

    func loadChats(_ list: ChatListKind, limit: Int) -> Bool { false }
    func markAsRead(_ chat: ChatSummary) {}
    func setMarkedAsUnread(chatId: Int64, _ isMarkedAsUnread: Bool) {}
    func setPinned(chatId: Int64, in list: ChatListKind, _ isPinned: Bool) {}
    func setMuted(chatId: Int64, _ isMuted: Bool) {}
    func moveChat(chatId: Int64, to list: ChatListKind) {}
    func deleteChat(_ chat: ChatSummary, forEveryone: Bool) {}
    func searchChats(_ query: String, limit: Int) -> [Int64] {
        UITestChatData.chats.filter { $0.title.localizedCaseInsensitiveContains(query) }.map(\.id)
    }

    func searchPublicChats(_ query: String) -> [Int64] { [] }

    func searchMessages(_ query: String, offset: String, limit: Int) -> MessageSearchPage {
        let results = UITestChatData.chats.compactMap { chat -> MessageSearchResult? in
            guard let message = chat.lastMessage, case .text(let text) = message.content,
                  text.localizedCaseInsensitiveContains(query) else { return nil }
            return MessageSearchResult(chatId: chat.id, message: message)
        }
        return MessageSearchPage(results: results, nextOffset: "")
    }
}

/// Conversations factices des tests UI : un exemple de chaque cas de la liste (non lus,
/// mention, épinglée, sourdine, brouillon, groupe, chaîne, secrète, Messages enregistrés,
/// archive). Textes courts : rien n'est coupé à la taille de texte par défaut.
enum UITestChatData {
    static let myUserId: Int64 = 42
    static let marie: Int64 = 7
    static let paul: Int64 = 5

    /// Aujourd'hui à 9 h 05, pour un libellé prévisible (« 9 h 05 »).
    static var todayMorning: Date {
        Calendar.current.date(bySettingHour: 9, minute: 5, second: 0, of: Date()) ?? Date()
    }

    static var yesterday: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: todayMorning) ?? Date()
    }

    static var chats: [ChatSummary] {
        [
            chat(42, kind: .user(userId: myUserId), title: "Moi", order: 100, pinned: true,
                 message: message(1, "Liste de courses", sender: myUserId, outgoing: true)),
            chat(1, kind: .user(userId: marie), title: "Marie Dupont", order: 90, unread: 3,
                 message: message(2, "On se voit demain ?", sender: marie)),
            chat(-100, kind: .supergroup, title: "Famille", order: 80, unread: 1, mentions: 1,
                 message: message(3, "Salut à tous", sender: paul, date: yesterday)),
            chat(-200, kind: .channel, title: "Infos", order: 70, muted: true,
                 message: message(4, "Nouvelle version", sender: -200, date: yesterday)),
            chat(2, kind: .secret(secretChatId: 3, userId: marie), title: "Marie Dupont", order: 60,
                 markedUnread: true, message: message(5, "D'accord", sender: myUserId, outgoing: true),
                 lastReadOutbox: 5),
            chat(3, kind: .user(userId: paul), title: "Paul Martin", order: 50, draft: .text("À finir"),
                 message: message(6, "Merci", sender: paul, date: yesterday)),
            chat(4, kind: .basicGroup, title: "Ancien groupe", archiveOrder: 10, unread: 1,
                 message: message(7, "Au revoir", sender: paul, date: yesterday)),
        ]
    }

    static func events() -> [ChatListEvent] {
        var events: [ChatListEvent] = [
            .myUserId(myUserId),
            .connection(.ready),
            .user(id: myUserId, name: UserName(firstName: "Moi", lastName: "", isDeleted: false)),
            .user(id: marie, name: UserName(firstName: "Marie", lastName: "Dupont", isDeleted: false)),
            .user(id: paul, name: UserName(firstName: "Paul", lastName: "Martin", isDeleted: false)),
            .scopeMute(scope: .privateChats, muteFor: 0),
            .scopeMute(scope: .groups, muteFor: 0),
            .scopeMute(scope: .channels, muteFor: 0),
            .listCounts(list: .archive, total: 1, unread: 1),
        ]
        events += chats.map { .newChat($0) }
        return events
    }

    private static func message(
        _ id: Int64,
        _ text: String,
        sender: Int64,
        outgoing: Bool = false,
        date: Date? = nil
    ) -> MessagePreview {
        MessagePreview(
            id: id,
            sender: sender < 0 ? .chat(sender) : .user(sender),
            isOutgoing: outgoing,
            date: date ?? todayMorning,
            content: .text(text),
            delivery: .sent
        )
    }

    private static func chat(
        _ id: Int64,
        kind: ChatKind,
        title: String,
        order: Int64? = nil,
        archiveOrder: Int64? = nil,
        pinned: Bool = false,
        unread: Int = 0,
        mentions: Int = 0,
        markedUnread: Bool = false,
        muted: Bool = false,
        draft: DraftSummary? = nil,
        message: MessagePreview,
        lastReadOutbox: Int64 = 0
    ) -> ChatSummary {
        var positions: [ChatListPosition] = []
        if let order { positions.append(ChatListPosition(list: .main, order: order, isPinned: pinned)) }
        if let archiveOrder { positions.append(ChatListPosition(list: .archive, order: archiveOrder, isPinned: false)) }
        return ChatSummary(
            id: id,
            kind: kind,
            title: title,
            positions: positions,
            lastMessage: message,
            unreadCount: unread,
            unreadMentionCount: mentions,
            unreadReactionCount: 0,
            isMarkedAsUnread: markedUnread,
            lastReadInboxMessageId: 0,
            lastReadOutboxMessageId: lastReadOutbox,
            muteSetting: ChatMuteSetting(usesDefault: !muted, muteFor: muted ? Int(Int32.max) : 0),
            draft: draft,
            canBeDeletedOnlyForSelf: true,
            canBeDeletedForAllUsers: kind == .user(userId: marie)
        )
    }
}
#endif
