import Foundation

/// Shared shell environment utilities for CLI-based AI providers.
/// Centralizes shell env loading, binary resolution, and RC file sourcing
/// to avoid duplication across ClaudeCLIClient and CodexCLIClient.
enum ShellEnvironment {

    // MARK: - Process Timeout

    /// Schedule process termination after a duration. Cancel the returned task when the process exits normally.
    @discardableResult
    static func scheduleTermination(of process: Process, after duration: Duration) -> Task<Void, Never> {
        Task.detached {
            try? await Task.sleep(for: duration)
            if process.isRunning { process.terminate() }
        }
    }

    // MARK: - Cached State

    private static let cacheLock = NSLock()
    private static nonisolated(unsafe) var cachedEnvironment: [String: String]?

    // MARK: - Shell Environment

    /// Load environment variables from user's shell config.
    /// Sources .zshrc/.bashrc explicitly (no -i flag to avoid side effects).
    /// Result is cached — shell is spawned only once per app session.
    static func loadUserEnvironment() -> [String: String] {
        if let cached = cacheLock.withLock({ cachedEnvironment }) { return cached }

        let baseEnv = ProcessInfo.processInfo.environment
        let userShell = baseEnv["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: userShell)
        process.arguments = ["-l", "-c", "\(rcSourceCommand); env"]
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()

            let timeout = scheduleTermination(of: process, after: .seconds(5))
            defer { timeout.cancel() }

            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                cacheLock.withLock { cachedEnvironment = baseEnv }
                return baseEnv
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            var env = baseEnv
            for line in output.split(separator: "\n") {
                guard let eqIndex = line.firstIndex(of: "=") else { continue }
                let key = String(line[line.startIndex..<eqIndex])
                let value = String(line[line.index(after: eqIndex)...])
                env[key] = value
            }
            cacheLock.withLock { cachedEnvironment = env }
            return env
        } catch {
            cacheLock.withLock { cachedEnvironment = baseEnv }
            return baseEnv
        }
    }

    // MARK: - Binary Resolution

    /// Resolve a CLI binary path via user's shell with explicit RC file sourcing.
    /// Uses `command -v` (POSIX, more reliable than `which`).
    static func resolveBinaryViaShell(_ binaryName: String) -> String? {
        let userShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: userShell)
        process.arguments = ["-l", "-c", "\(rcSourceCommand); command -v \(binaryName)"]
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()

            let timeout = scheduleTermination(of: process, after: .seconds(5))
            defer { timeout.cancel() }

            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Take last non-empty line (in case shell prints anything before)
            let path = output.split(separator: "\n").last.map(String.init) ?? output

            guard !path.isEmpty,
                  FileManager.default.isExecutableFile(atPath: path) else { return nil }
            return path
        } catch {
            return nil
        }
    }

    // MARK: - Process Output Collection

    /// Collect output from a running process, validate exit status, return trimmed result.
    /// Shared by ClaudeCLIClient and CodexCLIClient to avoid duplication.
    static func collectProcessOutput(
        process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        errorFactory: (Int32, String) -> Error,
        emptyErrorFactory: () -> Error
    ) throws -> String {
        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            throw errorFactory(process.terminationStatus, String(errorOutput.prefix(500)))
        }

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            throw emptyErrorFactory()
        }

        return trimmed
    }

    /// Write prompt data into a child process stdin and close it.
    /// Uses the throwing FileHandle API so broken pipes surface as normal Swift errors.
    static func writeProcessInput(_ input: String, to handle: FileHandle) throws {
        if let data = input.data(using: .utf8), !data.isEmpty {
            try handle.write(contentsOf: data)
        }
        try? handle.close()
    }

    /// Shell command to explicitly source RC files without interactive mode.
    private static var rcSourceCommand: String {
        "[ -f ~/.zprofile ] && . ~/.zprofile 2>/dev/null; [ -f ~/.bash_profile ] && . ~/.bash_profile 2>/dev/null; [ -f ~/.zshrc ] && . ~/.zshrc 2>/dev/null; [ -f ~/.bashrc ] && . ~/.bashrc 2>/dev/null"
    }
}
