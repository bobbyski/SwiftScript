# White Paper: A Protocol-Oriented Swift Scripting Framework Built on the Swift REPL

## Executive Summary

This paper proposes a Swift scripting framework that embeds or drives the Swift REPL machinery while exposing a clean, protocol-oriented interface for console I/O, host APIs, lifecycle management, and shell-style command execution. The goal is to make Swift usable as an application scripting language in the same broad category as Bash, Zsh, Python, Ruby, or JavaScript, while preserving Swift's type system, module model, concurrency features, and native interoperability.

The key architectural choice is to avoid baking the terminal, file descriptors, process model, and host APIs directly into the scripting engine. Instead, the framework defines protocols for standard input, standard output, standard error, diagnostics, module exposure, execution context, and shell integration. A command-line shell can bind those protocols to a real terminal. An IDE can bind them to editor panes. A server can bind them to WebSockets. A test harness can bind them to in-memory buffers.

The framework should use Swift's existing REPL implementation as much as possible rather than inventing a new Swift interpreter. In current Swift toolchains, the user-facing REPL is tightly coupled to LLDB and Swift expression evaluation. Swift Package Manager also demonstrates a practical model for launching the REPL with compiler arguments that make package library targets importable. Those two facts point toward an initial design that launches and controls a matched Swift/LLDB REPL process, then evolves toward deeper library-level integration only where stable APIs exist.

## Background

Swift already has a REPL, but it is not shaped like a reusable scripting framework. Swift.org documents that the Swift REPL is built on LLDB, and that the debugger and compiler must come from matching sources because Swift expression evaluation depends on tight compiler/debugger integration. This is a powerful foundation, but it also means a scripting framework should treat the REPL as a toolchain component with versioned compatibility requirements, not as a small embeddable library with a stable public ABI.

Swift Package Manager provides another important precedent. `swift run --repl` launches a REPL configured with compiler arguments that allow package library targets to be imported. This is almost exactly the capability a scripting framework needs for host API exposure: build or locate a module, pass the right include/library/search-path flags to the REPL, and let scripts write ordinary Swift such as:

```swift
import HostAutomation

let files = try Host.fileSystem.list("/tmp")
print(files)
```

The proposed framework should therefore begin with process-level REPL orchestration and protocol-based I/O. That keeps the first implementation realistic, portable, and testable. A later phase can investigate lower-level integration with LLDB's public APIs or specific Swift compiler internals.

## Goals

1. Provide Swift as a reusable scripting language engine for host applications.
2. Make stdin, stdout, and stderr pluggable through protocols.
3. Allow host applications to expose APIs to scripts as if those APIs came from normal Swift modules.
4. Support both interactive and non-interactive execution.
5. Provide shell-like behavior: prompts, command history, pipelines, process launching, environment variables, working directories, job control, and startup files.
6. Keep the architecture testable without a terminal or child process where possible.
7. Preserve a path toward deeper integration with the Swift compiler and LLDB without requiring it on day one.

## Non-Goals

1. Reimplementing the Swift compiler.
2. Reimplementing the full Swift runtime.
3. Creating a separate Swift-like language.
4. Guaranteeing sandboxing purely through Swift language boundaries.
5. Matching every behavior of Bash or Zsh in the first version.

## High-Level Architecture

The framework can be organized around five layers:

1. `SwiftScriptCore`: protocol definitions, execution models, stream abstractions, diagnostics, and common value types.
2. `SwiftREPLBridge`: a concrete implementation that launches and coordinates a Swift/LLDB REPL process.
3. `SwiftScriptModules`: support for building, discovering, loading, and exposing host API modules to the REPL.
4. `SwiftShellRuntime`: shell primitives such as commands, pipelines, redirection, environment, current directory, globbing, and jobs.
5. `swiftsh`: a shell executable that uses the framework as its scripting language engine.

The dependency direction should be strict:

```text
swiftsh
  -> SwiftShellRuntime
    -> SwiftScriptModules
      -> SwiftREPLBridge
        -> SwiftScriptCore
```

This keeps the REPL transport independent from shell behavior. A GUI app should be able to use `SwiftREPLBridge` without taking a dependency on shell parsing or job control.

## Protocol-Oriented Console I/O

The console should be modeled as capabilities, not global file descriptors. The minimal protocols are:

```swift
public protocol ScriptInput {
    func readLine(prompt: String?) async throws -> String?
    func readBytes(upTo count: Int) async throws -> [UInt8]
}

public protocol ScriptOutput {
    func write(_ text: String) async throws
    func write(bytes: [UInt8]) async throws
    func flush() async throws
}

public protocol ScriptConsole {
    var stdin: ScriptInput { get }
    var stdout: ScriptOutput { get }
    var stderr: ScriptOutput { get }
}
```

Concrete implementations can include:

1. `TerminalConsole`, backed by process stdin/stdout/stderr.
2. `MemoryConsole`, for tests.
3. `SocketConsole`, for remote REPL sessions.
4. `GUIConsole`, for an editor or notebook-style interface.
5. `MultiplexedConsole`, for teeing output to a terminal and a log.

The framework should not assume that stdin is a TTY. Prompting, raw mode, line editing, and terminal control should be separate optional protocols:

```swift
public protocol InteractiveConsole: ScriptConsole {
    var terminalSize: TerminalSize { get async }
    func setRawMode(_ enabled: Bool) async throws
}

public protocol ConsoleColorSupport {
    var supportsANSIColors: Bool { get }
}
```

This makes the system usable in scripts, CI, GUI applications, and web contexts.

## REPL Engine Protocols

The core engine should be represented by a protocol that hides whether execution is performed by an external process, LLDB APIs, or a future embedded Swift interpreter:

```swift
public protocol ScriptEngine {
    associatedtype Session: ScriptSession

    func start(configuration: ScriptEngineConfiguration,
               console: ScriptConsole) async throws -> Session
}

public protocol ScriptSession: AnyObject {
    var state: ScriptSessionState { get async }

    func evaluate(_ source: String) async throws -> ScriptEvaluationResult
    func interrupt() async throws
    func reset() async throws
    func finish() async throws
}
```

The REPL bridge implementation would provide:

```swift
public final class SwiftREPLEngine: ScriptEngine {
    public func start(configuration: ScriptEngineConfiguration,
                      console: ScriptConsole) async throws -> SwiftREPLSession {
        // Launch swift/lldb REPL with configured arguments.
    }
}
```

The design should separate source submission from output capture. Evaluation can produce structured metadata where available, while stdout and stderr remain stream events:

```swift
public struct ScriptEvaluationResult {
    public var exitStatus: ScriptExitStatus
    public var displayValue: String?
    public var diagnostics: [ScriptDiagnostic]
}
```

## Bridging to the Swift REPL

The first production-quality bridge should be process-based:

1. Locate a compatible Swift toolchain.
2. Launch the Swift REPL or LLDB-backed REPL with arguments.
3. Connect the child process stdin/stdout/stderr to the `ScriptConsole`.
4. Detect prompts, continuation prompts, diagnostics, and completion.
5. Provide cancellation through process signals or LLDB interrupt commands.
6. Restart sessions when the process becomes unrecoverable.

This is less elegant than linking directly to compiler internals, but it has two large advantages: it follows how Swift is distributed today, and it avoids taking source-level dependencies on unstable compiler implementation details.

The bridge needs a transport abstraction:

```swift
public protocol REPLTransport {
    func send(_ source: String) async throws
    func receiveEvent() async throws -> REPLEvent
    func interrupt() async throws
    func terminate() async throws
}
```

Initial transports:

1. `ProcessREPLTransport`, backed by a local child process.
2. `LLDBTransport`, a possible future implementation using LLDB APIs.
3. `RemoteREPLTransport`, for daemonized or containerized execution.

## Exposing Host APIs as Imported Modules

The cleanest way to expose APIs to scripts is to make them real Swift modules. That means scripts do not need special syntax or dynamic lookup rules. They simply import modules.

Example script:

```swift
import HostAutomation

let result = try await Host.http.get("https://example.com")
print(result.statusCode)
```

The framework can support this with a `ScriptModuleProvider` protocol:

```swift
public protocol ScriptModuleProvider {
    var moduleName: String { get }

    func prepareModule(for configuration: ScriptEngineConfiguration) async throws -> ScriptModuleDescriptor
}

public struct ScriptModuleDescriptor {
    public var moduleName: String
    public var compilerArguments: [String]
    public var linkerArguments: [String]
    public var runtimeEnvironment: [String: String]
}
```

A provider can represent:

1. A prebuilt Swift package library.
2. A host-generated wrapper module.
3. A C or Objective-C module exposed through a module map.
4. A dynamic library plus `.swiftmodule` files.
5. A remote API proxy generated as Swift source.

The engine configuration collects these descriptors and passes their arguments to the REPL. This mirrors the SwiftPM approach: configure the REPL so the module search path, library search path, SDK, target, and runtime paths make the host module importable.

## Host API Shape

Host APIs should be designed as ordinary Swift. Avoid forcing scripts through stringly typed command dispatch unless the API is truly dynamic.

Good:

```swift
public enum Host {
    public static let fileSystem = FileSystemClient()
    public static let process = ProcessClient()
    public static let secrets = SecretsClient()
}
```

Script:

```swift
import HostAutomation

let names = try Host.fileSystem.list(".")
try Host.process.run("git", ["status", "--short"])
```

For long-running or privileged hosts, the imported Swift module should usually be a client stub, not the host itself. The script calls Swift APIs, and those APIs communicate with the host over XPC, Unix sockets, HTTP, gRPC, or another RPC transport. This gives the host process control over authorization, auditing, cancellation, and resource limits.

## Dynamic API Injection

There are two ways to make APIs available:

1. Static module import.
2. Session prelude injection.

Static module import is preferable for stable APIs. Prelude injection is useful for convenience names:

```swift
import HostAutomation

let fs = Host.fileSystem
let sh = Host.process
```

The framework can support a startup prelude:

```swift
public struct ScriptPrelude {
    public var source: String
    public var visibility: PreludeVisibility
}
```

The prelude is evaluated automatically when a session starts. It can import modules, define aliases, configure logging, and install shell helpers.

## Shell App Design

A shell application like Bash or Zsh has two related but distinct jobs:

1. Provide an interactive command environment.
2. Execute scripts.

Using Swift as the scripting language means the shell needs to decide how traditional shell syntax maps to Swift syntax. There are three possible approaches.

### Approach A: Pure Swift Shell

The shell accepts Swift code directly:

```swift
let files = try sh.capture("ls", ["-la"])
print(files)
```

This is the simplest and most type-safe approach. It is excellent for automation, but less convenient for ad hoc terminal use.

### Approach B: Swift With Shell Literals

The shell accepts Swift plus special command syntax:

```swift
let files = try #sh("ls -la | grep swift")
```

This can be implemented as macros in compiled contexts, but a REPL/scripting environment may need parser support or a preprocessor that rewrites shell literals into Swift API calls.

### Approach C: Dual-Mode Shell

The shell treats simple command lines as shell commands and Swift blocks as Swift code:

```text
swiftsh> ls -la | grep swift
swiftsh> swift {
           let names = try Host.fileSystem.list(".")
           print(names)
         }
```

This is most familiar to shell users but is more complex. It requires a shell parser, command resolution, pipelines, redirection, quoting, globbing, and a clear escape hatch into Swift.

For a first version, this paper recommends Approach A plus a high-quality `sh` API. Approach C can be layered later.

## Shell Runtime API

The host module should expose shell primitives:

```swift
public struct Shell {
    public var environment: [String: String]
    public var currentDirectory: URL

    public func run(_ executable: String,
                    _ arguments: [String] = []) async throws -> ProcessResult

    public func capture(_ executable: String,
                        _ arguments: [String] = []) async throws -> String

    public func pipeline(_ commands: [Command]) async throws -> ProcessResult
}

public struct Command {
    public var executable: String
    public var arguments: [String]
}
```

Example script:

```swift
import SwiftShellRuntime

let changed = try await sh.capture("git", ["status", "--short"])

if changed.isEmpty {
    print("Clean")
} else {
    print(changed)
}
```

Pipelines can be strongly represented instead of parsed from strings:

```swift
try await sh.pipeline([
    .init("ps", ["aux"]),
    .init("grep", ["swift"]),
    .init("sort", ["-k", "2"])
])
```

With result builders, this could become:

```swift
try await sh.pipeline {
    Command("ps", "aux")
    Command("grep", "swift")
    Command("sort", "-k", "2")
}
```

## Interactive Shell Loop

The shell executable is mostly an adapter:

```swift
@main
struct SwiftShellMain {
    static func main() async throws {
        let console = TerminalConsole()
        let modules = [
            ShellRuntimeModuleProvider(),
            HostAutomationModuleProvider()
        ]

        let configuration = ScriptEngineConfiguration(
            modules: modules,
            prelude: .defaultShellPrelude
        )

        let engine = SwiftREPLEngine()
        let session = try await engine.start(configuration: configuration,
                                             console: console)

        let shell = InteractiveShell(console: console, session: session)
        try await shell.run()
    }
}
```

The interactive loop handles:

1. Prompt rendering.
2. History.
3. Multiline input.
4. Syntax completeness detection.
5. Evaluation.
6. Interrupts.
7. Exit commands.
8. Startup files such as `~/.swiftshrc`.

Syntax completeness is important. If a user types:

```swift
for file in files {
```

the shell should show a continuation prompt rather than immediately evaluating an incomplete fragment. Initially, completeness can be delegated to the REPL. Later, SwiftSyntax may provide better local parsing and editor features.

## Script Execution

For script files, `swiftsh` should support:

```bash
swiftsh script.swiftsh arg1 arg2
```

The script can be ordinary Swift with imports and top-level code. The runtime module exposes arguments:

```swift
import SwiftShellRuntime

print(CommandLine.arguments)
```

There are two execution strategies:

1. Feed the script into a configured REPL session.
2. Compile and run the script with `swift` or `swiftc` using the same module descriptors.

The REPL path is useful for interactive continuity. The compile/run path may be faster and more predictable for production scripts. The framework should support both behind one protocol:

```swift
public protocol ScriptRunner {
    func runFile(_ path: URL,
                 configuration: ScriptEngineConfiguration,
                 console: ScriptConsole) async throws -> ScriptRunResult
}
```

## Security Model

Swift's type system is not a sandbox. A script that can import Foundation and run processes can affect the system. Security must be designed explicitly.

Recommended controls:

1. Run untrusted scripts in a separate process.
2. Use OS sandboxing where available.
3. Expose privileged host APIs only through an authorization-checking RPC boundary.
4. Make file system and network access explicit capabilities.
5. Log privileged actions.
6. Support cancellation and resource limits.
7. Allow module allowlists.

The protocol-oriented design helps here: a host can provide a restricted `ScriptConsole`, restricted module providers, a constrained environment, and a separate execution process.

## Error Handling and Diagnostics

Diagnostics should be first-class:

```swift
public struct ScriptDiagnostic {
    public var severity: DiagnosticSeverity
    public var message: String
    public var location: SourceLocation?
    public var fixIts: [FixIt]
}
```

At process level, diagnostics may initially be parsed from stderr. That is brittle but useful. Deeper integration with SourceKit, SwiftSyntax, or compiler diagnostic formats can improve this over time.

The shell should distinguish:

1. Swift compile/type-check errors.
2. Runtime thrown errors.
3. Process exit failures.
4. REPL transport failures.
5. Host API authorization failures.

## Testing Strategy

Testing should happen at several layers:

1. Unit test `MemoryConsole`.
2. Unit test shell APIs without launching Swift.
3. Integration test `SwiftREPLEngine` against a known local toolchain.
4. Integration test module exposure with a tiny fixture package.
5. End-to-end test `swiftsh` with scripted stdin/stdout/stderr.
6. Compatibility test across supported Swift toolchain versions.

The process-backed REPL bridge should be tested with golden transcripts, but tests should avoid depending on cosmetic prompt details where possible.

## Versioning and Toolchain Compatibility

Because the Swift REPL is coupled to LLDB and compiler internals, the framework should model the toolchain explicitly:

```swift
public struct SwiftToolchain {
    public var swiftExecutable: URL
    public var lldbExecutable: URL?
    public var version: String
    public var resourceDirectory: URL?
}
```

The framework should detect incompatible or incomplete toolchains early and report a clear diagnostic. It should also allow applications to pin a toolchain.

## Roadmap

### Phase 1: Process-Backed REPL Prototype

1. Define `SwiftScriptCore` protocols.
2. Implement `TerminalConsole` and `MemoryConsole`.
3. Implement `ProcessREPLTransport`.
4. Launch Swift REPL with basic stdin/stdout/stderr bridging.
5. Evaluate single-line and multiline Swift.

### Phase 2: Module Exposure

1. Define `ScriptModuleProvider`.
2. Support prebuilt Swift module import.
3. Support package-based module import using SwiftPM-derived compiler arguments.
4. Add startup prelude support.

### Phase 3: Shell Runtime

1. Add `Shell` API for process execution.
2. Add capture, pipelines, environment, and working directory.
3. Build `swiftsh` interactive loop.
4. Add history and startup file support.

### Phase 4: Production Hardening

1. Add structured diagnostics.
2. Add cancellation and restart policies.
3. Add toolchain detection.
4. Add script execution mode.
5. Add security controls and module allowlists.

### Phase 5: Deeper Integration

1. Investigate LLDB API integration.
2. Investigate SourceKit/SwiftSyntax-assisted editing and completion.
3. Explore persistent compiled module caches.
4. Explore debugger-backed inspection and recovery features.

## Key Risks

1. Swift REPL internals are not designed primarily as a stable embedding API.
2. Prompt parsing and output detection can be fragile.
3. Toolchain/LLDB version mismatch can cause confusing failures.
4. Startup latency may be higher than traditional scripting languages.
5. Exposing host APIs safely requires an explicit security boundary.
6. Shell ergonomics may require syntax beyond plain Swift.

## Recommendation

Start with a process-backed Swift REPL bridge and a protocol-oriented console model. Use real Swift modules for API exposure rather than inventing a custom import mechanism. Build a shell as a host application that wires together:

1. A `ScriptConsole`.
2. A `SwiftREPLEngine`.
3. A set of `ScriptModuleProvider`s.
4. A startup prelude.
5. A `Shell` runtime module.

This approach gives the project a realistic first milestone while preserving long-term options. It treats Swift as Swift, lets host APIs feel native, and keeps the terminal, GUI, server, and test use cases cleanly separated behind protocols.

## Sources

1. Swift.org, "REPL and Debugger": https://www.swift.org/documentation/lldb/
2. Swift.org, "Swift Compiler": https://www.swift.org/documentation/swift-compiler/
3. Swift.org, "Source Code": https://www.swift.org/documentation/source-code/
4. Swift.org Blog, "REPL Support for Swift Packages": https://www.swift.org/blog/swiftpm-repl-support/
