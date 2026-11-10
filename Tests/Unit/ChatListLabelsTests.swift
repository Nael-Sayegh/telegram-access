import XCTest
@testable import TelegramAccess

final class ChatListLabelsTests: XCTestCase {
    private let calendar = ChatTestData.calendar
    private let now = ChatTestData.now

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        ChatTestData.date(year, month, day, hour, minute)
    }

    private func line(_ text: String, sender: String? = nil, status: String? = nil, at date: Date) -> LastMessageLine {
        LastMessageLine(senderLabel: sender, text: text, status: status, date: date)
    }

    // MARK: - Heure

    func testSpokenTime() {
        XCTAssertEqual(ChatListLabels.spokenTime(date(2026, 11, 10, 14, 32), now: now, calendar: calendar), "14 h 32")
        XCTAssertEqual(ChatListLabels.spokenTime(date(2026, 11, 10, 9, 5), now: now, calendar: calendar), "9 h 05")
        XCTAssertEqual(ChatListLabels.spokenTime(date(2026, 11, 10, 14, 0), now: now, calendar: calendar), "14 h")
        XCTAssertEqual(ChatListLabels.spokenTime(date(2026, 11, 9, 23, 59), now: now, calendar: calendar), "hier")
        XCTAssertEqual(ChatListLabels.spokenTime(date(2026, 11, 5), now: now, calendar: calendar), "jeudi")
        XCTAssertEqual(ChatListLabels.spokenTime(date(2026, 11, 4), now: now, calendar: calendar), "mercredi")
        XCTAssertEqual(ChatListLabels.spokenTime(date(2026, 11, 3), now: now, calendar: calendar), "3 novembre")
        XCTAssertEqual(ChatListLabels.spokenTime(date(2026, 11, 1), now: now, calendar: calendar), "1er novembre")
        XCTAssertEqual(ChatListLabels.spokenTime(date(2025, 12, 25), now: now, calendar: calendar), "25 décembre 2025")
    }

    func testVisibleTime() {
        XCTAssertEqual(ChatListLabels.visibleTime(date(2026, 11, 10, 9, 5), now: now, calendar: calendar), "09:05")
        XCTAssertEqual(ChatListLabels.visibleTime(date(2026, 11, 9), now: now, calendar: calendar), "Hier")
        XCTAssertEqual(ChatListLabels.visibleTime(date(2025, 12, 25), now: now, calendar: calendar), "25/12/2025")
    }

    // MARK: - Ligne

    func testPrivateChatWithUnreadMessages() {
        let row = ChatTestData.row(unread: 3, lastMessage: line("On se voit demain ?", at: date(2026, 11, 10, 14, 32)))
        XCTAssertEqual(
            ChatListLabels.row(row, now: now, calendar: calendar),
            "Marie Dupont, 3 non lus, dernier message : On se voit demain ?, 14 h 32"
        )
    }

    func testGroupWithMentionAndSender() {
        let row = ChatTestData.row(
            title: "Famille",
            kind: .supergroup,
            unread: 1,
            mentions: 1,
            lastMessage: line("Salut", sender: "Paul", at: date(2026, 11, 9))
        )
        XCTAssertEqual(ChatListLabels.row(row, now: now, calendar: calendar), "Famille, 1 non lu, 1 mention, Paul : Salut, hier")
    }

    func testOwnReadMessage() {
        let row = ChatTestData.row(lastMessage: line("D'accord", sender: "Vous", status: "lu", at: date(2026, 11, 10, 9, 5)))
        XCTAssertEqual(ChatListLabels.row(row, now: now, calendar: calendar), "Marie Dupont, Vous : D'accord, lu, 9 h 05")
    }

    func testSecretChatMarkedAsUnreadWithoutMessage() {
        let row = ChatTestData.row(title: "Marie", kind: .secret(secretChatId: 3, userId: 7), markedUnread: true)
        XCTAssertEqual(ChatListLabels.row(row, now: now, calendar: calendar), "Marie, conversation secrète, marquée comme non lue")
    }

    func testLongMessageIsTruncatedOnAWord() {
        let long = String(repeating: "mot ", count: 60)
        let label = ChatListLabels.truncated(long)
        XCTAssertTrue(label.hasSuffix("mot…"))
        XCTAssertLessThanOrEqual(label.count, ChatListLabels.previewLimit + 1)
    }

    func testLineBreaksAreFlattened() {
        XCTAssertEqual(ChatListLabels.truncated("Bonjour\n\nà tous"), "Bonjour à tous")
    }

    // MARK: - Contenu secondaire

    func testCustomContent() {
        let row = ChatTestData.row(kind: .basicGroup, pinned: true, muted: true, draft: .text("À finir"))
        XCTAssertEqual(
            ChatListLabels.customContent(row),
            ChatRowCustomContent(state: "Épinglée, notifications désactivées", draft: "À finir", type: "Groupe")
        )
    }

    func testCustomContentWhenOnlyMuted() {
        let row = ChatTestData.row(kind: .channel, muted: true)
        XCTAssertEqual(
            ChatListLabels.customContent(row),
            ChatRowCustomContent(state: "Notifications désactivées", draft: nil, type: "Chaîne")
        )
    }

    func testNoCustomContentForPlainPrivateChat() {
        XCTAssertEqual(ChatListLabels.customContent(ChatTestData.row()), ChatRowCustomContent())
    }

    func testConnectionTexts() {
        XCTAssertEqual(ChatListLabels.connection(.waitingForNetwork), "En attente du réseau…")
        XCTAssertNil(ChatListLabels.connection(.ready))
    }
}
