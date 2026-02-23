import Foundation

public enum ProviderVersionDetector {
    public static func codexVersion() -> String? {
        guard let path = TTYCommandRunner.which("codex") else { return nil }
        let candidates = [
            ["--version"],
            ["version"],
            ["-v"],
        ]
        for args in candidates {
            if let version = Self.run(path: path, args: args) { return version }
        }
        return nil
    }

    public static func geminiVersion() -> String? {
        let env = ProcessInfo.processInfo.environment
        guard let path = BinaryLocator.resolveGeminiBinary(env: env, loginPATH: nil)
            ?? TTYCommandRunner.which("gemini") else { return nil }
        let candidates = [
            ["--version"],
            ["-v"],
        ]
        for args in candidates {
            if let version = Self.run(path: path, args: args) { return version }
        }
        return nil
    }

    static func run(
        path: String,
        args: [String],
        timeout: TimeInterval = 2.0,
        terminateTimeout: TimeInterval = 0.5,
        killTimeout: TimeInterval = 0.5) -> String?
    {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()

        do {
            try proc.run()
        } catch {
            return nil
        }

        if !Self.waitForExit(process: proc, timeout: timeout) {
            Self.stop(process: proc, terminateTimeout: terminateTimeout, killTimeout: killTimeout)
        }

        // Ensure process lifetime is fully complete before reading termination status.
        if proc.isRunning {
            Self.stop(process: proc, terminateTimeout: terminateTimeout, killTimeout: killTimeout)
        }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard !proc.isRunning,
              proc.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8)?
                  .split(whereSeparator: \.isNewline).first
        else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func waitForExit(process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while process.isRunning, Date() < deadline {
            usleep(50000)
        }
        return !process.isRunning
    }

    private static func stop(process: Process, terminateTimeout: TimeInterval, killTimeout: TimeInterval) {
        guard process.isRunning else { return }

        process.terminate()
        if self.waitForExit(process: process, timeout: terminateTimeout) {
            return
        }

        if process.processIdentifier > 0 {
            _ = kill(process.processIdentifier, SIGKILL)
        }
        if self.waitForExit(process: process, timeout: killTimeout) {
            return
        }

        // Last resort to avoid deallocation while still running.
        process.waitUntilExit()
    }
}
