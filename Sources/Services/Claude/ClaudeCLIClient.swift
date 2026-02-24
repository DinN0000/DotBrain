import Foundation

/// Claude CLI client using `claude -p` pipe mode.
/// Sends prompts via stdin, receives responses from stdout.
/// Requires Claude CLI to be installed on the system.
actor ClaudeCLIClient {

    static let fastModel = "haiku"
    static let preciseModel = "sonnet"

    // MARK: - Availability Check (sync, for AIProvider.hasAPIKey)

    /// Check if claude CLI binary is found at known paths
    static func isAvailable() -> Bool {
        findClaudePath() != nil
    }

    private static func findClaudePath() -> String? {
        // 1. Resolve via user's login shell (loads .zshenv, .zprofile, .zshrc)
        if let path = resolveViaLoginShell() {
            return path
        }

        // 2. Fallback to well-known paths
        let homeDir = NSHomeDirectory()
        let candidates = [
            "\(homeDir)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Load environment variables from user's login shell.
    /// Captures PATH, proxy settings, SSL certs, etc. that GUI apps miss.
    private static func loadUserShellEnvironment() -> [String: String] {
        let baseEnv = ProcessInfo.processInfo.environment
        let userShell = baseEnv["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: userShell)
        process.arguments = ["-l", "-c", "env"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return baseEnv }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            var env = baseEnv
            for line in output.split(separator: "\n") {
                guard let eqIndex = line.firstIndex(of: "=") else { continue }
                let key = String(line[line.startIndex..<eqIndex])
                let value = String(line[line.index(after: eqIndex)...])
                env[key] = value
            }
            return env
        } catch {
            return baseEnv
        }
    }

    /// Run user's login shell to resolve claude path via `which`
    private static func resolveViaLoginShell() -> String? {
        let userShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: userShell)
        process.arguments = ["-l", "-c", "which claude"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !path.isEmpty,
                  FileManager.default.isExecutableFile(atPath: path) else { return nil }
            return path
        } catch {
            return nil
        }
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
