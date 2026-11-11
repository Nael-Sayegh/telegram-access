import XCTest
@testable import TelegramAccess

/// Service Telegram factice : enregistre les appels (connexion, conversations, messages) et
/// peut simuler une erreur Telegram.
actor FakeAuthService: TelegramService {
    nonisolated let steps: AsyncStream<AuthStep>
    private let continuation: AsyncStream<AuthStep>.Continuation
    nonisolated let chatEvents: AsyncStream<ChatListEvent>
    private let chatContinuation: AsyncStream<ChatListEvent>.Continuation
    nonisolated let messageEvents: AsyncStream<MessageEvent>
    private let messageContinuation: AsyncStream<MessageEvent>.Continuation

    private(set) var phoneNumbers: [String] = []
    private(set) var registrations: [String] = []
    private(set) var recoveries: [String] = []
    private(set) var recoveryRequests = 0
    private(set) var retryCount = 0
    private var nextError: TelegramError?

    init() {
        let stream = AsyncStream.makeStream(of: AuthStep.self)
        steps = stream.stream
        continuation = stream.continuation
        let chatStream = AsyncStream.makeStream(of: ChatListEvent.self)
        chatEvents = chatStream.stream
        chatContinuation = chatStream.continuation
        let messageStream = AsyncStream.makeStream(of: MessageEvent.self)
        messageEvents = messageStream.stream
        messageContinuation = messageStream.continuation
    }

    /// Simule un changement de message reçu de TDLib.
    nonisolated func send(_ event: MessageEvent) {
        messageContinuation.yield(event)
    }

    /// Simule un nouvel état reçu de TDLib.
    nonisolated func send(_ step: AuthStep) {
        continuation.yield(step)
    }

    /// Simule un changement de la liste des conversations reçu de TDLib.
    nonisolated func send(_ event: ChatListEvent) {
        chatContinuation.yield(event)
    }

    func failNextCall(with error: TelegramError) {
        nextError = error
    }

    func start() {}

    func retryInitialization() {
        retryCount += 1
    }

    func setPhoneNumber(_ phoneNumber: String) throws {
        try throwIfNeeded()
        phoneNumbers.append(phoneNumber)
    }

    func resendCode() throws { try throwIfNeeded() }
    func checkCode(_ code: String) throws { try throwIfNeeded() }
    func setEmailAddress(_ email: String) throws { try throwIfNeeded() }
    func checkEmailCode(_ code: String) throws { try throwIfNeeded() }
    func checkPassword(_ password: String) throws { try throwIfNeeded() }

    func requestPasswordRecovery() throws {
        try throwIfNeeded()
        recoveryRequests += 1
    }

    func recoverPassword(code: String, newPassword: String, newHint: String) throws {
        try throwIfNeeded()
        recoveries.append("\(code)|\(newPassword)|\(newHint)")
    }

    func register(firstName: String, lastName: String) throws {
        try throwIfNeeded()
        registrations.append("\(firstName)|\(lastName)")
    }

    func logOut() throws { try throwIfNeeded() }
    func countries() -> [Country] { [] }
    func estimatedCountryCode() -> String { "FR" }

    private(set) var loadChatsCalls: [ChatListKind] = []
    /// Pages restant à charger avant que `loadChats` signale la fin de la liste.
    private var pagesLeft = 0

    func setPagesLeft(_ count: Int) {
        pagesLeft = count
    }

    func loadChats(_ list: ChatListKind, limit: Int) throws -> Bool {
        try throwIfNeeded()
        loadChatsCalls.append(list)
        guard pagesLeft > 0 else { return false }
        pagesLeft -= 1
        return true
    }

    /// Actions reçues sur les conversations, ex. « pin 1 main true ».
    private(set) var chatCalls: [String] = []

    func markAsRead(_ chat: ChatSummary) throws {
        try throwIfNeeded()
        chatCalls.append("read \(chat.id)")
    }

    func setMarkedAsUnread(chatId: Int64, _ isMarkedAsUnread: Bool) throws {
        try throwIfNeeded()
        chatCalls.append("unread \(chatId) \(isMarkedAsUnread)")
    }

    func setPinned(chatId: Int64, in list: ChatListKind, _ isPinned: Bool) throws {
        try throwIfNeeded()
        chatCalls.append("pin \(chatId) \(list) \(isPinned)")
    }

    func setMuted(chatId: Int64, _ isMuted: Bool) throws {
        try throwIfNeeded()
        chatCalls.append("mute \(chatId) \(isMuted)")
    }

    func moveChat(chatId: Int64, to list: ChatListKind) throws {
        try throwIfNeeded()
        chatCalls.append("move \(chatId) \(list)")
    }

    func deleteChat(_ chat: ChatSummary, forEveryone: Bool) throws {
        try throwIfNeeded()
        chatCalls.append("delete \(chat.id) \(forEveryone)")
    }
    /// Recherches de messages reçues : « requête|décalage ».
    private(set) var messageSearches: [String] = []
    private var foundChats: [Int64] = []
    private var foundPublicChats: [Int64] = []
    /// Pages de messages renvoyées dans l'ordre, puis une page vide.
    private var messagePages: [MessageSearchPage] = []

    func setSearchResults(chats: [Int64], publicChats: [Int64] = [], messagePages: [MessageSearchPage] = []) {
        foundChats = chats
        foundPublicChats = publicChats
        self.messagePages = messagePages
    }

    func searchChats(_ query: String, limit: Int) throws -> [Int64] {
        try throwIfNeeded()
        return foundChats
    }

    func searchPublicChats(_ query: String) -> [Int64] { foundPublicChats }

    func searchMessages(_ query: String, offset: String, limit: Int) -> MessageSearchPage {
        messageSearches.append("\(query)|\(offset)")
        return messagePages.isEmpty ? MessageSearchPage(results: [], nextOffset: "") : messagePages.removeFirst()
    }

    // MARK: - Messages

    /// Opérations reçues sur les messages, ex. « send 1 Bonjour reply:5 », « open 1 ».
    private(set) var messageCalls: [String] = []
    /// Demandes d'historique : « conversation depuis décalage limite ».
    private(set) var historyCalls: [String] = []
    /// Pages d'historique renvoyées dans l'ordre, puis des pages vides.
    private var historyPages: [[ChatMessage]] = []
    private var storedMessages: [Int64: ChatMessage] = [:]
    private var messageCapabilities = MessageCapabilities()
    private var reactionChoices: [ReactionKind] = []

    func setHistoryPages(_ pages: [[ChatMessage]]) {
        historyPages = pages
    }

    func setStoredMessages(_ messages: [ChatMessage]) {
        for message in messages { storedMessages[message.id] = message }
    }

    func setCapabilities(_ capabilities: MessageCapabilities) {
        messageCapabilities = capabilities
    }

    func setAvailableReactions(_ reactions: [ReactionKind]) {
        reactionChoices = reactions
    }

    func openChat(_ chatId: Int64) throws {
        try throwIfNeeded()
        messageCalls.append("open \(chatId)")
    }

    func closeChat(_ chatId: Int64) throws {
        try throwIfNeeded()
        messageCalls.append("close \(chatId)")
    }

    private var historyError: TelegramError?

    /// Fait échouer la prochaine demande d'historique seulement.
    func failNextHistory(with error: TelegramError) {
        historyError = error
    }

    func history(chatId: Int64, from fromMessageId: Int64, offset: Int, limit: Int) throws -> [ChatMessage] {
        try throwIfNeeded()
        if let error = historyError {
            historyError = nil
            throw error
        }
        historyCalls.append("\(chatId) \(fromMessageId) \(offset) \(limit)")
        return historyPages.isEmpty ? [] : historyPages.removeFirst()
    }

    func message(chatId: Int64, id: Int64) throws -> ChatMessage {
        try throwIfNeeded()
        messageCalls.append("get \(chatId) \(id)")
        guard let message = storedMessages[id] else { throw TelegramError(code: 404, message: "Not Found") }
        return message
    }

    func capabilities(chatId: Int64, messageId: Int64) throws -> MessageCapabilities {
        try throwIfNeeded()
        return messageCapabilities
    }

    func viewMessages(chatId: Int64, ids: [Int64]) throws {
        try throwIfNeeded()
        messageCalls.append("view \(chatId) \(ids.map { String($0) }.joined(separator: ","))")
    }

    /// Identifiant provisoire du prochain message envoyé.
    private(set) var nextTemporaryId: Int64 = 1000

    func sendText(_ text: String, chatId: Int64, replyTo: Int64?) throws -> Int64 {
        try throwIfNeeded()
        messageCalls.append("send \(chatId) \(text)" + (replyTo.map { " reply:\($0)" } ?? ""))
        nextTemporaryId += 1
        return nextTemporaryId - 1
    }

    func editText(_ text: String, chatId: Int64, messageId: Int64) throws {
        try throwIfNeeded()
        messageCalls.append("edit \(chatId) \(messageId) \(text)")
    }

    func deleteMessages(chatId: Int64, ids: [Int64], forEveryone: Bool) throws {
        try throwIfNeeded()
        messageCalls.append("deleteMessages \(chatId) \(ids.map { String($0) }.joined(separator: ",")) \(forEveryone)")
    }

    func forwardMessages(_ ids: [Int64], from chatId: Int64, to targetChatId: Int64) throws {
        try throwIfNeeded()
        messageCalls.append("forward \(ids.map { String($0) }.joined(separator: ",")) \(chatId) \(targetChatId)")
    }

    func setMessagePinned(chatId: Int64, messageId: Int64, _ isPinned: Bool) throws {
        try throwIfNeeded()
        messageCalls.append("pinMessage \(chatId) \(messageId) \(isPinned)")
    }

    func availableReactions(chatId: Int64, messageId: Int64) throws -> [ReactionKind] {
        try throwIfNeeded()
        return reactionChoices
    }

    func setReaction(_ reaction: ReactionKind, chatId: Int64, messageId: Int64, isChosen: Bool) throws {
        try throwIfNeeded()
        messageCalls.append("react \(chatId) \(messageId) \(reaction) \(isChosen)")
    }

    func messageLink(chatId: Int64, messageId: Int64) throws -> String {
        try throwIfNeeded()
        return "https://t.me/c/\(chatId)/\(messageId)"
    }

    func resendMessages(chatId: Int64, ids: [Int64]) throws {
        try throwIfNeeded()
        messageCalls.append("resend \(chatId) \(ids.map { String($0) }.joined(separator: ","))")
    }

    func downloadFile(_ fileId: Int) throws -> FileRef {
        try throwIfNeeded()
        messageCalls.append("download \(fileId)")
        return FileRef(id: fileId, size: 0, localPath: "/tmp/\(fileId)")
    }

    func sendVoiceNote(chatId: Int64, file: URL, duration: Int, waveform: Data, replyTo: Int64?) throws -> Int64 {
        try throwIfNeeded()
        messageCalls.append("voice \(chatId) \(duration)")
        nextTemporaryId += 1
        return nextTemporaryId - 1
    }

    func setActivity(chatId: Int64, _ activity: ChatActivity?) {}

    private func throwIfNeeded() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }
}

@MainActor
final class AuthViewModelTests: XCTestCase {
    private let config = AppConfig(apiId: 1, apiHash: "test", applicationVersion: "1")
    private let france = Country(id: "FR", name: "France", callingCode: "33", flag: "🇫🇷")

    private var services: [FakeAuthService] = []

    /// Modèle démarré sur un service factice ; chaque (re)création de client en ajoute un à `services`.
    private func makeModel() -> AuthViewModel {
        let model = AuthViewModel(config: config) { [unowned self] _ in
            let service = FakeAuthService()
            self.services.append(service)
            return service
        }
        model.start()
        return model
    }

    private var service: FakeAuthService { services[0] }

    /// Attend qu'une condition devienne vraie (les actions du modèle sont asynchrones).
    private func waitUntil(
        _ condition: @MainActor () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition non remplie à temps", file: file, line: line)
    }

    func testStepsFromServiceAreShown() async {
        let model = makeModel()
        service.send(.phoneNumber)
        await waitUntil { model.step == .phoneNumber }
    }

    func testMissingConfigurationIsReported() {
        let model = AuthViewModel(config: nil)
        XCTAssertEqual(model.step, .configurationMissing)
    }

    func testPhoneNumberRequiresCountryAndTargetsCountryButton() {
        let model = makeModel()
        model.submitPhoneNumber("06 12 34 56 78")
        XCTAssertEqual(model.errorField, .country)
        XCTAssertEqual(model.errorMessage, "Choisissez d'abord votre pays.")
        XCTAssertEqual(model.errorCount, 1)
    }

    func testPhoneNumberRequiresDigits() {
        let model = makeModel()
        model.selectedCountry = france
        model.submitPhoneNumber("abc")
        XCTAssertEqual(model.errorField, .phoneNumber)
    }

    func testPhoneNumberIsSentInInternationalFormat() async {
        let model = makeModel()
        model.selectedCountry = france
        model.submitPhoneNumber("06 12 34 56 78")
        await waitUntil { await self.service.phoneNumbers == ["+33612345678"] }
        await waitUntil { !model.isBusy }
        XCTAssertNil(model.errorMessage)
    }

    func testTelegramErrorTargetsTheRightField() async {
        let model = makeModel()
        await service.failNextCall(with: TelegramError(code: 400, message: "LASTNAME_INVALID"))
        model.register(firstName: "Marie", lastName: "@@@")
        await waitUntil { model.errorField == .lastName }
        XCTAssertEqual(model.errorMessage, "Nom invalide.")
    }

    func testRegistrationTrimsNames() async {
        let model = makeModel()
        model.register(firstName: "  Marie ", lastName: " Dupont ")
        await waitUntil { await self.service.registrations == ["Marie|Dupont"] }
    }

    func testRegistrationRequiresFirstName() {
        let model = makeModel()
        model.register(firstName: "  ", lastName: "Dupont")
        XCTAssertEqual(model.errorField, .firstName)
    }

    func testEditingPhoneNumberIgnoresPendingCodeStep() async throws {
        let model = makeModel()
        let info = CodeInfo(phoneNumber: "+33612345678", delivery: .sms, codeLength: 5, nextDelivery: nil, resendTimeout: 0)
        service.send(.code(info))
        await waitUntil { model.step == .code(info) }

        model.editPhoneNumber()
        XCTAssertEqual(model.step, .phoneNumber)

        // TDLib est toujours en attente du code : l'écran du numéro doit rester affiché.
        service.send(.code(info))
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(model.step, .phoneNumber)
    }

    func testResendBeforeDelayIsRefusedWithRemainingTime() async {
        let model = makeModel()
        let info = CodeInfo(phoneNumber: "+33612345678", delivery: .telegramApp, codeLength: 5, nextDelivery: .sms, resendTimeout: 120)
        service.send(.code(info))
        await waitUntil { model.step == .code(info) }

        model.resendCode()
        XCTAssertEqual(model.errorField, .code)
        XCTAssertTrue(model.errorMessage?.hasPrefix("Nouveau code disponible dans") == true)
    }

    func testRetryReusesTheSameClient() async {
        let model = makeModel()
        service.send(.failed("Impossible d'initialiser la base locale chiffrée."))
        await waitUntil { if case .failed = model.step { return true } else { return false } }

        model.retry()
        await waitUntil { await self.service.retryCount == 1 }
        XCTAssertEqual(services.count, 1)
        XCTAssertEqual(model.step, .starting)
    }

    func testClosedClientIsReplaced() async {
        let model = makeModel()
        service.send(.ready)
        await waitUntil { model.step == .ready }

        service.send(.closed)
        await waitUntil { self.services.count == 2 }
        XCTAssertEqual(model.step, .starting)

        // Les états de l'ancien client sont ignorés.
        services[0].send(.ready)
        services[1].send(.phoneNumber)
        await waitUntil { model.step == .phoneNumber }
    }

    /// Le store des conversations et le hub des messages naissent avec le client (aucun
    /// `updateNewChat` ni message perdu) et sont remplacés avec lui après une déconnexion.
    func testChatStoreFollowsTheClient() async {
        let model = makeModel()
        let firstStore = model.chats
        let firstHub = model.messages
        XCTAssertNotNil(firstStore)
        XCTAssertNotNil(firstHub)

        service.send(.myUserId(42))
        await waitUntil { model.chats?.state.myUserId == 42 }

        service.send(.closed)
        await waitUntil { self.services.count == 2 }
        XCTAssertNotNil(model.chats)
        XCTAssertFalse(model.chats === firstStore)
        XCTAssertNil(model.chats?.state.myUserId)
        XCTAssertNotNil(model.messages)
        XCTAssertFalse(model.messages === firstHub)
    }

    func testForgotPasswordOpensRecovery() async {
        let model = makeModel()
        service.send(.password(PasswordInfo(hint: "", hasRecoveryEmail: true, recoveryEmailPattern: "")))
        await waitUntil { if case .password = model.step { return true } else { return false } }

        model.forgotPassword()
        await waitUntil { model.isRecoveringPassword }
        let requests = await service.recoveryRequests
        XCTAssertEqual(requests, 1)

        model.cancelPasswordRecovery()
        XCTAssertFalse(model.isRecoveringPassword)
    }

    func testRecoveryRequiresMatchingPasswords() {
        let model = makeModel()
        model.recoverPassword(code: "123456", newPassword: "secret-1", confirmation: "secret-2", hint: "")
        XCTAssertEqual(model.errorField, .newPassword)
    }

    func testRecoveryRequiresNewPassword() {
        let model = makeModel()
        model.recoverPassword(code: "123456", newPassword: "", confirmation: "", hint: "")
        XCTAssertEqual(model.errorField, .newPassword)
    }

    func testRecoveryHintMustNotRevealPassword() {
        let model = makeModel()
        model.recoverPassword(code: "123456", newPassword: "Soleil42", confirmation: "Soleil42", hint: "c'est soleil42")
        XCTAssertEqual(model.errorField, .passwordHint)
    }

    func testRecoverySendsCodeAndNewPassword() async {
        let model = makeModel()
        model.recoverPassword(code: " 123456 ", newPassword: "Soleil42", confirmation: "Soleil42", hint: " astre ")
        await waitUntil { await self.service.recoveries == ["123456|Soleil42|astre"] }
    }
}
