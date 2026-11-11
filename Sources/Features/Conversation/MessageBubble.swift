import SwiftUI

/// Bulle d'un message, pour l'affichage. VoiceOver ne la parcourt pas en détail :
/// `MessageListView` en fait un seul élément, avec le libellé complet du message.
///
/// Couleurs : message envoyé en texte « fond système » sur la couleur d'accent (blanc sur bleu
/// foncé en clair, noir sur bleu clair en sombre : contraste suffisant dans les deux modes),
/// message reçu en texte principal sur fond gris.
struct MessageBubble: View {
    let row: MessageRowModel
    @Environment(\.dynamicTypeSize) private var typeSize

    private var textColor: Color {
        row.isOutgoing ? Color(uiColor: .systemBackground) : Color.primary
    }

    private var bubbleColor: Color {
        row.isOutgoing ? Color.accentColor : Color(uiColor: .secondarySystemBackground)
    }

    var body: some View {
        HStack(spacing: 0) {
            if row.isOutgoing {
                Spacer(minLength: 48)
            }
            VStack(alignment: .leading, spacing: 4) {
                if let sender = row.senderLabel, !row.isOutgoing {
                    Text(sender)
                        .font(.subheadline.weight(.semibold))
                }
                if let origin = row.forwardedFrom {
                    Text("Transféré de \(origin)")
                        .font(.footnote.italic())
                }
                if let reply = row.reply {
                    ReplyPreview(reply: reply, color: textColor, lineLimit: typeSize.isAccessibilitySize ? nil : 2)
                }
                Text(ConversationLabels.content(row))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if !row.reactions.isEmpty {
                    Text(Self.visibleReactions(row.reactions))
                        .font(.footnote)
                }
                Text(footer)
                    .font(.caption)
                    .opacity(row.isOutgoing ? 1 : 0.8)
            }
            .foregroundStyle(textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(bubbleColor)
            )
            if !row.isOutgoing {
                Spacer(minLength: 48)
            }
        }
    }

    /// « modifié · épinglé · 14:32 · lu »
    private var footer: String {
        var parts: [String] = []
        if row.isEdited { parts.append("modifié") }
        if row.isPinned { parts.append("épinglé") }
        parts.append(ConversationLabels.visibleTime(row.date, calendar: .current))
        if let status = row.status { parts.append(status) }
        return parts.joined(separator: " · ")
    }

    /// « 👍 2  ❤️ 1 »
    static func visibleReactions(_ reactions: [MessageReactionCount]) -> String {
        reactions
            .map { "\(ConversationLabels.reactionName($0.kind)) \($0.count)" }
            .joined(separator: "  ")
    }
}

/// Message cité, au-dessus du contenu d'une réponse.
private struct ReplyPreview: View {
    let reply: ReplyLine
    let color: Color
    let lineLimit: Int?

    private var author: String {
        if reply.isDeleted { return "Message supprimé" }
        switch reply.author {
        case .me: return "Vous"
        case .named(let name): return name
        case .unknown: return "Message"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(author)
                    .font(.footnote.weight(.semibold))
                if let text = reply.text {
                    Text(text)
                        .font(.footnote)
                        .lineLimit(lineLimit)
                }
            }
        }
        // La barre verticale prend la hauteur du texte, pas plus.
        .fixedSize(horizontal: false, vertical: true)
    }
}
