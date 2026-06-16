// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CmdIME",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "CmdIME", targets: ["CmdIME"]),
        .executable(name: "keyboardctl", targets: ["keyboardctl"]),
        .library(name: "KeyboardSwitcherCore", targets: ["KeyboardSwitcherCore"]),
    ],
    targets: [
        .target(name: "KeyboardSwitcherCore"),
        .executableTarget(
            name: "CmdIME",
            dependencies: ["KeyboardSwitcherCore"]
        ),
        .executableTarget(
            name: "keyboardctl",
            dependencies: ["KeyboardSwitcherCore"]
        ),
        .testTarget(
            name: "KeyboardSwitcherCoreTests",
            dependencies: ["KeyboardSwitcherCore"]
        ),
    ]
)
