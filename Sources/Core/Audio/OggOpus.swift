import Foundation

/// Flux Opus extrait d'un fichier OGG : le format des messages vocaux Telegram, qu'AVFoundation
/// ne lit pas directement (le décodage Opus d'AudioToolbox, lui, est disponible).
struct OggOpusStream: Equatable {
    /// Fréquence de travail d'Opus, quelle que soit celle de l'enregistrement d'origine.
    static let sampleRate = 48_000

    var channelCount: Int
    /// Échantillons à ignorer au début du décodage (amorçage du décodeur).
    var preSkip: Int
    /// Paquets audio dans l'ordre, sans les en-têtes « OpusHead » et « OpusTags ».
    var packets: [Data]
    /// Position de fin (granule de la dernière page), pré-saut compris ; 0 si inconnue.
    var finalGranule: Int64

    /// Échantillons utiles, `nil` si la position de fin est inconnue.
    var sampleCount: Int? {
        finalGranule > 0 ? max(0, Int(finalGranule) - preSkip) : nil
    }
}

enum OggOpusError: Error, Equatable {
    /// Pas un fichier OGG.
    case notOgg
    /// Fichier coupé (téléchargement incomplet…).
    case truncated
    /// OGG, mais sans en-tête Opus.
    case notOpus
    case unsupportedChannels(Int)
    case noAudio
}

/// Lecture d'un fichier OGG Opus (RFC 3533 pour le conteneur, RFC 7845 pour Opus dans OGG).
/// Fonctions pures, testées unitairement sur un vrai vocal.
enum OggOpusReader {
    static func read(_ data: Data) throws -> OggOpusStream {
        let bytes = [UInt8](data)
        var offset = 0
        var packets: [Data] = []
        var partial: [UInt8] = []
        var serial: UInt64?
        var finalGranule: Int64 = 0
        while offset < bytes.count {
            guard offset + 4 <= bytes.count, bytes[offset ..< offset + 4].elementsEqual([0x4F, 0x67, 0x67, 0x53]) else {
                // « OggS » absent : pas de l'OGG au début, données abîmées ensuite.
                throw serial == nil ? OggOpusError.notOgg : OggOpusError.truncated
            }
            guard offset + 27 <= bytes.count else { throw OggOpusError.truncated }
            let granule = Int64(bitPattern: littleEndian(bytes, at: offset + 6, count: 8))
            let pageSerial = littleEndian(bytes, at: offset + 14, count: 4)
            let segmentCount = Int(bytes[offset + 26])
            let lacingStart = offset + 27
            guard lacingStart + segmentCount <= bytes.count else { throw OggOpusError.truncated }
            let lacing = bytes[lacingStart ..< lacingStart + segmentCount]
            var bodyOffset = lacingStart + segmentCount
            let bodyEnd = bodyOffset + lacing.reduce(0) { $0 + Int($1) }
            guard bodyEnd <= bytes.count else { throw OggOpusError.truncated }
            if serial == nil {
                serial = pageSerial
            }
            // Un seul flux logique : les autres (rares) sont ignorés.
            if pageSerial == serial {
                for value in lacing {
                    partial += bytes[bodyOffset ..< bodyOffset + Int(value)]
                    bodyOffset += Int(value)
                    // Un segment de 255 octets continue le paquet, sur cette page ou la suivante.
                    if value < 255 {
                        packets.append(Data(partial))
                        partial = []
                    }
                }
                // -1 : aucun paquet ne se termine sur la page.
                if granule > 0 {
                    finalGranule = granule
                }
            }
            offset = bodyEnd
        }
        guard packets.count >= 2,
              packets[0].count >= 19,
              packets[0].starts(with: Array("OpusHead".utf8)),
              packets[1].starts(with: Array("OpusTags".utf8)) else {
            throw serial == nil ? OggOpusError.notOgg : OggOpusError.notOpus
        }
        let head = [UInt8](packets[0])
        let channels = Int(head[9])
        guard channels == 1 || channels == 2 else { throw OggOpusError.unsupportedChannels(channels) }
        let preSkip = Int(littleEndian(head, at: 10, count: 2))
        let audio = packets.dropFirst(2).filter { !$0.isEmpty }
        guard !audio.isEmpty else { throw OggOpusError.noAudio }
        return OggOpusStream(channelCount: channels, preSkip: preSkip, packets: Array(audio), finalGranule: finalGranule)
    }

    private static func littleEndian(_ bytes: [UInt8], at offset: Int, count: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in stride(from: count - 1, through: 0, by: -1) {
            value = value << 8 | UInt64(bytes[offset + index])
        }
        return value
    }
}

/// Paquet Opus (RFC 6716, section 3.1).
enum OpusPacket {
    /// Échantillons à 48 kHz contenus dans un paquet, d'après son octet de tête (TOC) ;
    /// 0 pour un paquet vide ou invalide.
    static func sampleCount(_ packet: Data) -> Int {
        guard let toc = packet.first else { return 0 }
        let config = Int(toc >> 3)
        let frameSize: Int
        switch config {
        case 0 ..< 12:
            // SILK : 10, 20, 40 ou 60 ms.
            frameSize = [480, 960, 1920, 2880][config & 3]
        case 12 ..< 16:
            // Hybride : 10 ou 20 ms.
            frameSize = [480, 960][config & 1]
        default:
            // CELT : 2,5, 5, 10 ou 20 ms.
            frameSize = [120, 240, 480, 960][config & 3]
        }
        let frames: Int
        switch toc & 3 {
        case 0: frames = 1
        case 1, 2: frames = 2
        default:
            guard packet.count >= 2 else { return 0 }
            frames = Int(packet[packet.startIndex + 1] & 0x3F)
        }
        return frameSize * frames
    }
}
