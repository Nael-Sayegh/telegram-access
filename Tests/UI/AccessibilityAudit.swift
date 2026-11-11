import XCTest

/// Audit d'accessibilité commun aux tests UI.
enum AccessibilityAudit {
    /// Lance l'audit et signale tous les problèmes d'un coup (au lieu de s'arrêter au premier),
    /// avec le libellé de l'élément concerné.
    ///
    /// Ignoré : « Dynamic Type font sizes are partially unsupported » sur des textes et boutons
    /// SwiftUI qui utilisent tous les styles de texte système. L'audit agrandit la police, et dans
    /// une liste les lignes qui sortent alors de l'écran ne sont plus mesurables : faux positif
    /// connu, qui ne touche que les écrans assez longs. Le cas « unsupported » (police fixe)
    /// reste vérifié.
    @MainActor
    static func run(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        var problems: [String] = []
        try app.performAccessibilityAudit { issue in
            let element = issue.element.map { "« \($0.label) »" } ?? "élément inconnu"
            let description = "\(issue.compactDescription) — \(element) — \(issue.detailedDescription)"
            if issue.auditType == .dynamicType,
               issue.compactDescription == "Dynamic Type font sizes are partially unsupported" {
                print("Audit ignoré : \(description)")
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
}
