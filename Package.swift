// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "swift-ncurses",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "Ncurses", targets: ["Ncurses"]),
  ],
  targets: [
    .systemLibrary(
      name: "CNcurses",
      pkgConfig: "ncursesw",
      providers: [
        .brew(["ncurses"]),
        .apt(["libncursesw6", "libncursesw6-dev"])
      ]
    ),
    .target(
      name: "Ncurses",
      dependencies: ["CNcurses"]
    ),
    .testTarget(
      name: "NcursesTests",
      dependencies: ["Ncurses"]
    )
  ]
)
