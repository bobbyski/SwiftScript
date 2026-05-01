import Foundation

public enum SimpleShellCommandResult: Equatable, Sendable {
    case `continue`
    case exit(Int32)
}

public final class SimpleShellEngine: @unchecked Sendable {
    private let console: any ScriptConsole
    private let pathResolver: PathResolver
    private let processRunner: ProcessRunner
    private let fileManager: FileManager
    private var currentDirectory: URL
    private var isRunningScript = false

    public init(
        console: any ScriptConsole,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        pathResolver: PathResolver = PathResolver(),
        processRunner: ProcessRunner = ProcessRunner(),
        fileManager: FileManager = .default
    ) {
        self.console = console
        self.currentDirectory = currentDirectory
        self.pathResolver = pathResolver
        self.processRunner = processRunner
        self.fileManager = fileManager
    }

    public func runInteractive(prompt: String = "swiftsh> ") async throws -> Int32 {
        while let line = try await console.stdin.readLine(prompt: prompt) {
            let result = try await executeLine(line)
            if case let .exit(code) = result {
                return code
            }
        }

        return 0
    }

    public func runScript(at path: URL, shellPath: String? = nil) async throws -> Int32 {
        let script = try ShellScript.load(from: path, shellPath: shellPath)
        isRunningScript = true
        defer { isRunningScript = false }

        for rawLine in script.lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            let result = try await executeLine(line)
            if case let .exit(code) = result {
                return code
            }
        }

        return 0
    }

    @discardableResult
    public func executeLine(_ line: String) async throws -> SimpleShellCommandResult {
        guard let command = try CommandParser.parse(line) else {
            return .continue
        }

        switch command.executable {
        case "exit":
            return .exit(exitCode(from: command.arguments))
        case "ls":
            try await listDirectory(command.arguments)
            return .continue
        case "run":
            guard let scriptPath = command.arguments.first else {
                try await console.stderr.write("run: missing script file\n")
                return .continue
            }

            let scriptURL = URL(fileURLWithPath: scriptPath, relativeTo: currentDirectory)
                .standardizedFileURL
            let code = try await runScript(at: scriptURL)
            return code == 0 ? .continue : .exit(code)
        default:
            guard let executableURL = pathResolver.resolve(
                command.executable,
                currentDirectory: currentDirectory
            ) else {
                try await console.stderr.write("\(command.executable): command not found\n")
                return .continue
            }

            let result = try await processRunner.run(
                executableURL: executableURL,
                arguments: command.arguments,
                console: console,
                currentDirectory: currentDirectory
            )
            return result.exitCode == 0 || !isRunningScript
                ? .continue
                : .exit(result.exitCode)
        }
    }

    private func listDirectory(_ arguments: [String]) async throws {
        let path = arguments.first ?? "."
        let url = URL(fileURLWithPath: path, relativeTo: currentDirectory)
            .standardizedFileURL
        let entries = try fileManager.contentsOfDirectory(atPath: url.path).sorted()

        for entry in entries {
            try await console.stdout.write("\(entry)\n")
        }
    }

    private func exitCode(from arguments: [String]) -> Int32 {
        guard let first = arguments.first, let code = Int32(first) else {
            return 0
        }

        return code
    }
}
