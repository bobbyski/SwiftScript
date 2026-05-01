import Foundation

public struct PathResolver: @unchecked Sendable {
    private let fileManager: FileManager
    private let environment: [String: String]

    public init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.environment = environment
    }

    public func resolve(_ executable: String, currentDirectory: URL) -> URL? {
        if executable.contains("/") {
            let url = URL(fileURLWithPath: executable, relativeTo: currentDirectory)
                .standardizedFileURL
            return isExecutableFile(at: url) ? url : nil
        }

        let pathValue = environment["PATH"] ?? ""
        for directory in pathValue.split(separator: ":", omittingEmptySubsequences: false) {
            let base = directory.isEmpty
                ? currentDirectory
                : URL(fileURLWithPath: String(directory), isDirectory: true)
            let candidate = base.appendingPathComponent(executable)
            if isExecutableFile(at: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func isExecutableFile(at url: URL) -> Bool {
        fileManager.isExecutableFile(atPath: url.path)
    }
}
