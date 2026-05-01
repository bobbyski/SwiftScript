import Foundation
import Testing
@testable import SwiftScript

@Test func builtInLsListsDirectory() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    FileManager.default.createFile(
        atPath: temporaryDirectory.appendingPathComponent("hello.txt").path,
        contents: Data()
    )

    let console = MemoryConsole(lines: [])
    let engine = SimpleShellEngine(
        console: console,
        currentDirectory: temporaryDirectory
    )

    try await engine.executeLine("ls")

    let output = await console.output.contents()
    #expect(output.contains("hello.txt\n"))
}

@Test func builtInExitReturnsCode() async throws {
    let console = MemoryConsole(lines: [])
    let engine = SimpleShellEngine(console: console)

    let result = try await engine.executeLine("exit 7")

    #expect(result == .exit(7))
}

@Test func unknownCommandWritesError() async throws {
    let console = MemoryConsole(lines: [])
    let engine = SimpleShellEngine(
        console: console,
        pathResolver: PathResolver(environment: ["PATH": ""])
    )

    try await engine.executeLine("missing-command")

    let error = await console.errorOutput.contents()
    #expect(error.contains("missing-command: command not found"))
}

@Test func scriptLoaderValidatesShebangWhenShellPathIsProvided() throws {
    let temporaryFile = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).swiftsh")
    try "#!/tmp/SimpleShell\necho hi\n".write(to: temporaryFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: temporaryFile) }

    let script = try ShellScript.load(from: temporaryFile, shellPath: "/tmp/SimpleShell")

    #expect(script.lines == ["echo hi", ""])
}
