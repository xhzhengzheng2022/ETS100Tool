import Foundation
import XCTest
@testable import ETS100Core

final class TextCleaningTests: XCTestCase {
    func testParagraphTagsBecomeSingleLineBreaks() {
        let cleaned = ETS100Text.cleanDisplay("<p>First line.</p><p>Second line.</p>")
        XCTAssertEqual(cleaned, "First line.\nSecond line.")
    }

    func testInlineTagsAreRemoved() {
        let cleaned = ETS100Text.cleanDisplay("<b>Hello</b><br/>World&nbsp;&amp;&nbsp;friends")
        XCTAssertEqual(cleaned, "Hello\nWorld & friends")
    }

    func testZeroWidthSpaceIsRemoved() {
        XCTAssertEqual(ETS100Text.cleanDisplay("ab\u{200B}c"), "abc")
    }

    func testInternalPrefixIsStrippedOnlyAtStart() {
        XCTAssertEqual(ETS100Text.cleanQuestion("ets_th1 When is the party?"), "When is the party?")
        XCTAssertEqual(ETS100Text.cleanQuestion("What about ets_th2?"), "What about ets_th2?")
    }

    func testAnswerPipesSplitIntoLines() {
        XCTAssertEqual(ETS100Text.cleanAnswer("one|two|three"), "one\ntwo\nthree")
    }

    func testContainsChinese() {
        XCTAssertTrue(ETS100Text.containsChinese("第一题"))
        XCTAssertFalse(ETS100Text.containsChinese("Question 1"))
    }
}

final class ModelsTests: XCTestCase {
    func testAccountValidityMatchesAndroidRules() {
        let valid = EcardAccount(
            key: "0",
            id: "1",
            parentID: "p",
            userAccountID: "u",
            name: "学生",
            grade: "初二",
            status: "0",
            mobileStatus: "1",
            outOfDate: "0",
            classID: "c",
            className: "一班",
            machineCodeStatus: "0"
        )
        XCTAssertTrue(valid.isValid)

        var expired = valid
        expired.outOfDate = "1"
        XCTAssertFalse(expired.isValid)

        var noClass = valid
        noClass.classID = " "
        XCTAssertFalse(noClass.isValid)
    }

    func testHomeworkSubtitleAndZipFileName() {
        let homework = HomeworkItem(
            id: "h1",
            name: "Unit 3",
            contents: [
                HomeworkContent(groupName: "听后选择", url: "https://cdn.example.com/a.zip?token=1")
            ],
            totalScore: 30,
            point: 27,
            useTime: 125
        )
        XCTAssertEqual(homework.contents.first?.zipFileName, "a.zip")
        XCTAssertTrue(homework.subtitle.contains("得分 27 / 30"))
        XCTAssertTrue(homework.subtitle.contains("用时 2 分 5 秒"))
        XCTAssertFalse(homework.needsOnlineFetch)

        let pk = HomeworkItem(id: "h2", name: "词汇 PK", contents: [], pk: 1)
        XCTAssertTrue(pk.needsOnlineFetch)
        XCTAssertTrue(pk.subtitle.contains("在线作业"))
    }

    func testQuestionShareText() {
        let question = Question(
            order: 1,
            sectionOrder: 1,
            questionText: "Where does Tony come from?",
            answers: ["B. Australia."],
            options: ["A. Canada.", "B. Australia."],
            displayOrder: 3
        )
        XCTAssertEqual(question.numberedText, "3. Where does Tony come from?")
        XCTAssertTrue(question.shareText.contains("答案："))
        XCTAssertTrue(question.shareText.contains("B. Australia."))
    }
}
