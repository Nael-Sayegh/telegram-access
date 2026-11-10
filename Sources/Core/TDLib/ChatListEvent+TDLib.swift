import Foundation
@preconcurrency import TDLibKit

// Conversion des updates et objets TDLib en types de la liste des conversations.
// Seul endroit, avec `TelegramClient`, où les conversations dépendent de TDLibKit.

extension ChatListEvent {
    /// `nil` pour un update sans rapport avec la liste des conversations.
    init?(_ update: Update) {
        switch update {
        case .updateNewChat(let value):
            self = .newChat(ChatSummary(value.chat))
        case .updateChatTitle(let value):
            self = .title(chatId: value.chatId, title: value.title)
        case .updateChatLastMessage(let value):
            self = .lastMessage(
                chatId: value.chatId,
                message: value.lastMessage.map { MessagePreview($0) },
                positions: value.positions.map { ChatListPosition($0) }
            )
        case .updateChatPosition(let value):
            self = .position(chatId: value.chatId, position: ChatListPosition(value.position))
        case .updateChatReadInbox(let value):
            self = .readInbox(
                chatId: value.chatId,
                lastReadMessageId: value.lastReadInboxMessageId,
                unreadCount: value.unreadCount
            )
        case .updateChatReadOutbox(let value):
            self = .readOutbox(chatId: value.chatId, lastReadMessageId: value.lastReadOutboxMessageId)
        case .updateChatUnreadMentionCount(let value):
            self = .mentionCount(chatId: value.chatId, count: value.unreadMentionCount)
        case .updateMessageMentionRead(let value):
            self = .mentionCount(chatId: value.chatId, count: value.unreadMentionCount)
        case .updateChatUnreadReactionCount(let value):
            self = .reactionCount(chatId: value.chatId, count: value.unreadReactionCount)
        case .updateChatIsMarkedAsUnread(let value):
            self = .markedAsUnread(chatId: value.chatId, value: value.isMarkedAsUnread)
        case .updateChatNotificationSettings(let value):
            self = .muteSetting(chatId: value.chatId, setting: ChatMuteSetting(value.notificationSettings))
        case .updateScopeNotificationSettings(let value):
            self = .scopeMute(scope: NotificationScope(value.scope), muteFor: value.notificationSettings.muteFor)
        case .updateChatDraftMessage(let value):
            self = .draft(
                chatId: value.chatId,
                draft: value.draftMessage.map { DraftSummary($0) },
                positions: value.positions.map { ChatListPosition($0) }
            )
        case .updateUser(let value):
            self = .user(id: value.user.id, name: UserName(value.user))
        case .updateOption(let value):
            guard value.name == "my_id", case .optionValueInteger(let id) = value.value else { return nil }
            self = .myUserId(id.value.rawValue)
        case .updateConnectionState(let value):
            self = .connection(ConnectionStatus(value.state))
        default:
            return nil
        }
    }
}

extension ChatListKind {
    init(_ list: ChatList) {
        switch list {
        case .chatListMain: self = .main
        case .chatListArchive: self = .archive
        case .chatListFolder(let folder): self = .folder(folder.chatFolderId)
        }
    }

    var tdValue: ChatList {
        switch self {
        case .main: return .chatListMain
        case .archive: return .chatListArchive
        case .folder(let id): return .chatListFolder(ChatListFolder(chatFolderId: id))
        }
    }
}

extension ChatListPosition {
    init(_ position: ChatPosition) {
        self.init(list: ChatListKind(position.list), order: position.order.rawValue, isPinned: position.isPinned)
    }
}

extension ChatKind {
    init(_ type: ChatType) {
        switch type {
        case .chatTypePrivate(let value):
            self = .user(userId: value.userId)
        case .chatTypeBasicGroup:
            self = .basicGroup
        case .chatTypeSupergroup(let value):
            self = value.isChannel ? .channel : .supergroup
        case .chatTypeSecret(let value):
            self = .secret(secretChatId: value.secretChatId, userId: value.userId)
        }
    }
}

extension ChatSummary {
    init(_ chat: Chat) {
        self.init(
            id: chat.id,
            kind: ChatKind(chat.type),
            title: chat.title,
            positions: chat.positions.map { ChatListPosition($0) },
            lastMessage: chat.lastMessage.map { MessagePreview($0) },
            unreadCount: chat.unreadCount,
            unreadMentionCount: chat.unreadMentionCount,
            unreadReactionCount: chat.unreadReactionCount,
            isMarkedAsUnread: chat.isMarkedAsUnread,
            lastReadInboxMessageId: chat.lastReadInboxMessageId,
            lastReadOutboxMessageId: chat.lastReadOutboxMessageId,
            muteSetting: ChatMuteSetting(chat.notificationSettings),
            draft: chat.draftMessage.map { DraftSummary($0) },
            canBeDeletedOnlyForSelf: chat.canBeDeletedOnlyForSelf,
            canBeDeletedForAllUsers: chat.canBeDeletedForAllUsers
        )
    }
}

extension ChatMuteSetting {
    init(_ settings: ChatNotificationSettings) {
        self.init(usesDefault: settings.useDefaultMuteFor, muteFor: settings.muteFor)
    }
}

extension NotificationScope {
    init(_ scope: NotificationSettingsScope) {
        switch scope {
        case .notificationSettingsScopePrivateChats: self = .privateChats
        case .notificationSettingsScopeGroupChats: self = .groups
        case .notificationSettingsScopeChannelChats: self = .channels
        }
    }
}

extension ConnectionStatus {
    init(_ state: ConnectionState) {
        switch state {
        case .connectionStateWaitingForNetwork: self = .waitingForNetwork
        case .connectionStateConnectingToProxy: self = .connectingToProxy
        case .connectionStateConnecting: self = .connecting
        case .connectionStateUpdating: self = .updating
        case .connectionStateReady: self = .ready
        }
    }
}

extension UserName {
    init(_ user: User) {
        let isDeleted: Bool
        if case .userTypeDeleted = user.type {
            isDeleted = true
        } else {
            isDeleted = false
        }
        self.init(firstName: user.firstName, lastName: user.lastName, isDeleted: isDeleted)
    }
}

extension DraftSummary {
    init(_ draft: DraftMessage) {
        switch draft.content {
        case .draftMessageContentText(let value): self = .text(value.text.text)
        case .draftMessageContentVoiceNote: self = .voiceNote
        case .draftMessageContentVideoNote: self = .videoNote
        default: self = .other
        }
    }
}

extension MessagePreview {
    init(_ message: Message) {
        let sender: MessageSenderRef
        switch message.senderId {
        case .messageSenderUser(let value): sender = .user(value.userId)
        case .messageSenderChat(let value): sender = .chat(value.chatId)
        }
        let delivery: MessageDeliveryState
        switch message.sendingState {
        case .messageSendingStatePending?: delivery = .pending
        case .messageSendingStateFailed?: delivery = .failed
        case nil: delivery = .sent
        }
        self.init(
            id: message.id,
            sender: sender,
            isOutgoing: message.isOutgoing,
            date: Date(timeIntervalSince1970: TimeInterval(message.date)),
            content: MessageContentSummary(message.content),
            delivery: delivery
        )
    }
}

extension MessageContentSummary {
    init(_ content: MessageContent) {
        switch content {
        case .messageText(let value):
            self = .text(value.text.text)
        case .messagePhoto(let value):
            self = .photo(caption: value.caption.text)
        case .messageVideo(let value):
            self = .video(duration: value.video.duration, caption: value.caption.text)
        case .messageAnimation(let value):
            self = .animation(caption: value.caption.text)
        case .messageVoiceNote(let value):
            self = .voiceNote(duration: value.voiceNote.duration, caption: value.caption.text)
        case .messageVideoNote(let value):
            self = .videoNote(duration: value.videoNote.duration)
        case .messageAudio(let value):
            self = .audio(
                title: value.audio.title,
                performer: value.audio.performer,
                duration: value.audio.duration,
                caption: value.caption.text
            )
        case .messageDocument(let value):
            let file = value.document.document
            self = .document(
                fileName: value.document.fileName,
                size: max(file.size, file.expectedSize),
                caption: value.caption.text
            )
        case .messageSticker(let value):
            self = .sticker(emoji: value.sticker.emoji)
        case .messageLocation:
            self = .location
        case .messageVenue:
            self = .venue
        case .messageContact(let value):
            self = .contact(firstName: value.contact.firstName, lastName: value.contact.lastName)
        case .messagePoll(let value):
            self = .poll(question: value.poll.question.text)
        case .messageCall(let value):
            self = .call(isVideo: value.isVideo, duration: value.duration, outcome: CallOutcome(value.discardReason))
        case .messageStory:
            self = .story
        case .messageBasicGroupChatCreate, .messageSupergroupChatCreate:
            self = .groupCreated
        case .messageChatChangeTitle(let value):
            self = .titleChanged(value.title)
        case .messageChatChangePhoto:
            self = .photoChanged
        case .messageChatAddMembers:
            self = .membersAdded
        case .messageChatDeleteMember:
            self = .memberRemoved
        case .messagePinMessage:
            self = .pinnedMessage
        default:
            self = .unsupported
        }
    }
}

extension CallOutcome {
    init(_ reason: CallDiscardReason) {
        switch reason {
        case .callDiscardReasonMissed: self = .missed
        case .callDiscardReasonDeclined: self = .declined
        default: self = .ended
        }
    }
}
