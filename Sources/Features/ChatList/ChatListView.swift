import SwiftUI

/// Liste principale des conversations, affichée une fois connecté.
struct ChatListView: View {
    @Bindable var auth: AuthViewModel
    @State private var model: ChatListViewModel
    @State private var confirmsLogout = false

    init(auth: AuthViewModel, store: ChatStore, service: any ChatListService) {
        self.auth = auth
        _model = State(initialValue: ChatListViewModel(list: .main, store: store, service: service))
    }

    var body: some View {
        List {
            if let connection = model.connectionText {
                Section {
                    Label(connection, systemImage: "wifi.exclamationmark")
                        .readableSecondary()
                }
            }
            Section {
                rows
            } footer: {
                AppDisclaimer()
            }
        }
        .listStyle(.plain)
        .navigationTitle("Discussions")
        .navigationDestination(for: Int64.self) { chatId in
            ConversationPlaceholderView(title: title(of: chatId))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Se déconnecter", role: .destructive) {
                        confirmsLogout = true
                    }
                    .disabled(auth.isBusy)
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Se déconnecter de Telegram sur cet appareil ?", isPresented: $confirmsLogout, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) { auth.logOut() }
            Button("Annuler", role: .cancel) {}
        }
        .task { await model.loadMore() }
        .onChange(of: model.store.state.connection, initial: true) { _, status in
            model.connectionChanged(status)
        }
        .onChange(of: auth.errorCount) {
            if let message = auth.errorMessage { Announcer.announce(message) }
        }
    }

    @ViewBuilder
    private var rows: some View {
        let items = model.rows
        let now = Date()
        if items.isEmpty {
            if model.isFullyLoaded {
                Text("Aucune conversation.")
                    .readableSecondary()
            } else {
                ProgressView("Chargement des conversations…")
            }
        } else {
            ForEach(items) { row in
                NavigationLink(value: row.id) {
                    ChatRow(row: row, now: now)
                }
                .chatRowAccessibility(row, now: now)
                .onAppear { model.rowAppeared(row.id) }
            }
            if !model.isFullyLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Chargement de conversations supplémentaires")
            }
        }
    }

    private func title(of chatId: Int64) -> String {
        let state = model.store.state
        return state.chats[chatId].map { state.displayTitle(of: $0) } ?? "Conversation"
    }
}

extension View {
    /// Ligne lue comme un seul élément, informations secondaires dans « Plus de contenu ».
    /// Posé sur le lien lui-même : `.accessibilityElement(children:)` sur un bouton créerait
    /// un second élément.
    func chatRowAccessibility(_ row: ChatRowModel, now: Date) -> some View {
        let extra = ChatListLabels.customContent(row)
        return self
            .accessibilityLabel(ChatListLabels.row(row, now: now, calendar: .current))
            .accessibilityCustomContent(Text("État"), extra.state.map { Text(verbatim: $0) })
            .accessibilityCustomContent(Text("Brouillon"), extra.draft.map { Text(verbatim: $0) })
            .accessibilityCustomContent(Text("Type"), extra.type.map { Text(verbatim: $0) })
    }
}

/// Conversation : écran provisoire, l'écran complet arrive en phase 3.
struct ConversationPlaceholderView: View {
    let title: String

    var body: some View {
        List {
            Text("L'affichage des messages sera disponible dans une prochaine version.")
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
