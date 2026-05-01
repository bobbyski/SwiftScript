import Foundation

public struct ShellScript: Sendable {
    public var path: URL
    public var lines: [String]

    public init(path: URL, lines: [String]) {
        self.path = path
        self.lines = lines
    }

    public static func load(from path: URL, shellPath: String? = nil) throws -> ShellScript {
        let contents = try String(contentsOf: path, encoding: .utf8)
        var lines = contents.components(separatedBy: .newlines)

        if let first = lines.first, first.hasPrefix("#!") {
            if let shellPath {
                let referencedShell = String(first.dropFirst(2))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard referencedShell == shellPath else {
                    throw ShellScriptError.shebangMismatch(
                        expected: shellPath,
                        actual: referencedShell
                    )
                }
            }
            lines.removeFirst()
        }

        return ShellScript(path: path, lines: lines)
    }
}

public enum ShellScriptError: Error, CustomStringConvertible {
    case shebangMismatch(expected: String, actual: String)

    public var description: String {
        switch self {
        case let .shebangMismatch(expected, actual):
            "script shebang references '\(actual)', expected '\(expected)'"
        }
    }
}
