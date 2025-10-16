# ROADMAP

Roadmap for making the Swift ncurses façade production-ready and consumable by external packages needing broad ncurses functionality.

## Legend
- ✅ Completed
- ⬜️ Planned / pending
- 🔄 In progress

## Milestone M0 – Concurrency-Safe Core (✅ Complete)
- ✅ Actor-isolated screen lifecycle via `Curses.withScreen` with guaranteed cleanup (`Sources/Ncurses/ConcurrencySafe.swift:47`)
- ✅ Actor-backed standard streams shim avoiding global FILE usage (`Sources/Ncurses/ConcurrencySafe.swift:29`)
- ✅ Window lifecycle helpers preventing leaks (`Sources/Ncurses/ConcurrencySafe.swift:120`)
- ✅ Error propagation helper `withErrno` without suspension points (`Sources/Ncurses/ConcurrencySafe.swift:96`)

## Milestone M1 – P0 Interactive APIs (✅ Complete)
- ✅ IO configuration helpers (`configureIO`, `setCursorVisibility`) with safe `stdscr` handling through a shim (`Sources/Ncurses/ConcurrencySafe.swift:245`)
- ✅ Window subtree constructors (`withSubWindow`, `withPad`) for safe subwindow/pad management (`Sources/Ncurses/ConcurrencySafe.swift:299`)
- ✅ Blocking and non-blocking keyboard helpers plus polling stream (`setTimeout`, `setNonBlocking`, `getKey`, `keyEvents`) (`Sources/Ncurses/ConcurrencySafe.swift:332`)
- ✅ Color & attribute wrappers with shim-backed constants and pair allocator (`Sources/Ncurses/ConcurrencySafe.swift:424`)
- ✅ Minimal drawing primitives and refresh helpers (`mvadd`, `drawBox`, `refresh`, `flush`) (`Sources/Ncurses/ConcurrencySafe.swift:502`)
- ✅ Resize introspection utilities (`supportsResize`, `getSize`) (`Sources/Ncurses/ConcurrencySafe.swift:538`)
- ✅ C shim exporting attribute constants, keypad configuration, and color pair access (`Sources/CNcurses/empty.c:3`)

## Milestone M2 – Advanced Ncurses Surface (✅ Complete)
- ✅ Mouse support: option sets for masks, event decoding, enable/disable wrappers, and event polling integration. (`Sources/Ncurses/ConcurrencySafe.swift:65`)
- ✅ Panel API: lifecycled `withPanel`, visibility helpers, and panel flush coordination. (`Sources/Ncurses/ConcurrencySafe.swift:648`)
- ✅ Unicode-safe string routines (wide-char adders, ellipsis, wrapping utilities). (`Sources/Ncurses/ConcurrencySafe.swift:727`)
- ✅ Terminfo queries (`capability(_:)`, `hasTrueColor()`) with Swift optionals and caching. (`Sources/Ncurses/ConcurrencySafe.swift:841`)
- ✅ Locale bootstrap (`ensureLocaleOnce()`) guaranteeing wide-character readiness. (`Sources/Ncurses/ConcurrencySafe.swift:885`)
- ✅ Public `CursesResult` helper mirroring `OK/ERR` semantics for callers. (`Sources/Ncurses/ConcurrencySafe.swift:184`)

## Milestone M3 – Testing & Tooling (🔄 In Progress)
- ✅ PTY-based integration harness with out-of-process helper (`NcursesSnapshotHelper`) and first deterministic snapshot test.
- ✅ Snapshot testing utilities for screen buffers, resize simulations, and scripted keyboard/mouse input.
- ⬜️ Continuous integration configuration leveraging PTY harness and non-interactive runs.
- ⬜️ Developer tooling: fixture recorders, linting, and formatting enforcement.

## Milestone M4 – Ecosystem Readiness (⬜️ Planned)
- ⬜️ API documentation (DocC guides, tutorials, examples) covering the full surface.
- ⬜️ Versioned semantic tagging with CHANGELOG and upgrade notes.
- ⬜️ Swift Package products for façade vs. C shim separation if needed.
- ⬜️ Reference sample applications demonstrating best practices.

## Known Follow-Ups
- ⬜️ Evaluate exposing raw ncurses handles for advanced scenarios while preserving actor isolation guidance.
- ⬜️ Audit under Thread Sanitizer and Swift concurrency checks.
- ⬜️ Determine bridging strategy for menu/form subsystems after panel & mouse APIs land.
