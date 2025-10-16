import CNcurses
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct NewtermSmokeMain {
  static func main() {
    // Évite l’accès aux globals C non sendable (stdin/stdout/stderr)
    setenv("TERM", "xterm-256color", 1)

    let inFile  = fdopen(0, "r")
    let outFile = fdopen(1, "w")
    let errFile = fdopen(2, "w")

    guard let screen = newterm(nil, outFile, inFile) else {
      _ = fputs("newterm() failed\n", errFile)
      exit(1)
    }
    defer {
      endwin()
      delscreen(screen)
      fflush(outFile)
    }
    print("OK: newterm/init+cleanup")
  }
}
