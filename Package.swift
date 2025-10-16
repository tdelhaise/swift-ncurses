// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "swift-ncurses",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "Ncurses", targets: ["Ncurses"]),
    .executable(name: "NewtermSmoke", targets: ["NewtermSmoke"])
  ],
  targets: [
	// Cible C "normale" (pas systemLibrary) avec headers publics
	.target(
		name: "CNcurses",
		path: "Sources/CNcurses",
		publicHeadersPath: "include",
		cSettings: [
			// Apple Silicon (Homebrew /opt/homebrew)
			.unsafeFlags(["-I/opt/homebrew/opt/ncurses/include"], .when(platforms: [.macOS])),
			// Intel mac (Homebrew /usr/local)
			.unsafeFlags(["-I/usr/local/opt/ncurses/include"], .when(platforms: [.macOS]))
		],
		linkerSettings: [
			// Lier les sous-bibliothèques
			.linkedLibrary("ncursesw"),
			.linkedLibrary("panelw"),
			.linkedLibrary("menuw"),
			.linkedLibrary("formw"),
			// Et pointer vers le keg Homebrew si besoin
			.unsafeFlags(["-L/opt/homebrew/opt/ncurses/lib"], .when(platforms: [.macOS])),
			.unsafeFlags(["-L/usr/local/opt/ncurses/lib"], .when(platforms: [.macOS]))
		]
	),
    .target(
      name: "Ncurses",
      dependencies: ["CNcurses"]
    ),
    .executableTarget(
      name: "NewtermSmoke", 
      dependencies: ["CNcurses"]),
    .testTarget(
      name: "NcursesTests",
      dependencies: ["Ncurses"]
    )
  ]
)
