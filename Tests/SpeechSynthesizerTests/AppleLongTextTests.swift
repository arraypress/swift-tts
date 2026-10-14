//
//  AppleLongTextTests.swift
//  SpeechSynthesizerTests
//
//  Created by David Sherlock on 2026.
//
//  The Apple engine once returned only the first stretch of a paragraph:
//  `write(_:toBufferCallback:)` hands back an empty buffer at the end of
//  every stretch it synthesises, and the engine took the first one for the
//  end. A 144-word paragraph came back as 12 seconds instead of 40. These
//  render a long paragraph live and hold it against `say`, which speaks the
//  same text with the same voice through the same system synthesiser.
//

import AVFoundation
import Foundation
import XCTest
@testable import SpeechSynthesizer

final class AppleLongTextTests: XCTestCase {

    /// 144 words, nine sentences, commas and an apostrophe.
    static let paragraph = """
        The lighthouse stood at the end of a long stone pier, and every evening the keeper climbed its spiral \
        stairs to light the lamp. He had done this for thirty years, through storms that shook the glass and \
        calm nights when the sea lay flat as a mirror. The ships that passed never knew his name, but they \
        trusted the light. One winter the supply boat failed to arrive, and he rationed his oil carefully, \
        burning the lamp only in the darkest hours. When the boat finally came, the captain asked how he had \
        managed. The keeper smiled and said that a small light, kept steady, is worth more than a bright one \
        that goes out. The captain wrote those words in his log, and years later his daughter read them aloud \
        at the keeper's funeral, while the lamp still turned above the water.
        """

    func testLongParagraph_isAsLongAsSaySpeaksIt() async throws {
        guard let voice = AVSpeechSynthesisVoice(language: "en-US") else { throw XCTSkip("no en-US system voice") }
        var options = SynthesisOptions()
        options.voice = TTSVoice(id: voice.identifier, name: voice.name, language: voice.language, model: .apple)

        let audio = try await AppleEngine().synthesize(Self.paragraph, options: options)
        let reference = try Self.sayDuration(Self.paragraph, voice: voice.name)

        // Measured: 40.1 s, and say 40.1 s in the same voice. The bug gave 12.4 s.
        XCTAssertGreaterThan(audio.duration, reference * 0.85,
                             "\(audio.duration) s of audio; say speaks it in \(reference) s")
        XCTAssertLessThan(audio.duration, reference * 1.15,
                          "\(audio.duration) s of audio; say speaks it in \(reference) s")
    }

    /// Every word is there: the audio, transcribed back, matches the text.
    /// Needs the fleet's `transcribe`; skipped where it is not installed.
    func testLongParagraph_transcribesBackWithLowWordError() async throws {
        guard let transcribe = Self.executable("transcribe") else { throw XCTSkip("transcribe is not installed") }
        let audio = try await AppleEngine().synthesize(Self.paragraph, options: SynthesisOptions())
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent("apple-long-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        try audio.write(toWAV: wav)

        let heard = try Self.run(transcribe, [wav.path, "--text"])
        let error = WordError.rate(reference: Self.paragraph, hypothesis: heard)
        // Measured 0.7 %: one word, "thirty" heard as "30". The bug gave 67 %.
        XCTAssertLessThan(error, 0.10, "word error \(error): \(heard)")
    }

    func testWordError_countsSubstitutionsInsertionsAndDeletions() {
        XCTAssertEqual(WordError.rate(reference: "a b c d", hypothesis: "a b c d"), 0)
        XCTAssertEqual(WordError.rate(reference: "a b c d", hypothesis: "A, b. C d!"), 0)
        XCTAssertEqual(WordError.rate(reference: "a b c d", hypothesis: "a x c d"), 0.25)
        XCTAssertEqual(WordError.rate(reference: "a b c d", hypothesis: "a b"), 0.5)
        XCTAssertEqual(WordError.rate(reference: "a b", hypothesis: "a b c d"), 1)
    }

    // MARK: - Helpers

    /// How long `say` takes to speak `text` in `voice`, from the file it writes.
    static func sayDuration(_ text: String, voice: String) throws -> Double {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("say-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("text.txt")
        let output = folder.appendingPathComponent("say.aiff")
        try text.write(to: input, atomically: true, encoding: .utf8)
        _ = try run("/usr/bin/say", ["-v", voice, "-f", input.path, "-o", output.path])
        let file = try AVAudioFile(forReading: output)
        return Double(file.length) / file.fileFormat.sampleRate
    }

    static func executable(_ name: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let folders = path.split(separator: ":").map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin"]
        return folders.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs a tool and returns its standard output, read to the end before waiting.
    static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw TTSError.synthesisFailed("\(tool) exited \(process.terminationStatus)")
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Word error rate: edits to turn the reference's words into the
/// hypothesis's, over the reference's word count. Case and punctuation are
/// ignored.
enum WordError {

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
    }

    static func rate(reference: String, hypothesis: String) -> Double {
        let expected = words(reference)
        let heard = words(hypothesis)
        guard !expected.isEmpty else { return heard.isEmpty ? 0 : 1 }
        var previous = Array(0...heard.count)
        for (row, word) in expected.enumerated() {
            var current = [row + 1] + Array(repeating: 0, count: heard.count)
            for column in 1...max(1, heard.count) where column <= heard.count {
                let substitution = previous[column - 1] + (word == heard[column - 1] ? 0 : 1)
                current[column] = min(substitution, previous[column] + 1, current[column - 1] + 1)
            }
            previous = current
        }
        return Double(previous[heard.count]) / Double(expected.count)
    }
}
