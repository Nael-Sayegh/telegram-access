import Foundation

/// Informations secondaires d'une ligne, lues par le rotor « Plus de contenu ».
struct ChatRowCustomContent: Equatable {
    /// « Épinglée, notifications désactivées »
    var state: String?
    var draft: String?
    /// « Groupe », « Chaîne »
    var type: String?
}

/// Textes de la liste des conversations. Fonctions pures, testées unitairement.
enum ChatListLabels {
    /// Longueur maximale du dernier message dans le libellé d'une ligne.
    static let previewLimit = 150

    /// Libellé VoiceOver d'une ligne, en un seul élément :
    /// « Marie Dupont, 3 non lus, dernier message : On se voit demain ?, 14 h 32 ».
    static func row(_ row: ChatRowModel, now: Date, calendar: Calendar) -> String {
        var parts = [row.title]
        if row.isSecret {
            parts.append("conversation secrète")
        }
        if let unread = unread(row) {
            parts.append(unread)
        }
        if row.unreadMentionCount > 0 {
            parts.append(count(row.unreadMentionCount, "mention", "mentions"))
        }
        if let message = row.lastMessage {
            parts.append(lastMessage(message))
            parts.append(spokenTime(message.date, now: now, calendar: calendar))
        }
        return parts.joined(separator: ", ")
    }

    /// « 3 non lus », « 1 non lu », « marquée comme non lue », ou `nil`.
    static func unread(_ row: ChatRowModel) -> String? {
        if row.unreadCount > 0 {
            return count(row.unreadCount, "non lu", "non lus")
        }
        return row.isMarkedAsUnread ? "marquée comme non lue" : nil
    }

    /// « Paul : Salut », « Vous : D'accord, lu », « dernier message : Salut ».
    static func lastMessage(_ message: LastMessageLine) -> String {
        let text = truncated(message.text)
        var result = message.senderLabel.map { "\($0) : \(text)" } ?? "dernier message : \(text)"
        if let status = message.status {
            result += ", \(status)"
        }
        return result
    }

    /// Aperçu affiché sous le nom : « Paul : Salut ».
    static func visiblePreview(_ message: LastMessageLine) -> String {
        let text = singleLine(message.text)
        return message.senderLabel.map { "\($0) : \(text)" } ?? text
    }

    static func customContent(_ row: ChatRowModel) -> ChatRowCustomContent {
        var states: [String] = []
        if row.isPinned { states.append("Épinglée") }
        if row.isMuted { states.append("notifications désactivées") }
        let state = states.isEmpty ? nil : states.joined(separator: ", ").capitalizedFirst

        let type: String?
        switch row.kind {
        case .basicGroup, .supergroup: type = "Groupe"
        case .channel: type = "Chaîne"
        case .user, .secret: type = nil
        }
        return ChatRowCustomContent(state: state, draft: row.draft.map(draft), type: type)
    }

    static func draft(_ draft: DraftSummary) -> String {
        switch draft {
        case .text(let text): return truncated(text)
        case .voiceNote: return "Message vocal"
        case .videoNote: return "Message vidéo"
        case .other: return "Message en préparation"
        }
    }

    /// État de connexion affiché en haut de la liste ; `nil` une fois connecté.
    static func connection(_ status: ConnectionStatus) -> String? {
        switch status {
        case .waitingForNetwork: return "En attente du réseau…"
        case .connectingToProxy: return "Connexion au proxy…"
        case .connecting: return "Connexion…"
        case .updating: return "Mise à jour…"
        case .ready: return nil
        }
    }

    // MARK: - Dates

    /// Heure lue : « 14 h 32 » aujourd'hui, « hier », « lundi » dans la semaine,
    /// « 3 novembre » cette année, « 3 novembre 2025 » sinon.
    static func spokenTime(_ date: Date, now: Date, calendar: Calendar) -> String {
        switch day(of: date, now: now, calendar: calendar) {
        case .today:
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let hour = parts.hour ?? 0
            let minute = parts.minute ?? 0
            return minute == 0 ? "\(hour) h" : "\(hour) h \(String(format: "%02d", minute))"
        case .yesterday:
            return "hier"
        case .thisWeek:
            return calendar.weekdaySymbols[calendar.component(.weekday, from: date) - 1]
        case .thisYear:
            return dayAndMonth(date, calendar: calendar)
        case .older:
            return "\(dayAndMonth(date, calendar: calendar)) \(calendar.component(.year, from: date))"
        }
    }

    /// Heure affichée : « 14:32 », « Hier », « lun. », « 3 nov. », « 03/11/2025 ».
    static func visibleTime(_ date: Date, now: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        switch day(of: date, now: now, calendar: calendar) {
        case .today:
            return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        case .yesterday:
            return "Hier"
        case .thisWeek:
            return calendar.shortWeekdaySymbols[(parts.weekday ?? 1) - 1]
        case .thisYear:
            return "\(parts.day ?? 1) \(calendar.shortMonthSymbols[(parts.month ?? 1) - 1])"
        case .older:
            return String(format: "%02d/%02d/%04d", parts.day ?? 1, parts.month ?? 1, parts.year ?? 0)
        }
    }

    // MARK: - Privé

    private enum Day {
        case today, yesterday, thisWeek, thisYear, older
    }

    private static func day(of date: Date, now: Date, calendar: Calendar) -> Day {
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        switch days {
        case 0: return .today
        case 1: return .yesterday
        case 2...6: return .thisWeek
        default:
            return calendar.component(.year, from: date) == calendar.component(.year, from: now) ? .thisYear : .older
        }
    }

    /// « 1er novembre », « 3 novembre »
    private static func dayAndMonth(_ date: Date, calendar: Calendar) -> String {
        let day = calendar.component(.day, from: date)
        let month = calendar.monthSymbols[calendar.component(.month, from: date) - 1]
        return "\(day == 1 ? "1er" : String(day)) \(month)"
    }

    private static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value > 1 ? plural : singular)"
    }

    /// Texte sur une ligne, coupé sur un mot au-delà de `previewLimit` caractères.
    static func truncated(_ text: String) -> String {
        let line = singleLine(text)
        guard line.count > previewLimit else { return line }
        let prefix = line.prefix(previewLimit)
        let cut = prefix.lastIndex(of: " ").flatMap { index in
            prefix.distance(from: prefix.startIndex, to: index) > previewLimit / 2 ? prefix[..<index] : nil
        } ?? prefix
        return "\(cut)…"
    }

    private static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

private extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
