import SwiftUI

/// Destination de navigation depuis une liste de conversations.
enum ChatRoute: Hashable {
    case chat(Int64)
    case archive
    case search
}

/// Liste principale des conversations, affichée une fois connecté.
struct ChatListView: View {
    @Bindable var auth: AuthViewModel
    @State private var model: ChatListViewModel
    @State private var confirmsLogout = false
    @Namespace private var rotorNamespace
    private let service: any ChatListService

    init(auth: AuthViewModel, store: ChatStore, service: any ChatListService) {
        self.auth = auth
        self.service = service
        _model = State(initialValue: ChatListViewModel(list: .main, store: store, service: service))
    }

    var body: some View {
        List {
            listSections
        }
        .listStyle(.plain)
        .chatRotors(model, namespace: rotorNamespace)
        .navigationTitle("Discussions")
        // Ordre VoiceOver constant : Options, Discussions, Rechercher, Filtre. Titre toujours
        // dans la barre : un grand titre passait de sous la barre (lu après Options) à dans la
        // barre (lu avant) au défilement. Pas de champ `.searchable` : iOS 26 le place en bas
        // de l'écran, lu en dernier ; un bouton ouvre l'écran de recherche.
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ChatRoute.self) { route in
            switch route {
            case .chat(let chatId):
                ConversationPlaceholderView(title: title(of: chatId))
            case .archive:
                ArchiveView(store: model.store, service: service)
            case .search:
                GlobalSearchView(store: model.store, service: service)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(value: ChatRoute.search) {
                    Label("Rechercher", systemImage: "magnifyingglass")
                }
                filterMenu
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    // Mention « client non officiel » ici plutôt qu'en bas de la liste : en pied
                    // de liste, elle échouait à l'audit de contraste (contenu défilant dessous)
                    // et VoiceOver la lisait après toutes les conversations.
                    Section("\(RootView.appName) est un client Telegram non officiel.") {
                        Button("Se déconnecter", role: .destructive) {
                            confirmsLogout = true
                        }
                        .disabled(auth.isBusy)
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        // Alerte plutôt que `confirmationDialog`, pour que « Annuler » reste visible
        // (voir `ChatDeletionDialogModifier`).
        .alert("Se déconnecter de Telegram sur cet appareil ?", isPresented: $confirmsLogout) {
            Button("Se déconnecter", role: .destructive) { auth.logOut() }
            Button("Annuler", role: .cancel) {}
        }
        .chatDeletionDialog(model)
        .task { await model.loadMore() }
        .onChange(of: model.store.state.connection, initial: true) { _, status in
            model.connectionChanged(status)
        }
        .onChange(of: auth.errorCount) {
            if let message = auth.errorMessage { Announcer.announce(message) }
        }
    }

    /// Menu de choix du filtre. VoiceOver : « Filtre : Non lus », puis dans le menu chaque
    /// filtre avec son nombre de conversations, le filtre actif annoncé « sélectionné ».
    private var filterMenu: some View {
        Menu {
            Picker("Filtre", selection: Binding(get: { model.filter }, set: { model.select($0) })) {
                ForEach(ChatFilter.allCases, id: \.self) { filter in
                    Text(filter.menuTitle(count: model.count(for: filter))).tag(filter)
                }
            }
        } label: {
            Label(
                "Filtre",
                systemImage: model.filter == .all
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
        }
        .accessibilityLabel(model.filter.buttonLabel)
    }

    @ViewBuilder
    private var listSections: some View {
        if model.filter != .all {
            Section {
                // Rappel visible du filtre actif (VoiceOver : déjà dans le bouton Filtre).
                Button("Filtre : \(model.filter.name). Tout afficher") {
                    model.select(.all)
                }
            }
        }
        if let connection = model.connectionText {
            Section {
                // Pas de `Label` : l'audit Dynamic Type signale son texte comme coupé aux
                // grandes tailles. Ici le texte passe à la ligne.
                IconText(text: connection, systemImage: "wifi.exclamationmark")
                    .readableSecondary()
            }
        }
        Section {
            if let archive = archiveLabel, model.filter == .all {
                NavigationLink(value: ChatRoute.archive) {
                    IconText(text: "Archives", systemImage: "archivebox")
                }
                .accessibilityLabel(archive)
            }
            ChatRows(model: model, emptyText: model.filter.emptyText, rotorNamespace: rotorNamespace)
        }
    }

    /// Libellé de la ligne Archives, `nil` s'il n'y a aucune conversation archivée.
    private var archiveLabel: String? {
        let state = model.store.state
        let loaded = state.orderedIds[.archive]?.count ?? 0
        let counts = state.listCounts[.archive]
        let total = max(counts?.total ?? 0, loaded)
        guard total > 0 else { return nil }
        return ChatActionLabels.archiveRow(total: total, unread: counts?.unread ?? 0)
    }

    private func title(of chatId: Int64) -> String {
        let state = model.store.state
        return state.chats[chatId].map { state.displayTitle(of: $0) } ?? "Conversation"
    }
}

/// Conversations archivées.
struct ArchiveView: View {
    @State private var model: ChatListViewModel
    @Namespace private var rotorNamespace

    init(store: ChatStore, service: any ChatListService) {
        _model = State(initialValue: ChatListViewModel(list: .archive, store: store, service: service))
    }

    var body: some View {
        List {
            Section {
                ChatRows(model: model, emptyText: "Aucune conversation archivée.", rotorNamespace: rotorNamespace)
            }
        }
        .listStyle(.plain)
        .chatRotors(model, namespace: rotorNamespace)
        .navigationTitle("Archives")
        .navigationBarTitleDisplayMode(.inline)
        .chatDeletionDialog(model)
        .task { await model.loadMore() }
    }
}

/// Lignes d'une liste de conversations : chargement, liste vide, conversations et leurs actions.
struct ChatRows: View {
    let model: ChatListViewModel
    let emptyText: String
    /// Espace des rotors : chaque ligne y est repérée, même hors écran.
    let rotorNamespace: Namespace.ID

    var body: some View {
        let items = model.rows
        let now = Date()
        if items.isEmpty {
            if model.isFullyLoaded {
                Text(emptyText)
                    .readableSecondary()
            } else {
                ProgressView("Chargement des conversations…")
            }
        } else {
            ForEach(items) { row in
                NavigationLink(value: ChatRoute.chat(row.id)) {
                    ChatRow(row: row, now: now)
                }
                .chatRowAccessibility(row, now: now)
                .accessibilityActions {
                    ForEach(model.actions(for: row), id: \.self) { action in
                        Button(ChatActionLabels.name(action, for: row)) {
                            model.perform(action, on: row)
                        }
                    }
                }
                .modifier(ChatSwipeActions(row: row, model: model))
                .accessibilityRotorEntry(id: row.id, in: rotorNamespace)
                .onAppear { model.rowAppeared(row.id) }
            }
            if !model.isFullyLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Chargement de conversations supplémentaires")
            }
        }
    }
}

/// Actions par balayage, pour l'usage sans VoiceOver. Désactivées sous VoiceOver : SwiftUI
/// les exposerait aussi comme actions, en doublon des actions personnalisées.
private struct ChatSwipeActions: ViewModifier {
    let row: ChatRowModel
    let model: ChatListViewModel
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    func body(content: Content) -> some View {
        if voiceOverEnabled {
            content
        } else {
            let actions = model.actions(for: row)
            content
                .swipeActions(edge: .leading) {
                    ForEach(actions.filter(Self.isLeading), id: \.self) { button($0) }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    ForEach(actions.filter { !Self.isLeading($0) }.reversed(), id: \.self) { button($0) }
                }
        }
    }

    private static func isLeading(_ action: ChatRowAction) -> Bool {
        switch action {
        case .markAsRead, .markAsUnread, .pin, .unpin: return true
        case .mute, .unmute, .archive, .unarchive, .delete: return false
        }
    }

    private func button(_ action: ChatRowAction) -> some View {
        Button {
            model.perform(action, on: row)
        } label: {
            Label(ChatActionLabels.name(action, for: row), systemImage: Self.icon(action))
        }
        .tint(Self.tint(action))
    }

    private static func icon(_ action: ChatRowAction) -> String {
        switch action {
        case .markAsRead: return "envelope.open"
        case .markAsUnread: return "envelope.badge"
        case .pin: return "pin"
        case .unpin: return "pin.slash"
        case .mute: return "bell.slash"
        case .unmute: return "bell"
        case .archive: return "archivebox"
        case .unarchive: return "tray.and.arrow.up"
        case .delete: return "trash"
        }
    }

    private static func tint(_ action: ChatRowAction) -> Color {
        switch action {
        case .delete: return Color("DestructiveColor")
        case .markAsRead, .markAsUnread: return .accentColor
        case .pin, .unpin: return Color(red: 0.55, green: 0.35, blue: 0.0)
        case .mute, .unmute: return Color(red: 0.35, green: 0.35, blue: 0.40)
        case .archive, .unarchive: return Color(red: 0.25, green: 0.30, blue: 0.45)
        }
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
            // Seule la variante à clé accepte une valeur absente (`nil` : rien n'est ajouté).
            .accessibilityCustomContent(
                AccessibilityCustomContentKey(Text("État"), id: "chat.state"),
                extra.state.map { Text(verbatim: $0) }
            )
            .accessibilityCustomContent(
                AccessibilityCustomContentKey(Text("Brouillon"), id: "chat.draft"),
                extra.draft.map { Text(verbatim: $0) }
            )
            .accessibilityCustomContent(
                AccessibilityCustomContentKey(Text("Type"), id: "chat.type"),
                extra.type.map { Text(verbatim: $0) }
            )
    }

    /// Rotors VoiceOver « Non lus », « Mentions », « Épinglées » : aller directement d'une
    /// conversation concernée à la suivante, y compris hors écran.
    func chatRotors(_ model: ChatListViewModel, namespace: Namespace.ID) -> some View {
        let rows = model.rows
        let unread = rows.filter(ChatRotor.unread.matches)
        let mentions = rows.filter(ChatRotor.mentions.matches)
        let pinned = rows.filter(ChatRotor.pinned.matches)
        return self
            .accessibilityRotor(Text(ChatRotor.unread.name)) {
                ForEach(unread) { AccessibilityRotorEntry(Text($0.title), id: $0.id, in: namespace) }
            }
            .accessibilityRotor(Text(ChatRotor.mentions.name)) {
                ForEach(mentions) { AccessibilityRotorEntry(Text($0.title), id: $0.id, in: namespace) }
            }
            .accessibilityRotor(Text(ChatRotor.pinned.name)) {
                ForEach(pinned) { AccessibilityRotorEntry(Text($0.title), id: $0.id, in: namespace) }
            }
    }

    /// Dialogue de confirmation de suppression (ou de sortie d'un groupe / d'une chaîne).
    func chatDeletionDialog(_ model: ChatListViewModel) -> some View {
        modifier(ChatDeletionDialogModifier(model: model))
    }
}

/// Alerte plutôt que `confirmationDialog` : depuis iOS 26 (et sur iPad), la feuille d'actions
/// s'affiche près de la ligne et masque le bouton « Annuler » (fermeture en touchant à côté).
/// L'alerte, centrée et modale, affiche toujours « Annuler », que VoiceOver lit avec les autres
/// boutons ; le geste d'échappement l'active aussi.
private struct ChatDeletionDialogModifier: ViewModifier {
    @Bindable var model: ChatListViewModel

    func body(content: Content) -> some View {
        let request = model.deletionRequest
        let dialog = request.map { ChatActionLabels.deletionDialog(for: $0) }
        content.alert(
            Text(dialog?.title ?? ""),
            isPresented: Binding(
                get: { model.deletionRequest != nil },
                set: { if !$0 { model.deletionRequest = nil } }
            ),
            presenting: request
        ) { row in
            if let dialog {
                Button(dialog.confirm, role: .destructive) {
                    model.confirmDeletion(of: row, forEveryone: false)
                }
                if let forEveryone = dialog.confirmForEveryone {
                    Button(forEveryone, role: .destructive) {
                        model.confirmDeletion(of: row, forEveryone: true)
                    }
                }
            }
            Button("Annuler", role: .cancel) {}
        }
    }
}

/// Icône décorative suivie d'un texte qui passe à la ligne aux grandes tailles (contrairement
/// à `Label`, signalé comme coupé par l'audit Dynamic Type).
struct IconText: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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
