# AGENTS.md

Ce document explique **la façade Swift sûre** au-dessus de `ncurses` (pensée pour Swift 6 et son modèle de concurrence), et ce qu’il faut mettre en place **avant** de bâtir `swift-tui`.

---

## Objectifs

- **Sécure Concurrency** : ne jamais toucher aux globales C non-Sendable (`stdin`, `stdout`, `stderr`, `errno`, `stdscr`, …) depuis du code concurrent Swift.
- **API Swift idiomatique** : types forts, `OptionSet`, `enum`, nettoyage garanti via *scoped* helpers (`with…`), erreurs Swift.
- **Portabilité macOS/Linux** : headers `ncursesw` vs `curses` masqués via `shim.h`.
- **Testabilité en CI** : éviter l’UI interactive ; privilégier PTY, polling non bloquant, et rendu vérifiable.

---

## Principes & conventions

1. **Isolation**  
   - Toute interaction ncurses s’exécute sous `@CursesActor` (global actor) : sérialise les appels d’une lib non thread-safe.
2. **Flux standard**  
   - Jamais `CNcurses.stdin/stdout/stderr`.  
   - Utiliser l’acteur `StdStreams` (ouvre des `FILE*` via `fdopen(STDIN_FILENO/…)` une seule fois).
3. **Ressources C**  
   - Pas de valeurs C globales exposées.  
   - `withScreen { … }`, `withWindow { … }` font l’allocation **et** le `defer` du nettoyage.
4. **Const correctness**  
   - Adapter les paramètres attendus par l’import C (ex. `UnsafeMutablePointer<CChar>?` pour `newterm`) via `UnsafeMutablePointer(mutating:)` quand on passe des lits `const`.
5. **Erreurs**  
   - Fonctions qui retournent `ERR` → wrappers `throws`.
   - Helper `withErrno { … } -> (result, errnoValue)` sans `await` entre l’appel et la lecture d’`errno`.

---

## Architecture de la façade

### 1) Concurrency & flux standard

- `public actor StdStreams`  
  - `inputFile()`, `outputFile()`, `errorFile()` retournent des `FILE*` ouverts via `fdopen`.  
  - Cache interne, pas de duplication de FD.

- `@globalActor public struct CursesActor`  
  - Sérialise tous les appels ncurses.

### 2) Sessions & fenêtres

- `public enum Curses` (toutes les API `@CursesActor`)

```swift
public static func withScreen<R>(
  term: UnsafePointer<CChar>? = nil,
  _ body: (OpaquePointer /* SCREEN* */) throws -> R
) async throws -> R
```

- Démarre `newterm` avec `FILE*` issus de `StdStreams`. Fait `endwin` + `delscreen` en `defer`.

```swift
public static func withWindow<R>(
  height: Int32, width: Int32, startY: Int32, startX: Int32,
  _ body: (OpaquePointer /* WINDOW* */) throws -> R
) rethrows -> R
```

- Alloue `newwin`, exécute `body`, puis `delwin` garanti.

---

## Roadmap d’API (avant `swift-tui`)

### P0 — indispensables

**I/O & session**
```swift
public static func configureIO(
  on screen: OpaquePointer,
  raw: Bool = true, cbreak: Bool = true,
  echo: Bool = false, keypad: Bool = true
) throws

public enum CursorVisibility: Sendable { case hidden, normal, high }
public static func setCursorVisibility(_ v: CursorVisibility, on screen: OpaquePointer) throws
```

**Fenêtres & sous-fenêtres/pads**
```swift
public static func withSubWindow<R>(
  parent: OpaquePointer, height: Int32, width: Int32, startY: Int32, startX: Int32,
  _ body: (OpaquePointer) throws -> R
) rethrows -> R

public static func withPad<R>(
  rows: Int32, cols: Int32, _ body: (OpaquePointer) throws -> R
) rethrows -> R
```

**Clavier (bloquant/non-bloquant)**
```swift
public static func setTimeout(on win: OpaquePointer, milliseconds: Int32) // timeout()
public static func setNonBlocking(on win: OpaquePointer, enabled: Bool)   // nodelay()

public enum Key: Sendable {
  case char(UInt32), enter, backspace, up, down, left, right
  case home, end, pageUp, pageDown
  case f(Int), resize, mouse
  case unknown(Int32)
}
public static func getKey(from win: OpaquePointer) -> Key?
public static func keyEvents(from win: OpaquePointer, pollEvery ms: Int = 16) -> AsyncStream<Key>
```

**Couleurs & attributs**
```swift
public enum Color: Int16, Sendable { case black, red, green, yellow, blue, magenta, cyan, white }
public struct ColorPair: Sendable { public let id: Int16 }
public struct AttributeSet: OptionSet, Sendable {
  public let rawValue: Int32
  public static let bold, dim, underline, reverse, blink, standout, italic, invisible: AttributeSet
}

public static func startColorIfNeeded(on screen: OpaquePointer) throws
public static func allocateColorPair(fg: Color, bg: Color) throws -> ColorPair
public static func setAttributes(on win: OpaquePointer, attrs: AttributeSet = [], color: ColorPair?)
```

**Dessin minimal**
```swift
public static func mvadd(_ string: String, y: Int32, x: Int32, in win: OpaquePointer) throws
public static func drawBox(in win: OpaquePointer)
public static func refresh(_ win: OpaquePointer)
public static func flush() // doupdate()
```

**Redimensionnement**
```swift
public static func supportsResize() -> Bool
public static func getSize(of win: OpaquePointer) -> (rows: Int32, cols: Int32)
```

### P1 — très utile

**Souris**
```swift
public struct MouseMask: OptionSet, Sendable { public let rawValue: UInt32 }
public enum MouseEvent: Sendable {
  case pressed(btn: Int, y: Int32, x: Int32)
  case released(btn: Int, y: Int32, x: Int32)
  case moved(y: Int32, x: Int32)
}
public static func enableMouse(mask: MouseMask) throws
public static func disableMouse() throws
public static func getMouse() -> MouseEvent?
```

**Panels**
```swift
public static func withPanel<R>(window: OpaquePointer, _ body: (OpaquePointer /* PANEL* */) throws -> R) rethrows -> R
public static func show(panel: OpaquePointer)
public static func hide(panel: OpaquePointer)
public static func top(panel: OpaquePointer)
public static func bottom(panel: OpaquePointer)
public static func updatePanelsAndFlush()
```

**Unicode/chaînes**
- Ajouts `…nstr` pour tronquer sans dépasser la largeur, helpers d’ellipsis/wrapping.

**Terminfo**
```swift
public static func capability(_ name: String) -> String?
public static func hasTrueColor() -> Bool
```

### P2 — qualité de vie

**Locale**
```swift
public static func ensureLocaleOnce()
```

**Résultats & erreurs**
```swift
public enum CursesResult { case ok, err }
```

**Test harness PTY (CI)**
- Utilitaire basé sur `openpty` pour lancer `withScreen` avec un pseudo-terminal et capter la sortie (sans `script(1)`).
- Tests d’instantanés (rendu attendu vs obtenu).
- DSL de snapshot capable de paramétrer les fenêtres (couleurs, attributs, timeouts) et de scénariser clavier + souris via PTY.

---

## Exemples d’usage

**Hello box**
```swift
try await Curses.withScreen { screen in
  try Curses.configureIO(on: screen)
  try Curses.startColorIfNeeded(on: screen)
  let pair = try Curses.allocateColorPair(fg: .yellow, bg: .blue)

  try Curses.withWindow(height: 10, width: 40, startY: 2, startX: 4) { win in
    Curses.setAttributes(on: win, attrs: [.bold], color: pair)
    Curses.drawBox(in: win)
    try Curses.mvadd("Hello TUI 👋", y: 1, x: 2, in: win)
    Curses.refresh(win)

    Curses.setTimeout(on: win, milliseconds: 1000)
    if case .char(let c)? = Curses.getKey(from: win), c == 27 { /* ESC */ }
  }
}
```

**Boucle d’événements asynchrone**
```swift
try await Curses.withScreen { screen in
  try Curses.configureIO(on: screen)
  try Curses.withWindow(height: 0, width: 0, startY: 0, startX: 0) { win in
    Curses.setNonBlocking(on: win, enabled: true)
    for await key in Curses.keyEvents(from: win, pollEvery: 16) {
      switch key { case .resize: /* relayout */ ; case .char(let ch): /* input */ ; default: break }
    }
  }
}
```

---

## Tests & CI

- **Éviter `script -q /dev/null`** (comportement divergent selon distros).  
  Préférer un **PTY** : on connecte `newterm` sur des FDs du pseudo-terminal.
- **Non-bloquant** : toujours `nodelay()` + polling borné, ou `timeout(ms)`.
- **Instantanés** : log du buffer attendu (ex : `\u{1b}` séquences), comparer avec le rendu capturé.
- **Resize** : simuler via `ioctl(TIOCSWINSZ)` côté PTY.

---

## Portabilité

- `shim.h` inclut `ncursesw/*` et masque les différences (`NCURSES_CONST`, signatures comme `newterm(const char*, FILE*, FILE*)`).
- Sur macOS, la toolchain fournit `curses.h` compatible ncurses ; sur Linux, `ncursesw`. La façade harmonise les types Swift.

---

## Checklist Contrib

- [ ] Pas d’accès direct aux globales C (`stdin/out/err`, `stdscr`).
- [ ] Toute API publique `@CursesActor` si elle appelle ncurses.
- [ ] Nettoyage garanti (`with…` + `defer`).
- [ ] Pas d’`await` entre un appel C et la lecture d’`errno`.
- [ ] En cas de divergence de signature C, *adapter* en façade (pas dans l’appelant).
- [ ] Tests PTY pour toute nouvelle primitive visible.

---

## Étapes suivantes vers `swift-tui`

1. Implémenter **P0** complet.
2. Ajouter **Panels**, **Unicode** propre (P1).
3. Mettre en place le **test harness PTY** et stabiliser la CI (P2).
4. Démarrer `swift-tui` : layout, diffing, widgets, boucle d’événements basée sur `AsyncStream<Key>`.

---

## Références internes

- `Sources/Ncurses/ConcurrencySafe.swift` : `StdStreams`, `CursesActor`, `withScreen`, `withWindow`, `withErrno`.
- `Sources/CNcurses/include/shim.h` : pont d’en-têtes portable macOS/Linux.

> Cette façade constitue le contrat “bas niveau” stable pour `swift-tui`. Toute utilisation directe de ncurses hors façade est **déconseillée**.
