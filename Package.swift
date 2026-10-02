// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CmdIME",
    defaultLocalization: "en",
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
            dependencies: ["KeyboardSwitcherCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "keyboardctl",
            dependencies: ["KeyboardSwitcherCore"]
        ),
        // Test-only: a load-time hook that keeps the test process out of the Dock.
        .target(
            name: "TestProcessType",
            path: "Tests/TestProcessType",
            linkerSettings: [.linkedFramework("ApplicationServices")]
        ),
        .testTarget(
            name: "KeyboardSwitcherCoreTests",
            dependencies: ["KeyboardSwitcherCore", "TestProcessType"]
        ),
    ]
)
