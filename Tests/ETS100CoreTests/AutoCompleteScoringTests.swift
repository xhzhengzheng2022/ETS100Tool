import Foundation
import XCTest
@testable import ETS100Core

final class AutoCompleteScoringTests: XCTestCase {
    func testFullMarksConvertToPaperPoints() {
        XCTAssertEqual(AutoCompleteScoring.convertScore(5.0, maximum: 6.0), 6.0)
        XCTAssertEqual(AutoCompleteScoring.convertScore(5.0, maximum: 1.5), 1.5)
        XCTAssertEqual(AutoCompleteScoring.convertScore(5.0, maximum: 0.5), 0.5)
    }

    func testTargetBandRoundsUpToGraduation() {
        // 4.75 * 6 / 5 = 5.7 -> ceil(45.6) / 8 = 5.75
        XCTAssertEqual(AutoCompleteScoring.convertScore(4.75, maximum: 6.0), 5.75)
        // 0.5 of 1.5 -> 0.15 -> 0.25
        XCTAssertEqual(AutoCompleteScoring.convertScore(0.5, maximum: 1.5), 0.25)
    }

    func testConvertScoreNeverExceedsMaximum() {
        XCTAssertEqual(AutoCompleteScoring.convertScore(7.0, maximum: 2.0), 2.0)
    }

    func testRoundPointsUsesTwoDecimals() {
        XCTAssertEqual(AutoCompleteScoring.roundPoints(0.625), 0.63)
        XCTAssertEqual(AutoCompleteScoring.roundPoints(5.7049), 5.7)
        XCTAssertEqual(AutoCompleteScoring.formatted(5.7), "5.70")
    }

    func testScoreDetailContainsExpectedKeys() throws {
        let json = AutoCompleteScoring.scoreDetail(
            profile: ScoreProfile.target(ratio: 1.0),
            category: "collector.read",
            choose: "B"
        )
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["total_score"] as? String, "5.00")
        XCTAssertEqual(object["fluency_score"] as? String, "4.95")
        XCTAssertEqual(object["accuracy_score"] as? String, "4.95")
        XCTAssertEqual(object["integrity_score"] as? String, "4.95")
        XCTAssertEqual(object["standard_score"] as? String, "4.90")
        XCTAssertEqual(object["category"] as? String, "collector.read")
        XCTAssertEqual(object["rate_scale"] as? Int, 1)
        XCTAssertEqual(object["choose"] as? String, "B")
        XCTAssertNil(object["choose_id"])
    }

    func testScoreXMLHasExpectedShape() {
        let xml = AutoCompleteScoring.scoreXML(
            text: "I like apples. They are sweet!",
            profile: .target(ratio: 1.0),
            category: "collector.read",
            seed: 7
        )
        XCTAssertTrue(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"utf-8\"?>"))
        XCTAssertTrue(xml.contains("<read_chapter>"))
        XCTAssertTrue(xml.contains("<rec_paper"))
        XCTAssertTrue(xml.contains("is_rejected=\"false\""))
        XCTAssertTrue(xml.contains("<sentence content=\"I like apples\""))
        XCTAssertTrue(xml.contains("content=\"apples\""))
        XCTAssertTrue(xml.contains("<syll"))
        XCTAssertTrue(xml.hasSuffix("</rec_paper></read_chapter></xml_result>"))
    }

    func testScoreXMLIsDeterministicForSeed() {
        let first = AutoCompleteScoring.scoreXML(
            text: "Hello world",
            profile: .target(ratio: 1.0),
            category: "read_sentence",
            seed: 42
        )
        let second = AutoCompleteScoring.scoreXML(
            text: "Hello world",
            profile: .target(ratio: 1.0),
            category: "read_sentence",
            seed: 42
        )
        XCTAssertEqual(first, second)
    }

    func testScoreXMLEscapesAttributes() {
        let xml = AutoCompleteScoring.scoreXML(
            text: "A & B < C \"quote\"",
            profile: .target(ratio: 1.0),
            seed: 1
        )
        XCTAssertTrue(xml.contains("&amp;"))
        XCTAssertTrue(xml.contains("&lt;"))
        XCTAssertTrue(xml.contains("&quot;"))
    }

    func testPhonemesSplitsDigraphs() {
        XCTAssertEqual(AutoCompleteScoring.phonemes("think"), ["θ", "i", "n", "k"])
        XCTAssertEqual(AutoCompleteScoring.phonemes("school"), ["s", "tʃ", "uː", "l"])
        XCTAssertEqual(AutoCompleteScoring.phonemes("123"), ["*"])
    }

    func testOfficialUnits() {
        XCTAssertEqual(AutoCompleteScoring.toRealScore(1.5), "15000")
        XCTAssertEqual(AutoCompleteScoring.toRealScore(0.0), "0")
        XCTAssertEqual(AutoCompleteScoring.toScoreRate(1.5, total: 6.0), "250000")
        XCTAssertEqual(AutoCompleteScoring.toScoreRate(6.0, total: 6.0), "1000000")
        XCTAssertEqual(AutoCompleteScoring.toScoreRate(0.0, total: 6.0), "0")
    }

    func testDetailKeyMatchesOfficialFormat() {
        XCTAssertEqual(
            AutoCompleteScoring.buildDetailKey(
                resourceID: "58",
                setID: "711012",
                combination: "2",
                entityID: "772040"
            ),
            "58:711012:2:772040"
        )
    }

    func testContentTypeClassification() {
        XCTAssertEqual(AutoCompleteScoring.contentType(questionType: "collector.read", typeName: "朗读"), "phonics")
        XCTAssertEqual(AutoCompleteScoring.contentType(questionType: "collector.choose", typeName: "听选信息"), "read_and_write_on")
    }

    func testJSONObjectBridgesSwiftValues() throws {
        let object = JSONObject(anyValues: [
            "homework_id": 123,
            "graduation": 0.125,
            "auto_submit": 1,
            "batch": [["entity_id": "772040", "order": 0]],
        ])
        let data = Data(JSONValue.object(object).compactJSON.utf8)
        let dictionary = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(dictionary["homework_id"] as? Int, 123)
        XCTAssertEqual(dictionary["graduation"] as? Double, 0.125)
        XCTAssertEqual(dictionary["auto_submit"] as? Int, 1)
        let batch = try XCTUnwrap(dictionary["batch"] as? [[String: Any]])
        XCTAssertEqual(batch.first?["entity_id"] as? String, "772040")
        XCTAssertEqual(batch.first?["order"] as? Int, 0)
    }

    func testOptionsClampTargetRatio() {
        XCTAssertEqual(AutoCompleteOptions(targetRatio: 0).targetRatio, 0.05)
        XCTAssertEqual(AutoCompleteOptions(targetRatio: 2).targetRatio, 1.0)
        XCTAssertEqual(AutoCompleteOptions(targetRatio: 0.9).targetRatio, 0.9)
    }
}
