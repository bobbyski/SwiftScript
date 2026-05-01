import Foundation

public struct ProcessResult: Sendable {
    public var exitCode: Int32

    public init(exitCode: Int32) {
        self.exitCode = exitCode
    }
}

public struct ProcessRunner: Sendable {
    public init() {}

    public func run(
        executableURL: URL,
        arguments: [String],
        console: any ScriptConsole,
        currentDirectory: URL? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        async let outputTask: Void = stream(stdout.fileHandleForReading, to: console.stdout)
        async let errorTask: Void = stream(stderr.fileHandleForReading, to: console.stderr)

        process.waitUntilExit()
        try await outputTask
        try await errorTask

        return ProcessResult(exitCode: process.terminationStatus)
    }

    private func stream(_ handle: FileHandle, to output: any ScriptOutput) async throws {
        while true {
            let data = try handle.read(upToCount: 4096) ?? Data()
            if data.isEmpty {
                break
            }

            let text = String(decoding: data, as: UTF8.self)
            try await output.write(text)
        }
    }
}
