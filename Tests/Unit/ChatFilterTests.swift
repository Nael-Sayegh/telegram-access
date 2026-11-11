import XCTest
@testable import TelegramAccess

final class ChatFilterTests: XCTestCase {
    private let person = ChatTestData.chat(1, kind: .user(userId: 7))
    private let secret = ChatTestData.chat(2, kind: .secret(secretChatId: 3, userId: 7))
    private let group = ChatTestData.chat(3, kind: .basicGroup)
    private let supergroup = ChatTestData.chat(4, kind: .supergroup)
    private let channel = ChatTestData.chat(5, kind: .channel)

    private func ids(_ filter: ChatFilter, _ chats: [ChatSummary]) -> [Int64] {
        chats.filter(filter.matches).map(\.id)
    }

    func testTypeFilters() {
        let all = [person, secret, group, supergroup, channel]
        XCTAssertEqual(ids(.all, all), [1, 2, 3, 4, 5])
        XCTAssertEqual(ids(.people, all), [1, 2])
        XCTAssertEqual(ids(.groups, all), [3, 4])
        XCTAssertEqual(ids(.channels, all), [5])
    }

    func testUnreadFilterIncludesMentionsReactionsAndMarks() {
        var unread = person
        unread.unreadCount = 2
        var mention = group
        mention.unreadMentionCount = 1
        var reaction = supergroup
        reaction.unreadReactionCount = 1
        var marked = channel
        marked.isMarkedAsUnread = true
        XCTAssertEqual(ids(.unread, [unread, secret, mention, reaction, marked]), [1, 3, 4, 5])
    }

    func testLabels() {
        XCTAssertEqual(ChatFilter.unread.menuTitle(count: 4), "Non lus (4)")
        XCTAssertEqual(ChatFilter.all.menuTitle(count: nil), "Tous")
        XCTAssertEqual(ChatFilter.channels.buttonLabel, "Filtre : Chaînes")
        XCTAssertEqual(ChatFilter.resultAnnouncement(count: 0), "Aucune conversation.")
        XCTAssertEqual(ChatFilter.resultAnnouncement(count: 3), "3 conversations.")
        XCTAssertEqual(ChatFilter.unread.emptyText, "Aucune conversation non lue.")
    }

    func testRotors() {
        var row = ChatTestData.row(mentions: 1, pinned: true)
        row.hasUnread = true
        XCTAssertTrue(ChatRotor.unread.matches(row))
        XCTAssertTrue(ChatRotor.mentions.matches(row))
        XCTAssertTrue(ChatRotor.pinned.matches(row))
        let plain = ChatTestData.row()
        XCTAssertFalse(ChatRotor.allCases.contains { $0.matches(plain) })
    }
}
