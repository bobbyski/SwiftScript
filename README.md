# SwiftScript

SwiftScript is a SwiftPM package that starts the protocol-oriented scripting framework described in `WHITEPAPER.md`.

It currently contains:

1. `SwiftScript`: a reusable library with console protocols, command parsing, PATH resolution, script loading, process execution, and a small shell engine.
2. `SimpleShell`: a demo shell executable.

## SimpleShell Commands

`SimpleShell` supports three built-in commands:

```text
ls [directory]
run <scriptfile>
exit [code]
```

Any other command is resolved through the current `PATH` environment variable and executed as a child process.

## Usage

Run interactively:

```bash
swift run SimpleShell
```

Run a script:

```bash
swift run SimpleShell Examples/simple.swiftsh
```

Use as a shebang interpreter:

```swift
#!/absolute/path/to/SimpleShell
echo hello
exit 0
```

Then make the script executable:

```bash
chmod +x script.swiftsh
./script.swiftsh
```

## Development

Run tests:

```bash
swift test
```
