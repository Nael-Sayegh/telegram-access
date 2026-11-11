import SwiftUI
import UIKit

/// Liste des messages d'une conversation.
///
/// `UICollectionView` à source de données « diffable » identifiée par message : quand
/// l'historique s'insère au-dessus ou qu'un message arrive, les cellules existantes sont
/// conservées et le focus VoiceOver reste sur le même message ; le premier message visible
/// garde sa place à l'écran. Un message = un élément VoiceOver (la cellule), un jour = un
/// en-tête (rotor En-têtes).
final class ConversationViewController: UIViewController, UICollectionViewDelegate {
    /// Un message va s'afficher (chargement de la suite près d'un bord).
    var onMessageAppear: (@MainActor (Int64) -> Void)?
    /// Messages visibles une fois le défilement arrêté (lecture).
    var onVisibleMessages: (@MainActor ([Int64]) -> Void)?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Date, Int64>!
    private var sections: [ConversationSection] = []
    private var rows: [Int64: MessageRowModel] = [:]
    private var titles: [Date: String] = [:]
    private var handledFocusSerial = 0
    private var handledScrollRequest = 0
    private var visibleReportTask: Task<Void, Never>?
    /// Vrai quand la liste montre le dernier message : elle y reste si sa hauteur change
    /// (ouverture du clavier). Mis à jour après chaque défilement terminé.
    private var isPinnedToBottom = true
    private var lastHeight: CGFloat = 0

    /// Marge (en points) sous laquelle on considère la liste « en bas ».
    private static let bottomTolerance: CGFloat = 60

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.showsSeparators = false
        configuration.headerMode = .supplementary
        configuration.backgroundColor = .systemBackground
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)

        let collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.delegate = self
        // Pas de sélection : l'activation (lecture d'un vocal, lien) arrive avec les actions.
        collectionView.allowsSelection = false
        collectionView.keyboardDismissMode = .interactive
        view.addSubview(collectionView)
        self.collectionView = collectionView

        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Int64> { [weak self] cell, _, id in
            guard let row = self?.rows[id] else { return }
            MessageCellConfigurator.configure(cell, with: row)
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            guard let self, let day = self.dataSource.sectionIdentifier(for: indexPath.section) else { return }
            MessageCellConfigurator.configureHeader(header, title: self.titles[day] ?? "")
        }
        dataSource = UICollectionViewDiffableDataSource<Date, Int64>(collectionView: collectionView) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }

        // Taille du texte changée (Réglages, Centre de contrôle) : les bulles grandissent, les
        // hauteurs des cellules doivent être recalculées, sinon le texte serait coupé.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _: UITraitCollection) in
            self.refreshAllCells()
        }
    }

    /// Reconfigure toutes les cellules sur place (sans les recréer : le focus VoiceOver est
    /// conservé) et recalcule la mise en page.
    private func refreshAllCells() {
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
        collectionView.collectionViewLayout.invalidateLayout()
    }

    /// Le clavier réduit la hauteur de la liste : si l'on voyait le dernier message, on le
    /// garde à l'écran.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let height = collectionView.bounds.height
        guard height != lastHeight else { return }
        let sticks = isPinnedToBottom && lastHeight > 0
        lastHeight = height
        if sticks {
            scrollToBottom(animated: false)
        }
    }

    // MARK: - Mise à jour

    /// Affiche `newSections` sans recharger les cellules inchangées, puis traite les demandes
    /// nouvelles : focus sur un message (action de l'utilisateur), défilement en bas (envoi).
    func update(sections newSections: [ConversationSection], focus: MessageFocusRequest?, scrollToBottomRequest: Int) {
        loadViewIfNeeded()
        if newSections != sections {
            apply(newSections)
        }
        if let focus, focus.serial != handledFocusSerial {
            moveFocus(to: focus)
        }
        if scrollToBottomRequest != handledScrollRequest {
            handledScrollRequest = scrollToBottomRequest
            scrollToBottom(animated: true)
        }
    }

    private func apply(_ newSections: [ConversationSection]) {
        let previousRows = rows
        let previousLastId = sections.last?.rows.last?.id
        let anchor = topAnchor()
        let wasAtBottom = isAtBottom

        sections = newSections
        let allRows = newSections.flatMap(\.rows)
        rows = Dictionary(allRows.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        titles = Dictionary(newSections.map { ($0.id, $0.title) }, uniquingKeysWith: { _, last in last })

        var snapshot = NSDiffableDataSourceSnapshot<Date, Int64>()
        for section in newSections {
            snapshot.appendSections([section.id])
            snapshot.appendItems(section.rows.map(\.id), toSection: section.id)
        }
        // Même message, contenu changé (lu, modifié, réaction…) : cellule reconfigurée sur place.
        let changedIds = allRows.filter { row in previousRows[row.id].map { $0 != row } ?? false }.map(\.id)
        if !changedIds.isEmpty {
            snapshot.reconfigureItems(changedIds)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
        collectionView.layoutIfNeeded()

        if let anchor {
            restore(anchor)
        }
        // Sans VoiceOver, on suit les nouveaux messages si l'on était déjà en bas. Sous
        // VoiceOver, rien ne bouge : le focus ne doit jamais sauter.
        let lastId = newSections.last?.rows.last?.id
        if wasAtBottom, previousLastId != nil, lastId != previousLastId, !UIAccessibility.isVoiceOverRunning {
            scrollToBottom(animated: true)
        }
        reportVisibleSoon()
    }

    /// Amène le message à l'écran et y place le focus VoiceOver.
    private func moveFocus(to request: MessageFocusRequest) {
        guard let indexPath = dataSource.indexPath(for: request.messageId) else { return }
        handledFocusSerial = request.serial
        let position: UICollectionView.ScrollPosition = request.position == .top ? .top : .bottom
        // Deux passes : les hauteurs estimées des cellules sont corrigées par la première.
        collectionView.scrollToItem(at: indexPath, at: position, animated: false)
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(at: indexPath, at: position, animated: false)
        collectionView.layoutIfNeeded()
        if let cell = collectionView.cellForItem(at: indexPath) {
            UIAccessibility.post(notification: .layoutChanged, argument: cell)
        }
        isPinnedToBottom = isAtBottom
        reportVisibleSoon()
    }

    // MARK: - Position

    private struct Anchor {
        let id: Int64
        /// Distance entre le haut du message et le haut de la zone visible.
        let offset: CGFloat
    }

    private func topAnchor() -> Anchor? {
        for indexPath in collectionView.indexPathsForVisibleItems.sorted() {
            guard let id = dataSource.itemIdentifier(for: indexPath),
                  let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { continue }
            return Anchor(id: id, offset: attributes.frame.minY - collectionView.contentOffset.y)
        }
        return nil
    }

    private func restore(_ anchor: Anchor) {
        guard let indexPath = dataSource.indexPath(for: anchor.id),
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }
        let inset = collectionView.adjustedContentInset
        let maxOffset = max(-inset.top, collectionView.contentSize.height + inset.bottom - collectionView.bounds.height)
        let target = min(max(attributes.frame.minY - anchor.offset, -inset.top), maxOffset)
        if abs(target - collectionView.contentOffset.y) > 0.5 {
            collectionView.contentOffset.y = target
        }
    }

    private var isAtBottom: Bool {
        let visibleBottom = collectionView.contentOffset.y + collectionView.bounds.height
            - collectionView.adjustedContentInset.bottom
        return visibleBottom >= collectionView.contentSize.height - Self.bottomTolerance
    }

    private func scrollToBottom(animated: Bool) {
        guard let last = sections.last?.rows.last, let indexPath = dataSource.indexPath(for: last.id) else { return }
        collectionView.scrollToItem(at: indexPath, at: .bottom, animated: animated)
        isPinnedToBottom = true
    }

    // MARK: - Délégué

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        onMessageAppear?(id)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        reportVisibleSoon()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            isPinnedToBottom = isAtBottom
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        isPinnedToBottom = isAtBottom
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isPinnedToBottom = isAtBottom
    }

    /// Signale les messages visibles une demi-seconde après le dernier mouvement : un message
    /// seulement survolé pendant un défilement n'est pas compté comme lu.
    private func reportVisibleSoon() {
        visibleReportTask?.cancel()
        visibleReportTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.reportVisible()
        }
    }

    private func reportVisible() {
        let visibleArea = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
        let ids = collectionView.indexPathsForVisibleItems.compactMap { indexPath -> Int64? in
            guard let attributes = collectionView.layoutAttributesForItem(at: indexPath),
                  visibleArea.intersects(attributes.frame) else { return nil }
            return dataSource.itemIdentifier(for: indexPath)
        }
        if !ids.isEmpty {
            onVisibleMessages?(ids)
        }
    }
}

/// Contenu et accessibilité des cellules de la liste des messages.
///
/// La cellule UIKit est l'élément VoiceOver (un message = un élément, libellé complet) : c'est
/// elle que viseront les actions personnalisées et les rotors. L'audit automatique ne sait pas
/// vérifier la taille du texte d'un tel élément (le texte est dans la bulle SwiftUI) : elle
/// est contrôlée par un test UI dédié, qui lance l'app en très grande taille de texte.
@MainActor
enum MessageCellConfigurator {
    static func configure(_ cell: UICollectionViewListCell, with row: MessageRowModel) {
        cell.contentConfiguration = UIHostingConfiguration {
            MessageBubble(row: row)
        }
        .margins(.horizontal, 12)
        .margins(.vertical, 3)
        cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = ConversationLabels.message(row, calendar: .current)
        cell.accessibilityTraits = .staticText
    }

    /// En-tête de jour : centré, en couleur de texte principale (contraste), annoncé comme
    /// en-tête ; fond opaque, car l'en-tête reste épinglé en haut pendant le défilement.
    static func configureHeader(_ header: UICollectionViewListCell, title: String) {
        var content = UIListContentConfiguration.plainHeader()
        content.text = title
        content.textProperties.font = UIFont.preferredFont(forTextStyle: .subheadline)
        content.textProperties.adjustsFontForContentSizeCategory = true
        content.textProperties.color = .label
        content.textProperties.alignment = .center
        content.textProperties.numberOfLines = 0
        header.contentConfiguration = content
        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = .systemBackground
        header.backgroundConfiguration = background
        header.accessibilityTraits = .header
    }
}
