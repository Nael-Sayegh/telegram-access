import SwiftUI

/// Filtres de la liste principale. Boutons sur plusieurs lignes si nécessaire plutôt qu'un
/// contrôle segmenté, dont les libellés seraient coupés aux grandes tailles de texte.
/// VoiceOver : groupe « Filtres », puis « Non lus, 4 conversations, sélectionné, bouton ».
struct ChatFilterBar: View {
    let model: ChatListViewModel

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(ChatFilter.allCases, id: \.self) { filter in
                FilterButton(
                    title: filter.name,
                    accessibilityLabel: filter.accessibilityLabel(count: model.count(for: filter)),
                    isSelected: model.filter == filter
                ) {
                    model.select(filter)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filtres")
    }
}

private struct FilterButton: View {
    let title: String
    let accessibilityLabel: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                .background(Capsule().fill(isSelected ? Color.accentColor : Color.clear))
                .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5))
        }
        // Sans style « borderless », une ligne de liste déclencherait tous ses boutons à la fois.
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Dispose ses éléments de gauche à droite et passe à la ligne quand la place manque.
/// Un élément plus large que la ligne reçoit toute la largeur (son texte passe à la ligne).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > width {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.items.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append(Item(index: index, size: size))
        }
        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
