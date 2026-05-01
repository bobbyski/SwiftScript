import Foundation

public protocol ScriptInput: Sendable {
    func readLine(prompt: String?) async throws -> String?
}

public protocol ScriptOutput: Sendable {
    func write(_ text: String) async throws
    func flush() async throws
}

public protocol ScriptConsole: Sendable {
    var stdin: any ScriptInput { get }
    var stdout: any ScriptOutput { get }
    var stderr: any ScriptOutput { get }
}

public struct StandardInput: ScriptInput {
    public init() {}

    public func readLine(prompt: String?) async throws -> String? {
        if let prompt {
            print(prompt, terminator: "")
            fflush(stdout)
        }

        return Swift.readLine()
    }
}

public struct FileHandleOutput: ScriptOutput {
    private let handle: FileHandle

    public init(_ handle: FileHandle) {
        self.handle = handle
    }

    public func write(_ text: String) async throws {
        guard let data = text.data(using: .utf8) else {
            throw ConsoleError.encodingFailed
        }

        try handle.write(contentsOf: data)
    }

    public func flush() async throws {
        try handle.synchronize()
    }
}

public struct TerminalConsole: ScriptConsole {
    public let stdin: any ScriptInput
    public let stdout: any ScriptOutput
    public let stderr: any ScriptOutput

    public init() {
        self.stdin = StandardInput()
        self.stdout = FileHandleOutput(.standardOutput)
        self.stderr = FileHandleOutput(.standardError)
    }
}

public enum ConsoleError: Error {
    case encodingFailed
}
