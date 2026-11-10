import SwiftUI

/// Écran de recherche : champ en haut (clavier ouvert), choix Messages / Conversations, puis
/// les résultats. Ouvert par le bouton « Rechercher » de la liste : le champ de recherche
/// standard d'iOS 26 serait placé en bas de l'écran, donc lu en dernier par VoiceOver.
struct GlobalSearchView: View {
    @State private var search: GlobalSearchViewModel
    @FocusState private var isFieldFocused: Bool

    init(store: ChatStore, service: any ChatListService) {
        _search = State(initialValue: GlobalSearchViewModel(store: store, service: service))
    }

    var body: some View {
        List {
            Section {
                TextField(search.scope.prompt, text: $search.query)
                    .focused($isFieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { search.submit() }
                ChoiceChips(
                    label: "Rechercher dans",
                    options: SearchScope.allCases,
                    selection: search.scope,
                    title: \.name
                ) { search.setScope($0) }
            }
            SearchResults(search: search)
        }
        .listStyle(.plain)
        .navigationTitle("Rechercher")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: search.query) { search.queryChanged() }
        .task {
            // Après l'animation d'arrivée sur l'écran : le clavier s'ouvre sur le champ.
            try? await Task.sleep(for: .milliseconds(400))
            isFieldFocused = true
        }
    }
}

/// Sections de résultats de la recherche globale.
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
                } else if search.isActive {
                    Text(search.scope.noResult(search.trimmedQuery))
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.chatTitle)
                    .font(.headline)
                    // Aux tailles « accessibilité », rien n'est tronqué.
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                Spacer(minLength: 8)
                Text(ChatListLabels.visibleTime(row.line.date, now: now, calendar: .current))
                    .font(.footnote)
                    .readableSecondary()
            }
            Text(ChatListLabels.visiblePreview(row.line))
                .font(.subheadline)
                .readableSecondary()
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
        }
        .padding(.vertical, 4)
    }
}
