#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation
import Ncurses
import CNcurses
import SnapshotSupport

@main
struct SnapshotHelper {
    private struct ExecutionState {
        var colorPairs: [String: Curses.ColorPair] = [:]
    }

    static func main() async {
        do {
            try await run()
            exit(EXIT_SUCCESS)
        } catch {
            fputs("Snapshot helper failed: \(error)\n", stderr)
            fflush(stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let scriptPath = environment["NCURSES_SNAPSHOT_SCRIPT"] else {
            throw HelperError.missingScriptPath
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: scriptPath))
        let decoder = JSONDecoder()
        let program = try decoder.decode(SnapshotProgram.self, from: data)

        if let term = program.term {
            setenv("TERM", term, 1)
        }

        try await execute(program: program)
    }

    private static func execute(program: SnapshotProgram) async throws {
        if let term = program.term {
            var termCString = term.utf8CString
            guard let pointer = termCString.withUnsafeMutableBufferPointer({ buffer -> UnsafePointer<CChar>? in
                buffer.baseAddress.map { UnsafePointer<CChar>($0) }
            }) else {
                throw HelperError.invalidTerm
            }
            let commands = program.commands
            try await Curses.withScreen(term: pointer) { screen in
                try executeCommands(commands, on: screen)
            }
        } else {
            let commands = program.commands
            try await Curses.withScreen { screen in
                try executeCommands(commands, on: screen)
            }
        }
    }

    @CursesActor
    private static func executeCommands(_ commands: [SnapshotCommand], on screen: OpaquePointer) throws {
        Curses.ensureLocaleOnce()
        var state = ExecutionState()
        for command in commands {
            switch command {
            case let .configureIO(raw, cbreak, echo, keypad):
                try Curses.configureIO(on: screen, raw: raw, cbreak: cbreak, echo: echo, keypad: keypad)
            case let .withWindow(descriptor):
                try Curses.withWindow(height: descriptor.height, width: descriptor.width, startY: descriptor.startY, startX: descriptor.startX, on: screen) { window in
                    try executeWindowCommands(descriptor.commands, in: window, state: &state)
                }
            case .startColor:
                try Curses.startColorIfNeeded(on: screen)
            case let .allocateColorPair(descriptor):
                let pair = try Curses.allocateColorPair(fg: descriptor.foreground.cursesColor, bg: descriptor.background.cursesColor)
                state.colorPairs[descriptor.name] = pair
            case let .enableMouse(mask):
                try Curses.enableMouse(mask: mask.cursesMask)
            case .disableMouse:
                try Curses.disableMouse()
            case let .wait(milliseconds):
                sleepMilliseconds(milliseconds)
            case .flush:
                Curses.flush()
            }
        }
    }

    @CursesActor
    private static func executeWindowCommands(_ commands: [WindowCommand], in window: OpaquePointer, state: inout ExecutionState) throws {
        for command in commands {
            switch command {
            case .drawBox:
                Curses.drawBox(in: window)
            case let .mvAdd(string, y, x):
                try Curses.mvadd(string, y: y, x: x, in: window)
            case let .mvAddWithEllipsis(string, maxColumns, y, x, ellipsis):
                try Curses.mvaddWithEllipsis(string, maxColumns: maxColumns, y: y, x: x, ellipsis: ellipsis, in: window)
            case let .reportSize(prefix, y, x):
                _ = CNcurses.wmove(window, y, x)
                _ = CNcurses.wclrtoeol(window)
                let size = Curses.getSize(of: window)
                let text = "\(prefix): \(size.rows)x\(size.cols)"
                try Curses.mvadd(text, y: y, x: x, in: window)
            case let .reportTerminalSize(prefix, y, x):
                _ = CNcurses.wmove(window, y, x)
                _ = CNcurses.wclrtoeol(window)
                if let size = Curses.currentTerminalSize() {
                    let text = "\(prefix): \(size.rows)x\(size.cols)"
                    try Curses.mvadd(text, y: y, x: x, in: window)
                } else {
                    try Curses.mvadd("\(prefix): unavailable", y: y, x: x, in: window)
                }
            case let .setTimeout(milliseconds):
                Curses.setTimeout(on: window, milliseconds: milliseconds)
            case let .setNonBlocking(enabled):
                Curses.setNonBlocking(on: window, enabled: enabled)
            case let .configureKeypad(enabled):
                _ = CNcurses.keypad(window, enabled ? true : false)
            case let .recordKey(prefix, y, x, fallback):
                let description = resolveKey(in: window, fallback: fallback)
                _ = CNcurses.wmove(window, y, x)
                _ = CNcurses.wclrtoeol(window)
                try Curses.mvadd("\(prefix): \(description)", y: y, x: x, in: window)
            case let .recordMouse(prefix, y, x, fallback):
                let description = resolveMouseEvent(on: window, fallback: fallback)
                _ = CNcurses.wmove(window, y, x)
                _ = CNcurses.wclrtoeol(window)
                try Curses.mvadd("\(prefix): \(description)", y: y, x: x, in: window)
            case let .setAttributes(attributes, colorPair):
                var combined: Curses.AttributeSet = []
                for attribute in attributes {
                    combined.insert(attribute.attributeValue)
                }
                let pair = colorPair.flatMap { state.colorPairs[$0] }
                Curses.setAttributes(on: window, attrs: combined, color: pair)
            case .refresh:
                Curses.refresh(window)
            case .flush:
                Curses.flush()
            case let .wait(milliseconds):
                sleepMilliseconds(milliseconds)
            }
        }
    }

    private static func sleepMilliseconds(_ value: UInt32) {
        let microseconds = useconds_t(value) * 1000
        usleep(microseconds)
    }

    private enum HelperError: Error {
        case missingScriptPath
        case invalidTerm
    }
}

private func describeKey(_ key: Curses.Key?) -> String? {
    guard let key else { return nil }
    switch key {
    case let .char(value):
        if let scalar = UnicodeScalar(value), scalar.value >= 0x20 && scalar.value != 0x7F {
            return "char(\(Character(scalar)))"
        } else {
            return String(format: "char(0x%02X)", Int(value))
        }
    case .enter:
        return "enter"
    case .backspace:
        return "backspace"
    case .up:
        return "up"
    case .down:
        return "down"
    case .left:
        return "left"
    case .right:
        return "right"
    case .home:
        return "home"
    case .end:
        return "end"
    case .pageUp:
        return "pageUp"
    case .pageDown:
        return "pageDown"
    case let .f(index):
        return "f\(index)"
    case .resize:
        return "resize"
    case .mouse:
        return "mouse"
    case let .unknown(code):
        return "unknown(\(code))"
    }
}

@CursesActor
private func resolveKey(in window: OpaquePointer, fallback: String) -> String {
    guard let key = Curses.getKey(from: window) else { return fallback }
    if case let .char(value) = key, value == 0x1B {
        return decodeEscapeSequence(in: window, fallback: fallback)
    }
    return describeKey(key) ?? fallback
}

@CursesActor
private func decodeEscapeSequence(in window: OpaquePointer, fallback: String) -> String {
    guard let next = Curses.getKey(from: window) else {
        return "esc"
    }
    switch next {
    case let .char(bracket) where bracket == 0x5B: // '['
        guard let final = Curses.getKey(from: window) else {
            return "esc["
        }
        if case let .char(code) = final {
            switch code {
            case 0x41: return "up"
            case 0x42: return "down"
            case 0x43: return "right"
            case 0x44: return "left"
            case 0x48: return "home"
            case 0x46: return "end"
            default:
                return "esc[+\(renderChar(code))"
            }
        } else {
            let description = describeKey(final) ?? fallback
            return "esc[+\(description)"
        }
    case let .char(other):
        return "esc+\(renderChar(other))"
    default:
        let description = describeKey(next) ?? fallback
        return "esc+\(description)"
    }
}

private func renderChar(_ value: UInt32) -> String {
    if let scalar = UnicodeScalar(value), scalar.value >= 0x20 && scalar.value != 0x7F {
        return String(Character(scalar))
    }
    return String(format: "0x%02X", Int(value))
}

@CursesActor
private func resolveMouseEvent(on window: OpaquePointer, fallback: String) -> String {
    guard let key = Curses.getKey(from: window) else {
        return fallback
    }
    switch key {
    case .mouse:
        if let event = Curses.getMouse() {
            return describeMouseEvent(event)
        }
        return "mouse: none"
    case let .char(value) where value == 0x1B:
        return decodeEscapeSequence(in: window, fallback: fallback)
    default:
        return describeKey(key) ?? fallback
    }
}

@CursesActor
private func describeMouseEvent(_ event: Curses.MouseEvent) -> String {
    switch event {
    case let .pressed(btn, y, x):
        return "pressed(btn:\(btn),y:\(y),x:\(x))"
    case let .released(btn, y, x):
        return "released(btn:\(btn),y:\(y),x:\(x))"
    case let .moved(y, x):
        return "moved(y:\(y),x:\(x))"
    }
}

private extension SnapshotColor {
    var cursesColor: Curses.Color {
        switch self {
        case .black: return .black
        case .red: return .red
        case .green: return .green
        case .yellow: return .yellow
        case .blue: return .blue
        case .magenta: return .magenta
        case .cyan: return .cyan
        case .white: return .white
        }
    }
}

private extension SnapshotAttribute {
    var attributeValue: Curses.AttributeSet {
        switch self {
        case .bold: return .bold
        case .dim: return .dim
        case .underline: return .underline
        case .reverse: return .reverse
        case .blink: return .blink
        case .standout: return .standout
        case .italic: return .italic
        case .invisible: return .invisible
        }
    }
}

private extension SnapshotMouseMask {
    var cursesMask: Curses.MouseMask {
        var mask: Curses.MouseMask = []
        if contains(.button1Pressed) { mask.insert(.button1Pressed) }
        if contains(.button1Released) { mask.insert(.button1Released) }
        if contains(.button2Pressed) { mask.insert(.button2Pressed) }
        if contains(.button2Released) { mask.insert(.button2Released) }
        if contains(.button3Pressed) { mask.insert(.button3Pressed) }
        if contains(.button3Released) { mask.insert(.button3Released) }
        if contains(.button4Pressed) { mask.insert(.button4Pressed) }
        if contains(.button4Released) { mask.insert(.button4Released) }
        if contains(.moved) { mask.insert(.reportPosition) }
        return mask
    }
}
