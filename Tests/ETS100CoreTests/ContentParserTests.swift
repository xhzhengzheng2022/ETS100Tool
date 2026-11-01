import Foundation
import XCTest
@testable import ETS100Core

final class ContentParserTests: XCTestCase {
    // MARK: - Fixtures

    private func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw ETSError.parsingFailed("缺少测试夹具 \(name).json")
        }
        return try Data(contentsOf: url)
    }

    private func parse(_ name: String, groupName: String = "") throws -> ParsedContent {
        try ContentParser.parse(data: data(name), groupName: groupName)
    }

    // MARK: - Real packages

    func testChooseSectionKeepsOptionsAnswersAndOfficialOrder() throws {
        let parsed = try parse("choose", groupName: "听后选择")
        XCTAssertEqual(parsed.structureType, StructureType.choose)
        XCTAssertEqual(parsed.section.caption, "听后选择")
        XCTAssertEqual(parsed.section.questions.count, 2)

        let first = try XCTUnwrap(parsed.section.questions.first)
        XCTAssertEqual(first.displayOrder, 1)
        XCTAssertEqual(first.correctAnswer, "B")
        XCTAssertEqual(first.options.count, 3)
        XCTAssertEqual(first.answers.first, "B. Next week.")
        XCTAssertFalse(first.questionText.contains("ets_th"))
        XCTAssertTrue(first.questionText.contains("When is David's birthday?"))
    }

    func testReadSectionUsesPassageAsOriginalContent() throws {
        let parsed = try parse("read", groupName: "短文朗读")
        XCTAssertEqual(parsed.structureType, StructureType.read)
        let question = try XCTUnwrap(parsed.section.questions.first)
        XCTAssertEqual(question.questionText, "模仿朗读原文")
        XCTAssertTrue(parsed.section.originalContent?.contains("Beijing") == true)
        XCTAssertTrue(question.answers.isEmpty)
    }

    func testPictureSectionSplitsEachVariantWithoutTags() throws {
        let parsed = try parse("picture", groupName: "信息转述")
        XCTAssertEqual(parsed.structureType, StructureType.picture)
        XCTAssertEqual(parsed.section.questions.count, 5)

        let first = try XCTUnwrap(parsed.section.questions.first)
        XCTAssertEqual(first.questionText, "A New Student, Tony（第 1 段）")
        XCTAssertTrue(first.answers.first?.hasPrefix("I've got some information") == true)
        XCTAssertFalse(first.answers.first?.contains("<") == true)

        XCTAssertEqual(parsed.section.questions.last?.questionText, "A New Student, Tony（第 5 段）")
    }

    func testRoleSectionParsesQuestionsAndAnswers() throws {
        let parsed = try parse("role", groupName: "听说问答")
        XCTAssertEqual(parsed.structureType, StructureType.role)
        XCTAssertEqual(parsed.section.questions.count, 2)

        for question in parsed.section.questions {
            XCTAssertFalse(question.questionText.contains("ets_th"))
            XCTAssertFalse(question.answers.isEmpty)
            XCTAssertNil(question.originalText)
        }
        XCTAssertEqual(parsed.section.questions[0].displayOrder, 1)
    }

    // MARK: - Synthetic packages

    func testFillSectionKeepsBlankOrder() throws {
        let json = """
        {"structure_type":"collector.fill","info":{"std":[
          {"xth":"2","value":"modern"},
          {"xth":"1","value":"history"}
        ]}}
        """
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        let parsed = try ContentParser.parse(json: object, groupName: "听后记录")
        XCTAssertEqual(parsed.section.questions.count, 2)
        XCTAssertEqual(parsed.section.questions.map(\.displayOrder), [1, 2])
        XCTAssertEqual(parsed.section.questions.map { $0.answers.first ?? "" }, ["history", "modern"])
    }

    func testDialogueSectionUsesAskAndStandardAnswers() throws {
        let json = """
        {"structure_type":"collector.dialogue","info":{"question":[
          {"xh":"1","ask":"ets_th1 What did the man suggest?","std":[{"value":"Hold a surprise party."}]},
          {"xh":"2","ask":"ets_th2 Why?","std":[{"value":"David loves basketball."}]}
        ]}}
        """
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        let parsed = try ContentParser.parse(json: object, groupName: "回答问题")
        XCTAssertEqual(parsed.section.questions.count, 2)
        XCTAssertEqual(parsed.section.questions[0].questionText, "What did the man suggest?")
        XCTAssertEqual(parsed.section.questions[0].answers, ["Hold a surprise party."])
    }

    func testStartIndexContinuesGlobalNumbering() throws {
        let parsed = try ContentParser.parse(
            data: try data("choose"),
            groupName: "听后选择",
            startIndex: 10
        )
        XCTAssertEqual(parsed.section.questions.map(\.order), [11, 12])
        XCTAssertEqual(parsed.section.questions.map(\.sectionOrder), [1, 2])
    }

    func testEmptyPackageThrowsParsingFailure() {
        let json = Data(#"{"structure_type":"collector.empty","info":{}}"#.utf8)
        XCTAssertThrowsError(try ContentParser.parse(data: json, groupName: "空包")) { error in
            guard case ETSError.parsingFailed = error else {
                return XCTFail("expected parsingFailed, got \(error)")
            }
        }
    }
}
