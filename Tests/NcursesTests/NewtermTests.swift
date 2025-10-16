import XCTest
@testable import Ncurses

#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

final class NewtermTests: XCTestCase {

  /// Vérifie que `newterm` peut initialiser puis nettoyer correctement
  /// NOTE: en CI (sans TTY), on ignore proprement ce test.
  func testNewtermInitAndCleanup() throws {
    // La plupart des workers CI n'ont pas de TTY : on ignore le test dans ce cas.
    if isatty(STDIN_FILENO) == 0 {
      throw XCTSkip("Environnement sans TTY (CI) — test ignoré.")
    }

    // Certaines implémentations de curses exigent TERM.
    setenv("TERM", "xterm-256color", 1)

    // Éviter les globals C (stdin/stdout/stderr) non concurrency-safe en Swift 6.
    guard
      let inFile  = fdopen(STDIN_FILENO,  "r"),
      let outFile = fdopen(STDOUT_FILENO, "w"),
      let errFile = fdopen(STDERR_FILENO, "w")
    else {
      XCTFail("fdopen a échoué")
      return
    }

    // newterm crée un SCREEN* sans écrire directement sur le TTY courant
    guard let screen = newterm(nil, outFile, inFile) else {
      _ = fputs("newterm() failed\n", errFile)
      XCTFail("newterm a retourné nil (échec d'initialisation ncurses)")
      return
    }

    // Nettoyage ncurses
    endwin()
    delscreen(screen)
  }
}

