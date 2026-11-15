import AVFoundation

enum VoiceNoteDecoderError: Error, Equatable {
    /// Décodeur Opus du système indisponible.
    case decoderUnavailable
    case invalidPacket
    case decodingFailed
}

/// Décodage d'un vocal Telegram (OGG Opus) en PCM, avec le décodeur Opus d'AudioToolbox :
/// aucune dépendance externe. Appelé hors du fil principal.
enum VoiceNoteDecoder {
    /// PCM flottant à 48 kHz, pré-saut retiré et fin coupée à la position de fin du fichier.
    static func decode(_ stream: OggOpusStream) throws -> AVAudioPCMBuffer {
        let channels = AVAudioChannelCount(stream.channelCount)
        let sampleRate = Double(OggOpusStream.sampleRate)
        let framesPerPacket = OpusPacket.sampleCount(stream.packets[0])
        guard framesPerPacket > 0 else { throw VoiceNoteDecoderError.invalidPacket }
        var description = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatOpus,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: UInt32(framesPerPacket),
            mBytesPerFrame: 0,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 0,
            mReserved: 0
        )
        guard let inputFormat = AVAudioFormat(streamDescription: &description),
              let outputFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: sampleRate,
                  channels: channels,
                  interleaved: false
              ),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw VoiceNoteDecoderError.decoderUnavailable
        }

        let total = stream.packets.reduce(0) { $0 + OpusPacket.sampleCount($1) }
        guard let decoded = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(total + framesPerPacket)
        ) else { throw VoiceNoteDecoderError.decodingFailed }

        let feeder = PacketFeeder(packets: stream.packets, format: inputFormat)
        let chunkCapacity = AVAudioFrameCount(framesPerPacket * 50)
        var finished = false
        while !finished {
            guard let chunk = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: chunkCapacity) else {
                throw VoiceNoteDecoderError.decodingFailed
            }
            var conversionError: NSError?
            let status = converter.convert(to: chunk, error: &conversionError) { _, inputStatus in
                feeder.next(inputStatus)
            }
            switch status {
            case .error:
                throw conversionError ?? VoiceNoteDecoderError.decodingFailed
            case .endOfStream, .inputRanDry:
                finished = true
            case .haveData:
                break
            @unknown default:
                finished = true
            }
            append(chunk, to: decoded)
            if chunk.frameLength == 0, status == .haveData {
                // Garde-fou : un décodeur qui ne produit plus rien ne doit pas bloquer.
                finished = true
            }
        }

        // Retire l'amorçage du décodeur, puis coupe à la fin réelle.
        let available = Int(decoded.frameLength)
        let start = min(stream.preSkip, available)
        let length = min(stream.sampleCount ?? (available - start), available - start)
        guard length > 0,
              let trimmed = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(length)),
              let source = decoded.floatChannelData,
              let target = trimmed.floatChannelData else {
            throw VoiceNoteDecoderError.decodingFailed
        }
        for channel in 0 ..< Int(channels) {
            target[channel].update(from: source[channel] + start, count: length)
        }
        trimmed.frameLength = AVAudioFrameCount(length)
        return trimmed
    }

    /// Décode le fichier OGG `source` et l'écrit en PCM 16 bits dans `destination` (CAF, lu
    /// par `AVAudioPlayer`). Renvoie la durée en secondes.
    static func decodeFile(at source: URL, to destination: URL) throws -> TimeInterval {
        let stream = try OggOpusReader.read(Data(contentsOf: source))
        let buffer = try decode(stream)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: buffer.format.sampleRate,
            AVNumberOfChannelsKey: buffer.format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(
            forWriting: destination,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
        return Double(buffer.frameLength) / buffer.format.sampleRate
    }

    private static func append(_ chunk: AVAudioPCMBuffer, to buffer: AVAudioPCMBuffer) {
        let count = min(Int(chunk.frameLength), Int(buffer.frameCapacity - buffer.frameLength))
        guard count > 0, let source = chunk.floatChannelData, let target = buffer.floatChannelData else { return }
        let offset = Int(buffer.frameLength)
        for channel in 0 ..< Int(buffer.format.channelCount) {
            (target[channel] + offset).update(from: source[channel], count: count)
        }
        buffer.frameLength += AVAudioFrameCount(count)
    }
}

/// Fournit les paquets Opus un par un au convertisseur.
private final class PacketFeeder {
    private let packets: [Data]
    private let format: AVAudioFormat
    private let maximumSize: Int
    private var index = 0

    init(packets: [Data], format: AVAudioFormat) {
        self.packets = packets
        self.format = format
        self.maximumSize = packets.map(\.count).max() ?? 0
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard index < packets.count else {
            status.pointee = .endOfStream
            return nil
        }
        let packet = packets[index]
        index += 1
        let buffer = AVAudioCompressedBuffer(format: format, packetCapacity: 1, maximumPacketSize: maximumSize)
        packet.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                buffer.data.copyMemory(from: base, byteCount: packet.count)
            }
        }
        buffer.packetDescriptions?.pointee = AudioStreamPacketDescription(
            mStartOffset: 0,
            mVariableFramesInPacket: 0,
            mDataByteSize: UInt32(packet.count)
        )
        buffer.packetCount = 1
        buffer.byteLength = UInt32(packet.count)
        status.pointee = .haveData
        return buffer
    }
}
