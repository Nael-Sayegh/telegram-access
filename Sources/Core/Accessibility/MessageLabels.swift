import Foundation

/// Description d'un contenu de message, lue par VoiceOver et affichée en aperçu.
/// Fonctions pures, testées unitairement. Enrichies en phase 3 (écran de conversation).
enum MessageLabels {
    /// « Photo : légende », « Message vocal, 12 secondes », « Autocollant 😀 »…
    static func content(_ content: MessageContentSummary) -> String {
        switch content {
        case .text(let text):
            return text
        case .photo(let caption):
            return withCaption("Photo", caption)
        case .video(let duration, let caption):
            return withCaption("Vidéo, \(AuthLabels.duration(duration))", caption)
        case .animation(let caption):
            return withCaption("GIF", caption)
        case .voiceNote(let duration, let caption):
            return withCaption("Message vocal, \(AuthLabels.duration(duration))", caption)
        case .videoNote(let duration):
            return "Message vidéo, \(AuthLabels.duration(duration))"
        case .audio(let title, let performer, let duration, let caption):
            let name = [performer, title]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            let base = name.isEmpty ? "Audio" : "Audio, \(name)"
            return withCaption("\(base), \(AuthLabels.duration(duration))", caption)
        case .document(let fileName, let size, let caption):
            var parts = ["Fichier"]
            let name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { parts.append(name) }
            if size > 0 { parts.append(fileSize(size)) }
            return withCaption(parts.joined(separator: ", "), caption)
        case .sticker(let emoji):
            return emoji.isEmpty ? "Autocollant" : "Autocollant \(emoji)"
        case .location:
            return "Position"
        case .venue:
            return "Lieu"
        case .contact(let firstName, let lastName):
            let name = UserName(firstName: firstName, lastName: lastName, isDeleted: false)
            return [firstName, lastName].allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty })
                ? "Contact"
                : "Contact : \(name.displayName)"
        case .poll(let question):
            return withCaption("Sondage", question)
        case .call(let isVideo, let duration, let outcome):
            let kind = isVideo ? "Appel vidéo" : "Appel"
            switch outcome {
            case .missed: return "\(kind) manqué"
            case .declined: return "\(kind) refusé"
            case .ended: return duration > 0 ? "\(kind), \(AuthLabels.duration(duration))" : kind
            }
        case .story:
            return "Story"
        case .groupCreated:
            return "Groupe créé"
        case .titleChanged(let title):
            return "Nom changé en « \(title) »"
        case .photoChanged:
            return "Photo du groupe modifiée"
        case .membersAdded:
            return "Membres ajoutés"
        case .memberRemoved:
            return "Membre retiré"
        case .pinnedMessage:
            return "Message épinglé"
        case .unsupported:
            return "Message non pris en charge"
        }
    }

    /// Taille lisible : « 512 octets », « 350 Ko », « 2,4 Mo », « 12 Mo », « 1,1 Go ».
    static func fileSize(_ bytes: Int64) -> String {
        let kilo = 1024.0
        let value = Double(max(0, bytes))
        if value < kilo {
            let count = Int(value)
            return "\(count) octet\(count > 1 ? "s" : "")"
        }
        if value < kilo * kilo {
            return "\(Int((value / kilo).rounded())) Ko"
        }
        if value < kilo * kilo * kilo {
            return "\(decimal(value / (kilo * kilo))) Mo"
        }
        return "\(decimal(value / (kilo * kilo * kilo))) Go"
    }

    /// Une décimale sous 10 (« 2,4 »), entier au-delà (« 12 »), virgule française.
    private static func decimal(_ value: Double) -> String {
        if value >= 10 {
            return String(Int(value.rounded()))
        }
        let tenths = Int((value * 10).rounded())
        return tenths % 10 == 0 ? String(tenths / 10) : "\(tenths / 10),\(tenths % 10)"
    }

    private static func withCaption(_ base: String, _ caption: String) -> String {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? base : "\(base) : \(trimmed)"
    }
}
