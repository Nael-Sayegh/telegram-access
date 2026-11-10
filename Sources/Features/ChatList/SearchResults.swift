import SwiftUI

/// Sections de résultats de la recherche globale, affichées à la place de la liste.
/// Les en-têtes de section (« Conversations », « Messages ») sont annoncés comme en-têtes :
/// le rotor En-têtes permet de passer d'une catégorie à l'autre.
struct SearchResults: View {
    let search: GlobalSearchViewModel

    var body: some View {
        let now = Date()
        let chats = search.chatRows
        let publicChats = search.publicChatRows
        let isEmpty = chats.isEmpty && publicChats.isEmpty && search.messages.isEmpty

        if isEmpty {
            Section {
                if search.isSearching {
                    ProgressView("Recherche…")
                } else if search.failed {
                    Text("La recherche a échoué. Vérifiez votre connexion.")
                } else {
                    Text("Aucun résultat pour « \(search.trimmedQuery) ».")
                }
            }
        }
        if !chats.isEmpty {
            Section("Conversations") {
                chatLinks(chats, now: now)
            }
        }
        if !publicChats.isEmpty {
            Section("Groupes et chaînes publics") {
                chatLinks(publicChats, now: now)
            }
        }
        if !search.messages.isEmpty {
            Section("Messages") {
                ForEach(search.messages) { row in
                    NavigationLink(value: ChatRoute.chat(row.chatId)) {
                        SearchMessageView(row: row, now: now)
                    }
                    .accessibilityLabel(SearchLabels.message(row, now: now, calendar: .current))
                }
                if search.hasMoreMessages {
                    Button("Charger plus de messages") {
                        Task { await search.loadMoreMessages() }
                    }
                    .disabled(search.isSearching)
                }
            }
        }
    }

    private func chatLinks(_ rows: [ChatRowModel], now: Date) -> some View {
        ForEach(rows) { row in
            NavigationLink(value: ChatRoute.chat(row.id)) {
                ChatRow(row: row, now: now)
            }
            .chatRowAccessibility(row, now: now)
        }
    }
}

/// Message trouvé : conversation et heure, puis le message.
private struct SearchMessageView: View {
    let row: SearchMessageRow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.chatTitle)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(ChatListLabels.visibleTime(row.line.date, now: now, calendar: .current))
                    .font(.footnote)
                    .readableSecondary()
            }
            Text(ChatListLabels.visiblePreview(row.line))
                .font(.subheadline)
                .readableSecondary()
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }
}
