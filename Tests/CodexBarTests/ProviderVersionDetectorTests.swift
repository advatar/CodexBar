import Foundation
import Testing
@testable import CodexBarCore

@Suite
struct ProviderVersionDetectorTests {
    @Test
    func returnsVersionForFastCommand() throws {
        let env = try TestEnv()
        defer { env.cleanup() }

        let scriptURL = env.root.appendingPathComponent("version-fast.sh")
        try env.writeExecutableScript(
            """
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              echo "gemini-cli 1.2.3"
              exit 0
            fi
            exit 2
            """,
            to: scriptURL)

        let version = ProviderVersionDetector.run(
            path: scriptURL.path,
            args: ["--version"],
            timeout: 1.0,
            terminateTimeout: 0.2,
            killTimeout: 0.2)
        #expect(version == "gemini-cli 1.2.3")
    }

    @Test
    func returnsNilWhenStdoutClosesBeforeExit() throws {
        let env = try TestEnv()
        defer { env.cleanup() }

        let scriptURL = env.root.appendingPathComponent("version-stalls.sh")
        try env.writeExecutableScript(
            """
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              echo "gemini-cli 9.9.9"
              exec 1>&-
              sleep 30
            fi
            exit 2
            """,
            to: scriptURL)

        let startedAt = Date()
        let version = ProviderVersionDetector.run(
            path: scriptURL.path,
            args: ["--version"],
            timeout: 0.2,
            terminateTimeout: 0.2,
            killTimeout: 0.4)

        #expect(version == nil)
        #expect(Date().timeIntervalSince(startedAt) < 3.0)
    }
}

private struct TestEnv {
    let root: URL

    init() throws {
        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-provider-version-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func writeExecutableScript(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: self.root)
    }
}
