import AVFoundation
import Observation

/// Vocal chargé dans le lecteur.
struct VoicePlayback: Equatable {
    let messageId: Int64
    /// « Message vocal de Marie Dupont ».
    var title: String
    var duration: TimeInterval
    var position: TimeInterval = 0
    var isPlaying = false
    /// Téléchargement ou décodage en cours.
    var isLoading = true
}

/// Lecture des messages vocaux d'une conversation, un seul à la fois : lecture / pause,
/// vitesse (1, 1,5 ou 2 fois), avance et recul de 5 secondes.
///
/// Le vocal OGG Opus est décodé (`VoiceNoteDecoder`) dans un fichier temporaire lu par
/// `AVAudioPlayer`, effacé à la fermeture du lecteur.
@MainActor
@Observable
final class VoicePlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var current: VoicePlayback?
    /// Gardée d'un vocal à l'autre.
    private(set) var rate: Float = 1

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var decodedFile: URL?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    /// Prépare le lecteur pour un vocal (affiché « Chargement » jusqu'à `play`).
    func load(messageId: Int64, title: String, duration: TimeInterval) {
        stop()
        current = VoicePlayback(messageId: messageId, title: title, duration: duration)
    }

    /// Décode le fichier OGG téléchargé et lance la lecture, si ce vocal est toujours celui du
    /// lecteur (un autre a pu être choisi entre-temps).
    func play(file: URL, messageId: Int64) async throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("vocal-\(UUID().uuidString).caf")
        let duration = try await Task.detached(priority: .userInitiated) {
            try VoiceNoteDecoder.decodeFile(at: file, to: destination)
        }.value
        guard current?.messageId == messageId, current?.isLoading == true else {
            try? FileManager.default.removeItem(at: destination)
            return
        }
        let player = try AVAudioPlayer(contentsOf: destination)
        player.enableRate = true
        player.rate = rate
        player.delegate = self
        player.prepareToPlay()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        self.player = player
        decodedFile = destination
        current?.duration = duration
        current?.isLoading = false
        resume()
    }

    /// Lecture / pause (Magic Tap, bouton, double toucher sur le message).
    func togglePause() {
        guard let current, !current.isLoading else { return }
        if current.isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        player?.pause()
        current?.isPlaying = false
        progressTask?.cancel()
        updatePosition()
    }

    func resume() {
        guard let player else { return }
        player.play()
        current?.isPlaying = true
        startProgress()
    }

    /// Avance (positif) ou recule (négatif), dans les limites du vocal.
    func seek(by delta: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, player.currentTime + delta), player.duration)
        updatePosition()
    }

    /// Vitesse suivante : 1 → 1,5 → 2 → 1.
    func cycleRate() {
        rate = VoiceLabels.nextRate(after: rate)
        player?.rate = rate
    }

    /// Ferme le lecteur et efface le fichier décodé.
    func stop() {
        progressTask?.cancel()
        progressTask = nil
        player?.stop()
        player = nil
        if let decodedFile {
            try? FileManager.default.removeItem(at: decodedFile)
        }
        decodedFile = nil
        if current != nil {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        current = nil
    }

    // MARK: - Privé

    private func startProgress() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.updatePosition()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func updatePosition() {
        guard let player else { return }
        current?.position = player.currentTime
        // Lecture arrêtée par le système (appel, autre app) : le bouton repasse sur « Reprendre ».
        if current?.isPlaying == true, !player.isPlaying {
            current?.isPlaying = false
            progressTask?.cancel()
        }
    }

    /// Fin du vocal : le lecteur reste ouvert, prêt à le réécouter depuis le début.
    private func finished() {
        progressTask?.cancel()
        player?.currentTime = 0
        current?.position = 0
        current?.isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.finished()
        }
    }
}
