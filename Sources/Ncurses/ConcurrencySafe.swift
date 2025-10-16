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

// MARK: - API Swift fine pour démarrer/arrêter ncurses en toute sécurité

public enum CursesError: Error {
	case newtermFailed
}

public enum Curses {
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
		
		// Nettoyage garanti
		defer {
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
