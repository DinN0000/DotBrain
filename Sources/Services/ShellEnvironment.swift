import Foundation

/// Shared shell environment utilities for CLI-based AI providers.
/// Centralizes shell env loading, binary resolution, and RC file sourcing
/// to avoid duplication across ClaudeCLIClient and CodexCLIClient.
enum ShellEnvironment {

    // MARK: - Cached State

    private static var cachedEnvironment: [String: String]?

    // MARK: - Shell Environment

    /// Load environment variables from user's shell config.
    /// Sources .zshrc/.bashrc explicitly (no -i flag to avoid side effects).
    /// Result is cached — shell is spawned only once per app session.
    static func loadUserEnvironment() -> [String: String] {
        if let cached = cachedEnvironment { return cached }

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

            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                if process.isRunning { process.terminate() }
            }

            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                cachedEnvironment = baseEnv
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
            cachedEnvironment = env
            return env
        } catch {
            cachedEnvironment = baseEnv
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

            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                if process.isRunning { process.terminate() }
            }

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

    /// Shell command to explicitly source RC files without interactive mode.
    private static var rcSourceCommand: String {
        "[ -f ~/.zprofile ] && . ~/.zprofile 2>/dev/null; [ -f ~/.bash_profile ] && . ~/.bash_profile 2>/dev/null; [ -f ~/.zshrc ] && . ~/.zshrc 2>/dev/null; [ -f ~/.bashrc ] && . ~/.bashrc 2>/dev/null"
    }
}
