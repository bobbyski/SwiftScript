import Foundation

public actor MemoryInput: ScriptInput {
    private var lines: [String]

    public init(lines: [String]) {
        self.lines = lines
    }

    public func readLine(prompt: String?) async throws -> String? {
        guard !lines.isEmpty else {
            return nil
        }

        return lines.removeFirst()
    }
}

public actor MemoryOutput: ScriptOutput {
    private var buffer = ""

    public init() {}

    public func write(_ text: String) async throws {
        buffer += text
    }

    public func flush() async throws {}

    public func contents() -> String {
        buffer
    }
}

public struct MemoryConsole: ScriptConsole {
    public let stdin: any ScriptInput
    public let stdout: any ScriptOutput
    public let stderr: any ScriptOutput

    public let input: MemoryInput
    public let output: MemoryOutput
    public let errorOutput: MemoryOutput

    public init(lines: [String]) {
        let input = MemoryInput(lines: lines)
        let output = MemoryOutput()
        let errorOutput = MemoryOutput()

        self.input = input
        self.output = output
        self.errorOutput = errorOutput
        self.stdin = input
        self.stdout = output
        self.stderr = errorOutput
    }
}
