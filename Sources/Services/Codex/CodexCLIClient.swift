import Foundation

/// OpenAI Codex CLI client using `codex` command.
/// Sends prompts via stdin, receives responses from stdout.
/// Requires Codex CLI to be installed and authenticated via `codex auth login`.
actor CodexCLIClient {

    static let fastModel = "o4-mini"
    static let preciseModel = "o3"

    // MARK: - Cached State

    private static var cachedEnvironment: [String: String]?
    private static var cachedCodexPath: String?
    private static var codexPathResolved = false

    // MARK: - Availability Check

    /// Check if codex CLI binary is found at known paths
    static func isAvailable() -> Bool {
        findCodexPath() != nil
    }

    /// Check if codex CLI is authenticated (auth token exists)
    static func isAuthenticated() -> Bool {
        let homeDir = NSHomeDirectory()
        let authPath = "\(homeDir)/.codex/auth.json"
        return FileManager.default.fileExists(atPath: authPath)
    }

    private static func findCodexPath() -> String? {
        if codexPathResolved, let cached = cachedCodexPath {
            if FileManager.default.isExecutableFile(atPath: cached) {
                return cached
            }
            cachedCodexPath = nil
            codexPathResolved = false
        }
        if codexPathResolved { return cachedCodexPath }

        // 1. Resolve via user's shell
        if let path = resolveViaShell() {
            cachedCodexPath = path
            codexPathResolved = true
            return path
        }

        // 2. Fallback to well-known paths
        let homeDir = NSHomeDirectory()
        let candidates = [
            "\(homeDir)/.local/bin/codex",
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            "\(homeDir)/.npm-global/bin/codex",
            "/usr/bin/codex",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedCodexPath = path
                codexPathResolved = true
                return path
            }
        }

        codexPathResolved = true
        return nil
    }

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

    private static func resolveViaShell() -> String? {
        let userShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: userShell)
        process.arguments = ["-l", "-c", "\(rcSourceCommand); command -v codex"]
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

            let path = output.split(separator: "\n").last.map(String.init) ?? output

            guard !path.isEmpty,
                  FileManager.default.isExecutableFile(atPath: path) else { return nil }
            return path
        } catch {
            return nil
        }
    }

    private static var rcSourceCommand: String {
        "[ -f ~/.zprofile ] && . ~/.zprofile 2>/dev/null; [ -f ~/.bash_profile ] && . ~/.bash_profile 2>/dev/null; [ -f ~/.zshrc ] && . ~/.zshrc 2>/dev/null; [ -f ~/.bashrc ] && . ~/.bashrc 2>/dev/null"
    }

    // MARK: - Send Message

    /// Send a prompt to Codex CLI and return the text response.
    /// Uses `codex -q` quiet mode with full-auto approval for non-interactive use.
    func sendMessage(
        model: String,
        maxTokens: Int,
        userMessage: String
    ) async throws -> (String, TokenUsage?) {
        guard let codexPath = Self.findCodexPath() else {
            throw CodexCLIError.codexNotFound
        }

        guard Self.isAuthenticated() else {
            throw CodexCLIError.notAuthenticated
        }

        let arguments = ["-q", "--model", model, "--approval-mode", "full-auto"]
        let result = try await runProcess(
            executablePath: codexPath,
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
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.environment = Self.loadUserShellEnvironment()

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()

            // 180s timeout (CLI process overhead)
            DispatchQueue.global().asyncAfter(deadline: .now() + 180) {
                if process.isRunning { process.terminate() }
            }

            if let data = input.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            inputPipe.fileHandleForWriting.closeFile()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                throw CodexCLIError.processError(
                    status: process.terminationStatus,
                    message: String(errorOutput.prefix(500))
                )
            }

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                throw CodexCLIError.emptyResponse
            }

            return trimmed
        }.value
    }
}

// MARK: - Errors

enum CodexCLIError: LocalizedError {
    case codexNotFound
    case notAuthenticated
    case processError(status: Int32, message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "Codex CLI를 찾을 수 없습니다. 설치: npm install -g @openai/codex"
        case .notAuthenticated:
            return "Codex CLI 인증이 필요합니다. 터미널에서 codex auth login 실행"
        case .processError(_, let message):
            return "Codex CLI 오류: \(message.isEmpty ? "알 수 없는 오류" : message)"
        case .emptyResponse:
            return "Codex CLI에서 빈 응답"
        }
    }
}
