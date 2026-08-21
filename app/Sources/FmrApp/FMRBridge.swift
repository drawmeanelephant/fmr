import Foundation

public final class FMRBridge: Sendable {
    public static let shared = FMRBridge()

    private let jsonDecoder: JSONDecoder

    public init() {
        self.jsonDecoder = JSONDecoder()
    }

    /// Mirrors src/main.zig:578 fallback: ~/config/fmr/workspace.json → ~/config/yard/workspace.json.
    /// Do not hardcode the config path elsewhere; use this helper.
    public func resolveConfigPath() -> String {
        let home = NSHomeDirectory()
        let fmrPath = "\(home)/config/fmr/workspace.json"
        let yardPath = "\(home)/config/yard/workspace.json"
        let fm = FileManager.default
        if fm.fileExists(atPath: fmrPath) { return fmrPath }
        if fm.fileExists(atPath: yardPath) { return yardPath }
        return fmrPath
    }

    /// Locates the `fmr` binary on the system.
    public func resolveBinaryPath() -> String {
        // 1. Check embedded bundle helper if running from an .app bundle
        if let bundleHelper = Bundle.main.path(forResource: "fmr", ofType: nil, inDirectory: "Helpers") {
            if FileManager.default.isExecutableFile(atPath: bundleHelper) {
                return bundleHelper
            }
        }

        // 2. Check build output directory relative to source/working dir
        let cwd = FileManager.default.currentDirectoryPath
        let candidates = [
            "\(cwd)/zig-out/bin/fmr",
            "\(cwd)/../zig-out/bin/fmr",
            "\(cwd)/../../zig-out/bin/fmr",
            "\(NSHomeDirectory())/.local/bin/fmr",
            "\(NSHomeDirectory())/bin/fmr",
            "/usr/local/bin/fmr",
            "/opt/homebrew/bin/fmr"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return "fmr"
    }

    /// Runs an `fmr` command and decodes JSON output into `T`.
    public func run<T: Decodable>(_ arguments: [String]) async throws -> T {
        var args = arguments
        if !args.contains("--json") {
            args.append("--json")
        }

        let output = try await execute(arguments: args)
        guard let data = output.stdout.data(using: .utf8) else {
            throw FMRError.invalidEncoding
        }

        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            throw FMRError.jsonDecodeFailed(error: error, rawOutput: output.stdout)
        }
    }

    /// Executes `fmr` with raw stdout/stderr capture and exit code.
    public func execute(
        arguments: [String],
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> ExecutionResult {
        let binary = resolveBinaryPath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments

        // Inherit current environment and ensure PATH has Homebrew and system paths
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(existingPath):\(extraPaths)"
        } else {
            env["PATH"] = extraPaths
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        final class OutputBuffer: @unchecked Sendable {
            var stdoutData = Data()
            var stderrData = Data()
            let lock = NSLock()

            func appendStdout(_ data: Data) {
                lock.lock()
                defer { lock.unlock() }
                stdoutData.append(data)
            }

            func appendStderr(_ data: Data) {
                lock.lock()
                defer { lock.unlock() }
                stderrData.append(data)
            }

            func results() -> (String, String) {
                lock.lock()
                defer { lock.unlock() }
                let out = String(data: stdoutData, encoding: .utf8) ?? ""
                let err = String(data: stderrData, encoding: .utf8) ?? ""
                return (out, err)
            }
        }

        let buffer = OutputBuffer()

        return try await withCheckedThrowingContinuation { continuation in
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    buffer.appendStdout(chunk)
                    if let text = String(data: chunk, encoding: .utf8), let onOutput = onOutput {
                        onOutput(text)
                    }
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    buffer.appendStderr(chunk)
                    if let text = String(data: chunk, encoding: .utf8), let onOutput = onOutput {
                        onOutput(text)
                    }
                }
            }

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let remainingOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                buffer.appendStdout(remainingOut)
                let remainingErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                buffer.appendStderr(remainingErr)

                let (stdoutStr, stderrStr) = buffer.results()

                continuation.resume(returning: ExecutionResult(
                    exitCode: proc.terminationStatus,
                    stdout: stdoutStr,
                    stderr: stderrStr
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: FMRError.processLaunchFailed(error: error, binary: binary))
            }
        }
    }
}

public struct ExecutionResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var isSuccess: Bool { exitCode == 0 }
}

public enum FMRError: LocalizedError, Sendable {
    case invalidEncoding
    case jsonDecodeFailed(error: Error, rawOutput: String)
    case processLaunchFailed(error: Error, binary: String)

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Output could not be parsed as UTF-8."
        case .jsonDecodeFailed(let error, let raw):
            return "JSON decode failed: \(error.localizedDescription)\nRaw output: \(raw)"
        case .processLaunchFailed(let error, let binary):
            return "Could not execute fmr at '\(binary)': \(error.localizedDescription)"
        }
    }
}
