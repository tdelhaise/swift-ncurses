
[![CI](https://github.com/tdelhaise/swift-ncurses/actions/workflows/ci.yml/badge.svg)](https://github.com/tdelhaise/swift-ncurses/actions/workflows/ci.yml)


# swift-ncurses

Swift package **facade** for **libncursesw 6.x** (wide-char) with a Swift wrapper and a minimal integration smoke test.

> Targets:
> - `CNcurses`: C target exposing ncursesw headers
> - `Ncurses`: Swift wrapper (WIP)
> - `NewtermSmoke`: small executable to validate init/cleanup with `newterm()`

## Why

- Keep Apple SDK headers isolated from Homebrew ncurses headers (avoid `Darwin` module conflicts)
- Link explicitly to `ncursesw`, `panelw`, `menuw`, `formw`
- Provide a clean base for a future SwiftTUI layer.

## Requirements

- Swift toolchain **6.2** (or compatible with SPM 6.2 manifest)
- **ncurses (wide)** from your system package manager

### macOS (Intel / Apple Silicon)

Install ncurses via Homebrew:

```bash
brew install ncurses
