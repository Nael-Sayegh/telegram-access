import XCTest

/// Audit d'accessibilité commun aux tests UI.
enum AccessibilityAudit {
    /// Lance l'audit et signale tous les problèmes d'un coup (au lieu de s'arrêter au premier),
    /// avec le libellé de l'élément concerné.
    ///
    /// Ignorés (voir `ignoredReason`) :
    /// - « Dynamic Type font sizes are partially unsupported » sur des textes et boutons SwiftUI
    ///   qui utilisent tous les styles de texte système. L'audit agrandit la police, et dans une
    ///   liste les lignes qui sortent alors de l'écran ne sont plus mesurables : faux positif
    ///   connu, qui ne touche que les écrans assez longs. Le cas « unsupported » (police fixe)
    ///   reste vérifié ;
    /// - les éléments du clavier système (barre de suggestions), ouvert par Répondre ou
    ///   Modifier : ils n'appartiennent pas à l'app ;
    /// - le contraste d'un élément passé sous la barre de navigation : iOS 26 estompe le contenu
    ///   qui défile dessous. Ramené à l'écran, il est lisible, et contrôlé par les autres audits.
    ///
    /// `excluding` : vérifications que l'audit ne sait pas mener sur un écran donné. À réserver
    /// aux cas expliqués sur place, avec un test qui contrôle la même chose autrement.
    @MainActor
    static func run(
        _ app: XCUIApplication,
        excluding excluded: XCUIAccessibilityAuditType = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let navigationBar = app.navigationBars.firstMatch
        let keyboard = app.keyboards.firstMatch
        let keyboardFrame = keyboard.exists ? keyboard.frame : .null
        var problems: [String] = []
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(excluded)) { issue in
            let element = issue.element.map { "« \($0.label) »" } ?? "élément inconnu"
            let description = "\(issue.compactDescription) — \(element) — \(issue.detailedDescription)"
            if let reason = ignoredReason(issue, navigationBar: navigationBar, keyboardFrame: keyboardFrame) {
                print("Audit ignoré (\(reason)) : \(description)")
                return true
            }
            problems.append(description)
            return true
        }
        if !problems.isEmpty {
            // Capture jointe au rapport : un problème sans élément identifié (« élément
            // inconnu ») se repère à l'image.
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Écran audité"
            screenshot.lifetime = .keepAlways
            XCTContext.runActivity(named: "Capture de l'écran audité") { $0.add(screenshot) }
            XCTFail("Problèmes d'accessibilité :\n" + problems.joined(separator: "\n"), file: file, line: line)
        }
    }

    /// Raison d'ignorer un problème, `nil` s'il doit être signalé.
    @MainActor
    private static func ignoredReason(
        _ issue: XCUIAccessibilityAuditIssue,
        navigationBar: XCUIElement,
        keyboardFrame: CGRect
    ) -> String? {
        if issue.auditType == .dynamicType,
           issue.compactDescription == "Dynamic Type font sizes are partially unsupported" {
            return "taille de texte, faux positif connu"
        }
        // Cellules de la barre de suggestions du clavier (« TUIPredictionViewCell »).
        if issue.detailedDescription.contains("TUIPrediction") {
            return "clavier système"
        }
        guard let element = issue.element, element.exists else { return nil }
        let frame = element.frame
        if keyboardFrame.intersects(frame) {
            return "clavier système"
        }
        // Contenu de la liste qui déborde sous la barre ; les éléments de la barre elle-même
        // (titre, boutons) restent contrôlés.
        if issue.auditType == .contrast, navigationBar.exists, frame.minY < navigationBar.frame.maxY {
            let inBar = navigationBar.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", element.label))
                .firstMatch
            if !inBar.exists {
                return "sous la barre de navigation"
            }
        }
        return nil
    }
}
