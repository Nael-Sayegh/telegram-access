import XCTest
@testable import TelegramAccess

final class MessageLabelsTests: XCTestCase {
    func testTextIsReadAsIs() {
        XCTAssertEqual(MessageLabels.content(.text("On se voit demain ?")), "On se voit demain ?")
    }

    func testMediaWithDurationAndCaption() {
        XCTAssertEqual(MessageLabels.content(.voiceNote(duration: 12, caption: "")), "Message vocal, 12 secondes")
        XCTAssertEqual(MessageLabels.content(.video(duration: 80, caption: "")), "Vidéo, 1 minute 20 secondes")
        XCTAssertEqual(MessageLabels.content(.videoNote(duration: 1)), "Message vidéo, 1 seconde")
        XCTAssertEqual(MessageLabels.content(.photo(caption: " Vacances ")), "Photo : Vacances")
        XCTAssertEqual(MessageLabels.content(.photo(caption: "")), "Photo")
    }

    func testAudioAndDocument() {
        XCTAssertEqual(
            MessageLabels.content(.audio(title: "Clair de lune", performer: "Debussy", duration: 300, caption: "")),
            "Audio, Debussy, Clair de lune, 5 minutes"
        )
        XCTAssertEqual(MessageLabels.content(.audio(title: "", performer: "", duration: 30, caption: "")), "Audio, 30 secondes")
        XCTAssertEqual(
            MessageLabels.content(.document(fileName: "rapport.pdf", size: 2_516_582, caption: "")),
            "Fichier, rapport.pdf, 2,4 Mo"
        )
        XCTAssertEqual(MessageLabels.content(.document(fileName: "", size: 0, caption: "")), "Fichier")
    }

    func testOtherContents() {
        XCTAssertEqual(MessageLabels.content(.sticker(emoji: "😀")), "Autocollant 😀")
        XCTAssertEqual(MessageLabels.content(.contact(firstName: "Paul", lastName: "Martin")), "Contact : Paul Martin")
        XCTAssertEqual(MessageLabels.content(.poll(question: "Quelle date ?")), "Sondage : Quelle date ?")
        XCTAssertEqual(MessageLabels.content(.titleChanged("Famille")), "Nom changé en « Famille »")
        XCTAssertEqual(MessageLabels.content(.unsupported), "Message non pris en charge")
    }

    func testCalls() {
        XCTAssertEqual(MessageLabels.content(.call(isVideo: true, duration: 0, outcome: .missed)), "Appel vidéo manqué")
        XCTAssertEqual(MessageLabels.content(.call(isVideo: false, duration: 0, outcome: .declined)), "Appel refusé")
        XCTAssertEqual(MessageLabels.content(.call(isVideo: false, duration: 125, outcome: .ended)), "Appel, 2 minutes 5 secondes")
    }

    func testFileSizes() {
        XCTAssertEqual(MessageLabels.fileSize(1), "1 octet")
        XCTAssertEqual(MessageLabels.fileSize(512), "512 octets")
        XCTAssertEqual(MessageLabels.fileSize(350 * 1024), "350 Ko")
        XCTAssertEqual(MessageLabels.fileSize(2 * 1024 * 1024), "2 Mo")
        XCTAssertEqual(MessageLabels.fileSize(12 * 1024 * 1024), "12 Mo")
        XCTAssertEqual(MessageLabels.fileSize(1_181_116_006), "1,1 Go")
    }
}
