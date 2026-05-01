import Foundation

public struct ShellCommand: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]

    public init(executable: String, arguments: [String] = []) {
        self.executable = executable
        self.arguments = arguments
    }
}

public enum CommandParser {
    public static func parse(_ line: String) throws -> ShellCommand? {
        let tokens = try tokenize(line)
        guard let executable = tokens.first else {
            return nil
        }

        return ShellCommand(
            executable: executable,
            arguments: Array(tokens.dropFirst())
        )
    }

    public static func tokenize(_ line: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false

        for character in line {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }

            if character == "\\" {
                escaping = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            current.append(character)
        }

        if escaping {
            current.append("\\")
        }

        if quote != nil {
            throw CommandParserError.unterminatedQuote
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}

public enum CommandParserError: Error, CustomStringConvertible {
    case unterminatedQuote

    public var description: String {
        switch self {
        case .unterminatedQuote:
            "unterminated quote"
        }
    }
}
