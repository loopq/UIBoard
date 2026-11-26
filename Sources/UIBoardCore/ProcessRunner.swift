import Foundation

enum ProcessRunner {
    static func run(
        executable: URL,
        args: [String],
        timeout: TimeInterval
    ) async throws -> (stdout: Data, stderr: Data, status: Int32) {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = executable
        process.arguments = args
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // Not waitUntilExit(): it sleeps on the calling thread's run loop for an exit notice that, off the main
        // thread, sometimes never arrives — the test suite hung for 10+ minutes on a child that had long exited.
        // The handler is set before run() so even an instant exit is caught; the stream buffers it until awaited.
        let (exits, exited) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { exited.yield($0.terminationStatus); exited.finish() }

        try process.run()

        // Ceiling: each pipe is drained by a blocking read on a cooperative thread, so `facts` (3 commands at
        // once) parks 6 of them. Upgrade path: read with `readabilityHandler` instead.
        let stdoutTask = Task.detached { try stdoutPipe.fileHandleForReading.readToEnd() ?? Data() }
        let stderrTask = Task.detached { try stderrPipe.fileHandleForReading.readToEnd() ?? Data() }
        let waitTask = Task {
            for await status in exits { return status }
            return Int32(-1)   // unreachable: the handler always yields before it finishes the stream
        }

        let command = ([executable.path] + args).joined(separator: " ")
        do {
            let status = try await withThrowingTaskGroup(of: Int32.self) { group in
                group.addTask { await waitTask.value }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    if process.isRunning { process.terminate() }
                    throw UIBoardError.timeout(command)
                }
                guard let first = try await group.next() else {
                    throw UIBoardError.processFailed(status: -1, stderr: "Process produced no result.")
                }
                group.cancelAll()
                return first
            }
            return (try await stdoutTask.value, try await stderrTask.value, status)
        } catch {
            if process.isRunning { process.terminate() }
            _ = await waitTask.value
            _ = try? await stdoutTask.value
            _ = try? await stderrTask.value
            throw error
        }
    }
}
