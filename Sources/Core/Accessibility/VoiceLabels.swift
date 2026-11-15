import Foundation

/// Textes de la lecture des messages vocaux. Fonctions pures, testées unitairement.
enum VoiceLabels {
    static let listen = "Écouter"
    /// Indication sur un message vocal.
    static let listenHint = "Touchez deux fois pour écouter ou mettre en pause."
    static let resume = "Reprendre la lecture"
    static let pause = "Mettre en pause"
    static let close = "Fermer le lecteur"
    static let loading = "Chargement"
    static let failure = "Impossible de lire ce message vocal."
    static let downloadFailure = "Impossible de télécharger ce message vocal. Vérifiez votre connexion."
    /// Pas d'avance ou de recul (balayage vers le haut ou le bas sur la position).
    static let seekStep: TimeInterval = 5

    /// Vitesses proposées, dans l'ordre du bouton.
    static let rates: [Float] = [1, 1.5, 2]

    static func nextRate(after rate: Float) -> Float {
        guard let index = rates.firstIndex(of: rate) else { return rates[0] }
        return rates[(index + 1) % rates.count]
    }

    /// « Vitesse : 1,5 fois ».
    static func rate(_ rate: Float) -> String {
        "Vitesse : \(number(rate)) fois"
    }

    /// « 1,5× ».
    static func visibleRate(_ rate: Float) -> String {
        "\(number(rate))×"
    }

    /// « Message vocal de Marie Dupont », « Votre message vocal ».
    static func title(author: String?, isOutgoing: Bool) -> String {
        if isOutgoing { return "Votre message vocal" }
        guard let author, !author.isEmpty else { return "Message vocal" }
        return "Message vocal de \(author)"
    }

    /// Valeur de la position, lue par VoiceOver : « 12 secondes sur 40 secondes ».
    static func position(_ position: TimeInterval, of duration: TimeInterval) -> String {
        "\(AuthLabels.duration(Int(position.rounded(.down)))) sur \(AuthLabels.duration(Int(duration.rounded())))"
    }

    /// « 0:12 / 0:40 ».
    static func visiblePosition(_ position: TimeInterval, of duration: TimeInterval) -> String {
        "\(clock(position.rounded(.down))) / \(clock(duration.rounded()))"
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let rest = total % 60
        return "\(total / 60):\(rest < 10 ? "0" : "")\(rest)"
    }

    /// « 1 », « 1,5 », « 2 ».
    private static func number(_ value: Float) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
