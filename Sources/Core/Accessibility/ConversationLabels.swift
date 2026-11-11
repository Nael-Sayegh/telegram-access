import Foundation

/// Textes de l'alerte affichée avant d'ouvrir un lien vers une autre app.
struct LinkConfirmation: Equatable {
    var title: String
    /// Destination complète, telle qu'elle sera ouverte.
    var message: String
    var confirm: String
}

/// Textes de l'écran de conversation. Fonctions pures, testées unitairement.
enum ConversationLabels {
    /// Longueur maximale de l'extrait d'un message cité, dans le libellé d'une réponse.
    static let replyExcerptLimit = 80

    /// Libellé VoiceOver d'un message, en un seul élément, dans cet ordre : auteur, transfert,
    /// contenu, message cité, heure, état d'envoi, modifié, épinglé, réactions.
    /// « Paul Martin, D'accord, en réponse à votre message : On se voit ?, 14 h 32 ».
    static func message(_ row: MessageRowModel, calendar: Calendar) -> String {
        var parts: [String] = []
        if let sender = row.senderLabel {
            parts.append(sender)
        }
        if let origin = row.forwardedFrom {
            parts.append("transféré de \(origin)")
        }
        parts.append(content(row))
        if let cited = row.reply {
            parts.append(reply(cited))
        }
        parts.append(time(row.date, calendar: calendar))
        if let status = row.status {
            parts.append(status)
        }
        if row.isEdited {
            parts.append("modifié")
        }
        if row.isPinned {
            parts.append("épinglé")
        }
        if let reactionText = reactions(row.reactions) {
            parts.append(reactionText)
        }
        return parts.joined(separator: ", ")
    }

    /// Contenu lu : texte complet (non tronqué), ou description du média, suivie de « non
    /// écouté » pour un vocal reçu pas encore écouté.
    static func content(_ row: MessageRowModel) -> String {
        var text = MessageLabels.content(row.content).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            text = "Message vide"
        }
        if row.isUnopened {
            text += row.mediaKind == .videoNote ? ", non vu" : ", non écouté"
        }
        return text
    }

    /// « en réponse à Paul Martin : On se voit ? », « en réponse à votre message : … »,
    /// « en réponse à un message supprimé ».
    static func reply(_ reply: ReplyLine) -> String {
        if reply.isDeleted {
            return "en réponse à un message supprimé"
        }
        let target: String
        switch reply.author {
        case .me: target = "en réponse à votre message"
        case .named(let name): target = "en réponse à \(name)"
        case .unknown: target = "en réponse à un message"
        }
        guard let text = reply.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return target
        }
        return "\(target) : \(excerpt(text))"
    }

    /// « réactions : 👍 2, ❤️ de vous, 😂 3 dont vous » (VoiceOver lit le nom des émoji).
    static func reactions(_ reactions: [MessageReactionCount]) -> String? {
        guard !reactions.isEmpty else { return nil }
        let items = reactions.map { reaction -> String in
            let name = reactionName(reaction.kind)
            switch (reaction.isChosen, reaction.count) {
            case (true, ...1): return "\(name) de vous"
            case (true, _): return "\(name) \(reaction.count) dont vous"
            default: return "\(name) \(reaction.count)"
            }
        }
        return "réactions : " + items.joined(separator: ", ")
    }

    static func reactionName(_ kind: ReactionKind) -> String {
        switch kind {
        case .emoji(let emoji): return emoji
        case .customEmoji: return "émoji personnalisé"
        case .paid: return "étoiles"
        }
    }

    // MARK: - Liens

    /// Nom de l'action d'ouverture d'un lien. Il donne la vraie destination, et non le texte
    /// affiché dans le message (qui peut tromper) : « Ouvrir exemple.fr », « Écrire à
    /// marie@exemple.fr », « Ouvrir le lien Telegram », « Ouvrir dans une autre app :
    /// tel:+33612345678 ».
    static func openLinkAction(_ url: URL) -> String {
        let name = MessageTextTools.shortName(url)
        switch url.scheme?.lowercased() {
        case "mailto": return "Écrire à \(name)"
        case "tg": return "Ouvrir le \(name)"
        case "http", "https": return "Ouvrir \(name)"
        default: return "Ouvrir dans une autre app : \(excerpt(name))"
        }
    }

    /// Alerte avant d'ouvrir un lien vers une autre app (`MessageTextTools.requiresConfirmation`) :
    /// destination complète, boutons « Ouvrir » et « Annuler ».
    static func linkConfirmation(_ url: URL) -> LinkConfirmation {
        LinkConfirmation(
            title: "Ouvrir ce lien dans une autre app ?",
            message: "Destination : \(url.absoluteString)",
            confirm: "Ouvrir"
        )
    }

    // MARK: - Dates

    /// Heure d'un message : « 14 h 32 », « 9 h » (le jour est donné par l'en-tête de section).
    static func time(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        return minute == 0 ? "\(hour) h" : "\(hour) h \(String(format: "%02d", minute))"
    }

    /// Heure affichée sous un message : « 14:32 ».
    static func visibleTime(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// En-tête d'un jour : « Aujourd'hui », « Hier », « Lundi 9 novembre » dans la semaine,
    /// « 3 novembre » cette année, « 1er novembre 2025 » avant.
    static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        let day = calendar.component(.day, from: date)
        let month = calendar.monthSymbols[calendar.component(.month, from: date) - 1]
        let dayAndMonth = "\(day == 1 ? "1er" : String(day)) \(month)"
        switch days {
        case 0:
            return "Aujourd'hui"
        case 1:
            return "Hier"
        case 2...6:
            let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: date) - 1]
            return capitalizedFirst("\(weekday) \(dayAndMonth)")
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return sameYear ? dayAndMonth : "\(dayAndMonth) \(calendar.component(.year, from: date))"
        }
    }

    // MARK: - Activité

    /// Texte affiché sous le titre : « écrit… » en tête-à-tête, « Paul écrit… »,
    /// « Paul et Marie écrivent… », « 3 personnes écrivent… » en groupe ; `nil` sans activité.
    /// `activities` : participants actifs (nom et activité), dans un ordre stable.
    static func activity(_ activities: [(name: String, activity: ChatActivity)], isPrivateChat: Bool) -> String? {
        guard let first = activities.first else { return nil }
        if isPrivateChat || activities.count == 1 {
            let verb = singularVerb(first.activity)
            return isPrivateChat ? "\(verb)…" : "\(first.name) \(verb)…"
        }
        let allTyping = activities.allSatisfy { $0.activity == .typing }
        let subject = activities.count == 2
            ? "\(activities[0].name) et \(activities[1].name)"
            : "\(activities.count) personnes"
        return allTyping ? "\(subject) écrivent…" : "\(subject) sont en activité…"
    }

    // MARK: - Privé

    private static func singularVerb(_ activity: ChatActivity) -> String {
        switch activity {
        case .typing: return "écrit"
        case .recordingVoiceNote: return "enregistre un message vocal"
        case .recordingVideo: return "enregistre une vidéo"
        case .sendingFile: return "envoie un fichier"
        case .choosingSticker: return "choisit un autocollant"
        case .other: return "est en activité"
        }
    }

    /// Extrait sur une ligne, coupé sur un mot au-delà de `replyExcerptLimit` caractères.
    static func excerpt(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard line.count > replyExcerptLimit else { return line }
        let prefix = line.prefix(replyExcerptLimit)
        let cut = prefix.lastIndex(of: " ").flatMap { index in
            prefix.distance(from: prefix.startIndex, to: index) > replyExcerptLimit / 2 ? prefix[..<index] : nil
        } ?? prefix
        return "\(cut)…"
    }

    private static func capitalizedFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
