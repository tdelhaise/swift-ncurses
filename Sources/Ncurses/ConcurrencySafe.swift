//
//  ConcurrencySafe.swift
//  swift-ncurses
//
//  Created by Thierry DELHAISE on 16/10/2025.
//

import CNcurses
#if canImport(Glibc)
import Glibc
private let readMode = "r"
private let writeMode = "w"
#else
import Darwin
private let readMode = "r"
private let writeMode = "w"
#endif

// MARK: - Global actor pour sérialiser l’usage de ncurses (non thread-safe)

@globalActor
public struct CursesActor {
	public actor ActorType {}
	public static let shared = ActorType()
}

// MARK: - Fourniture de FILE* sans toucher aux globals C (même acteur global)

@CursesActor
public final class StdStreams {
	public static let shared = StdStreams()
	
	// On ouvre une seule fois, et on réutilise (fdopen ne duplique pas le FD)
	private var cachedIn: UnsafeMutablePointer<FILE>?
	private var cachedOut: UnsafeMutablePointer<FILE>?
	private var cachedErr: UnsafeMutablePointer<FILE>?
	
	public enum Error: Swift.Error { case fdopenFailed }
	
	public func inputFile() throws -> UnsafeMutablePointer<FILE> {
		if let f = cachedIn { return f }
		guard let f = fdopen(STDIN_FILENO, readMode) else { throw Error.fdopenFailed }
		cachedIn = f
		return f
	}
	
	public func outputFile() throws -> UnsafeMutablePointer<FILE> {
		if let f = cachedOut { return f }
		guard let f = fdopen(STDOUT_FILENO, writeMode) else { throw Error.fdopenFailed }
		cachedOut = f
		return f
	}
	
	public func errorFile() throws -> UnsafeMutablePointer<FILE> {
		if let f = cachedErr { return f }
		guard let f = fdopen(STDERR_FILENO, writeMode) else { throw Error.fdopenFailed }
		cachedErr = f
		return f
	}
}

// MARK: - Souris

public extension Curses {
	struct MouseMask: OptionSet, Sendable {
		public let rawValue: UInt
		public init(rawValue: UInt) { self.rawValue = rawValue }
		
		public static let button1Pressed = MouseMask(rawValue: UInt(CNcurses.swift_ncurses_button1_pressed()))
		public static let button1Released = MouseMask(rawValue: UInt(CNcurses.swift_ncurses_button1_released()))
		public static let button2Pressed = MouseMask(rawValue: UInt(CNcurses.swift_ncurses_button2_pressed()))
		public static let button2Released = MouseMask(rawValue: UInt(CNcurses.swift_ncurses_button2_released()))
		public static let button3Pressed = MouseMask(rawValue: UInt(CNcurses.swift_ncurses_button3_pressed()))
		public static let button3Released = MouseMask(rawValue: UInt(CNcurses.swift_ncurses_button3_released()))
		public static let button4Pressed = MouseMask(rawValue: UInt(CNcurses.swift_ncurses_button4_pressed()))
		public static let button4Released = MouseMask(rawValue: UInt(CNcurses.swift_ncurses_button4_released()))
		public static let reportPosition = MouseMask(rawValue: UInt(CNcurses.swift_ncurses_report_mouse_position()))
		
		public static let none: MouseMask = []
		public static let allEvents: MouseMask = [
			.button1Pressed, .button1Released,
			.button2Pressed, .button2Released,
			.button3Pressed, .button3Released,
			.button4Pressed, .button4Released,
			.reportPosition
		]
	}
	
	enum MouseEvent: Sendable {
		case pressed(btn: Int, y: Int32, x: Int32)
		case released(btn: Int, y: Int32, x: Int32)
		case moved(y: Int32, x: Int32)
	}
	
	@CursesActor
	static func enableMouse(mask: MouseMask) throws {
		try withActiveTerm {
			var previous: UInt = 0
			let (newMask, errnoValue) = withErrno {
				CNcurses.mousemask(mask.rawValue, &previous)
			}
			if errnoValue != 0 {
				throw CursesError.operationFailed(function: "mousemask", errno: errnoValue)
			}
			currentMouseMask = MouseMask(rawValue: UInt(newMask))
		}
	}
	
	@CursesActor
	static func disableMouse() throws {
		try withActiveTerm {
			var previous: UInt = 0
			let (_, errnoValue) = withErrno {
				CNcurses.mousemask(0, &previous)
			}
			if errnoValue != 0 {
				throw CursesError.operationFailed(function: "mousemask", errno: errnoValue)
			}
			currentMouseMask = []
		}
	}
	
	@CursesActor
	static func getMouse() -> MouseEvent? {
		do {
			return try withActiveTerm {
				var event = CNcurses.MEVENT()
				let (result, errnoValue) = withErrno {
					CNcurses.getmouse(&event)
				}
				
				guard result != ERR else {
					if errnoValue == EAGAIN || errnoValue == EINTR {
						return nil
					}
					return nil
				}
				
				return interpretMouseEvent(event)
			}
		} catch {
			return nil
		}
	}
	
	private static let mouseButtons: [(press: MouseMask, release: MouseMask, index: Int)] = [
		(.button1Pressed, .button1Released, 1),
		(.button2Pressed, .button2Released, 2),
		(.button3Pressed, .button3Released, 3),
		(.button4Pressed, .button4Released, 4)
	]
	
	private static func interpretMouseEvent(_ event: CNcurses.MEVENT) -> MouseEvent? {
		let state = MouseMask(rawValue: UInt(event.bstate))
		let y = Int32(event.y)
		let x = Int32(event.x)
		
		for button in mouseButtons {
			if button.press.rawValue != 0 && state.contains(button.press) {
				return .pressed(btn: button.index, y: y, x: x)
			}
			if button.release.rawValue != 0 && state.contains(button.release) {
				return .released(btn: button.index, y: y, x: x)
			}
		}
		
		if MouseMask.reportPosition.rawValue != 0 && state.contains(.reportPosition) {
			return .moved(y: y, x: x)
		}
		
		return nil
	}
}
// MARK: - API Swift fine pour démarrer/arrêter ncurses en toute sécurité

public enum CursesError: Error {
	case newtermFailed
	case colorsNotSupported
	case colorPairsExhausted
	case operationFailed(function: String, errno: Int32)
	case noActiveScreen
}

public enum CursesResult: Sendable {
	case ok
	case err
	
	public init(_ value: Int32) {
		self = value == OK ? .ok : .err
	}
	
	public var isSuccess: Bool { self == .ok }
}

public enum Curses {
	@CursesActor private static var nextColorPairIdentifier: Int16 = 1
	@CursesActor fileprivate static var activeScreen: OpaquePointer?
	@CursesActor private static var localeInitialized = false
	@CursesActor private static var currentMouseMask = MouseMask(rawValue: 0)

	/// Exécute `body` dans un contexte ncurses initialisé, avec nettoyage garanti.
	/// Tout est isolé par `@CursesActor`, ncurses n’est jamais appelé en concurrence.
	@CursesActor
	public static func withScreen<R>(
		term: UnsafePointer<CChar>? = nil,
		_ body: (OpaquePointer /* SCREEN* */) throws -> R
	) throws -> R {
		// Éviter tout accès à stdin/stdout/stderr globals : on passe par StdStreams.
		let inFile  = try StdStreams.shared.inputFile()
		let outFile = try StdStreams.shared.outputFile()
		
		// Adapter la const-correctness attendue par l’import C (Linux attend parfois char *)
		let mterm: UnsafeMutablePointer<CChar>? = term.map { UnsafeMutablePointer(mutating: $0) }
		
		// Important: pas de suspension ici; tout reste dans le même segment d’exécution.
		guard let screen = CNcurses.newterm(mterm, outFile, inFile) else {
			if let ef = try? StdStreams.shared.errorFile() {
				_ = fputs("newterm() failed\n", ef)
			}
			throw CursesError.newtermFailed
		}
		
		let previousScreen = activeScreen
		activeScreen = screen
		
		// Nettoyage garanti
		defer {
			activeScreen = previousScreen
			CNcurses.endwin()
			CNcurses.delscreen(screen)
		}
		
		return try body(screen)
	}
}

// MARK: - Helper errno (synchrone, aucune suspension)

@inline(__always)
public func withErrno<R>(_ body: () -> R) -> (result: R, errnoValue: Int32) {
	errno = 0
	let result = body()
	let error = errno
	return (result, error)
}


// MARK: - Fenêtres (WINDOW*) sûres avec nettoyage garanti

public enum WindowError: Error {
	case newwinFailed
	case couldNotGetTerminalSize
}

public enum PanelError: Error {
	case newPanelFailed
}

// MARK: - Helpers

@inline(__always)
@CursesActor
private func withTerm<R>(screen: OpaquePointer, _ body: () throws -> R) rethrows -> R {
	let previous = CNcurses.set_term(screen)
	defer { _ = CNcurses.set_term(previous) }
	return try body()
}

@inline(__always)
@CursesActor
private func withActiveTerm<R>(_ body: () throws -> R) throws -> R {
	guard let screen = Curses.activeScreen else { throw CursesError.noActiveScreen }
	let previous = CNcurses.set_term(screen)
	defer { _ = CNcurses.set_term(previous) }
	return try body()
}

@inline(__always)
private func ensureOk(_ result: Int32, function: StaticString, errnoValue: Int32) throws {
	guard result != ERR else {
		throw CursesError.operationFailed(function: "\(function)", errno: errnoValue)
	}
}

@inline(__always)
private func ensureCursorResult(_ result: Int32, function: StaticString, errnoValue: Int32) throws -> Int32 {
	guard result != ERR else {
		throw CursesError.operationFailed(function: "\(function)", errno: errnoValue)
	}
	return result
}

public extension Curses {
	/// Crée une fenêtre ncurses, exécute `body` puis la détruit (delwin) quoi qu’il arrive.
	/// - Parameters:
	///   - height: hauteur en lignes
	///   - width:  largeur en colonnes
	///   - startY: position Y de départ
	///   - startX: position X de départ
	///   - screen: le SCREEN* dans lequel créer la fenêtre
	///   - configure: configuration optionnelle (ex: keypad, nodelay, etc.)
	@CursesActor
	static func withWindow<R>(
		height: Int32,
		width: Int32,
		startY: Int32,
		startX: Int32,
		on screen: OpaquePointer,
		configure: ((OpaquePointer /* WINDOW* */) -> Void)? = nil,
		_ body: (OpaquePointer /* WINDOW* */) throws -> R
	) throws -> R {
		// Cible le bon SCREEN* pendant la durée de vie de la fenêtre
		let previous = CNcurses.set_term(screen)
		defer { _ = CNcurses.set_term(previous) }
		
		guard let win = CNcurses.newwin(height, width, startY, startX) else {
			throw WindowError.newwinFailed
		}
		defer { _ = CNcurses.delwin(win) }
		
		// Configuration facultative (ex. keypad(win, true), box(win, 0, 0), etc.)
		configure?(win)
		
		return try body(win)
	}
	
	/// Variante plein écran : calcule (lignes, colonnes) via ioctl(TIOCGWINSZ), puis crée une fenêtre 0,0 -> plein écran.
	@CursesActor
	static func withFullScreenWindow<R>(
		on screen: OpaquePointer,
		configure: ((OpaquePointer /* WINDOW* */) -> Void)? = nil,
		_ body: (OpaquePointer /* WINDOW* */) throws -> R
	) throws -> R {
		guard let (rows, cols) = terminalSize() else {
			throw WindowError.couldNotGetTerminalSize
		}
		return try withWindow(
			height: rows,
			width: cols,
			startY: 0,
			startX: 0,
			on: screen,
			configure: configure,
			body
		)
	}
}

// MARK: - Taille de terminal (ioctl) sans dépendre de `stdscr`

@CursesActor
private func terminalSize() -> (rows: Int32, cols: Int32)? {
	var ws = winsize()
#if os(Linux)
	// Glibc expose winsize avec ws_row / ws_col
	if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 {
		let rows = Int32(ws.ws_row)
		let cols = Int32(ws.ws_col)
		return (rows, cols)
	}
#else
	// Darwin (macOS) expose aussi winsize/ws_row/ws_col
	if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 {
		let rows = Int32(ws.ws_row)
		let cols = Int32(ws.ws_col)
		return (rows, cols)
	}
#endif
	return nil
}

// MARK: - Configuration I/O & curseur

public extension Curses {
	enum CursorVisibility: Sendable {
		case hidden
		case normal
		case high

		fileprivate var rawValue: Int32 {
			switch self {
			case .hidden: return 0
			case .normal: return 1
			case .high: return 2
			}
		}
	}

	@CursesActor
	static func configureIO(
		on screen: OpaquePointer,
		raw: Bool = true,
		cbreak: Bool = true,
		echo: Bool = false,
		keypad: Bool = true
	) throws {
		try withTerm(screen: screen) {
			if raw {
				let (result, errnoValue) = withErrno { CNcurses.raw() }
				try ensureOk(result, function: "raw", errnoValue: errnoValue)
			} else {
				let (result, errnoValue) = withErrno { CNcurses.noraw() }
				try ensureOk(result, function: "noraw", errnoValue: errnoValue)
			}

			if cbreak {
				let (result, errnoValue) = withErrno { CNcurses.cbreak() }
				try ensureOk(result, function: "cbreak", errnoValue: errnoValue)
			} else {
				let (result, errnoValue) = withErrno { CNcurses.nocbreak() }
				try ensureOk(result, function: "nocbreak", errnoValue: errnoValue)
			}

			if echo {
				let (result, errnoValue) = withErrno { CNcurses.echo() }
				try ensureOk(result, function: "echo", errnoValue: errnoValue)
			} else {
				let (result, errnoValue) = withErrno { CNcurses.noecho() }
				try ensureOk(result, function: "noecho", errnoValue: errnoValue)
			}

			// `keypad` agit sur la fenêtre principale associée au screen courant.
			let flag: Int32 = keypad ? 1 : 0
			let (result, errnoValue) = withErrno {
				CNcurses.swift_ncurses_configure_stdscr_keypad(flag)
			}
			try ensureOk(result, function: "keypad", errnoValue: errnoValue)
		}
	}

	@CursesActor
	static func setCursorVisibility(_ visibility: CursorVisibility, on screen: OpaquePointer) throws {
		try withTerm(screen: screen) {
			let (result, errnoValue) = withErrno { CNcurses.curs_set(visibility.rawValue) }
			_ = try ensureCursorResult(result, function: "curs_set", errnoValue: errnoValue)
		}
	}
}

// MARK: - Sous-fenêtres & pads

public extension Curses {
	@CursesActor
	static func withSubWindow<R>(
		parent: OpaquePointer,
		height: Int32,
		width: Int32,
		startY: Int32,
		startX: Int32,
		_ body: (OpaquePointer) throws -> R
	) throws -> R {
		guard let win = CNcurses.derwin(parent, height, width, startY, startX) else {
			throw WindowError.newwinFailed
		}
		defer { _ = CNcurses.delwin(win) }
		return try body(win)
	}

	@CursesActor
	static func withPad<R>(
		rows: Int32,
		cols: Int32,
		_ body: (OpaquePointer) throws -> R
	) throws -> R {
		guard let pad = CNcurses.newpad(rows, cols) else {
			throw WindowError.newwinFailed
		}
		defer { _ = CNcurses.delwin(pad) }
		return try body(pad)
	}
}

// MARK: - Modes clavier

public extension Curses {
	@CursesActor
	static func setTimeout(on win: OpaquePointer, milliseconds: Int32) {
		CNcurses.wtimeout(win, milliseconds)
	}

	@CursesActor
	static func setNonBlocking(on win: OpaquePointer, enabled: Bool) {
		let _ = CNcurses.nodelay(win, enabled ? true : false)
	}

	enum Key: Sendable, Equatable {
		case char(UInt32)
		case enter
		case backspace
		case up, down, left, right
		case home, end, pageUp, pageDown
		case f(Int)
		case resize
		case mouse
		case unknown(Int32)
	}

	@CursesActor
	static func getKey(from win: OpaquePointer) -> Key? {
		let (rawValue, errnoValue) = withErrno {
			CNcurses.wgetch(win)
		}
		let value = rawValue

		if value == ERR {
			// Pas d’entrée disponible : EAGAIN, EINTR… => on retourne nil.
			if errnoValue == EAGAIN || errnoValue == EINTR {
				return nil
			} else if errnoValue != 0 {
				// Autre erreur: exposer comme inconnue.
				return .unknown(value)
			}
			return nil
		}

		if value <= 0xFF {
			return .char(UInt32(UInt8(truncatingIfNeeded: value)))
		}

		switch value {
		case KEY_ENTER: return .enter
		case KEY_BACKSPACE: return .backspace
		case KEY_UP: return .up
		case KEY_DOWN: return .down
		case KEY_LEFT: return .left
		case KEY_RIGHT: return .right
		case KEY_HOME: return .home
		case KEY_END: return .end
		case KEY_PPAGE: return .pageUp
		case KEY_NPAGE: return .pageDown
		case KEY_RESIZE: return .resize
		case KEY_MOUSE: return .mouse
		default:
			let fBase = KEY_F0
			if value >= fBase {
				let index = Int(value - fBase)
				return .f(index)
			}
			return .unknown(value)
		}
	}

	@CursesActor
	static func keyEvents(
		from win: OpaquePointer,
		pollEvery milliseconds: Int = 16
	) -> AsyncStream<Key> {
		AsyncStream { continuation in
			let task = Task { @CursesActor in
				while !Task.isCancelled {
					if let key = Curses.getKey(from: win) {
						continuation.yield(key)
						continue
					}
					try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
				}
				continuation.finish()
			}

			continuation.onTermination = { _ in
				task.cancel()
			}
		}
	}
}

// MARK: - Couleurs & attributs

public extension Curses {
	enum Color: Int16, Sendable {
		case black = 0
		case red
		case green
		case yellow
		case blue
		case magenta
		case cyan
		case white
	}

	struct ColorPair: Sendable {
		public let id: Int16
		public init(id: Int16) { self.id = id }
	}

	struct AttributeSet: OptionSet, Sendable {
		public let rawValue: Int32
		public init(rawValue: Int32) { self.rawValue = rawValue }

		public static let bold = AttributeSet(rawValue: Int32(CNcurses.swift_ncurses_attr_bold()))
		public static let dim = AttributeSet(rawValue: Int32(CNcurses.swift_ncurses_attr_dim()))
		public static let underline = AttributeSet(rawValue: Int32(CNcurses.swift_ncurses_attr_underline()))
		public static let reverse = AttributeSet(rawValue: Int32(CNcurses.swift_ncurses_attr_reverse()))
		public static let blink = AttributeSet(rawValue: Int32(CNcurses.swift_ncurses_attr_blink()))
		public static let standout = AttributeSet(rawValue: Int32(CNcurses.swift_ncurses_attr_standout()))
		public static let italic = AttributeSet(rawValue: Int32(CNcurses.swift_ncurses_attr_italic()))
		public static let invisible = AttributeSet(rawValue: Int32(CNcurses.swift_ncurses_attr_invisible()))
	}

	@CursesActor
	static func startColorIfNeeded(on screen: OpaquePointer) throws {
		try withTerm(screen: screen) {
			guard CNcurses.has_colors() else {
				throw CursesError.colorsNotSupported
			}

			let (result, errnoValue) = withErrno {
				CNcurses.start_color()
			}
			try ensureOk(result, function: "start_color", errnoValue: errnoValue)

			nextColorPairIdentifier = 1
		}
	}

	@CursesActor
	static func allocateColorPair(fg: Color, bg: Color) throws -> ColorPair {
		let maxPairs = Int32(CNcurses.swift_ncurses_color_pairs())

		let pairId: Int16 = nextColorPairIdentifier
		if Int32(pairId) >= maxPairs {
			throw CursesError.colorPairsExhausted
		}

		let (result, errnoValue) = withErrno {
			CNcurses.init_pair(pairId, fg.rawValue, bg.rawValue)
		}
		try ensureOk(result, function: "init_pair", errnoValue: errnoValue)

		nextColorPairIdentifier = pairId &+ 1
		return ColorPair(id: pairId)
	}

	@CursesActor
	static func setAttributes(on win: OpaquePointer, attrs: AttributeSet = [], color: ColorPair? = nil) {
		let _ = CNcurses.wattrset(win, attrs.rawValue)
		if let color = color {
			let _ = CNcurses.wcolor_set(win, color.id, nil)
		} else {
			let _ = CNcurses.wcolor_set(win, 0, nil)
		}
	}
}

// MARK: - Panels

public extension Curses {
	@CursesActor
	static func withPanel<R>(
		window: OpaquePointer,
		_ body: (OpaquePointer /* PANEL* */) throws -> R
	) throws -> R {
		let panelPointer: UnsafeMutablePointer<CNcurses.PANEL> = try withActiveTerm {
			guard let created = CNcurses.new_panel(window) else {
				throw PanelError.newPanelFailed
			}
			return created
		}
		let panel = OpaquePointer(panelPointer)
		defer {
			try? withActiveTerm {
				_ = CNcurses.del_panel(panelPointer)
			}
		}
		return try body(panel)
	}

	@CursesActor
	static func show(panel: OpaquePointer) throws {
		let outcome: (Int32, Int32) = try withActiveTerm {
			let pair = withErrno {
				CNcurses.show_panel(UnsafeMutablePointer<CNcurses.PANEL>(panel))
			}
			return (pair.result, pair.errnoValue)
		}
		let (result, errnoValue) = outcome
		try ensureOk(result, function: "show_panel", errnoValue: errnoValue)
	}

	@CursesActor
	static func hide(panel: OpaquePointer) throws {
		let outcome: (Int32, Int32) = try withActiveTerm {
			let pair = withErrno {
				CNcurses.hide_panel(UnsafeMutablePointer<CNcurses.PANEL>(panel))
			}
			return (pair.result, pair.errnoValue)
		}
		let (result, errnoValue) = outcome
		try ensureOk(result, function: "hide_panel", errnoValue: errnoValue)
	}

	@CursesActor
	static func top(panel: OpaquePointer) throws {
		let outcome: (Int32, Int32) = try withActiveTerm {
			let pair = withErrno {
				CNcurses.top_panel(UnsafeMutablePointer<CNcurses.PANEL>(panel))
			}
			return (pair.result, pair.errnoValue)
		}
		let (result, errnoValue) = outcome
		try ensureOk(result, function: "top_panel", errnoValue: errnoValue)
	}

	@CursesActor
	static func bottom(panel: OpaquePointer) throws {
		let outcome: (Int32, Int32) = try withActiveTerm {
			let pair = withErrno {
				CNcurses.bottom_panel(UnsafeMutablePointer<CNcurses.PANEL>(panel))
			}
			return (pair.result, pair.errnoValue)
		}
		let (result, errnoValue) = outcome
		try ensureOk(result, function: "bottom_panel", errnoValue: errnoValue)
	}

	@CursesActor
	static func updatePanelsAndFlush() {
		try? withActiveTerm {
			CNcurses.update_panels()
			CNcurses.doupdate()
		}
	}
}

// MARK: - Dessin

public extension Curses {
	@CursesActor
	static func add(_ string: String, in win: OpaquePointer) throws {
		try write(string, into: win)
	}

	@CursesActor
	static func add(_ string: String, maxColumns: Int32, in win: OpaquePointer) throws {
		let truncated = string.ncTruncated(to: maxColumns)
		try write(truncated, into: win)
	}

	@CursesActor
	static func addWithEllipsis(
		_ string: String,
		maxColumns: Int32,
		ellipsis: String = "...",
		in win: OpaquePointer
	) throws {
		let truncated = string.ncTruncated(to: maxColumns, ellipsis: ellipsis)
		try write(truncated, into: win)
	}

	@CursesActor
	static func mvadd(_ string: String, y: Int32, x: Int32, in win: OpaquePointer) throws {
		let (moveResult, moveErrno) = withErrno {
			CNcurses.wmove(win, y, x)
		}
		try ensureOk(moveResult, function: "wmove", errnoValue: moveErrno)

		try write(string, into: win)
	}

	@CursesActor
	static func mvadd(
		_ string: String,
		maxColumns: Int32,
		y: Int32,
		x: Int32,
		in win: OpaquePointer
	) throws {
		let truncated = string.ncTruncated(to: maxColumns)
		try mvadd(truncated, y: y, x: x, in: win)
	}

	@CursesActor
	static func mvaddWithEllipsis(
		_ string: String,
		maxColumns: Int32,
		y: Int32,
		x: Int32,
		ellipsis: String = "...",
		in win: OpaquePointer
	) throws {
		let truncated = string.ncTruncated(to: maxColumns, ellipsis: ellipsis)
		try mvadd(truncated, y: y, x: x, in: win)
	}

	@CursesActor
	static func drawBox(in win: OpaquePointer) {
		let _ = CNcurses.box(win, 0, 0)
	}

	@CursesActor
	static func refresh(_ win: OpaquePointer) {
		let _ = CNcurses.wrefresh(win)
	}

	@CursesActor
	static func flush() {
		let _ = CNcurses.doupdate()
	}

	@CursesActor
	private static func write(_ string: String, into win: OpaquePointer) throws {
		let buffer = Array(string.utf8CString)
		let (result, errnoValue) = buffer.withUnsafeBufferPointer { ptr -> (Int32, Int32) in
			guard let base = ptr.baseAddress else { return (ERR, 0) }
			return withErrno {
				CNcurses.waddnstr(win, base, Int32(buffer.count - 1))
			}
		}
		try ensureOk(result, function: "waddnstr", errnoValue: errnoValue)
	}
}

// MARK: - Texte utilitaires

public extension Curses {
	static func wrap(_ string: String, width: Int) -> [String] {
		return string.ncWrapped(width: width)
	}
}

// MARK: - Redimensionnement

public extension Curses {
	@CursesActor
	static func supportsResize() -> Bool {
		return KEY_RESIZE != 0
	}

	@CursesActor
	static func getSize(of win: OpaquePointer) -> (rows: Int32, cols: Int32) {
		let rows = Int32(CNcurses.getmaxy(win))
		let cols = Int32(CNcurses.getmaxx(win))
		return (rows, cols)
	}
}

// MARK: - Terminfo & locale

public extension Curses {
	@CursesActor
	static func capability(_ name: String) -> String? {
		do {
			return try withActiveTerm {
				name.withCString { capName -> String? in
					let mutableName = UnsafeMutablePointer(mutating: capName)
					guard let raw = CNcurses.tigetstr(mutableName) else { return nil }
					let address = Int(bitPattern: UnsafeMutableRawPointer(raw))
					if address == -1 { return nil }
					return String(cString: raw)
				}
			}
		} catch {
			return nil
		}
	}

	@CursesActor
	static func hasTrueColor() -> Bool {
		do {
			return try withActiveTerm {
				if "Tc".withCString({ cap -> Int32 in
					let mutable = UnsafeMutablePointer(mutating: cap)
					return CNcurses.tigetflag(mutable)
				}) > 0 {
					return true
				}
				if "RGB".withCString({ cap -> Int32 in
					let mutable = UnsafeMutablePointer(mutating: cap)
					return CNcurses.tigetnum(mutable)
				}) > 0 {
					return true
				}
				return "Tc".withCString { capName -> Bool in
					let mutable = UnsafeMutablePointer(mutating: capName)
					guard let raw = CNcurses.tigetstr(mutable) else { return false }
					let address = Int(bitPattern: UnsafeMutableRawPointer(raw))
					return address != -1
				}
			}
		} catch {
			return false
		}
	}

	@CursesActor
	static func ensureLocaleOnce() {
		guard !localeInitialized else { return }
		CNcurses.swift_ncurses_setlocale()
		localeInitialized = true
	}
}

// MARK: - Helpers (strings)

private extension String {
	func ncTruncatedSegments(to columns: Int32) -> (value: String, truncated: Bool) {
		guard columns >= 0 else { return ("", !isEmpty) }
		var width: Int32 = 0
		var scalars: [UnicodeScalar] = []
		var truncated = false
		for scalar in unicodeScalars {
			let scalarWidth = scalar.ncColumnWidth
			if width + scalarWidth > columns {
				truncated = true
				break
			}
			width += scalarWidth
			scalars.append(scalar)
		}
		if !truncated {
			return (self, false)
		}
		let view = String.UnicodeScalarView(scalars)
		return (String(view), true)
	}

	func ncTruncated(to columns: Int32) -> String {
		return ncTruncatedSegments(to: columns).value
	}

	func ncTruncated(to columns: Int32, ellipsis: String) -> String {
		guard columns > 0 else { return "" }
		let ellipsisWidth = ellipsis.ncDisplayWidth()
		if ellipsisWidth >= columns {
			return ellipsis.ncTruncated(to: columns)
		}
		let remaining = columns - ellipsisWidth
		if remaining <= 0 {
			return ellipsis.ncTruncated(to: columns)
		}
		let (value, wasTruncated) = ncTruncatedSegments(to: remaining)
		if wasTruncated {
			return value + ellipsis
		}
		return value
	}

	func ncDisplayWidth() -> Int32 {
		return unicodeScalars.reduce(Int32(0)) { partial, scalar in
			partial + scalar.ncColumnWidth
		}
	}

	func ncWrapped(width: Int) -> [String] {
		guard width > 0 else { return [] }
		var lines: [String] = []
		var current: [UnicodeScalar] = []
		var currentWidth: Int32 = 0
		let maxWidth = Int32(width)

		for scalar in unicodeScalars {
			if scalar.value == 10 {
				lines.append(String(String.UnicodeScalarView(current)))
				current.removeAll(keepingCapacity: true)
				currentWidth = 0
				continue
			}
			let w = scalar.ncColumnWidth
			if currentWidth + w > maxWidth && !current.isEmpty {
				lines.append(String(String.UnicodeScalarView(current)))
				current.removeAll(keepingCapacity: true)
				currentWidth = 0
			}
			current.append(scalar)
			currentWidth += w
		}

		if !current.isEmpty || isEmpty {
			lines.append(String(String.UnicodeScalarView(current)))
		}

		return lines
	}
}

private extension UnicodeScalar {
	var ncColumnWidth: Int32 {
#if canImport(Darwin)
		let width = Darwin.wcwidth(Int32(bitPattern: UInt32(value)))
#else
		let width = Glibc.wcwidth(Int32(bitPattern: UInt32(value)))
#endif
		return width >= 0 ? width : 1
	}
}
