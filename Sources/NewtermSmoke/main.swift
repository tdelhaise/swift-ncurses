import CNcurses
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@MainActor
private func run() {
  setenv("TERM", "xterm-256color", 1)
  guard let screen = newterm(nil, stdout, stdin) else {
    _ = fputs("newterm() failed\n", stderr)
    exit(1)
  }
  defer { endwin(); delscreen(screen) }
  print("OK: newterm/init+cleanup")
}

@main
struct NewtermSmokeMain {
  static func main() {
    run()
  }
}
