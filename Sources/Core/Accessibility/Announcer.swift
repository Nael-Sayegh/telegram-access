import SwiftUI

/// Annonces VoiceOver centralisées.
@MainActor
enum Announcer {
    /// Annonce prioritaire (erreur, résultat d'une action demandée par l'utilisateur).
    static func announce(_ text: String) {
        var message = AttributedString(text)
        message.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(message).post()
    }

    /// Annonce mise en file d'attente, sans interrompre la parole en cours (messages entrants…).
    static func announceQueued(_ text: String) {
        var message = AttributedString(text)
        message.accessibilitySpeechAnnouncementPriority = .low
        AccessibilityNotification.Announcement(message).post()
    }
}
