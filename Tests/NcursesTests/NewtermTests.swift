import XCTest
import CNcurses

#if canImport(Darwin)
import Darwin   // stdout, stdin, setenv
#else
import Glibc
#endif

final class NewtermTests: XCTestCase {
  func test_newterm_initialization_and_cleanup() {
    // S'assure d'avoir une entrée TERM valide pour terminfo
    _ = setenv("TERM", "xterm-256color", 1)

    // newterm crée un SCREEN* sans écrire directement sur le TTY courant
    guard let screen = newterm(nil, stdout, stdin) else {
      XCTFail("newterm returned nil (échec d'initialisation ncurses)")
      return
    }

    // On peut sélectionner ce SCREEN si besoin (pas obligatoire pour ce smoke test)
    set_term(screen)

    // Nettoyage minimal : on termine la session curses puis on libère l'écran
    endwin()
    delscreen(screen)

    // Si on est arrivé ici, l'init+cleanup a fonctionné
    XCTAssertTrue(true)
  }
}
