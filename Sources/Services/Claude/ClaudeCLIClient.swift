import Foundation

/// Claude CLI client using `claude -p` pipe mode.
/// Sends prompts via stdin, receives responses from stdout.
/// Requires Claude CLI to be installed on the system.
actor ClaudeCLIClient {

    static let fastModel = "haiku"
    static let preciseModel = "sonnet"

    // MARK: - Cached State

    /// Cached user shell environment (loaded once per app session)
    private static var cachedEnvironment: [String: String]?
    /// Cached claude binary path (resolved once per app session)
    private static var cachedClaudePath: String?
    private static var claudePathResolved = false

    // MARK: - Availability Check (sync, for AIProvider.hasAPIKey)

    /// Check if claude CLI binary is found at known paths
    static func isAvailable() -> Bool {
        findClaudePath() != nil
    }

    private static func findClaudePath() -> String? {
        // Return cached result if already resolved AND still valid
        if claudePathResolved, let cached = cachedClaudePath {
            if FileManager.default.isExecutableFile(atPath: cached) {
                return cached
            }
            // Cached path no longer valid (e.g. CLI upgraded, binary moved)
            cachedClaudePath = nil
            claudePathResolved = false
        }
        if claudePathResolved { return cachedClaudePath }

        // 1. Resolve via user's shell (sources .zshrc/.bashrc explicitly)
        if let path = resolveViaShell() {
            cachedClaudePath = path
            claudePathResolved = true
            return path
        }

        // 2. Fallback to well-known paths
        let homeDir = NSHomeDirectory()
        let candidates = [
            "\(homeDir)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(homeDir)/.npm-global/bin/claude",
            "/usr/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedClaudePath = path
                claudePathResolved = true
                return path
            }
        }

        // 3. Scan Claude versions directory for latest binary
        // (handles broken symlinks after CLI upgrade)
        if let path = findLatestVersionBinary(homeDir: homeDir) {
            cachedClaudePath = path
            claudePathResolved = true
            return path
        }

        claudePathResolved = true
        return nil
    }

    /// Scan ~/.local/share/claude/versions/ for the latest executable binary.
    /// Handles cases where symlink at ~/.local/bin/claude is broken after upgrade.
    private static func findLatestVersionBinary(homeDir: String) -> String? {
        let versionsDir = "\(homeDir)/.local/share/claude/versions"
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(atPath: versionsDir) else {
            return nil
        }

        // Sort version entries descending to try newest first (skip hidden files)
        let sorted = entries
            .filter { !$0.hasPrefix(".") }
            .sorted { a, b in
                a.compare(b, options: .numeric) == .orderedDescending
            }

        for entry in sorted {
            let fullPath = "\(versionsDir)/\(entry)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue else { continue }
            if fm.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        return nil
    }

    /// Load environment variables from user's shell config.
    /// Captures PATH, proxy settings, SSL certs, etc. that GUI apps miss.
    /// Sources .zshrc/.bashrc explicitly (no -i flag to avoid side effects).
    /// Result is cached — shell is spawned only once per app session.
    private static func loadUserShellEnvironment() -> [String: String] {
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

            // 5-second timeout to prevent hanging on heavy shell configs
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

    /// Resolve claude path via user's shell with explicit RC file sourcing.
    /// Uses `command -v` (POSIX, more reliable than `which`).
    /// No -i flag — avoids oh-my-zsh output pollution and stdin read attempts.
    private static func resolveViaShell() -> String? {
        let userShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: userShell)
        process.arguments = ["-l", "-c", "\(rcSourceCommand); command -v claude"]
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()

            // 5-second timeout
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
    /// Sources profile files first (login shell configs, no interactive guard),
    /// then rc files (where PATH extensions like ~/.local/bin are often added).
    private static var rcSourceCommand: String {
        "[ -f ~/.zprofile ] && . ~/.zprofile 2>/dev/null; [ -f ~/.bash_profile ] && . ~/.bash_profile 2>/dev/null; [ -f ~/.zshrc ] && . ~/.zshrc 2>/dev/null; [ -f ~/.bashrc ] && . ~/.bashrc 2>/dev/null"
    }

    // MARK: - Send Message

    /// Send a prompt to Claude CLI and return the text response.
    /// Token usage is not available from CLI, so it returns nil.
    func sendMessage(
        model: String,
        maxTokens: Int,
        userMessage: String
    ) async throws -> (String, TokenUsage?) {
        guard let claudePath = Self.findClaudePath() else {
            throw ClaudeCLIError.claudeNotFound
        }

        let arguments = ["-p", "--model", model, "--output-format", "text"]

        let result = try await runProcess(
            executablePath: claudePath,
            arguments: arguments,
            input: userMessage
        )

        return (result, nil)
    }

    // MARK: - Process Execution

    private func runProcess(
        executablePath: String,
        arguments: [String],
        input: String
    ) async throws -> String {
        // Use Task.detached for blocking process execution (per project convention)
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            // Load user's shell environment (proxy, SSL certs, PATH, etc.)
            let env = Self.loadUserShellEnvironment()
            process.environment = env

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()

            // Write prompt to stdin (handles long prompts without shell length limits)
            if let data = input.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            inputPipe.fileHandleForWriting.closeFile()

            // Read output before waitUntilExit to avoid pipe buffer deadlock
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                throw ClaudeCLIError.processError(
                    status: process.terminationStatus,
                    message: String(errorOutput.prefix(500))
                )
            }

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                throw ClaudeCLIError.emptyResponse
            }

            return trimmed
        }.value
    }
}

// MARK: - Errors

enum ClaudeCLIError: LocalizedError {
    case claudeNotFound
    case processError(status: Int32, message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "Claude CLI를 찾을 수 없습니다. 설치 확인: https://claude.com/download"
        case .processError(_, let message):
            return "Claude CLI 오류: \(message.isEmpty ? "알 수 없는 오류" : message)"
        case .emptyResponse:
            return "Claude CLI에서 빈 응답"
        }
    }
}
