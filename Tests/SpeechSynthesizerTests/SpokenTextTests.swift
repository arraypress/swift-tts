//
//  SpokenTextTests.swift
//  SpeechSynthesizerTests
//
//  Created by David Sherlock on 2026.
//
//  A voice bake-off heard Kokoro say "x" for nearly every digit: 1 of 11
//  number items right in "On 3 Oct 2026 Dr. Smith paid $1,250.50 at
//  9:45 pm…". These pin the words every engine is now given instead.
//

import Testing
@testable import SpeechSynthesizer

private func spoken(_ text: String, _ language: String = "en-US") -> String {
    SpokenText.normalize(text, language: language)
}

// MARK: - The bake-off sentence

@Test func theBakeOffNumbersSentenceIsAllWords() {
    let text = "On 3 Oct 2026 Dr. Smith paid $1,250.50 at 9:45 pm. The invoice, no. 4471, was 15% higher than "
        + "the 2025 estimate, and the NHS refund of £82.99 arrives by Mon., 12 Jan."
    let result = spoken(text)
    #expect(result == "On the third of October twenty twenty-six Doctor Smith paid one thousand two hundred fifty "
        + "dollars and fifty cents at nine forty-five p.m. The invoice, number four thousand four hundred "
        + "seventy-one, was fifteen percent higher than the twenty twenty-five estimate, and the NHS refund of "
        + "eighty-two pounds and ninety-nine pence arrives by Monday, the twelfth of January.")
    #expect(!result.contains { $0.isNumber })
}

@Test func plainProseIsUntouched() {
    let text = "The lighthouse stood at the edge of the island. \"Are you sure?\" asked Maya.\nShe laughed."
    #expect(spoken(text) == text)
}

// MARK: - Number words

@Test(arguments: [
    (0, "zero"), (7, "seven"), (13, "thirteen"), (20, "twenty"), (21, "twenty-one"), (99, "ninety-nine"),
    (100, "one hundred"), (101, "one hundred one"), (1_000, "one thousand"), (1_250, "one thousand two hundred fifty"),
    (1_000_000, "one million"), (2_500_000_000, "two billion five hundred million"), (-4, "minus four"),
])
func cardinals(_ number: Int, _ words: String) {
    #expect(NumberWords.cardinal(number) == words)
}

@Test(arguments: [
    (1, "first"), (2, "second"), (3, "third"), (5, "fifth"), (8, "eighth"), (9, "ninth"), (12, "twelfth"),
    (20, "twentieth"), (21, "twenty-first"), (40, "fortieth"), (100, "one hundredth"), (103, "one hundred third"),
])
func ordinals(_ number: Int, _ words: String) {
    #expect(NumberWords.ordinal(number) == words)
}

@Test(arguments: [
    (2026, "twenty twenty-six"), (1905, "nineteen oh five"), (1900, "nineteen hundred"), (2000, "two thousand"),
    (2005, "two thousand five"), (2010, "twenty ten"), (1066, "ten sixty-six"), (1999, "nineteen ninety-nine"),
])
func years(_ number: Int, _ words: String) {
    #expect(NumberWords.year(number) == words)
}

@Test func decimalsAndDigits() {
    #expect(NumberWords.decimal("3.14") == "three point one four")
    #expect(NumberWords.decimal("0.5") == "zero point five")
    #expect(NumberWords.decimal(".5") == "point five")
    #expect(NumberWords.decimal("1,250.5") == "one thousand two hundred fifty point five")
    #expect(NumberWords.digits("0447") == "zero four four seven")
}

@Test func numberWordsAreRecognised() {
    #expect(NumberWords.isNumberWord("twenty-five"))
    #expect(NumberWords.isNumberWord("hundred"))
    #expect(NumberWords.isNumberWord("twelfth"))
    #expect(!NumberWords.isNumberWord("estimate"))
    #expect(!NumberWords.isNumberWord(""))
}

// MARK: - Rules

@Test(arguments: [
    ("$1,250.50", "one thousand two hundred fifty dollars and fifty cents"),
    ("$1", "one dollar"), ("$0.50", "fifty cents"), ("$20.00", "twenty dollars"), ("$3.5", "three dollars and fifty cents"),
    ("£82.99", "eighty-two pounds and ninety-nine pence"), ("£1.01", "one pound and one penny"),
    ("€3.50", "three euros and fifty cents"), ("¥500", "five hundred yen"), ("₹100", "one hundred rupees"),
    ("$2.5bn", "two point five billion dollars"), ("$5m", "five million dollars"),
    ("$3 billion", "three billion dollars"), ("A$40", "forty Australian dollars"),
    ("100 USD", "one hundred dollars"), ("EUR 50", "fifty euros"), ("50p", "fifty pence"), ("99¢", "ninety-nine cents"),
    ("-$5", "minus five dollars"), ("$0.125", "zero point one two five dollars"),
])
func money(_ text: String, _ words: String) {
    #expect(spoken(text) == words)
}

@Test(arguments: [
    ("15%", "fifteen percent"), ("2.5 %", "two point five percent"), ("-3%", "minus three percent"),
    ("10–15%", "ten to fifteen percent"),
])
func percentages(_ text: String, _ words: String) {
    #expect(spoken(text) == words)
}

@Test(arguments: [
    ("9:45 pm", "nine forty-five p.m."), ("9:05 AM", "nine oh five a.m."), ("12:00 p.m.", "twelve p.m."),
    ("9pm", "nine p.m."), ("7 a.m.", "seven a.m."), ("9.45 pm", "nine forty-five p.m."),
    ("21:30", "twenty-one thirty"), ("14:00", "fourteen hundred"), ("9:00", "nine o'clock"),
    ("9:45:30", "nine forty-five and thirty seconds"),
])
func times(_ text: String, _ words: String) {
    #expect(spoken(text) == words)
}

@Test func aTimeAtTheEndOfASentenceKeepsItsFullStop() {
    #expect(spoken("Meet at 9:45 pm. Bring tea.") == "Meet at nine forty-five p.m. Bring tea.")
}

@Test(arguments: [
    ("3 Oct 2026", "the third of October twenty twenty-six"), ("the 3rd of October", "the third of October"),
    ("Oct 3, 2026", "October third, twenty twenty-six"), ("October 3rd", "October third"),
    ("Oct. 15", "October fifteenth"), ("October 2026", "October twenty twenty-six"),
    ("2026-10-03", "October third, twenty twenty-six"), ("12 Jan.", "the twelfth of January."),
])
func dates(_ text: String, _ words: String) {
    #expect(spoken(text) == words)
}

@Test func slashDatesFollowTheLanguage() {
    #expect(spoken("3/10/2026") == "March tenth, twenty twenty-six")
    #expect(spoken("3/10/2026", "en-GB") == "the third of October, twenty twenty-six")
    // A day over twelve settles it either way.
    #expect(spoken("25/12/2025") == "the twenty-fifth of December, twenty twenty-five")
    #expect(spoken("12/25/25", "en-GB") == "December twenty-fifth, twenty twenty-five")
}

@Test func weekdays() {
    #expect(spoken("by Mon., 12 Jan.") == "by Monday, the twelfth of January.")
    #expect(spoken("Sat 14 Mar") == "Saturday the fourteenth of March")
    #expect(spoken("Open Tue.") == "Open Tuesday.")
    // Not an abbreviation without its full stop or a date after it.
    #expect(spoken("the Sun was out") == "the Sun was out")
}

@Test(arguments: [
    ("1990–1995", "nineteen ninety to nineteen ninety-five"), ("pages 5-7", "pages five to seven"),
    ("$10–$20", "ten dollars to twenty dollars"), ("9:00-17:00", "nine o'clock to seventeen hundred"),
    ("2025-26", "twenty twenty-five to twenty-six"),
])
func ranges(_ text: String, _ words: String) {
    #expect(spoken(text) == words)
}

@Test func aSpacedMinusIsNotARange() {
    #expect(spoken("5 - 3") == "five - three")
}

@Test(arguments: [
    ("5 km", "five kilometers"), ("1 km", "one kilometer"), ("1.5 m", "one point five meters"),
    ("10kg", "ten kilograms"), ("20°C", "twenty degrees Celsius"), ("3.5GB", "three point five gigabytes"),
    ("60 mph", "sixty miles per hour"), ("5 min", "five minutes"), ("2x", "two times"), ("90°", "ninety degrees"),
])
func units(_ text: String, _ words: String) {
    #expect(spoken(text) == words)
}

@Test(arguments: [
    ("+44 20 7946 0958", "plus four four, two zero, seven nine four six, zero nine five eight"),
    ("(555) 123-4567", "five five five, one two three, four five six seven"),
    ("555-123-4567", "five five five, one two three, four five six seven"),
    ("07700 900123", "zero seven seven zero zero, nine zero zero one two three"),
    ("020 7946 0958", "zero two zero, seven nine four six, zero nine five eight"),
])
func phoneNumbers(_ text: String, _ words: String) {
    #expect(spoken(text) == words)
}

@Test(arguments: [
    ("Dr. Smith", "Doctor Smith"), ("Mr Jones", "Mister Jones"), ("Mrs. Patel", "Missus Patel"),
    ("St. Paul's", "Saint Paul's"), ("12 Baker St.", "twelve Baker Street."), ("Elm Dr. is closed", "Elm Drive is closed"),
    ("Prof. Lee", "Professor Lee"), ("no. 5", "number five"), ("#3", "number three"), ("fig. 2", "figure two"),
    ("pp. 10-12", "pages ten to twelve"), ("apples, pears, etc.", "apples, pears, et cetera."),
    ("e.g. this", "for example this"), ("i.e. that", "that is that"), ("Acme Inc. Today", "Acme Incorporated. Today"),
    ("cats vs. dogs", "cats versus dogs"), ("salt & pepper", "salt and pepper"),
])
func abbreviations(_ text: String, _ words: String) {
    #expect(spoken(text) == words)
}

@Test func aTitleIsOnlyATitleBeforeAName() {
    // "No." is a word on its own; "Dr" without a name is not expanded.
    #expect(spoken("No. I said no.") == "No. I said no.")
    #expect(spoken("Gen Z") == "Gen Z")
}

@Test(arguments: [
    ("21st", "twenty-first"), ("2nd", "second"), ("103rd", "one hundred third"), ("1990s", "nineteen nineties"),
    ("the '80s", "the eighties"), ("1/2", "one half"), ("3/4", "three quarters"), ("2/3", "two thirds"),
    ("24/7", "twenty-four seven"), ("0.5", "zero point five"), ("-4", "minus four"), ("1,000,000", "one million"),
    ("007", "zero zero seven"), ("in 1066", "in ten sixty-six"), ("number 1984", "number one thousand nine hundred eighty-four"),
    ("4471", "four thousand four hundred seventy-one"), ("MP3", "MP three"), ("3D", "three D"),
    ("COVID-19", "COVID-nineteen"), ("version 2.0.1", "version two point zero point one"),
])
func numbers(_ text: String, _ words: String) {
    #expect(spoken(text) == words)
}

@Test func nothingNumericSurvives() {
    let text = "Call 0800 123 4567 on 3/10/2026 at 9am; it's 25% off $49.99, 3 for £10, 2.5kg, room 101, v1.2.3."
    let result = spoken(text)
    #expect(!result.contains { $0.isNumber }, "\(result)")
}

@Test func lineBreaksAreKept() {
    #expect(spoken("Chapter 1\n\nIt was 1984.") == "Chapter one\n\nIt was nineteen eighty-four.")
}
