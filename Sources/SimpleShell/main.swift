import Foundation
import SwiftScript

let console = TerminalConsole()
let engine = SimpleShellEngine(console: console)

do {
    let shellPath = CommandLine.arguments.first
    let exitCode: Int32

    if CommandLine.arguments.count > 1 {
        let scriptPath = CommandLine.arguments[1]
        let scriptURL = URL(fileURLWithPath: scriptPath).standardizedFileURL
        exitCode = try await engine.runScript(at: scriptURL, shellPath: shellPath)
    } else {
        exitCode = try await engine.runInteractive()
    }

    Foundation.exit(exitCode)
} catch {
    try? await console.stderr.write("SimpleShell: \(error)\n")
    Foundation.exit(1)
}
