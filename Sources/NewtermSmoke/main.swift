import CNcurses
#if canImport(Darwin)
import Darwin
@inline(__always) private func syswriteStderr(_ s: String) { s.withCString { _ = Darwin.write(2, $0, strlen($0)) } }
#else
import Glibc
@inline(__always) private func syswriteStderr(_ s: String) { s.withCString { _ = Glibc.write(2, $0, strlen($0)) } }
#endif

@main
struct NewtermSmokeMain {
  static func main() {
    // Évite l’accès aux globals C non sendable (stdin/stdout/stderr)
    setenv("TERM", "xterm-256color", 1)

    guard let inFile  = fdopen(0, "r"),
          let outFile = fdopen(1, "w"),
          let errFile = fdopen(2, "w") else {
      syswriteStderr("fdopen failed\n")
      exit(1)
    }


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
