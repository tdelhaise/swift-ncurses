import CNcurses
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

setenv("TERM", "xterm-256color", 1)
guard let screen = newterm(nil, stdout, stdin) else {
  fputs("newterm() failed\n", stderr)
  exit(1)
}
set_term(screen)
endwin()
delscreen(screen)
print("OK: newterm/init+cleanup")
