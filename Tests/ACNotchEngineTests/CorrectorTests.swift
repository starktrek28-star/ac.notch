import ACNotchEngine
import Foundation
import XCTest

final class CorrectorTests: XCTestCase {
    static let model: LanguageModel = {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try! LanguageModel(directory: root.appendingPathComponent("Resources/Language"))
    }()

    func testKeyboardDistance() {
        XCTAssertLessThan(KeyboardDistance.between("hwllo", "hello"), KeyboardDistance.between("hwllo", "hollo"))
        // A swap and a dropped double letter are cheap slips; a random wrong letter isn't.
        XCTAssertLessThan(KeyboardDistance.between("teh", "the"), KeyboardDistance.between("tqe", "the"))
        XCTAssertLessThan(KeyboardDistance.between("helo", "hello"), KeyboardDistance.between("hemlo", "hello"))
    }

    func testCommonTypos() {
        let c = Corrector(model: Self.model)
        XCTAssertEqual(c.correction(for: "teh", previous: "of"), "the")
        XCTAssertEqual(c.correction(for: "recieve"), "receive")
        XCTAssertEqual(c.correction(for: "dont"), "don't")
        XCTAssertEqual(c.correction(for: "Teh"), "The")
        XCTAssertEqual(c.correction(for: "i"), "I")
    }

    func testLeavesRealWordsAlone() {
        let c = Corrector(model: Self.model)
        for word in ["the", "Tom", "form", "NASA", "cafe", "their"] {
            XCTAssertNil(c.correction(for: word, previous: "<s>"), word)
        }
    }
}
