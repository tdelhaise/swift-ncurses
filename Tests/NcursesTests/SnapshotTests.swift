import XCTest
import SnapshotSupport
@testable import Ncurses

final class SnapshotTests: XCTestCase {
    func testHelloBoxSnapshot() async throws {
        let terminal = PTYTerminal(rows: 12, cols: 40)

        var builder = SnapshotProgramBuilder(term: "xterm-256color")
        builder.configureIO(raw: false, cbreak: true, echo: false, keypad: false)
        builder.withWindow(height: 8, width: 24, startY: 2, startX: 3) { window in
            window.drawBox()
            window.mvAdd("Hello TUI", y: 1, x: 2)
            window.mvAddWithEllipsis("Snapshot testing harness", maxColumns: 18, y: 3, x: 2)
            window.refresh()
        }
        builder.flush()
        let program = builder.build()

        let snapshot = try await terminal.captureSnapshot(program: program)
        let expected = "\u{1B}[?1049h\u{1B}[22;0;0t\u{1B}[1;12r\u{1B}(B\u{1B}[m\u{1B}[4l\u{1B}[?7h\u{1B}[?1l\u{1B}>\u{1B}[H\u{1B}[2J\u{1B}[3;4H\u{1B}(0\u{1B}[0mlq\u{1B}[21bk\u{1B}(B\u{1B}[4;4H\u{1B}(0\u{1B}[0mx\u{1B}(B Hello TUI\u{1B}[4;27H\u{1B}(0\u{1B}[0mx\u{1B}(B\u{1B}[5;4H\u{1B}(0\u{1B}[0mx\u{1B}(B\u{1B}[5;27H\u{1B}(0\u{1B}[0mx\u{1B}(B\u{1B}[6;4H\u{1B}(0\u{1B}[0mx\u{1B}(B Snapshot testin...   \u{1B}(0\u{1B}[0mx\u{1B}(B\u{1B}[7;4H\u{1B}(0\u{1B}[0mx\u{1B}(B\u{1B}[7;27H\u{1B}(0\u{1B}[0mx\u{1B}(B\u{1B}[8;4H\u{1B}(0\u{1B}[0mx\u{1B}(B\u{1B}[8;27H\u{1B}(0\u{1B}[0mx\u{1B}(B\u{1B}[9;4H\u{1B}(0\u{1B}[0mx\u{1B}(B\u{1B}[9;27H\u{1B}(0\u{1B}[0mx\u{1B}(B\u{1B}[10;4H\u{1B}(0\u{1B}[0mmq\u{1B}[21bj\u{1B}(B\u{1B}[6;24H\u{1B}(0\u{1B}[0m\u{1B}(B\u{1B}[12;1H\u{1B}[?1049l\u{1B}[23;0;0t\r\u{1B}[?1l\u{1B}>"
        XCTAssertEqual(snapshot.utf8String, expected)
    }

    func testResizeSnapshotReportsUpdatedWindowSize() async throws {
        let terminal = PTYTerminal(rows: 12, cols: 40)

        var builder = SnapshotProgramBuilder(term: "xterm-256color")
        builder.configureIO(raw: false, cbreak: true, echo: false, keypad: false)
        builder.withWindow(height: 0, width: 0, startY: 0, startX: 0) { window in
            window.reportTerminalSize(prefix: "Initial", y: 0, x: 0)
            window.refresh()
            window.flush()
            window.wait(milliseconds: 100)
            window.reportTerminalSize(prefix: "After", y: 1, x: 0)
            window.refresh()
            window.flush()
        }
        builder.flush()

        let program = builder.build()

        let snapshot = try await terminal.captureSnapshot(program: program) { context in
            try await Task.sleep(nanoseconds: 50_000_000)
            try context.resize(rows: 6, cols: 20)
        }

        let screen = TerminalScreen(snapshot: snapshot)
        let reports = screen.trimmedLines.filter { !$0.isEmpty }

        XCTAssertTrue(
            reports.contains(where: { $0.contains("Initial: 12x40") }),
            "Initial size report not found in snapshot."
        )
        XCTAssertTrue(
            reports.contains(where: { $0.contains("After: 6x20") }),
            "Resized size report not found in snapshot."
        )
    }

    func testColorAttributeSnapshotEmitsSGR() async throws {
        let terminal = PTYTerminal(rows: 10, cols: 30)

        var builder = SnapshotProgramBuilder(term: "xterm-256color")
        builder.configureIO(raw: true, cbreak: true, echo: false, keypad: false)
        builder.startColor()
        builder.allocateColorPair(named: "highlight", foreground: .yellow, background: .blue)
        builder.withWindow(height: 6, width: 28, startY: 1, startX: 1) { window in
            window.setAttributes(.bold, colorPair: "highlight")
            window.mvAdd("Colorful text", y: 2, x: 2)
            window.refresh()
            window.flush()
        }
        builder.flush()

        let program = builder.build()
        let snapshot = try await terminal.captureSnapshot(program: program)

        let screen = TerminalScreen(snapshot: snapshot)
        XCTAssertTrue(
            screen.trimmedLines.contains(where: { $0.contains("Colorful text") }),
            "Rendered text not found in snapshot buffer."
        )

        let sgrSequence = snapshot.escapedString
        XCTAssertTrue(
            sgrSequence.contains("[1;") || sgrSequence.contains("[0;1"),
            "Expected bold attribute sequence in output, got: \(sgrSequence)"
        )
        XCTAssertTrue(
            sgrSequence.contains("[38;") || sgrSequence.contains("[33m"),
            "Expected foreground color sequence in output, got: \(sgrSequence)"
        )
        XCTAssertTrue(
            sgrSequence.contains("[48;") || sgrSequence.contains("[44m"),
            "Expected background color sequence in output, got: \(sgrSequence)"
        )
    }

    func testKeyEventsSnapshotRecordsArrowAndCharacter() async throws {
        let terminal = PTYTerminal(rows: 8, cols: 30)

        var builder = SnapshotProgramBuilder(term: "xterm-256color")
        builder.configureIO(raw: false, cbreak: true, echo: false, keypad: true)
        builder.withWindow(height: 6, width: 28, startY: 1, startX: 1) { window in
            window.configureKeypad(true)
            window.setTimeout(milliseconds: 500)
            window.recordKey(prefix: "First", y: 1, x: 2)
            window.refresh()
            window.recordKey(prefix: "Second", y: 2, x: 2)
            window.refresh()
            window.flush()
        }
        builder.flush()

        let program = builder.build()
        let snapshot = try await terminal.captureSnapshot(program: program) { context in
            try await Task.sleep(nanoseconds: 50_000_000)
            try context.send("\u{1B}[Ax")
        }

        let screen = TerminalScreen(snapshot: snapshot)
        let lines = screen.trimmedLines.filter { !$0.isEmpty }

        XCTAssertTrue(
            lines.contains(where: { $0.contains("First: up") }),
            "Expected arrow key capture; got lines: \(lines)"
        )
        XCTAssertTrue(
            lines.contains(where: { $0.contains("Second: char(x)") }),
            "Expected character capture; got lines: \(lines)"
        )
    }

    func testMouseSnapshotRecordsPressEvent() async throws {
        let terminal = PTYTerminal(rows: 10, cols: 40)

        var builder = SnapshotProgramBuilder(term: "xterm-256color")
        builder.configureIO(raw: false, cbreak: true, echo: false, keypad: true)
        builder.enableMouse([.button1Pressed])
        builder.withWindow(height: 6, width: 30, startY: 1, startX: 1) { window in
            window.configureKeypad(true)
            window.setTimeout(milliseconds: 1000)
            window.recordMouse(prefix: "Mouse", y: 2, x: 2, fallback: "none")
            window.refresh()
            window.flush()
        }
        builder.flush()

        let program = builder.build()

        let snapshot = try await terminal.captureSnapshot(program: program) { context in
            try await Task.sleep(nanoseconds: 50_000_000)
            try context.sendMouse(button: 0, x: 5, y: 3)
        }

        let screen = TerminalScreen(snapshot: snapshot)
        let lines = screen.trimmedLines.filter { !$0.isEmpty }

        XCTAssertTrue(
            lines.contains(where: { $0.contains("Mouse: pressed") }),
            "Expected mouse press capture; got lines: \(lines)"
        )
    }
}
