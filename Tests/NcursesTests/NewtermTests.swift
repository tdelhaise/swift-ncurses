import XCTest
import CNcurses

#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

final class NewtermTests: XCTestCase {

  func testNewtermInitAndCleanup() throws {
    // En CI, souvent pas de TTY : on ignore proprement.
    if isatty(STDIN_FILENO) == 0 {
      throw XCTSkip("Pas de TTY détecté (CI) — test ignoré.")
    }

    // Certaines implémentations exigent TERM.
    setenv("TERM", "xterm-256color", 1)

    // Éviter stdin/stdout/stderr (non concurrency-safe en Swift 6).
    guard
      let inFile  = fdopen(STDIN_FILENO,  "r"),
      let outFile = fdopen(STDOUT_FILENO, "w"),
      let errFile = fdopen(STDERR_FILENO, "w")
    else {
      XCTFail("fdopen a échoué")
      return
    }

    // Utilise explicitement les symboles CNcurses.*
    guard let screen = CNcurses.newterm(nil, outFile, inFile) else {
      _ = fputs("newterm() failed\n", errFile)
      XCTFail("newterm a retourné nil (échec d'initialisation ncurses)")
      return
    }

    // Nettoyage
    CNcurses.endwin()
    CNcurses.delscreen(screen)
  }
}

