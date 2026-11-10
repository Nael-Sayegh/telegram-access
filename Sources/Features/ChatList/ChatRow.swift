import SwiftUI

/// Contenu visuel d'une ligne de conversation. Masqué en détail pour VoiceOver : la ligne
/// entière est un seul élément, dont le libellé est posé par `ChatListView` (sur le lien).
struct ChatRow: View {
    let row: ChatRowModel
    let now: Date
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Aux tailles « accessibilité », rien n'est tronqué : la ligne s'allonge.
    private var lineLimit: Int? {
        typeSize.isAccessibilitySize ? nil : 2
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ChatAvatar(title: row.title, chatId: row.id)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    if row.isSecret {
                        Image(systemName: "lock.fill")
                            .font(.footnote)
                    }
                    Text(row.title)
                        .font(.headline)
                        .lineLimit(lineLimit)
                    Spacer(minLength: 8)
                    if let message = row.lastMessage {
                        Text(ChatListLabels.visibleTime(message.date, now: now, calendar: .current))
                            .font(.footnote)
                            .readableSecondary()
                    }
                }
                HStack(alignment: .top) {
                    preview
                        .font(.subheadline)
                        .lineLimit(lineLimit)
                    Spacer(minLength: 8)
                    indicators
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var preview: some View {
        if case .text(let draft)? = row.draft {
            // Comme Telegram : le brouillon remplace l'aperçu à l'écran.
            (Text("Brouillon : ").foregroundStyle(Color("DestructiveColor")) + Text(draft))
                .readableSecondary()
        } else if let message = row.lastMessage {
            Text(ChatListLabels.visiblePreview(message))
                .readableSecondary()
        } else {
            Text(" ")
        }
    }

    @ViewBuilder
    private var indicators: some View {
        HStack(spacing: 6) {
            if row.isMuted {
                Image(systemName: "bell.slash.fill")
                    .readableSecondary()
            }
            if row.unreadMentionCount > 0 {
                Badge(text: "@")
            }
            if row.unreadCount > 0 {
                Badge(text: row.unreadCount > 999 ? "999+" : String(row.unreadCount))
            } else if row.isMarkedAsUnread {
                Badge(text: " ")
            } else if row.isPinned {
                Image(systemName: "pin.fill")
                    .readableSecondary()
            }
        }
        .font(.footnote)
    }
}

/// Pastille de compteur (non lus, mentions).
private struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .frame(minWidth: 22)
            .background(Capsule().fill(Color.accentColor))
    }
}

/// Initiales sur une pastille de couleur, décoratives (photos de profil : plus tard).
struct ChatAvatar: View {
    let title: String
    let chatId: Int64
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 48

    /// Couleurs assez foncées pour un texte blanc contrasté.
    private static let colors: [Color] = [
        Color(red: 0.70, green: 0.20, blue: 0.20),
        Color(red: 0.15, green: 0.45, blue: 0.25),
        Color(red: 0.15, green: 0.35, blue: 0.65),
        Color(red: 0.50, green: 0.25, blue: 0.60),
        Color(red: 0.60, green: 0.35, blue: 0.05),
        Color(red: 0.10, green: 0.45, blue: 0.50),
    ]

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Self.colors[Int(abs(chatId % Int64(Self.colors.count)))]))
            .accessibilityHidden(true)
    }

    private var initials: String {
        let words = title.split(whereSeparator: \.isWhitespace).prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}
