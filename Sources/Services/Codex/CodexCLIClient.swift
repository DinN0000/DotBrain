import Foundation

/// OpenAI Codex CLI client using `codex exec` non-interactive mode.
/// Sends prompts via stdin, receives responses from stdout.
/// Requires Codex CLI to be installed and authenticated via `codex login`.
actor CodexCLIClient {

    static let fastModel = "gpt-5.3-codex-spark"
    static let preciseModel = "gpt-5.3-codex"

    // MARK: - Cached State

    private static var cachedCodexPath: String?
    private static var codexPathResolved = false

    // MARK: - Availability Check

    static func isAvailable() -> Bool {
        findCodexPath() != nil
    }

    static func isAuthenticated() -> Bool {
        let authPath = "\(NSHomeDirectory())/.codex/auth.json"
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

        if let path = ShellEnvironment.resolveBinaryViaShell("codex") {
            cachedCodexPath = path
            codexPathResolved = true
            return path
        }

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

    // MARK: - Send Message

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

        let arguments = ["exec", "-m", model, "--full-auto"]
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
            process.environment = ShellEnvironment.loadUserEnvironment()

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()

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
            return "Codex CLI 인증이 필요합니다. 터미널에서 codex login 실행"
        case .processError(_, let message):
            return "Codex CLI 오류: \(message.isEmpty ? "알 수 없는 오류" : message)"
        case .emptyResponse:
            return "Codex CLI에서 빈 응답"
        }
    }
}
