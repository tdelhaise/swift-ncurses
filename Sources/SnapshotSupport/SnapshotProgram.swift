import Foundation

public struct SnapshotProgram: Codable, Sendable {
    public var term: String?
    public var commands: [SnapshotCommand]

    public init(term: String? = nil, commands: [SnapshotCommand] = []) {
        self.term = term
        self.commands = commands
    }
}

public enum SnapshotColor: String, Codable, Sendable {
    case black
    case red
    case green
    case yellow
    case blue
    case magenta
    case cyan
    case white
}

public enum SnapshotAttribute: String, Codable, Sendable {
    case bold
    case dim
    case underline
    case reverse
    case blink
    case standout
    case italic
    case invisible
}

public struct SnapshotMouseMask: OptionSet, Codable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let button1Pressed = SnapshotMouseMask(rawValue: 1 << 0)
    public static let button1Released = SnapshotMouseMask(rawValue: 1 << 1)
    public static let button2Pressed = SnapshotMouseMask(rawValue: 1 << 2)
    public static let button2Released = SnapshotMouseMask(rawValue: 1 << 3)
    public static let button3Pressed = SnapshotMouseMask(rawValue: 1 << 4)
    public static let button3Released = SnapshotMouseMask(rawValue: 1 << 5)
    public static let button4Pressed = SnapshotMouseMask(rawValue: 1 << 6)
    public static let button4Released = SnapshotMouseMask(rawValue: 1 << 7)
    public static let moved = SnapshotMouseMask(rawValue: 1 << 8)

    public static let all: SnapshotMouseMask = [
        .button1Pressed, .button1Released,
        .button2Pressed, .button2Released,
        .button3Pressed, .button3Released,
        .button4Pressed, .button4Released,
        .moved
    ]
}

public enum SnapshotCommand: Codable, Sendable {
    case configureIO(raw: Bool, cbreak: Bool, echo: Bool, keypad: Bool)
    case withWindow(WindowDescriptor)
    case startColor
    case allocateColorPair(ColorPairDescriptor)
    case enableMouse(SnapshotMouseMask)
    case disableMouse
    case wait(milliseconds: UInt32)
    case flush

    private enum CodingKeys: String, CodingKey {
        case type
        case parameters
    }

    private enum CommandType: String, Codable {
        case configureIO
        case withWindow
        case startColor
        case allocateColorPair
        case enableMouse
        case disableMouse
        case wait
        case flush
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .configureIO(raw, cbreak, echo, keypad):
            try container.encode(CommandType.configureIO, forKey: .type)
            var params = container.nestedContainer(keyedBy: ConfigureKeys.self, forKey: .parameters)
            try params.encode(raw, forKey: .raw)
            try params.encode(cbreak, forKey: .cbreak)
            try params.encode(echo, forKey: .echo)
            try params.encode(keypad, forKey: .keypad)
        case let .withWindow(descriptor):
            try container.encode(CommandType.withWindow, forKey: .type)
            try container.encode(descriptor, forKey: .parameters)
        case .startColor:
            try container.encode(CommandType.startColor, forKey: .type)
        case let .allocateColorPair(descriptor):
            try container.encode(CommandType.allocateColorPair, forKey: .type)
            try container.encode(descriptor, forKey: .parameters)
        case let .enableMouse(mask):
            try container.encode(CommandType.enableMouse, forKey: .type)
            try container.encode(mask, forKey: .parameters)
        case .disableMouse:
            try container.encode(CommandType.disableMouse, forKey: .type)
        case let .wait(milliseconds):
            try container.encode(CommandType.wait, forKey: .type)
            var params = container.nestedContainer(keyedBy: WaitKeys.self, forKey: .parameters)
            try params.encode(milliseconds, forKey: .milliseconds)
        case .flush:
            try container.encode(CommandType.flush, forKey: .type)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(CommandType.self, forKey: .type)
        switch type {
        case .configureIO:
            let params = try container.nestedContainer(keyedBy: ConfigureKeys.self, forKey: .parameters)
            let raw = try params.decode(Bool.self, forKey: .raw)
            let cbreak = try params.decode(Bool.self, forKey: .cbreak)
            let echo = try params.decode(Bool.self, forKey: .echo)
            let keypad = try params.decode(Bool.self, forKey: .keypad)
            self = .configureIO(raw: raw, cbreak: cbreak, echo: echo, keypad: keypad)
        case .withWindow:
            let descriptor = try container.decode(WindowDescriptor.self, forKey: .parameters)
            self = .withWindow(descriptor)
        case .startColor:
            self = .startColor
        case .allocateColorPair:
            let descriptor = try container.decode(ColorPairDescriptor.self, forKey: .parameters)
            self = .allocateColorPair(descriptor)
        case .enableMouse:
            let mask = try container.decode(SnapshotMouseMask.self, forKey: .parameters)
            self = .enableMouse(mask)
        case .disableMouse:
            self = .disableMouse
        case .wait:
            let params = try container.nestedContainer(keyedBy: WaitKeys.self, forKey: .parameters)
            let milliseconds = try params.decode(UInt32.self, forKey: .milliseconds)
            self = .wait(milliseconds: milliseconds)
        case .flush:
            self = .flush
        }
    }

    private enum ConfigureKeys: String, CodingKey {
        case raw
        case cbreak
        case echo
        case keypad
    }

    private enum WaitKeys: String, CodingKey {
        case milliseconds
    }
}

public struct ColorPairDescriptor: Codable, Sendable {
    public let name: String
    public let foreground: SnapshotColor
    public let background: SnapshotColor

    public init(name: String, foreground: SnapshotColor, background: SnapshotColor) {
        self.name = name
        self.foreground = foreground
        self.background = background
    }
}

public struct WindowDescriptor: Codable, Sendable {
    public let height: Int32
    public let width: Int32
    public let startY: Int32
    public let startX: Int32
    public let commands: [WindowCommand]

    public init(height: Int32, width: Int32, startY: Int32, startX: Int32, commands: [WindowCommand]) {
        self.height = height
        self.width = width
        self.startY = startY
        self.startX = startX
        self.commands = commands
    }
}

public enum WindowCommand: Codable, Sendable {
    case drawBox
    case mvAdd(string: String, y: Int32, x: Int32)
    case mvAddWithEllipsis(string: String, maxColumns: Int32, y: Int32, x: Int32, ellipsis: String)
    case reportSize(prefix: String, y: Int32, x: Int32)
    case reportTerminalSize(prefix: String, y: Int32, x: Int32)
    case setTimeout(milliseconds: Int32)
    case setNonBlocking(Bool)
    case configureKeypad(Bool)
    case recordKey(prefix: String, y: Int32, x: Int32, fallback: String)
    case recordMouse(prefix: String, y: Int32, x: Int32, fallback: String)
    case setAttributes(attributes: [SnapshotAttribute], colorPair: String?)
    case wait(milliseconds: UInt32)
    case refresh
    case flush

    private enum CodingKeys: String, CodingKey {
        case type
        case parameters
    }

    private enum CommandType: String, Codable {
        case drawBox
        case mvAdd
        case mvAddWithEllipsis
        case reportSize
        case reportTerminalSize
        case setTimeout
        case setNonBlocking
        case configureKeypad
        case recordKey
        case recordMouse
        case setAttributes
        case wait
        case refresh
        case flush
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .drawBox:
            try container.encode(CommandType.drawBox, forKey: .type)
        case let .mvAdd(string, y, x):
            try container.encode(CommandType.mvAdd, forKey: .type)
            var params = container.nestedContainer(keyedBy: MoveKeys.self, forKey: .parameters)
            try params.encode(string, forKey: .string)
            try params.encode(y, forKey: .y)
            try params.encode(x, forKey: .x)
        case let .mvAddWithEllipsis(string, maxColumns, y, x, ellipsis):
            try container.encode(CommandType.mvAddWithEllipsis, forKey: .type)
            var params = container.nestedContainer(keyedBy: MoveEllipsisKeys.self, forKey: .parameters)
            try params.encode(string, forKey: .string)
            try params.encode(maxColumns, forKey: .maxColumns)
            try params.encode(y, forKey: .y)
            try params.encode(x, forKey: .x)
            try params.encode(ellipsis, forKey: .ellipsis)
        case let .reportSize(prefix, y, x):
            try container.encode(CommandType.reportSize, forKey: .type)
            var params = container.nestedContainer(keyedBy: ReportSizeKeys.self, forKey: .parameters)
            try params.encode(prefix, forKey: .prefix)
            try params.encode(y, forKey: .y)
            try params.encode(x, forKey: .x)
        case let .reportTerminalSize(prefix, y, x):
            try container.encode(CommandType.reportTerminalSize, forKey: .type)
            var params = container.nestedContainer(keyedBy: ReportSizeKeys.self, forKey: .parameters)
            try params.encode(prefix, forKey: .prefix)
            try params.encode(y, forKey: .y)
            try params.encode(x, forKey: .x)
        case let .setTimeout(milliseconds):
            try container.encode(CommandType.setTimeout, forKey: .type)
            var params = container.nestedContainer(keyedBy: TimeoutKeys.self, forKey: .parameters)
            try params.encode(milliseconds, forKey: .milliseconds)
        case let .setNonBlocking(enabled):
            try container.encode(CommandType.setNonBlocking, forKey: .type)
            var params = container.nestedContainer(keyedBy: NonBlockingKeys.self, forKey: .parameters)
            try params.encode(enabled, forKey: .enabled)
        case let .configureKeypad(enabled):
            try container.encode(CommandType.configureKeypad, forKey: .type)
            var params = container.nestedContainer(keyedBy: KeypadKeys.self, forKey: .parameters)
            try params.encode(enabled, forKey: .enabled)
        case let .recordKey(prefix, y, x, fallback):
            try container.encode(CommandType.recordKey, forKey: .type)
            var params = container.nestedContainer(keyedBy: RecordKeyKeys.self, forKey: .parameters)
            try params.encode(prefix, forKey: .prefix)
            try params.encode(y, forKey: .y)
            try params.encode(x, forKey: .x)
            try params.encode(fallback, forKey: .fallback)
        case let .recordMouse(prefix, y, x, fallback):
            try container.encode(CommandType.recordMouse, forKey: .type)
            var params = container.nestedContainer(keyedBy: RecordMouseKeys.self, forKey: .parameters)
            try params.encode(prefix, forKey: .prefix)
            try params.encode(y, forKey: .y)
            try params.encode(x, forKey: .x)
            try params.encode(fallback, forKey: .fallback)
        case let .setAttributes(attributes, colorPair):
            try container.encode(CommandType.setAttributes, forKey: .type)
            var params = container.nestedContainer(keyedBy: AttributeKeys.self, forKey: .parameters)
            try params.encode(attributes, forKey: .attributes)
            try params.encode(colorPair, forKey: .colorPair)
        case let .wait(milliseconds):
            try container.encode(CommandType.wait, forKey: .type)
            var params = container.nestedContainer(keyedBy: WaitKeys.self, forKey: .parameters)
            try params.encode(milliseconds, forKey: .milliseconds)
        case .refresh:
            try container.encode(CommandType.refresh, forKey: .type)
        case .flush:
            try container.encode(CommandType.flush, forKey: .type)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(CommandType.self, forKey: .type)
        switch type {
        case .drawBox:
            self = .drawBox
        case .mvAdd:
            let params = try container.nestedContainer(keyedBy: MoveKeys.self, forKey: .parameters)
            let string = try params.decode(String.self, forKey: .string)
            let y = try params.decode(Int32.self, forKey: .y)
            let x = try params.decode(Int32.self, forKey: .x)
            self = .mvAdd(string: string, y: y, x: x)
        case .mvAddWithEllipsis:
            let params = try container.nestedContainer(keyedBy: MoveEllipsisKeys.self, forKey: .parameters)
            let string = try params.decode(String.self, forKey: .string)
            let maxColumns = try params.decode(Int32.self, forKey: .maxColumns)
            let y = try params.decode(Int32.self, forKey: .y)
            let x = try params.decode(Int32.self, forKey: .x)
            let ellipsis = try params.decode(String.self, forKey: .ellipsis)
            self = .mvAddWithEllipsis(string: string, maxColumns: maxColumns, y: y, x: x, ellipsis: ellipsis)
        case .reportSize:
            let params = try container.nestedContainer(keyedBy: ReportSizeKeys.self, forKey: .parameters)
            let prefix = try params.decode(String.self, forKey: .prefix)
            let y = try params.decode(Int32.self, forKey: .y)
            let x = try params.decode(Int32.self, forKey: .x)
            self = .reportSize(prefix: prefix, y: y, x: x)
        case .reportTerminalSize:
            let params = try container.nestedContainer(keyedBy: ReportSizeKeys.self, forKey: .parameters)
            let prefix = try params.decode(String.self, forKey: .prefix)
            let y = try params.decode(Int32.self, forKey: .y)
            let x = try params.decode(Int32.self, forKey: .x)
            self = .reportTerminalSize(prefix: prefix, y: y, x: x)
        case .setTimeout:
            let params = try container.nestedContainer(keyedBy: TimeoutKeys.self, forKey: .parameters)
            let milliseconds = try params.decode(Int32.self, forKey: .milliseconds)
            self = .setTimeout(milliseconds: milliseconds)
        case .setNonBlocking:
            let params = try container.nestedContainer(keyedBy: NonBlockingKeys.self, forKey: .parameters)
            let enabled = try params.decode(Bool.self, forKey: .enabled)
            self = .setNonBlocking(enabled)
        case .configureKeypad:
            let params = try container.nestedContainer(keyedBy: KeypadKeys.self, forKey: .parameters)
            let enabled = try params.decode(Bool.self, forKey: .enabled)
            self = .configureKeypad(enabled)
        case .recordKey:
            let params = try container.nestedContainer(keyedBy: RecordKeyKeys.self, forKey: .parameters)
            let prefix = try params.decode(String.self, forKey: .prefix)
            let y = try params.decode(Int32.self, forKey: .y)
            let x = try params.decode(Int32.self, forKey: .x)
            let fallback = try params.decode(String.self, forKey: .fallback)
            self = .recordKey(prefix: prefix, y: y, x: x, fallback: fallback)
        case .recordMouse:
            let params = try container.nestedContainer(keyedBy: RecordMouseKeys.self, forKey: .parameters)
            let prefix = try params.decode(String.self, forKey: .prefix)
            let y = try params.decode(Int32.self, forKey: .y)
            let x = try params.decode(Int32.self, forKey: .x)
            let fallback = try params.decode(String.self, forKey: .fallback)
            self = .recordMouse(prefix: prefix, y: y, x: x, fallback: fallback)
        case .wait:
            let params = try container.nestedContainer(keyedBy: WaitKeys.self, forKey: .parameters)
            let milliseconds = try params.decode(UInt32.self, forKey: .milliseconds)
            self = .wait(milliseconds: milliseconds)
        case .setAttributes:
            let params = try container.nestedContainer(keyedBy: AttributeKeys.self, forKey: .parameters)
            let attributes = try params.decode([SnapshotAttribute].self, forKey: .attributes)
            let colorPair = try params.decodeIfPresent(String.self, forKey: .colorPair)
            self = .setAttributes(attributes: attributes, colorPair: colorPair)
        case .refresh:
            self = .refresh
        case .flush:
            self = .flush
        }
    }

    private enum MoveKeys: String, CodingKey {
        case string
        case y
        case x
    }

    private enum MoveEllipsisKeys: String, CodingKey {
        case string
        case maxColumns
        case y
        case x
        case ellipsis
    }

    private enum ReportSizeKeys: String, CodingKey {
        case prefix
        case y
        case x
    }

    private enum WaitKeys: String, CodingKey {
        case milliseconds
    }

    private enum AttributeKeys: String, CodingKey {
        case attributes
        case colorPair
    }

    private enum TimeoutKeys: String, CodingKey {
        case milliseconds
    }

    private enum NonBlockingKeys: String, CodingKey {
        case enabled
    }

    private enum KeypadKeys: String, CodingKey {
        case enabled
    }

    private enum RecordKeyKeys: String, CodingKey {
        case prefix
        case y
        case x
        case fallback
    }

    private enum RecordMouseKeys: String, CodingKey {
        case prefix
        case y
        case x
        case fallback
    }
}

public struct SnapshotProgramBuilder {
    private var term: String?
    private var commands: [SnapshotCommand] = []

    public init(term: String? = nil) {
        self.term = term
    }

    public mutating func setTerm(_ value: String) {
        term = value
    }

    public mutating func configureIO(raw: Bool = true, cbreak: Bool = true, echo: Bool = false, keypad: Bool = true) {
        commands.append(.configureIO(raw: raw, cbreak: cbreak, echo: echo, keypad: keypad))
    }

    public mutating func withWindow(height: Int32, width: Int32, startY: Int32, startX: Int32, _ build: (inout WindowCommandBuilder) -> Void) {
        var builder = WindowCommandBuilder()
        build(&builder)
        let descriptor = WindowDescriptor(height: height, width: width, startY: startY, startX: startX, commands: builder.build())
        commands.append(.withWindow(descriptor))
    }

    public mutating func startColor() {
        commands.append(.startColor)
    }

    public mutating func allocateColorPair(named name: String, foreground: SnapshotColor, background: SnapshotColor) {
        let descriptor = ColorPairDescriptor(name: name, foreground: foreground, background: background)
        commands.append(.allocateColorPair(descriptor))
    }

    public mutating func enableMouse(_ mask: SnapshotMouseMask = .all) {
        commands.append(.enableMouse(mask))
    }

    public mutating func disableMouse() {
        commands.append(.disableMouse)
    }

    public mutating func wait(milliseconds: UInt32) {
        commands.append(.wait(milliseconds: milliseconds))
    }

    public mutating func flush() {
        commands.append(.flush)
    }

    public func build() -> SnapshotProgram {
        SnapshotProgram(term: term, commands: commands)
    }
}

public struct WindowCommandBuilder {
    private var commands: [WindowCommand] = []

    public mutating func drawBox() {
        commands.append(.drawBox)
    }

    public mutating func mvAdd(_ string: String, y: Int32, x: Int32) {
        commands.append(.mvAdd(string: string, y: y, x: x))
    }

    public mutating func mvAddWithEllipsis(_ string: String, maxColumns: Int32, y: Int32, x: Int32, ellipsis: String = "...") {
        commands.append(.mvAddWithEllipsis(string: string, maxColumns: maxColumns, y: y, x: x, ellipsis: ellipsis))
    }

    public mutating func setAttributes(_ attributes: [SnapshotAttribute] = [], colorPair name: String? = nil) {
        commands.append(.setAttributes(attributes: attributes, colorPair: name))
    }

    public mutating func setAttributes(_ attribute: SnapshotAttribute, colorPair name: String? = nil) {
        setAttributes([attribute], colorPair: name)
    }

    public mutating func setTimeout(milliseconds: Int32) {
        commands.append(.setTimeout(milliseconds: milliseconds))
    }

    public mutating func setNonBlocking(_ enabled: Bool) {
        commands.append(.setNonBlocking(enabled))
    }

    public mutating func configureKeypad(_ enabled: Bool) {
        commands.append(.configureKeypad(enabled))
    }

    public mutating func recordKey(prefix: String, y: Int32, x: Int32, fallback: String = "none") {
        commands.append(.recordKey(prefix: prefix, y: y, x: x, fallback: fallback))
    }

    public mutating func recordMouse(prefix: String, y: Int32, x: Int32, fallback: String = "none") {
        commands.append(.recordMouse(prefix: prefix, y: y, x: x, fallback: fallback))
    }

    public mutating func reportSize(prefix: String, y: Int32, x: Int32) {
        commands.append(.reportSize(prefix: prefix, y: y, x: x))
    }

    public mutating func reportTerminalSize(prefix: String, y: Int32, x: Int32) {
        commands.append(.reportTerminalSize(prefix: prefix, y: y, x: x))
    }

    public mutating func wait(milliseconds: UInt32) {
        commands.append(.wait(milliseconds: milliseconds))
    }

    public mutating func refresh() {
        commands.append(.refresh)
    }

    public mutating func flush() {
        commands.append(.flush)
    }

    public func build() -> [WindowCommand] {
        commands
    }
}
