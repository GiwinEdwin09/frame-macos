import Foundation

public struct CommandResult: Sendable {
    public let output: String
    public let diagnostics: String
}

/// Owns one process. Both pipes are drained concurrently so FFmpeg logs cannot block it.
public final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    public init() {}
    public func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()
        if let running, running.isRunning { running.interrupt() }
    }

    public func run(executable: URL, arguments: [String], onLine: @escaping @Sendable (String) -> Void = { _ in }) async throws -> CommandResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    let task = Process()
                    let stdout = Pipe(), stderr = Pipe()
                    task.executableURL = executable
                    task.arguments = arguments
                    task.environment = ToolLocator.environment
                    task.standardOutput = stdout
                    task.standardError = stderr
                    task.standardInput = FileHandle.nullDevice
                    lock.lock()
                    if cancelled {
                        lock.unlock()
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    process = task
                    do { try task.run() } catch {
                        process = nil
                        lock.unlock()
                        continuation.resume(throwing: error)
                        return
                    }
                    lock.unlock()
                    let group = DispatchGroup()
                    let output = Capture(), errors = Capture()
                    for (pipe, capture) in [(stdout, output), (stderr, errors)] {
                        group.enter()
                        DispatchQueue.global(qos: .utility).async {
                            var pending = Data()
                            while true {
                                let data = pipe.fileHandleForReading.availableData
                                if data.isEmpty { break }
                                capture.data.append(data)
                                pending.append(data)
                                while let index = pending.firstIndex(of: 10) {
                                    onLine(String(decoding: pending[..<index], as: UTF8.self))
                                    pending.removeSubrange(...index)
                                }
                            }
                            if !pending.isEmpty { onLine(String(decoding: pending, as: UTF8.self)) }
                            group.leave()
                        }
                    }
                    task.waitUntilExit()
                    group.wait()
                    lock.lock()
                    let wasCancelled = cancelled
                    process = nil
                    lock.unlock()
                    let diagnostics = String(decoding: errors.data, as: UTF8.self)
                    if wasCancelled { continuation.resume(throwing: CancellationError()) }
                    else if task.terminationStatus != 0 {
                        continuation.resume(throwing: VideoError.message(String(diagnostics.suffix(4000)).isEmpty ? "The video tool exited with code \(task.terminationStatus)." : String(diagnostics.suffix(4000))))
                    } else {
                        continuation.resume(returning: CommandResult(output: String(decoding: output.data, as: UTF8.self), diagnostics: diagnostics))
                    }
                }
            }
        } onCancel: { self.cancel() }
    }
}

private final class Capture: @unchecked Sendable { var data = Data() }
