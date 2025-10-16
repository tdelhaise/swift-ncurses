import Foundation

struct TerminalScreen {
    let rows: Int
    let cols: Int

    private var cells: [[Character]]
    private var cursorRow: Int = 0
    private var cursorCol: Int = 0
    private var lastPrinted: Character?
    private var currentCharset: CharacterSet = .ascii

    init(snapshot: TerminalSnapshot) {
        self.rows = max(0, Int(snapshot.rows))
        self.cols = max(0, Int(snapshot.cols))
        self.cells = Array(
            repeating: Array(repeating: " ", count: max(0, Int(snapshot.cols))),
            count: max(0, Int(snapshot.rows))
        )
        parse(snapshot.utf8String.unicodeScalars)
    }

    func line(_ index: Int) -> String {
        guard index >= 0 && index < rows else { return "" }
        return String(cells[index])
    }

    func trimmedLine(_ index: Int) -> String {
        trimTrailingSpaces(line(index))
    }

    var lines: [String] {
        cells.map { String($0) }
    }

    var trimmedLines: [String] {
        lines.map(trimTrailingSpaces)
    }
}

// MARK: - Parsing

private extension TerminalScreen {
    enum CharacterSet {
        case ascii
        case lineDrawing
    }

    mutating func parse(_ scalars: String.UnicodeScalarView) {
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            index = scalars.index(after: index)
            switch scalar.value {
            case 0x1B: // ESC
                index = handleEscape(in: scalars, startingAt: index)
            case 0x0A: // LF
                newline()
            case 0x0D: // CR
                carriageReturn()
            default:
                if scalar.value < 0x20 {
                    continue
                }
                writeMappedCharacter(for: scalar)
            }
        }
    }

    mutating func handleEscape(in scalars: String.UnicodeScalarView, startingAt index: String.UnicodeScalarIndex) -> String.UnicodeScalarIndex {
        guard index < scalars.endIndex else { return index }
        let code = scalars[index]
        var nextIndex = scalars.index(after: index)
        switch code {
        case "[":
            return handleControlSequence(in: scalars, startingAt: nextIndex)
        case "(":
            if index < scalars.endIndex {
                let selector = scalars[index]
                currentCharset = selector == "0" ? .lineDrawing : .ascii
                nextIndex = scalars.index(after: index)
            }
            return nextIndex
        case ")":
            currentCharset = .ascii
            return nextIndex
        default:
            return nextIndex
        }
    }

    mutating func handleControlSequence(in scalars: String.UnicodeScalarView, startingAt index: String.UnicodeScalarIndex) -> String.UnicodeScalarIndex {
        var idx = index
        var privateIndicator: UnicodeScalar?
        var parameters: [Int] = []
        var currentValue: Int = 0
        var parsingNumber = false

        if idx < scalars.endIndex {
            let indicator = scalars[idx]
            if indicator == "?" || indicator == ">" {
                privateIndicator = indicator
                idx = scalars.index(after: idx)
            }
        }

        while idx < scalars.endIndex {
            let scalar = scalars[idx]
            if scalar.isDigit {
                parsingNumber = true
                currentValue = (currentValue * 10) + Int(scalar.value - 48)
                idx = scalars.index(after: idx)
                continue
            }
            if scalar == ";" {
                parameters.append(parsingNumber ? currentValue : 0)
                parsingNumber = false
                currentValue = 0
                idx = scalars.index(after: idx)
                continue
            }

            if parsingNumber || !parameters.isEmpty {
                parameters.append(parsingNumber ? currentValue : 0)
            }
            parsingNumber = false

            executeControlSequence(final: scalar, parameters: parameters, privateIndicator: privateIndicator)
            return scalars.index(after: idx)
        }

        return idx
    }

    mutating func executeControlSequence(
        final: UnicodeScalar,
        parameters: [Int],
        privateIndicator: UnicodeScalar?
    ) {
        switch final {
        case "H", "f":
            let row = parameters.count >= 1 ? max(parameters[0] - 1, 0) : 0
            let col = parameters.count >= 2 ? max(parameters[1] - 1, 0) : 0
            moveCursor(row: row, col: col)
        case "J":
            let mode = parameters.first ?? 0
            if mode == 2 {
                clearScreen()
            } else if mode == 0 {
                clearFromCursorToEnd()
            }
        case "K":
            clearLineFromCursor()
        case "b":
            let count = parameters.first ?? 1
            repeatLastPrinted(times: max(count, 0))
        case "d":
            guard rows > 0 else { return }
            let requestedRow = parameters.first ?? 1
            let zeroBased = max(requestedRow - 1, 0)
            cursorRow = min(zeroBased, max(rows - 1, 0))
        case "m", "r", "t", "h", "l", "n", "s", "u":
            // Attribute / mode commands ignored for snapshot rendering
            break
        default:
            // Ignore unhandled sequences (scroll region, term settings, etc.)
            _ = privateIndicator // silence unused warning
        }
    }

    mutating func writeMappedCharacter(for scalar: UnicodeScalar) {
        guard rows > 0, cols > 0 else { return }
        let mapped = mapCharacter(scalar)
        if cursorRow >= 0 && cursorRow < rows && cursorCol >= 0 && cursorCol < cols {
            cells[cursorRow][cursorCol] = mapped
        }
        cursorCol += 1
        if cursorCol >= cols {
            cursorCol = cols
        }
        lastPrinted = mapped
    }

    mutating func repeatLastPrinted(times: Int) {
        guard times > 0, let lastPrinted else { return }
        for _ in 0..<times {
            writeCharacter(lastPrinted)
        }
    }

    mutating func writeCharacter(_ character: Character) {
        guard rows > 0, cols > 0 else { return }
        if cursorRow >= 0 && cursorRow < rows && cursorCol >= 0 && cursorCol < cols {
            cells[cursorRow][cursorCol] = character
        }
        cursorCol += 1
        if cursorCol >= cols {
            cursorCol = cols
        }
        lastPrinted = character
    }

    mutating func moveCursor(row: Int, col: Int) {
        guard rows > 0, cols > 0 else {
            cursorRow = 0
            cursorCol = 0
            return
        }
        let maxRow = max(rows - 1, 0)
        let maxCol = max(cols - 1, 0)
        cursorRow = min(max(row, 0), maxRow)
        cursorCol = min(max(col, 0), maxCol)
    }

    mutating func newline() {
        guard rows > 0 else { return }
        cursorRow = min(cursorRow + 1, max(rows - 1, 0))
    }

    mutating func carriageReturn() {
        cursorCol = 0
    }

    mutating func clearScreen() {
        for row in 0..<rows {
            for col in 0..<cols {
                cells[row][col] = " "
            }
        }
        cursorRow = 0
        cursorCol = 0
    }

    mutating func clearFromCursorToEnd() {
        guard rows > 0, cols > 0 else { return }
        clearLineFromCursor()
        var row = cursorRow + 1
        while row < rows {
            for col in 0..<cols {
                cells[row][col] = " "
            }
            row += 1
        }
    }

    mutating func clearLineFromCursor() {
        guard rows > 0, cols > 0 else { return }
        guard cursorRow >= 0 && cursorRow < rows else { return }
        var col = cursorCol
        if col < 0 { col = 0 }
        if col >= cols { return }
        while col < cols {
            cells[cursorRow][col] = " "
            col += 1
        }
    }

    func mapCharacter(_ scalar: UnicodeScalar) -> Character {
        switch currentCharset {
        case .ascii:
            return Character(scalar)
        case .lineDrawing:
            switch scalar {
            case "l", "k", "m", "j", "t", "u", "v", "w", "n":
                return "+"
            case "q":
                return "-"
            case "x":
                return "|"
            default:
                return Character(scalar)
            }
        }
    }
}

private extension UnicodeScalar {
    var isDigit: Bool {
        return value >= 48 && value <= 57
    }
}

private func trimTrailingSpaces(_ string: String) -> String {
    guard !string.isEmpty else { return string }
    var scalars = string.unicodeScalars
    while let last = scalars.last, last == " " {
        scalars.removeLast()
    }
    return String(scalars)
}
