import SwiftUI

/// Lecteur du vocal en cours, entre la liste et la barre de rédaction (pas superposé : aucun
/// message caché derrière). Ordre VoiceOver : lecture / pause, position, vitesse, fermer.
///
/// La position est réglable : balayer vers le haut avance de 5 secondes, vers le bas recule ;
/// VoiceOver lit la nouvelle position (« 17 secondes sur 40 secondes »).
struct VoicePlayerBar: View {
    let player: VoicePlayer
    @ScaledMetric(relativeTo: .title2) private var playIconSize: CGFloat = 32

    var body: some View {
        if let playback = player.current {
            HStack(spacing: 8) {
                Button {
                    player.togglePause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .resizable()
                        .frame(width: playIconSize, height: playIconSize)
                        .frame(minWidth: 44, minHeight: 44)
                        .foregroundStyle(Color.accentColor)
                }
                .disabled(playback.isLoading)
                .accessibilityLabel(playback.isPlaying ? VoiceLabels.pause : VoiceLabels.resume)
                .accessibilityAddTraits(.startsMediaSession)

                VStack(alignment: .leading, spacing: 2) {
                    Text(playback.title)
                        .font(.subheadline.weight(.semibold))
                    Text(playback.isLoading
                         ? "\(VoiceLabels.loading)…"
                         : VoiceLabels.visiblePosition(playback.position, of: playback.duration))
                        .font(.footnote)
                        .monospacedDigit()
                }
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(playback.title)
                .accessibilityValue(playback.isLoading
                                    ? VoiceLabels.loading
                                    : VoiceLabels.position(playback.position, of: playback.duration))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: player.seek(by: VoiceLabels.seekStep)
                    case .decrement: player.seek(by: -VoiceLabels.seekStep)
                    @unknown default: break
                    }
                }

                Button {
                    player.cycleRate()
                } label: {
                    Text(VoiceLabels.visibleRate(player.rate))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(VoiceLabels.rate(player.rate))

                Button {
                    player.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(VoiceLabels.close)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(uiColor: .systemBackground))
            .overlay(alignment: .top) { Divider() }
        }
    }
}
