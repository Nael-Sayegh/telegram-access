import AVFoundation
import XCTest
@testable import TelegramAccess

/// Vocal d'exemple (`Fixtures/voice-1s.ogg`) : 1 seconde de la à 440 Hz, mono, encodé par
/// ffmpeg (libopus, paquets de 20 ms) comme un vocal Telegram.
private enum VoiceFixture {
    static func url(file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        try XCTUnwrap(
            Bundle(for: BundleToken.self).url(forResource: "voice-1s", withExtension: "ogg"),
            "Vocal d'exemple absent du paquet de tests",
            file: file,
            line: line
        )
    }

    private final class BundleToken {}
}

/// Lecture du conteneur OGG et des paquets Opus.
final class OggOpusTests: XCTestCase {
    func testReadsATelegramStyleVoiceNote() throws {
        let stream = try OggOpusReader.read(Data(contentsOf: VoiceFixture.url()))
        XCTAssertEqual(stream.channelCount, 1)
        XCTAssertEqual(stream.preSkip, 312)
        XCTAssertEqual(stream.packets.count, 51)
        XCTAssertEqual(stream.finalGranule, 48_312)
        XCTAssertEqual(stream.sampleCount, 48_000, "Une seconde à 48 kHz")
        XCTAssertTrue(stream.packets.allSatisfy { OpusPacket.sampleCount($0) == 960 }, "Paquets de 20 ms")
    }

    func testRejectsWhatIsNotAnOpusVoiceNote() throws {
        XCTAssertThrowsError(try OggOpusReader.read(Data("pas un vocal".utf8))) {
            XCTAssertEqual($0 as? OggOpusError, .notOgg)
        }
        XCTAssertThrowsError(try OggOpusReader.read(Data())) {
            XCTAssertEqual($0 as? OggOpusError, .notOgg)
        }

        let data = try Data(contentsOf: VoiceFixture.url())
        XCTAssertThrowsError(try OggOpusReader.read(data.prefix(200)), "Téléchargement incomplet") {
            XCTAssertEqual($0 as? OggOpusError, .truncated)
        }

        var vorbis = data
        let head = try XCTUnwrap(vorbis.range(of: Data("OpusHead".utf8)))
        vorbis.replaceSubrange(head, with: Data("VorbHead".utf8))
        XCTAssertThrowsError(try OggOpusReader.read(vorbis)) {
            XCTAssertEqual($0 as? OggOpusError, .notOpus)
        }
    }

    /// Octet TOC (RFC 6716, 3.1) : configuration (mode et durée) et nombre de trames.
    func testPacketDurations() {
        XCTAssertEqual(OpusPacket.sampleCount(Data([0x78])), 960, "Hybride 20 ms, une trame")
        XCTAssertEqual(OpusPacket.sampleCount(Data([0x18])), 2880, "SILK 60 ms")
        XCTAssertEqual(OpusPacket.sampleCount(Data([0x79])), 1920, "Deux trames de 20 ms")
        XCTAssertEqual(OpusPacket.sampleCount(Data([0x7B, 0x03])), 2880, "Trois trames annoncées")
        XCTAssertEqual(OpusPacket.sampleCount(Data([0x80])), 120, "CELT 2,5 ms")
        XCTAssertEqual(OpusPacket.sampleCount(Data()), 0)
        XCTAssertEqual(OpusPacket.sampleCount(Data([0x7B])), 0, "Nombre de trames manquant")
    }
}

/// Décodage avec le décodeur Opus du système.
final class VoiceNoteDecoderTests: XCTestCase {
    func testDecodesTheVoiceNoteToOneSecondOfSound() throws {
        let stream = try OggOpusReader.read(Data(contentsOf: VoiceFixture.url()))
        let buffer = try VoiceNoteDecoder.decode(stream)
        XCTAssertEqual(buffer.frameLength, 48_000)
        XCTAssertEqual(buffer.format.sampleRate, 48_000)
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        var energy: Float = 0
        for index in 0 ..< Int(buffer.frameLength) {
            energy += samples[index] * samples[index]
        }
        let rms = (energy / Float(buffer.frameLength)).squareRoot()
        XCTAssertGreaterThan(rms, 0.02, "Son audible (pas du silence)")
        XCTAssertLessThan(rms, 0.5)
    }

    func testWritesAFileThatAVFoundationPlays() throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: destination) }
        let duration = try VoiceNoteDecoder.decodeFile(at: VoiceFixture.url(), to: destination)
        XCTAssertEqual(duration, 1, accuracy: 0.001)
        let file = try AVAudioFile(forReading: destination)
        XCTAssertEqual(file.length, 48_000)
        XCTAssertNoThrow(try AVAudioPlayer(contentsOf: destination))
    }
}

/// Textes du lecteur.
final class VoiceLabelsTests: XCTestCase {
    func testRates() {
        XCTAssertEqual(VoiceLabels.nextRate(after: 1), 1.5)
        XCTAssertEqual(VoiceLabels.nextRate(after: 1.5), 2)
        XCTAssertEqual(VoiceLabels.nextRate(after: 2), 1)
        XCTAssertEqual(VoiceLabels.nextRate(after: 0.75), 1, "Vitesse inconnue : retour à 1")
        XCTAssertEqual(VoiceLabels.rate(1), "Vitesse : 1 fois")
        XCTAssertEqual(VoiceLabels.rate(1.5), "Vitesse : 1,5 fois")
        XCTAssertEqual(VoiceLabels.visibleRate(2), "2×")
        XCTAssertEqual(VoiceLabels.visibleRate(1.5), "1,5×")
    }

    func testPositions() {
        XCTAssertEqual(VoiceLabels.position(12.7, of: 40), "12 secondes sur 40 secondes")
        XCTAssertEqual(VoiceLabels.position(0, of: 75), "0 seconde sur 1 minute 15 secondes")
        XCTAssertEqual(VoiceLabels.visiblePosition(12.7, of: 40), "0:12 / 0:40")
        XCTAssertEqual(VoiceLabels.visiblePosition(65, of: 600), "1:05 / 10:00")
    }

    func testTitles() {
        XCTAssertEqual(VoiceLabels.title(author: "Marie Dupont", isOutgoing: false), "Message vocal de Marie Dupont")
        XCTAssertEqual(VoiceLabels.title(author: nil, isOutgoing: true), "Votre message vocal")
        XCTAssertEqual(VoiceLabels.title(author: nil, isOutgoing: false), "Message vocal")
    }
}

/// Vocaux dans l'écran de conversation : actions, lecteur, Magic Tap, message écouté.
@MainActor
final class ConversationVoiceTests: XCTestCase {
    private typealias Fixture = ConversationTestData

    private func voiceMessage(_ id: Int64, path: String?, outgoing: Bool = false) -> ChatMessage {
        Fixture.message(
            id,
            sender: outgoing ? .user(Fixture.me) : .user(Fixture.marie),
            outgoing: outgoing,
            media: MessageMedia(
                kind: .voiceNote,
                file: FileRef(id: 77, size: 3983, localPath: path),
                isListened: false
            ),
            content: .voiceNote(duration: 1, caption: "")
        )
    }

    private func openModel(_ messages: [ChatMessage]) async -> (ConversationViewModel, FakeAuthService) {
        let service = FakeAuthService()
        await service.setHistoryPages([messages])
        let store = ChatStore(events: service.chatEvents)
        service.send(.user(id: Fixture.marie, name: UserName(firstName: "Marie", lastName: "Dupont", isDeleted: false)))
        let chat = ChatTestData.chat(Fixture.chatId, kind: .user(userId: Fixture.marie))
        service.send(.newChat(chat))
        await waitUntil { store.state.chats[chat.id] != nil && !store.state.users.isEmpty }
        let hub = MessageHub(events: service.messageEvents)
        let model = ConversationViewModel(chatId: chat.id, store: store, hub: hub, service: service)
        await model.open()
        return (model, service)
    }

    private func row(_ model: ConversationViewModel, _ id: Int64) -> MessageRowModel {
        model.items.compactMap(\.message).first { $0.id == id }!
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<300 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition non remplie à temps", file: file, line: line)
    }

    func testVoiceNoteIsPlayedThenMarkedListened() async throws {
        let path = try VoiceFixture.url().path
        let (model, service) = await openModel([voiceMessage(10, path: path)])
        XCTAssertEqual(model.actions(for: row(model, 10)).first, .listen, "Écouter en tête")

        model.toggleVoice(row(model, 10))
        XCTAssertEqual(model.voice.current?.title, "Message vocal de Marie Dupont")
        await waitUntil { model.voice.current?.isLoading == false }
        XCTAssertEqual(model.voice.current?.duration ?? 0, 1, accuracy: 0.01)
        await waitUntil { await service.messageCalls.contains("openContent 1 10") }
        let downloads = await service.messageCalls.filter { $0.hasPrefix("download") }
        XCTAssertTrue(downloads.isEmpty, "Fichier déjà téléchargé")

        // Magic Tap : lecture / pause du vocal plutôt qu'envoi.
        let wasPlaying = model.voice.current?.isPlaying ?? false
        model.magicTap()
        XCTAssertEqual(model.voice.current?.isPlaying, !wasPlaying)
        XCTAssertEqual(
            model.actions(for: row(model, 10)).first,
            wasPlaying ? .resumeListening : .pauseListening
        )

        model.close()
        XCTAssertNil(model.voice.current, "Lecteur fermé avec l'écran")
    }

    func testOwnVoiceNoteIsNotMarkedListened() async throws {
        let path = try VoiceFixture.url().path
        let (model, service) = await openModel([voiceMessage(10, path: path, outgoing: true)])
        model.toggleVoice(row(model, 10))
        XCTAssertEqual(model.voice.current?.title, "Votre message vocal")
        await waitUntil { model.voice.current?.isLoading == false }
        let calls = await service.messageCalls
        XCTAssertFalse(calls.contains { $0.hasPrefix("openContent") })
        model.voice.stop()
    }

    func testUnreadableVoiceNoteIsAnnounced() async {
        // Le faux service « télécharge » vers un chemin inexistant.
        let (model, service) = await openModel([voiceMessage(10, path: nil)])
        model.toggleVoice(row(model, 10))
        await waitUntil { model.lastAnnouncement == VoiceLabels.failure }
        XCTAssertNil(model.voice.current, "Lecteur refermé")
        let calls = await service.messageCalls
        XCTAssertTrue(calls.contains("download 77"))
    }

    func testOnlyVoiceNotesHaveTheListenAction() async {
        let (model, _) = await openModel([Fixture.message(10, text: "Texte")])
        XCTAssertNil(model.voiceAction(for: row(model, 10)))
        XCTAssertFalse(model.actions(for: row(model, 10)).contains(.listen))
    }
}
