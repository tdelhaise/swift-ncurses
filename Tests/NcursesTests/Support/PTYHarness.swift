import XCTest
import Ncurses
import CNcurses
import SnapshotSupport
import Foundation

#if canImport(Darwin)
import Darwin
typealias OSFileDescriptor = Int32
#else
import Glibc
typealias OSFileDescriptor = Int32
#endif

enum PTYError: Error {
    case openFailed
    case helperNotFound
    case spawnFailed(Int32)
    case waitFailed(status: Int32, output: String)
    case snapshotUnavailable
    case resizeFailed(errno: Int32)
    case writeFailed(errno: Int32)
}

final class PTYTerminal {
    private let defaultRows: Int32
    private let defaultCols: Int32
    private let defaultTERM: String

    init(rows: Int32 = 24, cols: Int32 = 80, term: String = "xterm-256color") {
        self.defaultRows = rows
        self.defaultCols = cols
        self.defaultTERM = term
    }

    typealias InteractionHandler = @Sendable (PTYInteractionContext) async throws -> Void

    func captureSnapshot(
        program: SnapshotProgram,
        rows: Int32? = nil,
        cols: Int32? = nil,
        interactions: InteractionHandler? = nil
    ) async throws -> TerminalSnapshot {
        var master: OSFileDescriptor = -1
        var slave: OSFileDescriptor = -1
        let rowsToUse = rows ?? defaultRows
        let colsToUse = cols ?? defaultCols

        guard swift_ncurses_openpty(&master, &slave, rowsToUse, colsToUse) == 0 else {
            throw PTYError.openFailed
        }
        defer {
            close(master)
        }
        defer {
            close(slave)
        }

        let currentFlags = fcntl(master, F_GETFL, 0)
        if currentFlags >= 0 {
            _ = fcntl(master, F_SETFL, currentFlags | O_NONBLOCK)
        }

        let encoder = JSONEncoder()
        let scriptData = try encoder.encode(program)
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try scriptData.write(to: scriptURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        guard let helperPath = locateHelperBinary(named: "NcursesSnapshotHelper") else {
            throw PTYError.helperNotFound
        }

        let helperURL = URL(fileURLWithPath: helperPath)
        let process = Process()
        process.executableURL = helperURL
        var environment = ProcessInfo.processInfo.environment
        environment["NCURSES_SNAPSHOT_SCRIPT"] = scriptURL.path
        environment["TERM"] = program.term ?? defaultTERM
        process.environment = environment

        let stdinFD = dup(slave)
        let stdoutFD = dup(slave)
        let stderrFD = dup(slave)
        process.standardInput = FileHandle(fileDescriptor: stdinFD, closeOnDealloc: true)
        process.standardOutput = FileHandle(fileDescriptor: stdoutFD, closeOnDealloc: true)
        process.standardError = FileHandle(fileDescriptor: stderrFD, closeOnDealloc: true)

        do {
            try process.run()
        } catch {
            throw PTYError.spawnFailed(errno)
        }

        let interactionContext = PTYInteractionContext(
            masterFD: master,
            slaveFD: slave,
            process: process
        )
        let interactionTask: Task<Void, Error>?
        if let interactions {
            interactionTask = Task {
                try await interactions(interactionContext)
            }
        } else {
            interactionTask = nil
        }

        var snapshotData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while process.isRunning {
            let bytesRead = read(master, &buffer, buffer.count)
            if bytesRead > 0 {
                snapshotData.append(buffer, count: bytesRead)
                continue
            }
            if bytesRead == 0 {
                break
            }
            if errno == EAGAIN || errno == EINTR {
                usleep(10_000)
                continue
            }
            break
        }

        process.waitUntilExit()

        if let interactionTask {
            do {
                try await interactionTask.value
            } catch {
                interactionTask.cancel()
                throw error
            }
        }

        while true {
            let bytesRead = read(master, &buffer, buffer.count)
            if bytesRead > 0 {
                snapshotData.append(buffer, count: bytesRead)
                continue
            }
            break
        }

        let status = process.terminationStatus
        if status != EXIT_SUCCESS {
            let outputString = String(decoding: snapshotData, as: UTF8.self)
            throw PTYError.waitFailed(status: status, output: outputString)
        }

        return TerminalSnapshot(data: snapshotData, rows: rowsToUse, cols: colsToUse)
    }

}

struct TerminalSnapshot {
    let data: Data
    let rows: Int32
    let cols: Int32

    var utf8String: String {
        String(decoding: data, as: UTF8.self)
    }

    var escapedString: String {
        var result = ""
        for scalar in utf8String.unicodeScalars {
            switch scalar.value {
            case 0x1B:
                result.append("\\u{1B}")
            case 0x0A:
                result.append("\\n")
            case 0x0D:
                result.append("\\r")
            default:
                if scalar.value < 0x20 {
                    result.append(String(format: "\\u{%02X}", scalar.value))
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
}

private func locateHelperBinary(named: String) -> String? {
    let fileManager = FileManager.default
    let basePaths = CommandLine.arguments.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }

    for base in basePaths {
        var current = base
        while current.pathComponents.count > 1 {
            let parent = current.deletingLastPathComponent()
            let helper = parent.appendingPathComponent(named)
            if fileManager.isExecutableFile(atPath: helper.path) {
                return helper.path
            }
            current = parent
        }
    }
    return nil
}

final class PTYInteractionContext {
    private let masterFD: OSFileDescriptor
    private let slaveFD: OSFileDescriptor
    private let process: Process
    private let lock = NSLock()

    init(masterFD: OSFileDescriptor, slaveFD: OSFileDescriptor, process: Process) {
        self.masterFD = masterFD
        self.slaveFD = slaveFD
        self.process = process
    }

    func resize(rows: Int32, cols: Int32) throws {
        lock.lock()
        defer { lock.unlock() }

        guard process.isRunning else { return }
        errno = 0
        let result = swift_ncurses_set_winsize(slaveFD, rows, cols)
        if result != 0 {
            throw PTYError.resizeFailed(errno: errno)
        }
        let pid = process.processIdentifier
        if pid > 0 {
            _ = kill(pid_t(pid), SIGWINCH)
        }
    }

    func send(_ string: String) throws {
        guard let data = string.data(using: .utf8) else { return }
        try send(data)
    }

    func send(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }

        guard process.isRunning else { return }
        if data.isEmpty { return }

        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let ptr = base.advanced(by: offset)
                let remaining = buffer.count - offset
                errno = 0
                let written = write(masterFD, ptr, remaining)
                if written < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw PTYError.writeFailed(errno: errno)
                }
                offset += written
            }
        }
    }

    func sendMouse(button: Int, x: Int, y: Int, released: Bool = false) throws {
        let suffix = released ? "m" : "M"
        let sequence = "\u{1B}[<\(button);\(x);\(y)\(suffix)"
        try send(sequence)
    }
}
