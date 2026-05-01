import Testing
@testable import SwiftScript

@Test func parsesSimpleCommand() throws {
    let parsed = try CommandParser.parse("echo hello world")
    let command = try #require(parsed)

    #expect(command.executable == "echo")
    #expect(command.arguments == ["hello", "world"])
}

@Test func parsesQuotedArguments() throws {
    let parsed = try CommandParser.parse("echo \"hello world\" 'again'")
    let command = try #require(parsed)

    #expect(command.executable == "echo")
    #expect(command.arguments == ["hello world", "again"])
}

@Test func rejectsUnterminatedQuote() {
    #expect(throws: CommandParserError.unterminatedQuote) {
        try CommandParser.tokenize("echo \"unfinished")
    }
}
