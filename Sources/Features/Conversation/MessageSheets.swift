import SwiftUI

/// Feuille « Réagir » : une ligne par réaction proposée, l'émoji en grand (VoiceOver lit son
/// nom), la réaction déjà choisie annoncée « sélectionné » (la choisir à nouveau la retire).
struct ReactionPicker: View {
    let row: MessageRowModel
    let model: ConversationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // `nil` pendant le chargement des réactions proposées.
                if let choices = model.reactionChoices {
                    if choices.isEmpty {
                        Text("Aucune réaction disponible pour ce message.")
                    }
                    ForEach(choices, id: \.self) { kind in
                        let isChosen = row.reactions.contains { $0.kind == kind && $0.isChosen }
                        Button {
                            model.toggleReaction(kind, on: row)
                        } label: {
                            HStack {
                                Text(ConversationLabels.reactionName(kind))
                                    .font(.largeTitle)
                                Spacer()
                                if isChosen {
                                    Image(systemName: "checkmark")
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .accessibilityAddTraits(isChosen ? .isSelected : [])
                    }
                } else {
                    ProgressView("Chargement des réactions…")
                }
            }
            .navigationTitle("Réagir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Feuille « Transférer à » : champ de recherche en haut, puis les conversations (liste
/// principale) par leur nom.
struct ForwardPicker: View {
    let targets: [ChatRowModel]
    let choose: (ChatRowModel) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [ChatRowModel] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return targets }
        return targets.filter { $0.title.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Sur plusieurs lignes, comme la recherche globale : rien n'est coupé aux
                    // grandes tailles de texte. Libellé explicite pour VoiceOver.
                    TextField("Rechercher une conversation", text: $query, axis: .vertical)
                        .lineLimit(1...3)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Rechercher une conversation")
                }
                Section {
                    if filtered.isEmpty {
                        Text("Aucune conversation trouvée.")
                    }
                    ForEach(filtered) { target in
                        Button {
                            choose(target)
                        } label: {
                            Text(target.title)
                                .foregroundStyle(Color.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .navigationTitle("Transférer à")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }
}
