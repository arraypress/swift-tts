//
//  DramaTextTests.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  The text rules against the reference implementation's own outputs
//  (Fixtures/chunking.json, written by mlx-audio's chunking.py).
//

import Foundation
import XCTest
@testable import DramaTTS

final class DramaTextTests: XCTestCase {

    private struct Fixture: Decodable {
        let inputs: [String: String]
        let split: [String: [String]]
        let tag: [String: String]
        let reference: [String: String]
        let validate: [String: String?]
    }

    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/chunking", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testSplitMatchesReference() throws {
        let fixture = try fixture()
        for (name, input) in fixture.inputs {
            XCTAssertEqual(DramaText.split(input), fixture.split[name], name)
        }
    }

    func testSpeakerTagMatchesReference() throws {
        let fixture = try fixture()
        for (name, input) in fixture.inputs {
            XCTAssertEqual(DramaText.withSpeakerTag(input), fixture.tag[name], name)
        }
    }

    func testReferenceTranscriptMatchesReference() throws {
        let fixture = try fixture()
        for (name, expected) in fixture.reference {
            XCTAssertEqual(DramaText.referenceTranscript(fixture.inputs[name]!), expected, name)
        }
    }

    func testValidationMatchesReference() throws {
        for (input, expected) in try fixture().validate {
            XCTAssertEqual(DramaText.problem(with: input, location: "text"), expected, input.debugDescription)
        }
    }

    func testCRLFStillEndsSentences() {
        // A Swift Character holds "\r\n" as one unit; the cut must still see the "\n".
        let pieces = DramaText.cutAfter(Array("one\r\ntwo".unicodeScalars), marks: DramaText.sentenceEnds)
        XCTAssertEqual(pieces.map { DramaText.string($0) }, ["one\r\n", "two"])
    }

    func testDecimalPointIsNotASentenceEnd() {
        let pieces = DramaText.cutAfter(Array("Pi is 3.14. Done".unicodeScalars), marks: DramaText.sentenceEnds)
        XCTAssertEqual(pieces.map { DramaText.string($0) }, ["Pi is 3.14.", " Done"])
    }
}
