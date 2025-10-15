import CNcurses

public enum Ncurses {
  @discardableResult
  public static func start() -> OpaquePointer? { initscr() }
  public static func stop() { endwin() }
}
