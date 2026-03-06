import Foundation

/// Claude CLI client using `claude -p` pipe mode.
/// Sends prompts via stdin, receives responses from stdout.
/// Requires Claude CLI to be installed on the system.
actor ClaudeCLIClient {

    static let fastModel = "haiku"
    static let preciseModel = "sonnet"

    // MARK: - Cached State

    /// Cached claude binary path (resolved once per app session)
    private static var cachedClaudePath: String?
    private static var claudePathResolved = false

    // MARK: - Process Pool

    private final class PooledProcess {
        let process: Process
        let stdinPipe: Pipe
        let stdoutPipe: Pipe
        let stderrPipe: Pipe
        let spawnTime: ContinuousClock.Instant

        init(process: Process, stdinPipe: Pipe, stdoutPipe: Pipe, stderrPipe: Pipe) {
            self.process = process
            self.stdinPipe = stdinPipe
            self.stdoutPipe = stdoutPipe
            self.stderrPipe = stderrPipe
            self.spawnTime = .now
        }

        var isAlive: Bool { process.isRunning }
        var isStale: Bool { ContinuousClock.now - spawnTime > .seconds(300) }
    }

    private var pool: [PooledProcess] = []
    private let poolSize = 2
    private let poolModel = ClaudeCLIClient.preciseModel

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
        if let path = ShellEnvironment.resolveBinaryViaShell("claude") {
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

    // Shell environment and binary resolution delegated to ShellEnvironment

    // MARK: - Pool Lifecycle

    func warmUp() {
        guard pool.isEmpty else { return }

        guard let claudePath = Self.findClaudePath() else {
            NSLog("[ClaudeCLI] Pool warmup skipped — claude not found")
            return
        }

        for _ in 0..<poolSize {
            if let p = spawnPooledProcess(claudePath: claudePath) {
                pool.append(p)
            }
        }
        NSLog("[ClaudeCLI] Pool warmed up: %d processes", pool.count)
    }

    func shutdown() {
        for p in pool {
            if p.isAlive {
                p.process.terminate()
            }
        }
        pool.removeAll()
        NSLog("[ClaudeCLI] Pool shut down")
    }

    private func checkoutWarmProcess(model: String, claudePath: String) -> PooledProcess? {
        // Pool only holds sonnet processes
        guard model == poolModel else { return nil }

        while let p = pool.first {
            pool.removeFirst()
            if p.isAlive && !p.isStale {
                // Replenish pool
                if let replacement = spawnPooledProcess(claudePath: claudePath) {
                    pool.append(replacement)
                }
                return p
            }
            // Dead or stale — discard
            if p.isAlive { p.process.terminate() }
        }
        return nil
    }

    private func spawnPooledProcess(claudePath: String) -> PooledProcess? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["-p", "--model", poolModel, "--output-format", "text"]
        process.environment = ShellEnvironment.loadUserEnvironment()

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            return PooledProcess(process: process, stdinPipe: stdinPipe, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
        } catch {
            NSLog("[ClaudeCLI] Failed to spawn pool process: %@", error.localizedDescription)
            return nil
        }
    }

    private func runWarmProcess(_ p: PooledProcess, input: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            // Timeout: terminate if still running after 120s
            DispatchQueue.global().asyncAfter(deadline: .now() + 120) {
                if p.process.isRunning { p.process.terminate() }
            }

            if let data = input.data(using: .utf8) {
                p.stdinPipe.fileHandleForWriting.write(data)
            }
            p.stdinPipe.fileHandleForWriting.closeFile()

            return try Self.collectProcessOutput(
                process: p.process,
                stdoutPipe: p.stdoutPipe,
                stderrPipe: p.stderrPipe
            )
        }.value
    }

    /// Collect output from a running process, validate exit status, return trimmed result.
    /// Called from within Task.detached context (synchronous/blocking I/O).
    private static func collectProcessOutput(
        process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe
    ) throws -> String {
        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

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

        // Try warm process from pool
        if let warm = checkoutWarmProcess(model: model, claudePath: claudePath) {
            let result = try await runWarmProcess(warm, input: userMessage)
            return (result, nil)
        }

        // Cold start fallback
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
            process.environment = ShellEnvironment.loadUserEnvironment()

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()

            if let data = input.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            inputPipe.fileHandleForWriting.closeFile()

            return try Self.collectProcessOutput(
                process: process,
                stdoutPipe: outputPipe,
                stderrPipe: errorPipe
            )
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
